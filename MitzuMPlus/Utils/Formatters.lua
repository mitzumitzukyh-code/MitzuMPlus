-- ===========================================================================
-- MitzuMPlus M+ Historial - Formatters Utility
-- Funciones de formateo de números, tiempo, fechas
-- ===========================================================================

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local L = MitzuMPlus.L

local Formatters = {}
MitzuMPlus.Formatters = Formatters

-- ===========================================================================
-- TIME FORMATTING
-- ===========================================================================

function Formatters:FormatTime(seconds, format)
    if not seconds or seconds < 0 then return "00:00" end
    
    format = format or "MM:SS"
    
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    
    if format == "HH:MM:SS" then
        return string.format("%02d:%02d:%02d", hours, mins, secs)
    elseif format == "seconds" then
        return tostring(math.floor(seconds))
    else
        return string.format("%02d:%02d", mins, secs)
    end
end

function Formatters:FormatTimeDelta(delta)
    if not delta then return "" end
    
    local sign = delta >= 0 and "+" or ""
    local absDelta = math.abs(delta)
    
    local mins = math.floor(absDelta / 60)
    local secs = math.floor(absDelta % 60)
    
    return string.format("%s%d:%02d", sign, mins, secs)
end

-- ===========================================================================
-- NUMBER FORMATTING
-- ===========================================================================

function Formatters:FormatNumber(num, decimals)
    if not num then return "0" end
    decimals = decimals or 0
    
    local formatted = string.format("%." .. decimals .. "f", num)
    
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    
    return formatted
end

function Formatters:FormatDPS(dps, format)
    if not dps or dps == 0 then return "0" end
    
    format = format or "k"
    
    if format == "full" then
        return self:FormatNumber(dps, 0)
    elseif format == "K" then
        if dps >= 1000000 then
            return string.format("%.1fM", dps / 1000000)
        elseif dps >= 1000 then
            return string.format("%.1fK", dps / 1000)
        else
            return tostring(math.floor(dps))
        end
    else
        if dps >= 1000000 then
            return string.format("%.1fM", dps / 1000000)
        elseif dps >= 1000 then
            return string.format("%.1fk", dps / 1000)
        else
            return tostring(math.floor(dps))
        end
    end
end

function Formatters:FormatPercent(value, decimals)
    if not value then return "0%" end
    decimals = decimals or 1
    
    return string.format("%." .. decimals .. "f%%", value * 100)
end

function Formatters:FormatDelta(current, baseline)
    if not current or not baseline or baseline == 0 then return "" end
    
    local delta = ((current - baseline) / baseline) * 100
    local sign = delta >= 0 and "+" or ""
    
    return string.format("%s%.1f%%", sign, delta)
end

-- ===========================================================================
-- DATE FORMATTING
-- ===========================================================================

function Formatters:FormatDate(timestamp, format)
    if not timestamp then return "" end
    
    format = format or "DD/MM/YYYY"
    
    local dateTable = date("*t", timestamp)
    
    if format == "relative" then
        return self:FormatRelativeDate(timestamp)
    elseif format == "MM/DD/YYYY" then
        return string.format("%02d/%02d/%04d", dateTable.month, dateTable.day, dateTable.year)
    elseif format == "YYYY-MM-DD" then
        return string.format("%04d-%02d-%02d", dateTable.year, dateTable.month, dateTable.day)
    else
        return string.format("%02d/%02d/%04d", dateTable.day, dateTable.month, dateTable.year)
    end
end

function Formatters:FormatRelativeDate(timestamp)
    if not timestamp then return "" end
    
    local now = time()
    local diff = now - timestamp
    local days = math.floor(diff / 86400)
    
    if days == 0 then
        return L["DATE_TODAY"]
    elseif days == 1 then
        return L["DATE_YESTERDAY"]
    elseif days < 7 then
        return string.format(L["DATE_DAYS_AGO"], days)
    elseif days < 30 then
        local weeks = math.floor(days / 7)
        -- Singular y plural son claves distintas: nunca "1 semanas".
        return weeks == 1 and L["DATE_WEEK_AGO"] or string.format(L["DATE_WEEKS_AGO"], weeks)
    else
        return self:FormatDate(timestamp, "DD/MM/YYYY")
    end
end

-- ===========================================================================
-- COLOR HELPERS
-- ===========================================================================

function Formatters:ColorText(text, colorTable)
    if not text or not colorTable then return text end
    
    local r = math.floor(colorTable.r * 255)
    local g = math.floor(colorTable.g * 255)
    local b = math.floor(colorTable.b * 255)
    
    return string.format("|cFF%02x%02x%02x%s|r", r, g, b, text)
end

function Formatters:ColorTextHex(text, hexColor)
    if not text or not hexColor then return text end
    
    hexColor = hexColor:gsub("#", "")
    return string.format("|cFF%s%s|r", hexColor, text)
end

-- ===========================================================================
-- ITEM LEVEL FORMATTING
-- ===========================================================================

function Formatters:FormatItemLevel(ilvl)
    if not ilvl or ilvl == 0 then return "-" end
    return tostring(math.floor(ilvl))
end

-- ===========================================================================
-- KEY LEVEL FORMATTING
-- ===========================================================================

function Formatters:FormatKeyLevel(level)
    if not level or level == 0 then return "-" end
    return "+" .. tostring(level)
end

-- ===========================================================================
-- DUNGEON NAME SHORTENING
-- ===========================================================================

-- FIX BUG-8: nombres cortos para las mazmorras de Midnight S1.
-- Se incluyen tanto nombres en inglés (cliente EN) como en español (cliente ES).
local DUNGEON_SHORT_NAMES = {
    -- -- The War Within ---------------------------------------------------
    ["Atal'dazar"]                    = "AD",
    ["Ara-Kara, City of Echoes"]      = "AK",
    ["Mists of Tirna Scithe"]         = "MOTS",
    ["City of Threads"]               = "COT",
    ["Cinderbrew Meadery"]            = "CM",
    ["Darkflame Cleft"]               = "DFC",
    ["Priory of the Sacred Flame"]    = "PSOF",
    ["The Rookery"]                   = "ROOK",
    ["The Stonevault"]                = "SV",
    ["The Dawnbreaker"]               = "DB",

    -- -- Midnight - Temporada 1 (M+ Pool confirmado) ------------------------
    -- Nuevas de Midnight
    ["Windrunner Spire"]              = "WS",
    ["Murder Row"]                    = "MR",
    ["Den of Nalorakk"]               = "DON",
    ["Maisara Caverns"]               = "MC",
    -- Legacy
    ["Magister's Terrace"]            = "MT",
    ["Pit of Saron"]                  = "POS",
    ["Seat of the Triumvirate"]       = "SOTT",
    ["Skyreach"]                      = "SKY",

    -- -- Midnight - nombres ES --------------------------------------------
    ["Aguja Brisaveloz"]              = "WS",
    ["Calle del Crimen"]              = "MR",
    ["Guarida de Nalorakk"]           = "DON",
    ["Cavernas de Maisara"]           = "MC",
    ["Bancal del Magister"]           = "MT",
    ["Foso de Saron"]                 = "POS",
    ["Trono del Triunvirato"]         = "SOTT",
    ["Cumbre del Cielo"]              = "SKY",
}

function Formatters:ShortenDungeonName(name)
    return DUNGEON_SHORT_NAMES[name] or name
end

return Formatters
