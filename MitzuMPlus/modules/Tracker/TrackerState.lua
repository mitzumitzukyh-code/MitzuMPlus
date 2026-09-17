-- ===========================================================================
-- MitzuMPlus - Tracker/TrackerState  (1.1.0, fase 2)
--
--     Blizzard API -> TrackerAdapter -> TrackerState -> Pace/Prediction -> Enhancer
--
-- Guarda UN snapshot normalizado de la llave en curso. Es la fuente que
-- consumira todo lo que venga despues (PaceEngine, PredictionEngine,
-- BlizzardTrackerEnhancer). En esta fase no tiene consumidores visuales.
--
-- REGLAS
--   * Los datos salen SOLO de TrackerAdapter:GetSnapshot(). Este fichero no
--     llama a ninguna API de Blizzard (lo vigila tests/run_static_checks.py).
--     Los eventos de Blizzard son disparadores de lectura, nunca datos.
--   * Solo campos normalizados. quantityString / quantity / criterios crudos
--     se quedan en el informe DEV del adaptador.
--   * "No lo se" sigue siendo nil. Una lectura parcial (p. ej. el hueco del
--     temporizador tras /reload) NO borra lo ya sabido de la misma llave: se
--     conserva y se marca como obsoleto (`timerStale`, `forcesStale`...).
--   * Sin OnUpdate. Eventos en rafaga se funden en una lectura; un ticker lento
--     resincroniza mientras hay llave (1 s en PENDING, 5 s en RUNNING) y se para
--     fuera de ella. El tiempo entre lecturas se interpola con GetTime().
--
-- CICLO DE VIDA
--   IDLE       sin llave activa
--   PENDING    llave activa pero sin temporizador del servidor todavia
--   RUNNING    llave activa con temporizador
--   COMPLETING CHALLENGE_MODE_COMPLETED visto; tiempo final ya congelado, pero
--              los criterios se releen durante una ventana corta (max. 3 s)
--              porque Blizzard puede publicar el ultimo boss despues del evento
--   COMPLETED  snapshot final congelado hasta que empiece otra llave
--              (START / RESET / inactiva -> activa / otro mapa)
--
-- CONVERGENCIA DEL FINAL (1.1.0-dev.5)
--   Retail dev.4 congelo bosses=2/3 en una llave completada: la lectura del
--   evento ya no traia criterios y el ultimo boss nunca se leyo. Ahora:
--     * el evento fija completedAt y finalElapsed y hace una lectura inmediata;
--     * mientras no haya fuerzas al 100 % y todos los bosses, se relee cada
--       COMPLETION_INTERVAL hasta COMPLETION_WINDOW (ticker propio, se cancela);
--     * cada lectura solo puede mejorar lo sabido: nil, 0 o un retroceso nunca
--       sustituyen un valor real;
--     * si Blizzard no llega a exponer el final, se congela lo ultimo real.
--       Nunca se inventa un boss.
--
-- AUTORIDAD DEL FINAL (1.1.0-dev.6)
--   Retail dev.5 (Reposo de los Reyes +12): el evento llego con 3/4 y 100 %, y
--   la primera relectura ya no traia nada (active=false, criterios nil). La
--   llave estaba terminada, pero el snapshot quedo como "criterios incompletos".
--   CHALLENGE_MODE_COMPLETED es la autoridad terminal: una Mitica+ solo termina
--   con todos los criterios cumplidos. Se separan dos preguntas:
--     * convergencia de API  -> completionConverged: Blizzard llego a mostrar
--       el final (100 % y todos los bosses) en alguna lectura;
--     * final autoritativo   -> terminalStateConfirmed: la llave termino.
--   Lo observado NO se toca (bossesCompleted sigue siendo 3). El valor terminal
--   va aparte y dice de donde sale:
--       bossesCompletedFinal=4  bossCountSource=INFERRED_FROM_COMPLETION_EVENT
--   criteriaUnavailableAfterCompletion=true si ninguna lectura de la ventana
--   trajo criterios. completionCriteriaIncomplete solo seria true con un final
--   sin autoridad, cosa que hoy no puede ocurrir (se conserva por compatibilidad).
-- ===========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local TS = {}
MitzuMPlus.TrackerState = TS

TS.VERSION = 1

local IDLE, PENDING, RUNNING, COMPLETING, COMPLETED = "IDLE", "PENDING", "RUNNING", "COMPLETING", "COMPLETED"
TS.STATUS = { IDLE = IDLE, PENDING = PENDING, RUNNING = RUNNING, COMPLETING = COMPLETING, COMPLETED = COMPLETED }

TS.REFRESH_DELAY       = 0.2   -- segundos para fundir eventos en rafaga
TS.RESYNC_PENDING      = 1     -- esperando el temporizador
TS.RESYNC_RUNNING      = 5     -- recalibrar reloj y recoger lo que no avise
TS.RECOVERED_THRESHOLD = 15    -- primera lectura con mas tiempo => llave recuperada
TS.TIMER_REGRESSION    = 2     -- segundos hacia atras tolerados antes de avisar
TS.MAX_WARNINGS        = 24

TS.COMPLETION_WINDOW       = 3     -- segundos maximos de relectura tras completar
TS.COMPLETION_INTERVAL     = 0.25  -- periodo del ticker de convergencia
TS.COMPLETION_MAX_ATTEMPTS = 16    -- tope duro de lecturas en la ventana
TS.COMPLETION_MAX_RECORDS  = 8     -- lecturas distintas anotadas en la caja negra

