-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · API pública de SOLO LECTURA  (MitzuMPlusAPI)
--
-- La única puerta por la que otro addon (hoy: MitzuRouteArrows) puede leer el
-- estado de MitzuMPlus. Pequeña a propósito: expone lo que un consumidor
-- necesita de verdad, y nada que le permita cambiar nada.
--
-- CONTRATO
--   · Todas las funciones son GETTERS. No hay ni una que escriba.
--   · Las tablas se devuelven como COPIAS profundas, sin metatablas. Mutar lo
--     que se recibe no toca el estado del core.
--   · Los eventos son notificaciones de una lista cerrada. A quien escucha le
--     llegan solo números, strings y booleanos: nunca un módulo interno. Los
--     eventos internos pasan objetos como RouteProgress o DungeonContext (con
--     sus SetPull y compañía); aquí eso se filtra.
--   · Quien escucha va SIEMPRE después de los manejadores del propio core, así
--     que cualquier lectura que haga ya ve el estado consolidado.
--   · Si el core no está listo o algo falla, se devuelve nil. Nunca se lanza
--     un error hacia el consumidor.
--
-- LO QUE ESTA API NO ES
-- Una barrera de seguridad entre addons. En WoW todos los addons comparten el
-- mismo entorno Lua y `_G.MitzuMPlus` sigue siendo alcanzable. La garantía de
-- que MitzuRouteArrows no escribe estado del core se sostiene en dos cosas: que
-- esta API no ofrece ninguna forma de hacerlo, y una comprobación estática que
-- verifica que MitzuRouteArrows no nombra `MitzuMPlus` en ningún sitio.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME, true)
if not MitzuMPlus then return end

-- Versión del CONTRATO, no del addon. Sube solo si cambia la forma de la API.
local API_VERSION = 1

local API = {}

-- ─────────────────────────────────────────────────────────────────────────
-- AYUDANTES
-- ─────────────────────────────────────────────────────────────────────────

-- Copia profunda de datos. Sin funciones, sin userdata, sin metatablas y a
-- prueba de ciclos: lo que sale de aquí no conserva ningún camino de vuelta
-- al estado del core.
local function copiar(v, vistos)
    if type(v) ~= "table" then
        local t = type(v)
        if t == "string" or t == "number" or t == "boolean" then return v end
        return nil
    end
    vistos = vistos or {}
    if vistos[v] then return vistos[v] end
    local out = {}
    vistos[v] = out
    for k, val in pairs(v) do
        local tk = type(k)
        if tk == "string" or tk == "number" or tk == "boolean" then
            local c = copiar(val, vistos)
            if c ~= nil then out[k] = c end
        end
    end
    return out
end

local function escalar(v)
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
    return nil
end

-- Llama a un método del core protegido. Cualquier error se traga y da nil:
-- un consumidor mal escrito no puede tumbar el core, ni al revés.
local function leer(obj, metodo, ...)
    if type(obj) ~= "table" then return nil end
    local fn = obj[metodo]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, obj, ...)
    if not ok then return nil end
    return a, b, c
end

local function modulo(nombre)  return rawget(MitzuMPlus, nombre) end
local function adaptativo(nombre)
    local AR = rawget(MitzuMPlus, "AdaptiveRoute")
    return type(AR) == "table" and rawget(AR, nombre) or nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- IDENTIDAD Y DISPONIBILIDAD
-- ─────────────────────────────────────────────────────────────────────────

function API.GetAPIVersion() return API_VERSION end

function API.GetVersion()
    return escalar(rawget(MitzuMPlus, "VERSION"))
end

-- Listo = la base de datos ya existe (OnInitialize ha corrido).
function API.IsReady()
    return type(rawget(MitzuMPlus, "db")) == "table"
end

-- ─────────────────────────────────────────────────────────────────────────
-- MAZMORRA Y LLAVE
-- ─────────────────────────────────────────────────────────────────────────

function API.IsChallengeActive()
    return leer(modulo("DungeonContext"), "IsChallengeActive") == true
end

-- OUTSIDE / IN_UNSUPPORTED_DUNGEON / PRE_KEY / RUNNING / COMPLETED / RESET
function API.GetDungeonState()
    return escalar((leer(modulo("DungeonContext"), "GetState")))
end

function API.GetCurrentDungeonKey()
    return escalar((leer(modulo("DungeonContext"), "GetDungeonKey")))
end

function API.GetChallengeMapID()
    return escalar((leer(modulo("DungeonContext"), "GetChallengeMapID")))
end

function API.GetKeystoneLevel()
    return escalar((leer(modulo("DungeonContext"), "GetKeystoneLevel")))
