MitzuForeverAtlas = MitzuForeverAtlas or {}
local MFA = MitzuForeverAtlas

MFA.name = "MitzuForeverAtlas"
MFA.version = "0.1.0-dev"

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, addonName)
    if event ~= "ADDON_LOADED" or addonName ~= MFA.name then
        return
    end

    MitzuForeverAtlasDB = MitzuForeverAtlasDB or {
        minimap = false,
        lastDungeon = nil,
    }

    MFA.db = MitzuForeverAtlasDB
    print("|cff55ccffMitzuForeverAtlas|r loaded. /mfa to open, /mfa probe for beta compatibility.")
end)

SLASH_MITZUFOREVERATLAS1 = "/mfa"
SlashCmdList.MITZUFOREVERATLAS = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "probe" then
        MFA.Probe:Print()
        return
    end

    if msg == "status" then
        print("|cff55ccffMitzuForeverAtlas|r version=" .. MFA.version .. " dungeons=" .. tostring(#(MFA.Dungeons or {})) .. " status=EXPERIMENTAL")
        return
    end

    if MFA.UI and MFA.UI.Toggle then
        MFA.UI:Toggle()
    else
        print("MitzuForeverAtlas UI is unavailable.")
    end
end
