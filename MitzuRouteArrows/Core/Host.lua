-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuRouteArrows · Core/Host  —  FACHADA DE SOLO LECTURA SOBRE MitzuMPlusAPI
--
-- Los módulos de flechas, evidencias y alignment se escribieron cuando vivían
-- DENTRO de MitzuMPlus, y leían cosas como RouteProgress:GetPullIndex() o
-- DungeonContext:GetState(). Reescribir su lógica para la separación habría
-- puesto en riesgo cientos de comprobaciones que ya la validan.
--
-- En su lugar, esta fachada ofrece a esos módulos objetos con los MISMOS
-- nombres de método, pero construidos sobre MitzuMPlusAPI:
--
--   Host.RouteProgress:GetPullIndex()   ->  MitzuMPlusAPI.GetCurrentPull()
--   Host.DungeonContext:GetState()      ->  MitzuMPlusAPI.GetDungeonState()
--   Host.EventBus:On("MITZU_PULL_CHANGED", fn)  ->  RegisterCallback("PULL_CHANGED", fn)
--
-- LA REGLA: aquí solo existen LECTORES. No hay Host.RouteProgress:SetPull, ni
-- NextPull, ni RestorePull, ni nada que escriba. Si un módulo intentara
-- llamar a uno, recibiría nil y fallaría en el acto, que es lo correcto.
--
-- Este es el ÚNICO fichero del addon, junto a Core/Bootstrap, que habla con
-- MitzuMPlusAPI. Ninguno nombra a `MitzuMPlus`; hay una comprobación estática
-- que lo verifica.
-- ═══════════════════════════════════════════════════════════════════════════

local MRA = _G.MitzuRouteArrows
if not MRA then return end

local Host = {}
MRA.Host = Host

local function api()
    local a = MRA:GetAPI()
    return a
end

-- Llama a una función de la API. Error, API ausente o incompatible: nil.
local function llamar(nombre, ...)
    local a = api()
    if not a then return nil end
    local okF, fn = pcall(function() return a[nombre] end)
    if not okF or type(fn) ~= "function" then return nil end
    local ok, x, y, z = pcall(fn, ...)
    if not ok then return nil end
    return x, y, z
end
Host._call = llamar

-- ─────────────────────────────────────────────────────────────────────────
-- CACHÉS
--
-- La API devuelve COPIAS, y copiar una ruta entera en cada tick de 0,4 s, o
-- el índice de clones en cada placa evaluada, sería gasto por nada. Se guarda
-- una copia y se renueva solo cuando cambia lo que la identifica.
--
-- Las copias son de este addon: aunque un módulo escribiera en ellas, el core
-- no se entera. Pero son COMPARTIDAS entre todos los módulos de este addon:
-- escribir en una estropea lo que leen los demás hasta la siguiente
-- revisión. Regla: lo que devuelve Host se trata como solo lectura.
-- ─────────────────────────────────────────────────────────────────────────

local cache = {
    routeRev = nil, route = nil,
    activeID = nil, active = nil,
    indexRev = nil, index = nil,
    enemies = {},      -- [mdtDungeonIdx] = { rev = n, data = copia }
    native = nil,      -- { keys = {...}, byKey = { [key] = { rutas } } }
}

function Host:InvalidateRoute()
    cache.routeRev, cache.route = nil, nil
    cache.activeID, cache.active = nil, nil
end

-- La copia se renueva cuando la API dice que la tabla de ruta del core ha
-- cambiado (GetRouteRevision), no por el id: una ruta reimportada puede
-- conservar el id y traer otros pulls.
local function rutaEnCurso()
    local rev = llamar("GetRouteRevision")
    if rev == nil then
        cache.routeRev, cache.route = nil, nil
        return nil
    end
    if rev ~= cache.routeRev then
        cache.route = llamar("GetCurrentRoute")
        cache.routeRev = rev
    end
    return cache.route
end

-- ─────────────────────────────────────────────────────────────────────────
-- RouteProgress (solo lectores)
-- ─────────────────────────────────────────────────────────────────────────

Host.RouteProgress = {
    GetRoute     = function() return rutaEnCurso() end,
    GetPullIndex = function() return llamar("GetCurrentPull") end,
    GetPullCount = function() return llamar("GetPullCount") or 0 end,
    GetState     = function() return llamar("GetRouteState") end,
    -- Del core, tal cual lo sirve RouteProgress:GetCurrentPull. Si la ruta en
    -- caché ya tiene ese pull se reutiliza; si no, se pide a la API.
    GetCurrentPull = function()
        local r = rutaEnCurso()
        local i = llamar("GetCurrentPull")
        if type(r) == "table" and type(r.pulls) == "table" and i and r.pulls[i] then
            return r.pulls[i]
        end
        return llamar("GetCurrentPullData")
    end,
}

Host.RouteManager = {
    GetActiveRoute = function()
        local r = rutaEnCurso()
        if r then return r end
        return llamar("GetActiveRoute")
    end,
}

-- ─────────────────────────────────────────────────────────────────────────
-- DungeonContext y ChallengeClock
-- ─────────────────────────────────────────────────────────────────────────

Host.DungeonContext = {
    GetState          = function() return llamar("GetDungeonState") end,
    IsChallengeActive = function() return llamar("IsChallengeActive") == true end,
    GetDungeonKey     = function() return llamar("GetCurrentDungeonKey") end,
    GetChallengeMapID = function() return llamar("GetChallengeMapID") end,
    GetKeystoneLevel  = function() return llamar("GetKeystoneLevel") end,
    GetDungeonName    = function() return llamar("GetDungeonName") end,
}

