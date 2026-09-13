-- MitzuMPlus (core): Coach HUD V2 contra el core REAL cargado por su .toc.
-- No se carga desde el TOC. Ejecutar con: python tests/run_lua_tests.py
--
--   A  visibilidad por ciclo de vida (DungeonContext, no challengeMapID)
--   B  el HUD refleja RouteProgress (comandos, teclas, SetPull)
--   C  el HUD no puede escribir RouteProgress
--   D  /reload reconstruye el HUD desde el estado recuperado, sin comandos
--   E  el HUD no es una segunda autoridad del pull
--   F  la vista previa no modifica ningún estado real
--   +  configuración (escala, alfa, bloqueo, aplazado en combate, migración)

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
local Src = dofile("tests/harness/lua_source.lua")

local function sinErrores(env, label)
    for _, e in ipairs(env.WoW.errors) do env.errors[#env.errors + 1] = "runtime: " .. e end
    env.WoW.errors = {}
    if #env.errors > 0 then
        error(label .. ": " .. table.concat(env.errors, "\n", 1, math.min(#env.errors, 6)), 2)
    end
    assertions = assertions + 1
end

local function MP() return rawget(_G, "MitzuMPlus") end
local function HUD() return MP().CoachHUD end
local function texto(campo) local f = HUD()._frame; return f and f[campo] and f[campo]:GetText() end
local function fila(key) local f = HUD()._frame; return f and f.rows[key].value:GetText() end

-- Estado REAL que el HUD no debe tocar nunca.
local function estadoReal()
    local M = MP()
    local RS = M.RunSession
    local mdb = S.deepCopy(rawget(_G, "MitzuMPlusDB") or {})
    -- La caja negra de QA y los ajustes del propio HUD no son estado de juego.
    if type(mdb.global) == "table" then mdb.global.qaFlight = nil end
    return table.concat({
        tostring(M.DungeonContext:GetState()),
        tostring(M.RouteProgress:GetState()), tostring(M.RouteProgress:GetPullIndex()),
        tostring(M.RouteProgress:GetRoute()), tostring(M.RouteProgress:WasRecovered()),
        tostring(RS:GetState()), tostring(RS:GetReason()), tostring(RS:IsDecided()),
        S.serialize(RS:GetSnapshot()),
        S.serialize(rawget(_G, "MPlusAdaptiveRouteDB")),
        tostring(rawget(_G, "MitzuMPlusCurrentRun")),
    }, "\n")
end

-- ── A ──────────────────────────────────────────────────────────────────────

test("A1 OUTSIDE oculto, PRE_KEY preparación, RUNNING completo", function()
    S.isolated(function()
        local env = S.boot({})
        sinErrores(env, "arranque")
        equal(HUD():GetMode(), "HIDDEN", "OUTSIDE: modo")
        equal(HUD():IsVisible(), false, "OUTSIDE: no visible")

        S.enterRuby(env)
        equal(MP().DungeonContext:GetState(), "PRE_KEY", "entrada sin piedra")
        equal(HUD():GetMode(), "PREPARE", "PRE_KEY: modo")
        truthy(HUD():IsVisible(), "PRE_KEY: visible")
        equal(texto("pull"), "PULL 1 / 11", "PRE_KEY: pull preparado")
        equal(texto("clock"), "PREPARACIÓN", "PRE_KEY: etiqueta")
        equal(HUD():IsTickerActive(), false, "PRE_KEY: sin ticker")

        S.startKey(env, { level = 12 })
        equal(HUD():GetMode(), "RUN", "RUNNING: modo")
        truthy(texto("header"):find("+12", 1, true), "cabecera con nivel: " .. tostring(texto("header")))
        truthy(texto("header"):find("ESTANQUES", 1, true), "cabecera con mazmorra")
        truthy(HUD():IsTickerActive(), "RUNNING: ticker del reloj")
        truthy(texto("clock"):find("/ 30:00", 1, true), "reloj con límite: " .. tostring(texto("clock")))
        truthy(fila("now"):find("mobs", 1, true), "fila AHORA")
        truthy(fila("next"):find("mobs", 1, true), "fila SIGUIENTE")
        sinErrores(env, "escenario")
    end)
end)

test("A2 el reloj avanza con el ticker sin reconstruir la vista", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        local antes = texto("clock")
        local reason = HUD():GetLastRefreshReason()
        env.WoW.advance(1)
        local despues = texto("clock")
        truthy(antes ~= despues, "el reloj cambia: " .. tostring(antes) .. " -> " .. tostring(despues))
        -- En un tick impar solo se toca el reloj: no hay refresco completo.
        equal(HUD():GetLastRefreshReason(), reason, "tick impar no refresca el modelo")
        env.WoW.advance(1)
        equal(HUD():GetLastRefreshReason(), "TICK", "tick par refresca fuerzas y Coach")
        sinErrores(env, "ticks")
    end)
end)

test("A3 COMPLETED muestra resumen y se oculta solo; el ticker se detiene", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        env.WoW.state.challengeActive = false
        env.WoW.fire("CHALLENGE_MODE_COMPLETED")
        equal(MP().DungeonContext:GetState(), "COMPLETED", "estado")
        equal(HUD():GetMode(), "SUMMARY", "resumen")
        equal(texto("clock"), "COMPLETADA", "etiqueta de resumen")
        equal(HUD():IsTickerActive(), false, "sin ticker en el resumen")
        env.WoW.advance(HUD().SUMMARY_SECONDS + 1)
        equal(HUD():GetMode(), "HIDDEN", "oculto tras el resumen")
        equal(HUD():IsVisible(), false, "no visible")
        sinErrores(env, "completar")
    end)
end)

test("A4 RESET oculta; salir de la mazmorra oculta y deja la ruta inactiva", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        env.WoW.fire("CHALLENGE_MODE_RESET")
        equal(MP().DungeonContext:GetState(), "RESET", "estado RESET")
        equal(HUD():GetMode(), "HIDDEN", "RESET oculta")
        env.WoW.state.challengeActive = false
        S.leaveDungeon(env)
        equal(MP().DungeonContext:GetState(), "OUTSIDE", "fuera")
        equal(HUD():IsVisible(), false, "fuera: oculto")
        equal(MP().RouteProgress:GetState(), "INACTIVE", "ruta descargada")
        sinErrores(env, "reset")
    end)
end)

test("A5 desactivado no se muestra; showPreKey=false oculta la preparación", function()
    S.isolated(function()
        local env = S.boot({})
        HUD():SetOption("showPreKey", false)
        S.enterRuby(env)
        equal(HUD():GetMode(), "HIDDEN", "PRE_KEY oculto por ajuste")
        S.startKey(env)
        equal(HUD():GetMode(), "RUN", "RUNNING sigue mostrándose")
        HUD():SetEnabled(false)
        equal(HUD():IsVisible(), false, "desactivado")
        equal(HUD():ReplacesClassicOverlay(), false, "desactivado no reemplaza el overlay clásico")
        HUD():SetEnabled(true)
        truthy(HUD():IsVisible(), "reactivado")
        equal(HUD():ReplacesClassicOverlay(), true, "por defecto reemplaza el overlay clásico")
        sinErrores(env, "ajustes")
    end)
end)

-- ── B ──────────────────────────────────────────────────────────────────────

test("B1 /emp next, /emp prev, /emp pull N y SetPull se reflejan al instante", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        local M = MP()
        M:HandleSlashCommand("next")
        equal(HUD():GetDisplayedPull(), 2, "tras next")
        equal(texto("pull"), "PULL 2 / 11", "texto tras next")
        M:HandleSlashCommand("pull 7")
        equal(HUD():GetDisplayedPull(), 7, "tras pull 7")
        M:HandleSlashCommand("prev")
        equal(HUD():GetDisplayedPull(), 6, "tras prev")
        M.RouteProgress:SetPull(11, "TEST")
        equal(texto("pull"), "PULL 11 / 11", "último pull")
        equal(fila("next"), "último pull de la ruta", "sin siguiente")
        -- El porcentaje es el PLANIFICADO por la ruta, calculado desde sus datos
        -- (Ruby suma 546 de 551 tropas: 99%), no un 100% supuesto.
        local route, suma = M.RouteProgress:GetRoute(), 0
        for _, p in ipairs(route.pulls) do suma = suma + (p.count or 0) end
        equal(texto("routePct"), string.format("RUTA %d%%", math.floor(suma * 100 / route.totalForces + 0.5)),
            "porcentaje planificado de la ruta completa")
        sinErrores(env, "comandos")
    end)
end)

