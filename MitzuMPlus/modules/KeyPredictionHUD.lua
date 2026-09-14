-- ===========================================================================
-- MitzuMPlus  -  Key Prediction HUD  -  el único HUD en vivo durante una Mythic+
--
--   ┌------------------------------------------┐
--   │ Estanques de Vida Rubí +10               │
--   │ 18:42 / 30:00                     ┌--┐   │
--   │ Confianza 82%  -  final ~23:10      │+2│   │
--   └------------------------------------------┘
--   (la predicción, grande y a color, a la derecha de las dos filas de abajo)
--
-- UNA SOLA MISIÓN: decir si la llave acaba en +3, +2, +1 o fuera de tiempo.
-- No sabe nada de pulls, rutas, packs, bosses siguientes ni posición física.
--
-- =========================================================================
-- LA REGLA: EL HUD ES UNA VISTA, NO UNA AUTORIDAD
--
-- Cada refresco construye un MODELO leyendo a las autoridades y lo pinta:
--
--   DungeonContext   -> estado de la llave, mazmorra, nivel
--   ChallengeClock   -> tiempo transcurrido y límite (servidor, sobrevive al /reload)
--   PredictionEngine -> bracket, confianza y proyección (que a su vez lee
--                       KeystoneTracker: fuerzas, bosses, muertes)
--   RUN_COMPLETED    -> el resultado oficial al terminar (nivel de mejora)
--
-- NO lee RouteProgress, RouteManager, RunSession, AdaptiveRoute, CoachAdvice,
-- placas ni nada de MitzuRouteArrows. Un test lo comprueba sobre el código.
--
-- Lo único que recuerda es lo que PINTÓ (para no repintar texto igual, para
-- el Bug Report y para enseñar la última predicción si la llave termina sin
-- resultado oficial). Eso es memoria de la vista, no estado del juego.
--
-- VISIBILIDAD (de DungeonContext):
--   OUTSIDE / IN_UNSUPPORTED_DUNGEON  oculto
--   PRE_KEY                           mazmorra + "Esperando piedra"
--   RUNNING                           tracker completo
--   COMPLETED                         resultado final unos segundos
--   RESET                             oculto
--
-- COMBATE: frame propio, sin plantillas seguras. Escala, alfa, posición y
-- ratón se aplican fuera de combate (si llegan en combate, se aplazan).
-- ===========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local HUD = {}
MitzuMPlus.KeyPredictionHUD = HUD

HUD.IMPLEMENTATION   = "KEY_PREDICTION_HUD"
HUD.MODES            = { HIDDEN = "HIDDEN", PREPARE = "PREPARE", RUN = "RUN", SUMMARY = "SUMMARY" }
HUD.SUMMARY_SECONDS  = 20
HUD.WIDTH            = 260
HUD.CALCULATING      = "CALCULANDO..."

-- Traducción del bracket de PredictionEngine al código que enseña el HUD.
-- Es una lista blanca: cualquier otra cosa (nil, secreto, texto raro) es "no
-- hay predicción", nunca un valor pintado a ciegas.
HUD.RESULT_CODE = { ["+3"] = "+3", ["+2"] = "+2", ["+1"] = "+1", ["FUERA"] = "OVERTIME" }

-- Memoria de la VISTA. Nada de esto es estado del juego.
HUD._frame          = nil
HUD._preview        = false
HUD._mode           = "HIDDEN"
HUD._displayed      = { mode = "HIDDEN" }
HUD._lastReason     = nil
HUD._lastRefreshAt  = nil
HUD._lastError      = nil
HUD._summaryUntil   = nil
HUD._final          = nil     -- resultado oficial recibido en RUN_COMPLETED
HUD._lastPrediction = nil     -- última predicción pintada en RUN
HUD._ticker         = nil
HUD._tick           = 0
HUD._pendingApply   = false
HUD._textCache      = {}

local function now()
    local ok, v = pcall(function() return GetTime and GetTime() end)
    return (ok and tonumber(v)) or 0
end

local function Safe() return MitzuMPlus.QASafe end
local function num(v)
    local S = Safe()
    if S then return S.Number(v) end
    return tonumber(v)
