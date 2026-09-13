-- ═══════════════════════════════════════════════════════════════════════════
-- Escenario comun para los bancos que cargan el core COMPLETO.
--
--   local S = dofile("tests/harness/core_scenario.lua")
--   local env = S.boot({ withRouteArrows = false, withMDT = false })
--   S.enterRubyAndStartKey(env)
--   S.snapshot(env)   -- estado observable del core, para comparar
--
-- Carga MitzuMPlus por su .toc real (y, si se pide, MitzuRouteArrows por el
-- suyo), dispara ADDON_LOADED / PLAYER_LOGIN como WoW y conduce una llave.
-- ═══════════════════════════════════════════════════════════════════════════

local S = {}

function S.boot(opts)
    opts = opts or {}
    local WoW = dofile("tests/harness/wow_mock.lua")
    local Loader = dofile("tests/harness/addon_loader.lua")

    if opts.withThreatPlates then
        _G.ThreatPlates = { _mock = true }
    end
    if opts.withMDT then
        _G.MDT = { _mock = true }
        WoW.addonsLoaded["MythicDungeonTools"] = true
    end

    local env = { WoW = WoW, Loader = Loader, errors = {} }

    if opts.withCore ~= false then
        WoW.registerToc("MitzuMPlus", Loader.metadata("MitzuMPlus/MitzuMPlus.toc"))
        local errs, loaded = Loader.load("MitzuMPlus/MitzuMPlus.toc")
        env.coreFiles = loaded
        for _, e in ipairs(errs) do env.errors[#env.errors + 1] = "core: " .. e end
    end
    if opts.withRouteArrows then
        WoW.registerToc("MitzuRouteArrows", Loader.metadata("MitzuRouteArrows/MitzuRouteArrows.toc"))
        local errs, loaded = Loader.load("MitzuRouteArrows/MitzuRouteArrows.toc")
        env.mraFiles = loaded
        for _, e in ipairs(errs) do env.errors[#env.errors + 1] = "mra: " .. e end
    end

    -- Orden de WoW: cada addon recibe su ADDON_LOADED al terminar de cargar y,
    -- con todos cargados, llega PLAYER_LOGIN.
    if opts.withCore ~= false then WoW.startAddon("MitzuMPlus") end
    if opts.withRouteArrows then WoW.startAddon("MitzuRouteArrows") end
    WoW.login()
    for _, e in ipairs(WoW.errors) do env.errors[#env.errors + 1] = "runtime: " .. e end
    WoW.errors = {}
    return env
end

-- Entra en Ruby Life Pools (challengeMapID 399), arranca la llave y deja
-- correr los temporizadores del core.
function S.enterRubyAndStartKey(env)
    local WoW = env.WoW
    local st = WoW.state
    st.inInstance, st.instanceType = true, "party"
    st.instanceMapID, st.instanceName = 2521, "Estanques de Vida Rubi"
    st.uiMapID = 2094
    WoW.fire("PLAYER_ENTERING_WORLD", false, false)
    WoW.fire("ZONE_CHANGED_NEW_AREA")
    WoW.advance(2)
    st.challengeActive, st.challengeMapID, st.keyLevel = true, 399, 12
    WoW.fire("CHALLENGE_MODE_START", 399)
    WoW.advance(3)
    for _, e in ipairs(WoW.errors) do env.errors[#env.errors + 1] = "scenario: " .. e end
    WoW.errors = {}
end

-- Deja guardado un perfil de ruta adaptativa para la mazmorra, como si el
-- jugador lo hubiera importado de MDT. Se construye con la ruta nativa del
-- addon, asi el navegador de pulls y el HUD tienen ruta indexada.
function S.seedAdaptiveProfile(dungeonKey)
    local MP = rawget(_G, "MitzuMPlus")
    local ruta = MP.NativeRouteDB:GetDefault(dungeonKey)
    assert(ruta, "sin ruta nativa para " .. tostring(dungeonKey))
    local pulls, planned = {}, {}
    for i, pull in ipairs(ruta.pulls) do
        pulls[i] = (pull.count or 0) * 100 / ruta.totalForces
        local enemies = {}
        for _, mob in ipairs(pull.mobs) do
            enemies[#enemies + 1] = { enemyIdx = mob.enemyIdx, npcID = mob.npcID,
                                      forceCount = mob.forces, clones = mob.cloneIDs }
        end
        planned[i] = { pct = pulls[i], enemies = enemies }
    end
    local ok = MP.AdaptiveRoute.ProfileManager:Save(tostring(dungeonKey), {
        pulls = pulls, plannedPulls = planned, name = ruta.name, source = "MDT",
        mdtDungeonIdx = ruta.mdtDungeonIdx, totalForces = ruta.totalForces,
    })
    assert(ok, "no se pudo guardar el perfil")
end

-- Estado observable del core, SOLO por la API publica, en una tabla plana.
function S.snapshot()
    local api = _G.MitzuMPlusAPI
    if not api then return { api = false } end
    local p = api.GetRouteProgress() or {}
    return {
        api = true,
        ready = api.IsReady(),
        version = api.GetVersion(),
        dungeonState = api.GetDungeonState(),
        dungeonKey = api.GetCurrentDungeonKey(),
        challenge = api.IsChallengeActive(),
        routeID = p.routeID,
        routeState = p.state,
        pull = p.pull,
        pullCount = p.pullCount,
        navigatorPull = api.GetNavigatorPull(),
        navigatorPullCount = api.GetNavigatorPullCount(),
    }
end

-- Serializacion determinista (claves ordenadas) de una tabla de datos.
function S.serialize(v, vistos)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t ~= "table" then return tostring(t == "function" and "fn" or v) end
    vistos = vistos or {}
    if vistos[v] then return "<ciclo>" end
    vistos[v] = true
    local claves = {}
    for k in pairs(v) do claves[#claves + 1] = k end
    table.sort(claves, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == "number" or ta == "string" then return a < b end
        return tostring(a) < tostring(b)
    end)
    local partes = {}
    for _, k in ipairs(claves) do
        partes[#partes + 1] = "[" .. S.serialize(k, vistos) .. "]=" .. S.serialize(v[k], vistos)
    end
    vistos[v] = nil
    return "{" .. table.concat(partes, ",") .. "}"
end

-- Las SavedVariables del core, tal como quedarian escritas al salir.
function S.coreSavedVariables()
    return S.serialize({ MitzuMPlusDB = rawget(_G, "MitzuMPlusDB"),
                         MPlusAdaptiveRouteDB = rawget(_G, "MPlusAdaptiveRouteDB") })
end

function S.same(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false, k end end
    for k, v in pairs(b) do if a[k] ~= v then return false, k end end
    return true
end

-- Ejecuta `fn` y despues deja _G exactamente como estaba: quita las globales
-- nuevas y restaura las que se cambiaron (tambien dentro de string/table/math).
-- Permite arrancar dos clientes simulados seguidos en el mismo banco sin que
-- el segundo herede nada del primero.
local function fotografia(t)
    local copia = {}
    for k, v in pairs(t) do copia[k] = v end
    return copia
end

local function restaurar(t, foto)
    for k in pairs(t) do
        if foto[k] == nil then rawset(t, k, nil) end
    end
    for k, v in pairs(foto) do rawset(t, k, v) end
end

function S.isolated(fn)
    local libs = { string = fotografia(string), table = fotografia(table),
                   math = fotografia(math), os = fotografia(os) }
    local foto = fotografia(_G)
    local mt = getmetatable(_G)
    local resultados = { pcall(fn) }
    setmetatable(_G, mt)
    restaurar(_G, foto)
    for nombre, f in pairs(libs) do restaurar(_G[nombre], f) end
    if not resultados[1] then error(resultados[2], 0) end
    return select(2, (table.unpack or unpack)(resultados))
end

return S
