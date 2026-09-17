-- Mitzu Tracker dev.7 inside the full addon (real TOC, simulated client and a
-- simulated Blizzard Objective Tracker with its real 12.1.0 structure):
-- run mode is embedded in Blizzard's Mythic+ block (never a floating HUD),
-- preview/summary use the floating view, attach/detach/reattach lifecycle,
-- /reload, completion and no mutation of Blizzard frames.
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
    if not _G.MitzuMPlusCurrentRun then _G.MitzuMPlus:OnChallengeStart() end
    truthy(_G.MitzuMPlusCurrentRun, "1.0 run created")
end
local function invariants(MP)
    local I = MP.QAInvariants
    local results = I:Evaluate(I:Gather())
    local fails = {}
    for _, r in ipairs(results) do if r.status == "FAIL" then fails[#fails + 1] = r.name .. " " .. tostring(r.detail) end end
    return #fails, table.concat(fails, "; "), I:Summary(results)
end
local function fields(MP)
    local f = {}
    for _, kv in ipairs(MP.MitzuTracker:DiagnosticFields()) do f[kv[1]] = kv[2] end
    return f
end
local function floatingShown(MP)
    local frame = MP.TrackerView.frame
    return frame ~= nil and frame:IsShown() == true
end
local function freshMock() return dofile("tests/harness/blizzard_tracker_mock.lua") end

-- A key with the Blizzard block active, forces bar present, 300 s in.
local function runningKey(env, BT, level)
    startRun(env, level or 12)
    BT.activate(0, 1800)
    BT.setForces(true)
    env.WoW.advance(300)
    crit.count, crit.bosses[1] = 343, true
    env.WoW.fire("SCENARIO_CRITERIA_UPDATE")
    BT.tick(300)
    env.WoW.advance(2)
end

test("tracker layers load in order and the enhancer is registered", function()
    S.isolated(function()
        local env = S.boot({})
        local MP = _G.MitzuMPlus
        equal(#env.errors, 0, errorsText(env))
        truthy(MP.MitzuTracker and MP.TrackerPresenter and MP.TrackerView and MP.BlizzardTrackerEnhancer)
        local loaded = table.concat(env.coreFiles, "\n")
        local c = loaded:find("Tracker/TrackerPresenter.lua", 1, true)
        local d = loaded:find("Tracker/TrackerView.lua", 1, true)
        local e = loaded:find("Tracker/BlizzardTrackerEnhancer.lua", 1, true)
        local f = loaded:find("Tracker/MitzuTracker.lua", 1, true)
        truthy(c and d and e and f and c < d and d < e and e < f, "presenter < view < enhancer < controller")
        equal(MP.MitzuTracker:GetMode(), "HIDDEN"); equal(MP.MitzuTracker:IsVisible(), false)
    end)
end)

test("A: running key renders inside the Blizzard block and never as a floating HUD", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local BT = freshMock(); BT.install()
        local MP = _G.MitzuMPlus
        local MT, EN = MP.MitzuTracker, MP.BlizzardTrackerEnhancer
        runningKey(env, BT)
        equal(MT:GetMode(), "RUNNING"); equal(MT:GetRenderMode(), "EMBEDDED")
        equal(floatingShown(MP), false, "no floating run HUD"); equal(MP.TrackerView.frame, nil, "floating frame never built")
        equal(EN:IsAttached(), true); equal(MT:IsEmbeddedVisible(), true); equal(MT:IsVisible(), true)
        equal(EN.elements.root:GetParent(), BT.block, "our root is a child of the Blizzard block")
        equal(EN.elements.forcesRoot:GetParent(), BT.block)

        local shown = EN._displayed
        equal(shown.forces, "343 / 686  faltan 343", "count and remaining in two columns, no duplicated %")
        equal(shown.forcesPrimary, "343 / 686"); equal(shown.forcesSecondary, "faltan 343"); equal(shown.forcesLayoutMode, "SPLIT")
        truthy(shown.upgrade and shown.upgrade:find("^%+3 %d+:%d%d$"), "ONE threshold only: " .. tostring(shown.upgrade))
        equal(shown.threshold, "+3"); equal(shown.thresholdMode, "NEXT")
        truthy(not EN.elements.threshold:GetText():find("+2", 1, true), "never the three thresholds")
        for _, key in ipairs({ "threshold", "pace", "paceExtra", "penalty" }) do
            local text = EN.elements[key]:GetText() or ""
            truthy(not text:find("Muertes", 1, true), "no duplicated death count in " .. key)
        end
        truthy(not (EN.elements.forcesPrimary:GetText() or ""):find("%%"), "no % under Blizzard's bar")
        truthy(shown.paceText and shown.paceText:find("RITMO", 1, true), tostring(shown.paceText))
        equal(shown.forcesBar, true)
        local d = MT:GetDisplayed()
        equal(d.timer, "BLIZZARD"); equal(d.bosses, "BLIZZARD", "Blizzard keeps timer and bosses")

        -- The upgrade line tracks the clock through the 1 s ticker.
        local before = shown.upgrade
        env.WoW.advance(3)
        truthy(EN._displayed.upgrade ~= before, "upgrade times move with the clock")

        local report = MP.BugReport:Build()
        for _, field in ipairs({ "implementation=BLIZZARD_TRACKER_ENHANCER", "renderMode=EMBEDDED",
            "blizzardTrackerLoaded=true", "challengeBlockFound=true", "challengeBlockShown=true", "attached=true",
            "attachGeneration=1", "attachReason=ATTACHED", "attachmentHealthy=true", "trackerVisible=true",
            "floatingVisible=false", "upgradeTimesDisplayed=true", "forcesCountDisplayed=true",
            "forcesRemainingDisplayed=true", "hooksInstalled=true", "lastRenderError=nil",
            "thresholdDisplayed=+3", "thresholdTimeDisplayed=", "thresholdMode=NEXT", "paceDisplayed=RITMO",
            "paceMode=", "forcesPrimaryDisplayed=343 / 686", "forcesSecondaryDisplayed=faltan 343",
            "forcesLayoutMode=SPLIT", "availableWidth=", "angryKeystonesLoaded=false" }) do
            truthy(report:find(field, 1, true), field .. "\n" .. report)
        end
        truthy(report:find("sectionsFailed=none", 1, true), report)
        truthy(not report:find("table: ", 1, true), "no frame references serialized")
        local fails, detail = invariants(MP); equal(fails, 0, detail)
        equal(#BT.foreign, 0, "Blizzard frames untouched: " .. table.concat(BT.foreign, ","))
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env))
    end)
end)

