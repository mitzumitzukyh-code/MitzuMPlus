local tests, assertions, failures = 0, 0, {}
local function equal(a, b, label)
    assertions = assertions + 1
    if a ~= b then error((label or "equal") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function test(name, fn)
    tests = tests + 1
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end

local addon = {}
local locale = {
    TANK = "Tank", HEALER = "Healer",
    LFG_NEEDS_PREFIX = "Party needs",
    LFG_COVERAGE_READY = "Core coverage ready",
    LFG_NEED_LUST = "Bloodlust",
    LFG_NEED_BREZ = "Battle rez",
    LFG_NEED_DPS_N = "DPS x%d",
}
_G.LibStub = function(name)
    if name == "AceAddon-3.0" then return { GetAddon = function() return addon end } end
    if name == "AceLocale-3.0" then return { GetLocale = function() return locale end } end
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

test("invalid snapshot produces no visible text", function()
    equal(Hint:BuildText(nil), "")
end)

if #failures > 0 then
    error(string.format("LFGCompositionHint: %d failures\n%s", #failures, table.concat(failures, "\n")), 0)
end
return { tests = tests, assertions = assertions }
