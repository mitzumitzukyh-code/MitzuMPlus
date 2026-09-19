-- ===========================================================================
-- MitzuMPlus - Tracker/BlizzardTrackerEnhancer  (dev.7 integracion, dev.8
-- densidad, dev.9 pulido final)
--
--     TrackerState -> MitzuTracker -> TrackerPresenter -> BlizzardTrackerEnhancer
--                                                              |  (anclas)
--                                        ScenarioObjectiveTracker.ChallengeModeBlock
--
-- Durante una Mitica+ real MitzuMPlus NO tiene ventana propia: anade lineas
-- pequenas al bloque M+ nativo de Blizzard. Blizzard sigue pintando nombre,
-- nivel, temporizador, jefes, barra de fuerzas y contador de muertes.
--
-- ESTRUCTURA REAL (Blizzard_ObjectiveTracker, 12.1.0.69814, ver
-- docs/tracker/MITZU_TRACKER.md):
--   ScenarioObjectiveTracker                 modulo (ScenarioObjectiveTrackerMixin)
--     :EndLayout()                           fin de cada reconstruccion del modulo
--     .usedProgressBars[line]                barras de pool (la de fuerzas en M+;
--                                            se libera al llegar al 100 %)
--     .ChallengeModeBlock                    bloque FIJO de XML, 251x87, no se recicla
--         :Activate(timerID, elapsed, limit) arranque del timer de la llave
--         :IsActive()                        not not timerID
--         .Level (TOPLEFT 28,-18)  .TimeLeft (debajo de Level)
--         .DeathCount (TOPLEFT en BOTTOMRIGHT -47,43)  .StatusBar (abajo)
--         .TimesUpLootStatus (a la derecha de TimeLeft, solo fuera de tiempo)
--
-- SEGURIDAD (taint)
--   * Solo dos post-hooks con hooksecurefunc(tabla, "Metodo", fn): Activate del
--     bloque y EndLayout del modulo. Nunca se reemplaza una funcion de Blizzard.
--   * Las referencias a Blizzard se llaman blizz* y SOLO se leen (Get*/Is* y
--     campos). Nada de SetPoint/SetText/Show/Hide/SetScript/HookScript/campos
--     sobre ellas: lo vigila run_static_checks.py.
--   * Los elementos son frames y FontStrings PROPIOS, hijos del bloque (siguen
--     su visibilidad, su escala y su posicion de Edit Mode) y anclados a sus
--     regiones. Nunca se cambia la altura del bloque ni el layout del modulo.
--   * Cada callback va en pcall; con MAX_ERRORS fallos el enhancer se apaga
--     solo, oculta lo suyo y el tracker de Blizzard sigue intacto.
--   * Sin OnUpdate: se repinta con el ticker de 1 s de MitzuTracker, con
--     MITZU_TRACKER_STATE_CHANGED y cuando Blizzard reconstruye el layout.
--
-- QUE SE PINTA (dev.8, "Blizzard mejorado", no un panel):
--   15:06  +2 8:18             <- TimeLeft de Blizzard + UN solo umbral
--          RITMO +1  37%       <- ritmo; confianza/ETA en gris, secundarias
--   [barra Blizzard 45%]
--   329 / 729      faltan 400  <- recuento y restantes, sin repetir el %
--   [calavera 4] -0:20         <- solo la penalizacion publicada
-- Que cabe lo decide TrackerPresenter.LayoutEmbedded (puro, testeado).
--
-- Con Angry Keystones cargado, el umbral junto al reloj es suyo: Mitzu no lo
-- repite y alinea el ritmo a la derecha para no pisar su texto.
--
-- PULIDO dev.9 (solo presentacion, sin logica nueva):
--   * RITMO se lee mejor: la etiqueta deja de ser casi gris y la linea ya no
--     se atenua por un bracket provisional. Mismo tamano, sin fondo, sin borde
--     y sin brillo: el reloj de Blizzard sigue siendo lo mas visible.
--   * Las dos columnas de fuerzas cuelgan de una fila propia anclada a los
--     extremos REALES de la StatusBar, compartiendo base y separacion.
--   * Cada render valido deja constancia de su salud (attachGeneration,
--     attachmentHealthy) para el snapshot de QA de MitzuTracker.
--
-- DATOS: solo el modelo de TrackerPresenter. Este fichero no lee APIs de
-- Mitica+ (C_ChallengeMode, C_ScenarioInfo, ...) ni el texto de Blizzard.
-- ===========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local E = {}
MitzuMPlus.BlizzardTrackerEnhancer = E

