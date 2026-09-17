-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - LootTracker
-- Trackea items que caen a cada miembro del grupo usando CHAT_MSG_LOOT.
-- Funciona en Midnight 12.0.5 sin CLEU ni app externa.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local LootTracker = {}
LootTracker.__index = LootTracker
MitzuMPlus.LootTracker = LootTracker

-- ─────────────────────────────────────────────────────────────────────────
-- ESTADO INTERNO
-- ─────────────────────────────────────────────────────────────────────────

local _frame    = nil
local _isActive = false

-- _loot[playerName] = { { itemID, itemLink, itemName, iconID, quantity, timestamp }, ... }
local _loot = {}

-- Valores por defecto (se sobreescriben por db.profile.settings en runtime)
LootTracker.minQuality = 2   -- 2 = Poco común
LootTracker.minIlvl    = 0   -- 0 = sin filtro de ilvl
LootTracker.enabled    = true

-- Lee la configuración actual del perfil
local function GetSettings()
    local db = MitzuMPlus and MitzuMPlus.db
    local s  = db and db.profile and db.profile.settings
    return s or {}
end

-- ─────────────────────────────────────────────────────────────────────────
-- PARSEO DE CHAT_MSG_LOOT
--
-- Formato típico en Midnight/Retail:
--   Mitzu obtiene: [Botas de la Tempestad] (2).       (jugador local)
--   Fulano obtiene: [Espada del Vacío].                (party member)
--
-- En inglés:
--   You receive loot: [Stormboots] (2).
--   Fulano receives loot: [Void Blade].
--
-- Blizzard emite CHAT_MSG_LOOT para el jugador local Y para party members
-- (siempre que estén en el mismo grupo y en la misma zona).
-- arg1 = mensaje de chat completo (ya localizado)
-- arg2 = player name (vacío para el jugador local en algunas versiones)
-- ─────────────────────────────────────────────────────────────────────────

local function ShortName(name)
    if type(name) ~= "string" or name == "" then return nil end
    return name:match("^([^%-]+)") or name
end

-- Safely coerce a potentially secret string into a plain Lua string.
-- Uses string.format as a more robust coercion than tostring for secret strings.
local _issecretvalue = rawget(_G, "issecretvalue")

local function SafeToString(val)
    if val == nil then return "" end
    -- If issecretvalue exists and the value is secret, try format coercion
    if _issecretvalue and _issecretvalue(val) then
        local ok, plain = pcall(string.format, "%s", val)
        if ok and plain then return plain end
        return ""  -- Irrecoverable secret string
    end
    -- Normal path
    local ok2, str = pcall(tostring, val)
    if ok2 and str then return str end
    return ""
end

-- Extrae itemLink e itemID del mensaje de loot
local function ParseLootMessage(msg)
    -- FIX BUG-SECRET-3 (Midnight 12.0.5): msg from CHAT_MSG_LOOT is a
    -- "secret string" that cannot be indexed with :match(). Use SafeToString
    -- to coerce into a plain string before pattern matching.
    local s = SafeToString(msg)
    if s == "" then return nil, nil end
    -- El link de item tiene forma |c...|Hitem:itemID:...|h[Nombre]|h|r
    local ok, itemLink = pcall(string.match, s, "|c%x+|Hitem:%d[^|]*|h%[.-%]|h|r")
    if not ok or not itemLink then return nil, nil end
    local itemID = tonumber(itemLink:match("|Hitem:(%d+)"))
    return itemLink, itemID
end

-- Extrae nombre del jugador del mensaje de loot
-- Soporta formatos en/es y "tú/you" para el jugador local
local function ParseLooterName(msg, arg2)
    -- arg2 = nombre del jugador que hizo loot (lo da Blizzard directamente)
    -- FIX BUG-SECRET-3b: arg2 may be a secret string in Midnight 12.0.5.
    local sArg2 = SafeToString(arg2)
    if sArg2 ~= "" then
        return ShortName(sArg2)
    end
    -- Fallback: parsear el mensaje (ya convertido a string plano)
    local s = SafeToString(msg)
    if s == "" then return nil end
    local name = s:match("^(.-)%s+recibe")
               or s:match("^(.-)%s+obtiene")
               or s:match("^(.-)%s+receives")
               or s:match("^(.-)%s+gets")
    if name and name ~= "" then
        return ShortName(name)
    end
    -- Si el mensaje empieza con "Tú" / "You" → jugador local
    if s:match("^T[úu]%s") or s:match("^You%s") then
        return ShortName(UnitName and UnitName("player") or "player")
    end
    return nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- HANDLER
-- ─────────────────────────────────────────────────────────────────────────

