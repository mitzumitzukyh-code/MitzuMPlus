-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuRouteArrows · GuidanceEngine v1  —  DECIDIR, y nada más
--
-- Responde a una sola pregunta:
--     ¿esta placa visible debe llevar flecha para el pull actual?
--
-- No dibuja, no crea frames, no toca Threat Plates, no conoce MDT y no sabe
-- qué es un atlas. Devuelve una decisión; quien la pinta es RouteArrowPresenter.
--
-- ═════════════════════════════════════════════════════════════════════════
-- POLÍTICA ESTRICTA — la regla que manda
--
--     MATCH        -> flecha
--     AMBIGUOUS    -> NO
--     UNKNOWN      -> NO
--     NO_MATCH     -> NO
--
-- Y fuera de RUNNING, nunca. En 12.1 la identidad del enemigo llega secreta
-- (comprobado en vivo: enemyIdentity=SECRET, forces=SECRET), así que hoy casi
-- todo será UNKNOWN. Eso es correcto: cero flechas es un resultado honesto,
-- cinco flechas sobre mobs equivocados no.
-- ═════════════════════════════════════════════════════════════════════════
--
-- EL PULL NO SE GUARDA AQUÍ. RouteProgress es la única autoridad y se le
-- pregunta cada vez. Lo único que se cachea es el índice derivado del pull, y
-- se tira entero en MITZU_PULL_CHANGED.
--
-- QUÉ NO HACE, y es deliberado: no cuenta muertes, no avanza el pull y no
-- interpreta NAME_PLATE_UNIT_REMOVED como nada más que "esa placa dejó de
-- verse". Una placa desaparece por rango, cámara, reciclaje o phasing.
-- ═══════════════════════════════════════════════════════════════════════════

local MRA = _G.MitzuRouteArrows
if not MRA then return end

-- AR: los demas modulos de este mismo addon.
-- Host: fachada de SOLO LECTURA sobre MitzuMPlusAPI (Core/Host.lua).
local AR = MRA
local Host = MRA.Host

local GuidanceEngine = {}
MRA.GuidanceEngine = GuidanceEngine

-- Estados que puede devolver el resolver, más el de prueba visual.
local MATCH, AMBIGUOUS, NO_MATCH, UNKNOWN =
      "MATCH", "AMBIGUOUS", "NO_MATCH", "UNKNOWN"
-- DEBUG_FORCED NUNCA se confunde con MATCH. Es un estado propio para que
-- ningún informe pueda presentar una prueba visual como identificación real.
local DEBUG_FORCED = "DEBUG_FORCED"

GuidanceEngine.STATES = {
    MATCH = MATCH, AMBIGUOUS = AMBIGUOUS, NO_MATCH = NO_MATCH,
    UNKNOWN = UNKNOWN, DEBUG_FORCED = DEBUG_FORCED,
}

-- Solo estos dos producen flecha. Cualquier estado nuevo cae por defecto del
-- lado de no marcar, que es donde debe caer una duda.
local MARCABLE = { [MATCH] = true, [DEBUG_FORCED] = true }

-- [unitToken] = true. Significa SOLO "esta placa se está viendo". No significa
-- vivo, ni muerto, ni del pull.
GuidanceEngine._visible = {}
GuidanceEngine._last    = {}   -- [unitToken] = última decisión, para el informe
GuidanceEngine._forced  = {}   -- [unitToken] = true, solo /mra arrowpulltest

-- ─────────────────────────────────────────────────────────────────────────
-- CONTEXTO
-- ─────────────────────────────────────────────────────────────────────────

-- La llave tiene que estar CORRIENDO. Que exista una ruta cargada no basta:
-- en PRE_KEY la ruta ya está preparada y ahí no se pinta nada.
function GuidanceEngine:IsRunning()
    local DC = Host.DungeonContext
    if DC and DC:GetState() ~= "RUNNING" then return false end
    local RP = Host.RouteProgress
    if not RP or RP:GetState() ~= "ACTIVE" then return false end
    return true