end

function API.GetDungeonName()
    return escalar((leer(modulo("DungeonContext"), "GetDungeonName")))
end

-- Segundos de llave según el servidor (ChallengeClock). nil fuera de la llave.
function API.GetChallengeElapsed()
    return escalar((leer(modulo("ChallengeClock"), "GetElapsed")))
end

-- Epoch (time()) en que arrancó la llave, según el servidor.
function API.GetChallengeStartedAt()
    return escalar((leer(modulo("ChallengeClock"), "GetStartedAt")))
end

-- ─────────────────────────────────────────────────────────────────────────
-- RUTA Y PROGRESO  (RouteProgress es la ÚNICA autoridad del pull)
-- ─────────────────────────────────────────────────────────────────────────

local ultimaRuta, revisionRuta = nil, 0
local function rutaActual()
    local r = leer(modulo("RouteProgress"), "GetRoute")
    if r ~= ultimaRuta then
        ultimaRuta = r
        revisionRuta = revisionRuta + 1
    end
    return r
end

-- Sube cada vez que RouteProgress pasa a tener OTRA tabla de ruta (incluida
-- una ruta distinta con el mismo id, o ninguna). Permite a un consumidor
-- guardar su copia y pedirla solo cuando cambie.
function API.GetRouteRevision()
    rutaActual()
    return revisionRuta
end

function API.GetCurrentRouteID()
    local r = rutaActual()
    return type(r) == "table" and escalar(r.id) or nil
end

-- Copia de la ruta en curso (MitzuRoute v1: pulls[].mobs[] con npcID,
-- enemyIdx, amount, cloneIDs...).
function API.GetCurrentRoute()
    local r = rutaActual()
    return type(r) == "table" and copiar(r) or nil
end

-- La ruta que RouteManager tiene cargada para la mazmorra (normalmente la
-- misma que la de RouteProgress).
function API.GetActiveRoute()
    local r = leer(modulo("RouteManager"), "GetActiveRoute")
    return type(r) == "table" and copiar(r) or nil
end

-- Índice del pull actual según RouteProgress.
function API.GetCurrentPull()
    return escalar((leer(modulo("RouteProgress"), "GetPullIndex")))
end

function API.GetPullCount()
    return escalar((leer(modulo("RouteProgress"), "GetPullCount")))
end

-- INACTIVE / PREPARED / ACTIVE / COMPLETED
function API.GetRouteState()
    return escalar((leer(modulo("RouteProgress"), "GetState")))
end

-- Copia del pull actual (la tabla con sus mobs).
function API.GetCurrentPullData()
    local p = leer(modulo("RouteProgress"), "GetCurrentPull")
    return type(p) == "table" and copiar(p) or nil
end

-- Copia de un pull concreto de la ruta en curso.
function API.GetPullData(index)
    local r, n = rutaActual(), tonumber(index)
    if type(r) ~= "table" or type(r.pulls) ~= "table" or not n then return nil end
    local p = r.pulls[n]
    return type(p) == "table" and copiar(p) or nil
end

-- Resumen en una tabla nueva. Escribir en ella no mueve nada.
function API.GetRouteProgress()
    local RP = modulo("RouteProgress")
    if type(RP) ~= "table" then return nil end
    return {
        routeID   = API.GetCurrentRouteID(),
        state     = API.GetRouteState(),
        pull      = API.GetCurrentPull(),
        pullCount = API.GetPullCount(),
        recovered = leer(RP, "WasRecovered") == true,
    }
end

-- ─────────────────────────────────────────────────────────────────────────
-- VISTA LEGADA DE LA RUTA ADAPTATIVA
--
-- Los resolutores de placas se escribieron contra el índice de DataStructure
-- (perfiles importados de MDT) y contra PullNavigator, que es el contador que
-- mueven las teclas de siguiente/anterior pull. Ese contador NO es siempre el
-- de RouteProgress: se sincroniza desde él, pero las teclas lo mueven sin
-- pasar por RouteProgress. Se expone tal cual, con otro nombre, para que el
-- consumidor vea exactamente lo mismo que veía antes de la separación.
-- ─────────────────────────────────────────────────────────────────────────

function API.GetNavigatorPull()
    return escalar((leer(adaptativo("PullNavigator"), "GetCurrentPull")))
end

function API.GetNavigatorPullCount()
    return escalar((leer(adaptativo("PullNavigator"), "GetPullCount")))
end

local ultimoIndice, revision = nil, 0
local function indiceAdaptativo()
    local idx = leer(adaptativo("DataStructure"), "Get")
    if idx ~= ultimoIndice then
        ultimoIndice = idx
        revision = revision + 1
    end
    return idx
