-- TrackerState: normalized Mythic+ snapshot built only from TrackerAdapter.
-- Fake adapter, fake clock and fake timers; no WoW client.
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

local clock, timers, records, emitted, raw, adapterCalls, frames

local function advance(secs)
    local target = clock.now + secs
    for _ = 1, 10000 do
        local nextT
        for _, t in ipairs(timers) do
            if not t.cancelled and t.at <= target and (not nextT or t.at < nextT.at) then nextT = t end
        end
        if not nextT then break end
        clock.now = nextT.at
        if nextT.period then nextT.at = nextT.at + nextT.period else nextT.cancelled = true end
        nextT.fn()
    end
    clock.now = target
end

-- Retail 12.1.0.69814 real key (Mutzuki, 2026-09-15): map 249, +6, 1980 s,
-- forces 144/608, first of four bosses down.
local function retailSample(elapsed)
    return {
        active = true, available = true, mapID = 249, mapName = "Sample", keystoneLevel = 6, timeLimit = 1980,
        elapsed = elapsed, timerSource = "WORLD_ELAPSED_TIMER", deaths = 1, deathTimeLost = 5,
        forcesCurrent = 144, forcesTotal = 608, forcesPercent = 144 / 608 * 100, forcesRemaining = 464,
        forcesRemainingPercent = 100 - 144 / 608 * 100, forcesSource = "COUNT_TOTAL",
        bossesCompleted = 1, bossesTotal = 4,
        bosses = { { index = 1, name = "B1", completed = true }, { index = 2, name = "B2", completed = false },
                   { index = 3, name = "B3", completed = false }, { index = 4, name = "B4", completed = false } },
        warnings = {},
        -- Raw diagnostics that must never reach TrackerState.
        forcesQuantityPercent = 23, quantityString = "144%", quantity = 23, criteriaSource = "C_ScenarioInfo",
    }
end

-- Retail sample whose server timer keeps running with the fake clock.
local function running(elapsedNow)
    local s = retailSample(elapsedNow)
    s.serverStartAt = clock.now - elapsedNow
    return s
end

