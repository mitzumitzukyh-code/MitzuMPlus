-- MitzuRouteArrows · EventCastEvidence v2.0 · FASE 3E, SOLO DIAGNOSTICO
-- Conserva casts efimeros por token nameplateN. No resuelve identidad.

local MRA = _G.MitzuRouteArrows
if not MRA then return end

-- AR: los demas modulos de este mismo addon.
-- Host: fachada de SOLO LECTURA sobre MitzuMPlusAPI (Core/Host.lua).
local AR = MRA
local Host = MRA.Host
local EventCastEvidence = {}
AR.EventCastEvidence = EventCastEvidence

local CAST_START, CHANNEL_START, SUCCEEDED, STOPPED, INTERRUPTED, UNKNOWN =
      "CAST_START", "CHANNEL_START", "SUCCEEDED", "STOPPED", "INTERRUPTED", "UNKNOWN"
local AVAILABLE, SECRET, UNAVAILABLE = "AVAILABLE", "SECRET", "UNAVAILABLE"

EventCastEvidence.STATES = {
    CAST_START = CAST_START, CHANNEL_START = CHANNEL_START,
    SUCCEEDED = SUCCEEDED, STOPPED = STOPPED,
    INTERRUPTED = INTERRUPTED, UNKNOWN = UNKNOWN,
}
EventCastEvidence.SPELL_ID_STATES = {
    AVAILABLE = AVAILABLE, SECRET = SECRET, UNAVAILABLE = UNAVAILABLE,
}

local TTL = 5
EventCastEvidence.TTL = TTL

-- Tras unitToken el payload es castGUID, spellID. castGUID nunca se enlaza.
local EVENTOS = {
    UNIT_SPELLCAST_START          = { state = CAST_START,    eventType = "START",         castState = "CASTING",   readsID = true },
    UNIT_SPELLCAST_CHANNEL_START  = { state = CHANNEL_START, eventType = "CHANNEL",       castState = "CHANNELING", readsID = true },
    UNIT_SPELLCAST_EMPOWER_START  = { state = CAST_START,    eventType = "EMPOWER_START", castState = "CASTING",   readsID = true },
    UNIT_SPELLCAST_SUCCEEDED      = { state = SUCCEEDED,     eventType = "SUCCEEDED",     castState = "NONE",      readsID = true },
    UNIT_SPELLCAST_STOP           = { state = STOPPED,       eventType = "STOP",          castState = "NONE" },
    UNIT_SPELLCAST_CHANNEL_STOP   = { state = STOPPED,       eventType = "CHANNEL_STOP",  castState = "NONE" },
    UNIT_SPELLCAST_EMPOWER_STOP   = { state = STOPPED,       eventType = "EMPOWER_STOP",  castState = "NONE" },
    UNIT_SPELLCAST_INTERRUPTED    = { state = INTERRUPTED,   eventType = "INTERRUPTED",   castState = "NONE" },
    UNIT_SPELLCAST_FAILED         = { state = STOPPED,       eventType = "FAILED",        castState = "NONE" },
    UNIT_SPELLCAST_FAILED_QUIET   = { state = STOPPED,       eventType = "FAILED_QUIET",  castState = "NONE" },
}
EventCastEvidence.EVENTS = EVENTOS

EventCastEvidence._cache = {}
EventCastEvidence._generation = {}
EventCastEvidence._visible = {}
EventCastEvidence._sequence = 0
EventCastEvidence._spellIDEventSafeObserved = false

local function estadoSecreto(v)
    local iss = rawget(_G, "issecretvalue")
    if type(iss) ~= "function" then return nil end
    local ok, res = pcall(iss, v)
    if not ok then return nil end
    if res == true then return true end
    if res == false then return false end
    return nil
end

local function ahora()
    local f = rawget(_G, "GetTime")
    if type(f) ~= "function" then return 0 end
    local ok, t = pcall(f)
    if not ok or type(t) ~= "number" then return 0 end
    return t
end

function EventCastEvidence:IsNameplateToken(unitToken)
    if estadoSecreto(unitToken) ~= false then return false end
    if type(unitToken) ~= "string" then return false end
    local ok, matched = pcall(string.match, unitToken, "^nameplate%d+$")
    return ok and matched ~= nil
end

-- La guarda ocurre antes de nil, type, comparacion o indexacion del spellID.
local function clasificarSpellID(...)
    local id = select(2, ...)
    local secreto = estadoSecreto(id)
    if secreto == true then return SECRET, nil end
    if secreto ~= false then return SECRET, nil end -- fail closed
    if id == nil then return UNAVAILABLE, nil end
    if type(id) ~= "number" then return UNAVAILABLE, nil end
    return AVAILABLE, id
end

function EventCastEvidence:Purge(t)
    t = t or ahora()
    local n = 0
    for token, obs in pairs(self._cache) do
        if obs.generation ~= self._generation[token] or (t - obs.t) > TTL then
            self._cache[token] = nil
            n = n + 1
        end
    end
    return n
end

