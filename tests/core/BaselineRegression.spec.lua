-- MitzuMPlus (core): REGRESIÓN OBLIGATORIA contra la baseline validada en vivo.
-- No se carga desde el TOC. Ejecutar con: python tests/run_lua_tests.py
--
-- Baseline: commit 05a4d77 (7.13.0-rc1), probada a mano en World of Warcraft
-- Retail 12.1.0 (build 69814, Interface 120100). Este banco reproduce, paso a
-- paso, la secuencia que se comprobó en el cliente real:
--
--   OUTSIDE
--   -> PRE_KEY dungeon 399 (sin piedra: challengeActive=false, challengeMapID=nil)
--   -> RUNNING +2 (secuencia real al insertar: RESET -> RUNNING)
--   -> pull 1 -> next -> pull 2 -> snapshotPull 2
--   -> /reload -> SESSION_MATCH -> RESTORED -> pull 2
--   -> next -> pull 3
--
-- Si un cambio futuro rompe cualquiera de estos pasos, falla aquí antes de
-- llegar a una llave de verdad. Incluye además:
--   · Detalle A: la transición PRE_KEY -> RESET -> RUNNING es la de Blizzard
--     y termina en un estado correcto (ruta ACTIVE, snapshot nuevo).
--   · Detalle B: tras avanzar, el diagnóstico conserva el pull RESTAURADO
--     (recoveryOriginalPull=2) y no lo confunde con el actual.

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

local function MP() return rawget(_G, "MitzuMPlus") end

