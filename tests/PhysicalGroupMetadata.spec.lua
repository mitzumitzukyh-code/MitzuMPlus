-- FASE 3B: metadatos fisicos estaticos. No se carga desde el TOC.

local assertions, tests, failures = 0, 0, {}

local function equal(actual, expected, label)
    assertions = assertions + 1
    if actual ~= expected then
        error(string.format("%s: esperado %s, recibido %s",
            label or "equal", tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(value, label)
    equal(not not value, true, label)
end

local function test(name, fn)
    tests = tests + 1
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end

_G.MitzuMPlus = { AdaptiveRoute = {} }
local MitzuMPlus = _G.MitzuMPlus
function LibStub()
    return { GetAddon = function() return MitzuMPlus end }
end

dofile("data/MDTEnemyData.lua")
dofile("data/MDTPhysicalGroupData.lua")
dofile("data/Routes/Season2/Registry.lua")
for _, file in ipairs({
    "KingsRest", "TempleOfSethraliss", "RubyLifePools", "BlindingVale",
    "VoidscarArena", "DenOfNalorakk", "MurderRow", "AltarOfFangs",
}) do
    dofile("data/Routes/Season2/" .. file .. ".lua")
end
dofile("modules/RouteSchema.lua")
dofile("modules/AdaptiveRoute/DataStructure.lua")
dofile("modules/AdaptiveRoute/PhysicalGroupMetadata.lua")
dofile("modules/MDTImporter.lua")

local AR = MitzuMPlus.AdaptiveRoute
local PG = AR.PhysicalGroupMetadata

test("snapshot preserves all requested clone fields", function()
    local meta = PG:Get(42, 2, 1)
    truthy(meta, "Ruby enemy 2 clone 1")
    equal(meta.g, 1, "g")
    equal(meta.sublevel, 1, "sublevel")
    equal(meta.x, 125.6, "x")
    equal(meta.y, -366, "y")

    local patrol = PG:Get(20, 6, 1)
    equal(type(patrol.patrol), "table", "patrol table")
    equal(#patrol.patrol, 12, "patrol points")
    equal(type(PG:Get(42, 4, 9).patrol), "table", "empty patrol presence preserved")
end)

test("Ruby pull 1 has the expected physical groups", function()
    local route = MitzuMPlus.NativeRouteDB:GetDefault(399)
    local result = PG:AnalyzePull(route, 1)
    local byG = {}
    for _, group in ipairs(result.groups) do byG[group.g] = group end

    equal(byG[1].selected, 2, "g1")
    equal(byG[2].selected, 3, "g2")
    equal(byG[6].selected, 2, "g6")
    equal(byG[7].selected, 2, "g7")
    equal(byG[32].selected, 3, "g32")
    equal(byG[40].selected, 1, "g40 selected")
    equal(byG[40].total, 2, "g40 universe")
    equal(byG[40].state, "PARTIAL_GROUP", "g40 state")
    equal(result.partialGroups, 1, "Ruby pull 1 partial groups")

    local text = table.concat(PG:StatusLines(route, 1), "\n")
    equal(text:find("g1 clones=2 COMPLETE_GROUP", 1, true) ~= nil, true,
        "diagnostic g1")
    equal(text:find("g40 clones=1/2 PARTIAL_GROUP", 1, true) ~= nil, true,
        "diagnostic partial g40")
end)

test("DataStructure indexes physical metadata without using it as identity", function()
    local profile = {
        pulls = { 100 }, totalForces = 10, mdtDungeonIdx = 42,
        plannedPulls = { {
            enemies = { { enemyIdx = 2, npcID = 187969, forceCount = 5, clones = { 1 } } },
        } },
    }
    local idx = AR.DataStructure:Build(profile)
    equal(idx.cloneCount, 1, "route clone count")
    equal(idx.clonesWithPhysicalMetadata, 1, "physical metadata count")
    equal(idx.clonesWithPhysicalGroup, 1, "physical group count")
    equal(AR.DataStructure:PhysicalOfClone(2, 1).g, 1, "physical lookup")
    equal(idx.routeClones[2][1], 1, "route identity remains pull index")
end)

test("legacy profiles without physical snapshot remain compatible", function()
    local idx = AR.DataStructure:Build({
        pulls = { 100 }, plannedPulls = { {
            enemies = { { enemyIdx = 99, clones = { 1 } } },
        } },
    })
    equal(idx.cloneCount, 1, "legacy clone retained")
    equal(idx.clonesWithPhysicalMetadata, 0, "legacy metadata unavailable")
    equal(AR.DataStructure:PhysicalOfClone(99, 1), nil, "legacy lookup")
end)

test("RouteSchema preserves optional embedded metadata", function()
    local route = MitzuMPlus.RouteSchema.FromLegacyProfile({
        plannedPulls = { { enemies = { {
            enemyIdx = 1, clones = { 1 },
            cloneMetadata = { [1] = { g = 9, sublevel = 2, x = 3, y = 4,
                patrol = { { x = 5, y = 6 } } } },
        } } } },
    }, 999)
    local meta = route.pulls[1].mobs[1].cloneMetadata[1]
    equal(meta.g, 9, "embedded g")
    equal(meta.sublevel, 2, "embedded sublevel")
    equal(meta.patrol[1].x, 5, "embedded patrol")
end)

test("MDTImporter preserves enemy and clone indices without MDT runtime", function()
    _G.MDT = nil
    local route = MitzuMPlus.MDTImporter:ExtractRoute({
        value = {
            currentDungeonIdx = 42,
            pulls = { { [2] = { 1, 3 } } },
        },
        text = "test",
    })
    local enemy = route.plannedPulls[1].enemies[1]
    equal(enemy.enemyIdx, 2, "import enemyIdx")
    equal(enemy.npcID, 187969, "import static npcID")
    equal(enemy.clones[1], 1, "import clone 1")
    equal(enemy.clones[2], 3, "import clone 3")
    equal(route.mdtDungeonIdx, 42, "import dungeon index")
end)

test("global bundled-route coverage is stable", function()
    local result = PG:GlobalCoverage()
    equal(result.routes, 8, "routes")
    equal(result.pulls, 104, "pulls")
    equal(result.clones, 907, "clones")
    equal(result.clonesWithMetadata, 907, "metadata coverage")
    equal(result.clonesWithG, 891, "g coverage")
    equal(result.clonesWithoutG, 16, "without g")
    equal(result.pullsWithMultipleG, 73, "pulls with multiple g")
    equal(result.partialGroups, 7, "partial groups")
end)

test("Ruby groups integrate with correlation as two size hypotheses", function()
    AR.EngagementEvidence = {
        EvaluateTokens = function()
            return {}, { total = 5, engaged = 3, notEngaged = 2, unknown = 0 }
        end,
    }
    dofile("modules/AdaptiveRoute/PhysicalGroupCorrelation.lua")
    local route = MitzuMPlus.NativeRouteDB:GetDefault(399)
    local result = AR.PhysicalGroupCorrelation:Correlate(
        route, 1, { "nameplate1", "nameplate2", "nameplate3", "nameplate4", "nameplate5" },
        "RUNNING")
    equal(result.candidateCount, 2, "Ruby correlation candidates")
    equal(result.candidateGroups[1].label, "g2", "Ruby correlation g2")
    equal(result.candidateGroups[2].label, "g32", "Ruby correlation g32")
    equal(result.groupState, "AMBIGUOUS", "Ruby correlation state")
    equal(result.reasonCode, "MULTIPLE_SIZE_CANDIDATES", "Ruby correlation reason")
    equal(result.identityState, "UNKNOWN", "Ruby correlation identity")
end)

if #failures > 0 then
    error(string.format("PhysicalGroupMetadata: %d tests, %d assertions, %d failures\n%s",
        tests, assertions, #failures, table.concat(failures, "\n")), 0)
end

return { tests = tests, assertions = assertions }