end

-- Sube cada vez que DataStructure reconstruye su índice. Sirve para que un
-- consumidor cachee su copia y solo la pida de nuevo cuando cambie.
function API.GetAdaptiveRouteRevision()
    indiceAdaptativo()
    return revision
end

function API.GetAdaptiveRouteIndex()
    local idx = indiceAdaptativo()
    return type(idx) == "table" and copiar(idx) or nil
end

function API.GetAdaptiveEnemiesOf(pullIndex)
    local e = leer(adaptativo("DataStructure"), "EnemiesOf", tonumber(pullIndex))
    return type(e) == "table" and copiar(e) or nil
end

function API.GetProfileContext()
    local ctx = leer(adaptativo("ProfileManager"), "GetContext")
    return type(ctx) == "table" and copiar(ctx) or nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- DATOS ESTÁTICOS DE ENEMIGOS  (data/MDTEnemyData.lua, empaquetado)
-- ─────────────────────────────────────────────────────────────────────────

local ultimosEnemigos, revisionEnemigos = {}, {}
local function enemigos(mdtDungeonIdx)
    local all = rawget(MitzuMPlus, "MDTEnemyData")
    local n = tonumber(mdtDungeonIdx)
    if type(all) ~= "table" or not n then return nil, n end
    local d = all[n]
    if d ~= ultimosEnemigos[n] then
        ultimosEnemigos[n] = d
        revisionEnemigos[n] = (revisionEnemigos[n] or 0) + 1
    end
    return d, n
end

function API.GetEnemySnapshot(mdtDungeonIdx)
    local d = enemigos(mdtDungeonIdx)
    return type(d) == "table" and copiar(d) or nil
end

-- Sube si la tabla de enemigos de esa mazmorra cambia. Son datos empaquetados
-- y en una sesion normal no cambian; la revision existe para que ningun
-- consumidor tenga que suponerlo.
function API.GetEnemySnapshotRevision(mdtDungeonIdx)
    local _, n = enemigos(mdtDungeonIdx)
    return n and (revisionEnemigos[n] or 0) or nil
end

-- Rutas nativas empaquetadas (data/Routes). Claves de mazmorra ordenadas.
function API.GetNativeRouteKeys()
    local db = rawget(MitzuMPlus, "NativeRouteDB")
    local keys = leer(db, "AllKeys")
    return type(keys) == "table" and copiar(keys) or nil
end

-- Copia de las rutas nativas de una mazmorra.
function API.GetNativeRoutesForDungeon(dungeonKey)
    local db = rawget(MitzuMPlus, "NativeRouteDB")
    local rutas = leer(db, "GetForDungeon", dungeonKey)
    return type(rutas) == "table" and copiar(rutas) or nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- JUGADOR
-- ─────────────────────────────────────────────────────────────────────────

local function rolYSpec()
    local fn = rawget(MitzuMPlus, "GetPlayerRoleAndSpec")
    if type(fn) ~= "function" then return nil end
    local ok, role, name, specID = pcall(fn)
    if not ok then return nil end
    return escalar(role), escalar(name), escalar(specID)
end

-- "TANK" / "HEALER" / "DAMAGER"
function API.GetPlayerRole()
    local role = rolYSpec()
    return role
end

-- specID, nombre de la spec
function API.GetPlayerSpec()
    local _, name, specID = rolYSpec()
    return specID, name
end

-- ─────────────────────────────────────────────────────────────────────────
-- EVENTOS  (lista cerrada, argumentos saneados)
--
-- Cada entrada dice de qué evento interno sale y QUÉ se entrega. La función
-- de argumentos recibe lo que emite el core y devuelve solo escalares.
-- ─────────────────────────────────────────────────────────────────────────

local function idDe(ruta) return type(ruta) == "table" and escalar(ruta.id) or nil end

