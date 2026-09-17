-- Mitzu Tracker inside the full addon (real TOC, simulated client):
-- preview isolation, a running key, completion with the criteria API gone,
-- /reload recovery, settings and the [TRACKER VISUAL] bug report section.
local tests, assertions, failures = 0, 0, {}
local function equal(a, b, l)
    assertions = assertions + 1
    if a ~= b then error((l or "equal") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function truthy(v, l) equal(not not v, true, l) end
local function test(n, f) tests = tests + 1; local ok, e = pcall(f); if not ok then failures[#failures + 1] = n .. ": " .. tostring(e) end end

local S = dofile("tests/harness/core_scenario.lua")

-- Scenario criteria driven by `crit` (same shape as TrackerIntegration.spec).
local crit
local function installScenario()
    crit = { count = 0, total = 686, bosses = { false, false, false } }
    local function entry(i)
        local n = #crit.bosses
        if i <= n then
            return { description = "Boss " .. i, completed = crit.bosses[i], quantity = crit.bosses[i] and 1 or 0,
                     totalQuantity = 1, quantityString = "", isWeightedProgress = false, elapsed = 0, duration = 0 }
        elseif i == n + 1 then
            return { description = "Enemy Forces", completed = crit.count >= crit.total,
                     quantity = math.floor(crit.count / crit.total * 100), totalQuantity = crit.total,
                     quantityString = crit.count .. "%", isWeightedProgress = true }
        end
    end
    local function active() return _G.__WOW.state.challengeActive end
    C_ScenarioInfo.GetScenarioStepInfo = function()
        if not active() then return nil end
        return { title = "", numCriteria = #crit.bosses + 1 }
    end
    C_ScenarioInfo.GetCriteriaInfo = function(i) if active() then return entry(i) end end
    C_Scenario.GetStepInfo = function()
        if not active() then return nil end
        return "", "", #crit.bosses + 1
    end
    _G.GetInventoryItemLink = _G.GetInventoryItemLink or function() return nil end
end

local function errorsText(env) return table.concat(env.errors, "\n") .. table.concat(env.WoW.errors, "\n") end
local function historyCount(MP)
    local n = 0
    for _ in pairs(MP.db.global.runs or {}) do n = n + 1 end
    return n
end
local function startRun(env, level)
    S.enterRubyAndStartKey(env, { level = level })
    local MP = _G.MitzuMPlus
    if not _G.MitzuMPlusCurrentRun then MP:OnChallengeStart() end
    truthy(_G.MitzuMPlusCurrentRun, "1.0 run created")
end
local function invariantsFail(MP)
    local I = MP.QAInvariants
    local totals = I:Summary(I:Evaluate(I:Gather()))
    return totals.FAIL, totals
end

test("tracker modules load from the TOC and the legacy HUD is gone", function()
    S.isolated(function()
        local env = S.boot({})
        local MP = _G.MitzuMPlus
        equal(#env.errors, 0, errorsText(env))
        truthy(MP.MitzuTracker and MP.TrackerPresenter and MP.TrackerView, "tracker layers registered")
        equal(MP.KeyPredictionHUD, nil, "no second visual engine")
        local loaded = table.concat(env.coreFiles, "\n")
        local a = loaded:find("Tracker/TrackerState.lua", 1, true)
        local b = loaded:find("PredictionEngine.lua", 1, true)
        local c = loaded:find("Tracker/TrackerPresenter.lua", 1, true)
        local d = loaded:find("Tracker/TrackerView.lua", 1, true)
        local e = loaded:find("Tracker/MitzuTracker.lua", 1, true)
        truthy(a and b and c and d and e and a < c and b < c and c < d and d < e, "load order state < presenter < view < controller")
        equal(MP.MitzuTracker:GetMode(), "HIDDEN"); equal(MP.MitzuTracker:IsVisible(), false)
    end)
end)

test("preview renders a realistic tracker without touching real state", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local MT, TS = MP.MitzuTracker, MP.TrackerState
        local engineCalls = 0
        local original = MP.PredictionEngine.GetSnapshot
        MP.PredictionEngine.GetSnapshot = function(...) engineCalls = engineCalls + 1; return original(...) end
        env.WoW.advance(2)                       -- let the boot-time refreshes settle
        local before = {
            revision = TS:GetRevision(), status = TS:GetStatus(), refreshes = TS._stats.refreshes,
            runs = historyCount(MP), session = S.serialize(MP.db.global.activeRunSession),
            sessionState = MP.RunSession:GetState(), run = rawget(_G, "MitzuMPlusCurrentRun"),
            nextRunID = MP.db.global.nextRunID,
        }
        MT:SetPreview(true)
        equal(MT:IsVisible(), true); equal(MT:GetMode(), "PREVIEW")
        local d = MT:GetDisplayed()
        equal(d.timer, "19:37"); equal(d.prediction, "+2"); equal(d.forces, "449 / 608 73.85%")
        equal(d.bosses, "2/4"); equal(d.deaths, "3"); equal(d.confidence, 50)
        env.WoW.advance(5)
        equal(MT:IsTickerActive(), false, "no ticker in preview")
        equal(engineCalls, 0, "preview never asks PredictionEngine")
        equal(TS:GetRevision(), before.revision); equal(TS:GetStatus(), before.status)
        equal(TS._stats.refreshes, before.refreshes, "preview never reads TrackerState/adapter")
        equal(historyCount(MP), before.runs); equal(MP.db.global.nextRunID, before.nextRunID)
        equal(S.serialize(MP.db.global.activeRunSession), before.session)
        equal(MP.RunSession:GetState(), before.sessionState); equal(rawget(_G, "MitzuMPlusCurrentRun"), before.run)
        local fails = invariantsFail(MP); equal(fails, 0)
        MT:SetPreview(false)
        equal(MT:IsVisible(), false); equal(MT:GetMode(), "HIDDEN")
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env))
    end)
end)

test("running key: tracker shows state-derived data, prediction from the engine, bug report section", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local MT = MP.MitzuTracker
        MT:SetPreview(true)
        startRun(env, 12)
        equal(MT:IsPreview(), false, "a real key turns the preview off")
        env.WoW.advance(300)
        crit.count, crit.bosses[1] = 343, true
        env.WoW.fire("SCENARIO_CRITERIA_UPDATE")
        env.WoW.advance(2)
        equal(MT:GetMode(), "RUNNING"); equal(MT:IsVisible(), true); equal(MT:IsTickerActive(), true)
        local d = MT:GetDisplayed()
        equal(d.forces, "343 / 686 50.00%"); equal(d.bosses, "1/3"); equal(d.deaths, "0")
        MT:Refresh("TEST")
        d = MT:GetDisplayed()
        equal(d.timer, MP.TrackerPresenter.FormatClock(1800 - MP.TrackerState:GetElapsed()))
        local engine = MP.PredictionEngine:GetSnapshot(_G.MitzuMPlusCurrentRun)
        local expected = engine and MP.TrackerPresenter.RESULT_CODE[engine.result] or "NONE"
        equal(d.prediction, expected, "tracker shows the engine bracket, never its own")
        equal(MT._stateRevision, MP.TrackerState:GetRevision())

        -- Timer ticks without a new state revision; the rendered revision follows.
        local rev = MT._renderRevision
        env.WoW.advance(3)
        truthy(MT._renderRevision > rev, "timer text refreshed by the ticker")

        local report = MP.BugReport:Build()
        truthy(report:find("[TRACKER VISUAL]", 1, true), report)
        for _, field in ipairs({ "implementation=MITZU_TRACKER", "visible=true", "mode=RUNNING", "stateRevision=",
            "renderRevision=", "predictionDisplayed=", "timerDisplayed=", "forcesDisplayed=343 / 686 50.00%",
            "bossesDisplayed=1/3", "deathsDisplayed=0", "lastRenderReason=", "blizzardTracker=COEXIST" }) do
            truthy(report:find(field, 1, true), field)
        end
        truthy(report:find("sectionsFailed=none", 1, true), report)
        equal((invariantsFail(MP)), 0)
        MP:HandleSlashCommand("tracker status")
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env))
    end)