test("B: preview uses the floating view, stays isolated and is refused during a key", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local MT, TS = MP.MitzuTracker, MP.TrackerState
        local engineCalls = 0
        local original = MP.PredictionEngine.GetSnapshot
        MP.PredictionEngine.GetSnapshot = function(...) engineCalls = engineCalls + 1; return original(...) end
        env.WoW.advance(2)
        local before = { revision = TS:GetRevision(), refreshes = TS._stats.refreshes, runs = historyCount(MP),
                         session = S.serialize(MP.db.global.activeRunSession), state = MP.RunSession:GetState() }
        equal(MT:SetPreview(true), true)
        equal(MT:GetMode(), "PREVIEW"); equal(MT:GetRenderMode(), "PREVIEW_FLOATING")
        equal(floatingShown(MP), true); equal(MP.BlizzardTrackerEnhancer:IsVisible(), false)
        local d = MT:GetDisplayed()
        equal(d.timer, "19:37"); equal(d.prediction, "+2"); equal(d.forces, "449 / 608  faltan 159")
        local r = MP.TrackerView.r
        equal(r.threshold:GetText():match("%+3") ~= nil and r.threshold:GetText():find("6:25", 1, true) ~= nil, true,
            "preview shows the single next threshold: " .. tostring(r.threshold:GetText()))
        equal(r.forcesLabel:GetText(), "73%", "simulated Blizzard label keeps the integer %")
        equal(r.penalty:GetText(), "-0:15"); equal(r.deathCount:GetText(), "3")
        truthy(MP.TrackerView.WIDTH <= 280, "preview simulates the narrow tracker, not the dev.6 panel")
        env.WoW.advance(5)
        equal(engineCalls, 0); equal(TS:GetRevision(), before.revision); equal(TS._stats.refreshes, before.refreshes)
        equal(historyCount(MP), before.runs); equal(S.serialize(MP.db.global.activeRunSession), before.session)
        equal(MP.RunSession:GetState(), before.state)
        equal((fields(MP)).renderMode, "PREVIEW_FLOATING")
        MT:SetPreview(false)
        equal(MT:IsVisible(), false)

        -- During a real key the floating preview cannot be opened.
        local BT = freshMock(); BT.install()
        runningKey(env, BT)
        local ok, why = MT:SetPreview(true)
        equal(ok, false); equal(why, "KEY_IN_PROGRESS"); equal(floatingShown(MP), false)
        MP:HandleSlashCommand("tracker preview")
        equal(floatingShown(MP), false); equal(MT:GetRenderMode(), "EMBEDDED")
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env))
    end)
end)

test("C/28: block missing -> nothing floating; attaches as soon as Blizzard's block appears", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local MT, EN = MP.MitzuTracker, MP.BlizzardTrackerEnhancer
        startRun(env, 12)
        env.WoW.advance(5)
        equal(MT:GetMode(), "RUNNING")
        equal(EN:IsAttached(), false); equal(floatingShown(MP), false, "no floating fallback during a run")
        local f = fields(MP)
        equal(f.attached, false); equal(f.attachReason, "BLIZZARD_TRACKER_NOT_LOADED"); equal(f.trackerVisible, false)

        local BT = freshMock(); BT.install()
        env.WoW.advance(1.1)
        equal(EN:IsAttached(), true, "attached on the next tick")
        equal(EN:IsVisible(), false, "block not active yet: nothing of ours shown")
        equal((fields(MP)).attachReason, "CHALLENGE_BLOCK_INACTIVE")
        BT.activate(305, 1800)                             -- Blizzard starts its timer late
        equal(EN:IsVisible(), true, "the Activate post-hook shows us immediately")
        equal(EN._generation, 1)
        truthy(EN._lastLayoutReason == "BLIZZARD_ACTIVATE" or EN._lastLayoutReason == "BLIZZARD_LAYOUT", tostring(EN._lastLayoutReason))
        equal(#BT.foreign, 0, table.concat(BT.foreign, ","))
        local recorded = table.concat(MP.FlightRecorder:Lines(300), "\n")
        truthy(recorded:find("EMBED_UNAVAILABLE", 1, true), recorded)
    end)
end)

