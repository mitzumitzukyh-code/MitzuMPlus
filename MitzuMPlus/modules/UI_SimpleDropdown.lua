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
    text:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
    text:SetWidth(math.max(40, (width or 180) - 32))
    text:SetWordWrap(false)
    dropdown:SetScript("OnSizeChanged", function(_, w)
        text:SetWidth(math.max(40, w - 32))
    end)
    text:SetJustifyH("LEFT")
    if Theme and Theme.TEXT and Theme.TEXT.primary then
        text:SetTextColor(Theme.TEXT.primary.r, Theme.TEXT.primary.g, Theme.TEXT.primary.b, 1)
    else
        text:SetTextColor(0.933, 0.933, 0.933, 1)
    end
    text:SetText("Select...")
    dropdown._text = text
    
    local arrow = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if Theme and Theme.ApplyFont then Theme:ApplyFont(arrow,"normal",12) end
    arrow:SetPoint("RIGHT", dropdown, "RIGHT", -8, 0)
    -- ASCII-only glyph: WoW clients may render Unicode arrows as squares.
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

    dropdown:HookScript("OnHide", function(self)
        local openMenu = MitzuMPlus._simpleDropdownMenu
        if openMenu and openMenu._ownerDropdown == self then
            openMenu:Hide()
        end
    end)
    
    function dropdown:SetItems(newItems)
        self._items = newItems or {}
        local found = false
        for _, item in ipairs(self._items) do
            if item.value == self._selectedValue then found = true; break end
        end
        if not found then
            local first = self._items[1]
            self._selectedValue = first and first.value or nil
            self._text:SetText(first and first.text or "Select...")
        end
    end
    
    function dropdown:SetSelectedValue(value)
        for _, item in ipairs(self._items) do
            if item.value == value then
                self._selectedValue = value
                self._text:SetText(item.text or "")
                return true
            end
        end
        local first = self._items[1]
        self._selectedValue = first and first.value or nil
        self._text:SetText(first and first.text or "Select...")
        return false
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
    
    -- The Blizzard context-menu API can use a cursor/parent anchor that is
    -- outside the addon when the frame is scaled. Use the controlled menu
    -- below so every client opens it next to the field that was clicked.
    self:OpenSimpleDropdownMenuLegacy(dropdown, items)
end