end

-- El pull actual, siempre desde RouteProgress. Nunca una copia local.
function GuidanceEngine:GetCurrentPullIndex()
    local RP = Host.RouteProgress
    return RP and RP:GetPullIndex() or nil
end

function GuidanceEngine:GetCurrentPull()
    local RP = Host.RouteProgress
    return RP and RP:GetCurrentPull() or nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- DECISIÓN
-- ─────────────────────────────────────────────────────────────────────────

-- ═════════════════════════════════════════════════════════════════════════
-- DECISIONES CANÓNICAS — BUG SEC-2
--
-- Visto en vivo: `nameplate1 UNKNOWN arrow=no NOT_RUNNING` se copiaba bien,
-- pero `nameplate3 UNKNOWN arrow=no FORCES_SECRET` disparaba el aviso de
-- Blizzard. La diferencia: NOT_RUNNING es un literal nuestro; FORCES_SECRET
-- venía del resolver.
--
-- POR QUÉ EL INTENTO ANTERIOR NO BASTÓ: validaba el motivo contra una lista
-- blanca y luego devolvía EL VALOR VALIDADO (`SAFE_REASONS[v] and v`).
-- Validar no es sanear. Comprobar que algo es aceptable y después
-- transportarlo sigue transportándolo.
--
-- AHORA: no se copia NADA del resolver. Las decisiones son tablas construidas
-- aquí, una vez, y se devuelven tal cual. La frontera vive en
-- LiveEnemyResolver:ResolveForGuidance, que devuelve un solo string canónico.
--
-- Se pierde detalle: un UNKNOWN ya no dice si fue por FORCES_SECRET o por
-- FORCES_NOT_RETURNED. Es un precio pequeño frente a transportar un valor
-- secreto, y la observabilidad fina sigue en /mra probe.
-- ═════════════════════════════════════════════════════════════════════════

-- Tablas fijas, creadas una sola vez. No se copian ni se mutan: quien las
-- recibe recibe siempre el mismo objeto, propiedad de Mitzu de punta a punta.
local DECISION_MATCH = {
    state = MATCH, shouldMark = true, reasonCode = "RESOLVER_MATCH" }
local DECISION_AMBIGUOUS = {
    state = AMBIGUOUS, shouldMark = false, reasonCode = "RESOLVER_AMBIGUOUS" }
local DECISION_NO_MATCH = {
    state = NO_MATCH, shouldMark = false, reasonCode = "RESOLVER_NO_MATCH" }
local DECISION_UNKNOWN = {
    state = UNKNOWN, shouldMark = false, reasonCode = "RESOLVER_UNKNOWN" }

-- Situaciones que decide Guidance sin llegar a preguntar al resolver.
local DECISION_NOT_RUNNING = {
    state = UNKNOWN, shouldMark = false, reasonCode = "NOT_RUNNING" }
local DECISION_NO_PULL = {
    state = UNKNOWN, shouldMark = false, reasonCode = "NO_CURRENT_PULL" }
local DECISION_NO_RESOLVER = {
    state = UNKNOWN, shouldMark = false, reasonCode = "NO_RESOLVER" }
local DECISION_NO_TOKEN = {
    state = UNKNOWN, shouldMark = false, reasonCode = "NO_UNIT_TOKEN" }
local DECISION_DEBUG = {
    state = DEBUG_FORCED, shouldMark = true, reasonCode = "DEBUG_VISUAL_TEST" }

GuidanceEngine.DECISIONS = {
    MATCH = DECISION_MATCH, AMBIGUOUS = DECISION_AMBIGUOUS,
    NO_MATCH = DECISION_NO_MATCH, UNKNOWN = DECISION_UNKNOWN,
    NOT_RUNNING = DECISION_NOT_RUNNING, NO_CURRENT_PULL = DECISION_NO_PULL,
    NO_RESOLVER = DECISION_NO_RESOLVER, NO_UNIT_TOKEN = DECISION_NO_TOKEN,
    DEBUG_FORCED = DECISION_DEBUG,
}

