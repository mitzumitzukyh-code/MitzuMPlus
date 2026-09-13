-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · RoutePullCandidateScorer (FASE 4)
--
-- EL NÚCLEO DE LA FASE. Función PURA: recibe una observación física y una
-- ruta, y devuelve una hipótesis puntuada sobre en qué punto de la ruta
-- estamos. No lee el cliente, no toca RouteProgress, no pinta nada, no
-- guarda estado. Se le puede llamar mil veces con los mismos datos y
-- devuelve exactamente lo mismo.
--
-- LO QUE ESTO NO HACE, Y NO DEBE HACER NUNCA
--   · No identifica mobs. Ni uno. Un episodio que encaja con el pull 4 no
--     dice que la placa 3 sea el clon 2 del enemigo 11.
--   · No produce MATCH. La palabra MATCH tiene semántica de identidad en
--     Mitzu y aquí no se usa; los estados son otros a propósito.
--   · No mueve el pull. Esta fase es observación e inferencia, no actuación.
--
-- POR QUÉ LOS COMPONENTES NO DISPONIBLES NO VALEN 0
-- Si el npcID llega secreto, la composición no es "mala": es DESCONOCIDA.
-- Puntuarla 0 hundiría cualquier hipótesis correcta hasta el suelo y todo
-- saldría WEAK para siempre. El total es la media ponderada de los
-- componentes DISPONIBLES, y la falta de identidad se paga donde toca: en
-- la puerta que permite llegar a STRONG, no en el número.
--
-- TODOS LOS UMBRALES VIVEN AQUÍ. Ninguno repartido por otros ficheros.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local Scorer = {}
AR.RoutePullCandidateScorer = Scorer

-- ─────────────────────────────────────────────────────────────────────────
-- ESTADOS DE SALIDA
--
-- De menos a más. Ninguno de ellos, ni STRONG, autoriza a tocar la ruta en
-- esta fase: STRONG significa "lo apuntaría en un papel", no "actúa".
-- ─────────────────────────────────────────────────────────────────────────

Scorer.STATES = {
    NO_EVIDENCE = "NO_EVIDENCE",
    WEAK        = "WEAK",
    AMBIGUOUS   = "AMBIGUOUS",
    PROBABLE    = "PROBABLE",
    STRONG      = "STRONG",
}
Scorer.STATE_ORDER = { "NO_EVIDENCE", "WEAK", "AMBIGUOUS", "PROBABLE", "STRONG" }

-- Vocabulario cerrado de motivos. Si aparece otro, es un bug.
local REASON_LIST = {
    "EXACT_NPC_COMPOSITION", "PARTIAL_NPC_COMPOSITION", "NO_NPC_IDENTITY",
    "MULTIPLICITY_MISMATCH", "SIZE_EXACT", "SIZE_NEAR", "SIZE_MISMATCH",
    "SEQUENCE_CURRENT", "SEQUENCE_AHEAD", "SEQUENCE_BEHIND",
    "CHAIN_HYPOTHESIS", "PERSISTED", "NOT_PERSISTED", "TIE_WITH_RUNNER_UP",
    "ENCOUNTER_ACTIVE", "ENCOUNTER_ABSENT", "NO_IDENTITY_COVERAGE",
    "LOW_SCORE", "NO_ROUTE", "NO_ENGAGEMENT", "NO_CANDIDATES",
    "OVERFLOW", "POSSIBLE_WIPE_REPEAT", "SIZE_NOT_UNIQUE",
    "CAST_ACTIVITY", "NO_CAST_ACTIVITY", "RECENT_EVENT_ENGAGEMENT",
    "NO_RECENT_EVENT", "TOKEN_LINKED", "NO_TOKEN_LINK",
    "CONFIDENCE_WEAK", "CONFIDENCE_MEDIUM", "CONFIDENCE_STRONG",
}
Scorer.REASONS = {}
for _, r in ipairs(REASON_LIST) do Scorer.REASONS[r] = r end
local R = Scorer.REASONS

-- ═════════════════════════════════════════════════════════════════════════
-- AlignmentConfig — TODOS LOS NÚMEROS MÁGICOS, EN UN SITIO
--
-- Valores iniciales razonados, no medidos: la fase LIVE existe justamente
-- para medirlos. Se pueden tocar sin abrir ningún otro fichero.
-- ═════════════════════════════════════════════════════════════════════════

