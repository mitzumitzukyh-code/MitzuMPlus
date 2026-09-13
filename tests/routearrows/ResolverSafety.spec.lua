-- FASE 3A: regresiones de seguridad del resolver y del pipeline de flechas.
-- No se carga desde el TOC. Ejecutar con: python tests/run_lua_tests.py

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

local npcByToken, forcesByToken, guidCalls = {}, {}, {}

function UnitExists(token) return npcByToken[token] ~= nil end
function UnitGUID(token)
    guidCalls[token] = (guidCalls[token] or 0) + 1
    local npcID = npcByToken[token]
    if npcID == "SECRET" then return "secret-guid" end
    return npcID and ("Creature-0-0-0-0-" .. npcID .. "-0000000000") or nil
end
function UnitName() return nil end
function UnitClassification() return nil end
function UnitCreatureType() return nil end
function UnitLevel() return nil end
function UnitHealthMax() return nil end
function UnitCastingInfo() return nil end
function issecretvalue(value) return value == "secret-guid" end
function strsplit(separator, value)
    local out = {}
    for part in string.gmatch(value, "[^" .. separator .. "]+") do
        out[#out + 1] = part
    end
    return table.unpack(out)
end

C_ScenarioInfo = {
    GetUnitCriteriaProgressValues = function(token) return forcesByToken[token] end,
}

-- ── Un MitzuMPlus FALSO hace de core. MitzuRouteArrows no lo ve directamente:
-- lo lee a traves de la API publica REAL (MitzuMPlus/API/PublicAPI.lua) y de
-- la fachada REAL (MitzuRouteArrows/Core/Host.lua). Asi este banco prueba el
-- camino completo: resolver -> Host -> API -> core.
_G.MitzuMPlus = { AdaptiveRoute = {}, MDTEnemyData = {}, db = {} }
local MitzuMPlus = _G.MitzuMPlus
local CORE_AR = MitzuMPlus.AdaptiveRoute
local routeIndex

CORE_AR.DataStructure = {
    Get = function() return routeIndex end,
    EnemiesOf = function(_, pullIndex)
        local pull = routeIndex and routeIndex.pulls[pullIndex]
        return pull and pull.enemies or nil
    end,
}
CORE_AR.PullNavigator = { GetCurrentPull = function() return 1 end }

MitzuMPlus.RouteManager = {
    GetActiveRoute = function() return { mdtDungeonIdx = 42 } end,
}

function LibStub()
    return { GetAddon = function() return MitzuMPlus end }
end
function CreateFrame()
    return { RegisterEvent = function() end, SetScript = function() end }
end

dofile("MitzuMPlus/API/PublicAPI.lua")
dofile("MitzuRouteArrows/Core/Bootstrap.lua")
dofile("MitzuRouteArrows/Core/Host.lua")
local AR = _G.MitzuRouteArrows

local function enemy(enemyIdx, npcID, forces, clones)
    return { enemyIdx = enemyIdx, npcID = npcID, forceCount = forces, clones = clones }
end

local function scenario(pulls, dungeonEnemies)
    routeIndex = { pulls = {}, pullCount = #pulls, mdtDungeonIdx = 42 }
    for i, enemies in ipairs(pulls) do
        routeIndex.pulls[i] = { index = i, enemies = enemies }
    end
    MitzuMPlus.MDTEnemyData[42] = { e = dungeonEnemies or {} }
    npcByToken, forcesByToken, guidCalls = {}, {}, {}
end

dofile("MitzuRouteArrows/Modules/LiveEnemyResolver.lua")
local LER = AR.LiveEnemyResolver

test("A global unique npcID in current pull is MATCH", function()
    scenario({ { enemy(1, 123, 5, { 1 }) } }, { [1] = { 123, 5, 1 } })
    npcByToken.plateA = 123
    local r = LER:Resolve("plateA", 1)
    equal(r.matchState, "MATCH", "A resolver")
    equal(LER:ResolveForGuidance("plateA", 1), "MATCH", "A guidance boundary")
end)

test("B multiple compatible clones all in current pull are AMBIGUOUS", function()
    scenario({ { enemy(1, 123, 5, { 1, 2 }) } }, { [1] = { 123, 5, 2 } })
    npcByToken.plateB = 123
    local r = LER:Resolve("plateB", 1)
    equal(r.matchState, "AMBIGUOUS", "B resolver")
    equal(LER:ResolveForGuidance("plateB", 1), "AMBIGUOUS", "B boundary")
end)

test("C compatible clone in current and future pull is AMBIGUOUS", function()
    scenario({
        { enemy(1, 123, 5, { 1 }) },
        { enemy(1, 123, 5, { 2 }) },
    }, { [1] = { 123, 5, 2 } })
    npcByToken.plateC = 123
    local r = LER:Resolve("plateC", 1)
    equal(r.matchState, "AMBIGUOUS", "C resolver")
    equal(r.candidateCount, 2, "C global candidates")
end)

test("D compatible clone outside route prevents MATCH", function()
    scenario({ { enemy(1, 123, 5, { 1 }) } }, { [1] = { 123, 5, 2 } })
    npcByToken.plateD = 123
    local r = LER:Resolve("plateD", 1)
    equal(r.matchState, "AMBIGUOUS", "D resolver")
    equal(r.candidateCount, 2, "D dungeon candidates")
end)

test("E two nameplates cannot choose between same compatible cloneIDs", function()
    scenario({ { enemy(1, 123, 5, { 1, 2 }) } }, { [1] = { 123, 5, 2 } })
    npcByToken.plateE1, npcByToken.plateE2 = 123, 123
    equal(LER:Resolve("plateE1", 1).matchState, "AMBIGUOUS", "E first")
    equal(LER:Resolve("plateE2", 1).matchState, "AMBIGUOUS", "E second")
end)

test("F npcID absent from current pull is NO_MATCH", function()
    scenario({
        { enemy(2, 999, 7, { 1 }) },
        { enemy(1, 123, 5, { 1 }) },
    }, { [1] = { 123, 5, 1 }, [2] = { 999, 7, 1 } })
    npcByToken.plateF = 123
    equal(LER:Resolve("plateF", 1).matchState, "NO_MATCH", "F resolver")
    equal(LER:ResolveForGuidance("plateF", 1), "NO_MATCH", "F boundary")
end)

test("G insufficient information is UNKNOWN", function()
    scenario({ { enemy(1, 123, 5, { 1 }) } }, { [1] = { 123, 5, 1 } })
    npcByToken.plateG = "SECRET"
    equal(LER:Resolve("plateG", 1).matchState, "UNKNOWN", "G resolver")
    equal(LER:ResolveForGuidance("plateG", 1), "UNKNOWN", "G boundary")
end)

test("G readable npcID without global clone universe is UNKNOWN", function()
    scenario({ { enemy(1, 123, 5, { 1 }) } }, {})
    npcByToken.plateG2 = 123
    local r = LER:Resolve("plateG2", 1)
    equal(r.matchState, "UNKNOWN", "G missing universe")
    equal(r.reason, "NPCID_UNIVERSE_INCOMPLETE", "G missing universe reason")
end)

test("forces signature alone never produces MATCH", function()
    scenario({ { enemy(1, 123, 5, { 1 }) } }, { [1] = { 123, 5, 1 } })
    npcByToken.plateForces = "SECRET"
    forcesByToken.plateForces = 5
    equal(LER:Resolve("plateForces", 1).matchState, "UNKNOWN", "forces-only")
end)

test("target and nameplate use independent direct UnitGUID paths", function()
    scenario({ { enemy(1, 123, 5, { 1 }) } }, { [1] = { 123, 5, 1 } })
    npcByToken.target = 123
    npcByToken.nameplate1 = "SECRET"
    forcesByToken.nameplate1 = "secret-guid"

    equal(LER:Resolve("target", 1).matchState, "MATCH", "direct target result")
    equal(LER:Resolve("nameplate1", 1).matchState, "UNKNOWN", "direct plate result")
    equal(guidCalls.target, 1, "UnitGUID target calls")
    equal(guidCalls.nameplate1, 1, "UnitGUID nameplate calls")
end)

test("SAME_UNIT evidence is not an identity-reading capability", function()
    scenario({ { enemy(1, 123, 5, { 1 }) } }, { [1] = { 123, 5, 1 } })
    npcByToken.nameplate1 = "SECRET"
    forcesByToken.nameplate1 = "secret-guid"
    local linkCalls = 0
    AR.UnitLinkEvidence = {
        Evaluate = function()
            linkCalls = linkCalls + 1
            return { state = "SAME_UNIT" }
        end,
    }

    local r = LER:Resolve("nameplate1", 1)
    equal(r.matchState, "UNKNOWN", "SAME_UNIT cannot create MATCH")
    equal(linkCalls, 0, "resolver does not consult UnitLinkEvidence")
end)

test("safe forces API cannot manufacture npcID when GUID is secret", function()
    scenario({ { enemy(1, 123, 5, { 1 }) } }, { [1] = { 123, 5, 1 } })
    npcByToken.nameplate1 = "SECRET"
    forcesByToken.nameplate1 = 5

    local r = LER:Resolve("nameplate1", 1)
    equal(r.npcID, nil, "npcID remains absent")
    equal(r.npcIDState, "UNAVAILABLE", "npcID state")
    equal(r.matchState, "UNKNOWN", "forces do not create identity")
    equal(r.reason, "FORCES_NOT_IDENTITY", "real resolver reason")
end)

test("resolver diagnostic exposes only closed safe states and real reason", function()
    scenario({ { enemy(1, 123, 5, { 1 }) } }, { [1] = { 123, 5, 1 } })
    npcByToken.nameplate1 = "SECRET"
    forcesByToken.nameplate1 = "secret-guid"

    local lines = LER:ResolverDiagnosticLines("nameplate1", 1)
    local text = table.concat(lines, "\n")
    equal(text:find("unitExists=YES", 1, true) ~= nil, true, "diagnostic exists")
    equal(text:find("guidState=SECRET", 1, true) ~= nil, true, "diagnostic guid")
    equal(text:find("npcIDState=UNAVAILABLE", 1, true) ~= nil, true, "diagnostic npcID")
    equal(text:find("candidateUniverseState=AVAILABLE", 1, true) ~= nil, true,
        "diagnostic universe")
    equal(text:find("resolverState=UNKNOWN", 1, true) ~= nil, true, "diagnostic state")
    equal(text:find("resolverReason=FORCES_SECRET", 1, true) ~= nil, true,
        "diagnostic real reason")
    equal(text:find("secret-guid", 1, true), nil, "secret value omitted")
    equal(text:find("npcID=", 1, true), nil, "raw npcID omitted")
end)

test("resolverdump enumerates each visible nameplate without raw identity", function()
    scenario({ { enemy(1, 123, 5, { 1 }) } }, { [1] = { 123, 5, 1 } })
    npcByToken.nameplate1 = "SECRET"
    npcByToken.nameplate2 = "SECRET"
    forcesByToken.nameplate1 = "secret-guid"
    forcesByToken.nameplate2 = "secret-guid"
    C_NamePlate = {
        GetNamePlates = function()
            return {
                { namePlateUnitToken = "nameplate2" },
                { namePlateUnitToken = "nameplate1" },
            }
        end,
    }

    local text = table.concat(LER:ResolverDumpLines(), "\n")
    equal(text:find("nameplate1", 1, true) ~= nil, true, "first plate present")
    equal(text:find("nameplate2", 1, true) ~= nil, true, "second plate present")
    equal(text:find("resolverReason=FORCES_SECRET", 1, true) ~= nil, true,
        "dump includes real reason")
    equal(text:find("secret-guid", 1, true), nil, "dump omits secret")
    equal(text:find("npcID=", 1, true), nil, "dump omits raw npcID")
end)

-- Pipeline real: resolver -> frontera -> Guidance -> Presenter -> MarkUnit.
local marked = 0
AR.RouteArrows = {
    MarkUnit = function() marked = marked + 1; return true end,
    UnmarkUnit = function() return true end,
    CountActive = function() return marked end,
}
MitzuMPlus.DungeonContext = { GetState = function() return "RUNNING" end }
MitzuMPlus.RouteProgress = {
    GetState = function() return "ACTIVE" end,
    GetPullIndex = function() return 1 end,
    GetCurrentPull = function() return { mobs = { true } } end,
}
MitzuMPlus.EventBus = nil

dofile("MitzuRouteArrows/Modules/GuidanceEngine.lua")
dofile("MitzuRouteArrows/Modules/RouteArrowPresenter.lua")

test("ambiguous npcID never produces automatic arrow", function()
    scenario({ { enemy(1, 123, 5, { 1, 2 }) } }, { [1] = { 123, 5, 2 } })
    npcByToken.plateArrow = 123
    marked = 0
    local decision = AR.GuidanceEngine:Evaluate("plateArrow")
    equal(decision.state, "AMBIGUOUS", "arrow decision state")
    equal(decision.shouldMark, false, "arrow decision mark")
    equal(AR.RouteArrowPresenter:Apply("plateArrow", decision), false,
        "presenter result")
    equal(marked, 0, "MarkUnit calls")
end)

if #failures > 0 then
    error(string.format("ResolverSafety: %d tests, %d assertions, %d failures\n%s",
        tests, assertions, #failures, table.concat(failures, "\n")), 0)
end

return { tests = tests, assertions = assertions }
