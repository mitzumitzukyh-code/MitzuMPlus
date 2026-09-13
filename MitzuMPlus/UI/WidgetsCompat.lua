-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - UI/WidgetsCompat.lua  (FIX v2)
-- Reemplaza Widgets.lua.
-- API idéntica al Widgets.lua original para que los paneles no cambien.
--
-- BUG CORREGIDO: CreateScrollFrame usaba UIPanelScrollFrameTemplate que
--   sobreescribía los SetScript/HookScript de los paneles → paneles blancos.
--   Ahora crea un ScrollFrame plano + scrollbar manual, igual que el original.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local Widgets = {}
MitzuMPlus.Widgets = Widgets

local function C() return MitzuMPlus.Colors or MitzuMPlus.Theme end
local function ApplyReadableFont(region, fontType, size)
    local theme=C()
    if region and theme and theme.ApplyFont then theme:ApplyFont(region,fontType or "normal",size) end
end

-- ─────────────────────────────────────────────────────────────────────────
-- BUTTON  →  UIPanelButtonTemplate
-- ─────────────────────────────────────────────────────────────────────────

function Widgets:CreateButton(parent, text, width, height, style)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 120, height or 25)
    btn:SetText(text or "")
    local fs = btn:GetFontString()
    if fs then
        ApplyReadableFont(fs,"normal",13)
        if     style == "bad"     then fs:SetTextColor(0.93, 0.30, 0.30, 1)
        elseif style == "ok"      then fs:SetTextColor(0.30, 0.90, 0.45, 1)
        elseif style == "primary" then fs:SetTextColor(1.00, 0.82, 0.00, 1)
        end
    end
    -- Alias que el panel Historial llama en los botones de paginación
    btn.SetButtonText = function(self, t) self:SetText(t) end
    return btn
end

-- ─────────────────────────────────────────────────────────────────────────
-- TOGGLE  →  UICheckButtonTemplate
-- API: :SetState(bool)  /  .onChange callback
-- ─────────────────────────────────────────────────────────────────────────

function Widgets:CreateToggle(parent, defaultState, onChange)
    local btn = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    btn:SetSize(26, 26)
    btn:SetChecked(defaultState or false)
    btn.onChange = onChange
    btn:SetScript("OnClick", function(self)
        if self.onChange then self.onChange(self:GetChecked()) end
    end)
    btn.SetState = function(self, state) self:SetChecked(state) end
    return btn
end

-- ─────────────────────────────────────────────────────────────────────────
-- SLIDER  →  OptionsSliderTemplate
-- ─────────────────────────────────────────────────────────────────────────

function Widgets:CreateSlider(parent, min, max, defaultValue, onChange)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetMinMaxValues(min or 0, max or 100)
    s:SetValue(defaultValue or min or 0)
    s:SetValueStep(1)
    s:SetWidth(160)
    local n = s:GetName()
    if n then
        if _G[n.."Low"]  then _G[n.."Low"]:SetText(tostring(min or 0))   end
        if _G[n.."High"] then _G[n.."High"]:SetText(tostring(max or 100)) end
    end
    s.onChange = onChange
    s:SetScript("OnValueChanged", function(self, v)
        if self.onChange then self.onChange(math.floor(v)) end
    end)
    return s
end

-- ─────────────────────────────────────────────────────────────────────────
-- NUMBER INPUT
-- ─────────────────────────────────────────────────────────────────────────

local _numN = 0
function Widgets:CreateNumberInput(parent, minVal, maxVal, defaultValue, onChange)
    _numN = _numN + 1
    local f  = CreateFrame("Frame", nil, parent)
    f:SetSize(58, 24)
    local eb = CreateFrame("EditBox", "MitzuNI"..(_numN), f, "InputBoxTemplate")
    eb:SetAllPoints(f)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(3)
    ApplyReadableFont(eb,"mono",13)
    eb:SetText(tostring(defaultValue or minVal or 0))
    eb.minVal = minVal or 0 ; eb.maxVal = maxVal or 99 ; eb.onChange = onChange
    local function apply(self)
        local v = math.max(self.minVal, math.min(self.maxVal, tonumber(self:GetText()) or self.minVal))
        self:SetText(tostring(v))
        if self.onChange then self.onChange(v) end
    end
    eb:SetScript("OnEnterPressed",  apply)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", apply)
    f.SetValue = function(self,v) eb:SetText(tostring(v)) end
    f.onChange = onChange ; f.numberInput = f
    return f
