-- ===========================================================================
-- Objective Tracker de Blizzard simulado para los bancos del enhancer.
--
-- Reproduce SOLO la estructura y el ciclo de vida que el enhancer usa, tal
-- como estan en Blizzard_ObjectiveTracker 12.1.0.69814 (rama `live` de
-- Gethe/wow-ui-source):
--   ScenarioObjectiveTracker (modulo): Update -> BeginLayout / LayoutContents /
--     EndLayout; usedProgressBars de pool (la barra de fuerzas se libera al 100 %)
--   .ChallengeModeBlock: bloque FIJO 251x87; Activate / UpdateTime / IsActive;
--     Level, TimeLeft, DeathCount(.Count), StatusBar, TimesUpLootStatus.
--     Se oculta en EndLayout cuando no esta activo (StopTimer -> timerID=nil).
--   ObjectiveTrackerFrame + QuestObjectiveTracker con un bloque de mision, para
--   comprobar que nadie los toca.
--
-- Cualquier llamada mutadora (SetPoint, SetText, Hide, SetScript...) hecha
-- sobre un frame de Blizzard FUERA de este mock queda en `BT.foreign`.
--
--   local BT = dofile("tests/harness/blizzard_tracker_mock.lua")
--   BT.install()   BT.activate(elapsed, limit)   BT.setForces(true|false)
--   BT.layout()    BT.stopTimer()   BT.setDeaths(n)   BT.uninstall()
-- ===========================================================================

local BT = { foreign = {}, internal = 0, layouts = 0 }

-- dev.11: SetFont/SetFontObject entran en la lista. Toda la iteracion va de
-- tipografia, y hasta ahora se podia reescribir la fuente del reloj de Blizzard
-- sin que este guardia dijera nada.
local MUTATORS = { "SetPoint", "ClearAllPoints", "SetAllPoints", "SetParent", "SetScale", "SetAlpha",
    "SetHeight", "SetWidth", "SetSize", "Show", "Hide", "SetShown", "SetText", "SetFormattedText",
    "SetTextColor", "SetFont", "SetFontObject", "SetScript", "HookScript", "SetValue",
    "SetMinMaxValues", "EnableMouse", "RegisterEvent", "UnregisterEvent",
    "SetFrameStrata", "SetFrameLevel" }

local function internal(fn, ...)
    BT.internal = BT.internal + 1
    local r = { pcall(fn, ...) }
    BT.internal = BT.internal - 1
    if not r[1] then error(r[2], 0) end
    return select(2, (table.unpack or unpack)(r))
end