test("D/E/G: detach when the block goes away, reattach to a rebuilt block, no duplicate hooks", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local EN = MP.BlizzardTrackerEnhancer
        local BT = freshMock(); BT.install()
        runningKey(env, BT)
        local root = EN.elements.root
        equal(EN._generation, 1)

        -- Many Blizzard layouts: one attachment, hook body runs once per layout.
        local calls = 0
        local render = EN.Render
        EN.Render = function(...) calls = calls + 1; return render(...) end
        for _ = 1, 5 do BT.layout() end
        equal(calls, 5, "one render per Blizzard layout (no duplicate hooks)")
        -- Repeated Activate (Blizzard re-checks timers): its hook body runs once each time.
        for _ = 1, 4 do BT.activate(310, 1800) end
        calls = 0
        BT.activate(311, 1800)
        equal(calls, 2, "one render for the inner layout + one for Activate, never accumulated")
        EN.Render = render
        equal(EN._generation, 1)

        -- Block hidden by Blizzard (timer stopped): our elements hide with it.
        BT.stopTimer()
        equal(BT.block:IsShown(), false); equal(EN:IsVisible(), false)
        BT.activate(320, 1800)
        equal(EN:IsVisible(), true); equal(EN._generation, 1, "same block: no reattach")

        -- Blizzard rebuilds the block while we are still attached: reattach at once.
        local BTr = freshMock(); BTr.install(); BTr.activate(325, 1800); BTr.setForces(true)
        env.WoW.advance(1.1)
        equal(EN._generation, 2, "rebuilt block without a detach in between")
        equal(root:GetParent(), BTr.block); equal(EN._hookedBlock, BTr.block); equal(EN:IsVisible(), true)
        equal((fields(MP)).attachmentHealthy, true)
        BT = BTr

        -- Tracker unloaded: detach and clean.
        BT.uninstall()
        env.WoW.advance(1.1)
        equal(EN:IsAttached(), false); equal(root:IsShown(), false); equal(root:GetParent(), nil)
        equal((fields(MP)).attachReason, "BLIZZARD_TRACKER_NOT_LOADED")

        -- Rebuilt tracker (new objects): reattach, reuse our elements, hook the new instances.
        local BT2 = freshMock(); BT2.install()
        BT2.activate(330, 1800); BT2.setForces(true)
        env.WoW.advance(1.1)
        equal(EN:IsAttached(), true); equal(EN._generation, 3)
        equal(EN.elements.root, root, "elements reused"); equal(root:GetParent(), BT2.block)
        equal(EN._hookedBlock, BT2.block); equal(EN._hookedTracker, BT2.tracker)
        equal(EN:IsVisible(), true); equal((fields(MP)).attachmentHealthy, true)
        equal((fields(MP)).attachReason, "ATTACHED")
        equal(#BT2.foreign, 0, table.concat(BT2.foreign, ","))
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env))
    end)
end)

test("forces line follows Blizzard's pooled bar and disappears at 100 %", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local EN = MP.BlizzardTrackerEnhancer
        local BT = freshMock(); BT.install()
        runningKey(env, BT)
        local bar = BT.tracker.usedProgressBars[BT.tracker.ObjectivesBlock.forcesLine]
        truthy(EN.elements.forcesRoot:IsShown())
        local anchor = EN.elements.forcesRoot.__points[1]
        equal(anchor[2], bar.Bar, "anchored under the Blizzard bar")
        crit.count, crit.bosses = 686, { true, true, false }
        env.WoW.fire("SCENARIO_CRITERIA_UPDATE")
        BT.setForces(false)                               -- Blizzard frees the bar when forces complete
        env.WoW.advance(2)
        equal(EN.elements.forcesRoot:IsShown(), false); equal(EN._displayed.forces, nil)
        equal((fields(MP)).forcesBarFound, false)
        -- Two weighted bars: ambiguous, nothing guessed.
        BT.setForces(true)
        BT.tracker.usedProgressBars.other = BT.tracker.usedProgressBars[BT.tracker.ObjectivesBlock.forcesLine]
        crit.count = 600; env.WoW.fire("SCENARIO_CRITERIA_UPDATE"); env.WoW.advance(1.1)
        equal((fields(MP)).forcesBarReason, "FORCES_BAR_AMBIGUOUS"); equal(EN._displayed.forces, nil)
        equal(EN.elements.forcesRoot:IsShown(), false)
        BT.tracker.usedProgressBars.other = nil
        env.WoW.advance(1.1)
        equal(EN._displayed.forces, "600 / 686  faltan 86", "back to the single real bar")
        equal(#BT.foreign, 0, table.concat(BT.foreign, ","))
    end)
end)

test("L: single threshold follows the clock, penalty narrows the line, options remove lines", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local EN = MP.BlizzardTrackerEnhancer
        local BT = freshMock(); BT.install()
        runningKey(env, BT)
        -- Mock font: 6 px per glyph. Block 251, TimeLeft "25:00" = 30 px:
        -- available = 251 - 47 - 4 - (28 + 30 + 8) = 134.
        equal(EN._displayed.available, 134)
        equal(EN._displayed.threshold, "+3")
        -- +3 at 18:00 (limit 30:00): past it the next relevant one is +2, then +1.
        env.WoW.advance(1090 - 305); BT.tick(1090); env.WoW.advance(1.1)
        equal(EN._displayed.threshold, "+2"); truthy(EN._displayed.upgrade:find("^%+2 "), EN._displayed.upgrade)
        env.WoW.advance(1450 - 1091); BT.tick(1450); env.WoW.advance(1.1)
        equal(EN._displayed.threshold, "+1")
        -- Deaths with published penalty: next to Blizzard's counter, line narrows.
        local wide = EN._displayed.available
        BT.setDeaths(2)
        _G.C_ChallengeMode.GetDeathCount = function() return 2, 10 end
        env.WoW.fire("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
        env.WoW.advance(2)
        equal(EN._displayed.penalty, "-0:10")
        equal(EN._displayed.available, wide - (5 * 6 + 4))
        equal(EN.elements.penalty.__points[1][2], BT.block.DeathCount)
        MP.MitzuTracker:SetOption("showUpgradeTimes", false)
        MP.MitzuTracker:SetOption("showDeaths", false)
        MP.MitzuTracker:SetOption("showForcesRemaining", false)
        equal(EN._displayed.upgrade, nil); equal(EN._displayed.thresholdMode, "DISABLED"); equal(EN._displayed.penalty, nil)
        equal(EN._displayed.forces, "343 / 686"); equal(EN._displayed.forcesSecondary, nil)
        MP.MitzuTracker:SetOption("showConfidence", false)
        equal(EN._displayed.confidence, nil); equal(EN.elements.paceExtra:GetText(), "")
        MP.MitzuTracker:SetOption("showPrediction", false)
        equal(EN._displayed.paceText, nil); equal(MP.MitzuTracker:GetDisplayed().prediction, "NONE")
        equal(#BT.foreign, 0, table.concat(BT.foreign, ","))
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env))
    end)
