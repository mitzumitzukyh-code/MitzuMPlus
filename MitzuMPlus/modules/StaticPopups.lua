-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - StaticPopups
-- Diálogos estáticos para confirmaciones y alertas
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local L = MitzuMPlus.L

local StaticPopupDialogs = _G.StaticPopupDialogs
if not StaticPopupDialogs then
    _G.StaticPopupDialogs = {}
    StaticPopupDialogs = _G.StaticPopupDialogs
end

StaticPopupDialogs["MITZUMPLUS_CONFIRM_DELETE"] = {
    text = L["POPUP_DELETE_RUN"],
    button1 = L["POPUP_BTN_DELETE"],
    button2 = L["POPUP_BTN_CANCEL"],
    OnAccept = function(self, runID)
        if MitzuMPlus and MitzuMPlus.DeleteRun then
            MitzuMPlus:DeleteRun(runID)
        end
        if MitzuMPlus and MitzuMPlus.RefreshHistorialTable then
            MitzuMPlus:RefreshHistorialTable()
        end
        if MitzuMPlus and MitzuMPlus.Footer and MitzuMPlus.Footer.UpdateStats then
            MitzuMPlus.Footer:UpdateStats()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["MITZUMPLUS_CONFIRM_CLEAR_ALL"] = {
    text = L["POPUP_CLEAR_ALL"],
    button1 = L["POPUP_BTN_CLEAR_ALL"],
    button2 = L["POPUP_BTN_CANCEL"],
    OnAccept = function()
        if MitzuMPlus and MitzuMPlus.db and MitzuMPlus.db.global then
            wipe(MitzuMPlus.db.global.runs)
            MitzuMPlus.db.global.nextRunID = 1
            -- El historial es la fuente de verdad de las marcas personales.
            -- Si se vacían las runs, conservar personalBests deja récords
            -- fantasma que impedirían detectar nuevas marcas correctamente.
            MitzuMPlus.db.global.personalBests = {}
        end
        if MitzuMPlus and MitzuMPlus.RefreshHistorialTable then
            MitzuMPlus:RefreshHistorialTable()
        end
        if MitzuMPlus and MitzuMPlus.Footer and MitzuMPlus.Footer.UpdateStats then
            MitzuMPlus.Footer:UpdateStats()
        end
        if MitzuMPlus and MitzuMPlus.ShowToast then
            MitzuMPlus:ShowToast(L["POPUP_HISTORY_CLEARED"], "ok")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["MITZUMPLUS_CONFIRM_RESET_CONFIG"] = {
    text = L["POPUP_RESET_CONFIG"],
    button1 = L["POPUP_BTN_RESET"],
    button2 = L["POPUP_BTN_CANCEL"],
    OnAccept = function()
        if MitzuMPlus and MitzuMPlus.db then
            MitzuMPlus.db:ResetProfile()

            -- Aplicar inmediatamente los valores que tienen estado runtime.
            local s = MitzuMPlus.db.profile and MitzuMPlus.db.profile.settings or {}
            if MitzuMPlus.Window then
                MitzuMPlus.Window:SetMovable(s.windowLocked ~= true)
                MitzuMPlus.Window:SetAlpha(tonumber(s.windowOpacity) or 1)
            end
            if MitzuMPlus.UpdateEscapeHandling then MitzuMPlus:UpdateEscapeHandling() end
            local fontTheme = MitzuMPlus.Colors or MitzuMPlus.Theme
            if fontTheme and fontTheme.RefreshFonts then
                fontTheme:RefreshFonts()
            end
            if MitzuMPlus.MitzuTracker and MitzuMPlus.MitzuTracker.ApplySettings then
                MitzuMPlus.MitzuTracker:ApplySettings()
            end

            local lib = LibStub and LibStub("LibDBIcon-1.0", true)
            local mm = s.minimapIcon
            if lib then
                if type(mm) == "table" and mm.hide == true then
                    lib:Hide("MitzuMPlus")
                else
                    lib:Show("MitzuMPlus")
                end
            end
        end
        if MitzuMPlus and MitzuMPlus.ShowToast then
            MitzuMPlus:ShowToast(L["POPUP_CONFIG_RESET"], "ok", 4, true)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["MITZUMPLUS_CONFIRM_DELETE_SELECTION"] = {
    text = L["POPUP_DELETE_SELECTION"],
    button1 = L["POPUP_BTN_DELETE"],
    button2 = L["POPUP_BTN_CANCEL"],
    OnAccept = function(self, selectedRuns)
        if not selectedRuns or not MitzuMPlus then return end
        
        local count = 0
        for runID in pairs(selectedRuns) do
            if MitzuMPlus.DeleteRun then
                MitzuMPlus:DeleteRun(runID, true)
                count = count + 1
            end
        end
        
        if MitzuMPlus.selectedRuns then
            wipe(MitzuMPlus.selectedRuns)
        end
        if MitzuMPlus.PersonalBest and MitzuMPlus.PersonalBest.RebuildFromHistory then
            MitzuMPlus.PersonalBest:RebuildFromHistory()
        end
        
        if MitzuMPlus.RefreshHistorialTable then
            MitzuMPlus:RefreshHistorialTable()
        end
        if MitzuMPlus.Footer and MitzuMPlus.Footer.UpdateStats then
            MitzuMPlus.Footer:UpdateStats()
        end
        
        if MitzuMPlus.ShowToast then
            MitzuMPlus:ShowToast(string.format(L["POPUP_RUNS_DELETED"], count), "ok")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