local function OnLootMessage(msg, arg2)
    if not _isActive then return end

    -- Respetar toggle de configuración
    local cfg = GetSettings()
    local lootEnabled = LootTracker.enabled
    if cfg.lootTracking == false then return end
    if lootEnabled == false then return end

    local itemLink, itemID = ParseLootMessage(msg)
    if not itemLink or not itemID then return end

    -- Filtrar por calidad mínima (config > campo > default 2).
    -- GetItemInfo devuelve itemLevel como 4.º valor; la versión anterior
    -- leía por error el 14.º retorno (bindType) como si fuera el ilvl.
    local minQ = tonumber(cfg.lootMinQuality or LootTracker.minQuality) or 2
    local itemName, _, quality, baseIlvl, _, _, _, _, _, iconID = GetItemInfo(itemLink)
    quality = tonumber(quality)
    if quality and quality < minQ then return end

    -- Filtrar por ilvl mínimo (0 = sin filtro). Para variantes escaladas
    -- (M+, raid, upgrade tracks, etc.) preferimos el ilvl detallado del link.
    local minIlvl = tonumber(cfg.lootMinIlvl or LootTracker.minIlvl) or 0
    local ilvl = tonumber(baseIlvl)
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, detailed = pcall(C_Item.GetDetailedItemLevelInfo, itemLink)
        if ok and tonumber(detailed) then ilvl = tonumber(detailed) end
    end
    if minIlvl > 0 and ilvl and ilvl < minIlvl then return end

    local playerName = ParseLooterName(msg, arg2)
    if not playerName then return end

    if not itemName then
        -- GetItemInfo devuelve nil si el item no está en caché aún.
        itemName = itemLink  -- el link ya contiene el nombre entre []
        iconID   = 134400    -- icono genérico de interrogante como fallback
    end

    -- msg ya es SafeToString() en ParseLootMessage, pero aquí usamos el original
    local sMsg = SafeToString(msg)
    local quantity = tonumber(sMsg:match("%((%d+)%)%s*$")) or 1

    if not _loot[playerName] then
        _loot[playerName] = {}
    end

    _loot[playerName][#_loot[playerName] + 1] = {
        itemID    = itemID,
        itemLink  = itemLink,
        itemName  = itemName,
        iconID    = iconID or 134400,
        quality   = quality or 1,
        quantity  = quantity,
        timestamp = time and time() or 0,
    }
end

-- ─────────────────────────────────────────────────────────────────────────
-- FRAME
-- ─────────────────────────────────────────────────────────────────────────

local function EnsureFrame()
    if _frame then return end
    _frame = CreateFrame("Frame")
    _frame:SetScript("OnEvent", function(_, event, msg, playerName)
        if event == "CHAT_MSG_LOOT" then
            -- Wrap in pcall to guard against any remaining secret-string crashes
            pcall(OnLootMessage, msg, playerName)
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────
-- API PÚBLICA
-- ─────────────────────────────────────────────────────────────────────────

function LootTracker:Start()
    _loot     = {}
    _isActive = true
    EnsureFrame()
    pcall(function() _frame:RegisterEvent("CHAT_MSG_LOOT") end)
end

function LootTracker:Stop()
    _isActive = false
    if _frame then
        pcall(function() _frame:UnregisterEvent("CHAT_MSG_LOOT") end)
    end
end

function LootTracker:Reset()
    _loot     = {}
    _isActive = false
    if _frame then
        pcall(function() _frame:UnregisterEvent("CHAT_MSG_LOOT") end)
    end
end

-- Devuelve copia de los datos de loot.
-- Formato: { [shortName] = { {itemID, itemLink, itemName, iconID, quality, quantity, timestamp} } }
function LootTracker:GetLoot()
    local copy = {}
    for name, items in pairs(_loot) do
        copy[name] = {}
        for i, item in ipairs(items) do
            copy[name][i] = {
                itemID    = item.itemID,
                itemLink  = item.itemLink,
                itemName  = item.itemName,
                iconID    = item.iconID,
                quality   = item.quality,
                quantity  = item.quantity,
                timestamp = item.timestamp,
            }
        end
    end
    return copy
end

-- Aplica el loot trackeado a run.loot (tabla de la run activa).
-- run.loot = { [shortName] = { ... } }
function LootTracker:ApplyToRun(run)
    if type(run) ~= "table" then return end
    run.loot = self:GetLoot()
end

function LootTracker:GetDebugDump()
    local lines = { "=== LootTracker Debug ===" }
    lines[#lines + 1] = "Active: " .. tostring(_isActive)
    local total = 0
    for name, items in pairs(_loot) do
        lines[#lines + 1] = string.format("  %s: %d items", name, #items)
        for _, item in ipairs(items) do
            lines[#lines + 1] = string.format(
                "    [%d] %s  qty=%d  q=%d",
                item.itemID, item.itemName or "?", item.quantity, item.quality or 0
            )
        end
        total = total + #items
    end
    if total == 0 then
        lines[#lines + 1] = "  (no loot recorded)"
    end
    return table.concat(lines, "\n")
end

return LootTracker
