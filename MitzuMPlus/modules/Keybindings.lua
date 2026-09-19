-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Keybindings (v1.0)
-- Keybinding support for opening window, tabs, overlay toggle
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local L = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME).L

-- Register binding category header
BINDING_HEADER_MITZUMPLUS = "MitzuMPlus"

-- Binding names (these correspond to Bindings.xml)
BINDING_NAME_MITZUMPLUS_TOGGLE     = L["BIND_TOGGLE"]
BINDING_NAME_MITZUMPLUS_HISTORIAL  = L["BIND_HISTORY"]
BINDING_NAME_MITZUMPLUS_STATS      = L["BIND_STATS"]
BINDING_NAME_MITZUMPLUS_OVERLAY    = L["BIND_TRACKER"]

-- ─────────────────────────────────────────────────────────────────────────
-- BINDING ACTIONS (called from Bindings.xml)
-- ─────────────────────────────────────────────────────────────────────────

function MitzuMPlus_ToggleBinding()
    local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
    if MitzuMPlus and MitzuMPlus.ToggleWindow then
        MitzuMPlus:ToggleWindow()
    end
end

function MitzuMPlus_HistoryTabBinding()
    local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
    if MitzuMPlus and MitzuMPlus.ShowTab then
        MitzuMPlus:ShowTab("historial")
    end
end

function MitzuMPlus_StatsBinding()
    local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
    if MitzuMPlus and MitzuMPlus.ShowTab then
        MitzuMPlus:ShowTab("stats")
    end
end


function MitzuMPlus_OverlayBinding()
    local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
    local HUD = MitzuMPlus and MitzuMPlus.MitzuTracker
    if HUD then
        HUD:SetEnabled(not HUD:IsEnabled())
    end
end
