local T = require("tests.harness.test")
local Loader = require("tests.harness.addon_loader")

T.describe("PartyNeeds", function()
    local addon

    T.before_each(function()
        addon = Loader.load({
            "MitzuMPlus/modules/Experimental/PartyNeeds.lua",
        })
    end)

    T.it("detects empty-party needs without inventing coverage", function()
        local s = addon.PartyNeeds:Analyze({})
        T.eq(s.size, 0)
        T.truthy(s.needTank)
        T.truthy(s.needHealer)
        T.eq(s.needDPS, 3)
        T.truthy(s.needLust)
        T.truthy(s.needBattleRez)
    end)

    T.it("detects lust and battle rez conservatively from class capability", function()
        local s = addon.PartyNeeds:Analyze({
            { role = "TANK", classFile = "PALADIN" },
            { role = "HEALER", classFile = "SHAMAN" },
            { role = "DAMAGER", classFile = "ROGUE" },
        })
        T.falsy(s.needTank)
        T.falsy(s.needHealer)
        T.eq(s.needDPS, 2)
        T.falsy(s.needLust)
        T.falsy(s.needBattleRez)
    end)

    T.it("does not treat unknown class or role as a positive signal", function()
        local s = addon.PartyNeeds:Analyze({
            { role = "NONE", classFile = "UNKNOWN" },
        })
        T.eq(s.size, 1)
        T.truthy(s.needTank)
        T.truthy(s.needHealer)
        T.eq(s.needDPS, 3)
        T.truthy(s.needLust)
        T.truthy(s.needBattleRez)
    end)

    T.it("reports only coverage an applicant would actually add", function()
        local s = addon.PartyNeeds:Analyze({
            { role = "TANK", classFile = "WARRIOR" },
            { role = "HEALER", classFile = "PRIEST" },
            { role = "DAMAGER", classFile = "ROGUE" },
            { role = "DAMAGER", classFile = "MONK" },
        })
        local add = addon.PartyNeeds:WouldAddCoverage(s, {
            role = "DAMAGER",
            classFile = "MAGE",
        })
        T.falsy(add.tank)
        T.falsy(add.healer)
        T.truthy(add.dps)
        T.truthy(add.lust)
        T.falsy(add.battleRez)
    end)

    T.it("keeps summary tokens language-neutral for the presenter", function()
        local s = addon.PartyNeeds:Analyze({
            { role = "TANK", classFile = "WARRIOR" },
        })
        local tokens = addon.PartyNeeds:SummaryTokens(s)
        T.eq(table.concat(tokens, ","), "HEALER,DPS:3,LUST,BREZ")
    end)
end)

return T
