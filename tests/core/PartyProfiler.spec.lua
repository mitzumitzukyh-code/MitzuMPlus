-- PartyProfiler + Bug Report [PARTY]: class and role must survive from the Unit
-- APIs to the report. Retail dev.5 (Reposo de los Reyes +12) reported
-- "class=nil role=nil spec=266 state=KNOWN" for every member while the
-- capabilities said partyClass/partyRoles=AVAILABLE: the report read fields
-- that PartyProfiler never writes (`class`, `role`).
local tests, assertions, failures = 0, 0, {}
local function equal(a, b, l)
    assertions = assertions + 1
    if a ~= b then error((l or "equal") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function truthy(v, l) equal(not not v, true, l) end
local function test(n, f) tests = tests + 1; local ok, e = pcall(f); if not ok then failures[#failures + 1] = n .. ": " .. tostring(e) end end

local S = dofile("tests/harness/core_scenario.lua")

-- The real group of that key.
local SPECS = {
    [65]  = { "Sagrado", "HEALER" },     [266] = { "Demonologia", "DAMAGER" },
    [62]  = { "Arcano", "DAMAGER" },     [259] = { "Asesinato", "DAMAGER" },
    [73]  = { "Proteccion", "TANK" },
}
local GROUP = {
    player = { guid = "Player-1-0001", class = "PALADIN", classID = 2, spec = 65, lfgRole = "HEALER" },
    party1 = { guid = "Player-1-0011", class = "WARLOCK", classID = 9, spec = 266, lfgRole = "DAMAGER" },
    party2 = { guid = "Player-1-0012", class = "MAGE", classID = 8, spec = 62, lfgRole = "DAMAGER" },
    party3 = { guid = "Player-1-0013", class = "ROGUE", classID = 4, spec = 259, lfgRole = "DAMAGER" },
    party4 = { guid = "Player-1-0014", class = "WARRIOR", classID = 1, spec = 73, lfgRole = "TANK" },
}

-- Unit APIs as the Retail client exposes them for a five-player party.
local function installGroup(opts)
    opts = opts or {}
    _G.GetNumGroupMembers = function() return 5 end
    _G.IsInRaid = function() return false end
    _G.IsInGroup = function() return true end
    _G.UnitExists = function(u) return GROUP[u] ~= nil end
    _G.UnitGUID = function(u) return GROUP[u] and GROUP[u].guid or nil end
    _G.UnitIsUnit = function(a, b) return a == b end
    _G.UnitName = function(u) return GROUP[u] and ("Name-" .. u) or nil end
    _G.UnitClassBase = function(u) local m = GROUP[u]; if m then return m.class, m.classID end end
    _G.UnitGroupRolesAssigned = function(u)
        if opts.noAssignedRoles then return "NONE" end
        return GROUP[u] and GROUP[u].lfgRole or "NONE"
    end
    _G.CanInspect = function() return true end
    _G.C_SpecializationInfo = {
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 65, SPECS[65][1], "", 0, SPECS[65][2] end,
        GetInspectSpecialization = function(u) return GROUP[u] and GROUP[u].spec or 0 end,
    }
    -- In Retail the by-ID lookup is a global function.
    _G.GetSpecializationInfoByID = function(id)
        local s = SPECS[id]
        if s then return id, s[1], "", 0, s[2] end
    end
end

local function inspectAll(PP)
    for token, m in pairs(GROUP) do
        if token ~= "player" then PP:OnInspectReady(m.guid) end
    end
end

local function members(PP)
    local byToken = {}
    for _, m in pairs(PP:GetMembers()) do byToken[m.unitToken] = m end
    return byToken
end

test("class and role come from Unit APIs before any inspection", function()
    S.isolated(function()
        local env = S.boot({})
        installGroup()
        local PP = _G.MitzuMPlus.PartyProfiler
        PP:Refresh("TEST")
        local m = members(PP)
        equal(m.party1.classFile, "WARLOCK"); equal(m.party1.effectiveRole, "DAMAGER")
        equal(m.party4.classFile, "WARRIOR"); equal(m.party4.effectiveRole, "TANK")
        equal(m.party1.specState, "PENDING", "spec still needs inspection")
        equal(m.player.classFile, "PALADIN"); equal(m.player.effectiveRole, "HEALER")
        equal(m.player.specID, 65); equal(m.player.specState, "KNOWN")
        equal(#env.errors, 0, table.concat(env.errors, "\n"))
    end)
end)

test("bug report prints the real class and role of a known group", function()
    S.isolated(function()
        S.boot({})
        installGroup()
        local MP = _G.MitzuMPlus
        MP.PartyProfiler:Refresh("TEST")
        inspectAll(MP.PartyProfiler)
        local report = MP.BugReport:Build()
        for token, expected in pairs({
            party1 = "class=WARLOCK role=DAMAGER spec=266 state=KNOWN",
            party2 = "class=MAGE role=DAMAGER spec=62 state=KNOWN",
            party3 = "class=ROGUE role=DAMAGER spec=259 state=KNOWN",
            party4 = "class=WARRIOR role=TANK spec=73 state=KNOWN",
            player = "class=PALADIN role=HEALER spec=65 state=KNOWN",
        }) do
            truthy(report:find(token .. "=" .. expected, 1, true), token .. " -> " .. expected .. "\n" .. report)
        end
        truthy(not report:find("class=nil role=nil", 1, true), "no nil class/role for known members")
        truthy(report:find("sectionsFailed=none", 1, true), report)
    end)
end)

test("premade group without assigned roles resolves the role from the known spec", function()
    S.isolated(function()
        S.boot({})
        installGroup({ noAssignedRoles = true })
        local PP = _G.MitzuMPlus.PartyProfiler
        PP:Refresh("TEST")
        local m = members(PP)
        equal(m.party4.assignedRole, "NONE"); equal(m.party4.effectiveRole, "NONE", "unknown until the spec is known")
        inspectAll(PP)
        m = members(PP)
        equal(m.party4.specRole, "TANK"); equal(m.party4.effectiveRole, "TANK")
        equal(m.party1.effectiveRole, "DAMAGER"); equal(m.player.effectiveRole, "HEALER")
        -- A later roster refresh keeps the spec-derived role (SpecCache).
        PP:Refresh("ROSTER")
        m = members(PP)
        equal(m.party4.specID, 73); equal(m.party4.effectiveRole, "TANK")
        equal(PP:GetTank().unitToken, "party4"); equal(PP:GetHealer().unitToken, "player")
        equal(#PP:GetDamagers(), 3)
    end)
end)

test("assigned role wins over the spec role", function()
    S.isolated(function()
        S.boot({})
        installGroup()
        GROUP.party2.lfgRole = "TANK"                     -- deliberately different from spec 62
        local PP = _G.MitzuMPlus.PartyProfiler
        PP:Refresh("TEST"); inspectAll(PP)
        local m = members(PP)
        equal(m.party2.assignedRole, "TANK"); equal(m.party2.specRole, "DAMAGER"); equal(m.party2.effectiveRole, "TANK")
        GROUP.party2.lfgRole = "DAMAGER"
    end)
end)

if #failures > 0 then error(string.format("PartyProfiler: %d failures\n%s", #failures, table.concat(failures, "\n")), 0) end
return { tests = tests, assertions = assertions }