Scorer.CONFIG = {
    -- Solo estas señales pueden cambiar el ranking de candidatos. Las cuatro
    -- primeras forman la media; sequencePrior aplica después una penalización
    -- máxima acotada, para desempatar sin imponerse a la evidencia física.
    weights = {
        npcComposition        = 0.34,  -- qué mobs, la señal fuerte si existe
        multiplicity          = 0.14,  -- cuántos de cada uno
        sizeSimilarity        = 0.18,  -- cuántos en total
        bossAnchor            = 0.04,  -- ENCOUNTER frente a pull sin tropas
        sequencePrior         = 0.15,  -- penalización máxima, no peso aditivo
    },

    -- Calidad global del episodio. Son valores iguales para todos los
    -- candidatos y por contrato nunca entran en candidateScore ni su margen.
    confidenceWeights = {
        engagementConsistency = 0.40,
        castActivity          = 0.20,
        eventEngagement       = 0.20,
        tokenLinkage          = 0.20,
    },
    confidenceMediumThreshold = 0.35,
    confidenceStrongThreshold = 0.70,

    -- ═════════════════════════════════════════════════════════════════════
    -- SECUENCIA ES UNA PENALIZACION ACOTADA, NO UN SUMANDO
    --
    -- BUG ENCONTRADO AL SIMULAR LA RUTA REAL: con los dos como componentes
    -- sumados, un episodio de 12 enganchados estando de verdad en el pull 2
    -- (que espera 12) salía como "pull 1, PROBABLE, margen 0.21" — una
    -- respuesta equivocada y convencida. La causa: sin npcID legible los
    -- pesos se renormalizan sobre lo poco que queda, y la prioridad de
    -- secuencia pasaba a valer casi un tercio del total. El orden de la ruta
    -- terminaba pesando más que lo que se estaba viendo.
    --
    -- Una prioridad es eso: una prioridad. Sirve para DESEMPATAR, no para
    -- fabricar una diferencia. Aplicadas como factor, mueven el resultado
    -- como mucho un 15%, así que entre dos candidatos con evidencia
    -- parecida el margen se queda por debajo del umbral y sale AMBIGUOUS,
    -- que es la respuesta correcta cuando no se puede distinguir.
    -- ═════════════════════════════════════════════════════════════════════

    -- Prioridad por distancia al pull actual. N y N+1 por delante de N+7.
    sequencePrior = { [0] = 1.00, [1] = 0.85, [2] = 0.62, [-1] = 0.50 },
    -- Una cadena es una hipótesis más cara: se le cobra en la prioridad.
    chainPenalty = 0.90,
    -- Suelo del multiplicador: cuánto puede mover la secuencia.
    sequenceFloor    = 0.85,

    strongThreshold      = 0.80,
    probableThreshold    = 0.60,
    weakThreshold        = 0.32,
    ambiguousMargin      = 0.12,
    minPersistenceMs     = 2000,
    -- Para decir STRONG hace falta identidad de verdad, o un tamaño exacto
    -- que además NINGÚN otro candidato comparta.
    minCoverageForStrong = 0.60,
    -- Solo se plantea una cadena si se ha visto bastante más de lo que un
    -- pull suelto espera. Sin esto, cada episodio generaría cadenas gratis.
    chainMinExcess       = 1.25,
    maxCandidates        = 8,
    -- Diferencia de tamaño a partir de la cual ya no es "casi".
    sizeNearTolerance    = 0.15,
}

local C = Scorer.CONFIG

-- ─────────────────────────────────────────────────────────────────────────
-- UTILIDADES PURAS
-- ─────────────────────────────────────────────────────────────────────────

local function limitar(x)
    if type(x) ~= "number" or x ~= x then return 0 end
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

local function sumaMultiset(t)
    local n = 0
    if type(t) == "table" then for _, v in pairs(t) do n = n + (tonumber(v) or 0) end end
    return n
end

-- ─────────────────────────────────────────────────────────────────────────
-- A · COMPOSICIÓN NPC
--
-- Cuánto de lo identificado encaja con lo esperado. El denominador se ajusta
-- a la COBERTURA: si solo se pudo identificar el 15% de lo que peleó, se
-- compara contra el 15% de lo esperado, no contra el pull entero. Así una
-- cobertura baja baja la confianza (y lo hace en la puerta de STRONG) sin
-- convertir un acierto parcial en un suspenso.
-- ─────────────────────────────────────────────────────────────────────────

