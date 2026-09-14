-- MitzuRouteArrows (experimental): relacion con MitzuMPlus.
-- No se carga desde el TOC. Ejecutar con: python tests/run_lua_tests.py
--
-- Cubre los requisitos de la separacion:
--   D  MitzuRouteArrows solo consume MitzuMPlusAPI
--   E  MitzuRouteArrows no puede mover el pull, fabricar identidad, cambiar el
--      progreso ni escribir la sesion de la run
--   F  con o sin MitzuRouteArrows, el core da exactamente el mismo resultado
--   G  MitzuRouteArrows detecta si estan MitzuMPlus y Threat Plates, sin errores
--   H  orden de carga del .toc de MitzuRouteArrows
--   I  comandos y teclas de los dos addons sin colisiones

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

local MRA_TOC = "MitzuRouteArrows/MitzuRouteArrows.toc"
local CORE_TOC = "MitzuMPlus/MitzuMPlus.toc"

local function sinErrores(env, label)
    if #env.errors > 0 then
        error(label .. ": " .. #env.errors .. " errores\n" ..
              table.concat(env.errors, "\n", 1, math.min(#env.errors, 8)), 2)
    end
    assertions = assertions + 1
end

local function impresoDesde(env, desde)
    return table.concat(env.WoW.printed, "\n", desde + 1)
end

-- Todos los comandos de /mra, con los subcomandos que activan cada capa.
local COMANDOS_MRA = {
    "status", "debug", "help",
    "alignment on", "alignment", "alignmentdetail", "alignment candidates",
    "alignment history", "alignment episodes", "alignment signature",
    "evidence", "evidence summary", "castevidence", "auraevidence", "eventcast",
    "packevidence", "plates", "guidance", "guidancedetail", "physicalgroups",
    "groupcorrelation", "probeplates", "resolverdump", "forcemap", "probe",
    "arrowdemo on", "arrowdemo status", "arrowdemo report", "arrow", "arrowall",
    "arrowpulltest 2", "marktarget", "unmarktarget", "resolveplates",
}

-- Estado del core leido POR DENTRO (el banco si puede): lo que MitzuRouteArrows
-- no debe poder cambiar.
local function estadoInterno()
    local MP = rawget(_G, "MitzuMPlus")
    local RP = MP.RouteProgress
    local RS = rawget(MP, "RunSession")
    return {
        pull = RP:GetPullIndex(),
        state = RP:GetState(),
        route = RP:GetRoute(),
        recovered = RP:WasRecovered(),
        navigator = MP.AdaptiveRoute.PullNavigator:GetCurrentPull(),
        session = RS and S.serialize(rawget(RS, "_state")) .. S.serialize(rawget(RS, "_reason")) or "-",
        saved = S.coreSavedVariables(),
    }
end

-- ── D ──────────────────────────────────────────────────────────────────────

local function ficherosMRA()
    local lista = {}
    for _, e in ipairs(Loader.files(MRA_TOC)) do
        lista[#lista + 1] = e.lua or error("falta " .. tostring(e.missing))
    end
    return lista
end

test("D1 ningun fichero de MitzuRouteArrows nombra el core fuera de MitzuMPlusAPI", function()
    local prohibidosId = { MitzuMPlus = true, MitzuMPlusDB = true, MPlusAdaptiveRouteDB = true,
                           MitzuMPlusEventBus = true, LibStub = true }
    local prohibidosStr = { MitzuMPlus = true, MitzuMPlusDB = true, MPlusAdaptiveRouteDB = true,
                            MitzuMPlusEventBus = true, ["AceAddon-3.0"] = true }
    local usosAPI = {}
    for _, ruta in ipairs(ficherosMRA()) do
        local texto = Src.read(ruta)
        local ids = Src.identifiers(texto)
        for nombre in pairs(prohibidosId) do
            if ids[nombre] then error(ruta .. " usa " .. nombre) end
        end
        for _, s in ipairs(Src.strings(texto)) do
            if prohibidosStr[s] then error(ruta .. " busca \"" .. s .. "\" por nombre") end
            if s == "MitzuMPlusAPI" then usosAPI[#usosAPI + 1] = ruta end
        end
        if ids.MitzuMPlusAPI then usosAPI[#usosAPI + 1] = ruta end
        assertions = assertions + 1
    end
    -- La API se localiza en un unico sitio: MRA:GetAPI().
    equal(#usosAPI, 1, "sitios que localizan la API")
    equal(usosAPI[1], "MitzuRouteArrows/Core/Bootstrap.lua", "solo Core/Bootstrap")
end)

test("D2 en tiempo de ejecucion, Host solo llega al core por MitzuMPlusAPI", function()
    S.isolated(function()
        local env = S.boot({ withRouteArrows = true })
        S.enterRubyAndStartKey(env)
        sinErrores(env, "arranque")
        local MRA = _G.MitzuRouteArrows
        local MP = rawget(_G, "MitzuMPlus")
        -- Ningun valor alcanzable desde MRA es un modulo del core.
        local internos = { [MP] = "MitzuMPlus", [MP.RouteProgress] = "RouteProgress",
                           [MP.AdaptiveRoute] = "AdaptiveRoute", [MP.EventBus] = "EventBus",
                           [MP.RouteManager] = "RouteManager", [MP.DungeonContext] = "DungeonContext",
                           [MP.RouteProgress:GetRoute()] = "ruta interna",
                           [MP.AdaptiveRoute.PullNavigator] = "PullNavigator",
                           [rawget(_G, "MitzuMPlusDB")] = "MitzuMPlusDB",
                           [rawget(_G, "MPlusAdaptiveRouteDB")] = "MPlusAdaptiveRouteDB" }
        if rawget(MP, "RunSession") then internos[MP.RunSession] = "RunSession" end
        -- Se llenan las caches de Host antes de buscar.
        MRA.Host.RouteProgress:GetRoute()
        MRA.Host.RouteProgress:GetCurrentPull()
        MRA.Host.DataStructure:Get()
        MRA.Commands:Handle("alignment on")
        MRA.Commands:Handle("alignmentdetail")
        local visto = {}
        local function buscar(v, camino)
            if type(v) ~= "table" or visto[v] then return end
            visto[v] = true
            if internos[v] then error("MRA alcanza " .. internos[v] .. " por " .. camino) end
            for k, x in pairs(v) do
                if type(x) == "table" then buscar(x, camino .. "." .. tostring(k)) end
            end
            local mt = getmetatable(v)
            if type(mt) == "table" then buscar(mt, camino .. "<mt>") end
        end
        buscar(MRA, "MitzuRouteArrows")
        buscar(rawget(_G, "MitzuRouteArrowsDB"), "MitzuRouteArrowsDB")
        assertions = assertions + 1
    end)
end)

-- ── E ──────────────────────────────────────────────────────────────────────

test("E1 Host no tiene ni un escritor", function()
    S.isolated(function()
        S.boot({ withRouteArrows = true })
        local Host = _G.MitzuRouteArrows.Host
        local lectores = 0
        for fachada, t in pairs(Host) do
            if type(t) == "table" then
                for metodo, fn in pairs(t) do
                    if type(fn) == "function" then
                        lectores = lectores + 1
                        local nombre = tostring(metodo)
                        local escritor = nombre:match("^Set") or nombre:match("^Next")
                            or nombre:match("^Prev") or nombre:match("^Restore")
                            or nombre:match("Reset") or nombre:match("^Start")
                            or nombre:match("^Complete") or nombre:match("^Mark")
                            or nombre:match("^Save") or nombre:match("^Emit")
                            or nombre:match("^Write")
                        equal(escritor, nil, "Host." .. fachada .. ":" .. nombre)
                    end
                end
            end
        end
        truthy(lectores >= 20, "lectores revisados: " .. lectores)
        equal(Host.EventBus.Emit, nil, "Host.EventBus no emite")
        equal(Host.RouteProgress.SetPull, nil, "sin SetPull")
    end)
end)

test("E2 el codigo de MitzuRouteArrows no llama a escritores del core", function()
    local escritores = { "SetPull", "NextPull", "PreviousPull", "RestorePull", "SetCurrentPull",
                         "routeCurrentPull", "RunSession", "OnRouteRecovered", "Emit" }
    for _, ruta in ipairs(ficherosMRA()) do
        local ids = Src.identifiers(Src.read(ruta))
        for _, nombre in ipairs(escritores) do
            if ids[nombre] then error(ruta .. " nombra " .. nombre) end
        end
        assertions = assertions + 1
    end
end)

test("E3 todos los comandos de /mra con una llave en marcha no cambian el core", function()
    S.isolated(function()
        local env = S.boot({ withRouteArrows = true, withThreatPlates = true })
        S.seedAdaptiveProfile(399)
        S.enterRubyAndStartKey(env)
        sinErrores(env, "arranque")
        equal(_G.MitzuMPlusAPI.GetNavigatorPullCount(), 11, "ruta adaptativa indexada")
        local MRA = _G.MitzuRouteArrows
        local MP = rawget(_G, "MitzuMPlus")
        MP.RouteProgress:NextPull("MANUAL")
        local antes = estadoInterno()
        local desde = #env.WoW.printed
        for _, cmd in ipairs(COMANDOS_MRA) do
            equal(MRA.Commands:Handle(cmd), true, "/mra " .. cmd)
        end
        env.WoW.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env.WoW.fire("PLAYER_TARGET_CHANGED")
        env.WoW.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        MitzuRouteArrows_MarkTargetBinding()
        local texto = impresoDesde(env, desde)
        -- El navegador lo mueve el core; MRA solo escucha (Lifecycle).
        local PN = MP.AdaptiveRoute.PullNavigator
        PN:NextPull()
        PN:PreviousPull()
        antes.saved = S.coreSavedVariables()
        equal(texto:find("Error en /mra", 1, true), nil, "ningun comando falla")
        equal(texto:find("EventBus Error", 1, true), nil, "ni el bus del core")
        equal(#env.WoW.errors, 0, "sin errores de ejecucion")
        local despues = estadoInterno()
        for k, v in pairs(antes) do equal(despues[k], v, "core." .. k) end
        MRA.Commands:Handle("arrowdemo off")
        MRA.Commands:Handle("alignment off")
    end)
end)

test("E4 lo que Host entrega son copias: mutarlas no llega al core", function()
    S.isolated(function()
        local env = S.boot({ withRouteArrows = true })
        S.enterRubyAndStartKey(env)
        local Host = _G.MitzuRouteArrows.Host
        local MP = rawget(_G, "MitzuMPlus")
        local ruta = Host.RouteProgress:GetRoute()
        truthy(ruta ~= MP.RouteProgress:GetRoute(), "no es la ruta interna")
        ruta.pulls[1].count = -1
        ruta.id = "manipulada"
        equal(MP.RouteProgress:GetRoute().id, "mitzu_399_standard", "id interno")
        truthy(MP.RouteProgress:GetRoute().pulls[1].count ~= -1, "pull interno")
        local ok = pcall(function() _G.MitzuMPlusAPI.GetCurrentPull = function() return 5 end end)
        equal(ok, false, "tampoco se puede reemplazar la API")
        equal(MP.RouteProgress:GetPullIndex(), 1, "pull del core")
        sinErrores(env, "escenario")
    end)
end)

test("E5 marcar un objetivo con la tecla es una anotacion local, no identidad del core", function()
    S.isolated(function()
        local env = S.boot({ withRouteArrows = true })
        S.enterRubyAndStartKey(env)
        local antes = estadoInterno()
        local MRA = _G.MitzuRouteArrows
        local PUR = MRA.PullUnitResolver
        truthy(PUR, "PullUnitResolver en MRA")
        MitzuRouteArrows_MarkTargetBinding()
        pcall(PUR.ResolveCurrentPull, PUR)
        local despues = estadoInterno()
        for k, v in pairs(antes) do equal(despues[k], v, "core." .. k) end
        sinErrores(env, "escenario")
    end)
end)

-- ── F ──────────────────────────────────────────────────────────────────────

-- La misma partida, paso a paso, con o sin MitzuRouteArrows funcionando a tope.
local function partida(conMRA)
    return S.isolated(function()
        local env = S.boot({ withRouteArrows = conMRA, withThreatPlates = true })
        S.seedAdaptiveProfile(399)
        S.enterRubyAndStartKey(env)
        local MRA = rawget(_G, "MitzuRouteArrows")
        local MP = rawget(_G, "MitzuMPlus")
        local fotos = {}
        local function foto(etiqueta)
            fotos[#fotos + 1] = etiqueta .. S.serialize(S.snapshot())
        end
        foto("inicio")
        if conMRA then
            for _, cmd in ipairs(COMANDOS_MRA) do MRA.Commands:Handle(cmd) end
        end
        foto("tras comandos")
        MP.RouteProgress:NextPull("MANUAL")
        env.WoW.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env.WoW.advance(4)
        foto("pull 2")
        MP.AdaptiveRoute.PullNavigator:NextPull()
        MP.RouteProgress:NextPull("MANUAL")
        env.WoW.advance(4)
        foto("pull 3")
        MP.RouteProgress:PreviousPull("MANUAL")
        env.WoW.advance(2)
        foto("vuelta a 2")
        if conMRA then
            MRA.Commands:Handle("arrowdemo off")
            MRA.Commands:Handle("alignment off")
        end
        return {
            fotos = table.concat(fotos, "\n"),
            saved = S.coreSavedVariables(),
            errores = #env.errors + #env.WoW.errors,
            mra = MRA ~= nil,
        }
    end)
end

test("F1 el core da el mismo resultado con y sin MitzuRouteArrows", function()
    local solo = partida(false)
    local con = partida(true)
    equal(solo.mra, false, "la primera partida es sin MRA")
    equal(con.mra, true, "la segunda con MRA")
    equal(solo.errores, 0, "sin errores (solo core)")
    equal(con.errores, 0, "sin errores (con MRA)")
    equal(con.fotos, solo.fotos, "estado observable paso a paso")
    equal(con.saved, solo.saved, "SavedVariables del core")
    truthy(solo.fotos:find("[\"pull\"]=3", 1, true), "la partida llego al pull 3")
    truthy(solo.fotos:find("[\"navigatorPull\"]=2", 1, true), "y el navegador se movio")
end)

-- ── G ──────────────────────────────────────────────────────────────────────

for _, conTP in ipairs({ false, true }) do
    local sufijo = conTP and " (con Threat Plates)" or " (sin Threat Plates)"

    test("G1 sin MitzuMPlus carga, avisa claro una vez y queda inerte" .. sufijo, function()
        S.isolated(function()
            local env = S.boot({ withCore = false, withRouteArrows = true, withThreatPlates = conTP })
            sinErrores(env, "arranque sin core")
            local MRA = _G.MitzuRouteArrows
            truthy(MRA, "el addon existe")
            equal(rawget(_G, "MitzuMPlusAPI"), nil, "no hay API")
            equal(MRA:HostState(), "MISSING", "estado")
            equal(MRA:CanOperate(), false, "no opera")
            local avisos = 0
            for _, l in ipairs(env.WoW.printed) do
                if l:find("necesita", 1, true) and l:find("MitzuMPlus", 1, true) then avisos = avisos + 1 end
            end
            equal(avisos, 1, "un aviso al entrar")

            local desde = #env.WoW.printed
            equal(MRA.Commands:Handle("evidence"), false, "/mra evidence rechazado")
            equal(MRA.Commands:Handle("alignmentdetail"), false, "/mra alignmentdetail rechazado")
            equal(MRA.Commands:Handle("arrowdemo on"), false, "/mra arrowdemo rechazado")
            truthy(impresoDesde(env, desde):find("necesita", 1, true), "explica por que")
            equal(MRA.Commands:Handle("status"), true, "/mra status responde")
            local st = impresoDesde(env, desde)
            truthy(st:find("state=MISSING", 1, true), "status dice MISSING")
            truthy(st:find(conTP and "nameplateAddons=ThreatPlates" or "nameplateAddons=ninguno", 1, true),
                "status detecta placas" .. sufijo)
            MitzuRouteArrows_MarkTargetBinding()

            -- Aunque ocurra lo que en una llave, nada pinta ni lanza.
            S.enterRubyAndStartKey(env)
            env.WoW.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
            env.WoW.advance(5)
            sinErrores(env, "escenario sin core")
            equal(#env.WoW.errors, 0, "sin errores de ejecucion")
            local RA = MRA.RouteArrows
            local activas = 0
            if RA and type(RA._active) == "table" then
                for _ in pairs(RA._active) do activas = activas + 1 end
            end
            equal(activas, 0, "ninguna flecha activa")
            equal(MRA.Host:PendingCount() > 0, true, "suscripciones en espera, no registradas")
        end)
    end)

    test("G2 con MitzuMPlus conecta y lo dice" .. sufijo, function()
        S.isolated(function()
            local env = S.boot({ withRouteArrows = true, withThreatPlates = conTP })
            sinErrores(env, "arranque")
            local MRA = _G.MitzuRouteArrows
            equal(MRA:HostState(), "OK", "estado")
            equal(MRA.Host:PendingCount(), 0, "todas las suscripciones registradas")
            for _, l in ipairs(env.WoW.printed) do
                equal(l:find("necesita", 1, true), nil, "sin aviso de ausencia")
            end
            local desde = #env.WoW.printed
            MRA.Commands:Handle("status")
            local st = impresoDesde(env, desde)
            truthy(st:find("state=OK", 1, true), "status OK")
            truthy(st:find("version=" .. Loader.metadata(CORE_TOC).Version, 1, true), "version del core")
            truthy(st:find(conTP and "ThreatPlates" or "ninguno", 1, true), "placas" .. sufijo)
        end)
    end)
end

test("G3 con una API de contrato distinto se niega a operar", function()
    S.isolated(function()
        local env = S.boot({ withRouteArrows = true })
        local MRA = _G.MitzuRouteArrows
        MRA.REQUIRED_API_VERSION = 99
        equal(MRA:HostState(), "INCOMPATIBLE", "estado")
        local desde = #env.WoW.printed
        equal(MRA.Commands:Handle("alignment"), false, "rechazado")
        truthy(impresoDesde(env, desde):find("compatible", 1, true), "mensaje de version")
        equal(MRA.Commands:Handle("status"), true, "status sigue respondiendo")
        sinErrores(env, "arranque")
    end)
end)

-- ── H ──────────────────────────────────────────────────────────────────────

test("H1 .toc de MitzuRouteArrows: experimental, dependencia opcional y todo existe", function()
    local meta = Loader.metadata(MRA_TOC)
    local core = Loader.metadata(CORE_TOC)
    truthy((meta.Title or ""):find("EXPERIMENTAL", 1, true), "Title marca EXPERIMENTAL")
    equal(meta["X-Status"], "EXPERIMENTAL", "X-Status")
    truthy((meta.Version or ""):find("dev", 1, true), "Version de desarrollo: " .. tostring(meta.Version))
    equal(meta.Interface, core.Interface, "mismo Interface que el core")
    equal(meta.SavedVariables, "MitzuRouteArrowsDB", "SavedVariables propias")
    truthy((meta.OptionalDeps or ""):find("MitzuMPlus", 1, true), "MitzuMPlus en OptionalDeps (carga antes)")
    equal(meta.Dependencies, nil, "sin Dependencies: si falta el core, avisa en vez de no cargar")
    equal(meta.RequiredDeps, nil, "sin RequiredDeps")

    local orden, vistos = {}, {}
    for _, e in ipairs(Loader.files(MRA_TOC)) do
        equal(e.missing, nil, "fichero que falta")
        if vistos[e.lua] then error("cargado dos veces: " .. e.lua) end
        vistos[e.lua] = true
        orden[#orden + 1] = e.lua
    end
    equal(orden[1], "MitzuRouteArrows/Core/Bootstrap.lua", "Bootstrap primero")
    equal(orden[2], "MitzuRouteArrows/Core/Host.lua", "Host segundo")
    equal(orden[#orden], "MitzuRouteArrows/Core/Commands.lua", "Commands al final")
    equal(orden[#orden - 1], "MitzuRouteArrows/Core/Lifecycle.lua", "Lifecycle antes de Commands")
    for _, r in ipairs(orden) do
        truthy(r:find("^MitzuRouteArrows/"), "todo dentro de su carpeta: " .. r)
    end
end)

test("H2 cada fichero de MitzuRouteArrows carga en orden, con y sin el core", function()
    for _, conCore in ipairs({ false, true }) do
        S.isolated(function()
            dofile("tests/harness/wow_mock.lua")
            if conCore then
                local e = Loader.load(CORE_TOC, { stopOnError = true })
                equal(#e, 0, "core: " .. tostring(e[1]))
            end
            local errores, cargados = Loader.load(MRA_TOC, { stopOnError = true })
            equal(#errores, 0, "MRA (core=" .. tostring(conCore) .. "): " .. tostring(errores[1]))
            equal(#cargados, #Loader.files(MRA_TOC), "todos cargados")
        end)
    end
end)

test("H3 ningun fichero Lua de MitzuRouteArrows queda fuera del .toc", function()
    local enToc = {}
    for _, r in ipairs(ficherosMRA()) do enToc[r] = true end
    local conocidos = {
        "Core/Bootstrap", "Core/Host", "Core/CopyBox", "Core/Lifecycle", "Core/Commands",
        "Data/MDTPhysicalGroupData",
        "Evidence/EngagementEvidence", "Evidence/UnitLinkEvidence", "Evidence/CastEvidence",
        "Evidence/AuraEvidence", "Evidence/EventCastEvidence", "Evidence/PackEvidence",
        "Evidence/PhysicalGroupMetadata", "Evidence/PhysicalGroupCorrelation",
        "Modules/NameplateAnchorProvider", "Modules/RouteArrows", "Modules/PullUnitResolver",
        "Modules/LiveEnemyResolver", "Modules/GuidanceEngine", "Modules/RouteArrowPresenter",
        "Modules/NameplateGenerations", "Modules/ArrowDemoTelemetry", "Modules/ArrowDemo",
        "Alignment/RouteSignature", "Alignment/ExecutionEpisodeTracker",
        "Alignment/RoutePullCandidateScorer", "Alignment/RouteAlignment",
    }
    for _, c in ipairs(conocidos) do
        truthy(enToc["MitzuRouteArrows/" .. c .. ".lua"], "en el .toc: " .. c)
    end
    equal(#ficherosMRA(), #conocidos, "ni uno de mas")
end)

-- ── I ──────────────────────────────────────────────────────────────────────

test("I1 barras, subcomandos y teclas de los dos addons no colisionan", function()
    S.isolated(function()
        local env = S.boot({ withRouteArrows = true })
        sinErrores(env, "arranque")
        local duenoDe = {}
        for k, v in pairs(_G) do
            if type(k) == "string" and type(v) == "string" then
                local clave = k:match("^SLASH_(.-)%d+$")
                if clave then
                    local barra = v:lower()
                    if duenoDe[barra] and duenoDe[barra] ~= clave then
                        error(barra .. " registrada por " .. duenoDe[barra] .. " y " .. clave)
                    end
                    duenoDe[barra] = clave
                end
            end
        end
        truthy(duenoDe["/emp"] and duenoDe["/emp"] ~= "MITZUROUTEARROWS", "/emp es del core")
        truthy(duenoDe["/mitzumplus"] and duenoDe["/mitzumplus"] ~= "MITZUROUTEARROWS", "/mitzumplus es del core")
        equal(duenoDe["/mra"], "MITZUROUTEARROWS", "/mra es de MRA")
        equal(duenoDe["/mitzuroutearrows"], "MITZUROUTEARROWS", "/mitzuroutearrows es de MRA")
        equal(type(SlashCmdList["MITZUROUTEARROWS"]), "function", "manejador de /mra")

        local MRA = _G.MitzuRouteArrows
        local lista = {}
        for _, c in ipairs(MRA.Commands:List()) do lista[c] = true end
        for _, c in ipairs({ "status", "alignment", "alignmentdetail", "evidence", "eventcast",
                             "castevidence", "plates", "debug" }) do
            truthy(lista[c], "/mra " .. c)
        end

        -- /mra atiende por la barra real de WoW.
        local desde = #env.WoW.printed
        SlashCmdList["MITZUROUTEARROWS"]("status")
        truthy(impresoDesde(env, desde):find("[MRA]", 1, true), "/mra status por SlashCmdList")
    end)
end)

test("I2 los nombres de binding de los dos Bindings.xml son disjuntos", function()
    local function nombres(xml)
        local out = {}
        for n in Src.read(xml):gsub("<!%-%-.-%-%->", ""):gmatch("<Binding%s+name%s*=%s*\"([^\"]+)\"") do
            out[n] = true
        end
        return out
    end
    local core, mra = nombres("MitzuMPlus/Bindings.xml"), nombres("MitzuRouteArrows/Bindings.xml")
    local nCore = 0
    for n in pairs(core) do
        nCore = nCore + 1
        equal(mra[n], nil, "binding en los dos: " .. n)
    end
    truthy(nCore > 0, "el core tiene teclas")
    truthy(mra["MITZUMPLUS_ROUTE_MARK_TARGET"], "la tecla de marcar conserva su nombre en MRA")
end)

if #failures > 0 then
    error(string.format("HostIsolation: %d tests, %d assertions, %d failures\n%s",
        tests, assertions, #failures, table.concat(failures, "\n")), 0)
end

return { tests = tests, assertions = assertions }
