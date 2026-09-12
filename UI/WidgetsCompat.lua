-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - UI/WidgetsCompat.lua  (FIX v2)
-- Reemplaza Widgets.lua.
-- API idéntica al Widgets.lua original para que los paneles no cambien.
--
-- BUG CORREGIDO: CreateScrollFrame usaba UIPanelScrollFrameTemplate que
--   sobreescribía los SetScript/HookScript de los paneles → paneles blancos.
--   Ahora crea un ScrollFrame plano + scrollbar manual, igual que el original.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local Widgets = {}
MitzuMPlus.Widgets = Widgets

local function C() return MitzuMPlus.Colors or MitzuMPlus.Theme end
local function ApplyReadableFont(region, fontType, size)
    local theme=C()
    if region and theme and theme.ApplyFont then theme:ApplyFont(region,fontType or "normal",size) end
end

-- ═════════════════════════════════════════════════════════════════════════
-- MEDIR TEXTO DE VERDAD  (BUG UI-DD2)
--
-- Lo que había antes para calcular el ancho de un menú era
-- `#texto * 7 + 20`. Dos fallos en una línea:
--   · `#` cuenta BYTES, no letras. "Estanques de Vida Rubí" tiene 22 letras
--     y 23 bytes; "Arena Rajavacío", 15 y 16. En español todos los nombres
--     con tilde salen mal medidos.
--   · 7 píxeles por letra es una media inventada. Una "i" y una "M" no
--     ocupan lo mismo, y menos aún al cambiar la fuente desde el tema.
--
-- La única medida buena es la que da el propio cliente. Se crea UNA
-- FontString oculta por widget, con la MISMA fuente que se va a pintar, y se
-- le pregunta. Va sobre el mismo padre que el texto real para que la escala
-- efectiva coincida: medir en UIParent y pintar en un marco con escala
-- propia devolvería anchos que no valen.
-- ═════════════════════════════════════════════════════════════════════════

local function CreateMeasurer(parent, fontType, size)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    ApplyReadableFont(fs, fontType or "normal", size)
    fs:SetWordWrap(false)
    fs:Hide()
    return function(text)
        if text == nil or text == "" then return 0 end
        fs:SetText(text)
        local w = fs:GetStringWidth() or 0
        return w
    end
end

-- Una sola línea, siempre. Si no cabe, el cliente recorta con puntos
-- suspensivos en vez de partir la palabra en dos renglones.
local function NoWrap(fs)
    if not fs then return end
    if fs.SetWordWrap then pcall(fs.SetWordWrap, fs, false) end
    if fs.SetMaxLines then pcall(fs.SetMaxLines, fs, 1) end
end

-- Los otros dos desplegables del addon (UI_Common y UI_SimpleDropdown) tenían
-- exactamente los mismos tres fallos. Se cargan DESPUÉS que este fichero, así
-- que se les prestan estas dos herramientas en vez de copiarlas una tercera
-- vez: una sola manera de medir texto en todo el addon.
Widgets._NoWrap         = NoWrap
Widgets._CreateMeasurer = CreateMeasurer

-- Mantiene un marco dentro de la pantalla. `anchor` es el widget del que
-- cuelga; devuelve el punto y el desplazamiento que hay que usar.
--   ancla, anclaDelBoton, dx, dy
local function FitOnScreen(anchorFrame, popup, gap, screenMargin)
    gap = gap or 2
    screenMargin = screenMargin or 24
    local bs = anchorFrame:GetEffectiveScale() or 1
    local ps = popup:GetEffectiveScale() or 1
    local left, right = anchorFrame:GetLeft(), anchorFrame:GetRight()
    local bottom, top = anchorFrame:GetBottom(), anchorFrame:GetTop()
    local pw, ph = popup:GetWidth(), popup:GetHeight()
    if not (left and right and bottom and top and pw and ph) or ps <= 0 then
        return "TOPLEFT", "BOTTOMLEFT", 0, -gap
    end

    local uiScale = (UIParent and UIParent:GetEffectiveScale()) or 1
    local screenWpx = ((UIParent and UIParent:GetWidth())  or 1024) * uiScale
    local screenHpx = ((UIParent and UIParent:GetHeight()) or 768)  * uiScale
    local margenPx  = screenMargin * uiScale
    local leftPx, rightPx = left * bs, right * bs
    local bottomPx, topPx = bottom * bs, top * bs
    local pwPx, phPx = pw * ps, ph * ps

    local haciaArriba = (bottomPx - gap * ps - phPx) < margenPx
                        and (topPx + phPx + gap * ps) <= (screenHpx - margenPx)

    local dxPx = 0
    if leftPx + pwPx > screenWpx - margenPx then
        local nuevo = rightPx - pwPx
        if nuevo + pwPx > screenWpx - margenPx then nuevo = screenWpx - margenPx - pwPx end
        if nuevo < margenPx then nuevo = margenPx end
        dxPx = nuevo - leftPx
    elseif leftPx < margenPx then
        dxPx = margenPx - leftPx
    end

    if haciaArriba then
        return "BOTTOMLEFT", "TOPLEFT", dxPx / ps, gap
    end
    return "TOPLEFT", "BOTTOMLEFT", dxPx / ps, -gap
