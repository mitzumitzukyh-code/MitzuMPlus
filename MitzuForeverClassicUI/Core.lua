local ADDON_NAME = ...

MitzuForeverClassicUIDB = MitzuForeverClassicUIDB or {}

local MFCUI = CreateFrame("Frame")
MFCUI:RegisterEvent("ADDON_LOADED")

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffMitzuForeverClassicUI:|r " .. tostring(msg))
end

MFCUI:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == ADDON_NAME then
        MitzuForeverClassicUIDB.version = MitzuForeverClassicUIDB.version or 1
        MitzuForeverClassicUIDB.profile = MitzuForeverClassicUIDB.profile or "CLASSIC"
    end
end)

SLASH_MITZUFOREVERCLASSICUI1 = "/mfui"
SlashCmdList.MITZUFOREVERCLASSICUI = function(msg)
    msg = (msg or ""):lower()
    if msg == "" or msg == "status" then
        Print("status=EXPERIMENTAL_PRE_BETA profile=" .. tostring(MitzuForeverClassicUIDB.profile or "CLASSIC"))
        Print("combatAutomation=DISABLED secureActions=UNCHANGED")
    elseif msg == "probe" then
        local interfaceVersion = select(4, GetBuildInfo())
        Print("interface=" .. tostring(interfaceVersion))
        Print("EditModeManagerFrame=" .. (_G.EditModeManagerFrame and "AVAILABLE" or "UNAVAILABLE"))
        Print("CompactPartyFrame=" .. (_G.CompactPartyFrame and "AVAILABLE" or "UNAVAILABLE"))
    else
        Print("commands: /mfui status | /mfui probe")
    end
end

_G.MitzuForeverClassicUI = MFCUI
