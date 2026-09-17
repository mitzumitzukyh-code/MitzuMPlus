-- ===========================================================================
-- MitzuMPlus - Tracker/TrackerView  (1.1.0-dev.6, Mitzu Tracker V1)
--
-- Pinta el modelo de TrackerPresenter. No lee APIs de Blizzard ni estado del
-- juego (lo vigila tests/run_static_checks.py): solo frames, texturas y texto.
--
--   Reposo de los Reyes                      [+12]
--   19:37                              RITMO  +2
--   13:23 / 33:00                 50%  final ~31:10
--   ======|====|=====================----------
--   +3 6:25          +2 13:01           +1 19:37
--   Fuerzas enemigas                     73.85%
--   ##############################-----------
--   449 / 608                        faltan 159
--   Jefes 2/4  [x][x][ ][ ]           Muertes 3 +0:15
--
-- RENDIMIENTO
--   * Los frames, texturas y FontStrings se crean UNA vez (Create).
--   * Render solo toca lo que cambio: cada texto, color, ancho o visibilidad
--     pasa por una cache y no se reescribe si es igual.
--   * Altura fija: nada salta de sitio entre estados.
--
-- COMBATE: frame propio sin plantillas seguras; nada de esto es protegido.
-- ===========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local TV = {}
MitzuMPlus.TrackerView = TV

TV.WIDTH, TV.HEIGHT, TV.PAD = 280, 172, 10
TV.MAX_PIPS = 8
TV.WHITE = "Interface\\Buttons\\WHITE8X8"

-- Identidad Mitzu: pizarra oscura, oro tenue de WoW en el marco, color solo
-- donde aporta. El resultado nunca depende solo del color: siempre va el texto.
TV.COLOR = {
    bg        = { 0.030, 0.034, 0.045, 0.86 },
    border    = { 0.78, 0.63, 0.30, 0.35 },
    accentOff = { 0.35, 0.35, 0.38, 0.9 },
    title     = { 1.00, 0.82, 0.00 },
    text      = { 0.95, 0.95, 0.95 },
    dim       = { 0.58, 0.58, 0.62 },
    faint     = { 0.38, 0.38, 0.42 },
    badgeBg   = { 0.16, 0.13, 0.07, 0.95 },
    barBg     = { 0.12, 0.12, 0.15, 0.95 },
    forces    = { 0.30, 0.66, 1.00 },
    forcesDone= { 0.25, 0.90, 0.45 },
    timeBar   = { 0.85, 0.85, 0.88 },
    tick      = { 1.00, 1.00, 1.00, 0.85 },
    overtime  = { 1.00, 0.27, 0.27 },
    preview   = { 0.64, 0.21, 0.93 },
    ["+3"]    = { 0.25, 1.00, 0.45 },
    ["+2"]    = { 0.72, 0.95, 0.30 },
    ["+1"]    = { 1.00, 0.82, 0.00 },
    OVERTIME  = { 1.00, 0.27, 0.27 },
    NONE      = { 0.58, 0.58, 0.62 },
}

-- ---------------------------------------------------------------------------
-- CONSTRUCCION  (una vez)
-- ---------------------------------------------------------------------------

local function fontPath()
    local obj = rawget(_G, "GameFontNormal")
    if obj and obj.GetFont then
        local ok, path = pcall(obj.GetFont, obj)
        if ok and type(path) == "string" then return path end
    end
    return rawget(_G, "STANDARD_TEXT_FONT") or "Fonts\\FRIZQT__.TTF"
end

