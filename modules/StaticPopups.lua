-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - StaticPopups
-- Diálogos estáticos para confirmaciones y alertas
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local StaticPopupDialogs = _G.StaticPopupDialogs
if not StaticPopupDialogs then
    _G.StaticPopupDialogs = {}
    StaticPopupDialogs = _G.StaticPopupDialogs
end

StaticPopupDialogs["MITZUMPLUS_CONFIRM_DELETE"] = {
    text = "¿Eliminar run #%d? Esta acción no se puede deshacer.",
    button1 = "Eliminar",
    button2 = "Cancelar",
    OnAccept = function(self, runID)
        if MitzuMPlus and MitzuMPlus.DeleteRun then
            MitzuMPlus:DeleteRun(runID)
        end
        if MitzuMPlus and MitzuMPlus.RefreshHistorialTable then
            MitzuMPlus:RefreshHistorialTable()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["MITZUMPLUS_CONFIRM_CLEAR_ALL"] = {
    text = "¿Borrar el historial de partidas? Se eliminarán las partidas guardadas y los récords personales calculados a partir de ellas. Las rutas y los ajustes se conservarán. Esta acción no se puede deshacer.",
    button1 = "|cFFFF4444Borrar historial|r",
    button2 = "Cancelar",
    OnAccept = function()
        local removed=0
        if MitzuMPlus and MitzuMPlus.DataManager and MitzuMPlus.DataManager.ClearRunHistory then
            removed=MitzuMPlus.DataManager:ClearRunHistory()
        end
        if MitzuMPlus and MitzuMPlus.PanelHistorial then
            MitzuMPlus.PanelHistorial.selectedRunID=nil
            if MitzuMPlus.PanelHistorial.selectedRunIDs then wipe(MitzuMPlus.PanelHistorial.selectedRunIDs) end
        end
        if MitzuMPlus and MitzuMPlus.RefreshHistorialTable then
            MitzuMPlus:RefreshHistorialTable()
        end
        if MitzuMPlus and MitzuMPlus.ShowToast then
            MitzuMPlus:ShowToast(string.format("Historial borrado: %d partidas.",removed), "ok")
        end
        if MitzuMPlus and MitzuMPlus.Footer and MitzuMPlus.Footer.UpdateStats then MitzuMPlus.Footer:UpdateStats() end
        if MitzuMPlus and MitzuMPlus.PanelConfig and MitzuMPlus.PanelConfig.Refresh then MitzuMPlus.PanelConfig:Refresh() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["MITZUMPLUS_CONFIRM_RESET_CONFIG"] = {
    text = "¿Restablecer todos los ajustes? Las partidas guardadas, sus notas y las rutas se conservarán. La interfaz se recargará para aplicar los valores por defecto.",
    button1 = "Restablecer",
    button2 = "Cancelar",
    OnAccept = function()
        if MitzuMPlus and MitzuMPlus.db then
            -- Las rutas son datos del usuario, no ajustes visuales. ResetProfile
            -- vacía todo el perfil, así que se conservan explícitamente.
            local routes=MitzuMPlus.db.profile and MitzuMPlus.db.profile.routes
            MitzuMPlus.db:ResetProfile()
            if routes and MitzuMPlus.db.profile then MitzuMPlus.db.profile.routes=routes end
        end
        if MitzuMPlus and MitzuMPlus.ShowToast then
            MitzuMPlus:ShowToast("Configuración restablecida.", "ok")
        end
        if ReloadUI then ReloadUI() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["MITZUMPLUS_CONFIRM_DELETE_SELECTION"] = {
    text = "¿Eliminar %d runs seleccionadas? Esta acción no se puede deshacer.",
    button1 = "Eliminar",
    button2 = "Cancelar",
    OnAccept = function(self, selectedRuns)
        if not selectedRuns or not MitzuMPlus then return end
        
        local count = 0
        for runID in pairs(selectedRuns) do
            if MitzuMPlus.DeleteRun then
                MitzuMPlus:DeleteRun(runID)
                count = count + 1
            end
        end
        
        if MitzuMPlus.selectedRuns then
            wipe(MitzuMPlus.selectedRuns)
        end
        
        if MitzuMPlus.RefreshHistorialTable then
            MitzuMPlus:RefreshHistorialTable()
        end
        
        if MitzuMPlus.ShowToast then
            MitzuMPlus:ShowToast(string.format("%d runs eliminadas", count), "ok")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
