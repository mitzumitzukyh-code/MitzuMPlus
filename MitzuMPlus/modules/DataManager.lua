-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - DataManager (v1.0)
-- Data integrity, backup, purge, multi-character filtering
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local L = MitzuMPlus.L

local DataManager = {}
MitzuMPlus.DataManager = DataManager

-- ─────────────────────────────────────────────────────────────────────────
-- MULTI-CHARACTER: Get unique characters from run history
-- ─────────────────────────────────────────────────────────────────────────

function DataManager:GetCharacters()
    local runs = MitzuMPlus:GetAllRuns() or {}
    local chars = {}
    local seen  = {}

    for _, run in ipairs(runs) do
        local name  = run.playerName  or ""
        local realm = run.playerRealm or ""
        local class = run.playerClass or ""
        local key   = name .. "-" .. realm

        if name ~= "" and not seen[key] then
            seen[key] = true
            local runCount = 0
            local bestKey  = 0
            for _, r in ipairs(runs) do
                local rk = (r.playerName or "") .. "-" .. (r.playerRealm or "")
                if rk == key then
                    runCount = runCount + 1
                    local kl = tonumber(r.keyLevel) or 0
                    if kl > bestKey then bestKey = kl end
                end
            end

            chars[#chars + 1] = {
                name     = name,
                realm    = realm,
                class    = class,
                key      = key,
                runCount = runCount,
                bestKey  = bestKey,
            }
        end
    end

    table.sort(chars, function(a, b) return a.runCount > b.runCount end)
    return chars
end

-- ─────────────────────────────────────────────────────────────────────────
-- MULTI-CHARACTER: Filter runs by character
-- ─────────────────────────────────────────────────────────────────────────

