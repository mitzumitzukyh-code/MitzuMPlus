-- ===========================================================================
-- MitzuMPlus - Tracker/MitzuTracker  (1.1.0-dev.6, Mitzu Tracker V1)
--
--     TrackerState ---------\
--     PredictionEngine ------> MitzuTracker -> TrackerPresenter -> TrackerView
--     RUN_COMPLETED (Core) --/
--
-- El tracker de Mitica+ en vivo. Sustituye a la ventana provisional de 1.0
-- (KeyPredictionHUD) conservando sus ajustes (settings.hud), su movimiento,
-- escala, alfa, vista previa y comandos.
--
-- ESTE FICHERO ES EL UNICO QUE JUNTA FUENTES. No lee APIs de Mitica+ de
-- Blizzard (lo vigila run_static_checks.py): las fuerzas, bosses, muertes y el
-- reloj salen de TrackerState; el bracket, de PredictionEngine; el resultado
-- oficial, del RUN_COMPLETED de Core. El Presenter decide que se ensena y la
-- View lo pinta.
--
-- VISTA PREVIA: aislada. Con la vista previa activa no se consulta ni se
-- escribe TrackerState, PredictionEngine, RunSession, historial ni sesiones:
-- el modelo sale de TrackerPresenter.PreviewInput().
--
-- TRACKER DE BLIZZARD: coexiste. No se oculta ni se engancha el bloque M+
-- nativo en esta version (ocultarlo sin taint no esta validado todavia).
-- ===========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local MT = {}
MitzuMPlus.MitzuTracker = MT

MT.IMPLEMENTATION  = "MITZU_TRACKER"
MT.VERSION         = 1
MT.SUMMARY_SECONDS = 20
MT.TICK            = 1
MT.BLIZZARD_TRACKER_POLICY = "COEXIST"
MT.FRAME_NAME      = "MitzuMPlusTracker"

-- Memoria de la VISTA. Nada de esto es estado del juego.
MT._preview        = false
MT._mode           = "HIDDEN"
MT._displayed      = { mode = "HIDDEN", prediction = "NONE" }
MT._lastReason     = nil
MT._lastError      = nil
MT._renderRevision = 0
MT._renderSig      = nil
MT._stateRevision  = nil
MT._summaryUntil   = nil
MT._final          = nil
MT._lastPrediction = nil      -- ultimo snapshot del motor leido en RUNNING
MT._lastStatus     = nil
MT._ticker         = nil
MT._tick           = 0
MT._pendingApply   = false

local function now()
    local fn = rawget(_G, "GetTime")
    local ok, v = pcall(function() return fn and fn() end)
    return (ok and tonumber(v)) or 0
end

local function record(event, data)
    local FR = MitzuMPlus.FlightRecorder
    if FR and FR.Record then FR:Record("TRACKER_VISUAL", event, data) end
end

local function inCombat()
    local fn = rawget(_G, "InCombatLockdown")
    local ok, v = pcall(function() return fn and fn() end)
    return ok and v == true
end

local function method(obj, name, ...)
    if type(obj) ~= "table" or type(obj[name]) ~= "function" then return nil end
    local ok, a, b = pcall(obj[name], obj, ...)
    if not ok then return nil end
    return a, b
end

local function clamp(v, a, b, def)
    v = tonumber(v)
    if not v then return def end
    if v < a then return a elseif v > b then return b end
    return v
end

-- -------------------------------------------------------------------------
-- AJUSTES  (MitzuMPlusDB.profile.settings.hud, los mismos de 1.0)
-- -------------------------------------------------------------------------

MT.DEFAULTS = {
    enabled = true, locked = false, scale = 1.0, alpha = 1.0,
    showConfidence = true, showETA = true,
    point = nil, relPoint = nil, x = nil, y = nil,
}
MT.SCALE_MIN, MT.SCALE_MAX = 0.6, 2.0
MT.ALPHA_MIN, MT.ALPHA_MAX = 0.2, 1.0

function MT:Settings()
    local p = MitzuMPlus.db and MitzuMPlus.db.profile
    local st = p and p.settings
    if type(st) ~= "table" then
        -- Sin DB todavia: copia en memoria, nunca los DEFAULTS compartidos.
        if not self._fallback then
            self._fallback = {}
            for k, v in pairs(MT.DEFAULTS) do self._fallback[k] = v end
        end
        return self._fallback
    end
    if type(st.hud) ~= "table" then st.hud = {} end
    local h = st.hud
    for k, v in pairs(MT.DEFAULTS) do
        if h[k] == nil and v ~= nil then h[k] = v end
    end
    return h