end)

test("completion with criteria gone: terminal state, summary 3/3 inferred, history +1 once", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local MT, TS = MP.MitzuTracker, MP.TrackerState
        startRun(env, 12)
        local before = historyCount(MP)
        env.WoW.advance(1500)
        crit.count, crit.bosses = 686, { true, true, false }
        env.WoW.fire("SCENARIO_CRITERIA_UPDATE")
        env.WoW.advance(1)
        equal(MT:GetDisplayed().bosses, "2/3")

        -- Blizzard retires the criteria before the final boss is ever visible.
        env.WoW.state.challengeActive = false
        env.WoW.fire("CHALLENGE_MODE_COMPLETED")
        equal(TS:GetStatus(), "COMPLETING")
        equal(MT:GetMode(), "COMPLETING"); equal(MT:IsVisible(), true, "no hide while the end converges")
        equal(MT:GetDisplayed().forces, "686 / 686 100.00%")
        env.WoW.fire("CHALLENGE_MODE_COMPLETED")
        env.WoW.advance(4)

        equal(TS:GetStatus(), "COMPLETED")
        local s = TS:GetSnapshot()
        equal(s.terminalStateConfirmed, true); equal(s.completionConverged, false)
        equal(s.completionCriteriaIncomplete, false); equal(s.criteriaUnavailableAfterCompletion, true)
        equal(s.bossesCompleted, 2); equal(s.bossesCompletedFinal, 3)
        equal(s.bossCountSource, "INFERRED_FROM_COMPLETION_EVENT")
        equal(MT:GetMode(), "SUMMARY"); equal(MT:IsVisible(), true)
        equal(MT:GetDisplayed().bosses, "3/3 (inferred)")
        equal(MT:IsTickerActive(), false, "no ticker in the summary")

        env.WoW.fire("CHALLENGE_MODE_COMPLETED")
        env.WoW.advance(10)
        equal(historyCount(MP), before + 1, "history finalized exactly once")
        local fails, totals = invariantsFail(MP)
        equal(fails, 0); equal(totals.WARN, 0)

        env.WoW.advance(MT.SUMMARY_SECONDS)
        equal(MT:GetMode(), "HIDDEN"); equal(MT:IsVisible(), false)
        local report = MP.BugReport:Build()
        for _, field in ipairs({ "completionSource=CHALLENGE_MODE_COMPLETED", "terminalStateConfirmed=true",
            "criteriaUnavailableAfterCompletion=true", "bossCountSource=INFERRED_FROM_COMPLETION_EVENT",
            "duplicateSessionIDs=0" }) do
            truthy(report:find(field, 1, true), field .. "\n" .. report)
        end
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env))
    end)