local function install(opts)
    opts = opts or {}
    clock = { now = 1000, epoch = 1789500000 }
    timers, records, emitted, adapterCalls, frames = {}, {}, {}, 0, {}
    raw = { active = false, warnings = {} }
    _G.GetTime = function() return clock.now end
    _G.time = function() return clock.epoch + math.floor(clock.now - 1000) end
    _G.C_Timer = {
        After = function(s, fn) timers[#timers + 1] = { at = clock.now + s, fn = fn } end,
        NewTicker = function(s, fn)
            local h = { at = clock.now + s, period = s, fn = fn }
            function h:Cancel() self.cancelled = true end
            timers[#timers + 1] = h
            return h
        end,
    }
    _G.C_EventUtils = opts.noValidator and nil or { IsEventValid = function(e) return e ~= opts.invalidEvent end }
    _G.CreateFrame = function()
        local f = { events = {} }
        function f:RegisterEvent(e)
            if e == opts.throwingEvent then error("unknown event " .. e) end
            self.events[#self.events + 1] = e
        end
        function f:SetScript(_, fn) self.onEvent = fn end
        frames[#frames + 1] = f
        return f
    end
    local adapter = {
        GetSnapshot = function()
            adapterCalls = adapterCalls + 1
            if raw == "THROW" then error("adapter boom") end
            local copy = {}
            for k, v in pairs(raw) do copy[k] = v end
            -- A running server clock: elapsed follows the fake time.
            if raw.serverStartAt then copy.elapsed = clock.now - raw.serverStartAt end
            copy.serverStartAt = nil
            return copy
        end,
    }
    _G.MitzuMPlus = {
        TrackerAdapter = adapter,
        FlightRecorder = { Record = function(_, s, e, d) records[#records + 1] = { s = s, e = e, d = d } end },
        EventBus = { Emit = function(_, ev) emitted[#emitted + 1] = ev end },
    }
    dofile("MitzuMPlus/modules/Tracker/TrackerState.lua")
    return _G.MitzuMPlus.TrackerState
end

local function count(list, value)
    local n = 0
    for _, v in ipairs(list) do if v == value or (type(v) == "table" and v.e == value) then n = n + 1 end end
    return n
end

local function activeTickers()
    local n, period = 0, nil
    for _, t in ipairs(timers) do if t.period and not t.cancelled then n = n + 1; period = t.period end end
    return n, period
end

-- ---------------------------------------------------------------------------

test("starts IDLE with an empty snapshot, no ticker, events registered", function()
    local TS = install()
    equal(TS:GetStatus(), "IDLE"); equal(TS:GetElapsed(), nil); equal(TS:GetTimeRemaining(), nil)
    local s = TS:GetSnapshot()
    equal(s.active, false); equal(s.forcesPercent, nil); equal(s.prediction, nil); equal(s.eta, nil)
    equal((activeTickers()), 0)
    equal(#frames, 1); has(frames[1].events, "CHALLENGE_MODE_COMPLETED"); has(frames[1].events, "SCENARIO_CRITERIA_UPDATE")
end)

test("invalid or throwing event names are rejected without breaking registration", function()
    install({ invalidEvent = "CHALLENGE_MODE_DEATH_COUNT_UPDATED", throwingEvent = "WORLD_STATE_TIMER_STOP" })
    local f = frames[1]
    equal(#f.events, 6)
    local rejected
    for _, r in ipairs(records) do if r.e == "STATE_EVENTS_REJECTED" then rejected = r.d.events end end
    equal(rejected, "CHALLENGE_MODE_DEATH_COUNT_UPDATED,WORLD_STATE_TIMER_STOP")
    truthy(f.onEvent, "script installed")
end)

test("pre-key: inactive challenge stays IDLE and never fakes zeros", function()
    local TS = install()
    TS:Refresh("test")
    equal(TS:GetStatus(), "IDLE")
    local s = TS:GetSnapshot()
    equal(s.forcesCurrent, nil); equal(s.bossesTotal, nil); equal(s.keystoneLevel, nil)
end)

test("challenge start: PENDING without timer, RUNNING once the server timer appears", function()
    local TS = install()
    raw = retailSample(nil)
    TS:OnEvent("CHALLENGE_MODE_START"); advance(0.3)
    equal(TS:GetStatus(), "PENDING"); equal(TS:GetElapsed(), nil)
    equal(select(2, activeTickers()), 1, "fast resync while pending")
    equal(count(records, "STATE_RUN_STARTED"), 1); has(emitted, "MITZU_TRACKER_RUN_STARTED")
    raw = running(3)
    advance(1)
    equal(TS:GetStatus(), "RUNNING"); near(TS:GetElapsed(), 4, 1e-9)
    local n, period = activeTickers(); equal(n, 1); equal(period, 5)
    equal(TS:GetSnapshot().recovered, false)
end)

test("real Retail sample is stored with normalized fields only", function()
    local TS = install()
    raw = retailSample(600)
    TS:Refresh("test")
    local s = TS:GetSnapshot()
    equal(s.mapID, 249); equal(s.keystoneLevel, 6); equal(s.timeLimit, 1980)
    equal(s.forcesCurrent, 144); equal(s.forcesTotal, 608); near(s.forcesPercent, 23.684, 0.001)
    equal(s.forcesRemaining, 464); near(s.forcesRemainingPercent, 76.316, 0.001)
    equal(s.bossesCompleted, 1); equal(s.bossesTotal, 4); equal(#s.bosses, 4)
    equal(s.bosses[1].completed, true); equal(s.bosses[2].completed, false)
    equal(s.deaths, 1); equal(s.deathTimeLost, 5)
    for _, forbidden in ipairs({ "quantityString", "quantity", "forcesQuantityPercent", "criteriaSource", "available", "timerID" }) do
        equal(s[forbidden], nil, forbidden .. " must not leak into TrackerState")
    end
    local allowed = {}
    for _, k in ipairs({ "status", "active", "warnings", "bosses", "pace", "prediction", "eta", "confidence",
        "mapID", "mapName", "keystoneLevel", "timeLimit", "deaths", "deathTimeLost", "forcesCurrent", "forcesTotal",
        "forcesPercent", "forcesRemaining", "forcesRemainingPercent", "forcesSource", "bossesCompleted", "bossesTotal",
        "elapsedBase", "elapsedAt", "timerSource", "timerStale", "forcesStale", "bossesStale", "timestamp", "reason",
        "revision", "recovered", "firstSeenAt", "completedAt", "finalElapsed", "adapterAvailable", "runWarnings" }) do allowed[k] = true end
    for k in pairs(s) do truthy(allowed[k], "unexpected snapshot field " .. tostring(k)) end
end)

test("forces 0%, 50%, 100%", function()
    local TS = install()
    for _, case in ipairs({ { 0, 0 }, { 304, 50 }, { 608, 100 } }) do
        raw = retailSample(100)
        raw.forcesCurrent, raw.forcesPercent = case[1], case[2]
        raw.forcesRemaining, raw.forcesRemainingPercent = 608 - case[1], 100 - case[2]
        TS:Refresh("forces")
        local s = TS:GetSnapshot()
        equal(s.forcesCurrent, case[1]); equal(s.forcesPercent, case[2]); equal(s.forcesRemaining, 608 - case[1])
        equal(s.forcesStale, false)
    end
    equal(#TS:GetSnapshot().warnings, 0)
end)

test("missing forces before any reading stay nil, never 0", function()
    local TS = install()
    raw = retailSample(10)
    for _, k in ipairs({ "forcesCurrent", "forcesTotal", "forcesPercent", "forcesRemaining", "forcesRemainingPercent", "forcesSource" }) do raw[k] = nil end
    TS:Refresh("t")
    local s = TS:GetSnapshot()
    equal(s.forcesPercent, nil); equal(s.forcesCurrent, nil); equal(s.forcesStale, nil)
end)

test("a gap after known data keeps the last values and marks them stale", function()
    local TS = install()
    raw = retailSample(100); TS:Refresh("t")
    raw = retailSample(nil); raw.forcesPercent, raw.forcesCurrent, raw.bossesTotal, raw.bosses = nil, nil, nil, nil
    raw.mapID, raw.timeLimit, raw.keystoneLevel = nil, nil, nil
    advance(4)
    TS:Refresh("gap")
    local s = TS:GetSnapshot()
    equal(TS:GetStatus(), "RUNNING", "known timer keeps the run RUNNING")
    equal(s.timerStale, true); near(TS:GetElapsed(), 104, 1e-9, "interpolated through the gap")
    equal(s.forcesStale, true); equal(s.forcesCurrent, 144); equal(s.bossesStale, true); equal(s.bossesCompleted, 1)
    equal(s.mapID, 249); equal(s.timeLimit, 1980); equal(s.keystoneLevel, 6)
    raw = retailSample(105); TS:Refresh("back")
    s = TS:GetSnapshot()
    equal(s.timerStale, false); equal(s.forcesStale, false); equal(s.bossesStale, false)
end)

test("timer: interpolation, exact limit and overtime", function()
    local TS = install()
    raw = running(1970); TS:Refresh("t")
    near(TS:GetTimeRemaining(), 10)
    advance(10)
    near(TS:GetTimeRemaining(), 0, 1e-9, "exact limit")
    advance(25)
    near(TS:GetTimeRemaining(), -25, 1e-9, "overtime is negative, not clamped")
    local live = TS:GetLiveSnapshot()
    near(live.elapsed, 2005); near(live.timeRemaining, -25)
    equal(#TS:GetSnapshot().runWarnings, 0, "a running server never looks like a regression")
    equal(TS:GetSnapshot().elapsed, nil, "live copy does not mutate the stored snapshot")
end)

test("unknown map: no limit means no remaining time", function()
    local TS = install()
    raw = retailSample(50); raw.mapID, raw.mapName, raw.timeLimit = 9999, nil, nil
    TS:Refresh("t")
    equal(TS:GetSnapshot().mapID, 9999); equal(TS:GetTimeRemaining(), nil); truthy(TS:GetElapsed())
end)

test("regressions are warned once per run", function()
    local TS = install()
    raw = retailSample(300); TS:Refresh("t")
    raw = retailSample(200); raw.forcesPercent = 10; raw.bossesCompleted = 0
    TS:Refresh("r1")
    local w = TS:GetSnapshot().warnings
    has(w, "TIMER_REGRESSION"); has(w, "FORCES_DECREASED"); has(w, "BOSSES_DECREASED")
    TS:Refresh("r2")
    equal(#TS:GetSnapshot().warnings, 0, "this read is clean")
    w = TS:GetSnapshot().runWarnings
    has(w, "TIMER_REGRESSION"); has(w, "FORCES_DECREASED"); has(w, "BOSSES_DECREASED")
    equal(count(records, "STATE_WARN"), 3, "each code recorded once")
end)

test("adapter warnings are propagated with a prefix (partial criteria)", function()
    local TS = install()
    raw = retailSample(20); raw.warnings = { "CRITERIA_PARTIAL" }
    TS:Refresh("t")
    has(TS:GetSnapshot().warnings, "ADAPTER_CRITERIA_PARTIAL")
end)

test("reload mid-key: timer gap then recovery flag", function()
    local TS = install()   -- fresh Lua state, as after /reload
    raw = retailSample(nil)
    TS:OnEvent("PLAYER_ENTERING_WORLD"); advance(0.3)
    equal(TS:GetStatus(), "PENDING"); equal(TS:GetSnapshot().recovered, nil)
    equal(TS:GetSnapshot().forcesCurrent, 144, "criteria available before the timer")
    raw = retailSample(575)
    advance(1)
    equal(TS:GetStatus(), "RUNNING"); equal(TS:GetSnapshot().recovered, true)
    equal(count(records, "STATE_RUN_RECOVERED"), 1)
end)

test("burst of events is coalesced into one adapter read", function()
    local TS = install()
    raw = retailSample(40)
    for _ = 1, 6 do TS:OnEvent("SCENARIO_CRITERIA_UPDATE") end
    equal(adapterCalls, 0)
    advance(0.3)
    equal(adapterCalls, 1); equal(TS._stats.coalesced, 5); equal(TS._stats.events.SCENARIO_CRITERIA_UPDATE, 6)
end)

test("change notification and revision only when content changes", function()
    local TS = install()
    raw = retailSample(40); TS:Refresh("a")
    local rev = TS:GetRevision()
    local changes = count(emitted, "MITZU_TRACKER_STATE_CHANGED")
    advance(3); raw = retailSample(43); TS:Refresh("same content, timer moved")
    equal(TS:GetRevision(), rev); equal(count(emitted, "MITZU_TRACKER_STATE_CHANGED"), changes)
    raw = retailSample(44); raw.forcesCurrent, raw.forcesPercent = 150, 150 / 608 * 100
    TS:Refresh("forces moved")
    equal(TS:GetRevision(), rev + 1); equal(count(emitted, "MITZU_TRACKER_STATE_CHANGED"), changes + 1)
end)

test("completion while the client still reports active: final snapshot frozen", function()
    local TS = install()
    raw = running(1500); TS:Refresh("t")
    advance(20)
    raw.bossesCompleted = 4
    raw.forcesCurrent, raw.forcesPercent, raw.forcesRemaining, raw.forcesRemainingPercent = 608, 100, 0, 0
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    equal(TS:GetStatus(), "COMPLETED")
    local s = TS:GetSnapshot()
    near(s.finalElapsed, 1520); truthy(s.completedAt); equal(s.forcesPercent, 100); equal(s.bossesCompleted, 4)
    has(emitted, "MITZU_TRACKER_RUN_COMPLETED"); equal(count(records, "STATE_RUN_COMPLETED"), 1)
    equal((activeTickers()), 0, "no resync after completion")
    advance(60)
    near(TS:GetElapsed(), 1520, 1e-9, "frozen")
    TS:OnEvent("SCENARIO_CRITERIA_UPDATE"); advance(0.3)
    equal(TS:GetStatus(), "COMPLETED", "still-active client does not start a phantom run")
    equal(count(records, "STATE_RUN_STARTED"), 1)
end)

test("completion after the client already went inactive", function()
    local TS = install()
    raw = running(900); TS:Refresh("t")
    advance(5)
    raw = retailSample(nil); raw.active = false
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    equal(TS:GetStatus(), "COMPLETED"); near(TS:GetSnapshot().finalElapsed, 905)
    equal(TS:GetSnapshot().active, false); equal(TS:GetSnapshot().forcesCurrent, 144)
end)

test("a new key after completion starts a new run", function()
    local TS = install()
    raw = retailSample(900); TS:Refresh("t")
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    equal(TS:GetStatus(), "COMPLETED")
    raw = retailSample(2); raw.keystoneLevel = 7
    TS:OnEvent("CHALLENGE_MODE_START"); advance(0.3)
    equal(TS:GetStatus(), "RUNNING"); equal(TS:GetSnapshot().keystoneLevel, 7)
    equal(TS:GetSnapshot().completedAt, nil); equal(count(records, "STATE_RUN_STARTED"), 2)
end)

test("a stray completion event with no run does not complete the next key", function()
    local TS = install()
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    equal(TS:GetStatus(), "IDLE")
    raw = retailSample(5)
    TS:OnEvent("CHALLENGE_MODE_START"); advance(0.3)
    equal(TS:GetStatus(), "RUNNING")
end)

test("reset or abandon without completion ends the run as IDLE", function()
    local TS = install()
    raw = retailSample(300); TS:Refresh("t")
    raw = { active = false, warnings = {} }
    TS:OnEvent("CHALLENGE_MODE_RESET"); advance(0.3)
    equal(TS:GetStatus(), "IDLE"); equal(TS:GetSnapshot().forcesCurrent, nil)
    equal(count(records, "STATE_RUN_ENDED"), 1); has(emitted, "MITZU_TRACKER_RUN_ENDED")
    equal((activeTickers()), 0)
end)

test("a different map while running starts a new run", function()
    local TS = install()
    raw = retailSample(300); TS:Refresh("t")
    raw = retailSample(4); raw.mapID = 250
    TS:Refresh("t2")
    equal(TS:GetSnapshot().mapID, 250); equal(count(records, "STATE_RUN_STARTED"), 2)
    equal(TS:GetSnapshot().recovered, false)
end)

test("API unavailable: unknown challenge state keeps the lifecycle and warns", function()
    local TS = install()
    raw = retailSample(300); TS:Refresh("t")
    raw = { active = nil, warnings = { "CHALLENGE_STATE_UNKNOWN" } }
    TS:Refresh("unknown")
    equal(TS:GetStatus(), "RUNNING"); equal(TS:GetSnapshot().forcesCurrent, 144)
    has(TS:GetSnapshot().warnings, "CHALLENGE_STATE_UNKNOWN")
end)

test("adapter errors and a missing adapter never throw or wipe data", function()
    local TS = install()
    raw = retailSample(300); TS:Refresh("t")
    raw = "THROW"
    equal(TS:Refresh("boom"), false)
    equal(TS:GetStatus(), "RUNNING"); equal(TS:GetSnapshot().forcesCurrent, 144); equal(TS._stats.adapterErrors, 1)
    _G.MitzuMPlus.TrackerAdapter = nil
    equal(TS:Refresh("gone"), false); equal(TS._stats.adapterErrors, 2)
    TS:SetAdapter({ GetSnapshot = function() return retailSample(301) end })
    equal(TS:Refresh("injected"), true)
end)

test("diagnostics and report render in every lifecycle state", function()
    local TS = install()
    local function check()
        local text = table.concat(TS:ReportLines(), "\n")
        truthy(text:find("=== END ===", 1, true))
        truthy(not text:find("quantityString", 1, true) and not text:find("144%%"), "no raw quantityString in report")
        local f = {}
        for _, p in ipairs(TS:DiagnosticFields()) do f[p[1]] = p[2] end
        equal(f.status, TS:GetStatus())
        return f
    end
    check()
    raw = retailSample(nil); TS:Refresh("p"); check()
    raw = retailSample(600); TS:Refresh("r")
    local f = check()
    equal(f.forcesPercent, "23.68"); equal(f.forcesRemaining, 464); equal(f.bossesTotal, 4); equal(f.timeRemaining, 1380)
    TS:OnEvent("CHALLENGE_MODE_COMPLETED"); check()
end)

if #failures > 0 then error(string.format("TrackerState: %d failures\n%s", #failures, table.concat(failures, "\n")), 0) end
return { tests = tests, assertions = assertions }