end
-- Texto utilizable para pintar, o nil. Un valor secreto nunca se pinta.
local function str(v)
    local S = Safe()
    if v == nil or (S and S.IsSecret(v)) or type(v) ~= "string" then return nil end
    return v
end

local function record(event, data)
    local FR = MitzuMPlus.FlightRecorder
    if FR and FR.Record then FR:Record("HUD", event, data) end
end

local function inCombat()
    local ok, v = pcall(function() return InCombatLockdown and InCombatLockdown() end)
    return ok and v == true
end

local function method(obj, name, ...)
    if type(obj) ~= "table" or type(obj[name]) ~= "function" then return nil end
    local ok, a, b, c = pcall(obj[name], obj, ...)
    if not ok then return nil end
    return a, b, c
end

-- -------------------------------------------------------------------------
-- AJUSTES  (MitzuMPlusDB.profile.settings.hud)
-- -------------------------------------------------------------------------

HUD.DEFAULTS = {
    enabled = true, locked = false, scale = 1.0, alpha = 1.0,
    showConfidence = true, showETA = true,
    point = nil, relPoint = nil, x = nil, y = nil,
}

local function clamp(v, a, b, def)
    v = tonumber(v)
    if not v then return def end
    if v < a then return a elseif v > b then return b end
    return v
end

HUD._fallback = nil

function HUD:Settings()
    local p = MitzuMPlus.db and MitzuMPlus.db.profile
    local st = p and p.settings
    if type(st) ~= "table" then
        -- Sin DB todavía: una copia en memoria, nunca los DEFAULTS compartidos.
        if not HUD._fallback then
            HUD._fallback = {}
            for k, v in pairs(HUD.DEFAULTS) do HUD._fallback[k] = v end
        end
        return HUD._fallback
    end
    if type(st.hud) ~= "table" then st.hud = {} end
    local h = st.hud
    for k, v in pairs(HUD.DEFAULTS) do
        if h[k] == nil and v ~= nil then h[k] = v end
    end
    return h
end

function HUD:IsEnabled() return self:Settings().enabled ~= false end

-- -------------------------------------------------------------------------
-- MODELO  (solo lectura de autoridades)
-- -------------------------------------------------------------------------

function HUD:_ModeFor(lifecycle)
    if not self:IsEnabled() then return "HIDDEN" end
    if lifecycle == "RUNNING" then return "RUN" end
    if lifecycle == "COMPLETED" then
        if self._summaryUntil and now() < self._summaryUntil then return "SUMMARY" end
        return "HIDDEN"
    end
    return "HIDDEN"
end

-- Extrae del snapshot de PredictionEngine SOLO lo que el HUD enseña.
-- Sin bracket reconocible no hay predicción: ni confianza ni final estimado.
function HUD.ReadPrediction(snap)
    if type(snap) ~= "table" then return nil end
    local result = str(snap.result)
    local code = result and HUD.RESULT_CODE[result] or nil
    if not code then return nil end
    local p = {
        code       = code,
        confidence = num(snap.confidence),
        confident  = snap.resultConfident == true,
    }
    -- El final estimado solo cuando el propio motor da el resultado por fiable
    -- y todavía es una proyección (con el tiempo agotado ya no hay nada que
    -- estimar: el motor devuelve el tiempo transcurrido).
    local projected = num(snap.projectedTime)
    local eff, limit = num(snap.effectiveElapsed), num(snap.timeLimit)
    if p.confident and projected and eff and limit and limit > 0 and eff < limit then
        p.estimatedFinish = projected
    end
    return p
end

-- Resultado de una llave terminada. Oficial solo si Core lo leyó de la API de
-- finalización (run.completionInfoSource). Sin esa marca, inTime=false y
-- keystoneUpgradeLevels=0 son los valores por defecto de Core, no un dato:
-- se enseña la última predicción y se dice que lo es.
function HUD.FinalFromRun(run, lastPrediction)
    if type(run) ~= "table" then return nil end
    local levels = num(run.keystoneUpgradeLevels) or 0
    local t = num(run.completionTime)
    if t and t <= 0 then t = nil end
    if str(run.completionInfoSource) and (run.inTime == true or run.inTime == false) then
        local code = "OVERTIME"
        if run.inTime == true then
            code = levels >= 3 and "+3" or (levels == 2 and "+2" or "+1")
        end
        return { code = code, source = "OFFICIAL", time = t }
    end
    return { code = lastPrediction and lastPrediction.code or nil, source = "LAST_PREDICTION", time = t }
