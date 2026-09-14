-- MitzuMPlus runtime capability matrix for final product features.
local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local RC = {}
MitzuMPlus.RuntimeCapabilities = RC

local AVAILABLE, AVAILABLE_ASYNC, LIMITED, UNAVAILABLE, UNKNOWN =
    "AVAILABLE", "AVAILABLE_ASYNC", "LIMITED", "UNAVAILABLE", "UNKNOWN"
RC.STATES = {
    AVAILABLE = AVAILABLE, AVAILABLE_ASYNC = AVAILABLE_ASYNC, LIMITED = LIMITED,
    UNAVAILABLE = UNAVAILABLE, UNKNOWN = UNKNOWN,
}
RC._caps, RC._why, RC._lastProbe = {}, {}, nil

local function set(self, key, value, why)
    self._caps[key], self._why[key] = value, why
end

function RC:Probe()
    self._caps, self._why = {}, {}
    set(self, "challengeMode",
        C_ChallengeMode and type(C_ChallengeMode.IsChallengeModeActive) == "function"
            and AVAILABLE or UNAVAILABLE,
        "C_ChallengeMode")
    set(self, "challengeClock",
        type(GetWorldElapsedTimers) == "function" and type(GetWorldElapsedTime) == "function"
            and AVAILABLE or UNAVAILABLE,
        "temporizador de Challenge Mode del servidor")
    set(self, "partyIdentity", type(UnitName) == "function" and AVAILABLE or UNAVAILABLE, "UnitName")
    set(self, "partyRoles", type(UnitGroupRolesAssigned) == "function" and AVAILABLE or UNAVAILABLE,
        "UnitGroupRolesAssigned")
    set(self, "partyClass", type(UnitClass) == "function" and AVAILABLE or UNAVAILABLE, "UnitClass")
    local hasPlayerSpec = (PlayerUtil and type(PlayerUtil.GetCurrentSpecID) == "function")
        or type(GetSpecializationInfo) == "function"
    set(self, "playerSpec", hasPlayerSpec and AVAILABLE or UNAVAILABLE,
        "PlayerUtil/GetSpecializationInfo")
    set(self, "partySpecs", type(NotifyInspect) == "function" and AVAILABLE_ASYNC or UNAVAILABLE,
        "NotifyInspect, sujeto a rango y caché")
    set(self, "damageMeter",
        C_DamageMeter and AVAILABLE or UNAVAILABLE,
        "C_DamageMeter")
    set(self, "enemyForcesAggregate",
        C_Scenario and type(C_Scenario.GetCriteriaInfo) == "function" and AVAILABLE or LIMITED,
        "criterios oficiales del escenario; solo total agregado")
    self._lastProbe = (GetTime and GetTime()) or 0
    return self._caps
end

function RC:Get(key)
    if not self._lastProbe then self:Probe() end
    return self._caps[key] or UNKNOWN
end
function RC:Why(key)
    if not self._lastProbe then self:Probe() end
    return self._why[key] or "sin sondeo"
end

local ORDER = {
    "challengeMode", "challengeClock", "partyIdentity", "partyRoles",
    "partyClass", "playerSpec", "partySpecs", "damageMeter", "enemyForcesAggregate",
}

function RC:Matrix()
    if not self._lastProbe then self:Probe() end
    local out = {}
    for _, key in ipairs(ORDER) do out[#out + 1] = key .. "=" .. self:Get(key) end
    return out
end

function RC:StatusLines(verbose)
    if not self._lastProbe then self:Probe() end
    local out = { "=== CAPACIDADES ===" }
    for _, key in ipairs(ORDER) do
        out[#out + 1] = key .. "=" .. self:Get(key)
        if verbose then out[#out + 1] = "  " .. self:Why(key) end
    end
    return out
end

return RC