end)

test("reload mid-key: same session, no new history, tracker visible with recovered data", function()
    local saved, sessionID, runs = S.isolated(function()
        local env = S.boot({})
        installScenario()
        startRun(env, 12)
        env.WoW.advance(1199)
        crit.count, crit.bosses = 686, { true, true, false }
        env.WoW.fire("SCENARIO_CRITERIA_UPDATE")
        env.WoW.advance(1)
        local MP = _G.MitzuMPlus
        equal(MP.MitzuTracker:GetMode(), "RUNNING")
        return S.captureForReload(env), _G.MitzuMPlusCurrentRun.sessionID, historyCount(MP)
    end)
    truthy(sessionID, "session before reload")
    S.isolated(function()
        _G.GetInventoryItemLink = function() return nil end
        local env = S.bootAfterReload(saved, { timerDelay = 4 })
        installScenario()
        crit.count, crit.bosses = 686, { true, true, false }
        env.WoW.fire("PLAYER_ENTERING_WORLD", false, true)
        env.WoW.advance(6)
        local MP = _G.MitzuMPlus
        if not _G.MitzuMPlusCurrentRun then MP:OnChallengeStart() end
        local run = _G.MitzuMPlusCurrentRun
        truthy(run, "run recovered")
        equal(run.sessionID, sessionID, "same sessionID after /reload")
        equal(run.sessionRecovered, true)
        equal(historyCount(MP), runs, "history does not grow on reload")
        local TS, MT = MP.TrackerState, MP.MitzuTracker
        equal(TS:GetStatus(), "RUNNING"); equal(TS:GetSnapshot().recovered, true)
        truthy(TS:GetElapsed() >= 1199, "elapsed recovered from the server: " .. tostring(TS:GetElapsed()))
        equal(TS:GetSnapshot().keystoneLevel, 12); equal(TS:GetSnapshot().mapID, 399)
        equal(MT:GetMode(), "RUNNING"); equal(MT:IsVisible(), true)
        local d = MT:GetDisplayed()
        equal(d.forces, "686 / 686 100.00%"); equal(d.bosses, "2/3")
        local recorded = table.concat(MP.FlightRecorder:Lines(300), "\n")
        truthy(recorded:find("STATE_RUN_RECOVERED", 1, true), recorded)
        equal((invariantsFail(MP)), 0)
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env))
    end)
