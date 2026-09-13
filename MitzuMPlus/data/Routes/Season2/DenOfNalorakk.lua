-- =========================================================================
-- MitzuMPlus - Ruta nativa empaquetada: Den of Nalorakk (dungeonKey 586)
--
-- GENERADO. No editar a mano.
--   generador: notas/_tools/export_native_routes.py
--   formato:   MitzuRoute v1 (modules/RouteSchema.lua)
--
-- Procedencia de los datos: ruta 'Tactyks PUG Friendly' de Mythic Dungeon Tools,
-- normalizada por RouteSchema.FromLegacyProfile. MDT NO hace falta en
-- ejecucion: estos datos ya viajan dentro del addon.
-- Ver DATA_SOURCES.md para atribucion y licencia.
--
-- 17 pulls - 103 clones (99 validos, 4 sin resolver)
-- =========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus or not MitzuMPlus.NativeRouteDB then return end

MitzuMPlus.NativeRouteDB:Register({
    schemaVersion = 1,
    id            = "mitzu_586_standard",
    dungeonKey    = 586,
    name          = "Mitzu Standard",
    dungeonName   = "Den of Nalorakk",
    totalForces   = 729,
    mdtDungeonIdx = 161,
    source = {
        type            = "MITZU_NATIVE",
        dataOrigin      = "MDT-API",
        originalRouteID = "Tactyks PUG Friendly",
    },
    legacyIDs = { "Tactyks PUG Friendly" },
    pulls = {
        { id = 1, count = 59, mobs = {
            { npcID = 245855, enemyIdx = 1, forces = 25, amount = 1, cloneIDs = { 3 } },
            { npcID = 241814, enemyIdx = 2, forces = 7, amount = 1, cloneIDs = { 3 } },
            { npcID = 241813, enemyIdx = 3, forces = 5, amount = 4, cloneIDs = { 3, 4, 5, 6 } },
            { npcID = 241816, enemyIdx = 17, forces = 7, amount = 1, cloneIDs = { 2 } },
            { npcID = 245567, enemyIdx = 24, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 2, count = 28, mobs = {
            { npcID = 241814, enemyIdx = 2, forces = 7, amount = 1, cloneIDs = { 8 } },
            { npcID = 241813, enemyIdx = 3, forces = 5, amount = 1, cloneIDs = { 15 } },
            { npcID = 241808, enemyIdx = 4, forces = 8, amount = 2, cloneIDs = { 4, 7 } },
            { npcID = 241809, enemyIdx = 15, forces = 0, amount = 4, cloneIDs = { 10, 11, 16, 17 } },
        } },
        { id = 3, count = 0, mobs = {
        } },
        { id = 4, count = 63, mobs = {
            { npcID = 241814, enemyIdx = 2, forces = 7, amount = 2, cloneIDs = { 5, 6 } },
            { npcID = 241813, enemyIdx = 3, forces = 5, amount = 4, cloneIDs = { 7, 8, 9, 10 } },
            { npcID = 241808, enemyIdx = 4, forces = 8, amount = 1, cloneIDs = { 8 } },
            { npcID = 241809, enemyIdx = 15, forces = 0, amount = 2, cloneIDs = { 18, 19 } },
            { npcID = 241816, enemyIdx = 17, forces = 7, amount = 3, cloneIDs = { 8, 9, 10 } },
        } },
        { id = 5, count = 0, mobs = {
            { npcID = 241812, enemyIdx = 16, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 6, count = 92, mobs = {
            { npcID = 241814, enemyIdx = 2, forces = 7, amount = 5, cloneIDs = { 10, 11, 12, 13, 14 } },
            { npcID = 241813, enemyIdx = 3, forces = 5, amount = 7, cloneIDs = { 17, 18, 19, 20, 21, 22, 23 } },
            { npcID = 241808, enemyIdx = 4, forces = 8, amount = 1, cloneIDs = { 11 } },
            { npcID = 241816, enemyIdx = 17, forces = 7, amount = 2, cloneIDs = { 11, 12 } },
        } },
        { id = 7, count = 36, mobs = {
            { npcID = 241808, enemyIdx = 4, forces = 8, amount = 2, cloneIDs = { 14, 15 } },
            { npcID = 241874, enemyIdx = 6, forces = 5, amount = 4, cloneIDs = { 1, 2, 17, 18 } },
        } },
        { id = 8, count = 82, mobs = {
            { npcID = 241874, enemyIdx = 6, forces = 5, amount = 3, cloneIDs = { 3, 4, 5 } },
            { npcID = 241911, enemyIdx = 7, forces = 7, amount = 3, cloneIDs = { 3, 6, 7 } },
            { npcID = 241872, enemyIdx = 8, forces = 9, amount = 2, cloneIDs = { 3, 4 } },
            { npcID = 241869, enemyIdx = 10, forces = 28, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 9, count = 47, mobs = {
            { npcID = 241874, enemyIdx = 6, forces = 5, amount = 3, cloneIDs = { 6, 7, 8 } },
            { npcID = 241872, enemyIdx = 8, forces = 9, amount = 2, cloneIDs = { 5, 6 } },
            { npcID = 241876, enemyIdx = 9, forces = 7, amount = 2, cloneIDs = { 4, 5 } },
        } },
        { id = 10, count = 102, mobs = {
            { npcID = 250478, enemyIdx = 5, forces = 50, amount = 1, cloneIDs = { 1 } },
            { npcID = 241874, enemyIdx = 6, forces = 5, amount = 2, cloneIDs = { 12, 13 } },
            { npcID = 241911, enemyIdx = 7, forces = 7, amount = 1, cloneIDs = { 5 } },
            { npcID = 241876, enemyIdx = 9, forces = 7, amount = 1, cloneIDs = { 7 } },
            { npcID = 241869, enemyIdx = 10, forces = 28, amount = 1, cloneIDs = { 2 } },
        } },
        { id = 11, count = 0, mobs = {
            { npcID = 244100, enemyIdx = 18, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 244696, enemyIdx = 19, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 244759, enemyIdx = 20, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 12, count = 44, mobs = {
            { npcID = 245143, enemyIdx = 11, forces = 5, amount = 1, cloneIDs = { 1 } },
            { npcID = 245139, enemyIdx = 12, forces = 7, amount = 2, cloneIDs = { 1, 2 } },
            { npcID = 245146, enemyIdx = 13, forces = 25, amount = 1, cloneIDs = { 1 } },
            { npcID = 245148, enemyIdx = 22, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 13, count = 50, mobs = {
            { npcID = 245143, enemyIdx = 11, forces = 5, amount = 2, cloneIDs = { 2, 3 } },
            { npcID = 245139, enemyIdx = 12, forces = 7, amount = 1, cloneIDs = { 3 } },
            { npcID = 245145, enemyIdx = 14, forces = 6, amount = 3, cloneIDs = { 1, 2, 3 } },
            { npcID = 245190, enemyIdx = 23, forces = 5, amount = 3, cloneIDs = { 1, 2, 3 } },
        } },
        { id = 14, count = 28, mobs = {
            { npcID = 245143, enemyIdx = 11, forces = 5, amount = 2, cloneIDs = { 4, 5 } },
            { npcID = 245139, enemyIdx = 12, forces = 7, amount = 1, cloneIDs = { 4 } },
            { npcID = 245145, enemyIdx = 14, forces = 6, amount = 1, cloneIDs = { 4 } },
            { npcID = 245190, enemyIdx = 23, forces = 5, amount = 1, cloneIDs = { 4 } },
        } },
        { id = 15, count = 57, mobs = {
            { npcID = 245139, enemyIdx = 12, forces = 7, amount = 1, cloneIDs = { 5 } },
            { npcID = 245146, enemyIdx = 13, forces = 25, amount = 2, cloneIDs = { 2, 3 } },
            { npcID = 245148, enemyIdx = 22, forces = 0, amount = 2, cloneIDs = { 2, 3 } },
        } },
        { id = 16, count = 35, mobs = {
            { npcID = 244889, enemyIdx = 21, forces = 35, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 17, count = 0, mobs = {
            { npcID = 246404, enemyIdx = 25, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 246409, enemyIdx = 26, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 247301, enemyIdx = 27, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
    },
})