end

function HUD:BuildModel()
    if self._preview then return self:PreviewModel() end

    local DC = MitzuMPlus.DungeonContext
    local lifecycle = method(DC, "GetState")
    local m = {
        preview   = false,
        lifecycle = lifecycle,
        mode      = self:_ModeFor(lifecycle),
        dungeon   = str(method(DC, "GetDungeonName")),
        level     = num(method(DC, "GetKeystoneLevel")),
        showConfidence = self:Settings().showConfidence ~= false,
        showETA        = self:Settings().showETA ~= false,
    }
    if m.mode == "RUN" then
        local CC = MitzuMPlus.ChallengeClock
        m.elapsed = num(method(CC, "GetElapsed"))
        m.limit   = num(method(CC, "GetTimeLimit"))
        local run = rawget(_G, "MitzuMPlusCurrentRun")
        local snap = run and method(MitzuMPlus.PredictionEngine, "GetSnapshot", run) or nil
        m.prediction = HUD.ReadPrediction(snap)
    elseif m.mode == "SUMMARY" then
        m.final = self._final or HUD.FinalFromRun({}, self._lastPrediction)
    end
    return m
end

-- Datos MOCK, exclusivamente visuales. No lee ni escribe ninguna autoridad.
-- Coherentes entre sí: 23:10 de final estimado con límite 30:00 es un +2
-- (umbral de +2 = 24:00, de +3 = 18:00).
function HUD:PreviewModel()
    return {
        preview = true, mode = "RUN", lifecycle = "PREVIEW",
        dungeon = "Ruby Life Pools", level = 10,
        elapsed = 1122, limit = 1800,
        prediction = { code = "+2", confidence = 82, confident = true, estimatedFinish = 1390 },
        showConfidence = true, showETA = true,
    }
end

-- -------------------------------------------------------------------------
-- TEXTO
-- -------------------------------------------------------------------------

local function reloj(s)
    s = num(s)
    if not s then return "-" end
    local neg = s < 0
    s = math.abs(math.floor(s))
    return string.format("%s%d:%02d", neg and "-" or "", math.floor(s / 60), s % 60)
end
HUD.FormatClock = reloj

-- Equivalentes a las constantes de color de Blizzard (NORMAL_FONT_COLOR,
-- HIGHLIGHT_FONT_COLOR, GREEN/RED_FONT_COLOR, GRAY_FONT_COLOR).
local COLOR = {
    normal    = { 1.00, 0.82, 0.00 },
    highlight = { 1.00, 1.00, 1.00 },
    green     = { 0.10, 1.00, 0.10 },
    red       = { 1.00, 0.10, 0.10 },
    gray      = { 0.50, 0.50, 0.50 },
    preview   = { 0.64, 0.21, 0.93 },   -- EPIC: se distingue del estado real
}
HUD.COLOR = COLOR
local PREDICTION_COLOR = { ["+3"] = COLOR.green, ["+2"] = COLOR.green, ["+1"] = COLOR.normal,
                           ["OVERTIME"] = COLOR.red }

-- +3/+2/+1 caben enormes; OVERTIME es largo y va un punto menor para no
-- comerse el reloj y la confianza en un frame de 260 px.
function HUD.FontFor(code)
    return code == "OVERTIME" and "GameFontNormalLarge" or "GameFontNormalHuge"
end

