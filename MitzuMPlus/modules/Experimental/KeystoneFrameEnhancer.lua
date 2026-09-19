-- ============================================================================
-- MitzuMPlus Experimental Keystone Frame Enhancer
-- Extends ChallengesKeystoneFrame with two explicit-click controls and
-- optional auto-slot when the Font of Power receptacle is opened.
-- NEVER starts the challenge automatically and NEVER mutates StartButton.
-- ============================================================================
local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local L = LibStub("AceLocale-3.0"):GetLocale("MitzuMPlusExperimental")

local K = {
    attached = false,
    autoSlotAttempts = 0,       -- actual UseContainerItem calls
    autoSlotDispatches = 0,
    autoSlotSuccesses = 0,      -- confirmed by CHALLENGE_MODE_KEYSTONE_SLOTTED
    receptacleGeneration = 0,
    lastAutoSlot = "NONE",
    lastPermission = false,
    _receptacleOpen = false,
    _autoSlotAttemptedGeneration = nil,
    _autoSlotConfirmedGeneration = nil,
    _hookedLifecycleFrame = nil,
}
MitzuMPlus.KeystoneFrameEnhancer = K

local function cfg()
    local core = MitzuMPlus.ExperimentalNativeUI
    return core and core:GetConfig() or nil
end

local function groupPermission()
    local inGroup = type(IsInGroup) == "function" and IsInGroup() or false
    if not inGroup then return false end
    local leader = type(UnitIsGroupLeader) == "function" and UnitIsGroupLeader("player") or false
    local assist = type(UnitIsGroupAssistant) == "function" and UnitIsGroupAssistant("player") or false
    return leader == true or assist == true
end

local function findOwnedKeystone()
    local CC = rawget(_G, "C_Container")
    local CI = rawget(_G, "C_Item")
    if not (CC and type(CC.GetContainerNumSlots) == "function" and type(CC.GetContainerItemID) == "function") then
        return nil
    end
    if not (CI and type(CI.IsItemKeystoneByID) == "function") then return nil end
    local maxBag = tonumber(rawget(_G, "NUM_BAG_SLOTS")) or 4
    for bag = 0, maxBag do
        local okN, n = pcall(CC.GetContainerNumSlots, bag)
        if okN and type(n) == "number" then
            for slot = 1, n do
                local okID, itemID = pcall(CC.GetContainerItemID, bag, slot)
                if okID and itemID then
                    local okK, isKey = pcall(CI.IsItemKeystoneByID, itemID)
                    if okK and isKey == true then return bag, slot, itemID end
                end
            end
        end
    end
    return nil
end

function K:TryAutoSlot(reason, generation)
    local c = cfg()
    if not c or c.enabled == false or c.autoSlotKeystone ~= true then
        self.lastAutoSlot = "DISABLED"
        return false
    end
    generation = tonumber(generation) or tonumber(self.receptacleGeneration) or 0
    if generation <= 0 or generation ~= self.receptacleGeneration then
        self.lastAutoSlot = "STALE_GENERATION"
        return false
    end
    if self._autoSlotAttemptedGeneration == generation then
        self.lastAutoSlot = "ALREADY_ATTEMPTED:" .. tostring(generation)
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        self.lastAutoSlot = "COMBAT"
        return false
    end
    if C_ChallengeMode and type(C_ChallengeMode.HasSlottedKeystone) == "function" then
        local ok, has = pcall(C_ChallengeMode.HasSlottedKeystone)
        if ok and has == true then
            self.lastAutoSlot = "ALREADY_SLOTTED"
            return true
        end
    end
    local bag, slot, itemID = findOwnedKeystone()
    if bag == nil then
        self.lastAutoSlot = "KEY_NOT_FOUND"
        return false
    end
    local CC = rawget(_G, "C_Container")
    if not (CC and type(CC.UseContainerItem) == "function") then
        self.lastAutoSlot = "USE_API_UNAVAILABLE"
        return false
    end

    -- Idempotence boundary: for one visible receptacle generation, Mitzu can
    -- dispatch at most one real UseContainerItem call. A second event/hook can
    -- observe the same generation but can never slot again.
    self._autoSlotAttemptedGeneration = generation
    self.autoSlotAttempts = self.autoSlotAttempts + 1
    local ok = pcall(CC.UseContainerItem, bag, slot)
    if ok then
        self.autoSlotDispatches = self.autoSlotDispatches + 1
        self.lastAutoSlot = "DISPATCHED_KEY_ITEM:" .. tostring(itemID) .. ":GEN:" .. tostring(generation)
        return true
    end
    self.lastAutoSlot = "USE_FAILED:GEN:" .. tostring(generation)
    return false