E.IMPLEMENTATION = "BLIZZARD_TRACKER_ENHANCER"
E.VERSION = 1
E.MAX_ERRORS = 3
E.SCALE_MIN, E.SCALE_MAX = 0.8, 1.25

-- Geometria del bloque segun su XML (px del bloque).
E.LAYOUT = {
    LEVEL_X        = 28,   -- Level y TimeLeft empiezan aqui
    DEATH_RIGHT    = 47,   -- DeathCount: TOPLEFT en BOTTOMRIGHT -47
    ELAPSED_COL_W  = 62,   -- columna izquierda reservada al reloj nativo
    COLUMN_GAP     = 8,   -- separacion fija reloj <-> umbral
    PACE_TOP_Y     = -17,  -- fila propia, debajo del reloj/umbral
    PACE_ROW_H     = 14,
    FORCES_GAP_Y   = -3,   -- 3 px uniformes bajo la StatusBar de Blizzard
    FORCES_ROW_H   = 14,   -- fila fija para GameFontHighlight
    FORCES_INSET   = 0,    -- columnas clavadas a los bordes reales de la barra
    MEASURE_CACHE  = 256,  -- anchos medidos que se recuerdan
    FALLBACK_TIME_W = 60,
    FALLBACK_BLOCK_W = 251,
}

-- El codigo va siempre como texto (+3/+2/+1/OVERTIME); el color solo refuerza.
E.COLOR = {
    code    = { ["+3"] = "40ff73", ["+2"] = "ffd100", ["+1"] = "ff9933", OVERTIME = "ff4545" },
    -- dev.11: el umbral es UN dato, con UN color. El oro de Blizzard (el mismo
    -- de los titulos de mision) lo separa del ritmo sin pedir un panel ni un
    -- brillo. El codigo contextual (+3 verde / +2 oro / +1 naranja) se queda
    -- donde de verdad informa de algo que cambia: la linea de RITMO.
    threshold = { 1.00, 0.843, 0.00 },
    -- dev.11: plata unica para todo lo secundario (confianza, ETA, restantes).
    -- `label` es ese mismo color en hexadecimal, para colorear en linea.
    secondary = { 0.78, 0.78, 0.812 },
    label   = "c7c7cf",
    -- El recuento de fuerzas es el dato principal de su fila: blanco pleno,
    -- como el texto de objetivo de Blizzard justo encima.
    forces  = { 1.00, 1.00, 1.00 },
    penalty = { 1.00, 0.40, 0.40, 0.9 },
}

-- Objetos de fuente de Blizzard por tipo de texto (solo se usan como plantilla).
-- experimental.7: misma presencia visual que la UI nativa aprobada:
--   Blizzard TimeLeft (Huge, 20) > threshold (Large, 16)
--   > pace (Medium, ~14) > forces/remaining/penalty (Highlight, ~12)
--   > confidence/ETA (DisableSmall, ~10).
-- Nunca se crea una fuente propia ni se llama a SetFont: solo plantillas nativas.
E.FONT = {
    threshold       = "GameFontHighlightLarge",
    pace            = "GameFontHighlightMedium",
    secondary       = "GameFontDisableSmall",
    forces          = "GameFontHighlight",
    forcesSecondary = "GameFontHighlight",
    penalty         = "GameFontHighlight",
}

-- Orden de la jerarquia, de mayor a menor. Lo consumen las pruebas y las
-- comprobaciones estaticas: ningun nivel puede adelantar al anterior.
E.FONT_ORDER = { "threshold", "pace", "forces", "forcesSecondary", "penalty", "secondary" }

E._hookedBlock, E._hookedTracker = nil, nil
E._blizzBlock = nil
E._attached = false
E._generation = 0
E._attachReason = "NOT_STARTED"
E._lastLayoutReason = nil
E._lastError = nil
E._errors = 0
E._disabled = false
E._model, E._opts = nil, nil
E._displayed = {}
E._cache = {}
E._widths, E._widthCount = nil, 0
E.elements = nil

