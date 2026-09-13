-- Tests de simulacion para PackEvidence. No se carga desde el TOC.
-- Ejecutar con: python tests/run_lua_tests.py

local assertions, tests = 0, 0

local function equal(actual, expected, label)
    assertions = assertions + 1
    if actual ~= expected then
        error(string.format("%s: esperado %s, recibido %s",
            label or "equal", tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(value, label)
    assertions = assertions + 1
    if not value then error((label or "truthy") .. ": valor falso", 2) end
end

local function test(name, fn)
    tests = tests + 1
    local ok, err = pcall(fn)
    if not ok then error("TEST " .. name .. "\n" .. tostring(err), 0) end
end

_G.MitzuRouteArrows = { Host = {} }
dofile("MitzuRouteArrows/Evidence/PackEvidence.lua")

local AR = _G.MitzuRouteArrows
local PE = AR.PackEvidence
local engagement = {}
local links = {}

AR.EngagementEvidence = {
    Evaluate = function(_, token)
        local value = engagement[token]
        if value == "ERROR" then error("mock engagement failure") end
        return value
    end,
}

AR.UnitLinkEvidence = {
    Evaluate = function(_, token, link)
        local value = links[token] and links[token][link]
        if value == "ERROR" then error("mock link failure") end
        return value
    end,
}

local function evaluate(expected, tokens, runtime)
    return PE:Evaluate({
        expectedCount = expected,
        expectedCountState = expected and "AVAILABLE" or "UNKNOWN",
        visibleTokens = tokens or {},
        runtimeState = runtime,
    })
end

test("exports closed vocabulary", function()
    equal(PE.STATES.ALIGNED, "ALIGNED", "state")
    equal(PE.IDENTITY_STATES.UNKNOWN, "UNKNOWN", "identity state")
    equal(PE.REASONS.ENGAGED_COUNT_ALIGNED, "ENGAGED_COUNT_ALIGNED", "reason")
end)

test("expected count uses amount and sums entries", function()
    local n, state = PE:ExpectedFromPull({ mobs = {
        { amount = 2, cloneIDs = { 1 } },
        { amount = "3", cloneIDs = { 1, 2, 3 } },
    } })
    equal(n, 5, "expected")
    equal(state, "AVAILABLE", "count state")
end)

test("expected count falls back to clone ids", function()
    local n, state = PE:ExpectedFromPull({ mobs = {
        { amount = 0, cloneIDs = { 2, 4 } },
    } })
    equal(n, 2, "fallback expected")
    equal(state, "AVAILABLE", "fallback state")
end)

test("invalid pulls fail closed", function()
    local cases = {
        {}, { mobs = {} }, { mobs = { false } },
        { mobs = { { amount = -1 } } },
        { mobs = { { amount = 1.5 } } },
        { mobs = { { amount = math.huge } } },
    }
    local n, state = PE:ExpectedFromPull(nil)
    equal(n, nil, "nil count")
    equal(state, "UNKNOWN", "nil state")
    for i, pull in ipairs(cases) do
        n, state = PE:ExpectedFromPull(pull)
        equal(n, nil, "invalid count " .. i)
        equal(state, "UNKNOWN", "invalid state " .. i)
    end
end)

test("aligned is shape only and never identity", function()
    engagement = { nameplate2 = "ENGAGED", nameplate1 = "ENGAGED" }
    links = {
        nameplate1 = { TARGET = "SAME_UNIT", MOUSEOVER = "DIFFERENT_UNIT",
            FOCUS = "DIFFERENT_UNIT", SOFTENEMY = "DIFFERENT_UNIT" },
        nameplate2 = { TARGET = "DIFFERENT_UNIT", MOUSEOVER = "DIFFERENT_UNIT",
            FOCUS = "DIFFERENT_UNIT", SOFTENEMY = "DIFFERENT_UNIT" },
    }
    local r = evaluate(2, { "nameplate2", "nameplate1" }, "RUNNING")
    equal(r.packState, "ALIGNED", "pack state")
    equal(r.identityState, "UNKNOWN", "identity")
    equal(r.evidenceKind, "PACK_SHAPE", "kind")
    equal(r.reasonCode, "ENGAGED_COUNT_ALIGNED", "reason")
    equal(r.engaged, 2, "engaged")
    equal(r.visible, 2, "visible")
    equal(r.links.TARGET, "YES", "target")
    equal(r.links.MOUSEOVER, "NO", "mouseover")
    equal(r.engagedTokens[1], "nameplate1", "sorted 1")
    equal(r.engagedTokens[2], "nameplate2", "sorted 2")
end)

test("under and over are classified", function()
    engagement = { a = "ENGAGED", b = "NOT_ENGAGED", c = "ENGAGED" }
    links = {}
    local under = evaluate(2, { "a", "b" }, "RUNNING")
    equal(under.packState, "UNDER", "under")
    equal(under.reasonCode, "ENGAGED_UNDER_EXPECTED", "under reason")
    local over = evaluate(1, { "a", "c" }, "RUNNING")
    equal(over.packState, "OVER", "over")
    equal(over.reasonCode, "ENGAGED_OVER_EXPECTED", "over reason")
end)

test("known over wins even with unknown engagement", function()
    engagement = { a = "ENGAGED", b = "ENGAGED", c = "UNKNOWN" }
    links = {}
    local r = evaluate(1, { "a", "b", "c" }, "RUNNING")
    equal(r.packState, "OVER", "state")
    equal(r.unknownEngagement, 1, "unknown count")
end)

test("unknown engagement prevents alignment", function()
    engagement = { a = "ENGAGED", b = "UNKNOWN" }
    links = {}
    local r = evaluate(1, { "a", "b" }, "RUNNING")
    equal(r.packState, "UNKNOWN", "state")
    equal(r.reasonCode, "ENGAGEMENT_UNKNOWN", "reason")
end)

test("runtime is fail closed", function()
    engagement = { a = "ENGAGED" }
    links = {}
    local absent = evaluate(1, { "a" }, nil)
    equal(absent.packState, "UNKNOWN", "missing runtime")
    equal(absent.reasonCode, "RUNTIME_UNKNOWN", "missing runtime reason")
    local inactive = evaluate(1, { "a" }, "PRE_KEY")
    equal(inactive.packState, "INACTIVE", "inactive")
    equal(inactive.reasonCode, "RUNTIME_NOT_RUNNING", "inactive reason")
end)

test("missing or invalid expected count is unknown", function()
    engagement = { a = "ENGAGED" }
    links = {}
    local missing = evaluate(nil, { "a" }, "RUNNING")
    equal(missing.packState, "UNKNOWN", "missing")
    equal(missing.reasonCode, "EXPECTED_COUNT_UNKNOWN", "missing reason")
    for _, invalid in ipairs({ 0, -1, 1.5, math.huge, 0 / 0 }) do
        local r = evaluate(invalid, { "a" }, "RUNNING")
        equal(r.expectedCountState, "UNKNOWN", "invalid state")
        equal(r.packState, "UNKNOWN", "invalid pack state")
    end
end)

test("dependency failures degrade to unknown", function()
    engagement = { a = "ERROR" }
    links = {}
    local r = evaluate(1, { "a" }, "RUNNING")
    equal(r.packState, "UNKNOWN", "engagement error")
    equal(r.unknownEngagement, 1, "engagement error count")

    engagement = { a = "ENGAGED" }
    links = { a = { TARGET = "ERROR", MOUSEOVER = "SAME_UNIT" } }
    r = evaluate(1, { "a" }, "RUNNING")
    equal(r.links.TARGET, "UNKNOWN", "link error")
    equal(r.links.MOUSEOVER, "YES", "positive link")
end)

test("missing modules degrade conservatively", function()
    local oldEE, oldUL = AR.EngagementEvidence, AR.UnitLinkEvidence
    AR.EngagementEvidence, AR.UnitLinkEvidence = nil, nil
    local r = evaluate(1, { "a" }, "RUNNING")
    equal(r.packState, "UNKNOWN", "missing engagement module")
    equal(r.links.TARGET, "UNKNOWN", "missing link module")
    AR.EngagementEvidence, AR.UnitLinkEvidence = oldEE, oldUL
end)

local sourceFile = assert(io.open("MitzuRouteArrows/Evidence/PackEvidence.lua", "r"))
local source = sourceFile:read("*a")
sourceFile:close()
for _, forbidden in ipairs({ "AR.RouteArrows", "AR.GuidanceEngine",
    "MitzuMPlus.RouteProgress", "COMBAT_LOG_EVENT_UNFILTERED",
    'rawget(_G, "UnitGUID")' }) do
    truthy(not string.find(source, forbidden, 1, true),
        "PackEvidence must not reference " .. forbidden)
end

return { tests = tests, assertions = assertions }
