-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · ArrowDemoTelemetry v1.0  —  EXPERIMENTAL
--
-- OBSERVAR Y REGISTRAR. Nada más.
--
-- No decide, no pone flechas, no avanza pulls, no produce identidad. Recibe lo
-- que ArrowDemo ve y decide, lo que el cliente anuncia por eventos, y lo
-- apunta con una marca de tiempo relativa al inicio de la llave, para poder
-- ponerlo después al lado del vídeo de la run.
--
-- ═════════════════════════════════════════════════════════════════════════
-- EL EJE DE TIEMPO
--
--     T = segundos desde CHALLENGE_MODE_START, con resolución de milisegundo
--
-- Se construye así: al abrir la sesión se anota GetTime() local y el tiempo
-- que el SERVIDOR dice que lleva la llave (ChallengeClock). Cada evento vale
--     base + (GetTime() - t0Local)
-- GetTime() es monotónico, así que T también. La base viene del temporizador
-- del servidor, que va en segundos enteros: la alineación ABSOLUTA con el
-- vídeo tiene ±1 s; la RELATIVA entre eventos, milisegundo. La cuenta atrás
-- de la llave se ve en el vídeo, y con eso se cuadra el segundo que falta.
--
-- Si la demo se enciende a mitad de llave, o hay un /reload, la base es el
-- tiempo ya transcurrido: todas las sesiones de una misma run comparten eje.
-- ═════════════════════════════════════════════════════════════════════════
--
-- NADA SECRETO SE GUARDA. Todo lo que llega a SavedVariables es un literal de
-- este fichero, un número calculado aquí, o un token de placa RECONSTRUIDO
-- ("nameplate" .. número) — nunca el string original. Si un valor del cliente
-- no se puede demostrar público, se escribe su ESTADO y no el valor.
--
-- MEMORIA ACOTADA. Topes fijos por run y como mucho tres runs guardadas. Al
-- llenarse, se deja de guardar DETALLE pero los contadores siguen siendo
-- exactos: se prefiere una línea temporal continua desde T+0 a una que
-- empieza a la mitad.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local T = {}
AR.ArrowDemoTelemetry = T

T.FORMAT = "MITZU_ARROW_DEMO_TELEMETRY_V1"

-- Topes. Configurables desde aquí; /emp arrowdemo status los enseña.
T.LIMITS = {
    MAX_RUNS          = 3,     -- runs completas guardadas
    MAX_EVENTS        = 6000,  -- líneas de detalle por run (sin contar casts)
    RESERVED_EVENTS   = 64,    -- hueco garantizado para el cierre de sesión
    MAX_CAST_EVENTS   = 2500,  -- líneas de cast por run
    MAX_SNAPSHOTS     = 900,   -- a 5 s son 75 minutos
    SNAPSHOT_INTERVAL = 5,     -- segundos
    QUIET_CONFIRM     = 3,     -- segundos a 0 enganchados antes de anotarlo
}

-- Vocabulario cerrado de códigos. Cualquier otro se rechaza al registrar.
local CODES = {
    -- sesión
    "SESSION_START", "SESSION_RESUMED", "SESSION_END", "CHALLENGE_START",
    "CHALLENGE_END", "ROUTE_SELECTED", "PULL_CHANGED", "MANUAL_NEXT",
    "ENCOUNTER_START", "ENCOUNTER_END",
    -- placas
    "NAMEPLATE_ADDED", "NAMEPLATE_REMOVED", "NAMEPLATE_SEEDED",
    "TOKEN_GENERATION_CHANGED",
    -- engagement
    "ENGAGEMENT_STARTED", "ENGAGEMENT_ENDED", "ENGAGEMENT_DIP",
    "ENGAGED", "NOT_ENGAGED", "UNKNOWN_ENGAGEMENT",
    -- flechas de la demo
    "DEMO_ARROW_WANTED", "DEMO_ARROW_APPLIED", "DEMO_ARROW_REMOVED",
    "DEMO_ARROW_REUSED", "DEMO_ARROW_REJECTED", "DEMO_ARROW_SKIPPED",
    -- casts
    "CAST_START", "CAST_CHANNEL", "CAST_EMPOWER", "CAST_SUCCEEDED",
    "CAST_STOP", "CAST_INTERRUPTED",
    -- problemas
    "LUA_ERROR", "INCONSISTENCY", "ARROW_ORPHAN", "GENERATION_MISMATCH",
    "POOL_INCONSISTENCY",
    -- FASE 4: alineación ruta <-> ejecución física. SOLO diagnóstico: ninguno
    -- de estos códigos implica que se haya tocado la ruta.
    "PHYSICAL_EPISODE_START", "PHYSICAL_EPISODE_END", "OBSERVATION",
    "PULL_CANDIDATE", "ALIGNMENT", "POSSIBLE_WIPE",
}
T.CODES = {}
for _, c in ipairs(CODES) do T.CODES[c] = c end

local CAST_CODES = {
    CAST_START = true, CAST_CHANNEL = true, CAST_EMPOWER = true,
    CAST_SUCCEEDED = true, CAST_STOP = true, CAST_INTERRUPTED = true,
}

