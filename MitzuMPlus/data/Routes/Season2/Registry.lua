-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · NativeRouteDB — rutas que VIAJAN CON EL ADDON
--
-- LA DIFERENCIA QUE JUSTIFICA ESTE FICHERO
-- Hasta ahora las rutas salían de MPlusAdaptiveRouteDB, o sea de
-- SavedVariables: de una importación que el jugador hizo antes. Eso demostraba
-- "puedo seguir usando lo que ya importé sin MDT", que no es lo mismo que
-- "acabo de instalar Mitzu y ya sé las rutas".
--
-- Esto es lo segundo. Los ficheros de Season2/ son datos de fábrica: existen
-- en una instalación limpia, sin MDT, sin SavedVariables y sin importar nada.
--
-- SOLO LECTURA. Nadie debe escribir aquí en ejecución: lo que el jugador
-- importe o elija vive en SavedVariables, separado a propósito. Mezclar las
-- dos cosas es como se acaba con datos de fábrica corrompidos por una
-- importación a medias.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local NativeRouteDB = { _byID = {}, _byDungeon = {}, _count = 0 }
MitzuMPlus.NativeRouteDB = NativeRouteDB

-- Los ficheros de mazmorra llaman aquí al cargar. La validación completa NO se
-- hace en el arranque: son 907 clones entre las ocho y no hay motivo para
-- pagarlo en cada login. Aquí solo se comprueba la forma; el validador entero
-- vive en /emp testnative y en los bancos de pruebas.
function NativeRouteDB:Register(route)
    if type(route) ~= "table" then return false, "no es una tabla" end
    if type(route.id) ~= "string" or route.id == "" then return false, "sin id" end
    if not tonumber(route.dungeonKey) then return false, "sin dungeonKey" end
    if type(route.pulls) ~= "table" or #route.pulls == 0 then return false, "sin pulls" end
    if route.schemaVersion ~= 1 then return false, "schemaVersion no soportada" end
    if self._byID[route.id] then return false, "id duplicado: " .. route.id end

    route.loadSource = "BUNDLED_NATIVE"
    route.readOnly   = true

    self._byID[route.id] = route
    local key = tostring(route.dungeonKey)
    local lista = self._byDungeon[key]
    if not lista then lista = {}; self._byDungeon[key] = lista end
    lista[#lista + 1] = route
    self._count = self._count + 1
    return true
end

function NativeRouteDB:Get(routeID)
    return routeID and self._byID[routeID] or nil
end

function NativeRouteDB:GetForDungeon(dungeonKey)
    return self._byDungeon[tostring(dungeonKey)] or {}
end

function NativeRouteDB:GetDefault(dungeonKey)
    return self:GetForDungeon(dungeonKey)[1]
end

function NativeRouteDB:Count() return self._count end

function NativeRouteDB:AllKeys()
    local out = {}
    for key in pairs(self._byDungeon) do out[#out + 1] = tonumber(key) end
    table.sort(out)
    return out
end

function NativeRouteDB:Stats()
    local pulls, clones, mobs, sinNPC = 0, 0, 0, 0
    for _, route in pairs(self._byID) do
        pulls = pulls + #route.pulls
        for _, pull in ipairs(route.pulls) do
            for _, m in ipairs(pull.mobs or {}) do
                mobs = mobs + 1
                if not m.npcID then sinNPC = sinNPC + 1 end
                clones = clones + #(m.cloneIDs or {})
            end
        end
    end
    return {
        routes = self._count, pulls = pulls, clones = clones,
        mobEntries = mobs, mobsWithoutNPC = sinNPC,
        npcCoverage = mobs > 0 and (100 * (mobs - sinNPC) / mobs) or 0,
    }
end

return NativeRouteDB
