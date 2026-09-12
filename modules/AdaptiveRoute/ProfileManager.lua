-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · ProfileManager v1.0
--
-- Perfiles de ruta persistentes, indexados por mazmorra + nivel + afijos.
--
-- Por qué la clave lleva los afijos: la ruta óptima de una +13 con Tiránico no
-- es la de una +13 con Fortificado. Guardarlas bajo la misma clave hace que
-- cada semana pises la ruta de la anterior. El nivel entra por lo mismo: en
-- una +2 saltas paquetes que en una +18 son obligatorios por el conteo.
--
-- SavedVariables propio (MPlusAdaptiveRouteDB) y no MitzuMPlusDB: las rutas
-- son grandes y se reescriben a menudo; mezclarlas con el historial de runs
-- haría que cada guardado serializase también todo el historial.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local ProfileManager = {}
AR.ProfileManager = ProfileManager

local DB_NAME  = "MPlusAdaptiveRouteDB"
local DB_VERSION = 1

-- Valores por defecto. Se FUSIONAN, nunca se asignan encima: sobrescribir la
-- tabla entera en cada carga borraría las rutas del usuario en la primera
-- actualización que añadiese un campo nuevo.
local DEFAULTS = {
    dbVersion = DB_VERSION,
    profiles  = {},   -- [profileKey] = perfil
    settings  = {
        enabled          = true,
        syncWithGroup    = true,   -- solo el líder emite
        autoSaveOnFinish = true,
        -- nameplateSkips se retiro con NameplateHooks. El campo puede seguir
        -- en la DB de quien ya jugo con el; no se borra porque borrar datos
        -- del usuario para ahorrar un byte no compensa. Lo sustituye
        -- routeArrowsEnabled, que a nil vale true.
        -- Route Arrows. routeArrowsEnabled sustituye a nameplateSkips; la
        -- fusion no destructiva deja en true a quien nunca lo haya tocado.
        routeArrowsEnabled = true,
        arrowSize          = 56,   -- ALTURA; el ancho sale de la proporcion del atlas
        arrowAnchor        = "placa",  -- el anchor de Threat Plates no va centrado
        arrowOffsetX       = 0,
        arrowOffsetY       = 8,
        arrowAlpha         = 1,
        arrowAnimate       = true,
    },
    stats = { saves = 0, loads = 0 },
}

-- Fusión recursiva no destructiva.
local function mergeDefaults(target, defaults)
    if type(target) ~= "table" then return CopyTable and CopyTable(defaults) or defaults end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            mergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

function ProfileManager:DB()
    return _G[DB_NAME]
end

function ProfileManager:Settings()
    local db = self:DB()
    return db and db.settings or DEFAULTS.settings
end

-- ─────────────────────────────────────────────────────────────────────────
-- CLAVE DE PERFIL
-- ─────────────────────────────────────────────────────────────────────────