local function composicion(obs, sig)
    local esperado = sig.npcMultiset
    local visto    = obs.npcMultiset
    local sumaVisto = sumaMultiset(visto)
    local sumaEsperado = sumaMultiset(esperado)
    if sumaVisto <= 0 or sumaEsperado <= 0 then return nil end

    local encajan = 0
    for npcID, n in pairs(visto) do
        local e = tonumber(esperado[npcID]) or 0
        encajan = encajan + math.min(tonumber(n) or 0, e)
    end

    local cobertura = tonumber(obs.npcCoverage) or 0
    if cobertura <= 0 then cobertura = 1 end
    local denominador = math.max(sumaVisto, sumaEsperado * cobertura)
    if denominador <= 0 then return nil end
    return limitar(encajan / denominador)
end

-- ─────────────────────────────────────────────────────────────────────────
-- A2 · MULTIPLICIDAD
--
-- "A x3, B x1" no es "A x1, B x3". Se mide SOLO sobre los npcIDs presentes
-- en los dos lados: los que sobran o faltan ya los castiga la composición, y
-- contarlos dos veces sería castigo doble.
-- ─────────────────────────────────────────────────────────────────────────

local function multiplicidad(obs, sig)
    local esperado, visto = sig.npcMultiset, obs.npcMultiset
    local diff, techo, compartidos = 0, 0, 0
    for npcID, n in pairs(visto) do
        local e = tonumber(esperado[npcID])
        if e and e > 0 then
            local v = tonumber(n) or 0
            compartidos = compartidos + 1
            diff  = diff + math.abs(v - e)
            techo = techo + math.max(v, e)
        end
    end
    if compartidos == 0 or techo <= 0 then return nil end
    return limitar(1 - (diff / techo))
end

-- ─────────────────────────────────────────────────────────────────────────
-- B · TAMAÑO
--
-- Evidencia débil por diseño: "hemos matado 7 y el pull espera 7" no dice
-- que fueran ESOS 7. Pesa poco y nunca abre STRONG por sí sola.
-- ─────────────────────────────────────────────────────────────────────────

local function tamano(obs, sig)
    local o = tonumber(obs.engagedCount) or 0
    local e = tonumber(sig.mobCount)
    if not e or e <= 0 or o <= 0 then return nil end
    return limitar(1 - (math.abs(o - e) / math.max(o, e)))
end

-- ─────────────────────────────────────────────────────────────────────────
-- C · SECUENCIA
-- ─────────────────────────────────────────────────────────────────────────

local function secuencia(sig, pullActual)
    if not pullActual or type(sig.pulls) ~= "table" or #sig.pulls == 0 then return nil end
    local mejor = nil
    for _, p in ipairs(sig.pulls) do
        local prior = C.sequencePrior[p - pullActual]
        if prior and (not mejor or prior > mejor) then mejor = prior end
    end
    if not mejor then return nil end
    if #sig.pulls > 1 then mejor = mejor * C.chainPenalty end
    return limitar(mejor)
end

-- ─────────────────────────────────────────────────────────────────────────
-- G · ANCLA DE BOSS
--
-- Las rutas NO traen encounterID: se comprobó. Lo único que hay es que el
-- pull no aporte tropas (`count == 0`), que en las ocho rutas coincide con
-- los pulls de boss pero también con basura sin valor. Por eso pesa 0.04 y
-- solo se aplica cuando de verdad distingue.
-- ─────────────────────────────────────────────────────────────────────────

local function ancla(obs, sig)
    local encuentro = obs.encounterEverSeen == true
    local sinTropas = sig.noForces == true
    if not encuentro and not sinTropas then return nil end
    if encuentro and sinTropas then return 1 end
    if encuentro and not sinTropas then return 0 end
    return 0.15  -- pull sin tropas pero no hubo ENCOUNTER: improbable
end

-- ═════════════════════════════════════════════════════════════════════════
-- PUNTUACIÓN DE UN CANDIDATO
-- ═════════════════════════════════════════════════════════════════════════

-- Los que forman la media de evidencia.
local CANDIDATE_COMPONENTS = {
    "npcComposition", "multiplicity", "sizeSimilarity", "bossAnchor",
    "sequencePrior",
}
local ADDITIVE_CANDIDATE_COMPONENTS = {
    "npcComposition", "multiplicity", "sizeSimilarity", "bossAnchor",
}
local CONFIDENCE_COMPONENTS = {
    "engagementConsistency", "castActivity", "eventEngagement", "tokenLinkage",
}
Scorer.COMPONENTS = CANDIDATE_COMPONENTS
Scorer.EVIDENCE_COMPONENTS = ADDITIVE_CANDIDATE_COMPONENTS
Scorer.CONFIDENCE_COMPONENTS = CONFIDENCE_COMPONENTS