local function record(event, data)
    local FR = MitzuMPlus.FlightRecorder
    if FR and FR.Record then FR:Record("TRACKER_VISUAL", "ENHANCER_" .. event, data) end
end

-- Lectura protegida de un campo de Blizzard.
local function get(t, k)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[k] end)
    return ok and v or nil
end

-- Llamada protegida a un metodo de LECTURA de Blizzard.
local function read(obj, name)
    local fn = get(obj, name)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, obj)
    return ok and v or nil
end

-- ---------------------------------------------------------------------------
-- DESCUBRIMIENTO Y ENGANCHE
-- ---------------------------------------------------------------------------

function E:FindBlock()
    local blizzTracker = rawget(_G, "ScenarioObjectiveTracker")
    if type(blizzTracker) ~= "table" then return nil, nil, "BLIZZARD_TRACKER_NOT_LOADED" end
    local blizzBlock = get(blizzTracker, "ChallengeModeBlock")
    if type(blizzBlock) ~= "table" or type(get(blizzBlock, "IsShown")) ~= "function"
       or type(get(blizzBlock, "TimeLeft")) ~= "table" then
        return blizzTracker, nil, "CHALLENGE_BLOCK_NOT_FOUND"
    end
    return blizzTracker, blizzBlock, nil
end

local function onBlizzardLayout(reason)
    if E._disabled then return end
    E._lastLayoutReason = reason

    -- experimental.11: EndLayout puede dispararse cuando las regiones ya
    -- existen pero sus metricas de texto aun no han convergido. Medir ahi
    -- hacia que TimeLeft pareciera mucho mas ancho durante un frame y el
    -- Presenter degradara RITMO a TOO_NARROW. Se difiere una vuelta del loop
    -- y se coalescan reconstrucciones consecutivas; no se modifica ningun
    -- frame de Blizzard.
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
        E._layoutSerial = (E._layoutSerial or 0) + 1
        local serial = E._layoutSerial
        timer.After(0, function()
            if E._disabled or E._layoutSerial ~= serial then return end
            if E._model then E:Render(E._model, E._opts, tostring(reason) .. "_STABLE") end
        end)
        return
    end
    if E._model then E:Render(E._model, E._opts, reason) end
end

-- Idempotente por instancia: un bloque o modulo nuevo (otro objeto tras un
-- /reload o una reconstruccion) recibe sus hooks; uno ya enganchado, no.
function E:InstallHooks(blizzTracker, blizzBlock)
    local hook = rawget(_G, "hooksecurefunc")
    if type(hook) ~= "function" then return false end
    if blizzBlock and self._hookedBlock ~= blizzBlock and type(get(blizzBlock, "Activate")) == "function" then
        hook(blizzBlock, "Activate", function() pcall(onBlizzardLayout, "BLIZZARD_ACTIVATE") end)
        self._hookedBlock = blizzBlock
        record("HOOK", { target = "ChallengeModeBlock.Activate" })
    end
    if blizzTracker and self._hookedTracker ~= blizzTracker and type(get(blizzTracker, "EndLayout")) == "function" then
        hook(blizzTracker, "EndLayout", function() pcall(onBlizzardLayout, "BLIZZARD_LAYOUT") end)
        self._hookedTracker = blizzTracker
        record("HOOK", { target = "ScenarioObjectiveTracker.EndLayout" })
    end
    return self._hookedBlock ~= nil and self._hookedTracker ~= nil
end

