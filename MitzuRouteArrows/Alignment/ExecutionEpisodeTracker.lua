-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuRouteArrows · ExecutionEpisodeTracker (FASE 4)
--
-- QUÉ ES UN EPISODIO
-- Un tramo de tiempo durante el cual hubo combate observable. Empieza cuando
-- se pasa de 0 a más de 0 placas ENGAGED y se da por cerrado tras unos
-- segundos de calma confirmada.
--
-- LO QUE UN EPISODIO NO ES
-- NO es un pull de la ruta. Nunca. En una M+ de verdad:
--   · se encadenan packs, y un episodio contiene dos pulls;
--   · un pull se hace en dos tandas, y hay dos episodios para un pull;
--   · entra una patrulla a mitad;
--   · hay wipe y los MISMOS mobs vuelven a aparecer enteros;
--   · el boss y sus adds son un episodio y media ruta;
--   · hay mobs que no dan tropas y no están en la ruta.
-- Por eso este módulo se llama "execution episode" y no "pull". Decir
-- EXECUTION_ENDED no es decir ROUTE_PULL_COMPLETED: son cosas distintas y
-- aquí solo se puede afirmar la primera.
--
-- QUÉ APORTA SOBRE LO QUE YA HABÍA
-- ArrowDemoTelemetry ya detectaba episodios, pero solo para ESCRIBIR líneas
-- de log: no deja un objeto que otro módulo pueda puntuar. Aquí el episodio
-- es un dato estructurado con sus miembros por generación. Las dos
-- detecciones conviven a propósito: tocar la de telemetría obligaría a
-- rehacer su banco de pruebas y esta fase no arregla nada roto allí.
--
-- IDENTIDAD
-- Por cada generación se intenta leer el npcID UNA sola vez, delegando en
-- LiveEnemyResolver:GetNPCID, que es el único sitio del addon que parte un
-- GUID. Si llega secreto o no llega: npcIDState y se acabó. Nunca se
-- convierte, ni se compara, ni se tostring-ea un valor que no se haya
-- demostrado público. Un episodio sin npcIDs es un episodio legítimo con
-- cobertura 0, no un error.
-- ═══════════════════════════════════════════════════════════════════════════

local MRA = _G.MitzuRouteArrows
if not MRA then return end

-- AR: los demas modulos de este mismo addon.
-- Host: fachada de SOLO LECTURA sobre MitzuMPlusAPI (Core/Host.lua).
local AR = MRA
local Host = MRA.Host

local EET = {}
AR.ExecutionEpisodeTracker = EET

EET.STATES = { IDLE = "IDLE", ACTIVE = "ACTIVE", QUIET_PENDING = "QUIET_PENDING" }

-- Estados de npcID de un miembro. Vocabulario cerrado.
EET.NPCID_STATES = {
    AVAILABLE   = "AVAILABLE",    -- número público leído del GUID
    SECRET      = "SECRET",       -- el cliente lo marca secreto
    UNAVAILABLE = "UNAVAILABLE",  -- no hay API, no hay unidad, o no es criatura
    UNKNOWN     = "UNKNOWN",      -- aún no se ha intentado
}

EET.PARAMS = {
    QUIET_CONFIRM_MS = 3000,  -- calma que hay que confirmar para cerrar
    MAX_MEMBERS      = 80,    -- tope por episodio; más que cualquier pull real
    MAX_HISTORY      = 12,    -- episodios cerrados que se conservan en memoria
    RETRY_NPCID_MS   = 1500,  -- reintento si la primera lectura no dio nada
}

local P = EET.PARAMS

-- ─────────────────────────────────────────────────────────────────────────
-- ESTADO
-- ─────────────────────────────────────────────────────────────────────────

EET._state    = "IDLE"
EET._episode  = nil
EET._history  = {}
EET._seq      = 0
EET._lastGens = {}   -- [gen] = true, del episodio cerrado anterior (wipes)

