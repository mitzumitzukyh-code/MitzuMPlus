-- =========================================================================
-- MitzuMPlus - Ruta nativa empaquetada: Kings' Rest (dungeonKey 249)
--
-- GENERADO. No editar a mano.
--   generador: notas/_tools/export_native_routes.py
--   formato:   MitzuRoute v1 (modules/RouteSchema.lua)
--
-- Procedencia de los datos: ruta 'KR - Pug Friendly' de Mythic Dungeon Tools,
-- normalizada por RouteSchema.FromLegacyProfile. MDT NO hace falta en
-- ejecucion: estos datos ya viajan dentro del addon.
-- Ver DATA_SOURCES.md para atribucion y licencia.
--
-- 15 pulls - 96 clones (87 validos, 9 sin resolver)
-- =========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus or not MitzuMPlus.NativeRouteDB then return end

MitzuMPlus.NativeRouteDB:Register({
    schemaVersion = 1,
    id            = "mitzu_249_standard",
    dungeonKey    = 249,
    name          = "Mitzu Standard",
    dungeonName   = "Kings' Rest",
    totalForces   = 608,
    mdtDungeonIdx = 17,
    source = {
        type            = "MITZU_NATIVE",
        dataOrigin      = "MDT-API",
        originalRouteID = "KR - Pug Friendly",
    },
    legacyIDs = { "KR - Pug Friendly" },
    pulls = {
        { id = 1, count = 0, mobs = {
            { npcID = 133943, enemyIdx = 2, forces = 0, amount = 8, cloneIDs = { 1, 2, 3, 4, 5, 6, 7, 8 } },
        } },
        { id = 2, count = 79, mobs = {
            { npcID = 133935, enemyIdx = 1, forces = 22, amount = 2, cloneIDs = { 3, 4 } },
            { npcID = 134158, enemyIdx = 4, forces = 25, amount = 1, cloneIDs = { 1 } },
            { npcID = 134157, enemyIdx = 5, forces = 5, amount = 2, cloneIDs = { 7, 8 } },
        } },
        { id = 3, count = 65, mobs = {
            { npcID = 133943, enemyIdx = 2, forces = 0, amount = 5, cloneIDs = { 9, 10, 11, 12, 14 } },
            { npcID = 134174, enemyIdx = 3, forces = 20, amount = 1, cloneIDs = { 4 } },
            { npcID = 134158, enemyIdx = 4, forces = 25, amount = 1, cloneIDs = { 2 } },
            { npcID = 134157, enemyIdx = 5, forces = 5, amount = 4, cloneIDs = { 1, 4, 5, 6 } },
        } },
        { id = 4, count = 0, mobs = {
            { npcID = 135322, enemyIdx = 6, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 135406, enemyIdx = 38, forces = 0, amount = 5, cloneIDs = { 1, 2, 3, 4, 5 } },
        } },
        { id = 5, count = 183, mobs = {
            { npcID = 137487, enemyIdx = 7, forces = 10, amount = 1, cloneIDs = { 1 } },
            { npcID = 137486, enemyIdx = 8, forces = 25, amount = 1, cloneIDs = { 1 } },
            { npcID = 137484, enemyIdx = 9, forces = 25, amount = 1, cloneIDs = { 1 } },
            { npcID = 137485, enemyIdx = 10, forces = 7, amount = 4, cloneIDs = { 1, 2, 3, 4 } },
            { npcID = 134251, enemyIdx = 11, forces = 10, amount = 1, cloneIDs = { 1 } },
            { npcID = 137473, enemyIdx = 12, forces = 10, amount = 1, cloneIDs = { 1 } },
            { npcID = 134331, enemyIdx = 13, forces = 25, amount = 1, cloneIDs = { 1 } },
            { npcID = 137474, enemyIdx = 14, forces = 25, amount = 1, cloneIDs = { 1 } },
            { npcID = 137478, enemyIdx = 15, forces = 25, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 6, count = 25, mobs = {
            { npcID = 134739, enemyIdx = 16, forces = 25, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 7, count = 38, mobs = {
            { npcID = 137969, enemyIdx = 17, forces = 15, amount = 1, cloneIDs = { 1 } },
            { npcID = 137989, enemyIdx = 26, forces = 1, amount = 9, cloneIDs = { 1, 2, 3, 4, 5, 6, 7, 8, 9 } },
            { npcID = 270502, enemyIdx = 37, forces = 7, amount = 2, cloneIDs = { 1, 2 } },
        } },
        { id = 8, count = 37, mobs = {
            { npcID = 137969, enemyIdx = 17, forces = 15, amount = 1, cloneIDs = { 2 } },
            { npcID = 137989, enemyIdx = 26, forces = 1, amount = 8, cloneIDs = { 10, 11, 12, 13, 14, 15, 16, 17 } },
            { npcID = 270502, enemyIdx = 37, forces = 7, amount = 2, cloneIDs = { 3, 4 } },
        } },
        { id = 9, count = 0, mobs = {
            { npcID = 134993, enemyIdx = 18, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 136256, enemyIdx = 30, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 10, count = 72, mobs = {
            { npcID = 135204, enemyIdx = 19, forces = 7, amount = 2, cloneIDs = { 1, 2 } },
            { npcID = 135167, enemyIdx = 20, forces = 22, amount = 2, cloneIDs = { 2, 4 } },
            { npcID = 135239, enemyIdx = 21, forces = 7, amount = 2, cloneIDs = { 4, 5 } },
            { npcID = 137591, enemyIdx = 39, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 11, count = 56, mobs = {
            { npcID = 135204, enemyIdx = 19, forces = 7, amount = 1, cloneIDs = { 3 } },
            { npcID = 135239, enemyIdx = 21, forces = 7, amount = 2, cloneIDs = { 2, 6 } },
            { npcID = 135231, enemyIdx = 22, forces = 25, amount = 1, cloneIDs = { 1 } },
            { npcID = 135192, enemyIdx = 23, forces = 5, amount = 2, cloneIDs = { 5, 6 } },
            { npcID = 137591, enemyIdx = 39, forces = 0, amount = 1, cloneIDs = { 2 } },
        } },
        { id = 12, count = 32, mobs = {
            { npcID = 135167, enemyIdx = 20, forces = 22, amount = 1, cloneIDs = { 1 } },
            { npcID = 135192, enemyIdx = 23, forces = 5, amount = 2, cloneIDs = { 1, 2 } },
        } },
        { id = 13, count = 0, mobs = {
            { npcID = 135761, enemyIdx = 27, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 135764, enemyIdx = 28, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 135765, enemyIdx = 29, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 269808, enemyIdx = 34, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 269810, enemyIdx = 35, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 269811, enemyIdx = 36, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 14, count = 30, mobs = {
            { npcID = 138489, enemyIdx = 24, forces = 30, amount = 1, cloneIDs = { 1 } },
            { npcID = 138493, enemyIdx = 33, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 15, count = 0, mobs = {
            { npcID = 136160, enemyIdx = 25, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 136976, enemyIdx = 31, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 136984, enemyIdx = 32, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
    },
})