-- Traduce el estado canónico del resolver a una decisión nuestra. Se compara
-- contra literales y se devuelve una tabla propia: el string recibido no se
-- guarda en ningún sitio.
local function decisionPara(canonState)
    if canonState == "MATCH"     then return DECISION_MATCH end
    if canonState == "AMBIGUOUS" then return DECISION_AMBIGUOUS end
    if canonState == "NO_MATCH"  then return DECISION_NO_MATCH end
    return DECISION_UNKNOWN
end

function GuidanceEngine:Evaluate(unitToken)
    if type(unitToken) ~= "string" then return DECISION_NO_TOKEN end

    -- Prueba visual: separada del resolver por completo, con estado propio.
    if self._forced[unitToken] then return DECISION_DEBUG end

    if not self:IsRunning() then return DECISION_NOT_RUNNING end
    if not self:GetCurrentPull() then return DECISION_NO_PULL end

    local AR = MRA
    local LER = AR and AR.LiveEnemyResolver
    -- SOLO la API de frontera. Resolve() devuelve la observación entera y
    -- Guidance no debe verla nunca: es la regla que este bug enseñó a golpes.
    if not LER or type(LER.ResolveForGuidance) ~= "function" then
        return DECISION_NO_RESOLVER
    end

    local ok, canon = pcall(function()
        return LER:ResolveForGuidance(unitToken, self:GetCurrentPullIndex())
    end)
    if not ok then return DECISION_UNKNOWN end

    -- `canon` se compara y se descarta.
    return decisionPara(canon)
end

-- ─────────────────────────────────────────────────────────────────────────
-- PLACAS VISIBLES
-- ─────────────────────────────────────────────────────────────────────────

function GuidanceEngine:OnNameplateAdded(unitToken)
    if type(unitToken) ~= "string" then return nil end
    self._visible[unitToken] = true
    local d = self:Evaluate(unitToken)
    self._last[unitToken] = d
    return d
end

-- Una placa que se deja de ver se olvida. Nada más: ni muerte, ni progreso,
-- ni tropas. Si esto llegara a tocar RouteProgress sería un auto-avance
-- basado en la cámara del jugador.
function GuidanceEngine:OnNameplateRemoved(unitToken)
    if type(unitToken) ~= "string" then return end
    self._visible[unitToken] = nil
    self._last[unitToken]    = nil
    self._forced[unitToken]  = nil
end

