-- MitzuMPlus (core): contrato de MitzuMPlusAPI, la API publica de SOLO LECTURA.
-- No se carga desde el TOC. Ejecutar con: python tests/run_lua_tests.py
--
-- Se prueba contra el core REAL cargado por su .toc, con una llave en marcha:
--   · no se puede escribir en la API ni reemplazar sus funciones por la via normal
--   · ninguna funcion escribe: no hay setters
--   · las tablas que devuelve son copias: mutarlas no cambia el core
--   · los eventos llegan con escalares, despues del core, y un consumidor que
--     falla no rompe al core ni aparece como error del core

local assertions, tests, failures = 0, 0, {}

local function equal(actual, expected, label)
    assertions = assertions + 1
    if actual ~= expected then
        error(string.format("%s: esperado %s, recibido %s",
            label or "equal", tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(value, label)
    equal(not not value, true, label)
end

local function test(name, fn)
    tests = tests + 1
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end

local S = dofile("tests/harness/core_scenario.lua")

local env = S.boot({ withRouteArrows = false })
S.enterRubyAndStartKey(env)
assert(#env.errors == 0, "el escenario base arranca sin errores: " .. tostring(env.errors[1]))

local API = _G.MitzuMPlusAPI
local MP = rawget(_G, "MitzuMPlus")
local RP = MP.RouteProgress

-- Lo que el contrato permite. Si se anade una funcion, se anade aqui a
-- conciencia; el test T2 falla con cualquier nombre nuevo no revisado.
local PERMITIDAS = {
    GetAPIVersion = true, GetVersion = true, IsReady = true,
    IsChallengeActive = true, GetDungeonState = true, GetCurrentDungeonKey = true,
    GetChallengeMapID = true, GetKeystoneLevel = true, GetDungeonName = true,
    GetChallengeElapsed = true, GetChallengeStartedAt = true,
    GetRouteRevision = true, GetCurrentRouteID = true, GetCurrentRoute = true,
    GetActiveRoute = true, GetCurrentPull = true, GetPullCount = true,
    GetRouteState = true, GetCurrentPullData = true, GetPullData = true,
    GetRouteProgress = true, GetNavigatorPull = true, GetNavigatorPullCount = true,
    GetAdaptiveRouteRevision = true, GetAdaptiveRouteIndex = true,
    GetAdaptiveEnemiesOf = true, GetProfileContext = true,
    GetEnemySnapshot = true, GetEnemySnapshotRevision = true,
    GetNativeRouteKeys = true, GetNativeRoutesForDungeon = true,
    GetPlayerRole = true, GetPlayerSpec = true,
    GetEvents = true, RegisterCallback = true, UnregisterCallback = true,
}

-- Nombres de la API: se leen por el __index del proxy, no se puede iterar el
-- proxy (esta vacio a proposito). Se recogen del fichero fuente.
local function nombresDeLaAPI()
    local f = assert(io.open("MitzuMPlus/API/PublicAPI.lua", "rb"))
    local src = f:read("*a")
    f:close()
    local out = {}
    for nombre in src:gmatch("\nfunction API%.([%w_]+)%s*%(") do out[#out + 1] = nombre end
    return out
end

test("T1 el proxy no deja escribir ni ver su metatabla", function()
    local ok, err = pcall(function() API.GetCurrentPull = function() return 99 end end)
    equal(ok, false, "asignar una funcion falla")
    truthy(tostring(err):find("solo lectura", 1, true), "mensaje claro: " .. tostring(err))
    ok = pcall(function() API.Nuevo = 1 end)
    equal(ok, false, "anadir un campo falla")
    equal(getmetatable(API), false, "metatabla protegida")
    ok = pcall(setmetatable, API, {})
    equal(ok, false, "no se puede cambiar la metatabla")
    equal(API.GetCurrentPull(), 1, "la funcion original sigue ahi")
    equal(next(API), nil, "el proxy no guarda nada propio")
end)

test("T2 todas las funciones son lecturas: ni una escribe", function()
    local nombres = nombresDeLaAPI()
    truthy(#nombres >= 30, "funciones encontradas: " .. #nombres)
    for _, nombre in ipairs(nombres) do
        truthy(PERMITIDAS[nombre], "funcion no revisada en el contrato: " .. nombre)
        equal(type(API[nombre]), "function", "expuesta: " .. nombre)
        local escritor = nombre:match("^Set") or nombre:match("^Next") or nombre:match("^Prev")
            or nombre:match("Reset") or nombre:match("^Restore") or nombre:match("^Start")
            or nombre:match("^Stop") or nombre:match("^Complete") or nombre:match("^Clear")
            or nombre:match("^Import") or nombre:match("^Load") or nombre:match("^Write")
        equal(escritor, nil, "nombre de escritura en la API: " .. nombre)
    end
    for nombre in pairs(PERMITIDAS) do
        equal(type(API[nombre]), "function", "contrato completo: " .. nombre)
    end
end)

test("T3 llamar a TODAS las funciones de lectura no cambia el estado del core", function()
    local antes = { RP:GetPullIndex(), RP:GetState(), RP:GetRoute(),
                    MP.AdaptiveRoute.PullNavigator:GetCurrentPull(), S.coreSavedVariables() }
    for _, nombre in ipairs(nombresDeLaAPI()) do
        if nombre ~= "RegisterCallback" and nombre ~= "UnregisterCallback" then
            local ok = pcall(API[nombre], 1)
            equal(ok, true, "no lanza: " .. nombre)
        end
    end
    equal(RP:GetPullIndex(), antes[1], "pull")
    equal(RP:GetState(), antes[2], "estado de la ruta")
    equal(RP:GetRoute(), antes[3], "misma ruta (identidad)")
    equal(MP.AdaptiveRoute.PullNavigator:GetCurrentPull(), antes[4], "navegador")
    equal(S.coreSavedVariables(), antes[5], "SavedVariables intactas")
end)

test("T4 las tablas son copias sin metatabla ni funciones", function()
    local ruta = API.GetCurrentRoute()
    truthy(type(ruta) == "table", "ruta")
    truthy(ruta ~= RP:GetRoute(), "no es la tabla interna")
    equal(getmetatable(ruta), nil, "sin metatabla")
    local pullsOriginales = #RP:GetRoute().pulls
    ruta.pulls[1] = nil
    ruta.id = "otra"
    table.insert(ruta.pulls, { enemies = {} })
    equal(RP:GetRoute().id, "mitzu_399_standard", "id interno intacto")
    equal(#RP:GetRoute().pulls, pullsOriginales, "pulls internos intactos")
    truthy(API.GetCurrentRoute().pulls[1], "una copia nueva vuelve entera")

    local prog = API.GetRouteProgress()
    prog.pull = 7
    prog.state = "COMPLETED"
    equal(RP:GetPullIndex(), 1, "cambiar la vista de progreso no mueve el pull")
    equal(RP:GetState(), "ACTIVE", "ni el estado")

    local pull = API.GetCurrentPullData()
    truthy(type(pull) == "table" and pull ~= RP:GetCurrentPull(), "pull copiado")
    local function sinFunciones(t, visto)
        visto = visto or {}
        if visto[t] then return end
        visto[t] = true
        for k, v in pairs(t) do
            if type(v) == "function" or type(k) == "function" then error("funcion en la copia: " .. tostring(k)) end
            if type(v) == "table" then
                if getmetatable(v) ~= nil then error("metatabla en la copia: " .. tostring(k)) end
                sinFunciones(v, visto)
            end
        end
    end
    sinFunciones(pull)
    sinFunciones(API.GetAdaptiveRouteIndex() or {})
    sinFunciones(API.GetProfileContext() or {})
    sinFunciones(API.GetNativeRoutesForDungeon("399") or {})
    assertions = assertions + 4

    local idx = API.GetCurrentRoute().mdtDungeonIdx
    local enemigos = API.GetEnemySnapshot(idx)
    truthy(type(enemigos) == "table" and next(enemigos) ~= nil, "foto de enemigos de la mazmorra " .. tostring(idx))
    local k = next(enemigos)
    enemigos[k] = nil
    truthy(API.GetEnemySnapshot(idx)[k] ~= nil, "vaciar la copia no vacia la foto del core")
end)

test("T5 no hay camino desde la API a un modulo del core", function()
    local function buscarModulos(v, visto)
        if type(v) ~= "table" then return end
        visto = visto or {}
        if visto[v] then return end
        visto[v] = true
        if v == MP or v == RP or v == MP.AdaptiveRoute or v == MP.EventBus
            or v == MP.DungeonContext or v == MP.RouteManager then
            error("la API entrega un modulo interno")
        end
        for _, x in pairs(v) do buscarModulos(x, visto) end
    end
    for _, nombre in ipairs(nombresDeLaAPI()) do
        if nombre ~= "RegisterCallback" and nombre ~= "UnregisterCallback" then
            local r = { pcall(API[nombre], "399") }
            buscarModulos(r)
            r = { pcall(API[nombre], 1) }
            buscarModulos(r)
            assertions = assertions + 1
        end
    end
end)

test("T6 los eventos llegan saneados y despues del core", function()
    local recibido, orden = {}, {}
    local bus = MP.EventBus
    -- Un manejador interno con la prioridad mas baja del core (10).
    bus:On("MITZU_PULL_CHANGED", function() orden[#orden + 1] = "core" end, 10)
    local id = API.RegisterCallback("PULL_CHANGED", function(...)
        orden[#orden + 1] = "api"
        recibido = { n = select("#", ...), ... }
        -- Lo que el consumidor lee ya es el estado consolidado.
        recibido.visto = API.GetCurrentPull()
    end, 100)
    truthy(id, "suscripcion aceptada")
    RP:NextPull("MANUAL")
    equal(orden[1], "core", "primero el core")
    equal(orden[#orden], "api", "el consumidor al final, aun con prioridad 100")
    equal(recibido[1], 2, "pull nuevo")
    equal(recibido[2], 1, "pull anterior")
    for i = 1, recibido.n do
        local t = type(recibido[i])
        truthy(t == "number" or t == "string" or t == "boolean" or t == "nil",
            "argumento " .. i .. " es escalar (" .. t .. ")")
    end
    equal(recibido.visto, 2, "la lectura en el callback ve el pull nuevo")
    equal(API.UnregisterCallback(id), true, "baja")
    local n = #orden
    RP:PreviousPull("MANUAL")
    equal(orden[#orden], "core", "tras la baja el consumidor ya no se entera")
    truthy(#orden == n + 1, "solo el core")

    local _, motivo = API.RegisterCallback("NO_EXISTE", function() end)
    truthy(motivo, "evento desconocido rechazado")
    local nil1 = API.RegisterCallback("PULL_CHANGED", "no es funcion")
    equal(nil1, nil, "sin funcion rechazado")
end)

test("T7 un consumidor que falla no rompe el core ni se reporta como error del core", function()
    local id = API.RegisterCallback("PULL_CHANGED", function() error("fallo del consumidor") end)
    local idNav = API.RegisterCallback("NAVIGATOR_PULL_CHANGED", function() error("fallo del consumidor") end)
    local impresos = #env.WoW.printed
    local okMover = pcall(RP.NextPull, RP, "MANUAL")
    equal(okMover, true, "el core mueve el pull")
    equal(RP:GetPullIndex(), 2, "pull movido")
    local PN = MP.AdaptiveRoute.PullNavigator
    local navAntes = PN:GetCurrentPull()
    local okNav = pcall(PN.NextPull, PN)
    equal(okNav, true, "el navegador sigue funcionando")
    truthy(PN:GetCurrentPull() ~= navAntes or PN:GetPullCount() <= 1, "y avanza")
    PN:PreviousPull()
    equal(PN:GetCurrentPull(), navAntes, "navegador restaurado")
    local texto = table.concat(env.WoW.printed, "\n", impresos + 1)
    equal(texto:find("EventBus Error", 1, true), nil, "no aparece como error de MitzuMPlus")
    API.UnregisterCallback(id)
    API.UnregisterCallback(idNav)
    RP:PreviousPull("MANUAL")
    equal(RP:GetPullIndex(), 1, "estado restaurado")
end)

test("T8 la lista de eventos es cerrada y documentada", function()
    local eventos = API.GetEvents()
    local esperados = { "DUNGEON_STATE_CHANGED", "KEY_COMPLETED", "KEY_RESET", "KEY_STARTED",
                        "NAVIGATOR_PULL_CHANGED", "PULL_CHANGED", "ROUTE_RECOVERED",
                        "ROUTE_STARTED", "ROUTE_UNLOADED", "RUN_TEARDOWN" }
    equal(#eventos, #esperados, "numero de eventos")
    for i, e in ipairs(esperados) do equal(eventos[i], e, "evento " .. i) end
    eventos[1] = "X"
    equal(API.GetEvents()[1], "DUNGEON_STATE_CHANGED", "la lista tambien es copia")
end)

test("T9 la revision de ruta cambia solo cuando cambia la ruta", function()
    local r1 = API.GetRouteRevision()
    equal(API.GetRouteRevision(), r1, "estable sin cambios")
    RP:NextPull("MANUAL")
    equal(API.GetRouteRevision(), r1, "mover el pull no es otra ruta")
    RP:PreviousPull("MANUAL")
    truthy(type(r1) == "number", "numerica")
end)

test("T10 rol y especializacion del jugador", function()
    local rol = API.GetPlayerRole()
    truthy(rol == nil or type(rol) == "string", "rol escalar")
    local specID, nombre = API.GetPlayerSpec()
    truthy(specID == nil or type(specID) == "number", "specID numerico")
    truthy(nombre == nil or type(nombre) == "string", "nombre escalar")
end)

equal(#env.WoW.errors, 0, "sin errores de ejecucion en todo el banco")

if #failures > 0 then
    error(string.format("PublicAPI: %d tests, %d assertions, %d failures\n%s",
        tests, assertions, #failures, table.concat(failures, "\n")), 0)
end

return { tests = tests, assertions = assertions }