end

-- ─────────────────────────────────────────────────────────────────────────
-- BADGE
-- ─────────────────────────────────────────────────────────────────────────

function Widgets:CreateBadge(parent, text, badgeType)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    f:SetSize(60, 18)
    local col = C() and C().STATUS
    local bgR, bgG, bgB, txR, txG, txB = 0.12, 0.12, 0.12, 0.9, 0.9, 0.9
    if badgeType=="ok"   and col then bgR,bgG,bgB=col.okD.r,col.okD.g,col.okD.b ; txR,txG,txB=col.ok.r,col.ok.g,col.ok.b
    elseif badgeType=="bad" and col then bgR,bgG,bgB=col.badD.r,col.badD.g,col.badD.b ; txR,txG,txB=col.bad.r,col.bad.g,col.bad.b
    elseif badgeType=="warn" and col then txR,txG,txB=col.warn.r,col.warn.g,col.warn.b end
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=false, tileSize=0, edgeSize=6, insets={left=2,right=2,top=2,bottom=2} })
        f:SetBackdropColor(bgR,bgG,bgB,0.9) ; f:SetBackdropBorderColor(txR,txG,txB,0.6)
    end
    local fs = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    ApplyReadableFont(fs,"mono",12)
    fs:SetPoint("CENTER") ; fs:SetText(text or "") ; fs:SetTextColor(txR,txG,txB,1)
    f.label=fs
    f.text=fs
    f.SetText=function(self,t) fs:SetText(t) end
    f.SetBadgeText=function(self,t) fs:SetText(t) end
    return f
end

-- ─────────────────────────────────────────────────────────────────────────
-- INPUT  →  EditBox + InputBoxTemplate
-- ─────────────────────────────────────────────────────────────────────────

local _inN = 0
function Widgets:CreateInput(parent, width, placeholder)
    _inN = _inN + 1
    local eb = CreateFrame("EditBox", "MitzuIn".._inN, parent, "InputBoxTemplate")
    eb:SetSize(width or 140, 26)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(64)
    ApplyReadableFont(eb,"normal",13)
    if placeholder then
        local ph = eb:CreateFontString(nil,"OVERLAY","GameFontDisable")
        ApplyReadableFont(ph,"normal",12)
        ph:SetPoint("LEFT",eb,"LEFT",6,0) ; ph:SetText(placeholder) ; ph:SetTextColor(0.5,0.5,0.5,0.8)
        eb:SetScript("OnTextChanged",     function(self) ph:SetShown(self:GetText()=="") end)
        eb:SetScript("OnEditFocusGained", function() ph:Hide() end)
        eb:SetScript("OnEditFocusLost",   function(self) ph:SetShown(self:GetText()=="") end)
    end
    return eb
end

-- ─────────────────────────────────────────────────────────────────────────
-- DROPDOWN  →  UIDropDownMenuTemplate
-- ─────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────
-- DROPDOWN — Implementación nativa sin UIDropDownMenuTemplate
-- API-1 FIX: UIDropDownMenuTemplate + UIDropDownMenu_* fueron deprecados en
-- patch 11.0 (The War Within) y eliminados definitivamente en Midnight.
-- Reemplazado por un dropdown 100% propio: Frame + Button items, sin
-- dependencia de ninguna API de Blizzard de dropdown.
-- API pública idéntica: CreateDropdown(parent, width, items, defaultIndex, onChange)
--   onChange(value, text) — value = índice 1-based, text = label del item
-- ─────────────────────────────────────────────────────────────────────────

local _ddN = 0

