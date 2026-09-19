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
    local byKey, chars = {}, {}

    -- Una sola pasada: la version anterior hacia un segundo loop por cada
    -- personaje y escalaba O(n^2) con historiales grandes.
    for _, run in ipairs(runs) do
        local name  = run.playerName  or ""
        local realm = run.playerRealm or ""
        if name ~= "" then
            local key = name .. "-" .. realm
            local entry = byKey[key]
            if not entry then
                entry = {
                    name = name, realm = realm, class = run.playerClass or "",
                    key = key, runCount = 0, bestKey = 0,
                }
                byKey[key] = entry
                chars[#chars + 1] = entry
            end
            entry.runCount = entry.runCount + 1
            entry.bestKey = math.max(entry.bestKey, tonumber(run.keyLevel) or 0)
        end
    end

    table.sort(chars, function(a, b)
        if a.runCount == b.runCount then return a.key < b.key end
        return a.runCount > b.runCount
    end)
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
    if not MitzuMPlus.db or not MitzuMPlus.db.global then return 0, 0, {} end

    local valid, invalid, corrupt = 0, 0, {}
    for runID, run in pairs(MitzuMPlus.db.global.runs or {}) do
        local ok = type(run) == "table"
            and (tonumber(run.dungeonID) or 0) > 0
            and (tonumber(run.keyLevel) or 0) >= 2
            and (tonumber(run.startTime) or 0) > 0
        if ok then
            valid = valid + 1
        else
            invalid = invalid + 1
            corrupt[#corrupt + 1] = runID
        end
    end
    return valid, invalid, corrupt
end

-- Reparar tablas antiguas cuando sea seguro y mover a cuarentena, nunca
-- borrar, lo que no cumpla la identidad minima de una run.
function DataManager:RepairAndQuarantineRuns()
    if not MitzuMPlus.db or not MitzuMPlus.db.global then return 0, 0 end
    local g = MitzuMPlus.db.global
    g.runs = type(g.runs) == "table" and g.runs or {}
    g.quarantineRuns = type(g.quarantineRuns) == "table" and g.quarantineRuns or {}

    local repaired, quarantine = 0, {}
    for runID, run in pairs(g.runs) do
        if type(run) == "table" then
            -- Sanitize solo normaliza tipos/campos; no inventa identidad valida.
            if type(MitzuMPlus.SanitizeRunData) == "function" then
                MitzuMPlus:SanitizeRunData(run)
            end
            local ok = (tonumber(run.dungeonID) or 0) > 0
                and (tonumber(run.keyLevel) or 0) >= 2
                and (tonumber(run.startTime) or 0) > 0
            if ok then
                if not run.dungeonName or run.dungeonName == "" then
                    local name
                    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
                        local success, value = pcall(C_ChallengeMode.GetMapUIInfo, run.dungeonID)
                        if success then name = value end
                    end
                    if name and name ~= "" then
                        run.dungeonName = name
                        repaired = repaired + 1
                    end
                    -- Si la API aun no esta lista al login, conservar la run.
                    -- El nombre se puede recuperar mas tarde; la identidad
                    -- dungeonID/key/startTime ya es suficiente para no perderla.
                end
            else
                quarantine[#quarantine + 1] = { id = runID, reason = "invalid identity" }
            end
        else
            quarantine[#quarantine + 1] = { id = runID, reason = "run is not a table" }
        end
    end

    if #quarantine > 0 and MitzuMPlus.CreateDatabaseBackup then
        MitzuMPlus:CreateDatabaseBackup("pre-quarantine")
    end
    for _, item in ipairs(quarantine) do
        local runID = item.id
        g.quarantineRuns[#g.quarantineRuns + 1] = {
            runID = runID, reason = item.reason,
            quarantinedAt = time and time() or 0,
            data = g.runs[runID],
        }
        g.runs[runID] = nil
    end

    if #quarantine > 0 and MitzuMPlus.Print then
        local msg = L["MSG_QUARANTINE_CORRUPT"] or "%d invalid runs moved to quarantine; %d valid runs kept."
        local valid = 0; for _ in pairs(g.runs) do valid = valid + 1 end
        MitzuMPlus:Print(string.format(msg, #quarantine, valid))
    end
    return repaired, #quarantine
end

-- Compatibilidad con callers antiguos: el nombre historico ya no elimina datos.
function DataManager:RemoveCorruptRuns()
    local _, quarantined = self:RepairAndQuarantineRuns()
    return quarantined
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

function DataManager:CreateBackup(reason)
    if MitzuMPlus.CreateDatabaseBackup then
        return MitzuMPlus:CreateDatabaseBackup(reason or "manual")
    end
    return false
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
