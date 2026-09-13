-- MitzuMPlus (core): Bug Report V2, caja negra de QA, saneado e invariantes.
-- No se carga desde el TOC. Ejecutar con: python tests/run_lua_tests.py
--
--   G  el informe sale completo con todos los módulos
--   H  el informe sale con módulos nil
--   I  el informe sobrevive a errores internos simulados y datos corruptos
--   J  saneado de valores problemáticos (secretos, rutas, BattleTags, "|")
--   K  la caja negra respeta su límite, funde repetidos y sobrevive al /reload
--   L  los invariantes detectan estados inconsistentes fabricados a mano

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

local SECCIONES = { "BUILD", "CONTEXT", "PLAYER", "PARTY", "ROUTE", "SESSION", "HUD", "COACH",
                    "CAPABILITIES", "INVARIANTS", "RECENT EVENTS", "ERRORS" }

local function MP() return rawget(_G, "MitzuMPlus") end

local function seccion(report, nombre)
    return report:match("%[" .. nombre:gsub("%s", "%%s") .. "%]\n(.-)\n\n") or
           report:match("%[" .. nombre:gsub("%s", "%%s") .. "%]\n(.-)\nsectionsFailed")
end

local function copiable(report, label)
    equal(report:find("|", 1, true), nil, label .. ": sin '|' (escape de la caja de copia)")
    equal(report:find("SECTION_ERROR", 1, true) ~= nil and label:find("roto") == nil, false,
        label .. ": sin secciones rotas")
end

-- ── G ──────────────────────────────────────────────────────────────────────

test("G1 con todo cargado y una llave en marcha, el informe tiene todas las secciones", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env, { level = 2 })
        MP():HandleSlashCommand("next")
        local r = MP().BugReport:Build()
        truthy(r:find("^=== MitzuMPlus Bug Report ===\n"), "cabecera")
        truthy(r:find("\n=== END ===$"), "cierre")
        for _, nombre in ipairs(SECCIONES) do
            truthy(r:find("[" .. nombre .. "]", 1, true), "sección " .. nombre)
        end
        truthy(r:find("ReportVersion=2", 1, true), "versión del informe")
        truthy(r:find("Addon=7.14.0-rc1", 1, true), "versión del addon")
        truthy(r:find("Interface=120100", 1, true), "interface")
        truthy(r:find("lifecycle=RUNNING", 1, true), "ciclo de vida")
        truthy(r:find("keystoneLevel=2", 1, true), "nivel")
        truthy(r:find("routeID=mitzu_399_standard", 1, true), "ruta")
        truthy(r:find("source=BUNDLED_NATIVE", 1, true), "fuente de ruta")
        truthy(r:find("\npull=2/11", 1, true), "pull")
        truthy(r:find("matchState=", 1, true), "sesión")
        truthy(r:find("displayedPull=2", 1, true) and r:find("authoritativePull=2", 1, true), "HUD vs autoridad")
        truthy(r:find("combatLog=UNAVAILABLE", 1, true), "capacidades")
        truthy(r:find("sectionsFailed=none", 1, true), "ninguna sección falla")
        local inv = seccion(r, "INVARIANTS")
        truthy(inv and inv:find("FAIL=0", 1, true), "sin invariantes en FAIL:\n" .. tostring(inv))
        truthy(r:find("ROUTE ; PULL ; from=1 reason=MANUAL to=2", 1, true), "caja negra con el cambio de pull")
        truthy(r:find("addon.MitzuRouteArrows=absent", 1, true), "MitzuRouteArrows ausente")
        copiable(r, "completo")
        env.WoW.errors = {}
    end)
end)

test("G2 privacidad: sin nombre del personaje, reino, GUID ni rutas locales", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        local r = MP().BugReport:Build()
        for _, prohibido in ipairs({ "Mitzuky", "EldreThalas", "Eldre'Thalas", "Player-1-0001", "WTF/Account/" }) do
            equal(r:find(prohibido, 1, true), nil, "no aparece " .. prohibido)
        end
        truthy(r:find("player=class=", 1, true), "el grupo sale por token de unidad")
    end)
end)

