-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Bootstrap.lua
-- DEBE cargar ANTES que cualquier módulo que use GetAddon().
--
-- PROBLEMA RAÍZ: Todos los módulos (Constants, Database, Utils, Trackers…)
-- hacen LibStub("AceAddon-3.0"):GetAddon("MitzuMPlus") al cargar.
-- Init.lua era el único archivo con NewAddon(), pero cargaba al final:
-- cuando los módulos intentaban GetAddon() el addon aún no existía → crash.
--
-- SOLUCIÓN: Este archivo llama NewAddon() primero, antes que cualquier módulo.
-- Init.lua pasa a usar GetAddon() y solo define los lifecycle hooks.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME    = "MitzuMPlus"
-- Leer la versión directamente del .toc en runtime.
-- En The War Within (patch 11.0+) GetAddOnMetadata fue reemplazada por
-- C_AddOns.GetAddOnMetadata. Se prueba la nueva API primero, luego la vieja.
local function ReadTocVersion(addonName)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addonName, "Version")
    elseif GetAddOnMetadata then
        return GetAddOnMetadata(addonName, "Version")
    end
    return nil
end
local ADDON_VERSION = ReadTocVersion(ADDON_NAME) or "5.0.0"

-- Crear el addon. A partir de aquí GetAddon() funciona en cualquier módulo.
local MitzuMPlus = LibStub("AceAddon-3.0"):NewAddon(
    ADDON_NAME,
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceSerializer-3.0"
)

-- Exponer globalmente para que módulos que usen _G.MitzuMPlus también funcionen.
_G[ADDON_NAME] = MitzuMPlus
_G.MitzuMPlus  = MitzuMPlus

-- Metadatos de versión — fuente única de verdad.
MitzuMPlus.VERSION     = ADDON_VERSION
MitzuMPlus.INITIALIZED = false