local function sinErrores(env, label)
    for _, e in ipairs(env.WoW.errors) do env.errors[#env.errors + 1] = "runtime: " .. e end
    env.WoW.errors = {}
    if #env.errors > 0 then
        error(label .. ": " .. table.concat(env.errors, "\n", 1, math.min(#env.errors, 6)), 2)
    end
    assertions = assertions + 1
end

-- Ningún invariante en FAIL en este punto de la partida.
local function invariantesSinFail(label)
    local Inv = MP().QAInvariants
    local results = Inv:Evaluate(Inv:Gather())
    for _, r in ipairs(results) do
        if r.result == "FAIL" then error(label .. ": invariante " .. r.id .. " FAIL " .. tostring(r.detail), 2) end
    end
    assertions = assertions + 1
    return results
end

local function lineas(L)
    local t = {}
    for _, l in ipairs(L) do
        local k, v = tostring(l):match("^([%w_]+)=(.*)$")
        if k then t[k] = v end
    end
    return t
end

local capturado

test("R1 OUTSIDE -> PRE_KEY 399 sin piedra -> ruta nativa PREPARED sin MDT", function()
    capturado = S.isolated(function()
        local env = S.boot({ withMDT = false })
        sinErrores(env, "arranque")
        local M = MP()
        equal(M.DungeonContext:GetState(), "OUTSIDE", "OUTSIDE")
        invariantesSinFail("OUTSIDE")

        S.enterRuby(env)
        local DC = lineas(M.DungeonContext:StatusLines())
        equal(DC.dungeonKey, "399", "dungeonKey=399")
        equal(DC.state, "PRE_KEY", "state=PRE_KEY")
        equal(DC.challengeActive, "false", "challengeActive=false")
        equal(DC.challengeMapID, "nil", "challengeMapID=nil")
        local RM = lineas(M.RouteManager:StatusLines())
        equal(RM.routeID, "mitzu_399_standard", "ruta nativa")
        equal(RM.routeLoadSource, "BUNDLED_NATIVE", "routeLoadSource=BUNDLED_NATIVE")
        equal(RM.mdtRuntimeRequired, "false", "mdtRuntimeRequired=false")
        equal(RM.savedRouteDataRequired, "false", "savedRouteDataRequired=false")
        equal(M.RouteProgress:GetState(), "PREPARED", "RouteProgress PREPARED antes de la piedra")
        -- No reaparece el falso inicio de M+ al entrar (BUG CTX-1).
        equal(rawget(_G, "MitzuMPlusCurrentRun"), nil, "sin run antes de la piedra")
        invariantesSinFail("PRE_KEY")

        -- Detalle A: al insertar la piedra, RESET y luego START.
        S.startKey(env, { level = 2, withReset = true })
        DC = lineas(M.DungeonContext:StatusLines())
        equal(DC.state, "RUNNING", "state=RUNNING")
        equal(DC.challengeActive, "true", "challengeActive=true")
        equal(DC.challengeMapID, "399", "challengeMapID=399")
        equal(DC.keystoneLevel, "2", "keystoneLevel=2")
        equal(DC.identitySource, "ACTIVE_CHALLENGE", "identitySource=ACTIVE_CHALLENGE")
        local life = lineas(M.DungeonContext:LifecycleLines())
        equal(life.previousState, "RESET", "la piedra pasa por RESET (secuencia de Blizzard)")
        truthy(life.lastTransition:find("RESET %-> RUNNING %(CHALLENGE_MODE_START%)"), "RESET -> RUNNING (CHALLENGE_MODE_START)")
        equal(M.RouteProgress:GetState(), "ACTIVE", "routeState=ACTIVE tras RESET -> RUNNING")
        equal(M.RouteProgress:GetPullIndex(), 1, "pull 1")
        local snap = M.RunSession:GetSnapshot()
        truthy(snap and snap.startedAt, "RunSession creó el snapshot pese al RESET previo")
        equal(snap.pullIndex, 1, "snapshotPull=1")
        equal(M.RunSession:IsDecided(), true, "sesión decidida (nueva)")
        invariantesSinFail("RUNNING")
        equal(M.CoachHUD:GetDisplayedPull(), 1, "HUD en pull 1")

        M:HandleSlashCommand("next")
        env.WoW.advance(1)
        equal(M.RouteProgress:GetPullIndex(), 2, "pull 2")
        equal(M.RunSession:GetSnapshot().pullIndex, 2, "snapshotPull=2 (sincronizados)")
        equal(lineas(M.RunSession:StatusLines()).matchState, "SESSION_MATCH", "matchState=SESSION_MATCH")
        equal(M.CoachHUD:GetDisplayedPull(), 2, "HUD en pull 2")
        invariantesSinFail("pull 2")
        sinErrores(env, "antes del reload")
        return S.captureForReload(env)
    end)
end)

test("R2 /reload -> SESSION_MATCH -> RESTORED -> pull 2 -> next -> pull 3", function()
    truthy(capturado, "R1 dejó la partida capturada")
    S.isolated(function()
        -- El cronómetro del servidor tarda en volver tras el reload (BUG RS-1).
        local env = S.bootAfterReload(capturado, { timerDelay = 3 })
        local M = MP()
        equal(M.DungeonContext:GetState(), "RUNNING", "state=RUNNING tras el reload")
        local snap = M.RunSession:GetSnapshot()
        equal(snap and snap.pullIndex, 2, "el snapshot NO se reescribe mientras se espera")
        invariantesSinFail("esperando cronómetro")

        env.WoW.advance(5)
        local RS = lineas(M.RunSession:StatusLines())
        equal(RS.matchState, "SESSION_MATCH", "matchState=SESSION_MATCH")
        equal(RS.restoreState, "RESTORED", "restoreState=RESTORED")
        equal(RS.restoreReason, "SESSION_MATCH", "restoreReason=SESSION_MATCH")
        equal(M.RouteProgress:GetPullIndex(), 2, "pull restaurado = 2")
        local RP = lineas(M.RouteProgress:StatusLines())
        equal(RP.recovered, "true", "recovered=true")
        equal(RP.recoveryOriginalPull, "2", "recoveryOriginalPull=2")
        local RMl = lineas(M.RouteManager:StatusLines())
        equal(RMl.recoveryReason, "SESSION_MATCH", "recoveryReason=SESSION_MATCH")
        equal(M.CoachHUD:GetDisplayedPull(), 2, "HUD reconstruido en pull 2")
        invariantesSinFail("restaurado")

        M:HandleSlashCommand("next")
        env.WoW.advance(1)
        equal(M.RouteProgress:GetPullIndex(), 3, "next tras la recuperación -> pull 3")
        equal(M.RunSession:GetSnapshot().pullIndex, 3, "el snapshot sigue actualizándose")
        equal(M.CoachHUD:GetDisplayedPull(), 3, "HUD en pull 3")

        -- Detalle B: el diagnóstico no confunde el restaurado con el actual.
        RP = lineas(M.RouteProgress:StatusLines())
        equal(RP.recoveryOriginalPull, "2", "recoveryOriginalPull sigue siendo 2")
        equal(RP.currentPull, "3", "currentPull=3")
        equal(RP.recoveryPull, nil, "ya no existe el campo ambiguo recoveryPull")
        RMl = lineas(M.RouteManager:StatusLines())
        equal(RMl.recoveryOriginalPull, "2", "RouteManager tambien informa el restaurado")
        equal(M.RunSession:GetRestoredPull(), 2, "RunSession recuerda el restaurado")

        local results = invariantesSinFail("pull 3")
        local report = M.BugReport:Build()
        truthy(report:find("recoveryOriginalPull=2", 1, true), "bug report con el pull restaurado")
        truthy(report:find("restoreState=RESTORED", 1, true), "bug report con la restauración")
        truthy(report:find("sectionsFailed=none", 1, true), "bug report completo")
        truthy(report:find("SESSION ; RECOVERY_SUCCEEDED ; pull=2", 1, true), "caja negra con la recuperación")
        truthy(report:find("SESSION_START ; session=2", 1, true), "caja negra a través del reload")
        equal(#results > 0, true, "invariantes evaluados")
        equal(M.ErrorLogger:Count(), 0, "/emp bugreport: cero errores")
        sinErrores(env, "tras el reload")
    end)
end)

test("R3 una llave NUEVA de la misma mazmorra y nivel no restaura la anterior", function()
    truthy(capturado, "R1 dejó la partida capturada")
    local saved = S.deepCopy(capturado)
    -- Misma mazmorra y nivel, pero otra llave: 10 minutos después, recién
    -- empezada (30 s). La huella de inicio difiere mucho más que la tolerancia.
    saved.clock.now = saved.clock.now + 600
    saved.clock.state.challengeStartedAt = saved.clock.now - 30
    S.isolated(function()
        local env = S.bootAfterReload(saved)
        env.WoW.advance(3)
        local M = MP()
        local RS = lineas(M.RunSession:StatusLines())
        truthy(M.RunSession:GetState() ~= "RESTORED", "no se restaura otra partida")
        equal(M.RouteProgress:GetPullIndex(), 1, "empieza en el pull 1")
        equal(M.CoachHUD:GetDisplayedPull(), 1, "HUD en 1")
        truthy(RS.restoreReason ~= "SESSION_MATCH", "motivo distinto de SESSION_MATCH: " .. tostring(RS.restoreReason))
        invariantesSinFail("llave nueva")
        sinErrores(env, "llave nueva")
    end)
end)

if #failures > 0 then
    error(string.format("BaselineRegression: %d tests, %d assertions, %d failures\n%s",
        tests, assertions, #failures, table.concat(failures, "\n")), 0)
end

return { tests = tests, assertions = assertions }