test("G3 /emp bugreport abre la caja de copia sin cerrarse sola; status y clear", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        local M = MP()
        M:HandleSlashCommand("bugreport")
        local cf = M._clipboardFrame
        truthy(cf and cf:IsShown(), "caja de copia visible")
        truthy(cf.editBox:GetText():find("=== MitzuMPlus Bug Report ===", 1, true), "con el informe")
        equal(cf.title:GetText(), "MITZUMPLUS · BUG REPORT", "título propio")
        truthy(cf.clearBtn:IsShown(), "botón de limpiar logs visible")
        env.WoW.advance(90)
        truthy(cf:IsShown(), "no se cierra sola a los 60 s")
        M:HandleSlashCommand("bugreport status")
        M:HandleSlashCommand("bugreport text")
        local impreso = table.concat(env.WoW.printed, "\n")
        truthy(impreso:find("invariants PASS=", 1, true), "resumen en el chat")
        M:HandleSlashCommand("bugreport clear")
        local lines = M.FlightRecorder:Lines()
        equal(#lines, 1, "caja negra limpia (queda la marca CLEARED)")
        truthy(lines[1]:find("CLEARED", 1, true), "marca de limpieza")
        -- Export normal conserva su comportamiento (título y auto-cierre).
        M.Export:CopyToClipboard("datos")
        equal(cf.title:GetText(), "EXPORTAR DATOS", "exportar mantiene su título")
        equal(cf.clearBtn:IsShown(), false, "exportar no muestra limpiar")
        env.WoW.advance(61)
        equal(cf:IsShown(), false, "exportar se cierra a los 60 s como siempre")
        env.WoW.errors = {}
    end)
end)

-- ── H ──────────────────────────────────────────────────────────────────────

test("H1 con módulos nil el informe sale entero y dice qué falta", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        local M = MP()
        for _, nombre in ipairs({ "RouteManager", "RouteProgress", "RunSession", "PartyProfiler",
                                  "CoachHUD", "DungeonContext", "ChallengeClock", "KeystoneTracker",
                                  "PredictionEngine", "RuntimeCapabilities", "ErrorLogger",
                                  "FlightRecorder", "QAInvariants", "CoachAdvice" }) do
            M[nombre] = nil
        end
        M.AdaptiveRoute = nil
        local r = M.BugReport:Build()
        for _, nombre in ipairs(SECCIONES) do
            truthy(r:find("[" .. nombre .. "]", 1, true), "sección " .. nombre)
        end
        truthy(r:find("sectionsFailed=none", 1, true), "sin secciones rotas: " .. (r:match("sectionsFailed=[^\n]*") or ""))
        truthy(r:find("DungeonContext=MODULE_NIL", 1, true), "dice que falta DungeonContext")
        truthy(r:find("CoachHUD=MODULE_NIL", 1, true), "dice que falta el HUD")
        truthy(r:find("=== END ===", 1, true), "cierre")
    end)
end)

-- ── I ──────────────────────────────────────────────────────────────────────

test("I1 métodos que lanzan, datos corruptos y SavedVariables a medias", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        local M = MP()
        local function boom() error("fallo simulado") end
        M.RouteManager.GetActiveRoute = boom
        M.RouteProgress.GetPullIndex = boom
        M.DungeonContext.GetState = boom
        M.PartyProfiler.GetMembers = function() return { "no soy tabla", { unitToken = "party1|cff" } } end
        M.RunSession.GetSnapshot = function() return { startedAt = "x", updatedAt = {}, pullIndex = boom } end
        M.CoachHUD.Settings = boom
        M.db.global.errorLog = { "entrada corrupta", { msg = { tabla = true }, time = "ayer", count = "?" } }
        local ok, r = pcall(M.BugReport.Build, M.BugReport)
        equal(ok, true, "Build no lanza")
        for _, nombre in ipairs(SECCIONES) do
            truthy(r:find("[" .. nombre .. "]", 1, true), "sección " .. nombre)
        end
        truthy(r:find("=== END ===", 1, true), "cierre")
        equal(r:find("|", 1, true), nil, "sigue siendo copiable")
        -- Una sección que lanza entera no se lleva a las demás.
        table.insert(M.BugReport.SECTIONS, 3, { "ROTA", function() error("sección rota") end })
        r = M.BugReport:Build()
        truthy(r:find("SECTION_ERROR=", 1, true), "la sección rota lo dice")
        truthy(r:find("sectionsFailed=ROTA", 1, true), "y se lista")
        truthy(r:find("[ROUTE]", 1, true) and r:find("[ERRORS]", 1, true), "las demás siguen")
        table.remove(M.BugReport.SECTIONS, 3)
        env.WoW.errors = {}
    end)
end)

