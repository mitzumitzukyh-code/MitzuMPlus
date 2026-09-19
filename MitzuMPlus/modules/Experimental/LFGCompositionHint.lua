-- ============================================================================
-- MitzuMPlus Experimental Group Finder Enhancer
-- Utility coverage tiles attached to Blizzard's native ApplicationViewer.
-- Applicant-row decoration remains disabled until a live row mapping is confirmed.
-- ============================================================================
local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local L = LibStub("AceLocale-3.0"):GetLocale("MitzuMPlusExperimental")

local Hint = { attached=false, refreshCount=0, applicantRowsDiscovered=false }
MitzuMPlus.LFGCompositionHint = Hint

local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local WAITING = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local UTILITY = {
    { key="lust",   label="LFG_TILE_LUST",   spellID=32182 }, -- Heroism representative icon
    { key="brez",   label="LFG_TILE_BREZ",   spellID=20484 }, -- Rebirth representative icon
    { key="soothe", label="LFG_TILE_SOOTHE", spellID=2908  }, -- Soothe
}

local function spellTexture(spellID)
    if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and tex then return tex end
    end
    if type(GetSpellTexture) == "function" then
        local ok, tex = pcall(GetSpellTexture, spellID)
        if ok and tex then return tex end
    end
    return FALLBACK_ICON
end

local function utilityState(s, key)
    if key == "lust" then
        if s.hasLust == true then return true, false end
        return false, s.hasConditionalLust == true
    elseif key == "brez" then
        return s.hasBattleRez == true, false
    elseif key == "soothe" then
        if s.hasSoothe == true then return true, false end
        return false, s.hasConditionalSoothe == true
    end
    return false, false
end

local function statusTexture(covered, conditional)
    if covered then return READY end
    if conditional then return WAITING end
    return NOT_READY
end

local function statusColor(covered, conditional)
    if covered then return 0.35, 1.00, 0.35 end
    if conditional then return 1.00, 0.82, 0.20 end
    return 1.00, 0.32, 0.32
end

function Hint:ShouldShow()
    local viewer = self.viewer
    if not viewer then return false end
    if type(viewer.IsShown) == "function" then
        local ok, shown = pcall(viewer.IsShown, viewer)
        if ok then return shown == true end
    end
    return true
end

function Hint:_LayoutTiles()
    if not self.bar or not self.tiles then return end
    local width = self.bar:GetWidth()
    if type(width) ~= "number" or width < 180 then width = 282 end
    local gap = 2
    local tileW = math.floor((width - gap * 2) / 3)
    if tileW < 82 then tileW = 82 end
    for i, tile in ipairs(self.tiles) do
        tile.frame:ClearAllPoints()
        if i == 1 then
            tile.frame:SetPoint("LEFT", self.bar, "LEFT", 0, 0)
        else
            tile.frame:SetPoint("LEFT", self.tiles[i - 1].frame, "RIGHT", gap, 0)
        end
        tile.frame:SetWidth(tileW)
        tile.frame:SetHeight(24)
    end
end

function Hint:Refresh()
    if not self.bar or not self.tiles then return end
    self.refreshCount = self.refreshCount + 1
    if not self:ShouldShow() then
        self.bar:Hide()
        self.lastVisible = false
        return
    end
    local PN = MitzuMPlus.PartyNeeds
    if not PN then self.bar:Hide(); self.lastVisible=false; return end
    local s = PN:GetSnapshot()
    self.lastSnapshot = s
    self:_LayoutTiles()

    for i, def in ipairs(UTILITY) do
        local tile = self.tiles[i]
        local covered, conditional = utilityState(s, def.key)
        local r, g, b = statusColor(covered, conditional)
        tile.label:SetText(L[def.label])
        tile.label:SetTextColor(r, g, b, 1)
        tile.status:SetTexture(statusTexture(covered, conditional))
        tile.statusState = covered and "COVERED" or (conditional and "CONDITIONAL" or "MISSING")
    end

    self.bar:Show()
    self.lastVisible = true
end