-- Orden fijo del resumen: el export sale igual siempre.
local SUMMARY_KEYS = {
    "pullsVisited", "pullChanges", "manualNext", "automaticRouteProgress",
    "generations", "nameplatesAdded", "nameplatesRemoved", "nameplatesSeeded",
    "tokenReuses",
    "episodes", "peakEngaged", "engagedTransitions", "unknownSamples",
    "demoWanted", "demoPlacements", "demoRemovals", "demoReuses",
    "demoRejections", "demoSkipped", "demoPeakSimultaneous",
    "castEvents", "safeSpellIDs", "secretSpellIDs",
    "encounters",
    "staleArrowEvents", "orphanArrowEvents", "generationMismatch",
    "poolInconsistencies", "luaErrors", "inconsistencies",
    "eventsDropped", "castLinesDropped", "snapshotsDropped",
    -- FASE 4. Se añaden AL FINAL: las claves anteriores no se mueven de sitio
    -- y un export viejo sigue leyéndose igual.
    "physicalEpisodes", "possibleWipes", "alignmentEvaluations",
    "alignmentStrong", "alignmentProbable", "alignmentAmbiguous",
    "alignmentWeak", "alignmentNoEvidence", "alignmentChains",
    "alignmentLogSuppressed", "alignmentAnchorAdvances", "alignmentAnchorResyncs",
    "npcIDAvailablePeak", "npcIDSecretPeak", "npcIDUnavailablePeak",
    "routeProgressInit",
}
T.SUMMARY_KEYS = SUMMARY_KEYS

-- ─────────────────────────────────────────────────────────────────────────
-- SANEADO
--
-- Tres puertas, y ninguna devuelve el valor que entró sin rehacerlo.
-- ─────────────────────────────────────────────────────────────────────────

local function estadoSecreto(v)
    local iss = rawget(_G, "issecretvalue")
    if type(iss) ~= "function" then return nil end
    local ok, res = pcall(iss, v)
    if not ok then return nil end
    if res == true then return true end
    if res == false then return false end
    return nil
end

-- Token de placa: se extraen los dígitos y se CONSTRUYE un string nuevo.
local function tokenSano(tok)
    if type(tok) ~= "string" then return nil end
    local ok, digitos = pcall(string.match, tok, "^nameplate(%d+)$")
    if not ok or not digitos then return nil end
    local n = tonumber(digitos)
    if not n then return nil end
    return "nameplate" .. string.format("%d", n)
end

-- Texto de fuera (nombre de mazmorra, id de ruta): solo si se demuestra
-- público, y rehecho con un alfabeto que no puede romper el formato de
-- export: sin "|" (en una EditBox de WoW es el carácter de ESCAPE: "|r"
-- cierra un color y "|T" abre una textura), sin "=" y sin saltos de línea.
-- Los bytes 128-255 se conservan: son los de las tildes en UTF-8, y ninguno
-- puede formar un carácter ASCII de control.
local function textoSano(v, max)
    if type(v) ~= "string" then return nil end
    if estadoSecreto(v) ~= false then return nil end
    local ok, limpio = pcall(function()
        return (v:gsub("[^%w %-%._':,\128-\255]", ""):gsub("%s+", " "))
    end)
    if not ok or type(limpio) ~= "string" or limpio == "" then return nil end
    return limpio:sub(1, max or 64)
end

-- Un texto de fuera, apto para ir DENTRO de una línea de evento, donde el
-- espacio separa campos: los espacios pasan a "_".
local function campoSano(v, max)
    local t = textoSano(v, max)
    if not t then return nil end
    return (t:gsub(" ", "_"))
end

-- Número de fuera: solo si es un número público.
local function numeroSano(v)
    if type(v) ~= "number" then return nil end
    if estadoSecreto(v) ~= false then return nil end
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

T._sanitize = { token = tokenSano, text = textoSano, field = campoSano,
                number = numeroSano }

-- Llama a un método de otro módulo sin dejar que reviente aquí.
local function llamar(obj, metodo, ...)
    if type(obj) ~= "table" or type(obj[metodo]) ~= "function" then return nil end
    local ok, v = pcall(obj[metodo], obj, ...)
    if not ok then return nil end
    return v
end

-- ─────────────────────────────────────────────────────────────────────────
-- ALMACÉN
--
-- Vive en MPlusAdaptiveRouteDB.arrowDemo. ProfileManager fusiona sin
-- destruir, así que una clave nueva sobrevive a sus cargas. Antes de que el
-- SavedVariable exista (o en las pruebas) se usa una tabla en memoria.
-- ─────────────────────────────────────────────────────────────────────────

T._memory = { runs = {} }

function T:Store()
    local root = rawget(_G, "MPlusAdaptiveRouteDB")
    local s
    if type(root) == "table" then
        if type(root.arrowDemo) ~= "table" then root.arrowDemo = { runs = {} } end
        s = root.arrowDemo
    else
        s = self._memory
    end
    if type(s.runs) ~= "table" then s.runs = {} end
    return s
end

-- ─────────────────────────────────────────────────────────────────────────
-- RELOJ
-- ─────────────────────────────────────────────────────────────────────────

local function ahora()
    local f = rawget(_G, "GetTime")
    if type(f) ~= "function" then return 0 end
    local ok, t = pcall(f)
    if not ok or type(t) ~= "number" then return 0 end
    return t
end

-- Milisegundos en el eje de la llave. Nunca retrocede.
function T:NowMs()
    local s = self._session
    if not s then return 0 end
    local ms = math.floor((s.base + (ahora() - s.t0Local)) * 1000 + 0.5)
    if ms < s.lastMs then ms = s.lastMs end
    s.lastMs = ms
    return ms
end

local function formatoTiempo(ms)
    ms = math.max(0, math.floor(tonumber(ms) or 0))
    local min = math.floor(ms / 60000)
    local seg = math.floor((ms % 60000) / 1000)
    return string.format("%02d:%02d.%03d", min, seg, ms % 1000)
end
T.FormatTime = formatoTiempo

-- ─────────────────────────────────────────────────────────────────────────
-- CONTEXTO (solo lectura de otros módulos)
-- ─────────────────────────────────────────────────────────────────────────

local function runtimeState()
    local DC = MitzuMPlus.DungeonContext
    local ok, st = pcall(function() return DC and DC:GetState() end)
    return (ok and type(st) == "string") and st or "UNKNOWN"
end