test("I2 un error de la caja de copia cae a impresión en el chat", function()
    S.isolated(function()
        local env = S.boot({})
        local M = MP()
        M.Export.CopyToClipboard = function() error("UI rota") end
        local ok, shown = pcall(M.BugReport.Show, M.BugReport)
        equal(ok, true, "Show no lanza")
        equal(shown, false, "no se pudo mostrar")
        truthy(table.concat(env.WoW.printed, "\n"):find("=== MitzuMPlus Bug Report ===", 1, true),
            "el informe sale por el chat")
    end)
end)

-- ── J ──────────────────────────────────────────────────────────────────────

test("J1 valores secretos, conversiones que fallan y datos privados", function()
    S.isolated(function()
        S.boot({})
        local Safe = MP().QASafe
        local SECRETO_NUM = setmetatable({}, {})
        local SECRETO_STR = "texto-secreto"
        issecretvalue = function(v) return v == SECRETO_NUM or v == SECRETO_STR end
        equal(Safe.Text(SECRETO_NUM), "SECRET", "tabla secreta")
        equal(Safe.Text(SECRETO_STR), "SECRET", "string secreto")
        equal(Safe.Number(SECRETO_STR), nil, "un número secreto no es utilizable")
        issecretvalue = function() error("la pregunta falla") end
        equal(Safe.Text("cualquiera"), "SECRET", "si preguntar falla, se trata como secreto")
        issecretvalue = function() return false end

        equal(Safe.Text(nil), "nil", "nil")
        equal(Safe.Text(true), "true", "booleano")
        equal(Safe.Text(12), "12", "entero")
        equal(Safe.Text(0 / 0), "NaN", "NaN")
        equal(Safe.Text(math.huge), "inf", "infinito")
        equal(Safe.Text(3.14159), "3.142", "decimal")
        equal(Safe.Text(function() end), "<function>", "función sin dirección de memoria")
        equal(Safe.Text({}), "<table>", "tabla sin dirección de memoria")
        equal(Safe.Text("|cFFff0000rojo|r"), "/cFFff0000rojo/r", "sin escapes de la caja de copia")
        equal(Safe.Text("a\nb\tc"), "a b c", "sin saltos de línea dentro de un valor")
        equal(Safe.Text([[C:\Users\pc\World of Warcraft\_retail_\Interface\AddOns\MitzuMPlus\Init.lua:12: x]]),
            "AddOns/MitzuMPlus\\Init.lua:12: x", "ruta local recortada a AddOns")
        truthy(not Safe.Text([[D:\privado\clave.txt]]):find("privado", 1, true), "otra ruta local redactada")
        truthy(Safe.Text("de Mitzu#12345 para"):find("REDACTED", 1, true), "BattleTag")
        truthy(Safe.Text("guid Player-1234-0ABCDEF9"):find("REDACTED", 1, true), "GUID de jugador")
        truthy(Safe.Text("WTF/Account/863861494#1/SavedVariables"):find("REDACTED", 1, true), "cuenta de WTF")
        equal(#Safe.Text(string.rep("x", 1000)), Safe.MAX_LEN + 3, "longitud acotada")
        local ok, motivo = Safe.Call(function() error({ raro = true }) end)
        equal(ok, false, "Call protege")
        equal(motivo, "<table>", "el motivo también se sanea")
    end)
end)

test("J2 un informe con valores secretos en las autoridades sigue siendo copiable", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        local M = MP()
        local SECRETO = setmetatable({}, { __tostring = function() error("no se deja convertir") end,
                                           __concat = function() error("no se deja concatenar") end })
        issecretvalue = function(v) return v == SECRETO end
        M.DungeonContext.GetDungeonName = function() return SECRETO end
        M.KeystoneTracker.GetOfficialSnapshot = function()
            return { enemyPct = SECRETO, enemyTotal = SECRETO, deaths = SECRETO }
        end
        M.ChallengeClock.GetElapsed = function() return SECRETO end
        local r = M.BugReport:Build()
        truthy(r:find("dungeonName=SECRET", 1, true), "nombre secreto marcado")
        truthy(r:find("enemyPct=SECRET", 1, true), "fuerzas secretas marcadas")
        truthy(r:find("sectionsFailed=none", 1, true), "ninguna sección falla por un secreto")
        -- Y el HUD tampoco rompe ni pinta el secreto.
        local okR = M.CoachHUD:Refresh("TEST_SECRET")
        equal(okR, true, "el HUD degrada sin error")
        truthy(not tostring(M.CoachHUD._frame.header:GetText()):find("table:", 1, true), "sin volcar tablas")
        issecretvalue = function() return false end
        env.WoW.errors = {}
    end)
end)

