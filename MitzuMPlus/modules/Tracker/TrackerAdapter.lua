-- ===========================================================================
-- MitzuMPlus - Tracker/TrackerAdapter  (1.1.0)
--
-- La UNICA capa del tracker 1.1 que habla con las APIs de Blizzard.
--
--     Blizzard API -> TrackerAdapter -> TrackerState -> Pace/Prediction -> HUD
--
-- Responsabilidad: leer, proteger y normalizar. Nada mas.
--   * no guarda estado entre lecturas (eso es TrackerState);
--   * no registra eventos ni tickers;
--   * no predice ni pinta;
--   * no sabe de rutas, pulls, NPCs ni placas.
--
-- REGLAS
--   1. Que una funcion exista no significa que funcione. Toda llamada va en
--      pcall y cada ruta de API lleva su propio registro de uso (OK / MISSING /
--      ERROR / EMPTY) para el informe de capacidades.
--   2. "No lo se" es una respuesta valida: nil. Nunca se devuelve 0 fingiendo
--      un dato (0% de fuerzas, 0 s de llave) cuando la API no contesto.
--   3. Midnight (12.x) marca algunos valores como SECRETOS. Un valor secreto no
--      se compara, no se concatena y no se convierte: se trata como ilegible.
--   4. Las APIs con forma de struct (C_ScenarioInfo) mandan; las multi-retorno
--      heredadas (C_Scenario) quedan como red por si el cliente no trae las
--      nuevas. Se informa de cual contesto.
--
-- APIS UTILIZADAS (todas opcionales; ver TrackerAdapter.API)
--   C_ChallengeMode.IsChallengeModeActive()   -> bool
--   C_ChallengeMode.GetActiveChallengeMapID() -> challengeMapID | nil
--   C_ChallengeMode.GetActiveKeystoneInfo()   -> level, affixIDs, wasCharged
--   C_ChallengeMode.GetMapUIInfo(mapID)       -> name, id, timeLimit, texture, bg
--   C_ChallengeMode.GetDeathCount()           -> numDeaths, timeLost
--   GetWorldElapsedTimers()                   -> timerID, ...
--   GetWorldElapsedTime(timerID)              -> description, elapsed, type
--   C_ScenarioInfo.GetScenarioInfo()          -> ScenarioInformation struct
--   C_Scenario.GetInfo()                      -> name, stage, numStages, flags,
--                                                ..., scenarioType (10o retorno)
--   C_ScenarioInfo.GetScenarioStepInfo()      -> ScenarioStepInfo struct
--   C_Scenario.GetStepInfo()                  -> title, desc, numCriteria, ...
--   C_ScenarioInfo.GetCriteriaInfo(i)         -> ScenarioCriteriaInfo struct
--   C_Scenario.GetCriteriaInfo(i)             -> multi-retorno heredado
--
-- FUERZAS ENEMIGAS - formato MEDIDO en Retail 12.1.0 (SavedVariables reales,
-- v1.0.0-beta.1), no supuesto:
--     isWeightedProgress = true
--     quantityString     = "183%"   <- RECUENTO crudo, con un "%" pegado
--     totalQuantity      = 729      <- total crudo de la mazmorra
--     quantity           = 25       <- PORCENTAJE entero, truncado
--   porcentaje = recuento / total * 100 = 25.10%  (coincide con quantity=25)
-- Es la regla que ya valida KeystoneTracker en llaves reales; aqui se
-- reimplementa como funcion pura para poder probarla y comparar (paridad).
-- ===========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local TA = {}
MitzuMPlus.TrackerAdapter = TA

TA.VERSION = 1

-- Estados de capacidad y de lectura.
local AVAILABLE, MISSING, ERROR, EMPTY, UNKNOWN = "AVAILABLE", "MISSING", "ERROR", "EMPTY", "UNKNOWN"
-- Una red heredada ausente cuando su API principal SI existe no es un problema:
-- se informa aparte y no entra en la firma de APIs que faltan.
local OPTIONAL_MISSING = "OPTIONAL_FALLBACK_MISSING"
TA.STATUS = { AVAILABLE = AVAILABLE, MISSING = MISSING, ERROR = ERROR, EMPTY = EMPTY, UNKNOWN = UNKNOWN,
              OPTIONAL_MISSING = OPTIONAL_MISSING }

-- Umbral a partir del cual el porcentaje calculado y el `quantity` oficial se
-- consideran en desacuerdo (quantity va truncado a entero: 1 punto es normal).
TA.FORCES_MISMATCH_POINTS = 3