end)

test("narrow block: threshold kept before secondary data, never overflows", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local EN = MP.BlizzardTrackerEnhancer
        local BT = freshMock(); BT.install({ blockWidth = 190 })
        runningKey(env, BT)
        -- available = 190 - 47 - 4 - 66 = 73: "+3 20:00" (48) fits, "RITMO --" (48) fits without extras.
        equal(EN._displayed.available, 73)
        equal(EN._displayed.thresholdMode, "NEXT")
        truthy(EN._displayed.paceMode == "COMPACT" or EN._displayed.paceMode == "STANDARD", tostring(EN._displayed.paceMode))
        local BT2 = freshMock(); BT2.install({ blockWidth = 150 })   -- rebuilt narrower: 33 px
        BT2.activate(310, 1800); BT2.setForces(true)
        env.WoW.advance(1.1)
        equal(EN._displayed.available, 33)
        equal(EN._displayed.thresholdMode, "TOO_NARROW"); equal(EN._displayed.upgrade, nil)
        equal(EN._displayed.paceText, nil, "no pace where the threshold does not fit")
        equal(EN.elements.threshold:GetText(), ""); equal(EN.elements.pace:GetText(), "")
        equal(#BT2.foreign, 0, table.concat(BT2.foreign, ","))
    end)
end)

test("Angry Keystones loaded: Mitzu does not repeat its threshold and right-aligns the pace", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        env.WoW.addonsLoaded.AngryKeystones = true
        local MP = _G.MitzuMPlus
        local EN = MP.BlizzardTrackerEnhancer
        local BT = freshMock(); BT.install()
        runningKey(env, BT)
        equal(EN._displayed.angryKeystones, true); equal(EN._displayed.thresholdMode, "DEFERRED")
        equal(EN._displayed.upgrade, nil); equal(EN.elements.threshold:GetText(), "")
        truthy(EN._displayed.paceText, "pace still shown")
        equal(EN.elements.paceExtra.__points[1][1], "TOPRIGHT", "pace anchored on the right, away from AK's text")
        equal(EN._displayed.available, 134 - EN.LAYOUT.AK_RESERVE)
        equal(EN._displayed.forces, "343 / 686  faltan 343", "never a second % over AK's precise label")
        local report = MP.BugReport:Build()
        truthy(report:find("angryKeystonesLoaded=true", 1, true)); truthy(report:find("thresholdMode=DEFERRED", 1, true))
        equal(#BT.foreign, 0, table.concat(BT.foreign, ","))
    end)
end)

test("performance: same content is not re-measured or re-written", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local EN = MP.BlizzardTrackerEnhancer
        local BT = freshMock(); BT.install()
        runningKey(env, BT)
        local measured, written = 0, 0
        for _, m in pairs(EN.elements.measure) do
            local set = m.SetText
            m.SetText = function(self, v) measured = measured + 1; return set(self, v) end
        end
        local set = EN.elements.forcesPrimary.SetText
        EN.elements.forcesPrimary.SetText = function(self, v) written = written + 1; return set(self, v) end
        local model, opts = EN._model, EN._opts
        for _ = 1, 5 do EN:Render(model, opts, "TEST") end
        equal(measured, 0, "cached widths"); equal(written, 0, "cached text")
    end)
end)

test("N/O: completion keeps the embedded state, then a floating summary, criteria gone, history +1 once", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local MT, TS, EN = MP.MitzuTracker, MP.TrackerState, MP.BlizzardTrackerEnhancer
        local BT = freshMock(); BT.install()
        runningKey(env, BT)
        local before = historyCount(MP)
        env.WoW.advance(1200)
        crit.count, crit.bosses = 686, { true, true, false }
        env.WoW.fire("SCENARIO_CRITERIA_UPDATE")
        BT.setForces(false)
        env.WoW.advance(1)

        env.WoW.state.challengeActive = false
        env.WoW.fire("CHALLENGE_MODE_COMPLETED")
        equal(TS:GetStatus(), "COMPLETING"); equal(MT:GetRenderMode(), "EMBEDDED")
        equal(EN:IsVisible(), true, "no flash while the end converges"); equal(floatingShown(MP), false)
        env.WoW.fire("CHALLENGE_MODE_COMPLETED")
        BT.stopTimer()                                    -- Blizzard retires its block
        env.WoW.advance(4)

        equal(TS:GetStatus(), "COMPLETED")
        local s = TS:GetSnapshot()
        equal(s.terminalStateConfirmed, true); equal(s.completionSource, "CHALLENGE_MODE_COMPLETED")
        equal(s.criteriaUnavailableAfterCompletion, true); equal(s.completionCriteriaIncomplete, false)
        equal(s.bossesCompleted, 2); equal(s.bossesCompletedFinal, 3); equal(s.bossCountSource, "INFERRED_FROM_COMPLETION_EVENT")
        equal(MT:GetMode(), "SUMMARY"); equal(MT:GetRenderMode(), "PREVIEW_FLOATING")
        equal(floatingShown(MP), true, "summary fallback outside the retired block")
        equal(EN:IsVisible(), false)
        equal(MT:GetDisplayed().bosses, "3/3 (inferred)")
        env.WoW.fire("CHALLENGE_MODE_COMPLETED"); env.WoW.advance(10)
        equal(historyCount(MP), before + 1)
        local fails, detail = invariants(MP); equal(fails, 0, detail)
        env.WoW.advance(MT.SUMMARY_SECONDS)
        equal(MT:GetMode(), "HIDDEN"); equal(MT:IsVisible(), false)
        equal(#BT.foreign, 0, table.concat(BT.foreign, ","))
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env))
    end)
