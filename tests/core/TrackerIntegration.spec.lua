-- TrackerAdapter inside the full addon: loads MitzuMPlus through its real TOC
-- with the simulated client and drives a key. The adapter must agree with the
-- 1.0 authorities (DungeonContext / ChallengeClock / KeystoneTracker), appear in
-- the Bug Report and survive a /reload in the middle of the key.
local tests, assertions, failures = 0, 0, {}
local function equal(a, b, l)
    assertions = assertions + 1
    if a ~= b then error((l or "equal") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function truthy(v, l) equal(not not v, true, l) end
local function test(n, f) tests = tests + 1; local ok, e = pcall(f); if not ok then failures[#failures + 1] = n .. ": " .. tostring(e) end end

local S = dofile("tests/harness/core_scenario.lua")

-- Scenario criteria as Blizzard exposes them (struct and legacy forms), driven
-- by `crit` so a test can move enemy forces and kill bosses.
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
end

local function errorsText(env) return table.concat(env.errors, "\n") end
local function lines(list) return table.concat(list, "\n") end

test("full TOC loads with the adapter and no load/runtime errors", function()
    S.isolated(function()
        local env = S.boot({})
        equal(#env.errors, 0, errorsText(env))
        local MP = _G.MitzuMPlus
        truthy(MP.TrackerAdapter, "TrackerAdapter registered")
        equal(MP.VERSION, "1.1.0-dev.6")
        equal((MP.TrackerAdapter:IsAvailable()), true)
        local loaded = table.concat(env.coreFiles, "\n")
        local a = loaded:find("RuntimeCapabilities.lua", 1, true)
        local b = loaded:find("Tracker/TrackerAdapter.lua", 1, true)
        local c = loaded:find("ChallengeClock.lua", 1, true)
        truthy(a and b and c and a < b and b < c, "load order RuntimeCapabilities < TrackerAdapter < ChallengeClock")
    end)
end)

test("pre-key and running key agree with 1.0 authorities", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local TA = MP.TrackerAdapter

        S.enterRuby(env)
        equal(MP.DungeonContext:GetState(), "PRE_KEY")
        local s = TA:GetSnapshot()
        equal(s.active, false); equal(s.keystoneLevel, nil); equal(s.elapsed, nil); equal(s.forcesPercent, nil)

        S.startKey(env, { level = 12 })
        equal(#env.errors, 0, errorsText(env))
        equal(MP.DungeonContext:GetState(), "RUNNING")
        -- The harness never creates MitzuMPlusCurrentRun; start the 1.0 tracker
        -- the way Core does so there is a legacy side to compare against.
        MP.KeystoneTracker:Start({ timeLimit = 1800, startTime = time(), dungeonName = "Ruby", keyLevel = 12 })

        env.WoW.advance(120)
        crit.count, crit.bosses[1] = 343, true
        env.WoW.fire("SCENARIO_CRITERIA_UPDATE")
        env.WoW.advance(1)
        equal(#env.errors, 0, errorsText(env))

        s = TA:GetSnapshot()
        equal(s.active, true); equal(s.mapID, 399); equal(s.keystoneLevel, 12)
        equal(s.timeLimit, 1800); equal(s.elapsed, 124)
        equal(s.forcesCurrent, 343); equal(s.forcesTotal, 686); equal(s.forcesPercent, 50)
        equal(s.forcesRemaining, 343); equal(s.bossesCompleted, 1); equal(s.bossesTotal, 3)
        equal(#s.warnings, 0, table.concat(s.warnings, ","))

        local parity = lines(TA:ParityLines(s))
        truthy(not parity:find("DIFF", 1, true), parity)
        truthy(parity:find("forcesPercent adapter=50 legacy=50 -> MATCH", 1, true), parity)
        truthy(parity:find("bossesCompleted adapter=1 legacy=1 -> MATCH", 1, true), parity)

        local recorded = lines(MP.FlightRecorder:Lines(200))
        truthy(recorded:find("ADAPTER_START", 1, true), recorded)
        truthy(recorded:find("ADAPTER_CAPS", 1, true), recorded)
    end)
end)

test("bug report and DEV command expose the adapter", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        S.enterRubyAndStartKey(env, { level = 10 })
        crit.count = 100
        env.WoW.advance(30)

        local report = MP.BugReport:Build()
        truthy(report:find("[TRACKER ADAPTER]", 1, true), "section present")
        truthy(report:find("forcesTotal=686", 1, true), report)
        truthy(report:find("keystoneLevel=10", 1, true), report)
        truthy(report:find("sectionsFailed=none", 1, true), report)
        -- The simulated client has no Blizzard Objective Tracker: the probe must
        -- say so instead of failing.
        truthy(report:find("[BLIZZARD TRACKER]", 1, true), "probe section present")
        truthy(report:find("enhanceable=false", 1, true), report)

        local before = #env.WoW.printed
        MP:HandleSlashCommand("dev blizzard")
        MP:HandleSlashCommand("dev tracker")
        MP:HandleSlashCommand("dev caps")
        MP:HandleSlashCommand("dev")
        equal(#env.WoW.errors, 0, table.concat(env.WoW.errors, "\n"))
        truthy(#env.WoW.printed > before, "dev commands print feedback")
        local help = {}
        local print0 = MP.Print
        MP.Print = function(_, msg) help[#help + 1] = tostring(msg) end
        MP:PrintHelp()
        MP.Print = print0
        truthy(not lines(help):find("dev", 1, true), "DEV tools are not advertised in product help")
    end)
end)

test("reload during the key: timer gap is reported, then recovered", function()
    local saved = S.isolated(function()
        local env = S.boot({})
        installScenario()
        S.enterRubyAndStartKey(env, { level = 13 })
        env.WoW.advance(572)
        crit.count = 200
        return S.captureForReload(env)
    end)
    S.isolated(function()
        local env = S.bootAfterReload(saved, { timerDelay = 5 })
        installScenario()
        crit.count = 200
        env.WoW.fire("PLAYER_ENTERING_WORLD", false, true)
        local TA = _G.MitzuMPlus.TrackerAdapter
        local s = TA:GetSnapshot()
        equal(s.active, true); equal(s.elapsed, nil)
        local warned = table.concat(s.warnings, ",")
        truthy(warned:find("ACTIVE_WITHOUT_TIMER", 1, true), warned)
        equal(s.forcesCurrent, 200, "criteria do not depend on the timer")
        env.WoW.advance(6)
        s = TA:GetSnapshot()
        truthy(s.elapsed and s.elapsed >= 580, "server timer recovered: " .. tostring(s.elapsed))
        equal(#env.errors, 0, errorsText(env))
    end)
end)

test("key completion: adapter reports inactive without active-state warnings", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        S.enterRubyAndStartKey(env, { level = 11 })
        env.WoW.advance(1500)
        crit.count, crit.bosses = 686, { true, true, true }
        env.WoW.fire("SCENARIO_CRITERIA_UPDATE")
        env.WoW.state.challengeActive = false
        env.WoW.fire("CHALLENGE_MODE_COMPLETED")
        env.WoW.advance(5)
        local s = MP.TrackerAdapter:GetSnapshot()
        equal(s.active, false)
        for _, w in ipairs(s.warnings) do truthy(not w:find("^ACTIVE_"), w) end
        local recorded = lines(MP.FlightRecorder:Lines(200))
        truthy(recorded:find("ADAPTER_COMPLETED", 1, true), recorded)
    end)
end)

test("TrackerState follows a real key through the full addon", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local TS = MP.TrackerState
        truthy(TS, "TrackerState registered")
        equal(TS:GetStatus(), "IDLE")

        S.enterRuby(env)
        env.WoW.advance(1)
        equal(TS:GetStatus(), "IDLE", "pre-key")

        S.startKey(env, { level = 9 })
        env.WoW.advance(1)
        equal(TS:GetStatus(), "RUNNING")
        local s = TS:GetSnapshot()
        equal(s.mapID, 399); equal(s.keystoneLevel, 9); equal(s.timeLimit, 1800); equal(s.recovered, false)

        env.WoW.advance(200)
        crit.count, crit.bosses[1] = 343, true
        env.WoW.fire("SCENARIO_CRITERIA_UPDATE")
        env.WoW.advance(1)
        s = TS:GetSnapshot()
        equal(s.forcesCurrent, 343); equal(s.forcesPercent, 50); equal(s.forcesRemaining, 343)
        equal(s.bossesCompleted, 1); equal(s.bossesTotal, 3); equal(s.quantityString, nil)
        local elapsed = TS:GetElapsed()
        truthy(elapsed >= 200 and elapsed <= 206, "elapsed follows the server timer: " .. tostring(elapsed))
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env))

        local report = MP.BugReport:Build()
        truthy(report:find("[TRACKER STATE]", 1, true), "state section")
        truthy(report:find("status=RUNNING", 1, true), report)
        truthy(report:find("forcesPercent=50.00", 1, true), report)
        local printed = #env.WoW.printed
        MP:HandleSlashCommand("dev state")
        equal(#env.WoW.errors, 0, table.concat(env.WoW.errors, "\n"))
        truthy(#env.WoW.printed >= printed)

        -- Last boss and last forces arrive before the completion event.
        crit.count, crit.bosses = 686, { true, true, true }
        env.WoW.fire("SCENARIO_CRITERIA_UPDATE")
        env.WoW.advance(1)
        env.WoW.state.challengeActive = false
        env.WoW.fire("CHALLENGE_MODE_COMPLETED")
        env.WoW.advance(2)
        equal(TS:GetStatus(), "COMPLETED")
        s = TS:GetSnapshot()
        equal(s.forcesPercent, 100); equal(s.bossesCompleted, 3); truthy(s.finalElapsed and s.finalElapsed >= 200)
        -- The mock stops exposing criteria once inactive. 100 % and 3/3 were read
        -- before the event and are terminal, so the final snapshot is converged.
        equal(s.completionConverged, true); equal(s.completionCriteriaIncomplete, false)
        equal(s.forcesStale, false); equal(s.bossesStale, false)
        local recorded = lines(MP.FlightRecorder:Lines(200))
        truthy(recorded:find("STATE_RUN_STARTED", 1, true) and recorded:find("STATE_RUN_COMPLETED", 1, true), recorded)
    end)
end)

test("TrackerState recovers a key after /reload", function()
    local saved = S.isolated(function()
        local env = S.boot({})
        installScenario()
        S.enterRubyAndStartKey(env, { level = 14 })
        env.WoW.advance(640)
        crit.count = 250
        return S.captureForReload(env)
    end)
    S.isolated(function()
        local env = S.bootAfterReload(saved, { timerDelay = 4 })
        installScenario()
        crit.count = 250
        env.WoW.fire("PLAYER_ENTERING_WORLD", false, true)
        env.WoW.advance(0.5)
        local TS = _G.MitzuMPlus.TrackerState
        equal(TS:GetStatus(), "PENDING", "timer not back yet")
        equal(TS:GetSnapshot().forcesCurrent, 250)
        env.WoW.advance(5)
        equal(TS:GetStatus(), "RUNNING")
        equal(TS:GetSnapshot().recovered, true)
        truthy(TS:GetElapsed() >= 640, "server time, not time since reload: " .. tostring(TS:GetElapsed()))
        equal(#env.errors, 0, errorsText(env))
    end)
end)

-- Real Retail dev.4 shape: the completion event arrives while the last boss is
-- not visible yet. The 1.0 history must still be written exactly once while
-- TrackerState waits for the criteria, even with repeated completion events.
test("completion convergence through the full addon keeps history finalization single", function()
    S.isolated(function()
        local env = S.boot({})
        installScenario()
        local MP = _G.MitzuMPlus
        local TS = MP.TrackerState
        _G.GetInventoryItemLink = _G.GetInventoryItemLink or function() return nil end
        S.enterRubyAndStartKey(env, { level = 12 })
        MP:OnChallengeStart()
        truthy(_G.MitzuMPlusCurrentRun, "1.0 run created")
        local function historyCount()
            local n = 0
            for _ in pairs(MP.db.global.runs or {}) do n = n + 1 end
            return n
        end
        local before = historyCount()

        env.WoW.advance(1500)
        crit.count, crit.bosses = 686, { true, true, false }
        env.WoW.fire("SCENARIO_CRITERIA_UPDATE")
        env.WoW.advance(1)
        equal(TS:GetStatus(), "RUNNING"); equal(TS:GetSnapshot().bossesCompleted, 2)

        env.WoW.fire("CHALLENGE_MODE_COMPLETED")
        equal(TS:GetStatus(), "COMPLETING")
        env.WoW.fire("CHALLENGE_MODE_COMPLETED")
        env.WoW.advance(0.4)
        crit.bosses[3] = true                         -- last boss published late
        env.WoW.advance(0.3)
        equal(TS:GetStatus(), "COMPLETED")
        local s = TS:GetSnapshot()
        equal(s.bossesCompleted, 3); equal(s.bossesTotal, 3); equal(s.forcesPercent, 100)
        equal(s.completionConverged, true); equal(s.completionCriteriaIncomplete, false)
        truthy(s.completionAttempts >= 2, "re-read inside the window: " .. tostring(s.completionAttempts))
        truthy(s.finalElapsed >= 1500 and s.finalElapsed <= 1510, "final time at the event: " .. tostring(s.finalElapsed))

        env.WoW.state.challengeActive = false
        env.WoW.fire("CHALLENGE_MODE_COMPLETED")
        env.WoW.advance(10)
        equal(historyCount(), before + 1, "history finalized exactly once")
        equal(TS._stats.duplicateCompletions, 2)
        equal(TS:GetSnapshot().bossesCompleted, 3, "frozen after the window")
        equal(#env.errors + #env.WoW.errors, 0, errorsText(env) .. table.concat(env.WoW.errors, "\n"))

        local recorded = lines(MP.FlightRecorder:Lines(400))
        local _, completedRecords = recorded:gsub("STATE_RUN_COMPLETED", "")
        equal(completedRecords, 1, recorded)
        truthy(recorded:find("STATE_COMPLETION_BEGIN", 1, true), recorded)

        local report = MP.BugReport:Build()
        truthy(report:find("completionConverged=true", 1, true), report)
        truthy(report:find("completionCriteriaIncomplete=false", 1, true), report)
        truthy(report:find("status=COMPLETED", 1, true), report)
        MP:HandleSlashCommand("dev state")
        equal(#env.WoW.errors, 0, table.concat(env.WoW.errors, "\n"))
    end)
end)

if #failures > 0 then error(string.format("TrackerIntegration: %d failures\n%s", #failures, table.concat(failures, "\n")), 0) end
return { tests = tests, assertions = assertions }
