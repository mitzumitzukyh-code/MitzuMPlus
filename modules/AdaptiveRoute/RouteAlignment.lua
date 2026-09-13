-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · RouteAlignment (FASE 4)  —  SOLO DIAGNÓSTICO
--
-- Junta las tres piezas y deja constancia:
--
--   ArrowDemo (tick 0,4 s)
--        │ obs = { token, gen, engagement, pointed }
--        ▼
--   ExecutionEpisodeTracker ──► PhysicalGroupObservation
--        │                              │
--        │                              ▼
--        │                    RoutePullCandidateScorer  (puro)
--        │                              │
--        ▼                              ▼
--   ArrowDemoTelemetry  ◄──────  RouteAlignmentHypothesis
--
-- LO QUE ESTE MÓDULO NO HACE — Y ES LO IMPORTANTE
--   · NO llama a RouteProgress:SetPull, NextPull, PreviousPull ni RestorePull.
--     Ni una vez. Hay una comprobación estática que lo verifica.
--   · NO toca flechas. Ni las de producción ni las de la demo. Una hipótesis
--     STRONG no pinta nada distinto: esta fase es medir, no actuar.
--   · NO escribe identidad en ningún sitio.
--
-- POR QUÉ VIVE EN EL TICK DE LA DEMO
-- Observar cuesta: EngagementEvidence pregunta por cada placa y cada miembro
-- del grupo. Montar un segundo bucle propio duplicaría ese coste para leer
-- exactamente lo mismo. Así que la alineación se alimenta del tick que ya
-- existe, y el interruptor del pipeline experimental sigue siendo uno solo:
-- `/emp arrowdemo on`. `/emp align off` apaga la inferencia, no la
-- observación.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local RouteAlignment = {}
AR.RouteAlignment = RouteAlignment

RouteAlignment.PARAMS = {
    EVAL_INTERVAL_MS   = 1000,  -- cada cuánto se vuelve a puntuar
    MAX_LOGGED_PER_EP  = 12,    -- cambios de hipótesis registrados por episodio
    MAX_CANDIDATE_LINES = 4,    -- candidatos volcados por cambio
    -- Episodios seguidos sin poder decir nada antes de volver a creerle al
    -- número de pull de verdad. Es la valvula de escape de una deriva.
    RESYNC_AFTER_BLIND = 2,
}
local P = RouteAlignment.PARAMS

-- ═════════════════════════════════════════════════════════════════════════
-- EL ANCLA: UNA CREENCIA PROPIA QUE NO ES RouteProgress
--
-- HALLAZGO AL SIMULAR LA RUTA REAL: en la M+ que ya jugamos, RouteProgress
-- se quedó en el pull 1 durante los 25 minutos enteros. Si la ventana de
-- candidatos se ancla SOLO en ese número, a partir del tercer pack todos los
-- candidatos son pulls que ya pasaron y la inferencia solo puede decir
-- NO_EVIDENCE. Nunca podría demostrarse lo que pide la fase.
--
-- Así que esta capa lleva su PROPIO número de pull creído. Avanza cuando un
-- episodio cierra con una hipótesis suficientemente buena y NUNCA se escribe
-- en RouteProgress: es una creencia de diagnóstico, y verla equivocarse en
-- la telemetría es justamente el objetivo de la fase.
--
-- Dos frenos contra la deriva:
--   · si el jugador mueve el pull a mano, el ancla se resincroniza con él.
--     El jugador es la verdad; la inferencia, no.
--   · tras RESYNC_AFTER_BLIND episodios sin poder decir nada, se vuelve al
--     número de verdad en vez de seguir a ciegas desde donde se perdió.
-- ═════════════════════════════════════════════════════════════════════════

RouteAlignment._inferredPull = nil
RouteAlignment._lastRpPull   = nil
RouteAlignment._blindStreak  = 0

RouteAlignment._enabled   = true
RouteAlignment._hypothesis = nil
RouteAlignment._persistLabel = nil
RouteAlignment._persistMs    = 0
RouteAlignment._lastEvalMs   = nil
RouteAlignment._loggedThisEp = 0
RouteAlignment._lastLogged   = nil
RouteAlignment._history      = {}

local function EET() return AR.ExecutionEpisodeTracker end
local function Scorer() return AR.RoutePullCandidateScorer end
local function TEL() return AR.ArrowDemoTelemetry end

