-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - MinimapIcon
-- Icono de minimapa con menú contextual
--
-- FIX: `Theme` se usaba en OnTooltipShow sin haber sido declarado en este
--   archivo. Usa MitzuMPlus.Theme si está disponible; si no, fallback hardcodeado.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

-- FIX: declarar Theme localmente para este módulo
local Theme = MitzuMPlus and MitzuMPlus.Theme

-- ─────────────────────────────────────────────────────────────────────────────
-- INICIALIZAR ICONO DE MINIMAP
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:InitMinimapIcon()
    -- Intentar obtener Theme si aún no estaba disponible al cargar el archivo
    if not Theme and MitzuMPlus.Theme then
        Theme = MitzuMPlus.Theme
    end

    if not self.db then return end

    local ok, LDB = pcall(function() return LibStub("LibDataBroker-1.1") end)
    if not ok or not LDB then return end

    local ok2, iconLib = pcall(function() return LibStub("LibDBIcon-1.0") end)
    if not ok2 or not iconLib then return end

    if self._ldbObject then return end

    self._ldbObject = LDB:NewDataObject("MitzuMPlus_Historial", {
        type = "data source",
        text = "MitzuMPlus M+",
        icon = "Interface\\AddOns\\MitzuMPlus_Historial\\Media\\Icons\\10_minimap",

        OnClick = function(anchorFrame, button)
            if button == "LeftButton" then
                if MitzuMPlus.ToggleWindow then MitzuMPlus:ToggleWindow() end
            elseif button == "RightButton" then
                MitzuMPlus:ShowMinimapMenu(anchorFrame)
            end
        end,

        OnTooltipShow = function(tt)
            -- Theme puede haberse asignado después de que este closure se creó
            local t = MitzuMPlus.Theme or Theme
            local gc = t and t.GOLD and t.GOLD.title
                       or { r = 0.784, g = 0.627, b = 0.188 }
            tt:AddLine("MitzuMPlus M+ Historial", gc.r, gc.g, gc.b)

            local total = 0
            if MitzuMPlus.db and MitzuMPlus.db.global and MitzuMPlus.db.global.runs then
                for _ in pairs(MitzuMPlus.db.global.runs) do
                    total = total + 1
                end
            end
            tt:AddLine(string.format("%d runs registradas", total), 1, 1, 1)

            if _G.MitzuMPlusCurrentRun then
                local run = _G.MitzuMPlusCurrentRun
                tt:AddLine(
                    string.format("Run activa: %s +%d",
                        run.dungeonName or "?", run.keyLevel or 0),
                    0.13, 0.87, 0.40)
            end

            tt:AddLine(" ")
            tt:AddLine("Click izquierdo: Historial", 0.7, 0.7, 0.7)
            tt:AddLine("Click derecho: Menú", 0.7, 0.7, 0.7)
        end,
    })

    -- Asegurar que minimapIcon existe en profile settings
    if not self.db.profile.settings.minimapIcon then
        self.db.profile.settings.minimapIcon = { hide = false }
    end

    iconLib:Register(
        "MitzuMPlus_Historial",
        self._ldbObject,
        self.db.profile.settings.minimapIcon
    )
end

-- ─────────────────────────────────────────────────────────────────────────────
-- MENÚ CONTEXTUAL (Midnight Menu API + fallback propio)
-- ─────────────────────────────────────────────────────────────────────────────

local function GetMenuItems()
    return {
        { text = "Ver historial",   fn = function() if MitzuMPlus.ToggleWindow then MitzuMPlus:ToggleWindow() end end },
        { sep = true },
        { text = "Activar captura", fn = function()
            if InCombatLockdown and InCombatLockdown() then
                if MitzuMPlus.Print then
                    MitzuMPlus:Print("[!] No puedes activar la captura en combate.")
                end
                return
            end
            if MitzuMPlus.RegisterCoreEvents then MitzuMPlus:RegisterCoreEvents() end
        end },
        { sep = true },
        { text = "Configuracion", fn = function()
            if MitzuMPlus.ShowTab then
                MitzuMPlus:ShowTab("settings")
            elseif MitzuMPlus.ShowConfig then
                MitzuMPlus:ShowConfig()
            end
        end },
        { text = "Ayuda", fn = function() MitzuMPlus:HandleSlashCommand("help") end },
    }
end

function MitzuMPlus:ShowMinimapMenu(anchorFrame)
    if Menu and Menu.OpenContextMenu then
        local ok = pcall(function()
            Menu.OpenContextMenu(anchorFrame, function(ownerRegion, rootDescription)
                rootDescription:CreateTitle("MitzuMPlus M+")
                for _, item in ipairs(GetMenuItems()) do
                    if item.sep then
                        rootDescription:CreateDivider()
                    else
                        rootDescription:CreateButton(item.text, item.fn)
                    end
                end
            end)
        end)
        if ok then return end
    end

    self:_ShowMinimapMenuFallback(anchorFrame)
end