function E:_CreateElements()
    if self.elements then return self.elements end
    local create = rawget(_G, "CreateFrame")
    local root = create("Frame", "MitzuMPlusTrackerEnhancer")
    local forcesRoot = create("Frame", "MitzuMPlusTrackerEnhancerForces")
    local function fs(parent, kind, justify)
        local t = parent:CreateFontString(nil, "OVERLAY", E.FONT[kind])
        t:SetJustifyH(justify or "LEFT")
        t:SetJustifyV("BOTTOM")
        t:SetWordWrap(false)
        return t
    end
    local el = { root = root, forcesRoot = forcesRoot }
    -- experimental.12: dos filas propias. El reloj de Blizzard NO se toca;
    -- timerRow solo nos da una geometria estable para alinear el umbral y
    -- paceRow una fila independiente para Ritmo.
    el.timerRow = create("Frame", nil, root)
    el.paceRow = create("Frame", nil, root)
    el.paceRow:SetHeight(E.LAYOUT.PACE_ROW_H)
    el.threshold = fs(el.timerRow, "threshold", "RIGHT")
    el.threshold:SetTextColor(E.COLOR.threshold[1], E.COLOR.threshold[2], E.COLOR.threshold[3], 1)
    el.pace = fs(el.paceRow, "pace", "CENTER")
    el.paceExtra = fs(el.paceRow, "secondary", "RIGHT")
    el.paceExtra:SetTextColor(E.COLOR.secondary[1], E.COLOR.secondary[2], E.COLOR.secondary[3], 1)
    el.penalty = fs(root, "penalty", "RIGHT")
    el.penalty:SetTextColor(E.COLOR.penalty[1], E.COLOR.penalty[2], E.COLOR.penalty[3], E.COLOR.penalty[4])
    el.forcesPrimary = fs(forcesRoot, "forces")
    el.forcesPrimary:SetJustifyV("TOP")
    el.forcesPrimary:SetTextColor(E.COLOR.forces[1], E.COLOR.forces[2], E.COLOR.forces[3], 1)
    -- dev.11: los restantes tienen fuente propia (legible), no la atenuada de
    -- la confianza. Antes compartian `secondary` y por eso casi no se veian.
    el.forcesSecondary = fs(forcesRoot, "forcesSecondary", "RIGHT")
    el.forcesSecondary:SetJustifyV("TOP")
    el.forcesSecondary:SetTextColor(E.COLOR.secondary[1], E.COLOR.secondary[2], E.COLOR.secondary[3], 1)
    -- Medidores ocultos, uno por fuente: deciden que cabe.
    el.measure = {}
    for kind in pairs(E.FONT) do
        el.measure[kind] = fs(root, kind)
        el.measure[kind]:Hide()
    end
    root:Hide(); forcesRoot:Hide()
    self.elements = el
    self:ApplySettings(self._scale, self._alpha)
    record("ELEMENTS_CREATED")
    return el
end

function E:Attach(blizzBlock, reason)
    local el = self:_CreateElements()
    if self._attached and self._blizzBlock == blizzBlock then return false end
    -- Reenganche: los mismos elementos propios pasan al bloque nuevo.
    el.root:SetParent(blizzBlock)
    el.forcesRoot:SetParent(blizzBlock)
    el.root:ClearAllPoints()
    el.root:SetAllPoints(blizzBlock)
    self._cache = {}
    self._blizzBlock = blizzBlock
    self._attached = true
    self._generation = self._generation + 1
    self._attachReason = reason or "ATTACHED"
    record("ATTACH", { generation = self._generation, reason = self._attachReason })
    return true
end

function E:_HideElements()
    local el = self.elements
    if not el then return end
    if el.root:IsShown() then el.root:Hide() end
    if el.forcesRoot:IsShown() then el.forcesRoot:Hide() end
end

function E:Detach(reason)
    local el = self.elements
    local was = self._attached
    self:_HideElements()
    if el then
        el.root:ClearAllPoints(); el.forcesRoot:ClearAllPoints()
        el.root:SetParent(nil); el.forcesRoot:SetParent(nil)
    end
    self._attached, self._blizzBlock, self._cache = false, nil, {}
    self._attachReason = reason or "DETACHED"
    self._displayed = {}
    if was then record("DETACH", { reason = self._attachReason }) end
end

function E:IsAttached() return self._attached == true end
function E:IsVisible()
    local el = self.elements
    return self._attached and el ~= nil and el.root:IsShown() == true and self._blizzBlock ~= nil
        and read(self._blizzBlock, "IsShown") == true
end

-- ---------------------------------------------------------------------------
-- PINTADO
-- ---------------------------------------------------------------------------