-- Registro documental de cada API. `kind`: function | event | constant.
-- `required` indica si sin ella el tracker no puede funcionar en absoluto.
-- `fallbackFor` marca una red heredada: solo importa si falta su API principal.
TA.API = {
    { key = "challenge.active",   path = "C_ChallengeMode.IsChallengeModeActive",   kind = "function", required = true },
    { key = "challenge.mapID",    path = "C_ChallengeMode.GetActiveChallengeMapID", kind = "function", required = true },
    { key = "challenge.keystone", path = "C_ChallengeMode.GetActiveKeystoneInfo",   kind = "function" },
    { key = "challenge.mapInfo",  path = "C_ChallengeMode.GetMapUIInfo",            kind = "function", required = true },
    { key = "challenge.deaths",   path = "C_ChallengeMode.GetDeathCount",           kind = "function" },
    { key = "challenge.completion", path = "C_ChallengeMode.GetChallengeCompletionInfo", kind = "function" },
    { key = "timer.list",         path = "GetWorldElapsedTimers",                   kind = "function", required = true },
    { key = "timer.read",         path = "GetWorldElapsedTime",                     kind = "function", required = true },
    { key = "timer.typeEnum",     path = "Enum.WorldElapsedTimerTypes.ChallengeMode", kind = "constant" },
    { key = "timer.typeCM",       path = "LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE", kind = "constant",
      fallbackFor = "Enum.WorldElapsedTimerTypes.ChallengeMode" },
    { key = "scenario.info",      path = "C_ScenarioInfo.GetScenarioInfo",          kind = "function" },
    { key = "scenario.infoLegacy", path = "C_Scenario.GetInfo",                     kind = "function",
      fallbackFor = "C_ScenarioInfo.GetScenarioInfo" },
    { key = "scenario.step",      path = "C_ScenarioInfo.GetScenarioStepInfo",      kind = "function" },
    { key = "scenario.stepLegacy", path = "C_Scenario.GetStepInfo",                 kind = "function",
      fallbackFor = "C_ScenarioInfo.GetScenarioStepInfo" },
    { key = "scenario.criteria",  path = "C_ScenarioInfo.GetCriteriaInfo",          kind = "function" },
    { key = "scenario.criteriaLegacy", path = "C_Scenario.GetCriteriaInfo",        kind = "function",
      fallbackFor = "C_ScenarioInfo.GetCriteriaInfo" },
    { key = "scenario.typeCM",    path = "LE_SCENARIO_TYPE_CHALLENGE_MODE",         kind = "constant" },
    { key = "season.current",     path = "C_MythicPlus.GetCurrentSeason",           kind = "function" },
    { key = "secrets.check",      path = "issecretvalue",                           kind = "function" },
    { key = "events.validate",    path = "C_EventUtils.IsEventValid",               kind = "function" },
    { key = "event.start",        path = "CHALLENGE_MODE_START",                    kind = "event" },
    { key = "event.completed",    path = "CHALLENGE_MODE_COMPLETED",                kind = "event" },
    { key = "event.reset",        path = "CHALLENGE_MODE_RESET",                    kind = "event" },
    { key = "event.deaths",       path = "CHALLENGE_MODE_DEATH_COUNT_UPDATED",      kind = "event" },
    { key = "event.criteria",     path = "SCENARIO_CRITERIA_UPDATE",                kind = "event" },
    { key = "event.poi",          path = "SCENARIO_POI_UPDATE",                     kind = "event" },
    { key = "event.timerStart",   path = "WORLD_STATE_TIMER_START",                 kind = "event" },
    { key = "event.timerStop",    path = "WORLD_STATE_TIMER_STOP",                  kind = "event" },
}

-- Uso real de cada ruta en esta sesion: [path] = { status, calls, errors, lastError }.
-- Contadores enteros; no crece con el tiempo (una entrada por ruta).
TA._usage = {}

local unpack = rawget(_G, "unpack") or table.unpack

-- Empaqueta retornos conservando los nil intermedios (Lua 5.1 no trae table.pack).
local function pack(...)
    return { n = select("#", ...), ... }
end

local function indexField(t, k) return t[k] end

-- ---------------------------------------------------------------------------
-- UTILIDADES PURAS
-- ---------------------------------------------------------------------------

-- Resuelve "A.B.C" desde _G. Un indice que falle devuelve nil, no un error.
function TA.Resolve(path)
    if type(path) ~= "string" then return nil end
    local node = _G
    for part in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        local ok, v = pcall(indexField, node, part)
        if not ok then return nil end
        node = v
    end
    return node
end

-- Un valor es legible si existe y no es secreto. Si la propia comprobacion
-- falla, se trata como ilegible: ante la duda, no se toca.
function TA.IsReadable(v)
    if type(v) == "nil" then return false end
    local isSecret = rawget(_G, "issecretvalue")
    if type(isSecret) == "function" then
        local ok, secret = pcall(isSecret, v)
        if not ok or secret == true then return false end
    end
    local canAccess = rawget(_G, "canaccessvalue")
    if type(canAccess) == "function" then
        local ok, can = pcall(canAccess, v)
        if ok and can == false then return false end
    end
    return true
end

function TA.IsSecret(v)
    if type(v) == "nil" then return false end
    return not TA.IsReadable(v)
end

-- Numero finito legible, o nil.
function TA.Number(v)
    if not TA.IsReadable(v) then return nil end
    local ok, n = pcall(tonumber, v)
    if not ok or type(n) ~= "number" then return nil end
    if n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

-- Entero positivo (>0) legible, o nil. Muchas APIs devuelven 0 como "no hay".
function TA.PositiveNumber(v)
    local n = TA.Number(v)
    if n and n > 0 then return n end
    return nil
end

function TA.Bool(v)
    if not TA.IsReadable(v) then return nil end
    if v == true then return true end
    if v == false then return false end
    return nil
end

function TA.String(v)
    if not TA.IsReadable(v) then return nil end
    if type(v) == "string" then return v end
    if type(v) == "number" then
        local ok, s = pcall(tostring, v)
        return ok and s or nil
    end
    return nil
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Recuento de tropas desde quantityString. Acepta "183%", "183", " 183 %",
-- "1,234%" / "1.234%" (separadores de miles) y "183/729" (toma el primero).
-- Devuelve nil si no hay un numero entero utilizable.
function TA.ParseForcesCount(s)
    s = TA.String(s)
    if not s then return nil end
    local ok, lead = pcall(string.match, s, "^%s*([%d][%d%.,]*)")
    if not ok or not lead then return nil end
    -- Un separador solo es de miles si le siguen exactamente tres digitos.
    local valid = true
    for group in lead:gmatch("[%.,](%d*)") do
        if #group ~= 3 then valid = false end
    end
    if not valid then return nil end
    local digits = lead:gsub("[%.,]", "")
    return tonumber(digits)
