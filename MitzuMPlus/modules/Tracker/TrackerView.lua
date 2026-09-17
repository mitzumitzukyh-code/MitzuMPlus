-- ===========================================================================
-- MitzuMPlus - Tracker/TrackerView  (dev.8 simulador del tracker de Blizzard,
-- dev.9 mismas anclas de fuerzas que el render integrado)
--
-- Ventana flotante SOLO para vista previa (herramienta de configuracion/QA
-- fuera de llave) y el resumen final. Durante una llave real nunca se usa:
-- los datos van dentro del tracker de Blizzard (BlizzardTrackerEnhancer).
--
-- Desde dev.8 imita el espacio estrecho real del bloque de Mitica+ (251 px)
-- con elementos PROPIOS que se parecen a los de Blizzard, y coloca las lineas
-- de Mitzu con la MISMA decision pura que el enhancer
-- (TrackerPresenter.LayoutEmbedded). Asi la vista previa ensena lo que se
-- vera en la llave:
--
--   Reposo de los Reyes
--      Nivel 12
--      19:37  +3 6:25                     <- reloj + un solo umbral
--             RITMO +2  50%     -0:15 [x]3
--      [=========barra de tiempo========]
--    [v] Jefe 1 ...
--    Fuerzas enemigas
--    [==========73%=========]              <- % entero, como Blizzard
--    449 / 608              faltan 159     <- lineas de Mitzu
--
-- No lee APIs de Blizzard ni estado del juego; no toca frames de Blizzard.
-- Frames, texturas y FontStrings se crean una vez; Render cachea escrituras.
-- ===========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local TV = {}
MitzuMPlus.TrackerView = TV

-- Geometria copiada del bloque de Blizzard (px) para que el ancho util sea real.
TV.BLOCK_W, TV.BLOCK_H = 251, 87
TV.LEVEL_X, TV.DEATH_RIGHT, TV.GAP, TV.LOOT_ICON, TV.LINE_2_Y = 28, 47, 8, 24, -14
TV.BAR_W = 191
-- Mismos numeros que E.LAYOUT en el enhancer: la vista previa debe ensenar la
-- misma fila de fuerzas que se vera dentro del bloque de Blizzard.
TV.FORCES_GAP_Y, TV.FORCES_ROW_H, TV.FORCES_INSET = -1, 12, 1
TV.MAX_BOSSES = 4
TV.WIDTH = TV.BLOCK_W + 20
TV.HEADER_H, TV.BOSS_H = 22, 16
TV.HEIGHT = TV.HEADER_H + TV.BLOCK_H + TV.MAX_BOSSES * TV.BOSS_H + 58
TV.WHITE = "Interface\\Buttons\\WHITE8X8"

TV.FONT = {
    threshold = "GameFontHighlight", pace = "GameFontHighlightSmall", secondary = "GameFontDisableSmall",
    forces = "GameFontHighlightSmall", penalty = "GameFontHighlightSmall", timer = "GameFontHighlightHuge",
}
TV.COLOR = {
    bg       = { 0, 0, 0, 0.45 },
    title    = { 1.00, 0.82, 0.00 },
    code     = { ["+3"] = "40ff73", ["+2"] = "ffd100", ["+1"] = "ff9933", OVERTIME = "ff4545" },
    label    = "c8c8d2",       -- dev.9: legible en combate, aun secundaria
    timeBarBg = { 0.10, 0.10, 0.12, 0.9 },
    timeBar  = { 0.95, 0.80, 0.25, 0.9 },
    forcesBg = { 0.08, 0.08, 0.10, 0.9 },
    forces   = { 0.35, 0.55, 0.95, 1 },
    done     = { 0.60, 0.60, 0.60 },
    penalty  = { 1.00, 0.40, 0.40, 0.9 },
    overtime = { 1.00, 0.10, 0.10 },
    preview  = { 0.64, 0.21, 0.93 },
}

local function colored(code)
    local hex = code and TV.COLOR.code[code]
    return hex and ("|cff" .. hex .. code .. "|r") or code
end

-- ---------------------------------------------------------------------------
-- CONSTRUCCION  (una vez)
-- ---------------------------------------------------------------------------

local function fs(parent, template, justify)
    local t = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    t:SetJustifyH(justify or "LEFT")
    t:SetJustifyV("BOTTOM")
    t:SetWordWrap(false)
    return t
end

local function tex(parent, layer, color)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(TV.WHITE)
    if color then t:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
    return t
end

