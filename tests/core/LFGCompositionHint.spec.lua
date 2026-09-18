local tests, assertions, failures = 0, 0, {}
local function equal(a, b, label)
    assertions = assertions + 1
    if a ~= b then error((label or "equal") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function truthy(v, label) equal(not not v, true, label) end
local function test(name, fn)
    tests = tests + 1
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end

local addon = {}
local locale = {
    LFG_NEEDS_PREFIX = "Party needs",
    LFG_COVERAGE_READY = "Core coverage ready",
    LFG_NEED_TANK = "Tank",
    LFG_NEED_HEALER = "Healer",
    LFG_NEED_LUST = "Bloodlust",
    LFG_NEED_BREZ = "Battle rez",
    LFG_NEED_DPS_N = "DPS x%d",
    LFG_APPLICANT_COVERS = "Covers",
    LFG_COV_TANK = "tank seat",
    LFG_COV_HEALER = "healer seat",
    LFG_COV_DPS = "DPS seat",
    LFG_COV_LUST = "Bloodlust",
    LFG_COV_BREZ = "battle rez",
}
_G.LibStub = function(name)
    if name == "AceAddon-3.0" then return { GetAddon = function() return addon end } end
    if name == "AceLocale-3.0" then
        return { GetLocale = function(namespace)
            equal(namespace, "MitzuMPlusExperimental", "locale namespace")
            return locale
        end }
    end
    error("unexpected library " .. tostring(name))
end
_G.CreateFrame = function()
    return {
        RegisterEvent = function() end,
        SetScript = function() end,
    }
end
_G.C_LFGList = nil
_G.LFGListFrame = nil

dofile("MitzuMPlus/modules/Experimental/PartyNeeds.lua")
dofile("MitzuMPlus/modules/Experimental/LFGCompositionHint.lua")
local Hint = addon.LFGCompositionHint

test("missing composition is rendered from locale keys", function()
    equal(Hint:BuildText({
        needTank = true, needHealer = true, needDPS = 2,
        needLust = true, needBattleRez = true,
    }), "Party needs: Tank  -  Healer  -  DPS x2  -  Bloodlust  -  Battle rez")
end)

test("complete composition uses localized ready state", function()
    equal(Hint:BuildText({
        needTank = false, needHealer = false, needDPS = 0,
        needLust = false, needBattleRez = false,
    }), "Core coverage ready")
end)

test("applicant coverage stays factual and localized", function()
    local snapshot = addon.PartyNeeds:Analyze({
        { classFile = "WARRIOR", role = "TANK" },
        { classFile = "PRIEST", role = "HEALER" },
        { classFile = "ROGUE", role = "DAMAGER" },
        { classFile = "MONK", role = "DAMAGER" },
    })
    equal(Hint:BuildApplicantCoverage(snapshot, { classFile = "SHAMAN", role = "DAMAGER" }),
        "Covers: DPS seat  -  Bloodlust")
    equal(Hint:BuildApplicantCoverage(snapshot, { classFile = "PALADIN", role = "DAMAGER" }),
        "Covers: DPS seat  -  battle rez")
end)

test("full party never recommends applicant coverage", function()
    local snapshot = addon.PartyNeeds:Analyze({
        { classFile = "WARRIOR", role = "TANK" },
        { classFile = "PRIEST", role = "HEALER" },
        { classFile = "ROGUE", role = "DAMAGER" },
        { classFile = "MONK", role = "DAMAGER" },
        { classFile = "WARRIOR", role = "DAMAGER" },
    })
    equal(Hint:BuildApplicantCoverage(snapshot, { classFile = "SHAMAN", role = "DAMAGER" }), "")
end)

test("invalid snapshot produces no visible text", function()
    equal(Hint:BuildText(nil), "")
end)

local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end
local function keys(source)
    local out = {}
    for key in source:gmatch('L%["([A-Z0-9_]+)"%]%s*=') do out[key] = true end
    return out
end

test("experimental English and Spanish locale keys have exact parity", function()
    local en = keys(read("MitzuMPlus/Locales/enUS_Experimental.lua"))
    local es = keys(read("MitzuMPlus/Locales/esES_Experimental.lua"))
    local countEn, countEs = 0, 0
    for key in pairs(en) do countEn = countEn + 1; truthy(es[key], "missing esES key " .. key) end
    for key in pairs(es) do countEs = countEs + 1; truthy(en[key], "missing enUS key " .. key) end
    equal(countEn, countEs, "locale key count")
    equal(countEn, 13, "expected experimental key count")
end)

if #failures > 0 then
    error(string.format("LFGCompositionHint: %d failures\n%s", #failures, table.concat(failures, "\n")), 0)
end
return { tests = tests, assertions = assertions }