end
Widgets._FitOnScreen = FitOnScreen

-- ═════════════════════════════════════════════════════════════════════════
-- REPARTIR EL ANCHO DE UNA FILA DE FILTROS
--
-- Una barra de filtros suele montarse en dos cadenas que crecen la una hacia
-- la otra —unos elementos anclados a la izquierda y otros al borde derecho—
-- y nada impide que se encuentren en medio. Sumar píxeles a mano no lo
-- arregla: el ancho de una etiqueta depende de la fuente, y la barra cambia
-- de tamaño con la ventana.
--
-- Esto lo reparte. Es una función PURA: solo números, sin marcos, para poder
-- probarla sin abrir el juego.
--
--   total      ancho de la barra
--   base       lo que ocupa lo fijo de la izquierda (etiquetas, márgenes)
--   optional   ancho de un bloque que se puede soltar si no cabe (0 si no hay)
--   tailExtra  lo fijo del bloque anclado a la derecha
--   tail       { pref, min } del elemento encogible de la derecha
--   flex       { { pref, min }, ... } los de la izquierda, por prioridad
--   gap        aire mínimo entre las dos mitades
--
-- Devuelve: lista de anchos, ancho de la cola, y si el bloque opcional cabe.
-- ═════════════════════════════════════════════════════════════════════════

-- ═════════════════════════════════════════════════════════════════════════
-- REPARTIR EL ANCHO DE LAS COLUMNAS DE UNA TABLA
--
-- El reparto que habia en el Historial no tenia camino para el caso "no
-- cabe": si los minimos sumaban mas que el contenedor, le daba a cada columna
-- su minimo igualmente y las ultimas se dibujaban fuera de la ventana.
--
-- Aqui hay tres salidas, en este orden:
--   1. Cabe: cada una su minimo y el sobrante repartido por peso.
--   2. No cabe: se sueltan columnas por `dropOrder` hasta que quepa. El peso
--      de las soltadas se reparte entre las que quedan, asi que soltar una
--      ensancha a las demas en vez de dejar un hueco.
--   3. No cabe ni soltandolas todas: se escalan los minimos para que quepan
--      justo. Titulos recortados, pero nada fuera de la ventana.
--
-- Funcion PURA. Devuelve: anchos por clave, sueltas por clave, y el total.
-- ═════════════════════════════════════════════════════════════════════════