local function elapsedServidor()
    local CC = MitzuMPlus.ChallengeClock
    local ok, e = pcall(function() return CC and CC:GetElapsed() end)
    return (ok and type(e) == "number") and e or nil
end

local function startedAtEpoch()
    local CC = MitzuMPlus.ChallengeClock
    local ok, e = pcall(function() return CC and CC:GetStartedAt() end)
    return (ok and type(e) == "number") and e or nil
end

local function rutaYPull()
    local RP = MitzuMPlus.RouteProgress
    if not RP then return nil, nil, nil end
    local ok, route, idx, count = pcall(function()
        return RP:GetRoute(), RP:GetPullIndex(), RP:GetPullCount()
    end)
    if not ok then return nil, nil, nil end
    return route, idx, count
end

-- Resumen ESTÁTICO del pull: cuántos espera y cuántos grupos físicos toca.
-- Sale de los datos de ruta empaquetados, no de nada en vivo.
function T:PullInfo(route, pullIndex)
    local info = { expected = nil, expectedState = "UNKNOWN", groups = nil,
                   partialGroups = nil, coverage = "UNKNOWN" }
    if type(route) ~= "table" or type(route.pulls) ~= "table" then return info end
    local pull = route.pulls[pullIndex or -1]
    local PE = AR.PackEvidence
    if PE and PE.ExpectedFromPull then
        local ok, n, st = pcall(PE.ExpectedFromPull, PE, pull)
        if ok and type(n) == "number" then info.expected, info.expectedState = n, "AVAILABLE" end
    end
    local PGM = AR.PhysicalGroupMetadata
    if PGM and PGM.AnalyzePull then
        local ok, r = pcall(PGM.AnalyzePull, PGM, route, pullIndex)
        if ok and type(r) == "table" and type(r.groups) == "table" then
            info.groups = #r.groups
            info.partialGroups = tonumber(r.partialGroups) or 0
            if r.state == "AVAILABLE" then
                info.coverage = (info.partialGroups > 0) and "PARTIAL" or "COMPLETE"
            end
        end
    end
    return info
end

-- ─────────────────────────────────────────────────────────────────────────
-- SESIÓN
-- ─────────────────────────────────────────────────────────────────────────

T._session   = nil   -- estado vivo, no se guarda tal cual
T._snapshotProvider = nil
T._ticker    = nil

function T:IsRecording() return self._session ~= nil end
function T:SetSnapshotProvider(fn) self._snapshotProvider = fn end

local function nuevoRun(meta)
    local run = {
        format = T.FORMAT, meta = meta, counters = {},
        events = {}, casts = {}, snapshots = {},
    }
    for _, k in ipairs(SUMMARY_KEYS) do run.counters[k] = 0 end
    return run
end

local function sumar(run, k, n)
    if not run then return end
    run.counters[k] = (run.counters[k] or 0) + (n or 1)
end
local function maximo(run, k, v)
    if not run then return end
    if (run.counters[k] or 0) < v then run.counters[k] = v end
end

-- Huella de la run para decidir si un /reload continúa la misma llave. Es la
-- lección de RunSession: dos llaves iguales se distinguen por el cronómetro
-- del servidor, no por la mazmorra.
local function mismaRun(meta, mapID, epoch)
    if type(meta) ~= "table" then return false end
    if not mapID or meta.challengeMapID ~= mapID then return false end
    if not epoch or type(meta.startedAtEpoch) ~= "number" then return false end
    return math.abs(meta.startedAtEpoch - epoch) <= 3
end

-- reason: "KEY_STARTED" (T+0 genuino) | "DEMO_ON" | "RESUMED"
function T:StartSession(reason)
    if self._session then return false, "ya hay una sesion" end
    local store = self:Store()
    local DC = MitzuMPlus.DungeonContext
    local mapID = numeroSano(llamar(DC, "GetChallengeMapID"))
    local epoch = startedAtEpoch()
    -- En KEY_STARTED el servidor dirá 0 o 1: la base es lo que lleve la llave,
    -- y así un arranque con retraso no desplaza todo el eje.
    local base = elapsedServidor() or 0

    -- ¿Continúa una run a medias (un /reload)?
    local run = store.current
    local resumed = false
    if run and mismaRun(run.meta, mapID, epoch) and run.meta.status == "RUNNING" then
        resumed = true
    elseif run then
        -- La run anterior quedó colgada y no es esta: se cierra como PARTIAL.
        run.meta.status = "PARTIAL"
        self:_Archive(run)
        store.current = nil
        run = nil
    end

    if not run then
        local route, idx, count = rutaYPull()
        local keyLevel = numeroSano(llamar(DC, "GetKeystoneLevel"))
        local nombre   = textoSano(llamar(DC, "GetDungeonName"))
        local fecha = (type(date) == "function") and date("%Y-%m-%d %H:%M:%S") or nil
        run = nuevoRun({
            format = T.FORMAT,
            status = "RUNNING",
            dungeon = nombre,
            challengeMapID = mapID,
            keyLevel = keyLevel,
            route = route and campoSano(route.id, 64) or nil,
            pullCount = numeroSano(count),
            t0 = "CHALLENGE_MODE_START",
            timeUnit = "ms_since_T0",
            startedAtEpoch = epoch,
            sessionStartDate = textoSano(fecha, 32),
            sessionStartReason = reason,
            serverElapsedAtSessionStart = math.floor(base),
            alignment = "absolute_pm1s_relative_ms",
        })
        store.current = run
    end

    self._session = {
        run = run, base = base, t0Local = ahora(), lastMs = 0,
        engagement = {},       -- [token] = { gen, state }
        episode = { active = false, n = 0 },
        lastPull = nil,
        errorsPrinted = 0,
    }
    -- Si se reanuda, el último ms guardado manda: el eje no retrocede.
    if resumed and type(run.meta.lastMs) == "number" then
        self._session.lastMs = run.meta.lastMs
    end

    if resumed then
        self:Log("SESSION_RESUMED", { "base", math.floor(base) })
    else
        self:Log("SESSION_START", { "reason", reason, "base", math.floor(base) })
        if reason == "KEY_STARTED" then self:Log("CHALLENGE_START") end
    end

    local route, idx, count = rutaYPull()
    if route then
        self:Log("ROUTE_SELECTED", { "route", campoSano(route.id, 64) or "-",
            "pullCount", numeroSano(count) or 0, "pull", numeroSano(idx) or 0 })
        self:_PullContext(idx, nil, "SESSION")
    end

    self:_StartTicker()
    return true, resumed
