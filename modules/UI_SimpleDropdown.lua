local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local Theme = MitzuMPlus and MitzuMPlus.Theme

-- ═════════════════════════════════════════════════════════════════════════
-- BUG UI-SD1 — el texto del filtro se partía en dos renglones y se salía
--
-- Este es el desplegable de ESTADISTICAS y JUGADORES (el de la flecha "v").
-- Tenía los mismos tres fallos que el del Historial, y se arreglan igual:
--
--  1. La etiqueta del botón se ataba a LEFT y RIGHT, lo que le pone un ancho
--     máximo, y con el ajuste de línea de fábrica un texto que no cabía se
--     partía en DOS renglones dentro de un botón de 22 px de alto. Por eso
--     "Todos los roles", "Todas las temporadas" y "Todos los personajes"
--     salían montados sobre su propia etiqueta de arriba.
--  2. El ancho del menú se calculaba con `#texto * 7 + 20`. `#` cuenta BYTES
--     (todos los nombres con tilde salen mal) y 7 px por letra es una media
--     inventada. Por eso "Caballero de la Muerte" y "Sin temporada
--     (histórico)" se salían del recuadro del menú.
--  3. El menú se colocaba siempre bajo el botón, sin mirar si cabía.
--
-- Las herramientas de medida se las presta Widgets (UI/WidgetsCompat.lua),
-- que se carga antes. Si por lo que sea no estuviera, hay respaldo local: un
-- desplegable sin medir es feo, pero un error de Lua tira el panel entero.
-- ═════════════════════════════════════════════════════════════════════════

local W = MitzuMPlus.Widgets

local NoWrap = (W and W._NoWrap) or function(fs)
    if not fs then return end
    if fs.SetWordWrap then pcall(fs.SetWordWrap, fs, false) end
    if fs.SetMaxLines then pcall(fs.SetMaxLines, fs, 1) end
end

local CreateMeasurer = (W and W._CreateMeasurer) or function(parent, _, size)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    if Theme and Theme.ApplyFont then Theme:ApplyFont(fs, "normal", size) end
    fs:Hide()
    return function(text)
        if not text or text == "" then return 0 end
        fs:SetText(text)
        return fs:GetStringWidth() or 0
    end
end

local FitOnScreen = (W and W._FitOnScreen) or function()
    return "TOPLEFT", "BOTTOMLEFT", 0, -2
end