test("B2 las teclas de siguiente/anterior pull mueven la autoridad y el HUD", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        MitzuMPlus_RouteNextPullBinding()
        MitzuMPlus_RouteNextPullBinding()
        equal(MP().RouteProgress:GetPullIndex(), 3, "RouteProgress avanzado por la tecla")
        equal(HUD():GetDisplayedPull(), 3, "HUD sigue a la tecla")
        MitzuMPlus_RoutePreviousPullBinding()
        equal(MP().RouteProgress:GetPullIndex(), 2, "retrocede")
        equal(HUD():GetDisplayedPull(), 2, "HUD retrocede")
        sinErrores(env, "teclas")
    end)
end)

test("B3 con ruta adaptativa indexada el navegador sigue a RouteProgress", function()
    S.isolated(function()
        local env = S.boot({})
        S.seedAdaptiveProfile(399)
        S.enterRubyAndStartKey(env)
        local PN = MP().AdaptiveRoute.PullNavigator
        MitzuMPlus_RouteNextPullBinding()
        equal(MP().RouteProgress:GetPullIndex(), 2, "autoridad")
        equal(PN:GetCurrentPull(), 2, "navegador sincronizado por evento")
        equal(HUD():GetDisplayedPull(), 2, "HUD")
        sinErrores(env, "navegador")
    end)
end)