end)

test("settings: scale, alpha, lock and position persist and a refresh never moves the tracker", function()
    S.isolated(function()
        S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local MT = MP.MitzuTracker
        MT:SetPreview(true)
        local f = MP.TrackerView.frame
        truthy(f, "frame built once")
        local calls = { scale = {}, alpha = {}, mouse = {}, clear = 0 }
        f.SetScale = function(_, v) calls.scale[#calls.scale + 1] = v end
        f.SetAlpha = function(_, v) calls.alpha[#calls.alpha + 1] = v end
        f.EnableMouse = function(_, v) calls.mouse[#calls.mouse + 1] = v end
        local clear = f.ClearAllPoints
        f.ClearAllPoints = function(self) calls.clear = calls.clear + 1; return clear(self) end

        for _, v in ipairs({ 1.2, 0.8, 1.0, 5, 0.1 }) do MT:SetOption("scale", v) end
        equal(calls.scale[1], 1.2); equal(calls.scale[2], 0.8); equal(calls.scale[4], 2.0); equal(calls.scale[5], 0.6)
        MT:SetOption("alpha", 0.5); equal(calls.alpha[#calls.alpha], 0.5)
        MT:SetOption("locked", true); equal(calls.mouse[#calls.mouse], false, "locked does not capture clicks")
        MT:SetOption("locked", false); equal(calls.mouse[#calls.mouse], true)

        -- Drag: the anchor is saved in settings.hud.
        f.__points = { { "CENTER", UIParent, "CENTER", 120, -40 } }
        f:GetScript("OnDragStart")(f); f:GetScript("OnDragStop")(f)
        local s = MP.db.profile.settings.hud
        equal(s.point, "CENTER"); equal(s.x, 120); equal(s.y, -40)
        MT:SetOption("locked", true)
        f:GetScript("OnDragStart")(f)
        equal(f._dragging, false, "locked tracker cannot be dragged")

        local cleared = calls.clear
        for _ = 1, 5 do MT:Refresh("TEST") end
        equal(calls.clear, cleared, "refresh never re-anchors")
        MT:SetOption("showConfidence", false)
        equal(MT:GetDisplayed().confidence, nil)
        MT:SetEnabled(false)
        equal(MT:GetMode(), "PREVIEW", "preview is explicit even when disabled")
        MT:SetPreview(false)
        equal(MT:IsVisible(), false)
    end)
end)

test("long dungeon names and large counts are laid out inside the frame", function()
    S.isolated(function()
        S.boot({})
        local MP = _G.MitzuMPlus
        local TV, TP = MP.TrackerView, MP.TrackerPresenter
        MP.MitzuTracker:SetPreview(true)
        local input = TP.PreviewInput({})
        input.state.mapName = "Operacion: Compuerta de las Profundidades del Remolino Eterno"
        input.state.forcesCurrent, input.state.forcesTotal = 1234, 1450
        input.state.forcesPercent = 1234 / 1450 * 100
        local shown = TV:Render(TP.Build(input))
        equal(shown.forces, "1,234 / 1,450 85.10%")
        local r = TV.r
        -- The title is bounded on both sides: the key badge can never be pushed out.
        equal(#r.title.__points, 2)
        equal(r.title.__points[2][1], "RIGHT"); equal(r.title.__points[2][2], r.badge)
        equal(r.title:GetText(), input.state.mapName)
        -- Threshold labels live in three fixed, equal columns.
        local w = r.segs[1]:GetWidth()
        truthy(w > 0 and w == r.segs[2]:GetWidth() and w == r.segs[3]:GetWidth(), "equal columns")
        truthy(w * 3 <= TV.WIDTH - 2 * TV.PAD + 0.5, "columns fit")
        MP.MitzuTracker:SetPreview(false)
    end)
end)

if #failures > 0 then error(string.format("TrackerVisual: %d failures\n%s", #failures, table.concat(failures, "\n")), 0) end
return { tests = tests, assertions = assertions }
