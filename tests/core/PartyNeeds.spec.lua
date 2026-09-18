local tests, assertions, failures = 0, 0, {}
local function equal(a, b, label)
    assertions = assertions + 1
    if a ~= b then error((label or "equal") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function truthy(v, label) equal(not not v, true, label) end
local function falsy(v, label) equal(not not v, false, label) end
local function test(name, fn)
    tests = tests + 1
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end

local addon = {}
_G.LibStub = function()
    return { GetAddon = function() return addon end }
end

dofile("MitzuMPlus/modules/Experimental/PartyNeeds.lua")
local PartyNeeds = addon.PartyNeeds

test("empty party exposes every factual need", function()
    local s = PartyNeeds:Analyze({})
    equal(s.size, 0)
    equal(s.slotsOpen, 5)
    equal(s.unknownRoles, 0)
    truthy(s.needTank)
    truthy(s.needHealer)
    equal(s.needDPS, 3)
    truthy(s.needLust)
    truthy(s.needBattleRez)
end)

test("class capability detects lust and battle rez", function()
    local s = PartyNeeds:Analyze({
        { role = "TANK", classFile = "PALADIN" },
        { role = "HEALER", classFile = "SHAMAN" },
        { role = "DAMAGER", classFile = "ROGUE" },
    })
    equal(s.slotsOpen, 2)
    falsy(s.needTank)
    falsy(s.needHealer)
    equal(s.needDPS, 2)
    falsy(s.needLust)
    falsy(s.needBattleRez)
end)

test("unknown class and role never become positive signals", function()
    local s = PartyNeeds:Analyze({ { role = "NONE", classFile = "UNKNOWN" } })
    equal(s.size, 1)
    equal(s.slotsOpen, 4)
    equal(s.unknownRoles, 1)
    truthy(s.needTank)
    truthy(s.needHealer)
    equal(s.needDPS, 2)
    truthy(s.needLust)
    truthy(s.needBattleRez)
end)

test("applicant coverage reports only missing capabilities", function()
    local s = PartyNeeds:Analyze({
        { role = "TANK", classFile = "WARRIOR" },
        { role = "HEALER", classFile = "PRIEST" },
        { role = "DAMAGER", classFile = "ROGUE" },
        { role = "DAMAGER", classFile = "MONK" },
    })
    local add = PartyNeeds:WouldAddCoverage(s, { role = "DAMAGER", classFile = "MAGE" })
    falsy(add.tank)
    falsy(add.healer)
    truthy(add.dps)
    truthy(add.lust)
    falsy(add.battleRez)
end)

test("duplicate roles cannot advertise more dps seats than remain", function()
    local s = PartyNeeds:Analyze({
        { role = "TANK", classFile = "WARRIOR" },
        { role = "TANK", classFile = "PALADIN" },
        { role = "DAMAGER", classFile = "ROGUE" },
        { role = "DAMAGER", classFile = "MONK" },
    })
    equal(s.slotsOpen, 1)
    truthy(s.needHealer)
    equal(s.needDPS, 0)
end)

test("full group never recommends an applicant even if utility is missing", function()
    local s = PartyNeeds:Analyze({
        { role = "TANK", classFile = "WARRIOR" },
        { role = "HEALER", classFile = "PRIEST" },
        { role = "DAMAGER", classFile = "ROGUE" },
        { role = "DAMAGER", classFile = "MONK" },
        { role = "DAMAGER", classFile = "DEMONHUNTER" },
    })
    equal(s.slotsOpen, 0)
    equal(s.needDPS, 0)
    local add = PartyNeeds:WouldAddCoverage(s, { role = "DAMAGER", classFile = "MAGE" })
    falsy(add.dps)
    falsy(add.lust)
end)

test("summary tokens remain language-neutral", function()
    local s = PartyNeeds:Analyze({ { role = "TANK", classFile = "WARRIOR" } })
    equal(table.concat(PartyNeeds:SummaryTokens(s), ","), "HEALER,DPS:2,LUST,BREZ")
end)

if #failures > 0 then
    error(string.format("PartyNeeds: %d failures\n%s", #failures, table.concat(failures, "\n")), 0)
end
return { tests = tests, assertions = assertions }