-- ── C ──────────────────────────────────────────────────────────────────────

local ESCRITORES = { "SetPull", "NextPull", "PreviousPull", "RestorePull", "SetCurrentPull",
                     "Prepare", "Start", "Complete", "Begin", "UpdatePull", "TryRestore",
                     "TryRecoverWhenReady", "_Transition", "Emit", "LoadForDungeon", "Unload",
                     "SetSelectedRoute" }

test("C1 el código del HUD, del adaptador PullHUD y de QA no nombra escritores", function()
    for _, ruta in ipairs({ "MitzuMPlus/modules/CoachHUD.lua", "MitzuMPlus/modules/AdaptiveRoute/PullHUD.lua",
                            "MitzuMPlus/modules/CoachAdvice.lua", "MitzuMPlus/modules/QA/Invariants.lua",
                            "MitzuMPlus/modules/QA/BugReport.lua", "MitzuMPlus/modules/QA/FlightRecorder.lua",
                            "MitzuMPlus/modules/QA/SafeValue.lua" }) do
        local ids = Src.identifiers(Src.read(ruta))
        for _, w in ipairs(ESCRITORES) do
            if ids[w] then error(ruta .. " nombra el escritor " .. w) end
        end
        for _, api in ipairs({ "C_NamePlate", "UnitGUID", "NAME_PLATE_UNIT_ADDED", "CombatLogGetCurrentEventInfo" }) do
            if ids[api] then error(ruta .. " toca " .. api .. " (el HUD no escanea placas ni mobs)") end
        end
        assertions = assertions + 1
    end
end)

test("C2 refrescos, ticks y modelo no cambian el estado real", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        MP():HandleSlashCommand("next")
        local antes = estadoReal()
        for _ = 1, 25 do HUD():Refresh("TEST") end
        for _ = 1, 5 do HUD():BuildModel() end
        HUD():_OnTick(); HUD():_OnTick()
        equal(estadoReal(), antes, "estado real intacto")
        sinErrores(env, "refrescos")
    end)
end)

-- ── D ──────────────────────────────────────────────────────────────────────

test("D1 pull 4 -> /reload -> SESSION_MATCH: el HUD muestra 4 sin ningún comando", function()
    local saved = S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env, { level = 2 })
        for _ = 1, 3 do MP():HandleSlashCommand("next") end
        equal(HUD():GetDisplayedPull(), 4, "antes del reload")
        return S.captureForReload(env)
    end)
    S.isolated(function()
        local env = S.bootAfterReload(saved, { timerDelay = 3 })
        -- Mientras RunSession espera el cronómetro, el HUD no pinta un pull falso.
        equal(HUD():GetMode(), "RUN", "RUNNING tras el login")
        equal(HUD():IsRecovering(), true, "esperando la decisión de la sesión")
        equal(HUD():GetDisplayedPull(), nil, "sin número mientras se decide")
        equal(texto("pull"), "PULL — / 11", "texto de espera")
        truthy(fila("status"):find("recuperando", 1, true), "estado de recuperación visible")

        env.WoW.advance(5)
        equal(MP().RunSession:GetState(), "RESTORED", "sesión restaurada")
        equal(MP().RouteProgress:GetPullIndex(), 4, "autoridad en 4")
        equal(HUD():GetDisplayedPull(), 4, "HUD en 4")
        equal(texto("pull"), "PULL 4 / 11", "texto")
        equal(HUD():IsRecovering(), false, "ya no espera")
        truthy(fila("status") == nil or fila("status") == "" or not HUD()._frame.rows.status.value:IsShown()
               or fila("status"):find("recuperado", 1, true), "sin estado de espera")
        local marcos = 0
        for _, f in ipairs(env.WoW.frames) do
            if f.__name == "MitzuMPlusCoachHUD" then marcos = marcos + 1 end
        end
        equal(marcos, 1, "un único frame de HUD (sin duplicados)")
        for _, l in ipairs(env.WoW.printed) do
            truthy(not l:find("/emp hud", 1, true) or l:find("Activa", 1, true), "sin necesidad de /emp hud")
        end
        MP():HandleSlashCommand("next")
        equal(HUD():GetDisplayedPull(), 5, "tras la recuperación next sigue funcionando")
        sinErrores(env, "reload")
    end)
