-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · RouteManager v1  —  registro y selección de rutas nativas
--
-- QUÉ RUTAS HAY, CUÁL ESTÁ ELEGIDA, Y CARGARLA. Nada más.
--
-- NO cuenta muertos, NO escucha nameplates, NO pinta flechas y NO detecta la
-- mazmorra: eso último se lo pregunta a DungeonContext, que ya lo resuelve
-- bien tanto en PRE_KEY como en RUNNING.
--
-- El registro vive aquí dentro en vez de en un fichero propio porque son tres
-- tablas y cuatro funciones; un módulo separado solo añadiría un `require`
-- mental sin separar nada de verdad.
--
-- ═════════════════════════════════════════════════════════════════════════
-- SIN MDT EN EJECUCIÓN — comprobado antes de escribir esto
--
-- Todo lo que necesita una ruta ya está dentro de Mitzu:
--   · los 11 pulls con enemyIdx, cloneIdx, npcID y tropas
--        -> MPlusAdaptiveRouteDB.profiles["399"].plannedPulls
--   · el valor en tropas de cada enemigo y su total (551 en Ruby)
--        -> data/MDTEnemyData.lua, empaquetado con el addon
--
-- Las llamadas a MythicDungeonToolsAPI que quedan en el addon son de
-- IMPORTACIÓN (traer una ruta nueva) y de DIAGNÓSTICO (SyncReport), nunca de
-- carga. La única del camino vivo es `npcForce()` en EventTracker, y es un
-- respaldo para rutas sin npcIDs — la nuestra los trae (npcResolved=36).
--
-- Por eso `dataOrigin="MDT"` y `mdtRuntimeRequired=false` son ciertas a la vez.
-- ═════════════════════════════════════════════════════════════════════════
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local RouteManager = {}
MitzuMPlus.RouteManager = RouteManager

RouteManager._routes    = {}    -- [routeID] = MitzuRoute
RouteManager._byDungeon = {}    -- [dungeonKey] = { routeID, ... }
RouteManager._active    = nil   -- MitzuRoute cargada
RouteManager._activeKey = nil
RouteManager._validation = nil  -- resultado del validador de la ruta activa
RouteManager._discovered = false

local function bus() return MitzuMPlus.EventBus end
local function schema() return MitzuMPlus.RouteSchema end

-- ─────────────────────────────────────────────────────────────────────────
-- REGISTRO
-- ─────────────────────────────────────────────────────────────────────────

