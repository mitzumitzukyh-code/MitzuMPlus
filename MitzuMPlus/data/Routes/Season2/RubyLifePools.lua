-- =========================================================================
-- MitzuMPlus - Ruta nativa empaquetada: Ruby Life Pools (dungeonKey 399)
--
-- GENERADO. No editar a mano.
--   generador: notas/_tools/export_native_routes.py
--   formato:   MitzuRoute v1 (modules/RouteSchema.lua)
--
-- Procedencia de los datos: ruta 'elitzur_rlp_1' de Mythic Dungeon Tools,
-- normalizada por RouteSchema.FromLegacyProfile. MDT NO hace falta en
-- ejecucion: estos datos ya viajan dentro del addon.
-- Ver DATA_SOURCES.md para atribucion y licencia.
--
-- 11 pulls - 86 clones (77 validos, 9 sin resolver)
-- =========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus or not MitzuMPlus.NativeRouteDB then return end

MitzuMPlus.NativeRouteDB:Register({
    schemaVersion = 1,
    id            = "mitzu_399_standard",
    dungeonKey    = 399,
    name          = "Mitzu Standard",
    dungeonName   = "Ruby Life Pools",
    totalForces   = 551,
    mdtDungeonIdx = 42,
    source = {
        type            = "MITZU_NATIVE",
        dataOrigin      = "MDT-API",
        originalRouteID = "elitzur_rlp_1",
    },
    legacyIDs = { "elitzur_rlp_1" },
    pulls = {
        { id = 1, count = 89, mobs = {
            { npcID = 188244, enemyIdx = 1, forces = 25, amount = 1, cloneIDs = { 1 } },
            { npcID = 187969, enemyIdx = 2, forces = 5, amount = 5, cloneIDs = { 1, 2, 3, 4, 9 } },
            { npcID = 188011, enemyIdx = 3, forces = 5, amount = 5, cloneIDs = { 1, 4, 5, 6, 8 } },
            { npcID = 188067, enemyIdx = 4, forces = 7, amount = 2, cloneIDs = { 1, 3 } },
        } },
        { id = 2, count = 96, mobs = {
            { npcID = 188244, enemyIdx = 1, forces = 25, amount = 1, cloneIDs = { 2 } },
            { npcID = 187969, enemyIdx = 2, forces = 5, amount = 3, cloneIDs = { 6, 7, 8 } },
            { npcID = 188011, enemyIdx = 3, forces = 5, amount = 1, cloneIDs = { 9 } },
            { npcID = 188067, enemyIdx = 4, forces = 7, amount = 3, cloneIDs = { 6, 8, 9 } },
            { npcID = 187894, enemyIdx = 5, forces = 0, amount = 3, cloneIDs = { 48, 49, 50 } },
            { npcID = 187897, enemyIdx = 6, forces = 30, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 3, count = 0, mobs = {
            { npcID = 188252, enemyIdx = 7, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 4, count = 53, mobs = {
            { npcID = 190207, enemyIdx = 10, forces = 7, amount = 2, cloneIDs = { 3, 6 } },
            { npcID = 190034, enemyIdx = 11, forces = 25, amount = 1, cloneIDs = { 1 } },
            { npcID = 190206, enemyIdx = 12, forces = 7, amount = 2, cloneIDs = { 1, 2 } },
        } },
        { id = 5, count = 63, mobs = {
            { npcID = 190207, enemyIdx = 10, forces = 7, amount = 2, cloneIDs = { 4, 5 } },
            { npcID = 190034, enemyIdx = 11, forces = 25, amount = 1, cloneIDs = { 2 } },
            { npcID = 190206, enemyIdx = 12, forces = 7, amount = 2, cloneIDs = { 3, 10 } },
            { npcID = 195119, enemyIdx = 13, forces = 10, amount = 1, cloneIDs = { 2 } },
        } },
        { id = 6, count = 53, mobs = {
            { npcID = 190207, enemyIdx = 10, forces = 7, amount = 2, cloneIDs = { 1, 2 } },
            { npcID = 190034, enemyIdx = 11, forces = 25, amount = 1, cloneIDs = { 3 } },
            { npcID = 190206, enemyIdx = 12, forces = 7, amount = 2, cloneIDs = { 4, 8 } },
        } },
        { id = 7, count = 53, mobs = {
            { npcID = 190207, enemyIdx = 10, forces = 7, amount = 2, cloneIDs = { 7, 10 } },
            { npcID = 190034, enemyIdx = 11, forces = 25, amount = 1, cloneIDs = { 4 } },
            { npcID = 190206, enemyIdx = 12, forces = 7, amount = 2, cloneIDs = { 6, 9 } },
        } },
        { id = 8, count = 0, mobs = {
            { npcID = 189232, enemyIdx = 15, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 9, count = 99, mobs = {
            { npcID = 190207, enemyIdx = 10, forces = 7, amount = 1, cloneIDs = { 9 } },
            { npcID = 190206, enemyIdx = 12, forces = 7, amount = 1, cloneIDs = { 7 } },
            { npcID = 197982, enemyIdx = 16, forces = 5, amount = 7, cloneIDs = { 1, 2, 3, 4, 5, 9, 10 } },
            { npcID = 197509, enemyIdx = 17, forces = 0, amount = 7, cloneIDs = { 1, 2, 3, 4, 5, 6, 22 } },
            { npcID = 198047, enemyIdx = 18, forces = 25, amount = 2, cloneIDs = { 1, 2 } },
        } },
        { id = 10, count = 40, mobs = {
            { npcID = 197982, enemyIdx = 16, forces = 5, amount = 2, cloneIDs = { 7, 8 } },
            { npcID = 197509, enemyIdx = 17, forces = 0, amount = 8, cloneIDs = { 7, 8, 9, 10, 11, 12, 13, 21 } },
            { npcID = 197535, enemyIdx = 19, forces = 30, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 11, count = 0, mobs = {
            { npcID = 197509, enemyIdx = 17, forces = 0, amount = 7, cloneIDs = { 14, 15, 16, 18, 19, 20, 23 } },
            { npcID = 190485, enemyIdx = 20, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 190484, enemyIdx = 21, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
    },
})
