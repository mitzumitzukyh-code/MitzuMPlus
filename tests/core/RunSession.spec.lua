-- Run identity, reload recovery and duplicate-finalization regression tests.
local tests, assertions, failures = 0, 0, {}
local function equal(a, b, label)
    assertions = assertions + 1
    if a ~= b then error((label or "equal") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function truthy(v, label) equal(not not v, true, label) end
local function test(name, fn)
    tests = tests + 1
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end

local currentTime, clockStart = 100000, 99000
_G.time = function() return currentTime end
_G.MitzuMPlus = {
    db = { global = { runs = {} } },
    ChallengeClock = { GetStartedAt = function() return clockStart end },
    FlightRecorder = { Record = function() end },
}
_G.LibStub = function()
    return { GetAddon = function() return _G.MitzuMPlus end }
end
dofile("MitzuMPlus/modules/RunSession.lua")
local RS = _G.MitzuMPlus.RunSession

local function reset()
    currentTime, clockStart = 100000, 99000
    _G.MitzuMPlus.db.global = { runs = {} }
    RS._state, RS._reason, RS._recovered = "NONE", "NO_SESSION", false
end

test("new run receives stable identity", function()
    reset()
    local s, reason = RS:StartOrRestore(586, 4)
    equal(reason, "NEW"); equal(s.id, "586:4:99000"); equal(s.state, "RUNNING")
    equal(_G.MitzuMPlus.db.global.activeRunSession, s)
end)

test("reload restores the same running session", function()
    reset()
    local first = RS:StartOrRestore(586, 4)
    currentTime = currentTime + 30; clockStart = 99008
    local restored, reason = RS:StartOrRestore(586, 4)
    equal(reason, "RESTORED"); equal(restored, first); equal(restored.id, "586:4:99000")
    truthy(RS:IsRecovered())
end)

test("completed session cannot be finalized twice", function()
    reset()
    local s = RS:StartOrRestore(586, 4)
    local run = { sessionID=s.id, dungeonID=586, keyLevel=4, playerName="Mitzuky", playerRealm="" }
    truthy(RS:Finalize(run, 1849, 100100, 41))
    local duplicate, reason, id = RS:IsDuplicateFinalization(run, 1849, 100101)
    truthy(duplicate); equal(reason, "SESSION_ALREADY_COMPLETED"); equal(id, 41)
end)

test("stale completion payload cannot start a phantom run", function()
    reset()
    local s = RS:StartOrRestore(586, 4)
    RS:Finalize({sessionID=s.id,dungeonID=586,keyLevel=4}, 1849, 100100, 41)
    currentTime = 100183; clockStart = 99000
    local newSession, reason = RS:StartOrRestore(586, 4)
    equal(newSession, nil); equal(reason, "STALE_COMPLETION")
end)

test("real Nalorakk recycled completion is rejected without deleting history", function()
    reset()
    local runs = _G.MitzuMPlus.db.global.runs
    runs[41] = { runID=41, dungeonID=586, keyLevel=4, completionTime=1849,
        startTime=1789324108, endTime=1789324580, playerName="Mitzukyh", playerRealm="" }
    local candidate = { sessionID="586:4:1789324663", dungeonID=586, keyLevel=4,
        startTime=1789324663, playerName="Mitzukyh", playerRealm="" }
    local duplicate, reason, id = RS:IsDuplicateFinalization(candidate, 1849, 1789324663)
    truthy(duplicate); equal(reason, "RECYCLED_COMPLETION_INFO"); equal(id, 41)
    equal(runs[41].runID, 41, "existing run is preserved")
end)

test("two legitimate similar runs remain allowed", function()
    reset()
    _G.MitzuMPlus.db.global.runs[7] = { runID=7, sessionID="586:4:1000", dungeonID=586,
        keyLevel=4, completionTime=1849, endTime=3000, playerName="Mitzuky", playerRealm="" }
    local run = { sessionID="586:4:5000", dungeonID=586, keyLevel=4,
        playerName="Mitzuky", playerRealm="" }
    local duplicate = RS:IsDuplicateFinalization(run, 1849, 5000)
    equal(duplicate, false)
end)

test("different player or level is never collapsed", function()
    reset()
    _G.MitzuMPlus.db.global.runs[1] = { dungeonID=586,keyLevel=4,completionTime=1849,
        endTime=99990,playerName="A",playerRealm="R" }
    equal(RS:IsDuplicateFinalization({dungeonID=586,keyLevel=5,playerName="A",playerRealm="R"},1849,100000), false)
    equal(RS:IsDuplicateFinalization({dungeonID=586,keyLevel=4,playerName="B",playerRealm="R"},1849,100000), false)
end)

if #failures > 0 then error(string.format("RunSession: %d failures\n%s", #failures, table.concat(failures, "\n")), 0) end
return { tests=tests, assertions=assertions }
