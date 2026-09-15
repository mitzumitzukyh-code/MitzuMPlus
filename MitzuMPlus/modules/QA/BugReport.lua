-- MitzuMPlus sanitized diagnostic report.
local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local BR = {}
MitzuMPlus.BugReport = BR
BR.REPORT_VERSION, BR.RECENT_EVENTS, BR.MAX_ERRORS = 3, 80, 10

local function safe()
    return MitzuMPlus.QASafe or {
        Text = function(v)
            if v == nil then return "nil" end
            local ok, text = pcall(tostring, v)
            return ok and text:gsub("|", "/") or "UNAVAILABLE"
        end,
    }
end
local function call(obj, name, ...)
    if type(obj) ~= "table" or type(obj[name]) ~= "function" then return nil end
    local values = { pcall(obj[name], obj, ...) }
    if not values[1] then return nil end
    return values[2], values[3], values[4], values[5]
end
local function count(t)
    local n = 0
    for _ in pairs(type(t) == "table" and t or {}) do n = n + 1 end
    return n
end

local SECTIONS = {}
SECTIONS[#SECTIONS + 1] = { "BUILD", function(add)
    add("ReportVersion", BR.REPORT_VERSION)
    add("Addon", MitzuMPlus.VERSION)
    local ok, version, build, buildDate, interface = pcall(GetBuildInfo)
    add("WoW", ok and version or "UNAVAILABLE")
    add("Build", ok and build or "UNAVAILABLE")
    add("BuildDate", ok and buildDate or "UNAVAILABLE")
    add("Interface", ok and interface or "UNAVAILABLE")
    local okLocale, locale = pcall(GetLocale)
    add("Locale", okLocale and locale or "UNAVAILABLE")
    local okDate, generated = pcall(date, "%Y-%m-%d %H:%M:%S")
    add("Generated", okDate and generated or "UNAVAILABLE")
end }

SECTIONS[#SECTIONS + 1] = { "CONTEXT", function(add)
    local DC, CC = MitzuMPlus.DungeonContext, MitzuMPlus.ChallengeClock
    add("dungeonKey", call(DC, "GetDungeonKey"))
    add("dungeonName", call(DC, "GetDungeonName"))
    add("lifecycle", call(DC, "GetState"))
    add("previousState", DC and rawget(DC, "_previousState"))
    add("lastTransition", DC and rawget(DC, "_lastTransition"))
    add("lastEvent", DC and rawget(DC, "_lastEvent"))
    add("challengeActive", call(DC, "IsChallengeActive"))
    add("challengeMapID", call(DC, "GetChallengeMapID"))
    add("keystoneLevel", call(DC, "GetKeystoneLevel"))
    add("identitySource", call(DC, "GetIdentitySource"))
    add("clock.state", call(CC, "GetState"))
    add("clock.elapsed", call(CC, "GetElapsed"))
    add("clock.limit", call(CC, "GetTimeLimit"))
    add("clock.remaining", call(CC, "GetRemaining", false))
end }

SECTIONS[#SECTIONS + 1] = { "PLAYER", function(add)
    local PP = MitzuMPlus.PartyProfiler
    local specID, specName, role, state = call(PP, "GetPlayerSpec")
    add("specID", specID); add("spec", specName); add("role", role); add("specState", state)
    local ok, _, class = pcall(UnitClass, "player")
    add("class", ok and class or "UNAVAILABLE")
end }