function Widgets:FitColumns(opts)
    opts = opts or {}
    local total   = tonumber(opts.total) or 0
    local order   = opts.order or {}
    local mins    = opts.mins or {}
    local weights = opts.weights or {}
    local dropOrder = opts.dropOrder or {}

    local visible = {}
    for _, key in ipairs(order) do visible[key] = true end

    local function sumaMinimos()
        local t = 0
        for _, key in ipairs(order) do
            if visible[key] then t = t + (mins[key] or 0) end
        end
        return t
    end

    local minTotal = sumaMinimos()
    local i = 1
    while minTotal > total and i <= #dropOrder do
        if visible[dropOrder[i]] ~= nil then visible[dropOrder[i]] = false end
        i = i + 1
        minTotal = sumaMinimos()
    end

    local escala = 1
    if minTotal > total and minTotal > 0 then escala = total / minTotal end

    local extra = math.max(0, total - minTotal)
    local pesoVisible = 0
    for _, key in ipairs(order) do
        if visible[key] then pesoVisible = pesoVisible + (weights[key] or 0) end
    end
    if pesoVisible <= 0 then pesoVisible = 1 end

    local anchos, sueltas, usado = {}, {}, 0
    local ultimaVisible
    for _, key in ipairs(order) do
        if visible[key] then ultimaVisible = key end
    end

    for _, key in ipairs(order) do
        if not visible[key] then
            sueltas[key] = true
        else
            local w = math.floor(((mins[key] or 0) * escala)
                                 + extra * ((weights[key] or 0) / pesoVisible))
            if key == ultimaVisible then
                -- La ultima absorbe el resto y llega EXACTAMENTE al borde: ni
                -- franja muerta por los redondeos de las anteriores, ni un
                -- pixel de mas.
                --
                -- Aqui habia un `math.max(20, ...)` que parecia razonable y
                -- se saltaba la unica regla que importa: con la tabla muy
                -- estrecha, el resto era 19 px, el suelo lo subia a 20 y la
                -- tabla acababa 1 px fuera de la ventana. Si no queda sitio
                -- de verdad, la columna se suelta; lo que no se hace es
                -- inventar espacio que no existe.
                w = total - usado
            end
            if w < 1 then
                sueltas[key] = true
            else
                anchos[key] = w
                usado = usado + w
            end
        end
    end

    return anchos, sueltas, usado
end

function Widgets:SplitRow(opts)
    opts = opts or {}
    local total     = tonumber(opts.total) or 0
    local base      = tonumber(opts.base) or 0
    local optional  = tonumber(opts.optional) or 0
    local tailExtra = tonumber(opts.tailExtra) or 0
    local gap       = tonumber(opts.gap) or 12
    local flex      = opts.flex or {}
    local tail      = opts.tail or { pref = 0, min = 0 }

    local sumaPref, sumaMin = 0, 0
    for _, f in ipairs(flex) do
        sumaPref = sumaPref + (f.pref or 0)
        sumaMin  = sumaMin  + (f.min or 0)
    end

    local function presupuesto(conOpcional, tailW)
        return total - tailExtra - tailW - gap - base
               - (conOpcional and optional or 0)
    end

    -- Se van soltando piezas por orden de menos valor, no todas a la vez.
    local conOpcional, tailW = true, tail.pref or 0
    local libre = presupuesto(conOpcional, tailW)
    if libre < sumaMin then
        tailW = tail.min or 0
        libre = presupuesto(conOpcional, tailW)
    end
    if libre < sumaMin and optional > 0 then
        conOpcional = false
        libre = presupuesto(conOpcional, tailW)
    end

    -- Reparto: cada uno pide su preferido; si no llega para todos, el primero
    -- de la lista es el último en ceder.
    local anchos = {}
    local restante = libre
    -- Reserva el mínimo de los que vienen detrás, para que nadie se quede sin.
    local minPendiente = sumaMin
    for i, f in ipairs(flex) do
        local pref, min = f.pref or 0, f.min or 0
        minPendiente = minPendiente - min
        local techo = restante - minPendiente
        local w = pref
        if w > techo then w = techo end
        if w < min then w = min end
        anchos[i] = w
        restante = restante - w
    end

    return anchos, tailW, conOpcional
end

-- ─────────────────────────────────────────────────────────────────────────
-- BUTTON  →  UIPanelButtonTemplate
-- ─────────────────────────────────────────────────────────────────────────

-- Márgenes internos del texto de un botón. Sale de aquí y no de cinco sitios.
local BTN_TEXT_PAD = 10

