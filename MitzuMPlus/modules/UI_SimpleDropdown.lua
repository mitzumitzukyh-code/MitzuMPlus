local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local Theme = MitzuMPlus and MitzuMPlus.Theme

-- MouseIsOver ya no esta disponible como funcion global en todos los clientes.
-- Las regiones modernas exponen IsMouseOver() directamente.
local function IsMouseOverSafe(region)
    if not region then return false end
    if region.IsMouseOver then
        local ok, result = pcall(region.IsMouseOver, region)
        if ok then return result == true end
    end
    if _G.MouseIsOver then
        local ok, result = pcall(_G.MouseIsOver, region)
        if ok then return result == true end
    end
    return false
end

function MitzuMPlus:CreateSimpleDropdown(parent, width, items, onSelect)
    local dropdown = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    dropdown:SetSize(width or 180, 24)
    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    
    if Theme and Theme.BG and Theme.BG.input then
        dropdown:SetBackdropColor(Theme.BG.input.r, Theme.BG.input.g, Theme.BG.input.b, Theme.BG.input.a)
    else
        dropdown:SetBackdropColor(0.059, 0.059, 0.071, 0.97)
    end
    
    if Theme and Theme.BORDER and Theme.BORDER.panel then
        dropdown:SetBackdropBorderColor(Theme.BORDER.panel.r, Theme.BORDER.panel.g, Theme.BORDER.panel.b, 0.6)
    else
        dropdown:SetBackdropBorderColor(0.133, 0.133, 0.125, 1)
    end
    
    local text = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if Theme and Theme.ApplyFont then Theme:ApplyFont(text,"normal",13) end
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", -20, 0)
    text:SetJustifyH("LEFT")
    if Theme and Theme.TEXT and Theme.TEXT.primary then
        text:SetTextColor(Theme.TEXT.primary.r, Theme.TEXT.primary.g, Theme.TEXT.primary.b, 1)
    else
        text:SetTextColor(0.933, 0.933, 0.933, 1)
    end
    text:SetText("Select...")
    dropdown._text = text
    
    local arrow = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if Theme and Theme.ApplyFont then Theme:ApplyFont(arrow,"mono",12) end
    arrow:SetPoint("RIGHT", -4, 0)
    arrow:SetText("v")
    if Theme and Theme.TEXT and Theme.TEXT.dim then
        arrow:SetTextColor(Theme.TEXT.dim.r, Theme.TEXT.dim.g, Theme.TEXT.dim.b, 1)
    else
        arrow:SetTextColor(0.471, 0.471, 0.471, 1)
    end
    
    local button = CreateFrame("Button", nil, dropdown)
    button:SetAllPoints()
    dropdown._button = button
    
    dropdown._items = items or {}
    dropdown._selectedValue = nil
    dropdown._onSelect = onSelect
    
    button:SetScript("OnClick", function()
        MitzuMPlus:OpenSimpleDropdownMenu(dropdown)
    end)
    
    button:SetScript("OnEnter", function()
        if Theme and Theme.GOLD and Theme.GOLD.borderFocus then
            dropdown:SetBackdropBorderColor(Theme.GOLD.borderFocus.r, Theme.GOLD.borderFocus.g, Theme.GOLD.borderFocus.b, 0.9)
        else
            dropdown:SetBackdropBorderColor(0.471, 0.365, 0.125, 1)
        end
    end)
    
    button:SetScript("OnLeave", function()
        if Theme and Theme.BORDER and Theme.BORDER.panel then
            dropdown:SetBackdropBorderColor(Theme.BORDER.panel.r, Theme.BORDER.panel.g, Theme.BORDER.panel.b, 0.6)
        else
            dropdown:SetBackdropBorderColor(0.133, 0.133, 0.125, 1)
        end
    end)
    
    function dropdown:SetItems(newItems)
        self._items = newItems or {}
    end
    
    function dropdown:SetSelectedValue(value)
        self._selectedValue = value
        for _, item in ipairs(self._items) do
            if item.value == value then
                self._text:SetText(item.text or "")
                return
            end
        end
        self._text:SetText(self._items[1] and self._items[1].text or "Select...")
    end
    
    function dropdown:GetSelectedValue()
        return self._selectedValue
    end
    
    return dropdown
end