-- Los afijos se ORDENAN antes de unirlos. La API no garantiza un orden estable
-- entre sesiones, y sin ordenar "9-10-152" y "10-9-152" serían dos perfiles
-- distintos para la misma semana.
--
-- HALLAZGO (medido en el cliente del usuario, v6.8.0): las dos fuentes de
-- afijos NO devuelven lo mismo.
--   Fuera de la llave, C_MythicPlus.GetCurrentAffixes  -> 9-10-147-160-165
--   Dentro,  C_ChallengeMode.GetActiveKeystoneInfo     -> 10-160
-- La de fuera lista TODOS los afijos de la semana; la de dentro solo los que
-- de verdad se aplican a ese nivel de llave. Resultado: la misma llave genera
-- dos claves distintas segun donde se calcule, y un perfil guardado dentro no
-- se encuentra desde fuera.
--
-- No se "arregla" inventando que afijos aplican a cada nivel: los umbrales
-- cambian por temporada y hardcodearlos envejece mal. Lo que se hace es que la
-- BUSQUEDA no dependa de los afijos (ver LoadNearest, que casa por mazmorra +
-- nivel), y que el guardado use la clave de DENTRO, que es la autoritativa.
-- ═════════════════════════════════════════════════════════════════════════
-- BUG CONTEXTO-1 (v7.9.2) — "donde estoy" no se preguntaba nunca.
--
-- GetContext() miraba dos cosas: la llave EN CURSO y, si no habia, la piedra
-- QUE LLEVAS EN LA BOLSA. Faltaba justo la del medio: la mazmorra en la que
-- estas plantado.
--
-- Efecto real: entrando a El Frontal de la Muerte con una piedra de Nalorakk
-- encima, el addon anunciaba "Mazmorra: Guarida de Nalorakk +14", cargaba SU
-- ruta de 17 packs y marcaba ese perfil como "<- esta mazmorra". Todo el
-- informe era coherente consigo mismo y equivocado de mazmorra.
--
-- Se resuelve por NOMBRE porque es lo unico que las dos APIs comparten:
-- GetInstanceInfo da el nombre de la instancia y GetMapUIInfo el de cada
-- mazmorra mitica+; los dos salen del mismo cliente, o sea el mismo idioma.
-- Es el mismo emparejamiento por nombre que Bootstrap ya usa para MDT.
--
-- LIMITE: las alas de megamazmorra ("Operacion: Mechagon - Taller") no casan
-- con el nombre de la instancia padre. En ese caso no se inventa nada: se
-- devuelve nil y se cae a la piedra, que es exactamente lo que hacia antes.
-- ═════════════════════════════════════════════════════════════════════════
local function normalizeName(s)
    if type(s) ~= "string" then return nil end
    s = s:lower():gsub("%s+", ""):gsub("%p", "")
    return s ~= "" and s or nil
end

local _challengeByName
local function currentInstanceChallengeMapID()
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable
            and C_ChallengeMode.GetMapUIInfo and GetInstanceInfo) then
        return nil
    end
    local okI, iname = pcall(GetInstanceInfo)
    local target = okI and normalizeName(iname)
    if not target then return nil end

    if not _challengeByName then
        _challengeByName = {}
        local okT, maps = pcall(C_ChallengeMode.GetMapTable)
        if okT and type(maps) == "table" then
            for _, id in ipairs(maps) do
                local okU, n = pcall(C_ChallengeMode.GetMapUIInfo, id)
                local k = okU and normalizeName(n)
                if k then _challengeByName[k] = id end
            end
        end
    end
    return _challengeByName[target]
end

