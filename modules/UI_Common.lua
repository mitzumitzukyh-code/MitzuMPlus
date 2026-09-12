local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local Theme = MitzuMPlus and MitzuMPlus.Theme

_G.MitzuMPlusColors = {
    stone1 = (Theme and Theme.BG and Theme.BG.bottomBar) or { r = 0.035, g = 0.031, b = 0.024 },
    stone2 = (Theme and Theme.BG and Theme.BG.window)    or { r = 0.039, g = 0.039, b = 0.047 },
    stone3 = (Theme and Theme.BG and Theme.BG.panel)     or { r = 0.078, g = 0.078, b = 0.094 },
    stone4 = (Theme and Theme.BG and Theme.BG.button)    or { r = 0.118, g = 0.118, b = 0.137 },
    metal1 = (Theme and Theme.BG and (Theme.BG.btnPrim or Theme.BG.btnSecHover)) or { r = 0.200, g = 0.157, b = 0.063 },
    metal2 = (Theme and Theme.BG and (Theme.BG.btnSecHover or Theme.BG.btnPrim)) or { r = 0.180, g = 0.173, b = 0.137 },
    metal3 = (Theme and Theme.BG and Theme.BG.panelHeader) or { r = 0.055, g = 0.055, b = 0.067 },

    gold0  = (Theme and Theme.GOLD   and Theme.GOLD.border)       or { r = 0.290, g = 0.235, b = 0.094 },
    gold1  = (Theme and Theme.BORDER and Theme.BORDER.window)     or { r = 0.165, g = 0.157, b = 0.125 },
    gold2  = (Theme and Theme.GOLD   and Theme.GOLD.borderFocus)  or { r = 0.471, g = 0.365, b = 0.125 },
    gold3  = (Theme and Theme.GOLD   and Theme.GOLD.sectionHead)  or { r = 0.784, g = 0.627, b = 0.188 },
    gold4  = (Theme and Theme.GOLD   and Theme.GOLD.title)        or { r = 0.784, g = 0.627, b = 0.188 },
    gold5  = (Theme and Theme.GOLD   and Theme.GOLD.btnPrimText)  or { r = 0.969, g = 0.827, b = 0.439 },

    ok     = (Theme and Theme.STATUS and Theme.STATUS.ok)   or { r = 0.13, g = 0.87, b = 0.40 },
    bad    = (Theme and Theme.STATUS and Theme.STATUS.bad)  or { r = 0.93, g = 0.20, b = 0.20 },
    warn   = (Theme and Theme.STATUS and Theme.STATUS.warn) or { r = 1.00, g = 0.60, b = 0.13 },
    blue   = (Theme and Theme.STATUS and Theme.STATUS.info) or { r = 0.53, g = 0.73, b = 0.93 },
    purple = { r = 0.73, g = 0.53, b = 0.93 },

    t1 = (Theme and Theme.TEXT and Theme.TEXT.primary)   or { r = 0.933, g = 0.933, b = 0.933 },
    t2 = (Theme and Theme.TEXT and Theme.TEXT.secondary) or { r = 0.722, g = 0.722, b = 0.722 },
    t3 = (Theme and Theme.TEXT and Theme.TEXT.secondary) or { r = 0.722, g = 0.722, b = 0.722 },
    t4 = (Theme and Theme.TEXT and Theme.TEXT.dim)       or { r = 0.471, g = 0.471, b = 0.471 },
}

MitzuMPlus.WatermarkText = "By Mutzukyhs  |  MitzuMPlus M+ HISTORIAL"

-- ─────────────────────────────────────────────────────────────────────────────
-- UTILIDADES GLOBALES
-- ─────────────────────────────────────────────────────────────────────────────

--- Convierte segundos (número) a "MM:SS".
--- @param seconds number|nil
--- @return string
function MitzuMPlus:FormatTime(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then return "00:00" end
    -- completionTime llega en milisegundos desde Midnight; detectar y convertir
    if seconds > 86400 then
        seconds = math.floor(seconds / 1000)
    end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%02d:%02d", m, s)
end

--- Formatea un número grande (ej: 152400 → "152.4k").
--- @param n number
--- @return string
function MitzuMPlus:FormatNumber(n)
    n = tonumber(n) or 0
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 1000    then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n))
end

--- Devuelve r, g, b, 1 de una tabla de color.
local function C(c)
    return c.r, c.g, c.b, 1
end