function RouteAlignment:IsEnabled() return self._enabled == true end
function RouteAlignment:SetEnabled(on)
    local target = on == true
    if target == self._enabled then return self._enabled end
    -- Una pausa es una frontera dura: al apagar o reactivar no se conservan
    -- miembros, relojes, puntuaciones ni evidencia temporal del episodio.
    self:Reset(nil)
    self._enabled = target
    return self._enabled
end
function RouteAlignment:Get() return self._hypothesis end
function RouteAlignment:History() return self._history end

-- ─────────────────────────────────────────────────────────────────────────
-- ENTORNO
-- ─────────────────────────────────────────────────────────────────────────

local function rutaYPull()
    local RP = MitzuMPlus.RouteProgress
    if not RP then return nil, nil, nil end
    local ok, route, idx, total = pcall(function()
        return RP:GetRoute(), RP:GetPullIndex(), RP:GetPullCount()
    end)
    if not ok then return nil, nil, nil end
    return route, tonumber(idx), tonumber(total)
end

local function log(code, fields)
    local t = TEL()
    if t and t.IsRecording and t:IsRecording() then pcall(t.Log, t, code, fields) end
end

local function count(key, n)
    local t = TEL()
    if t and t.IsRecording and t:IsRecording() then pcall(t.Count, t, key, n) end
end

-- ─────────────────────────────────────────────────────────────────────────
-- ENTRADA ÚNICA
--
-- La llama ArrowDemo con la misma lista que usa para decidir flechas. Nada
-- de lo que se haga aquí puede volver a ArrowDemo: es una calle de un solo
-- sentido, y por eso la demo no cambia de comportamiento por tener esto.
-- ─────────────────────────────────────────────────────────────────────────

-- `now` llega en SEGUNDOS, que es lo que usa el tick de ArrowDemo (GetTime).
-- Aguas abajo todo va en milisegundos, como el resto de la telemetría: aquí
-- está la única conversión, y por eso está sola y señalada. Es una diferencia
-- de tiempos, así que el origen del reloj da igual.
function RouteAlignment:Feed(obs, nowSeconds)
    if not self._enabled then return end
    local tracker = EET()
    if not tracker then return end
    local now = (tonumber(nowSeconds) or 0) * 1000
    -- Antes que nada, y en CADA tick, no solo cuando toque puntuar: si el
    -- jugador ha movido el pull, esa es la verdad desde ese mismo instante.
    self:_SyncAnchor()

    local evento, ep = tracker:Observe(obs, now)

    if evento == "STARTED" and ep then
        self._persistLabel, self._persistMs = nil, 0
        self._lastEvalMs, self._loggedThisEp, self._lastLogged = nil, 0, nil
        self._hypothesis = nil
        count("physicalEpisodes")
        log("PHYSICAL_EPISODE_START", {
            "episode", ep.episodeID,
            "routePull", ep.routePullAtStart or "-",
            "engaged", ep.generationsEngaged,
            "encounter", ep.encounterActive and 1 or 0,
        })
        if (ep.repeatedGenerations or 0) > 0 then
            count("possibleWipes")
            log("POSSIBLE_WIPE", {
                "episode", ep.episodeID, "repeatedGenerations", ep.repeatedGenerations,
            })
        end
        return
    end

    if evento == "ENDED" and ep then
        self:_Evaluate(ep, now, true)
        local o = tracker:Observation(ep)
        local h = self._hypothesis
        self:_AdvanceAnchor(h)
        log("PHYSICAL_EPISODE_END", {
            "episode", ep.episodeID,
            "durationMs", ep.durationMs or 0,
            "engaged", ep.generationsEngaged,
            "peak", ep.peakSimultaneousEngaged,
            "joined", ep.joinedDuringExecution,
            "removed", ep.removedDuringExecution,
            "routePull", ep.routePullAtEnd or "-",
            "state", h and h.state or "NO_EVIDENCE",
            "candidate", h and h.label or "-",
            "candidateScore", h and h.candidateScore or 0,
            "candidateMargin", h and h.candidateMargin or 0,
            "episodeConfidence", h and h.episodeConfidence or 0,
            "npcCoverage", o and o.npcCoverage or 0,
            "anchor", h and h.anchorPull or "-",
            "nextAnchor", self._inferredPull or "-",
        })
        if h then
            self._history[#self._history + 1] = {
                episodeID = ep.episodeID, state = h.state, label = h.label,
                candidateScore = h.candidateScore,
                runnerUpLabel = h.runnerUpLabel,
                candidateMargin = h.candidateMargin,
                episodeConfidence = h.episodeConfidence,
                confidenceState = h.confidenceState,
                routePull = ep.routePullAtStart,
                anchor = h.anchorPull,
            }
            while #self._history > 20 do table.remove(self._history, 1) end
        end
        return
    end

    if ep then self:_Evaluate(ep, now, false) end
