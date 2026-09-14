-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Keybindings (v1.0)
-- Keybinding support for opening window, tabs, overlay toggle
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"

-- Register binding category header
BINDING_HEADER_MITZUMPLUS = "MitzuMPlus"

-- Binding names (these correspond to Bindings.xml)
BINDING_NAME_MITZUMPLUS_TOGGLE     = "Toggle MitzuMPlus Window"
BINDING_NAME_MITZUMPLUS_HISTORIAL  = "Open History Tab"
BINDING_NAME_MITZUMPLUS_STATS      = "Open Statistics Tab"
BINDING_NAME_MITZUMPLUS_OVERLAY    = "Toggle Key Prediction HUD"

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
    local HUD = MitzuMPlus and MitzuMPlus.KeyPredictionHUD
    if HUD then
        HUD:SetEnabled(not HUD:IsEnabled())
    end
end
