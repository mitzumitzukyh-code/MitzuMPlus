-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · Coach HUD V2  —  la vista principal durante una Mythic+
--
--   ┌──────────────────────────────────────────┐
--   │ MITZU  ESTANQUES DE VIDA RUBÍ +12   07:42 │
--   │ PULL 4 / 11                     RUTA 36% │
--   │ ███████████████░░░░░░░░░░░░░░░░░         │
--   │ AHORA      6 mobs · 89 tropas            │
--   │ SIGUIENTE  +17.4% · 5 mobs               │
--   │ COACH      acelera fuerzas               │
--   └──────────────────────────────────────────┘
--
-- ═════════════════════════════════════════════════════════════════════════
-- LA REGLA: EL HUD ES UNA VISTA, NO UNA AUTORIDAD
--
-- No guarda el pull, ni el estado de la llave, ni la ruta. Cada refresco
-- construye un MODELO leyendo a las autoridades y lo pinta:
--
--   DungeonContext  -> estado de la llave, mazmorra, nivel
--   ChallengeClock  -> tiempo (el del servidor, que sobrevive al /reload)
--   RouteManager    -> ruta elegida y su fuente
--   RouteProgress   -> pull actual y total  (ÚNICA autoridad del pull)
--   RunSession      -> si el pull viene de una recuperación
--   KeystoneTracker -> fuerzas oficiales, si son legibles
--   PredictionEngine + CoachAdvice -> recomendación, solo con evidencia
--
-- Lo único que recuerda es lo que PINTÓ (para no repintar texto igual y para
-- que el Bug Report pueda comparar "pull mostrado" con "pull autoritativo").
-- Eso es memoria de la vista, no estado del juego.
--
-- CUÁNDO SE REFRESCA: por eventos del bus del core (transiciones, ruta, pull,
-- recuperación) y PLAYER_ENTERING_WORLD. Durante RUNNING hay un ticker de 1 s
-- que actualiza el reloj y, cada 2 s, fuerzas y Coach. Sin OnUpdate, sin
-- escanear placas, sin mirar mobs.
--
-- VISIBILIDAD (de DungeonContext, nunca de "hay challengeMapID"):
--   OUTSIDE / IN_UNSUPPORTED_DUNGEON  oculto
--   PRE_KEY                           preparación compacta (ajuste showPreKey)
--   RUNNING                           HUD completo
--   COMPLETED                         resumen corto y se oculta a los 20 s
--   RESET                             oculto y memoria visual limpia
--
-- COMBATE: frame propio, sin plantillas seguras ni botones protegidos. Solo
-- informa. Aun así, lo que el jugador configura (escala, alfa, posición,
-- ratón) se aplica fuera de combate: si llega en combate se aplaza a
-- PLAYER_REGEN_ENABLED.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local HUD = {}
MitzuMPlus.CoachHUD = HUD

HUD.MODES = { HIDDEN = "HIDDEN", PREPARE = "PREPARE", RUN = "RUN", SUMMARY = "SUMMARY" }
HUD.SUMMARY_SECONDS = 20
HUD.RECOVERY_BADGE_SECONDS = 15
HUD.WIDTH = 300

local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local LOGO = "Interface\\AddOns\\MitzuMPlus\\Media\\Icons\\logo_64"

-- Memoria de la VISTA. Nada de esto es estado del juego.
HUD._frame         = nil
HUD._preview       = false
HUD._mode          = "HIDDEN"
HUD._displayed     = {}      -- lo último pintado: pull, count, mode...
HUD._lastReason    = nil
HUD._lastRefreshAt = nil
HUD._lastError     = nil
HUD._summaryUntil  = nil
HUD._recoveryUntil = nil
HUD._ticker        = nil
HUD._tick          = 0
HUD._lastAdviceKey = nil
HUD._pendingApply  = false
HUD._textCache     = {}

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

-- ─────────────────────────────────────────────────────────────────────────
-- AJUSTES  (MitzuMPlusDB.profile.settings.hud)
-- ─────────────────────────────────────────────────────────────────────────