local function text(parent, template, size, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    if size then pcall(fs.SetFont, fs, fontPath(), size, flags or "") end
    fs:SetWordWrap(false)
    if fs.SetMaxLines then fs:SetMaxLines(1) end
    return fs
end

local function tex(parent, layer, color)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(TV.WHITE)
    if color then t:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
    return t
end

function TV:Create(parent, name)
    if self.frame then return self.frame end
    local C, P, W = TV.COLOR, TV.PAD, TV.WIDTH
    local inner = W - 2 * P
    local f = CreateFrame("Frame", name, parent or UIParent)
    f:SetSize(W, TV.HEIGHT)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")

    local r = {}
    self.r, self.frame, self._cache = r, f, {}

    -- Fondo plano y borde de 1 px (sin marco de ventana).
    r.bg = tex(f, "BACKGROUND", C.bg); r.bg:SetAllPoints(f)
    local function edge(p1, p2, horizontal)
        local t = tex(f, "BORDER", C.border)
        t:SetPoint(p1); t:SetPoint(p2)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
        return t
    end
    r.edgeTop = edge("TOPLEFT", "TOPRIGHT", true)
    r.edgeBottom = edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    r.edgeLeft = edge("TOPLEFT", "BOTTOMLEFT", false)
    r.edgeRight = edge("TOPRIGHT", "BOTTOMRIGHT", false)
    -- Franja de acento: el color del ritmo, 2 px a la izquierda.
    r.accent = tex(f, "ARTWORK", C.accentOff)
    r.accent:SetPoint("TOPLEFT", 1, -1); r.accent:SetPoint("BOTTOMLEFT", 1, 1); r.accent:SetWidth(2)

    -- Cabecera: la placa de nivel manda; el nombre se trunca antes de empujarla.
    r.badge = CreateFrame("Frame", nil, f)
    r.badge:SetPoint("TOPRIGHT", -P, -7)
    r.badge:SetSize(34, 16)
    r.badgeBg = tex(r.badge, "BACKGROUND", C.badgeBg); r.badgeBg:SetAllPoints(r.badge)
    r.keyText = text(r.badge, "GameFontNormal", 12, "")
    r.keyText:SetPoint("CENTER", 0, 0)
    r.keyText:SetTextColor(C.title[1], C.title[2], C.title[3], 1)

    r.title = text(f, "GameFontNormal", 12, "")
    r.title:SetPoint("TOPLEFT", P + 2, -9)
    r.title:SetPoint("RIGHT", r.badge, "LEFT", -8, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetTextColor(C.title[1], C.title[2], C.title[3], 1)

    -- Temporizador: el elemento dominante.
    r.timer = text(f, "GameFontHighlightHuge", 28, "OUTLINE")
    r.timer:SetPoint("TOPLEFT", P + 1, -27)
    r.timer:SetJustifyH("LEFT")

    r.predCode = text(f, "GameFontNormalHuge", 22, "OUTLINE")
    r.predCode:SetPoint("TOPRIGHT", -P, -30)
    r.predCode:SetJustifyH("RIGHT")
    r.predLabel = text(f, "GameFontDisableSmall", 9, "")
    r.predLabel:SetPoint("BOTTOMRIGHT", r.predCode, "BOTTOMLEFT", -5, 3)
    r.predLabel:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 1)

    r.timerSub = text(f, "GameFontHighlightSmall", 10, "")
    r.timerSub:SetPoint("TOPLEFT", P + 2, -60)
    r.timerSub:SetJustifyH("LEFT")
    r.timerSub:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 1)
    r.predSub = text(f, "GameFontHighlightSmall", 10, "")
    r.predSub:SetPoint("TOPRIGHT", -P, -60)
    r.predSub:SetPoint("LEFT", r.timerSub, "RIGHT", 6, 0)
    r.predSub:SetJustifyH("RIGHT")
    r.predSub:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 1)

    -- Barra de tiempo fina con marcas de +3 y +2.
    r.timeBar = tex(f, "ARTWORK", C.barBg)
    r.timeBar:SetPoint("TOPLEFT", P, -77); r.timeBar:SetSize(inner, 3)
    r.timeFill = tex(f, "ARTWORK", C.timeBar)
    r.timeFill:SetPoint("TOPLEFT", r.timeBar, "TOPLEFT", 0, 0); r.timeFill:SetHeight(3)
    r.ticks = {}
    for i = 1, 2 do
        local t = tex(f, "OVERLAY", C.tick)
        t:SetSize(1, 7)
        r.ticks[i] = t
    end

    -- Umbrales en tres columnas iguales: nunca se solapan.
    r.segs = {}
    local colW = inner / 3
    for i, justify in ipairs({ "LEFT", "CENTER", "RIGHT" }) do
        local s = text(f, "GameFontHighlightSmall", 10, "")
        s:SetPoint("TOPLEFT", P + (i - 1) * colW, -85)
        s:SetWidth(colW)
        s:SetJustifyH(justify)
        r.segs[i] = s
    end
    r.banner = text(f, "GameFontNormal", 11, "")
    r.banner:SetPoint("TOPLEFT", P, -85); r.banner:SetWidth(inner)
    r.banner:SetJustifyH("CENTER")

    -- Fuerzas enemigas.
    r.forcesLabel = text(f, "GameFontHighlightSmall", 11, "")
    r.forcesLabel:SetPoint("TOPLEFT", P + 2, -104)
    r.forcesLabel:SetJustifyH("LEFT")
    r.forcesLabel:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 1)
    r.forcesPct = text(f, "GameFontHighlight", 13, "")
    r.forcesPct:SetPoint("TOPRIGHT", -P, -102)
    r.forcesPct:SetJustifyH("RIGHT")
    r.forcesBar = tex(f, "ARTWORK", C.barBg)
    r.forcesBar:SetPoint("TOPLEFT", P, -119); r.forcesBar:SetSize(inner, 7)
    r.forcesFill = tex(f, "ARTWORK", C.forces)
    r.forcesFill:SetPoint("TOPLEFT", r.forcesBar, "TOPLEFT", 0, 0); r.forcesFill:SetHeight(7)
    r.forcesCount = text(f, "GameFontHighlightSmall", 10, "")
    r.forcesCount:SetPoint("TOPLEFT", P + 2, -131)
    r.forcesCount:SetJustifyH("LEFT")
    r.forcesLeft = text(f, "GameFontHighlightSmall", 10, "")
    r.forcesLeft:SetPoint("TOPRIGHT", -P, -131)
    r.forcesLeft:SetJustifyH("RIGHT")
    r.forcesLeft:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 1)

    -- Jefes y muertes.
    r.bosses = text(f, "GameFontHighlightSmall", 11, "")
    r.bosses:SetPoint("TOPLEFT", P + 2, -151)
    r.bosses:SetJustifyH("LEFT")
    r.pips = {}
    for i = 1, TV.MAX_PIPS do
        local p = tex(f, "ARTWORK", C.faint)
        p:SetSize(6, 6)
        if i == 1 then p:SetPoint("LEFT", r.bosses, "RIGHT", 6, 0)
        else p:SetPoint("LEFT", r.pips[i - 1], "RIGHT", 3, 0) end
        p:Hide()
        r.pips[i] = p
    end
    r.deaths = text(f, "GameFontHighlightSmall", 11, "")
    r.deaths:SetPoint("TOPRIGHT", -P, -151)
    r.deaths:SetJustifyH("RIGHT")

    -- Marca de vista previa: fuera del marco, como pestana.
    r.tag = text(f, "GameFontNormalSmall", 10, "")
    r.tag:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 4, 2)
    r.tag:SetTextColor(C.preview[1], C.preview[2], C.preview[3], 1)
    r.tag:Hide()

    f:Hide()
    return f
