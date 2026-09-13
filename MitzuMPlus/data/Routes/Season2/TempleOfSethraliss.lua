-- =========================================================================
-- MitzuMPlus - Ruta nativa empaquetada: Temple of Sethraliss (dungeonKey 250)
--
-- GENERADO. No editar a mano.
--   generador: notas/_tools/export_native_routes.py
--   formato:   MitzuRoute v1 (modules/RouteSchema.lua)
--
-- Procedencia de los datos: ruta 'elitzur_temple_1' de Mythic Dungeon Tools,
-- normalizada por RouteSchema.FromLegacyProfile. MDT NO hace falta en
-- ejecucion: estos datos ya viajan dentro del addon.
-- Ver DATA_SOURCES.md para atribucion y licencia.
--
-- 11 pulls - 114 clones (83 validos, 31 sin resolver)
-- =========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus or not MitzuMPlus.NativeRouteDB then return end

MitzuMPlus.NativeRouteDB:Register({
    schemaVersion = 1,
    id            = "mitzu_250_standard",
    dungeonKey    = 250,
    name          = "Mitzu Standard",
    dungeonName   = "Temple of Sethraliss",
    totalForces   = 687,
    mdtDungeonIdx = 20,
    source = {
        type            = "MITZU_NATIVE",
        dataOrigin      = "MDT-API",
        originalRouteID = "elitzur_temple_1",
    },
    legacyIDs = { "elitzur_temple_1" },
    pulls = {
        { id = 1, count = 82, mobs = {
            { npcID = 134600, enemyIdx = 1, forces = 7, amount = 2, cloneIDs = { 8, 22 } },
            { npcID = 134616, enemyIdx = 2, forces = 5, amount = 3, cloneIDs = { 8, 15, 16 } },
            { npcID = 134990, enemyIdx = 3, forces = 7, amount = 3, cloneIDs = { 2, 8, 9 } },
            { npcID = 134991, enemyIdx = 4, forces = 25, amount = 1, cloneIDs = { 4 } },
            { npcID = 134602, enemyIdx = 5, forces = 7, amount = 1, cloneIDs = { 11 } },
        } },
        { id = 2, count = 65, mobs = {
            { npcID = 134600, enemyIdx = 1, forces = 7, amount = 2, cloneIDs = { 23, 24 } },
            { npcID = 134616, enemyIdx = 2, forces = 5, amount = 1, cloneIDs = { 17 } },
            { npcID = 134990, enemyIdx = 3, forces = 7, amount = 1, cloneIDs = { 7 } },
            { npcID = 134991, enemyIdx = 4, forces = 25, amount = 1, cloneIDs = { 3 } },
            { npcID = 134602, enemyIdx = 5, forces = 7, amount = 2, cloneIDs = { 10, 12 } },
        } },
        { id = 3, count = 26, mobs = {
            { npcID = 134600, enemyIdx = 1, forces = 7, amount = 1, cloneIDs = { 21 } },
            { npcID = 134616, enemyIdx = 2, forces = 5, amount = 1, cloneIDs = { 13 } },
            { npcID = 134990, enemyIdx = 3, forces = 7, amount = 1, cloneIDs = { 6 } },
            { npcID = 134602, enemyIdx = 5, forces = 7, amount = 1, cloneIDs = { 5 } },
            { npcID = 262530, enemyIdx = 30, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 262822, enemyIdx = 31, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 4, count = 109, mobs = {
            { npcID = 134600, enemyIdx = 1, forces = 7, amount = 2, cloneIDs = { 13, 18 } },
            { npcID = 134990, enemyIdx = 3, forces = 7, amount = 3, cloneIDs = { 3, 4, 5 } },
            { npcID = 134629, enemyIdx = 6, forces = 25, amount = 2, cloneIDs = { 1, 2 } },
            { npcID = 135562, enemyIdx = 7, forces = 7, amount = 2, cloneIDs = { 1, 3 } },
            { npcID = 135846, enemyIdx = 8, forces = 5, amount = 2, cloneIDs = { 1, 3 } },
            { npcID = 264785, enemyIdx = 34, forces = 0, amount = 2, cloneIDs = { 1, 2 } },
        } },
        { id = 5, count = 77, mobs = {
            { npcID = 134629, enemyIdx = 6, forces = 25, amount = 1, cloneIDs = { 6 } },
            { npcID = 135562, enemyIdx = 7, forces = 7, amount = 3, cloneIDs = { 4, 5, 6 } },
            { npcID = 135846, enemyIdx = 8, forces = 5, amount = 2, cloneIDs = { 4, 5 } },
            { npcID = 134364, enemyIdx = 11, forces = 7, amount = 1, cloneIDs = { 1 } },
            { npcID = 139425, enemyIdx = 12, forces = 7, amount = 2, cloneIDs = { 1, 5 } },
            { npcID = 264785, enemyIdx = 34, forces = 0, amount = 1, cloneIDs = { 3 } },
        } },
        { id = 6, count = 63, mobs = {
            { npcID = 134600, enemyIdx = 1, forces = 7, amount = 1, cloneIDs = { 19 } },
            { npcID = 134629, enemyIdx = 6, forces = 25, amount = 1, cloneIDs = { 7 } },
            { npcID = 135562, enemyIdx = 7, forces = 7, amount = 1, cloneIDs = { 7 } },
            { npcID = 135846, enemyIdx = 8, forces = 5, amount = 2, cloneIDs = { 6, 7 } },
            { npcID = 134364, enemyIdx = 11, forces = 7, amount = 1, cloneIDs = { 6 } },
            { npcID = 139425, enemyIdx = 12, forces = 7, amount = 1, cloneIDs = { 6 } },
            { npcID = 264785, enemyIdx = 34, forces = 0, amount = 1, cloneIDs = { 4 } },
        } },
        { id = 7, count = 0, mobs = {
            { npcID = 133384, enemyIdx = 13, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 134388, enemyIdx = 20, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 134389, enemyIdx = 21, forces = 0, amount = 2, cloneIDs = { 1, 2 } },
            { npcID = 134390, enemyIdx = 22, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 134487, enemyIdx = 23, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 263181, enemyIdx = 32, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 263383, enemyIdx = 43, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 8, count = 79, mobs = {
            { npcID = 136076, enemyIdx = 14, forces = 25, amount = 2, cloneIDs = { 1, 4 } },
            { npcID = 134599, enemyIdx = 15, forces = 7, amount = 2, cloneIDs = { 1, 4 } },
            { npcID = 134691, enemyIdx = 16, forces = 5, amount = 2, cloneIDs = { 5, 10 } },
            { npcID = 265057, enemyIdx = 19, forces = 5, amount = 1, cloneIDs = { 1 } },
            { npcID = 139108, enemyIdx = 27, forces = 0, amount = 1, cloneIDs = { 2 } },
        } },
        { id = 9, count = 59, mobs = {
            { npcID = 136076, enemyIdx = 14, forces = 25, amount = 1, cloneIDs = { 2 } },
            { npcID = 134599, enemyIdx = 15, forces = 7, amount = 2, cloneIDs = { 5, 6 } },
            { npcID = 134691, enemyIdx = 16, forces = 5, amount = 4, cloneIDs = { 1, 2, 3, 4 } },
            { npcID = 135445, enemyIdx = 25, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 139131, enemyIdx = 28, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 263658, enemyIdx = 33, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 10, count = 75, mobs = {
            { npcID = 135007, enemyIdx = 24, forces = 25, amount = 2, cloneIDs = { 1, 2 } },
            { npcID = 139108, enemyIdx = 27, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 240681, enemyIdx = 29, forces = 0, amount = 2, cloneIDs = { 1, 2 } },
            { npcID = 139110, enemyIdx = 41, forces = 5, amount = 1, cloneIDs = { 1 } },
            { npcID = 269227, enemyIdx = 45, forces = 5, amount = 4, cloneIDs = { 1, 2, 3, 4 } },
        } },
        { id = 11, count = 45, mobs = {
            { npcID = 136250, enemyIdx = 17, forces = 25, amount = 1, cloneIDs = { 6 } },
            { npcID = 133392, enemyIdx = 18, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 268317, enemyIdx = 35, forces = 5, amount = 4, cloneIDs = { 1, 2, 3, 4 } },
            { npcID = 268344, enemyIdx = 36, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 268364, enemyIdx = 37, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 268427, enemyIdx = 38, forces = 0, amount = 2, cloneIDs = { 1, 2 } },
            { npcID = 268491, enemyIdx = 39, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 268729, enemyIdx = 40, forces = 0, amount = 4, cloneIDs = { 1, 2, 3, 4 } },
            { npcID = 135971, enemyIdx = 42, forces = 0, amount = 8, cloneIDs = { 5, 6, 7, 8, 9, 10, 11, 12 } },
            { npcID = 268747, enemyIdx = 44, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
    },
})