function MitzuMPlus:_ShowMinimapMenuFallback(anchorFrame)
    if not self._mmMenu then
        local ITEM_H = 22
        local MENU_W = 190
        local items  = GetMenuItems()

        local menuH = 6
        for _, item in ipairs(items) do
            menuH = menuH + (item.sep and 8 or ITEM_H + 2)
        end

        local menu = CreateFrame("Frame", "MitzuMPlusMMMenu", UIParent, "BackdropTemplate")
        if not menu.SetBackdrop then Mixin(menu, BackdropTemplateMixin) end
        menu:SetSize(MENU_W, menuH)
        menu:SetFrameStrata("TOOLTIP")
        menu:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })

        local col = _G.MitzuMPlusColors or {}
        menu:SetBackdropColor(
            (col.stone2 and col.stone2.r) or 0.04,
            (col.stone2 and col.stone2.g) or 0.04,
            (col.stone2 and col.stone2.b) or 0.05, 0.98)
        menu:SetBackdropBorderColor(
            (col.gold1 and col.gold1.r) or 0.165,
            (col.gold1 and col.gold1.g) or 0.157,
            (col.gold1 and col.gold1.b) or 0.125, 1)
        menu:Hide()

        local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 8, -5)
        title:SetText("MitzuMPlus M+")
        title:SetTextColor(
            (col.gold3 and col.gold3.r) or 0.784,
            (col.gold3 and col.gold3.g) or 0.627,
            (col.gold3 and col.gold3.b) or 0.188)

        local y = -20
        for _, item in ipairs(items) do
            if item.sep then
                local line = menu:CreateTexture(nil, "OVERLAY")
                line:SetPoint("TOPLEFT",  8,  y - 1)
                line:SetPoint("TOPRIGHT", -8, y - 1)
                line:SetHeight(1)
                line:SetColorTexture(
                    (col.gold0 and col.gold0.r) or 0.29,
                    (col.gold0 and col.gold0.g) or 0.24,
                    (col.gold0 and col.gold0.b) or 0.09, 0.5)
                y = y - 8
            else
                local local_fn = item.fn
                local row = CreateFrame("Button", nil, menu, "BackdropTemplate")
                if not row.SetBackdrop then Mixin(row, BackdropTemplateMixin) end
                row:SetSize(MENU_W - 8, ITEM_H)
                row:SetPoint("TOPLEFT", 4, y)
                row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
                row:SetBackdropColor(0, 0, 0, 0)

                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fs:SetPoint("LEFT", 6, 0)
                fs:SetWidth(MENU_W - 20)
                fs:SetJustifyH("LEFT")
                fs:SetText(item.text)
                fs:SetTextColor(
                    (col.t2 and col.t2.r) or 0.72,
                    (col.t2 and col.t2.g) or 0.72,
                    (col.t2 and col.t2.b) or 0.72)

                row:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(
                        (col.metal1 and col.metal1.r) or 0.20,
                        (col.metal1 and col.metal1.g) or 0.16,
                        (col.metal1 and col.metal1.b) or 0.06, 0.8)
                    fs:SetTextColor(
                        (col.gold5 and col.gold5.r) or 0.97,
                        (col.gold5 and col.gold5.g) or 0.83,
                        (col.gold5 and col.gold5.b) or 0.44)
                end)
                row:SetScript("OnLeave", function(self)
                    self:SetBackdropColor(0, 0, 0, 0)
                    fs:SetTextColor(
                        (col.t2 and col.t2.r) or 0.72,
                        (col.t2 and col.t2.g) or 0.72,
                        (col.t2 and col.t2.b) or 0.72)
                end)
                row:SetScript("OnClick", function()
                    menu:Hide()
                    if local_fn then
                        local ok, err = pcall(local_fn)
                        if not ok and MitzuMPlus and MitzuMPlus.Print then
                            MitzuMPlus:Print("Error al ejecutar acción: " .. tostring(err))
                        end
                    end
                end)

                y = y - ITEM_H - 2
            end
        end

        -- Backdrop transparente para cerrar al hacer click fuera.
        -- FIX BUG-8: el backdrop debe estar en "DIALOG" (mayor que HIGH, menor que
        -- TOOLTIP) para que intercepte todos los clicks que NO sean sobre el propio menú.
        -- Con "HIGH" el menú (TOOLTIP) lo tapaba y el click-fuera-para-cerrar no funcionaba.
        local backdrop = CreateFrame("Frame", nil, UIParent)
        backdrop:SetAllPoints()
        backdrop:SetFrameStrata("DIALOG")
        backdrop:EnableMouse(true)
        backdrop:Hide()
        backdrop:SetScript("OnMouseDown", function()
            menu:Hide()
            backdrop:Hide()
        end)
        menu._backdrop = backdrop

        menu:SetScript("OnShow", function() backdrop:Show() end)
        menu:SetScript("OnHide", function() backdrop:Hide() end)

        self._mmMenu = menu
    end

    local menu = self._mmMenu
    if menu:IsShown() then
        menu:Hide()
        return
    end

    menu:ClearAllPoints()
    if anchorFrame then
        menu:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 2)
    else
        menu:SetPoint("CENTER")
    end
    menu:Show()
end
