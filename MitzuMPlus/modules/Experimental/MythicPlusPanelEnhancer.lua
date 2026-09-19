-- ============================================================================
-- MitzuMPlus Experimental Mythic+ Season Panel Enhancer
-- Extends Blizzard ChallengesFrame INSIDE the native panel and adds small
-- Mitzu-owned decorators to Blizzard dungeon icons. Blizzard frames are read
-- and used as anchors only; they are never repositioned or rewritten.
-- ============================================================================
local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local L = LibStub("AceLocale-3.0"):GetLocale("MitzuMPlusExperimental")

local M = {
    attached = false,
    refreshCount = 0,
    panelPosition = "NONE",
    teleportButtons = {},
    dungeonDecorators = {},
    secureTemplateWorks = nil,
}
MitzuMPlus.MythicPlusPanelEnhancer = M

local function cfg()
    local core = MitzuMPlus.ExperimentalNativeUI
    return core and core:GetConfig() or nil
end

local function currentGoal()
    local core = MitzuMPlus.ExperimentalNativeUI
    return core and core:GetCharacterGoal(false) or { enabled=false, target=0 }
end

local function fmtTime(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function mapName(mapID)
    if C_ChallengeMode and type(C_ChallengeMode.GetMapUIInfo) == "function" then
        local ok, name = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
        if ok and name then return name end
    end
    return tostring(mapID)
end

local function seasonBest(mapID)
    if not (C_MythicPlus and type(C_MythicPlus.GetSeasonBestForMap) == "function") then return nil, nil end
    local ok, intime, overtime = pcall(C_MythicPlus.GetSeasonBestForMap, mapID)
    if not ok then return nil, nil end
    return intime, overtime
end

local function dungeonScore(mapID, intime, overtime)
    if C_MythicPlus and type(C_MythicPlus.GetSeasonBestAffixScoreInfoForMap) == "function" then
        local ok, _, best = pcall(C_MythicPlus.GetSeasonBestAffixScoreInfoForMap, mapID)
        if ok and type(best) == "number" then return math.floor(best + 0.5) end
    end
    local a = type(intime) == "table" and tonumber(intime.dungeonScore) or nil
    local b = type(overtime) == "table" and tonumber(overtime.dungeonScore) or nil
    local v = math.max(a or 0, b or 0)
    return v > 0 and math.floor(v + 0.5) or nil
end

-- Keep Blizzard's map-table order. ChallengesFrame.DungeonIcons is built from
-- this same season table; sorting by our own best level could attach data to the
-- wrong native card.
local function seasonMaps()
    local maps = {}
    if C_ChallengeMode and type(C_ChallengeMode.GetMapTable) == "function" then
        local ok, t = pcall(C_ChallengeMode.GetMapTable)
        if ok and type(t) == "table" then
            for _, id in ipairs(t) do
                local intime, overtime = seasonBest(id)
                local bestLevel = 0
                if type(intime) == "table" then bestLevel = math.max(bestLevel, tonumber(intime.level) or 0) end
                if type(overtime) == "table" then bestLevel = math.max(bestLevel, tonumber(overtime.level) or 0) end
                maps[#maps + 1] = {
                    id = id,
                    level = bestLevel,
                    score = dungeonScore(id, intime, overtime),
                    -- A season-best table is the evidence. Do not call a map
                    -- "progress" just because a numeric default happens to exist.
                    hasRecord = type(intime) == "table" or type(overtime) == "table",
                }
            end
        end
    end
    return maps
end

local function mapTimeLimit(mapID)
    if not (mapID and C_ChallengeMode and type(C_ChallengeMode.GetMapUIInfo) == "function") then return nil end
    local ok, _, _, limit = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
    limit = ok and tonumber(limit) or nil
    return limit and limit > 0 and limit or nil
end

local function runHistoryDuration(run)
    local sec = tonumber(run and run.durationSec)
    if sec and sec > 0 then return sec end
    local raw = tonumber(run and run.duration)
    if not raw or raw <= 0 then return nil end
    -- Some Blizzard structures expose milliseconds, others durationSec.
    if raw > 100000 then raw = raw / 1000 end
    return raw
end

local function runHistoryTimed(run)
    if type(run) ~= "table" or run.completed == false then return false end
    local mapID = tonumber(run.mapChallengeModeID or run.mapID)
    local duration = runHistoryDuration(run)
    local limit = mapTimeLimit(mapID)
    return duration ~= nil and limit ~= nil and duration <= limit
end

local function normalizeRealm(value)
    return tostring(value or ""):lower():gsub("[%s%-']", "")
end

local function currentCharacterMatches(run)
    local name, realm
    if type(UnitFullName) == "function" then name, realm = UnitFullName("player") end
    if not name and type(UnitName) == "function" then name = UnitName("player") end
    if not realm or realm == "" then realm = type(GetRealmName) == "function" and GetRealmName() or "" end
    return tostring(run and run.playerName or ""):lower() == tostring(name or ""):lower()
        and normalizeRealm(run and run.playerRealm) == normalizeRealm(realm)
end

local function weeklyFromMitzuHistory()
    if type(MitzuMPlus.GetAllRuns) ~= "function" or type(MitzuMPlus.GetWeeklyResetWindow) ~= "function" then
        return nil, nil, nil
    end
    local weekStart = tonumber((MitzuMPlus:GetWeeklyResetWindow()))
    if not weekStart or weekStart <= 0 then return nil, nil, nil end
    local best, count = nil, 0
    for _, r in ipairs(MitzuMPlus:GetAllRuns() or {}) do
        if type(r) == "table" and currentCharacterMatches(r)
           and (tonumber(r.startTime) or 0) >= weekStart
           and (tonumber(r.completionTime) or 0) > 0 then
            count = count + 1
            if r.inTime == true then
                local level = tonumber(r.keyLevel) or 0
                local duration = tonumber(r.completionTime) or math.huge
                if not best or level > best.level or (level == best.level and duration < best.duration) then
                    best = { level=level, duration=duration, mapID=r.dungeonID }
                end
            end
        end
    end
    return best, count, "MITZU_HISTORY"
end

-- "Best weekly" has one meaning only: highest-level run completed IN TIME
-- this reset week; ties go to the faster run. Depleted runs still count in
-- Runs This Week but can never become "best weekly".
local function weeklySummary()
    if C_MythicPlus and type(C_MythicPlus.GetRunHistory) == "function" then
        local ok, runs = pcall(C_MythicPlus.GetRunHistory, false, false, true)
        if ok and type(runs) == "table" then
            local best, count, sawWeekField = nil, 0, false
            for _, r in ipairs(runs) do
                if type(r) == "table" and r.thisWeek ~= nil then sawWeekField = true end
                if type(r) == "table" and r.thisWeek == true and r.completed ~= false then
                    count = count + 1
                    if runHistoryTimed(r) then
                        local level = tonumber(r.level) or 0
                        local duration = runHistoryDuration(r) or math.huge
                        if not best or level > best.level or (level == best.level and duration < best.duration) then
                            best = { level=level, duration=duration, mapID=r.mapChallengeModeID or r.mapID }
                        end
                    end
                end
            end
            -- An empty table is authoritative (zero weekly runs). If Blizzard
            -- returned entries without the thisWeek marker, fall back instead
            -- of guessing which reset they belong to.
            if #runs == 0 or sawWeekField then
                return best, count, "BLIZZARD_RUN_HISTORY"
            end
        end
    end
    local best, count, source = weeklyFromMitzuHistory()
    return best, count or 0, source or "UNAVAILABLE"
end

local function positionRow(row, y)
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", 8, y)
    row.value:ClearAllPoints()
    row.value:SetPoint("TOPRIGHT", -4, y)
end

local function showRow(row, shown)
    row.label:SetShown(shown)
    row.value:SetShown(shown)
end

local function layoutIntegratedPanel(f, goalEnabled)
    positionRow(f.progress, -22)
    showRow(f.progress, true)
    if goalEnabled then
        positionRow(f.target, -40)
        positionRow(f.current, -58)
        positionRow(f.missing, -76)
        positionRow(f.weekly, -94)
        positionRow(f.runs, -112)
        showRow(f.target, true); showRow(f.current, true); showRow(f.missing, true)
        f:SetHeight(154)
    else
        showRow(f.target, false); showRow(f.current, false); showRow(f.missing, false)
        positionRow(f.weekly, -40)
        positionRow(f.runs, -58)
        f:SetHeight(100)
    end
    showRow(f.weekly, true); showRow(f.runs, true)
end

local function createIntegratedPanel(parent)
    local f = CreateFrame("Frame", "MitzuMPlusExperimentalSeasonPanel", parent)
    f:SetSize(184, 100)
    f:SetFrameStrata(parent:GetFrameStrata() or "MEDIUM")
    f:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
    f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, -166)

    local accent = f:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(0.78, 0.62, 0.19, 0.65)
    accent:SetPoint("TOPLEFT", 0, -2)
    accent:SetPoint("BOTTOMLEFT", 0, 26)
    accent:SetWidth(1)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, 0)
    title:SetText("MitzuMPlus")
    title:SetTextColor(1, 0.82, 0, 1)

    local function row(labelText)
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetWidth(120)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetText(labelText)

        local value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        value:SetWidth(49)
        value:SetJustifyH("RIGHT")
        value:SetWordWrap(false)
        return { label=label, value=value }
    end

    -- "Recorded" is deliberately precise: this count means Blizzard returned
    -- a season-best record for the map, not that Mitzu judged it as progress.
    f.progress = row(L["SEASON_RECORDS_SHORT"])
    f.target = row(L["SEASON_TARGET"])
    f.current = row(L["SEASON_CURRENT"])
    f.missing = row(L["SEASON_MISSING"])
    f.weekly = row(L["SEASON_WEEK_SHORT"])
    f.runs = row(L["SEASON_RUNS_SHORT"])

    local b = CreateFrame("Button", "MitzuMPlusExperimentalOpenHistory", f, "UIPanelButtonTemplate")
    b:SetSize(166, 22)
    b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 0)
    b:SetText(L["SEASON_OPEN_HISTORY"])
    b:SetScript("OnClick", function()
        if MitzuMPlus.ShowTab then MitzuMPlus:ShowTab("historial") end
    end)
    f.openHistory = b
    layoutIntegratedPanel(f, false)
    return f