-- Una sola linea. Se lo presta Widgets, que se carga antes; con respaldo por
-- si el orden del TOC cambiara.
local NoWrap = (MitzuMPlus.Widgets and MitzuMPlus.Widgets._NoWrap) or function(fs)
    if not fs then return end
    if fs.SetWordWrap then pcall(fs.SetWordWrap, fs, false) end
    if fs.SetMaxLines then pcall(fs.SetMaxLines, fs, 1) end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- DROPDOWN PERSONALIZADO — sin UIDropDownMenu (eliminado en 120000)
-- ─────────────────────────────────────────────────────────────────────────────
-- Uso:
--   local dd = MitzuMPlus:CreateDropdown(parent, width, defaultText, items, onSelect)
--   items = { { text = "Opción A", value = "a" }, ... }
--   onSelect(value, text)
--   dd:SetSelectedValue(value)
--   dd:GetSelectedValue()  →  value

local _activeDropdown = nil   -- solo uno abierto a la vez

local function CloseActiveDropdown()
    if _activeDropdown and _activeDropdown:IsShown() then
        _activeDropdown:Hide()
    end
    _activeDropdown = nil
end

function MitzuMPlus:CreateDropdown(parent, width, defaultText, items, onSelect)
    width = width or 160
    local ROW_H = 20
    local MAX_VISIBLE = 8

    -- ── botón principal ──────────────────────────────────────────────────────
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, 22)
    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(
        _G.MitzuMPlusColors.stone4.r,
        _G.MitzuMPlusColors.stone4.g,
        _G.MitzuMPlusColors.stone4.b, 1)
    btn:SetBackdropBorderColor(C(_G.MitzuMPlusColors.gold0))

    -- NOTA: hoy nadie llama a este CreateDropdown (los paneles usan
    -- Widgets:CreateDropdown o CreateSimpleDropdown). Se le aplica de todas
    -- formas la regla de una sola linea: si alguien lo reutiliza manana, no
    -- debe heredar el mismo fallo que tenian los otros dos.
    local labelFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if Theme and Theme.ApplyFont then Theme:ApplyFont(labelFS,"normal",13) end
    labelFS:SetPoint("LEFT", 6, 0)
    labelFS:SetWidth(width - 22)
    labelFS:SetJustifyH("LEFT")
    NoWrap(labelFS)
    labelFS:SetText(defaultText or "")
    labelFS:SetTextColor(C(_G.MitzuMPlusColors.t1))
    btn._labelFS = labelFS

    local arrowFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if Theme and Theme.ApplyFont then Theme:ApplyFont(arrowFS,"mono",12) end
    arrowFS:SetPoint("RIGHT", -5, 0)
    arrowFS:SetText("v")
    arrowFS:SetTextColor(C(_G.MitzuMPlusColors.gold3))

    -- ── panel desplegable ────────────────────────────────────────────────────
    local itemCount  = items and #items or 0
    local visRows    = math.min(itemCount, MAX_VISIBLE)
    local popupH     = visRows * ROW_H + 4
    local needsScroll = itemCount > MAX_VISIBLE

    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetFrameStrata("TOOLTIP")
    popup:SetWidth(width)
    popup:SetHeight(popupH)
    popup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    popup:SetBackdropColor(
        _G.MitzuMPlusColors.stone2.r,
        _G.MitzuMPlusColors.stone2.g,
        _G.MitzuMPlusColors.stone2.b, 0.98)
    popup:SetBackdropBorderColor(C(_G.MitzuMPlusColors.gold1))
    popup:Hide()
    popup._owner = btn

    -- scroll frame dentro del popup
    local sf = CreateFrame("ScrollFrame", nil, popup)
    sf:SetPoint("TOPLEFT", 2, -2)
    sf:SetPoint("BOTTOMRIGHT", -2, 2)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(width - 4, itemCount * ROW_H)
    sf:SetScrollChild(content)

    if needsScroll then
        popup:EnableMouseWheel(true)
        popup:SetScript("OnMouseWheel", function(_, delta)
            local cur = sf:GetVerticalScroll()
            local max = sf:GetVerticalScrollRange()
            sf:SetVerticalScroll(math.max(0, math.min(max, cur - delta * ROW_H)))
        end)
    end

    -- filas del popup
    local function BuildRows(newItems)
        -- limpiar filas viejas
        for _, child in ipairs({ content:GetChildren() }) do child:Hide() end

        newItems = newItems or {}
        content:SetSize(width - 4, #newItems * ROW_H)

        for i, item in ipairs(newItems) do
            local row = CreateFrame("Button", nil, content, "BackdropTemplate")
            row:SetSize(width - 4, ROW_H)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            row:SetBackdropColor(0, 0, 0, 0)

            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            if Theme and Theme.ApplyFont then Theme:ApplyFont(fs,"normal",13) end
            fs:SetPoint("LEFT", 6, 0)
            fs:SetWidth(width - 14)
            fs:SetJustifyH("LEFT")
            NoWrap(fs)
            fs:SetText(item.text or "")
            fs:SetTextColor(C(_G.MitzuMPlusColors.t2))

            row:SetScript("OnEnter", function(self)
                self:SetBackdropColor(
                    _G.MitzuMPlusColors.metal1.r,
                    _G.MitzuMPlusColors.metal1.g,
                    _G.MitzuMPlusColors.metal1.b, 0.8)
                fs:SetTextColor(C(_G.MitzuMPlusColors.gold5))
            end)
            row:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0, 0, 0, 0)
                fs:SetTextColor(C(_G.MitzuMPlusColors.t2))
            end)
            row:SetScript("OnClick", function()
                btn._labelFS:SetText(item.text or "")
                btn._selectedValue = item.value
                CloseActiveDropdown()
                if onSelect then
                    pcall(onSelect, item.value, item.text)
                end
            end)
        end
    end

    BuildRows(items)

    -- abrir / cerrar al hacer click en el botón principal
    btn:SetScript("OnClick", function()
        if popup:IsShown() then
            CloseActiveDropdown()
        else
            CloseActiveDropdown()
            -- posicionar debajo del botón
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
            popup:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -1)
            local newH = math.min(#items, MAX_VISIBLE) * ROW_H + 4
            popup:SetHeight(math.max(newH, ROW_H + 4))
            popup:Show()
            _activeDropdown = popup
        end
    end)

    -- cerrar si se hace click fuera
    popup:SetScript("OnHide", function()
        if _activeDropdown == popup then _activeDropdown = nil end
    end)

    -- ── API pública del dropdown ─────────────────────────────────────────────
    btn._popup = popup

    function btn:SetItems(newItems, newDefault)
        items = newItems or {}
        BuildRows(items)
        if newDefault ~= nil then
            self._labelFS:SetText(newDefault)
        end
        local newH = math.min(#items, MAX_VISIBLE) * ROW_H + 4
        popup:SetHeight(math.max(newH, ROW_H + 4))
        content:SetSize(width - 4, #items * ROW_H)
    end

    function btn:SetSelectedValue(val)
        self._selectedValue = val
        for _, item in ipairs(items or {}) do
            if item.value == val then
                self._labelFS:SetText(item.text or "")
                return
            end
        end
    end

    function btn:SetSelectedText(text)
        self._labelFS:SetText(text or "")
    end

    function btn:GetSelectedValue()
        return self._selectedValue
    end

    return btn
end

-- ─────────────────────────────────────────────────────────────────────────────
-- VENTANA PRINCIPAL
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:CreateWindow(name, width, height, title, subtitle)
    local uiParent = UIParent  -- API-6 FIX: GetUIParent() deprecated → UIParent global

    local f = CreateFrame("Frame", name, uiParent, "BackdropTemplate")
    if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end

    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:Hide()
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")

    if Theme and Theme.StyleWindow then
        Theme:StyleWindow(f)
    else
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        f:SetBackdropColor(C(_G.MitzuMPlusColors.stone2))
        f:SetBackdropBorderColor(C(_G.MitzuMPlusColors.gold1))
    end

    -- titlebar
    local titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    if not titleBar.SetBackdrop then Mixin(titleBar, BackdropTemplateMixin) end
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetHeight(44)
    if Theme and Theme.StyleTitlebar then
        Theme:StyleTitlebar(titleBar)
    else
        titleBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        titleBar:SetBackdropColor(0.13, 0.10, 0.05, 1)
    end

    local t = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 12, -8)
    t:SetText(title or "")
    if Theme and Theme.GOLD and Theme.GOLD.title then
        t:SetTextColor(Theme.GOLD.title.r, Theme.GOLD.title.g, Theme.GOLD.title.b, 1)
    else
        t:SetTextColor(C(_G.MitzuMPlusColors.gold4))
    end

    local st = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    st:SetPoint("TOPLEFT", 12, -26)
    st:SetText(subtitle or "")
    if Theme and Theme.TEXT and Theme.TEXT.secondary then
        st:SetTextColor(Theme.TEXT.secondary.r, Theme.TEXT.secondary.g, Theme.TEXT.secondary.b, 1)
    else
        st:SetTextColor(C(_G.MitzuMPlusColors.t3))
    end

    -- botón cerrar
    local close = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    if not close.SetBackdrop then Mixin(close, BackdropTemplateMixin) end
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    if Theme and Theme.BG and Theme.BG.button then
        close:SetBackdropColor(
            Theme.BG.button.r, Theme.BG.button.g,
            Theme.BG.button.b, Theme.BG.button.a)
    else
        close:SetBackdropColor(C(_G.MitzuMPlusColors.stone3))
    end
    if Theme and Theme.BORDER and Theme.BORDER.panel then
        close:SetBackdropBorderColor(
            Theme.BORDER.panel.r, Theme.BORDER.panel.g,
            Theme.BORDER.panel.b, 0.8)
    else
        close:SetBackdropBorderColor(C(_G.MitzuMPlusColors.gold0))
    end

    local cx = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cx:SetPoint("CENTER")
    cx:SetText("X")
    if Theme and Theme.TEXT and Theme.TEXT.primary then
        cx:SetTextColor(Theme.TEXT.primary.r, Theme.TEXT.primary.g, Theme.TEXT.primary.b, 1)
    else
        cx:SetTextColor(C(_G.MitzuMPlusColors.gold3))
    end
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C(_G.MitzuMPlusColors.bad))
        cx:SetTextColor(C(_G.MitzuMPlusColors.bad))
    end)
    close:SetScript("OnLeave", function(self)
        if Theme and Theme.BORDER and Theme.BORDER.panel then
            self:SetBackdropBorderColor(Theme.BORDER.panel.r, Theme.BORDER.panel.g, Theme.BORDER.panel.b, 0.8)
        else
            self:SetBackdropBorderColor(C(_G.MitzuMPlusColors.gold0))
        end
        cx:SetTextColor(C(_G.MitzuMPlusColors.gold3))
    end)

    -- footer / watermark
    local footer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    if not footer.SetBackdrop then Mixin(footer, BackdropTemplateMixin) end
    footer:SetPoint("BOTTOMLEFT",  0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    footer:SetHeight(28)
    footer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    if Theme and Theme.BG and Theme.BG.bottomBar then
        footer:SetBackdropColor(
            Theme.BG.bottomBar.r, Theme.BG.bottomBar.g,
            Theme.BG.bottomBar.b, Theme.BG.bottomBar.a)
    else
        footer:SetBackdropColor(C(_G.MitzuMPlusColors.stone1))
    end

    local wm = footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wm:SetPoint("RIGHT", -10, 0)
    wm:SetText(self.WatermarkText)
    if Theme and Theme.TEXT and Theme.TEXT.watermark then
        wm:SetTextColor(
            Theme.TEXT.watermark.r, Theme.TEXT.watermark.g,
            Theme.TEXT.watermark.b, Theme.TEXT.watermark.a)
    else
        wm:SetTextColor(_G.MitzuMPlusColors.t4.r, _G.MitzuMPlusColors.t4.g, _G.MitzuMPlusColors.t4.b, 0.7)
    end

    -- tecla Escape cierra la ventana
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then self:Hide() end
    end)

    f.titleBar  = titleBar
    f.btnClose  = close
    f.footer    = footer
    return f