end)

test("F: /reload mid-key reattaches to the new Blizzard block with the same session", function()
    local saved, sessionID, runs = S.isolated(function()
        local env = S.boot({})
        installScenario()
        local BT = freshMock(); BT.install()
        runningKey(env, BT)
        env.WoW.advance(900)
        local MP = _G.MitzuMPlus
        equal(MP.BlizzardTrackerEnhancer:IsVisible(), true)
        return S.captureForReload(env), _G.MitzuMPlusCurrentRun.sessionID, historyCount(MP)
    end)
    S.isolated(function()
        _G.GetInventoryItemLink = function() return nil end
        local env = S.bootAfterReload(saved, { timerDelay = 4 })
        installScenario()
        crit.count, crit.bosses = 343, { true, false, false }
        local BT = freshMock(); BT.install()
        env.WoW.fire("PLAYER_ENTERING_WORLD", false, true)
        env.WoW.advance(5)
        BT.activate(1210, 1800); BT.setForces(true)       -- ScenarioTimerFrame after the reload
        env.WoW.advance(2)
        local MP = _G.MitzuMPlus
        if not _G.MitzuMPlusCurrentRun then MP:OnChallengeStart() end
        equal(_G.MitzuMPlusCurrentRun.sessionID, sessionID); equal(historyCount(MP), runs)
        equal(MP.TrackerState:GetStatus(), "RUNNING"); equal(MP.TrackerState:GetSnapshot().recovered, true)
        local EN = MP.BlizzardTrackerEnhancer
        equal(EN:IsAttached(), true); equal(EN:IsVisible(), true); equal(floatingShown(MP), false)
        equal(EN._displayed.forces, "343 / 686  faltan 343")
        local fails, detail = invariants(MP); equal(fails, 0, detail)
        equal(#BT.foreign, 0, table.concat(BT.foreign, ","))
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env))
    end)
end)

test("kill switch: repeated enhancer failures disable it and leave Blizzard intact", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local EN = MP.BlizzardTrackerEnhancer
        local BT = freshMock(); BT.install()
        runningKey(env, BT)
        local build = MP.TrackerPresenter.BuildEmbedded
        MP.TrackerPresenter.BuildEmbedded = function() error("boom") end
        for _ = 1, 4 do BT.layout() end
        MP.TrackerPresenter.BuildEmbedded = build
        equal(EN._disabled, true); equal(EN:IsVisible(), false); equal(BT.block:IsShown(), true)
        env.WoW.advance(3)
        equal(EN:IsVisible(), false, "stays off")
        local f = fields(MP)
        equal(f.enhancerDisabled, true); truthy(tostring(f.lastEnhancerError):find("boom", 1, true))
        equal(floatingShown(MP), false)
        equal(#BT.foreign, 0, table.concat(BT.foreign, ","))
    end)
end)

