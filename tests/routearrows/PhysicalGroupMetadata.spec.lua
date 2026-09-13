-- FASE 3B: metadatos fisicos estaticos (MitzuRouteArrows). No se carga desde el TOC.
--
-- Las rutas nativas son de MitzuMPlus: aqui se cargan los ficheros de datos
-- REALES del core, y la capa experimental las lee por la API publica REAL y
-- la fachada REAL, como en el juego. Lo que antes probaba este banco sobre
-- DataStructure, RouteSchema y MDTImporter (core) vive ahora en
-- tests/core/RouteData.spec.lua.

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

_G.MitzuMPlus = { AdaptiveRoute = {}, db = {} }
local MitzuMPlus = _G.MitzuMPlus
function LibStub()
    return { GetAddon = function() return MitzuMPlus end }
end

-- Core: datos empaquetados y API publica.
dofile("MitzuMPlus/data/MDTEnemyData.lua")
dofile("MitzuMPlus/data/Routes/Season2/Registry.lua")
for _, file in ipairs({
    "KingsRest", "TempleOfSethraliss", "RubyLifePools", "BlindingVale",
    "VoidscarArena", "DenOfNalorakk", "MurderRow", "AltarOfFangs",
}) do
    dofile("MitzuMPlus/data/Routes/Season2/" .. file .. ".lua")
end
dofile("MitzuMPlus/API/PublicAPI.lua")

-- MitzuRouteArrows: nucleo, datos fisicos y el modulo bajo prueba.
dofile("MitzuRouteArrows/Core/Bootstrap.lua")
dofile("MitzuRouteArrows/Core/Host.lua")
dofile("MitzuRouteArrows/Data/MDTPhysicalGroupData.lua")
dofile("MitzuRouteArrows/Evidence/PhysicalGroupMetadata.lua")

local AR = _G.MitzuRouteArrows
local PG = AR.PhysicalGroupMetadata

-- La ruta por defecto de una mazmorra, leida como la lee el addon: por la API.
local function rutaNativa(dungeonKey)
    return AR.Host.NativeRouteDB:GetForDungeon(dungeonKey)[1]
end

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
    local route = rutaNativa(399)
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

test("la ruta que entrega la API es una COPIA: tocarla no cambia el core", function()
    -- Copia NUEVA pedida a la API, no la que guarda Host en cache: la de la
    -- cache es compartida por todo este addon y ensuciarla afectaria a los
    -- tests siguientes (que es justo lo que paso en el primer intento).
    local copia = _G.MitzuMPlusAPI.GetNativeRoutesForDungeon(399)[1]
    local original = MitzuMPlus.NativeRouteDB:GetDefault(399)
    truthy(copia ~= original, "no es la misma tabla")
    local antes = original.pulls[1].mobs[1].amount
    copia.pulls[1].mobs[1].amount = 999
    copia.pulls[1] = nil
    equal(original.pulls[1].mobs[1].amount, antes, "el core conserva su dato")
    truthy(original.pulls[1] ~= nil, "el core conserva su pull")
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
    dofile("MitzuRouteArrows/Evidence/PhysicalGroupCorrelation.lua")
    local route = rutaNativa(399)
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
