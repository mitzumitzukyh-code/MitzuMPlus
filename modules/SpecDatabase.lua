-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · SpecDatabase v1.0  —  ESQUEMA, NO DATASET
--
-- Dos cosas que se confunden a menudo y aquí no se mezclan:
--
--   IDENTIDAD DE SPEC   qué clase es, cómo se llama, qué rol cumple.
--                       Se resuelve contra la API del cliente, no a mano: son
--                       39 specs y una tabla escrita a mano envejece con cada
--                       parche. GetSpecializationInfoByID ya lo sabe.
--
--   CAPACIDADES         si ESE jugador puede interrumpir, disipar magia,
--                       resucitar en combate... Depende de talentos, no solo
--                       de la spec, así que NO se puede deducir del specID.
--                       Aquí solo está el vocabulario; rellenarlo es otra fase.
--
-- Escribir "Brewmaster = TANK" a mano sería redundante. Escribir "Brewmaster
-- siempre tiene interrupt" sería directamente falso en cuanto un talento lo
-- cambie. De ahí la separación.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local SpecDatabase = {}
MitzuMPlus.SpecDatabase = SpecDatabase

-- Vocabulario de capacidades. Es una lista cerrada a propósito: quien añada
-- una capacidad nueva tiene que tocar aquí, y así no aparecen cadenas sueltas
-- escritas de tres formas distintas por el addon.
SpecDatabase.CAPABILITIES = {
    "INTERRUPT",
    "DISPEL_MAGIC", "DISPEL_CURSE", "DISPEL_POISON", "DISPEL_DISEASE",
    "PURGE", "SOOTHE",
    "STUN", "INCAPACITATE", "KNOCK", "GRIP",
    "BATTLE_REZ", "BLOODLUST",
    "EXTERNAL_DEFENSIVE", "PERSONAL_DEFENSIVE", "IMMUNITY",
}

-- Cómo de disponible está una capacidad para ese jugador concreto.
SpecDatabase.AVAILABILITY = {
    BASE = "BASE",                          -- siempre la tiene
    TALENT_GATED = "TALENT_GATED",          -- depende de un talento
    HERO_TALENT_GATED = "HERO_TALENT_GATED",
    UNKNOWN = "UNKNOWN",                    -- no lo sabemos todavía
}

local valida = {}
for _, c in ipairs(SpecDatabase.CAPABILITIES) do valida[c] = true end

function SpecDatabase:IsCapability(name)
    return valida[name] == true
end

-- [specID] = { classFile, name, role, capabilities = {} }
SpecDatabase._specs = {}

-- Identidad resuelta contra el cliente y cacheada. Devuelve nil si el specID
-- no existe: no se inventa una spec para que un test pase.
function SpecDatabase:Get(specID)
    specID = tonumber(specID)
    if not specID then return nil end
    local cached = self._specs[specID]
    if cached then return cached end

    local CSI = C_SpecializationInfo
    local fn = CSI and CSI.GetSpecializationInfoByID
    if type(fn) ~= "function" then return nil end
    local ok, id, name, _, _, role, classFile = pcall(fn, specID)
    if not ok or not id then return nil end

    local entry = {
        specID    = id,
        name      = name,
        role      = role,
        classFile = classFile,
        capabilities = {},   -- se rellena en una fase posterior
    }
    self._specs[specID] = entry
    return entry
end

-- Registrar una capacidad de una spec. Valida el vocabulario en vez de
-- aceptar cualquier cadena.
function SpecDatabase:AddCapability(specID, capability, availability, spellID)
    local e = self:Get(specID)
    if not e then return false, "specID desconocido" end
    if not self:IsCapability(capability) then return false, "capacidad no válida" end
    availability = availability or self.AVAILABILITY.UNKNOWN
    e.capabilities[#e.capabilities + 1] = {
        capability   = capability,
        availability = availability,
        spellID      = tonumber(spellID),
    }
    return true
end

function SpecDatabase:GetCapabilities(specID)
    local e = self:Get(specID)
    return e and e.capabilities or nil
end

function SpecDatabase:StatusLines()
    local n = 0
    for _ in pairs(self._specs) do n = n + 1 end
    return {
        "specs resueltas en cache: " .. n,
        "vocabulario de capacidades: " .. #self.CAPABILITIES,
        "datos de capacidades por spec: |cFFff9922vacio (fase posterior)|r",
    }
end

return SpecDatabase
