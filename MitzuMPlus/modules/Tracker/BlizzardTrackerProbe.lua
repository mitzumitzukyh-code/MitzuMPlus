-- ===========================================================================
-- MitzuMPlus - Tracker/BlizzardTrackerProbe  (1.1.0)
--
-- SONDA DE SOLO LECTURA del Objective Tracker nativo de Blizzard.
--
-- 1.1 no crea un HUD propio: BlizzardTrackerEnhancer (fase visual) decorara
-- el bloque de Mythic+ que ya pinta Blizzard. Antes de enganchar nada hay que
-- confirmar EN EL CLIENTE REAL que existen los frames, metodos y regiones que
-- dice el codigo fuente. Esta sonda lo comprueba y no toca nada:
--   * no llama a hooksecurefunc, no crea regiones, no escribe texto;
--   * solo indexa campos (en pcall) y llama a metodos puros (IsShown, GetText,
--     GetWidth, IsActive -> `not not self.timerID`);
--   * guarda una linea base de taint con issecurevariable ANTES de que el
--     potenciador exista, para poder demostrar despues que no lo introduce.
--
-- ORIGEN DE LOS NOMBRES (auditoria de Blizzard_ObjectiveTracker, identico en
-- Retail 12.1.0.69814 y PTR 12.1.5.69594):
--   ScenarioObjectiveTracker                  frame global, ScenarioObjectiveTrackerMixin
--     .ChallengeModeBlock                     bloque fijo M+ (251x87):
--         :Activate(timerID, elapsed, limit)  al detectar el timer de la llave
--         :UpdateTime(elapsed)                cada frame via ScenarioTimerFrame
--         :IsActive() :UpdateDeathCount()
--         .Level .TimeLeft .StatusBar .DeathCount .TimerBG .timeLimit .timerID
--     .ObjectivesBlock                        lineas de criterios (bosses)
--     :LayoutContents() :UpdateCriteria(n)    reconstruccion del modulo
--     .usedProgressBars[line]                 barra de fuerzas (ScenarioProgressBarTemplate)
--         .Bar.Label  -> "%d%%" de criteriaInfo.quantity (porcentaje ENTERO)
--   ScenarioTimerFrame                        OnUpdate que llama a UpdateTime
-- ===========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local BTP = {}
MitzuMPlus.BlizzardTrackerProbe = BTP

BTP.VERSION = 1
BTP.BLIZZARD_ADDON = "Blizzard_ObjectiveTracker"

local function indexField(t, k) return t[k] end

-- Campo anidado "a.b.c" desde una raiz, sin errores ni metodos.
local function field(root, path)
    local node = root
    for part in tostring(path):gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        local ok, v = pcall(indexField, node, part)
        if not ok then return nil end
        node = v
    end
    return node
end
BTP.Field = field

-- Metodo puro protegido. Devuelve ok, valor.
local function pure(obj, name, ...)
    local fn = field(obj, name)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, obj, ...)
    if not ok then return false end
    return true, v
end

-- Que se espera encontrar. kind: frame | method | region | mixinMethod | global.
BTP.EXPECTED = {
    { key = "tracker",           path = "ScenarioObjectiveTracker",                         kind = "frame",  required = true },
    { key = "trackerLayout",     path = "ScenarioObjectiveTracker.LayoutContents",          kind = "method", required = true },
    { key = "trackerCriteria",   path = "ScenarioObjectiveTracker.UpdateCriteria",          kind = "method" },
    { key = "trackerDirty",      path = "ScenarioObjectiveTracker.MarkDirty",               kind = "method" },
    { key = "cmBlock",           path = "ScenarioObjectiveTracker.ChallengeModeBlock",      kind = "frame",  required = true },
    { key = "cmActivate",        path = "ScenarioObjectiveTracker.ChallengeModeBlock.Activate",   kind = "method", required = true },
    { key = "cmUpdateTime",      path = "ScenarioObjectiveTracker.ChallengeModeBlock.UpdateTime", kind = "method", required = true },
    { key = "cmIsActive",        path = "ScenarioObjectiveTracker.ChallengeModeBlock.IsActive",   kind = "method" },
    { key = "cmDeaths",          path = "ScenarioObjectiveTracker.ChallengeModeBlock.UpdateDeathCount", kind = "method" },
    { key = "cmLevel",           path = "ScenarioObjectiveTracker.ChallengeModeBlock.Level",      kind = "region" },
    { key = "cmTimeLeft",        path = "ScenarioObjectiveTracker.ChallengeModeBlock.TimeLeft",   kind = "region", required = true },
    { key = "cmStatusBar",       path = "ScenarioObjectiveTracker.ChallengeModeBlock.StatusBar",  kind = "region", required = true },
    { key = "cmDeathCount",      path = "ScenarioObjectiveTracker.ChallengeModeBlock.DeathCount", kind = "region" },
    { key = "objectivesBlock",   path = "ScenarioObjectiveTracker.ObjectivesBlock",         kind = "frame" },
    { key = "timerFrame",        path = "ScenarioTimerFrame",                               kind = "frame" },
    { key = "cmMixin",           path = "ScenarioObjectiveTrackerChallengeModeMixin.UpdateTime", kind = "mixinMethod" },
    { key = "barMixin",          path = "ScenarioTrackerProgressBarMixin.SetValue",         kind = "mixinMethod" },
    { key = "timerMixin",        path = "ScenarioTimerMixin.CheckTimers",                   kind = "mixinMethod" },
    { key = "hookApi",           path = "hooksecurefunc",                                   kind = "global", required = true },
    { key = "taintApi",          path = "issecurevariable",                                 kind = "global" },
    { key = "scenarioTypeCM",    path = "LE_SCENARIO_TYPE_CHALLENGE_MODE",                  kind = "global" },
}

