-- ============================================================================
-- MitzuMPlus Native UI Core
-- Extends Blizzard UI; never replaces it. Internal legacy namespace is preserved for SavedVariables compatibility.
-- ============================================================================
local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local Core = {
    VERSION = 6,
    _booted = false,
}
MitzuMPlus.ExperimentalNativeUI = Core

local function normalizePullTimer(v)
    v = math.floor(tonumber(v) or 10)
    if v == 5 or v == 10 or v == 20 then return v end
    return 10
end

local function playerIdentity()
    local guid = type(UnitGUID) == "function" and UnitGUID("player") or nil
    local name, realm
    if type(UnitFullName) == "function" then
        name, realm = UnitFullName("player")
    elseif type(UnitName) == "function" then
        name = UnitName("player")
    end
    if not realm or realm == "" then
        realm = type(GetRealmName) == "function" and GetRealmName() or ""
    end
    name, realm = tostring(name or ""), tostring(realm or "")
    local key
    if guid and guid ~= "" then
        key = "GUID:" .. tostring(guid)
    elseif name ~= "" then
        key = "NAME:" .. name .. "-" .. realm
    end
    return key, name, realm, guid
end

function Core:GetCharacterIdentity()
    return playerIdentity()
end

function Core:GetConfig()
    local db = MitzuMPlus.db
    if not (db and db.profile) then return nil end
    local cfg = db.profile.experimental
    if type(cfg) ~= "table" then
        cfg = {}
        db.profile.experimental = cfg
    end
    if cfg.enabled == nil then cfg.enabled = true end
    if cfg.autoSlotKeystone == nil then cfg.autoSlotKeystone = true end
    cfg.pullTimerSeconds = normalizePullTimer(cfg.pullTimerSeconds)
    if type(cfg.seasonGoals) ~= "table" then cfg.seasonGoals = {} end

    -- experimental.10: old builds imposed seasonGoal=2000 globally. That value
    -- was an addon default, not a user decision, so it must never silently become
    -- the current character's goal. A non-2000 legacy value may have been chosen
    -- explicitly through /emp; preserve it once we can identify the character.
    if cfg.seasonGoal ~= nil and cfg.seasonGoalLegacyMigrated ~= true then
        local legacy = math.max(0, math.floor(tonumber(cfg.seasonGoal) or 0))
        local key, name, realm = playerIdentity()
        if legacy == 0 or legacy == 2000 then
            cfg.seasonGoal = nil
            cfg.seasonGoalLegacyMigrated = true
        elseif key then
            cfg.seasonGoals[key] = {
                enabled = true,
                target = legacy,
                name = name,
                realm = realm,
            }
            cfg.seasonGoal = nil
            cfg.seasonGoalLegacyMigrated = true
        end
    elseif cfg.seasonGoal == nil and cfg.seasonGoalLegacyMigrated == nil then
        cfg.seasonGoalLegacyMigrated = true
    end

    return cfg
end

function Core:GetCharacterGoal(create)
    local cfg = self:GetConfig()
    if not cfg then return nil end
    local key, name, realm = playerIdentity()
    if not key then
        return { enabled = false, target = 0, key = nil, name = name, realm = realm }
    end
    local goal = cfg.seasonGoals[key]
    if type(goal) ~= "table" then
        if not create then
            return { enabled = false, target = 0, key = key, name = name, realm = realm }
        end
        goal = { enabled = false, target = 0, name = name, realm = realm }
        cfg.seasonGoals[key] = goal
    end
    goal.enabled = goal.enabled == true
    goal.target = math.max(0, math.floor(tonumber(goal.target) or 0))
    goal.name = name ~= "" and name or tostring(goal.name or "")
    goal.realm = realm ~= "" and realm or tostring(goal.realm or "")
    goal.key = key
    return goal
end

function Core:SetCharacterGoalTarget(value)
    local goal = self:GetCharacterGoal(true)
    if not goal then return false end
    goal.target = math.max(0, math.floor(tonumber(value) or 0))
    if goal.target <= 0 then goal.enabled = false end
    return true
end

function Core:SetCharacterGoalEnabled(enabled)
    local goal = self:GetCharacterGoal(true)
    if not goal then return false end
    if enabled == true and (tonumber(goal.target) or 0) <= 0 then
        goal.enabled = false
        return false
    end
    goal.enabled = enabled == true
    return true
end

function Core:IsEnabled()
    local cfg = self:GetConfig()
    return cfg ~= nil and cfg.enabled ~= false
end

function Core:RefreshSeasonPanel(reason)
    local panel = MitzuMPlus.MythicPlusPanelEnhancer
    if panel and type(panel.Refresh) == "function" then
        pcall(panel.Refresh, panel, reason or "CONFIG")
    end
end

function Core:Boot()
    if self._booted then return true end
    local cfg = self:GetConfig()
    if not cfg or cfg.enabled == false then return false end
    self._booted = true

    local modules = {
        MitzuMPlus.PartyNeeds,
        MitzuMPlus.TeleportResolver,
        MitzuMPlus.KeystoneFrameEnhancer,
        MitzuMPlus.MythicPlusPanelEnhancer,
        MitzuMPlus.LFGCompositionHint,
    }
    for _, m in ipairs(modules) do
        if m and type(m.Initialize) == "function" then
            pcall(m.Initialize, m)
        end
    end
    return true