function RouteManager:Register(route)
    local S = schema()
    if not S then return false, "RouteSchema no cargado" end
    if type(route) ~= "table" or not route.id or not route.dungeonKey then
        return false, "ruta sin id o sin dungeonKey"
    end
    local v = S.Validate(route, route.mdtDungeonIdx)
    if not v.valid then
        return false, "ruta inválida: " .. tostring(v.errors[1])
    end
    self._routes[route.id] = route
    local key = tostring(route.dungeonKey)
    local lista = self._byDungeon[key]
    if not lista then lista = {}; self._byDungeon[key] = lista end
    local ya = false
    for _, id in ipairs(lista) do if id == route.id then ya = true break end end
    if not ya then lista[#lista + 1] = route.id end
    return true, v
end

function RouteManager:Get(routeID)
    return routeID and self._routes[routeID] or nil
end

function RouteManager:GetRoutesForDungeon(dungeonKey)
    self:Discover()
    local out = {}
    for _, id in ipairs(self._byDungeon[tostring(dungeonKey)] or {}) do
        out[#out + 1] = self._routes[id]
    end
    return out
end

-- La primera registrada para esa mazmorra. Con una ruta por mazmorra, que es
-- el caso de hoy, "por defecto" y "la única" coinciden.
-- La empaquetada manda como default aunque se registrara despues: es el dato
-- de fabrica, y una instalacion limpia tiene que comportarse igual que una
-- que lleva meses con rutas importadas.
function RouteManager:GetDefaultRouteID(dungeonKey)
    local lista = self._byDungeon[tostring(dungeonKey)]
    if not lista or #lista == 0 then return nil end
    for _, id in ipairs(lista) do
        local r = self._routes[id]
        if r and r.loadSource == "BUNDLED_NATIVE" then return id end
    end
    return lista[1]
end

function RouteManager:GetLoadSource()
    return self._active and self._active.loadSource or "NONE"
end

-- ¿Hacen falta las rutas guardadas en SavedVariables? Solo si la ruta activa
-- vino de ahi. Con la empaquetada, no.
function RouteManager:SavedRouteDataRequired()
    return self:GetLoadSource() == "LEGACY_FALLBACK"
end

-- ─────────────────────────────────────────────────────────────────────────
-- DESCUBRIMIENTO DESDE LOS PERFILES HEREDADOS
--
-- Adaptador, no dependencia: RouteManager nunca lee plannedPulls. Le pide la
-- conversión a RouteSchema y a partir de ahí solo maneja MitzuRoute.
-- ─────────────────────────────────────────────────────────────────────────

-- PRIORIDAD DE FUENTES
--   1. BUNDLED_NATIVE   las que vienen con el addon (data/Routes/Season2)
--   2. LEGACY_FALLBACK  normalizadas de MPlusAdaptiveRouteDB, SOLO si esa
--                       mazmorra no tiene ruta empaquetada
--
-- La eleccion del jugador se aplica DESPUES, sobre lo que haya registrado:
-- elegir no es descubrir.
--
-- Por que la legacy no se normaliza cuando ya hay empaquetada: darian el mismo
-- id (`mitzu_399_standard`, derivado del dungeonKey) y chocarian. Y no aporta:
-- la empaquetada salio exactamente de ella.
function RouteManager:Discover(force)
    if self._discovered and not force then return self end
    self._bundled, self._legacy = 0, 0

    -- 1) Empaquetadas.
    local NDB = MitzuMPlus.NativeRouteDB
    if NDB then
        for _, key in ipairs(NDB:AllKeys()) do
            for _, route in ipairs(NDB:GetForDungeon(key)) do
                if self:Register(route) then self._bundled = self._bundled + 1 end
            end
        end
    end

    -- 2) Respaldo desde SavedVariables, solo donde falte.
    local S = schema()
    local db = _G.MPlusAdaptiveRouteDB
    if S and type(db) == "table" and type(db.profiles) == "table" then
        for key, profile in pairs(db.profiles) do
            local dungeonKey = tonumber(key) or tonumber(profile.challengeMapID)
            local yaEmpaquetada = dungeonKey and NDB and NDB:GetDefault(dungeonKey) ~= nil
            if dungeonKey and not yaEmpaquetada then
                local route = S.FromLegacyProfile(profile, dungeonKey)
                if route then
                    route.mdtDungeonIdx = tonumber(profile.mdtDungeonIdx)
                    route.loadSource = "LEGACY_FALLBACK"
                    if self:Register(route) then self._legacy = self._legacy + 1 end
                end
            end
        end
    end

    self._discovered = true
    return self
end

-- Cuenta de cada origen, para el informe.
function RouteManager:SourceCounts()
    self:Discover()
    return self._bundled or 0, self._legacy or 0
end

-- ─────────────────────────────────────────────────────────────────────────
-- SELECCIÓN PERSISTIDA
--
-- Solo se guarda la ELECCIÓN, nunca la ruta: duplicar la base de datos nativa
-- en SavedVariables sería garantizar que las dos copias divergen.
-- ─────────────────────────────────────────────────────────────────────────

local function selectedStore()
    local db = _G.MPlusAdaptiveRouteDB
    if type(db) ~= "table" then return nil end
    db.selectedRoutes = db.selectedRoutes or {}
    return db.selectedRoutes
end

