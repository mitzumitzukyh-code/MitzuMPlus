-- MitzuMPlus product invariants.
local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local Inv = {}
MitzuMPlus.QAInvariants = Inv

local VALID = { ["+3"] = true, ["+2"] = true, ["+1"] = true, OVERTIME = true, NONE = true }

local function call(obj, name, ...)
    if type(obj) ~= "table" or type(obj[name]) ~= "function" then return nil end
    local ok, a = pcall(obj[name], obj, ...)
    return ok and a or nil
end
local function result(name, status, detail)
    return { name = name, status = status, detail = detail }
end

function Inv:Gather()
    local DC, HUD = MitzuMPlus.DungeonContext, MitzuMPlus.MitzuTracker
    local state = call(DC, "GetState")
    local challenge = call(DC, "IsChallengeActive")
    local displayed = call(HUD, "GetDisplayed") or {}
    local run = rawget(_G, "MitzuMPlusCurrentRun")
    local snapshot = run and call(MitzuMPlus.PredictionEngine, "GetSnapshot", run) or nil

    local duplicateSessions, seen = 0, {}
    local runs = MitzuMPlus.db and MitzuMPlus.db.global and MitzuMPlus.db.global.runs or {}
    for _, saved in pairs(type(runs) == "table" and runs or {}) do
        if type(saved) == "table" and type(saved.sessionID) == "string" and saved.sessionID ~= "" then
            if seen[saved.sessionID] then duplicateSessions = duplicateSessions + 1
            else seen[saved.sessionID] = true end
        end
    end

    local PP = MitzuMPlus.PartyProfiler
    local party = call(PP, "GetRosterDiagnostics") or {}
    return {
        lifecycle = state,
        challengeActive = challenge,
        runActive = run ~= nil,
        trackerVisible = call(HUD, "IsVisible"),
        trackerPreview = call(HUD, "IsPreview"),
        trackerMode = call(HUD, "GetMode"),
        trackerFloatingVisible = call(HUD, "IsFloatingVisible"),
        trackerPrediction = displayed.prediction or "NONE",
        enginePrediction = snapshot and snapshot.result or nil,
        duplicateSessions = duplicateSessions,
        routeModulesPresent = rawget(MitzuMPlus, "RouteProgress") ~= nil
            or rawget(MitzuMPlus, "RouteManager") ~= nil
            or rawget(MitzuMPlus, "AdaptiveRoute") ~= nil,
        mdtRuntimePresent = rawget(MitzuMPlus, "MDTImporter") ~= nil
            or rawget(MitzuMPlus, "MDTEnemyData") ~= nil,
        routeArrowsInCore = rawget(MitzuMPlus, "RouteArrows") ~= nil
            or rawget(MitzuMPlus, "RouteAlignment") ~= nil,
        partyExpected = party.expectedGroupSize,
        partyCached = party.cachedSize,
        partyAge = party.lastRosterAge,
    }
end

function Inv:Evaluate(st)
    st = st or self:Gather()
    local out = {}

    local challengeConsistent = st.challengeActive ~= true or st.lifecycle == "RUNNING"
    out[#out + 1] = result("CHALLENGE_IMPLIES_RUNNING",
        challengeConsistent and "PASS" or "FAIL",
        st.challengeActive == true and st.lifecycle ~= "RUNNING" and ("lifecycle=" .. tostring(st.lifecycle)) or nil)
    local runningConsistent = st.lifecycle ~= "RUNNING" or st.challengeActive == true
    out[#out + 1] = result("RUNNING_IMPLIES_CHALLENGE",
        runningConsistent and "PASS" or "FAIL",
        st.lifecycle == "RUNNING" and st.challengeActive ~= true and "challenge=false" or nil)

    -- COMPLETING mantiene visible el ultimo estado mientras converge el final.
    local validTrackerContext = st.trackerPreview == true
        or st.trackerVisible ~= true
        or st.lifecycle == "RUNNING"
        or (st.lifecycle == "COMPLETED" and (st.trackerMode == "SUMMARY" or st.trackerMode == "COMPLETING"))
    out[#out + 1] = result("TRACKER_ONLY_DURING_VALID_CONTEXT",
        validTrackerContext and "PASS" or "FAIL",
        validTrackerContext and nil or ("lifecycle=" .. tostring(st.lifecycle)))

    -- dev.7: durante una llave real no existe ventana flotante de Mitzu; los
    -- datos van dentro del tracker de Blizzard. Solo vista previa o resumen.
    local floatingDuringKey = st.trackerFloatingVisible == true and st.trackerPreview ~= true
        and (st.lifecycle == "RUNNING" or st.trackerMode == "RUNNING" or st.trackerMode == "PENDING"
             or st.trackerMode == "COMPLETING")
    out[#out + 1] = result("NO_FLOATING_HUD_DURING_KEY",
        floatingDuringKey and "FAIL" or "PASS",
        floatingDuringKey and ("mode=" .. tostring(st.trackerMode)) or nil)

    out[#out + 1] = result("PREDICTION_VALID_ENUM",
        VALID[tostring(st.trackerPrediction)] and "PASS" or "FAIL",
        "value=" .. tostring(st.trackerPrediction))
    out[#out + 1] = result("PREDICTION_NO_ROUTE_DEPENDENCY",
        not st.routeModulesPresent and "PASS" or "FAIL")
    local duplicateSessions = tonumber(st.duplicateSessions) or 0
    out[#out + 1] = result("HISTORY_NO_DUPLICATE_FINALIZATION",
        duplicateSessions == 0 and "PASS" or "FAIL",
        duplicateSessions > 0 and ("duplicateSessionIDs=" .. duplicateSessions) or nil)
    out[#out + 1] = result("NO_ROUTEARROWS_IN_CORE",
        not st.routeArrowsInCore and "PASS" or "FAIL")
    out[#out + 1] = result("NO_MDT_RUNTIME_DEPENDENCY",
        not st.mdtRuntimePresent and "PASS" or "FAIL")

    if st.lifecycle == "RUNNING" and tonumber(st.partyExpected) and tonumber(st.partyCached)
       and st.partyExpected > st.partyCached and (tonumber(st.partyAge) or 0) >= 10 then
        out[#out + 1] = result("PARTY_ROSTER_CONVERGED", "WARN",
            string.format("expected=%s cached=%s age=%.1f", st.partyExpected, st.partyCached,
                tonumber(st.partyAge) or 0))
    else
        out[#out + 1] = result("PARTY_ROSTER_CONVERGED", "PASS")
    end
    return out
end

function Inv:Summary(results)
    local totals = { PASS = 0, WARN = 0, FAIL = 0, SKIP = 0 }
    for _, item in ipairs(results or {}) do
        totals[item.status] = (totals[item.status] or 0) + 1
    end
    return totals
end

return Inv