function TV:Create(parent, name)
    if self.frame then return self.frame end
    local C = TV.COLOR
    local f = CreateFrame("Frame", name, parent or UIParent)
    f:SetSize(TV.WIDTH, TV.HEIGHT)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    local r = {}
    self.r, self.frame, self._cache, self._widths = r, f, {}, {}

    r.bg = tex(f, "BACKGROUND", C.bg); r.bg:SetAllPoints(f)

    r.header = fs(f, "GameFontNormal")
    r.header:SetPoint("TOPLEFT", 10, -6); r.header:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    r.header:SetTextColor(C.title[1], C.title[2], C.title[3], 1)

    local block = CreateFrame("Frame", nil, f)
    block:SetSize(TV.BLOCK_W, TV.BLOCK_H)
    block:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -TV.HEADER_H)
    r.block = block
    r.level = fs(block, "GameFontNormalMed2")
    r.level:SetPoint("TOPLEFT", TV.LEVEL_X, -18)
    r.timeLeft = fs(block, "GameFontHighlightHuge")
    r.timeLeft:SetPoint("TOPLEFT", r.level, "BOTTOMLEFT", 0, -8)
    r.threshold = fs(block, TV.FONT.threshold)
    r.pace = fs(block, TV.FONT.pace)
    r.paceExtra = fs(block, TV.FONT.secondary)
    r.paceExtra:SetPoint("LEFT", r.pace, "RIGHT", 6, 0)
    r.death = CreateFrame("Frame", nil, block)
    r.death:SetSize(20, 16)
    r.death:SetPoint("TOPLEFT", block, "BOTTOMRIGHT", -TV.DEATH_RIGHT, 43)
    r.deathIcon = r.death:CreateTexture(nil, "ARTWORK")
    r.deathIcon:SetAtlas("poi-graveyard-neutral", true)
    r.deathIcon:SetPoint("LEFT")
    r.deathCount = fs(r.death, "GameFontHighlightSmall")
    r.deathCount:SetPoint("LEFT", r.deathIcon, "RIGHT", 1, 0)
    r.penalty = fs(block, TV.FONT.penalty, "RIGHT")
    r.penalty:SetPoint("RIGHT", r.death, "LEFT", -2, 0)
    r.penalty:SetTextColor(C.penalty[1], C.penalty[2], C.penalty[3], C.penalty[4])
    r.timeBarBg = tex(block, "ARTWORK", C.timeBarBg)
    r.timeBarBg:SetSize(207, 13); r.timeBarBg:SetPoint("BOTTOM", block, "BOTTOM", 0, 10)
    r.timeBar = tex(block, "ARTWORK", C.timeBar)
    r.timeBar:SetHeight(13); r.timeBar:SetPoint("LEFT", r.timeBarBg, "LEFT", 0, 0)

    r.bosses = {}
    for i = 1, TV.MAX_BOSSES do
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -(TV.HEADER_H + TV.BLOCK_H + 4 + (i - 1) * TV.BOSS_H))
        local line = fs(f, "GameFontHighlight")
        line:SetPoint("LEFT", icon, "RIGHT", 4, 0); line:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        r.bosses[i] = { icon = icon, line = line }
    end

    local forcesTop = -(TV.HEADER_H + TV.BLOCK_H + 6 + TV.MAX_BOSSES * TV.BOSS_H)
    r.forcesTitle = fs(f, "GameFontHighlight")
    r.forcesTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 36, forcesTop)
    r.forcesBarBg = tex(f, "ARTWORK", C.forcesBg)
    r.forcesBarBg:SetSize(TV.BAR_W, 17)
    r.forcesBarBg:SetPoint("TOPLEFT", f, "TOPLEFT", 40, forcesTop - 16)
    r.forcesBar = tex(f, "ARTWORK", C.forces)
    r.forcesBar:SetHeight(17); r.forcesBar:SetPoint("LEFT", r.forcesBarBg, "LEFT", 0, 0)
    r.forcesLabel = fs(f, "GameFontHighlightMedium", "CENTER")
    r.forcesLabel:SetPoint("CENTER", r.forcesBarBg, "CENTER", 0, 0)
    -- Fila propia anclada a los dos extremos de la barra; las dos columnas
    -- comparten borde inferior, asi que comparten base (misma jerarquia que el
    -- render integrado: recuento legible, restantes en gris).
    r.forcesRow = CreateFrame("Frame", nil, f)
    r.forcesRow:SetHeight(TV.FORCES_ROW_H)
    r.forcesRow:SetPoint("TOPLEFT", r.forcesBarBg, "BOTTOMLEFT", 0, TV.FORCES_GAP_Y)
    r.forcesRow:SetPoint("TOPRIGHT", r.forcesBarBg, "BOTTOMRIGHT", 0, TV.FORCES_GAP_Y)
    r.forcesPrimary = fs(r.forcesRow, TV.FONT.forces)
    r.forcesPrimary:SetPoint("BOTTOMLEFT", r.forcesRow, "BOTTOMLEFT", TV.FORCES_INSET, 0)
    r.forcesSecondary = fs(r.forcesRow, TV.FONT.secondary, "RIGHT")
    r.forcesSecondary:SetPoint("BOTTOMRIGHT", r.forcesRow, "BOTTOMRIGHT", -TV.FORCES_INSET, 0)

    r.measure = {}
    for kind, template in pairs(TV.FONT) do
        r.measure[kind] = fs(f, template)
        r.measure[kind]:Hide()
    end

    -- Marca de vista previa: fuera del marco, como pestana.
    r.tag = fs(f, "GameFontNormalSmall")
    r.tag:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 4, 2)
    r.tag:SetTextColor(C.preview[1], C.preview[2], C.preview[3], 1)
    r.tag:Hide()

    f:Hide()
    return f