function EventCastEvidence:Clear()
    local n = 0
    for token in pairs(self._cache) do self._cache[token] = nil; n = n + 1 end
    for token in pairs(self._generation) do self._generation[token] = nil end
    for token in pairs(self._visible) do self._visible[token] = nil end
    return n
end

function EventCastEvidence:Forget(unitToken)
    if not self:IsNameplateToken(unitToken) then return false end
    local existed = self._cache[unitToken] ~= nil
    self._cache[unitToken] = nil
    return existed
end

function EventCastEvidence:_BeginGeneration(unitToken, visible)
    if not self:IsNameplateToken(unitToken) then return nil end
    self._generation[unitToken] = (self._generation[unitToken] or 0) + 1
    self._cache[unitToken] = nil
    self._visible[unitToken] = visible == true or nil
    return self._generation[unitToken]
end

function EventCastEvidence:Observe(event, unitToken, ...)
    if type(event) ~= "string" then return nil end
    if event == "PLAYER_ENTERING_WORLD" then self:Clear(); return nil end
    if event == "NAME_PLATE_UNIT_ADDED" then self:_BeginGeneration(unitToken, true); return nil end
    if event == "NAME_PLATE_UNIT_REMOVED" then self:_BeginGeneration(unitToken, false); return nil end

    local def = EVENTOS[event]
    if not def or not self:IsNameplateToken(unitToken) then return nil end
    if self._generation[unitToken] == nil then self._generation[unitToken] = 1 end

    local idState, id = UNAVAILABLE, nil
    if def.readsID then idState, id = clasificarSpellID(...) end
    self._sequence = self._sequence + 1
    self._cache[unitToken] = {
        state = def.state, eventType = def.eventType, castState = def.castState,
        spellIDState = idState, spellID = id,
        sequence = self._sequence, generation = self._generation[unitToken],
        t = ahora(),
    }
    if idState == AVAILABLE then self._spellIDEventSafeObserved = true end
    return def.state
end

function EventCastEvidence:Get(unitToken)
    if not self:IsNameplateToken(unitToken) then return UNKNOWN, nil end
    self:Purge()
    local obs = self._cache[unitToken]
    if not obs then return UNKNOWN, nil end
    return obs.state, obs.spellID
end

function EventCastEvidence:InspectToken(unitToken)
    self:Purge()
    local obs = self:IsNameplateToken(unitToken) and self._cache[unitToken] or nil
    if not obs then
        return { eventState = "NONE", eventType = "NONE", castState = "NONE",
            spellIDState = UNAVAILABLE, safeSpellID = "NO",
            tokenLinked = "NO", identityState = "UNKNOWN" }
    end
    local age = math.max(0, math.floor((ahora() - obs.t) * 1000 + 0.5))
    return {
        eventState = "SEEN", eventType = obs.eventType, castState = obs.castState,
        spellIDState = obs.spellIDState,
        safeSpellID = obs.spellIDState == AVAILABLE and "YES" or "NO",
        safeSpellIDValue = obs.spellID, ageMs = age,
        generation = obs.generation, tokenLinked = "YES",
        identityState = "UNKNOWN",
    }
end

function EventCastEvidence:HasSafeSpellID()
    return self._spellIDEventSafeObserved == true
end

function EventCastEvidence:Snapshot()
    self:Purge()
    local lista = {}
    local r = { tracked = 0, castStart = 0, channelStart = 0, succeeded = 0,
        stopped = 0, interrupted = 0, unknown = 0, safeSpellIDs = 0,
        secretSpellIDs = 0, eventOnly = 0 }
    for token, obs in pairs(self._cache) do
        local e = self:InspectToken(token)
        e.unitToken, e.state, e.sequence = token, obs.state, obs.sequence
        lista[#lista + 1] = e
    end
    table.sort(lista, function(a, b) return a.unitToken < b.unitToken end)
    for _, e in ipairs(lista) do
        r.tracked = r.tracked + 1
        if e.state == CAST_START then r.castStart = r.castStart + 1
        elseif e.state == CHANNEL_START then r.channelStart = r.channelStart + 1
        elseif e.state == SUCCEEDED then r.succeeded = r.succeeded + 1
        elseif e.state == STOPPED then r.stopped = r.stopped + 1
        elseif e.state == INTERRUPTED then r.interrupted = r.interrupted + 1
        else r.unknown = r.unknown + 1 end
        if e.spellIDState == AVAILABLE then r.safeSpellIDs = r.safeSpellIDs + 1
        elseif e.spellIDState == SECRET then r.secretSpellIDs = r.secretSpellIDs + 1 end
        if e.eventState == "SEEN" and e.spellIDState ~= AVAILABLE then r.eventOnly = r.eventOnly + 1 end
    end
    return lista, r
end

local frame = CreateFrame("Frame")
for evento in pairs(EVENTOS) do frame:RegisterEvent(evento) end
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, unitToken, ...)
    return EventCastEvidence:Observe(event, unitToken, ...)
end)

if Host.EventBus then
    local function limpiar() pcall(function() EventCastEvidence:Clear() end) end
    Host.EventBus:On("MITZU_KEY_COMPLETED", limpiar)
    Host.EventBus:On("MITZU_KEY_RESET", limpiar)
end

return EventCastEvidence
