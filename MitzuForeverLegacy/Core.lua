local ADDON_NAME = ...

MitzuForeverLegacyDB = MitzuForeverLegacyDB or {}

local MFL = CreateFrame("Frame")
MFL:RegisterEvent("ADDON_LOADED")

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffMitzuForeverLegacy:|r " .. tostring(msg))
end

MFL:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == ADDON_NAME then
        MitzuForeverLegacyDB.version = MitzuForeverLegacyDB.version or 1
        MitzuForeverLegacyDB.characters = MitzuForeverLegacyDB.characters or {}
        MitzuForeverLegacyDB.account = MitzuForeverLegacyDB.account or {}
    end
end)

SLASH_MITZUFOREVERLEGACY1 = "/mfl"
SlashCmdList.MITZUFOREVERLEGACY = function(msg)
    msg = (msg or ""):lower()
    if msg == "" or msg == "status" then
        Print("status=EXPERIMENTAL_PRE_BETA version=0.1.0-dev")
        Print("dataMode=VERIFIED_ONLY accountPlanning=ENABLED")
    elseif msg == "probe" then
        local interfaceVersion = select(4, GetBuildInfo())
        Print("interface=" .. tostring(interfaceVersion))
        Print("C_QuestLog=" .. (C_QuestLog and "AVAILABLE" or "UNAVAILABLE"))
        Print("C_UnitAuras=" .. (C_UnitAuras and "AVAILABLE" or "UNAVAILABLE"))
    else
        Print("commands: /mfl status | /mfl probe")
    end
end

_G.MitzuForeverLegacy = MFL