end

function T:EndSession(status)
    local s = self._session
    if not s then return false end
    if status == "COMPLETED" or status == "RESET" then
        self:Log("CHALLENGE_END", { "status", status }, true)
    end
    self:Log("SESSION_END", { "status", status or "UNKNOWN" }, true)
    local run = s.run
    run.meta.status = status or "UNKNOWN"
    run.meta.durationMs = s.lastMs
    run.meta.lastMs = s.lastMs
    self:_StopTicker()
    self._session = nil

    local store = self:Store()
    if store.current == run then store.current = nil end
    -- Un cierre por /reload no llega aquí: la run se queda en `current` y se
    -- reanuda o se archiva como PARTIAL al volver.
    self:_Archive(run)
    return true, run
end

function T:_Archive(run)
    local store = self:Store()
    table.insert(store.runs, 1, run)
    while #store.runs > self.LIMITS.MAX_RUNS do
        table.remove(store.runs)
    end
end

-- Antes del /reload: dejar anotado hasta dónde llegó el eje.
function T:Checkpoint()
    local s = self._session
    if s then s.run.meta.lastMs = s.lastMs end
end

function T:ClearStored()
    local store = self:Store()
    local n = #store.runs
    store.runs = {}
    if not self._session then store.current = nil end
    return n
end

-- ─────────────────────────────────────────────────────────────────────────
-- REGISTRO
--
-- Una línea por evento:   <ms> <CODIGO> clave=valor clave=valor ...
--
-- fields es una lista PLANA y ORDENADA: { clave1, valor1, clave2, valor2 }.
-- El orden es el del código que llama, así que el export es determinista.
-- Los valores tienen que ser números o strings nuestros; cualquier otra cosa
-- se escribe como "-". Nunca se hace tostring de un valor que no se conoce.
-- ─────────────────────────────────────────────────────────────────────────

-- Valor DENTRO de una línea de evento: sin espacios (separan campos), sin
-- "=" y sin "|" (escape de WoW).
--
-- Lo primero, antes de formatear o comparar con nada: si el cliente dice que
-- el valor es secreto, se escribe "-". Un número secreto no se puede sanear
-- (formatearlo ya es tocarlo) y un string secreto podría atravesar el
-- string.match de abajo con el resultado marcado en vez de fallar.
-- Sin issecretvalue (un cliente anterior a Midnight, donde no existen los
-- secretos) los números propios se escriben: no hay nada que filtrar.
local function valorLinea(v)
    if v ~= nil and estadoSecreto(v) == true then return "-" end
    local t = type(v)
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "-" end
        if v == math.floor(v) then return string.format("%d", v) end
        return string.format("%.3f", v)
    end
    if t == "boolean" then return v and "true" or "false" end
    if t == "string" then
        local ok, bueno = pcall(string.match, v, "^[%w_%-%.:/',\128-\255]+$")
        if ok and bueno then return v end
        return "-"
    end
    return "-"
end

-- Valor de una línea meta.clave=valor: aquí sí caben espacios, porque el
-- valor llega hasta el final de la línea.
local function valorMeta(v)
    if v ~= nil and estadoSecreto(v) == true then return "-" end
    if type(v) == "string" then
        local ok, bueno = pcall(string.match, v, "^[%w _%-%.:/',\128-\255]+$")
        if ok and bueno then return v end
        return "-"
    end
    return valorLinea(v)
end