end

function K:EndOpenGeneration(reason)
    if not self._receptacleOpen then return end
    self._receptacleOpen = false
    self.lastOpenEndReason = reason or "HIDE"
end

function K:BeginOpenGeneration(reason)
    if self._receptacleOpen then return self.receptacleGeneration end
    self._receptacleOpen = true
    self.receptacleGeneration = self.receptacleGeneration + 1
    self._autoSlotAttemptedGeneration = nil
    self._autoSlotConfirmedGeneration = nil
    local generation = self.receptacleGeneration
    self.lastOpenReason = reason or "OPEN"

    local function attempt()
        -- The frame may have been closed before the deferred callback fires.
        if not K._receptacleOpen or K.receptacleGeneration ~= generation then return end
        K:Attach()
        K:TryAutoSlot(reason or "OPEN", generation)
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, attempt) else attempt() end
    return generation
end

local function createButton(parent, name, text)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetHeight(25)
    b:SetText(text)
    local fs = b:GetFontString()
    local textWidth = fs and fs.GetStringWidth and fs:GetStringWidth() or 0
    -- Never shrink the label to fit the box: widen the Blizzard button instead.
    -- 126 works for the short EN label; ES grows to the measured width, capped so
    -- the two buttons still leave the native PowerLevel unobstructed.
    b:SetWidth(math.max(126, math.min(138, math.ceil(textWidth + 28))))
    return b
end

function K:RefreshLabels()
    if self.readyButton then
        self.readyButton:SetText(L["KEY_READY_CHECK"])
    end
    if self.pullButton then
        self.pullButton:SetText(L["KEY_PULL_TIMER"])
    end
end

function K:RefreshPermission()
    local allowed = groupPermission()
    self.lastPermission = allowed
    if self.readyButton then self.readyButton:SetEnabled(allowed) end
    if self.pullButton then self.pullButton:SetEnabled(allowed) end
end