function MitzuMPlus:OpenSimpleDropdownMenuLegacy(dropdown, items)
    if self._simpleDropdownMenu then
        self._simpleDropdownMenu:Hide()
        self._simpleDropdownMenu = nil
    end

    items = items or {}
    if #items == 0 then return end

    local ITEM_H = 24
    local MAX_VISIBLE = 8
    local visibleCount = math.min(#items, MAX_VISIBLE)

    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu._ownerDropdown = dropdown
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetToplevel(true)
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

    -- Cap the menu height. The old implementation used #items * 24, so a
    -- dungeon/character filter with many values escaped the addon window and
    -- looked like stray filter text below it.
    local maxWidth = math.max(100, dropdown:GetWidth() or 100)
    for _, item in ipairs(items) do
        local label = tostring(item.text or "")
        -- Byte length is only a rough estimate, but the clamp below makes it
        -- safe even with accented labels.
        maxWidth = math.max(maxWidth, math.min(420, #label * 7 + 28))
    end
    local footerH = #items > visibleCount and 14 or 0
    menu:SetWidth(maxWidth)
    menu:SetHeight(visibleCount * ITEM_H + 8 + footerH)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:EnableMouseWheel(#items > visibleCount)
    menu.offset = 0

    local rows = {}
    for slot = 1, visibleCount do
        local btn = CreateFrame("Button", nil, menu)
        btn:SetPoint("TOPLEFT", 4, -(slot - 1) * ITEM_H - 4)
        btn:SetPoint("TOPRIGHT", -4, -(slot - 1) * ITEM_H - 4)
        btn:SetHeight(ITEM_H)

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if Theme and Theme.ApplyFont then Theme:ApplyFont(fs, "normal", 13) end
        fs:SetPoint("LEFT", 6, 0)
        fs:SetPoint("RIGHT", -18, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        if Theme and Theme.TEXT and Theme.TEXT.primary then
            fs:SetTextColor(Theme.TEXT.primary.r, Theme.TEXT.primary.g, Theme.TEXT.primary.b, 1)
        else
            fs:SetTextColor(0.933, 0.933, 0.933, 1)
        end
        btn._label = fs

        local hover = btn:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints()
        hover:SetTexture("Interface\\Buttons\\WHITE8X8")
        local hc = Theme and Theme.BG and Theme.BG.rowHover
        hover:SetVertexColor(hc and hc.r or 0.18, hc and hc.g or 0.14,
            hc and hc.b or 0.05, hc and hc.a or 0.90)
        hover:Hide()
        btn._hover = hover

        btn:SetScript("OnEnter", function(self) self._hover:Show() end)
        btn:SetScript("OnLeave", function(self) self._hover:Hide() end)
        rows[slot] = btn
    end

    local scrollHint
    if #items > visibleCount then
        scrollHint = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if Theme and Theme.ApplyFont then Theme:ApplyFont(scrollHint, "normal", 10) end
        scrollHint:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -7, 5)
        scrollHint:SetTextColor(0.58, 0.55, 0.48, 1)
    end

    local function ClampOffset()
        local maxOffset = math.max(0, #items - visibleCount)
        menu.offset = math.max(0, math.min(maxOffset, tonumber(menu.offset) or 0))
    end

    local function RefreshRows()
        ClampOffset()
        for slot, btn in ipairs(rows) do
            local idx = menu.offset + slot
            local item = items[idx]
            if item then
                btn._index = idx
                btn._label:SetText(tostring(item.text or ""))
                btn:SetScript("OnClick", function(self)
                    local selected = items[self._index]
                    -- Hide the popup before refreshing the owning panel. Some
                    -- filter callbacks rebuild dropdown contents immediately;
                    -- doing that while this UIParent popup is still active can
                    -- make the click look ignored or close the wrong menu.
                    menu:Hide()
                    if selected and selected.func then
                        local ok, err = pcall(selected.func)
                        if not ok and MitzuMPlus and MitzuMPlus.Print then
                            MitzuMPlus:Print("Error al aplicar filtro: " .. tostring(err))
                        end
                    end
                end)
                btn:Show()
            else
                btn._index = nil
                btn:Hide()
            end
        end
        if scrollHint then
            local last = math.min(#items, menu.offset + visibleCount)
            scrollHint:SetText(string.format("%d-%d/%d", menu.offset + 1, last, #items))
        end
    end

    menu:SetScript("OnMouseWheel", function(self, delta)
        self.offset = (self.offset or 0) - delta
        RefreshRows()
    end)

    -- Open on the current selection when possible instead of always starting
    -- at the first item.
    local selectedValue = dropdown._selectedValue
    if selectedValue ~= nil then
        for i, raw in ipairs(dropdown._items or {}) do
            if raw.value == selectedValue then
                if i > visibleCount then menu.offset = i - visibleCount end
                break
            end
        end
    end
    RefreshRows()

    -- Anchor next to the control. Height is capped so SetClampedToScreen no
    -- longer has to move a giant menu to an unrelated area of the screen.
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)

    menu:SetScript("OnHide", function(self)
        if MitzuMPlus._simpleDropdownMenu == self then
            MitzuMPlus._simpleDropdownMenu = nil
        end
    end)

    menu:Show()
    self._simpleDropdownMenu = menu

    -- Do NOT close this popup from an OnUpdate mouse-over poll. Retail can
    -- report a one-frame gap while the pointer moves from the owner field to
    -- this UIParent child, which made filter menus disappear before the click
    -- reached an item. The menu now closes deterministically on selection or
    -- when another dropdown is opened.
end