local EVENTOS = {
    KEY_STARTED   = { interno = "MITZU_KEY_STARTED",   args = function() end },
    KEY_COMPLETED = { interno = "MITZU_KEY_COMPLETED", args = function() end },
    KEY_RESET     = { interno = "MITZU_KEY_RESET",     args = function() end },
    DUNGEON_STATE_CHANGED = { interno = "MITZU_DUNGEON_STATE_CHANGED",
        args = function(nuevo, anterior) return escalar(nuevo), escalar(anterior) end },
    ROUTE_STARTED = { interno = "MITZU_ROUTE_STARTED",
        args = function(ruta) return idDe(ruta) end },
    ROUTE_UNLOADED = { interno = "MITZU_ROUTE_UNLOADED",
        args = function(ruta) return idDe(ruta) end },
    ROUTE_RECOVERED = { interno = "MITZU_ROUTE_RECOVERED",
        args = function(routeID, pull) return escalar(routeID), escalar(pull) end },
    PULL_CHANGED = { interno = "MITZU_PULL_CHANGED",
        args = function(pull, anterior, motivo)
            return escalar(pull), escalar(anterior), escalar(motivo)
        end },
    RUN_TEARDOWN = { interno = "RUN_TEARDOWN",
        args = function(motivo) return escalar(motivo) end },
    -- No sale del bus: es el OnChange de PullNavigator (ver arriba).
    NAVIGATOR_PULL_CHANGED = { navegador = true,
        args = function(pull, total) return escalar(pull), escalar(total) end },
}

function API.GetEvents()
    local out = {}
    for nombre in pairs(EVENTOS) do out[#out + 1] = nombre end
    table.sort(out)
    return out
end

-- PullNavigator solo acepta listeners, no permite quitarlos. Se engancha UNA
-- vez un repartidor propio y las altas y bajas se gestionan aquí.
local oyentesNavegador, navegadorEnganchado = {}, false
local function engancharNavegador()
    if navegadorEnganchado then return end
    local PN = adaptativo("PullNavigator")
    if type(PN) ~= "table" or type(PN.OnChange) ~= "function" then return end
    navegadorEnganchado = true
    pcall(PN.OnChange, PN, function(pull, total)
        local a, b = EVENTOS.NAVIGATOR_PULL_CHANGED.args(pull, total)
        for _, h in ipairs(oyentesNavegador) do
            if h.activo then pcall(h.fn, a, b) end
        end
    end)
end

local suscripciones, siguienteId = {}, 0

-- Suscribe `fn` a un evento público. `priority` (0-100, por defecto 50) solo
-- ordena entre consumidores: todos van DESPUÉS de los manejadores del core.
-- Devuelve un identificador para UnregisterCallback, o nil y un motivo.
function API.RegisterCallback(evento, fn, priority)
    local def = EVENTOS[evento]
    if not def then return nil, "evento desconocido: " .. tostring(evento) end
    if type(fn) ~= "function" then return nil, "falta la función" end

    siguienteId = siguienteId + 1
    local h = { id = siguienteId, evento = evento, fn = fn, activo = true }

    if def.navegador then
        engancharNavegador()
        oyentesNavegador[#oyentesNavegador + 1] = h
    else
        local bus = modulo("EventBus")
        if type(bus) ~= "table" or type(bus.On) ~= "function" then
            return nil, "EventBus no disponible"
        end
        local p = tonumber(priority) or 50
        if p < 0 then p = 0 elseif p > 100 then p = 100 end
        -- El core usa prioridades enteras de 10 a 90. Entre 0 y 0,1 cualquier
        -- consumidor queda siempre por detrás de todos ellos.
        -- El error de un consumidor se queda en el consumidor: no llega al
        -- EventBus, que lo imprimiria como un fallo de MitzuMPlus.
        h.envoltorio = function(...)
            if not h.activo then return end
            pcall(fn, def.args(...))
        end
        bus:On(def.interno, h.envoltorio, p / 1000)
    end
    suscripciones[h.id] = h
    return h.id
end

function API.UnregisterCallback(id)
    local h = suscripciones[id]
    if not h then return false end
    h.activo = false
    suscripciones[id] = nil
    if h.envoltorio then
        local bus = modulo("EventBus")
        if type(bus) == "table" and type(bus.Off) == "function" then
            pcall(bus.Off, bus, EVENTOS[h.evento].interno, h.envoltorio)
        end
    else
        for i = #oyentesNavegador, 1, -1 do
            if oyentesNavegador[i] == h then table.remove(oyentesNavegador, i) end
        end
    end
    return true
end

-- ─────────────────────────────────────────────────────────────────────────
-- EXPORTACIÓN: una tabla vacía cuyo __index son estas funciones.
--
--  · Asignar un campo nuevo lanza error (__newindex).
--  · __metatable = false impide leer o sustituir la metatabla.
--  · Las funciones viven en un upvalue local: aunque alguien haga rawset sobre
--    el proxy, no puede reemplazar las del core ni tocar el estado.
-- ─────────────────────────────────────────────────────────────────────────

local proxy = setmetatable({}, {
    __index = API,
    __newindex = function()
        error("MitzuMPlusAPI es de solo lectura", 2)
    end,
    __metatable = false,
})

_G.MitzuMPlusAPI = proxy
