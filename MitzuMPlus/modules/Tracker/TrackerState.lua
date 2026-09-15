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
--   COMPLETED  CHALLENGE_MODE_COMPLETED visto; snapshot final congelado hasta
--              que empiece otra llave (START / RESET / inactiva -> activa)
-- ===========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local TS = {}
MitzuMPlus.TrackerState = TS

TS.VERSION = 1

local IDLE, PENDING, RUNNING, COMPLETED = "IDLE", "PENDING", "RUNNING", "COMPLETED"
TS.STATUS = { IDLE = IDLE, PENDING = PENDING, RUNNING = RUNNING, COMPLETED = COMPLETED }

TS.REFRESH_DELAY       = 0.2   -- segundos para fundir eventos en rafaga
TS.RESYNC_PENDING      = 1     -- esperando el temporizador
TS.RESYNC_RUNNING      = 5     -- recalibrar reloj y recoger lo que no avise
TS.RECOVERED_THRESHOLD = 15    -- primera lectura con mas tiempo => llave recuperada
TS.TIMER_REGRESSION    = 2     -- segundos hacia atras tolerados antes de avisar
TS.MAX_WARNINGS        = 24

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
    return { status = IDLE, active = false, warnings = {}, bosses = {},
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
    self._awaitingNewRun = false
    self._sawInactive = false
    self._stats = { refreshes = 0, coalesced = 0, adapterErrors = 0, events = {}, lastReason = nil }
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

    for _, w in ipairs(type(raw.warnings) == "table" and raw.warnings or {}) do
        self:_Warn(snap, "ADAPTER_" .. tostring(w))
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
        return false
    end
    local ok, raw = pcall(adapter.GetSnapshot, adapter)
    if not ok or type(raw) ~= "table" then
        -- El adaptador nunca deberia lanzar; si lo hace, se conserva lo sabido.
        stats.adapterErrors = stats.adapterErrors + 1
        stats.lastAdapterError = tostring(raw)
        record("ADAPTER_ERROR", { reason = reason })
        return false
    end
    self:_Apply(raw, reason)
    return true
end

function TS:_Apply(raw, reason)
    local prev = self._snapshot or emptySnapshot()
    local status = self._status

    if raw.active == true then
        local newRun = false
        if status == IDLE then
            newRun = true
        elseif status == COMPLETED then
            newRun = (not self._awaitingNewRun) or self._sawInactive
        elseif self._run and raw.mapID and self._run.mapID and raw.mapID ~= self._run.mapID then
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
            return self:_Complete(snap, reason)
        end
        self:_SetStatus(snap.elapsedBase and RUNNING or PENDING, reason)
        return self:_Commit(snap, reason)
    end

    if raw.active == false then
        if status == RUNNING or status == PENDING then
            if self._completedEvent then
                -- Tras completar, los criterios aun se leen: foto final.
                local snap = self:_BuildActive(raw, prev)
                snap.active = false
                return self:_Complete(snap, reason)
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

function TS:_Complete(snap, reason)
    snap.completedAt = epoch()
    snap.finalElapsed = self._completedElapsed or self:_LiveElapsed(snap)
    snap.timerStale = false
    self._completedEvent = nil
    self._completedElapsed = nil
    self._awaitingNewRun = true
    self._sawInactive = snap.active == false
    self:_SetStatus(COMPLETED, reason)
    record("RUN_COMPLETED", {
        map = snap.mapID, level = snap.keystoneLevel,
        elapsed = snap.finalElapsed and math.floor(snap.finalElapsed) or nil,
        forces = snap.forcesPercent and string.format("%.2f", snap.forcesPercent) or nil,
        bosses = snap.bossesTotal and (tostring(snap.bossesCompleted) .. "/" .. tostring(snap.bossesTotal)) or nil,
    })
    self:_Commit(snap, reason)
    emit("MITZU_TRACKER_RUN_COMPLETED", self)
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
        self._completedEvent = true
        self._completedElapsed = self:GetElapsed()
        -- Lectura inmediata: la foto final no debe esperar a la coalescencia.
        -- El aviso se consume en esta misma lectura; si no habia llave que
        -- cerrar, no puede quedarse armado para la siguiente.
        local ok = self:Refresh(event)
        self._completedEvent, self._completedElapsed = nil, nil
        return ok
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

-- Snapshot actual. Es de solo lectura por contrato: nadie debe modificarlo.
function TS:GetSnapshot() return self._snapshot end

function TS:_LiveElapsed(snap)
    if not snap.elapsedBase then return nil end
    return snap.elapsedBase + math.max(0, mono() - (snap.elapsedAt or mono()))
end

-- Segundos de llave. Interpolado mientras corre; congelado al completar.
function TS:GetElapsed()
    local snap = self._snapshot
    if self._status == COMPLETED then return snap.finalElapsed end
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
        { "refreshes", st.refreshes },
        { "coalesced", st.coalesced },
        { "adapterErrors", st.adapterErrors },
        { "resyncPeriod", self._tickerPeriod },
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
    end
    L[#L + 1] = "warnings=" .. ((#s.warnings > 0) and table.concat(s.warnings, ",") or "none")
    L[#L + 1] = "runWarnings=" .. ((s.runWarnings and #s.runWarnings > 0) and table.concat(s.runWarnings, ",") or "none")
    local st = self._stats
    local ev = {}
    for name, n in pairs(st.events) do ev[#ev + 1] = name .. "=" .. n end
    table.sort(ev)
    L[#L + 1] = string.format("refreshes=%d coalesced=%d adapterErrors=%d resync=%s lastReason=%s",
        st.refreshes, st.coalesced, st.adapterErrors, text(self._tickerPeriod), text(st.lastReason))
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
