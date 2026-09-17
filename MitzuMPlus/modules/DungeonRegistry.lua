-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · DungeonRegistry v1.0
--
-- CUATRO IDENTIFICADORES DISTINTOS PARA LA MISMA MAZMORRA, Y NO SON LO MISMO:
--
--   instanceID      el 8º retorno de GetInstanceInfo(). La instancia física.
--   uiMapID         C_Map.GetBestMapForUnit("player"). El mapa de la UI, que
--                   además CAMBIA entre plantas de la misma mazmorra.
--   challengeMapID  C_ChallengeMode. El que usa el sistema de llaves. 399 para
--                   Estanques de Vida Rubí.
--   profileID       la clave con la que Mitzu guarda la ruta. Hoy coincide con
--                   challengeMapID, y por eso es tentador confundirlos.
--
-- Este módulo los converge en una identidad canónica. Sin él, DungeonContext
-- solo sabía quién era la mazmorra cuando C_ChallengeMode ya estaba activo —
-- es decir, justo cuando ya no hacía falta preguntar.
--
-- ═════════════════════════════════════════════════════════════════════════
-- CÓMO SE RESUELVE SIN LLAVE, Y POR QUÉ NO HAY NINGUNA TABLA A MANO
--
-- No existe API que traduzca instanceID -> challengeMapID. Pero sí hay dos que
-- dan el NOMBRE de la mazmorra, y el cliente las escribe igual porque es el
-- mismo cliente y el mismo idioma:
--
--   GetInstanceInfo()                        -> nombre de donde estás
--   C_ChallengeMode.GetMapTable()            -> todos los challengeMapID
--   C_ChallengeMode.GetMapUIInfo(id)         -> nombre de cada uno
--
-- Se cruzan por nombre normalizado. Esta lógica NO es mía: ya vivía en
-- ProfileManager.lua:128 (`currentInstanceChallengeMapID`), lleva tiempo
-- funcionando en vivo y es la que resolvía el perfil 399 cuando
-- DungeonContext fallaba. Aquí se extrae para que haya un solo dueño, y se le
-- añade lo que le faltaba: memoria.
--
-- APRENDIZAJE: cuando la llave SÍ está corriendo conocemos a la vez el
-- instanceID físico y el challengeMapID. Ese par se guarda. A partir de la
-- segunda visita la mazmorra se reconoce por instanceID, sin depender de que
-- dos cadenas de texto coincidan. Cubre las 8 de la temporada según se juegan,
-- sin escribir ni un ID a mano.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local DungeonRegistry = {}
MitzuMPlus.DungeonRegistry = DungeonRegistry

DungeonRegistry.byChallengeMapID = {}   -- [id]   = { challengeMapID, name }
DungeonRegistry.byName           = {}   -- [norm] = challengeMapID
DungeonRegistry.byInstanceMapID  = {}   -- [id]   = challengeMapID   (aprendido)
DungeonRegistry.byUIMapID        = {}   -- [id]   = challengeMapID   (aprendido)
DungeonRegistry._built           = false

local function normalizeName(s)
    if type(s) ~= "string" then return nil end
    s = s:lower():gsub("%s+", ""):gsub("%p", "")
    return s ~= "" and s or nil
end
DungeonRegistry.NormalizeName = normalizeName

-- ─────────────────────────────────────────────────────────────────────────
-- PERSISTENCIA DE LA IDENTIDAD FÍSICA APRENDIDA
-- ─────────────────────────────────────────────────────────────────────────

local function store()
    local global = MitzuMPlus.db and MitzuMPlus.db.global
    if type(global) ~= "table" then return nil end
    global.dungeonRegistry = global.dungeonRegistry or { byInstanceMapID = {}, byUIMapID = {} }
    global.dungeonRegistry.byInstanceMapID = global.dungeonRegistry.byInstanceMapID or {}
    global.dungeonRegistry.byUIMapID       = global.dungeonRegistry.byUIMapID or {}
    return global.dungeonRegistry
end