end

-- ─────────────────────────────────────────────────────────────────────────
-- EVALUACIÓN
-- ─────────────────────────────────────────────────────────────────────────

function RouteAlignment:_Evaluate(ep, now, forzar)
    local sc, tracker = Scorer(), EET()
    if not (sc and tracker) then return end
    if not forzar and self._lastEvalMs
       and (now - self._lastEvalMs) < P.EVAL_INTERVAL_MS then
        return
    end
    local dt = self._lastEvalMs and (now - self._lastEvalMs) or 0
    self._lastEvalMs = now

    local obsv = tracker:Observation(ep)
    if not obsv then return end
    local route, pull, total = rutaYPull()
    local anchor = math.max(tonumber(pull) or 1, tonumber(self._inferredPull) or 1)
    if total and anchor > total then anchor = total end

    local h = sc:Evaluate(obsv, route, anchor, {
        persistLabel = self._persistLabel,
        persistMs    = self._persistMs,
    })
    h.anchorPull = anchor
    h.routeProgressPull = pull
    count("alignmentEvaluations")
    self:_CountStates(h)
    self:_CountIdentity(obsv)

    -- Persistencia: cuenta el tiempo que la MISMA etiqueta lleva ganando.
    if h.label and h.label == self._persistLabel then
        self._persistMs = self._persistMs + dt
    else
        self._persistLabel, self._persistMs = h.label, 0
    end

    local anterior = self._hypothesis
    self._hypothesis = h
    self._hypothesis.episodeID = ep.episodeID
    self._hypothesis.observation = obsv

    -- Solo se escribe cuando cambia algo que importe. Un episodio largo no
    -- puede escribir una línea por segundo: llenaría el buffer y taparía el
    -- resto de la telemetría.
    local firma = (h.state or "-") .. "/" .. (h.label or "-")
    if firma ~= self._lastLogged and self._loggedThisEp < P.MAX_LOGGED_PER_EP then
        self._lastLogged = firma
        self._loggedThisEp = self._loggedThisEp + 1
        self:_LogAlignment(ep, obsv, h)
    elseif firma ~= self._lastLogged then
        count("alignmentLogSuppressed")
        self._lastLogged = firma
    end
    return h, anterior
end

-- El jugador manda: si el número de verdad se ha movido, el ancla se pone
-- donde él lo ha puesto y se olvida de lo que creía.
function RouteAlignment:_SyncAnchor()
    local _, pull = rutaYPull()
    if pull ~= self._lastRpPull then
        self._lastRpPull   = pull
        self._inferredPull = pull
        self._blindStreak  = 0
    end
end