HUD.DEFAULTS = {
    enabled = true, locked = false, scale = 1.0, alpha = 1.0, compact = false,
    showPreKey = true, replaceClassic = true,
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
        -- Sin DB todavia: una copia en memoria, nunca los DEFAULTS compartidos.
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
    -- Migración NO destructiva de la posición del PullHUD antiguo: se COPIA una
    -- vez; los campos viejos de MPlusAdaptiveRouteDB se quedan donde estaban.
    if h.point == nil and not h.migratedPullHud then
        local ar = rawget(_G, "MPlusAdaptiveRouteDB")
        local old = type(ar) == "table" and type(ar.settings) == "table" and ar.settings or nil
        if old and type(old.pullHudPoint) == "string" then
            h.point, h.relPoint = old.pullHudPoint, old.pullHudPoint
            h.x, h.y = tonumber(old.pullHudX) or 0, tonumber(old.pullHudY) or 0
        end
        h.migratedPullHud = true
    end
    return h
end

function HUD:IsEnabled() return self:Settings().enabled ~= false end

-- El overlay clásico del Coach consulta esto para no duplicarse en pantalla.
function HUD:ReplacesClassicOverlay()
    local s = self:Settings()
    return s.enabled ~= false and s.replaceClassic ~= false
end

-- ─────────────────────────────────────────────────────────────────────────
-- MODELO  (solo lectura de autoridades)
-- ─────────────────────────────────────────────────────────────────────────

local function method(obj, name, ...)
    if type(obj) ~= "table" or type(obj[name]) ~= "function" then return nil end
    local ok, a, b, c = pcall(obj[name], obj, ...)
    if not ok then return nil end
    return a, b, c
end

local function resumenPull(pull, totalForces)
    if type(pull) ~= "table" then return nil end
    local units, groups = 0, 0
    for _, m in ipairs(type(pull.mobs) == "table" and pull.mobs or {}) do
        groups = groups + 1
        units = units + (tonumber(m.amount) or 0)
    end
    local forces = tonumber(pull.count)
    local pct = (forces and totalForces and totalForces > 0) and (forces * 100 / totalForces) or nil
    return { units = units, groups = groups, forces = forces, pct = pct }
end

function HUD:_ModeFor(lifecycle)
    if not self:IsEnabled() then return "HIDDEN" end
    if lifecycle == "RUNNING" then return "RUN" end
    if lifecycle == "PRE_KEY" then
        return self:Settings().showPreKey ~= false and "PREPARE" or "HIDDEN"
    end
    if lifecycle == "COMPLETED" then
        if self._summaryUntil and now() < self._summaryUntil then return "SUMMARY" end
        return "HIDDEN"
    end
    return "HIDDEN"
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
    }
    if m.mode == "HIDDEN" then return m end

    local CC = MitzuMPlus.ChallengeClock
    if lifecycle == "RUNNING" then
        m.elapsed = num(method(CC, "GetElapsed"))
        m.limit   = num(method(CC, "GetTimeLimit"))
    end

    local RP = MitzuMPlus.RouteProgress
    local RM = MitzuMPlus.RouteManager
    local route = method(RP, "GetRoute")
    if type(route) == "table" and type(route.pulls) == "table" then
        local pull  = num(method(RP, "GetPullIndex"))
        local count = num(method(RP, "GetPullCount")) or #route.pulls
        local total = num(route.totalForces)
        local acum = 0
        for i = 1, math.min(pull or 0, #route.pulls) do
            acum = acum + (tonumber(route.pulls[i] and route.pulls[i].count) or 0)
        end
        m.route = {
            id = str(route.id), name = str(route.name),
            source = str(method(RM, "GetLoadSource")),
            state = str(method(RP, "GetState")),
            pull = pull, count = count,
            plannedPct = (total and total > 0 and pull) and math.min(100, acum * 100 / total) or nil,
        }
        m.current = pull and resumenPull(route.pulls[pull], total) or nil
        m.next = (pull and pull < count) and resumenPull(route.pulls[pull + 1], total) or nil
        m.lastPull = pull ~= nil and pull >= count
    end

    -- Tras un /reload, RouteProgress arranca en el pull 1 y RunSession tarda
    -- unos segundos en poder decidir (espera el cronometro del servidor). Pintar
    -- ese 1 y saltar luego al 4 recuperado seria mostrar un dato que aun no es
    -- el de la partida. Mientras hay un snapshot pendiente de decidir, el HUD
    -- dice que esta recuperando y no pinta numero. No decide nada: solo lee.
    if lifecycle == "RUNNING" and m.route then
        local RS = MitzuMPlus.RunSession
        local snap = method(RS, "GetSnapshot")
        if method(RS, "IsDecided") == false and type(snap) == "table" and snap.startedAt ~= nil then
            m.recovering = true
            m.route.pull, m.route.plannedPct = nil, nil
            m.current, m.next, m.lastPull = nil, nil, nil
        end
    end

    if lifecycle == "RUNNING" then
        local KT = MitzuMPlus.KeystoneTracker
        local official = method(KT, "GetOfficialSnapshot")
        if type(official) == "table" then
            local pct = num(official.enemyPct)
            local tot = num(official.enemyTotal)
            -- Solo con total conocido: un 0% sin total es "no lo sé", no un dato.
            if pct and tot and tot > 0 then m.forces = pct end
        end
        local PE = MitzuMPlus.PredictionEngine
        local run = rawget(_G, "MitzuMPlusCurrentRun")
        local snap = run and method(PE, "GetSnapshot", run) or nil
        local CA = MitzuMPlus.CoachAdvice
        if type(snap) == "table" and CA and CA.Evaluate then
            local okA, advice = pcall(CA.Evaluate, snap, { requireBasis = true })
            if okA then m.coach = advice end
        end
        if self._recoveryUntil and now() < self._recoveryUntil and method(RP, "WasRecovered") then
            m.recoveredPull = num(method(RP, "GetRecoveryPull"))
        end
    end
    return m
end

-- Datos MOCK, exclusivamente visuales. No lee ni escribe ninguna autoridad.
function HUD:PreviewModel()
    return {
        preview = true, mode = "RUN", lifecycle = "PREVIEW",
        dungeon = "MAZMORRA DE PRUEBA", level = 12,
        elapsed = 462, limit = 1800,
        route = { id = "preview", name = "Preview", source = "PREVIEW", state = "PREVIEW",
                  pull = 4, count = 11, plannedPct = 36 },
        current = { units = 6, groups = 3, forces = 89, pct = 16.2 },
        next = { units = 5, groups = 2, forces = 96, pct = 17.4 },
        forces = 31.5,
        coach = { key = "PACE", severity = "WARN", evidence = "PROJECTION",
                  text = "acelera fuerzas (faltan 0.7%/min)" },
    }
end

-- ─────────────────────────────────────────────────────────────────────────
-- TEXTO
-- ─────────────────────────────────────────────────────────────────────────

local function reloj(s)
    s = num(s)
    if not s then return "—" end
    local neg = s < 0
    s = math.abs(math.floor(s))
    return string.format("%s%d:%02d", neg and "-" or "", math.floor(s / 60), s % 60)
end
HUD.FormatClock = reloj

local COLOR = {
    gold   = { 0.96, 0.78, 0.25 },
    title  = { 1.00, 0.86, 0.45 },
    text   = { 0.92, 0.92, 0.94 },
    dim    = { 0.62, 0.62, 0.66 },
    good   = { 0.35, 0.95, 0.45 },
    warn   = { 1.00, 0.82, 0.20 },
    bad    = { 1.00, 0.35, 0.30 },
    info   = { 0.55, 0.85, 1.00 },
    preview= { 0.75, 0.55, 1.00 },
}
local SEVERITY_COLOR = { CRITICAL = COLOR.bad, WARN = COLOR.warn, INFO = COLOR.info, GOOD = COLOR.good }

function HUD:Lines(m)
    local L = {}
    local head = (m.dungeon and tostring(m.dungeon):upper()) or "MYTHIC+"
    if m.level then head = head .. " +" .. tostring(m.level) end
    L.header = head
    if m.mode == "RUN" then
        if m.limit and m.elapsed then
            L.clock = reloj(m.elapsed) .. " / " .. reloj(m.limit)
            local rem = m.limit - m.elapsed
            L.clockColor = rem <= 120 and COLOR.bad or (rem <= 300 and COLOR.warn or COLOR.text)
        else
            L.clock = reloj(m.elapsed)
            L.clockColor = COLOR.text
        end
    elseif m.mode == "PREPARE" then
        L.clock, L.clockColor = "PREPARACIÓN", COLOR.dim
    elseif m.mode == "SUMMARY" then
        L.clock, L.clockColor = "COMPLETADA", COLOR.good
    end

    local r = m.route
    if r and r.pull then
        L.pull = string.format("PULL %d / %d", r.pull, r.count or 0)
        L.routePct = r.plannedPct and string.format("RUTA %d%%", math.floor(r.plannedPct + 0.5)) or nil
        L.bar = r.plannedPct
    elseif r and m.recovering then
        L.pull = string.format("PULL — / %d", r.count or 0)
    elseif m.mode ~= "SUMMARY" then
        L.pull = "SIN RUTA"
    end

    if m.mode == "PREPARE" then
        if r then
            L.now = string.format("%s · %d pulls", tostring(r.name or r.id or "ruta"), r.count or 0)
        end
        L.status = "esperando la piedra"
        return L
    end

    if m.current then
        L.now = string.format("%d mobs · %s tropas", m.current.units or 0,
            m.current.forces and tostring(m.current.forces) or "—")
    end
    if m.next then
        L.next = string.format("%s · %d mobs",
            m.next.pct and string.format("+%.1f%%", m.next.pct) or "—", m.next.units or 0)
    elseif m.lastPull then
        L.next = "último pull de la ruta"
    end
    if m.coach then
        L.coach = m.coach.text
        L.coachColor = SEVERITY_COLOR[m.coach.severity] or COLOR.text
    end
    local status = {}
    if m.preview then status[#status + 1] = "PREVIEW · datos de ejemplo" end
    if m.recovering then status[#status + 1] = "recuperando la sesión" end
    if m.forces then status[#status + 1] = string.format("fuerzas %.1f%%", m.forces) end
    if m.recoveredPull then status[#status + 1] = "recuperado en pull " .. m.recoveredPull end
    if #status > 0 then L.status = table.concat(status, " · ") end
    return L
end

-- ─────────────────────────────────────────────────────────────────────────
-- FRAME
-- ─────────────────────────────────────────────────────────────────────────

local ROWS = { "now", "next", "coach", "status" }
local ROW_LABEL = { now = "AHORA", next = "SIGUIENTE", coach = "COACH", status = "" }

local function fuente(fs, kind, size, flags)
    local T = MitzuMPlus.Theme
    if T and T.ApplyFont then
        pcall(T.ApplyFont, T, fs, kind, size)
    else
        pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", size, flags or "")
    end
end

function HUD:_Build()
    if self._frame then return self._frame end
    local f = CreateFrame("Frame", "MitzuMPlusCoachHUD", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(HUD.WIDTH, 120)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(0.03, 0.035, 0.045, 0.82)
        f:SetBackdropBorderColor(0.45, 0.36, 0.12, 0.9)
    end

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(18, 18)
    logo:SetPoint("TOPLEFT", 8, -6)
    logo:SetTexture(LOGO)
    f.logo = logo

    local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fuente(header, "title", 12)
    header:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    header:SetJustifyH("LEFT")
    header:SetWordWrap(false)
    f.header = header

    local clock = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fuente(clock, "mono", 13)
    clock:SetPoint("TOPRIGHT", -10, -8)
    clock:SetJustifyH("RIGHT")
    f.clock = clock
    header:SetPoint("RIGHT", clock, "LEFT", -8, 0)

    local pull = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fuente(pull, "title", 18)
    pull:SetPoint("TOPLEFT", 10, -30)
    f.pull = pull

    local routePct = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fuente(routePct, "mono", 12)
    routePct:SetPoint("TOPRIGHT", -10, -34)
    f.routePct = routePct

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    bar:SetHeight(6)
    bar:SetPoint("TOPLEFT", 10, -54)
    bar:SetPoint("TOPRIGHT", -10, -54)
    bar:SetStatusBarColor(0.96, 0.72, 0.18, 1)
    local bbg = bar:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints(bar)
    bbg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
    f.bar = bar

    f.rows = {}
    for i, key in ipairs(ROWS) do
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fuente(label, "normal", 10)
        label:SetTextColor(COLOR.dim[1], COLOR.dim[2], COLOR.dim[3], 1)
        label:SetText(ROW_LABEL[key])
        local value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fuente(value, "normal", 12)
        value:SetJustifyH("LEFT")
        value:SetWordWrap(false)
        f.rows[key] = { label = label, value = value, index = i }
    end

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
    local visible = m.mode ~= "HIDDEN"
    if not visible then
        if self._frame and self._frame:IsShown() then self._frame:Hide() end
        self._displayed = { mode = "HIDDEN" }
        return
    end
    local f = self:_Build()
    local L = self:Lines(m)
    local s = self:Settings()
    local compact = s.compact == true

    setText(self, f.header, "header", L.header, m.preview and COLOR.preview or COLOR.title)
    setText(self, f.clock, "clock", L.clock or "", L.clockColor or COLOR.text)
    setText(self, f.pull, "pull", L.pull or "", COLOR.gold)
    setText(self, f.routePct, "routePct", L.routePct or "", COLOR.dim)
    if L.bar then
        f.bar:SetValue(math.max(0, math.min(100, L.bar)))
        f.bar:Show()
    else
        f.bar:Hide()
    end

    local y = -66
    for _, key in ipairs(ROWS) do
        local row = f.rows[key]
        local text = L[key]
        local show = text ~= nil and (not compact or key == "coach" or key == "status")
        if show then
            row.label:ClearAllPoints()
            row.label:SetPoint("TOPLEFT", 10, y - 2)
            row.value:ClearAllPoints()
            row.value:SetPoint("TOPLEFT", key == "status" and 10 or 78, y)
            row.value:SetPoint("RIGHT", f, "RIGHT", -10, 0)
            local color = COLOR.text
            if key == "coach" then color = L.coachColor or COLOR.text end
            if key == "status" then color = m.preview and COLOR.preview or COLOR.dim end
            setText(self, row.value, "row_" .. key, text, color)
            row.label:Show()
            row.value:Show()
            y = y - 17
        else
            row.label:Hide()
            row.value:Hide()
        end
    end
    local height = math.max(66, -y + 6)
    if self._displayed.height ~= height then f:SetHeight(height) end

    if not f:IsShown() then f:Show() end
    self._displayed = {
        mode = m.mode, preview = m.preview == true, height = height,
        pull = m.route and m.route.pull or nil,
        count = m.route and m.route.count or nil,
        recovering = m.recovering == true,
        lifecycle = m.lifecycle,
        adviceKey = m.coach and m.coach.key or nil,
    }
end

-- ─────────────────────────────────────────────────────────────────────────
-- REFRESCO
-- ─────────────────────────────────────────────────────────────────────────

function HUD:Refresh(reason)
    self._lastReason = reason or "UNKNOWN"
    self._lastRefreshAt = now()
    local ok, err = pcall(function()
        local antes = self._mode
        local m = self:BuildModel()
        self:Render(m)
        self._mode = m.mode
        if antes ~= m.mode then
            record(m.mode == "HIDDEN" and "HIDDEN" or "SHOWN",
                { mode = m.mode, reason = self._lastReason, preview = m.preview or nil })
        end
        local adviceKey = m.coach and m.coach.key or nil
        if adviceKey ~= self._lastAdviceKey and not m.preview then
            self._lastAdviceKey = adviceKey
            record("COACH_ADVICE", { key = adviceKey or "NONE",
                evidence = m.coach and m.coach.evidence or nil })
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

-- Ticker solo mientras hay HUD completo. Reloj cada segundo; el resto cada 2.
function HUD:_SyncTicker(mode)
    local needed = (mode == "RUN")
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

-- ─────────────────────────────────────────────────────────────────────────
-- API PARA COMANDOS Y CONFIGURACIÓN
-- ─────────────────────────────────────────────────────────────────────────

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
    record(on and "PREVIEW_ON" or "PREVIEW_OFF")
    self:Refresh(on and "PREVIEW_ON" or "PREVIEW_OFF")
    return on
end

function HUD:IsPreview() return self._preview == true end
function HUD:IsVisible() return self._frame ~= nil and self._frame:IsShown() == true end
function HUD:GetMode() return self._mode end
function HUD:GetDisplayedPull() return self._displayed and self._displayed.pull or nil end
function HUD:IsRecovering() return self._displayed and self._displayed.recovering == true or false end
function HUD:GetDisplayed() return self._displayed end
function HUD:GetLastRefreshReason() return self._lastReason end
function HUD:GetLastError() return self._lastError end
function HUD:IsTickerActive() return self._ticker ~= nil end

function HUD:SetOption(key, value)
    local s = self:Settings()
    if key == "scale" then
        s.scale = clamp(value, 0.6, 2.0, s.scale)
    elseif key == "alpha" then
        s.alpha = clamp(value, 0.2, 1.0, s.alpha)
    elseif key == "locked" or key == "compact" or key == "showPreKey" or key == "replaceClassic" then
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

function HUD:StatusLines()
    local s = self:Settings()
    local RP = MitzuMPlus.RouteProgress
    return {
        "enabled=" .. tostring(s.enabled ~= false),
        "visible=" .. tostring(self:IsVisible()),
        "mode=" .. tostring(self._mode),
        "preview=" .. tostring(self._preview),
        "displayedPull=" .. tostring(self:GetDisplayedPull()),
        "authoritativePull=" .. tostring(method(RP, "GetPullIndex")),
        "lastRefreshReason=" .. tostring(self._lastReason),
        "locked=" .. tostring(s.locked == true) .. " scale=" .. tostring(s.scale) ..
            " alpha=" .. tostring(s.alpha) .. " compact=" .. tostring(s.compact == true),
        "replaceClassic=" .. tostring(s.replaceClassic ~= false),
        "ticker=" .. tostring(self._ticker ~= nil),
    }
end

-- ─────────────────────────────────────────────────────────────────────────
-- SUSCRIPCIONES
--
-- Prioridad 5: después de las autoridades del core (10-90), así el modelo lee
-- el estado ya consolidado de cada evento.
-- ─────────────────────────────────────────────────────────────────────────

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
        elseif nuevo == "RESET" or nuevo == "OUTSIDE" then
            HUD._summaryUntil, HUD._recoveryUntil = nil, nil
            HUD._textCache = {}
        end
        if nuevo == "RUNNING" and HUD._preview then
            -- La vista previa nunca sobrevive al arranque de una llave real.
            HUD._preview = false
            record("PREVIEW_OFF", { reason = "KEY_STARTED" })
        end
        HUD:Refresh("LIFECYCLE_" .. tostring(nuevo))
    end, P)
    bus:On("MITZU_DUNGEON_CHANGED", function() HUD:Refresh("DUNGEON_CHANGED") end, P)
    for _, ev in ipairs({ "MITZU_ROUTE_LOADED", "MITZU_ROUTE_UNLOADED", "MITZU_ROUTE_PREPARED",
                          "MITZU_ROUTE_STARTED", "MITZU_ROUTE_COMPLETED" }) do
        bus:On(ev, function() HUD:Refresh(ev) end, P)
    end
    bus:On("MITZU_ROUTE_RECOVERED", function()
        HUD._recoveryUntil = now() + HUD.RECOVERY_BADGE_SECONDS
        HUD:Refresh("ROUTE_RECOVERED")
    end, P)
    bus:On("MITZU_PULL_CHANGED", function(_, _, reason)
        HUD:Refresh("PULL_" .. tostring(reason or "CHANGED"))
    end, P)
    bus:On("RUN_STARTED", function() HUD:Refresh("RUN_STARTED") end, P)
    bus:On("RUN_TEARDOWN", function() HUD:Refresh("RUN_TEARDOWN") end, P)
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
