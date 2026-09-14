-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - PersonalBest (v1.0)
-- Sistema de Personal Best por mazmorra y nivel de llave
--
-- Funcionalidades:
--   • PB por mazmorra (mejor tiempo en cada dungeon)
--   • PB por mazmorra + nivel (mejor +15 de Ara-Kara, etc.)
--   • PB de DPS/HPS por mazmorra
--   • Detección automática de nuevo PB al completar run
--   • Historial de PBs anteriores para ver progresión
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local PersonalBest = {}
MitzuMPlus.PersonalBest = PersonalBest

-- ─────────────────────────────────────────────────────────────────────────
-- ENSURE DB STRUCTURE
-- ─────────────────────────────────────────────────────────────────────────

local function EnsureDB()
    if not MitzuMPlus.db or not MitzuMPlus.db.global then return false end
    if not MitzuMPlus.db.global.personalBests then
        MitzuMPlus.db.global.personalBests = {}
    end
    return true
end

local function GetPBTable()
    if not EnsureDB() then return nil end
    return MitzuMPlus.db.global.personalBests
end

-- ─────────────────────────────────────────────────────────────────────────
-- KEY GENERATION
-- ─────────────────────────────────────────────────────────────────────────

local function DungeonKey(dungeonName)
    return tostring(dungeonName or "unknown"):lower():gsub("%s+", "_")
end

local function DungeonLevelKey(dungeonName, keyLevel)
    return DungeonKey(dungeonName) .. "_+" .. tostring(keyLevel or 0)
end

local function CharKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName() or ""
    return name .. "-" .. realm
end

-- ─────────────────────────────────────────────────────────────────────────
-- CHECK AND UPDATE PERSONAL BEST
-- Called after each completed run. Returns table of new PBs achieved.
-- ─────────────────────────────────────────────────────────────────────────

function PersonalBest:CheckRun(runData)
    if not runData or not EnsureDB() then return {} end

    local pb = GetPBTable()
    local charKey = CharKey()
    if not pb[charKey] then pb[charKey] = {} end
    local charPB = pb[charKey]

    local results = {}
    local dungeonName = runData.dungeonName or ""
    local keyLevel = tonumber(runData.keyLevel) or 0
    local completionTime = tonumber(runData.completionTime) or 0
    local inTime = runData.inTime and true or false

    if dungeonName == "" or completionTime <= 0 then return results end

    local dKey = DungeonKey(dungeonName)
    local dlKey = DungeonLevelKey(dungeonName, keyLevel)

    -- Stats for comparison
    local dps = 0
    local hps = 0
    if runData.stats then
        local dmg = tonumber(runData.stats.damageTotal) or 0
        local heal = tonumber(runData.stats.healingTotal) or 0
        if completionTime > 0 then
            dps = dmg / completionTime
            hps = heal / completionTime
        end
    end

    local now = time and time() or 0

    -- ── PB: Best Time per Dungeon (any level, must be in time) ──────────
    if inTime then
        if not charPB[dKey] then
            charPB[dKey] = {}
        end
        local current = charPB[dKey].bestTime
        if not current or completionTime < current.completionTime then
            local oldTime = current and current.completionTime or nil
            charPB[dKey].bestTime = {
                completionTime = completionTime,
                keyLevel       = keyLevel,
                runID          = runData.runID,
                date           = now,
                dps            = dps,
                previous       = oldTime,
            }
            results[#results + 1] = {
                type     = "best_time",
                dungeon  = dungeonName,
                keyLevel = keyLevel,
                newValue = completionTime,
                oldValue = oldTime,
            }
        end
    end

    -- ── PB: Highest Key per Dungeon (in time) ──────────────────────────
    if inTime then
        if not charPB[dKey] then charPB[dKey] = {} end
        local current = charPB[dKey].highestKey
        if not current or keyLevel > current.keyLevel then
            local oldKey = current and current.keyLevel or nil
            charPB[dKey].highestKey = {
                keyLevel       = keyLevel,
                completionTime = completionTime,
                runID          = runData.runID,
                date           = now,
                previous       = oldKey,
            }
            results[#results + 1] = {
                type     = "highest_key",
                dungeon  = dungeonName,
                keyLevel = keyLevel,
                newValue = keyLevel,
                oldValue = oldKey,
            }
        end
    end

    -- ── PB: Best Time per Dungeon+Level ─────────────────────────────────
    if inTime then
        if not charPB[dlKey] then charPB[dlKey] = {} end
        local current = charPB[dlKey].bestTime
        if not current or completionTime < current.completionTime then
            local oldTime = current and current.completionTime or nil
            charPB[dlKey].bestTime = {
                completionTime = completionTime,
                runID          = runData.runID,
                date           = now,
                previous       = oldTime,
            }
            results[#results + 1] = {
                type     = "best_time_level",
                dungeon  = dungeonName,
                keyLevel = keyLevel,
                newValue = completionTime,
                oldValue = oldTime,
            }
        end
    end

    -- ── PB: Best DPS per Dungeon ────────────────────────────────────────
    if dps > 0 then
        if not charPB[dKey] then charPB[dKey] = {} end
        local current = charPB[dKey].bestDPS
        if not current or dps > current.dps then
            local oldDPS = current and current.dps or nil
            charPB[dKey].bestDPS = {
                dps            = dps,
                keyLevel       = keyLevel,
                completionTime = completionTime,
                runID          = runData.runID,
                date           = now,
                previous       = oldDPS,
            }
            results[#results + 1] = {
                type     = "best_dps",
                dungeon  = dungeonName,
                keyLevel = keyLevel,
                newValue = dps,
                oldValue = oldDPS,
            }
        end
    end

    -- ── PB: Best HPS per Dungeon (healers) ──────────────────────────────
    if hps > 0 and runData.playerRole == "HEALER" then
        if not charPB[dKey] then charPB[dKey] = {} end
        local current = charPB[dKey].bestHPS
        if not current or hps > current.hps then
            local oldHPS = current and current.hps or nil
            charPB[dKey].bestHPS = {
                hps            = hps,
                keyLevel       = keyLevel,
                completionTime = completionTime,
                runID          = runData.runID,
                date           = now,
                previous       = oldHPS,
            }
            results[#results + 1] = {
                type     = "best_hps",
                dungeon  = dungeonName,
                keyLevel = keyLevel,
                newValue = hps,
                oldValue = oldHPS,
            }
        end
    end

    -- ── PB: Zero Deaths Run ─────────────────────────────────────────────
    if inTime and runData.stats and (tonumber(runData.stats.deaths) or 0) == 0 then
        if not charPB[dKey] then charPB[dKey] = {} end
        if not charPB[dKey].flawlessHighest or keyLevel > charPB[dKey].flawlessHighest.keyLevel then
            charPB[dKey].flawlessHighest = {
                keyLevel = keyLevel,
                runID    = runData.runID,
                date     = now,
            }
            results[#results + 1] = {
                type     = "flawless",
                dungeon  = dungeonName,
                keyLevel = keyLevel,
            }
        end
    end

    return results