SECTIONS[#SECTIONS + 1] = { "PARTY", function(add)
    local PP = MitzuMPlus.PartyProfiler
    local members = call(PP, "GetMembers") or {}
    local list = {}
    for _, member in pairs(type(members) == "table" and members or {}) do
        if type(member) == "table" then list[#list + 1] = member end
    end
    table.sort(list, function(a, b) return tostring(a.unitToken) < tostring(b.unitToken) end)
    add("size", #list)
    local diag = call(PP, "GetRosterDiagnostics") or {}
    for _, key in ipairs({ "expectedGroupSize", "cachedSize", "lastRosterAge",
                            "rosterRefreshCount", "lastRefreshReason", "inspectPending", "inspectActive" }) do
        add(key, diag[key])
    end
    for _, member in ipairs(list) do
        local token = tostring(member.unitToken or "unit?"):match("^%a+%d*$") or "unit?"
        add(token, string.format("class=%s role=%s spec=%s state=%s",
            safe().Text(member.class), safe().Text(member.role),
            safe().Text(member.specID), safe().Text(member.specState)))
    end
end }

SECTIONS[#SECTIONS + 1] = { "RUN", function(add)
    local run = rawget(_G, "MitzuMPlusCurrentRun")
    add("active", type(run) == "table")
    if type(run) == "table" then
        add("sessionID", run.sessionID)
        add("recovered", run.sessionRecovered == true)
        add("dungeonID", run.dungeonID)
        add("level", run.keyLevel)
        add("startedAt", run.startTime)
        add("groupSize", count(run.group))
    end
    local RS = MitzuMPlus.RunSession
    add("sessionState", call(RS, "GetState"))
    add("sessionReason", call(RS, "GetReason"))
    local snapshot = call(RS, "GetSnapshot")
    if type(snapshot) == "table" then
        add("snapshotID", snapshot.id)
        add("snapshotState", snapshot.state)
        add("snapshotStartedAt", snapshot.startedAt)
        add("snapshotFinishedAt", snapshot.finishedAt)
        add("snapshotRunID", snapshot.runID)
    end
end }

SECTIONS[#SECTIONS + 1] = { "HISTORY", function(add)
    local runs = MitzuMPlus.db and MitzuMPlus.db.global and MitzuMPlus.db.global.runs or {}
    local sessions, duplicates, valid, partial = {}, 0, 0, 0
    for _, run in pairs(type(runs) == "table" and runs or {}) do
        if type(run) == "table" then
            valid = valid + 1
            if type(run.sessionID) == "string" and run.sessionID ~= "" then
                if sessions[run.sessionID] then duplicates = duplicates + 1
                else sessions[run.sessionID] = true end
            else
                partial = partial + 1
            end
        end
    end
    add("runs", valid)
    add("legacyWithoutSessionID", partial)
    add("duplicateSessionIDs", duplicates)
    add("nextRunID", MitzuMPlus.db and MitzuMPlus.db.global and MitzuMPlus.db.global.nextRunID)
end }

SECTIONS[#SECTIONS + 1] = { "TRACKER", function(add)
    local HUD = MitzuMPlus.KeyPredictionHUD
    local fields = call(HUD, "DiagnosticFields")
    if type(fields) ~= "table" then add("module", HUD and "AVAILABLE" or "UNAVAILABLE") return end
    for _, pair in ipairs(fields) do
        if type(pair) == "table" then add(pair[1], pair[2]) end
    end
end }

-- 1.1: lectura directa de Blizzard a traves del adaptador, para contrastarla
-- con la seccion TRACKER (que sigue saliendo de los modulos 1.0).
SECTIONS[#SECTIONS + 1] = { "TRACKER ADAPTER", function(add)
    local TA = MitzuMPlus.TrackerAdapter
    local fields = call(TA, "DiagnosticFields")
    if type(fields) ~= "table" then add("module", TA and "ERROR" or "UNAVAILABLE") return end
    for _, pair in ipairs(fields) do
        if type(pair) == "table" then add(pair[1], pair[2]) end
    end
end }

-- 1.1: estructura y taint del Objective Tracker nativo que se va a decorar.
SECTIONS[#SECTIONS + 1] = { "BLIZZARD TRACKER", function(add)
    local BTP = MitzuMPlus.BlizzardTrackerProbe
    local fields = call(BTP, "DiagnosticFields")
    if type(fields) ~= "table" then add("module", BTP and "ERROR" or "UNAVAILABLE") return end
    for _, pair in ipairs(fields) do
        if type(pair) == "table" then add(pair[1], pair[2]) end
    end
end }

SECTIONS[#SECTIONS + 1] = { "PREDICTION", function(add)
    local run = rawget(_G, "MitzuMPlusCurrentRun")
    local snap = run and call(MitzuMPlus.PredictionEngine, "GetSnapshot", run) or nil
    add("available", type(snap) == "table")
    if type(snap) == "table" then
        add("result", snap.result == "FUERA" and "OVERTIME" or snap.result)
        add("confidence", snap.confidence)
        add("hasBasis", snap.hasBasis)
        add("projectedTime", snap.projectedTime)
        add("elapsed", snap.elapsed)
        add("timeLimit", snap.timeLimit)
    end
end }

SECTIONS[#SECTIONS + 1] = { "CAPABILITIES", function(add, line)
    local RC = MitzuMPlus.RuntimeCapabilities
    local matrix = call(RC, "Matrix")
    if type(matrix) ~= "table" then add("status", "UNAVAILABLE") return end
    for _, item in ipairs(matrix) do line(item) end
end }

SECTIONS[#SECTIONS + 1] = { "INVARIANTS", function(add, line)
    local Inv = MitzuMPlus.QAInvariants
    local results = Inv and Inv:Evaluate(Inv:Gather()) or {}
    local totals = Inv and Inv:Summary(results) or {}
    add("summary", string.format("PASS=%s WARN=%s FAIL=%s SKIP=%s",
        safe().Text(totals.PASS or 0), safe().Text(totals.WARN or 0),
        safe().Text(totals.FAIL or 0), safe().Text(totals.SKIP or 0)))
    for _, item in ipairs(results) do
        line(string.format("%s %s%s", item.status, item.name,
            item.detail and (" ; " .. item.detail) or ""))
    end
end }

SECTIONS[#SECTIONS + 1] = { "RECENT EVENTS", function(add, line)
    local FR = MitzuMPlus.FlightRecorder
    add("stored", string.format("%s/%s", safe().Text(call(FR, "Count")), safe().Text(call(FR, "Capacity"))))
    for _, item in ipairs(call(FR, "Lines", BR.RECENT_EVENTS) or {}) do line(item) end
end }

SECTIONS[#SECTIONS + 1] = { "ERRORS", function(add, line)
    local EL = MitzuMPlus.ErrorLogger
    local entries = call(EL, "Entries") or {}
    add("count", #entries)
    add("debugEvents", call(EL, "DebugCount"))
    for i = math.max(1, #entries - BR.MAX_ERRORS + 1), #entries do
        local e = entries[i]
        if type(e) == "table" then
            line(string.format("[%d] x%s v%s %s", i, safe().Text(e.count or 1),
                safe().Text(e.version), safe().Text(e.msg, 400)))
        end
    end
end }

BR.SECTIONS = SECTIONS

function BR:BuildLines()
    local lines, failed = { "=== MitzuMPlus Bug Report ===" }, {}
    for _, section in ipairs(SECTIONS) do
        local name, fn, buffer = section[1], section[2], {}
        lines[#lines + 1] = ""
        lines[#lines + 1] = "[" .. name .. "]"
        local function add(k, v) buffer[#buffer + 1] = safe().Text(k, 60) .. "=" .. safe().Text(v) end
        local function line(v) buffer[#buffer + 1] = safe().Text(v, 500) end
        local ok, err = pcall(fn, add, line)
        for _, value in ipairs(buffer) do lines[#lines + 1] = value end
        if not ok then
            failed[#failed + 1] = name
            lines[#lines + 1] = "SECTION_ERROR=" .. safe().Text(err, 200)
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "sectionsFailed=" .. (#failed > 0 and table.concat(failed, ",") or "none")
    lines[#lines + 1] = "=== END ==="
    return lines, #failed
end

function BR:Build()
    local ok, lines = pcall(self.BuildLines, self)
    if not ok then return "=== MitzuMPlus Bug Report ===\nREPORT_ERROR=" .. safe().Text(lines) .. "\n=== END ===" end
    return table.concat(lines, "\n")
end

function BR:SummaryLines()
    local Inv = MitzuMPlus.QAInvariants
    local totals = Inv and Inv:Summary(Inv:Evaluate(Inv:Gather())) or {}
    return {
        string.format("v%s · lifecycle=%s · tracker=%s", safe().Text(MitzuMPlus.VERSION),
            safe().Text(call(MitzuMPlus.DungeonContext, "GetState")),
            safe().Text(call(MitzuMPlus.KeyPredictionHUD, "GetMode"))),
        string.format("invariants PASS=%s WARN=%s FAIL=%s · errors=%s · events=%s",
            safe().Text(totals.PASS or 0), safe().Text(totals.WARN or 0), safe().Text(totals.FAIL or 0),
            safe().Text(call(MitzuMPlus.ErrorLogger, "Count")),
            safe().Text(call(MitzuMPlus.FlightRecorder, "Count"))),
    }
end

function BR:Show()
    local text = self:Build()
    local EX = MitzuMPlus.Export
    local shown = EX and EX.CopyToClipboard
        and pcall(EX.CopyToClipboard, EX, text, {
            title = "MITZUMPLUS · BUG REPORT",
            hint = "Ctrl+A y Ctrl+C para copiar todo.",
            autoClose = false, mono = true,
            clearLabel = "LIMPIAR LOGS",
            onClear = function() BR:ClearLogs() end,
        })
    return shown == true, text
end

function BR:ClearLogs()
    if MitzuMPlus.FlightRecorder then MitzuMPlus.FlightRecorder:Clear() end
    local global = MitzuMPlus.db and MitzuMPlus.db.global
    if type(global) == "table" then global.errorLog = {} end
    return true
end

return BR
