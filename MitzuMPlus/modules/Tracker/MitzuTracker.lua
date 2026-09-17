-- ===========================================================================
-- MitzuMPlus - Tracker/MitzuTracker  (1.1.0-dev.9)
--
--     TrackerState ---------\                       /-> BlizzardTrackerEnhancer (llave real)
--     PredictionEngine ------> MitzuTracker -> Presenter
--     RUN_COMPLETED (Core) --/                       \-> TrackerView (vista previa / resumen)
--
-- dev.6 fue un prototipo visual independiente. Desde dev.7, DURANTE UNA LLAVE
-- REAL NO HAY VENTANA PROPIA: los datos de Mitzu se integran en el bloque M+
-- nativo de Blizzard (BlizzardTrackerEnhancer). La ventana flotante
-- (TrackerView) queda solo para:
--   * PREVIEW  herramienta de configuracion/QA fuera de llave;
--   * SUMMARY  resumen de ~20 s al terminar: Blizzard retira el bloque M+ en
--              cuanto para el timer, asi que no hay donde integrarlo.
-- Si el bloque de Blizzard no aparece, no se muestra nada propio (nunca la
-- ventana flotante): la llave sigue jugable con el tracker nativo.
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
-- TRACKER DE BLIZZARD: se mejora, no se oculta ni se mueve. La posicion es la
-- del Objective Tracker (Edit Mode); settings.hud.point/x/y solo afectan a la
-- ventana de vista previa/resumen.
-- ===========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local MT = {}
MitzuMPlus.MitzuTracker = MT

MT.IMPLEMENTATION  = "BLIZZARD_TRACKER_ENHANCER"
MT.VERSION         = 2
MT.SUMMARY_SECONDS = 20
MT.TICK            = 1
MT.BLIZZARD_TRACKER_POLICY = "ENHANCE"

-- Enrutado por modo. La ventana flotante NUNCA pinta una llave en curso.
MT.RENDER_ROUTE = {
    HIDDEN = "NONE",
    PREVIEW = "FLOATING", SUMMARY = "FLOATING",
    PENDING = "EMBEDDED", RUNNING = "EMBEDDED", COMPLETING = "EMBEDDED",
}
MT.RENDER_MODE = { FLOATING = "PREVIEW_FLOATING", EMBEDDED = "EMBEDDED", NONE = "NONE" }
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
MT._route          = "NONE"
MT._warnedNoBlock  = false
MT._lastEmbedded   = nil      -- dev.9: foto QA del ultimo render integrado

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
    -- dev.7: lineas integradas en el bloque M+ de Blizzard.
    showPrediction = true, showUpgradeTimes = true, showForcesCount = true,
    showForcesRemaining = true, showDeaths = true,
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

-- Opciones del modelo integrado. Con Angry Keystones cargado su texto de
-- umbral ocupa el hueco tras el reloj: Mitzu no repite el umbral (dev.8).
function MT:EmbeddedOptions()
    local s = self:Settings()
    local isLoaded = rawget(_G, "C_AddOns") and C_AddOns.IsAddOnLoaded
    local ok, ak = pcall(function() return isLoaded and isLoaded("AngryKeystones") end)
    return {
        showPrediction = s.showPrediction ~= false, showConfidence = s.showConfidence ~= false,
        showUpgradeTimes = s.showUpgradeTimes ~= false, showForcesCount = s.showForcesCount ~= false,
        showForcesRemaining = s.showForcesRemaining ~= false, showDeaths = s.showDeaths ~= false,
        showETA = s.showETA ~= false,
        angryKeystones = ok and ak == true,
    }
end

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