end)

-- ── E ──────────────────────────────────────────────────────────────────────

test("E1 el HUD no guarda el pull como estado: lo que pinta sale siempre de RouteProgress", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        local M = MP()
        -- Se falsea la memoria de la vista: el siguiente refresco la corrige.
        HUD()._displayed.pull = 9
        equal(M.RouteProgress:GetPullIndex(), 1, "la autoridad no se entera")
        HUD():Refresh("TEST")
        equal(HUD():GetDisplayedPull(), 1, "el refresco vuelve a la autoridad")
        -- Ningún campo del módulo contiene el pull fuera de la memoria de vista.
        for k, v in pairs(HUD()) do
            if type(k) == "string" and k:lower():find("pull") and k ~= "_displayed" then
                truthy(type(v) == "function", "campo de pull que no es método: " .. k)
            end
        end
        local model = HUD():BuildModel()
        truthy(model ~= HUD()._displayed, "el modelo es nuevo en cada refresco")
        sinErrores(env, "autoridad")
    end)
end)

-- ── F ──────────────────────────────────────────────────────────────────────

test("F1 /emp hud test: datos MOCK marcados PREVIEW, sin tocar nada real", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        MP():HandleSlashCommand("next")
        local antes = estadoReal()
        MP():HandleSlashCommand("hud test")
        equal(HUD():IsPreview(), true, "preview activo")
        truthy(fila("status"):find("PREVIEW", 1, true), "indicación PREVIEW visible")
        equal(texto("pull"), "PULL 4 / 11", "datos de ejemplo")
        truthy(texto("header"):find("PRUEBA", 1, true), "cabecera de prueba")
        env.WoW.advance(4)
        equal(estadoReal(), antes, "preview no cambia el estado real")
        MP():HandleSlashCommand("hud test off")
        equal(HUD():IsPreview(), false, "preview desactivado")
        equal(HUD():GetDisplayedPull(), 2, "vuelve el estado real")
        equal(estadoReal(), antes, "tras salir, intacto")
        sinErrores(env, "preview")
    end)
end)

test("F2 preview fuera de mazmorra y auto-apagado al arrancar una llave real", function()
    S.isolated(function()
        local env = S.boot({})
        local antes = estadoReal()
        HUD():SetPreview(true)
        truthy(HUD():IsVisible(), "preview visible fuera de mazmorra")
        equal(MP().DungeonContext:GetState(), "OUTSIDE", "sigue fuera")
        equal(estadoReal(), antes, "nada real cambia")
        S.enterRubyAndStartKey(env)
        equal(HUD():IsPreview(), false, "la llave real apaga el preview")
        equal(HUD():GetDisplayedPull(), 1, "estado real")
        sinErrores(env, "preview2")
    end)
end)

-- ── Configuración ─────────────────────────────────────────────────────────

test("G1 escala/alfa acotadas, bloqueo, compacto y posición", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        local M = MP()
        M:HandleSlashCommand("hud scale 5")
        equal(HUD():Settings().scale, 2.0, "escala acotada a 2")
        M:HandleSlashCommand("hud alpha 0")
        equal(HUD():Settings().alpha, 0.2, "alfa acotada a 0.2")
        M:HandleSlashCommand("hud lock")
        equal(HUD():Settings().locked, true, "bloqueado")
        M:HandleSlashCommand("hud compact")
        equal(HUD():Settings().compact, true, "compacto")
        equal(HUD()._frame.rows.now.value:IsShown(), false, "compacto oculta AHORA")
        M:HandleSlashCommand("hud compact off")
        equal(HUD()._frame.rows.now.value:IsShown(), true, "normal vuelve a mostrarla")
        HUD():Settings().point = "LEFT"
        M:HandleSlashCommand("hud reset")
        equal(HUD():Settings().point, nil, "posición restablecida")
        M:HandleSlashCommand("hud status")
        M:HandleSlashCommand("hud off")
        equal(HUD():IsVisible(), false, "off")
        M:HandleSlashCommand("hud on")
        truthy(HUD():IsVisible(), "on")
        sinErrores(env, "config")
    end)