end

local function tryCreateSecureButton(parent, index)
    local name = "MitzuMPlusExperimentalTeleport" .. tostring(index)
    local ok, b = pcall(CreateFrame, "Button", name, parent, "SecureActionButtonTemplate")
    if ok and b then return b, true end
    return CreateFrame("Button", name, parent), false
end

function M:GetDungeonDecorator(iconFrame, index)
    local e = self.dungeonDecorators[iconFrame]
    if e then return e end

    local score = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    -- Match the native dungeon-card typography when Blizzard exposes it.
    local nativeLevel = iconFrame.HighestLevel
    if nativeLevel and type(nativeLevel.GetFontObject) == "function" and type(score.SetFontObject) == "function" then
        local ok, fontObject = pcall(nativeLevel.GetFontObject, nativeLevel)
        if ok and fontObject then score:SetFontObject(fontObject) end
    end
    score:SetPoint("BOTTOM", iconFrame, "BOTTOM", 0, 4)
    score:SetJustifyH("CENTER")
    score:SetTextColor(1, 0.82, 0, 1)
    if score.SetShadowColor then score:SetShadowColor(0, 0, 0, 1) end
    if score.SetShadowOffset then score:SetShadowOffset(1, -1) end

    local button, secure = tryCreateSecureButton(iconFrame, index)
    self.secureTemplateWorks = self.secureTemplateWorks == nil and secure or (self.secureTemplateWorks or secure)
    button:SetSize(15, 15)
    button:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", -2, -2)
    button:SetFrameLevel((iconFrame:GetFrameLevel() or 1) + 30)
    local tex = button:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    -- Always use a generic portal glyph. The spell's dungeon artwork looked like
    -- a duplicate dungeon icon stacked on top of Blizzard's own card.
    tex:SetTexture("Interface\\Icons\\Spell_Arcane_TeleportStormWind")
    button.icon = tex

    e = { score=score, button=button, secure=secure, mapID=nil }
    self.dungeonDecorators[iconFrame] = e
    self.teleportButtons[iconFrame] = e
    return e