end

function MT:IsEnabled() return self:Settings().enabled ~= false end

-- -------------------------------------------------------------------------
-- ENTRADAS DEL PRESENTER
-- -------------------------------------------------------------------------

function MT:_SummaryActive(status)
    local prev = self._lastStatus
    self._lastStatus = status
    -- El resumen empieza al ver entrar la llave en COMPLETED desde la llave en
    -- curso; asi no hay un instante oculto entre COMPLETING y el resumen.
    if status == "COMPLETED" and prev and prev ~= "COMPLETED" and prev ~= "IDLE" then
        self:_StartSummary()
    end
    return self._summaryUntil ~= nil and now() < self._summaryUntil
end

function MT:_StartSummary()
    self._summaryUntil = now() + MT.SUMMARY_SECONDS
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
        local mark = self._summaryUntil
        timer.After(MT.SUMMARY_SECONDS + 0.1, function()
            -- Solo si sigue siendo el mismo resumen.
            if MT._summaryUntil == mark then MT:Refresh("SUMMARY_EXPIRED") end
        end)
    end
end

function MT:GatherInput(readPrediction)
    local s = self:Settings()
    local settings = { showConfidence = s.showConfidence ~= false, showETA = s.showETA ~= false }
    if self._preview then
        return MitzuMPlus.TrackerPresenter.PreviewInput(settings)
    end
    local TS = MitzuMPlus.TrackerState
    local status = method(TS, "GetStatus")
    local input = {
        enabled = self:IsEnabled(), status = status, settings = settings,
        state = method(TS, "GetSnapshot"), elapsed = method(TS, "GetElapsed"),
        summary = self:_SummaryActive(status),
    }
    if status == "RUNNING" or status == "PENDING" then
        if readPrediction ~= false or not self._lastPrediction then
            local run = rawget(_G, "MitzuMPlusCurrentRun")
            self._lastPrediction = run and method(MitzuMPlus.PredictionEngine, "GetSnapshot", run) or nil
        end
        input.prediction = self._lastPrediction
    elseif status == "COMPLETING" then
        -- Se mantiene lo ultimo valido mientras converge el final.
        input.prediction = self._lastPrediction
    elseif status == "COMPLETED" then
        input.prediction = self._lastPrediction
        local code = self._displayedPace
        input.final = self._final or { code = code, source = "LAST_PREDICTION" }
    end
    return input
end

-- -------------------------------------------------------------------------
-- FRAME
-- -------------------------------------------------------------------------

function MT:_Build()
    local TV = MitzuMPlus.TrackerView
    if TV.frame then return TV.frame end
    local f = TV:Create(rawget(_G, "UIParent"), MT.FRAME_NAME)
    f:SetScript("OnDragStart", function(self_)
        if MT:Settings().locked then return end
        self_._dragging = true
        self_:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self_)
        if not self_._dragging then return end
        self_._dragging = false
        self_:StopMovingOrSizing()
        local point, _, relPoint, x, y = self_:GetPoint()
        local s = MT:Settings()
        s.point, s.relPoint, s.x, s.y = point, relPoint, x, y
        record("MOVED", { point = point })
    end)
    self:ApplySettings()
    record("FRAME_BUILT")
    return f
end

-- Escala, alfa, posicion y raton. Fuera de combate; en combate se aplaza.
-- Nunca se llama desde el refresco: una actualizacion no mueve el tracker.
function MT:ApplySettings()
    local f = MitzuMPlus.TrackerView and MitzuMPlus.TrackerView.frame
    if not f then return false end
    if inCombat() then
        self._pendingApply = true
        return false
    end
    self._pendingApply = false
    local s = self:Settings()
    f:SetScale(clamp(s.scale, MT.SCALE_MIN, MT.SCALE_MAX, 1.0))
    f:SetAlpha(clamp(s.alpha, MT.ALPHA_MIN, MT.ALPHA_MAX, 1.0))
    f:ClearAllPoints()
    if type(s.point) == "string" then
        f:SetPoint(s.point, rawget(_G, "UIParent"), s.relPoint or s.point, tonumber(s.x) or 0, tonumber(s.y) or 0)
    else
        f:SetPoint("TOPRIGHT", rawget(_G, "UIParent"), "TOPRIGHT", -260, -230)
    end
    -- Bloqueado no captura ni un clic sobre el mundo.
    f:EnableMouse(s.locked ~= true)
    return true