-- Metodos cuya seguridad se vigila (linea base de taint).
BTP.TAINT_WATCH = {
    { "ScenarioObjectiveTracker", "LayoutContents" },
    { "ScenarioObjectiveTracker", "UpdateCriteria" },
    { "ScenarioObjectiveTracker.ChallengeModeBlock", "Activate" },
    { "ScenarioObjectiveTracker.ChallengeModeBlock", "UpdateTime" },
    { "ScenarioObjectiveTracker.ChallengeModeBlock", "timeLimit" },
}

local function kindMatches(kind, v)
    if kind == "method" or kind == "mixinMethod" then return type(v) == "function" end
    if kind == "frame" or kind == "region" then
        return type(v) == "table" and type(field(v, "IsShown")) == "function"
    end
    if kind == "global" then return v ~= nil end
    return false
end

function BTP:IsBlizzardTrackerLoaded()
    local fn = field(_G, "C_AddOns.IsAddOnLoaded") or rawget(_G, "IsAddOnLoaded")
    if type(fn) ~= "function" then return nil end
    local ok, loaded = pcall(fn, BTP.BLIZZARD_ADDON)
    if not ok then return nil end
    return loaded == true
end

-- Lista { key, path, kind, required, present }.
function BTP:ProbeStructure()
    local out = {}
    for _, e in ipairs(BTP.EXPECTED) do
        local v = field(_G, e.path)
        out[#out + 1] = { key = e.key, path = e.path, kind = e.kind,
                          required = e.required == true, present = kindMatches(e.kind, v) }
    end
    return out
end

