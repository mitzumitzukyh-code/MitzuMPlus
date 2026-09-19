-- ============================================================================
-- MitzuMPlus Experimental Party Needs
-- Pure composition analysis. Roles come from assigned/spec data, never class.
-- ============================================================================
local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local PartyNeeds = {}
MitzuMPlus.PartyNeeds = PartyNeeds

local GUARANTEED_LUST = { EVOKER=true, MAGE=true, SHAMAN=true }
local CONDITIONAL_LUST = { HUNTER=true }
local BATTLE_REZ = { DEATHKNIGHT=true, DRUID=true, PALADIN=true, WARLOCK=true }
-- Enrage-dispel / "Soothe" coverage. Keep this conservative: Druid and Rogue
-- provide it directly; Hunter capability depends on its current loadout/pet/talent,
-- so it is tracked as conditional rather than reported as guaranteed coverage.
local SOOTHE = { DRUID=true, ROGUE=true }
local CONDITIONAL_SOOTHE = { HUNTER=true }

local function normClass(v)
    if type(v) ~= "string" then return nil end
    v = v:upper():gsub("[^A-Z]", "")
    return v ~= "" and v or nil
end

local function normRole(v)
    if type(v) ~= "string" then return nil end
    v = v:upper()
    if v == "TANK" or v == "HEALER" or v == "DAMAGER" then return v end
    return nil
end

function PartyNeeds:ClassProvides(classFile)
    local c = normClass(classFile)
    return {
        lust = c and GUARANTEED_LUST[c] == true or false,
        conditionalLust = c and CONDITIONAL_LUST[c] == true or false,
        battleRez = c and BATTLE_REZ[c] == true or false,
        soothe = c and SOOTHE[c] == true or false,
        conditionalSoothe = c and CONDITIONAL_SOOTHE[c] == true or false,
    }
end

