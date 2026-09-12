-- Tests de GEOMETRIA de los widgets: el desplegable de MAZMORRA y los cinco
-- botones de la barra de acciones del Historial.
-- No se carga desde el TOC. Ejecutar con: python tests/run_lua_tests.py
--
-- POR QUE ESTE BANCO EXISTE
-- "Se ve mal" no se puede comprobar con un assert, pero "este texto mide 143
-- px y el hueco son 120" si. Aqui se simula un cliente que MIDE el texto como
-- lo hace WoW: por caracter y segun la fuente, no por bytes. Asi el fallo que
-- habia (#texto * 7, que cuenta bytes y se inventa el ancho de la letra) no
-- puede volver sin que salte una prueba.

local assertions, tests = 0, 0

local function equal(actual, expected, label)
    assertions = assertions + 1
    if actual ~= expected then
        error(string.format("%s: esperado %s, recibido %s",
            label or "equal", tostring(expected), tostring(actual)), 2)
    end
end
local function truthy(v, label)
    assertions = assertions + 1
    if not v then error((label or "truthy") .. ": valor falso", 2) end
end
local function falsy(v, label)
    assertions = assertions + 1
    if v then error((label or "falsy") .. ": valor verdadero", 2) end
end
local function atMost(a, b, label)
    assertions = assertions + 1
    if not (type(a) == "number" and type(b) == "number" and a <= b) then
        error(string.format("%s: %s deberia ser <= %s",
            label or "atMost", tostring(a), tostring(b)), 2)
    end
end
local function atLeast(a, b, label)
    assertions = assertions + 1
    if not (type(a) == "number" and type(b) == "number" and a >= b) then
        error(string.format("%s: %s deberia ser >= %s",
            label or "atLeast", tostring(a), tostring(b)), 2)
    end
end
local function test(name, fn)
    tests = tests + 1
    local ok, err = pcall(fn)
    if not ok then error("TEST " .. name .. "\n" .. tostring(err), 0) end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- UN CLIENTE QUE MIDE TEXTO COMO WOW
--
-- Anchos por caracter a tamano 13, escalados linealmente. Las letras NO miden
-- todas igual: si midieran igual, un bug que cuente bytes o que use una media
-- fija pasaria desapercibido. Las vocales con tilde ocupan lo mismo que su
-- version sin tilde, que es justo lo que una cuenta de BYTES se salta.
-- ═══════════════════════════════════════════════════════════════════════════

local ANCHOS = {
    [" "] = 4, ["."] = 3, [","] = 3, ["/"] = 4, ["·"] = 4,
    i = 3, l = 3, j = 3, t = 4, f = 4, r = 4, ["í"] = 3,
    m = 10, w = 9, M = 11, W = 12,
}
local ANCHO_MINUSCULA, ANCHO_MAYUSCULA = 6.5, 8.5

-- Itera CARACTERES utf-8, no bytes: los bytes de continuacion (0x80-0xBF) no
-- cuentan como letra.
local function caracteres(s)
    local out, i = {}, 1
    while i <= #s do
        local b = s:byte(i)
        local n = 1
        if b >= 0xF0 then n = 4 elseif b >= 0xE0 then n = 3 elseif b >= 0xC0 then n = 2 end
        out[#out + 1] = s:sub(i, i + n - 1)
        i = i + n
    end
    return out
end

local function anchoTexto(s, size)
    local total = 0
    for _, ch in ipairs(caracteres(s)) do
        local w = ANCHOS[ch]
        if not w then
            w = (ch:match("%u") or ch:match("^[ÁÉÍÓÚÑ]$")) and ANCHO_MAYUSCULA or ANCHO_MINUSCULA
        end
        total = total + w
    end
    return total * ((size or 13) / 13)
end

-- ── Marcos simulados ───────────────────────────────────────────────────────

local SCREEN_W, SCREEN_H = 1280, 720

local function nuevaFontString(parent)
    local fs = { _text = "", _size = 13, _wrap = true, _maxLines = nil,
                 _points = {}, _parent = parent, _shown = true }
    function fs:SetText(t) self._text = tostring(t or "") end
    function fs:GetText() return self._text end
    function fs:SetFont(_, size) self._size = size or 13 end
    function fs:GetStringWidth() return anchoTexto(self._text, self._size) end
    function fs:SetWordWrap(v) self._wrap = v and true or false end
    function fs:SetMaxLines(n) self._maxLines = n end
    function fs:SetPoint(p, rel, relP, x, y)
        self._points[#self._points + 1] = { p = p, rel = rel, relP = relP, x = x or 0, y = y or 0 }
    end
    function fs:ClearAllPoints() self._points = {} end
    function fs:SetJustifyH() end
    function fs:SetTextColor() end
    function fs:Hide() self._shown = false end
    function fs:Show() self._shown = true end
    function fs:SetShown(v) self._shown = v and true or false end
    -- Ancho util real: distancia entre el anclaje LEFT y el RIGHT.
    function fs:AvailableWidth()
        local l, r
        for _, pt in ipairs(self._points) do
            if pt.p == "LEFT"  then l = pt.x end
            if pt.p == "RIGHT" then r = pt.x end
        end
        if not l or not r then return nil end
        return (self._parent and self._parent:GetWidth() or 0) + r - l
    end
    -- ¿Cuantas lineas ocuparia? Es LA pregunta del bug original.
    function fs:LineCount()
        local avail = self:AvailableWidth()
        if not avail then return 1 end            -- sin ancho maximo no parte
        if self._wrap == false then return 1 end  -- prohibido partir
        local w = self:GetStringWidth()
        if w <= avail then return 1 end
        return math.ceil(w / avail)
    end
    return fs
end

local todosLosMarcos = {}

local function nuevoMarco(kind, parent, template)
    local f = { _kind = kind, _parent = parent, _template = template,
                _w = 0, _h = 0, _points = {}, _shown = true, _scripts = {},
                _children = {}, _fontStrings = {}, _text = "" }
    todosLosMarcos[#todosLosMarcos + 1] = f
    if parent and parent._children then parent._children[#parent._children + 1] = f end

    function f:SetWidth(w) self._w = w end
    function f:SetHeight(h) self._h = h end
    function f:GetWidth() return self._w end
    function f:GetHeight() return self._h end
    function f:SetSize(w, h) self._w, self._h = w, h end
    function f:SetPoint(p, rel, relP, x, y)
        self._points[#self._points + 1] = { p = p, rel = rel, relP = relP, x = x or 0, y = y or 0 }
    end
    function f:ClearAllPoints() self._points = {} end
    function f:SetAllPoints() end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:IsShown() return self._shown end
    function f:SetShown(v) self._shown = v and true or false end
    function f:SetScript(s, fn) self._scripts[s] = fn end
    function f:GetScript(s) return self._scripts[s] end
    function f:HookScript(s, fn) self._scripts[s] = fn end
    function f:CreateFontString()
        local fs = nuevaFontString(self)
        self._fontStrings[#self._fontStrings + 1] = fs
        return fs
    end
    function f:CreateTexture()
        return { SetAllPoints = function() end, SetTexture = function() end,
                 SetVertexColor = function() end, Hide = function() end,
                 Show = function() end }
    end
    function f:SetBackdrop() end
    function f:SetBackdropColor() end
    function f:SetBackdropBorderColor() end
    function f:SetFrameStrata(v) self._strata = v end
    function f:SetClipsChildren() end
    function f:EnableMouse() end
    function f:SetPropagateMouseClicks(v) self._propagate = v and true or false end
    function f:EnableMouseWheel() end
    function f:GetEffectiveScale() return 1 end
    function f:SetText(t)
        self._text = tostring(t or "")
        if self._fs then self._fs:SetText(self._text) end
    end
    function f:GetText() return self._text end
    function f:GetFontString() return self._fs end
    -- Coordenadas en pantalla: las pone el test a mano en el marco que le
    -- interese. Sin ellas, el widget usa su camino de respaldo.
    function f:GetLeft()   return self._left end
    function f:GetRight()  return self._left and (self._left + self._w) or nil end
    function f:GetBottom() return self._bottom end
    function f:GetTop()    return self._bottom and (self._bottom + self._h) or nil end
    function f:Place(left, bottom) self._left, self._bottom = left, bottom end

    if template == "UIPanelButtonTemplate" then
        f._fs = f:CreateFontString()
    end
    return f
end

function CreateFrame(kind, name, parent, template)
    return nuevoMarco(kind, parent, template)
end

UIParent = nuevoMarco("Frame", nil, nil)
UIParent:SetSize(SCREEN_W, SCREEN_H)
UIParent:Place(0, 0)

BackdropTemplateMixin = {}

-- Temporizador simulado: guarda las llamadas y las dispara cuando el test
-- quiere. Sin esto, un `C_Timer.After` no se ejecutaria nunca y una prueba
-- sobre lo que pasa "0,1 s despues de abrir" pasaria sin comprobar nada.
local pendientes = {}
C_Timer = {
    After = function(_, fn) pendientes[#pendientes + 1] = fn end,
    NewTicker = function(_, fn) return { fn = fn, Cancel = function() end } end,
}
local function correrTemporizadores()
    local lista = pendientes
    pendientes = {}
    for _, fn in ipairs(lista) do fn() end
end
GameTooltip = {
    _owner = nil, _text = nil, _shown = false,
    SetOwner = function(self, o) self._owner = o end,
    SetText  = function(self, t) self._text = t end,
    AddLine  = function() end,
    Show     = function(self) self._shown = true end,
    Hide     = function(self) self._shown = false end,
}

-- ── Addon simulado ─────────────────────────────────────────────────────────

MitzuMPlus = {}
_G.MitzuMPlus = MitzuMPlus
function LibStub() return { GetAddon = function() return MitzuMPlus end } end

-- Tema minimo: lo unico que importa aqui es que ApplyFont fije el TAMANO,
-- porque de el depende el ancho que mide el cliente.
MitzuMPlus.Theme = {
    ApplyFont = function(_, region, _, size)
        if region and region.SetFont then region:SetFont("f", size or 13, "") end
    end,
}

dofile("UI/WidgetsCompat.lua")
local Widgets = MitzuMPlus.Widgets
truthy(Widgets and Widgets.CreateDropdown, "se cargo WidgetsCompat")

-- Los NUEVE nombres de la captura, tal cual.
local MAZMORRAS = {
    "Todas",
    "Altar de Colmillos",
    "Arena Rajavacío",
    "El Frontal de la Muerte",
    "El Valle Enceguecedor",
    "Estanques de Vida Rubí",
    "Guarida de Nalorakk",
    "Reposo de los Reyes",
    "Templo de Sethraliss",
}

-- Saca del widget sus piezas: el marco del menu y sus filas.
local function piezasDe(dd)
    local menu, filas = nil, {}
    for _, f in ipairs(todosLosMarcos) do
        if f._parent == UIParent and f._kind == "Frame" and f.scrollHint then
            menu = f
        end
    end
    if menu then
        for _, f in ipairs(menu._children) do
            if f._kind == "Button" then filas[#filas + 1] = f end
        end
    end
    return menu, filas
end

local function abrir(dd)
    local onClick = dd:GetScript("OnClick")
    truthy(onClick, "el desplegable responde al clic")
    onClick(dd)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EL DESPLEGABLE DE MAZMORRA
-- ═══════════════════════════════════════════════════════════════════════════

test("A1 el medidor cuenta LETRAS, no bytes", function()
    -- Si alguien vuelve a medir con #texto, esta prueba lo caza: los dos
    -- nombres tienen los mismos bytes y distinto numero de letras.
    equal(#"Arena Rajavacío", 16, "bytes con tilde")
    equal(#caracteres("Arena Rajavacío"), 15, "letras de verdad")
    truthy(anchoTexto("Arena Rajavacío", 13) < anchoTexto("Arena Rajavacioo", 13),
        "15 letras miden menos que 16")
end)

test("A2 ninguno de los nueve nombres parte en dos lineas", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400)
    panel:Place(100, 400)
    local dd = Widgets:CreateDropdown(panel, 180, MAZMORRAS, 1, function() end)
    dd:Place(300, 380)
    abrir(dd)

    local menu, filas = piezasDe(dd)
    truthy(menu, "hay marco de menu")
    equal(#filas, #MAZMORRAS, "una fila por mazmorra")

    for i, fila in ipairs(filas) do
        local fs = fila._fontStrings[1]
        truthy(fs, "la fila " .. i .. " tiene texto")
        equal(fs:GetText(), MAZMORRAS[i], "texto de la fila " .. i)
        equal(fs:LineCount(), 1, "UNA linea en: " .. MAZMORRAS[i])
        equal(fs._wrap, false, "sin ajuste de linea en: " .. MAZMORRAS[i])
        equal(fs._maxLines, 1, "una linea maxima en: " .. MAZMORRAS[i])
    end
end)

test("A3 el menu se ensancha hasta el nombre mas largo", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400)
    panel:Place(100, 400)
    local dd = Widgets:CreateDropdown(panel, 180, MAZMORRAS, 1, function() end)
    dd:Place(300, 380)
    abrir(dd)
    local menu, filas = piezasDe(dd)

    -- Cual de los nueve sea el mas ancho depende de la fuente de verdad; lo
    -- que se comprueba aqui es que el menu se ajusta al mas ancho, sea cual
    -- sea, no que sea uno concreto.
    local masLargo = 0
    for _, n in ipairs(MAZMORRAS) do
        local w = anchoTexto(n, 13)
        if w > masLargo then masLargo = w end
    end

    -- Cabe entero, con sus margenes, y sin recortar.
    atLeast(menu:GetWidth(), masLargo + 10, "el menu cabe el nombre mas largo")
    atLeast(menu:GetWidth(), dd:GetWidth(), "el menu nunca es mas estrecho que el boton")
    for i, fila in ipairs(filas) do
        falsy(fila.truncated, "no hace falta recortar: " .. MAZMORRAS[i])
        local fs = fila._fontStrings[1]
        atLeast(fs:AvailableWidth(), fs:GetStringWidth(), "cabe: " .. MAZMORRAS[i])
    end
end)

test("A4 todas las filas miden lo mismo de alto", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = Widgets:CreateDropdown(panel, 180, MAZMORRAS, 1, function() end)
    dd:Place(300, 380)
    abrir(dd)
    local _, filas = piezasDe(dd)
    local alto = filas[1]:GetHeight()
    atLeast(alto, 20, "altura razonable")
    for i, fila in ipairs(filas) do
        equal(fila:GetHeight(), alto, "misma altura en la fila " .. i)
    end
end)

test("A5 las filas no se solapan: cada una empieza donde acaba la anterior", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = Widgets:CreateDropdown(panel, 180, MAZMORRAS, 1, function() end)
    dd:Place(300, 380)
    abrir(dd)
    local _, filas = piezasDe(dd)

    -- Se leen las posiciones que LayoutRows dejo puestas (la ultima de cada
    -- fila) y se comprueba que el paso entre visibles es exactamente el alto.
    local visibles = {}
    for _, fila in ipairs(filas) do
        if fila._shown then
            local p = fila._points[#fila._points]
            visibles[#visibles + 1] = { y = p.y, h = fila:GetHeight() }
        end
    end
    atLeast(#visibles, 8, "hay filas visibles")
    table.sort(visibles, function(a, b) return a.y > b.y end)
    for i = 2, #visibles do
        equal(visibles[i - 1].y - visibles[i].y, visibles[i].h,
            "la fila " .. i .. " empieza justo donde acaba la anterior")
    end
end)

test("A6 el contador 8/9 no pisa la ultima fila", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = Widgets:CreateDropdown(panel, 180, MAZMORRAS, 1, function() end)
    dd:Place(300, 380)
    abrir(dd)
    local menu, filas = piezasDe(dd)

    truthy(menu.scrollHint._shown, "con 9 opciones y 8 visibles, el contador se ve")
    equal(menu.scrollHint:GetText(), "8/9", "lo que decia la captura")

    -- La franja del contador esta POR DEBAJO de la ultima fila visible.
    local masBaja = 0
    for _, fila in ipairs(filas) do
        if fila._shown then
            local p = fila._points[#fila._points]
            local fondo = -p.y + fila:GetHeight()   -- distancia desde arriba
            if fondo > masBaja then masBaja = fondo end
        end
    end
    atLeast(menu:GetHeight(), masBaja + 10, "queda sitio bajo la ultima fila")
end)

test("A7 si no cabe en pantalla se recorta y sale tooltip, pero no salta de linea", function()
    local largos = { "Todas" }
    for i = 1, 4 do
        largos[#largos + 1] = string.rep("Mazmorra Interminable ", 12) .. i
    end
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = Widgets:CreateDropdown(panel, 180, largos, 1, function() end)
    dd:Place(300, 380)
    abrir(dd)
    local menu, filas = piezasDe(dd)

    atMost(menu:GetWidth(), SCREEN_W, "el menu no es mas ancho que la pantalla")
    local recortadas = 0
    for i, fila in ipairs(filas) do
        equal(fila._fontStrings[1]:LineCount(), 1, "sigue siendo UNA linea (" .. i .. ")")
        if fila.truncated then recortadas = recortadas + 1 end
    end
    equal(recortadas, 4, "las cuatro largas se marcan para tooltip")

    -- Y el tooltip ensena el nombre completo.
    GameTooltip._text, GameTooltip._shown = nil, false
    local larga
    for _, fila in ipairs(filas) do if fila.truncated then larga = fila; break end end
    larga:GetScript("OnEnter")(larga)
    truthy(GameTooltip._shown, "se muestra el tooltip")
    equal(GameTooltip._text, larga.label, "con el nombre entero")
end)

test("A8 el menu no se sale por la derecha ni por abajo", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)

    -- Desplegable pegado al borde derecho y al de abajo.
    local dd = Widgets:CreateDropdown(panel, 180, MAZMORRAS, 1, function() end)
    dd:Place(SCREEN_W - 190, 60)
    abrir(dd)
    local menu = piezasDe(dd)

    local p = menu._points[#menu._points]
    truthy(p, "el menu esta colocado")
    -- Se abre hacia ARRIBA: por debajo no cabe.
    equal(p.p, "BOTTOMLEFT", "ancla inferior = abre hacia arriba")
    equal(p.relP, "TOPLEFT", "sobre el boton")
    -- Y se corre a la izquierda lo justo para no salirse.
    local izquierdaFinal = dd:GetLeft() + p.x
    atLeast(izquierdaFinal, 0, "no se sale por la izquierda")
    atMost(izquierdaFinal + menu:GetWidth(), SCREEN_W, "no se sale por la derecha")
end)

test("A8b con la ventana a otra escala, el menu sigue sin salirse", function()
    -- La ventana del addon puede tener escala propia. Si se restan numeros de
    -- dos escalas distintas, el menu acaba colocado donde no toca.
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = Widgets:CreateDropdown(panel, 180, MAZMORRAS, 1, function() end)
    -- El boton mide en unidades suyas: 1500 * 0.8 = 1200 px, casi el borde.
    dd.GetEffectiveScale = function() return 0.8 end
    dd:Place(1500, 500)
    abrir(dd)
    local menu = piezasDe(dd)
    local p = menu._points[#menu._points]
    -- dx viene en unidades del MENU (escala 1), aplicado sobre un punto del
    -- boton que esta a 1200 px: el borde derecho debe caber en 1280.
    local izquierdaPx = 1500 * 0.8 + p.x * 1
    atMost(izquierdaPx + menu:GetWidth(), SCREEN_W, "no se sale por la derecha")
    atLeast(izquierdaPx, 0, "ni por la izquierda")
end)

test("A9 con sitio de sobra el menu se abre hacia abajo y alineado", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = Widgets:CreateDropdown(panel, 180, MAZMORRAS, 1, function() end)
    dd:Place(200, 600)
    abrir(dd)
    local menu = piezasDe(dd)
    local p = menu._points[#menu._points]
    equal(p.p, "TOPLEFT", "ancla superior = abre hacia abajo")
    equal(p.x, 0, "sin desplazamiento lateral")
end)

test("A10 el boton principal tampoco parte el nombre elegido", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = Widgets:CreateDropdown(panel, 180, MAZMORRAS, 1, function() end)
    dd:Place(300, 380)
    local etiqueta = dd._fontStrings[1]
    for i = 1, #MAZMORRAS do
        dd:GetScript("OnClick")(dd)              -- abrir
        local _, filas = piezasDe(dd)
        filas[i]:GetScript("OnClick")(filas[i])  -- elegir
        equal(etiqueta:GetText(), MAZMORRAS[i], "el boton ensena " .. MAZMORRAS[i])
        equal(etiqueta:LineCount(), 1, "en UNA linea: " .. MAZMORRAS[i])
    end
end)

test("A11 AutoSizeToItems ajusta el boton al nombre mas largo dentro del limite", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = Widgets:CreateDropdown(panel, 180, MAZMORRAS, 1, function() end)
    local w = dd:AutoSizeToItems(150, 230)
    atLeast(w, 150, "respeta el minimo")
    atMost(w, 230, "respeta el maximo")
    local masLargo = 0
    for _, n in ipairs(MAZMORRAS) do
        local x = anchoTexto(n, 13)
        if x > masLargo then masLargo = x end
    end
    atLeast(w, masLargo, "cabe el nombre mas largo de los nueve")
    falsy(dd._truncated, "y por tanto no hay que recortar el seleccionado")

    -- Con un tope pequeno, recorta y avisa con tooltip en vez de partir.
    local dd2 = Widgets:CreateDropdown(panel, 180, MAZMORRAS, 1, function() end)
    dd2:AutoSizeToItems(80, 100)
    dd2:GetScript("OnClick")(dd2)
    local _, filas = piezasDe(dd2)
    filas[4]:GetScript("OnClick")(filas[4])      -- "El Frontal de la Muerte"
    equal(dd2._fontStrings[1]:LineCount(), 1, "una linea aunque no quepa")
    truthy(dd2._truncated, "marcado como recortado")
    GameTooltip._shown = false
    dd2:GetScript("OnEnter")(dd2)
    truthy(GameTooltip._shown, "tooltip con el nombre entero")
    equal(GameTooltip._text, "El Frontal de la Muerte", "texto del tooltip")
end)

test("A12 al cambiar la lista se vuelve a ajustar", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = Widgets:CreateDropdown(panel, 180, { "Todas", "Ab" }, 1, function() end)
    local corto = dd:AutoSizeToItems(60, 400)
    dd:SetItems(MAZMORRAS)
    local largo = dd:GetWidth()
    atLeast(largo, corto, "el boton crece con la lista nueva")
    local masLargo = 0
    for _, n in ipairs(MAZMORRAS) do
        local x = anchoTexto(n, 13)
        if x > masLargo then masLargo = x end
    end
    atLeast(largo, masLargo, "y cabe el mas largo")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- LOS CINCO BOTONES DE LA BARRA DE ACCIONES
-- ═══════════════════════════════════════════════════════════════════════════

local ACCIONES = { "EXPORTAR", "COMPARAR", "EDITAR", "FAVORITA", "ELIMINAR" }

test("B1 el texto de un boton nunca se sale: tiene ancho maximo y no parte", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    for _, t in ipairs(ACCIONES) do
        local b = Widgets:CreateButton(panel, t, 88, 26, "normal", 12)
        local fs = b:GetFontString()
        equal(fs._wrap, false, "sin ajuste de linea: " .. t)
        equal(fs._maxLines, 1, "una linea: " .. t)
        truthy(fs:AvailableWidth() ~= nil, "el texto tiene ancho maximo: " .. t)
        atMost(fs:AvailableWidth(), b:GetWidth(), "y cabe dentro del boton: " .. t)
    end
end)

test("B2 FitToText deja sitio de sobra para el texto de cada boton", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    for _, t in ipairs(ACCIONES) do
        local b = Widgets:CreateButton(panel, t, 88, 26, "normal", 12)
        b:FitToText(70, 110, 11)
        local fs = b:GetFontString()
        atLeast(fs:AvailableWidth(), fs:GetStringWidth(),
            "el texto cabe sin recortar: " .. t)
        atLeast(b:GetWidth(), 70, "minimo: " .. t)
        atMost(b:GetWidth(), 110, "maximo: " .. t)
        equal(fs:LineCount(), 1, "una linea: " .. t)
    end
end)

test("B3 los cinco juntos caben en la barra del Historial", function()
    -- Ancho tipico de la ventana en la captura, menos el margen derecho.
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(1057, 44); panel:Place(0, 300)
    local total, sep = 10, 7
    for _, t in ipairs(ACCIONES) do
        local b = Widgets:CreateButton(panel, t, 88, 26, "normal", 12)
        b:FitToText(70, 110, 11)
        total = total + b:GetWidth() + sep
    end
    atMost(total, 560, "los cinco caben en el hueco que les reserva la barra")
    -- Y queda sitio para el texto de estado a la izquierda.
    atLeast(panel:GetWidth() - total, 300, "sobra barra para el resumen")
end)

test("B4 la fuente a 12 mide menos que a 13 (el ajuste pedido tiene efecto)", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local grande = Widgets:CreateButton(panel, "EXPORTAR", 88, 26, "primary")
    local chico  = Widgets:CreateButton(panel, "EXPORTAR", 88, 26, "primary", 12)
    atLeast(grande:GetFontString():GetStringWidth(),
            chico:GetFontString():GetStringWidth() + 1, "13 es mas ancho que 12")
    -- Cuanto margen deja cada tamano dentro del mismo boton de 88 px. Con la
    -- fuente real del tema (mas ancha que la de este modelo) ese margen era
    -- negativo a 13, que es lo que se veia desbordado en la captura.
    local holguraGrande = grande:GetFontString():AvailableWidth()
                          - grande:GetFontString():GetStringWidth()
    local holguraChica  = chico:GetFontString():AvailableWidth()
                          - chico:GetFontString():GetStringWidth()
    atLeast(holguraChica, holguraGrande + 1, "bajar a 12 gana margen")
end)

test("B5 un texto imposible se recorta, no desborda", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local b = Widgets:CreateButton(panel, "EXPORTAR SELECCION COMPLETA A CSV", 88, 26, "normal", 12)
    local fs = b:GetFontString()
    equal(fs:LineCount(), 1, "una linea")
    atMost(fs:AvailableWidth(), b:GetWidth(), "el hueco del texto no pasa del boton")
    truthy(fs:GetStringWidth() > fs:AvailableWidth(), "no cabe, asi que el cliente lo recorta")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- EL DESPLEGABLE DE ESTADISTICAS Y JUGADORES (CreateSimpleDropdown)
-- ═══════════════════════════════════════════════════════════════════════════

MitzuMPlusColors = setmetatable({}, { __index = function()
    return { r = 0.5, g = 0.5, b = 0.5, a = 1 }
end })
MitzuMPlus.Theme.BG     = { input = { r=0,g=0,b=0,a=1 }, tooltip = { r=0,g=0,b=0,a=1 },
                            rowHover = { r=0,g=0,b=0,a=1 } }
MitzuMPlus.Theme.BORDER = { panel = { r=0,g=0,b=0 }, window = { r=0,g=0,b=0 } }
MitzuMPlus.Theme.TEXT   = { primary = { r=1,g=1,b=1 }, dim = { r=0.5,g=0.5,b=0.5 } }
MitzuMPlus.Theme.GOLD   = { borderFocus = { r=1,g=0.8,b=0.2 } }

dofile("modules/UI_SimpleDropdown.lua")
truthy(MitzuMPlus.CreateSimpleDropdown, "se cargo UI_SimpleDropdown")

-- Los de la captura de JUGADORES y ESTADISTICAS.
local ROLES = { { text = "Todos los roles", value = "ALL" },
                { text = "Tanque", value = "TANK" },
                { text = "Sanador", value = "HEALER" },
                { text = "DPS", value = "DPS" } }
local CLASES = {}
for _, n in ipairs({ "Todas las clases", "Brujo", "Caballero de la Muerte",
                     "Cazador", "Cazador de Demonios", "Chamán", "Druida",
                     "Evocador", "Guerrero", "Mago", "Monje", "Paladín",
                     "Pícaro", "Sacerdote" }) do
    CLASES[#CLASES + 1] = { text = n, value = n }
end
local TEMPORADAS = { { text = "Todas las temporadas", value = "ALL" },
                     { text = "Midnight - Temporada 18", value = "S18" },
                     { text = "Sin temporada (histórico)", value = "NONE" } }

local function menuAbierto()
    return MitzuMPlus._simpleDropdownMenu
end

local function abrirSimple(dd)
    dd._button:GetScript("OnClick")(dd._button)
    return menuAbierto()
end

test("C1 el filtro elegido no se parte en dos renglones", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    -- 145 px es el ancho real del filtro de ROL en la pestana JUGADORES.
    local dd = MitzuMPlus:CreateSimpleDropdown(panel, 145, ROLES, function() end)
    dd:Place(300, 380)
    dd:SetSelectedValue("ALL")
    local fs = dd._text
    equal(fs:GetText(), "Todos los roles", "texto elegido")
    equal(fs._wrap, false, "sin ajuste de linea")
    equal(fs._maxLines, 1, "una linea maxima")
    equal(fs:LineCount(), 1, "UNA linea")
end)

test("C2 si no cabe se marca para tooltip, y el tooltip lo ensena entero", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = MitzuMPlus:CreateSimpleDropdown(panel, 100, TEMPORADAS, function() end)
    dd:Place(300, 380)
    dd:SetSelectedValue("NONE")
    truthy(dd._truncated, "no cabe en 100 px")
    equal(dd._text:LineCount(), 1, "pero sigue en una linea")
    GameTooltip._shown = false
    dd._button:GetScript("OnEnter")(dd._button)
    truthy(GameTooltip._shown, "se ensena el tooltip")
    equal(GameTooltip._text, "Sin temporada (histórico)", "con el nombre entero")

    -- Y con sitio de sobra no molesta con ningun tooltip.
    local ancho = MitzuMPlus:CreateSimpleDropdown(panel, 300, TEMPORADAS, function() end)
    ancho:Place(300, 300)
    ancho:SetSelectedValue("NONE")
    falsy(ancho._truncated, "con 300 px cabe")
    GameTooltip._shown = false
    ancho._button:GetScript("OnEnter")(ancho._button)
    falsy(GameTooltip._shown, "y no aparece tooltip")
end)

test("C3 el menu se ensancha hasta la opcion mas larga", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = MitzuMPlus:CreateSimpleDropdown(panel, 190, CLASES, function() end)
    dd:Place(300, 380)
    local menu = abrirSimple(dd)
    truthy(menu, "el menu se abre")

    local masLarga = 0
    for _, item in ipairs(CLASES) do
        local w = anchoTexto(item.text, 13)
        if w > masLarga then masLarga = w end
    end
    atLeast(menu:GetWidth(), masLarga + 10, "cabe la clase mas larga")
    atLeast(menu:GetWidth(), dd:GetWidth(), "nunca mas estrecho que el boton")

    for _, fila in ipairs(menu._rows or {}) do
        local fs = fila._fontStrings[1]
        equal(fs:LineCount(), 1, "una linea: " .. tostring(fila._label))
        falsy(fila._truncated, "sin recortar: " .. tostring(fila._label))
    end
end)

test("C4 el mismo caso de la captura de ESTADISTICAS", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(1000, 52); panel:Place(40, 560)
    -- 150 px es el ancho real del filtro TEMPORADA en ESTADISTICAS.
    local dd = MitzuMPlus:CreateSimpleDropdown(panel, 150, TEMPORADAS, function() end)
    dd:Place(200, 570)
    local menu = abrirSimple(dd)
    local mas = 0
    for _, item in ipairs(TEMPORADAS) do
        local w = anchoTexto(item.text, 13)
        if w > mas then mas = w end
    end
    -- Era lo que se salia del recuadro en la captura.
    atLeast(menu:GetWidth(), mas + 10, "'Sin temporada (histórico)' cabe dentro")
    for _, fila in ipairs(menu._rows or {}) do
        falsy(fila._truncated, "nada recortado: " .. tostring(fila._label))
    end
end)

test("C5 una lista larga no se sale de la pantalla por abajo", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local muchos = {}
    for i = 1, 40 do muchos[i] = { text = "Personaje " .. i, value = i } end
    local dd = MitzuMPlus:CreateSimpleDropdown(panel, 190, muchos, function() end)
    dd:Place(300, 380)
    local menu = abrirSimple(dd)
    atMost(menu:GetHeight(), SCREEN_H, "el menu no es mas alto que la pantalla")
    -- Solo se pintan las que caben; el resto se ocultan, no se dibujan fuera.
    local visibles = 0
    for _, fila in ipairs(menu._rows or {}) do
        if fila._shown then visibles = visibles + 1 end
    end
    atMost(visibles, 12, "como mucho MAX_VIS filas a la vez")
    equal(#menu._rows, 40, "pero estan las 40 creadas")
end)

test("C6 el menu se coloca dentro de la pantalla", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = MitzuMPlus:CreateSimpleDropdown(panel, 190, CLASES, function() end)
    -- Pegado al borde inferior: no cabe hacia abajo.
    dd:Place(600, 40)
    local menu = abrirSimple(dd)
    local p = menu._points[#menu._points]
    equal(p.p, "BOTTOMLEFT", "se abre hacia arriba")
    equal(p.relP, "TOPLEFT", "sobre el boton")
end)

test("C7 AutoSizeToItems tambien esta en este desplegable", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = MitzuMPlus:CreateSimpleDropdown(panel, 100, TEMPORADAS, function() end)
    dd:Place(300, 380)
    local w = dd:AutoSizeToItems(120, 260)
    atLeast(w, 120, "minimo")
    atMost(w, 260, "maximo")
    dd:SetSelectedValue("NONE")
    falsy(dd._truncated, "ya no hace falta recortar")
    equal(dd._text:LineCount(), 1, "una linea")
end)

test("C9 el menu NO se cierra solo por mover el raton", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = MitzuMPlus:CreateSimpleDropdown(panel, 150, CLASES, function() end)
    dd:Place(300, 380)
    local menu = abrirSimple(dd)
    truthy(menu._shown, "el menu esta abierto")

    -- Pasa el tiempo que tardaba en armarse el cierre automatico.
    correrTemporizadores()
    equal(menu:GetScript("OnUpdate"), nil,
        "no queda ningun vigilante por fotograma que lo esconda")
    truthy(menu._shown, "sigue abierto")

    -- Y el cursor recorriendo las filas tampoco lo cierra.
    for _, fila in ipairs(menu._rows or {}) do
        if fila._shown then
            fila:GetScript("OnEnter")(fila)
            fila:GetScript("OnLeave")(fila)
        end
    end
    truthy(menu._shown, "recorrer las opciones no lo cierra")
end)

test("C10 se cierra al elegir, y al clicar fuera", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local elegido
    local dd = MitzuMPlus:CreateSimpleDropdown(panel, 150, CLASES,
        function(v) elegido = v end)
    dd:Place(300, 380)

    -- 1. Elegir una opcion.
    local menu = abrirSimple(dd)
    local fila = menu._rows[3]        -- "Caballero de la Muerte"
    fila:GetScript("OnClick")(fila)
    equal(elegido, "Caballero de la Muerte", "se aplica el filtro")
    equal(dd._text:GetText(), "Caballero de la Muerte", "y se ve en el boton")
    falsy(menu._shown, "el menu se cierra al elegir")

    -- 2. Clicar fuera.
    menu = abrirSimple(dd)
    truthy(menu._shown, "abierto otra vez")
    local fondo = MitzuMPlus._simpleDropdownBg
    truthy(fondo, "hay un recogeclics a pantalla completa")
    truthy(fondo._shown, "y esta activo mientras el menu lo esta")
    fondo:GetScript("OnMouseDown")(fondo)
    falsy(menu._shown, "clicar fuera lo cierra")
    falsy(fondo._shown, "y el recogeclics se retira")
end)

test("C11 el recogeclics queda por debajo del menu, no encima", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = MitzuMPlus:CreateSimpleDropdown(panel, 150, ROLES, function() end)
    dd:Place(300, 380)
    local menu = abrirSimple(dd)
    local fondo = MitzuMPlus._simpleDropdownBg
    -- Si estuviera en la misma capa que el menu, o por encima, se tragaria
    -- los clics de las opciones y no se podria elegir nada.
    equal(fondo._strata, "DIALOG", "el recogeclics, en DIALOG")
    equal(menu._strata, "TOOLTIP", "el menu, por encima")
end)

test("C12 abrir un filtro cierra el que estuviera abierto", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local a = MitzuMPlus:CreateSimpleDropdown(panel, 150, ROLES, function() end)
    local b = MitzuMPlus:CreateSimpleDropdown(panel, 150, CLASES, function() end)
    a:Place(200, 380); b:Place(420, 380)
    local menuA = abrirSimple(a)
    local menuB = abrirSimple(b)
    falsy(menuA._shown, "el primero se cierra")
    truthy(menuB._shown, "y queda el segundo")
    equal(MitzuMPlus._simpleDropdownMenu, menuB, "solo uno abierto a la vez")
end)

-- Una cadena corta en BYTES pero ANCHA al pintarla. El atajo que habia
-- (#texto * 7 + 20) se queda corto aqui: 10 bytes le dan 90 px cuando el
-- texto necesita 110. Es el caso que se veia en la captura, con "Caballero
-- de la Muerte" saliendose del recuadro del menu.
local ANCHA = "MMMMMMMMMM"

test("C8 el ancho del menu sale de medir, no de contar bytes", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local items = { { text = "Todas", value = 1 }, { text = ANCHA, value = 2 } }

    -- Lo que habria dado el atajo, para dejar constancia de la diferencia.
    local porBytes = #ANCHA * 7 + 20
    local deVerdad = anchoTexto(ANCHA, 13)
    truthy(deVerdad > porBytes, "el atajo se queda corto: " ..
        math.floor(deVerdad) .. " px reales frente a " .. porBytes)

    local dd = MitzuMPlus:CreateSimpleDropdown(panel, 100, items, function() end)
    dd:Place(300, 380)
    local menu = abrirSimple(dd)
    atLeast(menu:GetWidth(), deVerdad + 10, "el menu se dimensiona con la medida real")
    for _, fila in ipairs(menu._rows or {}) do
        falsy(fila._truncated, "nada recortado: " .. tostring(fila._label))
        equal(fila._fontStrings[1]:LineCount(), 1, "una linea")
    end
end)

test("A14 el desplegable del Historial tampoco se cierra solo", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local elegido
    local dd = Widgets:CreateDropdown(panel, 180, MAZMORRAS, 1,
        function(_, texto) elegido = texto end)
    dd:Place(300, 380)
    abrir(dd)
    local menu, filas = piezasDe(dd)
    truthy(menu._shown, "abierto")
    correrTemporizadores()
    equal(menu:GetScript("OnUpdate"), nil, "sin vigilante por fotograma")

    -- El recogeclics existe, esta por debajo del menu y no lo tapa.
    local fondo
    for _, f in ipairs(todosLosMarcos) do
        if f._parent == UIParent and f._strata == "DIALOG" and f._shown then fondo = f end
    end
    truthy(fondo, "hay recogeclics activo")
    equal(menu._strata, "TOOLTIP", "el menu por encima del recogeclics")

    -- Recorrer las opciones no cierra nada; elegir, si.
    for _, fila in ipairs(filas) do
        if fila._shown then fila:GetScript("OnEnter")(fila) end
    end
    truthy(menu._shown, "recorrer no lo cierra")
    filas[5]:GetScript("OnClick")(filas[5])
    equal(elegido, MAZMORRAS[5], "se aplica la mazmorra elegida")
    falsy(menu._shown, "y se cierra al elegir")
end)

test("A15 el recogeclics deja pasar el clic al filtro de al lado", function()
    -- Sin esto, con un filtro abierto el primer clic en otro solo servia para
    -- cerrar el primero.
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = Widgets:CreateDropdown(panel, 180, MAZMORRAS, 1, function() end)
    dd:Place(300, 380)
    abrir(dd)
    local fondo
    for _, f in ipairs(todosLosMarcos) do
        if f._parent == UIParent and f._strata == "DIALOG" and f._shown then fondo = f end
    end
    truthy(fondo, "hay recogeclics")
    equal(fondo._propagate, true, "deja pasar los clics")

    local simple = MitzuMPlus:CreateSimpleDropdown(panel, 150, ROLES, function() end)
    simple:Place(500, 380)
    abrirSimple(simple)
    equal(MitzuMPlus._simpleDropdownBg._propagate, true,
        "y el de Estadisticas y Jugadores tambien")
end)

test("A13 lo mismo en el desplegable del Historial", function()
    local panel = nuevoMarco("Frame", UIParent, nil)
    panel:SetSize(800, 400); panel:Place(100, 400)
    local dd = Widgets:CreateDropdown(panel, 100, { "Todas", ANCHA }, 1, function() end)
    dd:Place(300, 380)
    abrir(dd)
    local menu, filas = piezasDe(dd)
    atLeast(menu:GetWidth(), anchoTexto(ANCHA, 13) + 10,
        "medido, no estimado por bytes")
    for _, fila in ipairs(filas) do
        falsy(fila.truncated, "nada recortado: " .. tostring(fila.label))
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- EL REPARTO DE LA FILA DE FILTROS  (Widgets:SplitRow)
-- ═══════════════════════════════════════════════════════════════════════════

-- Los numeros reales de la fila 1 del Historial, medidos con este modelo:
--   base       = margen + buscador + separadores + "MAZMORRA" + "PERSONAJE"
--   temporadaW = "TEMPORADA" + insignia
--   ordenExtra = "ORDENAR" + separador + margen derecho
local FILA = {
    base       = 12 + 180 + 8 + 1 + 8 + anchoTexto("MAZMORRA", 11) + 6
                 + 8 + 1 + 8 + anchoTexto("PERSONAJE", 11) + 6,
    temporadaW = 10 + anchoTexto("TEMPORADA", 11) + 6 + 120,
    ordenExtra = anchoTexto("ORDENAR", 11) + 8 + 10 + 1 + 12,
    tail       = { pref = 160, min = 110 },
    flex       = { { pref = 205, min = 110 }, { pref = 160, min = 100 } },
    gap        = 14,
}

local function repartir(total)
    local anchos, tailW, conTemporada = Widgets:SplitRow({
        total = total, base = FILA.base, optional = FILA.temporadaW,
        tailExtra = FILA.ordenExtra, gap = FILA.gap,
        tail = FILA.tail, flex = FILA.flex,
    })
    -- Ancho total ocupado de verdad, para comprobar que no hay solape.
    local usado = FILA.base + anchos[1] + anchos[2]
                  + (conTemporada and FILA.temporadaW or 0)
                  + FILA.gap + tailW + FILA.ordenExtra
    return anchos, tailW, conTemporada, usado
end

test("D1 con la ventana ancha nadie se encoge y la temporada se ve", function()
    local anchos, tailW, conTemporada, usado = repartir(1400)
    equal(anchos[1], 205, "MAZMORRA a su ancho preferido")
    equal(anchos[2], 160, "PERSONAJE a su ancho preferido")
    equal(tailW, 160, "ORDENAR a su ancho preferido")
    truthy(conTemporada, "la temporada se ve")
    atMost(usado, 1400, "y sobra sitio")
end)

test("D2 el caso de la captura: 1057 px, ya NO se solapan", function()
    local anchos, tailW, conTemporada, usado = repartir(1057)
    atMost(usado, 1057, "todo cabe dentro de la barra")
    atLeast(anchos[1], FILA.flex[1].min, "MAZMORRA no baja del minimo")
    atLeast(anchos[2], FILA.flex[2].min, "PERSONAJE no baja del minimo")
    atLeast(tailW, FILA.tail.min, "ORDENAR no baja del minimo")
end)

test("D3 se encoge por orden: primero PERSONAJE, MAZMORRA aguanta", function()
    local anchoTotal, previo = nil, nil
    for _, total in ipairs({ 1400, 1200, 1100, 1000 }) do
        local anchos = repartir(total)
        if previo then
            atMost(anchos[1], previo[1], "MAZMORRA no crece al estrecharse")
            atMost(anchos[2], previo[2], "PERSONAJE no crece al estrecharse")
        end
        previo = anchos
    end
    -- Con sitio justo, PERSONAJE se agota primero y MAZMORRA sigue por
    -- encima de su minimo: los nombres de mazmorra son los largos.
    local a = repartir(1050)
    equal(a[2], FILA.flex[2].min, "PERSONAJE ya esta al minimo")
    truthy(a[1] > FILA.flex[1].min, "MAZMORRA todavia conserva margen")
    truthy(a[1] < FILA.flex[1].pref, "pero ya ha cedido algo")
end)

test("D4 cuando ya no cabe, se suelta la TEMPORADA antes que recortar mas", function()
    local sueltaEn = nil
    for total = 1400, 500, -10 do
        local _, _, conTemporada = repartir(total)
        if not conTemporada then sueltaEn = total; break end
    end
    truthy(sueltaEn, "en algun ancho se suelta")
    -- Y justo por encima de ese punto todavia se ve.
    local _, _, antes = repartir(sueltaEn + 10)
    truthy(antes, "un poco mas ancha, la temporada sigue ahi")
    -- Antes de soltarla se ha encogido ORDENAR.
    local _, tailW = repartir(sueltaEn + 10)
    equal(tailW, FILA.tail.min, "ORDENAR ya estaba al minimo")
end)

test("D5 nunca se solapan, sea cual sea el ancho de la ventana", function()
    for total = 1920, 420, -20 do
        local anchos, tailW, conTemporada, usado = repartir(total)
        atLeast(anchos[1], FILA.flex[1].min, "MAZMORRA >= minimo en " .. total)
        atLeast(anchos[2], FILA.flex[2].min, "PERSONAJE >= minimo en " .. total)
        atLeast(tailW, FILA.tail.min, "ORDENAR >= minimo en " .. total)
        -- Por debajo de lo que ocupan los minimos no hay reparto posible;
        -- lo que se exige es que no se invente espacio que no existe.
        local suelo = FILA.base + FILA.flex[1].min + FILA.flex[2].min
                      + FILA.gap + FILA.tail.min + FILA.ordenExtra
        if total >= suelo then
            atMost(usado, total, "cabe todo en " .. total)
        end
    end
end)

test("D6 el reparto es idempotente: mismos numeros, mismo resultado", function()
    for _, total in ipairs({ 1400, 1057, 900, 700 }) do
        local a1, t1, s1 = repartir(total)
        local a2, t2, s2 = repartir(total)
        equal(a1[1], a2[1], "MAZMORRA estable en " .. total)
        equal(a1[2], a2[2], "PERSONAJE estable en " .. total)
        equal(t1, t2, "ORDENAR estable en " .. total)
        equal(s1, s2, "temporada estable en " .. total)
    end
end)

test("D7 con una fuente mas grande el reparto se ajusta solo", function()
    -- Misma barra, etiquetas un 40% mas anchas (fuente 11 -> 15).
    local grande = {
        base = 12 + 180 + 8 + 1 + 8 + anchoTexto("MAZMORRA", 15) + 6
               + 8 + 1 + 8 + anchoTexto("PERSONAJE", 15) + 6,
        temporadaW = 10 + anchoTexto("TEMPORADA", 15) + 6 + 120,
        ordenExtra = anchoTexto("ORDENAR", 15) + 8 + 10 + 1 + 12,
    }
    local anchos, tailW, conTemporada = Widgets:SplitRow({
        total = 1057, base = grande.base, optional = grande.temporadaW,
        tailExtra = grande.ordenExtra, gap = FILA.gap,
        tail = FILA.tail, flex = FILA.flex,
    })
    local usado = grande.base + anchos[1] + anchos[2]
                  + (conTemporada and grande.temporadaW or 0)
                  + FILA.gap + tailW + grande.ordenExtra
    atMost(usado, 1057, "con la fuente grande tampoco se sale")
    -- Y algo ha tenido que ceder: o los desplegables se estrechan, o se
    -- suelta la temporada. Lo que no puede pasar es que no cambie nada.
    local normales, tailNormal, tempNormal = repartir(1057)
    local cedieron = (anchos[1] + anchos[2]) < (normales[1] + normales[2])
                     or tailW < tailNormal
                     or (tempNormal and not conTemporada)
    truthy(cedieron, "con letra mas grande la fila se reajusta sola")
end)

test("D8 sin bloque opcional el reparto sigue funcionando", function()
    local anchos, tailW, conOpcional = Widgets:SplitRow({
        total = 900, base = 200, optional = 0, tailExtra = 60, gap = 10,
        tail = { pref = 150, min = 100 },
        flex = { { pref = 300, min = 120 }, { pref = 200, min = 100 } },
    })
    truthy(conOpcional, "sin bloque opcional no hay nada que soltar")
    atLeast(anchos[1], 120, "minimo respetado")
    atLeast(anchos[2], 100, "minimo respetado (2)")
    atMost(200 + anchos[1] + anchos[2] + 10 + tailW + 60, 900, "cabe")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- LAS COLUMNAS DE LA TABLA DEL HISTORIAL  (Widgets:FitColumns)
-- ═══════════════════════════════════════════════════════════════════════════

-- Los datos reales del Historial: orden, titulos, minimos de datos y pesos.
local COL_ORDER = {
    "favorite","dungeon","level","season","result",
    "margin","character","role","quality","notes","tags","group","date","actions",
}
local COL_TITULO = {
    favorite="FAV.", dungeon="MAZMORRA", level="NIVEL", season="TEMPORADA",
    result="RESULTADO", margin="MARGEN", character="PERSONAJE", role="ROL",
    quality="DATOS", notes="NOTA", tags="ETIQUETA", group="GRUPO",
    date="FECHA", actions="",
}
local COL_MIN_DATOS = {
    favorite=45,dungeon=220,level=60,season=115,result=105,
    margin=75,character=140,role=50,quality=75,notes=50,
    tags=85,group=100,date=100,actions=35,
}
local COL_PESOS = {
    favorite=0.035,dungeon=0.170,level=0.050,season=0.090,result=0.085,
    margin=0.065,character=0.105,role=0.040,quality=0.065,notes=0.040,
    tags=0.070,group=0.075,date=0.075,actions=0.035,
}
local COL_DROP = { "season", "notes", "tags", "quality", "group" }

-- El minimo de verdad: el mayor entre el de los datos y el del titulo, con
-- sus margenes. Es la misma regla que PanelHistorial:_ColumnMin.
local function minimosReales(fontSize)
    local m = {}
    for _, key in ipairs(COL_ORDER) do
        local base = COL_MIN_DATOS[key]
        local titulo = COL_TITULO[key]
        if titulo ~= "" then
            local necesario = anchoTexto(titulo, fontSize or 12) + 20
            if necesario > base then base = necesario end
        end
        m[key] = base
    end
    return m
end

local function columnas(total, fontSize)
    local mins = minimosReales(fontSize)
    local anchos, sueltas, usado = Widgets:FitColumns({
        total = total, order = COL_ORDER, mins = mins,
        weights = COL_PESOS, dropOrder = COL_DROP,
    })
    return anchos, sueltas, usado, mins
end

test("E1 los minimos de fabrica sumaban mas que la ventana: ese era el bug", function()
    local suma = 0
    for _, key in ipairs(COL_ORDER) do suma = suma + COL_MIN_DATOS[key] end
    equal(suma, 1255, "los minimos suman 1255 px")
    -- La ventana de la captura mide 1057; el contenedor de la tabla, menos.
    truthy(suma > 1040, "no cabian en el contenedor real (~1040 px)")
end)

test("E2 el caso de la captura: nada se sale de la ventana", function()
    local anchos, sueltas, usado = columnas(1040)
    equal(usado, 1040, "las columnas ocupan EXACTAMENTE el ancho disponible")
    truthy(next(sueltas) ~= nil, "ha tenido que soltar alguna")
    -- Y lo primero que suelta es TEMPORADA, que pone "Midnight" en 20 filas.
    truthy(sueltas.season, "la primera en caer es TEMPORADA")
end)

test("E3 ninguna columna visible baja de lo que mide su titulo", function()
    for _, total in ipairs({ 1920, 1400, 1200, 1040, 900, 800 }) do
        local anchos, sueltas, _, mins = columnas(total)
        for _, key in ipairs(COL_ORDER) do
            if not sueltas[key] and COL_TITULO[key] ~= "" then
                atLeast(anchos[key], anchoTexto(COL_TITULO[key], 12),
                    "el titulo " .. COL_TITULO[key] .. " cabe con " .. total .. " px")
            end
        end
    end
end)

test("E4 la suma nunca pasa del ancho disponible, en ningun tamano", function()
    for total = 1920, 300, -20 do
        local _, _, usado = columnas(total)
        atMost(usado, total, "cabe todo con " .. total .. " px")
    end
end)

test("E5 la ultima columna llega justo al borde, sin franja muerta", function()
    for _, total in ipairs({ 1920, 1500, 1040, 820, 640 }) do
        local _, _, usado = columnas(total)
        equal(usado, total, "sin hueco ni desbordamiento con " .. total .. " px")
    end
end)

test("E6 con la ventana ancha se ven las catorce", function()
    local anchos, sueltas = columnas(1920)
    for _, key in ipairs(COL_ORDER) do
        falsy(sueltas[key], "no se suelta " .. key .. " con 1920 px")
        truthy(anchos[key] and anchos[key] > 0, "tiene ancho: " .. key)
    end
end)

test("E7 se sueltan por orden de menos valor, y las importantes nunca", function()
    local soltadasEn = {}
    for total = 1920, 300, -10 do
        local _, sueltas = columnas(total)
        for _, key in ipairs(COL_DROP) do
            if sueltas[key] and not soltadasEn[key] then soltadasEn[key] = total end
        end
        -- Las de siempre no se sueltan JAMAS, ni en la ventana mas estrecha.
        for _, key in ipairs({ "favorite","dungeon","level","result","margin",
                               "character","role","date","actions" }) do
            falsy(sueltas[key], key .. " no debe soltarse nunca (" .. total .. " px)")
        end
    end
    -- Orden: TEMPORADA antes que NOTA, NOTA antes que ETIQUETA, etc.
    local previo = nil
    for _, key in ipairs(COL_DROP) do
        truthy(soltadasEn[key], key .. " llega a soltarse")
        if previo then
            atMost(soltadasEn[key], previo,
                key .. " se suelta despues que la anterior")
        end
        previo = soltadasEn[key]
    end
end)

test("E8 soltar una columna ensancha a las demas, no deja un hueco", function()
    -- Justo antes y justo despues de soltar TEMPORADA.
    local sueltaEn
    for total = 1400, 600, -2 do
        local _, sueltas = columnas(total)
        if sueltas.season then sueltaEn = total; break end
    end
    truthy(sueltaEn, "hay un punto donde se suelta")
    local antes = columnas(sueltaEn + 2)
    local despues = columnas(sueltaEn)
    -- MAZMORRA es la que mas peso tiene: gana sitio al soltarse TEMPORADA.
    atLeast(despues.dungeon, antes.dungeon,
        "MAZMORRA no pierde ancho cuando desaparece una columna")
end)

test("E9 con una fuente mas grande los titulos siguen cabiendo", function()
    -- mono 12 -> mono 16: los titulos piden mas y el reparto lo respeta.
    local anchos, sueltas, usado = columnas(1040, 16)
    atMost(usado, 1040, "sigue sin salirse")
    for _, key in ipairs(COL_ORDER) do
        if not sueltas[key] and COL_TITULO[key] ~= "" then
            atLeast(anchos[key], anchoTexto(COL_TITULO[key], 16),
                "cabe " .. COL_TITULO[key] .. " a tamano 16")
        end
    end
    -- Y ha tenido que soltar mas columnas que con la fuente normal.
    local _, pocas = columnas(1040, 12)
    local n1, n2 = 0, 0
    for _ in pairs(pocas) do n1 = n1 + 1 end
    for _ in pairs(sueltas) do n2 = n2 + 1 end
    atLeast(n2, n1, "con letra mas grande se sueltan al menos tantas")
end)

test("E10 ventana absurdamente estrecha: se escala, no se desborda", function()
    -- Ni soltandolas todas caben: entonces se aprietan hasta el limite.
    local anchos, sueltas, usado = columnas(420)
    atMost(usado, 420, "no se sale ni con 420 px")
    for _, key in ipairs(COL_ORDER) do
        if not sueltas[key] then
            truthy(anchos[key] > 0, "ninguna columna con ancho cero: " .. key)
        end
    end
end)

test("E12 si MAZMORRA pide mas sitio, lo consigue soltando relleno", function()
    -- Era la truncadura mas visible: "Estanques de Vida...". Ahora esa columna
    -- pide lo que mide el nombre mas largo y las de relleno le dejan sitio.
    local nombres = { "Estanques de Vida Rubí", "El Valle Enceguecedor",
                      "El Frontal de la Muerte", "Templo de Sethraliss",
                      "Reposo de los Reyes", "Guarida de Nalorakk" }
    local masLargo = 0
    for _, n in ipairs(nombres) do
        local w = anchoTexto(n, 14)     -- la fuente de las celdas
        if w > masLargo then masLargo = w end
    end
    local pide = masLargo + 32 + 8      -- hueco del icono y margenes

    local mins = minimosReales(12)
    if pide > mins.dungeon then mins.dungeon = pide end
    local anchos, sueltas, usado = Widgets:FitColumns({
        total = 1040, order = COL_ORDER, mins = mins,
        weights = COL_PESOS, dropOrder = COL_DROP,
    })
    equal(usado, 1040, "sigue cabiendo exactamente")
    atLeast(anchos.dungeon, pide, "MAZMORRA cabe el nombre mas largo")
    -- Y el hueco sale de las columnas de relleno, no de las importantes.
    for _, key in ipairs({ "dungeon","level","result","margin","character","date" }) do
        falsy(sueltas[key], key .. " sigue en la tabla")
    end
end)

test("E13 MAZMORRA no se come la tabla entera", function()
    -- Con un nombre desmesurado, el tope la frena: la columna es importante,
    -- pero no puede dejar el resto de la fila sin sitio.
    local mins = minimosReales(12)
    mins.dungeon = 2000
    local anchos, sueltas, usado = Widgets:FitColumns({
        total = 1040, order = COL_ORDER, mins = mins,
        weights = COL_PESOS, dropOrder = COL_DROP,
    })
    atMost(usado, 1040, "no se desborda ni asi")
    -- Se escala todo, asi que las demas conservan algo de ancho.
    for _, key in ipairs({ "level","result","character","date" }) do
        truthy((anchos[key] or 0) > 0, key .. " conserva ancho")
    end
end)

test("E11 sin columnas que soltar tampoco se desborda", function()
    local _, _, usado = Widgets:FitColumns({
        total = 300, order = COL_ORDER, mins = minimosReales(12),
        weights = COL_PESOS, dropOrder = {},
    })
    atMost(usado, 300, "se escala aunque no haya nada que soltar")
end)

return { tests = tests, assertions = assertions }