function T:Log(code, fields, reserved)
    local s = self._session
    if not s then return false end
    if not self.CODES[code] then
        sumar(s.run, "inconsistencies")
        return false
    end
    local partes = { string.format("%d", self:NowMs()), code }
    if type(fields) == "table" then
        for i = 1, #fields, 2 do
            local k, v = fields[i], fields[i + 1]
            if type(k) == "string" then
                partes[#partes + 1] = k .. "=" .. valorLinea(v)
            end
        end
    end
    local linea = table.concat(partes, " ")
    local run = s.run

    if CAST_CODES[code] then
        if #run.casts < self.LIMITS.MAX_CAST_EVENTS then
            run.casts[#run.casts + 1] = linea
        else
            sumar(run, "castLinesDropped")
        end
        return true
    end

    local tope = self.LIMITS.MAX_EVENTS
    if reserved then tope = tope + self.LIMITS.RESERVED_EVENTS end
    if #run.events < tope then
        run.events[#run.events + 1] = linea
        return true
    end
    sumar(run, "eventsDropped")
    return false
end

-- Contadores sueltos, para quien decide (ArrowDemo) sin tener que escribir
-- una línea por cada cosa que cuenta.
function T:Count(key, n)
    local s = self._session
    if not s then return end
    sumar(s.run, key, n)
end
function T:Max(key, v)
    local s = self._session
    if not s then return end
    maximo(s.run, key, v)
end

function T:Error(where)
    local s = self._session
    if not s then return end
    sumar(s.run, "luaErrors")
    -- Ni el mensaje ni la traza se guardan: podrían arrastrar texto de
    -- quién sabe dónde. El sitio basta para ir a buscarlo.
    self:Log("LUA_ERROR", { "where", where or "UNKNOWN" }, true)
    if s.errorsPrinted == 0 and MitzuMPlus.Print then
        s.errorsPrinted = 1
        pcall(MitzuMPlus.Print, MitzuMPlus,
            "|cFFff9922Arrow Demo: error interno registrado (/emp arrowdemo report).|r")
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- RUTA
-- ─────────────────────────────────────────────────────────────────────────

function T:_PullContext(pullIndex, prev, reason)
    local s = self._session
    if not s then return end
    local route, idx, count = rutaYPull()
    pullIndex = pullIndex or idx
    local info = self:PullInfo(route, pullIndex)
    s.pullInfo = info
    s.lastPull = pullIndex
    if reason ~= "SESSION" then
        self:Log("PULL_CHANGED", {
            "pull", numeroSano(pullIndex) or 0, "from", numeroSano(prev) or 0,
            "pullCount", numeroSano(count) or 0, "reason", reason or "UNKNOWN",
            "expected", info.expected or "-", "groups", info.groups or "-",
            "partialGroups", info.partialGroups or "-", "coverage", info.coverage,
        })
        sumar(s.run, "pullChanges")
        if reason == "MANUAL" and numeroSano(pullIndex) and numeroSano(prev)
           and pullIndex == prev + 1 then
            self:Log("MANUAL_NEXT", { "pull", pullIndex })
            sumar(s.run, "manualNext")
        end
        -- Cualquier cambio de pull que no venga del jugador ni de una
        -- recuperación es progreso automático, venga de donde venga. Es una
        -- medición real, no un cero puesto a mano.
        --
        -- BUG ENCONTRADO EN LA TELEMETRÍA LIVE DEL 2026-09-11: la run de
        -- Altar of Fangs salió con automaticRouteProgress=1 sin que nada
        -- hubiera inferido nada. El culpable era `RunSession` poniendo el
        -- pull a 1 con reason=NEW_RUN al arrancar la llave. Eso es
        -- INICIALIZACIÓN, no inferencia. Poner la ruta en su punto de
        -- partida y adivinar por dónde vamos son cosas distintas y ahora se
        -- cuentan por separado: la invariante de la fase 4 no se cumple
        -- silenciando nada, se cumple clasificando bien.
        if reason == "NEW_RUN" or reason == "RESET" then
            sumar(s.run, "routeProgressInit")
        elseif reason ~= "MANUAL" and reason ~= "RECOVERY" then
            sumar(s.run, "automaticRouteProgress")
        end
    end
    s.visitedPulls = s.visitedPulls or {}
    if pullIndex and not s.visitedPulls[pullIndex] then
        s.visitedPulls[pullIndex] = true
        sumar(s.run, "pullsVisited")
    end
end

function T:OnPullChanged(n, prev, reason)
    if not self._session then return end
    local r = (type(reason) == "string") and valorLinea(reason) or "UNKNOWN"
    self:_PullContext(n, prev, r)
end

-- ─────────────────────────────────────────────────────────────────────────
-- PLACAS (avisos de NameplateGenerations)
-- ─────────────────────────────────────────────────────────────────────────

function T:OnGeneration(kind, token, gen, prevGen)
    local s = self._session
    if not s then return end
    local tok = tokenSano(token)
    if kind == "ADDED" then
        self:Log("NAMEPLATE_ADDED", { "token", tok or "-", "gen", gen })
        sumar(s.run, "nameplatesAdded")
        sumar(s.run, "generations")
    elseif kind == "SEEDED" then
        self:Log("NAMEPLATE_SEEDED", { "token", tok or "-", "gen", gen })
        sumar(s.run, "nameplatesSeeded")
        sumar(s.run, "generations")
    elseif kind == "REMOVED" then
        self:Log("NAMEPLATE_REMOVED", { "token", tok or "-", "gen", prevGen or "-" })
        sumar(s.run, "nameplatesRemoved")
        local ep = s.episode
        if ep.active and prevGen and ep.gens and ep.gens[prevGen] then
            ep.removed = (ep.removed or 0) + 1
        end
        if tok then s.engagement[tok] = nil end
    elseif kind == "REPLACED" then
        self:Log("TOKEN_GENERATION_CHANGED", { "token", tok or "-", "from", prevGen or "-" })
        sumar(s.run, "tokenReuses")
        if tok then s.engagement[tok] = nil end
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- ENGAGEMENT
--
-- obs = { { token, gen, engagement }, ... } tal y como lo ve ArrowDemo en su
-- tick. Aquí solo se anotan TRANSICIONES, no cada muestra.
--
-- EPISODIOS: observaciones para estudiar después "PullExecution". Un
-- episodio empieza cuando se pasa de 0 a más de 0 enganchados y se da por
-- tranquilo tras QUIET_CONFIRM segundos a 0. NO se afirma que un episodio sea
-- un pull de la ruta, ni que el pico sea el tamaño del pull, ni que las
-- generaciones enganchadas sean clones.
-- ─────────────────────────────────────────────────────────────────────────

local ENG_CODE = { ENGAGED = "ENGAGED", NOT_ENGAGED = "NOT_ENGAGED",
                   UNKNOWN = "UNKNOWN_ENGAGEMENT" }

function T:ObserveEngagement(obs)
    local s = self._session
    if not s or type(obs) ~= "table" then return end
    local run = s.run
    local engagedNow, unknownNow = 0, 0

    for _, o in ipairs(obs) do
        local tok = tokenSano(o.token)
        local gen = numeroSano(o.gen)
        local est = ENG_CODE[o.engagement] and o.engagement or "UNKNOWN"
        if tok and gen then
            if est == "ENGAGED" then engagedNow = engagedNow + 1
            elseif est == "UNKNOWN" then
                unknownNow = unknownNow + 1
                sumar(run, "unknownSamples")
            end
            local prev = s.engagement[tok]
            if not prev or prev.gen ~= gen then
                -- Primera vez que se ve este ocupante. NOT_ENGAGED es lo normal
                -- y ya lo dice NAMEPLATE_ADDED: solo se anota lo que no lo es.
                if est ~= "NOT_ENGAGED" then
                    self:Log(ENG_CODE[est], { "token", tok, "gen", gen })
                    sumar(run, "engagedTransitions")
                end
                s.engagement[tok] = { gen = gen, state = est }
            elseif prev.state ~= est then
                self:Log(ENG_CODE[est], { "token", tok, "gen", gen, "from", prev.state })
                sumar(run, "engagedTransitions")
                prev.state = est
            end
        end
    end

    maximo(run, "peakEngaged", engagedNow)
    s.lastEngaged, s.lastUnknown = engagedNow, unknownNow

    local ep = s.episode
    local t = self:NowMs()
    if not ep.active then
        if engagedNow > 0 then
            ep.active, ep.n = true, ep.n + 1
            ep.startMs, ep.peak, ep.joined, ep.removed = t, engagedNow, 0, 0
            ep.gens, ep.genCount, ep.initial, ep.quietSince = {}, 0, {}, nil
            for _, o in ipairs(obs) do
                if o.engagement == "ENGAGED" and numeroSano(o.gen) then
                    ep.initial[o.gen] = true
                    ep.gens[o.gen] = true
                    ep.genCount = ep.genCount + 1
                end
            end
            sumar(run, "episodes")
            self:Log("ENGAGEMENT_STARTED", { "obs", "possibleExecutionStart",
                "ep", ep.n, "engaged", engagedNow, "pull", s.lastPull or "-" })
        end
        return
    end

    for _, o in ipairs(obs) do
        local g = numeroSano(o.gen)
        if o.engagement == "ENGAGED" and g and not ep.gens[g] then
            ep.gens[g] = true
            ep.genCount = ep.genCount + 1
            if not ep.initial[g] then ep.joined = ep.joined + 1 end
        end
    end
    if engagedNow > ep.peak then ep.peak = engagedNow end

    if engagedNow == 0 and unknownNow == 0 then
        if not ep.quietSince then
            ep.quietSince = t
        elseif (t - ep.quietSince) >= self.LIMITS.QUIET_CONFIRM * 1000 then
            self:Log("ENGAGEMENT_ENDED", { "obs", "possibleQuietStart",
                "ep", ep.n, "quietAt", ep.quietSince,
                "peakSimultaneousEngaged", ep.peak,
                "generationsEverEngaged", ep.genCount,
                "joinedDuringExecution", ep.joined,
                "removedDuringExecution", ep.removed,
                "durationMs", ep.quietSince - ep.startMs,
                "pull", s.lastPull or "-" })
            ep.active = false
        end
    elseif ep.quietSince then
        -- Volvió el combate antes de confirmar la calma: no era el final.
        self:Log("ENGAGEMENT_DIP", { "ep", ep.n, "durMs", t - ep.quietSince })
        ep.quietSince = nil
    end
end

function T:CurrentEpisode()
    local s = self._session
    return s and s.episode or nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- CASTS
--
-- Payload tras `unit`: (castGUID, spellID). El castGUID es un string secreto
-- y no se ata a ninguna variable: select(2, ...) lo deja donde está. Del
-- spellID se guarda su ESTADO; el número solo si se demuestra público.
-- ─────────────────────────────────────────────────────────────────────────

local CAST_EVENTS = {
    UNIT_SPELLCAST_START         = "CAST_START",
    UNIT_SPELLCAST_CHANNEL_START = "CAST_CHANNEL",
    UNIT_SPELLCAST_EMPOWER_START = "CAST_EMPOWER",
    UNIT_SPELLCAST_SUCCEEDED     = "CAST_SUCCEEDED",
    UNIT_SPELLCAST_STOP          = "CAST_STOP",
    UNIT_SPELLCAST_CHANNEL_STOP  = "CAST_STOP",
    UNIT_SPELLCAST_EMPOWER_STOP  = "CAST_STOP",
    UNIT_SPELLCAST_INTERRUPTED   = "CAST_INTERRUPTED",
}
T.CAST_EVENTS = CAST_EVENTS

local function clasificarSpellID(...)
    local id = select(2, ...)
    if id == nil then return "UNAVAILABLE", nil end
    local sec = estadoSecreto(id)
    if sec ~= false then return "SECRET", nil end
    if type(id) ~= "number" then return "UNAVAILABLE", nil end
    return "AVAILABLE", id
end

function T:OnCastEvent(event, unitToken, ...)
    local s = self._session
    if not s then return nil end
    local code = CAST_EVENTS[event]
    if not code then return nil end
    local tok = tokenSano(unitToken)
    if not tok then return nil end
    local NG = AR.NameplateGenerations
    local gen = NG and NG:Current(tok) or nil
    local st, id = clasificarSpellID(...)
    sumar(s.run, "castEvents")
    if st == "AVAILABLE" then sumar(s.run, "safeSpellIDs")
    elseif st == "SECRET" then sumar(s.run, "secretSpellIDs") end
    local fields = { "token", tok, "gen", gen or "-", "spellIDState", st }
    if st == "AVAILABLE" then
        fields[#fields + 1] = "spellID"
        fields[#fields + 1] = id
    end
    self:Log(code, fields)
    return code
end

-- El estado del encuentro se guarda FUERA de la sesión: el tracker de
-- episodios lo consulta para segmentar, y tiene que saberlo aunque la
-- telemetría no esté grabando.
T._encounterActive = false
function T:IsEncounterActive() return self._encounterActive == true end

function T:OnEncounter(event)
    if event == "ENCOUNTER_START" then self._encounterActive = true
    elseif event == "ENCOUNTER_END" then self._encounterActive = false end
    local s = self._session
    if not s then return end
    if event == "ENCOUNTER_START" then
        sumar(s.run, "encounters")
        self:Log("ENCOUNTER_START", { "pull", s.lastPull or "-" })
    elseif event == "ENCOUNTER_END" then
        self:Log("ENCOUNTER_END", { "pull", s.lastPull or "-" })
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- SNAPSHOTS — ligeros, cada SNAPSHOT_INTERVAL segundos, nunca por frame.
-- ─────────────────────────────────────────────────────────────────────────

function T:Snapshot()
    local s = self._session
    if not s then return false end
    local run = s.run
    if #run.snapshots >= self.LIMITS.MAX_SNAPSHOTS then
        sumar(run, "snapshotsDropped")
        return false
    end
    local extra = {}
    if self._snapshotProvider then
        local ok, e = pcall(self._snapshotProvider)
        if ok and type(e) == "table" then extra = e end
    end
    local _, idx, count = rutaYPull()
    local NG = AR.NameplateGenerations
    local ep = s.episode
    local info = s.pullInfo or {}
    local campos = {
        string.format("%d", self:NowMs()),
        "SNAPSHOT",
        "rt=" .. valorLinea(runtimeState()),
        "pull=" .. valorLinea(idx or "-") .. "/" .. valorLinea(count or "-"),
        "visible=" .. valorLinea(extra.visible or 0),
        "engaged=" .. valorLinea(extra.engaged or s.lastEngaged or 0),
        "notEngaged=" .. valorLinea(extra.notEngaged or 0),
        "unknownEngagement=" .. valorLinea(extra.unknown or s.lastUnknown or 0),
        "demoCandidates=" .. valorLinea(extra.candidates or 0),
        "demoArrowsVisible=" .. valorLinea(extra.arrows or 0),
        "peakEngagedCurrentExecution=" .. valorLinea(ep.active and ep.peak or 0),
        "nameplateGenerationsActive=" .. valorLinea(NG and NG:ActiveCount() or 0),
        "physicalGroupsKnown=" .. valorLinea(info.groups or "-"),
    }
    run.snapshots[#run.snapshots + 1] = table.concat(campos, " ")
    if s.lastMs then run.meta.lastMs = s.lastMs end
    return true
end

function T:_StartTicker()
    self:_StopTicker()
    local CT = rawget(_G, "C_Timer")
    if type(CT) == "table" and type(CT.NewTicker) == "function" then
        self._ticker = CT.NewTicker(self.LIMITS.SNAPSHOT_INTERVAL, function()
            local ok = pcall(T.Snapshot, T)
            if not ok then T:Error("SNAPSHOT") end
        end)
    end
end

function T:_StopTicker()
    if self._ticker and self._ticker.Cancel then pcall(self._ticker.Cancel, self._ticker) end
    self._ticker = nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- LECTURA: resumen, informe, log y export
-- ─────────────────────────────────────────────────────────────────────────

-- run = índice (1 = la más reciente guardada) o nil (la viva si la hay).
function T:GetRun(which)
    if which == nil and self._session then return self._session.run, true end
    local store = self:Store()
    local i = tonumber(which) or 1
    return store.runs[i], false
end

function T:ReportLines(run)
    if type(run) ~= "table" then return { "|cFFff9922No hay ninguna run de Arrow Demo guardada.|r" } end
    local m, c = run.meta or {}, run.counters or {}
    local function v(x) return valorLinea(x ~= nil and x or "-") end
    local dur = tonumber(m.durationMs or m.lastMs) or 0
    return {
        "|cFFe8b84a--- Arrow Demo Report ---|r",
        "Dungeon: " .. valorMeta(m.dungeon or "-") .. "  Key: +" .. v(m.keyLevel) ..
            "  Duration: " .. formatoTiempo(dur) .. "  Status: " .. v(m.status),
        "Route: " .. v(m.route) .. "  pulls=" .. v(m.pullCount) ..
            "  visited=" .. v(c.pullsVisited) .. "  manualNext=" .. v(c.manualNext),
        "Nameplates: generations=" .. v(c.generations) .. " added=" .. v(c.nameplatesAdded) ..
            " removed=" .. v(c.nameplatesRemoved) .. " tokenReuses=" .. v(c.tokenReuses),
        "Engagement: episodes=" .. v(c.episodes) .. " peakEngaged=" .. v(c.peakEngaged) ..
            " unknownSamples=" .. v(c.unknownSamples),
        "Demo arrows: placements=" .. v(c.demoPlacements) .. " removals=" .. v(c.demoRemovals) ..
            " reuses=" .. v(c.demoReuses) .. " rejections=" .. v(c.demoRejections) ..
            " peakSimultaneous=" .. v(c.demoPeakSimultaneous),
        "Cast: events=" .. v(c.castEvents) .. " safeSpellIDs=" .. v(c.safeSpellIDs) ..
            " secretSpellIDs=" .. v(c.secretSpellIDs),
        "Alignment: episodes=" .. v(c.physicalEpisodes) ..
            " evals=" .. v(c.alignmentEvaluations) ..
            " strong=" .. v(c.alignmentStrong) .. " probable=" .. v(c.alignmentProbable) ..
            " ambiguous=" .. v(c.alignmentAmbiguous) .. " weak=" .. v(c.alignmentWeak) ..
            " noEvidence=" .. v(c.alignmentNoEvidence) ..
            " chains=" .. v(c.alignmentChains) .. " wipes=" .. v(c.possibleWipes),
        "Identity (pico por episodio): npcIDAvailable=" .. v(c.npcIDAvailablePeak) ..
            " npcIDSecret=" .. v(c.npcIDSecretPeak) ..
            " npcIDUnavailable=" .. v(c.npcIDUnavailablePeak),
        "Safety: resolverMatchesFabricated=0 identityWrites=0 (estructural)" ..
            " automaticRouteProgress=" .. v(c.automaticRouteProgress) .. " (medido)" ..
            " routeProgressInit=" .. v(c.routeProgressInit) .. " (NEW_RUN/RESET)",
        "Possible problems: staleArrowEvents=" .. v(c.staleArrowEvents) ..
            " orphanArrowEvents=" .. v(c.orphanArrowEvents) ..
            " generationMismatch=" .. v(c.generationMismatch) ..
            " luaErrors=" .. v(c.luaErrors),
        "Stored: events=" .. #(run.events or {}) .. " casts=" .. #(run.casts or {}) ..
            " snapshots=" .. #(run.snapshots or {}) .. " dropped=" ..
            v((c.eventsDropped or 0) + (c.castLinesDropped or 0) + (c.snapshotsDropped or 0)),
    }
end

-- Las últimas n líneas de eventos, con el tiempo ya formateado.
function T:LogLines(run, n)
    if type(run) ~= "table" then return {} end
    n = tonumber(n) or 15
    local ev = run.events or {}
    local out = {}
    for i = math.max(1, #ev - n + 1), #ev do
        local ms, resto = ev[i]:match("^(%d+) (.*)$")
        out[#out + 1] = formatoTiempo(ms) .. " " .. (resto or "")
    end
    return out
end

local META_KEYS = {
    "format", "status", "dungeon", "challengeMapID", "keyLevel", "route",
    "pullCount", "t0", "timeUnit", "alignment", "startedAtEpoch",
    "sessionStartDate", "sessionStartReason", "serverElapsedAtSessionStart",
    "durationMs",
}

-- FORMATO MITZU_ARROW_DEMO_TELEMETRY_V1 (texto, una cosa por línea):
--   línea 1                    MITZU_ARROW_DEMO_TELEMETRY_V1
--   "# meta"      -> meta.<clave>=<valor>          (orden fijo, META_KEYS;
--                                                   el valor llega a fin de línea)
--   "# summary"   -> summary.<clave>=<n>            (orden fijo, SUMMARY_KEYS)
--   "# events"    -> mm:ss.mmm CODIGO k=v k=v       (orden de llegada)
--   "# casts"     -> mm:ss.mmm CAST_* k=v ...
--   "# snapshots" -> mm:ss.mmm SNAPSHOT k=v ...
--   "# end"
-- Separador de campos: UN espacio. Los valores de campo nunca contienen
-- espacios, "=" ni "|": este último es el carácter de escape de las EditBox
-- de WoW y rompería la caja de copia. Mismo run, mismo texto, byte a byte.
function T:Export(run)
    if type(run) ~= "table" then return nil end
    local L = { T.FORMAT, "# meta" }
    local m, c = run.meta or {}, run.counters or {}
    for _, k in ipairs(META_KEYS) do
        L[#L + 1] = "meta." .. k .. "=" .. valorMeta(m[k] ~= nil and m[k] or "-")
    end
    L[#L + 1] = "# summary"
    for _, k in ipairs(SUMMARY_KEYS) do
        L[#L + 1] = "summary." .. k .. "=" .. valorLinea(c[k] or 0)
    end
    local function volcar(titulo, lista)
        L[#L + 1] = "# " .. titulo
        for _, linea in ipairs(lista or {}) do
            local ms, resto = linea:match("^(%d+) (.*)$")
            if ms then L[#L + 1] = formatoTiempo(ms) .. " " .. resto end
        end
    end
    volcar("events", run.events)
    volcar("casts", run.casts)
    volcar("snapshots", run.snapshots)
    L[#L + 1] = "# end"
    return table.concat(L, "\n")
end

-- ─────────────────────────────────────────────────────────────────────────
-- EVENTOS DEL CLIENTE
--
-- Registrados AL CARGAR y apagados con la bandera de sesión (taint). Sin
-- sesión, cada handler sale en la primera línea.
-- ─────────────────────────────────────────────────────────────────────────

if type(CreateFrame) == "function" then
    local frame = CreateFrame("Frame")
    for ev in pairs(CAST_EVENTS) do frame:RegisterEvent(ev) end
    frame:RegisterEvent("ENCOUNTER_START")
    frame:RegisterEvent("ENCOUNTER_END")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_LOGOUT" then
            pcall(T.Checkpoint, T)
            return
        end
        -- ENCOUNTER pasa SIEMPRE: marca un estado que otros consultan, y
        -- perderse un END por no estar grabando dejaría "hay boss" colgado
        -- para siempre. Dentro, OnEncounter ya sale solo si no hay sesión.
        if event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
            if not pcall(T.OnEncounter, T, event) then T:Error("EVENT") end
            return
        end
        if not T._session then return end
        if not pcall(T.OnCastEvent, T, event, ...) then T:Error("EVENT") end
    end)
    T._frame = frame
end

local NG = AR.NameplateGenerations
if NG and NG.Subscribe then
    NG:Subscribe(function(kind, token, gen, prev)
        if not T._session then return end
        local ok = pcall(T.OnGeneration, T, kind, token, gen, prev)
        if not ok then T:Error("GENERATION") end
    end)
end

if MitzuMPlus.EventBus then
    -- Prioridad alta: el cambio de pull queda anotado ANTES de que nadie
    -- reaccione a él, y así las retiradas de flechas salen detrás.
    MitzuMPlus.EventBus:On("MITZU_PULL_CHANGED", function(n, prev, reason)
        if not T._session then return end
        local ok = pcall(T.OnPullChanged, T, n, prev, reason)
        if not ok then T:Error("PULL") end
    end, 90)
end

return T