test("floating settings: scale, alpha, lock and position only move the preview window", function()
    S.isolated(function()
        S.boot({})
        local MP = _G.MitzuMPlus
        local MT = MP.MitzuTracker
        MT:SetPreview(true)
        local f = MP.TrackerView.frame
        local calls = { scale = {}, mouse = {}, clear = 0 }
        f.SetScale = function(_, v) calls.scale[#calls.scale + 1] = v end
        f.EnableMouse = function(_, v) calls.mouse[#calls.mouse + 1] = v end
        local clear = f.ClearAllPoints
        f.ClearAllPoints = function(self) calls.clear = calls.clear + 1; return clear(self) end
        MT:SetOption("scale", 1.2); MT:SetOption("scale", 5)
        equal(calls.scale[1], 1.2); equal(calls.scale[2], 2.0)
        MT:SetOption("locked", true); equal(calls.mouse[#calls.mouse], false)
        MT:SetOption("locked", false)
        f.__points = { { "CENTER", UIParent, "CENTER", 120, -40 } }
        f:GetScript("OnDragStart")(f); f:GetScript("OnDragStop")(f)
        equal(MP.db.profile.settings.hud.x, 120)
        local cleared = calls.clear
        for _ = 1, 5 do MT:Refresh("TEST") end
        equal(calls.clear, cleared, "refresh never re-anchors")
        -- Embedded scale is clamped and applied only to Mitzu's own elements.
        local EN = MP.BlizzardTrackerEnhancer
        EN:_CreateElements()
        local scaled
        EN.elements.root.SetScale = function(_, v) scaled = v end
        MT:SetOption("scale", 2.0)
        equal(scaled, EN.SCALE_MAX)
        MT:SetPreview(false)
    end)
end)

-- ---------------------------------------------------------------------------
-- 1.1.0-dev.9: pulido final y observabilidad del ultimo render integrado.
-- ---------------------------------------------------------------------------

local function flat(snap)
    for key, value in pairs(snap or {}) do
        local t = type(value)
        truthy(t == "string" or t == "number" or t == "boolean",
            "the QA snapshot only stores flat values: " .. tostring(key) .. " is " .. t)
    end
end
local function reportValue(report, key)
    return report:match("\n" .. key:gsub("([%.%-%+])", "%%%1") .. "=([^\n]*)")
end

test("dev.9 A/B/C/H/I/J: the embedded render is snapshotted, updated and never erased by a hide", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local MT, TS, EN = MP.MitzuTracker, MP.TrackerState, MP.BlizzardTrackerEnhancer
        equal(MT:GetLastEmbedded(), nil, "nothing to remember before a key")
        local BT = freshMock(); BT.install()
        runningKey(env, BT)

        -- A: a valid embedded render creates the snapshot, with what was painted.
        local snap = MT:GetLastEmbedded()
        truthy(snap, "A: the embedded render creates the snapshot")
        equal(snap.forcesPrimaryDisplayed, "343 / 686"); equal(snap.forcesSecondaryDisplayed, "faltan 343")
        equal(snap.forcesLayoutMode, "SPLIT"); equal(snap.thresholdDisplayed, "+3"); equal(snap.thresholdMode, "NEXT")
        truthy(snap.paceDisplayed and snap.paceDisplayed:find("RITMO", 1, true), tostring(snap.paceDisplayed))
        equal(snap.angryKeystonesLoaded, false); equal(snap.attachmentHealthy, true)
        equal(snap.attachGeneration, EN._generation); equal(snap.availableWidth, EN._displayed.available)
        equal(snap.penaltyDisplayed, nil, "no deaths yet: no penalty remembered")
        equal(snap.stateRevision, TS:GetRevision()); equal(snap.renderRevision, MT._renderRevision)
        flat(snap)

        -- H/I/J: taking the picture changes no game state at all.
        local before = { revision = TS:GetRevision(), runs = historyCount(MP), status = TS:GetStatus(),
                         session = S.serialize(MP.db.global.activeRunSession),
                         sessionID = _G.MitzuMPlusCurrentRun.sessionID,
                         state = S.serialize(TS:GetSnapshot()) }
        for _ = 1, 3 do MT:Refresh("TEST") end
        equal(TS:GetRevision(), before.revision, "H: no state revision moved")
        equal(S.serialize(TS:GetSnapshot()), before.state, "H: TrackerState untouched")
        equal(historyCount(MP), before.runs, "I: history never grows for a snapshot")
        equal(_G.MitzuMPlusCurrentRun.sessionID, before.sessionID, "J: same sessionID")
        equal(S.serialize(MP.db.global.activeRunSession), before.session, "J: same stored session")
        equal(MP.db.global.lastEmbedded, nil, "the snapshot never reaches SavedVariables")

        -- B: a later valid render replaces it (and clears what stopped showing).
        crit.count = 600
        env.WoW.fire("SCENARIO_CRITERIA_UPDATE")
        BT.setDeaths(2)
        _G.C_ChallengeMode.GetDeathCount = function() return 2, 10 end
        env.WoW.fire("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
        env.WoW.advance(2)
        local second = MT:GetLastEmbedded()
        equal(second, snap, "B: the same table is reused, not a new allocation per render")
        equal(second.forcesPrimaryDisplayed, "600 / 686"); equal(second.forcesSecondaryDisplayed, "faltan 86")
        equal(second.penaltyDisplayed, "-0:10", "B: the published penalty is remembered")
        truthy(second.timestamp >= snap.timestamp)

        -- C: Blizzard hides its block (timer stopped) -> nothing of ours is shown,
        -- but the picture of the run stays exactly as it was.
        BT.stopTimer()
        env.WoW.advance(2)
        equal(EN:IsVisible(), false); equal(EN._displayed.thresholdMode, nil, "current state is gone")
        local kept = MT:GetLastEmbedded()
        truthy(kept, "C: hiding never erases the snapshot")
        equal(kept.forcesPrimaryDisplayed, "600 / 686"); equal(kept.penaltyDisplayed, "-0:10")
        equal(kept.thresholdMode, "NEXT"); equal(kept.attachmentHealthy, true)
        equal(#BT.foreign, 0, table.concat(BT.foreign, ","))
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env))
    end)
end)

test("dev.9 D/E/F/G: summary, preview and leaving the dungeon keep the snapshot; a new key replaces it", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local MT, TS, EN = MP.MitzuTracker, MP.TrackerState, MP.BlizzardTrackerEnhancer
        local BT = freshMock(); BT.install()
        runningKey(env, BT)
        local during = S.serialize(MT:GetLastEmbedded())
        truthy(MT:GetLastEmbedded().forcesPrimaryDisplayed, "a run was painted")

        -- D: the key completes and the floating summary takes over.
        env.WoW.advance(1200)
        crit.count, crit.bosses = 686, { true, true, false }
        env.WoW.fire("SCENARIO_CRITERIA_UPDATE")
        BT.setForces(false)
        env.WoW.advance(1)
        env.WoW.state.challengeActive = false
        env.WoW.fire("CHALLENGE_MODE_COMPLETED")
        env.WoW.fire("CHALLENGE_MODE_COMPLETED")
        BT.stopTimer()
        env.WoW.advance(4)
        equal(MT:GetMode(), "SUMMARY"); equal(MT:GetRenderMode(), "PREVIEW_FLOATING")
        local afterSummary = MT:GetLastEmbedded()
        truthy(afterSummary, "D: the summary does not replace the snapshot")
        equal(afterSummary.thresholdMode, "NEXT", "D: still the embedded values, not the summary window")
        truthy(afterSummary.paceDisplayed:find("RITMO", 1, true), "D: the pace of the run, not the result")
        equal(afterSummary.attachmentHealthy, true)
        -- Blizzard frees its bar at 100 %, so the last thing Mitzu painted under
        -- it was nothing: that is exactly what has to be remembered.
        equal(afterSummary.forcesLayoutMode, "NO_BAR"); equal(afterSummary.forcesPrimaryDisplayed, nil)
        local frozen = S.serialize(afterSummary)

        -- The bug report tells CURRENT and LAST apart while the summary is up.
        local report = MP.BugReport:Build()
        truthy(report:find("[LAST EMBEDDED RENDER]", 1, true), "the section exists")
        equal(reportValue(report, "renderMode"), "PREVIEW_FLOATING", "CURRENT is the summary window")
        equal(reportValue(report, "lastEmbedded.available"), "true")
        equal(reportValue(report, "lastEmbedded.thresholdMode"), "NEXT")
        equal(reportValue(report, "thresholdMode"), "nil", "CURRENT has no threshold any more")

        -- F: the summary expires and the player leaves the dungeon.
        env.WoW.advance(MT.SUMMARY_SECONDS + 1)
        equal(MT:GetMode(), "HIDDEN")
        S.leaveDungeon(env)
        env.WoW.advance(2)
        equal(MT:GetRenderMode(), "NONE"); equal(MT:IsVisible(), false)
        equal(S.serialize(MT:GetLastEmbedded()), frozen, "F: leaving the dungeon never erases the snapshot")
        report = MP.BugReport:Build()
        equal(reportValue(report, "trackerVisible"), "false")
        equal(reportValue(report, "renderMode"), "NONE", "CURRENT: nothing is being painted")
        equal(reportValue(report, "lastEmbedded.available"), "true", "still answerable after the key")
        equal(reportValue(report, "lastEmbedded.paceDisplayed"), afterSummary.paceDisplayed)
        truthy(tonumber(reportValue(report, "lastEmbedded.age")), "the age of the picture is reported")

        -- E: the floating preview simulates the same layout but is not a real render.
        equal(MT:SetPreview(true), true)
        env.WoW.advance(3)
        equal(MT:GetRenderMode(), "PREVIEW_FLOATING")
        equal(S.serialize(MT:GetLastEmbedded()), frozen, "E: the preview never overwrites the snapshot")
        truthy(not frozen:find("449", 1, true), "E: no preview data leaked in")
        MT:SetPreview(false)

        -- G: a brand new key replaces it as soon as it paints its first valid render.
        local generation = MT:GetLastEmbedded().attachGeneration
        local BT2 = freshMock(); BT2.install()
        runningKey(env, BT2, 8)
        local fresh = MT:GetLastEmbedded()
        equal(fresh.forcesPrimaryDisplayed, "343 / 686", "G: the new run owns the snapshot")
        truthy(fresh.attachGeneration > generation, "G: a new attachment generation")
        truthy(S.serialize(fresh) ~= during, "G: the old picture is gone")
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env))
    end)
end)