function K:Attach()
    local frame = rawget(_G, "ChallengesKeystoneFrame")
    if type(frame) ~= "table" or type(frame.CreateFontString) ~= "function" then
        self.attached = false
        return false
    end
    if self.frame == frame and self.readyButton and self.pullButton then
        self.attached = true
        self:RefreshLabels()
        self:RefreshPermission()
        return true
    end

    self.frame = frame
    if self._hookedLifecycleFrame ~= frame and type(hooksecurefunc) == "function" then
        if type(frame.OnShow) == "function" then
            hooksecurefunc(frame, "OnShow", function() K:BeginOpenGeneration("FRAME_ONSHOW") end)
        end
        if type(frame.OnHide) == "function" then
            hooksecurefunc(frame, "OnHide", function() K:EndOpenGeneration("FRAME_ONHIDE") end)
        end
        self._hookedLifecycleFrame = frame
    end
    if not self.readyButton then
        local ready = createButton(frame, "MitzuMPlusExperimentalKeystoneReadyCheck", L["KEY_READY_CHECK"])
        local pull = createButton(frame, "MitzuMPlusExperimentalKeystonePullTimer", L["KEY_PULL_TIMER"])

        -- Keep the native PowerLevel visually dominant. The buttons live in the
        -- free top corners and are wide enough for both English and Spanish.
        -- Only Mitzu-owned frames are positioned.
        ready:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -31)
        pull:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -31)

        ready:SetScript("OnClick", function()
            if groupPermission() and type(DoReadyCheck) == "function" then
                DoReadyCheck()
            end
        end)
        pull:SetScript("OnClick", function()
            if not groupPermission() then return end
            local c = cfg() or {}
            local seconds = tonumber(c.pullTimerSeconds) or 10
            if C_PartyInfo and type(C_PartyInfo.DoCountdown) == "function" then
                C_PartyInfo.DoCountdown(seconds)
            end
        end)

        ready:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(L["KEY_READY_CHECK"], 1, 0.82, 0)
            GameTooltip:AddLine(L["KEY_READY_CHECK_TIP"], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        ready:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pull:SetScript("OnEnter", function(self)
            local c = cfg() or {}
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(L["KEY_PULL_TIMER"], 1, 0.82, 0)
            GameTooltip:AddLine(string.format(L["KEY_PULL_TIMER_TIP"], tonumber(c.pullTimerSeconds) or 10), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        pull:SetScript("OnLeave", function() GameTooltip:Hide() end)

        self.readyButton, self.pullButton = ready, pull
    else
        self.readyButton:SetParent(frame)
        self.pullButton:SetParent(frame)
    end
    self.attached = true
    self:RefreshLabels()
    self:RefreshPermission()
    return true
end

function K:OnReceptacleOpen()
    self:Attach()
    -- OnShow and this event can both fire for the same opening. BeginOpenGeneration
    -- coalesces them, so only one generation and one possible slot call exist.
    self:BeginOpenGeneration("RECEPTACLE_OPEN")
end

function K:Initialize()
    if self.eventFrame then return end
    local f = CreateFrame("Frame")
    self.eventFrame = f
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
    f:RegisterEvent("CHALLENGE_MODE_KEYSTONE_SLOTTED")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("PARTY_LEADER_CHANGED")
    f:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "ADDON_LOADED" then
            if arg1 == "Blizzard_ChallengesUI" then K:Attach() end
        elseif event == "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN" then
            K:OnReceptacleOpen()
        elseif event == "CHALLENGE_MODE_KEYSTONE_SLOTTED" then
            K:Attach(); K:RefreshPermission()
            local generation = K.receptacleGeneration
            if K._autoSlotAttemptedGeneration == generation and K._autoSlotConfirmedGeneration ~= generation then
                K._autoSlotConfirmedGeneration = generation
                K.autoSlotSuccesses = K.autoSlotSuccesses + 1
                K.lastAutoSlot = "SLOTTED_CONFIRMED:GEN:" .. tostring(generation)
            else
                K.lastAutoSlot = "SLOTTED_EXTERNAL_OR_MANUAL"
            end
        else
            K:RefreshPermission()
        end
    end)
    self:Attach()
    local frame = self.frame
    if frame and type(frame.IsShown) == "function" and frame:IsShown() then
        self:BeginOpenGeneration("INITIALIZE_SHOWN")
    end
end

function K:ReportLines()
    local frame = rawget(_G, "ChallengesKeystoneFrame")
    local c = cfg() or {}
    local has = false
    if C_ChallengeMode and type(C_ChallengeMode.HasSlottedKeystone) == "function" then
        local ok, v = pcall(C_ChallengeMode.HasSlottedKeystone)
        if ok then has = v == true end
    end
    return {
        "frame=ChallengesKeystoneFrame exists=" .. tostring(type(frame) == "table")
            .. " shown=" .. tostring(frame and frame.IsShown and frame:IsShown() or false),
        "attached=" .. tostring(self.attached),
        "readyCheck=" .. tostring(self.readyButton ~= nil) .. " permission=" .. tostring(self.lastPermission),
        "pullTimer=" .. tostring(self.pullButton ~= nil) .. " seconds=" .. tostring(c.pullTimerSeconds or 10),
        "autoSlot=" .. tostring(c.autoSlotKeystone == true) .. " hasSlotted=" .. tostring(has),
        "autoSlotGeneration=" .. tostring(self.receptacleGeneration)
            .. " open=" .. tostring(self._receptacleOpen == true),
        "autoSlotAttempts=" .. tostring(self.autoSlotAttempts)
            .. " dispatches=" .. tostring(self.autoSlotDispatches)
            .. " confirmations=" .. tostring(self.autoSlotSuccesses),
        "lastAutoSlot=" .. tostring(self.lastAutoSlot),
        "startButtonMutated=false",
        "autoStartChallenge=false",
    }
end

return K