-- Vigila los mutadores de un frame/region de Blizzard.
local function watch(obj, label)
    for _, name in ipairs(MUTATORS) do
        local original = obj[name]
        if type(original) == "function" then
            obj[name] = function(self, ...)
                if BT.internal == 0 then BT.foreign[#BT.foreign + 1] = label .. ":" .. name end
                return original(self, ...)
            end
        end
    end
    return obj
end

local function clock(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

function BT.install(opts)
    opts = opts or {}
    BT.foreign, BT.layouts = {}, 0
    return internal(function()
        local container = watch(CreateFrame("Frame", "ObjectiveTrackerFrame", UIParent), "ObjectiveTrackerFrame")
        local quests = watch(CreateFrame("Frame", "QuestObjectiveTracker", container), "QuestObjectiveTracker")
        quests.questBlock = watch(CreateFrame("Frame", nil, quests), "QuestBlock")
        quests.questBlock.HeaderText = watch(quests.questBlock:CreateFontString(), "QuestBlock.HeaderText")
        quests.questBlock.HeaderText:SetText("Una mision")

        local tracker = watch(CreateFrame("Frame", "ScenarioObjectiveTracker", container), "ScenarioObjectiveTracker")
        tracker.usedProgressBars = {}
        tracker.ObjectivesBlock = watch(CreateFrame("Frame", nil, tracker), "ObjectivesBlock")
        tracker.ObjectivesBlock.forcesLine = watch(tracker.ObjectivesBlock:CreateFontString(), "ForcesLine")

        local block = CreateFrame("Frame", nil, tracker)
        block:SetSize(opts.blockWidth or 251, 87)
        block.height = 87
        block:Hide()
        block.Level = watch(block:CreateFontString(), "Level")
        block.TimeLeft = watch(block:CreateFontString(), "TimeLeft")
        block.StatusBar = watch(CreateFrame("StatusBar", nil, block), "StatusBar")
        block.TimesUpLootStatus = watch(CreateFrame("Frame", nil, block), "TimesUpLootStatus")
        block.TimesUpLootStatus:Hide()
        block.DeathCount = watch(CreateFrame("Frame", nil, block), "DeathCount")
        block.DeathCount.Count = watch(block.DeathCount:CreateFontString(), "DeathCount.Count")
        block.DeathCount:Hide()
        watch(block, "ChallengeModeBlock")

        function block:IsActive() return not not self.timerID end
        function block:UpdateTime(elapsed)
            internal(function()
                local left = math.max(0, self.timeLimit - elapsed)
                self.TimeLeft:SetText(clock(left))
                self.TimesUpLootStatus:SetShown(left == 0)
            end)
        end
        function block:Activate(timerID, elapsed, limit)
            internal(function()
                self.timerID, self.timeLimit = timerID, limit
                self.Level:SetText("Nivel " .. tostring(opts.level or 12))
                self:UpdateTime(elapsed)
            end)
            BT.layout()
        end
        function tracker:EndLayout()
            internal(function()
                for key, bar in pairs(self.usedProgressBars) do
                    if not bar.used then
                        self.usedProgressBars[key] = nil
                        bar:Hide(); bar:ClearAllPoints()
                        BT.pool[#BT.pool + 1] = bar
                    end
                end
                block:SetShown(block.__layoutUsed == true)
            end)
        end
        tracker.ChallengeModeBlock = block
        BT.tracker, BT.block, BT.quests, BT.pool = tracker, block, quests, BT.pool or {}
        BT.forces = false
        return tracker
    end)
end

-- ObjectiveTrackerModuleMixin:Update simplificado: BeginLayout, LayoutContents
-- (bloque M+ si activo, barra de fuerzas si procede) y EndLayout.
function BT.layout()
    local tracker, block = BT.tracker, BT.block
    BT.layouts = BT.layouts + 1
    internal(function()
        for _, bar in pairs(tracker.usedProgressBars) do bar.used = nil end
        block.__layoutUsed = block:IsActive()
        if block.__layoutUsed and BT.forces then
            local line = tracker.ObjectivesBlock.forcesLine
            local bar = tracker.usedProgressBars[line]
            if not bar then
                bar = table.remove(BT.pool or {}) or CreateFrame("Frame", nil, tracker.ObjectivesBlock)
                if not rawget(bar, "Bar") then
                    bar.Bar = CreateFrame("StatusBar", nil, bar)
                    bar.Bar:SetSize(191, 17)
                    bar.Bar.Label = bar.Bar:CreateFontString()
                    watch(bar, "ProgressBar"); watch(bar.Bar, "ProgressBar.Bar"); watch(bar.Bar.Label, "ProgressBar.Label")
                end
                tracker.usedProgressBars[line] = bar
                bar:Show()
            end
            bar.used = true
        end
    end)
    tracker:EndLayout()
end

function BT.activate(elapsed, limit)
    BT.block:Activate(1, elapsed or 0, limit or 1800)
end
function BT.tick(elapsed) BT.block:UpdateTime(elapsed) end
function BT.setForces(on) BT.forces = on and true or false; BT.layout() end
function BT.setDeaths(n)
    internal(function()
        BT.block.DeathCount:SetShown(n > 0)
        BT.block.DeathCount.Count:SetText(tostring(n))
    end)
end
-- ScenarioTimerMixin:StopTimer -> timerID=nil -> MarkDirty -> layout oculta el bloque.
function BT.stopTimer()
    BT.block.timerID = nil
    BT.layout()
end
function BT.uninstall()
    _G.ScenarioObjectiveTracker, _G.ObjectiveTrackerFrame, _G.QuestObjectiveTracker = nil, nil, nil
end

return BT