function DataManager:GetRunsByCharacter(charKey)
    if not charKey or charKey == "" then
        return MitzuMPlus:GetAllRuns()
    end

    local runs = MitzuMPlus:GetAllRuns() or {}
    local filtered = {}

    for _, run in ipairs(runs) do
        local rk = (run.playerName or "") .. "-" .. (run.playerRealm or "")
        if rk == charKey then
            filtered[#filtered + 1] = run
        end
    end

    return filtered
end

-- ─────────────────────────────────────────────────────────────────────────
-- DATA INTEGRITY: Validate all stored runs
-- ─────────────────────────────────────────────────────────────────────────

function DataManager:ValidateAllRuns()
    if not MitzuMPlus.db or not MitzuMPlus.db.global then return 0, 0 end

    local runs = MitzuMPlus.db.global.runs or {}
    local valid   = 0
    local invalid = 0
    local corrupt = {}

    for runID, run in pairs(runs) do
        if type(run) ~= "table" then
            corrupt[#corrupt + 1] = runID
            invalid = invalid + 1
        elseif not run.dungeonName or run.dungeonName == ""
            or not run.keyLevel or tonumber(run.keyLevel) == nil
            or not run.startTime or tonumber(run.startTime) == nil
            or not run.completionTime or tonumber(run.completionTime) == nil then
            corrupt[#corrupt + 1] = runID
            invalid = invalid + 1
        else
            valid = valid + 1
        end
    end

    return valid, invalid, corrupt
end

-- ─────────────────────────────────────────────────────────────────────────
-- DATA INTEGRITY: Remove corrupt runs
-- ─────────────────────────────────────────────────────────────────────────

function DataManager:RemoveCorruptRuns()
    local valid, invalid, corrupt = self:ValidateAllRuns()
    if invalid == 0 then return 0 end

    for _, runID in ipairs(corrupt) do
        MitzuMPlus.db.global.runs[runID] = nil
    end

    if MitzuMPlus.Print then
        MitzuMPlus:Print(string.format(
            L["MSG_PURGE_CORRUPT"],
            invalid, valid))
    end

    return invalid
end

-- ─────────────────────────────────────────────────────────────────────────
-- PURGE: Remove old runs beyond limit
-- ─────────────────────────────────────────────────────────────────────────

function DataManager:EnforceRunLimit()
    if not MitzuMPlus.db or not MitzuMPlus.db.global then return 0 end

    local maxRuns = (MitzuMPlus.Constants and MitzuMPlus.Constants.MAX_RUNS_STORED) or 1000
    local runs = MitzuMPlus:GetAllRuns() or {}

    if #runs <= maxRuns then return 0 end

    -- Runs already sorted newest→oldest by GetAllRuns()
    local purged = 0
    for i = maxRuns + 1, #runs do
        local run = runs[i]
        if run and run.runID and not run.isFavorite then
            MitzuMPlus.db.global.runs[run.runID] = nil
            purged = purged + 1
        end
    end

    if purged > 0 and MitzuMPlus.Print then
        MitzuMPlus:Print(string.format(
            L["MSG_PURGE_OLD"],
            purged, maxRuns))
    end

    return purged
end

-- ─────────────────────────────────────────────────────────────────────────
-- PURGE: Remove runs older than N days
-- ─────────────────────────────────────────────────────────────────────────

function DataManager:PurgeOlderThan(days)
    if not MitzuMPlus.db or not MitzuMPlus.db.global then return 0 end

    local cutoff = (time and time() or 0) - (days * 86400)
    local purged = 0

    for runID, run in pairs(MitzuMPlus.db.global.runs or {}) do
        if type(run) == "table" and not run.isFavorite then
            local st = tonumber(run.startTime) or 0
            if st > 0 and st < cutoff then
                MitzuMPlus.db.global.runs[runID] = nil
                purged = purged + 1
            end
        end
    end

    return purged
end

-- ─────────────────────────────────────────────────────────────────────────
-- BACKUP: Save a snapshot of current data
-- ─────────────────────────────────────────────────────────────────────────

function DataManager:CreateBackup()
    if not MitzuMPlus.db or not MitzuMPlus.db.global then return false end

    if not MitzuMPlus.db.global.backups then
        MitzuMPlus.db.global.backups = {}
    end

    -- Keep max 3 backups
    while #MitzuMPlus.db.global.backups >= 3 do
        table.remove(MitzuMPlus.db.global.backups, 1)
    end

    local runCount = 0
    for _ in pairs(MitzuMPlus.db.global.runs or {}) do
        runCount = runCount + 1
    end

    MitzuMPlus.db.global.backups[#MitzuMPlus.db.global.backups + 1] = {
        date     = time and time() or 0,
        runCount = runCount,
        version  = MitzuMPlus.VERSION or "unknown",
    }

    return true
end

-- ─────────────────────────────────────────────────────────────────────────
-- NOTES & TAGS for runs
-- ─────────────────────────────────────────────────────────────────────────

local function FindStoredRun(runID)
    if not MitzuMPlus.db or not MitzuMPlus.db.global then return nil end
    runID = tonumber(runID)
    if not runID then return nil end
    for _, run in pairs(MitzuMPlus.db.global.runs or {}) do
        if type(run) == "table" and tonumber(run.runID) == runID then return run end
    end
    return nil
end

function DataManager:SetRunNotes(runID, notes)
    if not MitzuMPlus.db or not MitzuMPlus.db.global then return false end
    local run = FindStoredRun(runID)
    if not run then return false end
    run.notes = tostring(notes or "")
    return true
end

function DataManager:GetRunNotes(runID)
    if not MitzuMPlus.db or not MitzuMPlus.db.global then return "" end
    local run = FindStoredRun(runID)
    return run and run.notes or ""
end

function DataManager:SetRunTags(runID, tags)
    if not MitzuMPlus.db or not MitzuMPlus.db.global then return false end
    local run = FindStoredRun(runID)
    if not run then return false end
    if type(tags) == "string" then
        -- Parse comma-separated tags
        local parsed = {}
        for tag in tags:gmatch("[^,]+") do
            tag = tag:match("^%s*(.-)%s*$")
            if tag ~= "" then
                parsed[#parsed + 1] = tag:lower()
            end
        end
        tags = parsed
    end
    run.tags = tags or {}
    return true
end

function DataManager:GetRunTags(runID)
    if not MitzuMPlus.db or not MitzuMPlus.db.global then return {} end
    local run = FindStoredRun(runID)
    return run and run.tags or {}
end

function DataManager:ToggleFavorite(runID)
    if not MitzuMPlus.db or not MitzuMPlus.db.global then return false end
    local run = FindStoredRun(runID)
    if not run then return false end
    run.isFavorite = not run.isFavorite
    return run.isFavorite
end

-- ─────────────────────────────────────────────────────────────────────────
-- GET ALL UNIQUE TAGS (for filter dropdowns)
-- ─────────────────────────────────────────────────────────────────────────

function DataManager:GetAllTags()
    local runs = MitzuMPlus:GetAllRuns() or {}
    local tagSet = {}

    for _, run in ipairs(runs) do
        if run.tags and type(run.tags) == "table" then
            for _, tag in ipairs(run.tags) do
                tagSet[tag] = (tagSet[tag] or 0) + 1
            end
        end
    end

    local result = {}
    for tag, count in pairs(tagSet) do
        result[#result + 1] = { tag = tag, count = count }
    end
    table.sort(result, function(a, b) return a.count > b.count end)

    return result
end

return DataManager