function Scorer:ScoreOne(obs, sig, ctx)
    ctx = ctx or {}
    local s = {
        label = AR.RouteSignature and AR.RouteSignature:Label(sig) or "-",
        pulls = sig.pulls,
        expected = sig.mobCount,
        observed = tonumber(obs.engagedCount) or 0,
        components = {}, contributions = {}, available = {},
        candidateScore = 0, componentsUsed = 0,
    }

    s.components.npcComposition        = composicion(obs, sig)
    s.components.multiplicity          = multiplicidad(obs, sig)
    s.components.sizeSimilarity        = tamano(obs, sig)
    s.components.sequencePrior         = secuencia(sig, ctx.currentPull)
    s.components.bossAnchor            = ancla(obs, sig)

    -- Persistencia: la aporta quien lleva la cuenta entre ticks, y solo
    -- cuenta si la hipótesis que persiste es ESTA.
    local persistMs = tonumber(ctx.persistMs) or 0
    if ctx.persistLabel ~= nil and ctx.persistLabel == s.label then
        s.components.temporalPersistence =
            limitar(persistMs / math.max(1, C.minPersistenceMs))
    else
        s.components.temporalPersistence = 0
    end

    local suma, pesos = 0, 0
    for _, nombre in ipairs(ADDITIVE_CANDIDATE_COMPONENTS) do
        local v = s.components[nombre]
        if v ~= nil then
            local w = C.weights[nombre] or 0
            suma = suma + (v * w)
            pesos = pesos + w
            s.available[nombre] = true
            s.componentsUsed = s.componentsUsed + 1
        end
    end
    s.evidence = (pesos > 0) and limitar(suma / pesos) or 0
    s.weightUsed = pesos
    for _, nombre in ipairs(ADDITIVE_CANDIDATE_COMPONENTS) do
        local v = s.components[nombre]
        if v ~= nil and pesos > 0 then
            s.contributions[nombre] = (v * (C.weights[nombre] or 0)) / pesos
        end
    end

    -- La secuencia solo puede mover un poco lo que la evidencia ya dice.
    local prior = s.components.sequencePrior
    if prior ~= nil then
        s.available.sequencePrior = true
        s.componentsUsed = s.componentsUsed + 1
    end
    s.sequenceFactor = (prior == nil) and 1
        or (C.sequenceFloor + (1 - C.sequenceFloor) * prior)
    s.candidateScore = limitar(s.evidence * s.sequenceFactor)
    s.contributions.sequencePrior = s.candidateScore - s.evidence
    s.sizeExact = (s.expected ~= nil and s.observed == s.expected)
    return s
end

-- Señales globales del episodio. Se calculan una vez, fuera de cada candidato,
-- para que sea estructuralmente imposible que alteren el ranking o el margen.
function Scorer:EpisodeConfidence(obs)
    local signals, contributions = {}, {}
    local suma, pesos = 0, 0
    for _, nombre in ipairs(CONFIDENCE_COMPONENTS) do
        local raw = type(obs) == "table" and obs[nombre] or nil
        if type(raw) == "number" then
            local v = limitar(raw)
            local w = C.confidenceWeights[nombre] or 0
            signals[nombre] = v
            contributions[nombre] = v * w
            suma = suma + contributions[nombre]
            pesos = pesos + w
        end
    end
    local value = (pesos > 0) and limitar(suma / pesos) or 0
    if pesos > 0 then
        for nombre, contribution in pairs(contributions) do
            contributions[nombre] = contribution / pesos
        end
    end
    local state
    if value >= C.confidenceStrongThreshold then state = "STRONG"
    elseif value >= C.confidenceMediumThreshold then state = "MEDIUM"
    else state = "WEAK" end
    return value, state, signals, contributions, pesos
end

-- ═════════════════════════════════════════════════════════════════════════
-- CANDIDATOS
--
-- N-1, N, N+1, N+2 y, solo con evidencia de exceso, las cadenas N+N+1 y
-- N+1+N+2. No se recorre la ruta entera: eso es un diagnóstico aparte, no
-- una hipótesis viva.
-- ═════════════════════════════════════════════════════════════════════════