end

-- ---------------------------------------------------------------------------
-- PINTADO  (solo lo que cambia)
-- ---------------------------------------------------------------------------

function TV:_Text(key, fs, value)
    value = value or ""
    if self._cache[key] ~= value then
        fs:SetText(value)
        self._cache[key] = value
    end
end

function TV:_Color(key, region, c, alpha)
    if not c then return end
    local sig = c[1] .. "," .. c[2] .. "," .. c[3] .. "," .. (alpha or c[4] or 1)
    if self._cache[key] == sig then return end
    self._cache[key] = sig
    if region.SetTextColor then region:SetTextColor(c[1], c[2], c[3], alpha or 1)
    else region:SetVertexColor(c[1], c[2], c[3], alpha or c[4] or 1) end
end

function TV:_Shown(key, region, shown)
    shown = shown and true or false
    if self._cache[key] == shown then return end
    self._cache[key] = shown
    if shown then region:Show() else region:Hide() end
end

function TV:_Width(key, region, width)
    width = math.floor(width + 0.5)
    if self._cache[key] == width then return end
    self._cache[key] = width
    if width <= 0 then region:Hide() else region:SetWidth(width); region:Show() end
end

function TV:_Point(key, region, x)
    x = math.floor(x + 0.5)
    if self._cache[key] == x then return end
    self._cache[key] = x
    region:ClearAllPoints()
    region:SetPoint("CENTER", self.r.timeBar, "LEFT", x, 0)
end

function TV:ResetCache() self._cache = {} end