-- Escala, alfa, posicion y raton de la ventana flotante (vista previa y
-- resumen); escala y alfa acotadas de las lineas integradas. Fuera de combate;
-- en combate se aplaza. Nunca se llama desde el refresco.
function MT:ApplySettings()
    local EN = MitzuMPlus.BlizzardTrackerEnhancer
    if EN and EN.ApplySettings then
        local s = self:Settings()
        EN:ApplySettings(s.scale, clamp(s.alpha, MT.ALPHA_MIN, MT.ALPHA_MAX, 1.0))
    end
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
        local TP, TV, EN = MitzuMPlus.TrackerPresenter, MitzuMPlus.TrackerView, MitzuMPlus.BlizzardTrackerEnhancer
        local before, beforePred = self._mode, self._displayed.prediction
        local model = TP.Build(self:GatherInput(readPrediction))
        local route = MT.RENDER_ROUTE[model.mode] or "NONE"
        local shown, embedded
        if route == "FLOATING" then
            self:_Build()
            EN:Render({ mode = "HIDDEN" }, nil, self._lastReason)
            shown = TV:Render(model) or {}
        else
            if TV.frame then TV:Render({ mode = "HIDDEN" }) end
            local opts = self:EmbeddedOptions()
            local emb = EN:Render(model, opts, self._lastReason) or {}
            embedded = emb
            if route == "EMBEDDED" and not EN:IsAttached() and not self._warnedNoBlock then
                self._warnedNoBlock = true
                record("EMBED_UNAVAILABLE", { reason = EN._attachReason })
            end
            local p = model.prediction or {}
            shown = {
                prediction = (route == "EMBEDDED" and emb.paceText) and (p.code or "NONE") or "NONE",
                confidence = (route == "EMBEDDED" and emb.confidence) and p.confidence or nil,
                timer = route == "EMBEDDED" and "BLIZZARD" or nil,
                upgrade = emb.upgrade, forces = emb.forces, deaths = emb.penalty,
                forcesPrimary = emb.forcesPrimary, forcesSecondary = emb.forcesSecondary,
                bosses = route == "EMBEDDED" and "BLIZZARD" or nil,
            }
        end
        self._route = route
        self._mode = model.mode
        self._displayed = {
            mode = model.mode, preview = model.preview, route = route,
            prediction = shown.prediction or "NONE", confidence = shown.confidence,
            timer = shown.timer, forces = shown.forces, bosses = shown.bosses, deaths = shown.deaths,
            upgrade = shown.upgrade,
            forcesPrimary = shown.forcesPrimary, forcesSecondary = shown.forcesSecondary,
        }
        if model.mode == "RUNNING" or model.mode == "PENDING" then
            self._displayedPace = (shown.prediction ~= "NONE") and shown.prediction or self._displayedPace
        end
        local sig = table.concat({ tostring(model.mode), tostring(shown.prediction), tostring(shown.timer),
            tostring(shown.forces), tostring(shown.bosses), tostring(shown.deaths), tostring(shown.upgrade) }, "|")
        if sig ~= self._renderSig then
            self._renderSig = sig
            self._renderRevision = self._renderRevision + 1
        end
        if not model.preview then
            self._stateRevision = method(MitzuMPlus.TrackerState, "GetRevision")
        end
        -- Foto QA: solo tras un render integrado valido, ya con las revisiones
        -- de este refresco. Nunca se borra en los demas caminos.
        self:_CaptureEmbedded(route, embedded)
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
-- SNAPSHOT QA DEL ULTIMO RENDER INTEGRADO  (dev.9)
--
-- Cuando la llave termina, Blizzard retira el ChallengeModeBlock y todo lo que
-- el enhancer ensena pasa a nil: un `/emp bugreport` posterior no podia contar
-- ya nada de lo que se vio DURANTE la run. Esto no era un fallo visual, era una
-- limitacion de observabilidad.
--
-- La foto es SOLO diagnostico y solo de lectura para el juego: copia PLANA de
-- strings, numeros y booleanos ya calculados (nada de frames, nada de tablas de
-- Blizzard, ninguna medicion extra, sin copia profunda). Vive en memoria, no
-- toca SavedVariables, ni TrackerState, ni la sesion, ni el historial, y
-- desaparece con /reload como cualquier dato de vista.
--
-- Se ACTUALIZA solo con un render integrado valido: ruta EMBEDDED, bloque de
-- Blizzard visible y activo y enganche sano. NO se borra ni se sobrescribe al
-- ocultarse el tracker, con el resumen, con la vista previa, al pasar a
-- COMPLETED o al salir de la mazmorra. Una llave nueva la reemplaza en cuanto
-- pinta su primer render integrado valido.
-- -------------------------------------------------------------------------