function RouteManager:GetSelectedRouteID(dungeonKey)
    self:Discover()
    local key = tostring(dungeonKey)
    local store = selectedStore()
    local id = store and store[key]

    -- Una selección que apunta a una ruta que ya no existe no es un error:
    -- se cae al valor por defecto en silencio. Romper la carga por una
    -- preferencia caducada sería castigar al jugador por haber actualizado.
    if id and self._routes[id] then return id, "SAVED" end
    if id then
        -- Puede ser el id heredado ("elitzur_rlp_1"): se migra al nativo.
        for rid, route in pairs(self._routes) do
            if tostring(route.dungeonKey) == key then
                for _, legacy in ipairs(route.legacyIDs or {}) do
                    if legacy == id then
                        if store then store[key] = rid end
                        return rid, "MIGRATED"
                    end
                end
            end
        end
    end
    local def = self:GetDefaultRouteID(dungeonKey)
    return def, def and "DEFAULT" or "NONE"
end

function RouteManager:SetSelectedRoute(dungeonKey, routeID)
    self:Discover()
    local route = self._routes[routeID]
    if not route then return false, "esa ruta no existe" end
    if tostring(route.dungeonKey) ~= tostring(dungeonKey) then
        return false, "esa ruta no es de esta mazmorra"
    end
    local store = selectedStore()
    if store then store[tostring(dungeonKey)] = routeID end
    if tostring(self._activeKey) == tostring(dungeonKey) then
        self:LoadForDungeon(dungeonKey)
        if bus() then bus():Emit("MITZU_ROUTE_CHANGED", route) end
    end
    return true, routeID
end

-- ─────────────────────────────────────────────────────────────────────────
-- CARGA
-- ─────────────────────────────────────────────────────────────────────────

function RouteManager:GetActiveRoute() return self._active end
function RouteManager:IsReady()        return self._active ~= nil end
function RouteManager:GetValidation()  return self._validation end

-- ─────────────────────────────────────────────────────────────────────────
-- FIRMA DE UN PULL  (fase 4)
--
-- Qué espera la ruta en el pull N: cuántas unidades y de qué npcIDs.
--
--   RouteManager:GetPullSignature(nil, 4)
--     -> { pull = 4, mobCount = 7, npcMultiset = { [190207] = 2, ... } }
--
-- `routeID` nil significa la ruta ACTIVA. Funciona sin MDT instalado: sale
-- de los ficheros empaquetados, igual que todo lo demás de la ruta nativa.
--
-- El cálculo vive en AdaptiveRoute/RouteSignature para poder probarlo
-- aislado; aquí solo está la puerta, porque el manager es quien sabe
-- resolver un routeID.
-- ─────────────────────────────────────────────────────────────────────────

function RouteManager:GetPullSignature(routeID, pullIndex)
    local AR = MitzuMPlus.AdaptiveRoute
    local RS = AR and AR.RouteSignature
    if not RS then return nil, "RouteSignature no está cargado" end
    local route = routeID and self:Get(routeID) or self._active
    if not route then return nil, "no hay ruta" end
    return RS:ForPull(route, pullIndex)
end

function RouteManager:LoadForDungeon(dungeonKey)
    self:Discover()
    if not dungeonKey then return nil, "sin dungeonKey" end

    local id = self:GetSelectedRouteID(dungeonKey)
    local route = id and self._routes[id] or nil
    if not route then
        self:Unload()
        return nil, "no hay ninguna ruta para esta mazmorra"
    end
    -- Ya estaba cargada: no se vuelve a normalizar ni a emitir nada. Al poner
    -- la llave llega MITZU_KEY_STARTED y no debe redescubrirse la ruta entera.
    if self._active == route then return route, "ya cargada" end

    local S = schema()
    self._validation = S and S.Validate(route, route.mdtDungeonIdx) or nil
    self._active     = route
    self._activeKey  = dungeonKey

    if bus() then bus():Emit("MITZU_ROUTE_LOADED", route, self._validation) end
    return route
end

function RouteManager:Unload()
    if not self._active then return false end
    local antes = self._active
    self._active, self._activeKey, self._validation = nil, nil, nil
    if bus() then bus():Emit("MITZU_ROUTE_UNLOADED", antes) end
    return true
