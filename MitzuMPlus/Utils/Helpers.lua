-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Helper Utilities
-- Funciones auxiliares generales
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local Helpers = {}
MitzuMPlus.Helpers = Helpers

-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

function Helpers:TableCopy(original)
    local copy = {}
    for k, v in pairs(original) do
        if type(v) == "table" then
            copy[k] = self:TableCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

function Helpers:TableCount(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function Helpers:TableContains(tbl, value)
    for _, v in pairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

function Helpers:TableFilter(tbl, predicate)
    local result = {}
    for k, v in pairs(tbl) do
        if predicate(v, k) then
            result[k] = v
        end
    end
    return result
end

function Helpers:TableMap(tbl, mapper)
    local result = {}
    for k, v in pairs(tbl) do
        result[k] = mapper(v, k)
    end
    return result
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STRING UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

function Helpers:Trim(str)
    if not str then return "" end
    return str:match("^%s*(.-)%s*$")
end

function Helpers:Split(str, delimiter)
    local result = {}
    local pattern = string.format("([^%s]+)", delimiter)
    for match in str:gmatch(pattern) do
        table.insert(result, match)
    end
    return result
end

function Helpers:StartsWith(str, prefix)
    return str:sub(1, #prefix) == prefix
end

function Helpers:EndsWith(str, suffix)
    return suffix == "" or str:sub(-#suffix) == suffix
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MATH UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

function Helpers:Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

function Helpers:Round(value, decimals)
    decimals = decimals or 0
    local mult = 10^decimals
    return math.floor(value * mult + 0.5) / mult
end

function Helpers:Lerp(a, b, t)
    return a + (b - a) * t
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FRAME UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

function Helpers:CreateFrame(frameType, parent, name, inherits)
    return CreateFrame(frameType, name, parent, inherits)
end

function Helpers:HideFrame(frame)
    if frame and frame.Hide then
        frame:Hide()
    end
end

function Helpers:ShowFrame(frame)
    if frame and frame.Show then
        frame:Show()
    end
end

function Helpers:SetFrameAlpha(frame, alpha)
    if frame and frame.SetAlpha then
        frame:SetAlpha(alpha)
    end
end

function Helpers:ClearAllPoints(frame)
    if frame and frame.ClearAllPoints then
        frame:ClearAllPoints()
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TEXTURE UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

function Helpers:SetTexture(texture, path)
    if texture and texture.SetTexture then
        texture:SetTexture(path)
    end
end

function Helpers:SetVertexColor(texture, r, g, b, a)
    if texture and texture.SetVertexColor then
        texture:SetVertexColor(r, g, b, a or 1.0)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FONTSTRING UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

function Helpers:SetText(fontString, text)
    if fontString and fontString.SetText then
        fontString:SetText(text or "")
    end
end

function Helpers:SetTextColor(fontString, r, g, b, a)
    if fontString and fontString.SetTextColor then
        fontString:SetTextColor(r, g, b, a or 1.0)
    end
end

function Helpers:SetFont(fontString, path, size, flags)
    if fontString and fontString.SetFont then
        fontString:SetFont(path, size, flags or "")
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PLAYER UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

function Helpers:GetPlayerName()
    return UnitName("player")
end

function Helpers:GetPlayerClass()
    local _, class = UnitClass("player")
    return class
end

function Helpers:GetPlayerGUID()
    return UnitGUID("player")
end

function Helpers:GetPlayerSpecialization()
    -- Ruta 1: PlayerUtil (TWW 11.0.2+ y Midnight 12.0+)
    local specID
    if PlayerUtil and PlayerUtil.GetCurrentSpecID then
        specID = PlayerUtil.GetCurrentSpecID()
    end

    -- Ruta 2: GetSpecialization() devuelve ÍNDICE → convertir a specID
    if (not specID or specID == 0) and GetSpecialization then
        local specIndex = GetSpecialization()
        if specIndex and specIndex > 0 and GetSpecializationInfo then
            specID = GetSpecializationInfo(specIndex)
        end
    end

    -- Obtener nombre de spec a partir del specID
    if specID and specID > 0 and GetSpecializationInfoByID then
        local _, name = GetSpecializationInfoByID(specID)
        return name or "Unknown", specID
    end

    return "Unknown", 0
end

function Helpers:GetPlayerItemLevel()
    -- API-4 FIX: C_PaperDollInfo.GetAverageItemLevels() preferida en Midnight.
    if C_PaperDollInfo and C_PaperDollInfo.GetAverageItemLevels then
        local total, equipped = C_PaperDollInfo.GetAverageItemLevels()
        return math.floor(equipped or total or 0)
    elseif GetAverageItemLevel then
        local total, equipped = GetAverageItemLevel()
        return math.floor(equipped or total or 0)
    end
    return 0
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DUNGEON UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

function Helpers:GetActiveChallengeMapID()
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        return C_ChallengeMode.GetActiveChallengeMapID()
    end
    return nil
end

function Helpers:GetMapUIInfo(mapID)
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        return C_ChallengeMode.GetMapUIInfo(mapID)
    end
    return nil, nil
end

function Helpers:GetActiveKeystoneLevel()
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        return C_ChallengeMode.GetActiveKeystoneInfo()
    end
    return 0
end

-- ═══════════════════════════════════════════════════════════════════════════
-- AFFIX UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

function Helpers:GetCurrentAffixes()
    -- API-9 FIX: C_MythicPlus.GetCurrentAffixes() cambió su retorno en TWW.
    -- Antes (pre-TWW): devolvía array de { id=N, name="...", description="..." }.
    -- Desde TWW / Midnight: devuelve array de { id=N } únicamente.
    -- El nombre se obtiene por separado vía C_ChallengeMode.GetAffixInfo(id).
    local affixes = {}
    if not (C_MythicPlus and C_MythicPlus.GetCurrentAffixes) then return affixes end

    local raw = C_MythicPlus.GetCurrentAffixes()
    if type(raw) ~= "table" then return affixes end

    for _, entry in ipairs(raw) do
        local id = type(entry) == "table" and entry.id or tonumber(entry)
        if id then
            local name, desc
            if C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
                name, desc = C_ChallengeMode.GetAffixInfo(id)
            end
            table.insert(affixes, {
                id   = id,
                name = name or ("Afijo " .. tostring(id)),
                description = desc or "",
            })
        end
    end
    return affixes
end

-- ═══════════════════════════════════════════════════════════════════════════
-- COMBAT UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

function Helpers:IsInCombat()
    return InCombatLockdown()
end

function Helpers:IsInInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance, instanceType
end

function Helpers:IsInMythicPlus()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then return false end
    
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local mapID = C_ChallengeMode.GetActiveChallengeMapID()
        return mapID ~= nil
    end
    
    return false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TIME UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

function Helpers:GetCurrentTime()
    return time()
end

function Helpers:GetServerTime()
    return GetServerTime()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SORT UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

function Helpers:SortByKey(tbl, key, descending)
    table.sort(tbl, function(a, b)
        if descending then
            return (a[key] or 0) > (b[key] or 0)
        else
            return (a[key] or 0) < (b[key] or 0)
        end
    end)
    return tbl
end

function Helpers:SortByFunc(tbl, sortFunc)
    table.sort(tbl, sortFunc)
    return tbl
end

-- ═══════════════════════════════════════════════════════════════════════════
-- VALIDATION UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

function Helpers:IsValidRun(run)
    return run and run.dungeonID and run.completionTime and run.startTime
end

function Helpers:IsPositiveNumber(value)
    return type(value) == "number" and value > 0
end

function Helpers:IsNonEmptyString(value)
    return type(value) == "string" and value ~= ""
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DEBUG UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

function Helpers:Debug(...)
    if MitzuMPlus.db and MitzuMPlus.db.profile and MitzuMPlus.db.profile.settings and MitzuMPlus.db.profile.settings.debugMode then
        print("|cFFe8b84a[MitzuMPlus Debug]|r", ...)
    end
end

function Helpers:DumpTable(tbl, indent)
    indent = indent or 0
    local spacing = string.rep("  ", indent)
    
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            print(spacing .. tostring(k) .. " = {")
            self:DumpTable(v, indent + 1)
            print(spacing .. "}")
        else
            print(spacing .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- RUN STAT HELPERS (v4.0.0)
-- Fuente única de verdad para cálculos derivados de stats de runs.
-- Todos los paneles UI deben usar estas funciones en vez de calcular inline.
-- ═══════════════════════════════════════════════════════════════════════════

--- Calcula el DPS real de una run (daño total / tiempo de completado).
--- @param run table — datos de la run
--- @return number — DPS en daño por segundo, 0 si no hay datos válidos
function Helpers:GetRunDPS(run)
    if not run or not run.stats then return 0 end
    local dmg = tonumber(run.stats.damageTotal) or 0
    local ct  = tonumber(run.completionTime) or 0
    if ct > 0 and dmg > 0 then
        return dmg / ct
    end
    return 0
end

--- Calcula el HPS real de una run (healing total / tiempo de completado).
--- @param run table — datos de la run
--- @return number — HPS en healing por segundo, 0 si no hay datos válidos
function Helpers:GetRunHPS(run)
    if not run or not run.stats then return 0 end
    local heal = tonumber(run.stats.healingTotal) or 0
    local ct   = tonumber(run.completionTime) or 0
    if ct > 0 and heal > 0 then
        return heal / ct
    end
    return 0
end

--- Calcula el DTPS real de una run (daño recibido / tiempo de completado).
--- @param run table — datos de la run
--- @return number — DTPS en daño recibido por segundo
function Helpers:GetRunDTPS(run)
    if not run or not run.stats then return 0 end
    local dmgTaken = tonumber(run.stats.damageTaken) or tonumber(run.stats.tankDamageTakenEffective) or 0
    local ct = tonumber(run.completionTime) or 0
    if ct > 0 and dmgTaken > 0 then
        return dmgTaken / ct
    end
    return 0
end

--- Calcula el DPS promedio de una lista de runs.
--- @param runs table — array de runs
--- @param maxRuns number|nil — límite de runs a promediar (nil = todas)
--- @return number avgDPS, number count
function Helpers:GetAverageDPS(runs, maxRuns)
    if not runs or #runs == 0 then return 0, 0 end
    local sum, count = 0, 0
    for _, run in ipairs(runs) do
        local dps = self:GetRunDPS(run)
        if dps > 0 then
            sum = sum + dps
            count = count + 1
            if maxRuns and count >= maxRuns then break end
        end
    end
    return count > 0 and (sum / count) or 0, count
end

--- Indica si una run tiene datos limitados (Midnight sin CLEU).
--- Útil para mostrar indicadores en la UI.
--- @param run table
--- @return boolean
function Helpers:IsLimitedData(run)
    if not run then return true end
    return run.dataSource == "C_DamageMeter"
end

--- Indica qué métricas están disponibles según la fuente de datos.
--- @param run table
--- @return table — { hasPeakDPS=bool, hasHealBreakdown=bool, hasTankAvoidance=bool, ... }
function Helpers:GetAvailableMetrics(run)
    local limited = self:IsLimitedData(run)
    return {
        hasDamageTotal     = true,  -- siempre (CLEU o meter)
        hasHealingTotal    = true,  -- siempre
        hasDeaths          = true,  -- siempre (CLEU event o health polling)
        hasKicks           = true,  -- siempre (CLEU o meter.interrupts)
        hasDispels         = true,  -- siempre (CLEU o meter.dispels)
        hasPeakDPS         = not limited,  -- solo CLEU (ventana 10s)
        hasHealBreakdown   = not limited,  -- overheal, group/self, absorbs
        hasCastEfficiency  = not limited,  -- solo CLEU
        hasCrisisEvents    = not limited,  -- solo CLEU
        hasHealCDUptime    = not limited,  -- solo CLEU (aura tracking)
        hasTankAvoidance   = not limited,  -- parry/dodge/block/miss
        hasTankDefensiveUp = not limited,  -- defensive CD uptime
        hasTankMitigation  = not limited,  -- damage mitigated (absorbs)
        hasTimeline        = not limited,  -- kicks/brez/death events
    }
end

return Helpers
