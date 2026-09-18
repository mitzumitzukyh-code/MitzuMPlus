-- MitzuMPlus experimental lab: compact, read-only composition hint in Blizzard LFG.
-- This module never filters, sorts, invites, declines, or writes protected state.

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

local Hint = {}
MitzuMPlus.LFGCompositionHint = Hint

local eventFrame
local text

local function ActiveListingExists()
    if not (C_LFGList and type(C_LFGList.GetActiveEntryInfo) == "function") then
        return false
    end
    local ok, info = pcall(C_LFGList.GetActiveEntryInfo)
    return ok and info ~= nil
end

local function CollectParty()
    local members = {}
    local units = { "player", "party1", "party2", "party3", "party4" }
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local classFile = UnitClassBase and UnitClassBase(unit) or select(2, UnitClass(unit))
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "NONE"
            members[#members + 1] = { classFile = classFile, role = role }
        end
    end
    return members
end

function Hint:BuildText(snapshot)
    if type(snapshot) ~= "table" then return "" end
    local needs = {}
    if snapshot.needTank then needs[#needs + 1] = L["TANK"] end
    if snapshot.needHealer then needs[#needs + 1] = L["HEALER"] end
    local dps = tonumber(snapshot.needDPS) or 0
    if dps > 0 then needs[#needs + 1] = L["LFG_NEED_DPS_N"]:format(dps) end
    if snapshot.needLust then needs[#needs + 1] = L["LFG_NEED_LUST"] end
    if snapshot.needBattleRez then needs[#needs + 1] = L["LFG_NEED_BREZ"] end
    if #needs == 0 then return L["LFG_COVERAGE_READY"] end
    return L["LFG_NEEDS_PREFIX"] .. ": " .. table.concat(needs, "  -  ")
end

function Hint:Refresh()
    if not text then return end
    if not ActiveListingExists() then
        text:Hide()
        return
    end
    local analyzer = MitzuMPlus.PartyNeeds
    if not (analyzer and type(analyzer.Analyze) == "function") then
        text:Hide()
        return
    end
    text:SetText(self:BuildText(analyzer:Analyze(CollectParty())))
    text:Show()
end

function Hint:TryAttach()
    if text then return true end
    local viewer = _G.LFGListFrame and _G.LFGListFrame.ApplicationViewer
    if not viewer or type(viewer.CreateFontString) ~= "function" then return false end

    text = viewer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPRIGHT", viewer, "TOPRIGHT", -34, -8)
    text:SetJustifyH("RIGHT")
    text:SetWidth(390)
    text:SetWordWrap(false)
    text:Hide()
    self:Refresh()
    return true
end

function Hint:Initialize()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    eventFrame:SetScript("OnEvent", function(_, event, loadedName)
        if event == "ADDON_LOADED" and loadedName ~= "Blizzard_GroupFinder" then return end
        if Hint:TryAttach() then Hint:Refresh() end
    end)
    self:TryAttach()
end

Hint:Initialize()
return Hint