end

-- ─────────────────────────────────────────────────────────────────────────────
-- PANEL
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:CreatePanel(parent, x, y, width, height, headerText)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if not p.SetBackdrop then Mixin(p, BackdropTemplateMixin) end
    p:SetSize(width, height)
    p:SetPoint("TOPLEFT", x, y)

    if Theme and Theme.StylePanel then
        Theme:StylePanel(p)
    else
        p:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        p:SetBackdropColor(C(_G.MitzuMPlusColors.stone3))
        p:SetBackdropBorderColor(C(_G.MitzuMPlusColors.gold0))
    end

    if headerText and headerText ~= "" then
        local h = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", 10, -8)
        h:SetText((headerText or ""):upper())
        if Theme and Theme.GOLD and Theme.GOLD.sectionHead then
            h:SetTextColor(Theme.GOLD.sectionHead.r, Theme.GOLD.sectionHead.g, Theme.GOLD.sectionHead.b, 1)
        else
            h:SetTextColor(C(_G.MitzuMPlusColors.gold3))
        end
        p.header = h
    end

    return p
end

-- ─────────────────────────────────────────────────────────────────────────────
-- BOTÓN
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:CreateButton(parent, label, style, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    if not b.SetBackdrop then Mixin(b, BackdropTemplateMixin) end
    b:SetHeight((style == "sm") and 22 or 24)
    b:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    local txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if Theme and Theme.ApplyFont then Theme:ApplyFont(txt,"normal",13) end
    txt:SetPoint("CENTER")
    txt:SetText((label or ""):upper())
    if Theme and Theme.GOLD and Theme.GOLD.btnText then
        txt:SetTextColor(Theme.GOLD.btnText.r, Theme.GOLD.btnText.g, Theme.GOLD.btnText.b, 1)
    else
        txt:SetTextColor(C(_G.MitzuMPlusColors.gold3))
    end
    b.text = txt

    if Theme and Theme.StyleButton then
        Theme:StyleButton(b, style == "primary")
    else
        b:SetBackdropColor(C(_G.MitzuMPlusColors.stone4))
        b:SetBackdropBorderColor(C(_G.MitzuMPlusColors.gold0))
    end

    if style == "primary" then
        if Theme and Theme.GOLD and Theme.GOLD.btnPrimText then
            txt:SetTextColor(Theme.GOLD.btnPrimText.r, Theme.GOLD.btnPrimText.g, Theme.GOLD.btnPrimText.b, 1)
        else
            txt:SetTextColor(C(_G.MitzuMPlusColors.gold5))
        end
    elseif style == "bad" then
        txt:SetTextColor(C(_G.MitzuMPlusColors.bad))
    elseif style == "ok" then
        txt:SetTextColor(C(_G.MitzuMPlusColors.ok))
    elseif style == "dis" then
        txt:SetTextColor(C(_G.MitzuMPlusColors.t4))
        b:Disable()
    end

    if not (Theme and Theme.StyleButton) then
        b:SetScript("OnEnter", function()
            if b:IsEnabled() then
                b:SetBackdropBorderColor(C(_G.MitzuMPlusColors.gold3))
            end
        end)
        b:SetScript("OnLeave", function()
            if b:IsEnabled() then
                b:SetBackdropBorderColor(C(_G.MitzuMPlusColors.gold0))
            end
        end)
    end

    b:SetScript("OnClick", function()
        if onClick then pcall(onClick) end
    end)

    return b
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TOAST
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:ShowToast(message, toastType, duration)
    if not self.db or not self.db.profile or not self.db.profile.settings
       or not self.db.profile.settings.showToasts then
        return
    end

    duration = duration or 3
    message  = message or ""
    if #message > 80 then message = message:sub(1, 77) .. "..." end

    if not self._toastFrame then
        local uiParent = UIParent  -- API-6 FIX: GetUIParent() deprecated → UIParent global
        local tf = CreateFrame("Frame", nil, uiParent, "BackdropTemplate")
        if not tf.SetBackdrop then Mixin(tf, BackdropTemplateMixin) end
        tf:SetSize(360, 44)
        tf:SetPoint("BOTTOMRIGHT", uiParent, "BOTTOMRIGHT", -22, 22)
        tf:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 2,
        })
        tf:SetFrameStrata("DIALOG")

        local t2 = tf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t2:SetPoint("CENTER")
        t2:SetWidth(340)
        t2:SetJustifyH("CENTER")
        t2:SetWordWrap(false)
        t2:SetTextColor(C(_G.MitzuMPlusColors.t1))
        tf.text = t2

        tf:Hide()
        self._toastFrame = tf
    end

    local tf = self._toastFrame
    tf.text:SetText(message)

    if toastType == "ok" then
        if Theme and Theme.STATUS and Theme.STATUS.okBg then
            tf:SetBackdropColor(Theme.STATUS.okBg.r, Theme.STATUS.okBg.g, Theme.STATUS.okBg.b, 0.95)
        else
            tf:SetBackdropColor(0.04, 0.12, 0.06, 0.95)
        end
        tf:SetBackdropBorderColor(C(_G.MitzuMPlusColors.ok))
        tf.text:SetTextColor(C(_G.MitzuMPlusColors.ok))
    else
        if Theme and Theme.STATUS and Theme.STATUS.badBg then
            tf:SetBackdropColor(Theme.STATUS.badBg.r, Theme.STATUS.badBg.g, Theme.STATUS.badBg.b, 0.95)
        else
            tf:SetBackdropColor(0.12, 0.04, 0.04, 0.95)
        end
        tf:SetBackdropBorderColor(C(_G.MitzuMPlusColors.bad))
        tf.text:SetTextColor(C(_G.MitzuMPlusColors.bad))
    end

    tf:Show()

    if tf._toastTimer then
        tf._toastTimer:Cancel()
        tf._toastTimer = nil
    end

    if C_Timer and C_Timer.NewTimer then
        tf._toastTimer = C_Timer.NewTimer(duration, function()
            tf:Hide()
        end)
    end
end