-- Ancho de un texto en la fuente de su tipo. Cacheado: el mismo texto no se
-- vuelve a medir (el umbral cambia una vez por segundo, no por frame).
function E:_Measure(text, kind)
    kind = E.FONT[kind] and kind or "pace"
    local key = kind .. "\31" .. text
    local cache = self._widths
    if not cache or self._widthCount > E.LAYOUT.MEASURE_CACHE then
        cache, self._widthCount = {}, 0
        self._widths = cache
    end
    local v = cache[key]
    if v then return v end
    local m = self.elements.measure[kind]
    m:SetText(text)
    v = m:GetStringWidth() or (#text * 6)
    cache[key] = v
    self._widthCount = self._widthCount + 1
    return v
end

local function setText(self, key, fs, text)
    if self._cache[key] ~= text then
        fs:SetText(text)
        self._cache[key] = text
    end
    if text == "" then fs:Hide() else fs:Show() end
end

-- Coloca `region` (propia) con una firma cacheada: solo re-ancla si cambia.
local function place(self, key, region, sig, fn)
    if self._cache[key] == sig then return end
    self._cache[key] = sig
    region:ClearAllPoints()
    fn()
end

local function colored(code)
    local hex = code and E.COLOR.code[code]
    return hex and ("|cff" .. hex .. code .. "|r") or code
end

-- La barra de fuerzas de Blizzard en esta llave: la unica barra de progreso
-- usada del modulo. Si hay varias o ninguna, no se adivina.
function E:FindForcesBar(blizzTracker)
    local found, n = nil, 0
    local bars = get(blizzTracker, "usedProgressBars")
    if type(bars) ~= "table" then return nil, "NO_PROGRESS_BARS" end
    local ok = pcall(function()
        for _, blizzBar in pairs(bars) do
            if type(blizzBar) == "table" and get(blizzBar, "used") and read(blizzBar, "IsShown")
               and type(get(blizzBar, "Bar")) == "table" then
                n = n + 1
                found = blizzBar
            end
        end
    end)
    if not ok then return nil, "PROGRESS_BARS_UNREADABLE" end
    if n == 1 then return found, nil end
    return nil, n == 0 and "FORCES_BAR_ABSENT" or "FORCES_BAR_AMBIGUOUS"
end

-- model: TrackerPresenter.Build(); opts: ajustes + preciseForcesPercent.
-- Devuelve lo pintado (tabla plana, sin referencias a frames).
function E:Render(model, opts, reason)
    self._model, self._opts = model, opts
    if self._disabled then self:_HideElements(); return self._displayed end
    local ok, err = pcall(self._Render, self, model, opts, reason)
    if not ok then
        self._errors = self._errors + 1
        local S = MitzuMPlus.QASafe
        self._lastError = S and S.Text(err, 160) or tostring(err)
        record("RENDER_FAILED", { err = self._lastError, errors = self._errors })
        self:_HideElements()
        if self._errors >= E.MAX_ERRORS then
            self._disabled = true
            record("DISABLED", { reason = "TOO_MANY_ERRORS" })
        end
    end
    return self._displayed
end

function E:_Render(model, opts, reason)
    local TP = MitzuMPlus.TrackerPresenter
    local emb = TP.BuildEmbedded(model, opts)
    if not emb.active then
        self:_HideElements()
        self._displayed = { active = false }
        return
    end

    local blizzTracker, blizzBlock, why = self:FindBlock()
    if not blizzBlock then
        if self._attached or self._attachReason ~= why then record("NOT_FOUND", { reason = why }) end
        self:Detach(why)
        self._displayed = { active = true }
        return
    end
    self:InstallHooks(blizzTracker, blizzBlock)
    if self._blizzBlock ~= blizzBlock then
        self:Attach(blizzBlock, self._generation == 0 and "CHALLENGE_BLOCK_FOUND" or "CHALLENGE_BLOCK_REBUILT")
    end
    local el = self.elements

    if read(blizzBlock, "IsShown") ~= true or read(blizzBlock, "IsActive") ~= true then
        -- Bloque sin llave (todavia sin timer, o ya retirado): nada propio visible.
        self:_HideElements()
        self._attachReason = "CHALLENGE_BLOCK_INACTIVE"
        self._displayed = { active = true }
        return
    end
    self._attachReason = "ATTACHED"
    if not el.root:IsShown() then el.root:Show() end

    local L = E.LAYOUT
    local TPL = TP
    local blizzTimeLeft, blizzDeath = get(blizzBlock, "TimeLeft"), get(blizzBlock, "DeathCount")
    local blockW = read(blizzBlock, "GetWidth") or L.FALLBACK_BLOCK_W

    -- experimental.12: las posiciones ya no dependen del ancho medido del
    -- texto del reloj. Se conserva la medicion SOLO como telemetria QA.
    local timeW = read(blizzTimeLeft, "GetUnboundedStringWidth")
    local timeWidthSource = "UNBOUNDED"
    if type(timeW) ~= "number" or timeW <= 0 then
        timeW = read(blizzTimeLeft, "GetStringWidth")
        timeWidthSource = "STRING"
    end
    if type(timeW) ~= "number" or timeW <= 0 then
        timeW = L.FALLBACK_TIME_W
        timeWidthSource = "FALLBACK"
    end
    local defer = opts and opts.angryKeystones == true
    local measure = function(text, kind) return self:_Measure(text, kind) end

    -- Penalizacion junto al contador de muertes de Blizzard (a su izquierda).
    local penalty = (emb.penaltyText and blizzDeath and read(blizzDeath, "IsShown")) and emb.penaltyText or ""
    setText(self, "penalty", el.penalty, penalty)
    local penaltyW = 0
    if penalty ~= "" then
        penaltyW = measure(penalty, "penalty") + 4
        place(self, "penaltyAt", el.penalty, "death", function()
            el.penalty:SetPoint("RIGHT", blizzDeath, "LEFT", -2, 0)
        end)
    end
    local rightEdge = blockW - L.DEATH_RIGHT - 4 - penaltyW
    local paceRightEdge = blockW - L.DEATH_RIGHT - 4
    local rowWidth = math.max(0, rightEdge - L.LEVEL_X)
    local thresholdWidth = math.max(0, rowWidth - L.ELAPSED_COL_W - L.COLUMN_GAP)
    -- La penalizacion vive en la fila del reloj. Ritmo no se desplaza cuando
    -- cambia el contador de muertes: conserva siempre el centro del area segura.
    local paceWidth = math.max(0, paceRightEdge - L.LEVEL_X)

    -- Filas deterministas: timerRow comparte exactamente la vertical del
    -- TimeLeft nativo y tiene ancho fijo hasta el borde seguro; paceRow ocupa
    -- el mismo ancho pero una linea mas abajo. Ninguna usa GetStringWidth para
    -- decidir coordenadas.
    place(self, "timerGrid", el.timerRow, string.format("%d:%d", math.floor(rowWidth + 0.5), math.floor(rightEdge + 0.5)), function()
        el.timerRow:SetPoint("TOPLEFT", blizzTimeLeft, "TOPLEFT", 0, 0)
        el.timerRow:SetPoint("BOTTOMLEFT", blizzTimeLeft, "BOTTOMLEFT", 0, 0)
        el.timerRow:SetWidth(rowWidth)
    end)
    place(self, "paceGrid", el.paceRow, string.format("%d:%d", math.floor(paceWidth + 0.5), L.PACE_TOP_Y), function()
        el.paceRow:SetPoint("TOPLEFT", blizzTimeLeft, "TOPLEFT", 0, L.PACE_TOP_Y)
        el.paceRow:SetWidth(paceWidth)
        el.paceRow:SetHeight(L.PACE_ROW_H)
    end)

    local blizzBar, barWhy = self:FindForcesBar(blizzTracker)
    local blizzInner = blizzBar and get(blizzBar, "Bar") or nil
    local lay = TPL.LayoutEmbedded(emb, {
        thresholdWidth = thresholdWidth, paceWidth = paceWidth,
        deferThreshold = defer,
        forcesWidth = blizzInner and read(blizzInner, "GetWidth") or nil,
    }, measure)

    -- 1. Umbral: "+2 8:18" junto al reloj. dev.11: en oro y en la fuente Large,
    -- sin codigo de color en linea. Es el dato que el jugador busca de un
    -- vistazo y ahora pesa lo mismo que en Angry Keystones.
    local th = lay.threshold
    setText(self, "threshold", el.threshold, th.text or "")
    place(self, "thresholdAt", el.threshold, "GRID_RIGHT", function()
        el.threshold:SetPoint("BOTTOMRIGHT", el.timerRow, "BOTTOMRIGHT", 0, 0)
    end)

    -- 2. Ritmo: fila independiente y centrada. Sin prediccion valida no hay
    -- placeholder. Confianza/ETA solo aparecen a la derecha si caben SIN tocar
    -- el texto centrado; nunca desplazan Ritmo ni cambian su alineacion.
    local pc = lay.pace
    local paceText = pc.text and ("|cff" .. E.COLOR.label .. pc.label .. "|r " .. colored(pc.value)) or ""
    setText(self, "pace", el.pace, paceText)
    place(self, "paceAt", el.pace, "GRID_CENTER", function()
        el.pace:SetPoint("CENTER", el.paceRow, "CENTER", 0, 0)
    end)
    local extras = {}
    if pc.confidence then extras[#extras + 1] = pc.confidence end
    if pc.eta then extras[#extras + 1] = pc.eta end
    local extrasText = pc.text and table.concat(extras, "  ") or ""
    if extrasText ~= "" then
        local paceTextW = measure(pc.text, "pace")
        local extrasW = measure(extrasText, "secondary")
        local rightRoom = (paceWidth / 2) - (paceTextW / 2) - TPL.GAP
        if extrasW > rightRoom then extrasText = "" end
    end
    local extrasVisible = extrasText ~= ""
    setText(self, "paceExtra", el.paceExtra, extrasText)
    place(self, "paceExtraAt", el.paceExtra, "GRID_RIGHT", function()
        el.paceExtra:SetPoint("RIGHT", el.paceRow, "RIGHT", 0, 0)
    end)

    -- 3. Fuerzas: debajo de la barra de Blizzard, en dos columnas.
    local fo = lay.forces
    local showForces = blizzInner ~= nil and (fo.primary or fo.secondary) ~= nil
    if showForces then
        place(self, "forcesAt", el.forcesRoot, tostring(blizzInner), function()
            -- La fila propia copia la geometria real de la barra: sus dos
            -- extremos y una unica separacion vertical. Nada de coordenadas
            -- absolutas y nada escrito sobre la StatusBar de Blizzard.
            el.forcesRoot:SetPoint("TOPLEFT", blizzInner, "BOTTOMLEFT", 0, L.FORCES_GAP_Y)
            el.forcesRoot:SetPoint("TOPRIGHT", blizzInner, "BOTTOMRIGHT", 0, L.FORCES_GAP_Y)
            el.forcesRoot:SetHeight(L.FORCES_ROW_H)
            el.forcesPrimary:ClearAllPoints(); el.forcesSecondary:ClearAllPoints()
            -- experimental.13: ambos textos nacen en el borde SUPERIOR de la
            -- misma fila y usan el mismo FontObject. Asi la primera linea de
            -- glifos comparte baseline visual y queda a 3 px de la barra, sin
            -- caer al fondo de un contenedor de 14 px. X nunca depende del
            -- ancho del string: LEFT/RIGHT siguen los extremos reales del bar.
            el.forcesPrimary:SetPoint("TOPLEFT", el.forcesRoot, "TOPLEFT", L.FORCES_INSET, 0)
            el.forcesSecondary:SetPoint("TOPRIGHT", el.forcesRoot, "TOPRIGHT", -L.FORCES_INSET, 0)
        end)
    else
        self._cache.forcesAt = nil
    end
    setText(self, "forcesPrimary", el.forcesPrimary, showForces and fo.primary or "")
    setText(self, "forcesSecondary", el.forcesSecondary, showForces and fo.secondary or "")
    if showForces then
        if not el.forcesRoot:IsShown() then el.forcesRoot:Show() end
    elseif el.forcesRoot:IsShown() then
        el.forcesRoot:Hide()
    end

    local forcesLine = showForces and table.concat({ fo.primary or "", fo.secondary or "" }, fo.primary and fo.secondary and "  " or "") or nil
    self._displayed = {
        active = true,
        attachGeneration = self._generation,
        attachmentHealthy = self._attached == true and el.root:GetParent() == blizzBlock,
        provisional = emb.provisional == true,
        threshold = th.upgrade, thresholdTime = th.timeText, thresholdMode = th.mode,
        upgrade = th.text,
        pace = emb.paceCode, paceText = pc.text, paceMode = pc.mode,
        confidence = extrasVisible and pc.confidence or nil,
        eta = extrasVisible and pc.eta or nil,
        layoutMode = "GRID_V1",
        forcesPrimary = showForces and fo.primary or nil, forcesSecondary = showForces and fo.secondary or nil,
        -- Al 100 % Blizzard puede liberar su progress bar. Eso no es un
        -- fallo de layout: ya no hay fuerzas restantes que Mitzu deba repetir.
        forcesLayoutMode = emb.forcesComplete and "COMPLETE" or (blizzInner and fo.mode or "NO_BAR"),
        forces = forcesLine,
        forcesBar = blizzBar ~= nil, forcesBarReason = barWhy,
        penalty = penalty ~= "" and penalty or nil,
        -- dev.11: solo el NOMBRE de la plantilla, nunca el objeto de fuente.
        -- Responde a "se te ve pequeno" sin pedir una captura de pantalla.
        thresholdFont = E.FONT.threshold, paceFont = E.FONT.pace,
        forcesPrimaryFont = E.FONT.forces, forcesSecondaryFont = E.FONT.forcesSecondary,
        available = math.floor(rowWidth + 0.5),
        thresholdColumnWidth = math.floor(thresholdWidth + 0.5),
        paceRowWidth = math.floor(paceWidth + 0.5),
        timerTextWidth = math.floor(timeW + 0.5),
        timerWidthSource = timeWidthSource,
        angryKeystones = defer,
        reason = reason,
    }
end

function E:ApplySettings(scale, alpha)
    self._scale, self._alpha = scale, alpha
    local el = self.elements
    if not el then return end
    local s = tonumber(scale) or 1
    if s < E.SCALE_MIN then s = E.SCALE_MIN elseif s > E.SCALE_MAX then s = E.SCALE_MAX end
    local a = tonumber(alpha) or 1
    el.root:SetScale(s); el.forcesRoot:SetScale(s)
    el.root:SetAlpha(a); el.forcesRoot:SetAlpha(a)
    self._cache, self._widths = {}, nil
end

function E:DiagnosticFields()
    local blizzTracker, blizzBlock, why = self:FindBlock()
    local healthy = self._attached and blizzBlock ~= nil and self._blizzBlock == blizzBlock
        and self.elements ~= nil and read(self.elements.root, "GetParent") == blizzBlock
    local d = self._displayed or {}
    return {
        { "blizzardTrackerLoaded", blizzTracker ~= nil },
        { "challengeBlockFound", blizzBlock ~= nil },
        { "challengeBlockShown", blizzBlock and read(blizzBlock, "IsShown") == true or false },
        { "challengeBlockActive", blizzBlock and read(blizzBlock, "IsActive") == true or false },
        { "attached", self._attached },
        { "attachGeneration", self._generation },
        { "attachReason", self._attached and self._attachReason or (why or self._attachReason) },
        { "attachmentHealthy", healthy and true or false },
        { "hooksInstalled", self._hookedBlock ~= nil and self._hookedTracker ~= nil },
        { "forcesBarFound", d.forcesBar == true },
        { "forcesBarReason", d.forcesBarReason },
        { "thresholdDisplayed", d.threshold },
        { "thresholdTimeDisplayed", d.thresholdTime },
        { "thresholdMode", d.thresholdMode },
        { "paceDisplayed", d.paceText },
        { "paceMode", d.paceMode },
        { "layoutMode", d.layoutMode },
        { "confidenceTextDisplayed", d.confidence },
        { "etaDisplayed", d.eta },
        { "forcesPrimaryDisplayed", d.forcesPrimary },
        { "forcesSecondaryDisplayed", d.forcesSecondary },
        { "forcesLayoutMode", d.forcesLayoutMode },
        { "forcesLineDisplayed", d.forces },
        { "penaltyDisplayed", d.penalty },
        { "availableWidth", d.available },
        { "thresholdColumnWidth", d.thresholdColumnWidth },
        { "paceRowWidth", d.paceRowWidth },
        { "timerTextWidth", d.timerTextWidth },
        { "timerWidthSource", d.timerWidthSource },
        { "angryKeystonesLoaded", d.angryKeystones },
        { "lastLayoutReason", self._lastLayoutReason },
        { "enhancerErrors", self._errors },
        { "enhancerDisabled", self._disabled },
        { "lastEnhancerError", self._lastError },
    }
end

return E