MT.LAST_EMBEDDED_PREFIX = "lastEmbedded."

-- { campo del informe, campo de BlizzardTrackerEnhancer._displayed }
MT.LAST_EMBEDDED_FIELDS = {
    { "thresholdDisplayed", "threshold" },
    { "thresholdTimeDisplayed", "thresholdTime" },
    { "thresholdMode", "thresholdMode" },
    { "paceDisplayed", "paceText" },
    { "paceMode", "paceMode" },
    { "prediction", "pace" },
    { "provisional", "provisional" },
    { "confidenceDisplayed", "confidence" },
    { "etaDisplayed", "eta" },
    { "forcesPrimaryDisplayed", "forcesPrimary" },
    { "forcesSecondaryDisplayed", "forcesSecondary" },
    { "forcesLayoutMode", "forcesLayoutMode" },
    { "penaltyDisplayed", "penalty" },
    { "availableWidth", "available" },
    -- dev.11: nombres de plantilla de fuente, solo texto. Dicen si el
    -- jugador tenia de verdad la jerarquia nueva cuando le parecio pequeno.
    { "thresholdFont", "thresholdFont" },
    { "paceFont", "paceFont" },
    { "forcesPrimaryFont", "forcesPrimaryFont" },
    { "forcesSecondaryFont", "forcesSecondaryFont" },
    { "angryKeystonesLoaded", "angryKeystones" },
    { "attachGeneration", "attachGeneration" },
    { "attachmentHealthy", "attachmentHealthy" },
    { "renderReason", "reason" },
}

-- `emb` es BlizzardTrackerEnhancer._displayed (tabla plana). Devuelve si se
-- guardo. La tabla se reutiliza: cada captura reescribe TODOS los campos, asi
-- que un valor que desaparece (la penalizacion, por ejemplo) no se queda pegado.
function MT:_CaptureEmbedded(route, emb)
    if route ~= "EMBEDDED" or type(emb) ~= "table" or emb.active ~= true then return false end
    if emb.attachmentHealthy ~= true or not self:IsEmbeddedVisible() then return false end
    local snap = self._lastEmbedded
    if not snap then snap = {}; self._lastEmbedded = snap end
    for _, pair in ipairs(MT.LAST_EMBEDDED_FIELDS) do
        local v = emb[pair[2]]
        local t = type(v)
        -- Sin `a and b or c`: un `false` legitimo (angryKeystonesLoaded,
        -- attachmentHealthy, provisional) se perderia como nil.
        if t == "string" or t == "number" or t == "boolean" then
            snap[pair[1]] = v
        else
            snap[pair[1]] = nil
        end
    end
    snap.timestamp = now()
    snap.stateRevision = self._stateRevision
    snap.renderRevision = self._renderRevision
    return true
end

function MT:GetLastEmbedded() return self._lastEmbedded end

