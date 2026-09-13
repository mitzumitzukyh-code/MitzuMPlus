-- MitzuMPlus (core) funcionando SOLO, cargado por su .toc real en un cliente
-- de WoW simulado. No se carga desde el TOC. Ejecutar con:
--   python tests/run_lua_tests.py
--
-- Cubre los requisitos de la separacion:
--   A  el core funciona sin MitzuRouteArrows
--   B  el core funciona con MDT desactivado (y no se rompe si esta)
--   C  el core no carga flechas, nameplates, Evidence, Alignment ni Threat Plates
--   H  orden de carga del .toc del core
--   I  comandos del core sin los experimentales

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
local Loader = dofile("tests/harness/addon_loader.lua")
local Src = dofile("tests/harness/lua_source.lua")

local CORE_TOC = "MitzuMPlus/MitzuMPlus.toc"

-- Todo lo que se fue a MitzuRouteArrows. Ningun fichero, modulo ni global con
-- estos nombres puede existir en el core.
local EXPERIMENTAL = {
    "RouteArrows", "NameplateAnchorProvider", "NameplateGenerations",
    "PullUnitResolver", "LiveEnemyResolver", "ArrowDemo", "ArrowDemoTelemetry",
    "GuidanceEngine", "RouteArrowPresenter",
    "EngagementEvidence", "UnitLinkEvidence", "CastEvidence", "AuraEvidence",
    "EventCastEvidence", "PackEvidence", "PhysicalGroupMetadata",
    "PhysicalGroupCorrelation", "MDTPhysicalGroupData",
    "RouteSignature", "ExecutionEpisodeTracker", "RoutePullCandidateScorer",
    "RouteAlignment",
}