function HUD:Lines(m)
    local L = {}
    local title = m.dungeon or "Mítica+"
    if m.level and m.mode ~= "PREPARE" then title = title .. " +" .. tostring(m.level) end
    L.title = title
    L.tag = m.preview and "PREVIEW" or nil

    if m.mode == "RUN" then
        if m.elapsed and m.limit and m.limit > 0 then
            L.clock = reloj(m.elapsed) .. " / " .. reloj(m.limit)
            L.clockColor = m.elapsed > m.limit and COLOR.red or COLOR.highlight
        elseif m.elapsed then
            L.clock, L.clockColor = reloj(m.elapsed), COLOR.highlight
        else
            L.clock, L.clockColor = "-", COLOR.gray
        end
        local p = m.prediction
        if p then
            -- Por debajo de la confianza del motor el bracket es provisional: se
            -- enseña, pero con "?" en lugar de venderlo como un hecho.
            L.prediction = p.code .. (p.confident and "" or "?")
            L.predictionColor = PREDICTION_COLOR[p.code] or COLOR.highlight
            L.predictionFont = HUD.FontFor(p.code)
            local parts = {}
            if m.showConfidence then
                parts[#parts + 1] = p.confidence
                    and string.format("Confianza %d%%", math.floor(p.confidence + 0.5))
                    or "Confianza -"
            end
            if m.showETA and p.estimatedFinish then
                parts[#parts + 1] = "Final ~" .. reloj(p.estimatedFinish)
            end
            L.detail = #parts > 0 and table.concat(parts, "  -  ") or nil
        else
            L.prediction, L.predictionColor, L.predictionFont = HUD.CALCULATING, COLOR.gray, "GameFontDisable"
            L.detail = m.showConfidence and "Confianza -" or nil
        end
    elseif m.mode == "SUMMARY" then
        local f = m.final or {}
        L.clock = f.time and ("Completada en " .. reloj(f.time)) or "Completada"
        L.clockColor = COLOR.highlight
        if f.code then
            L.prediction, L.predictionColor, L.predictionFont = f.code, PREDICTION_COLOR[f.code], HUD.FontFor(f.code)
        end
        if f.source == "OFFICIAL" then
            L.detail = "Resultado oficial"
        elseif f.code then
            L.detail = "Última predicción"
        end
    end
    return L
end

-- -------------------------------------------------------------------------
-- FRAME  (sobrio, con el borde y el fondo de los tooltips de Blizzard)
-- -------------------------------------------------------------------------

local LINE_Y = { title = -9, clock = -27, detail = -44 }

function HUD:_Build()
    if self._frame then return self._frame end
    local f = CreateFrame("Frame", "MitzuMPlusKeyPredictionHUD", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(HUD.WIDTH, 62)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.03, 0.03, 0.04, 0.85)
        f:SetBackdropBorderColor(0.55, 0.55, 0.55, 0.9)
    end

    -- Título a todo el ancho: el nombre de la mazmorra y el nivel no compiten
    -- con la predicción aunque el nombre localizado sea largo.
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, LINE_Y.title)
    title:SetPoint("TOPRIGHT", -10, LINE_Y.title)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    f.title = title

    -- Predicción: el elemento principal, a la derecha de las dos filas de abajo.
    local prediction = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    prediction:SetPoint("RIGHT", f, "TOPRIGHT", -10, -40)
    prediction:SetJustifyH("RIGHT")
    prediction:SetWordWrap(false)
    f.prediction = prediction
    f._predictionFont = "GameFontNormalHuge"

    local clock = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    clock:SetPoint("TOPLEFT", 10, LINE_Y.clock)
    clock:SetPoint("RIGHT", prediction, "LEFT", -6, 0)
    clock:SetJustifyH("LEFT")
    clock:SetWordWrap(false)
    f.clock = clock

    local detail = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail:SetPoint("TOPLEFT", 10, LINE_Y.detail)
    detail:SetPoint("RIGHT", prediction, "LEFT", -6, 0)
    detail:SetJustifyH("LEFT")
    detail:SetWordWrap(false)
    detail:SetTextColor(COLOR.gray[1], COLOR.gray[2], COLOR.gray[3], 1)
    f.detail = detail

    -- Marca de vista previa: fuera del marco, como una pestaña, para que no se
    -- confunda nunca con una llave real.
    local tag = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tag:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 6, 1)
    tag:SetText("PREVIEW")
    tag:SetTextColor(COLOR.preview[1], COLOR.preview[2], COLOR.preview[3], 1)
    tag:Hide()
    f.tag = tag

    f:SetScript("OnDragStart", function(self_)
        if HUD:Settings().locked then return end
        self_._dragging = true
        self_:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self_)
        if not self_._dragging then return end
        self_._dragging = false
        self_:StopMovingOrSizing()
        local point, _, relPoint, x, y = self_:GetPoint()
        local s = HUD:Settings()
        s.point, s.relPoint, s.x, s.y = point, relPoint, x, y
        record("MOVED", { point = point })
    end)

    f:Hide()
    self._frame = f
    self:ApplySettings()
    record("FRAME_BUILT")
    return f