function Scorer:Candidates(route, pullActual, obs)
    local RS = AR.RouteSignature
    local out = {}
    if not RS or type(route) ~= "table" then return out end
    local pulls = rawget(route, "pulls")
    if type(pulls) ~= "table" then return out end
    local total = #pulls
    local n = tonumber(pullActual)
    if not n then return out end

    local vistos = {}
    local function anadir(sig)
        if sig.state == RS.STATES.UNKNOWN or not sig.mobCount then return end
        local etiqueta = RS:Label(sig)
        if vistos[etiqueta] then return end
        vistos[etiqueta] = true
        out[#out + 1] = sig
    end

    local sueltos = {}
    for _, off in ipairs({ 0, 1, 2, -1 }) do
        local i = n + off
        if i >= 1 and i <= total then
            local sig = RS:ForPull(route, i)
            sueltos[i] = sig
            anadir(sig)
        end
    end

    -- Cadenas: solo si lo observado supera con holgura lo que el primero
    -- espera. Sin esta puerta se generarían cadenas en cada episodio y el
    -- empate estaría servido.
    local observadas = tonumber(obs and obs.engagedCount) or 0
    for _, base in ipairs({ n, n + 1 }) do
        local a, b = sueltos[base], sueltos[base + 1]
        if a and b and a.mobCount and observadas >= a.mobCount * C.chainMinExcess then
            anadir(RS:ForChain(route, { base, base + 1 }))
        end
    end

    while #out > C.maxCandidates do table.remove(out) end
    return out
end

-- ═════════════════════════════════════════════════════════════════════════
-- EVALUACIÓN COMPLETA
-- ═════════════════════════════════════════════════════════════════════════

local function claveOrden(s)
    local k = 0
    for _, p in ipairs(s.pulls or {}) do k = k + p end
    return k
end

local function vacio(razon, pullActual, obs)
    local confidence, confidenceState, confidenceSignals,
          confidenceContributions, confidenceWeightUsed = Scorer:EpisodeConfidence(obs)
    return {
        state = Scorer.STATES.NO_EVIDENCE, candidatePull = nil, label = nil,
        candidateScore = 0, runnerUpPull = nil, runnerUpLabel = nil,
        candidateMargin = 0,
        reasons = { razon }, candidates = {}, currentPull = pullActual,
        isChain = false, episodeConfidence = confidence,
        confidenceState = confidenceState,
        confidenceReasons = { R["CONFIDENCE_" .. confidenceState] },
        confidenceSignals = confidenceSignals,
        confidenceContributions = confidenceContributions,
        confidenceWeightUsed = confidenceWeightUsed,
    }
end

function Scorer:Evaluate(obs, route, pullActual, ctx)
    ctx = ctx or {}
    ctx.currentPull = tonumber(pullActual)

    if type(obs) ~= "table" then return vacio(R.NO_ENGAGEMENT, ctx.currentPull, obs) end
    if (tonumber(obs.engagedCount) or 0) <= 0 then
        return vacio(R.NO_ENGAGEMENT, ctx.currentPull, obs)
    end
    if type(route) ~= "table" or not ctx.currentPull then
        return vacio(R.NO_ROUTE, ctx.currentPull, obs)
    end

    local cands = self:Candidates(route, ctx.currentPull, obs)
    if #cands == 0 then return vacio(R.NO_CANDIDATES, ctx.currentPull, obs) end

    local puntuados = {}
    for _, sig in ipairs(cands) do
        puntuados[#puntuados + 1] = self:ScoreOne(obs, sig, ctx)
    end
    -- Orden determinista: por total, y a igualdad por la suma de índices de
    -- pull. Dos ejecuciones con los mismos datos dan el mismo ganador.
    table.sort(puntuados, function(a, b)
        if a.candidateScore ~= b.candidateScore then
            return a.candidateScore > b.candidateScore
        end
        return claveOrden(a) < claveOrden(b)
    end)

    local mejor = puntuados[1]
    local segundo = puntuados[2]
    local margen = segundo and
        (mejor.candidateScore - segundo.candidateScore) or mejor.candidateScore

    -- ── Tamaño único: ¿hay otro candidato que espere exactamente lo mismo?
    local tamanoUnico = true
    for i = 2, #puntuados do
        if puntuados[i].expected == mejor.expected then tamanoUnico = false; break end
    end

    local razones = {}
    local function razon(r) razones[#razones + 1] = r end

    -- Identidad
    local comp = mejor.components.npcComposition
    if comp == nil then razon(R.NO_NPC_IDENTITY)
    elseif comp >= 0.999 then razon(R.EXACT_NPC_COMPOSITION)
    else razon(R.PARTIAL_NPC_COMPOSITION) end
    local mult = mejor.components.multiplicity
    if mult ~= nil and mult < 0.999 then razon(R.MULTIPLICITY_MISMATCH) end

    -- Tamaño
    if mejor.sizeExact then razon(R.SIZE_EXACT)
    elseif mejor.components.sizeSimilarity
       and mejor.components.sizeSimilarity >= (1 - C.sizeNearTolerance) then
        razon(R.SIZE_NEAR)
    else razon(R.SIZE_MISMATCH) end
    if mejor.sizeExact and not tamanoUnico then razon(R.SIZE_NOT_UNIQUE) end

    -- Secuencia
    local primero = mejor.pulls and mejor.pulls[1]
    if primero == ctx.currentPull then razon(R.SEQUENCE_CURRENT)
    elseif primero and primero > ctx.currentPull then razon(R.SEQUENCE_AHEAD)
    elseif primero then razon(R.SEQUENCE_BEHIND) end
    local esCadena = (mejor.pulls and #mejor.pulls > 1) or false
    if esCadena then razon(R.CHAIN_HYPOTHESIS) end

    -- Contexto
    if obs.encounterEverSeen then razon(R.ENCOUNTER_ACTIVE) else razon(R.ENCOUNTER_ABSENT) end
    if (tonumber(obs.castActivity) or 0) > 0 then
        razon(R.CAST_ACTIVITY)
    else
        razon(R.NO_CAST_ACTIVITY)
    end
    if (tonumber(obs.eventEngagement) or 0) > 0 then
        razon(R.RECENT_EVENT_ENGAGEMENT)
    else
        razon(R.NO_RECENT_EVENT)
    end
    if (tonumber(obs.tokenLinkage) or 0) > 0 then
        razon(R.TOKEN_LINKED)
    else
        razon(R.NO_TOKEN_LINK)
    end
    if obs.overflow then razon(R.OVERFLOW) end
    if (tonumber(obs.repeatedGenerations) or 0) > 0 then razon(R.POSSIBLE_WIPE_REPEAT) end

    local persistido = (mejor.components.temporalPersistence or 0) >= 1
    razon(persistido and R.PERSISTED or R.NOT_PERSISTED)

    -- ── ESTADO
    local cobertura = tonumber(obs.npcCoverage) or 0
    local puertaFuerte = (cobertura >= C.minCoverageForStrong)
                         or (mejor.sizeExact and tamanoUnico)

    local estado
    if mejor.candidateScore < C.weakThreshold then
        estado = self.STATES.NO_EVIDENCE
        razon(R.LOW_SCORE)
    elseif mejor.candidateScore < C.probableThreshold then
        estado = self.STATES.WEAK
    elseif segundo and margen < C.ambiguousMargin then
        estado = self.STATES.AMBIGUOUS
        razon(R.TIE_WITH_RUNNER_UP)
    elseif mejor.candidateScore >= C.strongThreshold and persistido and puertaFuerte then
        estado = self.STATES.STRONG
    else
        estado = self.STATES.PROBABLE
        if mejor.candidateScore >= C.strongThreshold and not puertaFuerte then
            razon(R.NO_IDENTITY_COVERAGE)
        end
    end

    local episodeConfidence, confidenceState, confidenceSignals,
          confidenceContributions, confidenceWeightUsed = self:EpisodeConfidence(obs)
    local confidenceReason = R["CONFIDENCE_" .. confidenceState]

    return {
        state         = estado,
        candidatePull = primero,
        candidatePulls = mejor.pulls,
        label         = mejor.label,
        isChain       = esCadena,
        candidateScore = mejor.candidateScore,
        runnerUpPull  = segundo and segundo.pulls and segundo.pulls[1] or nil,
        runnerUpLabel = segundo and segundo.label or nil,
        runnerUpScore = segundo and segundo.candidateScore or nil,
        candidateMargin = margen,
        npcCoverage   = cobertura,
        sizeExact     = mejor.sizeExact,
        sizeUnique    = tamanoUnico,
        components    = mejor.components,
        contributions = mejor.contributions,
        episodeConfidence = episodeConfidence,
        confidenceState = confidenceState,
        confidenceReasons = { confidenceReason },
        confidenceSignals = confidenceSignals,
        confidenceContributions = confidenceContributions,
        confidenceWeightUsed = confidenceWeightUsed,
        reasons       = razones,
        candidates    = puntuados,
        currentPull   = ctx.currentPull,
    }
end

return Scorer