function Hint:TryAttach()
    local lfg = rawget(_G, "LFGListFrame")
    local viewer = lfg and lfg.ApplicationViewer
    if not viewer or type(viewer.CreateFontString) ~= "function" then self.attached=false; return false end
    if self.viewer == viewer and self.bar and self.tiles then
        self.attached=true
        self:Refresh()
        return true
    end
    self.viewer = viewer

    if not self.bar then
        local bar = CreateFrame("Frame", "MitzuMPlusExperimentalUtilityCoverage", viewer)
        bar:SetHeight(24)
        bar:SetFrameLevel((viewer:GetFrameLevel() or 1) + 20)

        -- Keep Mitzu completely above Blizzard's native column-header row.
        local leftHeader = viewer.NameColumnHeader
        local rightHeader = viewer.RatingColumnHeader
        if leftHeader and rightHeader then
            bar:SetPoint("BOTTOMLEFT", leftHeader, "TOPLEFT", 0, 3)
            bar:SetPoint("BOTTOMRIGHT", rightHeader, "TOPRIGHT", 0, 3)
        elseif viewer.Inset then
            bar:SetPoint("BOTTOMLEFT", viewer.Inset, "TOPLEFT", 4, 27)
            bar:SetPoint("BOTTOMRIGHT", viewer.Inset, "TOPRIGHT", -4, 27)
        else
            bar:SetPoint("TOPLEFT", viewer, "TOPLEFT", 12, -103)
            bar:SetPoint("TOPRIGHT", viewer, "TOPRIGHT", -38, -103)
        end

        self.tiles = {}
        for i, def in ipairs(UTILITY) do
            local f = CreateFrame("Frame", nil, bar)
            local icon = f:CreateTexture(nil, "ARTWORK")
            icon:SetSize(15, 15)
            icon:SetPoint("LEFT", f, "LEFT", 2, 0)
            icon:SetTexture(spellTexture(def.spellID))

            local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)

            local status = f:CreateTexture(nil, "ARTWORK")
            status:SetSize(13, 13)
            status:SetPoint("RIGHT", f, "RIGHT", -2, 0)

            label:SetPoint("RIGHT", status, "LEFT", -3, 0)

            if i < #UTILITY then
                local sep = f:CreateTexture(nil, "BACKGROUND")
                sep:SetTexture("Interface\\Buttons\\WHITE8X8")
                sep:SetVertexColor(0.55, 0.48, 0.28, 0.40)
                sep:SetWidth(1)
                sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, -3)
                sep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, 3)
            end

            self.tiles[i] = { frame=f, icon=icon, label=label, status=status, def=def }
        end
        self.bar = bar
    else
        self.bar:SetParent(viewer)
    end

    self.attached = true
    self:Refresh()
    return true
end

function Hint:ScheduleRefresh()
    if self._pending then return end
    self._pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() Hint._pending=false; Hint:TryAttach() end)
    else
        self._pending=false; self:TryAttach()
    end
end

function Hint:GetApplicantCount()
    if not (C_LFGList and type(C_LFGList.GetApplicants) == "function") then return 0 end
    local ok, ids = pcall(C_LFGList.GetApplicants)
    return ok and type(ids) == "table" and #ids or 0
end

function Hint:Initialize()
    if self.eventFrame then return end
    local f = CreateFrame("Frame")
    self.eventFrame = f
    for _, ev in ipairs({
        "ADDON_LOADED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
        "LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_APPLICANT_LIST_UPDATED",
        "LFG_LIST_APPLICANT_UPDATED", "PLAYER_ROLES_ASSIGNED",
    }) do f:RegisterEvent(ev) end
    f:SetScript("OnEvent", function(_, event, name)
        if event == "ADDON_LOADED" and name ~= "Blizzard_GroupFinder" then return end
        Hint:ScheduleRefresh()
    end)
    self:TryAttach()
end

function Hint:ReportLines()
    local viewer = rawget(_G, "LFGListFrame") and LFGListFrame.ApplicationViewer
    local states = {}
    if self.tiles then
        for i, tile in ipairs(self.tiles) do
            states[#states + 1] = UTILITY[i].key .. "=" .. tostring(tile.statusState or "UNKNOWN")
        end
    end
    return {
        "frame=LFGListFrame exists=" .. tostring(type(rawget(_G, "LFGListFrame")) == "table"),
        "applicationViewer=" .. tostring(viewer ~= nil),
        "attached=" .. tostring(self.attached),
        "coverageVisible=" .. tostring(self.lastVisible == true),
        "coveragePlacement=UTILITY_TILES_ABOVE_HEADERS",
        "coverageStates=" .. table.concat(states, ","),
        "applicants=" .. tostring(self:GetApplicantCount()),
        "applicantRowsDiscovered=" .. tostring(self.applicantRowsDiscovered),
        "rowEnhancerImplemented=false",
        "refreshCount=" .. tostring(self.refreshCount),
    }
end

return Hint