-- Mueve SOLO la creencia propia. Ni una linea toca la ruta de verdad.
function RouteAlignment:_AdvanceAnchor(h)
    local S = Scorer().STATES
    local _, pull, total = rutaYPull()
    if not h or h.state == S.NO_EVIDENCE or h.state == S.WEAK then
        self._blindStreak = self._blindStreak + 1
        if self._blindStreak >= P.RESYNC_AFTER_BLIND then
            self._inferredPull = pull
            self._blindStreak = 0
            count("alignmentAnchorResyncs")
        end
        return
    end
    if h.state == S.AMBIGUOUS then return end   -- con dudas no se avanza

    local ultimo = h.candidatePulls and h.candidatePulls[#h.candidatePulls]
    if not ultimo then return end
    local siguiente = ultimo + 1
    if total and siguiente > total then siguiente = total end
    if siguiente ~= self._inferredPull then
        self._inferredPull = siguiente
        count("alignmentAnchorAdvances")
    end
    self._blindStreak = 0
end

function RouteAlignment:_CountStates(h)
    local S = Scorer().STATES
    if h.state == S.STRONG then count("alignmentStrong")
    elseif h.state == S.PROBABLE then count("alignmentProbable")
    elseif h.state == S.AMBIGUOUS then count("alignmentAmbiguous")
    elseif h.state == S.WEAK then count("alignmentWeak")
    else count("alignmentNoEvidence") end
    if h.isChain then count("alignmentChains") end
end

-- Los tres contadores que responden la pregunta abierta de la fase: ¿existe
-- el npcID en una M+ real de 12.1? Se mide, no se supone.
function RouteAlignment:_CountIdentity(obsv)
    local t = TEL()
    if not (t and t.IsRecording and t:IsRecording()) then return end
    pcall(t.Max, t, "npcIDAvailablePeak", obsv.identifiedUnits or 0)
    pcall(t.Max, t, "npcIDSecretPeak", obsv.secretUnits or 0)
    pcall(t.Max, t, "npcIDUnavailablePeak", obsv.unavailableUnits or 0)
end

function RouteAlignment:_LogAlignment(ep, obsv, h)
    log("OBSERVATION", {
        "episode", ep.episodeID,
        "visible", obsv.visibleCount, "engaged", obsv.engagedCount,
        "peak", obsv.peakEngaged,
        "identified", obsv.identifiedUnits, "secret", obsv.secretUnits,
        "unavailable", obsv.unavailableUnits,
        "linked", obsv.linkedUnits,
        "casting", obsv.castingUnits, "recentEvents", obsv.recentEventUnits,
    })
    local n = 0
    for _, c in ipairs(h.candidates or {}) do
        n = n + 1
        if n > P.MAX_CANDIDATE_LINES then break end
        log("PULL_CANDIDATE", {
            "episode", ep.episodeID, "candidate", c.label,
            "candidateScore", c.candidateScore, "expected", c.expected or "-",
            "observed", c.observed,
            "npc", c.components.npcComposition,
            "multiplicity", c.components.multiplicity,
            "size", c.components.sizeSimilarity,
            "seq", c.components.sequencePrior,
            "boss", c.components.bossAnchor,
        })
    end
    log("ALIGNMENT", {
        "episode", ep.episodeID, "state", h.state,
        "candidate", h.label or "-", "candidateScore", h.candidateScore,
        "runnerUp", h.runnerUpLabel or "-", "candidateMargin", h.candidateMargin,
        "episodeConfidence", h.episodeConfidence,
        "confidenceState", h.confidenceState,
        "routePull", h.routeProgressPull or "-", "anchor", h.anchorPull or "-",
        "npcCoverage", h.npcCoverage or 0,
        "reasons", table.concat(h.reasons or {}, ","),
    })
end

-- ─────────────────────────────────────────────────────────────────────────
-- CORTES DUROS
-- ─────────────────────────────────────────────────────────────────────────

function RouteAlignment:Reset(nowSeconds)
    local tracker = EET()
    local now = nowSeconds and (tonumber(nowSeconds) or 0) * 1000 or nil
    if tracker then pcall(tracker.Reset, tracker, now, false) end
    self._hypothesis, self._persistLabel, self._persistMs = nil, nil, 0
    self._lastEvalMs, self._loggedThisEp, self._lastLogged = nil, 0, nil
    self._inferredPull, self._lastRpPull, self._blindStreak = nil, nil, 0
    self._history = {}
    local eventEvidence = AR.EventCastEvidence
    if eventEvidence and type(eventEvidence.Clear) == "function" then
        pcall(eventEvidence.Clear, eventEvidence)
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- DIAGNÓSTICO  (/emp align)
-- ─────────────────────────────────────────────────────────────────────────

local function num(x, d)
    if type(x) ~= "number" then return "-" end
    return string.format("%." .. (d or 2) .. "f", x)
end

function RouteAlignment:StatusLines()
    local route, pull = rutaYPull()
    local tracker = EET()
    local L = {
        "|cFFe8b84a--- Route alignment (diagnóstico) ---|r",
        "|cFF888888Una hipótesis NO mueve el pull ni pinta flechas.|r",
        "inference=" .. (self._enabled and "ON" or "OFF") ..
            "  observación=" .. ((AR.ArrowDemo and AR.ArrowDemo:IsEnabled())
                                 and "ArrowDemo ON" or "ArrowDemo OFF"),
        "route=" .. tostring(route and route.id or "-") ..
            "  routeCurrentPull=" .. tostring(pull or "-") ..
            "  anchorPull=" .. tostring(self._inferredPull or pull or "-") ..
            " |cFF888888(creencia propia, no mueve la ruta)|r",
    }
    if tracker then
        local ep = tracker:Current()
        L[#L + 1] = "physicalEpisode=" .. (ep and tostring(ep.episodeID) or "ninguno") ..
            "  trackerState=" .. tracker:GetState()
    end

    local h = self._hypothesis
    if not h then
        L[#L + 1] = "alignmentState=NO_EVIDENCE (sin hipótesis todavía)"
        return L
    end
    L[#L + 1] = "alignmentState=" .. h.state ..
        "  bestCandidate=" .. tostring(h.label or "-") ..
        "  candidateScore=" .. num(h.candidateScore)
    L[#L + 1] = "runnerUp=" .. tostring(h.runnerUpLabel or "-") ..
        "  candidateMargin=" .. num(h.candidateMargin) ..
        "  chain=" .. tostring(h.isChain == true)
    local o = h.observation
    if o then
        L[#L + 1] = string.format(
            "evidence: engaged=%d peak=%d identified=%d secret=%d unavailable=%d coverage=%s",
            o.engagedCount, o.peakEngaged, o.identifiedUnits, o.secretUnits,
            o.unavailableUnits, num(o.npcCoverage))
    end
    L[#L + 1] = "episodeConfidence=" .. num(h.episodeConfidence) ..
        " confidenceState=" .. tostring(h.confidenceState or "WEAK")
    L[#L + 1] = "reasons=" .. table.concat(h.reasons or {}, ",")
    return L
end

function RouteAlignment:CandidateLines()
    local h = self._hypothesis
    if not h or type(h.candidates) ~= "table" or #h.candidates == 0 then
        return { "|cFFff9922No hay candidatos evaluados ahora mismo.|r" }
    end
    local L = { "|cFFe8b84a--- Candidatos evaluados ---|r",
                "pull candidateScore npc mult size seq boss expected" }
    for _, c in ipairs(h.candidates) do
        local k = c.components
        L[#L + 1] = string.format("%-5s %s %s %s %s %s %s %s",
            c.label, num(c.candidateScore), num(k.npcComposition),
            num(k.multiplicity), num(k.sizeSimilarity), num(k.sequencePrior),
            num(k.bossAnchor), tostring(c.expected or "-"))
    end
    L[#L + 1] = "observado=" .. tostring(h.candidates[1].observed) ..
        "  componentesUsados=" .. tostring(h.candidates[1].componentsUsed)
    return L
end

-- Vista auditable de la hipótesis. Cada señal muestra valor y peso por
-- separado; `eventEngagement` es el único dato derivado de EventCastEvidence
-- y por contrato solo representa actividad temporal reciente.
function RouteAlignment:DetailLines()
    local h = self._hypothesis
    local L = {
        "|cFFe8b84a--- alignmentdetail (SOLO DIAGNOSTICO) ---|r",
        "authority=NONE  progressWrites=0  matchAuthority=NONE  arrowWrites=0",
        "eventCastRole=TEMPORAL_ENGAGEMENT_ONLY  eventIdentity=DISABLED",
    }
    if not h then
        L[#L + 1] = "bestCandidate=-  runnerUp=-  candidateMargin=0.00"
        L[#L + 1] = "episodeConfidence=0.00 confidenceState=WEAK reasons=NO_EVIDENCE"
        L[#L + 1] = "reasons=NO_EVIDENCE"
        return L
    end

    L[#L + 1] = "bestCandidate=" .. tostring(h.label or "-") ..
        " candidateScore=" .. num(h.candidateScore) ..
        "  runnerUp=" .. tostring(h.runnerUpLabel or "-") ..
        " runnerUpScore=" .. num(h.runnerUpScore) ..
        "  candidateMargin=" .. num(h.candidateMargin)

    local o = h.observation or {}
    L[#L + 1] = string.format(
        "observed: engaged=%d peak=%d casting=%d recentEvent=%d linked=%d",
        tonumber(o.engagedCount) or 0, tonumber(o.peakEngaged) or 0,
        tonumber(o.castingUnits) or 0, tonumber(o.recentEventUnits) or 0,
        tonumber(o.linkedUnits) or 0)

    local config = Scorer().CONFIG
    local weights = config.weights
    local function candidateSignal(name, value, contribution, role)
        L[#L + 1] = string.format(
            "candidate.%s value=%s weight=%s contribution=%s role=%s",
            name, num(value), num(weights[name] or 0), num(contribution), role)
    end
    local k = h.components or {}
    local contributions = h.contributions or {}
    candidateSignal("size", k.sizeSimilarity, contributions.sizeSimilarity,
        "CANDIDATE_EVIDENCE")
    candidateSignal("sequence", k.sequencePrior, contributions.sequencePrior,
        "BOUNDED_PRIOR")
    candidateSignal("npcComposition", k.npcComposition,
        contributions.npcComposition, "CANDIDATE_EVIDENCE")
    candidateSignal("multiplicity", k.multiplicity,
        contributions.multiplicity, "CANDIDATE_EVIDENCE")
    candidateSignal("bossAnchor", k.bossAnchor,
        contributions.bossAnchor, "CANDIDATE_EVIDENCE")
    L[#L + 1] = "stability.persistence value=" .. num(k.temporalPersistence) ..
        " thresholdMs=" .. tostring(config.minPersistenceMs) ..
        " contribution=0.00 role=STATE_GATE_ONLY"
    L[#L + 1] = "reasons=" .. table.concat(h.reasons or {}, ",")

    L[#L + 1] = "episodeConfidence=" .. num(h.episodeConfidence) ..
        " confidenceState=" .. tostring(h.confidenceState or "WEAK") ..
        " reasons=" .. table.concat(h.confidenceReasons or {}, ",")
    local confidenceWeights = config.confidenceWeights or {}
    local confidenceSignals = h.confidenceSignals or {}
    local confidenceContributions = h.confidenceContributions or {}
    local function episodeSignal(label, key, role)
        L[#L + 1] = string.format(
            "episode.%s value=%s weight=%s contribution=%s role=%s",
            label, num(confidenceSignals[key]), num(confidenceWeights[key] or 0),
            num(confidenceContributions[key]), role)
    end
    episodeSignal("engagement", "engagementConsistency", "EPISODE_QUALITY_ONLY")
    episodeSignal("recentCast", "castActivity", "EPISODE_QUALITY_ONLY")
    episodeSignal("recentEvent", "eventEngagement", "TEMPORAL_ACTIVITY_ONLY")
    episodeSignal("tokenLink", "tokenLinkage", "EPISODE_QUALITY_ONLY")

    for i, c in ipairs(h.candidates or {}) do
        if i > P.MAX_CANDIDATE_LINES then break end
        local ck = c.components or {}
        local cc = c.contributions or {}
        L[#L + 1] = string.format("candidate.%d=%s candidateScore=%s",
            i, tostring(c.label or "-"), num(c.candidateScore))
        local function candidatePart(label, key)
            L[#L + 1] = string.format(
                "  candidate.%d.%s value=%s weight=%s contribution=%s",
                i, label, num(ck[key]), num(weights[key] or 0), num(cc[key]))
        end
        candidatePart("size", "sizeSimilarity")
        candidatePart("sequence", "sequencePrior")
        candidatePart("npcComposition", "npcComposition")
        candidatePart("multiplicity", "multiplicity")
        candidatePart("bossAnchor", "bossAnchor")
    end
    return L
end

function RouteAlignment:HistoryLines()
    if #self._history == 0 then
        return { "|cFFff9922Todavía no ha terminado ningún episodio.|r" }
    end
    local L = { "|cFFe8b84a--- Episodios cerrados ---|r" }
    for _, e in ipairs(self._history) do
        L[#L + 1] = string.format(
            "Episode %d  currentRoutePull=%s  anchor=%s  best=%s  state=%s  candidateScore=%s  runnerUp=%s confidence=%s/%s",
            e.episodeID, tostring(e.routePull or "-"), tostring(e.anchor or "-"),
            tostring(e.label or "-"), e.state, num(e.candidateScore),
            tostring(e.runnerUpLabel or "-"), num(e.episodeConfidence),
            tostring(e.confidenceState or "WEAK"))
    end
    return L
end

-- ─────────────────────────────────────────────────────────────────────────
-- CABLEADO
--
-- Solo escucha. No emite nada al bus, no registra eventos del cliente y no
-- tiene frame propio: todo lo que necesita se lo trae ArrowDemo.
-- ─────────────────────────────────────────────────────────────────────────

local NG = AR.NameplateGenerations
if NG and NG.Subscribe then
    NG:Subscribe(function(kind, _, _, prevGen)
        if kind ~= "REMOVED" and kind ~= "REPLACED" then return end
        local tracker = EET()
        if tracker then pcall(tracker.OnGenerationRemoved, tracker, prevGen) end
    end)
end

if MitzuMPlus.EventBus then
    local function cortar()
        pcall(function() RouteAlignment:Reset(nil) end)
    end
    MitzuMPlus.EventBus:On("MITZU_KEY_STARTED", cortar, 25)
    MitzuMPlus.EventBus:On("MITZU_KEY_COMPLETED", cortar, 25)
    MitzuMPlus.EventBus:On("MITZU_KEY_RESET", cortar, 25)
end

return RouteAlignment
