-- ===========================================================================
-- MitzuMPlus · InspectArbiter
--
-- A single owner for WoW's process-global inspect channel.
--
-- PLAYER-INSPECT-001:
-- Blizzard's native InspectFrame and addons all share NotifyInspect /
-- INSPECT_READY state.  Two simultaneous consumers can replace each other's
-- request, and ClearInspectPlayer can invalidate the native frame's cache.
--
-- Rules enforced here:
--   * every proactive Mitzu NotifyInspect goes through this arbiter;
--   * only one Mitzu request can be in flight;
--   * requests yield while Blizzard's InspectFrame is visible;
--   * a short grace is observed after native/external inspection activity;
--   * global request rate is throttled across all Mitzu consumers;
--   * Mitzu NEVER calls ClearInspectPlayer.
--
-- The native InspectFrame always wins.  If the player opens it while Mitzu had
-- a request in flight, callers abandon/requeue their own work without touching
-- Blizzard's inspect cache.
-- ===========================================================================

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local InspectArbiter = {}
MitzuMPlus.InspectArbiter = InspectArbiter

local MIN_REQUEST_INTERVAL = 2.5
local EXTERNAL_GRACE        = 2.5
local NATIVE_GRACE          = 1.5

InspectArbiter._owner = nil
InspectArbiter._guid = nil
InspectArbiter._unit = nil
InspectArbiter._requestedAt = 0
InspectArbiter._lastRequestAt = -1000
InspectArbiter._externalYieldUntil = 0
InspectArbiter._nativeYieldUntil = 0
InspectArbiter._lastExternalGUID = nil
InspectArbiter._lastCompletedGUID = nil
InspectArbiter._lastCompletedAt = -1000
InspectArbiter._lastReason = "INIT"
InspectArbiter._requests = 0
InspectArbiter._blockedNative = 0
InspectArbiter._blockedThrottle = 0
InspectArbiter._blockedMitzu = 0

local function now()
    return (type(GetTime) == "function" and GetTime()) or 0
end

local function callBool(obj, method)
    if not obj then return false end
    local fn = obj[method]
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, obj)
    return ok and value == true
end

-- Read-only probe of Blizzard's native inspect state. Current Retail sets
-- InspectFrame.unit immediately after its own NotifyInspect(), but only shows
-- the window after the matching INSPECT_READY. Checking IsShown() alone leaves
-- exactly the race window from PLAYER-INSPECT-001, so `unit` is authoritative
-- even while the frame is still hidden and waiting for server data.
function InspectArbiter:NativeInspectState()
    local frame = rawget(_G, "InspectFrame")
    local shown, unit = false, nil
    if frame ~= nil then
        shown = callBool(frame, "IsShown") or callBool(frame, "IsVisible")
        local ok, value = pcall(function() return frame.unit end)
        if ok and type(value) == "string" and value ~= "" then unit = value end
    end

    -- Retail can keep the inspected talent/spell view alive while the paperdoll
    -- frame transitions. Treat that as native ownership too when the API exists.
    local spells = rawget(_G, "PlayerSpellsFrame")
    local spellsInspecting = callBool(spells, "IsInspecting")

    return shown or unit ~= nil or spellsInspecting, shown, unit
end

function InspectArbiter:IsNativeInspectVisible()
    local _, shown = self:NativeInspectState()
    return shown
end

function InspectArbiter:IsNativeInspectBusy()
    local t = now()
    local active = self:NativeInspectState()
    if active then
        self._nativeYieldUntil = math.max(self._nativeYieldUntil or 0, t + NATIVE_GRACE)
        self._lastReason = "NATIVE_INSPECT_ACTIVE"
        return true, "NATIVE_INSPECT_ACTIVE"
    end
    if t < (self._nativeYieldUntil or 0) then
        return true, "NATIVE_INSPECT_GRACE"
    end
    if t < (self._externalYieldUntil or 0) then
        return true, "EXTERNAL_INSPECT_GRACE"
    end
    return false, nil
end

function InspectArbiter:CurrentOwner()
    return self._owner, self._guid, self._unit
end

function InspectArbiter:IsOwnedBy(owner, guid)
    if self._owner ~= owner then return false end
    if guid ~= nil and self._guid ~= guid then return false end
    return true
end