end

-- ---------------------------------------------------------------------------
-- PINTADO  (solo lo que cambia)
-- ---------------------------------------------------------------------------

function TV:_Text(key, region, value)
    value = value or ""
    if self._cache[key] ~= value then
        region:SetText(value)
        self._cache[key] = value
    end
    if value == "" then region:Hide() else region:Show() end
end

function TV:_Width(key, region, width)
    width = math.floor(width + 0.5)
    if self._cache[key] == width then return end
    self._cache[key] = width
    if width <= 0 then region:Hide() else region:SetWidth(width); region:Show() end
end

function TV:_Place(key, sig, fn)
    if self._cache[key] == sig then return end
    self._cache[key] = sig
    fn()
end

function TV:ResetCache() self._cache, self._widths = {}, {} end

function TV:_Measure(text, kind)
    local key = kind .. ":" .. text
    local v = self._widths[key]
    if v then return v end
    local m = self.r.measure[kind] or self.r.measure.pace
    m:SetText(text)
    v = m:GetStringWidth() or (#text * 6)
    self._widths[key] = v
    return v
end

-- Devuelve lo que quedo pintado (para diagnostico). Nunca lee el juego.
function TV:Render(m)
    local f = self.frame
    if not f then return nil end
    local r, C, TP = self.r, TV.COLOR, MitzuMPlus.TrackerPresenter
    local shown = { mode = m.mode }

    if m.mode == "HIDDEN" then
        if f:IsShown() then f:Hide() end
        return shown
    end
    local summary = m.summary
    self:_Text("tag", r.tag, m.preview and TP.TEXT.PREVIEW or "")
    self:_Text("header", r.header, m.dungeonName)

    -- Bloque: nivel y reloj como los pinta Blizzard (restante; al terminar, final).
    local t = m.timer or {}
    local clock = summary and TP.FormatClock(t.elapsed) or (t.remaining and TP.FormatClock(math.max(0, t.remaining))) or TP.TEXT.NO_TIMER
    self:_Text("level", r.level, summary and summary.title or (m.keyLevel and ("Nivel " .. m.keyLevel) or ""))
    self:_Text("timeLeft", r.timeLeft, clock)
    local red = t.overtime and not summary
    if self._cache.timeRed ~= red then
        self._cache.timeRed = red
        local c = red and C.overtime or { 1, 1, 1 }
        r.timeLeft:SetTextColor(c[1], c[2], c[3], 1)
    end
    self:_Width("timeBar", r.timeBar, 207 * (t.fraction and (1 - t.fraction) or 0))
    shown.timer = clock

    -- Lineas de Mitzu con la misma decision que el enhancer.
    local timeW = self:_Measure(clock, "timer")
    local offsetX = TV.GAP + (red and TV.LOOT_ICON or 0)
    local d = m.deaths or {}
    local deaths = (d.count and d.count > 0) and tostring(math.floor(d.count)) or ""
    self:_Text("deathCount", r.deathCount, deaths)
    if deaths ~= "" then r.death:Show() else r.death:Hide() end
    shown.deaths = d.text

    if summary then
        local p = m.prediction or {}
        self:_Text("threshold", r.threshold, p.code ~= TP.NONE and colored(p.code) or "")
        self:_Text("pace", r.pace, summary.timeText or "")
        self:_Text("paceExtra", r.paceExtra, p.sourceText or "")
        self:_Text("penalty", r.penalty, d.penaltyText and ("-" .. d.penaltyText:sub(2)) or "")
        shown.prediction = p.code or TP.NONE
    else
        local emb = TP.BuildEmbedded(m, { simulate = true })
        local penalty = (deaths ~= "" and emb.penaltyText) or ""
        self:_Text("penalty", r.penalty, penalty)
        local penaltyW = penalty ~= "" and (self:_Measure(penalty, "penalty") + 4) or 0
        local available = TV.BLOCK_W - TV.DEATH_RIGHT - 4 - penaltyW - (TV.LEVEL_X + timeW + offsetX)
        local lay = TP.LayoutEmbedded(emb, { timerWidth = available, forcesWidth = TV.BAR_W },
            function(text, kind) return self:_Measure(text, kind) end)
        local th, pc, fo = lay.threshold, lay.pace, lay.forces
        self:_Text("threshold", r.threshold, th.text and (colored(th.upgrade) .. " " .. th.timeText) or "")
        self:_Text("pace", r.pace, pc.text and ("|cff" .. C.label .. pc.label .. "|r " .. colored(pc.value)) or "")
        local extras = {}
        if pc.confidence then extras[#extras + 1] = pc.confidence end
        if pc.eta then extras[#extras + 1] = pc.eta end
        self:_Text("paceExtra", r.paceExtra, table.concat(extras, "  "))
        self:_Text("forcesPrimary", r.forcesPrimary, fo.primary)
        self:_Text("forcesSecondary", r.forcesSecondary, fo.secondary)
        shown.prediction = pc.text and (emb.paceCode or TP.NONE) or TP.NONE
        shown.confidence = pc.confidence and (m.prediction or {}).confidence or nil
        shown.threshold, shown.thresholdMode, shown.paceMode, shown.forcesLayoutMode = th.text, th.mode, pc.mode, fo.mode
        shown.forces = (fo.primary or fo.secondary) and table.concat({ fo.primary or "", fo.secondary or "" },
            fo.primary and fo.secondary and "  " or "") or nil
        shown.available = math.floor(available + 0.5)
    end
    self:_Place("lines", tostring(offsetX), function()
        r.threshold:ClearAllPoints(); r.pace:ClearAllPoints()
        r.threshold:SetPoint("TOPLEFT", r.timeLeft, "TOPRIGHT", offsetX, -1)
        r.pace:SetPoint("TOPLEFT", r.timeLeft, "TOPRIGHT", offsetX, TV.LINE_2_Y)
    end)

    -- Jefes (datos del modelo; en el resumen, inferidos si procede).
    local b = m.bosses or {}
    for i = 1, TV.MAX_BOSSES do
        local row, info = r.bosses[i], b.list and b.list[i]
        local total = b.available and b.total or 0
        if i <= total then
            local done = info and info.completed or ((b.completed or 0) >= i)
            local name = info and info.name or ("Jefe " .. i)
            self:_Text("boss" .. i, row.line, name)
            if self._cache["bossDone" .. i] ~= done then
                self._cache["bossDone" .. i] = done
                row.icon:SetAtlas(done and "ui-questtracker-tracker-check" or "ui-questtracker-objective-nub", false)
                local c = done and C.done or { 1, 1, 1 }
                row.line:SetTextColor(c[1], c[2], c[3], 1)
            end
            row.icon:Show()
        else
            self:_Text("boss" .. i, row.line, "")
            row.icon:Hide()
        end
    end
    shown.bosses = b.available and (b.text .. (b.inferred and " (inferred)" or "")) or "NONE"

    -- Barra de fuerzas con el % ENTERO de Blizzard; las lineas de Mitzu debajo.
    local fo = m.forces or {}
    self:_Text("forcesTitle", r.forcesTitle, TP.TEXT.FORCES)
    self:_Width("forcesBar", r.forcesBar, TV.BAR_W * (fo.fraction or 0))
    self:_Text("forcesLabel", r.forcesLabel, fo.percent and string.format("%d%%", math.floor(fo.percent)) or "")
    if summary then
        self:_Text("forcesPrimary", r.forcesPrimary, fo.countText)
        self:_Text("forcesSecondary", r.forcesSecondary, "")
        shown.forces = fo.available and ((fo.countText or "?") .. " " .. (fo.percentText or "")) or "NONE"
    end

    if not f:IsShown() then f:Show() end
    return shown
end

return TV
