-- Tests de simulacion de ArrowDemo + ArrowDemoTelemetry + NameplateGenerations.
-- No se carga desde el TOC. Ejecutar con: python tests/run_lua_tests.py
--
-- Se cargan los modulos REALES de produccion que la demo comparte o no debe
-- tocar: RouteArrows (con su pool de verdad), GuidanceEngine, Presenter,
-- PullUnitResolver, PackEvidence, EventBus y la ruta empaquetada de Ruby Life
-- Pools. Solo son simulados el cliente, el resolver, las dos evidencias en
-- vivo y el contexto de la llave.

local assertions, tests = 0, 0

local function equal(actual, expected, label)
    assertions = assertions + 1
    if actual ~= expected then
        error(string.format("%s: esperado %s, recibido %s",
            label or "equal", tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(value, label)
    assertions = assertions + 1
    if not value then error((label or "truthy") .. ": valor falso", 2) end
end

local function test(name, fn)
    tests = tests + 1
    local ok, err = pcall(fn)
    if not ok then error("TEST " .. name .. "\n" .. tostring(err), 0) end
end

-- ── Valores prohibidos ─────────────────────────────────────────────────────

local SECRET_NUM  = 999777
local SECRET_NAME = "S3CR3T_DUNGEON_NAME"
local HOSTIL = setmetatable({}, {
    __tostring = function() error("PROHIBIDO: tostring de un valor hostil") end,
    __concat   = function() error("PROHIBIDO: concatenar un valor hostil") end,
    __eq       = function() error("PROHIBIDO: comparar un valor hostil") end,
    __lt       = function() error("PROHIBIDO: ordenar un valor hostil") end,
    __index    = function() error("PROHIBIDO: leer dentro de un valor hostil") end,
})

function issecretvalue(v)
    if type(v) == "table" then return true end
    return v == SECRET_NUM or v == SECRET_NAME
end

-- ── Mundo simulado ─────────────────────────────────────────────────────────

local world = {
    time = 1000, state = "RUNNING", elapsed = 0, startedAt = 1788000000,
    pull = 1, plates = {}, visible = {}, engagement = {}, pointed = {},
    cast = {}, recentEvent = {},
    dungeonName = "Ruby Life Pools",
}

function GetTime() return world.time end
function date() return "2026-09-11 20:00:00" end

local frames = {}
local function magicFrame(kind)
    local f = { _kind = kind, _events = {}, _shown = false }
    return setmetatable(f, { __index = function(_, k)
        if k == "RegisterEvent" then return function(self, e) self._events[e] = true end end
        if k == "UnregisterEvent" then return function(self) self._unregistered = true end end
        if k == "SetScript" then
            return function(self, s, fn) if s == "OnEvent" then self._onEvent = fn end end
        end
        if k == "Show" then return function(self) self._shown = true end end
        if k == "Hide" then return function(self) self._shown = false end end
        if k == "IsShown" then return function(self) return self._shown end end
        if k == "GetObjectType" then return function() return kind or "Frame" end end
        if k == "GetFrameLevel" then return function() return 1 end end
        if k == "CreateTexture" or k == "CreateFontString"
           or k == "CreateAnimationGroup" or k == "CreateAnimation" then
            return function() return magicFrame("Region") end
        end
        return function() end
    end })
end

function CreateFrame(kind)
    local f = magicFrame(kind)
    frames[#frames + 1] = f
    return f
end
UIParent = magicFrame("Frame")

-- Orden normal: el de registro (orden de carga). El cliente no lo garantiza,
-- asi que hay pruebas que disparan al reves.
local function fire(event, ...)
    for _, f in ipairs(frames) do
        if f._events[event] and f._onEvent then f._onEvent(f, event, ...) end
    end
end
local function fireReverse(event, ...)
    for i = #frames, 1, -1 do
        local f = frames[i]
        if f._events[event] and f._onEvent then f._onEvent(f, event, ...) end
    end
end

local function makePlate(tok)
    return {
        unitToken = tok, namePlateUnitToken = tok,
        GetObjectType = function() return "Frame" end,
        GetFrameLevel = function() return 1 end,
        UnitFrame = { GetObjectType = function() return "Frame" end,
                      GetFrameLevel = function() return 2 end },
    }
end

C_NamePlate = {
    GetNamePlates = function()
        local out = {}
        for _, t in ipairs(world.visible) do out[#out + 1] = world.plates[t] end
        return out
    end,
    GetNamePlateForUnit = function(tok) return world.plates[tok] end,
}
C_Texture = { GetAtlasInfo = function(n)
    if n == "NPE_ArrowDown" then return { width = 30, height = 24 } end
end }
function UnitExists(u) return world.plates[u] ~= nil end
function UnitIsUnit(a, b) return a == b end

local tickers = {}
C_Timer = {
    NewTicker = function(secs, fn)
        local h = { secs = secs, fn = fn, cancelled = false }
        function h:Cancel() self.cancelled = true end
        tickers[#tickers + 1] = h
        return h
    end,
    After = function() end,
}

-- ── Addon ──────────────────────────────────────────────────────────────────

local printed = {}
MitzuMPlus = { AdaptiveRoute = {}, Print = function(_, m) printed[#printed + 1] = m end }
_G.MitzuMPlus = MitzuMPlus
function LibStub() return { GetAddon = function() return MitzuMPlus end } end
MPlusAdaptiveRouteDB = {}

dofile("modules/EventBus.lua")
local bus = MitzuMPlus.EventBus

MitzuMPlus.DungeonContext = {
    GetState = function() return world.state end,
    GetChallengeMapID = function() return 399 end,
    GetKeystoneLevel = function() return 12 end,
    GetDungeonName = function() return world.dungeonName end,
}
MitzuMPlus.ChallengeClock = {
    GetElapsed = function() return world.state == "RUNNING" and world.elapsed or nil end,
    GetStartedAt = function() return world.startedAt end,
}

-- La ruta de verdad, no una inventada.
local ROUTE
MitzuMPlus.NativeRouteDB = { Register = function(_, r) ROUTE = r; return true end }
dofile("data/Routes/Season2/RubyLifePools.lua")
assert(ROUTE and #ROUTE.pulls == 11, "no se cargo la ruta real")

local rpCalls = { SetPull = 0, NextPull = 0, PreviousPull = 0, RestorePull = 0 }
MitzuMPlus.RouteProgress = {
    GetState = function() return "ACTIVE" end,
    GetRoute = function() return ROUTE end,
    GetPullIndex = function() return world.pull end,
    GetPullCount = function() return #ROUTE.pulls end,
    GetCurrentPull = function() return ROUTE.pulls[world.pull] end,
    SetPull = function(self, n, reason)
        rpCalls.SetPull = rpCalls.SetPull + 1
        local prev = world.pull
        world.pull = n
        bus:Emit("MITZU_PULL_CHANGED", n, prev, reason or "UNKNOWN", self)
        return true, n
    end,
    NextPull = function(self, reason)
        rpCalls.NextPull = rpCalls.NextPull + 1
        return self:SetPull(world.pull + 1, reason or "MANUAL")
    end,
    PreviousPull = function() rpCalls.PreviousPull = rpCalls.PreviousPull + 1 end,
    RestorePull = function() rpCalls.RestorePull = rpCalls.RestorePull + 1 end,
}
local function rpTotal()
    return rpCalls.SetPull + rpCalls.NextPull + rpCalls.PreviousPull + rpCalls.RestorePull
end

function MitzuMPlus:_VisibleNameplates()
    local out = {}
    for _, t in ipairs(world.visible) do out[#out + 1] = t end
    table.sort(out)
    return out
end

local AR = MitzuMPlus.AdaptiveRoute

-- Evidencias en vivo: simuladas con el vocabulario canonico.
AR.EngagementEvidence = { Evaluate = function(_, tok)
    local v = world.engagement[tok]
    if v == "ERROR" then error("mock engagement failure") end
    return v or "NOT_ENGAGED"
end }
AR.UnitLinkEvidence = { Evaluate = function(_, tok, clase)
    local p = world.pointed[tok]
    return (p and p[clase]) and "SAME_UNIT" or "DIFFERENT_UNIT"
end }
AR.CastEvidence = { Evaluate = function(_, tok)
    return world.cast[tok] or "NOT_CASTING"
end }
AR.EventCastEvidence = { InspectToken = function(_, tok)
    return { eventState = world.recentEvent[tok] and "SEEN" or "NONE",
             safeSpellIDValue = SECRET_NUM }
end }

-- Resolver simulado: identidad secreta, nunca MATCH. Se cuentan sus llamadas.
local lerCalls = 0
AR.LiveEnemyResolver = { ResolveForGuidance = function()
    lerCalls = lerCalls + 1
    return "UNKNOWN"
end }

dofile("modules/AdaptiveRoute/PackEvidence.lua")
dofile("modules/AdaptiveRoute/RouteArrows.lua")
dofile("modules/AdaptiveRoute/PullUnitResolver.lua")
dofile("modules/GuidanceEngine.lua")
dofile("modules/RouteArrowPresenter.lua")
dofile("modules/AdaptiveRoute/NameplateGenerations.lua")
dofile("modules/AdaptiveRoute/ArrowDemoTelemetry.lua")
dofile("modules/AdaptiveRoute/ArrowDemo.lua")

local RA  = AR.RouteArrows
local G   = MitzuMPlus.GuidanceEngine
local Pr  = MitzuMPlus.RouteArrowPresenter
local NG  = AR.NameplateGenerations
local TEL = AR.ArrowDemoTelemetry
local AD  = AR.ArrowDemo

-- ── Utilidades del escenario ───────────────────────────────────────────────

local function addPlate(tok, eng)
    world.plates[tok] = makePlate(tok)
    world.visible[#world.visible + 1] = tok
    world.engagement[tok] = eng or "NOT_ENGAGED"
    fire("NAME_PLATE_UNIT_ADDED", tok)
end

local function dropVisible(tok)
    for i = #world.visible, 1, -1 do
        if world.visible[i] == tok then table.remove(world.visible, i) end
    end
    world.plates[tok] = nil
end

local function removePlate(tok, reverse)
    dropVisible(tok)
    if reverse then fireReverse("NAME_PLATE_UNIT_REMOVED", tok)
    else fire("NAME_PLATE_UNIT_REMOVED", tok) end
end

local function tick(dt)
    world.time = world.time + (dt or 0.4)
    AD:SafeTick()
end

local function resetWorld()
    for _, tok in ipairs(world.visible) do world.plates[tok] = nil end
    world.visible, world.engagement, world.pointed = {}, {}, {}
    world.cast, world.recentEvent = {}, {}
    world.state, world.pull, world.elapsed = "RUNNING", 1, 0
    world.dungeonName = "Ruby Life Pools"
end

local function demoOn()
    if not AD:IsEnabled() then AD:SetEnabled(true) end
end
local function demoOff()
    if AD:IsEnabled() then AD:SetEnabled(false) end
end

local function fresh()
    demoOff()
    for _, tok in ipairs(world.visible) do fire("NAME_PLATE_UNIT_REMOVED", tok) end
    resetWorld()
    RA:ClearAll()
    Pr:ClearAll()
    TEL:ClearStored()
    TEL:Store().current = nil
    printed = {}
end

test("alignment observation carries states, never the event payload", function()
    fresh()
    addPlate("nameplate1", "ENGAGED")
    world.pointed.nameplate1 = { TARGET = true }
    world.cast.nameplate1 = "CASTING"
    world.recentEvent.nameplate1 = true
    local obs = AD:_Observe(world.time)
    equal(#obs, 1, "una observacion")
    equal(obs[1].castState, "CASTING", "estado de cast")
    equal(obs[1].recentEvent, "RECENT_EVENT", "evento temporal")
    equal(obs[1].tokenLink, "TARGET", "enlace de token")
    equal(obs[1].safeSpellIDValue, nil, "payload no transportado")
    equal(obs[1].spellID, nil, "identidad de cast no transportada")
end)

local function events(run)
    run = run or TEL:GetRun(nil)
    return (run and run.events) or {}
end
local function find(run, pattern)
    for i, l in ipairs(events(run)) do
        if l:find(pattern) then return i, l end
    end
    return nil
end
local function countLines(run, pattern)
    local n = 0
    for _, l in ipairs(events(run)) do if l:find(pattern) then n = n + 1 end end
    return n
end
local function demoTokens()
    local out = {}
    for _, m in ipairs(AD:GetMarks()) do out[#out + 1] = m.token end
    return table.concat(out, ",")
end
local function poolOK()
    local st = RA._stats
    return (st.acquired - st.released) == RA:CountActive()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- VOCABULARIO
-- ═══════════════════════════════════════════════════════════════════════════

test("closed vocabulary, never MATCH", function()
    equal(AD.STATES.DEMO_CANDIDATE, "DEMO_CANDIDATE", "candidate")
    equal(AD.STATES.DEMO_MARKED, "DEMO_MARKED", "marked")
    equal(AD.STATES.DEMO_SKIPPED, "DEMO_SKIPPED", "skipped")
    equal(AD.STATES.DEMO_UNKNOWN, "DEMO_UNKNOWN", "unknown")
    equal(AD.STATES.MATCH, nil, "no MATCH state")
    equal(AD.REASONS.MATCH, nil, "no MATCH reason")
    -- "GENERATION_MISMATCH" es un problema de generaciones, no una identidad:
    -- se descarta antes de buscar la palabra.
    local function sinMismatch(s) return (s:gsub("MISMATCH", "")) end
    for code in pairs(TEL.CODES) do
        equal(sinMismatch(code):find("MATCH", 1, true), nil, "telemetry code " .. code)
    end
    for r in pairs(AD.REASONS) do
        equal(sinMismatch(r):find("MATCH", 1, true), nil, "reason " .. r)
    end
    equal(TEL.FORMAT, "MITZU_ARROW_DEMO_TELEMETRY_V1", "format")
    truthy(AD.BANNER:find("no representa identidad", 1, true), "banner wording")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- HEURISTICA PURA
-- ═══════════════════════════════════════════════════════════════════════════

local function obs(list)
    local out = {}
    for _, o in ipairs(list) do
        out[#out + 1] = { token = o[1], gen = o[2], engagement = o[3], pointed = o[4] }
    end
    return out
end

test("decide: not running removes everything", function()
    local plan = AD:Decide({ now = 5, running = false,
        marks = { nameplate1 = { gen = 1 }, nameplate2 = { gen = 2 } } })
    equal(plan.phase, "INACTIVE", "phase")
    equal(#plan.remove, 2, "removals")
    equal(plan.remove[1].reason, "NOT_RUNNING", "reason")
    equal(#plan.add, 0, "no adds")
end)

test("decide: execution marks engaged up to cap, by first engagement", function()
    local plan = AD:Decide({ now = 10, running = true, expected = 3,
        obs = obs({ { "nameplate1", 11, "ENGAGED" }, { "nameplate2", 12, "ENGAGED" },
                    { "nameplate3", 13, "ENGAGED" }, { "nameplate4", 14, "ENGAGED" },
                    { "nameplate5", 15, "NOT_ENGAGED" } }),
        marks = {}, firstEngaged = { [11] = 9, [12] = 5, [13] = 7, [14] = 8 } })
    equal(plan.phase, "EXECUTION", "phase")
    equal(plan.cap, 3, "cap from expected")
    equal(#plan.add, 3, "three adds")
    local added = {}
    for _, a in ipairs(plan.add) do added[a.token] = a.reason end
    truthy(added.nameplate2 and added.nameplate3 and added.nameplate4, "earliest engaged win")
    equal(added.nameplate1, nil, "latest engaged left out")
    equal(plan.add[1].reason, "ENGAGED_IN_EXECUTION", "reason")
    equal(#plan.skipped, 1, "one skipped")
    equal(plan.skipped[1].reason, "OVER_CAP", "skip reason")
    equal(plan.states.nameplate1, "DEMO_SKIPPED", "state skipped")
    equal(plan.states.nameplate5, nil, "not engaged gets no state in execution")
end)

test("decide: an existing arrow is never displaced (stability)", function()
    local plan = AD:Decide({ now = 10, running = true, expected = 2,
        obs = obs({ { "nameplate1", 1, "ENGAGED" }, { "nameplate2", 2, "ENGAGED" },
                    { "nameplate3", 3, "ENGAGED" } }),
        marks = { nameplate2 = { gen = 2, lastEngagedAt = 9 },
                  nameplate3 = { gen = 3, lastEngagedAt = 9 } },
        firstEngaged = { [1] = 1, [2] = 8, [3] = 8 } })
    equal(#plan.add, 0, "no new arrow despite earlier candidate")
    equal(plan.keep.nameplate2.keepReason, "KEPT_ENGAGED", "kept")
    equal(plan.states.nameplate1, "DEMO_SKIPPED", "earlier candidate waits")
end)

test("decide: grace against flicker, then removal", function()
    local marks = { nameplate1 = { gen = 1, lastEngagedAt = 10 } }
    local o = obs({ { "nameplate1", 1, "NOT_ENGAGED" }, { "nameplate2", 2, "ENGAGED" } })
    local plan = AD:Decide({ now = 11, running = true, expected = 4, obs = o, marks = marks })
    equal(plan.keep.nameplate1.keepReason, "GRACE_NOT_ENGAGED", "within grace")
    plan = AD:Decide({ now = 12, running = true, expected = 4, obs = o, marks = marks })
    equal(plan.keep.nameplate1, nil, "grace expired")
    equal(plan.remove[1].reason, "NOT_ENGAGED_AFTER_GRACE", "removal reason")
end)

test("decide: UNKNOWN holds an arrow briefly and never adds one", function()
    local marks = { nameplate1 = { gen = 1, lastEngagedAt = 1 } }
    local o = obs({ { "nameplate1", 1, "UNKNOWN" }, { "nameplate2", 2, "UNKNOWN" },
                    { "nameplate3", 3, "ENGAGED" } })
    local plan = AD:Decide({ now = 20, running = true, expected = 5, obs = o, marks = marks })
    equal(plan.keep.nameplate1.keepReason, "HOLD_UNKNOWN", "held")
    equal(plan.states.nameplate2, "DEMO_UNKNOWN", "unknown state")
    for _, a in ipairs(plan.add) do
        truthy(a.token ~= "nameplate2", "UNKNOWN never added")
    end
    marks.nameplate1 = plan.keep.nameplate1
    plan = AD:Decide({ now = 23.5, running = true, expected = 5, obs = o, marks = marks })
    equal(plan.remove[1].reason, "UNKNOWN_TIMEOUT", "timeout")
end)

test("decide: idle follows what the player points at", function()
    local o = obs({ { "nameplate1", 1, "NOT_ENGAGED", "TARGET" },
                    { "nameplate2", 2, "NOT_ENGAGED", "SOFTENEMY" },
                    { "nameplate3", 3, "NOT_ENGAGED", "TARGET" },
                    { "nameplate4", 4, "NOT_ENGAGED" } })
    local plan = AD:Decide({ now = 5, running = true, expected = 4, obs = o, marks = {} })
    equal(plan.phase, "IDLE", "phase")
    equal(#plan.add, 2, "idle max")
    local byTok = {}
    for _, a in ipairs(plan.add) do byTok[a.token] = a.reason end
    equal(byTok.nameplate2, "POINTED_SOFTENEMY", "softenemy first")
    equal(byTok.nameplate1, "POINTED_TARGET", "then target")
    equal(plan.states.nameplate3, "DEMO_SKIPPED", "third pointed skipped")
    equal(plan.states.nameplate4, nil, "unpointed untouched")
end)

test("decide: idle arrow survives brief loss of pointing, then leaves", function()
    local marks = { nameplate1 = { gen = 1, lastPointedAt = 5 } }
    local o = obs({ { "nameplate1", 1, "NOT_ENGAGED" } })
    local plan = AD:Decide({ now = 5.5, running = true, obs = o, marks = marks })
    equal(plan.keep.nameplate1.keepReason, "KEPT_POINTED", "point grace")
    plan = AD:Decide({ now = 6.5, running = true, obs = o, marks = marks })
    equal(plan.remove[1].reason, "NO_LONGER_POINTED", "left")
end)

test("decide: combat elsewhere drops a pointed idle arrow", function()
    local marks = { nameplate1 = { gen = 1, lastPointedAt = 5 } }
    local o = obs({ { "nameplate1", 1, "NOT_ENGAGED", "TARGET" },
                    { "nameplate2", 2, "ENGAGED" } })
    local plan = AD:Decide({ now = 6, running = true, expected = 3, obs = o, marks = marks })
    equal(plan.remove[1].reason, "PHASE_EXECUTION", "execution phase wins")
end)

test("decide: an arrow never survives a generation change", function()
    local plan = AD:Decide({ now = 1, running = true,
        obs = obs({ { "nameplate1", 8, "ENGAGED" } }),
        marks = { nameplate1 = { gen = 7 }, nameplate2 = { gen = 3 } } })
    local why = {}
    for _, r in ipairs(plan.remove) do why[r.token] = r.reason end
    equal(why.nameplate1, "GENERATION_CHANGED", "new occupant")
    equal(why.nameplate2, "NAMEPLATE_REMOVED", "gone")
    equal(plan.add[1].gen, 8, "new generation may get its own arrow")
end)

test("decide: cap bounds", function()
    local o = obs({ { "nameplate1", 1, "ENGAGED" } })
    equal(AD:Decide({ running = true, obs = o }).cap, 6, "default cap")
    equal(AD:Decide({ running = true, obs = o, expected = 20 }).cap, 12, "hard cap")
    equal(AD:Decide({ running = true, obs = o, expected = 0 }).cap, 1, "floor")
end)

test("decide: hostile input degrades, never explodes", function()
    local ok, plan = pcall(function()
        return AD:Decide({ now = 1, running = true, expected = HOSTIL,
            obs = { { token = HOSTIL, gen = 1, engagement = "ENGAGED" },
                    { token = "nameplate1", gen = 1, engagement = HOSTIL },
                    HOSTIL },
            marks = {} })
    end)
    truthy(ok, "no error: " .. tostring(plan))
    equal(plan.counts.engaged, 0, "hostile engagement is not ENGAGED")
    equal(plan.counts.unknown, 1, "it is UNKNOWN")
    equal(#plan.add, 0, "nothing added")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- A. DEMO OFF: PRODUCCION INTACTA
-- ═══════════════════════════════════════════════════════════════════════════

test("A. demo off leaves production untouched", function()
    fresh()
    addPlate("nameplate1", "ENGAGED")
    addPlate("nameplate2", "ENGAGED")
    local lerAntes = lerCalls
    for _ = 1, 5 do tick() end
    equal(RA:CountActive(), 0, "no arrows")
    equal(TEL:IsRecording(), false, "no session")
    equal(lerCalls, lerAntes, "demo ticks do not reach the resolver")
    equal(Pr:CountTracked(), 0, "presenter untouched")
    equal(#tickers == 0 or tickers[#tickers].cancelled ~= false, true, "no live ticker")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- B. UNKNOWN SIGUE SIENDO UNKNOWN · C. NADIE ESCRIBE MATCH · D. PULL QUIETO
-- ═══════════════════════════════════════════════════════════════════════════

test("B. demo on: guidance still says UNKNOWN, no arrow from production", function()
    fresh()
    addPlate("nameplate1", "ENGAGED")
    addPlate("nameplate2", "ENGAGED")
    local antes = G:Evaluate("nameplate1")
    demoOn()
    tick()
    equal(AD:CountMarks(), 2, "demo drew its arrows")
    local despues = G:Evaluate("nameplate1")
    equal(antes.state, "UNKNOWN", "before")
    equal(despues.state, "UNKNOWN", "after")
    equal(despues.shouldMark, false, "production would not mark")
    equal(Pr:CountTracked(), 0, "presenter tracks nothing")
    local lerAntes = lerCalls
    for _ = 1, 10 do tick() end
    equal(lerCalls, lerAntes, "demo never calls the resolver")
end)

test("C. demo cannot write MATCH anywhere", function()
    -- estatico: el codigo (sin comentarios) no escribe MATCH ni toca identidad
    for _, path in ipairs({ "modules/AdaptiveRoute/ArrowDemo.lua",
                            "modules/AdaptiveRoute/ArrowDemoTelemetry.lua",
                            "modules/AdaptiveRoute/NameplateGenerations.lua" }) do
        local f = assert(io.open(path, "r"))
        local src = f:read("*a")
        f:close()
        local code = {}
        for line in (src .. "\n"):gmatch("([^\n]*)\n") do
            if line:gsub("^%s+", ""):sub(1, 2) ~= "--" then
                code[#code + 1] = (line:gsub("%s%-%-.*$", ""))
            end
        end
        code = table.concat(code, "\n")
        equal(code:find('"MATCH"', 1, true), nil, path .. " MATCH literal")
        equal(code:find("matchState", 1, true), nil, path .. " matchState")
        equal(code:find("ResolveForGuidance", 1, true), nil, path .. " resolver")
        equal(code:find("LiveEnemyResolver", 1, true), nil, path .. " resolver module")
        equal(code:find("GuidanceEngine", 1, true), nil, path .. " guidance")
        equal(code:find("DEBUG_FORCED", 1, true), nil, path .. " forced")
        equal(code:find("SetDebugForced", 1, true), nil, path .. " forced setter")
        equal(code:find("NextPull", 1, true), nil, path .. " NextPull")
        equal(code:find("SetPull", 1, true), nil, path .. " SetPull")
        equal(code:find("RestorePull", 1, true), nil, path .. " RestorePull")
        equal(code:find("UnitGUID", 1, true), nil, path .. " GUID")
        equal(code:find("UnitName", 1, true), nil, path .. " name")
        equal(code:find("COMBAT_LOG", 1, true), nil, path .. " combat log")
        equal(code:find("UnregisterEvent", 1, true), nil, path .. " taint")
    end
    -- en ejecucion: ni una linea de telemetria contiene MATCH
    for _, l in ipairs(events()) do
        equal((l:gsub("MISMATCH", "")):find("MATCH", 1, true), nil, "telemetry line")
    end
    equal(G:GetLastDecision("nameplate1") and G:GetLastDecision("nameplate1").state == "MATCH",
          false, "guidance never saw MATCH")
end)

test("D. demo never advances RouteProgress", function()
    fresh()
    local antes = rpTotal()
    demoOn()
    for i = 1, 6 do addPlate("nameplate" .. i, "ENGAGED") end
    for _ = 1, 20 do tick() end
    for i = 1, 6 do world.engagement["nameplate" .. i] = "NOT_ENGAGED" end
    for _ = 1, 20 do tick() end
    bus:Emit("MITZU_KEY_COMPLETED")
    equal(rpTotal(), antes, "no RouteProgress calls")
    equal(world.pull, 1, "pull untouched")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- E. PLACA RETIRADA · F. GENERACION NUEVA
-- ═══════════════════════════════════════════════════════════════════════════

test("E. NAME_PLATE_UNIT_REMOVED removes the demo arrow (both handler orders)", function()
    for _, reverse in ipairs({ false, true }) do
        fresh()
        demoOn()
        addPlate("nameplate1", "ENGAGED")
        addPlate("nameplate2", "ENGAGED")
        tick()
        truthy(RA:IsMarked("nameplate1"), "marked first")
        removePlate("nameplate1", reverse)
        equal(RA:IsMarked("nameplate1"), false, "arrow gone")
        tick()
        equal(demoTokens(), "nameplate2", "demo forgot it")
        truthy(find(nil, "DEMO_ARROW_REMOVED token=nameplate1"), "removal logged")
        truthy(poolOK(), "pool consistent")
    end
end)

test("F. a reused token never inherits the old arrow", function()
    fresh()
    demoOn()
    addPlate("nameplate3", "ENGAGED")
    tick()
    local g1 = NG:Current("nameplate3")
    equal(AD:GetMarks()[1].gen, g1, "arrow bound to gen")
    -- ADDED otra vez sin REMOVED: el cliente ha reciclado el token.
    world.engagement["nameplate3"] = "NOT_ENGAGED"
    fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
    local g2 = NG:Current("nameplate3")
    truthy(g2 > g1, "new generation")
    equal(AD:CountMarks(), 0, "old arrow invalidated")
    truthy(find(nil, "TOKEN_GENERATION_CHANGED token=nameplate3"), "reuse logged")
    tick()
    equal(RA:IsMarked("nameplate3"), false, "new idle occupant gets nothing")
    world.engagement["nameplate3"] = "ENGAGED"
    tick()
    equal(AD:GetMarks()[1].gen, g2, "only the new generation can hold an arrow")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- G. CAMBIO DE PULL · H. FIN DE LLAVE · I. DEMO OFF
-- ═══════════════════════════════════════════════════════════════════════════

test("G. manual pull change clears and recomputes", function()
    fresh()
    demoOn()
    for i = 1, 3 do addPlate("nameplate" .. i, "ENGAGED") end
    tick()
    equal(AD:CountMarks(), 3, "three before")
    MitzuMPlus.RouteProgress:NextPull("MANUAL")   -- lo que hace /emp next
    local iPull = find(nil, "PULL_CHANGED pull=2 from=1")
    local iNext = find(nil, "MANUAL_NEXT pull=2")
    local iRem  = find(nil, "reason=PULL_CHANGED")
    truthy(iPull and iNext and iRem, "all logged")
    truthy(iPull < iRem, "pull change logged before arrows react")
    equal(AD:CountMarks(), 3, "recomputed at once for the new pull")
    truthy(find(nil, "PULL_CHANGED pull=2 from=1 pullCount=11 reason=MANUAL expected=12"),
           "static expected count of the real pull 2")
    local run = TEL:GetRun(nil)
    equal(run.counters.manualNext, 1, "manual next counted")
    equal(run.counters.automaticRouteProgress, 0, "manual is not automatic")
end)

test("G2. a non-manual pull change is measured as automatic progress", function()
    fresh()
    demoOn()
    tick()
    MitzuMPlus.RouteProgress:SetPull(3, "FORCES")
    equal(TEL:GetRun(nil).counters.automaticRouteProgress, 1, "measured, not hardcoded")
end)

test("H. challenge end leaves zero demo arrows and archives the run", function()
    fresh()
    demoOn()
    for i = 1, 4 do addPlate("nameplate" .. i, "ENGAGED") end
    tick()
    equal(RA:CountActive(), 4, "four arrows")
    bus:Emit("MITZU_KEY_COMPLETED")
    equal(AD:CountMarks(), 0, "demo empty")
    equal(RA:CountActive(), 0, "RouteArrows empty")
    equal(TEL:IsRecording(), false, "session closed")
    local run = TEL:GetRun(1)
    equal(run.meta.status, "COMPLETED", "status")
    truthy(find(run, "CHALLENGE_END status=COMPLETED"), "end logged")
    truthy(poolOK(), "pool consistent")
end)

test("I. demo off: zero arrows, ticker cancelled, indicator hidden", function()
    fresh()
    demoOn()
    local ticker = AD._ticker
    truthy(ticker, "ticker running")
    truthy(AD._indicator and AD._indicator:IsShown(), "indicator shown")
    for i = 1, 3 do addPlate("nameplate" .. i, "ENGAGED") end
    tick()
    AD:SetEnabled(false)
    equal(AD:CountMarks(), 0, "demo empty")
    equal(RA:CountActive(), 0, "RouteArrows empty")
    truthy(ticker.cancelled, "ticker cancelled")
    equal(AD._ticker, nil, "ticker dropped")
    equal(AD._indicator:IsShown(), false, "indicator hidden")
    equal(TEL:GetRun(1).meta.status, "DEMO_OFF", "session closed as DEMO_OFF")
    equal(TEL:Store().enabled, false, "persisted off")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- J. POOL · PROPIEDAD
-- ═══════════════════════════════════════════════════════════════════════════

test("J. frames come back from the RouteArrows pool", function()
    fresh()
    demoOn()
    for i = 1, 3 do addPlate("nameplate" .. i, "ENGAGED") end
    tick()
    local creados = RA._stats.created
    for i = 1, 3 do world.engagement["nameplate" .. i] = "NOT_ENGAGED" end
    tick(2)   -- pasada la gracia
    equal(AD:CountMarks(), 0, "all released")
    for i = 1, 3 do world.engagement["nameplate" .. i] = "ENGAGED" end
    tick()
    equal(AD:CountMarks(), 3, "back")
    equal(RA._stats.created, creados, "no new frames")
    truthy(countLines(nil, "DEMO_ARROW_REUSED") >= 3, "reuse logged")
    truthy(find(nil, "pool=REUSED"), "applied says REUSED")
    truthy(poolOK(), "pool consistent")
end)

test("J2. production owns its arrows: demo rejects and yields", function()
    fresh()
    demoOn()
    addPlate("nameplate1", "ENGAGED")
    addPlate("nameplate2", "ENGAGED")
    -- produccion marca nameplate1 ANTES que la demo
    Pr:Apply("nameplate1", { shouldMark = true })
    tick()
    truthy(find(nil, "DEMO_ARROW_SKIPPED token=nameplate1 .- reason=PRODUCTION_OWNS"),
           "skipped before even trying")
    equal(demoTokens(), "nameplate2", "demo took only the free one")
    -- produccion marca DESPUES una placa que ya era de la demo
    Pr:Apply("nameplate2", { shouldMark = true })
    tick()
    truthy(find(nil, "reason=PRODUCTION_TOOK_OVER"), "yielded")
    equal(AD:CountMarks(), 0, "demo owns nothing")
    AD:SetEnabled(false)
    truthy(RA:IsMarked("nameplate1") and RA:IsMarked("nameplate2"),
           "demo off never removes production arrows")
    Pr:ClearAll()
end)

test("decide: a blocked plate does not eat the cap", function()
    local plan = AD:Decide({ now = 10, running = true, expected = 2,
        obs = obs({ { "nameplate1", 1, "ENGAGED" }, { "nameplate2", 2, "ENGAGED" },
                    { "nameplate3", 3, "ENGAGED" } }),
        marks = {}, firstEngaged = { [1] = 1, [2] = 2, [3] = 3 },
        blocked = { nameplate1 = true } })
    equal(#plan.add, 2, "two free plates get the two slots")
    equal(plan.add[1].token, "nameplate2", "second")
    equal(plan.add[2].token, "nameplate3", "third")
    equal(plan.states.nameplate1, "DEMO_SKIPPED", "blocked one skipped")
    equal(plan.skipped[1].reason, "PRODUCTION_OWNS", "reason")
end)

test("no log spam: a persistent refusal is written once per generation", function()
    fresh()
    demoOn()
    addPlate("nameplate1", "ENGAGED")
    addPlate("nameplate2", "ENGAGED")
    Pr:Apply("nameplate1", { shouldMark = true })     -- producción, todo el combate
    world.plates["nameplate2"] = nil                   -- visible pero sin placa resoluble
    for _ = 1, 50 do tick() end
    equal(countLines(nil, "token=nameplate1 .- reason=PRODUCTION_OWNS"), 1, "one skip line")
    equal(countLines(nil, "DEMO_ARROW_REJECTED token=nameplate2"), 1, "one reject line")
    equal(countLines(nil, "DEMO_ARROW_WANTED token=nameplate2"), 1, "one wanted line")
    world.plates["nameplate2"] = makePlate("nameplate2")
    Pr:ClearAll()
end)

test("J3. RouteArrows releasing on its own is caught as stale, not orphan", function()
    fresh()
    demoOn()
    addPlate("nameplate1", "ENGAGED")
    tick()
    RA:UnmarkUnit("nameplate1")    -- alguien lo quita por detras
    tick()
    local run = TEL:GetRun(nil)
    truthy(run.counters.staleArrowEvents >= 1, "stale counted")
    -- y en el tick siguiente vuelve a quererla: la placa sigue enganchada
    equal(RA:IsMarked("nameplate1"), true, "re-marked")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- K. TIEMPO · L. MEMORIA
-- ═══════════════════════════════════════════════════════════════════════════

local function msOf(line) return tonumber(line:match("^(%d+) ")) end

test("K. timestamps are monotonic and T+0 is the challenge start", function()
    fresh()
    world.state = "PRE_KEY"
    demoOn()
    tick()
    equal(TEL:IsRecording(), false, "no session before the key")
    world.state, world.elapsed = "RUNNING", 0
    bus:Emit("MITZU_KEY_STARTED")
    local i, l = find(nil, "CHALLENGE_START")
    truthy(i, "T+0 logged")
    equal(msOf(l), 0, "at zero")
    for n = 1, 5 do addPlate("nameplate" .. n, n % 2 == 0 and "ENGAGED" or "NOT_ENGAGED") end
    for _ = 1, 30 do tick(0.37) end
    world.time = world.time + 12.345
    TEL:Snapshot()
    local last = -1
    for _, line in ipairs(events()) do
        local ms = msOf(line)
        truthy(ms and ms >= last, "monotonic: " .. line)
        last = ms
    end
    equal(TEL.FormatTime(754321), "12:34.321", "format")
end)

test("K2. a /reload continues the same run on the same time axis", function()
    fresh()
    demoOn()
    world.elapsed = 100
    tick()
    local run = TEL:GetRun(nil)
    local lastBefore = run.events[#run.events]
    TEL:Checkpoint()
    -- /reload: el estado Lua desaparece, el SavedVariable no.
    TEL._session = nil
    world.time, world.elapsed = world.time + 30, 99   -- el servidor redondea hacia abajo
    local ok, resumed = TEL:StartSession("DEMO_ON")
    truthy(ok and resumed, "resumed")
    equal(TEL:GetRun(nil), run, "same run object")
    truthy(find(run, "SESSION_RESUMED"), "resume logged")
    truthy(msOf(run.events[#run.events]) >= msOf(lastBefore), "axis never goes back")
    -- una llave distinta NO se reanuda: la vieja se archiva como PARTIAL
    TEL._session = nil
    world.startedAt = world.startedAt + 3600
    TEL:StartSession("DEMO_ON")
    truthy(TEL:GetRun(nil) ~= run, "new run")
    equal(TEL:GetRun(1).meta.status, "PARTIAL", "old one archived as PARTIAL")
    world.startedAt = 1788000000
end)

test("L. memory limits: events, casts, snapshots and runs are bounded", function()
    fresh()
    demoOn()
    tick()
    local lim = TEL.LIMITS
    local run = TEL:GetRun(nil)
    for _ = 1, lim.MAX_EVENTS + 250 do TEL:Log("INCONSISTENCY", { "where", "TEST" }) end
    equal(#run.events, lim.MAX_EVENTS, "events capped")
    truthy(run.counters.eventsDropped >= 250, "drops counted")
    TEL:Log("SESSION_END", { "status", "TEST" }, true)
    equal(#run.events, lim.MAX_EVENTS + 1, "reserved slot still available")
    addPlate("nameplate1", "ENGAGED")
    for _ = 1, lim.MAX_CAST_EVENTS + 40 do
        fire("UNIT_SPELLCAST_START", "nameplate1", HOSTIL, SECRET_NUM)
    end
    equal(#run.casts, lim.MAX_CAST_EVENTS, "casts capped")
    equal(run.counters.castLinesDropped, 40, "cast drops counted")
    truthy(run.counters.castEvents >= lim.MAX_CAST_EVENTS + 40, "counters stay exact")
    for _ = 1, lim.MAX_SNAPSHOTS + 5 do TEL:Snapshot() end
    equal(#run.snapshots, lim.MAX_SNAPSHOTS, "snapshots capped")
    AD:SetEnabled(false)
    for _ = 1, lim.MAX_RUNS + 3 do
        AD:SetEnabled(true)
        tick()
        AD:SetEnabled(false)
    end
    equal(#TEL:Store().runs, lim.MAX_RUNS, "only the last runs are kept")
    equal(TEL:Store().current, nil, "no dangling session")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- M. SECRETOS · N. spellID · O. EXPORT
-- ═══════════════════════════════════════════════════════════════════════════

test("M. secret values are never serialized", function()
    fresh()
    world.dungeonName = SECRET_NAME
    demoOn()
    addPlate("nameplate1", "ENGAGED")
    tick()
    fire("UNIT_SPELLCAST_START", "nameplate1", HOSTIL, SECRET_NUM)
    fire("UNIT_SPELLCAST_CHANNEL_START", "nameplate1", HOSTIL, HOSTIL)
    fire("UNIT_SPELLCAST_START", HOSTIL, HOSTIL, 1)          -- token hostil
    fire("UNIT_SPELLCAST_START", "player", HOSTIL, 2)        -- no es placa
    local ok = pcall(TEL.Log, TEL, "INCONSISTENCY", { "where", HOSTIL, "n", SECRET_NUM })
    truthy(ok, "hostile field value does not explode")
    bus:Emit("MITZU_KEY_COMPLETED")
    local texto = TEL:Export(TEL:GetRun(1))
    equal(texto:find(SECRET_NAME, 1, true), nil, "secret name")
    equal(texto:find(tostring(SECRET_NUM), 1, true), nil, "secret number")
    equal(texto:find("table:", 1, true), nil, "no table addresses")
    equal(texto:find("player", 1, true), nil, "non-nameplate token ignored")
    equal(texto:find("|", 1, true), nil, "no WoW escape character at all")
    truthy(texto:find("meta.dungeon=-", 1, true), "unprovable name written as '-'")
end)

test("N. a secret spellID stores only its state", function()
    fresh()
    demoOn()
    addPlate("nameplate1", "ENGAGED")
    tick()
    fire("UNIT_SPELLCAST_START", "nameplate1", HOSTIL, SECRET_NUM)
    fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", HOSTIL, 12345)
    local run = TEL:GetRun(nil)
    local secreto, publico
    for _, l in ipairs(run.casts) do
        if l:find("CAST_START") then secreto = l end
        if l:find("CAST_SUCCEEDED") then publico = l end
    end
    truthy(secreto:find("spellIDState=SECRET", 1, true), "state recorded")
    equal(secreto:find("spellID=", 1, true), nil, "no id field when secret")
    truthy(publico:find("spellIDState=AVAILABLE spellID=12345", 1, true), "public id kept")
    equal(run.counters.secretSpellIDs, 1, "secret counted")
    equal(run.counters.safeSpellIDs, 1, "safe counted")
end)

test("O. export is deterministic and parseable", function()
    fresh()
    demoOn()
    for i = 1, 3 do addPlate("nameplate" .. i, "ENGAGED") end
    for _ = 1, 5 do tick() end
    TEL:Snapshot()
    fire("UNIT_SPELLCAST_START", "nameplate2", HOSTIL, SECRET_NUM)
    bus:Emit("MITZU_KEY_COMPLETED")
    local run = TEL:GetRun(1)
    local a, b = TEL:Export(run), TEL:Export(run)
    equal(a, b, "byte-identical")
    local lines = {}
    for l in (a .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
    equal(lines[1], "MITZU_ARROW_DEMO_TELEMETRY_V1", "header")
    local section, seen = nil, {}
    for i = 2, #lines do
        local l = lines[i]
        local s = l:match("^# (%a+)$")
        if s then
            section = s
            seen[#seen + 1] = s
        elseif section == "meta" then
            truthy(l:match("^meta%.[%w]+=.+$"), "meta line: " .. l)
        elseif section == "summary" then
            truthy(l:match("^summary%.[%a]+=%d+$"), "summary line: " .. l)
        elseif section == "events" or section == "casts" or section == "snapshots" then
            local t, code, rest = l:match("^(%d%d:%d%d%.%d%d%d) ([A-Z_]+)(.*)$")
            truthy(t and code, "event line: " .. l)
            for field in rest:gmatch("%S+") do
                truthy(field:match("^[%a]+=[^%s=|]+$"), "field: " .. field .. " in " .. l)
            end
        end
    end
    equal(table.concat(seen, ","), "meta,summary,events,casts,snapshots,end", "sections")
    truthy(a:find("meta.t0=CHALLENGE_MODE_START", 1, true), "T+0 declared")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- ROBUSTEZ
-- ═══════════════════════════════════════════════════════════════════════════

test("episodes are observations, not pull boundaries", function()
    fresh()
    local rpAntes = rpTotal()
    demoOn()
    addPlate("nameplate1", "ENGAGED")
    addPlate("nameplate2", "ENGAGED")
    tick()
    addPlate("nameplate3", "ENGAGED")   -- se une a mitad
    tick()
    removePlate("nameplate1")            -- muere o sale de rango
    tick()
    world.engagement.nameplate2 = "NOT_ENGAGED"
    world.engagement.nameplate3 = "NOT_ENGAGED"
    tick(0.5)
    equal(find(nil, "ENGAGEMENT_ENDED"), nil, "not ended yet: quiet must hold")
    world.engagement.nameplate2 = "ENGAGED"
    tick(0.5)
    truthy(find(nil, "ENGAGEMENT_DIP"), "dip, not an end")
    world.engagement.nameplate2 = "NOT_ENGAGED"
    tick(0.4)
    tick(3.2)
    local _, l = find(nil, "ENGAGEMENT_ENDED")
    truthy(l, "ended after quiet confirmed")
    truthy(l:find("obs=possibleQuietStart", 1, true), "framed as observation")
    truthy(l:find("peakSimultaneousEngaged=3", 1, true), "peak")
    truthy(l:find("generationsEverEngaged=3", 1, true), "generations")
    truthy(l:find("joinedDuringExecution=1", 1, true), "joined")
    truthy(l:find("removedDuringExecution=1", 1, true), "removed")
    equal(rpTotal(), rpAntes, "and the pull did not move")
end)

test("engagement evidence failing degrades to UNKNOWN, never to an arrow", function()
    fresh()
    demoOn()
    addPlate("nameplate1", "ERROR")
    tick()
    equal(AD:CountMarks(), 0, "no arrow on failure")
    truthy(find(nil, "UNKNOWN_ENGAGEMENT token=nameplate1"), "logged as unknown")
    equal(TEL:GetRun(nil).counters.luaErrors, 0, "handled, not an error")
end)

test("a RouteArrows failure is contained and reported once", function()
    fresh()
    demoOn()
    local original = RA.MarkUnit
    RA.MarkUnit = function() error("boom") end
    addPlate("nameplate1", "ENGAGED")
    addPlate("nameplate2", "ENGAGED")
    tick()
    tick()
    RA.MarkUnit = original
    local run = TEL:GetRun(nil)
    truthy(run.counters.luaErrors >= 1, "error counted")
    truthy(find(run, "reason=MARK_FAILED"), "rejection logged")
    local avisos = 0
    for _, m in ipairs(printed) do if m:find("error interno", 1, true) then avisos = avisos + 1 end end
    equal(avisos, 1, "chat warned exactly once")
end)

test("leaving the run clears arrows even without a key event", function()
    fresh()
    demoOn()
    addPlate("nameplate1", "ENGAGED")
    tick()
    world.state = "OUTSIDE"
    tick()
    equal(AD:CountMarks(), 0, "cleared")
    equal(RA:CountActive(), 0, "no arrows left")
    equal(TEL:GetRun(1).meta.status, "NOT_RUNNING", "session closed")
end)

test("zone change resets generations and demo arrows", function()
    fresh()
    demoOn()
    addPlate("nameplate1", "ENGAGED")
    tick()
    fire("PLAYER_ENTERING_WORLD")
    equal(AD:CountMarks(), 0, "demo cleared")
    equal(NG:Current("nameplate1"), nil, "generation closed")
    local g = NG:LastSequence()
    fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    truthy(NG:Current("nameplate1") > g, "generations never restart")
end)

test("after /reload an enabled demo comes back, with a notice", function()
    fresh()
    demoOn()
    AD._enabled = false     -- simula el estado Lua perdido; el SV sigue en true
    AD:_StopTicker()
    printed = {}
    fire("PLAYER_ENTERING_WORLD")
    equal(AD:IsEnabled(), true, "back on")
    truthy(printed[1] and printed[1]:find("sigue activo", 1, true), "never silent")
end)

test("production pipeline is not wired to the demo", function()
    for _, path in ipairs({ "modules/GuidanceEngine.lua", "modules/RouteArrowPresenter.lua",
                            "modules/AdaptiveRoute/RouteArrows.lua",
                            "modules/AdaptiveRoute/LiveEnemyResolver.lua",
                            "modules/RouteProgress.lua" }) do
        local f = assert(io.open(path, "r"))
        local src = f:read("*a")
        f:close()
        equal(src:find("ArrowDemo", 1, true), nil, path .. " knows nothing of the demo")
    end
end)

return { tests = tests, assertions = assertions }
