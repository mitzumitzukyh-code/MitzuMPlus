-- MitzuMPlus (core): datos de ruta sin MDT en ejecucion.
-- No se carga desde el TOC. Ejecutar con: python tests/run_lua_tests.py
--
-- Venian de PhysicalGroupMetadata.spec, que mezclaba core y capa experimental.
-- Aqui queda solo lo que es del core tras la separacion: DataStructure indexa
-- la identidad de ruta (enemyIdx + cloneIdx) y conserva la geometria que el
-- perfil traiga EMBEBIDA, pero ya no consulta la fotografia fisica externa
-- (MDTPhysicalGroupData), que es de MitzuRouteArrows.

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

dofile("MitzuMPlus/data/MDTEnemyData.lua")
dofile("MitzuMPlus/data/Routes/Season2/Registry.lua")
for _, file in ipairs({
    "KingsRest", "TempleOfSethraliss", "RubyLifePools", "BlindingVale",
    "VoidscarArena", "DenOfNalorakk", "MurderRow", "AltarOfFangs",
}) do
    dofile("MitzuMPlus/data/Routes/Season2/" .. file .. ".lua")
end
dofile("MitzuMPlus/modules/RouteSchema.lua")
dofile("MitzuMPlus/modules/AdaptiveRoute/DataStructure.lua")
dofile("MitzuMPlus/modules/MDTImporter.lua")

local AR = MitzuMPlus.AdaptiveRoute

test("DataStructure indexa la identidad de ruta y no usa geometria como identidad", function()
    local profile = {
        pulls = { 100 }, totalForces = 10, mdtDungeonIdx = 42,
        plannedPulls = { {
            enemies = { { enemyIdx = 2, npcID = 187969, forceCount = 5, clones = { 1 } } },
        } },
    }
    local idx = AR.DataStructure:Build(profile)
    equal(idx.cloneCount, 1, "route clone count")
    equal(idx.routeClones[2][1], 1, "route identity remains pull index")
    -- La fotografia fisica externa ya no es del core.
    equal(idx.physicalByClone, nil, "sin indice fisico en el core")
    equal(idx.clonesWithPhysicalMetadata, nil, "sin contador fisico en el core")
    equal(AR.DataStructure.PhysicalOfClone, nil, "sin consulta fisica en el core")
    equal(MitzuMPlus.MDTPhysicalGroupData, nil, "el core no carga la fotografia fisica")
end)

test("DataStructure conserva la geometria EMBEBIDA en el perfil", function()
    local idx = AR.DataStructure:Build({
        pulls = { 100 }, plannedPulls = { {
            enemies = { { enemyIdx = 7, clones = { 3 },
                cloneMetadata = { [3] = { g = 4, sublevel = 1, x = 10, y = 20 } } } },
        } },
    })
    local enemy = idx.pulls[1].enemies[1]
    equal(enemy.cloneMetadata[3].g, 4, "g embebido conservado")
    equal(enemy.cloneMetadata[3].x, 10, "x embebido conservado")
end)

test("perfiles antiguos sin geometria siguen siendo compatibles", function()
    local idx = AR.DataStructure:Build({
        pulls = { 100 }, plannedPulls = { {
            enemies = { { enemyIdx = 99, clones = { 1 } } },
        } },
    })
    equal(idx.cloneCount, 1, "legacy clone retained")
    equal(next(idx.pulls[1].enemies[1].cloneMetadata), nil, "sin geometria")
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
    _G.MythicDungeonToolsAPI = nil
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

test("las ocho rutas nativas viajan con el core y no necesitan MDT", function()
    local db = MitzuMPlus.NativeRouteDB
    equal(db:Count(), 8, "rutas registradas")
    local st = db:Stats()
    equal(st.pulls, 104, "pulls")
    equal(st.clones, 907, "clones")
    truthy(db:GetDefault(399), "Ruby Life Pools tiene ruta por defecto")
    equal(rawget(_G, "MDT"), nil, "MDT no esta")
end)

if #failures > 0 then
    error(string.format("RouteData: %d tests, %d assertions, %d failures\n%s",
        tests, assertions, #failures, table.concat(failures, "\n")), 0)
end

return { tests = tests, assertions = assertions }
