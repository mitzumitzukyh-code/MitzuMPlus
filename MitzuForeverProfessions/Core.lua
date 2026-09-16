local ADDON_NAME = ...

MitzuForeverProfessionsDB = MitzuForeverProfessionsDB or {}

local MFP = CreateFrame("Frame")
MFP:RegisterEvent("ADDON_LOADED")

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffMitzuForeverProfessions:|r " .. tostring(msg))
end

local function Status()
    local interfaceVersion = select(4, GetBuildInfo())
    Print("status=EXPERIMENTAL_PRE_BETA version=0.1.0-dev interface=" .. tostring(interfaceVersion))
    Print("dataMode=VERIFIED_ONLY combatAutomation=DISABLED")
end

MFP:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == ADDON_NAME then
        MitzuForeverProfessionsDB.version = MitzuForeverProfessionsDB.version or 1
    end
end)

SLASH_MITZUFOREVERPROFESSIONS1 = "/mfp"
SlashCmdList.MITZUFOREVERPROFESSIONS = function(msg)
    msg = (msg or ""):lower()
    if msg == "status" or msg == "" then
        Status()
    elseif msg == "probe" then
        local APIs = {
            C_TradeSkillUI = C_TradeSkillUI ~= nil,
            C_Container = C_Container ~= nil,
            C_Item = C_Item ~= nil,
            C_Map = C_Map ~= nil,
        }
        Print("probe begin")
        for name, available in pairs(APIs) do
            Print(name .. "=" .. (available and "AVAILABLE" or "UNAVAILABLE"))
        end
    else
        Print("commands: /mfp status | /mfp probe")
    end
end

_G.MitzuForeverProfessions = MFP
