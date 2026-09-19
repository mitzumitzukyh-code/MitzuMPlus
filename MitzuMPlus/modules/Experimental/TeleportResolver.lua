-- ============================================================================
-- MitzuMPlus Experimental Teleport Resolver
-- Season 2 map->teleport IDs validated by live probe on Retail 12.1.x.
-- Resolves state only; casting is handled by secure click buttons.
-- ============================================================================
local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local T = {}
MitzuMPlus.TeleportResolver = T

T.SOURCE = "LIVE_PROBE_12.1_S2"
T.SPELLS = {
    [249] = 1286831, -- King's Rest
    [250] = 1286828, -- Temple of Sethraliss
    [399] = 393256,  -- Ruby Life Pools
    [584] = 1286801, -- The Blinding Vale
    [585] = 1286804, -- Voidscar Arena
    [586] = 1286807, -- Den of Nalorakk
    [587] = 1286809, -- Murder Row
    [588] = 1286812, -- Altar of Fangs
}

local function spellInfo(spellID)
    local CS = rawget(_G, "C_Spell")
    if not (CS and type(CS.GetSpellInfo) == "function") then return nil end
    local ok, info = pcall(CS.GetSpellInfo, spellID)
    if not ok or not info then return nil end
    if type(info) == "table" then
        return info.name, info.iconID or info.iconFileID
    end
    if type(info) == "string" then return info, nil end
    return nil
end

local function texture(spellID)
    local CS = rawget(_G, "C_Spell")
    if CS and type(CS.GetSpellTexture) == "function" then
        local ok, tex = pcall(CS.GetSpellTexture, spellID)
        if ok and tex then return tex end
    end
    local _, tex = spellInfo(spellID)
    return tex
end

local function known(spellID)
    local f1 = rawget(_G, "IsPlayerSpell")
    if type(f1) == "function" then
        local ok, v = pcall(f1, spellID)
        if ok and v == true then return true end
    end
    local f2 = rawget(_G, "IsSpellKnown")
    if type(f2) == "function" then
        local ok, v = pcall(f2, spellID)
        if ok and v == true then return true end
    end
    return false
end

local function cooldown(spellID)
    local CS = rawget(_G, "C_Spell")
    if not (CS and type(CS.GetSpellCooldown) == "function") then return 0, 0 end
    local ok, cd = pcall(CS.GetSpellCooldown, spellID)
    if not ok or type(cd) ~= "table" then return 0, 0 end
    return tonumber(cd.startTime) or 0, tonumber(cd.duration) or 0
end

function T:GetSpellID(mapID)
    return self.SPELLS[tonumber(mapID)]
end

function T:Get(mapID)
    mapID = tonumber(mapID)
    local spellID = mapID and self.SPELLS[mapID] or nil
    if not spellID then return { mapID=mapID, state="UNAVAILABLE" } end

    local name, icon = spellInfo(spellID)
    icon = icon or texture(spellID)
    if not name then
        return { mapID=mapID, spellID=spellID, state="UNAVAILABLE", icon=icon }
    end
    if not known(spellID) then
        return { mapID=mapID, spellID=spellID, spellName=name, icon=icon, state="LOCKED" }
    end
    if InCombatLockdown and InCombatLockdown() then
        return { mapID=mapID, spellID=spellID, spellName=name, icon=icon, state="COMBAT_LOCKED" }
    end
    local startTime, duration = cooldown(spellID)
    if duration and duration > 1.5 and startTime and startTime > 0 then
        local now = GetTime and GetTime() or 0
        local remaining = math.max(0, startTime + duration - now)
        if remaining > 0.5 then
            return {
                mapID=mapID, spellID=spellID, spellName=name, icon=icon,
                state="COOLDOWN", cooldownStart=startTime, cooldownDuration=duration,
                cooldownRemaining=remaining,
            }
        end
    end
    return { mapID=mapID, spellID=spellID, spellName=name, icon=icon, state="AVAILABLE" }
end

function T:GetSeasonMaps()
    local out = {}
    if C_ChallengeMode and type(C_ChallengeMode.GetMapTable) == "function" then
        local ok, maps = pcall(C_ChallengeMode.GetMapTable)
        if ok and type(maps) == "table" then
            for _, mapID in ipairs(maps) do out[#out + 1] = mapID end
        end
    end
    return out
end

function T:Initialize()
    -- Pure resolver; no event ownership needed.
end

function T:ReportLines()
    local maps = self:GetSeasonMaps()
    local resolved, available = 0, 0
    local out = { "resolverSource=" .. self.SOURCE, "seasonMaps=" .. tostring(#maps) }
    for _, mapID in ipairs(maps) do
        local e = self:Get(mapID)
        if e.spellID then resolved = resolved + 1 end
        if e.state == "AVAILABLE" then available = available + 1 end
        local mapName = nil
        if C_ChallengeMode and type(C_ChallengeMode.GetMapUIInfo) == "function" then
            local ok, n = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
            if ok then mapName = n end
        end
        out[#out + 1] = string.format("%s %s spell=%s %s", tostring(mapID), tostring(e.state), tostring(e.spellID), tostring(mapName or "?"))
    end
    table.insert(out, 2, "resolved=" .. tostring(resolved) .. " available=" .. tostring(available))
    return out
end

return T