function DungeonRegistry:LoadLearned()
    local s = store()
    if not s then return 0 end
    local n = 0
    for k, v in pairs(s.byInstanceMapID) do
        local ik, iv = tonumber(k), tonumber(v)
        if ik and iv then self.byInstanceMapID[ik] = iv; n = n + 1 end
    end
    for k, v in pairs(s.byUIMapID) do
        local ik, iv = tonumber(k), tonumber(v)
        if ik and iv then self.byUIMapID[ik] = iv; n = n + 1 end
    end
    return n
end

-- ─────────────────────────────────────────────────────────────────────────
-- CONSTRUCCIÓN
-- ─────────────────────────────────────────────────────────────────────────

function DungeonRegistry:Build(force)
    if self._built and not force then return self end
    local CM = C_ChallengeMode
    if not (CM and CM.GetMapTable and CM.GetMapUIInfo) then return self end

    local ok, maps = pcall(CM.GetMapTable)
    if not ok or type(maps) ~= "table" then return self end

    for _, id in ipairs(maps) do
        local okU, name = pcall(CM.GetMapUIInfo, id)
        if okU and name then
            self.byChallengeMapID[id] = { challengeMapID = id, name = name }
            local k = normalizeName(name)
            if k then self.byName[k] = id end
        end
    end
    self:LoadLearned()
    self._built = true
    return self
end

function DungeonRegistry:Count()
    local n = 0
    for _ in pairs(self.byChallengeMapID) do n = n + 1 end
    return n
end

-- ─────────────────────────────────────────────────────────────────────────
-- RESOLUCIÓN
--
-- Devuelve: challengeMapID, nombre, fuente.
-- El orden importa: lo aprendido va primero porque es exacto; el nombre es la
-- vía de reserva, y funciona pero depende de texto.
-- ─────────────────────────────────────────────────────────────────────────

function DungeonRegistry:Resolve(instanceMapID, uiMapID, instanceName)
    self:Build()

    local id = instanceMapID and self.byInstanceMapID[instanceMapID]
    if id then return id, self:GetName(id), "INSTANCE_MAP" end

    id = uiMapID and self.byUIMapID[uiMapID]
    if id then return id, self:GetName(id), "UI_MAP" end

    local k = normalizeName(instanceName)
    id = k and self.byName[k]
    if id then return id, self:GetName(id), "LEGACY_MIGRATED" end

    return nil, nil, "UNKNOWN"
end

function DungeonRegistry:GetName(challengeMapID)
    local e = challengeMapID and self.byChallengeMapID[challengeMapID]
    return e and e.name or nil
end

function DungeonRegistry:IsKnown(challengeMapID)
    return challengeMapID ~= nil and self.byChallengeMapID[challengeMapID] ~= nil
end

-- Se llama cuando la llave está corriendo: ahí se conocen a la vez el mapa
-- físico y el de challenge, y el par ya no hay que deducirlo nunca más.
function DungeonRegistry:Learn(challengeMapID, instanceMapID, uiMapID)
    challengeMapID = tonumber(challengeMapID)
    if not challengeMapID then return false end
    local aprendido = false
    local s = store()

    instanceMapID = tonumber(instanceMapID)
    if instanceMapID and self.byInstanceMapID[instanceMapID] ~= challengeMapID then
        self.byInstanceMapID[instanceMapID] = challengeMapID
        if s then s.byInstanceMapID[tostring(instanceMapID)] = challengeMapID end
        aprendido = true
    end

    -- El uiMapID cambia entre plantas de la misma mazmorra, asi que un mismo
    -- challengeMapID puede acumular varios. No se pisan: se suman.
    uiMapID = tonumber(uiMapID)
    if uiMapID and self.byUIMapID[uiMapID] ~= challengeMapID then
        self.byUIMapID[uiMapID] = challengeMapID
        if s then s.byUIMapID[tostring(uiMapID)] = challengeMapID end
        aprendido = true
    end
    return aprendido
end

function DungeonRegistry:StatusLines()
    self:Build()
    local ni, nu = 0, 0
    for _ in pairs(self.byInstanceMapID) do ni = ni + 1 end
    for _ in pairs(self.byUIMapID) do nu = nu + 1 end
    return {
        "known challenge dungeons: " .. self:Count(),
        "instanceMapID learned: " .. ni,
        "uiMapID learned: " .. nu,
    }
end

return DungeonRegistry
