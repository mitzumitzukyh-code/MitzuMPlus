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
        equal(MP.VERSION, "1.1.0-dev.1")
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

        local before = #env.WoW.printed
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

if #failures > 0 then error(string.format("TrackerIntegration: %d failures\n%s", #failures, table.concat(failures, "\n")), 0) end
return { tests = tests, assertions = assertions }