function MitzuMPlus:OpenSimpleDropdownMenu(dropdown)
    if not dropdown or not dropdown._items then return end
    
    local items = {}
    for _, item in ipairs(dropdown._items) do
        -- Copias locales: los handlers no deben depender de la variable de
        -- control del bucle cuando se ejecuten mas tarde.
        local itemText, itemValue = item.text, item.value
        items[#items + 1] = {
            text = itemText,
            func = function()
                dropdown._selectedValue = itemValue
                dropdown._text:SetText(itemText)
                if dropdown._onSelect then
                    dropdown._onSelect(itemValue, itemText)
                end
            end
        }
    end
    
    if Menu and Menu.OpenContextMenu then
        Menu.OpenContextMenu(dropdown, function(ownerRegion, rootDescription)
            for _, item in ipairs(items) do
                rootDescription:CreateButton(item.text, item.func)
            end
        end)
    else
        self:OpenSimpleDropdownMenuLegacy(dropdown, items)
    end
end

function MitzuMPlus:OpenSimpleDropdownMenuLegacy(dropdown, items)
    if self._simpleDropdownMenu then
        self._simpleDropdownMenu:Hide()
        self._simpleDropdownMenu = nil
    end
    
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("DIALOG")
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    
    if Theme and Theme.BG and Theme.BG.tooltip then
        menu:SetBackdropColor(Theme.BG.tooltip.r, Theme.BG.tooltip.g, Theme.BG.tooltip.b, Theme.BG.tooltip.a)
    else
        menu:SetBackdropColor(0.027, 0.027, 0.035, 0.98)
    end
    
    if Theme and Theme.BORDER and Theme.BORDER.window then
        menu:SetBackdropBorderColor(Theme.BORDER.window.r, Theme.BORDER.window.g, Theme.BORDER.window.b, 1)
    else
        menu:SetBackdropBorderColor(0.165, 0.157, 0.125, 1)
    end
    
    local maxWidth = 100
    for _, item in ipairs(items) do
        local w = (item.text and #item.text or 0) * 7 + 20
        if w > maxWidth then maxWidth = w end
    end
    
    menu:SetWidth(math.max(dropdown:GetWidth(), maxWidth))
    menu:SetHeight(#items * 24 + 8)
    
    local x, y = dropdown:GetCenter()
    local scale = dropdown:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    menu:SetPoint("TOP", UIParent, "BOTTOMLEFT", (x * scale) / uiScale, (y * scale) / uiScale - (dropdown:GetHeight() / 2))
    
    for i, item in ipairs(items) do
        local menuItem = item
        local btn = CreateFrame("Button", nil, menu)
        btn:SetPoint("TOPLEFT", 4, -(i-1) * 24 - 4)
        btn:SetPoint("TOPRIGHT", -4, -(i-1) * 24 - 4)
        btn:SetHeight(24)
        
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if Theme and Theme.ApplyFont then Theme:ApplyFont(fs,"normal",13) end
        fs:SetPoint("LEFT", 4, 0)
        fs:SetJustifyH("LEFT")
        fs:SetText(menuItem.text)
        if Theme and Theme.TEXT and Theme.TEXT.primary then
            fs:SetTextColor(Theme.TEXT.primary.r, Theme.TEXT.primary.g, Theme.TEXT.primary.b, 1)
        else
            fs:SetTextColor(0.933, 0.933, 0.933, 1)
        end

        -- Un Button sin BackdropTemplate no tiene SetBackdrop en Retail.
        -- El hover se dibuja con una textura propia, valida para cualquier
        -- tipo de Button y sin crear NineSlice/backdrops en cada entrada.
        local hover = btn:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints()
        hover:SetTexture("Interface\\Buttons\\WHITE8X8")
        local hc = Theme and Theme.BG and Theme.BG.rowHover
        hover:SetVertexColor(hc and hc.r or 0.18, hc and hc.g or 0.14,
            hc and hc.b or 0.05, hc and hc.a or 0.90)
        hover:Hide()
        btn._hover = hover
        
        btn:SetScript("OnEnter", function(self)
            self._hover:Show()
        end)
        
        btn:SetScript("OnLeave", function(self)
            self._hover:Hide()
        end)
        
        btn:SetScript("OnClick", function()
            if menuItem.func then menuItem.func() end
            menu:Hide()
        end)
    end
    
    menu:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        MitzuMPlus._simpleDropdownMenu = nil
    end)
    
    menu:Show()
    self._simpleDropdownMenu = menu
    
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            if not menu:IsShown() then return end
            menu:SetScript("OnUpdate", function(self)
                if not IsMouseOverSafe(self) and not IsMouseOverSafe(dropdown) then
                    self:Hide()
                end
            end)
        end)
    end
end