end

-- -------------------------------------------------------------------------
-- REFRESCO
-- -------------------------------------------------------------------------

function MT:Refresh(reason, readPrediction)
    self._lastReason = reason or "UNKNOWN"
    local ok, err = pcall(function()
        local TP, TV = MitzuMPlus.TrackerPresenter, MitzuMPlus.TrackerView
        local before, beforePred = self._mode, self._displayed.prediction
        local model = TP.Build(self:GatherInput(readPrediction))
        if model.mode ~= "HIDDEN" then self:_Build() end
        local shown = TV:Render(model) or { mode = model.mode }
        self._mode = model.mode
        self._displayed = {
            mode = model.mode, preview = model.preview,
            prediction = shown.prediction or "NONE", confidence = shown.confidence,
            timer = shown.timer, forces = shown.forces, bosses = shown.bosses, deaths = shown.deaths,
        }
        if model.mode == "RUNNING" or model.mode == "PENDING" then
            self._displayedPace = (shown.prediction ~= "NONE") and shown.prediction or self._displayedPace
        end
        local sig = table.concat({ tostring(model.mode), tostring(shown.prediction), tostring(shown.timer),
            tostring(shown.forces), tostring(shown.bosses), tostring(shown.deaths) }, "|")
        if sig ~= self._renderSig then
            self._renderSig = sig
            self._renderRevision = self._renderRevision + 1
        end
        if not model.preview then
            self._stateRevision = method(MitzuMPlus.TrackerState, "GetRevision")
        end
        if before ~= model.mode then
            record(model.mode == "HIDDEN" and "HIDDEN" or "SHOWN",
                { mode = model.mode, reason = self._lastReason, preview = model.preview or nil })
        end
        if self._displayed.prediction ~= beforePred and not model.preview and model.mode ~= "HIDDEN" then
            record("PREDICTION", { prediction = self._displayed.prediction, confidence = shown.confidence })
        end
        self:_SyncTicker(model.mode)
    end)
    if not ok then
        local S = MitzuMPlus.QASafe
        self._lastError = S and S.Text(err, 160) or tostring(err)
        record("RENDER_FAILED", { err = self._lastError, reason = self._lastReason })
        return false
    end
    return true
end

-- Ticker de 1 s solo con llave visible. El reloj cada tick; el motor de
-- prediccion cada 2 (el resto sale de caches: la View no reescribe texto igual).
function MT:_SyncTicker(mode)
    local needed = (mode == "RUNNING" or mode == "PENDING" or mode == "COMPLETING") and not self._preview
    local timer = rawget(_G, "C_Timer")
    if needed and not self._ticker and type(timer) == "table" and type(timer.NewTicker) == "function" then
        self._tick = 0
        self._ticker = timer.NewTicker(MT.TICK, function() MT:_OnTick() end)
    elseif not needed and self._ticker then
        if self._ticker.Cancel then self._ticker:Cancel() end
        self._ticker = nil
    end
end

function MT:_OnTick()
    self._tick = (self._tick or 0) + 1
    if self._preview then return end
    self:Refresh("TICK", self._tick % 2 == 0)
end

-- -------------------------------------------------------------------------
-- API PARA COMANDOS, CONFIGURACION Y QA
-- -------------------------------------------------------------------------

function MT:SetEnabled(on)
    self:Settings().enabled = on and true or false
    record(on and "ENABLED" or "DISABLED")
    self:Refresh(on and "ENABLED" or "DISABLED")
    return self:IsEnabled()
end

function MT:SetPreview(on)
    on = on and true or false
    if self._preview == on then return on end
    self._preview = on
    local TV = MitzuMPlus.TrackerView
    if TV and TV.ResetCache then TV:ResetCache() end
    record(on and "PREVIEW_ON" or "PREVIEW_OFF")
    self:Refresh(on and "PREVIEW_ON" or "PREVIEW_OFF")
    return on
end

function MT:IsPreview() return self._preview == true end
function MT:IsVisible()
    local f = MitzuMPlus.TrackerView and MitzuMPlus.TrackerView.frame
    return f ~= nil and f:IsShown() == true
end
function MT:GetMode() return self._mode end
function MT:GetDisplayed() return self._displayed end
function MT:GetDisplayedPrediction() return self._displayed and self._displayed.prediction or "NONE" end
function MT:GetLastRefreshReason() return self._lastReason end
function MT:GetLastError() return self._lastError end
function MT:IsTickerActive() return self._ticker ~= nil end