local PAD_L, PAD_R, ARROW_W = 8, 6, 20
local FONT_SIZE, ROW_H, MAX_VIS = 13, 24, 12

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
    if Theme and Theme.ApplyFont then Theme:ApplyFont(text,"normal",FONT_SIZE) end
    text:SetPoint("LEFT", PAD_L, 0)
    text:SetPoint("RIGHT", -ARROW_W, 0)
    text:SetJustifyH("LEFT")
    NoWrap(text)   -- ← una línea SIEMPRE; si no cabe, se recorta

    dropdown._measure = CreateMeasurer(dropdown, "normal", FONT_SIZE)

    -- Pone el texto y anota si ha habido que recortarlo, para el tooltip.
    function dropdown:SetLabel(t)
        t = t or ""
        self._text:SetText(t)
        self._fullText = t
        local avail = (self:GetWidth() or 0) - PAD_L - ARROW_W
        self._truncated = (t ~= "" and self._measure(t) > avail)
    end
    if Theme and Theme.TEXT and Theme.TEXT.primary then
        text:SetTextColor(Theme.TEXT.primary.r, Theme.TEXT.primary.g, Theme.TEXT.primary.b, 1)
    else
        text:SetTextColor(0.933, 0.933, 0.933, 1)
    end
    dropdown._text = text
    dropdown:SetLabel("Select...")

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
        -- Si el filtro elegido no cabe en el boton, el nombre entero se lee
        -- aqui. Recortar si; partir en dos renglones, nunca.
        if dropdown._truncated and dropdown._fullText and GameTooltip then
            GameTooltip:SetOwner(dropdown, "ANCHOR_TOP")
            GameTooltip:SetText(dropdown._fullText, 1, 0.85, 0.45, 1, true)
            GameTooltip:Show()
        end
    end)
    
    button:SetScript("OnLeave", function()
        if Theme and Theme.BORDER and Theme.BORDER.panel then
            dropdown:SetBackdropBorderColor(Theme.BORDER.panel.r, Theme.BORDER.panel.g, Theme.BORDER.panel.b, 0.6)
        else
            dropdown:SetBackdropBorderColor(0.133, 0.133, 0.125, 1)
        end
        if GameTooltip then GameTooltip:Hide() end
    end)
    
    function dropdown:SetItems(newItems)
        self._items = newItems or {}
        -- La lista nueva puede traer textos mas largos: si alguien pidio el
        -- ajuste automatico, hay que rehacerlo.
        if self._autoMin or self._autoMax then
            self:AutoSizeToItems(self._autoMin, self._autoMax)
        else
            self:SetLabel(self._fullText)
        end
    end

    -- Ajusta el ANCHO del boton al texto mas largo de la lista, entre un
    -- minimo y un maximo. Lo pide quien conoce el hueco de su barra.
    function dropdown:AutoSizeToItems(minW, maxW)
        self._autoMin, self._autoMax = minW, maxW
        local longest = 0
        for _, item in ipairs(self._items or {}) do
            local w = self._measure(item.text or "")
            if w > longest then longest = w end
        end
        local wanted = longest + PAD_L + ARROW_W + 4
        if minW and wanted < minW then wanted = minW end
        if maxW and wanted > maxW then wanted = maxW end
        if wanted > 0 then self:SetWidth(math.floor(wanted + 0.5)) end
        self:SetLabel(self._fullText)
        return self:GetWidth()
    end
    
    function dropdown:SetSelectedValue(value)
        self._selectedValue = value
        for _, item in ipairs(self._items) do
            if item.value == value then
                self:SetLabel(item.text or "")
                return
            end
        end
        self:SetLabel(self._items[1] and self._items[1].text or "Select...")
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
                dropdown:SetLabel(itemText)
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
    -- TOOLTIP, por encima del recogeclics de abajo (DIALOG). Estaba en DIALOG,
    -- la MISMA capa: al anadir un marco a pantalla completa en esa capa, y
    -- creado despues, habria quedado por delante del menu y se habria tragado
    -- los clics de las opciones. Es el mismo par de capas que usa el
    -- desplegable del Historial, que lleva funcionando desde el principio.
    menu:SetFrameStrata("TOOLTIP")
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
    
    -- ANCHO DEL MENU: el del texto mas largo, medido de verdad. Nunca mas
    -- estrecho que el boton y nunca mas ancho que la pantalla. Lo que no
    -- quepa se recorta con puntos y sale entero en el tooltip.
    local medir = dropdown._measure or CreateMeasurer(menu, "normal", FONT_SIZE)
    local masLargo = 0
    for _, item in ipairs(items) do
        local w = medir(item.text or "")
        if w > masLargo then masLargo = w end
    end
    local ancho = masLargo + PAD_L + PAD_R + 8
    if ancho < (dropdown:GetWidth() or 0) then ancho = dropdown:GetWidth() end
    local uiScale = (UIParent and UIParent:GetEffectiveScale()) or 1
    local ms = menu:GetEffectiveScale() or 1
    if ms > 0 and UIParent then
        local maxAncho = (((UIParent:GetWidth() or 1024) * uiScale) - 48 * ms) / ms
        if ancho > maxAncho then ancho = maxAncho end
    end
    local anchoTexto = ancho - PAD_L - PAD_R - 8

    -- ALTURA: como mucho MAX_VIS filas. Una lista de 30 personajes no puede
    -- salirse por abajo de la pantalla solo porque tenga 30 entradas.
    local visibles = math.min(#items, MAX_VIS)
    menu:SetWidth(math.floor(ancho + 0.5))
    menu:SetHeight(visibles * ROW_H + 8)
    menu.offset = 0

    for i, item in ipairs(items) do
        local menuItem = item
        local btn = CreateFrame("Button", nil, menu)
        btn:SetHeight(ROW_H)

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if Theme and Theme.ApplyFont then Theme:ApplyFont(fs,"normal",FONT_SIZE) end
        fs:SetPoint("LEFT", PAD_L - 4, 0)
        fs:SetPoint("RIGHT", -PAD_R, 0)
        fs:SetJustifyH("LEFT")
        NoWrap(fs)   -- ← una linea por opcion, sin excepciones
        fs:SetText(menuItem.text)
        btn._label = menuItem.text
        btn._truncated = (medir(menuItem.text or "") > anchoTexto)
        menu._rows = menu._rows or {}
        menu._rows[i] = btn
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
            if self._truncated and self._label and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self._label, 1, 0.85, 0.45, 1, true)
                GameTooltip:Show()
            end
        end)
        
        btn:SetScript("OnLeave", function(self)
            self._hover:Hide()
            if GameTooltip then GameTooltip:Hide() end
        end)
        
        btn:SetScript("OnClick", function()
            if menuItem.func then menuItem.func() end
            menu:Hide()
        end)
    end

    -- Coloca las filas segun el desplazamiento y esconde las que no caben.
    -- Sin esto, una lista larga dibujaba filas fuera del recuadro.
    local function LayoutRows()
        local maxOffset = math.max(0, #items - visibles)
        if menu.offset > maxOffset then menu.offset = maxOffset end
        if menu.offset < 0 then menu.offset = 0 end
        for i, row in ipairs(menu._rows or {}) do
            local slot = i - menu.offset
            if slot >= 1 and slot <= visibles then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT",  menu, "TOPLEFT",   4, -(slot - 1) * ROW_H - 4)
                row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -(slot - 1) * ROW_H - 4)
                row:Show()
            else
                row:Hide()
            end
        end
    end
    if #items > visibles then
        menu:EnableMouseWheel(true)
        menu:SetScript("OnMouseWheel", function(self, delta)
            self.offset = (self.offset or 0) - delta
            LayoutRows()
        end)
    end
    LayoutRows()

    -- COLOCACION: debajo del boton si cabe, encima si no, y siempre dentro de
    -- la pantalla. Antes se calculaba a mano desde el centro del boton y no
    -- miraba ni el borde derecho ni el inferior.
    menu:ClearAllPoints()
    local punto, anclaBoton, dx, dy = FitOnScreen(dropdown, menu, 1, 24)
    menu:SetPoint(punto, dropdown, anclaBoton, dx, dy)

    -- ═════════════════════════════════════════════════════════════════════
    -- BUG UI-SD2 — el menu se cerraba solo al ir a elegir una opcion
    --
    -- Se cerraba con un OnUpdate que miraba, EN CADA FOTOGRAMA, si el raton
    -- seguia encima del menu o del boton; si no lo estaba, se escondia. Eso
    -- funcionaba de milagro mientras el menu se dibujaba SOLAPANDO el boton
    -- (se anclaba a la altura de su centro). Al colocarlo bien —justo por
    -- debajo, y desplazado a un lado cuando no cabe— aparecio un pasillo por
    -- el que el cursor no esta sobre ninguno de los dos, y bastaba UN
    -- fotograma ahi para que se cerrara. Bajar a la segunda opcion se volvia
    -- una carrera contra el reloj.
    --
    -- "Cerrar si el raton se va" es fragil por definicion: cualquier hueco,
    -- borde o desplazamiento lo rompe. Se sustituye por lo que ya usa el
    -- desplegable del Historial y funciona: un marco invisible a pantalla
    -- completa POR DEBAJO del menu que lo cierra al hacer clic fuera. El
    -- menu se queda abierto hasta que eliges o clicas en otro sitio.
    --
    -- El marco es uno solo para todo el addon y se reutiliza: crear uno por
    -- cada apertura seria dejar marcos tirados, que en WoW no se liberan.
    -- ═════════════════════════════════════════════════════════════════════
    local bgClose = MitzuMPlus._simpleDropdownBg
    if not bgClose then
        bgClose = CreateFrame("Frame", nil, UIParent)
        bgClose:SetAllPoints(UIParent)
        bgClose:SetFrameStrata("DIALOG")   -- por debajo del menu (TOOLTIP)
        bgClose:EnableMouse(true)
        -- Deja pasar el clic al marco de abajo. Sin esto, con un filtro
        -- abierto el primer clic en OTRO filtro solo servia para cerrar el
        -- primero: habia que clicar dos veces para cambiar de filtro.
        if bgClose.SetPropagateMouseClicks then
            pcall(bgClose.SetPropagateMouseClicks, bgClose, true)
        end
        bgClose:Hide()
        bgClose:SetScript("OnMouseDown", function(self)
            local abierto = MitzuMPlus._simpleDropdownMenu
            if abierto then abierto:Hide() end
            self:Hide()
        end)
        MitzuMPlus._simpleDropdownBg = bgClose
    end

    menu:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        if MitzuMPlus._simpleDropdownBg then MitzuMPlus._simpleDropdownBg:Hide() end
        if MitzuMPlus._simpleDropdownMenu == self then
            MitzuMPlus._simpleDropdownMenu = nil
        end
    end)

    menu:Show()
    bgClose:Show()
    self._simpleDropdownMenu = menu
end
