-- =========================================================================
-- MitzuMPlus - Ruta nativa empaquetada: Altar of Fangs (dungeonKey 588)
--
-- GENERADO. No editar a mano.
--   generador: notas/_tools/export_native_routes.py
--   formato:   MitzuRoute v1 (modules/RouteSchema.lua)
--
-- Procedencia de los datos: ruta 'elitzur_altar_1' de Mythic Dungeon Tools,
-- normalizada por RouteSchema.FromLegacyProfile. MDT NO hace falta en
-- ejecucion: estos datos ya viajan dentro del addon.
-- Ver DATA_SOURCES.md para atribucion y licencia.
--
-- 12 pulls - 111 clones (103 validos, 8 sin resolver)
-- =========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus or not MitzuMPlus.NativeRouteDB then return end

MitzuMPlus.NativeRouteDB:Register({
    schemaVersion = 1,
    id            = "mitzu_588_standard",
    dungeonKey    = 588,
    name          = "Mitzu Standard",
    dungeonName   = "Altar of Fangs",
    totalForces   = 817,
    mdtDungeonIdx = 164,
    source = {
        type            = "MITZU_NATIVE",
        dataOrigin      = "MDT-API",
        originalRouteID = "elitzur_altar_1",
    },
    legacyIDs = { "elitzur_altar_1" },
    pulls = {
        { id = 1, count = 143, mobs = {
            { npcID = 270306, enemyIdx = 1, forces = 25, amount = 1, cloneIDs = { 1 } },
            { npcID = 261560, enemyIdx = 6, forces = 7, amount = 5, cloneIDs = { 1, 2, 5, 6, 8 } },
            { npcID = 261553, enemyIdx = 7, forces = 5, amount = 11, cloneIDs = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13 } },
            { npcID = 261554, enemyIdx = 10, forces = 25, amount = 1, cloneIDs = { 1 } },
            { npcID = 261550, enemyIdx = 11, forces = 1, amount = 3, cloneIDs = { 16, 17, 18 } },
        } },
        { id = 2, count = 64, mobs = {
            { npcID = 270306, enemyIdx = 1, forces = 25, amount = 1, cloneIDs = { 2 } },
            { npcID = 261560, enemyIdx = 6, forces = 7, amount = 3, cloneIDs = { 3, 4, 9 } },
            { npcID = 261553, enemyIdx = 7, forces = 5, amount = 2, cloneIDs = { 11, 21 } },
            { npcID = 261550, enemyIdx = 11, forces = 1, amount = 8, cloneIDs = { 11, 12, 13, 14, 15, 19, 20, 21 } },
        } },
        { id = 3, count = 59, mobs = {
            { npcID = 270306, enemyIdx = 1, forces = 25, amount = 1, cloneIDs = { 3 } },
            { npcID = 261560, enemyIdx = 6, forces = 7, amount = 2, cloneIDs = { 11, 12 } },
            { npcID = 261553, enemyIdx = 7, forces = 5, amount = 4, cloneIDs = { 14, 15, 17, 18 } },
        } },
        { id = 4, count = 99, mobs = {
            { npcID = 270306, enemyIdx = 1, forces = 25, amount = 1, cloneIDs = { 4 } },
            { npcID = 261560, enemyIdx = 6, forces = 7, amount = 2, cloneIDs = { 13, 14 } },
            { npcID = 261553, enemyIdx = 7, forces = 5, amount = 2, cloneIDs = { 19, 20 } },
            { npcID = 261554, enemyIdx = 10, forces = 25, amount = 2, cloneIDs = { 2, 3 } },
        } },
        { id = 5, count = 0, mobs = {
            { npcID = 259445, enemyIdx = 14, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 6, count = 69, mobs = {
            { npcID = 261552, enemyIdx = 2, forces = 5, amount = 6, cloneIDs = { 1, 2, 3, 14, 15, 16 } },
            { npcID = 261557, enemyIdx = 3, forces = 7, amount = 2, cloneIDs = { 1, 3 } },
            { npcID = 262011, enemyIdx = 12, forces = 25, amount = 1, cloneIDs = { 1 } },
        } },
        { id = 7, count = 52, mobs = {
            { npcID = 261552, enemyIdx = 2, forces = 5, amount = 4, cloneIDs = { 4, 5, 6, 7 } },
            { npcID = 261557, enemyIdx = 3, forces = 7, amount = 1, cloneIDs = { 4 } },
            { npcID = 262011, enemyIdx = 12, forces = 25, amount = 1, cloneIDs = { 2 } },
        } },
        { id = 8, count = 54, mobs = {
            { npcID = 261552, enemyIdx = 2, forces = 5, amount = 3, cloneIDs = { 11, 12, 13 } },
            { npcID = 261557, enemyIdx = 3, forces = 7, amount = 2, cloneIDs = { 10, 11 } },
            { npcID = 262011, enemyIdx = 12, forces = 25, amount = 1, cloneIDs = { 3 } },
            { npcID = 259446, enemyIdx = 15, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 262398, enemyIdx = 17, forces = 0, amount = 2, cloneIDs = { 1, 2 } },
            { npcID = 270417, enemyIdx = 21, forces = 0, amount = 2, cloneIDs = { 1, 2 } },
        } },
        { id = 9, count = 83, mobs = {
            { npcID = 261557, enemyIdx = 3, forces = 7, amount = 4, cloneIDs = { 12, 13, 14, 15 } },
            { npcID = 261573, enemyIdx = 9, forces = 30, amount = 1, cloneIDs = { 1 } },
            { npcID = 271453, enemyIdx = 13, forces = 5, amount = 5, cloneIDs = { 1, 2, 3, 4, 5 } },
        } },
        { id = 10, count = 51, mobs = {
            { npcID = 263112, enemyIdx = 5, forces = 1, amount = 6, cloneIDs = { 13, 14, 15, 16, 17, 18 } },
            { npcID = 263109, enemyIdx = 8, forces = 25, amount = 1, cloneIDs = { 2 } },
            { npcID = 271453, enemyIdx = 13, forces = 5, amount = 4, cloneIDs = { 10, 11, 14, 15 } },
        } },
        { id = 11, count = 59, mobs = {
            { npcID = 261560, enemyIdx = 6, forces = 7, amount = 2, cloneIDs = { 15, 16 } },
            { npcID = 261554, enemyIdx = 10, forces = 25, amount = 1, cloneIDs = { 4 } },
            { npcID = 271453, enemyIdx = 13, forces = 5, amount = 4, cloneIDs = { 16, 17, 18, 19 } },
        } },
        { id = 12, count = 85, mobs = {
            { npcID = 270306, enemyIdx = 1, forces = 25, amount = 2, cloneIDs = { 5, 6 } },
            { npcID = 263109, enemyIdx = 8, forces = 25, amount = 1, cloneIDs = { 4 } },
            { npcID = 271453, enemyIdx = 13, forces = 5, amount = 2, cloneIDs = { 20, 21 } },
            { npcID = 259447, enemyIdx = 16, forces = 0, amount = 1, cloneIDs = { 1 } },
            { npcID = 268358, enemyIdx = 19, forces = 0, amount = 1, cloneIDs = { 1 } },
        } },
    },
})
