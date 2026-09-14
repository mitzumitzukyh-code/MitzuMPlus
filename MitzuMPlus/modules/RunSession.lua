-- MitzuMPlus RunSession
-- Stable run identity, /reload recovery and duplicate-finalization protection.
-- This module deliberately knows nothing about routes or combat navigation.

local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon("MitzuMPlus")
local RunSession = {}
MitzuMPlus.RunSession = RunSession

RunSession.SCHEMA = 2
RunSession.STATES = { NONE = "NONE", RUNNING = "RUNNING", COMPLETED = "COMPLETED" }
RunSession._state, RunSession._reason, RunSession._recovered = "NONE", "NO_SESSION", false

local function now() return (time and time()) or 0 end
local function record(event, data)
    local FR = MitzuMPlus.FlightRecorder
    if FR and FR.Record then FR:Record("SESSION", event, data) end
end
local function storage()
    local global = MitzuMPlus.db and MitzuMPlus.db.global
    return type(global) == "table" and global or nil
end
local function clockStartedAt()
    local clock = MitzuMPlus.ChallengeClock
    if not (clock and clock.GetStartedAt) then return nil end
    local ok, value = pcall(clock.GetStartedAt, clock)
    value = ok and tonumber(value) or nil
    return value and math.floor(value) or nil
end
local function identity(dungeonID, level, startedAt)
    dungeonID, level, startedAt = tonumber(dungeonID), tonumber(level), tonumber(startedAt)
    if not dungeonID or not level or not startedAt then return nil end
    return string.format("%d:%d:%d", dungeonID, level, math.floor(startedAt))
end
RunSession.MakeIdentity = identity

local function sameStart(a, b)
    a, b = tonumber(a), tonumber(b)
    return a and b and math.abs(a - b) <= 20
end

function RunSession:GetSnapshot()
    local global = storage()
    return global and global.activeRunSession or nil
end

function RunSession:StartOrRestore(dungeonID, level)
    dungeonID, level = tonumber(dungeonID), tonumber(level)
    if not dungeonID or dungeonID <= 0 or not level or level <= 0 then
        self._state, self._reason = "NONE", "INVALID_CONTEXT"
        return nil, self._reason
    end
    local global = storage()
    if not global then
        self._state, self._reason = "NONE", "DB_UNAVAILABLE"
        return nil, self._reason
    end

    local startedAt = clockStartedAt()
    local old = global.activeRunSession
    local sameContext = type(old) == "table"
        and tonumber(old.dungeonID) == dungeonID
        and tonumber(old.keystoneLevel) == level

    if sameContext and old.state == "COMPLETED"
       and (not startedAt or sameStart(old.startedAt, startedAt)) then
        self._state, self._reason, self._recovered = "COMPLETED", "STALE_COMPLETION", false
        record("START_REJECTED", { reason = self._reason, id = old.id })
        return nil, self._reason
    end

    if sameContext and old.state == "RUNNING"
       and (not startedAt or sameStart(old.startedAt, startedAt)) then
        old.lastSeenAt, old.schema = now(), self.SCHEMA
        self._state, self._reason, self._recovered = "RUNNING", "RELOAD_RECOVERY", true
        record("RESTORED", { id = old.id, startedAt = old.startedAt })
        return old, "RESTORED"
    end

    startedAt = startedAt or now()
    local session = {
        schema = self.SCHEMA,
        id = identity(dungeonID, level, startedAt),
        state = "RUNNING",
        dungeonID = dungeonID,
        keystoneLevel = level,
        startedAt = startedAt,
        createdAt = now(),
        lastSeenAt = now(),
    }
    global.activeRunSession = session
    self._state, self._reason, self._recovered = "RUNNING", "NEW_RUN", false
    record("STARTED", { id = session.id, startedAt = startedAt })
    return session, "NEW"
end