test("dev.9: the snapshot only follows a healthy embedded render", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local MT, EN = MP.MitzuTracker, MP.BlizzardTrackerEnhancer
        -- Running key with no Blizzard block at all: nothing was painted, nothing stored.
        startRun(env, 12)
        env.WoW.advance(3)
        equal(MT:GetRenderMode(), "EMBEDDED"); equal(EN:IsAttached(), false)
        equal(MT:GetLastEmbedded(), nil, "an unavailable block leaves no picture")
        local report = MP.BugReport:Build()
        equal(reportValue(report, "lastEmbedded.available"), "false")
        -- Attached but the block is not active yet: still nothing.
        local BT = freshMock(); BT.install()
        env.WoW.advance(1.1)
        equal(EN:IsAttached(), true); equal(EN:IsVisible(), false)
        equal(MT:GetLastEmbedded(), nil, "attached is not the same as painted")
        BT.activate(305, 1800); BT.setForces(true)
        env.WoW.advance(1.1)
        truthy(MT:GetLastEmbedded(), "the first visible render is the first picture")
        -- Kill switch: a disabled enhancer paints nothing, so it stores nothing new.
        local kept = S.serialize(MT:GetLastEmbedded())
        local build = MP.TrackerPresenter.BuildEmbedded
        MP.TrackerPresenter.BuildEmbedded = function() error("boom") end
        for _ = 1, 4 do BT.layout() end
        env.WoW.advance(2)
        MP.TrackerPresenter.BuildEmbedded = build
        equal(EN._disabled, true)
        equal(S.serialize(MT:GetLastEmbedded()), kept, "a disabled enhancer never refreshes the picture")
        equal(#BT.foreign, 0, table.concat(BT.foreign, ","))
    end)
end)