-- De donde sale un valor terminal del final de llave.
TS.SOURCE = {
    OBSERVED = "OBSERVED",                           -- leido de Blizzard
    INFERRED = "INFERRED_FROM_COMPLETION_EVENT",     -- implicado por el evento oficial
    UNAVAILABLE = "UNAVAILABLE",                     -- no hubo dato ni autoridad
}
TS.COMPLETION_AUTHORITY = "CHALLENGE_MODE_COMPLETED"

-- Carreras normales de sincronizacion: al arrancar la llave (o tras /reload)
-- Blizzard tarda unos segundos en exponer temporizador y criterios. Mientras
-- duren menos de TRANSIENT_WINDOW no son un problema de la llave: se muestran
-- en `transient` y, al resolverse, la caja negra anota cuanto tardaron. Solo si
-- persisten pasan a `warnings` / `runWarnings`.
TS.TRANSIENT_WINDOW = 10
TS.TRANSIENT_CODES = {
    ACTIVE_WITHOUT_TIMER = true, ACTIVE_WITHOUT_CRITERIA = true,
    ACTIVE_WITHOUT_FORCES = true, ACTIVE_WITHOUT_MAP = true,
}

-- Disparadores. Todos documentados en Blizzard_APIDocumentationGenerated 12.1.5;
-- aun asi se validan antes de registrarse.
TS.EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "CHALLENGE_MODE_START",
    "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_RESET",
    "CHALLENGE_MODE_DEATH_COUNT_UPDATED",
    "SCENARIO_CRITERIA_UPDATE",
    "WORLD_STATE_TIMER_START",
    "WORLD_STATE_TIMER_STOP",
    -- Cambios de paso / cierre del escenario: pueden traer el ultimo criterio.
    "SCENARIO_UPDATE",
    "SCENARIO_COMPLETED",
}

-- Campos normalizados que se copian del adaptador. Nada fuera de esta lista.
TS.FIELDS = {
    "mapID", "mapName", "keystoneLevel", "timeLimit", "deaths", "deathTimeLost",
    "forcesCurrent", "forcesTotal", "forcesPercent", "forcesRemaining", "forcesRemainingPercent",
    "forcesSource", "bossesCompleted", "bossesTotal",
}

-- ---------------------------------------------------------------------------
-- RELOJ E INYECCION (los tests sustituyen adaptador y reloj)
-- ---------------------------------------------------------------------------

local function mono()
    local fn = rawget(_G, "GetTime")
    if type(fn) ~= "function" then return 0 end
    local ok, v = pcall(fn)
    return (ok and tonumber(v)) or 0
end

local function epoch()
    local fn = rawget(_G, "time")
    if type(fn) ~= "function" then return 0 end
    local ok, v = pcall(fn)
    return (ok and tonumber(v)) or 0
end

function TS:SetAdapter(adapter) self._adapter = adapter end
function TS:GetAdapter() return self._adapter or MitzuMPlus.TrackerAdapter end

-- ---------------------------------------------------------------------------
-- ESTADO
-- ---------------------------------------------------------------------------

local function emptySnapshot()
    return { status = IDLE, active = false, warnings = {}, transient = {}, bosses = {},
             -- Reservados para las fases 5-6. Siguen nil hasta que haya motor.
             pace = nil, prediction = nil, eta = nil, confidence = nil }
end

function TS:Reset()
    self._status = IDLE
    self._snapshot = emptySnapshot()
    self._snapshot.revision = 0
    self._revision = 0
    self._run = nil
    self._lastSignature = nil
    self._refreshPending = false
    self._completedEvent = nil
    self._completedElapsed = nil
    self._completion = nil
    self:_StopCompletionTicker()
    self._awaitingNewRun = false
    self._sawInactive = false
    self._stats = { refreshes = 0, coalesced = 0, adapterErrors = 0, events = {}, lastReason = nil,
                    duplicateCompletions = 0 }
    self:_SyncTicker()
end

-- ---------------------------------------------------------------------------
-- CAJA NEGRA Y BUS
-- ---------------------------------------------------------------------------

local function record(event, data)
    local FR = MitzuMPlus.FlightRecorder
    if FR and FR.Record then FR:Record("TRACKER", "STATE_" .. event, data) end
end

local function emit(event, ...)
    local bus = MitzuMPlus.EventBus
    if bus and bus.Emit then bus:Emit(event, ...) end
end

