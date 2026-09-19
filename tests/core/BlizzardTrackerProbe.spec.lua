-- BlizzardTrackerProbe: read-only inspection of Blizzard's native Objective
-- Tracker. The mock mirrors Blizzard_ScenarioObjectiveTracker (12.1.0/12.1.5)
-- and every write, hook or region creation is recorded so the spec can prove
-- the probe never touches Blizzard frames.
local tests, assertions, failures = 0, 0, {}
local function equal(a, b, l)
    assertions = assertions + 1
    if a ~= b then error((l or "equal") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function truthy(v, l) equal(not not v, true, l) end
local function test(n, f) tests = tests + 1; local ok, e = pcall(f); if not ok then failures[#failures + 1] = n .. ": " .. tostring(e) end end

local writes

-- A region whose readers work and whose writers are recorded.
local function region(props)
    props = props or {}
    local r = { __text = props.text, __shown = props.shown ~= false, __w = props.w or 0, __h = props.h or 0 }
    function r:IsShown() return self.__shown end
    function r:GetText() return self.__text end
    function r:GetWidth() return self.__w end
    function r:GetHeight() return self.__h end
    return setmetatable(r, { __index = function(_, k)
        if type(k) == "string" and (k:match("^Set") or k:match("^Create") or k:match("^Hook")
            or k == "Show" or k == "Hide" or k == "ClearAllPoints") then
            return function() writes[#writes + 1] = k end
        end
    end })
end

local function blizzardTracker(opts)
    opts = opts or {}
    local block = region({ shown = opts.active, w = 251, h = 87 })
    block.timerID = opts.active and 1 or nil
    block.timeLimit = opts.active and 1800 or nil
    block.deathCount, block.timeLost = opts.active and 2 or nil, opts.active and 10 or nil
    block.Level = region({ text = opts.active and "Nivel 12" or nil })
    block.TimeLeft = region({ text = opts.active and "21:40" or nil })
    block.StatusBar = region()
    block.DeathCount = region({ shown = false })
    function block:IsActive() return not not self.timerID end
    function block:Activate() writes[#writes + 1] = "Activate" end
    function block:UpdateTime() writes[#writes + 1] = "UpdateTime" end
    function block:UpdateDeathCount() writes[#writes + 1] = "UpdateDeathCount" end

    local tracker = region({ shown = true })
    tracker.Header = { Text = region({ text = "Ruby Life Pools" }) }
    tracker.ChallengeModeBlock = block
    tracker.ObjectivesBlock = region()
    function tracker:LayoutContents() writes[#writes + 1] = "LayoutContents" end
    function tracker:UpdateCriteria() writes[#writes + 1] = "UpdateCriteria" end
    function tracker:MarkDirty() writes[#writes + 1] = "MarkDirty" end
    if opts.active then
        local line = { Text = region({ text = "Enemy Forces" }) }
        tracker.usedProgressBars = { [line] = { Bar = { Label = region({ text = "43%" }) }, percentage = 43, parentLine = line } }
    end
    return tracker
end

local function install(opts)
    opts = opts or {}
    writes = {}
    for _, g in ipairs({ "ScenarioObjectiveTracker", "ScenarioTimerFrame", "ScenarioObjectiveTrackerChallengeModeMixin",
        "ScenarioTrackerProgressBarMixin", "ScenarioTimerMixin", "hooksecurefunc", "issecurevariable",
        "LE_SCENARIO_TYPE_CHALLENGE_MODE", "C_AddOns", "IsAddOnLoaded", "C_Timer" }) do _G[g] = nil end
    if not opts.noBlizzard then
        _G.ScenarioObjectiveTracker = blizzardTracker(opts)
        _G.ScenarioTimerFrame = region({ shown = opts.active })
        _G.ScenarioObjectiveTrackerChallengeModeMixin = { UpdateTime = function() end }
        _G.ScenarioTrackerProgressBarMixin = { SetValue = function() end }
        _G.ScenarioTimerMixin = { CheckTimers = function() end }
        _G.LE_SCENARIO_TYPE_CHALLENGE_MODE = 8
    end
    _G.C_AddOns = { IsAddOnLoaded = function(name) return (not opts.noBlizzard) and name == "Blizzard_ObjectiveTracker" end }
    _G.hooksecurefunc = function() writes[#writes + 1] = "hooksecurefunc" end
    _G.issecurevariable = function(t, k)
        if opts.taintedKey == k then return false, "SomeAddon" end
        return true, nil
    end
    local records = {}
    _G.MitzuMPlus = {
        FlightRecorder = { Record = function(_, s, e, d) records[#records + 1] = { s = s, e = e, d = d } end },
        EventBus = { handlers = {}, On = function(self, ev, fn) self.handlers[ev] = fn end },
    }
    dofile("MitzuMPlus/modules/Tracker/BlizzardTrackerProbe.lua")
    return _G.MitzuMPlus.BlizzardTrackerProbe, records
end

test("real 12.1.5 structure is detected as enhanceable", function()
    local P = install({ active = true })
    local structure = P:ProbeStructure()
    for _, s in ipairs(structure) do truthy(s.present, s.path) end
    local ok, missing = P:IsEnhanceable(structure)
    equal(ok, true); equal(#missing, 0)
    equal(P:IsBlizzardTrackerLoaded(), true)
end)

test("the probe never writes, hooks or creates anything", function()
    local P = install({ active = true })
    P:ProbeStructure(); P:TaintBaseline(); P:LiveState(); P:ReportLines(); P:DiagnosticFields()
    P:RecordState("KEY_STARTED")
    equal(#writes, 0, table.concat(writes, ","))
end)

test("live state reads the active challenge block and the forces bar", function()
    local P = install({ active = true })
    local s = P:LiveState()
    equal(s.trackerShown, true); equal(s.header, "Ruby Life Pools")
    equal(s.blockShown, true); equal(s.blockActive, true); equal(s.blockWidth, 251); equal(s.blockHeight, 87)
    equal(s.timeLimit, 1800); equal(s.levelText, "Nivel 12"); equal(s.timeLeftText, "21:40")
    equal(s.deathCount, 2); equal(s.timeLost, 10); equal(s.timerFrameShown, true)
    equal(#s.progressBars, 1); equal(s.progressBars[1].label, "43%"); equal(s.progressBars[1].percentage, 43)
    equal(s.progressBars[1].line, "Enemy Forces")
end)

test("outside a key: inactive block keeps false, not nil", function()
    local P = install({ active = false })
    local s = P:LiveState()
    equal(s.blockActive, false); equal(s.blockShown, false); equal(s.timerFrameShown, false)
    equal(#s.progressBars, 0)
    equal((P:IsEnhanceable()), true, "structure exists even without a key")
end)

test("missing Blizzard tracker degrades without errors", function()
    local P = install({ noBlizzard = true })
    local ok, missing = P:IsEnhanceable()
    equal(ok, false); truthy(table.concat(missing, ","):find("cmUpdateTime", 1, true))
    equal(P:IsBlizzardTrackerLoaded(), false)
    local s = P:LiveState(); equal(s.blockActive, nil); equal(#s.progressBars, 0)
    local text = table.concat(P:ReportLines(), "\n")
    truthy(text:find("enhanceable=false", 1, true), text)
    truthy(text:find("MISSING ScenarioObjectiveTracker.ChallengeModeBlock.UpdateTime", 1, true), text)
end)

test("renamed internals are reported, not assumed", function()
    local P = install({ active = true })
    _G.ScenarioObjectiveTracker.ChallengeModeBlock.UpdateTime = nil
    _G.ScenarioObjectiveTracker.ChallengeModeBlock.TimeLeft = "not a region"
    local ok, missing = P:IsEnhanceable()
    equal(ok, false); equal(table.concat(missing, ","), "cmUpdateTime,cmTimeLeft")
end)

test("throwing getters and fields never escape the probe", function()
    local P = install({ active = true })
    local block = _G.ScenarioObjectiveTracker.ChallengeModeBlock
    block.IsActive = function() error("boom") end
    setmetatable(_G.ScenarioObjectiveTracker.usedProgressBars, { __pairs = function() error("pairs boom") end })
    local s = P:LiveState()
    equal(s.blockActive, nil)
    local report = table.concat(P:ReportLines(), "\n")
    truthy(report:find("=== END ===", 1, true))
end)

test("taint baseline reports secure and tainted members", function()
    local P = install({ active = true, taintedKey = "UpdateTime" })
    local byName = {}
    for _, t in ipairs(P:TaintBaseline()) do byName[t.name] = t end
    equal(byName.LayoutContents.secure, true)
    equal(byName.UpdateTime.secure, false); equal(byName.UpdateTime.taintedBy, "SomeAddon")
    local fields = {}
    for _, f in ipairs(P:DiagnosticFields()) do fields[f[1]] = f[2] end
    equal(fields.tainted, "UpdateTime:SomeAddon"); equal(fields.enhanceable, true)
    equal(fields.forcesBarLabel, "43%")
    _G.issecurevariable = nil
    equal(P:TaintBaseline()[1].secure, nil, "no taint API -> unknown")
end)

test("flight recorder: once per signature before the key, always at key start", function()
    local P, records = install({ active = false })
    local bus = _G.MitzuMPlus.EventBus
    bus.handlers.MITZU_PRE_KEY(); bus.handlers.MITZU_PRE_KEY()
    equal(#records, 1); equal(records[1].e, "BLIZZARD_PRE_KEY"); equal(records[1].d.enhanceable, true)
    bus.handlers.MITZU_KEY_STARTED()   -- no C_Timer in this mock: records immediately
    equal(#records, 2); equal(records[2].e, "BLIZZARD_KEY_STARTED")
    truthy(P)
end)

if #failures > 0 then error(string.format("BlizzardTrackerProbe: %d failures\n%s", #failures, table.concat(failures, "\n")), 0) end
return { tests = tests, assertions = assertions }