Host.ChallengeClock = {
    GetElapsed   = function() return llamar("GetChallengeElapsed") end,
    GetStartedAt = function() return llamar("GetChallengeStartedAt") end,
}

-- ─────────────────────────────────────────────────────────────────────────
-- Vista legada de la ruta adaptativa (DataStructure / PullNavigator)
-- ─────────────────────────────────────────────────────────────────────────

local function indice()
    local rev = llamar("GetAdaptiveRouteRevision")
    if rev == nil then
        cache.indexRev, cache.index = nil, nil
        return nil
    end
    if rev ~= cache.indexRev then
        cache.index = llamar("GetAdaptiveRouteIndex")
        cache.indexRev = rev
    end
    return cache.index
end

Host.DataStructure = {
    Get = function() return indice() end,
    EnemiesOf = function(_, pullIndex)
        local idx = indice()
        local n = tonumber(pullIndex)
        if type(idx) ~= "table" or type(idx.pulls) ~= "table" or not n then return nil end
        local p = idx.pulls[n]
        return type(p) == "table" and p.enemies or nil
    end,
}

Host.PullNavigator = {
    GetCurrentPull = function() return llamar("GetNavigatorPull") end,
    GetPullCount   = function() return llamar("GetNavigatorPullCount") or 0 end,
}

Host.ProfileManager = {
    GetContext = function() return llamar("GetProfileContext") end,
}

-- MDTEnemyData[dungeonIdx], como antes, pero cada entrada es una copia que se
-- pide a la API y se renueva solo si la API dice que esos datos cambiaron.
Host.MDTEnemyData = setmetatable({}, {
    __index = function(_, k)
        local n = tonumber(k)
        if not n then return nil end
        local rev = llamar("GetEnemySnapshotRevision", n)
        if rev == nil then return nil end
        local c = cache.enemies[n]
        if not c or c.rev ~= rev then
            c = { rev = rev, data = llamar("GetEnemySnapshot", n) }
            cache.enemies[n] = c
        end
        return c.data
    end,
    __newindex = function() end,
})

-- Rutas nativas empaquetadas, para los diagnósticos de cobertura.
local function nativas()
    if cache.native then return cache.native end
    local keys = llamar("GetNativeRouteKeys")
    if type(keys) ~= "table" then return nil end
    cache.native = { keys = keys, byKey = {} }
    return cache.native
end

Host.NativeRouteDB = {
    AllKeys = function()
        local n = nativas()
        return n and n.keys or {}
    end,
    GetForDungeon = function(_, key)
        local n = nativas()
        if not n then return {} end
        if n.byKey[key] == nil then
            n.byKey[key] = llamar("GetNativeRoutesForDungeon", key) or {}
        end
        return n.byKey[key]
    end,
}

-- ─────────────────────────────────────────────────────────────────────────
-- EventBus: los nombres internos que usaban los módulos, traducidos a los
-- eventos públicos de la API. Solo existe On: escuchar, nunca emitir.
-- ─────────────────────────────────────────────────────────────────────────

local TRADUCCION = {
    MITZU_KEY_STARTED           = "KEY_STARTED",
    MITZU_KEY_COMPLETED         = "KEY_COMPLETED",
    MITZU_KEY_RESET             = "KEY_RESET",
    MITZU_DUNGEON_STATE_CHANGED = "DUNGEON_STATE_CHANGED",
    MITZU_ROUTE_STARTED         = "ROUTE_STARTED",
    MITZU_ROUTE_UNLOADED        = "ROUTE_UNLOADED",
    MITZU_ROUTE_RECOVERED       = "ROUTE_RECOVERED",
    MITZU_PULL_CHANGED          = "PULL_CHANGED",
    RUN_TEARDOWN                = "RUN_TEARDOWN",
}
Host.EVENT_TRANSLATION = TRADUCCION

-- Suscripciones pedidas. Si al pedirlas la API aún no está (o falta), se
-- quedan aquí y se registran en Host:Attach, al hacer login.
local pendientes, registradas = {}, {}

local function registrar(s)
    if registradas[s] then return true end
    local id = llamar("RegisterCallback", s.publico, s.fn, s.priority)
    if id then
        registradas[s] = id
        return true
    end
    return false
end

Host.EventBus = {
    On = function(_, evento, fn, priority)
        local publico = TRADUCCION[evento] or evento
        if type(fn) ~= "function" then return end
        local s = { publico = publico, fn = fn, priority = priority }
        pendientes[#pendientes + 1] = s
        registrar(s)
    end,
}

-- La ruta en caché se tira cada vez que la ruta del core cambia de estado.
local function invalidar() Host:InvalidateRoute() end
for _, ev in ipairs({ "MITZU_ROUTE_STARTED", "MITZU_ROUTE_UNLOADED",
                      "MITZU_ROUTE_RECOVERED", "MITZU_KEY_STARTED" }) do
    Host.EventBus:On(ev, invalidar, 100)
end

-- Registra lo que quedara pendiente. Idempotente.
function Host:Attach()
    local n = 0
    for _, s in ipairs(pendientes) do
        if registrar(s) then n = n + 1 end
    end
    return n
end

function Host:PendingCount()
    local n = 0
    for _, s in ipairs(pendientes) do
        if not registradas[s] then n = n + 1 end
    end
    return n
end

return Host