function PartyNeeds:CollectCurrentParty()
    local out = {}
    local PP = MitzuMPlus.PartyProfiler
    if PP and type(PP.Refresh) == "function" then pcall(PP.Refresh, PP, "EXPERIMENTAL_PARTY_NEEDS") end
    if PP and type(PP.GetMembers) == "function" then
        local ok, members = pcall(PP.GetMembers, PP)
        if ok and type(members) == "table" then
            for _, m in pairs(members) do
                if type(m) == "table" then
                    out[#out + 1] = {
                        guid = m.guid,
                        classFile = m.classFile,
                        role = normRole(m.effectiveRole) or normRole(m.assignedRole) or normRole(m.specRole),
                        assignedRole = m.assignedRole,
                        specRole = m.specRole,
                    }
                end
            end
            if #out > 0 then return out end
        end
    end

    -- Conservative fallback if PartyProfiler is not ready yet.
    for _, unit in ipairs({"player", "party1", "party2", "party3", "party4"}) do
        if UnitExists and UnitExists(unit) then
            local classFile = UnitClassBase and UnitClassBase(unit) or select(2, UnitClass(unit))
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "NONE"
            if unit == "player" and not normRole(role) and GetSpecialization and GetSpecializationRole then
                local idx = GetSpecialization()
                if idx then role = GetSpecializationRole(idx) end
            end
            out[#out + 1] = { classFile = classFile, role = normRole(role) }
        end
    end
    return out
end

function PartyNeeds:Analyze(members)
    local r = {
        size = 0,
        slotsOpen = 5,
        unknownRoles = 0,
        roles = { TANK=0, HEALER=0, DAMAGER=0 },
        hasLust = false,
        hasConditionalLust = false,
        hasBattleRez = false,
        hasSoothe = false,
        hasConditionalSoothe = false,
        lustBy = nil,
        battleRezBy = nil,
        sootheBy = nil,
        needTank = true,
        needHealer = true,
        needDPS = 3,
        needLust = true,
        needBattleRez = true,
        needSoothe = true,
    }
    if type(members) ~= "table" then return r end

    for _, m in ipairs(members) do
        if type(m) == "table" then
            r.size = r.size + 1
            local role = normRole(m.role or m.effectiveRole or m.assignedRole or m.specRole)
            if role then r.roles[role] = r.roles[role] + 1 else r.unknownRoles = r.unknownRoles + 1 end
            local u = self:ClassProvides(m.classFile or m.class)
            if u.lust then
                r.hasLust = true
                r.lustBy = r.lustBy or normClass(m.classFile or m.class)
            elseif u.conditionalLust then
                r.hasConditionalLust = true
            end
            if u.battleRez then
                r.hasBattleRez = true
                r.battleRezBy = r.battleRezBy or normClass(m.classFile or m.class)
            end
            if u.soothe then
                r.hasSoothe = true
                r.sootheBy = r.sootheBy or normClass(m.classFile or m.class)
            elseif u.conditionalSoothe then
                r.hasConditionalSoothe = true
            end
        end
    end

    r.slotsOpen = math.max(0, 5 - r.size)
    r.needTank = r.roles.TANK < 1
    r.needHealer = r.roles.HEALER < 1
    local reserved = (r.needTank and 1 or 0) + (r.needHealer and 1 or 0)
    local dpsSeats = math.max(0, r.slotsOpen - reserved)
    r.needDPS = math.min(math.max(0, 3 - r.roles.DAMAGER), dpsSeats)
    r.needLust = not r.hasLust
    r.needBattleRez = not r.hasBattleRez
    r.needSoothe = not r.hasSoothe
    r.complete = (not r.needTank) and (not r.needHealer) and r.needDPS == 0
        and (not r.needLust) and (not r.needBattleRez) and (not r.needSoothe)
    return r
end

function PartyNeeds:WouldAddCoverage(snapshot, applicant)
    snapshot = type(snapshot) == "table" and snapshot or self:Analyze({})
    applicant = type(applicant) == "table" and applicant or {}
    local role = normRole(applicant.role or applicant.effectiveRole or applicant.assignedRole or applicant.specRole)
    local u = self:ClassProvides(applicant.classFile or applicant.class)
    local seat = (tonumber(snapshot.slotsOpen) or 0) > 0
    return {
        tank = seat and snapshot.needTank == true and role == "TANK",
        healer = seat and snapshot.needHealer == true and role == "HEALER",
        dps = seat and (tonumber(snapshot.needDPS) or 0) > 0 and role == "DAMAGER",
        lust = seat and snapshot.needLust == true and u.lust,
        conditionalLust = seat and snapshot.needLust == true and u.conditionalLust,
        battleRez = seat and snapshot.needBattleRez == true and u.battleRez,
        soothe = seat and snapshot.needSoothe == true and u.soothe,
        conditionalSoothe = seat and snapshot.needSoothe == true and u.conditionalSoothe,
    }
end

function PartyNeeds:GetSnapshot()
    return self:Analyze(self:CollectCurrentParty())
end

function PartyNeeds:ReportLines()
    local s = self:GetSnapshot()
    local out = {
        "size=" .. tostring(s.size) .. " tank=" .. tostring(s.roles.TANK)
            .. " healer=" .. tostring(s.roles.HEALER) .. " dps=" .. tostring(s.roles.DAMAGER)
            .. " unknownRole=" .. tostring(s.unknownRoles),
        "bloodlust=" .. tostring(s.hasLust) .. " conditional=" .. tostring(s.hasConditionalLust)
            .. " by=" .. tostring(s.lustBy),
        "battleRez=" .. tostring(s.hasBattleRez) .. " by=" .. tostring(s.battleRezBy),
        "soothe=" .. tostring(s.hasSoothe) .. " conditional=" .. tostring(s.hasConditionalSoothe)
            .. " by=" .. tostring(s.sootheBy),
        "complete=" .. tostring(s.complete),
    }
    if s.needTank then out[#out + 1] = "missing ROLE TANK x1" end
    if s.needHealer then out[#out + 1] = "missing ROLE HEALER x1" end
    if s.needDPS > 0 then out[#out + 1] = "missing ROLE DAMAGER x" .. tostring(s.needDPS) end
    if s.needLust then out[#out + 1] = "missing UTILITY BLOODLUST x1" end
    if s.needBattleRez then out[#out + 1] = "missing UTILITY BATTLE_REZ x1" end
    if s.needSoothe then out[#out + 1] = "missing UTILITY SOOTHE x1" end
    return out
end

return PartyNeeds