function Widgets:CreateButton(parent, text, width, height, style, fontSize)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 120, height or 25)
    btn:SetText(text or "")
    local size = fontSize or 13
    local fs = btn:GetFontString()
    if fs then
        ApplyReadableFont(fs,"normal",size)
        -- ═══════════════════════════════════════════════════════════════
        -- BUG UI-BTN1 — el texto se salía del botón.
        --
        -- UIPanelButtonTemplate ancla su FontString al CENTRO, sin límite de
        -- ancho. Al cambiarle la fuente por la del tema (más ancha que la de
        -- Blizzard) a tamaño 13, "EXPORTAR" o "ELIMINAR" pintan más largo
        -- que el botón de 88 px y el texto se derrama por fuera, encima del
        -- botón de al lado y hasta fuera de la ventana.
        --
        -- Atarlo a LEFT y RIGHT le pone un ancho máximo, y NoWrap hace que
        -- lo que no quepa se recorte con puntos en vez de saltar de línea.
        -- Esto es la RED DE SEGURIDAD: ningún botón puede desbordar aunque
        -- alguien le ponga un texto largo o cambie de idioma. Para que
        -- además no haga falta recortar, está :FitToText().
        -- ═══════════════════════════════════════════════════════════════
        fs:ClearAllPoints()
        fs:SetPoint("LEFT",  btn, "LEFT",   BTN_TEXT_PAD, 0)
        fs:SetPoint("RIGHT", btn, "RIGHT", -BTN_TEXT_PAD, 0)
        fs:SetJustifyH("CENTER")
        NoWrap(fs)
        if     style == "bad"     then fs:SetTextColor(0.93, 0.30, 0.30, 1)
        elseif style == "ok"      then fs:SetTextColor(0.30, 0.90, 0.45, 1)
        elseif style == "primary" then fs:SetTextColor(1.00, 0.82, 0.00, 1)
        end
    end

    btn._fontSize = size

    -- Ajusta el ancho al texto que de verdad lleva. Opcional a propósito:
    -- muchos botones del addon están alineados en rejilla y crecer les
    -- rompería la fila. Quien lo llama, lo pide.
    btn.FitToText = function(self, minW, maxW, pad)
        local label = self:GetText() or ""
        if label == "" then return self:GetWidth() end
        self._measure = self._measure or CreateMeasurer(self, "normal", self._fontSize)
        local w = self._measure(label) + 2 * (pad or BTN_TEXT_PAD)
        if minW and w < minW then w = minW end
        if maxW and w > maxW then w = maxW end
        self:SetWidth(math.floor(w + 0.5))
        return self:GetWidth()
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
    local FONT_SIZE = 13

    -- ═════════════════════════════════════════════════════════════════════
    -- BUG UI-DD1 — los nombres largos se PISABAN unos a otros.
    --
    -- Cada fila ataba su FontString a LEFT y a RIGHT, lo que le da un ancho
    -- máximo. Con el ajuste de línea activado (que es el de fábrica), un
    -- nombre que no cabía se partía en DOS renglones... dentro de una fila de
    -- 26 px de alto colocada cada 26 px. El segundo renglón se dibujaba
    -- encima de la fila siguiente. Por eso "El Frontal de la / Muerte" y
    -- "El Valle / Enceguecedor" salían montados en la captura.
    --
    -- Se arregla por los dos lados:
    --   · NoWrap en cada fila: una línea siempre, pase lo que pase.
    --   · el menú se mide y se ensancha hasta el nombre más largo, para que
    --     normalmente no haya nada que recortar.
    -- La altura de fila NO depende del texto: es BTN_H para todas.
    -- ═════════════════════════════════════════════════════════════════════
    local PAD_L, PAD_R = 6, 4      -- márgenes del texto dentro de la fila
    local ARROW_W      = 18        -- hueco de la flecha en el botón principal
    local SCROLL_STRIP = 13        -- franja inferior para el contador "8/9"
    local SCREEN_MARGIN = 24       -- lo que se deja libre contra el borde

    -- Botón principal (muestra el item seleccionado)
    local mainBtn = CreateFrame("Button", "MitzuDD" .. _ddN, parent,
                                BackdropTemplateMixin and "BackdropTemplate")
    mainBtn:SetSize(W, 26)
    mainBtn:SetBackdrop({ bgFile   = "Interface\\Buttons\\WHITE8X8",
                          edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    mainBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.92)
    mainBtn:SetBackdropBorderColor(0.25, 0.22, 0.16, 1)

    local mainLabel = mainBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ApplyReadableFont(mainLabel,"normal",FONT_SIZE)
    mainLabel:SetPoint("LEFT",  mainBtn, "LEFT",  PAD_L,  0)
    mainLabel:SetPoint("RIGHT", mainBtn, "RIGHT", -ARROW_W, 0)
    mainLabel:SetJustifyH("LEFT")
    mainLabel:SetTextColor(0.90, 0.82, 0.65, 1)
    NoWrap(mainLabel)

    -- El medidor vive en el botón: misma escala efectiva que lo que se pinta.
    local Measure = CreateMeasurer(mainBtn, "normal", FONT_SIZE)

    local arrow = mainBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ApplyReadableFont(arrow,"mono",12)
    arrow:SetPoint("RIGHT", mainBtn, "RIGHT", -4, 0)
    arrow:SetText("|cFFaaaaaa+|r")

    -- Etiqueta de un item, en un solo sitio. Antes estaba copiada en cinco.
    local function LabelOf(item, i)
        if type(item) == "table" then
            return item.label or item.text or item[1] or tostring(i)
        end
        return tostring(item)
    end

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
    --
    -- BUG UI-DD3: estaba pegado al BOTTOMRIGHT del marco, o sea ENCIMA de la
    -- última fila. En la captura, el "8/9" se lee pisando "Reposo de los
    -- Reyes". Ahora el menú reserva una franja propia abajo (SCROLL_STRIP) y
    -- el contador vive ahí: no comparte píxeles con ningún nombre.
    local scrollHint = menuFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ApplyReadableFont(scrollHint, "mono", 10)
    scrollHint:SetPoint("BOTTOMRIGHT", menuFrame, "BOTTOMRIGHT", -5, 3)
    scrollHint:SetTextColor(0.55, 0.50, 0.40, 1)
    NoWrap(scrollHint)
    scrollHint:Hide()
    menuFrame.scrollHint = scrollHint

    -- ─────────────────────────────────────────────────────────────────────
    -- ANCHO DEL MENÚ — el del nombre más largo, sin pasarse de la pantalla
    -- ─────────────────────────────────────────────────────────────────────
    local menuTextWidth = 0   -- ancho util para el texto de una fila

    local function ComputeMenuWidth()
        local longest = 0
        for i, item in ipairs(items) do
            local w = Measure(LabelOf(item, i))
            if w > longest then longest = w end
        end
        -- Hueco del texto + márgenes + borde. La franja del contador va
        -- debajo, no al lado, así que no se descuenta del ancho.
        local wanted = longest + PAD_L + PAD_R + 2

        -- Nunca más estrecho que el botón: un menú más corto que su propio
        -- desplegable se ve roto.
        if wanted < W then wanted = W end

        -- Y nunca más ancho que la pantalla. Si no cabe, se recorta con
        -- puntos suspensivos y el nombre completo sale en el tooltip; lo que
        -- no se permite JAMÁS es partirlo en dos renglones.
        --
        -- El ancho de la pantalla se mide en PÍXELES y se traduce a las
        -- unidades del menú. Comparar el ancho de un marco con el de otro que
        -- tiene otra escala da un número sin sentido, y la ventana del addon
        -- sí puede tener escala propia.
        local maxW = math.max(W, 800)
        local ms = menuFrame:GetEffectiveScale() or 1
        if UIParent and ms > 0 then
            local screenPx = (UIParent:GetWidth() or 1024) * (UIParent:GetEffectiveScale() or 1)
            local disponible = (screenPx - SCREEN_MARGIN * 2 * ms) / ms
            maxW = math.max(W, disponible)
        end
        if wanted > maxW then wanted = maxW end

        menuTextWidth = wanted - PAD_L - PAD_R - 2
        return math.floor(wanted + 0.5)
    end

    -- Backdrop para cerrar al clicar fuera
    local bgClose = CreateFrame("Frame", nil, UIParent)
    bgClose:SetAllPoints()
    bgClose:SetFrameStrata("DIALOG")
    bgClose:EnableMouse(true)
    -- Deja pasar el clic al marco de abajo. Sin esto, con un filtro
    -- abierto el primer clic en OTRO filtro solo servia para cerrar el
    -- primero: habia que clicar dos veces para cambiar de filtro.
    if bgClose.SetPropagateMouseClicks then
        pcall(bgClose.SetPropagateMouseClicks, bgClose, true)
    end
    bgClose:Hide()
    bgClose:SetScript("OnMouseDown", function()
        menuFrame:Hide(); bgClose:Hide()
        arrow:SetText("|cFFaaaaaa+|r")
    end)

    local rows       = {}
    local selectedIdx = defaultIndex or 1

    -- Pone el texto del botón principal y, si no cabe, deja el nombre entero
    -- a mano en el tooltip. Recortado sí; partido en dos líneas, nunca.
    local function SetMainLabel(lbl)
        mainLabel:SetText(lbl or "")
        local avail = mainBtn:GetWidth() - PAD_L - ARROW_W
        mainBtn._fullText = lbl
        mainBtn._truncated = (lbl ~= nil and lbl ~= "" and Measure(lbl) > avail)
    end

    local function SelectItem(idx)
        if not items[idx] then return end
        selectedIdx = idx
        local lbl = LabelOf(items[idx], idx)
        SetMainLabel(lbl)
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

    -- ─────────────────────────────────────────────────────────────────────
    -- COLOCAR EL MENÚ SIN QUE SE SALGA DE LA PANTALLA
    --
    -- Antes se anclaba siempre TOPLEFT bajo el botón. Con el menú ya ancho
    -- de verdad, un desplegable a la derecha de la ventana se salía por el
    -- lado; y uno abajo del todo, por debajo. Se prueba la posición natural
    -- y solo se cambia si hace falta.
    -- ─────────────────────────────────────────────────────────────────────
    -- Todo se calcula en PÍXELES de pantalla, y el desplazamiento final se
    -- devuelve a las unidades del menú, que es en las que WoW interpreta el
    -- offset de un SetPoint. El botón vive en la ventana del addon y el menú
    -- cuelga de UIParent: pueden tener escalas distintas, y restar números de
    -- dos escalas daría un menú colocado donde no toca.
    local function PlaceMenu()
        menuFrame:ClearAllPoints()
        local punto, anclaBoton, dx, dy = FitOnScreen(mainBtn, menuFrame, 2, SCREEN_MARGIN)
        menuFrame:SetPoint(punto, mainBtn, anclaBoton, dx, dy)
    end

    menuFrame:SetScript("OnMouseWheel", function(self, delta)
        self.offset = (self.offset or 0) - delta
        LayoutRows()
    end)

    local function BuildRows()
        for _, r in ipairs(rows) do r:Hide() end
        rows = {}
        local vis = math.min(#items, MAX_VIS)

        -- Primero el ancho: las filas se cuelgan de él.
        local mw = ComputeMenuWidth()
        menuFrame:SetWidth(mw)
        -- Altura: SIEMPRE vis filas iguales, más la franja del contador si
        -- va a hacer falta. Ninguna fila cambia de alto por su texto.
        local strip = (#items > vis) and SCROLL_STRIP or 0
        menuFrame:SetHeight(vis * BTN_H + 4 + strip)
        menuFrame.offset = 0

        for i, item in ipairs(items) do
            local lbl = LabelOf(item, i)
            local row = CreateFrame("Button", nil, menuFrame,
                                    BackdropTemplateMixin and "BackdropTemplate")
            row:SetSize(mw - 2, BTN_H)
            row:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, -1 - (i-1)*BTN_H)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            row:SetBackdropColor(i == selectedIdx and 0.18 or 0,
                                 i == selectedIdx and 0.15 or 0,
                                 i == selectedIdx and 0.07 or 0,
                                 i == selectedIdx and 1    or 0)
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            ApplyReadableFont(fs,"normal",FONT_SIZE)
            fs:SetPoint("LEFT", row, "LEFT", PAD_L, 0)
            fs:SetPoint("RIGHT", row, "RIGHT", -PAD_R, 0)
            fs:SetJustifyH("LEFT")
            NoWrap(fs)          -- ← una línea por mazmorra, sin excepciones
            fs:SetText(lbl)
            fs:SetTextColor(i == selectedIdx and 1.0 or 0.80,
                            i == selectedIdx and 0.85 or 0.75,
                            i == selectedIdx and 0.30 or 0.65, 1)
            row.fs = fs
            row.label = lbl
            -- Solo se marca como recortado si de verdad no cabe. Con el menú
            -- ya medido, lo normal es que esto sea false y no haya tooltip.
            row.truncated = (Measure(lbl) > menuTextWidth)

            local ci = i
            row:SetScript("OnEnter", function(self)
                if ci ~= selectedIdx then
                    self:SetBackdropColor(0.12, 0.10, 0.05, 0.85)
                    fs:SetTextColor(0.95, 0.88, 0.55, 1)
                end
                if self.truncated and GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.label, 1, 0.85, 0.45, 1, true)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function(self)
                if ci ~= selectedIdx then
                    self:SetBackdropColor(0, 0, 0, 0)
                    fs:SetTextColor(0.80, 0.75, 0.65, 1)
                end
                if GameTooltip then GameTooltip:Hide() end
            end)
            row:SetScript("OnClick", function() SelectItem(ci) end)
            rows[i] = row
        end
        LayoutRows()
    end

    BuildRows()

    if items[selectedIdx] then
        SetMainLabel(LabelOf(items[selectedIdx], selectedIdx))
    end

    -- Si el nombre elegido no cabe en el botón, el completo sale al pasar por
    -- encima. El botón vive en una barra de filtros con sitio contado; el
    -- menú es el que se permite crecer.
    mainBtn:SetScript("OnEnter", function(self)
        if self._truncated and self._fullText and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self._fullText, 1, 0.85, 0.45, 1, true)
            GameTooltip:Show()
        end
    end)
    mainBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    mainBtn:SetScript("OnClick", function()
        if menuFrame:IsShown() then
            menuFrame:Hide(); bgClose:Hide()
            arrow:SetText("|cFFaaaaaa+|r")
        else
            -- Abrir mostrando la opcion actual: con 25 fuentes, abrir siempre
            -- por el principio obliga a buscar la que ya tienes puesta.
            local vis = math.min(#items, MAX_VIS)
            if selectedIdx > vis then
                menuFrame.offset = selectedIdx - vis
            else
                menuFrame.offset = 0
            end
            LayoutRows()
            -- Colocar DESPUÉS de tener el tamaño definitivo: PlaceMenu mide
            -- el marco para decidir si cabe hacia abajo y hacia la derecha.
            PlaceMenu()
            menuFrame:Show(); bgClose:Show()
            arrow:SetText("|cFFaaaaaa-|r")
        end
    end)

    mainBtn.SetItems = function(self, newItems)
        items = newItems or {}
        if selectedIdx > #items then selectedIdx = 1 end
        -- Si alguien pidió el ajuste automático, hay que rehacerlo: la lista
        -- nueva puede traer un nombre más largo que el que fijó el ancho.
        if self._autoMin or self._autoMax then
            self:AutoSizeToItems(self._autoMin, self._autoMax)
            return
        end
        BuildRows()
        if items[selectedIdx] then
            SetMainLabel(LabelOf(items[selectedIdx], selectedIdx))
        end
    end

    -- Ajusta el ANCHO DEL BOTÓN al nombre más largo de la lista, entre un
    -- mínimo y un máximo. Lo llama quien conoce el hueco que tiene en su
    -- barra; el widget no puede saberlo. Si el máximo no da para el nombre
    -- más largo, ese se recortará con puntos y tendrá tooltip.
    mainBtn.AutoSizeToItems = function(self, minW, maxW)
        self._autoMin, self._autoMax = minW, maxW
        local longest = 0
        for i, item in ipairs(items) do
            local w = Measure(LabelOf(item, i))
            if w > longest then longest = w end
        end
        local wanted = longest + PAD_L + ARROW_W + 4
        if minW and wanted < minW then wanted = minW end
        if maxW and wanted > maxW then wanted = maxW end
        W = math.floor(wanted + 0.5)
        self:SetWidth(W)
        BuildRows()
        if items[selectedIdx] then
            SetMainLabel(LabelOf(items[selectedIdx], selectedIdx))
        end
        return W
    end

    mainBtn.GetSelectedIndex = function() return selectedIdx end
    mainBtn.SetButtonText    = function(self, t) SetMainLabel(t or "") end
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