end

local function linesOf(module)
    if not (module and type(module.ReportLines) == "function") then return {} end
    local ok, lines = pcall(module.ReportLines, module)
    return ok and type(lines) == "table" and lines or {}
end

function Core:ReportLines()
    local cfg = self:GetConfig() or {}
    local goal = self:GetCharacterGoal(false) or {}
    local out = {
        "=== NATIVE UI ===",
        "version=" .. tostring(MitzuMPlus.VERSION or "?"),
        "nativeUIEnabled=" .. tostring(cfg.enabled ~= false),
        "booted=" .. tostring(self._booted),
        "autoSlotKeystone=" .. tostring(cfg.autoSlotKeystone == true),
        "pullTimerSeconds=" .. tostring(cfg.pullTimerSeconds or 10),
        "seasonGoalCharacter=" .. tostring(goal.key or "none"),
        "seasonGoalEnabled=" .. tostring(goal.enabled == true),
        "seasonGoalTarget=" .. tostring(goal.target or 0),
    }
    local groups = {
        { "", "-- keystone --", MitzuMPlus.KeystoneFrameEnhancer },
        { "", "-- season --", MitzuMPlus.MythicPlusPanelEnhancer },
        { "", "-- teleports --", MitzuMPlus.TeleportResolver },
        { "", "-- lfg --", MitzuMPlus.LFGCompositionHint },
        { "", "-- party needs --", MitzuMPlus.PartyNeeds },
        { "", "-- inspect safety --", MitzuMPlus.InspectArbiter },
    }
    for _, g in ipairs(groups) do
        out[#out + 1] = g[1]
        out[#out + 1] = g[2]
        for _, line in ipairs(linesOf(g[3])) do out[#out + 1] = line end
    end
    return out
end

function Core:_Show(module, title)
    if MitzuMPlus.ShowDevReport and module then
        MitzuMPlus:ShowDevReport(module, title)
        return
    end
    for _, line in ipairs(linesOf(module)) do MitzuMPlus:Print(line) end
end

function Core:HandleDevCommand(args)
    local sub = args and args[2]
    if sub == "nativeui" then
        local action, value = args[3], args[4]
        local cfg = self:GetConfig()
        if action == "autoslot" and cfg then
            cfg.autoSlotKeystone = value ~= "off"
            MitzuMPlus:Print("[EXP] autoSlotKeystone=" .. tostring(cfg.autoSlotKeystone))
        elseif action == "goal" and cfg then
            if value == "off" or value == "disable" or tonumber(value) == 0 then
                self:SetCharacterGoalEnabled(false)
            else
                local n = math.max(0, math.floor(tonumber(value) or 0))
                if n > 0 then
                    self:SetCharacterGoalTarget(n)
                    self:SetCharacterGoalEnabled(true)
                end
            end
            local goal = self:GetCharacterGoal(false) or {}
            MitzuMPlus:Print("[EXP] seasonGoal enabled=" .. tostring(goal.enabled == true)
                .. " target=" .. tostring(goal.target or 0))
            self:RefreshSeasonPanel("DEV_GOAL")
        elseif action == "pull" and cfg then
            cfg.pullTimerSeconds = normalizePullTimer(value)
            MitzuMPlus:Print("[EXP] pullTimerSeconds=" .. tostring(cfg.pullTimerSeconds))
            if MitzuMPlus.KeystoneFrameEnhancer and MitzuMPlus.KeystoneFrameEnhancer.RefreshLabels then
                MitzuMPlus.KeystoneFrameEnhancer:RefreshLabels()
            end
        else
            self:_Show(self, "MITZUMPLUS [EXP] NATIVE UI")
        end
        return true
    elseif sub == "keystoneui" then
        self:_Show(MitzuMPlus.KeystoneFrameEnhancer, "MITZUMPLUS [EXP] KEYSTONE UI")
        return true
    elseif sub == "seasonui" then
        self:_Show(MitzuMPlus.MythicPlusPanelEnhancer, "MITZUMPLUS [EXP] SEASON UI")
        return true
    elseif sub == "teleports" then
        self:_Show(MitzuMPlus.TeleportResolver, "MITZUMPLUS [EXP] TELEPORTS")
        return true
    elseif sub == "partyneeds" then
        self:_Show(MitzuMPlus.PartyNeeds, "MITZUMPLUS [EXP] PARTY NEEDS")
        return true
    elseif sub == "lfgui" then
        self:_Show(MitzuMPlus.LFGCompositionHint, "MITZUMPLUS [EXP] LFG UI")
        return true
    elseif sub == "inspect" then
        self:_Show(MitzuMPlus.InspectArbiter, "MITZUMPLUS [EXP] INSPECT SAFETY")
        return true
    end
    return false
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= ADDON_NAME then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() Core:Boot() end)
    else
        Core:Boot()
    end
end)

return Core
