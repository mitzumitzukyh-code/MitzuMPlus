-- MitzuMPlus experimental lab: factual Mythic+ composition coverage.
-- Pure data module: no LFG writes, no protected actions, no UI ownership.

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local PartyNeeds = {}
MitzuMPlus.PartyNeeds = PartyNeeds

-- Class-level utility is intentionally conservative. It answers whether the
-- current party can provide a capability, not whether a specific talent is
-- selected or whether an applicant is a "good" choice.
local LUST_CLASSES = {
    EVOKER = true,
    HUNTER = true,
    MAGE = true,
    SHAMAN = true,
}

local BATTLE_REZ_CLASSES = {
    DEATHKNIGHT = true,
    DRUID = true,
    PALADIN = true,
    WARLOCK = true,
}

local function NormalizeClass(classFile)
    if type(classFile) ~= "string" then return nil end
    local value = classFile:upper():gsub("[^A-Z]", "")
    return value ~= "" and value or nil
end

local function NormalizeRole(role)
    if type(role) ~= "string" then return nil end
    role = role:upper()
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
        return role
    end
    return nil
end

function PartyNeeds:ClassProvides(classFile)
    local class = NormalizeClass(classFile)
    return {
        lust = class and LUST_CLASSES[class] == true or false,
        battleRez = class and BATTLE_REZ_CLASSES[class] == true or false,
    }
end

function PartyNeeds:Analyze(members)
    local result = {
        size = 0,
        slotsOpen = 5,
        unknownRoles = 0,
        roles = { TANK = 0, HEALER = 0, DAMAGER = 0 },
        hasLust = false,
        hasBattleRez = false,
        needTank = true,
        needHealer = true,
        needDPS = 3,
        needLust = true,
        needBattleRez = true,
    }

    if type(members) ~= "table" then
        return result
    end

    for _, member in ipairs(members) do
        if type(member) == "table" then
            result.size = result.size + 1
            local role = NormalizeRole(member.role)
            if role then
                result.roles[role] = result.roles[role] + 1
            else
                result.unknownRoles = result.unknownRoles + 1
            end

            local utility = self:ClassProvides(member.classFile or member.class)
            result.hasLust = result.hasLust or utility.lust
            result.hasBattleRez = result.hasBattleRez or utility.battleRez
        end
    end

    result.slotsOpen = math.max(0, 5 - result.size)
    result.needTank = result.roles.TANK < 1
    result.needHealer = result.roles.HEALER < 1

    -- DPS demand must never exceed the number of seats left after reserving
    -- seats for a missing tank/healer. This keeps the hint actionable for odd
    -- compositions (duplicate roles, role NONE, or a full group).
    local reserved = (result.needTank and 1 or 0) + (result.needHealer and 1 or 0)
    local dpsSeats = math.max(0, result.slotsOpen - reserved)
    result.needDPS = math.min(math.max(0, 3 - result.roles.DAMAGER), dpsSeats)

    -- Utility remains factual even when no seat is open: it describes current
    -- coverage. WouldAddCoverage below separately refuses to recommend an
    -- applicant when the party is already full.
    result.needLust = not result.hasLust
    result.needBattleRez = not result.hasBattleRez
    return result
end

function PartyNeeds:WouldAddCoverage(snapshot, applicant)
    snapshot = type(snapshot) == "table" and snapshot or self:Analyze({})
    applicant = type(applicant) == "table" and applicant or {}
    local role = NormalizeRole(applicant.role)
    local utility = self:ClassProvides(applicant.classFile or applicant.class)
    local hasSeat = (tonumber(snapshot.slotsOpen) or 0) > 0

    return {
        tank = hasSeat and snapshot.needTank == true and role == "TANK",
        healer = hasSeat and snapshot.needHealer == true and role == "HEALER",
        dps = hasSeat and (tonumber(snapshot.needDPS) or 0) > 0 and role == "DAMAGER",
        lust = hasSeat and snapshot.needLust == true and utility.lust,
        battleRez = hasSeat and snapshot.needBattleRez == true and utility.battleRez,
    }
end

function PartyNeeds:SummaryTokens(snapshot)
    snapshot = type(snapshot) == "table" and snapshot or self:Analyze({})
    local tokens = {}
    if snapshot.needTank then tokens[#tokens + 1] = "TANK" end
    if snapshot.needHealer then tokens[#tokens + 1] = "HEALER" end
    local dps = tonumber(snapshot.needDPS) or 0
    if dps > 0 then tokens[#tokens + 1] = "DPS:" .. tostring(dps) end
    if snapshot.needLust then tokens[#tokens + 1] = "LUST" end
    if snapshot.needBattleRez then tokens[#tokens + 1] = "BREZ" end
    return tokens
end

return PartyNeeds