function MT:SetOption(key, value)
    local s = self:Settings()
    if key == "scale" then
        s.scale = clamp(value, MT.SCALE_MIN, MT.SCALE_MAX, s.scale)
    elseif key == "alpha" then
        s.alpha = clamp(value, MT.ALPHA_MIN, MT.ALPHA_MAX, s.alpha)
    elseif key == "locked" or key == "enabled" or key == "showConfidence" or key == "showETA" then
        s[key] = value and true or false
    else
        return false, "opcion desconocida"
    end
    self:ApplySettings()
    self:Refresh("OPTION_" .. key)
    return true, s[key]
end

function MT:ResetPosition()
    local s = self:Settings()
    s.point, s.relPoint, s.x, s.y = nil, nil, nil, nil
    self:ApplySettings()
    record("POSITION_RESET")
    return true
end

-- Pares clave/valor. /emp tracker status y el Bug Report ensenan lo mismo.
function MT:DiagnosticFields()
    local s = self:Settings()
    local d = self._displayed or {}
    local S = MitzuMPlus.QASafe
    return {
        { "implementation", MT.IMPLEMENTATION },
        { "version", MT.VERSION },
        { "enabled", s.enabled ~= false },
        { "visible", self:IsVisible() },
        { "mode", self._mode },
        { "preview", self._preview == true },
        { "stateRevision", self._stateRevision },
        { "renderRevision", self._renderRevision },
        { "predictionDisplayed", d.prediction or "NONE" },
        { "confidenceDisplayed", d.confidence },
        { "timerDisplayed", d.timer },
        { "forcesDisplayed", d.forces },
        { "bossesDisplayed", d.bosses },
        { "deathsDisplayed", d.deaths },
        { "lastRenderReason", self._lastReason },
        { "lastRenderError", self._lastError and (S and S.Text(self._lastError, 160) or self._lastError) or nil },
        { "ticker", self._ticker ~= nil },
        { "locked", s.locked == true },
        { "scale", s.scale },
        { "alpha", s.alpha },
        { "showConfidence", s.showConfidence ~= false },
        { "showETA", s.showETA ~= false },
        { "blizzardTracker", MT.BLIZZARD_TRACKER_POLICY },
    }
end

function MT:StatusLines()
    local out = {}
    for _, kv in ipairs(self:DiagnosticFields()) do out[#out + 1] = kv[1] .. "=" .. tostring(kv[2]) end
    return out
end

-- -------------------------------------------------------------------------
-- SUSCRIPCIONES  (prioridad 5: despues de las autoridades del core)
-- -------------------------------------------------------------------------

local function clearRun()
    MT._summaryUntil, MT._final, MT._lastPrediction, MT._displayedPace = nil, nil, nil, nil
    local TV = MitzuMPlus.TrackerView
    if TV and TV.ResetCache then TV:ResetCache() end
end

local bus = MitzuMPlus.EventBus
if bus and bus.On then
    local P = 5
    bus:On("MITZU_TRACKER_STATE_CHANGED", function() MT:Refresh("STATE_CHANGED") end, P)
    bus:On("MITZU_TRACKER_RUN_STARTED", function()
        clearRun()
        if MT._preview then
            -- La vista previa nunca sobrevive al arranque de una llave real.
            MT._preview = false
            record("PREVIEW_OFF", { reason = "KEY_STARTED" })
        end
        MT:Refresh("RUN_STARTED")
    end, P)
    bus:On("MITZU_TRACKER_RUN_ENDED", function() clearRun(); MT:Refresh("RUN_ENDED") end, P)
    bus:On("RUN_COMPLETED", function(run)
        MT._final = MitzuMPlus.TrackerPresenter.FinalFromRun(run, MT._displayedPace)
        MT:Refresh("RUN_COMPLETED")
    end, P)
    bus:On("MITZU_DUNGEON_STATE_CHANGED", function(new)
        if new == "RESET" or new == "OUTSIDE" then MT._summaryUntil = nil end
        MT:Refresh("LIFECYCLE_" .. tostring(new))
    end, P)
end

local create = rawget(_G, "CreateFrame")
if type(create) == "function" then
    local ev = create("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if MT._pendingApply then MT:ApplySettings() end
            return
        end
        -- Tras /reload o zona el tracker se reconstruye solo.
        local TV = MitzuMPlus.TrackerView
        if TV and TV.ResetCache then TV:ResetCache() end
        MT:Refresh(event)
    end)
    MT._eventFrame = ev
end

return MT