function GuidanceEngine:GetVisible()
    local out = {}
    for token in pairs(self._visible) do out[#out + 1] = token end
    table.sort(out)
    return out
end

-- Reevalúa TODAS las placas que se están viendo. Es lo que permite que
-- cambiar de pull surta efecto sin esperar a que las placas desaparezcan y
-- vuelvan.
function GuidanceEngine:EvaluateAll()
    local out = {}
    for _, token in ipairs(self:GetVisible()) do
        local d = self:Evaluate(token)
        self._last[token] = d
        out[token] = d
    end
    return out
end

function GuidanceEngine:GetLastDecision(unitToken)
    return unitToken and self._last[unitToken] or nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- PRUEBA VISUAL
--
-- Existe para demostrar el recorrido completo cuando Blizzard impide obtener
-- un MATCH real. Va por el MISMO camino que una decisión de verdad —Guidance,
-- Presenter, RouteArrows— pero con un estado propio, DEBUG_FORCED, que nadie
-- puede confundir con identificación real.
-- ─────────────────────────────────────────────────────────────────────────

function GuidanceEngine:SetDebugForced(tokens)
    self._forced = {}
    for _, t in ipairs(tokens or {}) do
        if type(t) == "string" then self._forced[t] = true end
    end
    return self:CountForced()
end

function GuidanceEngine:ClearDebugForced()
    local n = self:CountForced()
    self._forced = {}
    return n
end

function GuidanceEngine:CountForced()
    local n = 0
    for _ in pairs(self._forced) do n = n + 1 end
    return n
end

function GuidanceEngine:HasDebugForced() return self:CountForced() > 0 end

-- ─────────────────────────────────────────────────────────────────────────
-- INFORME
--
-- SECRET-SAFE por diseño: aquí solo salen tokens de placa ("nameplate3"),
-- estados y motivos. Ni GUIDs, ni nombres, ni vidas, ni tropas por unidad.
-- ─────────────────────────────────────────────────────────────────────────

function GuidanceEngine:Summary()
    local s = { MATCH = 0, AMBIGUOUS = 0, NO_MATCH = 0, UNKNOWN = 0,
                DEBUG_FORCED = 0, visible = 0, wanted = 0 }
    for _, token in ipairs(self:GetVisible()) do
        s.visible = s.visible + 1
        local d = self._last[token] or self:Evaluate(token)
        s[d.state] = (s[d.state] or 0) + 1
        if d.shouldMark then s.wanted = s.wanted + 1 end
    end
    return s
end

function GuidanceEngine:StatusLines()
    local DC = Host.DungeonContext
    local RM = Host.RouteManager
    local RP = Host.RouteProgress
    local P  = MRA.RouteArrowPresenter
    local RA = MRA.RouteArrows
    local route = RM and RM:GetActiveRoute()
    local s = self:Summary()

    local L = {}
    L[#L + 1] = "state=" .. tostring(DC and DC:GetState() or "?")
    L[#L + 1] = "routeState=" .. tostring(RP and RP:GetState() or "?")
    L[#L + 1] = "guidanceActive=" .. tostring(self:IsRunning())
    L[#L + 1] = "route=" .. tostring(route and route.id or "ninguna")
    L[#L + 1] = string.format("pull=%s/%s",
        tostring(RP and RP:GetPullIndex() or "?"),
        tostring(RP and RP:GetPullCount() or "?"))
    L[#L + 1] = "visibleNameplates=" .. s.visible
    L[#L + 1] = string.format("MATCH=%d  AMBIGUOUS=%d  UNKNOWN=%d  NO_MATCH=%d",
        s.MATCH, s.AMBIGUOUS, s.UNKNOWN, s.NO_MATCH)
    if s.DEBUG_FORCED > 0 then
        L[#L + 1] = "|cFFf7d470DEBUG_FORCED=" .. s.DEBUG_FORCED ..
                    " (prueba visual, NO identificacion real)|r"
    end
    L[#L + 1] = "arrowsWanted=" .. s.wanted
    L[#L + 1] = "arrowsVisible=" .. tostring(RA and RA:CountActive() or "?")
    L[#L + 1] = "presenterTracked=" .. tostring(P and P:CountTracked() or "?")
    return L
end

function GuidanceEngine:DetailLines()
    local tokens = self:GetVisible()
    if #tokens == 0 then
        return { "|cFFff9922No hay ninguna placa visible.|r" }
    end
    local RA = MRA.RouteArrows
    local L = {}
    for _, token in ipairs(tokens) do
        local d = self._last[token] or self:Evaluate(token)
        local color = (d.state == MATCH and "|cFF21de66")
                   or (d.state == DEBUG_FORCED and "|cFFf7d470")
                   or (d.state == AMBIGUOUS and "|cFFff9922")
                   or (d.state == NO_MATCH and "|cFFff5555") or "|cFF999999"
        L[#L + 1] = string.format("%-12s %s%-13s|r arrow=%-3s %s",
            token, color, d.state,
            (RA and RA:IsMarked(token)) and "si" or "no",
            tostring(d.reasonCode or ""))
    end
    return L
end

return GuidanceEngine