end

-- ─────────────────────────────────────────────────────────────────────────
-- QUERY PBs
-- ─────────────────────────────────────────────────────────────────────────

function PersonalBest:GetDungeonPB(dungeonName, charOverride)
    if not EnsureDB() then return nil end
    local charKey = charOverride or CharKey()
    local pb = GetPBTable()
    if not pb[charKey] then return nil end
    return pb[charKey][DungeonKey(dungeonName)]
end

function PersonalBest:GetDungeonLevelPB(dungeonName, keyLevel, charOverride)
    if not EnsureDB() then return nil end
    local charKey = charOverride or CharKey()
    local pb = GetPBTable()
    if not pb[charKey] then return nil end
    return pb[charKey][DungeonLevelKey(dungeonName, keyLevel)]
end

function PersonalBest:GetAllDungeonPBs(charOverride)
    if not EnsureDB() then return {} end
    local charKey = charOverride or CharKey()
    local pb = GetPBTable()
    if not pb[charKey] then return {} end

    local result = {}
    for key, data in pairs(pb[charKey]) do
        if not key:find("_%+%d") then
            result[key] = data
        end
    end
    return result
end

function PersonalBest:GetAllCharacters()
    if not EnsureDB() then return {} end
    local pb = GetPBTable()
    local chars = {}
    for charKey in pairs(pb) do
        chars[#chars + 1] = charKey
    end
    table.sort(chars)
    return chars
end

-- ─────────────────────────────────────────────────────────────────────────
-- REBUILD PBs FROM EXISTING DATA
-- Call once after upgrade to recalculate PBs from all stored runs.
-- ─────────────────────────────────────────────────────────────────────────

function PersonalBest:RebuildFromHistory()
    if not EnsureDB() then return 0 end
    MitzuMPlus.db.global.personalBests = {}

    local runs = MitzuMPlus:GetAllRuns() or {}
    local count = 0
    for _, run in ipairs(runs) do
        local results = self:CheckRun(run)
        count = count + #results
    end
    return count
end

-- ─────────────────────────────────────────────────────────────────────────
-- ANNOUNCE NEW PBs
-- ─────────────────────────────────────────────────────────────────────────

-- ═════════════════════════════════════════════════════════════════════════
-- AVISOS (v7.9.0)
--
-- Las casillas de NOTIFICACIONES escribian en la base de datos y NADIE las
-- leia: eran interruptores conectados a nada. El panel las guarda al nivel de
-- profile, pero un perfil viejo puede tenerlas bajo settings, asi que se miran
-- los dos sitios — el mismo patron que Init.lua ya usa para shareData.
--
-- Por defecto encendidas (~= false), que es como las lee el panel: quien nunca
-- toco la casilla sigue viendo lo de siempre.
-- ═════════════════════════════════════════════════════════════════════════
function MitzuMPlus:NotifyEnabled(key)
    local db = self.db and self.db.profile
    if not db then return true end
    if db[key] ~= nil then return db[key] ~= false end
    local st = db.settings
    if st and st[key] ~= nil then return st[key] ~= false end
    return true
end

function PersonalBest:AnnounceResults(results)
    if not results or #results == 0 then return end

    -- "Nuevo record" es subir de nivel de llave; "Marca personal" cubre
    -- tiempo/DPS/HPS/flawless. Cada interruptor controla tanto el mensaje de
    -- chat como el aviso visual correspondiente.
    local wantRecord = MitzuMPlus:NotifyEnabled("notifyNewRecord")
    local wantPB     = MitzuMPlus:NotifyEnabled("notifyPersonalBest")
    local recordToast, personalToast

    for _, pb in ipairs(results) do
        local wanted = (pb.type == "highest_key") and wantRecord or wantPB
        local msg = ""
        if pb.type == "highest_key" then
            msg = string.format(
                "|cFF21de66NUEVO RECORD!|r Mejor llave en %s: |cFFe8b84a+%d|r",
                pb.dungeon, pb.newValue)
            if pb.oldValue then
                msg = msg .. string.format(" (anterior: +%d)", pb.oldValue)
            end
        elseif pb.type == "best_time" then
            local newT = MitzuMPlus.FormatTime and MitzuMPlus:FormatTime(pb.newValue) or tostring(pb.newValue)
            msg = string.format(
                "|cFF21de66NUEVO PB!|r Mejor tiempo en %s: |cFFe8b84a%s|r",
                pb.dungeon, newT)
            if pb.oldValue then
                local diff = pb.oldValue - pb.newValue
                local diffT = MitzuMPlus.FormatTime and MitzuMPlus:FormatTime(diff) or tostring(diff)
                msg = msg .. string.format(" (|cFF21de66-%s|r)", diffT)
            end
        elseif pb.type == "best_time_level" then
            -- Este resultado existia desde CheckRun(), pero no tenia rama de
            -- anuncio y por tanto podia quedar completamente silencioso.
            local newT = MitzuMPlus.FormatTime and MitzuMPlus:FormatTime(pb.newValue) or tostring(pb.newValue)
            msg = string.format(
                "|cFF21de66NUEVO PB!|r Mejor tiempo en %s +%d: |cFFe8b84a%s|r",
                pb.dungeon, pb.keyLevel or 0, newT)
            if pb.oldValue then
                local diff = pb.oldValue - pb.newValue
                local diffT = MitzuMPlus.FormatTime and MitzuMPlus:FormatTime(diff) or tostring(diff)
                msg = msg .. string.format(" (|cFF21de66-%s|r)", diffT)
            end
        elseif pb.type == "best_dps" then
            local fn = MitzuMPlus.FormatNumber and function(v) return MitzuMPlus:FormatNumber(v) end or tostring
            msg = string.format(
                "|cFF21de66NUEVO PB DPS!|r %s: |cFFe8b84a%s|r DPS",
                pb.dungeon, fn(math.floor(pb.newValue)))
        elseif pb.type == "best_hps" then
            local fn = MitzuMPlus.FormatNumber and function(v) return MitzuMPlus:FormatNumber(v) end or tostring
            msg = string.format(
                "|cFF21de66NUEVO PB HPS!|r %s: |cFFe8b84a%s|r HPS",
                pb.dungeon, fn(math.floor(pb.newValue)))
        elseif pb.type == "flawless" then
            msg = string.format(
                "|cFF21de66FLAWLESS!|r %s +%d completada sin muertes",
                pb.dungeon, pb.keyLevel)
        end

        if wanted and msg ~= "" then
            if MitzuMPlus.Print then MitzuMPlus:Print(msg) end
            if pb.type == "highest_key" then
                recordToast = recordToast or msg
            else
                personalToast = personalToast or msg
            end
        end
    end

    -- Como una sola run puede disparar varias marcas a la vez, se limita a un
    -- toast por categoria. ShowToast mantiene una cola para no pisarlos entre
    -- si ni pisar el aviso de run completada.
    if recordToast and MitzuMPlus.ShowToast then
        MitzuMPlus:ShowToast(recordToast, "record", 4, true)
    end
    if personalToast and MitzuMPlus.ShowToast then
        MitzuMPlus:ShowToast(personalToast, "personal", 4, true)
    end

    if MitzuMPlus.EventBus then
        MitzuMPlus.EventBus:Emit("PERSONAL_BEST_ACHIEVED", results)
    end
end

return PersonalBest