function EET:GetState()   return self._state end
function EET:Current()    return self._episode end
function EET:History()    return self._history end
function EET:LastClosed() return self._history[#self._history] end

-- ─────────────────────────────────────────────────────────────────────────
-- LECTURAS DEL ENTORNO
--
-- Todas opcionales y todas entre pcall: este módulo tiene que poder
-- ejecutarse en un banco de pruebas donde no exista ninguna de ellas.
-- ─────────────────────────────────────────────────────────────────────────

local function pullActual()
    local RP = Host.RouteProgress
    if not RP or type(RP.GetPullIndex) ~= "function" then return nil end
    local ok, n = pcall(RP.GetPullIndex, RP)
    return (ok and tonumber(n)) or nil
end

local function encuentroActivo()
    local T = AR.ArrowDemoTelemetry
    if not T or type(T.IsEncounterActive) ~= "function" then return false end
    local ok, v = pcall(T.IsEncounterActive, T)
    return (ok and v == true) or false
end

-- npcID de una placa. Delega en el único sitio que parte GUIDs.
local function leerNPCID(token)
    local LER = AR.LiveEnemyResolver
    if not LER or type(LER.GetNPCID) ~= "function" then
        return nil, EET.NPCID_STATES.UNAVAILABLE
    end
    local ok, id, estado = pcall(LER.GetNPCID, LER, token)
    if not ok then return nil, EET.NPCID_STATES.UNAVAILABLE end
    if estado == "SECRET" then return nil, EET.NPCID_STATES.SECRET end
    -- `id` ya ha pasado la puerta de seguridad del resolver: solo sale de
    -- allí si el GUID se demostró público. Aun así se comprueba el tipo.
    if type(id) == "number" and id > 0 and id == math.floor(id) then
        return id, EET.NPCID_STATES.AVAILABLE
    end
    return nil, EET.NPCID_STATES.UNAVAILABLE
end
EET._leerNPCID = leerNPCID

-- ─────────────────────────────────────────────────────────────────────────
-- MIEMBROS
--
-- La clave es la GENERACIÓN, no el token. nameplate3 gen 17 y nameplate3
-- gen 18 son dos ocupantes distintos y jamás se mezclan. Es la misma regla
-- que sostiene las flechas de la demo.
-- ─────────────────────────────────────────────────────────────────────────

local function nuevoMiembro(o, now)
    return {
        gen         = o.gen,
        token       = o.token,
        firstSeenMs = now,
        lastSeenMs  = now,
        firstEngagedMs = nil,
        lastEngagedMs  = nil,
        engagedTicks   = 0,
        everEngaged    = false,
        linkTicks      = 0,     -- veces vista como target/mouseover/softenemy
        castTicks      = 0,     -- CASTING/CHANNELING observados por sondeo
        eventTicks     = 0,     -- evento de cast reciente; solo actividad temporal
        castActive       = false,
        recentEventActive = false,
        tokenLinkedActive = false,
        everSawCast      = false, -- historial diagnóstico; nunca score/confidence
        everSawEvent     = false, -- historial diagnóstico; nunca score/confidence
        everSawTokenLink = false, -- historial diagnóstico; nunca score/confidence
        npcID          = nil,
        npcIDState     = EET.NPCID_STATES.UNKNOWN,
        npcIDTriedAt   = nil,
    }
end

-- Un intento de identificación por miembro, con UN reintento diferido. Si el
-- cliente dice SECRET no se reintenta: no va a dejar de serlo a mitad de
-- combate y repreguntar es gasto por nada.
function EET:_Identify(m, now)
    if m.npcIDState == self.NPCID_STATES.AVAILABLE then return end
    if m.npcIDState == self.NPCID_STATES.SECRET then return end
    if m.npcIDTriedAt and (now - m.npcIDTriedAt) < P.RETRY_NPCID_MS then return end
    if m.npcIDTriedAt and m.npcIDRetried then return end
    if m.npcIDTriedAt then m.npcIDRetried = true end
    m.npcIDTriedAt = now

    local id, estado = leerNPCID(m.token)
    m.npcID, m.npcIDState = id, estado
end

-- ─────────────────────────────────────────────────────────────────────────
-- CICLO DE VIDA DEL EPISODIO
-- ─────────────────────────────────────────────────────────────────────────

function EET:_Open(now)
    self._seq = self._seq + 1
    local ep = {
        episodeID   = self._seq,
        startedAt   = now,
        endedAt     = nil,
        members     = {},        -- [gen] = miembro
        memberCount = 0,
        order       = {},        -- generaciones en orden de primer enganche

        generationsSeen        = 0,
        generationsEngaged     = 0,
        peakSimultaneousEngaged = 0,
        joinedDuringExecution  = 0,
        removedDuringExecution = 0,

        encounterActive   = encuentroActivo(),
        encounterEverSeen = encuentroActivo(),
        routePullAtStart  = pullActual(),
        routePullAtEnd    = nil,

        repeatedGenerations = 0,  -- miembros que ya estaban en el episodio anterior
        overflow            = false,
        ticks               = 0,
    }
    self._episode = ep
    self._state   = "ACTIVE"
    self._quietSince = nil
    return ep
end

function EET:_Close(now)
    local ep = self._episode
    if not ep then return nil end
    ep.endedAt        = self._quietSince or now
    ep.routePullAtEnd = pullActual()
    ep.durationMs     = ep.endedAt - ep.startedAt

    self._lastGens = {}
    for gen in pairs(ep.members) do self._lastGens[gen] = true end

    self._history[#self._history + 1] = ep
    while #self._history > P.MAX_HISTORY do table.remove(self._history, 1) end

    self._episode   = nil
    self._state     = "IDLE"
    self._quietSince = nil
    return ep
end

-- Corte duro: fin de llave, cambio de zona, demo apagada. Lo que hubiera
-- abierto se cierra con lo que se supiera; no se descarta en silencio.
function EET:Reset(now, keepHistory)
    if self._episode then self:_Close(tonumber(now) or self._episode.startedAt) end
    self._state, self._quietSince = "IDLE", nil
    self._lastGens = {}
    if not keepHistory then self._history = {} end
end

-- ─────────────────────────────────────────────────────────────────────────
-- OBSERVACIÓN
--
-- `obs` es exactamente la lista que ArrowDemo construye en su tick:
--   { { token = "nameplate3", gen = 17, engagement = "ENGAGED",
--       tokenLink = "SOFTENEMY" | nil,
--       castState = "CASTING" | "CHANNELING" | "NOT_CASTING" | "UNKNOWN",
--       recentEvent = "RECENT_EVENT" | "NONE" }, ... }
-- Devuelve: evento ("STARTED" | "ENDED" | nil) y el episodio afectado.
-- ─────────────────────────────────────────────────────────────────────────

local ENGAGED = "ENGAGED"

-- La lista de observación la construye ArrowDemo, pero este módulo no da eso
-- por hecho: en los bancos de pruebas entran tablas con metatablas hostiles,
-- y leer con `t.k` dispararía su __index. `rawget` no llama a nada.
local function campo(t, k)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(rawget, t, k)
    if not ok then return nil end
    return v
end

function EET:Observe(obs, now)
    now = tonumber(now) or 0
    if type(obs) ~= "table" then return nil, self._episode end

    local enganchadas, dudosas = 0, 0
    for i = 1, #obs do
        local o = obs[i]
        if type(o) == "table" then
            local e = campo(o, "engagement")
            if e == ENGAGED then enganchadas = enganchadas + 1
            elseif e ~= "NOT_ENGAGED" then dudosas = dudosas + 1 end
        end
    end

    -- ── Apertura
    if not self._episode then
        if enganchadas == 0 then return nil, nil end
        local ep = self:_Open(now)
        self:_Absorber(ep, obs, now, true)
        ep.peakSimultaneousEngaged = enganchadas
        return "STARTED", ep
    end

    -- ── Episodio vivo
    local ep = self._episode
    ep.ticks = ep.ticks + 1
    ep.encounterActive = encuentroActivo()
    if ep.encounterActive then ep.encounterEverSeen = true end
    self:_Absorber(ep, obs, now, false)
    if enganchadas > ep.peakSimultaneousEngaged then
        ep.peakSimultaneousEngaged = enganchadas
    end

    -- ── Cierre: calma CONFIRMADA. Una duda no es calma: con UNKNOWN por
    -- medio no se puede afirmar que el combate haya terminado.
    if enganchadas == 0 and dudosas == 0 then
        if not self._quietSince then
            self._quietSince = now
            self._state = "QUIET_PENDING"
        elseif (now - self._quietSince) >= P.QUIET_CONFIRM_MS then
            return "ENDED", self:_Close(now)
        end
    elseif self._quietSince then
        self._quietSince = nil
        self._state = "ACTIVE"
    end

    return nil, ep
end

-- Mete en el episodio lo que se ve ahora mismo.
function EET:_Absorber(ep, obs, now, inicial)
    -- Estas tres señales describen el tick actual. Se limpian antes de
    -- absorber la foto nueva para que un cast, evento o enlace antiguo no se
    -- quede fijado durante todo el episodio. EventCastEvidence aplica su TTL
    -- de 5 s antes de producir RECENT_EVENT; aquí solo respetamos su salida.
    for _, m in pairs(ep.members) do
        m.castActive = false
        m.recentEventActive = false
        m.tokenLinkedActive = false
    end
    for i = 1, #obs do
        local o = obs[i]
        local gen = tonumber(campo(o, "gen"))
        local tok = campo(o, "token")
        local est = campo(o, "engagement")
        local apuntada = campo(o, "pointed")
        local enlace = campo(o, "tokenLink") or apuntada
        local castState = campo(o, "castState")
        local recentEvent = campo(o, "recentEvent")
        if gen and type(tok) == "string" then
            local m = ep.members[gen]
            if not m then
                if ep.memberCount >= P.MAX_MEMBERS then
                    ep.overflow = true
                else
                    m = nuevoMiembro({ gen = gen, token = tok }, now)
                    ep.members[gen] = m
                    ep.memberCount = ep.memberCount + 1
                    ep.generationsSeen = ep.generationsSeen + 1
                    if self._lastGens[gen] then
                        ep.repeatedGenerations = ep.repeatedGenerations + 1
                    end
                end
            end
            if m then
                m.lastSeenMs = now
                -- El token puede cambiar dentro de la misma generación? No:
                -- la generación ES el par (token, ocupante). Se conserva el
                -- primero y no se sobrescribe.
                if est == ENGAGED then
                    if not m.everEngaged then
                        m.everEngaged = true
                        m.firstEngagedMs = now
                        ep.generationsEngaged = ep.generationsEngaged + 1
                        ep.order[#ep.order + 1] = gen
                        if not inicial then
                            ep.joinedDuringExecution = ep.joinedDuringExecution + 1
                        end
                    end
                    m.lastEngagedMs = now
                    m.engagedTicks = m.engagedTicks + 1
                    -- La identidad solo se busca en lo que de verdad peleó.
                    self:_Identify(m, now)
                end
                if enlace then
                    m.linkTicks = m.linkTicks + 1
                    m.tokenLinkedActive = true
                    m.everSawTokenLink = true
                end
                if castState == "CASTING" or castState == "CHANNELING" then
                    m.castTicks = m.castTicks + 1
                    m.castActive = true
                    m.everSawCast = true
                end
                -- Nunca se copia el payload del evento. Esta señal solo dice
                -- que hubo actividad temporal reciente en ese token.
                if recentEvent == "RECENT_EVENT" then
                    m.eventTicks = m.eventTicks + 1
                    m.recentEventActive = true
                    m.everSawEvent = true
                end
            end
        end
    end
end

-- Aviso desde NameplateGenerations: una placa que estaba en el episodio se
-- fue. Se cuenta, no se borra: un mob muerto sigue siendo parte de lo que
-- ocurrió en ese episodio.
function EET:OnGenerationRemoved(gen)
    local ep = self._episode
    local g = tonumber(gen)
    if not ep or not g then return end
    local m = ep.members[g]
    if m and not m.removed then
        m.removed = true
        m.castActive = false
        m.recentEventActive = false
        m.tokenLinkedActive = false
        ep.removedDuringExecution = ep.removedDuringExecution + 1
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- OBSERVACIÓN FÍSICA  (PhysicalGroupObservation)
--
-- La foto de lo que se vio, SIN afirmar identidad de ruta. Es lo único que
-- el comparador recibe: no ve tokens, ni placas, ni el cliente.
-- ─────────────────────────────────────────────────────────────────────────

function EET:Observation(ep)
    ep = ep or self._episode
    if type(ep) ~= "table" then return nil end

    local obsv = {
        observationID = ep.episodeID,
        episodeID     = ep.episodeID,
        startedAt     = ep.startedAt,
        endedAt       = ep.endedAt,
        durationMs    = (ep.endedAt or ep.startedAt) - ep.startedAt,

        engagedCount   = ep.generationsEngaged,
        visibleCount   = ep.generationsSeen,
        peakEngaged    = ep.peakSimultaneousEngaged,
        joined         = ep.joinedDuringExecution,
        removed        = ep.removedDuringExecution,

        npcMultiset     = {},
        identifiedUnits = 0,
        secretUnits     = 0,
        unavailableUnits = 0,
        npcCoverage     = 0,

        linkedUnits    = 0,
        castingUnits   = 0,
        recentEventUnits = 0,
        everSawEventUnits = 0,
        encounterActive = ep.encounterActive == true,
        encounterEverSeen = ep.encounterEverSeen == true,
        routePullAtStart = ep.routePullAtStart,
        repeatedGenerations = ep.repeatedGenerations,
        overflow       = ep.overflow == true,

        generations = {},
    }

    for gen, m in pairs(ep.members) do
        if m.everEngaged then
            obsv.generations[#obsv.generations + 1] = gen
            if m.npcIDState == self.NPCID_STATES.AVAILABLE and m.npcID then
                obsv.npcMultiset[m.npcID] = (obsv.npcMultiset[m.npcID] or 0) + 1
                obsv.identifiedUnits = obsv.identifiedUnits + 1
            elseif m.npcIDState == self.NPCID_STATES.SECRET then
                obsv.secretUnits = obsv.secretUnits + 1
            else
                obsv.unavailableUnits = obsv.unavailableUnits + 1
            end
            if m.tokenLinkedActive then obsv.linkedUnits = obsv.linkedUnits + 1 end
            if m.castActive then obsv.castingUnits = obsv.castingUnits + 1 end
            if m.recentEventActive then
                obsv.recentEventUnits = obsv.recentEventUnits + 1
            end
            if m.everSawEvent then obsv.everSawEventUnits = obsv.everSawEventUnits + 1 end
        end
    end
    table.sort(obsv.generations)

    if obsv.engagedCount > 0 then
        obsv.npcCoverage = obsv.identifiedUnits / obsv.engagedCount
    end

    -- Consistencia física: cuánto del episodio estuvo peleando A LA VEZ. Un
    -- pack real sube casi todo junto; una secuencia de mobs sueltos no.
    obsv.engagementConsistency = (obsv.engagedCount > 0)
        and (obsv.peakEngaged / obsv.engagedCount) or 0
    obsv.castActivity = (obsv.engagedCount > 0)
        and (obsv.castingUnits / obsv.engagedCount) or 0
    -- EventCastEvidence se expresa deliberadamente como engagement temporal:
    -- presencia de actividad reciente, nunca firma ni identidad de criatura.
    obsv.eventEngagement = (obsv.engagedCount > 0)
        and (obsv.recentEventUnits / obsv.engagedCount) or 0
    obsv.tokenLinkage = (obsv.engagedCount > 0)
        and (obsv.linkedUnits / obsv.engagedCount) or 0

    return obsv
end

-- ─────────────────────────────────────────────────────────────────────────
-- DIAGNÓSTICO
-- ─────────────────────────────────────────────────────────────────────────

function EET:StatusLines()
    local L = { "|cFFe8b84a--- Execution episodes ---|r",
                "state=" .. self._state .. "  closed=" .. #self._history }
    local ep = self._episode
    if ep then
        L[#L + 1] = string.format(
            "episode=%d engaged=%d seen=%d peak=%d joined=%d removed=%d pullAtStart=%s",
            ep.episodeID, ep.generationsEngaged, ep.generationsSeen,
            ep.peakSimultaneousEngaged, ep.joinedDuringExecution,
            ep.removedDuringExecution, tostring(ep.routePullAtStart))
        local o = self:Observation(ep)
        if o then
            L[#L + 1] = string.format(
                "npcCoverage=%.2f identified=%d secret=%d unavailable=%d linked=%d",
                o.npcCoverage, o.identifiedUnits, o.secretUnits,
                o.unavailableUnits, o.linkedUnits)
        end
    else
        L[#L + 1] = "sin episodio en curso"
    end
    return L
end

return EET