local function sinErrores(env, label)
    if #env.errors > 0 then
        error(label .. ": " .. #env.errors .. " errores\n" ..
              table.concat(env.errors, "\n", 1, math.min(#env.errors, 8)), 2)
    end
    assertions = assertions + 1
end

local function ultimoImpreso(env, patron)
    for i = #env.WoW.printed, 1, -1 do
        if env.WoW.printed[i]:find(patron) then return env.WoW.printed[i] end
    end
end

-- ── A ──────────────────────────────────────────────────────────────────────

test("A1 el core carga entero por su .toc sin MitzuRouteArrows y sin errores", function()
    S.isolated(function()
        local env = S.boot({ withRouteArrows = false })
        sinErrores(env, "arranque")
        truthy(#env.coreFiles > 60, "ficheros cargados: " .. #env.coreFiles)
        equal(rawget(_G, "MitzuRouteArrows"), nil, "MitzuRouteArrows no existe")
        equal(rawget(_G, "MitzuRouteArrowsDB"), nil, "ni sus SavedVariables")
        local api = rawget(_G, "MitzuMPlusAPI")
        truthy(api, "API publicada")
        equal(api.IsReady(), true, "core listo tras PLAYER_LOGIN")
        equal(api.GetVersion(), Loader.metadata(CORE_TOC).Version, "version del .toc")
        truthy(type(rawget(_G, "MitzuMPlusDB")) == "table", "SavedVariables del core creadas")
    end)
end)

test("A2 el core juega una llave solo: mazmorra, ruta nativa y avance de pull", function()
    S.isolated(function()
        local env = S.boot({ withRouteArrows = false })
        S.enterRubyAndStartKey(env)
        sinErrores(env, "escenario")
        local snap = S.snapshot()
        equal(snap.dungeonState, "RUNNING", "estado de mazmorra")
        equal(snap.challenge, true, "llave activa")
        equal(snap.dungeonKey, "399", "Ruby Life Pools (la clave es texto)")
        equal(snap.routeID, "mitzu_399_standard", "ruta nativa elegida")
        equal(snap.routeState, "ACTIVE", "ruta activa")
        equal(snap.pull, 1, "empieza en el pull 1")
        equal(snap.pullCount, 11, "pulls de la ruta")

        local MP = rawget(_G, "MitzuMPlus")
        truthy(MP.RouteProgress:NextPull("MANUAL"), "RouteProgress avanza")
        equal(_G.MitzuMPlusAPI.GetCurrentPull(), 2, "la API ve el pull 2")
        truthy(MP.RouteProgress:PreviousPull("MANUAL"), "RouteProgress retrocede")
        equal(_G.MitzuMPlusAPI.GetCurrentPull(), 1, "vuelve al pull 1")

        -- Los paneles se construyen y la ayuda del core responde.
        MP:HandleSlashCommand("help")
        truthy(ultimoImpreso(env, "/MitzuMPlus") or ultimoImpreso(env, "/emp"), "ayuda impresa")
        sinErrores(env, "comandos")
        equal(#env.WoW.errors, 0, "sin errores en tiempo de ejecucion")
    end)
end)

-- ── B ──────────────────────────────────────────────────────────────────────

test("B1 sin MDT la ruta sale de los datos nativos del addon", function()
    S.isolated(function()
        local env = S.boot({ withRouteArrows = false, withMDT = false })
        S.enterRubyAndStartKey(env)
        sinErrores(env, "sin MDT")
        equal(rawget(_G, "MDT"), nil, "MDT no esta")
        equal(env.WoW.addonsLoaded["MythicDungeonTools"], nil, "ni figura como cargado")
        local snap = S.snapshot()
        equal(snap.routeState, "ACTIVE", "ruta activa sin MDT")
        equal(snap.pullCount, 11, "pulls de la ruta nativa")
        truthy(#_G.MitzuMPlusAPI.GetNativeRouteKeys() >= 8, "rutas nativas de la temporada")
    end)
end)

test("B2 MDT es opcional: el .toc no lo exige y su presencia no rompe el arranque", function()
    local meta = Loader.metadata(CORE_TOC)
    equal(meta.Dependencies, nil, "sin Dependencies")
    equal(meta.RequiredDeps, nil, "sin RequiredDeps")
    truthy((meta.OptionalDeps or ""):find("MythicDungeonTools", 1, true), "MDT en OptionalDeps")
    S.isolated(function()
        local env = S.boot({ withRouteArrows = false, withMDT = true })
        S.enterRubyAndStartKey(env)
        sinErrores(env, "con MDT (simulado)")
        equal(S.snapshot().routeState, "ACTIVE", "ruta activa con MDT presente")
    end)
end)

-- ── C ──────────────────────────────────────────────────────────────────────

test("C1 el .toc del core no nombra ni un fichero experimental", function()
    for _, entrada in ipairs(Loader.files(CORE_TOC)) do
        local ruta = entrada.lua or entrada.missing
        for _, nombre in ipairs(EXPERIMENTAL) do
            if ruta:find("/" .. nombre .. ".lua", 1, true) then
                error("el core carga " .. ruta)
            end
        end
        assertions = assertions + 1
        if ruta:find("/Evidence/", 1, true) or ruta:find("/Alignment/", 1, true) then
            error("el core carga " .. ruta)
        end
    end
end)

test("C2 tras jugar una llave no hay modulos ni globales experimentales", function()
    S.isolated(function()
        local env = S.boot({ withRouteArrows = false })
        S.enterRubyAndStartKey(env)
        local MP = rawget(_G, "MitzuMPlus")
        local AR = rawget(MP, "AdaptiveRoute")
        for _, nombre in ipairs(EXPERIMENTAL) do
            equal(rawget(MP, nombre), nil, "MitzuMPlus." .. nombre)
            equal(rawget(AR, nombre), nil, "AdaptiveRoute." .. nombre)
            equal(rawget(_G, nombre), nil, "_G." .. nombre)
        end
        equal(rawget(_G, "MitzuMPlusEventBus"), nil, "el EventBus ya no se publica en _G")
        equal(rawget(MP.RouteManager, "GetPullSignature"), nil, "firma de pull fuera del core")
        local defaults = MP.AdaptiveRoute.ProfileManager
        local db = rawget(_G, "MPlusAdaptiveRouteDB") or {}
        for _, clave in ipairs({ "routeArrowsEnabled", "arrowSize", "arrowAnchor",
                                 "arrowOffsetX", "arrowOffsetY", "arrowAlpha", "arrowAnimate" }) do
            equal(db[clave], nil, "ajuste de flechas en la DB del core: " .. clave)
        end
        truthy(defaults, "ProfileManager sigue en el core")
    end)
end)

test("C3 el codigo del core no nombra modulos experimentales ni Threat Plates", function()
    local prohibidos = { ThreatPlates = true, TidyPlatesThreat = true, Plater = true,
                         MitzuRouteArrows = true, MitzuRouteArrowsDB = true }
    local porNombre = {}
    for _, nombre in ipairs(EXPERIMENTAL) do prohibidos[nombre] = true; porNombre[nombre] = true end
    local revisados = 0
    for _, entrada in ipairs(Loader.files(CORE_TOC)) do
        local ruta = entrada.lua
        if ruta and not ruta:find("^MitzuMPlus/libs/") then
            revisados = revisados + 1
            local texto = Src.read(ruta)
            local ids = Src.identifiers(texto)
            for nombre in pairs(prohibidos) do
                if ids[nombre] then error(ruta .. " usa " .. nombre) end
            end
            -- Tampoco por su nombre en un string (rawget(M, "RouteArrows")...).
            for _, s in ipairs(Src.strings(texto)) do
                if porNombre[s] then error(ruta .. " busca el modulo " .. s .. " por nombre") end
            end
            assertions = assertions + 1
        end
    end
    truthy(revisados > 60, "ficheros propios revisados: " .. revisados)
end)

-- ── H ──────────────────────────────────────────────────────────────────────

test("H1 .toc del core: metadatos de release y todo lo que nombra existe", function()
    local meta = Loader.metadata(CORE_TOC)
    equal(meta.Title, "MitzuMPlus", "Title")
    truthy(meta.Interface and meta.Interface:match("^%d+"), "Interface")
    truthy(meta.Version and not meta.Version:find("dev", 1, true), "Version sin -dev: " .. tostring(meta.Version))
    truthy(meta.Author, "Author")
    truthy(meta.Notes, "Notes")
    equal(meta.SavedVariables, "MitzuMPlusDB, MPlusAdaptiveRouteDB", "SavedVariables")
    truthy(not (meta.Title or ""):find("Historial", 1, true), "sin el nombre antiguo")

    local vistos, orden = {}, {}
    for i, e in ipairs(Loader.files(CORE_TOC)) do
        equal(e.missing, nil, "fichero que falta")
        assertions = assertions + 1
        if vistos[e.lua] then error("cargado dos veces: " .. e.lua) end
        vistos[e.lua] = i
        orden[#orden + 1] = e.lua
    end
    local function pos(sufijo)
        for i, r in ipairs(orden) do
            if r:sub(-#sufijo) == sufijo then return i end
        end
        error("no esta en el .toc: " .. sufijo)
    end
    truthy(pos("libs/LibStub/LibStub.lua") < pos("MitzuMPlus/MitzuMPlus_main.lua"), "LibStub antes que el addon")
    truthy(pos("MitzuMPlus/MitzuMPlus_main.lua") < pos("modules/EventBus.lua"), "main antes que los modulos")
    truthy(pos("modules/RouteProgress.lua") < pos("API/PublicAPI.lua"), "la API despues de RouteProgress")
    truthy(pos("AdaptiveRoute/PullNavigator.lua") < pos("API/PublicAPI.lua"), "la API despues de PullNavigator")
    truthy(pos("API/PublicAPI.lua") < pos("MitzuMPlus/Init.lua"), "la API antes de Init")
end)

test("H2 los ficheros del .toc cargan en orden y sin errores uno a uno", function()
    S.isolated(function()
        dofile("tests/harness/wow_mock.lua")
        local errores, cargados = Loader.load(CORE_TOC, { stopOnError = true })
        equal(#errores, 0, "errores de carga: " .. tostring(errores[1]))
        equal(#cargados, #Loader.files(CORE_TOC), "todos cargados")
    end)
end)

-- ── I ──────────────────────────────────────────────────────────────────────

test("I1 el core ya no atiende los comandos que se fueron a /mra", function()
    S.isolated(function()
        local env = S.boot({ withRouteArrows = false })
        local MP = rawget(_G, "MitzuMPlus")
        for _, cmd in ipairs({ "alignment", "alignmentdetail", "evidence", "castevidence",
                               "auraevidence", "eventcast", "packevidence", "plates",
                               "arrow", "arrowall", "arrowdemo", "guidance", "marktarget",
                               "physicalgroups", "groupcorrelation", "probe", "resolverdump" }) do
            local antes = #env.WoW.printed
            MP:HandleSlashCommand(cmd)
            local texto = table.concat(env.WoW.printed, "\n", antes + 1)
            truthy(texto:find("Comando desconocido", 1, true), "/emp " .. cmd .. " desconocido")
        end
        sinErrores(env, "comandos")
        -- El core registra sus dos barras y ninguna de MitzuRouteArrows.
        local barras = {}
        for k, v in pairs(_G) do
            if type(k) == "string" and k:match("^SLASH_") and type(v) == "string" then
                barras[v:lower()] = k
            end
        end
        truthy(barras["/emp"], "/emp registrado")
        truthy(barras["/mitzumplus"], "/mitzumplus registrado")
        equal(barras["/mra"], nil, "/mra no es del core")
        equal(rawget(_G, "BINDING_NAME_MITZUMPLUS_ROUTE_MARK_TARGET"), nil, "tecla de marcar fuera del core")
    end)
end)

test("I2 Bindings.xml del core no declara la tecla de marcar objetivo", function()
    local xml = Src.read("MitzuMPlus/Bindings.xml")
    truthy(not xml:find("MARK_TARGET", 1, true), "sin MARK_TARGET")
    truthy(not xml:find("PullUnitResolver", 1, true), "sin PullUnitResolver")
    truthy(xml:find("MitzuMPlus_HistoryTabBinding", 1, true), "binding del historial renombrado")
end)

if #failures > 0 then
    error(string.format("CoreStandalone: %d tests, %d assertions, %d failures\n%s",
        tests, assertions, #failures, table.concat(failures, "\n")), 0)
end

return { tests = tests, assertions = assertions }