end

-- Los datos vienen de MDT, pero ya están dentro de Mitzu. Esta función
-- responde a la pregunta que de verdad importa: ¿hace falta MDT AHORA?
function RouteManager:MDTRuntimeRequired()
    return false
end

-- ─────────────────────────────────────────────────────────────────────────
-- ENGANCHE CON DUNGEONCONTEXT
--
-- Se carga en PRE_KEY, no al arrancar la llave. Cuando llega
-- MITZU_KEY_STARTED la ruta ya está lista y solo hay que activarla.
-- ─────────────────────────────────────────────────────────────────────────

if MitzuMPlus.EventBus then
    MitzuMPlus.EventBus:On("MITZU_DUNGEON_CHANGED", function(dungeonKey)
        pcall(function() RouteManager:LoadForDungeon(dungeonKey) end)
    end, 70)   -- antes que RouteProgress, que consume lo que esto carga

    MitzuMPlus.EventBus:On("MITZU_DUNGEON_STATE_CHANGED", function(nuevo)
        if nuevo == "OUTSIDE" then pcall(function() RouteManager:Unload() end) end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────
-- INFORMES
-- ─────────────────────────────────────────────────────────────────────────

function RouteManager:StatusLines()
    local DC = MitzuMPlus.DungeonContext
    local key = DC and DC:GetDungeonKey() or nil
    local L = { "dungeonKey=" .. tostring(key) }
    local r = self._active
    if not r then
        L[#L + 1] = "routeID=(ninguna cargada)"
        L[#L + 1] = "mdtRuntimeRequired=" .. tostring(self:MDTRuntimeRequired())
        return L
    end
    local v = self._validation
    local RP = MitzuMPlus.RouteProgress
    L[#L + 1] = "routeID=" .. tostring(r.id)
    L[#L + 1] = "routeName=" .. tostring(r.name)
    L[#L + 1] = "source=" .. tostring(r.source and r.source.type)
    L[#L + 1] = "routeLoadSource=" .. tostring(r.loadSource or "UNKNOWN")
    L[#L + 1] = "dataOrigin=" .. tostring(r.source and r.source.dataOrigin)
    L[#L + 1] = "originalRouteID=" .. tostring(r.source and r.source.originalRouteID)
    L[#L + 1] = "schemaVersion=" .. tostring(r.schemaVersion)
    L[#L + 1] = "routeState=" .. tostring(RP and RP:GetState() or "sin RouteProgress")
    L[#L + 1] = string.format("pull=%s/%s",
        tostring(RP and RP:GetPullIndex() or "?"), tostring(#r.pulls))
    if v then
        L[#L + 1] = string.format("totalClones=%d", v.clones.total)
        L[#L + 1] = string.format("validClones=%d", v.clones.valid)
        L[#L + 1] = string.format("unresolvedClones=%d", v.clones.unresolved)
        if #v.warnings > 0 then
            L[#L + 1] = "warnings=" .. #v.warnings .. " (|cFFf7d470/emp routes|r para verlos)"
        end
    end
    L[#L + 1] = "mdtRuntimeRequired=" .. tostring(self:MDTRuntimeRequired())
    L[#L + 1] = "savedRouteDataRequired=" .. tostring(self:SavedRouteDataRequired())
    local RS = MitzuMPlus.RunSession
    if RP and RP.WasRecovered and RP:WasRecovered() then
        L[#L + 1] = "recovered=true"
        L[#L + 1] = "recoveryPull=" .. tostring(RP:GetPullIndex())
        L[#L + 1] = "recoveryReason=" .. tostring(RS and RS:GetReason() or "?")
    elseif RS then
        L[#L + 1] = "recovered=false"
        L[#L + 1] = "recoveryReason=" .. tostring(RS:GetReason())
    end
    return L
end

function RouteManager:RoutesLines(dungeonKey)
    local DC = MitzuMPlus.DungeonContext
    dungeonKey = dungeonKey or (DC and DC:GetDungeonKey())
    if not dungeonKey then return { "|cFFff9922No sé en qué mazmorra estás.|r" } end
    local lista = self:GetRoutesForDungeon(dungeonKey)
    local sel = self:GetSelectedRouteID(dungeonKey)
    local def = self:GetDefaultRouteID(dungeonKey)
    local bundled, legacy = self:SourceCounts()
    local L = {
        string.format("|cFF999999Bundled routes: %d · Legacy routes: %d|r", bundled, legacy),
        "|cFFe8b84a" .. tostring(DC and DC:GetDungeonName() or dungeonKey) .. "|r",
    }
    if #lista == 0 then
        L[#L + 1] = "  (ninguna ruta disponible)"
        return L
    end
    for _, r in ipairs(lista) do
        L[#L + 1] = string.format("%s %s", (r.id == sel) and "|cFF21de66*|r" or " ", r.name)
        L[#L + 1] = "    id=" .. r.id
        L[#L + 1] = "    " .. tostring(r.loadSource or "UNKNOWN") ..
                    " · pulls=" .. #r.pulls ..
                    ((r.id == def) and " · default=true" or "")
        local v = MitzuMPlus.RouteSchema and MitzuMPlus.RouteSchema.Validate(r, r.mdtDungeonIdx)
        if v then
            for _, w in ipairs(v.warnings) do
                L[#L + 1] = "    |cFFf7d470aviso:|r " .. w
            end
        end
    end
    return L
end

-- ─────────────────────────────────────────────────────────────────────────
-- AUTOPRUEBA NATIVA
--
-- Responde a "¿funcionaria esto en una instalacion limpia?" SIN tocar los
-- datos del jugador. No borra ni renombra nada: consulta NativeRouteDB
-- directamente, que es justo lo unico que existiria en un instalacion nueva.
-- ─────────────────────────────────────────────────────────────────────────

function RouteManager:SelfTestNativeLines()
    local NDB = MitzuMPlus.NativeRouteDB
    local L = { "|cFFe8b84a═══ AUTOPRUEBA DE RUTAS NATIVAS ═══|r" }
    if not NDB then
        L[#L + 1] = "|cFFff5555NativeRouteDB no esta cargada.|r"
        return L
    end
    L[#L + 1] = "|cFF999999Sin mirar MDT ni las rutas de SavedVariables.|r"
    L[#L + 1] = ""

    local S = schema()
    local claves = NDB:AllKeys()
    local ok = 0
    for _, key in ipairs(claves) do
        local r = NDB:GetDefault(key)
        local linea, bien
        if not r then
            linea, bien = "sin ruta", false
        else
            local v = S and S.Validate(r, r.mdtDungeonIdx) or nil
            bien = (v == nil) or v.valid
            linea = string.format("%d pulls", #r.pulls)
            if v and v.clones.unresolved > 0 then
                linea = linea .. string.format(" · %d/%d clones",
                    v.clones.valid, v.clones.total)
            end
        end
        if bien then ok = ok + 1 end
        L[#L + 1] = string.format("%-5d %-26s %s · %s", key,
            tostring(r and r.dungeonName or "?"):sub(1, 26),
            bien and "|cFF21de66PASS|r" or "|cFFff5555FAIL|r", linea)
    end

    local st = NDB:Stats()
    L[#L + 1] = ""
    L[#L + 1] = string.format("%s%d/%d PASS|r", (ok == #claves) and "|cFF21de66" or "|cFFff9922",
        ok, #claves)
    L[#L + 1] = string.format("pulls=%d · clones=%d · npcCoverage=%.0f%%",
        st.pulls, st.clones, st.npcCoverage)
    L[#L + 1] = "runtimeMDTRequired=" .. tostring(self:MDTRuntimeRequired())
    L[#L + 1] = "savedRouteDataRequired=false"
    return L
end

return RouteManager