test("dev.9: RITMO stays readable and the forces columns share the Blizzard bar geometry", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local EN = MP.BlizzardTrackerEnhancer
        local BT = freshMock(); BT.install()
        runningKey(env, BT)

        -- The pace line is never dimmed as a whole: the confidence is the
        -- secondary part, in its own (grey, disabled) font.
        local alphas = {}
        local setAlpha = EN.elements.pace.SetAlpha
        EN.elements.pace.SetAlpha = function(self, v) alphas[#alphas + 1] = v; return setAlpha(self, v) end
        for _ = 1, 3 do EN:Render(EN._model, EN._opts, "TEST") end
        EN.elements.pace.SetAlpha = setAlpha
        for _, a in ipairs(alphas) do truthy(a >= 1, "the pace line is never faded: " .. tostring(a)) end
        equal(EN.FONT.pace, "GameFontHighlightSmall", "RITMO keeps a legible highlight font")
        equal(EN.FONT.secondary, "GameFontDisableSmall", "the confidence stays secondary")
        equal(EN.FONT.forces, "GameFontHighlightSmall")
        truthy(EN.COLOR.label ~= "a8a8b0", "dev.9 lifts the RITMO label out of near-grey")
        for _, font in pairs(EN.FONT) do truthy(not font:find("Huge"), "no big font competes with the timer") end
        truthy(EN.elements.pace:GetText():find("RITMO", 1, true), EN.elements.pace:GetText())

        -- Both columns hang from one row anchored to the real ends of the bar.
        local bar = BT.tracker.usedProgressBars[BT.tracker.ObjectivesBlock.forcesLine].Bar
        local row = EN.elements.forcesRoot
        equal(#row.__points, 2, "the row spans the whole bar")
        equal(row.__points[1][1], "TOPLEFT"); equal(row.__points[1][2], bar); equal(row.__points[1][3], "BOTTOMLEFT")
        equal(row.__points[2][1], "TOPRIGHT"); equal(row.__points[2][2], bar); equal(row.__points[2][3], "BOTTOMRIGHT")
        equal(row.__points[1][5], row.__points[2][5], "one single vertical gap under the bar")
        local left, right = EN.elements.forcesPrimary.__points[1], EN.elements.forcesSecondary.__points[1]
        equal(left[1], "BOTTOMLEFT"); equal(left[2], row); equal(left[3], "BOTTOMLEFT")
        equal(right[1], "BOTTOMRIGHT"); equal(right[2], row); equal(right[3], "BOTTOMRIGHT")
        equal(left[5], right[5], "same baseline for count and remaining")
        equal(left[4], -right[4], "symmetric inset: neither column leaves the bar")
        equal(EN._displayed.forcesLayoutMode, "SPLIT")
        equal(#BT.foreign, 0, "Blizzard's bar is only read: " .. table.concat(BT.foreign, ","))
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env))
    end)
end)

test("dev.9 Angry Keystones: deferred threshold, one pace, one percentage, snapshot says so", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        env.WoW.addonsLoaded.AngryKeystones = true
        local MP = _G.MitzuMPlus
        local MT, EN = MP.MitzuTracker, MP.BlizzardTrackerEnhancer
        local BT = freshMock(); BT.install()
        runningKey(env, BT)
        equal(EN._displayed.angryKeystones, true); equal(EN._displayed.thresholdMode, "DEFERRED")
        equal(EN.elements.threshold:GetText(), "", "Angry Keystones owns the threshold next to the clock")
        truthy(EN.elements.pace:GetText():find("RITMO", 1, true), "the pace is still Mitzu's")
        truthy(not (EN.elements.forcesPrimary:GetText() or ""):find("%%"), "no second percentage")
        truthy(not (EN.elements.forcesSecondary:GetText() or ""):find("%%"))
        equal(EN._displayed.forcesLayoutMode, "SPLIT", "the forces columns are not duplicated either")
        local snap = MT:GetLastEmbedded()
        equal(snap.angryKeystonesLoaded, true); equal(snap.thresholdMode, "DEFERRED")
        equal(snap.thresholdDisplayed, nil, "nothing to remember: Mitzu painted no threshold")
        truthy(snap.paceDisplayed:find("RITMO", 1, true))
        local report = MP.BugReport:Build()
        equal(reportValue(report, "lastEmbedded.angryKeystonesLoaded"), "true")
        equal(reportValue(report, "lastEmbedded.thresholdMode"), "DEFERRED")
        -- Without Angry Keystones the same run shows Mitzu's own threshold.
        env.WoW.addonsLoaded.AngryKeystones = nil
        env.WoW.advance(2)
        equal(EN._displayed.thresholdMode, "NEXT")
        equal(MT:GetLastEmbedded().thresholdMode, "NEXT")
        equal(#BT.foreign, 0, table.concat(BT.foreign, ","))
    end)
end)

test("dev.9 death penalty: only the published time lost, beside Blizzard's own counter", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local EN = MP.BlizzardTrackerEnhancer
        local BT = freshMock(); BT.install()
        runningKey(env, BT)
        equal(EN._displayed.penalty, nil, "deaths=0 timeLost=0: nothing")
        equal(EN.elements.penalty:GetText(), "")
        local cases = { { 1, 5, "-0:05" }, { 3, 15, "-0:15" }, { 12, 60, "-1:00" } }
        for _, case in ipairs(cases) do
            BT.setDeaths(case[1])
            _G.C_ChallengeMode.GetDeathCount = function() return case[1], case[2] end
            env.WoW.fire("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
            env.WoW.advance(1.1)
            equal(EN._displayed.penalty, case[3], "deaths=" .. case[1] .. " timeLost=" .. case[2])
            equal(EN.elements.penalty:GetText(), case[3])
            truthy(not EN.elements.penalty:GetText():find(tostring(case[1]) .. "$"),
                "the count is Blizzard's, never repeated")
        end
        -- The penalty hangs off Blizzard's death counter, which is only read.
        equal(EN.elements.penalty.__points[1][1], "RIGHT")
        equal(EN.elements.penalty.__points[1][2], BT.block.DeathCount)
        equal(EN.elements.penalty.__points[1][3], "LEFT")
        -- Deaths without a published time lost: nothing at all, never "-0:00".
        _G.C_ChallengeMode.GetDeathCount = function() return 4, nil end
        env.WoW.fire("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
        env.WoW.advance(1.1)
        equal(EN._displayed.penalty, nil); equal(EN.elements.penalty:GetText(), "")
        _G.C_ChallengeMode.GetDeathCount = function() return 4, 0 end
        env.WoW.fire("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
        env.WoW.advance(1.1)
        equal(EN._displayed.penalty, nil, "timeLost=0 is not a penalty")
        equal(#BT.foreign, 0, "Blizzard's DeathCount is never written: " .. table.concat(BT.foreign, ","))
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env))
    end)
end)

if #failures > 0 then error(string.format("TrackerVisual: %d failures\n%s", #failures, table.concat(failures, "\n")), 0) end
return { tests = tests, assertions = assertions }