-- true si todo lo imprescindible para decorar el bloque M+ esta presente.
function BTP:IsEnhanceable(structure)
    structure = structure or self:ProbeStructure()
    local missing = {}
    for _, s in ipairs(structure) do
        if s.required and not s.present then missing[#missing + 1] = s.key end
    end
    return #missing == 0, missing
end

-- { owner, name, secure, taintedBy } por metodo vigilado. secure=nil si la
-- API de taint no existe.
function BTP:TaintBaseline()
    local out = {}
    local check = rawget(_G, "issecurevariable")
    for _, w in ipairs(BTP.TAINT_WATCH) do
        local owner = field(_G, w[1])
        local entry = { owner = w[1], name = w[2] }
        if type(check) == "function" and type(owner) == "table" then
            local ok, secure, taintedBy = pcall(check, owner, w[2])
            if ok then entry.secure, entry.taintedBy = secure, taintedBy end
        end
        out[#out + 1] = entry
    end
    return out
end

-- Valor de un metodo puro, conservando false (nil solo si no se pudo llamar).
local function pureValue(obj, name)
    local ok, v = pure(obj, name)
    if ok then return v end
    return nil
end

local function text(v)
    local S = MitzuMPlus.QASafe
    if S then return S.Text(v) end
    return v == nil and "nil" or tostring(v)
end

local function regionText(region)
    return pureValue(region, "GetText")
end

-- Estado visible del bloque M+ y de las barras de progreso del modulo.
function BTP:LiveState()
    local s = { loaded = self:IsBlizzardTrackerLoaded() }
    local tracker = field(_G, "ScenarioObjectiveTracker")
    local block = field(tracker, "ChallengeModeBlock")
    s.trackerShown = pureValue(tracker, "IsShown")
    s.header = regionText(field(tracker, "Header.Text"))
    if type(block) == "table" then
        s.blockShown = pureValue(block, "IsShown")
        s.blockActive = pureValue(block, "IsActive")
        s.blockWidth = pureValue(block, "GetWidth")
        s.blockHeight = pureValue(block, "GetHeight")
        s.timeLimit = field(block, "timeLimit")
        s.timerID = field(block, "timerID")
        s.levelText = regionText(field(block, "Level"))
        s.timeLeftText = regionText(field(block, "TimeLeft"))
        s.deathCount = field(block, "deathCount")
        s.timeLost = field(block, "timeLost")
    end
    local timerFrame = field(_G, "ScenarioTimerFrame")
    s.timerFrameShown = pureValue(timerFrame, "IsShown")

    s.progressBars = {}
    local bars = field(tracker, "usedProgressBars")
    if type(bars) == "table" then
        local ok = pcall(function()
            for _, bar in pairs(bars) do
                if type(bar) == "table" then
                    s.progressBars[#s.progressBars + 1] = {
                        label = regionText(field(bar, "Bar.Label")),
                        percentage = field(bar, "percentage"),
                        line = regionText(field(bar, "parentLine.Text")),
                    }
                end
            end
        end)
        if not ok then s.progressBarsError = true end
    end
    return s
end

function BTP:ReportLines()
    local L = { "=== MitzuMPlus [DEV] Blizzard Objective Tracker probe v" .. BTP.VERSION .. " ===" }
    L[#L + 1] = "readOnly=true (esta sonda no engancha ni modifica nada)"
    local structure = self:ProbeStructure()
    local enhanceable, missing = self:IsEnhanceable(structure)
    L[#L + 1] = "blizzardAddonLoaded=" .. text(self:IsBlizzardTrackerLoaded())
    L[#L + 1] = "enhanceable=" .. text(enhanceable) .. ((#missing > 0) and (" missing=" .. table.concat(missing, ",")) or "")

    L[#L + 1] = ""
    L[#L + 1] = "[STRUCTURE]"
    for _, s in ipairs(structure) do
        L[#L + 1] = string.format("%s %s (%s%s)", s.present and "PRESENT" or "MISSING", s.path, s.kind,
            s.required and ",required" or "")
    end

    L[#L + 1] = ""
    L[#L + 1] = "[TAINT BASELINE]"
    for _, t in ipairs(self:TaintBaseline()) do
        L[#L + 1] = string.format("%s.%s secure=%s taintedBy=%s", t.owner, t.name, text(t.secure), text(t.taintedBy))
    end

    L[#L + 1] = ""
    L[#L + 1] = "[LIVE]"
    local live = self:LiveState()
    L[#L + 1] = string.format("trackerShown=%s header=%s timerFrameShown=%s",
        text(live.trackerShown), text(live.header), text(live.timerFrameShown))
    L[#L + 1] = string.format("challengeBlock shown=%s active=%s size=%sx%s timerID=%s timeLimit=%s",
        text(live.blockShown), text(live.blockActive), text(live.blockWidth), text(live.blockHeight),
        text(live.timerID), text(live.timeLimit))
    L[#L + 1] = string.format("challengeBlock level=%s timeLeft=%s deaths=%s timeLost=%s",
        text(live.levelText), text(live.timeLeftText), text(live.deathCount), text(live.timeLost))
    if #live.progressBars == 0 then
        L[#L + 1] = "progressBars=none"
    end
    for i, b in ipairs(live.progressBars) do
        L[#L + 1] = string.format("progressBar[%d] label=%s percentage=%s line=%s", i, text(b.label),
            text(b.percentage), text(b.line))
    end
    if live.progressBarsError then L[#L + 1] = "progressBarsError=true" end
    L[#L + 1] = "=== END ==="
    return L
end

function BTP:DiagnosticFields()
    local enhanceable, missing = self:IsEnhanceable()
    local live = self:LiveState()
    local tainted = {}
    for _, t in ipairs(self:TaintBaseline()) do
        if t.secure == false then tainted[#tainted + 1] = t.name .. ":" .. tostring(t.taintedBy) end
    end
    return {
        { "probeVersion", BTP.VERSION },
        { "blizzardAddonLoaded", self:IsBlizzardTrackerLoaded() },
        { "enhanceable", enhanceable },
        { "missing", (#missing > 0) and table.concat(missing, ",") or "none" },
        { "tainted", (#tainted > 0) and table.concat(tainted, ",") or "none" },
        { "challengeBlockActive", live.blockActive },
        { "challengeBlockShown", live.blockShown },
        { "timeLeftText", live.timeLeftText },
        { "forcesBarLabel", live.progressBars[1] and live.progressBars[1].label or nil },
    }
end

-- Caja negra: estructura al preparar y al empezar la llave, solo si cambia.
function BTP:RecordState(label)
    local enhanceable, missing = self:IsEnhanceable()
    local sig = tostring(enhanceable) .. ":" .. table.concat(missing, ",")
    local live = self:LiveState()
    local FR = MitzuMPlus.FlightRecorder
    if not (FR and FR.Record) then return false end
    if label == "PRE_KEY" and sig == self._lastSignature then return false end
    self._lastSignature = sig
    FR:Record("TRACKER", "BLIZZARD_" .. tostring(label), {
        enhanceable = enhanceable, missing = (#missing > 0) and table.concat(missing, ",") or nil,
        active = live.blockActive, shown = live.blockShown, bars = #live.progressBars,
    })
    return true
end

local bus = MitzuMPlus.EventBus
if bus and bus.On then
    bus:On("MITZU_PRE_KEY", function() BTP:RecordState("PRE_KEY") end)
    -- El bloque se activa con el timer, que llega poco despues del arranque.
    bus:On("MITZU_KEY_STARTED", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(5, function() BTP:RecordState("KEY_STARTED") end)
        else
            BTP:RecordState("KEY_STARTED")
        end
    end)
end

return BTP