end

-- ---------------------------------------------------------------------------
-- LLAMADAS PROTEGIDAS
-- ---------------------------------------------------------------------------

local function usage(path)
    local u = TA._usage[path]
    if not u then
        u = { status = UNKNOWN, calls = 0, errors = 0 }
        TA._usage[path] = u
    end
    return u
end

-- Llama a una API por su ruta. Devuelve (ok, ...) donde ok=false significa
-- ausente o con error. Registra el resultado en _usage.
function TA:Call(path, ...)
    local u = usage(path)
    u.calls = u.calls + 1
    local fn = TA.Resolve(path)
    if type(fn) ~= "function" then
        u.status = MISSING
        return false
    end
    local r = pack(pcall(fn, ...))
    if not r[1] then
        u.status = ERROR
        u.errors = u.errors + 1
        local S = MitzuMPlus.QASafe
        if S then
            u.lastError = S.Text(r[2], 160)
        else
            u.lastError = (type(r[2]) == "string") and r[2]:sub(1, 160) or "error"
        end
        return false
    end
    -- type() es seguro con valores secretos; una comparacion con nil no.
    u.status = (type(r[2]) == "nil") and EMPTY or AVAILABLE
    return true, unpack(r, 2, r.n)
end

function TA:HasFunction(path)
    return type(TA.Resolve(path)) == "function"
end

function TA:ResetUsage()
    self._usage = {}
end

-- ---------------------------------------------------------------------------
-- CHALLENGE MODE
-- ---------------------------------------------------------------------------

-- El tracker puede funcionar en este cliente: existen las APIs imprescindibles.
function TA:IsAvailable()
    for _, api in ipairs(TA.API) do
        if api.required and api.kind == "function" and not self:HasFunction(api.path) then
            return false, api.path
        end
    end
    return true
end

-- true / false, o nil si no se puede saber.
function TA:IsChallengeActive()
    local ok, active = self:Call("C_ChallengeMode.IsChallengeModeActive")
    if not ok then return nil end
    return TA.Bool(active)
end

function TA:GetMapID()
    local ok, id = self:Call("C_ChallengeMode.GetActiveChallengeMapID")
    if not ok then return nil end
    return TA.PositiveNumber(id)
end

