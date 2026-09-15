-- TrackerAdapter: normalization of Blizzard Challenge Mode / scenario APIs.
-- Pure mocks, no frames. Every API is optional and may be missing, fail,
-- return partial data or return Midnight secret values.
local tests, assertions, failures = 0, 0, {}
local function equal(a, b, l)
    assertions = assertions + 1
    if a ~= b then error((l or "equal") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function near(a, b, eps, l)
    assertions = assertions + 1
    if type(a) ~= "number" or math.abs(a - b) > (eps or 1e-6) then
        error((l or "near") .. ": " .. tostring(a) .. " !~ " .. tostring(b), 2)
    end
end
local function truthy(v, l) equal(not not v, true, l) end
local function has(list, value, l)
    assertions = assertions + 1
    for _, v in ipairs(list or {}) do if v == value then return end end
    error((l or "has") .. ": " .. tostring(value) .. " not in {" .. table.concat(list or {}, ",") .. "}", 2)
end
local function test(n, f) tests = tests + 1; local ok, e = pcall(f); if not ok then failures[#failures + 1] = n .. ": " .. tostring(e) end end

-- Secret values: any table registered here is "secret" for issecretvalue.
local SECRETS = setmetatable({}, { __mode = "k" })
local function secret() local s = {}; SECRETS[s] = true; return s end

local GLOBALS = { "C_ChallengeMode", "C_Scenario", "C_ScenarioInfo", "C_MythicPlus", "C_EventUtils",
    "GetWorldElapsedTimers", "GetWorldElapsedTime", "LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE",
    "LE_SCENARIO_TYPE_CHALLENGE_MODE", "issecretvalue", "canaccessvalue", "GetTime", "GetBuildInfo" }

local W   -- simulated client state
local records

-- Blizzard-like criteria for a 4-boss dungeon with enemy forces (struct form).
local function criteria(count, total, qty, bossesDone)
    local list = {}
    for i = 1, 4 do
        list[#list + 1] = { description = "Boss " .. i, completed = i <= (bossesDone or 0),
            quantity = (i <= (bossesDone or 0)) and 1 or 0, totalQuantity = 1, quantityString = "",
            isWeightedProgress = false, elapsed = 0, duration = 0, criteriaID = 100 + i }
    end
    list[#list + 1] = { description = "Enemy Forces", completed = count ~= nil and total ~= nil and count >= total,
        quantity = qty, totalQuantity = total, quantityString = count and (tostring(count) .. "%") or "",
        isWeightedProgress = true, criteriaID = 200 }
    return list
end

local function install(opts)
    opts = opts or {}
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
    W = { active = false, mapID = nil, level = 0, affixes = {}, timers = {}, criteria = nil,
          deaths = 0, timeLost = 0, now = 5000, scenarioType = 8 }
    _G.GetTime = function() return W.now end
    _G.GetBuildInfo = function() return "12.1.5", "69594", "Aug 28 2026", 120105 end
    _G.issecretvalue = function(v) return SECRETS[v] == true end
    _G.LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE = 1
    _G.LE_SCENARIO_TYPE_CHALLENGE_MODE = 8
    _G.C_ChallengeMode = {
        IsChallengeModeActive = function() return W.active end,
        GetActiveChallengeMapID = function() return W.mapID end,
        GetActiveKeystoneInfo = function() return W.level, W.affixes, false end,
        GetMapUIInfo = function(id)
            if id == 399 then return "Ruby Life Pools", 399, 1800, 123, 456 end
            return nil
        end,
        GetDeathCount = function() return W.deaths, W.timeLost end,
        GetChallengeCompletionInfo = function() return nil end,
    }
    _G.GetWorldElapsedTimers = function()
        local ids = {}
        for _, t in ipairs(W.timers) do ids[#ids + 1] = t.id end
        return table.unpack(ids)
    end
    _G.GetWorldElapsedTime = function(id)
        for _, t in ipairs(W.timers) do
            if t.id == id then return "", t.elapsed, t.type end
        end
        return nil
    end
    _G.C_ScenarioInfo = {
        GetScenarioInfo = function()
            if not W.criteria then return nil end
            return { name = "Ruby Life Pools", currentStage = 1, numStages = 1, type = W.scenarioType, scenarioID = 1 }
        end,
        GetScenarioStepInfo = function()
            if not W.criteria then return nil end
            return { title = "", numCriteria = #W.criteria }
        end,
        GetCriteriaInfo = function(i) return W.criteria and W.criteria[i] or nil end,
    }
    _G.C_EventUtils = { IsEventValid = function(e) return e ~= "CHALLENGE_MODE_DEATH_COUNT_UPDATED" end }
    if opts.legacyOnly then
        _G.C_ScenarioInfo = nil
        _G.C_Scenario = {
            GetInfo = function()
                if not W.criteria then return nil end
                return "Ruby Life Pools", 1, 1, 0, false, false, false, 0, 0, W.scenarioType
            end,
            GetStepInfo = function()
                if not W.criteria then return nil end
                return "", "", #W.criteria
            end,
            GetCriteriaInfo = function(i)
                local c = W.criteria and W.criteria[i]
                if not c then return nil end
                return c.description, 0, c.completed, c.quantity, c.totalQuantity, 0, 0,
                    c.quantityString, c.criteriaID, c.duration, c.elapsed, false, c.isWeightedProgress
            end,
        }
    end
    records = {}
    _G.MitzuMPlus = {
        VERSION = "1.1.0-dev.1",
        FlightRecorder = { Record = function(_, s, e, d) records[#records + 1] = { s = s, e = e, d = d } end },
        EventBus = { handlers = {}, On = function(self, ev, fn) self.handlers[ev] = fn end },
    }
    dofile("MitzuMPlus/modules/Tracker/TrackerAdapter.lua")
    return _G.MitzuMPlus.TrackerAdapter
end

local function running(level, elapsed)
    W.active, W.mapID, W.level, W.affixes = true, 399, level or 12, { 9, 10 }
    W.timers = { { id = 7, elapsed = elapsed or 600, type = 1 } }
end

-- ---------------------------------------------------------------------------
-- API availability and guards
-- ---------------------------------------------------------------------------

test("API unavailable: every getter degrades to nil without throwing", function()
    local TA = install()
    _G.C_ChallengeMode, _G.C_ScenarioInfo, _G.GetWorldElapsedTimers, _G.GetWorldElapsedTime = nil, nil, nil, nil
    local ok, missing = TA:IsAvailable()
    equal(ok, false); equal(missing, "C_ChallengeMode.IsChallengeModeActive")
    equal(TA:IsChallengeActive(), nil); equal(TA:GetMapID(), nil); equal(TA:GetKeystoneLevel(), nil)
    equal(TA:GetTimeLimit(399), nil); equal(TA:GetElapsedTime(), nil); equal(TA:GetCriteria(), nil)
    local s = TA:GetSnapshot()
    equal(s.active, nil); equal(s.forcesPercent, nil); equal(s.bossesTotal, nil)
    has(s.warnings, "CHALLENGE_STATE_UNKNOWN")
    equal(TA._usage["C_ChallengeMode.IsChallengeModeActive"].status, "MISSING")
end)

test("an API that exists but throws is reported as ERROR, not trusted", function()
    local TA = install()
    _G.C_ChallengeMode.IsChallengeModeActive = function() error("boom") end
    equal(TA:IsChallengeActive(), nil)
    local u = TA._usage["C_ChallengeMode.IsChallengeModeActive"]
    equal(u.status, "ERROR"); equal(u.errors, 1); truthy(u.lastError:find("boom"))
    equal((TA:IsAvailable()), true, "existing but failing API still counts as present")
end)

test("nil return is EMPTY and zero map/level mean no key", function()
    local TA = install()
    equal(TA:GetMapID(), nil)
    equal(TA._usage["C_ChallengeMode.GetActiveChallengeMapID"].status, "EMPTY")
    W.mapID = 0; equal(TA:GetMapID(), nil)
    W.level = 0; equal(TA:GetKeystoneLevel(), nil)
end)

test("secret values are never used as data", function()
    local TA = install()
    W.active = secret()
    equal(TA:IsChallengeActive(), nil)
    running(12)
    W.level = secret()
    equal(TA:GetKeystoneLevel(), nil)
    equal(TA.IsReadable(nil), false); equal(TA.IsSecret(secret()), true)
    _G.issecretvalue = function() error("cannot ask") end
    equal(TA.IsReadable(5), false, "failing secret check is treated as unreadable")
end)

test("canaccessvalue=false marks a value unreadable", function()
    local TA = install()
    _G.canaccessvalue = function(v) return v ~= 42 end
    equal(TA.Number(42), nil); equal(TA.Number(41), 41)
end)

-- ---------------------------------------------------------------------------
-- Challenge mode, map, keystone
-- ---------------------------------------------------------------------------

test("pre-key: inside dungeon without key", function()
    local TA = install()
    equal(TA:IsChallengeActive(), false)
    equal(TA:GetMapID(), nil); equal(TA:GetKeystoneLevel(), nil); equal(TA:GetElapsedTime(), nil)
    local s = TA:GetSnapshot()
    equal(s.active, false); equal(#s.warnings, 0, "pre-key is a clean state")
end)

test("running key: map, level, affixes, limit", function()
    local TA = install()
    running(14)
    equal(TA:IsChallengeActive(), true); equal(TA:GetMapID(), 399)
    local level, affixes, charged = TA:GetKeystoneLevel()
    equal(level, 14); equal(#affixes, 2); equal(affixes[1], 9); equal(charged, false)
    local info = TA:GetMapInfo(399)
    equal(info.name, "Ruby Life Pools"); equal(info.timeLimit, 1800)
    equal(TA:GetTimeLimit(), 1800)
end)

test("unknown map returns nil info and nil limit", function()
    local TA = install()
    running(10); W.mapID = 9999
    equal(TA:GetMapInfo(9999), nil); equal(TA:GetTimeLimit(), nil)
    local s = TA:GetSnapshot()
    equal(s.mapID, 9999); equal(s.mapName, nil); equal(s.timeLimit, nil); equal(s.timeRemaining, nil)
end)

test("death count keeps zero as a real value and rejects garbage", function()
    local TA = install()
    local d, t = TA:GetDeathCount(); equal(d, 0); equal(t, 0)
    W.deaths, W.timeLost = 3, 15; d, t = TA:GetDeathCount(); equal(d, 3); equal(t, 15)
    W.deaths = -1; equal(TA:GetDeathCount(), nil)
    W.deaths, W.timeLost = 2, secret(); d, t = TA:GetDeathCount(); equal(d, 2); equal(t, nil)
end)

-- ---------------------------------------------------------------------------
-- Server timer
-- ---------------------------------------------------------------------------

test("timer: picks the challenge-mode timer among several", function()
    local TA = install()
    W.timers = { { id = 3, elapsed = 50, type = 0 }, { id = 7, elapsed = 912, type = 1 } }
    local e, id, source = TA:GetElapsedTime()
    equal(e, 912); equal(id, 7); equal(source, "WORLD_ELAPSED_TIMER")
end)

test("timer: no challenge timer -> nil, never 0", function()
    local TA = install()
    W.timers = { { id = 3, elapsed = 50, type = 0 } }
    equal(TA:GetElapsedTime(), nil)
    W.timers = {}
    equal(TA:GetElapsedTime(), nil)
end)

test("timer: without the type constant the first timer is flagged untyped", function()
    local TA = install()
    _G.LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE = nil
    W.timers = { { id = 2, elapsed = 30, type = 99 } }
    local e, _, source = TA:GetElapsedTime()
    equal(e, 30); equal(source, "WORLD_ELAPSED_TIMER_UNTYPED")
end)

test("timer boundaries: zero, exact limit, overtime, negative", function()
    local TA = install()
    running(10, 0)
    local s = TA:GetSnapshot(); equal(s.elapsed, 0); equal(s.timeRemaining, 1800)
    W.timers[1].elapsed = 1800; s = TA:GetSnapshot(); equal(s.timeRemaining, 0)
    W.timers[1].elapsed = 1834; s = TA:GetSnapshot(); equal(s.timeRemaining, -34)
    W.timers[1].elapsed = -5; equal(TA:GetElapsedTime(), nil)
    equal(TA.FormatTime(-34), "-0:34"); equal(TA.FormatTime(1800), "30:00"); equal(TA.FormatTime(nil), "nil")
end)

test("reload during challenge: timer gap is a warning, then recovers", function()
    local TA = install()
    running(12, 575)
    W.criteria = criteria(100, 686, 14, 1)
    local saved = W.timers; W.timers = {}
    local s = TA:GetSnapshot()
    equal(s.active, true); equal(s.elapsed, nil); has(s.warnings, "ACTIVE_WITHOUT_TIMER")
    near(s.forcesPercent, 100 / 686 * 100, 1e-9, "forces still readable during timer gap")
    W.timers = saved
    s = TA:GetSnapshot(); equal(s.elapsed, 575); equal(#s.warnings, 0)
end)

-- ---------------------------------------------------------------------------
-- Criteria
-- ---------------------------------------------------------------------------

test("challenge start before criteria populate: honest partial snapshot", function()
    local TA = install()
    running(12, 1)
    local s = TA:GetSnapshot()
    equal(s.criteriaCount, nil); equal(s.bossesTotal, nil); equal(s.forcesPercent, nil)
    has(s.warnings, "ACTIVE_WITHOUT_CRITERIA")
end)

test("struct criteria are normalized with kind and source", function()
    local TA = install()
    running(); W.criteria = criteria(183, 729, 25, 2)
    local list = TA:GetCriteria()
    equal(list.numCriteria, 5); equal(list.source, "C_ScenarioInfo"); equal(list.partial, false)
    equal(list.criteria[1].kind, "BOSS"); equal(list.criteria[5].kind, "ENEMY_FORCES")
    equal(list.criteria[5].source, "C_ScenarioInfo")
    equal(TA:GetScenarioInfo().isChallengeMode, true)
end)

test("legacy multi-return criteria give the same result", function()
    local TA = install({ legacyOnly = true })
    running(); W.criteria = criteria(183, 729, 25, 2)
    local list = TA:GetCriteria()
    equal(list.source, "C_Scenario"); equal(list.criteria[5].source, "C_Scenario")
    local f = TA:GetEnemyForces()
    equal(f.current, 183); equal(f.total, 729); near(f.percent, 183 / 729 * 100)
    local b = TA:GetBossProgress(); equal(b.completed, 2); equal(b.total, 4)
    local scen = TA:GetScenarioInfo(); equal(scen.source, "C_Scenario"); equal(scen.isChallengeMode, true)
end)

test("struct step without numCriteria falls back to legacy step", function()
    local TA = install()
    running(); W.criteria = criteria(10, 686, 1, 0)
    _G.C_ScenarioInfo.GetScenarioStepInfo = function() return { title = "" } end
    _G.C_Scenario = { GetStepInfo = function() return "", "", #W.criteria end }
    local step = TA:GetStepInfo(); equal(step.numCriteria, 5); equal(step.source, "C_Scenario")
end)

test("partial criteria: unreadable entries and secret fields are flagged", function()
    local TA = install()
    running(); W.criteria = criteria(300, 686, 43, 1)
    W.criteria[2] = nil
    local secretCount = secret()
    W.criteria[5].quantityString = secretCount
    local list = TA:GetCriteria()
    equal(list.partial, true); equal(list.missing, 1); equal(#list.criteria, 4)
    local ef = list.criteria[4]
    equal(ef.kind, "ENEMY_FORCES"); equal(ef.quantityString, nil); has(ef.secret, "quantityString")
    local f = TA.PickEnemyForces(list.criteria)
    equal(f.source, "QUANTITY_PERCENT"); equal(f.percent, 43); equal(f.current, nil); equal(f.remaining, nil)
    equal(f.remainingPercent, 57)
    has(TA:GetSnapshot().warnings, "CRITERIA_PARTIAL")
end)

test("numCriteria zero means no scenario, not an empty key", function()
    local TA = install()
    W.criteria = {}
    equal(TA:GetCriteria(), nil); equal(TA:GetEnemyForces(), nil); equal(TA:GetBossProgress(), nil)
end)

-- ---------------------------------------------------------------------------
-- Enemy forces
-- ---------------------------------------------------------------------------

local function ef(qs, total, qty, completed)
    return { isWeightedProgress = true, quantityString = qs, totalQuantity = total, quantity = qty, completed = completed }
end

test("forces 0%", function()
    local TA = install()
    local f = TA.NormalizeEnemyForces(ef("0%", 686, 0))
    equal(f.current, 0); equal(f.total, 686); equal(f.percent, 0)
    equal(f.remaining, 686); equal(f.remainingPercent, 100); equal(f.source, "COUNT_TOTAL")
end)

test("forces 50%", function()
    local TA = install()
    local f = TA.NormalizeEnemyForces(ef("343%", 686, 50))
    equal(f.current, 343); near(f.percent, 50); equal(f.remaining, 343); near(f.remainingPercent, 50)
    equal(f.mismatch, nil)
end)

test("forces 100% and above total never exceed 100", function()
    local TA = install()
    local f = TA.NormalizeEnemyForces(ef("686%", 686, 100, true))
    equal(f.percent, 100); equal(f.remaining, 0); equal(f.remainingPercent, 0); equal(f.completed, true)
    f = TA.NormalizeEnemyForces(ef("700%", 686, 100, true))
    equal(f.source, "QUANTITY_PERCENT"); equal(f.percent, 100); equal(f.warning, "COUNT_EXCEEDS_TOTAL")
end)

test("forces: measured Retail 12.1.0 samples", function()
    local TA = install()
    -- From real SavedVariables of 1.0.0-beta.1 runs.
    local f = TA.NormalizeEnemyForces(ef("183%", 729, 25)); near(f.percent, 25.10288065843622, 1e-9); equal(f.mismatch, nil)
    f = TA.NormalizeEnemyForces(ef("175%", 686, 25)); near(f.percent, 25.51020408163265, 1e-9)
    f = TA.NormalizeEnemyForces(ef("252%", 686, 36)); near(f.percent, 36.73469387755102, 1e-9)
    f = TA.NormalizeEnemyForces(ef("59%", 551, 10)); near(f.percent, 10.707803992740472, 1e-9)
end)

test("forces: missing data and nil values", function()
    local TA = install()
    equal(TA.NormalizeEnemyForces(nil), nil)
    equal(TA.NormalizeEnemyForces({ isWeightedProgress = false, quantityString = "5%", totalQuantity = 10 }), nil)
    equal(TA.NormalizeEnemyForces(ef(nil, nil, nil)), nil)
    equal(TA.NormalizeEnemyForces(ef("", 0, nil)), nil)
    local f = TA.NormalizeEnemyForces(ef("", 686, 12))
    equal(f.source, "QUANTITY_PERCENT"); equal(f.percent, 12); equal(f.current, nil)
    f = TA.NormalizeEnemyForces(ef("120%", nil, 17))
    equal(f.source, "QUANTITY_PERCENT"); equal(f.total, nil); equal(f.percent, 17)
    equal(TA.NormalizeEnemyForces(ef("", 686, 250)), nil, "out-of-range quantity is not a percent")
    f = TA.NormalizeEnemyForces(ef(nil, 686, nil, true))
    equal(f.source, "COMPLETED_FLAG"); equal(f.percent, 100); equal(f.remaining, 0)
end)

test("forces: disagreement with official quantity is flagged, count still wins", function()
    local TA = install()
    local f = TA.NormalizeEnemyForces(ef("35%", 686, 35))
    equal(f.source, "COUNT_TOTAL"); near(f.percent, 35 / 686 * 100); equal(f.mismatch, true)
    equal(f.warning, "PERCENT_MISMATCH")
end)

test("forces count parser", function()
    local TA = install()
    equal(TA.ParseForcesCount("183%"), 183); equal(TA.ParseForcesCount(" 183 %"), 183)
    equal(TA.ParseForcesCount("183"), 183); equal(TA.ParseForcesCount("183/729"), 183)
    equal(TA.ParseForcesCount("1,234%"), 1234); equal(TA.ParseForcesCount("1.234%"), 1234)
    equal(TA.ParseForcesCount("25.10%"), nil); equal(TA.ParseForcesCount("%"), nil)
    equal(TA.ParseForcesCount(""), nil); equal(TA.ParseForcesCount(nil), nil)
    equal(TA.ParseForcesCount(12), 12); equal(TA.ParseForcesCount(secret()), nil)
end)

test("only the first weighted criterion is enemy forces (BUG EF-2)", function()
    local TA = install()
    local list = {
        TA.NormalizeCriterion(1, ef("200%", 686, 29), "t"),
        TA.NormalizeCriterion(2, ef("686%", 686, 100, true), "t"),
        TA.NormalizeCriterion(3, { isWeightedProgress = false, completed = true, description = "Boss" }, "t"),
    }
    local f, seen = TA.PickEnemyForces(list)
    near(f.percent, 200 / 686 * 100); equal(seen, 2)
    local b = TA.NormalizeBosses(list); equal(b.total, 1, "extra weighted criterion is not a boss")
    running(); W.criteria = { list[1], list[2] }
    W.criteria = { ef("200%", 686, 29), ef("686%", 686, 100, true) }
    has(TA:GetSnapshot().warnings, "MULTIPLE_WEIGHTED_CRITERIA")
end)

test("active key with criteria but no weighted criterion warns", function()
    local TA = install()
    running(); W.criteria = criteria(10, 686, 1, 0); W.criteria[5] = nil
    local s = TA:GetSnapshot()
    equal(s.forcesPercent, nil); equal(s.bossesTotal, 4); has(s.warnings, "ACTIVE_WITHOUT_FORCES")
end)

-- ---------------------------------------------------------------------------
-- Bosses
-- ---------------------------------------------------------------------------

test("boss state: 2/4 with names and order", function()
    local TA = install()
    running(); W.criteria = criteria(300, 686, 43, 2)
    local b = TA:GetBossProgress()
    equal(b.completed, 2); equal(b.total, 4); equal(#b.list, 4)
    equal(b.list[1].name, "Boss 1"); equal(b.list[1].completed, true); equal(b.list[3].completed, false)
end)

test("boss state: unclassified criteria are not guessed as bosses", function()
    local TA = install()
    local list = {
        TA.NormalizeCriterion(1, { description = "Boss", completed = true }, "t"),
        TA.NormalizeCriterion(2, { description = "Boss", completed = false, isWeightedProgress = false }, "t"),
    }
    equal(list[1].kind, "UNKNOWN")
    local b = TA.NormalizeBosses(list); equal(b.total, 1); equal(b.unknown, 1); equal(b.completed, 0)
    equal(TA.NormalizeBosses(nil).total, 0)
    running(); W.criteria = { { description = "?", completed = false }, ef("1%", 686, 0) }
    has(TA:GetSnapshot().warnings, "UNCLASSIFIED_CRITERIA")
end)

-- ---------------------------------------------------------------------------
-- Snapshot lifecycle
-- ---------------------------------------------------------------------------

test("full running snapshot", function()
    local TA = install()
    running(15, 1080); W.criteria = criteria(412, 686, 60, 3); W.deaths, W.timeLost = 4, 20
    local s = TA:GetSnapshot()
    equal(s.adapterVersion, 1); equal(s.available, true); equal(s.active, true)
    equal(s.mapID, 399); equal(s.mapName, "Ruby Life Pools"); equal(s.keystoneLevel, 15)
    equal(s.elapsed, 1080); equal(s.timeLimit, 1800); equal(s.timeRemaining, 720); equal(s.timerID, 7)
    equal(s.deaths, 4); equal(s.deathTimeLost, 20)
    equal(s.forcesCurrent, 412); equal(s.forcesTotal, 686); near(s.forcesPercent, 412 / 686 * 100)
    equal(s.forcesRemaining, 274); near(s.forcesRemainingPercent, 100 - 412 / 686 * 100)
    equal(s.bossesCompleted, 3); equal(s.bossesTotal, 4); equal(s.criteriaSource, "C_ScenarioInfo")
    equal(s.scenarioIsChallengeMode, true); equal(s.timestamp, 5000); equal(#s.warnings, 0)
end)

test("challenge end: inactive after completion keeps last criteria readable", function()
    local TA = install()
    running(15, 1700); W.criteria = criteria(686, 686, 100, 4)
    W.active, W.mapID, W.timers = false, nil, {}
    local s = TA:GetSnapshot()
    equal(s.active, false); equal(s.mapID, nil); equal(s.elapsed, nil)
    equal(s.bossesCompleted, 4); equal(s.forcesPercent, 100)
    equal(#s.warnings, 0, "no ACTIVE_* warnings once the challenge is over")
end)

-- ---------------------------------------------------------------------------
-- Capabilities, logging, report
-- ---------------------------------------------------------------------------

test("capability probe covers functions, constants and events", function()
    local TA = install()
    local caps = TA:ProbeCapabilities()
    local by = {}
    for _, c in ipairs(caps) do by[c.path] = c end
    equal(by["C_ChallengeMode.IsChallengeModeActive"].status, "AVAILABLE")
    equal(by["C_ChallengeMode.IsChallengeModeActive"].required, true)
    equal(by["C_Scenario.GetCriteriaInfo"].status, "MISSING")
    equal(by["LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE"].status, "AVAILABLE")
    equal(by["CHALLENGE_MODE_START"].status, "AVAILABLE")
    equal(by["CHALLENGE_MODE_DEATH_COUNT_UPDATED"].status, "MISSING")
    _G.C_EventUtils = nil
    equal(TA:ProbeCapabilities()[21].status, "UNKNOWN", "events are UNKNOWN without a validator")
    truthy(TA:CapabilitySignature(caps):find("scenario.criteriaLegacy", 1, true))
end)

test("capabilities are logged once per distinct signature", function()
    local TA = install()
    equal(TA:LogCapabilities("t1"), true); equal(TA:LogCapabilities("t2"), false)
    equal(#records, 1); equal(records[1].e, "ADAPTER_CAPS")
    _G.C_ChallengeMode.GetDeathCount = nil
    equal(TA:LogCapabilities("t3"), true); equal(#records, 2)
    equal(records[2].d.available, true); truthy(records[2].d.missing:find("challenge.deaths", 1, true))
end)

test("bus lifecycle hooks record compact adapter snapshots", function()
    local TA = install()
    local bus = _G.MitzuMPlus.EventBus
    truthy(bus.handlers.MITZU_KEY_STARTED); truthy(bus.handlers.MITZU_KEY_COMPLETED); truthy(bus.handlers.MITZU_PRE_KEY)
    running(12, 3); W.criteria = criteria(0, 686, 0, 0)
    bus.handlers.MITZU_KEY_STARTED()
    local last = records[#records]
    equal(last.e, "ADAPTER_START"); equal(last.d.map, 399); equal(last.d.level, 12); equal(last.d.bosses, "0/4")
    bus.handlers.MITZU_KEY_STARTED()
    equal(records[#records - 1].e, "ADAPTER_START", "caps are not repeated, only the snapshot")
end)

test("parity lines compare against 1.0 authorities with one return value", function()
    local TA = install()
    running(12, 600); W.criteria = criteria(343, 686, 50, 1)
    local MP = _G.MitzuMPlus
    MP.DungeonContext = {
        IsChallengeActive = function() return true end,
        GetChallengeMapID = function() return 399 end,
        GetKeystoneLevel = function() return 12, "extra" end,
    }
    MP.ChallengeClock = { GetElapsed = function() return 601.4 end, GetTimeLimit = function() return 1800 end }
    MP.KeystoneTracker = {
        IsActive = function() return true end,
        GetOfficialSnapshot = function()
            return { enemyPct = 50, enemyTotal = 686, deaths = 0,
                     bosses = { { completed = true }, { completed = false }, { completed = false }, { completed = false } } }
        end,
    }
    local lines = TA:ParityLines(TA:GetSnapshot())
    local text = table.concat(lines, "\n")
    truthy(not text:find("DIFF", 1, true), text)
    truthy(text:find("keystoneLevel adapter=12 legacy=12 -> MATCH", 1, true), text)
    truthy(text:find("elapsed adapter=600 legacy=601.4 -> MATCH", 1, true), text)
    MP.KeystoneTracker.GetOfficialSnapshot = function() return { enemyPct = 29.44, enemyTotal = 686, deaths = 0, bosses = {} } end
    text = table.concat(TA:ParityLines(TA:GetSnapshot()), "\n")
    -- Lua 5.4 prints 50.0 where WoW's 5.1 prints 50.
    truthy(text:find("forcesPercent adapter=50%.?0? legacy=29%.44 %-> DIFF"), text)
end)

test("report renders in every state without errors", function()
    local TA = install()
    for _, setup in ipairs({
        function() end,
        function() running(12, 0) end,
        function() running(12, 900); W.criteria = criteria(343, 686, 50, 2) end,
        function() _G.C_ChallengeMode = nil; _G.C_ScenarioInfo = nil end,
    }) do
        install(); setup()
        local TA2 = _G.MitzuMPlus.TrackerAdapter
        local lines = TA2:ReportLines()
        local text = table.concat(lines, "\n")
        for _, section in ipairs({ "[SNAPSHOT]", "[CRITERIA RAW]", "[PARITY vs 1.0]", "[CAPABILITIES]", "=== END ===" }) do
            truthy(text:find(section, 1, true), section)
        end
        truthy(text:find("interface=120105", 1, true))
        local fields = TA2:DiagnosticFields()
        equal(fields[1][1], "adapterVersion")
    end
    truthy(TA)
end)

if #failures > 0 then error(string.format("TrackerAdapter: %d failures\n%s", #failures, table.concat(failures, "\n")), 0) end
return { tests = tests, assertions = assertions }
