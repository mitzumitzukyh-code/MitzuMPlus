-- =========================================================================
-- MitzuMPlus - Ruta nativa empaquetada: The Blinding Vale (dungeonKey 584)
--
-- GENERADO. No editar a mano.
--   generador: notas/_tools/export_native_routes.py
--   formato:   MitzuRoute v1 (modules/RouteSchema.lua)
--
-- Procedencia de los datos: ruta 'Peon BV' de Mythic Dungeon Tools,
-- normalizada por RouteSchema.FromLegacyProfile. MDT NO hace falta en
-- ejecucion: estos datos ya viajan dentro del addon.
-- Ver DATA_SOURCES.md para atribucion y licencia.
--
-- 14 pulls - 130 clones (124 validos, 6 sin resolver)
-- =========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus or not MitzuMPlus.NativeRouteDB then return end

MitzuMPlus.NativeRouteDB:Register({
    schemaVersion = 1,
    id            = "mitzu_584_standard",
    dungeonKey    = 584,
    name          = "Mitzu Standard",
    dungeonName   = "The Blinding Vale",
    totalForces   = 686,
    mdtDungeonIdx = 162,
    source = {
        type            = "MITZU_NATIVE",
        dataOrigin      = "MDT-API",
        originalRouteID = "Peon BV",
    },
    legacyIDs = { "Peon BV" },
    pulls = {
        { id = 1, count = 104, mobs = {
            { npcID = 245345, enemyIdx = 1, forces = 7, amount = 5, cloneIDs = { 11, 12, 13, 22, 23 } },
            { npcID = 245410, enemyIdx = 2, forces = 1, amount = 17, cloneIDs = { 27, 28, 29, 30, 31, 32, 33, 34, 73, 74, 75, 76, 77, 78, 79, 80, 81 } },
            { npcID = 245339, enemyIdx = 3, forces = 6, amount = 3, cloneIDs = { 3, 4, 8 } },
            { npcID = 245346, enemyIdx = 4, forces = 20, amount = 1, cloneIDs = { 2 } },
            { npcID = 245336, enemyIdx = 6, forces = 7, amount = 2, cloneIDs = { 4, 11 } },
        } },
        { id = 2, count = 65, mobs = {
            { npcID = 245345, enemyIdx = 1, forces = 7, amount = 2, cloneIDs = { 18, 19 } },
            { npcID = 245410, enemyIdx = 2, forces = 1, amount = 7, cloneIDs = { 50, 51, 85, 86, 87, 88, 89 } },
            { npcID = 245339, enemyIdx = 3, forces = 6, amount = 2, cloneIDs = { 9, 10 } },
            { npcID = 254850, enemyIdx = 5, forces = 25, amount = 1, cloneIDs = { 9 } },
            { npcID = 245336, enemyIdx = 6, forces = 7, amount = 1, cloneIDs = { 7 } },
        } },
        { id = 3, count = 69, mobs = {
            { npcID = 245345, enemyIdx = 1, forces = 7, amount = 1, cloneIDs = { 17 } },
            { npcID = 245410, enemyIdx = 2, forces = 1, amount = 11, cloneIDs = { 44, 45, 46, 47, 48, 49, 52, 53, 54, 55, 56 } },
            { npcID = 245339, enemyIdx = 3, forces = 6, amount = 2, cloneIDs = { 5, 6 } },
            { npcID = 254850, enemyIdx = 5, forces = 25, amount = 1, cloneIDs = { 7 } },
            { npcID = 245336, enemyIdx = 6, forces = 7, amount = 2, cloneIDs = { 9, 15 } },
        } },
        { id = 4, count = 57, mobs = {
            { npcID = 245345, enemyIdx = 1, forces = 7, amount = 3, cloneIDs = { 14, 15, 16 } },
            { npcID = 245410, enemyIdx = 2, forces = 1, amount = 9, cloneIDs = { 35, 36, 37, 38, 39, 40, 41, 42, 43 } },
            { npcID = 245346, enemyIdx = 4, forces = 20, amount = 1, cloneIDs = { 3 } },
            { npcID = 245336, enemyIdx = 6, forces = 7, amount = 1, cloneIDs = { 5 } },
        } },
        { id = 5, count = 0, mobs = {
            { npcID = 243028, enemyIdx = 13, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 243029, enemyIdx = 14, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 243030, enemyIdx = 15, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 6, count = 81, mobs = {
            { npcID = 245345, enemyIdx = 1, forces = 7, amount = 1, cloneIDs = { 25 } },
            { npcID = 245410, enemyIdx = 2, forces = 1, amount = 5, cloneIDs = { 90, 91, 92, 93, 94 } },
            { npcID = 245339, enemyIdx = 3, forces = 6, amount = 2, cloneIDs = { 11, 12 } },
            { npcID = 245346, enemyIdx = 4, forces = 20, amount = 1, cloneIDs = { 5 } },
            { npcID = 254850, enemyIdx = 5, forces = 25, amount = 1, cloneIDs = { 10 } },
            { npcID = 245484, enemyIdx = 7, forces = 7, amount = 1, cloneIDs = { 16 } },
            { npcID = 245473, enemyIdx = 8, forces = 5, amount = 1, cloneIDs = { 9 } },
        } },
        { id = 7, count = 0, mobs = {
            { npcID = 244887, enemyIdx = 18, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 8, count = 46, mobs = {
            { npcID = 245484, enemyIdx = 7, forces = 7, amount = 1, cloneIDs = { 17 } },
            { npcID = 245473, enemyIdx = 8, forces = 5, amount = 1, cloneIDs = { 10 } },
            { npcID = 245527, enemyIdx = 9, forces = 1, amount = 5, cloneIDs = { 18, 19, 20, 21, 22 } },
            { npcID = 245460, enemyIdx = 10, forces = 7, amount = 1, cloneIDs = { 9 } },
            { npcID = 246871, enemyIdx = 12, forces = 22, amount = 1, cloneIDs = { 4 } },
        } },
        { id = 9, count = 86, mobs = {
            { npcID = 254850, enemyIdx = 5, forces = 25, amount = 1, cloneIDs = { 11 } },
            { npcID = 245473, enemyIdx = 8, forces = 5, amount = 3, cloneIDs = { 11, 12, 13 } },
            { npcID = 245527, enemyIdx = 9, forces = 1, amount = 10, cloneIDs = { 30, 31, 32, 33, 34, 35, 36, 37, 38, 39 } },
            { npcID = 245460, enemyIdx = 10, forces = 7, amount = 2, cloneIDs = { 10, 11 } },
            { npcID = 246871, enemyIdx = 12, forces = 22, amount = 1, cloneIDs = { 5 } },
        } },
        { id = 10, count = 0, mobs = {
            { npcID = 245912, enemyIdx = 16, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 246367, enemyIdx = 20, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 246371, enemyIdx = 21, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 11, count = 60, mobs = {
            { npcID = 249756, enemyIdx = 23, forces = 60, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 12, count = 68, mobs = {
            { npcID = 254850, enemyIdx = 5, forces = 25, amount = 1, cloneIDs = { 3 } },
            { npcID = 245484, enemyIdx = 7, forces = 7, amount = 3, cloneIDs = { 2, 3, 4 } },
            { npcID = 246871, enemyIdx = 12, forces = 22, amount = 1, cloneIDs = { 2 } },
        } },
        { id = 13, count = 46, mobs = {
            { npcID = 245339, enemyIdx = 3, forces = 6, amount = 2, cloneIDs = { 15, 16 } },
            { npcID = 245346, enemyIdx = 4, forces = 20, amount = 1, cloneIDs = { 7 } },
            { npcID = 245336, enemyIdx = 6, forces = 7, amount = 2, cloneIDs = { 13, 14 } },
        } },
        { id = 14, count = 0, mobs = {
            { npcID = 247755, enemyIdx = 22, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 253571, enemyIdx = 26, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
    },
})
