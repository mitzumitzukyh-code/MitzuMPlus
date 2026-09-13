-- FASE 3C: correlacion estructural. No se carga desde el TOC.

local assertions, tests, failures = 0, 0, {}

local function equal(actual, expected, label)
    assertions = assertions + 1
    if actual ~= expected then
        error(string.format("%s: esperado %s, recibido %s",
            label or "equal", tostring(expected), tostring(actual)), 2)
    end
end

local function test(name, fn)
    tests = tests + 1
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end

_G.MitzuRouteArrows = { Host = {} }
local AR = _G.MitzuRouteArrows
local summary = { total = 0, engaged = 0, notEngaged = 0, unknown = 0 }
local physical = { state = "AVAILABLE", groups = {}, clonesWithoutG = 0 }

AR.EngagementEvidence = {
    EvaluateTokens = function()
        return {}, {
            total = summary.total, engaged = summary.engaged,
            notEngaged = summary.notEngaged, unknown = summary.unknown,
        }
    end,
}
AR.PhysicalGroupMetadata = {
    AnalyzePull = function() return physical end,
}

dofile("MitzuRouteArrows/Evidence/PhysicalGroupCorrelation.lua")
local C = AR.PhysicalGroupCorrelation
local route = { id = "test_route", pulls = { {} } }

local function complete(g, size)
    return { g = g, sublevel = 1, selected = size, total = size,
             state = "COMPLETE_GROUP" }
end

local function partial(g, selected, total)
    return { g = g, sublevel = 1, selected = selected, total = total,
             state = "PARTIAL_GROUP" }
end

local function correlate(groups, engaged, notEngaged, unknown, ungrouped)
    summary = {
        total = engaged + notEngaged + unknown,
        engaged = engaged, notEngaged = notEngaged, unknown = unknown,
    }
    physical = {
        state = "AVAILABLE", groups = groups,
        clonesWithoutG = ungrouped or 0,
    }
    return C:Correlate(route, 1, { "nameplate1" }, "RUNNING")
end

test("A engaged 3 with g2 and g32 is ambiguous", function()
    local r = correlate({
        complete(1, 2), complete(2, 3), complete(6, 2),
        complete(7, 2), complete(32, 3), partial(40, 1, 2),
    }, 3, 2, 0)
    equal(r.candidateCount, 2, "A candidate count")
    equal(r.candidateGroups[1].label, "g2", "A first candidate")
    equal(r.candidateGroups[2].label, "g32", "A second candidate")
    equal(r.groupState, "AMBIGUOUS", "A state")
    equal(r.reasonCode, "MULTIPLE_SIZE_CANDIDATES", "A reason")
    equal(r.identityState, "UNKNOWN", "A identity")
end)

test("B engaged 2 with several size-2 groups is ambiguous", function()
    local r = correlate({ complete(1, 2), complete(6, 2), complete(7, 2) }, 2, 0, 0)
    equal(r.candidateCount, 3, "B candidate count")
    equal(r.groupState, "AMBIGUOUS", "B state")
    equal(r.reasonCode, "MULTIPLE_SIZE_CANDIDATES", "B reason")
end)

test("C a unique size candidate remains only a hypothesis", function()
    local r = correlate({ complete(1, 1), complete(2, 3) }, 1, 0, 0)
    equal(r.candidateCount, 1, "C candidate count")
    equal(r.candidateGroups[1].label, "g1", "C candidate")
    equal(r.groupState, "HYPOTHESIS", "C state")
    equal(r.reasonCode, "UNIQUE_SIZE_CANDIDATE", "C reason")
    equal(r.identityState, "UNKNOWN", "C identity")
    equal(r.groupState == "MATCH", false, "C never MATCH")
end)

test("D no group of the observed size yields no size candidate", function()
    local r = correlate({ complete(1, 2), complete(2, 4) }, 3, 0, 0)
    equal(r.candidateCount, 0, "D candidate count")
    equal(r.groupState, "NONE", "D state")
    equal(r.reasonCode, "NO_SIZE_CANDIDATE", "D reason")
    equal(r.identityState, "UNKNOWN", "D identity")
end)

test("E a compatible partial group blocks confidence elevation", function()
    local r = correlate({ complete(1, 2), partial(40, 1, 2) }, 2, 0, 0)
    equal(r.candidateCount, 2, "E includes contextual partial")
    equal(r.candidateGroups[2].physicalState, "PARTIAL_GROUP", "E partial marked")
    equal(r.groupState, "AMBIGUOUS", "E state")
    equal(r.reasonCode, "PARTIAL_GROUP_PRESENT", "E reason")
    equal(r.identityState, "UNKNOWN", "E identity")
end)

test("F ungrouped clones make the candidate universe non-exhaustive", function()
    local r = correlate({ complete(1, 1), complete(2, 3) }, 1, 0, 0, 2)
    equal(r.candidateCount, 1, "F known candidates")
    equal(r.clonesWithoutG, 2, "F ungrouped")
    equal(r.groupState, "UNKNOWN", "F state")
    equal(r.reasonCode, "UNGROUPED_CLONES_PRESENT", "F reason")
    equal(r.identityState, "UNKNOWN", "F identity")
end)

test("G unknown engagement degrades the size comparison", function()
    local r = correlate({ complete(1, 1) }, 1, 0, 1)
    equal(r.unknownEngagement, 1, "G unknown count")
    equal(r.candidateCount, 0, "G no candidates asserted")
    equal(r.groupState, "UNKNOWN", "G state")
    equal(r.reasonCode, "UNKNOWN_ENGAGEMENT", "G reason")
    equal(r.identityState, "UNKNOWN", "G identity")
end)

test("no engaged plates is diagnostic unknown", function()
    local r = correlate({ complete(1, 1) }, 0, 2, 0)
    equal(r.groupState, "UNKNOWN", "no engaged state")
    equal(r.reasonCode, "NO_ENGAGED", "no engaged reason")
end)

test("missing metadata is reported without candidates", function()
    physical = { state = "UNAVAILABLE", groups = {}, clonesWithoutG = 0 }
    summary = { total = 1, engaged = 1, notEngaged = 0, unknown = 0 }
    local r = C:Correlate(route, 1, {}, "RUNNING")
    equal(r.candidateCount, 0, "no metadata candidates")
    equal(r.groupState, "UNKNOWN", "no metadata state")
    equal(r.reasonCode, "NO_METADATA", "no metadata reason")
end)

test("status output labels hypotheses without identity", function()
    local r = correlate({ complete(1, 1) }, 1, 0, 0)
    local text = table.concat(C:StatusLines(r), "\n")
    equal(text:find("candidateGroups=g1", 1, true) ~= nil, true, "output candidate")
    equal(text:find("groupState=HYPOTHESIS", 1, true) ~= nil, true, "output state")
    equal(text:find("reasonCode=UNIQUE_SIZE_CANDIDATE", 1, true) ~= nil, true,
        "output reason")
    equal(text:find("identityState=UNKNOWN", 1, true) ~= nil, true, "output identity")
    equal(text:find("MATCH", 1, true), nil, "output never says MATCH")
end)

if #failures > 0 then
    error(string.format("PhysicalGroupCorrelation: %d tests, %d assertions, %d failures\n%s",
        tests, assertions, #failures, table.concat(failures, "\n")), 0)
end

return { tests = tests, assertions = assertions }