-- ── K ──────────────────────────────────────────────────────────────────────

test("K1 anillo: límite, orden, fusión de repetidos", function()
    S.isolated(function()
        S.boot({})
        local FR = MP().FlightRecorder
        FR:Clear()
        local cap = FR:Capacity()
        for i = 1, cap + 57 do FR:Record("T", "E", { i = i }) end
        equal(FR:Count(), cap, "nunca pasa del límite")
        local lista = FR:Entries()
        equal(#lista, cap, "entradas")
        truthy(lista[1].d:find("i=58", 1, true), "se descartan las más antiguas: " .. tostring(lista[1].d))
        truthy(lista[#lista].d:find("i=" .. (cap + 57), 1, true), "la última es la más reciente")
        FR:Record("T", "IGUAL", { a = 1 })
        FR:Record("T", "IGUAL", { a = 1 })
        FR:Record("T", "IGUAL", { a = 1 })
        lista = FR:Entries()
        equal(lista[#lista].n, 3, "repetidos fundidos")
        truthy(FR:Lines(1)[1]:find("IGUAL x3", 1, true), "con contador en el texto")
        local ok = pcall(FR.Record, FR, nil, setmetatable({}, { __tostring = function() error("x") end }), function() end)
        equal(ok, true, "Record nunca lanza")
    end)
end)

test("K2 la caja negra sobrevive al /reload y descarta un anillo guardado corrupto", function()
    local saved = S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        MP():HandleSlashCommand("next")
        return S.captureForReload(env)
    end)
    S.isolated(function()
        S.bootAfterReload(saved)
        local lines = table.concat(MP().FlightRecorder:Lines(), "\n")
        truthy(lines:find("SESSION_START ; session=1", 1, true), "sesión anterior conservada")
        truthy(lines:find("SESSION_START ; session=2", 1, true), "sesión nueva marcada")
        truthy(lines:find("reason=MANUAL to=2", 1, true), "hechos de antes del reload")
    end)
    saved.savedVariables.MitzuMPlusDB.global.qaFlight = { schema = 1, cap = 200, head = 999, count = -4, entries = "x" }
    S.isolated(function()
        local env = S.bootAfterReload(saved)
        local lines = table.concat(MP().FlightRecorder:Lines(), "\n")
        truthy(lines:find("WARN_RING_DISCARDED", 1, true), "el anillo corrupto se descarta y se anota")
        equal(#env.errors, 0, "sin errores al cargar")
    end)
end)

test("K3 un error de Lua del addon queda en el log y en la caja negra, saneado", function()
    S.isolated(function()
        S.boot({})
        local M = MP()
        local handler
        seterrorhandler = function(fn) handler = fn end
        geterrorhandler = function() return function() end end
        M.ErrorLogger._installed = false
        M.ErrorLogger:Install()
        handler([[C:\Users\pc\Games\Interface\AddOns\MitzuMPlus\modules\CoachHUD.lua:10: boom]])
        equal(M.ErrorLogger:Count(), 1, "guardado en el log")
        local lines = table.concat(M.FlightRecorder:Lines(), "\n")
        truthy(lines:find("ERROR ; LUA_ERROR", 1, true), "en la caja negra")
        equal(lines:find("Users", 1, true), nil, "sin la ruta local")
        local r = M.BugReport:Build()
        truthy(r:find("count=1", 1, true), "el informe lo cuenta")
        equal(r:find("Users\\pc", 1, true), nil, "el informe no expone la ruta")
    end)
end)

-- ── L ──────────────────────────────────────────────────────────────────────

local function resultado(results, id)
    for _, r in ipairs(results) do if r.id == id then return r.result end end
end

test("L1 invariantes con estados inconsistentes fabricados", function()
    S.isolated(function()
        S.boot({})
        local Inv = MP().QAInvariants
        local base = {
            lifecycle = "RUNNING", challengeActive = true, pendingActivationChecks = 0,
            routeState = "ACTIVE", routePresent = true, routeID = "r1", pull = 4, pullCount = 11,
            activeRouteID = "r1", routeManagerAvailable = true,
            sessionDecided = true, snapshotExists = true, snapshotPull = 4, snapshotRouteID = "r1",
            navigatorPull = 4, navigatorCount = 11,
            hudVisible = true, hudPreview = false, hudDisplayedPull = 4, hudRecovering = false,
            experimentalInCore = {}, apiPresent = true, apiReadOnly = true,
        }
        local function con(cambios)
            local t = {}
            for k, v in pairs(base) do t[k] = v end
            for k, v in pairs(cambios) do t[k] = v end
            return Inv:Evaluate(t)
        end
        local todo = Inv:Summary(Inv:Evaluate(base))
        equal(todo.FAIL, 0, "estado coherente sin FAIL")
        equal(todo.WARN, 0, "estado coherente sin WARN")

        equal(resultado(con({ lifecycle = "PRE_KEY" }), "CHALLENGE_IMPLIES_RUNNING"), "FAIL", "llave activa en PRE_KEY")
        equal(resultado(con({ lifecycle = "PRE_KEY", pendingActivationChecks = 3 }), "CHALLENGE_IMPLIES_RUNNING"),
            "WARN", "cuenta atrás: transitorio")
        equal(resultado(con({ lifecycle = "RESET" }), "CHALLENGE_IMPLIES_RUNNING"), "WARN",
            "RESET al insertar la piedra: transitorio")
        equal(resultado(con({ challengeActive = false }), "RUNNING_IMPLIES_CHALLENGE"), "FAIL", "RUNNING sin llave")
        equal(resultado(con({ routePresent = false }), "ROUTE_STATE_HAS_ROUTE"), "FAIL", "ACTIVE sin ruta")
        equal(resultado(con({ pull = 12 }), "PULL_IN_RANGE"), "FAIL", "pull fuera de rango")
        equal(resultado(con({ activeRouteID = "r2" }), "ROUTE_MATCHES_MANAGER"), "FAIL", "rutas distintas")
        equal(resultado(con({ lifecycle = "OUTSIDE", challengeActive = false }), "OUTSIDE_NO_PROGRESS"), "FAIL",
            "progreso fuera de la mazmorra")
        equal(resultado(con({ routeState = "PREPARED" }), "RUNNING_ROUTE_ACTIVE"), "WARN", "llave sin ruta activa")
        equal(resultado(con({ snapshotPull = 2 }), "SNAPSHOT_MATCHES_PULL"), "WARN", "snapshot desincronizado")
        equal(resultado(con({ hudDisplayedPull = 3 }), "HUD_MATCHES_AUTHORITY"), "FAIL", "HUD distinto de la autoridad")
        equal(resultado(con({ hudDisplayedPull = 3, hudPreview = true }), "HUD_MATCHES_AUTHORITY"), "SKIP",
            "preview no cuenta")
        equal(resultado(con({ hudDisplayedPull = nil, hudRecovering = true }), "HUD_MATCHES_AUTHORITY"), "SKIP",
            "esperando la recuperación")
        equal(resultado(con({ hudPreview = true }), "PREVIEW_NOT_DURING_RUN"), "WARN", "preview durante la llave")
        equal(resultado(con({ navigatorPull = 1 }), "NAVIGATOR_FOLLOWS_PROGRESS"), "WARN", "navegador divergente")
        equal(resultado(con({ experimentalInCore = { "RouteArrows" } }), "NO_ROUTEARROWS_IN_CORE"), "FAIL",
            "módulo de MitzuRouteArrows en el core")
        equal(resultado(con({ apiReadOnly = false }), "PUBLIC_API_READ_ONLY"), "FAIL", "API escribible")
        local vacio = Inv:Evaluate({})
        truthy(#vacio >= 13, "sin datos no lanza")
    end)
end)

test("L2 Gather detecta de verdad un módulo experimental colado en el core", function()
    S.isolated(function()
        S.boot({})
        local M = MP()
        local Inv = M.QAInvariants
        equal(resultado(Inv:Evaluate(Inv:Gather()), "NO_ROUTEARROWS_IN_CORE"), "PASS", "limpio")
        M.AdaptiveRoute.RouteArrows = {}
        equal(resultado(Inv:Evaluate(Inv:Gather()), "NO_ROUTEARROWS_IN_CORE"), "FAIL", "detectado")
        M.AdaptiveRoute.RouteArrows = nil
        -- Gather no escribe en la API para comprobar que es de solo lectura.
        equal(next(_G.MitzuMPlusAPI), nil, "el proxy de la API sigue vacío")
    end)
end)

if #failures > 0 then
    error(string.format("BugReport: %d tests, %d assertions, %d failures\n%s",
        tests, assertions, #failures, table.concat(failures, "\n")), 0)
end

return { tests = tests, assertions = assertions }