end

-- Escala, alfa, posición y ratón. Fuera de combate; en combate se aplaza.
function HUD:ApplySettings()
    local f = self._frame
    if not f then return false end
    if inCombat() then
        self._pendingApply = true
        return false
    end
    self._pendingApply = false
    local s = self:Settings()
    f:SetScale(clamp(s.scale, 0.6, 2.0, 1.0))
    f:SetAlpha(clamp(s.alpha, 0.2, 1.0, 1.0))
    f:ClearAllPoints()
    if type(s.point) == "string" then
        f:SetPoint(s.point, UIParent, s.relPoint or s.point, tonumber(s.x) or 0, tonumber(s.y) or 0)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -170)
    end
    -- Bloqueado no captura ni un clic sobre el mundo.
    f:EnableMouse(s.locked ~= true)
    return true
end

local function setText(self, fs, key, text, color)
    local cache = self._textCache
    text = text or ""
    if cache[key] ~= text then
        fs:SetText(text)
        cache[key] = text
    end
    if color then fs:SetTextColor(color[1], color[2], color[3], 1) end
end

function HUD:Render(m)
    if m.mode == "HIDDEN" then
        if self._frame and self._frame:IsShown() then self._frame:Hide() end
        self._displayed = { mode = "HIDDEN", lifecycle = m.lifecycle, prediction = "NONE" }
        return
    end
    local f = self:_Build()
    local L = self:Lines(m)

    setText(self, f.title, "title", L.title, COLOR.normal)
    setText(self, f.clock, "clock", L.clock or "", L.clockColor or COLOR.highlight)
    local font = L.predictionFont or "GameFontNormalHuge"
    if f._predictionFont ~= font then
        local obj = rawget(_G, font)
        if obj and f.prediction.SetFontObject then pcall(f.prediction.SetFontObject, f.prediction, obj) end
        f._predictionFont = font
    end
    setText(self, f.prediction, "prediction", L.prediction or "", L.predictionColor or COLOR.highlight)
    setText(self, f.detail, "detail", L.detail or "")
    if L.detail then f.detail:Show() else f.detail:Hide() end
    if L.tag then f.tag:Show() else f.tag:Hide() end

    local height = L.detail and 62 or 46
    if self._displayed.height ~= height then f:SetHeight(height) end
    if not f:IsShown() then f:Show() end

    local p = m.mode == "RUN" and m.prediction or nil
    local final = m.mode == "SUMMARY" and m.final or nil
    if p and not m.preview then self._lastPrediction = { code = p.code } end
    self._displayed = {
        mode = m.mode, preview = m.preview == true, lifecycle = m.lifecycle, height = height,
        prediction = (p and p.code) or (final and final.code) or "NONE",
        confident = p and p.confident or nil,
        confidence = p and p.confidence or nil,
        estimatedFinish = p and p.estimatedFinish or nil,
        finalSource = final and final.source or nil,
        elapsed = m.elapsed, limit = m.limit,
        text = L.prediction,
    }
end

-- -------------------------------------------------------------------------
-- REFRESCO
-- -------------------------------------------------------------------------