-- Devuelve lo que quedo pintado (para diagnostico). Nunca lee el juego.
function TV:Render(m)
    local f = self.frame
    if not f then return nil end
    local r, C = self.r, TV.COLOR
    local inner = TV.WIDTH - 2 * TV.PAD
    local shown = { mode = m.mode }

    if m.mode == "HIDDEN" then
        if f:IsShown() then f:Hide() end
        return shown
    end

    -- Cabecera
    self:_Text("title", r.title, m.dungeonName)
    self:_Text("key", r.keyText, m.keyText or "")
    self:_Shown("badge", r.badge, m.keyText ~= nil)
    if m.keyText then
        local w = math.max(30, math.floor((r.keyText:GetStringWidth() or 0) + 12))
        if self._cache.badgeW ~= w then r.badge:SetWidth(w); self._cache.badgeW = w end
    end
    self:_Text("tag", r.tag, m.preview and MitzuMPlus.TrackerPresenter.TEXT.PREVIEW or "")
    self:_Shown("tag", r.tag, m.preview)

    -- Temporizador
    local t = m.timer or {}
    self:_Text("timer", r.timer, t.text)
    local timerColor = t.overtime and C.overtime or C.text
    self:_Color("timerC", r.timer, timerColor, (t.stale or m.mode == "PENDING") and 0.7 or 1)
    self:_Text("timerSub", r.timerSub, t.subText)
    shown.timer = t.text

    local frac = t.fraction or 0
    self:_Width("timeFill", r.timeFill, inner * frac)
    self:_Color("timeFillC", r.timeFill, t.overtime and C.overtime or C.timeBar)
    local segs = t.segments or {}
    for i = 1, 2 do
        local seg = segs[i]
        self:_Shown("tick" .. i, r.ticks[i], seg ~= nil)
        if seg then self:_Point("tickX" .. i, r.ticks[i], inner * seg.fraction) end
    end

    -- Prediccion (o resultado en el resumen)
    local p = m.prediction or {}
    local pc = C[p.code] or C.NONE
    self:_Text("predCode", r.predCode, p.text or "--")
    self:_Color("predCodeC", r.predCode, pc, p.provisional and 0.75 or 1)
    self:_Text("predLabel", r.predLabel, p.label or "")
    self:_Color("accentC", r.accent, p.code ~= "NONE" and pc or C.accentOff)
    local parts = {}
    if p.confidenceText then parts[#parts + 1] = p.confidenceText end
    if p.etaText then parts[#parts + 1] = p.etaText end
    if p.sourceText then parts[#parts + 1] = p.sourceText end
    self:_Text("predSub", r.predSub, table.concat(parts, "  "))
    shown.prediction = p.code or "NONE"
    shown.confidence = p.confidence

    -- Umbrales o resumen
    local summary = m.summary
    self:_Shown("banner", r.banner, summary ~= nil)
    if summary then
        self:_Text("banner", r.banner, summary.title)
        self:_Color("bannerC", r.banner, p.code ~= "NONE" and pc or C.title)
    end
    for i = 1, 3 do
        local seg = segs[i]
        local fs = r.segs[i]
        self:_Shown("seg" .. i, fs, seg ~= nil and not summary)
        if seg and not summary then
            self:_Text("segT" .. i, fs, seg.text)
            local col = seg.lost and C.faint or (seg.current and C[seg.code] or C.text)
            self:_Color("segC" .. i, fs, col)
        end
    end

    -- Fuerzas
    local fo = m.forces or {}
    self:_Text("forcesLabel", r.forcesLabel, MitzuMPlus.TrackerPresenter.TEXT.FORCES)
    self:_Text("forcesPct", r.forcesPct, fo.percentText)
    self:_Color("forcesPctC", r.forcesPct, fo.complete and C.forcesDone or C.text, fo.stale and 0.7 or 1)
    self:_Width("forcesFill", r.forcesFill, inner * (fo.fraction or 0))
    self:_Color("forcesFillC", r.forcesFill, fo.complete and C.forcesDone or C.forces, fo.stale and 0.6 or 1)
    self:_Text("forcesCount", r.forcesCount, fo.countText or "")
    self:_Text("forcesLeft", r.forcesLeft, fo.remainingText or "")
    shown.forces = fo.available and ((fo.countText or "?") .. " " .. fo.percentText) or "NONE"

    -- Jefes (marcas solo con total real) y muertes
    local b = m.bosses or {}
    self:_Text("bosses", r.bosses, (b.label or "") .. " " .. (b.text or "--"))
    self:_Color("bossesC", r.bosses, b.complete and C.forcesDone or C.text, b.stale and 0.7 or 1)
    local total = (b.available and b.total) or 0
    for i = 1, TV.MAX_PIPS do
        local on = i <= total
        self:_Shown("pip" .. i, r.pips[i], on)
        if on then
            local killed = (b.completed or 0) >= i
            self:_Color("pipC" .. i, r.pips[i], killed and C.forcesDone or C.faint)
        end
    end
    shown.bosses = b.available and (b.text .. (b.inferred and " (inferred)" or "")) or "NONE"

    local d = m.deaths or {}
    self:_Text("deaths", r.deaths, (d.label or "") .. " " .. (d.text or "--") .. (d.penaltyText and ("  " .. d.penaltyText) or ""))
    self:_Color("deathsC", r.deaths, (d.count or 0) > 0 and C.text or C.dim)
    shown.deaths = d.text

    if not f:IsShown() then f:Show() end
    return shown
end

return TV