function Widgets:CreateDropdown(parent, width, items, defaultIndex, onChange)
    items = items or {}
    _ddN  = _ddN + 1

    local W      = width or 120
    local BTN_H  = 26
    local MAX_VIS = 8

    -- Botón principal (muestra el item seleccionado)
    local mainBtn = CreateFrame("Button", "MitzuDD" .. _ddN, parent,
                                BackdropTemplateMixin and "BackdropTemplate")
    mainBtn:SetSize(W, 26)
    mainBtn:SetBackdrop({ bgFile   = "Interface\\Buttons\\WHITE8X8",
                          edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    mainBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.92)
    mainBtn:SetBackdropBorderColor(0.25, 0.22, 0.16, 1)

    local mainLabel = mainBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ApplyReadableFont(mainLabel,"normal",13)
    mainLabel:SetPoint("LEFT",  mainBtn, "LEFT",  6,  0)
    mainLabel:SetPoint("RIGHT", mainBtn, "RIGHT", -18, 0)
    mainLabel:SetJustifyH("LEFT")
    mainLabel:SetTextColor(0.90, 0.82, 0.65, 1)

    local arrow = mainBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ApplyReadableFont(arrow,"mono",12)
    arrow:SetPoint("RIGHT", mainBtn, "RIGHT", -4, 0)
    arrow:SetText("|cFFaaaaaa+|r")

    -- Menú desplegable
    local menuH    = math.min(#items, MAX_VIS) * BTN_H + 4
    local menuFrame = CreateFrame("Frame", nil, UIParent,
                                  BackdropTemplateMixin and "BackdropTemplate")
    menuFrame:SetSize(W, menuH)
    menuFrame:SetFrameStrata("TOOLTIP")
    menuFrame:SetBackdrop({ bgFile   = "Interface\\Buttons\\WHITE8X8",
                             edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    menuFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
    menuFrame:SetBackdropBorderColor(0.30, 0.26, 0.18, 1)
    -- ═════════════════════════════════════════════════════════════════════
    -- BUG DD-1 (v7.4.0) — el menu no tenia scroll y "se recortaba".
    --
    -- menuFrame:SetHeight(min(#items, MAX_VIS) * BTN_H) limitaba la ALTURA a 8
    -- filas, pero el bucle de abajo creaba una fila POR CADA item, colocadas en
    -- -(i-1)*BTN_H. Con 25 fuentes, las filas 9 a 25 caian fuera del marco: o
    -- se salian del fondo, o quedaban cortadas. No era un problema de
    -- frameStrata (el menu ya vive en UIParent y en strata TOOLTIP, por encima
    -- de todo), sino que faltaba poder desplazarse.
    --
    -- Afecta a CUALQUIER desplegable del addon con mas de 8 opciones, no solo
    -- al de fuentes: el filtro de mazmorras del Historial tiene el mismo fallo.
    -- ═════════════════════════════════════════════════════════════════════
    menuFrame:SetClipsChildren(true)
    menuFrame:EnableMouseWheel(true)
    menuFrame.offset = 0
    menuFrame:Hide()

    -- Contador "visibles/total" en la esquina: barato y suficiente para saber
    -- que la lista sigue.
    local scrollHint = menuFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scrollHint:SetPoint("BOTTOMRIGHT", menuFrame, "BOTTOMRIGHT", -4, 3)
    scrollHint:SetTextColor(0.55, 0.50, 0.40, 1)
    scrollHint:Hide()
    menuFrame.scrollHint = scrollHint

    -- Backdrop para cerrar al clicar fuera
    local bgClose = CreateFrame("Frame", nil, UIParent)
    bgClose:SetAllPoints()
    bgClose:SetFrameStrata("DIALOG")
    bgClose:EnableMouse(true)
    bgClose:Hide()
    bgClose:SetScript("OnMouseDown", function()
        menuFrame:Hide(); bgClose:Hide()
        arrow:SetText("|cFFaaaaaa+|r")
    end)

    local rows       = {}
    local selectedIdx = defaultIndex or 1

    local function SelectItem(idx)
        if not items[idx] then return end
        selectedIdx = idx
        local lbl = type(items[idx]) == "table"
                    and (items[idx].label or items[idx].text or items[idx][1] or tostring(idx))
                    or  tostring(items[idx])
        mainLabel:SetText(lbl)
        for i, r in ipairs(rows) do
            if i == selectedIdx then
                r:SetBackdropColor(0.18, 0.15, 0.07, 1)
                r.fs:SetTextColor(1.0, 0.85, 0.30, 1)
            else
                r:SetBackdropColor(0, 0, 0, 0)
                r.fs:SetTextColor(0.80, 0.75, 0.65, 1)
            end
        end
        if onChange then onChange(idx, lbl) end
        menuFrame:Hide(); bgClose:Hide()
        arrow:SetText("|cFFaaaaaa+|r")
    end

    -- Recoloca las filas segun el desplazamiento actual. Solo se muestran las
    -- que caben; el resto se ocultan en vez de dibujarse fuera del marco.
    local function LayoutRows()
        local vis = math.min(#items, MAX_VIS)
        local maxOffset = math.max(0, #items - vis)
        if menuFrame.offset > maxOffset then menuFrame.offset = maxOffset end
        if menuFrame.offset < 0 then menuFrame.offset = 0 end

        for i, r in ipairs(rows) do
            local slot = i - menuFrame.offset
            if slot >= 1 and slot <= vis then
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, -1 - (slot - 1) * BTN_H)
                r:Show()
            else
                r:Hide()
            end
        end

        -- Indicador de que hay mas: sin el, un menu lleno parece completo.
        if menuFrame.scrollHint then
            if #items > vis then
                menuFrame.scrollHint:SetText(string.format("%d/%d", menuFrame.offset + vis, #items))
                menuFrame.scrollHint:Show()
            else
                menuFrame.scrollHint:Hide()
            end
        end
    end

    menuFrame:SetScript("OnMouseWheel", function(self, delta)
        self.offset = (self.offset or 0) - delta
        LayoutRows()
    end)

    local function BuildRows()
        for _, r in ipairs(rows) do r:Hide() end
        rows = {}
        local vis = math.min(#items, MAX_VIS)
        menuFrame:SetHeight(vis * BTN_H + 4)
        menuFrame.offset = 0
        for i, item in ipairs(items) do
            local lbl = type(item) == "table"
                        and (item.label or item.text or item[1] or tostring(i))
                        or  tostring(item)
            local row = CreateFrame("Button", nil, menuFrame,
                                    BackdropTemplateMixin and "BackdropTemplate")
            row:SetSize(W - 2, BTN_H)
            row:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, -1 - (i-1)*BTN_H)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            row:SetBackdropColor(i == selectedIdx and 0.18 or 0,
                                 i == selectedIdx and 0.15 or 0,
                                 i == selectedIdx and 0.07 or 0,
                                 i == selectedIdx and 1    or 0)
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            ApplyReadableFont(fs,"normal",13)
            fs:SetPoint("LEFT", row, "LEFT", 6, 0)
            fs:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            fs:SetJustifyH("LEFT")
            fs:SetText(lbl)
            fs:SetTextColor(i == selectedIdx and 1.0 or 0.80,
                            i == selectedIdx and 0.85 or 0.75,
                            i == selectedIdx and 0.30 or 0.65, 1)
            row.fs = fs
            local ci = i
            row:SetScript("OnEnter", function(self)
                if ci ~= selectedIdx then
                    self:SetBackdropColor(0.12, 0.10, 0.05, 0.85)
                    fs:SetTextColor(0.95, 0.88, 0.55, 1)
                end
            end)
            row:SetScript("OnLeave", function(self)
                if ci ~= selectedIdx then
                    self:SetBackdropColor(0, 0, 0, 0)
                    fs:SetTextColor(0.80, 0.75, 0.65, 1)
                end
            end)
            row:SetScript("OnClick", function() SelectItem(ci) end)
            rows[i] = row
        end
        LayoutRows()
    end

    BuildRows()

    if items[selectedIdx] then
        local lbl = type(items[selectedIdx]) == "table"
                    and (items[selectedIdx].label or items[selectedIdx].text or tostring(selectedIdx))
                    or  tostring(items[selectedIdx])
        mainLabel:SetText(lbl)
    end

    mainBtn:SetScript("OnClick", function()
        if menuFrame:IsShown() then
            menuFrame:Hide(); bgClose:Hide()
            arrow:SetText("|cFFaaaaaa+|r")
        else
            menuFrame:ClearAllPoints()
            menuFrame:SetPoint("TOPLEFT", mainBtn, "BOTTOMLEFT", 0, -2)
            -- Abrir mostrando la opcion actual: con 25 fuentes, abrir siempre
            -- por el principio obliga a buscar la que ya tienes puesta.
            local vis = math.min(#items, MAX_VIS)
            if selectedIdx > vis then
                menuFrame.offset = selectedIdx - vis
            else
                menuFrame.offset = 0
            end
            LayoutRows()
            menuFrame:Show(); bgClose:Show()
            arrow:SetText("|cFFaaaaaa-|r")
        end
    end)

    mainBtn.SetItems = function(self, newItems)
        items = newItems or {}
        if selectedIdx > #items then selectedIdx = 1 end
        BuildRows()
        if items[selectedIdx] then
            local lbl = type(items[selectedIdx]) == "table"
                        and (items[selectedIdx].label or items[selectedIdx].text or tostring(selectedIdx))
                        or  tostring(items[selectedIdx])
            mainLabel:SetText(lbl)
        end
    end
    mainBtn.GetSelectedIndex = function() return selectedIdx end
    mainBtn.SetButtonText    = function(self, t) mainLabel:SetText(t or "") end
    return mainBtn
end

-- ─────────────────────────────────────────────────────────────────────────
-- PROGRESS BAR  →  StatusBar nativa
-- ─────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────
-- PROGRESS BAR  →  Frame + fill texture
-- API original:
--   bar:SetProgress(percent)    -- 0..100
--   bar:SetColor(colorType)     -- "ok" | "bad" | "info" | default=gold
-- ─────────────────────────────────────────────────────────────────────────

function Widgets:CreateProgressBar(parent, width, height)
    local w = width  or 200
    local h = height or 4

    local bar = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    bar:SetSize(w, h)
    if bar.SetBackdrop then
        bar:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = {left=0,right=0,top=0,bottom=0},
        })
        bar:SetBackdropColor(0.10, 0.10, 0.10, 0.8)
        bar:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)
    end

    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT",    bar, "TOPLEFT",    1, -1)
    fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1,  1)
    fill:SetWidth(1)   -- se actualiza con SetProgress
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Color inicial: dorado (igual que original)
    local T = MitzuMPlus.Colors or MitzuMPlus.Theme
    if T and T.SetGradientH then
        T:SetGradientH(fill,
            T.GOLD.gold2.r, T.GOLD.gold2.g, T.GOLD.gold2.b, 1,
            T.GOLD.gold4.r, T.GOLD.gold4.g, T.GOLD.gold4.b, 1)
    else
        fill:SetVertexColor(0.91, 0.72, 0.29, 1)
    end

    bar.fill     = fill
    bar.maxWidth = w - 2

    function bar:SetProgress(percent)
        percent = math.max(0, math.min(100, percent or 0))
        local fw = math.max(1, (self.maxWidth * percent) / 100)
        self.fill:SetWidth(fw)
    end

    function bar:SetColor(colorType)
        local Th = MitzuMPlus.Colors or MitzuMPlus.Theme
        if not Th then return end
        if colorType == "ok" then
            if Th.SetGradientH then
                Th:SetGradientH(self.fill, 0.084, 0.467, 0.220, 1,
                    Th.STATUS.ok.r, Th.STATUS.ok.g, Th.STATUS.ok.b, 1)
            else
                self.fill:SetVertexColor(Th.STATUS.ok.r, Th.STATUS.ok.g, Th.STATUS.ok.b, 1)
            end
        elseif colorType == "bad" then
            if Th.SetGradientH then
                Th:SetGradientH(self.fill, 0.478, 0.082, 0.082, 1,
                    Th.STATUS.bad.r, Th.STATUS.bad.g, Th.STATUS.bad.b, 1)
            else
                self.fill:SetVertexColor(Th.STATUS.bad.r, Th.STATUS.bad.g, Th.STATUS.bad.b, 1)
            end
        elseif colorType == "info" then
            if Th.SetGradientH then
                Th:SetGradientH(self.fill, 0.133, 0.267, 0.400, 1,
                    Th.STATUS.info.r, Th.STATUS.info.g, Th.STATUS.info.b, 1)
            else
                self.fill:SetVertexColor(Th.STATUS.info.r, Th.STATUS.info.g, Th.STATUS.info.b, 1)
            end
        else
            if Th.SetGradientH then
                Th:SetGradientH(self.fill,
                    Th.GOLD.gold2.r, Th.GOLD.gold2.g, Th.GOLD.gold2.b, 1,
                    Th.GOLD.gold4.r, Th.GOLD.gold4.g, Th.GOLD.gold4.b, 1)
            else
                self.fill:SetVertexColor(Th.GOLD.gold4.r, Th.GOLD.gold4.g, Th.GOLD.gold4.b, 1)
            end
        end
    end

    bar:SetProgress(0)
    return bar
end

-- ─────────────────────────────────────────────────────────────────────────
-- SCROLL FRAME  ← BUG FIX: ya no usa UIPanelScrollFrameTemplate
--
-- Crea un ScrollFrame plano + scrollbar manual, igual que el Widgets.lua
-- original. Esto es compatible con:
--   scrollFrame:SetPoint(...)              ← los paneles posicionan así
--   scrollFrame.scrollChild               ← acceso al contenido interno
--   scrollFrame:SetScript("OnSizeChanged")← los paneles setean esto
--   scrollFrame:HookScript("OnShow")      ← los paneles hookean esto
--   scrollFrame:UpdateScrollRange()       ← los paneles llaman esto
-- ─────────────────────────────────────────────────────────────────────────

function Widgets:CreateScrollFrame(parent, width, height)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetSize(width or 400, height or 300)

    -- Child frame (los paneles lo usan como "content" donde pegan widgets)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(width or 400, height or 300)
    sf:SetScrollChild(child)
    sf.scrollChild = child

    -- Scrollbar vertical (1 línea sutil, sin template para no interferir)
    local sb = CreateFrame("Slider", nil, sf)
    sb:SetPoint("TOPRIGHT",    sf, "TOPRIGHT",    -2,  -2)
    sb:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -2,   2)
    sb:SetWidth(5)
    sb:SetOrientation("VERTICAL")
    sb:SetMinMaxValues(0, 0)
    sb:SetValue(0)

    -- Pista
    local track = sb:CreateTexture(nil,"BACKGROUND")
    track:SetAllPoints()
    track:SetTexture("Interface\\Buttons\\WHITE8X8")
    track:SetVertexColor(0.12, 0.12, 0.12, 0.5)

    -- Pulgar color dorado suave (encaja con look Blizzard)
    local thumb = sb:CreateTexture(nil,"OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumb:SetSize(5, 40)
    thumb:SetVertexColor(0.60, 0.55, 0.30, 0.85)
    sb:SetThumbTexture(thumb)

    sb:SetScript("OnValueChanged", function(self, value)
        sf:SetVerticalScroll(value)
    end)

    sf.scrollBar = sb

    -- Rueda del ratón
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = sb:GetValue()
        local lo, hi = sb:GetMinMaxValues()
        sb:SetValue(math.max(lo, math.min(hi, cur - delta * 20)))
    end)

    -- UpdateScrollRange: los paneles llaman esto después de cambiar altura del child
    function sf:UpdateScrollRange()
        local maxScroll = math.max(0, self.scrollChild:GetHeight() - self:GetHeight())
        self.scrollBar:SetMinMaxValues(0, maxScroll)
        self.scrollBar:SetValue(math.min(self.scrollBar:GetValue(), maxScroll))
        if maxScroll > 0 then self.scrollBar:Show() else self.scrollBar:Hide() end
    end

    return sf
end

-- ─────────────────────────────────────────────────────────────────────────
-- LABEL
-- ─────────────────────────────────────────────────────────────────────────

function Widgets:CreateLabel(parent, text, fontType, fontSize, colorType)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(fontSize and fontSize + 4 or 18)
    local fs = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    fs:SetAllPoints(f) ; fs:SetText(text or "")
    local col = C()
    if col then
        col:ApplyFont(fs, fontType or "normal", fontSize)
        col:SetTextColor(fs, (colorType and col.TEXT[colorType]) or col.TEXT.primary)
    end
    f.label=fs ; f.SetText=function(self,t) fs:SetText(t) end
    return f
end

-- ─────────────────────────────────────────────────────────────────────────
-- SECTION HEADER
-- ─────────────────────────────────────────────────────────────────────────

function Widgets:CreateSectionHeader(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(22)
    local fs = f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    ApplyReadableFont(fs,"title",14)
    fs:SetPoint("LEFT",f,"LEFT",0,0) ; fs:SetText(text or "") ; fs:SetTextColor(1,0.82,0.0,1)
    local sep = f:CreateTexture(nil,"ARTWORK")
    sep:SetPoint("LEFT",fs,"RIGHT",8,0) ; sep:SetPoint("RIGHT",f,"RIGHT",0,0)
    sep:SetHeight(1) ; sep:SetColorTexture(0.45,0.40,0.18,0.55)
    f.label=fs
    f.text=fs
    return f
end

-- ─────────────────────────────────────────────────────────────────────────
-- STAT ROW
-- ─────────────────────────────────────────────────────────────────────────

function Widgets:CreateStatRow(parent, labelText, valueText, valueColor)
    -- Resolver nombres de color a tablas {r,g,b,a}
    local COLOR_NAMES = {
        gold = { r=0.910, g=0.722, b=0.290, a=1 },
        ok   = { r=0.129, g=0.871, b=0.400, a=1 },
        bad  = { r=0.933, g=0.200, b=0.200, a=1 },
        warn = { r=1.000, g=0.600, b=0.133, a=1 },
        info = { r=0.533, g=0.733, b=0.933, a=1 },
        white= { r=1,     g=1,     b=1,     a=1 },
    }
    if type(valueColor) == "string" then
        valueColor = COLOR_NAMES[valueColor] or COLOR_NAMES.white
    end
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(22)
    local lbl = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    ApplyReadableFont(lbl,"normal",13)
    lbl:SetPoint("LEFT",f,"LEFT",0,0) ; lbl:SetText(labelText or "") ; lbl:SetTextColor(0.75,0.75,0.75,1)
    local val = f:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    ApplyReadableFont(val,"mono",13)
    val:SetPoint("RIGHT",f,"RIGHT",0,0) ; val:SetText(valueText or "—")
    if valueColor then val:SetTextColor(valueColor.r,valueColor.g,valueColor.b,valueColor.a or 1) end
    f.labelText=lbl ; f.valueText=val
    -- Alias para compatibilidad con código que usa row.value / row.label
    -- (p.ej. Detail.lua PopulateStats). Sin esto los guiones nunca se reemplazaban.
    f.value = val ; f.label = lbl
    f.SetValue=function(self,t,c)
        val:SetText(t or "—")
        if c then
            if type(c) == "string" then c = COLOR_NAMES[c] or COLOR_NAMES.white end
            val:SetTextColor(c.r,c.g,c.b,c.a or 1)
        end
    end
    return f
end

-- ─────────────────────────────────────────────────────────────────────────
-- EMPTY STATE
-- ─────────────────────────────────────────────────────────────────────────

function Widgets:CreateEmptyState(parent, iconPath, titleText, descText, ctaText, ctaCallback)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(360,220)
    local ico = f:CreateTexture(nil,"ARTWORK")
    ico:SetSize(48,48) ; ico:SetPoint("TOP",f,"TOP",0,-8)
    ico:SetTexture(iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")
    if iconPath then ico:SetTexCoord(0.05,0.95,0.05,0.95) end
    ico:SetVertexColor(0.8,0.7,0.3,0.9)
    local title = f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    ApplyReadableFont(title,"title",16)
    title:SetPoint("TOP",ico,"BOTTOM",0,-10) ; title:SetText(titleText or "Sin datos") ; title:SetTextColor(1,0.82,0,1)
    local desc = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    ApplyReadableFont(desc,"normal",13)
    desc:SetPoint("TOP",title,"BOTTOM",0,-8) ; desc:SetWidth(300) ; desc:SetWordWrap(true)
    desc:SetJustifyH("CENTER") ; desc:SetText(descText or "") ; desc:SetTextColor(0.65,0.65,0.65,1)
    if ctaText and ctaCallback then
        local btn = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
        btn:SetSize(130,26) ; btn:SetPoint("TOP",desc,"BOTTOM",0,-12) ; btn:SetText(ctaText)
        btn:SetScript("OnClick",ctaCallback) ; f.ctaBtn=btn
    end
    f.icon=ico ; f.title=title ; f.desc=desc
    return f
end

return Widgets