-- Pares clave/valor con prefijo propio: el informe no puede confundir el estado
-- ACTUAL ([TRACKER VISUAL]) con lo ultimo que se vio durante la llave.
function MT:LastEmbeddedFields()
    local P = MT.LAST_EMBEDDED_PREFIX
    local snap = self._lastEmbedded
    local out = { { P .. "available", snap ~= nil } }
    if not snap then return out end
    local age = now() - (snap.timestamp or 0)
    if age < 0 then age = 0 end
    out[#out + 1] = { P .. "age", math.floor(age * 10 + 0.5) / 10 }
    out[#out + 1] = { P .. "stateRevision", snap.stateRevision }
    out[#out + 1] = { P .. "renderRevision", snap.renderRevision }
    for _, pair in ipairs(MT.LAST_EMBEDDED_FIELDS) do
        out[#out + 1] = { P .. pair[1], snap[pair[1]] }
    end
    return out
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

-- La vista previa flotante no se abre con una llave en curso: durante una
-- llave real solo existe el tracker de Blizzard mejorado.
function MT:IsKeyInProgress()
    local TS = MitzuMPlus.TrackerState
    local st = TS and TS.GetStatus and TS:GetStatus()
    return st == "PENDING" or st == "RUNNING" or st == "COMPLETING"
end

function MT:SetPreview(on)
    on = on and true or false
    if on and self:IsKeyInProgress() then
        record("PREVIEW_REFUSED", { reason = "KEY_IN_PROGRESS" })
        return false, "KEY_IN_PROGRESS"
    end
    if self._preview == on then return on end
    self._preview = on
    local TV = MitzuMPlus.TrackerView
    if TV and TV.ResetCache then TV:ResetCache() end
    record(on and "PREVIEW_ON" or "PREVIEW_OFF")
    self:Refresh(on and "PREVIEW_ON" or "PREVIEW_OFF")
    return on
end

function MT:IsPreview() return self._preview == true end
function MT:IsFloatingVisible()
    local f = MitzuMPlus.TrackerView and MitzuMPlus.TrackerView.frame
    return f ~= nil and f:IsShown() == true
end
function MT:IsEmbeddedVisible()
    local EN = MitzuMPlus.BlizzardTrackerEnhancer
    return EN ~= nil and EN:IsVisible() == true
end
function MT:IsVisible() return self:IsFloatingVisible() or self:IsEmbeddedVisible() end
function MT:GetRenderMode() return MT.RENDER_MODE[self._route] or "NONE" end
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
    elseif key == "locked" or key == "enabled" or key == "showConfidence" or key == "showETA"
        or key == "showPrediction" or key == "showUpgradeTimes" or key == "showForcesCount"
        or key == "showForcesRemaining" or key == "showDeaths" then
        s[key] = value and true or false
    else
        return false, "unknown option"
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
    local out = {
        { "implementation", MT.IMPLEMENTATION },
        { "version", MT.VERSION },
        { "renderMode", self:GetRenderMode() },
        { "enabled", s.enabled ~= false },
        { "trackerVisible", self:IsVisible() },
        { "floatingVisible", self:IsFloatingVisible() },
        { "embeddedVisible", self:IsEmbeddedVisible() },
        { "mode", self._mode },
        { "preview", self._preview == true },
        { "stateRevision", self._stateRevision },
        { "renderRevision", self._renderRevision },
        { "predictionDisplayed", d.prediction or "NONE" },
        { "confidenceDisplayed", d.confidence },
        { "timerDisplayed", d.timer },
        { "upgradeTimesDisplayed", d.upgrade ~= nil },
        { "forcesDisplayed", d.forces },
        { "forcesCountDisplayed", d.forcesPrimary ~= nil },
        { "forcesRemainingDisplayed", d.forcesSecondary ~= nil },
        { "bossesDisplayed", d.bosses },
        { "deathsDisplayed", d.deaths },
        { "lastRenderReason", self._lastReason },
        { "lastRenderError", self._lastError and (S and S.Text(self._lastError, 160) or self._lastError) or nil },
        { "ticker", self._ticker ~= nil },
        { "locked", s.locked == true },
        { "scale", s.scale },
        { "alpha", s.alpha },
        { "showPrediction", s.showPrediction ~= false },
        { "showConfidence", s.showConfidence ~= false },
        { "showUpgradeTimes", s.showUpgradeTimes ~= false },
        { "showForcesCount", s.showForcesCount ~= false },
        { "showForcesRemaining", s.showForcesRemaining ~= false },
        { "showDeaths", s.showDeaths ~= false },
        { "showETA", s.showETA ~= false },
        { "blizzardTracker", MT.BLIZZARD_TRACKER_POLICY },
    }
    local EN = MitzuMPlus.BlizzardTrackerEnhancer
    if EN and EN.DiagnosticFields then
        local ok, fields = pcall(EN.DiagnosticFields, EN)
        if ok then for _, kv in ipairs(fields) do out[#out + 1] = kv end end
    end
    return out
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
    MT._warnedNoBlock = false
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