-- level (>0) o nil; ademas lista de afijos legibles y el flag de carga.
function TA:GetKeystoneLevel()
    local ok, level, affixes, charged = self:Call("C_ChallengeMode.GetActiveKeystoneInfo")
    if not ok then return nil end
    local ids = {}
    if type(affixes) == "table" and TA.IsReadable(affixes) then
        for _, id in ipairs(affixes) do
            local n = TA.PositiveNumber(id)
            if n then ids[#ids + 1] = n end
        end
    end
    return TA.PositiveNumber(level), ids, TA.Bool(charged)
end

-- Informacion estatica de una mazmorra de piedra, o nil.
function TA:GetMapInfo(mapID)
    mapID = TA.PositiveNumber(mapID)
    if not mapID then return nil end
    local ok, name, id, timeLimit, texture, background = self:Call("C_ChallengeMode.GetMapUIInfo", mapID)
    if not ok then return nil end
    local info = {
        mapID = TA.PositiveNumber(id) or mapID,
        name = TA.String(name),
        timeLimit = TA.PositiveNumber(timeLimit),
        texture = TA.IsReadable(texture) and texture or nil,
        background = TA.IsReadable(background) and background or nil,
    }
    if not info.name and not info.timeLimit then return nil end
    return info
end

-- Limite oficial en segundos de la mazmorra activa (o de `mapID`), o nil.
function TA:GetTimeLimit(mapID)
    local info = self:GetMapInfo(mapID or self:GetMapID())
    return info and info.timeLimit or nil
end

-- deaths, timeLost (segundos). nil si la API no contesta.
function TA:GetDeathCount()
    local ok, deaths, timeLost = self:Call("C_ChallengeMode.GetDeathCount")
    if not ok then return nil end
    local d = TA.Number(deaths)
    if not d or d < 0 then return nil end
    local t = TA.Number(timeLost)
    return d, (t and t >= 0) and t or nil
end

-- ---------------------------------------------------------------------------
-- TEMPORIZADOR DEL SERVIDOR
--
-- Es el que sobrevive al /reload (BUG CLK-1 de 1.0). Sin interpolacion: eso lo
-- hara TrackerState. Aqui solo se lee lo que el servidor dice.
-- ---------------------------------------------------------------------------

-- Tipo de temporizador de Challenge Mode. El propio tracker de Blizzard (12.1.0
-- y 12.1.5, Blizzard_ScenarioObjectiveTracker.lua, ScenarioTimerMixin) compara
-- contra Enum.WorldElapsedTimerTypes.ChallengeMode; la constante LE_ heredada
-- no aparece en su codigo, asi que solo es red. Devuelve valor y fuente.
function TA.ChallengeTimerType()
    local v = TA.Number(TA.Resolve("Enum.WorldElapsedTimerTypes.ChallengeMode"))
    if v then return v, "ENUM" end
    v = TA.Number(rawget(_G, "LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE"))
    if v then return v, "LE_CONSTANT" end
    return nil
end

-- elapsed (segundos), timerID, fuente. nil si no hay temporizador de Challenge Mode.
function TA:GetElapsedTime()
    -- GetWorldElapsedTimers devuelve una lista variable de IDs.
    local r = pack(self:Call("GetWorldElapsedTimers"))
    if not r[1] then return nil end

    local typeCM = TA.ChallengeTimerType()
    for i = 2, r.n do
        local id = TA.Number(r[i])
        if id then
            local okT, _, elapsed, timerType = self:Call("GetWorldElapsedTime", id)
            local e = okT and TA.Number(elapsed) or nil
            if e and e >= 0 then
                local t = TA.Number(timerType)
                -- Sin la constante no se puede filtrar por tipo: se acepta el
                -- primero y se marca la fuente como no verificada.
                if typeCM == nil then return e, id, "WORLD_ELAPSED_TIMER_UNTYPED" end
                if t == typeCM then return e, id, "WORLD_ELAPSED_TIMER" end
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- ESCENARIO
-- ---------------------------------------------------------------------------

-- { name, currentStage, numStages, scenarioType, isChallengeMode, source } o nil.
function TA:GetScenarioInfo()
    local typeCM = TA.Number(rawget(_G, "LE_SCENARIO_TYPE_CHALLENGE_MODE"))
    local ok, info = self:Call("C_ScenarioInfo.GetScenarioInfo")
    if ok and type(info) == "table" and TA.IsReadable(info) then
        local out = {
            name = TA.String(info.name),
            currentStage = TA.Number(info.currentStage),
            numStages = TA.Number(info.numStages),
            scenarioType = TA.Number(info.type),
            scenarioID = TA.Number(info.scenarioID),
            source = "C_ScenarioInfo",
        }
        if out.scenarioType and typeCM then out.isChallengeMode = (out.scenarioType == typeCM) end
        return out
    end
    local okL, name, currentStage, numStages, _, _, _, _, _, _, scenarioType = self:Call("C_Scenario.GetInfo")
    if okL and type(name) ~= "nil" then
        local out = {
            name = TA.String(name),
            currentStage = TA.Number(currentStage),
            numStages = TA.Number(numStages),
            scenarioType = TA.Number(scenarioType),
            source = "C_Scenario",
        }
        if out.scenarioType and typeCM then out.isChallengeMode = (out.scenarioType == typeCM) end
        return out
    end
    return nil
end

-- { title, numCriteria, source } o nil. numCriteria nil = no se pudo leer.
function TA:GetStepInfo()
    local ok, info = self:Call("C_ScenarioInfo.GetScenarioStepInfo")
    if ok and type(info) == "table" and TA.IsReadable(info) then
        local n = TA.Number(info.numCriteria)
        if n then
            return { title = TA.String(info.title), numCriteria = n, source = "C_ScenarioInfo" }
        end
    end
    local okL, title, _, numCriteria = self:Call("C_Scenario.GetStepInfo")
    if okL then
        if type(title) == "table" and TA.IsReadable(title) then
            local n = TA.Number(title.numCriteria)
            if n then return { title = TA.String(title.title), numCriteria = n, source = "C_Scenario" } end
        else
            local n = TA.Number(numCriteria)
            if n then return { title = TA.String(title), numCriteria = n, source = "C_Scenario" } end
        end
    end
    return nil
end

-- Convierte cualquiera de las dos formas de criterio en una tabla comun.
-- Cada campo ilegible sale nil y su nombre se anota en `secret`.
function TA.NormalizeCriterion(index, raw, source)
    if type(raw) ~= "table" then return nil end
    local c = { index = index, source = source, secret = {} }
    local function field(name, reader)
        local v = raw[name]
        if type(v) ~= "nil" and not TA.IsReadable(v) then
            c.secret[#c.secret + 1] = name
            return nil
        end
        return reader(v)
    end
    c.description      = field("description", TA.String)
    c.completed        = field("completed", TA.Bool)
    c.quantity         = field("quantity", TA.Number)
    c.totalQuantity    = field("totalQuantity", TA.Number)
    c.quantityString   = field("quantityString", TA.String)
    c.criteriaID       = field("criteriaID", TA.Number)
    c.duration         = field("duration", TA.Number)
    c.elapsed          = field("elapsed", TA.Number)
    c.failed           = field("failed", TA.Bool)
    c.isWeightedProgress = field("isWeightedProgress", TA.Bool)

    if c.isWeightedProgress == true then
        c.kind = "ENEMY_FORCES"
    elseif c.isWeightedProgress == false then
        c.kind = "BOSS"
    else
        -- Sin la marca no se adivina por el texto (depende del idioma).
        c.kind = "UNKNOWN"
    end
    return c
end

function TA:GetCriteriaInfo(index)
    local ok, info = self:Call("C_ScenarioInfo.GetCriteriaInfo", index)
    if ok and type(info) == "table" and TA.IsReadable(info) then
        return TA.NormalizeCriterion(index, info, "C_ScenarioInfo")
    end
    local okL, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13 =
        self:Call("C_Scenario.GetCriteriaInfo", index)
    if not okL or type(r1) == "nil" then return nil end
    if type(r1) == "table" then
        return TA.NormalizeCriterion(index, r1, "C_Scenario")
    end
    return TA.NormalizeCriterion(index, {
        description = r1, criteriaType = r2, completed = r3, quantity = r4,
        totalQuantity = r5, flags = r6, assetID = r7, quantityString = r8,
        criteriaID = r9, duration = r10, elapsed = r11, failed = r12,
        isWeightedProgress = r13,
    }, "C_Scenario")
end

-- Lista completa de criterios del paso actual.
-- Devuelve { numCriteria, criteria = {...}, source, partial, missing = n } o nil
-- si no hay escenario legible.
function TA:GetCriteria()
    local step = self:GetStepInfo()
    if not step or not step.numCriteria or step.numCriteria <= 0 then return nil end
    local out = { numCriteria = step.numCriteria, criteria = {}, source = step.source,
                  partial = false, missing = 0 }
    for i = 1, step.numCriteria do
        local c = self:GetCriteriaInfo(i)
        if c then
            out.criteria[#out.criteria + 1] = c
            if #c.secret > 0 then out.partial = true end
        else
            out.missing = out.missing + 1
            out.partial = true
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- NORMALIZACION: FUERZAS Y BOSSES  (funciones puras, sin API)
-- ---------------------------------------------------------------------------

-- Fuerzas desde un criterio normalizado con isWeightedProgress=true.
-- Devuelve nil si el criterio no sirve, o:
--   { current, total, percent, remaining, remainingPercent, completed,
--     source = "COUNT_TOTAL" | "QUANTITY_PERCENT",
--     quantityPercent, mismatch, warning }
-- `current`/`remaining` son nil cuando solo se conoce el porcentaje.
function TA.NormalizeEnemyForces(c)
    if type(c) ~= "table" or c.isWeightedProgress ~= true then return nil end
    local total = c.totalQuantity
    if total and total <= 0 then total = nil end
    local count = TA.ParseForcesCount(c.quantityString)
    local qPct = c.quantity
    if qPct and (qPct < 0 or qPct > 100) then qPct = nil end

    local f = { total = total, quantityPercent = qPct, completed = c.completed }

    if count and total and count >= 0 and count <= total then
        f.current = count
        f.percent = count / total * 100
        f.source = "COUNT_TOTAL"
    elseif qPct then
        f.percent = qPct
        f.source = "QUANTITY_PERCENT"
        if count and total and count > total then
            f.warning = "COUNT_EXCEEDS_TOTAL"
        end
    elseif c.completed == true and total then
        -- Criterio cerrado sin cadena ni porcentaje legibles: esta al 100%.
        f.current = total
        f.percent = 100
        f.source = "COMPLETED_FLAG"
    else
        return nil
    end

    f.percent = clamp(f.percent, 0, 100)
    f.remainingPercent = 100 - f.percent
    if f.current and f.total then
        f.remaining = math.max(0, f.total - f.current)
    end

    if f.source == "COUNT_TOTAL" and qPct
       and math.abs(f.percent - qPct) > TA.FORCES_MISMATCH_POINTS then
        f.mismatch = true
        f.warning = "PERCENT_MISMATCH"
    end
    return f
end

-- { completed, total, list = { {index, name, completed, elapsed} }, unknown }
-- desde la lista normalizada de criterios. El primer criterio ponderado son
-- las fuerzas; cualquier criterio ponderado adicional no es un boss (BUG EF-2).
function TA.NormalizeBosses(criteria)
    local out = { completed = 0, total = 0, list = {}, unknown = 0 }
    if type(criteria) ~= "table" then return out end
    for _, c in ipairs(criteria) do
        if type(c) == "table" then
            if c.kind == "BOSS" then
                out.total = out.total + 1
                local done = c.completed == true
                if done then out.completed = out.completed + 1 end
                out.list[#out.list + 1] = {
                    index = c.index, name = c.description, completed = done,
                    elapsed = c.elapsed,
                }
            elseif c.kind == "UNKNOWN" then
                out.unknown = out.unknown + 1
            end
        end
    end
    return out
end

-- Primer criterio ponderado, normalizado como fuerzas. Tambien devuelve el
-- numero de criterios ponderados vistos (mas de uno es sospechoso).
function TA.PickEnemyForces(criteria)
    if type(criteria) ~= "table" then return nil, 0 end
    local seen, forces = 0, nil
    for _, c in ipairs(criteria) do
        if type(c) == "table" and c.kind == "ENEMY_FORCES" then
            seen = seen + 1
            if seen == 1 then forces = TA.NormalizeEnemyForces(c) end
        end
    end
    return forces, seen
end

function TA:GetEnemyForces()
    local list = self:GetCriteria()
    if not list then return nil, 0 end
    return TA.PickEnemyForces(list.criteria)
end

function TA:GetBossProgress()
    local list = self:GetCriteria()
    if not list then return nil end
    return TA.NormalizeBosses(list.criteria)
end

-- ---------------------------------------------------------------------------
-- SNAPSHOT
--
-- Una lectura completa, sin cache. Todos los campos pueden ser nil. TrackerState
-- (fase 2) sera quien la programe por eventos y la guarde.
-- ---------------------------------------------------------------------------

local function now()
    local fn = rawget(_G, "GetTime")
    if type(fn) ~= "function" then return 0 end
    local ok, v = pcall(fn)
    return (ok and tonumber(v)) or 0
end

function TA:GetSnapshot()
    local s = { adapterVersion = TA.VERSION, timestamp = now(), warnings = {} }
    local function warn(code) s.warnings[#s.warnings + 1] = code end

    s.available = self:IsAvailable()
    s.active = self:IsChallengeActive()
    if s.active == nil then warn("CHALLENGE_STATE_UNKNOWN") end

    s.mapID = self:GetMapID()
    s.keystoneLevel, s.affixIDs, s.charged = self:GetKeystoneLevel()
    local map = s.mapID and self:GetMapInfo(s.mapID) or nil
    s.mapName = map and map.name or nil
    s.timeLimit = map and map.timeLimit or nil

    s.elapsed, s.timerID, s.timerSource = self:GetElapsedTime()
    if s.timeLimit and s.elapsed then s.timeRemaining = s.timeLimit - s.elapsed end
    s.deaths, s.deathTimeLost = self:GetDeathCount()

    local scen = self:GetScenarioInfo()
    s.scenarioType = scen and scen.scenarioType or nil
    s.scenarioIsChallengeMode = scen and scen.isChallengeMode or nil

    local list = self:GetCriteria()
    s.criteriaCount = list and list.numCriteria or nil
    s.criteriaSource = list and list.source or nil
    s.criteriaPartial = list and list.partial or nil

    local forces, weighted = TA.PickEnemyForces(list and list.criteria)
    s.weightedCriteria = weighted
    if forces then
        s.forcesCurrent = forces.current
        s.forcesTotal = forces.total
        s.forcesPercent = forces.percent
        s.forcesRemaining = forces.remaining
        s.forcesRemainingPercent = forces.remainingPercent
        s.forcesSource = forces.source
        s.forcesQuantityPercent = forces.quantityPercent
        if forces.warning then warn("FORCES_" .. forces.warning) end
    end
    if weighted > 1 then warn("MULTIPLE_WEIGHTED_CRITERIA") end

    local bosses = TA.NormalizeBosses(list and list.criteria)
    if list then
        s.bossesCompleted = bosses.completed
        s.bossesTotal = bosses.total
        s.bosses = bosses.list
        if bosses.unknown > 0 then warn("UNCLASSIFIED_CRITERIA") end
    end

    -- Coherencia: una llave activa sin temporizador ni criterios es dato parcial
    -- (pasa unos segundos tras /reload), no una llave vacia.
    if s.active == true then
        if not s.mapID then warn("ACTIVE_WITHOUT_MAP") end
        if not s.elapsed then warn("ACTIVE_WITHOUT_TIMER") end
        if not list then warn("ACTIVE_WITHOUT_CRITERIA") end
        if list and not forces then warn("ACTIVE_WITHOUT_FORCES") end
    end
    if list and list.partial then warn("CRITERIA_PARTIAL") end
    return s
end

-- ---------------------------------------------------------------------------
-- CAPACIDADES
-- ---------------------------------------------------------------------------

-- Estado de cada API del registro: AVAILABLE / MISSING / UNKNOWN.
-- Para eventos se usa C_EventUtils.IsEventValid si existe; si no, UNKNOWN
-- (registrar un evento inexistente lanza error, asi que no se prueba asi).
function TA:ProbeCapabilities()
    local out = {}
    local validator = TA.Resolve("C_EventUtils.IsEventValid")
    for _, api in ipairs(TA.API) do
        local status
        if api.kind == "function" then
            status = self:HasFunction(api.path) and AVAILABLE or MISSING
        elseif api.kind == "constant" then
            status = (TA.Number(TA.Resolve(api.path)) ~= nil) and AVAILABLE or MISSING
        elseif api.kind == "event" then
            if type(validator) == "function" then
                local ok, valid = pcall(validator, api.path)
                if ok and valid == true then status = AVAILABLE
                elseif ok and valid == false then status = MISSING
                else status = UNKNOWN end
            else
                status = UNKNOWN
            end
        end
        if status == MISSING and api.fallbackFor then
            local primary = TA.Resolve(api.fallbackFor)
            local primaryPresent = (type(primary) == "function") or (TA.Number(primary) ~= nil)
            if primaryPresent then status = OPTIONAL_MISSING end
        end
        local u = TA._usage[api.path]
        out[#out + 1] = {
            key = api.key, path = api.path, kind = api.kind, required = api.required == true,
            fallbackFor = api.fallbackFor,
            status = status, lastCall = u and u.status or nil,
            calls = u and u.calls or 0, errors = u and u.errors or 0, lastError = u and u.lastError or nil,
        }
    end
    return out
end

-- Clasifica lo que falta. Devuelve { required = {keys}, optional = {keys},
-- legacyAbsent = n }. `required` vacio significa que el tracker puede funcionar;
-- `optional` son APIs no imprescindibles ausentes; `legacyAbsent` cuenta redes
-- heredadas que no hacen falta porque su API principal existe.
function TA:MissingCapabilities(caps)
    caps = caps or self:ProbeCapabilities()
    local out = { required = {}, optional = {}, legacyAbsent = 0 }
    for _, c in ipairs(caps) do
        if c.status == MISSING then
            local list = c.required and out.required or out.optional
            list[#list + 1] = c.key
        elseif c.status == OPTIONAL_MISSING then
            out.legacyAbsent = out.legacyAbsent + 1
        end
    end
    return out
end

local function listOrNone(list)
    return (#list == 0) and "none" or table.concat(list, ",")
end
TA.ListOrNone = listOrNone

-- Firma compacta, para registrar solo cuando cambia. Nunca "all": con todo
-- presente dice explicitamente "required=none;optional=none".
function TA:CapabilitySignature(caps)
    local m = self:MissingCapabilities(caps)
    return "required=" .. listOrNone(m.required) .. ";optional=" .. listOrNone(m.optional)
end

-- Deja constancia en la caja negra una vez por firma distinta (sin spam).
function TA:LogCapabilities(reason)
    local caps = self:ProbeCapabilities()
    local sig = self:CapabilitySignature(caps)
    if sig == self._loggedSignature then return false end
    self._loggedSignature = sig
    local FR = MitzuMPlus.FlightRecorder
    if FR and FR.Record then
        local available = self:IsAvailable()
        local m = self:MissingCapabilities(caps)
        FR:Record("TRACKER", "ADAPTER_CAPS", {
            available = available, requiredMissing = listOrNone(m.required),
            optionalMissing = listOrNone(m.optional), legacyAbsent = m.legacyAbsent,
            reason = reason or "probe",
        })
    end
    return true
end

-- ---------------------------------------------------------------------------
-- INFORME (DEV/QA)
-- ---------------------------------------------------------------------------

local function text(v)
    local S = MitzuMPlus.QASafe
    if S then return S.Text(v) end
    if v == nil then return "nil" end
    return tostring(v)
end

local function fmtTime(sec)
    if type(sec) ~= "number" then return "nil" end
    local neg = sec < 0
    sec = math.floor(math.abs(sec))
    return string.format("%s%d:%02d", neg and "-" or "", math.floor(sec / 60), sec % 60)
end
TA.FormatTime = fmtTime

local function fmtPct(p)
    if type(p) ~= "number" then return "nil" end
    return string.format("%.2f%%", p)
end

-- Comparacion con las autoridades de 1.0 (KeystoneTracker / ChallengeClock /
-- DungeonContext). Si el adaptador y la build estable no coinciden en una llave
-- real, manda la estable hasta entender por que.
function TA:ParityLines(s)
    local L = {}
    local DC, CC, KT = MitzuMPlus.DungeonContext, MitzuMPlus.ChallengeClock, MitzuMPlus.KeystoneTracker
    local function cmp(label, adapterValue, legacyValue, tolerance)
        local status
        if adapterValue == nil and legacyValue == nil then status = "BOTH_NIL"
        elseif adapterValue == nil or legacyValue == nil then status = "ONE_NIL"
        elseif type(adapterValue) == "number" and type(legacyValue) == "number" then
            status = (math.abs(adapterValue - legacyValue) <= (tolerance or 0)) and "MATCH" or "DIFF"
        else
            status = (adapterValue == legacyValue) and "MATCH" or "DIFF"
        end
        L[#L + 1] = string.format("%s adapter=%s legacy=%s -> %s", label, text(adapterValue), text(legacyValue), status)
    end
    -- Un solo retorno: si devolviera dos, el segundo se colaria como tolerancia.
    local function method(obj, name, ...)
        if type(obj) ~= "table" or type(obj[name]) ~= "function" then return nil end
        local ok, a = pcall(obj[name], obj, ...)
        if not ok then return nil end
        return a
    end
    cmp("challengeActive", s.active, method(DC, "IsChallengeActive"))
    cmp("mapID", s.mapID, method(DC, "GetChallengeMapID"))
    cmp("keystoneLevel", s.keystoneLevel, method(DC, "GetKeystoneLevel"))
    -- ChallengeClock interpola; se admite 2 s de diferencia.
    cmp("elapsed", s.elapsed, method(CC, "GetElapsed"), 2)
    cmp("timeLimit", s.timeLimit, method(CC, "GetTimeLimit"))
    local legacy = nil
    if method(KT, "IsActive") == true then legacy = method(KT, "GetOfficialSnapshot") end
    if type(legacy) == "table" then
        cmp("forcesPercent", s.forcesPercent, legacy.enemyPct, 0.01)
        cmp("forcesTotal", s.forcesTotal, legacy.enemyTotal)
        local done = 0
        for _, b in ipairs(legacy.bosses or {}) do if b.completed then done = done + 1 end end
        cmp("bossesCompleted", s.bossesCompleted, done)
        cmp("bossesTotal", s.bossesTotal, #(legacy.bosses or {}))
        cmp("deaths", s.deaths, legacy.deaths)
    else
        L[#L + 1] = "legacyTracker=INACTIVE (paridad de fuerzas/bosses solo con llave en curso)"
    end
    return L
end

function TA:ReportLines()
    local L = { "=== MitzuMPlus [DEV] TrackerAdapter v" .. TA.VERSION .. " ===" }
    local okB, version, build, _, interface = pcall(rawget(_G, "GetBuildInfo") or function() end)
    L[#L + 1] = string.format("addon=%s client=%s build=%s interface=%s",
        text(MitzuMPlus.VERSION), text(okB and version or nil), text(okB and build or nil),
        text(okB and interface or nil))

    local s = self:GetSnapshot()
    local available, firstMissing = self:IsAvailable()
    L[#L + 1] = ""
    L[#L + 1] = "[SNAPSHOT]"
    L[#L + 1] = "available=" .. text(available) .. (firstMissing and (" missing=" .. firstMissing) or "")
    L[#L + 1] = "challengeActive=" .. text(s.active)
    L[#L + 1] = string.format("mapID=%s map=%s keystoneLevel=%s affixes=%d charged=%s",
        text(s.mapID), text(s.mapName), text(s.keystoneLevel), #(s.affixIDs or {}), text(s.charged))
    L[#L + 1] = string.format("elapsed=%s (%s) timeLimit=%s (%s) remaining=%s timer=%s/%s",
        text(s.elapsed), fmtTime(s.elapsed), text(s.timeLimit), fmtTime(s.timeLimit),
        fmtTime(s.timeRemaining), text(s.timerSource), text(s.timerID))
    L[#L + 1] = string.format("deaths=%s timeLost=%s", text(s.deaths), text(s.deathTimeLost))
    L[#L + 1] = string.format("scenarioType=%s isChallengeMode=%s",
        text(s.scenarioType), text(s.scenarioIsChallengeMode))
    L[#L + 1] = string.format("criteria=%s source=%s partial=%s weighted=%s",
        text(s.criteriaCount), text(s.criteriaSource), text(s.criteriaPartial), text(s.weightedCriteria))
    L[#L + 1] = string.format("forces=%s/%s %s remaining=%s (%s) source=%s quantity=%s",
        text(s.forcesCurrent), text(s.forcesTotal), fmtPct(s.forcesPercent),
        text(s.forcesRemaining), fmtPct(s.forcesRemainingPercent), text(s.forcesSource),
        text(s.forcesQuantityPercent))
    L[#L + 1] = string.format("bosses=%s/%s", text(s.bossesCompleted), text(s.bossesTotal))
    for _, b in ipairs(s.bosses or {}) do
        L[#L + 1] = string.format("  boss[%s] %s completed=%s", text(b.index), text(b.name), text(b.completed))
    end
    L[#L + 1] = "warnings=" .. ((#s.warnings > 0) and table.concat(s.warnings, ",") or "none")

    L[#L + 1] = ""
    L[#L + 1] = "[CRITERIA RAW]"
    local list = self:GetCriteria()
    if not list then
        L[#L + 1] = "none (sin escenario legible: normal fuera de una llave)"
    else
        for _, c in ipairs(list.criteria) do
            L[#L + 1] = string.format("[%d] kind=%s completed=%s qty=%s total=%s qs=%s secret=%s src=%s",
                c.index, text(c.kind), text(c.completed), text(c.quantity), text(c.totalQuantity),
                text(c.quantityString), (#c.secret > 0) and table.concat(c.secret, "+") or "none",
                text(c.source))
        end
        if list.missing > 0 then L[#L + 1] = "unreadableCriteria=" .. list.missing end
    end

    L[#L + 1] = ""
    L[#L + 1] = "[PARITY vs 1.0]"
    for _, line in ipairs(self:ParityLines(s)) do L[#L + 1] = line end

    L[#L + 1] = ""
    L[#L + 1] = "[CAPABILITIES]"
    local caps = self:ProbeCapabilities()
    for _, c in ipairs(caps) do
        L[#L + 1] = string.format("%s %s (%s%s%s) lastCall=%s calls=%d errors=%d%s",
            c.status, c.path, c.kind, c.required and ",required" or "",
            c.fallbackFor and (",legacyFallbackFor=" .. c.fallbackFor) or "", text(c.lastCall),
            c.calls, c.errors, c.lastError and (" lastError=" .. c.lastError) or "")
    end
    local m = self:MissingCapabilities(caps)
    L[#L + 1] = "requiredMissing=" .. listOrNone(m.required)
    L[#L + 1] = "optionalMissing=" .. listOrNone(m.optional)
    L[#L + 1] = "legacyFallbacksAbsent=" .. m.legacyAbsent .. " (redes heredadas no necesarias: su API principal existe)"
    L[#L + 1] = "=== END ==="
    return L
end

-- Campos compactos para la seccion del Bug Report.
function TA:DiagnosticFields()
    local s = self:GetSnapshot()
    local caps = self:ProbeCapabilities()
    return {
        { "adapterVersion", TA.VERSION },
        { "available", (self:IsAvailable()) },
        { "challengeActive", s.active },
        { "mapID", s.mapID },
        { "keystoneLevel", s.keystoneLevel },
        { "elapsed", s.elapsed },
        { "timeLimit", s.timeLimit },
        { "timerSource", s.timerSource },
        { "forcesCurrent", s.forcesCurrent },
        { "forcesTotal", s.forcesTotal },
        { "forcesPercent", s.forcesPercent and string.format("%.2f", s.forcesPercent) or nil },
        { "forcesSource", s.forcesSource },
        { "bossesCompleted", s.bossesCompleted },
        { "bossesTotal", s.bossesTotal },
        { "criteriaSource", s.criteriaSource },
        { "warnings", (#s.warnings > 0) and table.concat(s.warnings, ",") or "none" },
        { "requiredMissing", listOrNone(self:MissingCapabilities(caps).required) },
        { "optionalMissing", listOrNone(self:MissingCapabilities(caps).optional) },
    }
end

-- ---------------------------------------------------------------------------
-- CAJA NEGRA
--
-- Sin eventos de Blizzard: se escucha el bus interno, que ya emite las
-- transiciones decididas por DungeonContext. Una entrada de capacidades por
-- firma distinta y una foto compacta al empezar y al terminar cada llave.
-- ---------------------------------------------------------------------------

function TA:RecordLifecycle(label)
    self:LogCapabilities(label)
    local FR = MitzuMPlus.FlightRecorder
    if not (FR and FR.Record) then return end
    local s = self:GetSnapshot()
    FR:Record("TRACKER", "ADAPTER_" .. tostring(label), {
        active = s.active, map = s.mapID, level = s.keystoneLevel,
        elapsed = s.elapsed and math.floor(s.elapsed) or nil, limit = s.timeLimit,
        forces = s.forcesPercent and string.format("%.1f", s.forcesPercent) or nil,
        total = s.forcesTotal, bosses = s.bossesTotal and (tostring(s.bossesCompleted) .. "/" .. tostring(s.bossesTotal)) or nil,
        criteria = s.criteriaSource, warn = (#s.warnings > 0) and table.concat(s.warnings, ",") or nil,
    })
end

local bus = MitzuMPlus.EventBus
if bus and bus.On then
    bus:On("MITZU_PRE_KEY", function() TA:LogCapabilities("PRE_KEY") end)
    bus:On("MITZU_KEY_STARTED", function() TA:RecordLifecycle("START") end)
    bus:On("MITZU_KEY_COMPLETED", function() TA:RecordLifecycle("COMPLETED") end)
end

return TA