end

function M:ConfigureDungeonDecorator(e, map)
    if not (e and map) then return end
    e.mapID = map.id
    if map.score and map.score > 0 then
        e.score:SetText(tostring(map.score))
        e.score:Show()
    else
        e.score:SetText("")
        e.score:Hide()
    end

    local R = MitzuMPlus.TeleportResolver
    local info = R and R:Get(map.id) or { state="UNAVAILABLE" }
    e.info = info
    local b = e.button
    b.icon:SetDesaturated(info.state ~= "AVAILABLE" and info.state ~= "COOLDOWN")
    b:SetAlpha(info.state == "LOCKED" and 0.32 or 0.85)

    if e.secure and not (InCombatLockdown and InCombatLockdown()) then
        if info.spellName and (info.state == "AVAILABLE" or info.state == "COOLDOWN") then
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", info.spellName)
        else
            b:SetAttribute("type", nil)
            b:SetAttribute("spell", nil)
        end
    end

    if not e.tooltipInstalled then
        b:SetScript("OnEnter", function(self)
            local entry = e.info or {}
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(mapName(e.mapID), 1, 0.82, 0)
            local key = "TELEPORT_STATE_" .. tostring(entry.state or "UNAVAILABLE")
            GameTooltip:AddLine(L[key] or tostring(entry.state), 1, 1, 1, true)
            if entry.state == "COOLDOWN" and entry.cooldownRemaining then
                GameTooltip:AddLine(string.format(L["TELEPORT_COOLDOWN_REMAINING"], fmtTime(entry.cooldownRemaining)), 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        e.tooltipInstalled = true
    end

    if info.state == "UNAVAILABLE" then b:Hide() else b:Show() end
end

function M:Refresh(reason)
    local frame = self.frame or rawget(_G, "ChallengesFrame")
    if type(frame) ~= "table" then return false end
    self.frame = frame
    if not self.panel then self.panel = createIntegratedPanel(frame) end
    self.panelPosition = "INSIDE"
    self.refreshCount = self.refreshCount + 1

    local maps = seasonMaps()
    local done = 0
    for _, m in ipairs(maps) do if m.hasRecord == true then done = done + 1 end end
    local total = #maps

    local score = 0
    if C_ChallengeMode and type(C_ChallengeMode.GetOverallDungeonScore) == "function" then
        local ok, v = pcall(C_ChallengeMode.GetOverallDungeonScore)
        if ok then score = math.floor(tonumber(v) or 0) end
    end

    local goal = currentGoal() or { enabled=false, target=0 }
    local target = math.max(0, math.floor(tonumber(goal.target) or 0))
    local goalEnabled = goal.enabled == true and target > 0
    local missing = goalEnabled and math.max(0, target - score) or nil
    layoutIntegratedPanel(self.panel, goalEnabled)

    self.panel.progress.label:SetText(L["SEASON_RECORDS_SHORT"])
    self.panel.progress.value:SetText(string.format("%d / %d", done, total))
    if goalEnabled then
        self.panel.target.label:SetText(L["SEASON_TARGET"])
        self.panel.current.label:SetText(L["SEASON_CURRENT"])
        self.panel.target.value:SetText(tostring(target))
        self.panel.current.value:SetText(tostring(score))
        if missing == 0 then
            self.panel.missing.label:SetText(L["SEASON_GOAL_COMPLETE_SHORT"])
            self.panel.missing.value:SetText("✓")
        else
            self.panel.missing.label:SetText(L["SEASON_MISSING"])
            self.panel.missing.value:SetText(tostring(missing))
        end
    end

    local best, runs, weeklySource = weeklySummary()
    if best then
        self.panel.weekly.value:SetText(string.format("+%d %s", best.level or 0, best.duration < math.huge and fmtTime(best.duration) or L["NO_DATA_SHORT"] or "--"))
    else
        self.panel.weekly.value:SetText(L["SEASON_NO_TIMED_WEEK_SHORT"] or "--")
    end
    self.panel.runs.value:SetText(tostring(runs))

    local icons = frame.DungeonIcons
    if type(icons) == "table" then
        for i, map in ipairs(maps) do
            local icon = icons[i]
            if type(icon) == "table" and type(icon.CreateTexture) == "function" then
                local e = self:GetDungeonDecorator(icon, i)
                self:ConfigureDungeonDecorator(e, map)
            end
        end
    end

    self.lastProgress = string.format("%d/%d", done, total)
    self.lastProgressSource = "BLIZZARD_SEASON_BEST"
    self.lastScore = score
    self.lastGoalEnabled = goalEnabled
    self.lastGoalTarget = target
    self.lastGoalCharacter = goal.key
    self.lastWeeklyRuns = runs
    self.lastWeeklyBest = best
    self.lastWeeklySource = weeklySource
    self.lastReason = reason
    return true
end

function M:Attach()
    local frame = rawget(_G, "ChallengesFrame")
    if type(frame) ~= "table" then self.attached = false; return false end
    self.frame = frame
    self.attached = true
    if not self._hookedUpdate and type(frame.Update) == "function" and type(hooksecurefunc) == "function" then
        hooksecurefunc(frame, "Update", function() M:Refresh("BLIZZARD_UPDATE") end)
        self._hookedUpdate = true
    elseif not self._hookedGlobal and type(rawget(_G, "ChallengesFrame_Update")) == "function" and type(hooksecurefunc) == "function" then
        hooksecurefunc("ChallengesFrame_Update", function(f)
            if f == M.frame then M:Refresh("BLIZZARD_UPDATE_GLOBAL") end
        end)
        self._hookedGlobal = true
    end
    self:Refresh("ATTACH")
    return true
end

function M:Initialize()
    if self.eventFrame then return end
    local f = CreateFrame("Frame")
    self.eventFrame = f
    for _, ev in ipairs({
        "ADDON_LOADED", "CHALLENGE_MODE_MAPS_UPDATE", "CHALLENGE_MODE_COMPLETED",
        "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", "WEEKLY_REWARDS_UPDATE", "PLAYER_REGEN_ENABLED",
        "SPELL_UPDATE_COOLDOWN",
    }) do f:RegisterEvent(ev) end
    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "ADDON_LOADED" then
            if arg1 == "Blizzard_ChallengesUI" then M:Attach() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            M:Refresh(event)
        elseif M.frame then
            M:Refresh(event)
        end
    end)
    self:Attach()
end

function M:ReportLines()
    local maps = seasonMaps()
    local clickable, infoOnly = 0, 0
    for _, e in pairs(self.teleportButtons) do
        if e.secure then clickable = clickable + 1 else infoOnly = infoOnly + 1 end
    end
    return {
        "frame=ChallengesFrame exists=" .. tostring(type(rawget(_G, "ChallengesFrame")) == "table"),
        "attached=" .. tostring(self.attached),
        "sidecar=false integrated=" .. tostring(self.panel ~= nil) .. " position=" .. tostring(self.panelPosition),
        "seasonMaps=" .. tostring(#maps) .. " records=" .. tostring(self.lastProgress)
            .. " progressSource=" .. tostring(self.lastProgressSource),
        "score=" .. tostring(self.lastScore) .. " goalEnabled=" .. tostring(self.lastGoalEnabled == true)
            .. " goalTarget=" .. tostring(self.lastGoalTarget or 0)
            .. " goalCharacter=" .. tostring(self.lastGoalCharacter or "none"),
        "weeklyRuns=" .. tostring(self.lastWeeklyRuns)
            .. " weeklyTimedBest=" .. tostring(self.lastWeeklyBest and self.lastWeeklyBest.level)
            .. " weeklySource=" .. tostring(self.lastWeeklySource),
        "dungeonScores=true",
        "secureTemplate=" .. tostring(self.secureTemplateWorks),
        "teleportButtons=" .. tostring(clickable + infoOnly) .. " clickable=" .. tostring(clickable) .. " infoOnly=" .. tostring(infoOnly),
        "teleportIcon=GENERIC_PORTAL",
        "blizzardDirectMutations=0",
    }
end

return M
