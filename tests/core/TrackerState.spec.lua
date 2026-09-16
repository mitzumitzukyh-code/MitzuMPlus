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
    local TS = install({ invalidEvent = "CHALLENGE_MODE_DEATH_COUNT_UPDATED", throwingEvent = "WORLD_STATE_TIMER_STOP" })
    local f = frames[1]
    equal(#f.events, #TS.EVENTS - 2)
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
        "revision", "recovered", "firstSeenAt", "completedAt", "finalElapsed", "adapterAvailable", "runWarnings", "transient",
        "completionConverged", "completionAttempts", "completionConvergenceMs", "completionCriteriaIncomplete",
        "completionRegressionsIgnored" }) do allowed[k] = true end
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

test("startup timer race is transient: no run warning, sync duration recorded", function()
    local TS = install()
    raw = retailSample(nil); raw.warnings = { "ACTIVE_WITHOUT_TIMER" }
    TS:OnEvent("CHALLENGE_MODE_START"); advance(0.3)
    local s = TS:GetSnapshot()
    equal(TS:GetStatus(), "PENDING")
    has(s.transient, "ADAPTER_ACTIVE_WITHOUT_TIMER")
    equal(#s.warnings, 0); equal(#s.runWarnings, 0)
    advance(3)
    equal(#TS:GetSnapshot().runWarnings, 0, "still inside the synchronization window")
    raw = running(4); raw.warnings = {}
    advance(1)
    s = TS:GetSnapshot()
    equal(TS:GetStatus(), "RUNNING"); equal(#s.transient, 0); equal(#s.runWarnings, 0)
    equal(count(records, "STATE_WARN"), 0)
    equal(count(records, "STATE_SYNC"), 1)
    local sync
    for _, r in ipairs(records) do if r.e == "STATE_SYNC" then sync = r.d end end
    equal(sync.code, "ADAPTER_ACTIVE_WITHOUT_TIMER"); equal(sync.seconds, "4.0")
end)

test("a synchronization gap that persists past the window becomes a run warning", function()
    local TS = install()
    raw = retailSample(nil); raw.warnings = { "ACTIVE_WITHOUT_TIMER", "CRITERIA_PARTIAL" }
    TS:OnEvent("CHALLENGE_MODE_START"); advance(0.3)
    local s = TS:GetSnapshot()
    has(s.warnings, "ADAPTER_CRITERIA_PARTIAL", "non-transient codes are immediate")
    equal(#s.transient, 1)
    advance(11)
    s = TS:GetSnapshot()
    has(s.warnings, "ADAPTER_ACTIVE_WITHOUT_TIMER"); has(s.runWarnings, "ADAPTER_ACTIVE_WITHOUT_TIMER")
    equal(#s.transient, 0)
    equal(count(records, "STATE_WARN"), 2, "each code recorded once")
    raw = running(20); raw.warnings = {}
    advance(1)
    equal(count(records, "STATE_SYNC"), 0, "a promoted warning is not also reported as a normal sync")
    has(TS:GetSnapshot().runWarnings, "ADAPTER_ACTIVE_WITHOUT_TIMER")
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
    equal(TS:GetStatus(), "COMPLETING", "1/4 bosses and 23 % are not a final state")
    near(TS:GetElapsed(), 905, 1e-9, "time is frozen at the event while criteria converge")
    advance(TS.COMPLETION_WINDOW + 0.1)
    equal(TS:GetStatus(), "COMPLETED"); near(TS:GetSnapshot().finalElapsed, 905)
    equal(TS:GetSnapshot().active, false); equal(TS:GetSnapshot().forcesCurrent, 144)
    equal(TS:GetSnapshot().completionCriteriaIncomplete, true)
end)

test("a new key after completion starts a new run", function()
    local TS = install()
    raw = retailSample(900); TS:Refresh("t")
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    equal(TS:GetStatus(), "COMPLETING")
    raw = retailSample(2); raw.keystoneLevel = 7
    TS:OnEvent("CHALLENGE_MODE_START"); advance(0.3)
    equal(TS:GetStatus(), "RUNNING"); equal(TS:GetSnapshot().keystoneLevel, 7)
    equal(TS:GetSnapshot().completedAt, nil); equal(count(records, "STATE_RUN_STARTED"), 2)
    equal(count(records, "STATE_RUN_COMPLETED"), 1, "the open window was closed once by the new key")
    equal((activeTickers()), 1, "only the running resync ticker")
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

-- ---------------------------------------------------------------------------
-- COMPLETION CONVERGENCE (1.1.0-dev.5)
-- Retail 12.1.0.69814 dev.4 run: Altar de Colmillos (map 588) +12, limit 30:00,
-- final 29:43, 9 deaths / 135 s, forces 817/817 before the end, final boss not
-- yet visible when CHALLENGE_MODE_COMPLETED arrived (frozen as 2/3).
-- ---------------------------------------------------------------------------

local function altar(elapsed, bossesDone)
    bossesDone = bossesDone or 2
    local bosses = {}
    for i = 1, 3 do bosses[i] = { index = i, name = "B" .. i, completed = i <= bossesDone } end
    return {
        active = true, available = true, mapID = 588, mapName = "Altar", keystoneLevel = 12, timeLimit = 1800,
        elapsed = elapsed, timerSource = "WORLD_ELAPSED_TIMER", deaths = 9, deathTimeLost = 135,
        forcesCurrent = 817, forcesTotal = 817, forcesPercent = 100, forcesRemaining = 0,
        forcesRemainingPercent = 0, forcesSource = "COUNT_TOTAL",
        bossesCompleted = bossesDone, bossesTotal = 3, bosses = bosses, warnings = {}, criteriaCount = 4,
    }
end
local function altarRunning(elapsedNow, bossesDone)
    local s = altar(elapsedNow, bossesDone)
    s.serverStartAt = clock.now - elapsedNow
    return s
end
-- What the Retail client returned: no criteria at all after the event.
local function noCriteria(active)
    return { active = active, available = true, mapID = 588, keystoneLevel = 12, timeLimit = 1800,
             warnings = {}, criteriaCount = nil }
end
local function recordData(name)
    local out = {}
    for _, r in ipairs(records) do if r.e == name then out[#out + 1] = r.d end end
    return out
end

test("completion 1: criteria already converged freeze immediately", function()
    local TS = install()
    raw = altarRunning(1780, 3); TS:Refresh("t")
    advance(3)
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    equal(TS:GetStatus(), "COMPLETED")
    local s = TS:GetSnapshot()
    equal(s.bossesCompleted, 3); equal(s.bossesTotal, 3); equal(s.forcesPercent, 100); equal(s.forcesCurrent, 817)
    equal(s.completionConverged, true); equal(s.completionCriteriaIncomplete, false)
    equal(s.completionAttempts, 1); equal(s.completionConvergenceMs, 0)
    equal(s.timerStale, false); equal(s.forcesStale, false); equal(s.bossesStale, false)
    near(s.finalElapsed, 1783); equal(s.deaths, 9); equal(s.deathTimeLost, 135)
    equal(s.mapID, 588); equal(s.keystoneLevel, 12)
    equal((activeTickers()), 0, "no window ticker when nothing is missing")
    equal(count(emitted, "MITZU_TRACKER_RUN_COMPLETED"), 1)
end)

test("completion 2: event before the final boss update converges to 3/3", function()
    local TS = install()
    raw = altarRunning(1780, 2); TS:Refresh("t")
    advance(3)
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    equal(TS:GetStatus(), "COMPLETING")
    equal(TS:IsActive(), false); equal(TS:IsCompleting(), true)
    local n, period = activeTickers()
    equal(n, 1, "only the bounded completion ticker"); equal(period, TS.COMPLETION_INTERVAL)
    equal(count(emitted, "MITZU_TRACKER_RUN_COMPLETED"), 0, "not final yet")
    equal(TS:GetSnapshot().bossesCompleted, 2)
    advance(0.3)
    raw = altar(nil, 3)                       -- Blizzard publishes the last boss
    advance(0.25)
    equal(TS:GetStatus(), "COMPLETED")
    local s = TS:GetSnapshot()
    equal(s.bossesCompleted, 3); equal(s.bosses[3].completed, true); equal(s.bossesStale, false)
    equal(s.completionConverged, true); equal(s.completionCriteriaIncomplete, false)
    equal(s.completionAttempts, 3); equal(s.completionConvergenceMs, 500)
    near(s.finalElapsed, 1783, 1e-9, "server time at the event, not at convergence")
    near(TS:GetElapsed(), 1783, 1e-9)
    equal((activeTickers()), 0)
    equal(count(records, "STATE_RUN_COMPLETED"), 1); equal(count(emitted, "MITZU_TRACKER_RUN_COMPLETED"), 1)
    local done = recordData("STATE_RUN_COMPLETED")[1]
    equal(done.bosses, "3/3"); equal(done.converged, true); equal(done.elapsed, 1783)
end)

test("completion 2b: a SCENARIO_CRITERIA_UPDATE inside the window also converges", function()
    local TS = install()
    raw = altarRunning(1000, 2); TS:Refresh("t")
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    raw = altar(nil, 3)
    TS:OnEvent("SCENARIO_CRITERIA_UPDATE"); advance(0.2)
    equal(TS:GetStatus(), "COMPLETED"); equal(TS:GetSnapshot().bossesCompleted, 3)
    equal((activeTickers()), 0)
end)

test("completion 3: temporary nil and zero reads never overwrite good data", function()
    local TS = install()
    raw = altarRunning(1780, 2); TS:Refresh("t")
    advance(3)
    raw = noCriteria(false)
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    local s = TS:GetSnapshot()
    equal(TS:GetStatus(), "COMPLETING")
    equal(s.forcesCurrent, 817); equal(s.forcesPercent, 100); equal(s.bossesCompleted, 2); equal(s.bossesTotal, 3)
    equal(s.deaths, 9); equal(s.deathTimeLost, 135); equal(s.mapID, 588)
    -- A broken read: zeros and a shrunken criteria list.
    raw = altar(nil, 0); raw.forcesCurrent, raw.forcesPercent, raw.forcesRemaining = 0, 0, 817
    raw.bossesTotal, raw.bosses, raw.deaths, raw.deathTimeLost = 0, {}, nil, nil
    advance(0.25)
    s = TS:GetSnapshot()
    equal(s.forcesCurrent, 817); equal(s.forcesPercent, 100); equal(s.bossesCompleted, 2); equal(s.bossesTotal, 3)
    equal(s.deaths, 9); equal(#s.bosses, 3)
    raw = noCriteria(nil)
    advance(0.25)
    equal(TS:GetSnapshot().bossesCompleted, 2)
    raw = altar(nil, 3); raw.active = false
    advance(0.25)
    s = TS:GetSnapshot()
    equal(TS:GetStatus(), "COMPLETED")
    equal(s.bossesCompleted, 3); equal(s.forcesCurrent, 817); equal(s.deaths, 9)
    equal(s.completionRegressionsIgnored, 2, "zero forces and zero bosses were ignored")
    equal(s.active, false, "last known client state")
end)

test("completion 4: Blizzard never exposes 3/3, the real value is kept and flagged", function()
    local TS = install()
    raw = altarRunning(1780, 2); TS:Refresh("t")
    advance(3)
    raw = noCriteria(false)
    local calls0 = adapterCalls
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    advance(TS.COMPLETION_WINDOW - 0.3)
    equal(TS:GetStatus(), "COMPLETING", "still inside the window")
    advance(0.5)
    equal(TS:GetStatus(), "COMPLETED")
    local s = TS:GetSnapshot()
    equal(s.bossesCompleted, 2, "never invented"); equal(s.bossesTotal, 3); equal(s.bosses[3].completed, false)
    equal(s.bossesStale, true, "2/3 was not confirmed after the event")
    equal(s.forcesPercent, 100); equal(s.forcesStale, false, "100 % is terminal")
    equal(s.completionConverged, false); equal(s.completionCriteriaIncomplete, true)
    equal(s.completionConvergenceMs, TS.COMPLETION_WINDOW * 1000)
    equal(s.completionAttempts, TS.COMPLETION_WINDOW / TS.COMPLETION_INTERVAL + 1)
    truthy(s.completionAttempts <= TS.COMPLETION_MAX_ATTEMPTS, "bounded")
    near(s.finalElapsed, 1783)
    equal(#s.warnings, 0, "an API timing limitation is not a warning")
    equal((activeTickers()), 0)
    local calls = adapterCalls
    advance(30)
    equal(adapterCalls, calls, "nothing keeps reading after the window")
    truthy(calls - calls0 <= TS.COMPLETION_MAX_ATTEMPTS)
    local report = table.concat(TS:ReportLines(), "\n")
    truthy(report:find("completionConverged=false", 1, true), report)
    truthy(report:find("completionCriteriaIncomplete=true", 1, true), report)
    local f = {}
    for _, p in ipairs(TS:DiagnosticFields()) do f[p[1]] = p[2] end
    equal(f.status, "COMPLETED"); equal(f.completionConverged, false); equal(f.completionCriteriaIncomplete, true)
    equal(f.completionWindowOpen, false); equal(f.bossesCompleted, 2)
    local reads = recordData("STATE_COMPLETION_READ")
    equal(#reads, 1, "identical reads are recorded once")
    equal(reads[1].read, "active=false forces=nil bosses=nil criteria=nil")
end)

test("completion 5: forces at 100 % before the end are preserved", function()
    local TS = install()
    raw = altarRunning(1500, 2); TS:Refresh("t")
    raw = noCriteria(false)
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    advance(TS.COMPLETION_WINDOW + 1)
    local s = TS:GetSnapshot()
    equal(s.forcesCurrent, 817); equal(s.forcesTotal, 817); equal(s.forcesPercent, 100)
    equal(s.forcesRemaining, 0); equal(s.forcesStale, false)
end)

test("completion 7: repeated completion events finalize once", function()
    local TS = install()
    raw = altarRunning(1780, 2); TS:Refresh("t")
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    local calls = adapterCalls
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    equal(adapterCalls, calls, "a duplicate inside the window does not read or restart it")
    raw = altar(nil, 3); advance(0.25)
    equal(TS:GetStatus(), "COMPLETED")
    local final = TS:GetSnapshot().finalElapsed
    advance(10)
    TS:OnEvent("CHALLENGE_MODE_COMPLETED"); advance(1)
    equal(TS:GetStatus(), "COMPLETED")
    near(TS:GetSnapshot().finalElapsed, final, 1e-9)
    equal(TS._stats.duplicateCompletions, 2)
    equal(count(records, "STATE_RUN_COMPLETED"), 1); equal(count(emitted, "MITZU_TRACKER_RUN_COMPLETED"), 1)
    equal(count(records, "STATE_COMPLETION_BEGIN"), 1)
    equal(count(records, "STATE_COMPLETION_DUPLICATE"), 2)
    equal(count(records, "STATE_RUN_STARTED"), 1)
end)

test("completion 8/9: adapter errors inside the window still end it and clean up", function()
    local TS = install()
    raw = altarRunning(1780, 2); TS:Refresh("t")
    raw = "THROW"
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    equal(TS:GetStatus(), "COMPLETING", "a failed read at the event still closes the run")
    advance(TS.COMPLETION_WINDOW + 0.5)
    equal(TS:GetStatus(), "COMPLETED")
    local s = TS:GetSnapshot()
    equal(s.bossesCompleted, 2); equal(s.completionCriteriaIncomplete, true)
    equal((activeTickers()), 0); equal(TS._completionTicker, nil); equal(TS._completion, nil)
    truthy(TS._stats.adapterErrors >= 2)
end)

test("completion: RESET inside the window freezes, then the run ends", function()
    local TS = install()
    raw = altarRunning(900, 1); TS:Refresh("t")
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    raw = { active = false, warnings = {} }
    TS:OnEvent("CHALLENGE_MODE_RESET")
    equal(TS:GetStatus(), "COMPLETED"); equal(TS._completion, nil)
    equal(TS:GetSnapshot().bossesCompleted, 1); equal(TS:GetSnapshot().completionCriteriaIncomplete, true)
    advance(1)
    equal((activeTickers()), 0); equal(count(records, "STATE_RUN_COMPLETED"), 1)
end)

test("completion: a key on another map inside the window starts a new run", function()
    local TS = install()
    raw = altarRunning(900, 1); TS:Refresh("t")
    TS:OnEvent("CHALLENGE_MODE_COMPLETED")
    raw = retailSample(3)
    TS:Refresh("other map")
    equal(TS:GetStatus(), "RUNNING"); equal(TS:GetSnapshot().mapID, 249)
    equal(count(records, "STATE_RUN_COMPLETED"), 1); equal(count(records, "STATE_RUN_STARTED"), 2)
    local n, period = activeTickers()
    equal(n, 1); equal(period, 5)
end)

test("completion 10: startup transients still behave after the dev.5 changes", function()
    local TS = install()
    raw = altar(nil, 0); raw.warnings = { "ACTIVE_WITHOUT_TIMER" }
    raw.forcesCurrent, raw.forcesPercent = 0, 0
    TS:OnEvent("CHALLENGE_MODE_START"); advance(0.3)
    equal(TS:GetStatus(), "PENDING"); has(TS:GetSnapshot().transient, "ADAPTER_ACTIVE_WITHOUT_TIMER")
    raw = altarRunning(9, 0); raw.forcesCurrent, raw.forcesPercent = 0, 0
    advance(1)
    equal(TS:GetStatus(), "RUNNING"); equal(#TS:GetSnapshot().runWarnings, 0)
    equal(count(records, "STATE_SYNC"), 1)
end)

if #failures > 0 then error(string.format("TrackerState: %d failures\n%s", #failures, table.concat(failures, "\n")), 0) end
return { tests = tests, assertions = assertions }