-- The only proactive NotifyInspect entry point MitzuMPlus should use.
function InspectArbiter:Request(owner, unit, guid)
    if type(owner) ~= "string" or owner == "" then return false, "INVALID_OWNER" end
    if type(unit) ~= "string" or unit == "" then return false, "INVALID_UNIT" end
    if type(NotifyInspect) ~= "function" then return false, "API_UNAVAILABLE" end

    local nativeBusy, nativeReason = self:IsNativeInspectBusy()
    if nativeBusy then
        self._blockedNative = (self._blockedNative or 0) + 1
        return false, nativeReason
    end

    if self._owner ~= nil then
        self._blockedMitzu = (self._blockedMitzu or 0) + 1
        return false, "MITZU_INSPECT_BUSY"
    end

    local t = now()
    local remaining = MIN_REQUEST_INTERVAL - (t - (self._lastRequestAt or -1000))
    if remaining > 0 then
        self._blockedThrottle = (self._blockedThrottle or 0) + 1
        return false, "GLOBAL_THROTTLE", remaining
    end

    -- Claim before the call. INSPECT_READY is asynchronous on Retail, but this
    -- keeps ownership correct even if a test double fires synchronously.
    self._owner = owner
    self._guid = guid
    self._unit = unit
    self._requestedAt = t
    self._lastRequestAt = t
    self._lastReason = "REQUESTED"

    local ok = pcall(NotifyInspect, unit)
    if not ok then
        self._owner, self._guid, self._unit = nil, nil, nil
        self._lastReason = "NOTIFY_FAILED"
        return false, "NOTIFY_FAILED"
    end

    self._requests = (self._requests or 0) + 1
    return true, "REQUESTED"
end

function InspectArbiter:Complete(owner, guid)
    if not self:IsOwnedBy(owner, guid) then return false end
    self._owner, self._guid, self._unit = nil, nil, nil
    self._lastCompletedGUID = guid
    self._lastCompletedAt = now()
    self._lastReason = "COMPLETED"
    return true
end

function InspectArbiter:Abandon(owner, guid, reason)
    if not self:IsOwnedBy(owner, guid) then return false end
    self._owner, self._guid, self._unit = nil, nil, nil
    self._lastReason = tostring(reason or "ABANDONED")
    return true
end

-- Called by the arbiter's own event frame before consumer-specific handlers.
-- A mismatched GUID means some other consumer (normally Blizzard InspectFrame)
-- completed an inspection.  We do NOT clear our current ownership here; its
-- caller will timeout/requeue conservatively.  We only establish a grace
-- period so no new Mitzu request can immediately overwrite native data.
function InspectArbiter:ObserveInspectReady(guid)
    if type(guid) ~= "string" then return end
    local t = now()
    if (self._guid ~= nil and self._guid == guid)
       or (self._lastCompletedGUID == guid and t - (self._lastCompletedAt or -1000) < 0.5) then
        self._lastReason = "OWN_READY"
        return
    end
    self._lastExternalGUID = guid
    self._externalYieldUntil = math.max(self._externalYieldUntil or 0, now() + EXTERNAL_GRACE)
    self._lastReason = "EXTERNAL_READY"
end

function InspectArbiter:Status()
    local nativeActive, nativeShown, nativeUnit = self:NativeInspectState()
    local t = now()
    return {
        owner = self._owner,
        guid = self._guid,
        unit = self._unit,
        nativeInspectActive = nativeActive,
        nativeInspectVisible = nativeShown,
        nativeInspectUnit = nativeUnit,
        externalGrace = math.max(0, (self._externalYieldUntil or 0) - t),
        nativeGrace = math.max(0, (self._nativeYieldUntil or 0) - t),
        lastExternalGUID = self._lastExternalGUID,
        lastReason = self._lastReason,
        requests = self._requests or 0,
        blockedNative = self._blockedNative or 0,
        blockedThrottle = self._blockedThrottle or 0,
        blockedMitzu = self._blockedMitzu or 0,
        clearInspectCalls = 0,
    }
end

function InspectArbiter:ReportLines()
    local st = self:Status()
    return {
        "=== INSPECT SAFETY / PLAYER-INSPECT-001 ===",
        "owner=" .. tostring(st.owner or "none"),
        "guid=" .. tostring(st.guid or "none"),
        "nativeInspectActive=" .. tostring(st.nativeInspectActive == true),
        "nativeInspectVisible=" .. tostring(st.nativeInspectVisible == true),
        "nativeInspectUnit=" .. tostring(st.nativeInspectUnit or "none"),
        "nativeGrace=" .. string.format("%.2f", tonumber(st.nativeGrace) or 0),
        "externalGrace=" .. string.format("%.2f", tonumber(st.externalGrace) or 0),
        "lastExternalGUID=" .. tostring(st.lastExternalGUID or "none"),
        "lastReason=" .. tostring(st.lastReason or "none"),
        "requests=" .. tostring(st.requests or 0),
        "blockedNative=" .. tostring(st.blockedNative or 0),
        "blockedThrottle=" .. tostring(st.blockedThrottle or 0),
        "blockedMitzu=" .. tostring(st.blockedMitzu or 0),
        "clearInspectCalls=0",
    }
end

-- Register before PartyProfiler/InspectQueue in the TOC so this observer sees
-- INSPECT_READY independently of either consumer.
local frame = CreateFrame("Frame", "MitzuMPlusInspectArbiterFrame")
frame:RegisterEvent("INSPECT_READY")
frame:SetScript("OnEvent", function(_, event, guid)
    if event == "INSPECT_READY" then
        InspectArbiter:ObserveInspectReady(guid)
    end
end)

return InspectArbiter