end)

test("G2 en combate los ajustes se aplazan hasta PLAYER_REGEN_ENABLED", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        env.WoW.state.inCombat = true
        HUD():SetOption("scale", 1.5)
        equal(HUD()._pendingApply, true, "aplazado en combate")
        env.WoW.state.inCombat = false
        env.WoW.fire("PLAYER_REGEN_ENABLED")
        equal(HUD()._pendingApply, false, "aplicado al salir de combate")
        sinErrores(env, "combate")
    end)
end)

test("G3 la posición del PullHUD antiguo se copia sin borrar el original", function()
    S.isolated(function()
        local env = S.boot({ savedVariables = { MPlusAdaptiveRouteDB = {
            settings = { pullHudPoint = "TOPLEFT", pullHudX = 40, pullHudY = -60, pullHudShown = true } } } })
        local h = HUD():Settings()
        equal(h.point, "TOPLEFT", "punto migrado")
        equal(h.x, 40, "x migrada")
        equal(h.y, -60, "y migrada")
        equal(rawget(_G, "MPlusAdaptiveRouteDB").settings.pullHudPoint, "TOPLEFT", "el original sigue")
        -- El adaptador PullHUD sigue existiendo y delega en el HUD V2.
        local PH = MP().AdaptiveRoute.PullHUD
        truthy(PH and PH.Toggle, "AR.PullHUD conserva su interfaz")
        equal(PH:Toggle(), false, "Toggle desactiva el HUD V2")
        equal(PH:Toggle(), true, "Toggle lo reactiva")
        equal(rawget(_G, "MitzuMPlusPullHUD"), nil, "ya no se crea el frame antiguo")
        sinErrores(env, "migracion")
    end)
end)

test("G4 el overlay clásico consulta al HUD V2 para no duplicarse", function()
    local src = Src.code(Src.read("MitzuMPlus/modules/UI_Overlay_v2.lua"))
    truthy(src:find("ReplacesClassicOverlay", 1, true), "el overlay pregunta al HUD")
    local main = Src.read("MitzuMPlus/MitzuMPlus_main.lua")
    truthy(main:find("replaceClassic%s*=%s*true"), "default compatible replaceClassic")
    truthy(not Src.code(Src.read("MitzuMPlus/modules/CoachHUD.lua")):find("overlayEnabled", 1, true),
        "el HUD no toca la preferencia overlayEnabled")
end)

test("G5 la ventana principal construye todas sus pestañas y el panel Coach controla el HUD", function()
    S.isolated(function()
        local env = S.boot({})
        S.enterRubyAndStartKey(env)
        local M = MP()
        M:ToggleWindow()
        env.WoW.advance(1)
        for _, tab in ipairs({ "historial", "stats", "players", "coach", "settings" }) do
            local ok, err = pcall(M.ShowTab, M, tab)
            truthy(ok, "pestaña " .. tab .. ": " .. tostring(err))
            env.WoW.advance(1.1)
        end
        for _, panel in ipairs({ "PanelHistorial", "PanelStats", "PanelPlayers", "PanelCoach", "PanelConfig" }) do
            truthy(M[panel], "panel " .. panel .. " cargado")
        end
        local PC = M.PanelCoach
        truthy(PC.hudState, "bloque COACH HUD V2 construido")
        PC:Refresh()
        truthy(PC.hudState.value:GetText():find("RUN", 1, true), "estado del HUD en el panel: " .. tostring(PC.hudState.value:GetText()))
        equal(PC.hudPull.value:GetText(), "1 / 1", "pull mostrado / de la ruta")
        -- Los botones del bloque solo llaman a la vista.
        local antesPull = M.RouteProgress:GetPullIndex()
        HUD():SetPreview(true); PC:Refresh()
        truthy(PC.hudState.value:GetText():find("PREVIEW", 1, true), "el panel ve la vista previa")
        HUD():SetPreview(false)
        equal(M.RouteProgress:GetPullIndex(), antesPull, "el panel no mueve el pull")
        sinErrores(env, "ventana")
    end)
end)

if #failures > 0 then
    error(string.format("CoachHUD: %d tests, %d assertions, %d failures\n%s",
        tests, assertions, #failures, table.concat(failures, "\n")), 0)
end

return { tests = tests, assertions = assertions }
