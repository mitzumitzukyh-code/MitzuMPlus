-- MitzuMPlus experimental lab: compact, read-only composition hint in Blizzard LFG.
-- This module never filters, sorts, invites, declines, or writes protected state.

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local L = LibStub("AceLocale-3.0"):GetLocale("MitzuMPlusExperimental")

local Hint = {}
MitzuMPlus.LFGCompositionHint = Hint

local eventFrame
local text
local refreshPending = false
local lastRenderedText
local lastVisible = false

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
    if snapshot.needTank then needs[#needs + 1] = L["LFG_NEED_TANK"] end
    if snapshot.needHealer then needs[#needs + 1] = L["LFG_NEED_HEALER"] end
    local dps = tonumber(snapshot.needDPS) or 0
    if dps > 0 then needs[#needs + 1] = L["LFG_NEED_DPS_N"]:format(dps) end
    if snapshot.needLust then needs[#needs + 1] = L["LFG_NEED_LUST"] end
    if snapshot.needBattleRez then needs[#needs + 1] = L["LFG_NEED_BREZ"] end
    if #needs == 0 then return L["LFG_COVERAGE_READY"] end
    return L["LFG_NEEDS_PREFIX"] .. ": " .. table.concat(needs, "  -  ")
end

function Hint:BuildApplicantCoverage(snapshot, applicant)
    local analyzer = MitzuMPlus.PartyNeeds
    if not (analyzer and type(analyzer.WouldAddCoverage) == "function") then return "" end
    local coverage = analyzer:WouldAddCoverage(snapshot, applicant)
    local labels = {}
    if coverage.tank then labels[#labels + 1] = L["LFG_COV_TANK"] end
    if coverage.healer then labels[#labels + 1] = L["LFG_COV_HEALER"] end
    if coverage.dps then labels[#labels + 1] = L["LFG_COV_DPS"] end
    if coverage.lust then labels[#labels + 1] = L["LFG_COV_LUST"] end
    if coverage.battleRez then labels[#labels + 1] = L["LFG_COV_BREZ"] end
    if #labels == 0 then return "" end
    return L["LFG_APPLICANT_COVERS"] .. ": " .. table.concat(labels, "  -  ")
end

function Hint:ReadApplicantMember(applicantID, memberIndex)
    if not (C_LFGList and type(C_LFGList.GetApplicantMemberInfo) == "function") then return nil end
    local ok, _, classFile, _, _, _, _, tank, healer, damage, _, _, _, _, _, specID = pcall(C_LFGList.GetApplicantMemberInfo, applicantID, memberIndex or 1)
    if not ok then return nil end
    local role
    if tank then role = "TANK"
    elseif healer then role = "HEALER"
    elseif damage then role = "DAMAGER" end
    return { classFile = classFile, role = role, specID = specID }
end

function Hint:GetApplicantCoverageText(applicantID, memberIndex)
    local applicant = self:ReadApplicantMember(applicantID, memberIndex)
    if not applicant then return "" end
    local analyzer = MitzuMPlus.PartyNeeds
    if not (analyzer and type(analyzer.Analyze) == "function") then return "" end
    return self:BuildApplicantCoverage(analyzer:Analyze(CollectParty()), applicant)
end

-- Keep the Blizzard-owned viewer as the source of layout truth. We only update
-- our FontString when its semantic state actually changes, avoiding redundant
-- SetText/Show/Hide churn during noisy LFG event bursts.
function Hint:ApplyPresentation(value, visible)
    if not text then return false end
    value = type(value) == "string" and value or ""
    visible = visible == true
    local changed = false
    if visible and value ~= lastRenderedText then
        text:SetText(value)
        lastRenderedText = value
        changed = true
    end
    if visible ~= lastVisible then
        if visible then text:Show() else text:Hide() end
        lastVisible = visible
        changed = true
    end
    return changed
end

function Hint:Refresh()
    if not text then return end
    if not ActiveListingExists() then
        self:ApplyPresentation("", false)
        return
    end
    local analyzer = MitzuMPlus.PartyNeeds
    if not (analyzer and type(analyzer.Analyze) == "function") then
        self:ApplyPresentation("", false)
        return
    end
    self:ApplyPresentation(self:BuildText(analyzer:Analyze(CollectParty())), true)
end

-- LFG can emit several applicant/list events in the same UI burst. Coalesce them
-- into one next-frame refresh so Mitzu stays event-driven without repeatedly
-- rebuilding the same five-member party snapshot.
function Hint:ScheduleRefresh()
    if refreshPending then return false end
    refreshPending = true
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            refreshPending = false
            Hint:Refresh()
        end)
    else
        refreshPending = false
        self:Refresh()
    end
    return true
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
    lastVisible = false
    lastRenderedText = nil
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
    eventFrame:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")
    eventFrame:RegisterEvent("LFG_LIST_APPLICANT_UPDATED")
    eventFrame:SetScript("OnEvent", function(_, event, loadedName)
        if event == "ADDON_LOADED" and loadedName ~= "Blizzard_GroupFinder" then return end
        if Hint:TryAttach() then Hint:ScheduleRefresh() end
    end)
    self:TryAttach()
end

Hint:Initialize()
return Hint
