-- =========================================================================
-- MitzuMPlus - Ruta nativa empaquetada: Murder Row (dungeonKey 587)
--
-- GENERADO. No editar a mano.
--   generador: notas/_tools/export_native_routes.py
--   formato:   MitzuRoute v1 (modules/RouteSchema.lua)
--
-- Procedencia de los datos: ruta 'Peon MR' de Mythic Dungeon Tools,
-- normalizada por RouteSchema.FromLegacyProfile. MDT NO hace falta en
-- ejecucion: estos datos ya viajan dentro del addon.
-- Ver DATA_SOURCES.md para atribucion y licencia.
--
-- 13 pulls - 160 clones (155 validos, 5 sin resolver)
-- =========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus or not MitzuMPlus.NativeRouteDB then return end

MitzuMPlus.NativeRouteDB:Register({
    schemaVersion = 1,
    id            = "mitzu_587_standard",
    dungeonKey    = 587,
    name          = "Mitzu Standard",
    dungeonName   = "Murder Row",
    totalForces   = 655,
    mdtDungeonIdx = 160,
    source = {
        type            = "MITZU_NATIVE",
        dataOrigin      = "MDT-API",
        originalRouteID = "Peon MR",
    },
    legacyIDs = { "Peon MR" },
    pulls = {
        { id = 1, count = 87, mobs = {
            { npcID = 236085, enemyIdx = 1, forces = 1, amount = 9, cloneIDs = { 1, 2, 3, 4, 5, 6, 7, 8, 9 } },
            { npcID = 236073, enemyIdx = 2, forces = 3, amount = 4, cloneIDs = { 1, 2, 3, 4 } },
            { npcID = 236084, enemyIdx = 3, forces = 7, amount = 5, cloneIDs = { 1, 2, 3, 4, 5 } },
            { npcID = 236071, enemyIdx = 4, forces = 25, amount = 1, cloneIDs = { 1 } },
            { npcID = 236091, enemyIdx = 8, forces = 3, amount = 2, cloneIDs = { 3, 6 } },
        } },
        { id = 2, count = 61, mobs = {
            { npcID = 236085, enemyIdx = 1, forces = 1, amount = 4, cloneIDs = { 15, 16, 17, 18 } },
            { npcID = 236073, enemyIdx = 2, forces = 3, amount = 2, cloneIDs = { 5, 6 } },
            { npcID = 236084, enemyIdx = 3, forces = 7, amount = 2, cloneIDs = { 8, 9 } },
            { npcID = 236071, enemyIdx = 4, forces = 25, amount = 1, cloneIDs = { 4 } },
            { npcID = 236082, enemyIdx = 6, forces = 6, amount = 1, cloneIDs = { 5 } },
            { npcID = 255604, enemyIdx = 39, forces = 6, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 3, count = 49, mobs = {
            { npcID = 236085, enemyIdx = 1, forces = 1, amount = 5, cloneIDs = { 10, 11, 12, 13, 14 } },
            { npcID = 236073, enemyIdx = 2, forces = 3, amount = 4, cloneIDs = { 9, 10, 11, 12 } },
            { npcID = 236084, enemyIdx = 3, forces = 7, amount = 2, cloneIDs = { 6, 7 } },
            { npcID = 236902, enemyIdx = 7, forces = 12, amount = 1, cloneIDs = { 1 } },
            { npcID = 236091, enemyIdx = 8, forces = 3, amount = 2, cloneIDs = { 4, 5 } },
            { npcID = 253324, enemyIdx = 37, forces = 0, amount = 2, cloneIDs = { 1, 2 } },
        } },
        { id = 4, count = 12, mobs = {
            { npcID = 236073, enemyIdx = 2, forces = 3, amount = 2, cloneIDs = { 7, 8 } },
            { npcID = 236091, enemyIdx = 8, forces = 3, amount = 2, cloneIDs = { 1, 2 } },
            { npcID = 234648, enemyIdx = 21, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 234660, enemyIdx = 23, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 255050, enemyIdx = 38, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 5, count = 26, mobs = {
            { npcID = 236893, enemyIdx = 9, forces = 2, amount = 6, cloneIDs = { 1, 2, 3, 4, 5, 6 } },
            { npcID = 236897, enemyIdx = 10, forces = 7, amount = 2, cloneIDs = { 1, 2 } },
            { npcID = 234649, enemyIdx = 22, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 234852, enemyIdx = 26, forces = 0, amount = 5, cloneIDs = { 1, 2, 3, 4, 5 } },
            { npcID = 234860, enemyIdx = 27, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 6, count = 66, mobs = {
            { npcID = 234849, enemyIdx = 11, forces = 2, amount = 1, cloneIDs = { 57 } },
            { npcID = 235261, enemyIdx = 12, forces = 5, amount = 4, cloneIDs = { 9, 10, 11, 12 } },
            { npcID = 235268, enemyIdx = 13, forces = 7, amount = 2, cloneIDs = { 5, 6 } },
            { npcID = 235267, enemyIdx = 14, forces = 5, amount = 1, cloneIDs = { 7 } },
            { npcID = 235465, enemyIdx = 17, forces = 25, amount = 1, cloneIDs = { 6 } },
        } },
        { id = 7, count = 47, mobs = {
            { npcID = 235267, enemyIdx = 14, forces = 5, amount = 2, cloneIDs = { 10, 11 } },
            { npcID = 235265, enemyIdx = 15, forces = 25, amount = 1, cloneIDs = { 1 } },
            { npcID = 235257, enemyIdx = 16, forces = 1, amount = 12, cloneIDs = { 1, 2, 4, 5, 6, 7, 8, 9, 18, 19, 20, 21 } },
        } },
        { id = 8, count = 57, mobs = {
            { npcID = 235261, enemyIdx = 12, forces = 5, amount = 2, cloneIDs = { 13, 14 } },
            { npcID = 235268, enemyIdx = 13, forces = 7, amount = 2, cloneIDs = { 10, 12 } },
            { npcID = 235257, enemyIdx = 16, forces = 1, amount = 8, cloneIDs = { 10, 11, 12, 13, 14, 15, 16, 17 } },
            { npcID = 235465, enemyIdx = 17, forces = 25, amount = 1, cloneIDs = { 7 } },
        } },
        { id = 9, count = 0, mobs = {
            { npcID = 234647, enemyIdx = 20, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 235520, enemyIdx = 29, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 10, count = 94, mobs = {
            { npcID = 234849, enemyIdx = 11, forces = 2, amount = 11, cloneIDs = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 } },
            { npcID = 235261, enemyIdx = 12, forces = 5, amount = 2, cloneIDs = { 1, 3 } },
            { npcID = 235268, enemyIdx = 13, forces = 7, amount = 1, cloneIDs = { 1 } },
            { npcID = 235267, enemyIdx = 14, forces = 5, amount = 4, cloneIDs = { 1, 2, 3, 4 } },
            { npcID = 235322, enemyIdx = 19, forces = 35, amount = 1, cloneIDs = { 4 } },
        } },
        { id = 11, count = 101, mobs = {
            { npcID = 234849, enemyIdx = 11, forces = 2, amount = 18, cloneIDs = { 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30 } },
            { npcID = 235261, enemyIdx = 12, forces = 5, amount = 3, cloneIDs = { 4, 5, 6 } },
            { npcID = 235265, enemyIdx = 15, forces = 25, amount = 1, cloneIDs = { 5 } },
            { npcID = 235465, enemyIdx = 17, forces = 25, amount = 1, cloneIDs = { 5 } },
        } },
        { id = 12, count = 59, mobs = {
            { npcID = 235261, enemyIdx = 12, forces = 5, amount = 2, cloneIDs = { 7, 8 } },
            { npcID = 235268, enemyIdx = 13, forces = 7, amount = 2, cloneIDs = { 2, 3 } },
            { npcID = 235322, enemyIdx = 19, forces = 35, amount = 1, cloneIDs = { 7 } },
        } },
        { id = 13, count = 0, mobs = {
            { npcID = 234763, enemyIdx = 24, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 234799, enemyIdx = 25, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 237626, enemyIdx = 33, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 238414, enemyIdx = 34, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
    },
})