-- Aviso deduplicado por llave: aparece en el snapshot y se anota una sola vez.
function TS:_Warn(snap, code)
    snap.warnings[#snap.warnings + 1] = code
    local run = self._run
    if not run or run.warned[code] then return end
    if run.warnCount >= TS.MAX_WARNINGS then return end
    run.warned[code] = true
    run.warnCount = run.warnCount + 1
    record("WARN", { code = code, map = run.mapID })
end

-- ---------------------------------------------------------------------------
-- CONSTRUCCION DEL SNAPSHOT
-- ---------------------------------------------------------------------------

local function copyBosses(list)
    local out = {}
    for i, b in ipairs(type(list) == "table" and list or {}) do
        if type(b) == "table" then
            out[#out + 1] = { index = b.index or i, name = b.name, completed = b.completed == true }
        end
    end
    return out
end

function TS:_StartRun(raw, reason)
    self._run = {
        mapID = raw.mapID, keystoneLevel = raw.keystoneLevel,
        firstSeenAt = epoch(), recovered = nil,
        warned = {}, warnCount = 0,
        syncing = {},   -- [codigo] = GetTime() de la primera lectura en que aparecio
    }
    self._awaitingNewRun = false
    self._sawInactive = false
    self._snapshot = emptySnapshot()
    record("RUN_STARTED", { map = raw.mapID, level = raw.keystoneLevel, reason = reason })
    emit("MITZU_TRACKER_RUN_STARTED", self)
end

-- Mezcla la lectura del adaptador con lo ya sabido de la misma llave.
function TS:_BuildActive(raw, prev)
    local snap = emptySnapshot()
    local now = mono()
    snap.active = true

    for _, k in ipairs(TS.FIELDS) do snap[k] = raw[k] end

    -- Identidad y limite no cambian dentro de una llave: si falta, se conserva.
    for _, k in ipairs({ "mapID", "mapName", "keystoneLevel", "timeLimit" }) do
        if snap[k] == nil and prev[k] ~= nil then snap[k] = prev[k] end
    end
    if snap.deaths == nil and prev.deaths ~= nil then
        snap.deaths, snap.deathTimeLost = prev.deaths, prev.deathTimeLost
    end

    -- Temporizador: base del servidor + interpolacion.
    if raw.elapsed then
        local expected = prev.elapsedBase and (prev.elapsedBase + (now - (prev.elapsedAt or now))) or nil
        if expected and raw.elapsed < expected - TS.TIMER_REGRESSION then
            self:_Warn(snap, "TIMER_REGRESSION")
        end
        snap.elapsedBase, snap.elapsedAt, snap.timerSource = raw.elapsed, now, raw.timerSource
        snap.timerStale = false
    elseif prev.elapsedBase then
        snap.elapsedBase, snap.elapsedAt, snap.timerSource = prev.elapsedBase, prev.elapsedAt, prev.timerSource
        snap.timerStale = true
    end

    -- Fuerzas: el servidor manda, pero un hueco no borra y un retroceso avisa.
    if raw.forcesPercent ~= nil then
        if prev.forcesPercent and raw.forcesPercent < prev.forcesPercent - 1e-6 then
            self:_Warn(snap, "FORCES_DECREASED")
        end
        snap.forcesStale = false
    elseif prev.forcesPercent ~= nil then
        for _, k in ipairs({ "forcesCurrent", "forcesTotal", "forcesPercent", "forcesRemaining",
                             "forcesRemainingPercent", "forcesSource" }) do
            snap[k] = prev[k]
        end
        snap.forcesStale = true
    end

    -- Bosses: igual.
    if raw.bossesTotal ~= nil then
        if prev.bossesCompleted and raw.bossesCompleted and raw.bossesCompleted < prev.bossesCompleted then
            self:_Warn(snap, "BOSSES_DECREASED")
        end
        snap.bosses = copyBosses(raw.bosses)
        snap.bossesStale = false
    elseif prev.bossesTotal ~= nil then
        snap.bossesCompleted, snap.bossesTotal = prev.bossesCompleted, prev.bossesTotal
        snap.bosses = copyBosses(prev.bosses)
        snap.bossesStale = true
    end

    local run, seen = self._run, {}
    for _, w in ipairs(type(raw.warnings) == "table" and raw.warnings or {}) do
        local code = tostring(w)
        if TS.TRANSIENT_CODES[code] and run then
            seen[code] = true
            run.syncing[code] = run.syncing[code] or now
            if now - run.syncing[code] < TS.TRANSIENT_WINDOW then
                snap.transient[#snap.transient + 1] = "ADAPTER_" .. code
            else
                self:_Warn(snap, "ADAPTER_" .. code)
            end
        else
            self:_Warn(snap, "ADAPTER_" .. code)
        end
    end
    if run then
        for code, since in pairs(run.syncing) do
            if not seen[code] then
                run.syncing[code] = nil
                if not run.warned["ADAPTER_" .. code] then
                    record("SYNC", { code = "ADAPTER_" .. code, seconds = string.format("%.1f", now - since) })
                end
            end
        end
    end
    return snap
end

local function signature(s)
    return table.concat({
        tostring(s.status), tostring(s.active), tostring(s.mapID), tostring(s.keystoneLevel),
        tostring(s.timeLimit), tostring(s.deaths), tostring(s.forcesCurrent), tostring(s.forcesTotal),
        s.forcesPercent and string.format("%.3f", s.forcesPercent) or "nil",
        tostring(s.bossesCompleted), tostring(s.bossesTotal), tostring(s.timerStale),
        tostring(s.forcesStale), tostring(s.bossesStale), tostring(s.recovered),
        tostring(s.elapsedBase ~= nil), table.concat(s.warnings or {}, ","),
        tostring(s.completionAttempts), tostring(s.completionConverged),
        tostring(s.completionCriteriaIncomplete), tostring(s.terminalStateConfirmed),
    }, "|")
end

function TS:_Commit(snap, reason)
    snap.status = self._status
    snap.timestamp = epoch()
    snap.reason = reason
    if self._run then
        snap.recovered = self._run.recovered
        snap.firstSeenAt = self._run.firstSeenAt
        -- `warnings` describe esta lectura; `runWarnings`, todo lo visto en la llave.
        local seen = {}
        for code in pairs(self._run.warned) do seen[#seen + 1] = code end
        table.sort(seen)
        snap.runWarnings = seen
    end
    local sig = signature(snap)
    if sig ~= self._lastSignature then
        self._lastSignature = sig
        self._revision = self._revision + 1
        snap.revision = self._revision
        self._snapshot = snap
        emit("MITZU_TRACKER_STATE_CHANGED", self)
    else
        snap.revision = self._revision
        self._snapshot = snap
    end
    self:_SyncTicker()
end

function TS:_SetStatus(status, why)
    if self._status == status then return end
    local previous = self._status
    self._status = status
    record("STATUS", { from = previous, to = status, why = why })
end

-- ---------------------------------------------------------------------------
-- LECTURA
-- ---------------------------------------------------------------------------

function TS:Refresh(reason)
    self._refreshPending = false
    local stats = self._stats
    stats.refreshes = stats.refreshes + 1
    stats.lastReason = reason

    local adapter = self:GetAdapter()
    if type(adapter) ~= "table" or type(adapter.GetSnapshot) ~= "function" then
        stats.adapterErrors = stats.adapterErrors + 1
        local snap = self._snapshot
        snap.adapterAvailable = false
        if self._status == COMPLETING then self:_ApplyCompleting(nil, reason) end
        return false
    end
    local ok, raw = pcall(adapter.GetSnapshot, adapter)
    if not ok or type(raw) ~= "table" then
        -- El adaptador nunca deberia lanzar; si lo hace, se conserva lo sabido.
        stats.adapterErrors = stats.adapterErrors + 1
        stats.lastAdapterError = tostring(raw)
        record("ADAPTER_ERROR", { reason = reason })
        -- Una lectura fallida tambien cuenta: la ventana de cierre siempre termina.
        if self._status == COMPLETING then self:_ApplyCompleting(nil, reason) end
        return false
    end
    self:_Apply(raw, reason)
    return true
end

function TS:_Apply(raw, reason)
    local status = self._status
    local otherMap = (self._run and raw.mapID and self._run.mapID and raw.mapID ~= self._run.mapID) and true or false

    if status == COMPLETING then
        if not (raw.active == true and otherMap) then
            return self:_ApplyCompleting(raw, reason)
        end
        -- Otra llave en otro mapa: se cierra la anterior con lo que haya.
        self:_FinishCompletion("NEW_RUN")
        status = self._status
    end
    local prev = self._snapshot or emptySnapshot()

    if raw.active == true then
        local newRun = false
        if status == IDLE then
            newRun = true
        elseif status == COMPLETED then
            newRun = (not self._awaitingNewRun) or self._sawInactive or otherMap
        elseif otherMap then
            newRun = true
        end
        if newRun then
            self:_StartRun(raw, reason)
            prev = self._snapshot
            status = IDLE
        end

        if self._status == COMPLETED and not newRun then
            -- Llave recien terminada que el cliente aun reporta activa.
            return self:_Commit(prev, reason)
        end

        local snap = self:_BuildActive(raw, prev)
        local run = self._run
        if run and run.recovered == nil and raw.elapsed then
            run.recovered = raw.elapsed > TS.RECOVERED_THRESHOLD
            if run.recovered then record("RUN_RECOVERED", { elapsed = math.floor(raw.elapsed) }) end
        end
        if run and not run.mapID and raw.mapID then run.mapID = raw.mapID end

        if self._completedEvent then
            -- En una llave ya seguida se parte de lo ultimo bueno: la lectura del
            -- evento se mezcla sin poder retroceder nada.
            return self:_EnterCompleting(newRun and snap or prev, raw, reason)
        end
        self:_SetStatus(snap.elapsedBase and RUNNING or PENDING, reason)
        return self:_Commit(snap, reason)
    end

    if raw.active == false then
        if status == RUNNING or status == PENDING then
            if self._completedEvent then
                -- Tras completar, los criterios pueden seguir leyendose.
                return self:_EnterCompleting(prev, raw, reason)
            end
            record("RUN_ENDED", { reason = reason, map = self._run and self._run.mapID })
            emit("MITZU_TRACKER_RUN_ENDED", self)
            self._run = nil
            self:_SetStatus(IDLE, reason)
            return self:_Commit(emptySnapshot(), reason)
        end
        if status == COMPLETED then
            self._sawInactive = true
            prev.active = false
            return self:_Commit(prev, reason)
        end
        self:_SetStatus(IDLE, reason)
        return self:_Commit(emptySnapshot(), reason)
    end

    -- active == nil: no se sabe. No se cambia de estado ni se inventa nada.
    local snap = {}
    for k, v in pairs(prev) do snap[k] = v end
    snap.warnings = {}
    self:_Warn(snap, "CHALLENGE_STATE_UNKNOWN")
    return self:_Commit(snap, reason)
end

-- ---------------------------------------------------------------------------
-- CONVERGENCIA DEL FINAL
-- ---------------------------------------------------------------------------

local EPS = 1e-6
local function forcesDone(s) return s.forcesPercent ~= nil and s.forcesPercent >= 100 - EPS end
local function bossesDone(s)
    return s.bossesTotal ~= nil and s.bossesTotal > 0 and s.bossesCompleted ~= nil
       and s.bossesCompleted >= s.bossesTotal
end

-- Final convergido: fuerzas al 100 % y todos los bosses, leidos de Blizzard.
function TS.IsFinalCriteriaConverged(s) return forcesDone(s) and bossesDone(s) end

local FORCES_KEYS = { "forcesCurrent", "forcesTotal", "forcesPercent", "forcesRemaining",
                      "forcesRemainingPercent", "forcesSource" }

local function frac(v, total)
    if v == nil and total == nil then return "nil" end
    return tostring(v) .. "/" .. tostring(total)
end

-- `base` es lo ultimo bueno de la llave; `raw`, la lectura que coincidio con el evento.
function TS:_EnterCompleting(base, raw, reason)
    local now = mono()
    local best = {}
    for k, v in pairs(base) do best[k] = v end
    best.warnings, best.transient, best.bosses = {}, {}, copyBosses(base.bosses)
    local c = {
        startedAt = now, deadline = now + TS.COMPLETION_WINDOW, officialAt = epoch(),
        finalElapsed = self._completedElapsed or self:_LiveElapsed(base)
            or (type(raw) == "table" and raw.elapsed or nil),
        attempts = 0, regressions = 0, records = 0, best = best,
        source = TS.COMPLETION_AUTHORITY,
        forcesFresh = false, bossesFresh = false, sawInactive = false,
    }
    self._completedEvent, self._completedElapsed = nil, nil
    self._completion = c
    best.completedAt, best.finalElapsed, best.timerStale = c.officialAt, c.finalElapsed, false
    self:_SetStatus(COMPLETING, reason)
    record("COMPLETION_BEGIN", {
        elapsed = c.finalElapsed and math.floor(c.finalElapsed) or nil,
        forces = best.forcesPercent and string.format("%.2f", best.forcesPercent) or nil,
        bosses = frac(best.bossesCompleted, best.bossesTotal),
    })
    return self:_ApplyCompleting(raw, reason)
end

-- Mezcla una lectura dentro de la ventana. Solo mejora; nunca borra ni retrocede.
function TS:_MergeCompletion(raw)
    local c = self._completion
    local best = c.best
    if raw.active == false then c.sawInactive = true end
    if raw.active ~= nil then best.active = raw.active end

    for _, k in ipairs({ "mapID", "mapName", "keystoneLevel", "timeLimit" }) do
        if best[k] == nil and raw[k] ~= nil then best[k] = raw[k] end
    end
    if raw.deaths ~= nil and (best.deaths == nil or raw.deaths >= best.deaths) then
        best.deaths, best.deathTimeLost = raw.deaths, raw.deathTimeLost
    end

    if raw.forcesPercent ~= nil then
        if best.forcesPercent == nil or raw.forcesPercent >= best.forcesPercent - EPS then
            for _, k in ipairs(FORCES_KEYS) do best[k] = raw[k] end
            c.forcesFresh = true
        else
            c.regressions = c.regressions + 1
        end
    end

    if raw.bossesTotal ~= nil then
        local sameShape = best.bossesTotal == nil or raw.bossesTotal == best.bossesTotal
        local notBack = best.bossesCompleted == nil or (raw.bossesCompleted or 0) >= best.bossesCompleted
        if raw.bossesTotal > 0 and sameShape and notBack then
            best.bossesCompleted, best.bossesTotal = raw.bossesCompleted, raw.bossesTotal
            best.bosses = copyBosses(raw.bosses)
            c.bossesFresh = true
        elseif best.bossesTotal ~= nil then
            c.regressions = c.regressions + 1
        end
    end
end

function TS:_ApplyCompleting(raw, reason)
    local c = self._completion
    if not c then return end
    c.attempts = c.attempts + 1
    if type(raw) == "table" then
        self:_MergeCompletion(raw)
        -- Evidencia para la siguiente prueba real: que expone Blizzard tras el evento.
        local summary = string.format("active=%s forces=%s bosses=%s criteria=%s", tostring(raw.active),
            frac(raw.forcesCurrent, raw.forcesTotal), frac(raw.bossesCompleted, raw.bossesTotal),
            tostring(raw.criteriaCount))
        if summary ~= c.lastSummary and c.records < TS.COMPLETION_MAX_RECORDS then
            c.lastSummary, c.records = summary, c.records + 1
            record("COMPLETION_READ", { attempt = c.attempts, read = summary,
                ms = math.floor((mono() - c.startedAt) * 1000 + 0.5) })
        end
    end

    if TS.IsFinalCriteriaConverged(c.best) or mono() >= c.deadline
       or c.attempts >= TS.COMPLETION_MAX_ATTEMPTS or not self:_StartCompletionTicker() then
        return self:_FinishCompletion(reason)
    end
    c.best.completionAttempts = c.attempts
    return self:_Commit(c.best, reason)
end

-- Congela el snapshot final. Idempotente: sin ventana abierta no hace nada.
function TS:_FinishCompletion(reason)
    local c = self._completion
    if not c then return end
    self._completion = nil
    self:_StopCompletionTicker()

    local snap = c.best
    local converged = TS.IsFinalCriteriaConverged(snap)
    snap.completedAt, snap.finalElapsed, snap.timerStale = c.officialAt, c.finalElapsed, false
    -- Un valor terminal (100 %, todos los bosses) ya no puede cambiar: es final
    -- aunque no se haya releido. Lo demas es fresco solo si llego en la ventana.
    if snap.forcesPercent ~= nil then snap.forcesStale = not (c.forcesFresh or forcesDone(snap)) end
    if snap.bossesTotal ~= nil then snap.bossesStale = not (c.bossesFresh or bossesDone(snap)) end
    snap.completionConverged = converged
    -- La ventana solo se abre con CHALLENGE_MODE_COMPLETED: el final es oficial.
    local terminal = c.source ~= nil
    snap.completionSource = c.source
    snap.terminalStateConfirmed = terminal
    snap.completionCriteriaIncomplete = not (converged or terminal)
    snap.criteriaUnavailableAfterCompletion = not (c.forcesFresh or c.bossesFresh)
    TS.ApplyTerminalCounts(snap, terminal)
    snap.completionAttempts = c.attempts
    snap.completionConvergenceMs = math.floor((mono() - c.startedAt) * 1000 + 0.5)
    snap.completionRegressionsIgnored = c.regressions

    self._awaitingNewRun = true
    self._sawInactive = c.sawInactive
    self:_SetStatus(COMPLETED, reason)
    record("RUN_COMPLETED", {
        map = snap.mapID, level = snap.keystoneLevel,
        elapsed = snap.finalElapsed and math.floor(snap.finalElapsed) or nil,
        forces = snap.forcesPercent and string.format("%.2f", snap.forcesPercent) or nil,
        bosses = snap.bossesTotal and (tostring(snap.bossesCompleted) .. "/" .. tostring(snap.bossesTotal)) or nil,
        converged = converged, attempts = c.attempts, ms = snap.completionConvergenceMs,
        terminal = terminal, source = c.source, bossSource = snap.bossCountSource,
        criteriaUnavailable = snap.criteriaUnavailableAfterCompletion,
    })
    self:_Commit(snap, reason)
    emit("MITZU_TRACKER_RUN_COMPLETED", self)
end

-- Valores terminales separados de lo observado. Con autoridad, todos los bosses
-- y el 100 % de fuerzas estan implicados por el evento; sin ella, solo cuenta
-- lo que Blizzard mostro. Nunca se toca bossesCompleted / forcesPercent.
function TS.ApplyTerminalCounts(snap, terminal)
    local SRC = TS.SOURCE
    snap.bossesCompletedObserved = snap.bossesCompleted
    if snap.bossesTotal == nil or snap.bossesTotal <= 0 then
        snap.bossCountSource, snap.bossesCompletedFinal = SRC.UNAVAILABLE, nil
    elseif bossesDone(snap) or not terminal then
        snap.bossCountSource, snap.bossesCompletedFinal = SRC.OBSERVED, snap.bossesCompleted
    else
        snap.bossCountSource, snap.bossesCompletedFinal = SRC.INFERRED, snap.bossesTotal
    end
    if forcesDone(snap) then
        snap.forcesCompletionSource, snap.forcesPercentFinal = SRC.OBSERVED, snap.forcesPercent
    elseif terminal then
        snap.forcesCompletionSource, snap.forcesPercentFinal = SRC.INFERRED, 100
    elseif snap.forcesPercent ~= nil then
        snap.forcesCompletionSource, snap.forcesPercentFinal = SRC.OBSERVED, snap.forcesPercent
    else
        snap.forcesCompletionSource, snap.forcesPercentFinal = SRC.UNAVAILABLE, nil
    end
end

function TS:_StartCompletionTicker()
    if self._completionTicker then return true end
    local timer = rawget(_G, "C_Timer")
    if type(timer) ~= "table" or type(timer.NewTicker) ~= "function" then return false end
    self._completionTicker = timer.NewTicker(TS.COMPLETION_INTERVAL, function() TS:Refresh("COMPLETION_SYNC") end)
    return self._completionTicker ~= nil
end

function TS:_StopCompletionTicker()
    local t = self._completionTicker
    self._completionTicker = nil
    if t and t.Cancel then t:Cancel() end
end

-- ---------------------------------------------------------------------------
-- DISPARADORES
-- ---------------------------------------------------------------------------

-- Pide una lectura; varias peticiones seguidas se funden en una.
function TS:RequestRefresh(reason)
    if self._refreshPending then
        self._stats.coalesced = self._stats.coalesced + 1
        return false
    end
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
        self._refreshPending = true
        timer.After(TS.REFRESH_DELAY, function() TS:Refresh(reason) end)
        return true
    end
    self:Refresh(reason)
    return true
end

function TS:OnEvent(event)
    local counts = self._stats.events
    counts[event] = (counts[event] or 0) + 1
    if event == "CHALLENGE_MODE_COMPLETED" then
        if self._status == COMPLETING or self._status == COMPLETED then
            -- El cliente puede repetir el evento: una sola finalizacion por llave.
            self._stats.duplicateCompletions = self._stats.duplicateCompletions + 1
            record("COMPLETION_DUPLICATE", { status = self._status })
            return false
        end
        local wasRunning = self._status == RUNNING or self._status == PENDING
        self._completedEvent = true
        self._completedElapsed = self:GetElapsed()
        -- Lectura inmediata: la foto final no debe esperar a la coalescencia.
        -- El aviso se consume en esta misma lectura; si no habia llave que
        -- cerrar, no puede quedarse armado para la siguiente.
        local ok = self:Refresh(event)
        if self._completedEvent and wasRunning then
            -- Lectura fallida o estado desconocido: la llave termino igual.
            self:_EnterCompleting(self._snapshot, nil, event)
        end
        self._completedEvent, self._completedElapsed = nil, nil
        return ok
    end
    if (event == "CHALLENGE_MODE_START" or event == "CHALLENGE_MODE_RESET") and self._status == COMPLETING then
        self:_FinishCompletion(event)
    end
    if event == "CHALLENGE_MODE_START" or event == "CHALLENGE_MODE_RESET" then
        if self._status == COMPLETED then self._sawInactive = true end
        if event == "CHALLENGE_MODE_RESET" and (self._status == RUNNING or self._status == PENDING) then
            self._completedEvent = nil
        end
    end
    return self:RequestRefresh(event)
end

function TS:_SyncTicker()
    local period
    if self._status == PENDING then period = TS.RESYNC_PENDING
    elseif self._status == RUNNING then period = TS.RESYNC_RUNNING end
    if self._tickerPeriod == period then return end
    if self._ticker and self._ticker.Cancel then self._ticker:Cancel() end
    self._ticker, self._tickerPeriod = nil, nil
    local timer = rawget(_G, "C_Timer")
    if period and type(timer) == "table" and type(timer.NewTicker) == "function" then
        self._ticker = timer.NewTicker(period, function() TS:Refresh("RESYNC") end)
        self._tickerPeriod = period
    end
end

-- ---------------------------------------------------------------------------
-- CONSULTA
-- ---------------------------------------------------------------------------

function TS:GetStatus() return self._status end
function TS:GetRevision() return self._revision end
function TS:IsActive() return self._status == RUNNING or self._status == PENDING end
function TS:IsCompleting() return self._status == COMPLETING end

-- Snapshot actual. Es de solo lectura por contrato: nadie debe modificarlo.
function TS:GetSnapshot() return self._snapshot end

function TS:_LiveElapsed(snap)
    if not snap.elapsedBase then return nil end
    return snap.elapsedBase + math.max(0, mono() - (snap.elapsedAt or mono()))
end

-- Segundos de llave. Interpolado mientras corre; congelado al completar.
function TS:GetElapsed()
    local snap = self._snapshot
    if self._status == COMPLETED or self._status == COMPLETING then return snap.finalElapsed end
    if self._status == RUNNING or self._status == PENDING then return self:_LiveElapsed(snap) end
    return nil
end

-- Puede ser negativo: eso es informacion (fuera de tiempo), no un error.
function TS:GetTimeRemaining()
    local e, limit = self:GetElapsed(), self._snapshot.timeLimit
    if not e or not limit then return nil end
    return limit - e
end

-- Copia con los campos vivos calculados, para quien necesite una foto estable.
function TS:GetLiveSnapshot()
    local out = {}
    for k, v in pairs(self._snapshot) do out[k] = v end
    out.elapsed = self:GetElapsed()
    out.timeRemaining = self:GetTimeRemaining()
    return out
end

-- ---------------------------------------------------------------------------
-- DIAGNOSTICO
-- ---------------------------------------------------------------------------

local function text(v)
    local S = MitzuMPlus.QASafe
    if S then return S.Text(v) end
    return v == nil and "nil" or tostring(v)
end

local function fmtTime(sec)
    if type(sec) ~= "number" then return "nil" end
    local neg = sec < 0
    sec = math.floor(math.abs(sec))
    return string.format("%s%d:%02d", neg and "-" or "", math.floor(sec / 60), sec % 60)
end

function TS:DiagnosticFields()
    local s = self:GetLiveSnapshot()
    local st = self._stats
    return {
        { "stateVersion", TS.VERSION },
        { "status", self._status },
        { "revision", self._revision },
        { "mapID", s.mapID },
        { "keystoneLevel", s.keystoneLevel },
        { "elapsed", s.elapsed and math.floor(s.elapsed) or nil },
        { "timeLimit", s.timeLimit },
        { "timeRemaining", s.timeRemaining and math.floor(s.timeRemaining) or nil },
        { "forcesCurrent", s.forcesCurrent },
        { "forcesTotal", s.forcesTotal },
        { "forcesPercent", s.forcesPercent and string.format("%.2f", s.forcesPercent) or nil },
        { "forcesRemaining", s.forcesRemaining },
        { "bossesCompleted", s.bossesCompleted },
        { "bossesTotal", s.bossesTotal },
        { "deaths", s.deaths },
        { "recovered", s.recovered },
        { "stale", string.format("timer=%s forces=%s bosses=%s", text(s.timerStale), text(s.forcesStale), text(s.bossesStale)) },
        { "warnings", (#s.warnings > 0) and table.concat(s.warnings, ",") or "none" },
        { "runWarnings", (s.runWarnings and #s.runWarnings > 0) and table.concat(s.runWarnings, ",") or "none" },
        { "transient", (s.transient and #s.transient > 0) and table.concat(s.transient, ",") or "none" },
        { "refreshes", st.refreshes },
        { "coalesced", st.coalesced },
        { "adapterErrors", st.adapterErrors },
        { "resyncPeriod", self._tickerPeriod },
        { "finalElapsed", s.finalElapsed and math.floor(s.finalElapsed) or nil },
        { "completionConverged", s.completionConverged },
        { "completionAttempts", s.completionAttempts },
        { "completionConvergenceMs", s.completionConvergenceMs },
        { "completionCriteriaIncomplete", s.completionCriteriaIncomplete },
        { "completionRegressionsIgnored", s.completionRegressionsIgnored },
        { "completionSource", s.completionSource },
        { "terminalStateConfirmed", s.terminalStateConfirmed },
        { "criteriaUnavailableAfterCompletion", s.criteriaUnavailableAfterCompletion },
        { "bossesCompletedObserved", s.bossesCompletedObserved },
        { "bossesCompletedFinal", s.bossesCompletedFinal },
        { "bossCountSource", s.bossCountSource },
        { "forcesPercentFinal", s.forcesPercentFinal and string.format("%.2f", s.forcesPercentFinal) or nil },
        { "forcesCompletionSource", s.forcesCompletionSource },
        { "completionWindowOpen", self._completion ~= nil },
        { "duplicateCompletions", st.duplicateCompletions },
    }
end

function TS:ReportLines()
    local L = { "=== MitzuMPlus [DEV] TrackerState v" .. TS.VERSION .. " ===" }
    local s = self:GetLiveSnapshot()
    L[#L + 1] = string.format("status=%s revision=%s reason=%s recovered=%s", text(self._status),
        text(self._revision), text(s.reason), text(s.recovered))
    L[#L + 1] = string.format("map=%s (%s) level=%s", text(s.mapID), text(s.mapName), text(s.keystoneLevel))
    L[#L + 1] = string.format("elapsed=%s limit=%s remaining=%s timerSource=%s timerStale=%s",
        fmtTime(s.elapsed), fmtTime(s.timeLimit), fmtTime(s.timeRemaining), text(s.timerSource), text(s.timerStale))
    L[#L + 1] = string.format("forces=%s/%s %s remaining=%s (%s) source=%s stale=%s",
        text(s.forcesCurrent), text(s.forcesTotal),
        s.forcesPercent and string.format("%.2f%%", s.forcesPercent) or "nil",
        text(s.forcesRemaining),
        s.forcesRemainingPercent and string.format("%.2f%%", s.forcesRemainingPercent) or "nil",
        text(s.forcesSource), text(s.forcesStale))
    L[#L + 1] = string.format("bosses=%s/%s stale=%s deaths=%s timeLost=%s", text(s.bossesCompleted),
        text(s.bossesTotal), text(s.bossesStale), text(s.deaths), text(s.deathTimeLost))
    for _, b in ipairs(s.bosses or {}) do
        L[#L + 1] = string.format("  boss[%s] %s completed=%s", text(b.index), text(b.name), text(b.completed))
    end
    if s.completedAt then
        L[#L + 1] = string.format("completedAt=%s finalElapsed=%s", text(s.completedAt), fmtTime(s.finalElapsed))
        L[#L + 1] = string.format("completionConverged=%s completionAttempts=%s completionConvergenceMs=%s "
            .. "completionCriteriaIncomplete=%s regressionsIgnored=%s windowOpen=%s",
            text(s.completionConverged), text(s.completionAttempts), text(s.completionConvergenceMs),
            text(s.completionCriteriaIncomplete), text(s.completionRegressionsIgnored), text(self._completion ~= nil))
        L[#L + 1] = string.format("completionSource=%s terminalStateConfirmed=%s criteriaUnavailableAfterCompletion=%s",
            text(s.completionSource), text(s.terminalStateConfirmed), text(s.criteriaUnavailableAfterCompletion))
        L[#L + 1] = string.format("bossesObserved=%s bossesFinal=%s/%s bossCountSource=%s forcesFinal=%s forcesCompletionSource=%s",
            text(s.bossesCompletedObserved), text(s.bossesCompletedFinal), text(s.bossesTotal), text(s.bossCountSource),
            s.forcesPercentFinal and string.format("%.2f%%", s.forcesPercentFinal) or "nil", text(s.forcesCompletionSource))
        if s.terminalStateConfirmed and not s.completionConverged then
            L[#L + 1] = "  (Blizzard retiro los criterios antes de mostrar el final: la llave termino segun "
                .. text(s.completionSource) .. " y lo inferido queda marcado; limitacion del cliente, no error)"
        end
    end
    L[#L + 1] = "warnings=" .. ((#s.warnings > 0) and table.concat(s.warnings, ",") or "none")
    L[#L + 1] = "runWarnings=" .. ((s.runWarnings and #s.runWarnings > 0) and table.concat(s.runWarnings, ",") or "none")
    L[#L + 1] = "transient=" .. ((s.transient and #s.transient > 0) and table.concat(s.transient, ",")
        or "none") .. " (sincronizacion normal del cliente; aviso solo si dura mas de " .. TS.TRANSIENT_WINDOW .. " s)"
    local st = self._stats
    local ev = {}
    for name, n in pairs(st.events) do ev[#ev + 1] = name .. "=" .. n end
    table.sort(ev)
    L[#L + 1] = string.format("refreshes=%d coalesced=%d adapterErrors=%d resync=%s lastReason=%s duplicateCompletions=%d",
        st.refreshes, st.coalesced, st.adapterErrors, text(self._tickerPeriod), text(st.lastReason),
        st.duplicateCompletions)
    L[#L + 1] = "events " .. ((#ev > 0) and table.concat(ev, " ") or "none")
    L[#L + 1] = "registeredEvents=" .. text(self._registered and table.concat(self._registered, ",") or nil)
    L[#L + 1] = "=== END ==="
    return L
end

-- ---------------------------------------------------------------------------
-- ARRANQUE
-- ---------------------------------------------------------------------------

local function eventIsValid(name)
    local utils = rawget(_G, "C_EventUtils")
    local fn = type(utils) == "table" and utils.IsEventValid or nil
    if type(fn) ~= "function" then return nil end
    local ok, valid = pcall(fn, name)
    if not ok then return nil end
    return valid == true
end

function TS:RegisterEvents()
    if self._frame then return self._registered end
    local create = rawget(_G, "CreateFrame")
    if type(create) ~= "function" then return nil end
    local frame = create("Frame")
    self._frame = frame
    self._registered, self._rejected = {}, {}
    for _, name in ipairs(TS.EVENTS) do
        -- Registrar un evento inexistente lanza error: se valida y se protege.
        if eventIsValid(name) ~= false and pcall(frame.RegisterEvent, frame, name) then
            self._registered[#self._registered + 1] = name
        else
            self._rejected[#self._rejected + 1] = name
        end
    end
    if #self._rejected > 0 then record("EVENTS_REJECTED", { events = table.concat(self._rejected, ",") }) end
    frame:SetScript("OnEvent", function(_, event) TS:OnEvent(event) end)
    return self._registered
end

TS:Reset()
TS:RegisterEvents()

return TS
