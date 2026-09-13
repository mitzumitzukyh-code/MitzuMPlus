-- =========================================================================
-- MitzuMPlus - Ruta nativa empaquetada: Voidscar Arena (dungeonKey 585)
--
-- GENERADO. No editar a mano.
--   generador: notas/_tools/export_native_routes.py
--   formato:   MitzuRoute v1 (modules/RouteSchema.lua)
--
-- Procedencia de los datos: ruta 'elitzur_voidscar_1' de Mythic Dungeon Tools,
-- normalizada por RouteSchema.FromLegacyProfile. MDT NO hace falta en
-- ejecucion: estos datos ya viajan dentro del addon.
-- Ver DATA_SOURCES.md para atribucion y licencia.
--
-- 11 pulls - 107 clones (102 validos, 5 sin resolver)
-- =========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus or not MitzuMPlus.NativeRouteDB then return end

MitzuMPlus.NativeRouteDB:Register({
    schemaVersion = 1,
    id            = "mitzu_585_standard",
    dungeonKey    = 585,
    name          = "Mitzu Standard",
    dungeonName   = "Voidscar Arena",
    totalForces   = 738,
    mdtDungeonIdx = 163,
    source = {
        type            = "MITZU_NATIVE",
        dataOrigin      = "MDT-API",
        originalRouteID = "elitzur_voidscar_1",
    },
    legacyIDs = { "elitzur_voidscar_1" },
    pulls = {
        { id = 1, count = 73, mobs = {
            { npcID = 243996, enemyIdx = 1, forces = 4, amount = 3, cloneIDs = { 12, 13, 14 } },
            { npcID = 243988, enemyIdx = 2, forces = 4, amount = 2, cloneIDs = { 12, 13 } },
            { npcID = 238883, enemyIdx = 5, forces = 7, amount = 3, cloneIDs = { 14, 15, 16 } },
            { npcID = 241496, enemyIdx = 6, forces = 7, amount = 1, cloneIDs = { 13 } },
            { npcID = 252053, enemyIdx = 8, forces = 25, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 2, count = 40, mobs = {
            { npcID = 267545, enemyIdx = 9, forces = 40, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 3, count = 158, mobs = {
            { npcID = 243996, enemyIdx = 1, forces = 4, amount = 5, cloneIDs = { 1, 2, 3, 4, 5 } },
            { npcID = 243988, enemyIdx = 2, forces = 4, amount = 5, cloneIDs = { 1, 2, 3, 4, 5 } },
            { npcID = 243983, enemyIdx = 3, forces = 4, amount = 5, cloneIDs = { 1, 2, 3, 4, 5 } },
            { npcID = 243985, enemyIdx = 4, forces = 5, amount = 5, cloneIDs = { 1, 2, 3, 4, 5 } },
            { npcID = 244260, enemyIdx = 11, forces = 25, amount = 1, cloneIDs = { 1 } },
            { npcID = 249608, enemyIdx = 12, forces = 5, amount = 1, cloneIDs = { 1 } },
            { npcID = 249603, enemyIdx = 13, forces = 5, amount = 1, cloneIDs = { 1 } },
            { npcID = 244309, enemyIdx = 14, forces = 25, amount = 1, cloneIDs = { 1 } },
            { npcID = 249461, enemyIdx = 15, forces = 5, amount = 1, cloneIDs = { 1 } },
            { npcID = 249590, enemyIdx = 16, forces = 8, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 4, count = 0, mobs = {
            { npcID = 238887, enemyIdx = 25, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 254677, enemyIdx = 30, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 5, count = 84, mobs = {
            { npcID = 241496, enemyIdx = 6, forces = 7, amount = 1, cloneIDs = { 4 } },
            { npcID = 243835, enemyIdx = 17, forces = 5, amount = 1, cloneIDs = { 1 } },
            { npcID = 243766, enemyIdx = 18, forces = 7, amount = 1, cloneIDs = { 1 } },
            { npcID = 245950, enemyIdx = 21, forces = 65, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 6, count = 104, mobs = {
            { npcID = 238883, enemyIdx = 5, forces = 7, amount = 1, cloneIDs = { 8 } },
            { npcID = 241496, enemyIdx = 6, forces = 7, amount = 1, cloneIDs = { 6 } },
            { npcID = 252053, enemyIdx = 8, forces = 25, amount = 1, cloneIDs = { 3 } },
            { npcID = 245950, enemyIdx = 21, forces = 65, amount = 1, cloneIDs = { 4 } },
        } },
        { id = 7, count = 0, mobs = {
            { npcID = 239008, enemyIdx = 26, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 239070, enemyIdx = 28, forces = 0, amount = 2, cloneIDs = { 1, 2 } },
        } },
        { id = 8, count = 95, mobs = {
            { npcID = 243996, enemyIdx = 1, forces = 4, amount = 2, cloneIDs = { 9, 10 } },
            { npcID = 243988, enemyIdx = 2, forces = 4, amount = 2, cloneIDs = { 9, 10 } },
            { npcID = 243983, enemyIdx = 3, forces = 4, amount = 2, cloneIDs = { 7, 8 } },
            { npcID = 243835, enemyIdx = 17, forces = 5, amount = 2, cloneIDs = { 16, 17 } },
            { npcID = 243766, enemyIdx = 18, forces = 7, amount = 1, cloneIDs = { 15 } },
            { npcID = 268184, enemyIdx = 22, forces = 30, amount = 1, cloneIDs = { 3 } },
            { npcID = 252508, enemyIdx = 23, forces = 1, amount = 10, cloneIDs = { 51, 52, 53, 54, 55, 56, 57, 58, 59, 60 } },
            { npcID = 244708, enemyIdx = 24, forces = 7, amount = 2, cloneIDs = { 5, 6 } },
        } },
        { id = 9, count = 96, mobs = {
            { npcID = 243996, enemyIdx = 1, forces = 4, amount = 2, cloneIDs = { 7, 8 } },
            { npcID = 243988, enemyIdx = 2, forces = 4, amount = 1, cloneIDs = { 6 } },
            { npcID = 243983, enemyIdx = 3, forces = 4, amount = 1, cloneIDs = { 6 } },
            { npcID = 238883, enemyIdx = 5, forces = 7, amount = 1, cloneIDs = { 4 } },
            { npcID = 243835, enemyIdx = 17, forces = 5, amount = 3, cloneIDs = { 12, 13, 15 } },
            { npcID = 243766, enemyIdx = 18, forces = 7, amount = 2, cloneIDs = { 8, 14 } },
            { npcID = 268184, enemyIdx = 22, forces = 30, amount = 1, cloneIDs = { 1 } },
            { npcID = 244708, enemyIdx = 24, forces = 7, amount = 2, cloneIDs = { 1, 2 } },
        } },
        { id = 10, count = 88, mobs = {
            { npcID = 241496, enemyIdx = 6, forces = 7, amount = 2, cloneIDs = { 9, 10 } },
            { npcID = 243835, enemyIdx = 17, forces = 5, amount = 4, cloneIDs = { 6, 7, 18, 19 } },
            { npcID = 268184, enemyIdx = 22, forces = 30, amount = 1, cloneIDs = { 2 } },
            { npcID = 252508, enemyIdx = 23, forces = 1, amount = 10, cloneIDs = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 } },
            { npcID = 244708, enemyIdx = 24, forces = 7, amount = 2, cloneIDs = { 3, 4 } },
        } },
        { id = 11, count = 0, mobs = {
            { npcID = 239167, enemyIdx = 27, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 255000, enemyIdx = 31, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 255001, enemyIdx = 32, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
    },
})