function HUD:Refresh(reason)
    self._lastReason = reason or "UNKNOWN"
    self._lastRefreshAt = now()
    local ok, err = pcall(function()
        local antes = self._mode
        local antesPred = self._displayed and self._displayed.prediction
        local m = self:BuildModel()
        self:Render(m)
        self._mode = m.mode
        if antes ~= m.mode then
            record(m.mode == "HIDDEN" and "HIDDEN" or "SHOWN",
                { mode = m.mode, reason = self._lastReason, preview = m.preview or nil })
        end
        local pred = self._displayed.prediction
        if pred ~= antesPred and not m.preview and m.mode ~= "HIDDEN" then
            record("PREDICTION", { prediction = pred, confidence = self._displayed.confidence })
        end
        self:_SyncTicker(m.mode)
    end)
    if not ok then
        local S = Safe()
        self._lastError = S and S.Text(err, 160) or tostring(err)
        record("RENDER_FAILED", { err = self._lastError, reason = self._lastReason })
        return false
    end
    return true
end

-- Ticker solo durante RUN. Reloj cada segundo; la predicción cada 2.
function HUD:_SyncTicker(mode)
    local needed = (mode == "RUN") and not self._preview
    if needed and not self._ticker and C_Timer and C_Timer.NewTicker then
        self._tick = 0
        self._ticker = C_Timer.NewTicker(1, function() HUD:_OnTick() end)
    elseif not needed and self._ticker then
        if self._ticker.Cancel then self._ticker:Cancel() end
        self._ticker = nil
    end
end

function HUD:_OnTick()
    self._tick = (self._tick or 0) + 1
    if self._preview then return end
    if self._tick % 2 == 0 then
        self:Refresh("TICK")
        return
    end
    -- Solo el reloj.
    local f = self._frame
    if not f or not f:IsShown() or self._mode ~= "RUN" then return end
    pcall(function()
        local CC = MitzuMPlus.ChallengeClock
        local e, lim = num(method(CC, "GetElapsed")), num(method(CC, "GetTimeLimit"))
        local L = self:Lines({ mode = "RUN", elapsed = e, limit = lim })
        setText(self, f.clock, "clock", L.clock or "", L.clockColor)
    end)
end

-- -------------------------------------------------------------------------
-- API PARA COMANDOS, CONFIGURACIÓN Y QA
-- -------------------------------------------------------------------------

function HUD:SetEnabled(on)
    self:Settings().enabled = on and true or false
    record(on and "ENABLED" or "DISABLED")
    self:Refresh(on and "ENABLED" or "DISABLED")
    return self:IsEnabled()
end

function HUD:SetPreview(on)
    on = on and true or false
    if self._preview == on then return on end
    self._preview = on
    self._textCache = {}
    record(on and "PREVIEW_ON" or "PREVIEW_OFF")
    self:Refresh(on and "PREVIEW_ON" or "PREVIEW_OFF")
    return on
end

function HUD:IsPreview() return self._preview == true end
function HUD:IsVisible() return self._frame ~= nil and self._frame:IsShown() == true end
function HUD:GetMode() return self._mode end
function HUD:GetDisplayed() return self._displayed end
function HUD:GetDisplayedPrediction() return self._displayed and self._displayed.prediction or "NONE" end
function HUD:GetLastRefreshReason() return self._lastReason end
function HUD:GetLastError() return self._lastError end
function HUD:IsTickerActive() return self._ticker ~= nil end

function HUD:SetOption(key, value)
    local s = self:Settings()
    if key == "scale" then
        s.scale = clamp(value, 0.6, 2.0, s.scale)
    elseif key == "alpha" then
        s.alpha = clamp(value, 0.2, 1.0, s.alpha)
    elseif key == "locked" or key == "enabled"
       or key == "showConfidence" or key == "showETA" then
        s[key] = value and true or false
    else
        return false, "opción desconocida"
    end
    self:ApplySettings()
    self:Refresh("OPTION_" .. key)
    return true, s[key]
end

function HUD:ResetPosition()
    local s = self:Settings()
    s.point, s.relPoint, s.x, s.y = nil, nil, nil, nil
    self:ApplySettings()
    record("POSITION_RESET")
    return true
end