local function affixString(affixIDs)
    if type(affixIDs) ~= "table" or #affixIDs == 0 then return "noaffix" end
    local ids = {}
    for _, a in ipairs(affixIDs) do
        local id = tonumber(type(a) == "table" and (a.id or a[1]) or a)
        if id then ids[#ids + 1] = id end
    end
    if #ids == 0 then return "noaffix" end
    table.sort(ids)
    return table.concat(ids, "-")
end

-- Dentro de una llave activa manda C_ChallengeMode. Fuera, se usa la llave que
-- lleva el jugador en la bolsa, para poder preparar la ruta antes de entrar.
function ProfileManager:GetContext()
    local dungeonID, keyLevel, affixIDs, source

    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local ok, id = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        if ok and id then
            dungeonID = id
            source = "active"
            if C_ChallengeMode.GetActiveKeystoneInfo then
                local ok2, lvl, affixes = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
                if ok2 then
                    keyLevel = tonumber(lvl)
                    affixIDs = affixes
                end
            end
        end
    end

    -- Sin llave corriendo pero dentro de una mazmorra: manda DONDE ESTAS.
    -- Va antes que la piedra a proposito; lo que llevas en la bolsa no dice
    -- nada de donde te encuentras.
    if not dungeonID and IsInInstance then
        local okIn, inInstance, kind = pcall(IsInInstance)
        if okIn and inInstance and (kind == "party" or kind == "scenario") then
            local id = currentInstanceChallengeMapID()
            if id then
                dungeonID = id
                source = "instancia"
                -- El nivel solo se copia de la piedra si es de ESTA mazmorra.
                -- Poner el +14 de Nalorakk sobre El Frontal seria repetir el
                -- mismo error un campo mas abajo.
                if C_MythicPlus then
                    local okO, ownedID = pcall(function()
                        return C_MythicPlus.GetOwnedKeystoneChallengeMapID() end)
                    if okO and ownedID == id then
                        local okL, lvl = pcall(function()
                            return C_MythicPlus.GetOwnedKeystoneLevel() end)
                        if okL then keyLevel = tonumber(lvl) end
                    end
                    local okA, aff = pcall(function()
                        return C_MythicPlus.GetCurrentAffixes() end)
                    if okA then affixIDs = aff end
                end
            end
        end
    end

    if not dungeonID and C_MythicPlus then
        local ok, id = pcall(function() return C_MythicPlus.GetOwnedKeystoneChallengeMapID() end)
        if ok and id then
            dungeonID = id
            source = "owned"
            local ok2, lvl = pcall(function() return C_MythicPlus.GetOwnedKeystoneLevel() end)
            if ok2 then keyLevel = tonumber(lvl) end
            local ok3, aff = pcall(function() return C_MythicPlus.GetCurrentAffixes() end)
            if ok3 then affixIDs = aff end
        end
    end

    if not dungeonID then return nil end
    return {
        dungeonID = dungeonID,
        keyLevel  = keyLevel or 0,
        affixes   = affixString(affixIDs),
        source    = source,
    }
end

-- ═════════════════════════════════════════════════════════════════════════
-- v7.1.0 — LA CLAVE ES LA MAZMORRA. Punto.
--
-- BUG medido: importando la ruta de Altar de Colmillos con una llave de otra
-- mazmorra en la bolsa, el perfil se guardo como "250_12_9-10-147-160-165".
-- Mazmorra equivocada (la de la llave, no la de la ruta) y nivel equivocado.
-- Al entrar en Altar de Colmillos no se encontraba nada.
--
-- El error de fondo era mio y de diseño: meti nivel y afijos en la clave
-- pensando que la ruta optima cambia con ellos. Cambia el JUEGO de la ruta
-- (que saltas, que no), pero la RUTA de MDT es una sola por mazmorra — es lo
-- que el usuario dibuja y guarda alli. Trocearla por nivel y afijos generaba
-- un perfil nuevo cada semana y cada nivel, y ninguno se reutilizaba.
--
-- Ahora: clave = ID de mazmorra. Nivel y afijos se guardan como METADATOS
-- (utiles para el aviso y para el solver), no como parte de la identidad.
-- ═════════════════════════════════════════════════════════════════════════
function ProfileManager:BuildProfileKey(ctx)
    ctx = ctx or self:GetContext()
    if not ctx or not ctx.dungeonID then return nil end
    return tostring(ctx.dungeonID)
end

-- Migracion de las claves antiguas "<dungeon>_<nivel>_<afijos>".
-- Se queda con la mas reciente de cada mazmorra y borra el resto. Sin esto,
-- los perfiles ya guardados quedarian huerfanos para siempre.
function ProfileManager:MigrateLegacyKeys()
    local db = self:DB()
    if not db or type(db.profiles) ~= "table" then return 0 end
    local migrated, best = 0, {}

    for k, p in pairs(db.profiles) do
        local dungeon = type(k) == "string" and k:match("^(%d+)_%d+_")
        if dungeon then
            local cur = best[dungeon]
            if not cur or (tonumber(p.updated) or 0) > (tonumber(cur.updated) or 0) then
                best[dungeon] = p
            end
        end
    end

    for dungeon, p in pairs(best) do
        -- Un perfil ya guardado con la clave nueva manda: no se pisa.
        if not db.profiles[dungeon] then
            p.key = dungeon
            db.profiles[dungeon] = p
            migrated = migrated + 1
        end
    end

    for k in pairs(db.profiles) do
        if type(k) == "string" and k:match("^%d+_%d+_") then db.profiles[k] = nil end
    end
    return migrated
end

-- ─────────────────────────────────────────────────────────────────────────
-- CARGA / GUARDADO
-- ─────────────────────────────────────────────────────────────────────────

function ProfileManager:Load(key)
    key = key or self:BuildProfileKey()
    if not key then return nil, "sin contexto de mazmorra" end
    local db = self:DB()
    if not db then return nil, "DB no inicializada" end
    local p = db.profiles[key]
    if not p then return nil, "sin perfil guardado" end
    db.stats.loads = (db.stats.loads or 0) + 1
    self._activeKey = key
    self._active = p
    return p, key
end

-- Busca el perfil más cercano cuando no hay uno exacto: misma mazmorra, otros
-- afijos o nivel. Reimportar de MDT cada semana es justo lo que se quería
-- evitar, y una ruta de la semana pasada es infinitamente mejor que nada.
-- Con la clave por mazmorra ya no hace falta buscar "el mas parecido": o hay
-- ruta para esta mazmorra o no la hay. Se conserva el nombre por compatibilidad
-- con los llamantes.
function ProfileManager:LoadNearest(ctx)
    ctx = ctx or self:GetContext()
    if not ctx then return nil, nil, "sin contexto de mazmorra" end
    local key = self:BuildProfileKey(ctx)
    local p = key and self:Load(key)
    if p then return p, key, "exacto" end
    return nil, key, "sin ruta guardada para esta mazmorra"
end

function ProfileManager:Save(key, profile)
    key = key or self._activeKey or self:BuildProfileKey()
    if not key then return false, "sin contexto de mazmorra" end
    profile = profile or self._active
    if type(profile) ~= "table" then return false, "perfil vacío" end
    local db = self:DB()
    if not db then return false, "DB no inicializada" end

    profile.updated = (time and time()) or 0
    profile.key = key
    db.profiles[key] = profile
    db.stats.saves = (db.stats.saves or 0) + 1
    self._activeKey = key
    self._active = profile
    return true, key
end

function ProfileManager:GetActive()
    return self._active, self._activeKey
end

function ProfileManager:SetActive(profile, key)
    self._active = profile
    self._activeKey = key or self._activeKey
end

function ProfileManager:Delete(key)
    local db = self:DB()
    if not db or not key then return false end
    db.profiles[key] = nil
    if self._activeKey == key then self._active, self._activeKey = nil, nil end
    return true
end

function ProfileManager:List()
    local db = self:DB()
    local out = {}
    if not db then return out end
    for k, p in pairs(db.profiles) do
        out[#out + 1] = {
            key = k,
            name = p.name or "?",
            pulls = type(p.pulls) == "table" and #p.pulls or 0,
            updated = p.updated or 0,
        }
    end
    table.sort(out, function(a, b) return (a.updated or 0) > (b.updated or 0) end)
    return out
end

-- ─────────────────────────────────────────────────────────────────────────
-- INICIALIZACIÓN SEGURA
--
-- ADDON_LOADED puede dispararse para cualquier addon; se filtra por nombre. La
-- tabla de SavedVariables solo existe a partir de ese evento, así que ningún
-- otro módulo debe tocar la DB antes de que esto corra.
-- ─────────────────────────────────────────────────────────────────────────

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON_NAME then return end
    -- BUG TAINT-1: aqui habia un loader:UnregisterEvent("ADDON_LOADED") al
    -- terminar. El cliente rechaza UnregisterEvent desde codigo del addon
    -- (ver EventTracker:Stop). Una bandera hace lo mismo y no puede ser
    -- rechazada: ADDON_LOADED dispara unas pocas veces por sesion.
    if ProfileManager._ready then return end

    if type(_G[DB_NAME]) ~= "table" then _G[DB_NAME] = {} end
    mergeDefaults(_G[DB_NAME], DEFAULTS)

    local db = _G[DB_NAME]
    -- Migraciones futuras entran aquí. Hoy solo se sella la versión.
    if (tonumber(db.dbVersion) or 0) < DB_VERSION then
        db.dbVersion = DB_VERSION
    end

    ProfileManager._ready = true
    local migrated = ProfileManager:MigrateLegacyKeys()
    if migrated > 0 and MitzuMPlus.Print then
        MitzuMPlus:Print(string.format(
            "|cFFd9b33eRutas:|r %d perfil(es) migrados a la clave por mazmorra.", migrated))
    end
    if AR.OnProfileDBReady then pcall(AR.OnProfileDBReady) end
end)

return ProfileManager