function RunSession:Touch(run)
    local s = self:GetSnapshot()
    if type(s) ~= "table" or s.state ~= "RUNNING" then return false end
    if run and run.sessionID and s.id ~= run.sessionID then return false end
    s.lastSeenAt = now()
    return true
end

local function samePlayer(a, b)
    return tostring(a.playerName or "") == tostring(b.playerName or "")
       and tostring(a.playerRealm or "") == tostring(b.playerRealm or "")
end

function RunSession:IsDuplicateFinalization(run, completionTime, finishedAt)
    if type(run) ~= "table" then return false end
    completionTime, finishedAt = tonumber(completionTime), tonumber(finishedAt) or now()
    local current = self:GetSnapshot()
    if type(current) == "table" and current.state == "COMPLETED"
       and run.sessionID and current.id == run.sessionID then
        return true, "SESSION_ALREADY_COMPLETED", current.runID
    end

    local runs = MitzuMPlus.db and MitzuMPlus.db.global and MitzuMPlus.db.global.runs
    if type(runs) ~= "table" or not completionTime then return false end
    local window = math.min(300, math.max(30, completionTime * 0.25))
    for id, saved in pairs(runs) do
        if type(saved) == "table"
           and tonumber(saved.dungeonID) == tonumber(run.dungeonID)
           and tonumber(saved.keyLevel) == tonumber(run.keyLevel)
           and samePlayer(saved, run)
           and math.abs((tonumber(saved.completionTime) or -99999) - completionTime) <= 1 then
            if run.sessionID and saved.sessionID and run.sessionID == saved.sessionID then
                return true, "SESSION_ID_MATCH", id
            end
            local priorEnd = tonumber(saved.endTime)
            if priorEnd and finishedAt >= priorEnd and finishedAt - priorEnd <= window then
                return true, "RECYCLED_COMPLETION_INFO", id
            end
        end
    end
    return false
end

function RunSession:Finalize(run, completionTime, finishedAt, runID)
    local global = storage()
    if not global then return false end
    local s = global.activeRunSession
    if type(s) ~= "table" or (run and run.sessionID and s.id ~= run.sessionID) then
        s = {
            schema = self.SCHEMA, id = run and run.sessionID,
            dungeonID = run and run.dungeonID, keystoneLevel = run and run.keyLevel,
            startedAt = run and run.startTime,
        }
        global.activeRunSession = s
    end
    s.state, s.finishedAt = "COMPLETED", tonumber(finishedAt) or now()
    s.completionTime, s.runID, s.lastSeenAt = tonumber(completionTime), runID, now()
    self._state, self._reason, self._recovered = "COMPLETED", "FINALIZED", false
    record("FINALIZED", { id = s.id, runID = runID })
    return true
end

function RunSession:Clear(reason)
    local global = storage()
    if global then global.activeRunSession = nil end
    self._state, self._reason, self._recovered = "NONE", reason or "CLEARED", false
    record("CLEARED", { reason = self._reason })
end

function RunSession:GetState()
    local s = self:GetSnapshot()
    return type(s) == "table" and s.state or self._state
end
function RunSession:GetReason() return self._reason end
function RunSession:IsRecovered() return self._recovered == true end
function RunSession:IsDecided() return self:GetState() ~= "NONE" end
function RunSession:GetWaitingFor() return self:GetState() == "NONE" and "CHALLENGE" or "NONE" end

function RunSession:StatusLines()
    local s = self:GetSnapshot()
    return {
        "state=" .. tostring(self:GetState()),
        "reason=" .. tostring(self._reason),
        "recovered=" .. tostring(self._recovered == true),
        "sessionID=" .. tostring(s and s.id),
        "dungeonID=" .. tostring(s and s.dungeonID),
        "keystoneLevel=" .. tostring(s and s.keystoneLevel),
        "startedAt=" .. tostring(s and s.startedAt),
        "finishedAt=" .. tostring(s and s.finishedAt),
        "runID=" .. tostring(s and s.runID),
    }
end

return RunSession