-- Pares ordenados clave/valor del diagnóstico. /emp hud status y el Bug Report
-- enseñan exactamente lo mismo.
function HUD:DiagnosticFields()
    local s = self:Settings()
    local d = self._displayed or {}
    local S = Safe()
    local function clock(v) return v and reloj(v) or "nil" end
    return {
        { "implementation", HUD.IMPLEMENTATION },
        { "enabled", s.enabled ~= false },
        { "visible", self:IsVisible() },
        { "mode", self._mode },
        { "preview", self._preview == true },
        { "prediction", d.prediction or "NONE" },
        { "provisional", d.confident == false },
        { "confidence", d.confidence },
        { "estimatedFinish", d.estimatedFinish and clock(d.estimatedFinish) or nil },
        { "finalSource", d.finalSource },
        { "elapsed", d.elapsed and clock(d.elapsed) or nil },
        { "limit", d.limit and clock(d.limit) or nil },
        { "lastRefreshReason", self._lastReason },
        { "lastError", self._lastError and (S and S.Text(self._lastError, 160) or self._lastError) or nil },
        { "ticker", self._ticker ~= nil },
        { "locked", s.locked == true },
        { "scale", s.scale },
        { "alpha", s.alpha },
    }
end

function HUD:StatusLines()
    local out = {}
    for _, kv in ipairs(self:DiagnosticFields()) do
        out[#out + 1] = kv[1] .. "=" .. tostring(kv[2])
    end
    return out
end

-- -------------------------------------------------------------------------
-- SUSCRIPCIONES
--
-- Prioridad 5: después de las autoridades del core (10-90), así el modelo lee
-- el estado ya consolidado de cada evento. Ningún evento de ruta ni de pull.
-- -------------------------------------------------------------------------

local bus = MitzuMPlus.EventBus
if bus and bus.On then
    local P = 5
    bus:On("MITZU_DUNGEON_STATE_CHANGED", function(nuevo)
        if nuevo == "COMPLETED" then
            HUD._summaryUntil = now() + HUD.SUMMARY_SECONDS
            if C_Timer and C_Timer.After then
                local marca = HUD._summaryUntil
                C_Timer.After(HUD.SUMMARY_SECONDS + 0.1, function()
                    -- Solo si sigue siendo el mismo resumen: una llave nueva
                    -- en medio no debe ocultarse por un temporizador viejo.
                    if HUD._summaryUntil == marca then HUD:Refresh("SUMMARY_EXPIRED") end
                end)
            end
        elseif nuevo == "RUNNING" then
            HUD._summaryUntil, HUD._final, HUD._lastPrediction = nil, nil, nil
            if HUD._preview then
                -- La vista previa nunca sobrevive al arranque de una llave real.
                HUD._preview = false
                record("PREVIEW_OFF", { reason = "KEY_STARTED" })
            end
        elseif nuevo == "RESET" or nuevo == "OUTSIDE" then
            HUD._summaryUntil, HUD._final, HUD._lastPrediction = nil, nil, nil
            HUD._textCache = {}
        end
        HUD:Refresh("LIFECYCLE_" .. tostring(nuevo))
    end, P)
    bus:On("MITZU_DUNGEON_CHANGED", function() HUD:Refresh("DUNGEON_CHANGED") end, P)
    bus:On("RUN_STARTED", function() HUD:Refresh("RUN_STARTED") end, P)
    bus:On("RUN_TEARDOWN", function() HUD:Refresh("RUN_TEARDOWN") end, P)
    bus:On("BOSS_KILLED", function() HUD:Refresh("BOSS_KILLED") end, P)
    bus:On("RUN_COMPLETED", function(run)
        HUD._final = HUD.FinalFromRun(run, HUD._lastPrediction)
        HUD:Refresh("RUN_COMPLETED")
    end, P)
end

if type(CreateFrame) == "function" then
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if HUD._pendingApply then HUD:ApplySettings() end
            return
        end
        -- Tras /reload o zona: DungeonContext ya refrescó en este mismo evento
        -- (su frame se registró antes). El HUD se reconstruye solo, sin /emp hud.
        HUD._textCache = {}
        HUD:Refresh(event)
    end)
    HUD._eventFrame = ev
end

return HUD
