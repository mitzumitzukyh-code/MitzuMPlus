-- Tests de la FASE 4: RouteSignature + ExecutionEpisodeTracker +
-- RoutePullCandidateScorer + RouteAlignment.
-- No se carga desde el TOC. Ejecutar con: python tests/run_lua_tests.py
--
-- Se cargan los modulos REALES, la ruta empaquetada de Ruby Life Pools y el
-- RouteManager de produccion. Solo son simulados el cliente, el resolver de
-- identidad y RouteProgress (con contadores, para demostrar que NADIE mueve
-- el pull en esta fase).

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

local function falsy(value, label)
    assertions = assertions + 1
    if value then error((label or "falsy") .. ": valor verdadero", 2) end
end

local function near(actual, expected, tol, label)
    assertions = assertions + 1
    if type(actual) ~= "number" or math.abs(actual - expected) > (tol or 0.001) then
        error(string.format("%s: esperado ~%s, recibido %s",
            label or "near", tostring(expected), tostring(actual)), 2)
    end
end

local function greater(a, b, label)
    assertions = assertions + 1
    if not (type(a) == "number" and type(b) == "number" and a > b) then
        error(string.format("%s: %s no es mayor que %s",
            label or "greater", tostring(a), tostring(b)), 2)
    end
end

local function test(name, fn)
    tests = tests + 1
    local ok, err = pcall(fn)
    if not ok then error("TEST " .. name .. "\n" .. tostring(err), 0) end
end

-- ── Valores prohibidos ─────────────────────────────────────────────────────

local SECRET_GUID = "SECRET-GUID-VALUE"
local HOSTIL = setmetatable({}, {
    __tostring = function() error("PROHIBIDO: tostring de un valor hostil") end,
    __concat   = function() error("PROHIBIDO: concatenar un valor hostil") end,
    __eq       = function() error("PROHIBIDO: comparar un valor hostil") end,
    __lt       = function() error("PROHIBIDO: ordenar un valor hostil") end,
    __index    = function() error("PROHIBIDO: leer dentro de un valor hostil") end,
})

function issecretvalue(v)
    if type(v) == "table" then return true end
    return v == SECRET_GUID
end

-- ── Mundo simulado ─────────────────────────────────────────────────────────

local world = { time = 1000, state = "RUNNING", elapsed = 0, startedAt = 1788000000,
                pull = 1, visible = {}, plates = {}, engagement = {}, pointed = {} }

function GetTime() return world.time end
function date() return "2026-09-11 21:00:00" end

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

local function fire(event, ...)
    for _, f in ipairs(frames) do
        if f._events[event] and f._onEvent then f._onEvent(f, event, ...) end
    end
end

C_NamePlate = {
    GetNamePlates = function() return {} end,
    GetNamePlateForUnit = function(tok) return world.plates[tok] end,
}
function UnitExists(u) return world.plates[u] ~= nil end

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
    GetDungeonName = function() return "Ruby Life Pools" end,
}
MitzuMPlus.ChallengeClock = {
    GetElapsed = function() return world.state == "RUNNING" and world.elapsed or nil end,
    GetStartedAt = function() return world.startedAt end,
}

-- La ruta real empaquetada.
local RUBY
MitzuMPlus.NativeRouteDB = { Register = function(_, r) RUBY = r; return true end }
dofile("data/Routes/Season2/RubyLifePools.lua")
assert(RUBY and #RUBY.pulls == 11, "no se cargo la ruta real de Ruby Life Pools")

-- RouteProgress simulado CON CONTADORES: si algo de la fase 4 intentara
-- mover el pull, estos numeros dejarian de ser cero y los tests lo cantarian.
local ACTIVE_ROUTE = RUBY
local rpCalls = { SetPull = 0, NextPull = 0, PreviousPull = 0, RestorePull = 0 }
MitzuMPlus.RouteProgress = {
    GetState = function() return "ACTIVE" end,
    GetRoute = function() return ACTIVE_ROUTE end,
    GetPullIndex = function() return world.pull end,
    GetPullCount = function() return #ACTIVE_ROUTE.pulls end,
    GetCurrentPull = function() return ACTIVE_ROUTE.pulls[world.pull] end,
    SetPull = function(_, n) rpCalls.SetPull = rpCalls.SetPull + 1; world.pull = n; return true, n end,
    NextPull = function() rpCalls.NextPull = rpCalls.NextPull + 1 end,
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

-- Evidencias en vivo simuladas.
AR.EngagementEvidence = { Evaluate = function(_, tok)
    return world.engagement[tok] or "NOT_ENGAGED"
end }
AR.UnitLinkEvidence = { Evaluate = function(_, tok, clase)
    local p = world.pointed[tok]
    return (p and p[clase]) and "SAME_UNIT" or "DIFFERENT_UNIT"
end }

-- Resolver de identidad simulado. `world.npcID[token]` puede ser:
--   un numero      -> npcID publico
--   "SECRET"       -> el cliente lo marca secreto
--   nil            -> no disponible
world.npcID = {}
local npcIDCalls = 0
AR.LiveEnemyResolver = {
    GetNPCID = function(_, token)
        npcIDCalls = npcIDCalls + 1
        local v = world.npcID[token]
        if v == "SECRET" then return nil, "SECRET", "secret" end
        if type(v) == "number" then return v, "AVAILABLE", "string" end
        return nil, "UNKNOWN", nil
    end,
    ResolveForGuidance = function() return "UNKNOWN" end,
}

-- RouteArrows simulado: la fase 4 no lo toca, pero ArrowDemo si.
local RAmock = {
    _stats = { created = 0, acquired = 0, released = 0 }, _active = {},
    MarkUnit = function(self, tok)
        if not self._active[tok] then
            self._stats.created = self._stats.created + 1
            self._stats.acquired = self._stats.acquired + 1
        end
        self._active[tok] = true
        return true
    end,
    UnmarkUnit = function(self, tok)
        if self._active[tok] then self._stats.released = self._stats.released + 1 end
        self._active[tok] = nil
        return true
    end,
    IsMarked = function(self, tok) return self._active[tok] == true end,
    CountActive = function(self)
        local n = 0
        for _ in pairs(self._active) do n = n + 1 end
        return n
    end,
    ClearAll = function(self) self._active = {} end,
    IsEnabled = function() return true end,
}
AR.RouteArrows = RAmock
AR.PackEvidence = { ExpectedFromPull = function(_, pull)
    local n = 0
    for _, m in ipairs(pull and pull.mobs or {}) do n = n + (m.amount or 0) end
    if n <= 0 then return nil, "UNKNOWN" end
    return n, "AVAILABLE"
end }

dofile("modules/RouteManager.lua")
dofile("modules/AdaptiveRoute/NameplateGenerations.lua")
dofile("modules/AdaptiveRoute/ArrowDemoTelemetry.lua")
dofile("modules/AdaptiveRoute/ArrowDemo.lua")
dofile("modules/AdaptiveRoute/RouteSignature.lua")
dofile("modules/AdaptiveRoute/ExecutionEpisodeTracker.lua")
dofile("modules/AdaptiveRoute/RoutePullCandidateScorer.lua")
dofile("modules/AdaptiveRoute/RouteAlignment.lua")

local RS  = AR.RouteSignature
local EET = AR.ExecutionEpisodeTracker
local SC  = AR.RoutePullCandidateScorer
local RAl = AR.RouteAlignment
local TEL = AR.ArrowDemoTelemetry
local NG  = AR.NameplateGenerations
local AD  = AR.ArrowDemo
local RM  = MitzuMPlus.RouteManager

local S = SC.STATES

-- ── Utilidades ─────────────────────────────────────────────────────────────

local A, B, Cc, D, Z = 1001, 1002, 1003, 1004, 1099

-- Construye una ruta sintetica: mkRoute({ { {A,2}, {B,1} }, ... })
local function mkRoute(pulls, counts)
    local r = { id = "test_route", schemaVersion = 1, dungeonKey = 1, pulls = {} }
    for i, entradas in ipairs(pulls) do
        local mobs = {}
        for j, e in ipairs(entradas) do
            mobs[j] = { npcID = e[1], enemyIdx = j, forces = 5, amount = e[2],
                        cloneIDs = {} }
            for k = 1, e[2] do mobs[j].cloneIDs[k] = k end
        end
        r.pulls[i] = { id = i, count = (counts and counts[i]) or 10, mobs = mobs }
    end
    return r
end

-- Observacion sintetica. npcs = { [npcID] = n } o nil para "sin identidad".
local function mkObs(engaged, npcs, extra)
    local o = {
        observationID = 1, episodeID = 1, startedAt = 0, endedAt = 0, durationMs = 0,
        engagedCount = engaged, visibleCount = engaged, peakEngaged = engaged,
        joined = 0, removed = 0,
        npcMultiset = {}, identifiedUnits = 0, secretUnits = 0, unavailableUnits = 0,
        npcCoverage = 0, linkedUnits = 0,
        encounterActive = false, encounterEverSeen = false,
        routePullAtStart = 1, repeatedGenerations = 0, overflow = false,
        generations = {}, engagementConsistency = 1,
    }
    if npcs then
        for id, n in pairs(npcs) do
            o.npcMultiset[id] = n
            o.identifiedUnits = o.identifiedUnits + n
        end
    end
    o.unavailableUnits = engaged - o.identifiedUnits
    o.npcCoverage = (engaged > 0) and (o.identifiedUnits / engaged) or 0
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
end

local PERSIST = { persistMs = 5000 }
local function ctxFor(label) return { persistLabel = label, persistMs = 5000 } end

local function events(run)
    run = run or TEL:GetRun(nil)
    return (run and run.events) or {}
end
local function findLine(pattern)
    for _, l in ipairs(events()) do if l:find(pattern) then return l end end
    return nil
end
local function countLines(pattern)
    local n = 0
    for _, l in ipairs(events()) do if l:find(pattern) then n = n + 1 end end
    return n
end

local function resetAll()
    if AD:IsEnabled() then AD:SetEnabled(false) end
    RAl:Reset(nil)
    RAl:SetEnabled(true)
    EET:Reset(nil, false)
    EET._seq = 0
    for _, tok in ipairs(world.visible) do fire("NAME_PLATE_UNIT_REMOVED", tok) end
    world.visible, world.plates, world.engagement = {}, {}, {}
    world.pointed, world.npcID = {}, {}
    world.pull, world.state = 1, "RUNNING"
    ACTIVE_ROUTE = RUBY
    RAmock:ClearAll()
    TEL:ClearStored()
    TEL:Store().current = nil
    if TEL:IsRecording() then TEL:EndSession("TEST") end
    TEL._encounterActive = false
    printed = {}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- A · FIRMA DE LA RUTA (RouteSignature / RouteManager:GetPullSignature)
-- ═══════════════════════════════════════════════════════════════════════════

test("A1 firma del pull 1 real de Ruby Life Pools", function()
    local sig = RS:ForPull(RUBY, 1)
    equal(sig.state, "AVAILABLE", "estado")
    equal(sig.mobCount, 13, "unidades esperadas")    -- 1 + 5 + 5 + 2
    equal(sig.entries, 4, "entradas de mob")
    equal(sig.npcMultiset[188244], 1, "npc elite")
    equal(sig.npcMultiset[187969], 5, "npc x5")
    equal(sig.npcMultiset[188011], 5, "npc x5 (2)")
    equal(sig.npcMultiset[188067], 2, "npc x2")
    equal(sig.npcTypes, 4, "tipos distintos")
    equal(sig.unresolvedUnits, 0, "todas con npcID")
    equal(sig.noForces, false, "el pull 1 aporta tropas")
end)

test("A2 un pull de boss se marca como sin tropas, sin inventar encounterID", function()
    local sig = RS:ForPull(RUBY, 3)
    equal(sig.mobCount, 1, "un solo mob")
    equal(sig.forcesCount, 0, "count de la ruta")
    equal(sig.noForces, true, "no aporta tropas")
    -- Y lo que NO hay: la ruta no trae encounterID por ninguna parte.
    falsy(rawget(RUBY.pulls[3], "encounterID"), "la ruta no trae encounterID")
end)

test("A3 un pull vacio o corrupto vale UNKNOWN, nunca 0", function()
    local rota = { pulls = { { id = 1, mobs = {} } } }
    local sig = RS:ForPull(rota, 1)
    equal(sig.state, "UNKNOWN", "estado")
    equal(sig.mobCount, nil, "mobCount es nil, no 0")

    local sinAmount = { pulls = { { id = 1, mobs = { { npcID = A } } } } }
    equal(RS:ForPull(sinAmount, 1).mobCount, nil, "sin amount ni clones")

    equal(RS:ForPull(nil, 1).state, "UNKNOWN", "ruta nil")
    equal(RS:ForPull(RUBY, 99).state, "UNKNOWN", "pull fuera de rango")
    equal(RS:ForPull(RUBY, nil).state, "UNKNOWN", "pull nil")
end)

test("A4 la cadena suma los dos multisets", function()
    local sig = RS:ForChain(RUBY, { 4, 5 })
    equal(sig.mobCount, 11, "5 + 6")
    equal(sig.npcMultiset[190207], 4, "2 + 2")
    equal(sig.npcMultiset[190034], 2, "1 + 1")
    equal(sig.npcMultiset[195119], 1, "solo en el pull 5")
    equal(RS:Label(sig), "4+5", "etiqueta")
    equal(RS:Label(RS:ForPull(RUBY, 7)), "7", "etiqueta suelta")
end)

test("A5 RouteManager:GetPullSignature funciona sin MDT", function()
    RM._active = RUBY
    local sig, err = RM:GetPullSignature(nil, 9)
    truthy(sig, "hay firma: " .. tostring(err))
    equal(sig.mobCount, 18, "pull 9 de Ruby")
    equal(sig.pull, 9, "indice")
    RM._active = nil
    local nada, motivo = RM:GetPullSignature(nil, 1)
    equal(nada, nil, "sin ruta activa no hay firma")
    truthy(motivo, "y da un motivo")
    RM._active = RUBY
end)

test("A6 una ruta con metatabla hostil no revienta la firma", function()
    local hostil = setmetatable({}, { __index = function() error("PROHIBIDO") end })
    equal(RS:ForPull(hostil, 1).state, "UNKNOWN", "ruta hostil")
    local conMobHostil = { pulls = { { id = 1, mobs = { HOSTIL } } } }
    equal(RS:ForPull(conMobHostil, 1).state, "UNKNOWN", "mob hostil")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- B · LOS DOCE CASOS DEL SCORER
-- ═══════════════════════════════════════════════════════════════════════════

test("caso 1 · composicion exacta da candidato fuerte", function()
    local route = mkRoute({ { { A, 2 }, { B, 1 }, { Cc, 1 } }, { { Z, 9 } } })
    local obs = mkObs(4, { [A] = 2, [B] = 1, [Cc] = 1 })
    local h = SC:Evaluate(obs, route, 1, ctxFor("1"))
    equal(h.state, S.STRONG, "estado")
    equal(h.candidatePull, 1, "candidato")
    equal(h.label, "1", "etiqueta")
    near(h.components.npcComposition, 1.0, 0.001, "composicion")
    near(h.components.multiplicity, 1.0, 0.001, "multiplicidad")
    near(h.components.sizeSimilarity, 1.0, 0.001, "tamano")
    near(h.score, 1.0, 0.001, "total")
    truthy(h.margin > SC.CONFIG.ambiguousMargin, "margen amplio")
end)

test("caso 2 · multiplicidad incorrecta no es coincidencia exacta", function()
    -- esperado A A B   vs   observado A B B
    local route = mkRoute({ { { A, 2 }, { B, 1 } }, { { Z, 9 } } })
    local obs = mkObs(3, { [A] = 1, [B] = 2 })
    local h = SC:Evaluate(obs, route, 1, ctxFor("1"))
    near(h.components.npcComposition, 2 / 3, 0.001, "composicion parcial")
    near(h.components.multiplicity, 0.5, 0.001, "multiplicidad penalizada")
    truthy(h.score < 1.0, "no es un 1.0")
    local tiene = false
    for _, r in ipairs(h.reasons) do
        if r == "MULTIPLICITY_MISMATCH" then tiene = true end
        if r == "EXACT_NPC_COMPOSITION" then error("no puede ser exacta") end
    end
    truthy(tiene, "motivo de multiplicidad")

    -- Y el caso espejo puntua distinto: el multiset NO es un conjunto.
    local espejo = SC:Evaluate(mkObs(3, { [A] = 2, [B] = 1 }), route, 1, ctxFor("1"))
    greater(espejo.score, h.score, "A A B encaja mejor que A B B")
end)

test("caso 3 · observacion parcial es evidencia parcial, no identidad", function()
    -- esperado A A B C   vs   observado A B
    local route = mkRoute({ { { A, 2 }, { B, 1 }, { Cc, 1 } }, { { Z, 9 } } })
    local obs = mkObs(2, { [A] = 1, [B] = 1 })
    local h = SC:Evaluate(obs, route, 1, ctxFor("1"))
    near(h.components.npcComposition, 0.5, 0.001, "composicion a medias")
    truthy(h.state ~= S.STRONG, "nunca STRONG con la mitad del pack")
end)

test("caso 4 · un mob de mas penaliza", function()
    local route = mkRoute({ { { A, 1 }, { B, 1 }, { Cc, 1 } }, { { Z, 9 } } })
    local exacto = SC:Evaluate(mkObs(3, { [A] = 1, [B] = 1, [Cc] = 1 }), route, 1, ctxFor("1"))
    local sobra  = SC:Evaluate(mkObs(4, { [A] = 1, [B] = 1, [Cc] = 1, [D] = 1 }), route, 1, ctxFor("1"))
    near(sobra.components.npcComposition, 0.75, 0.001, "composicion con extra")
    near(sobra.components.sizeSimilarity, 0.75, 0.001, "tamano con extra")
    greater(exacto.score, sobra.score, "el extra baja la puntuacion")
end)

test("caso 5 · chain pull: 4+5 gana a 4", function()
    -- pull4 = A B, pull5 = C D, observado = A B C D
    local route = mkRoute({
        { { Z, 5 } }, { { Z, 5 } }, { { Z, 5 } },
        { { A, 1 }, { B, 1 } },
        { { Cc, 1 }, { D, 1 } },
        { { Z, 5 } },
    })
    local obs = mkObs(4, { [A] = 1, [B] = 1, [Cc] = 1, [D] = 1 })
    local h = SC:Evaluate(obs, route, 4, ctxFor("4+5"))
    equal(h.label, "4+5", "gana la cadena")
    truthy(h.isChain, "marcada como cadena")
    equal(h.candidatePull, 4, "primer pull de la cadena")
    -- Y el pull 4 suelto sigue estando evaluado, por debajo.
    local suelto
    for _, c in ipairs(h.candidates) do if c.label == "4" then suelto = c end end
    truthy(suelto, "el 4 suelto esta entre los candidatos")
    greater(h.score, suelto.total, "la cadena puntua mas")
end)

test("caso 5b · sin exceso observado NO se generan cadenas", function()
    local route = mkRoute({
        { { Z, 5 } }, { { Z, 5 } }, { { Z, 5 } },
        { { A, 1 }, { B, 1 } }, { { Cc, 1 }, { D, 1 } }, { { Z, 5 } },
    })
    local h = SC:Evaluate(mkObs(2, { [A] = 1, [B] = 1 }), route, 4, ctxFor("4"))
    for _, c in ipairs(h.candidates) do
        if c.label:find("+") then error("cadena generada sin evidencia: " .. c.label) end
    end
    equal(h.label, "4", "gana el pull suelto")
end)

test("caso 6 · dos pulls con la misma composicion dan AMBIGUOUS", function()
    local route = mkRoute({
        { { Z, 4 } },
        { { A, 2 }, { B, 1 } },
        { { A, 2 }, { B, 1 } },
        { { Z, 7 } },
    })
    local h = SC:Evaluate(mkObs(3, { [A] = 2, [B] = 1 }), route, 2, ctxFor("2"))
    equal(h.state, S.AMBIGUOUS, "estado")
    truthy(h.margin < SC.CONFIG.ambiguousMargin, "margen por debajo del umbral")
    truthy(h.runnerUpLabel ~= nil, "hay segundo candidato")
    local tiene = false
    for _, r in ipairs(h.reasons) do if r == "TIE_WITH_RUNNER_UP" then tiene = true end end
    truthy(tiene, "motivo de empate")
end)

test("caso 6b · si la composicion desempata, ya no es AMBIGUOUS", function()
    local route = mkRoute({
        { { Z, 4 } },
        { { A, 2 }, { B, 1 } },
        { { Cc, 2 }, { D, 1 } },
        { { Z, 7 } },
    })
    local h = SC:Evaluate(mkObs(3, { [A] = 2, [B] = 1 }), route, 2, ctxFor("2"))
    equal(h.label, "2", "gana el que encaja")
    truthy(h.state == S.STRONG or h.state == S.PROBABLE, "estado: " .. h.state)
    truthy(h.margin >= SC.CONFIG.ambiguousMargin, "margen suficiente")
end)

test("caso 8 · ancla de boss: con ENCOUNTER gana el pull sin tropas", function()
    local route = mkRoute({
        { { A, 1 } },   -- count 10 -> aporta tropas
        { { B, 1 } },   -- count 0  -> no aporta
    }, { 10, 0 })
    local sinBoss = SC:Evaluate(mkObs(1, nil), route, 1, ctxFor("1"))
    local conBoss = SC:Evaluate(
        mkObs(1, nil, { encounterEverSeen = true, encounterActive = true }),
        route, 1, ctxFor("1"))
    local function porEtiqueta(h)
        local m = {}
        for _, c in ipairs(h.candidates) do m[c.label] = c end
        return m
    end
    -- El componente existe solo cuando distingue.
    local sin, con = porEtiqueta(sinBoss), porEtiqueta(conBoss)
    equal(sin["1"].components.bossAnchor, nil, "sin encounter y con tropas: no aplica")
    near(sin["2"].components.bossAnchor, 0.15, 0.001, "pull sin tropas y sin encounter: raro")
    equal(con["1"].components.bossAnchor, 0, "con encounter, un pull con tropas puntua 0")
    equal(con["2"].components.bossAnchor, 1, "el pull sin tropas puntua 1")
    -- Y eso cambia quien gana: sin ENCOUNTER manda la secuencia, con el manda
    -- el ancla.
    equal(sinBoss.label, "1", "sin boss gana el pull actual")
    equal(conBoss.label, "2", "con boss gana el pull sin tropas")
end)

test("caso 9 · sin npcIDs degrada de forma segura, no a cero", function()
    local route = mkRoute({ { { A, 2 }, { B, 2 } }, { { Cc, 2 }, { D, 2 } } })
    local obs = mkObs(4, nil)   -- cuatro enganchados, ninguno identificado
    local h = SC:Evaluate(obs, route, 1, ctxFor("1"))
    -- Lo desconocido NO vale 0: sencillamente no participa.
    equal(h.components.npcComposition, nil, "composicion no disponible")
    equal(h.components.multiplicity, nil, "multiplicidad no disponible")
    near(h.components.sizeSimilarity, 1.0, 0.001, "el tamano si se puede medir")
    equal(h.npcCoverage, 0, "cobertura 0")
    -- Los dos pulls esperan 4: el tamano no distingue y no se puede decir STRONG.
    truthy(h.state ~= S.STRONG, "sin identidad y con tamano repetido: nunca STRONG")
    equal(h.sizeUnique, false, "el tamano no es unico")
    local tiene = false
    for _, r in ipairs(h.reasons) do if r == "NO_NPC_IDENTITY" then tiene = true end end
    truthy(tiene, "motivo de falta de identidad")
end)

test("caso 9b · la puerta de STRONG exige cobertura o tamano exacto y unico", function()
    local route = mkRoute({ { { A, 4 } }, { { Z, 9 } } })
    -- Sin identidad, pero el tamano 4 es unico entre los candidatos.
    local h = SC:Evaluate(mkObs(4, nil), route, 1, ctxFor("1"))
    equal(h.sizeExact, true, "tamano exacto")
    equal(h.sizeUnique, true, "y unico")
    equal(h.state, S.STRONG, "esa es la unica via sin npcID")
    -- Con un empate de tamanos, la misma observacion ya no llega a STRONG.
    local route2 = mkRoute({ { { A, 4 } }, { { Z, 4 } } })
    local h2 = SC:Evaluate(mkObs(4, nil), route2, 1, ctxFor("1"))
    truthy(h2.state ~= S.STRONG, "con tamano repetido no")
end)

test("caso 10 · valores secretos se ignoran sin error", function()
    resetAll()
    world.npcID["nameplate1"] = "SECRET"
    world.npcID["nameplate2"] = SECRET_GUID   -- el mock devuelve UNKNOWN
    local obs = {
        { token = "nameplate1", gen = 1, engagement = "ENGAGED" },
        { token = "nameplate2", gen = 2, engagement = "ENGAGED" },
    }
    EET:Observe(obs, 0)
    local o = EET:Observation()
    equal(o.identifiedUnits, 0, "nada identificado")
    equal(o.secretUnits, 1, "uno secreto")
    equal(o.unavailableUnits, 1, "uno no disponible")
    equal(o.npcCoverage, 0, "cobertura 0")
    -- Y el estado del miembro secreto es exactamente SECRET, no UNKNOWN.
    local ep = EET:Current()
    equal(ep.members[1].npcIDState, "SECRET", "estado del miembro secreto")
    equal(ep.members[1].npcID, nil, "no se guarda ningun numero")
end)

test("caso 10b · un npcID SECRET no se reintenta", function()
    resetAll()
    world.npcID["nameplate1"] = "SECRET"
    npcIDCalls = 0
    local obs = { { token = "nameplate1", gen = 1, engagement = "ENGAGED" } }
    for i = 0, 10 do EET:Observe(obs, i * 400) end
    equal(npcIDCalls, 1, "una sola lectura para un valor secreto")
end)

test("caso 11 · dos generaciones del mismo token no se mezclan jamas", function()
    resetAll()
    world.npcID["nameplate3"] = 5001
    EET:Observe({ { token = "nameplate3", gen = 17, engagement = "ENGAGED" } }, 0)
    world.npcID["nameplate3"] = 5002   -- otro ocupante del mismo token
    EET:Observe({ { token = "nameplate3", gen = 18, engagement = "ENGAGED" } }, 400)
    local ep = EET:Current()
    equal(ep.memberCount, 2, "dos miembros")
    equal(ep.members[17].npcID, 5001, "gen 17")
    equal(ep.members[18].npcID, 5002, "gen 18")
    local o = EET:Observation()
    equal(o.engagedCount, 2, "cuentan como dos unidades")
    equal(o.npcMultiset[5001], 1, "uno de cada")
    equal(o.npcMultiset[5002], 1, "uno de cada (2)")
end)

test("caso 12 · target/mouseover refuerza continuidad, no identidad", function()
    local route = mkRoute({ { { A, 2 } }, { { Z, 9 } } })
    local sinLink = mkObs(2, { [A] = 2 })
    local conLink = mkObs(2, { [A] = 2 }, { linkedUnits = 2 })
    local h1 = SC:Evaluate(sinLink, route, 1, ctxFor("1"))
    local h2 = SC:Evaluate(conLink, route, 1, ctxFor("1"))
    equal(h1.score, h2.score, "el enlace NO cambia la puntuacion")
    equal(h1.state, h2.state, "ni el estado")
    -- Lo que si hace es contarse como observacion.
    equal(conLink.linkedUnits, 2, "queda registrado")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- C · PUREZA Y ROBUSTEZ DEL SCORER
-- ═══════════════════════════════════════════════════════════════════════════

test("C1 Evaluate es determinista y no muta sus entradas", function()
    local route = mkRoute({ { { A, 2 }, { B, 1 } }, { { Cc, 3 } } })
    local obs = mkObs(3, { [A] = 2, [B] = 1 })
    local antes = obs.engagedCount
    local h1 = SC:Evaluate(obs, route, 1, ctxFor("1"))
    local h2 = SC:Evaluate(obs, route, 1, ctxFor("1"))
    equal(h1.score, h2.score, "mismo total")
    equal(h1.label, h2.label, "mismo ganador")
    equal(table.concat(h1.reasons, ","), table.concat(h2.reasons, ","), "mismos motivos")
    equal(obs.engagedCount, antes, "la observacion no se toca")
    equal(#route.pulls, 2, "la ruta no se toca")
end)

test("C2 entradas imposibles dan NO_EVIDENCE, nunca un error", function()
    equal(SC:Evaluate(nil, mkRoute({ { { A, 1 } } }), 1).state, S.NO_EVIDENCE, "obs nil")
    equal(SC:Evaluate(mkObs(0, nil), mkRoute({ { { A, 1 } } }), 1).state, S.NO_EVIDENCE, "sin enganchados")
    equal(SC:Evaluate(mkObs(3, nil), nil, 1).state, S.NO_EVIDENCE, "sin ruta")
    equal(SC:Evaluate(mkObs(3, nil), mkRoute({ { { A, 1 } } }), nil).state, S.NO_EVIDENCE, "sin pull actual")
    equal(SC:Evaluate(mkObs(3, nil), HOSTIL, 1).state, S.NO_EVIDENCE, "ruta hostil")
    local rotaTotal = { pulls = { { id = 1, mobs = {} } } }
    equal(SC:Evaluate(mkObs(3, nil), rotaTotal, 1).state, S.NO_EVIDENCE, "ruta sin firmas")
end)

test("C3 todos los motivos salen del vocabulario cerrado", function()
    local route = mkRoute({ { { A, 2 }, { B, 1 } }, { { A, 2 }, { B, 1 } }, { { Z, 9 } } })
    local vistos = {}
    for _, obs in ipairs({
        mkObs(3, { [A] = 2, [B] = 1 }),
        mkObs(9, nil),
        mkObs(1, { [A] = 1 }, { encounterEverSeen = true, repeatedGenerations = 2, overflow = true }),
    }) do
        for _, pull in ipairs({ 1, 2, 3 }) do
            local h = SC:Evaluate(obs, route, pull, ctxFor("1"))
            for _, r in ipairs(h.reasons) do
                vistos[r] = true
                truthy(SC.REASONS[r], "motivo desconocido: " .. tostring(r))
            end
            truthy(SC.STATES[h.state], "estado desconocido: " .. tostring(h.state))
        end
    end
    truthy(next(vistos) ~= nil, "se ha probado algun motivo")
end)

test("C4 la palabra MATCH no aparece en estados ni motivos", function()
    -- MISMATCH lleva MATCH dentro y no es lo mismo: se quita antes de buscar.
    local function usaMatch(s) return (s:gsub("MISMATCH", "")):find("MATCH") end
    for _, s in pairs(SC.STATES) do
        falsy(usaMatch(s), "estado con MATCH: " .. s)
    end
    for _, r in pairs(SC.REASONS) do
        falsy(usaMatch(r), "motivo con MATCH: " .. r)
    end
end)

test("C5 la persistencia solo cuenta para la hipotesis que persiste", function()
    local route = mkRoute({ { { A, 2 } }, { { Z, 9 } } })
    local obs = mkObs(2, { [A] = 2 })
    local sin = SC:Evaluate(obs, route, 1, { persistLabel = nil, persistMs = 0 })
    local con = SC:Evaluate(obs, route, 1, ctxFor("1"))
    local otra = SC:Evaluate(obs, route, 1, { persistLabel = "2", persistMs = 5000 })
    equal(sin.components.temporalPersistence, 0, "sin persistencia")
    equal(con.components.temporalPersistence, 1, "persistida")
    equal(otra.components.temporalPersistence, 0, "la persistencia de otro no cuenta")
    greater(con.score, sin.score, "persistir suma")
end)

test("C6 solo se evaluan N-1, N, N+1, N+2 y sus cadenas", function()
    local pulls = {}
    for i = 1, 12 do pulls[i] = { { Z, 3 } } end
    local route = mkRoute(pulls)
    local h = SC:Evaluate(mkObs(3, nil), route, 6, ctxFor("6"))
    local etiquetas = {}
    for _, c in ipairs(h.candidates) do etiquetas[c.label] = true end
    truthy(etiquetas["5"] and etiquetas["6"] and etiquetas["7"] and etiquetas["8"],
        "los cuatro sueltos")
    falsy(etiquetas["1"], "no se recorre la ruta entera")
    falsy(etiquetas["12"], "ni el final")
    truthy(#h.candidates <= SC.CONFIG.maxCandidates, "tope de candidatos")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- D · EPISODIOS  (ExecutionEpisodeTracker)
-- ═══════════════════════════════════════════════════════════════════════════

local function obsDe(lista)
    local out = {}
    for _, e in ipairs(lista) do
        out[#out + 1] = { token = e[1], gen = e[2], engagement = e[3], pointed = e[4] }
    end
    return out
end

test("D1 un episodio empieza al primer ENGAGED y cierra con calma confirmada", function()
    resetAll()
    local ev = EET:Observe(obsDe({ { "nameplate1", 1, "NOT_ENGAGED" } }), 0)
    equal(ev, nil, "nadie peleando: no hay episodio")
    equal(EET:Current(), nil, "ni episodio abierto")

    ev = EET:Observe(obsDe({ { "nameplate1", 1, "ENGAGED" } }), 400)
    equal(ev, "STARTED", "arranca")
    equal(EET:GetState(), "ACTIVE", "estado")

    EET:Observe(obsDe({ { "nameplate1", 1, "NOT_ENGAGED" } }), 800)
    equal(EET:GetState(), "QUIET_PENDING", "calma sin confirmar")
    ev = EET:Observe(obsDe({ { "nameplate1", 1, "NOT_ENGAGED" } }), 2000)
    equal(ev, nil, "aun no")
    ev = EET:Observe(obsDe({ { "nameplate1", 1, "NOT_ENGAGED" } }), 3900)
    equal(ev, "ENDED", "cierra a los 3 s")
    equal(EET:GetState(), "IDLE", "vuelve a reposo")
    equal(#EET:History(), 1, "queda en el historial")
end)

test("D2 una duda impide dar el combate por terminado", function()
    resetAll()
    EET:Observe(obsDe({ { "nameplate1", 1, "ENGAGED" } }), 0)
    for t = 400, 8000, 400 do
        EET:Observe(obsDe({ { "nameplate1", 1, "UNKNOWN" } }), t)
    end
    equal(EET:GetState(), "ACTIVE", "con UNKNOWN no se cierra")
    truthy(EET:Current() ~= nil, "el episodio sigue abierto")
end)

test("D3 un dip de combate no cierra el episodio", function()
    resetAll()
    EET:Observe(obsDe({ { "nameplate1", 1, "ENGAGED" } }), 0)
    EET:Observe(obsDe({ { "nameplate1", 1, "NOT_ENGAGED" } }), 400)
    EET:Observe(obsDe({ { "nameplate1", 1, "ENGAGED" } }), 1200)
    equal(EET:GetState(), "ACTIVE", "vuelve el combate")
    local ev = EET:Observe(obsDe({ { "nameplate1", 1, "ENGAGED" } }), 9000)
    equal(ev, nil, "sigue vivo tras 9 s de pelea")
    equal(#EET:History(), 0, "nada cerrado")
end)

test("D4 el episodio cuenta pico, entradas tardias y retiradas", function()
    resetAll()
    EET:Observe(obsDe({ { "nameplate1", 1, "ENGAGED" }, { "nameplate2", 2, "ENGAGED" } }), 0)
    EET:Observe(obsDe({
        { "nameplate1", 1, "ENGAGED" }, { "nameplate2", 2, "ENGAGED" },
        { "nameplate3", 3, "ENGAGED" },
    }), 400)
    EET:OnGenerationRemoved(2)
    local ep = EET:Current()
    equal(ep.generationsEngaged, 3, "tres pelearon")
    equal(ep.peakSimultaneousEngaged, 3, "pico simultaneo")
    equal(ep.joinedDuringExecution, 1, "uno se unio tarde")
    equal(ep.removedDuringExecution, 1, "uno se fue")
    equal(ep.routePullAtStart, 1, "pull al empezar")
    equal(#ep.order, 3, "orden de enganche")
    equal(ep.order[3], 3, "el ultimo en engancharse")
end)

test("caso 7 · wipe: los mismos mobs vuelven y NO es un pull completado", function()
    resetAll()
    local antes = rpTotal()
    local pack = obsDe({
        { "nameplate1", 1, "ENGAGED" }, { "nameplate2", 2, "ENGAGED" },
        { "nameplate3", 3, "ENGAGED" },
    })
    local calma = obsDe({
        { "nameplate1", 1, "NOT_ENGAGED" }, { "nameplate2", 2, "NOT_ENGAGED" },
        { "nameplate3", 3, "NOT_ENGAGED" },
    })
    EET:Observe(pack, 0)
    EET:Observe(calma, 400)
    local ev = EET:Observe(calma, 4000)
    equal(ev, "ENDED", "primer episodio cerrado")

    -- Reset del pack: las MISMAS generaciones vuelven a pelear.
    ev = EET:Observe(pack, 20000)
    equal(ev, "STARTED", "segundo episodio")
    local ep = EET:Current()
    equal(ep.repeatedGenerations, 3, "las tres generaciones se repiten")
    equal(ep.episodeID, 2, "es otro episodio, no una continuacion")
    -- Lo importante: nadie ha tocado la ruta.
    equal(rpTotal(), antes, "cero escrituras en RouteProgress")
    -- Y el vocabulario no confunde los dos conceptos.
    falsy(TEL.CODES["ROUTE_PULL_COMPLETED"], "no existe tal codigo")
    truthy(TEL.CODES["PHYSICAL_EPISODE_END"], "lo que existe es el fin de EJECUCION")
end)

test("D5 tope de miembros por episodio", function()
    resetAll()
    local grande = {}
    for i = 1, EET.PARAMS.MAX_MEMBERS + 10 do
        grande[#grande + 1] = { token = "nameplate" .. i, gen = i, engagement = "ENGAGED" }
    end
    EET:Observe(grande, 0)
    local ep = EET:Current()
    equal(ep.memberCount, EET.PARAMS.MAX_MEMBERS, "no pasa del tope")
    equal(ep.overflow, true, "y lo dice")
end)

test("D6 entradas basura no rompen el tracker", function()
    resetAll()
    EET:Observe({ HOSTIL, 42, "texto", { token = 7, gen = "x" }, {} }, 0)
    equal(EET:Current(), nil, "nada de eso es un enganche")
    EET:Observe(nil, 0)
    EET:Observe("no soy una tabla", 0)
    equal(EET:GetState(), "IDLE", "sigue entero")
end)

test("D7 cast, evento reciente y linkage quedan como observacion agregada", function()
    resetAll()
    EET:Observe({ {
        token = "nameplate1", gen = 1, engagement = "ENGAGED",
        castState = "CASTING", recentEvent = "RECENT_EVENT", tokenLink = "TARGET",
    } }, 0)
    local o = EET:Observation()
    equal(o.castingUnits, 1, "unidad casteando")
    equal(o.recentEventUnits, 1, "unidad con evento reciente")
    equal(o.linkedUnits, 1, "unidad enlazada")
    near(o.castActivity, 1, 0.001, "actividad de cast")
    near(o.eventEngagement, 1, 0.001, "evento como engagement temporal")
    near(o.tokenLinkage, 1, 0.001, "linkage agregado")
end)

test("D8 un evento de cast sin engagement no abre un episodio", function()
    resetAll()
    EET:Observe({ {
        token = "nameplate1", gen = 1, engagement = "NOT_ENGAGED",
        recentEvent = "RECENT_EVENT", tokenLink = "TARGET",
    } }, 0)
    equal(EET:Current(), nil, "EventCast no tiene autoridad para abrir combate")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- E · RouteAlignment  (integracion + telemetria)
-- ═══════════════════════════════════════════════════════════════════════════

local function startSession()
    world.state = "RUNNING"
    world.elapsed = 0
    TEL:StartSession("TEST")
end

test("E1 un episodio completo deja su rastro en la telemetria", function()
    resetAll()
    startSession()
    world.npcID["nameplate1"] = 188244
    world.npcID["nameplate2"] = 187969
    local pack = obsDe({
        { "nameplate1", 1, "ENGAGED" }, { "nameplate2", 2, "ENGAGED" },
    })
    RAl:Feed(pack, 10)
    truthy(findLine("PHYSICAL_EPISODE_START"), "arranque del episodio")
    for t = 10.4, 16, 0.4 do RAl:Feed(pack, t) end
    truthy(findLine("ALIGNMENT "), "hipotesis registrada")
    truthy(findLine("PULL_CANDIDATE "), "candidatos registrados")
    truthy(findLine("OBSERVATION "), "observacion registrada")

    local calma = obsDe({
        { "nameplate1", 1, "NOT_ENGAGED" }, { "nameplate2", 2, "NOT_ENGAGED" },
    })
    for t = 16.4, 21, 0.4 do RAl:Feed(calma, t) end
    truthy(findLine("PHYSICAL_EPISODE_END"), "cierre del episodio")
    equal(#RAl:History(), 1, "queda en el historial de hipotesis")
    TEL:EndSession("TEST")
end)

test("E2 la alineacion NUNCA escribe en RouteProgress", function()
    resetAll()
    startSession()
    local antes = rpTotal()
    world.npcID["nameplate1"] = 188244
    for i = 1, 20 do
        world.npcID["nameplate" .. i] = 187969
    end
    local pack = {}
    for i = 1, 13 do
        pack[#pack + 1] = { token = "nameplate" .. i, gen = i, engagement = "ENGAGED" }
    end
    for t = 1, 30 do RAl:Feed(pack, t) end
    local h = RAl:Get()
    truthy(h, "hay hipotesis")
    -- Aunque sea la mas fuerte posible, el pull no se mueve.
    equal(rpTotal(), antes, "cero llamadas a RouteProgress")
    equal(world.pull, 1, "el pull sigue en 1")
    local run = TEL:GetRun(nil)
    equal(run.counters.automaticRouteProgress, 0, "sin progreso automatico")
    TEL:EndSession("TEST")
end)

test("E3 el log de hipotesis no se repite en cada tick", function()
    resetAll()
    startSession()
    local pack = obsDe({ { "nameplate1", 1, "ENGAGED" } })
    for t = 1, 60 do RAl:Feed(pack, t) end   -- 60 segundos de combate
    local lineas = countLines("ALIGNMENT ")
    truthy(lineas <= RAl.PARAMS.MAX_LOGGED_PER_EP,
        "solo " .. RAl.PARAMS.MAX_LOGGED_PER_EP .. " como mucho, hubo " .. lineas)
    truthy(lineas >= 1, "pero al menos una")
    TEL:EndSession("TEST")
end)

test("E4 apagar la inferencia no observa nada", function()
    resetAll()
    startSession()
    RAl:SetEnabled(false)
    RAl:Feed(obsDe({ { "nameplate1", 1, "ENGAGED" } }), 1)
    equal(EET:Current(), nil, "sin episodio")
    falsy(findLine("PHYSICAL_EPISODE_START"), "sin rastro")
    RAl:SetEnabled(true)
    TEL:EndSession("TEST")
end)

test("E5 un wipe queda anotado como POSSIBLE_WIPE, no como pull hecho", function()
    resetAll()
    startSession()
    local pack = obsDe({ { "nameplate1", 1, "ENGAGED" }, { "nameplate2", 2, "ENGAGED" } })
    local calma = obsDe({ { "nameplate1", 1, "NOT_ENGAGED" }, { "nameplate2", 2, "NOT_ENGAGED" } })
    RAl:Feed(pack, 1)
    for t = 1.4, 6, 0.4 do RAl:Feed(calma, t) end
    RAl:Feed(pack, 20)
    truthy(findLine("POSSIBLE_WIPE"), "wipe anotado")
    local run = TEL:GetRun(nil)
    equal(run.counters.possibleWipes, 1, "contado una vez")
    equal(run.counters.physicalEpisodes, 2, "dos episodios")
    TEL:EndSession("TEST")
end)

test("E6 el tick de ArrowDemo alimenta la alineacion de verdad", function()
    resetAll()
    world.plates["nameplate1"] = { unitToken = "nameplate1" }
    world.visible = { "nameplate1" }
    world.engagement["nameplate1"] = "ENGAGED"
    world.npcID["nameplate1"] = 188244
    fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    AD:SetEnabled(true)
    for i = 1, 12 do
        world.time = world.time + 0.4
        AD:SafeTick()
    end
    truthy(EET:Current() ~= nil, "el tick abrio un episodio")
    truthy(RAl:Get() ~= nil, "y produjo una hipotesis")
    truthy(findLine("PHYSICAL_EPISODE_START"), "con su rastro en la telemetria")
    AD:SetEnabled(false)
end)

test("E7 al apagar la demo se cierra el episodio abierto", function()
    resetAll()
    startSession()
    RAl:Feed(obsDe({ { "nameplate1", 1, "ENGAGED" } }), 1)
    truthy(EET:Current() ~= nil, "episodio abierto")
    AD:SetEnabled(true)
    AD:SetEnabled(false)
    equal(EET:Current(), nil, "cerrado al apagar")
    TEL:EndSession("TEST")
end)

test("E8 el fin de llave corta la alineacion por el bus", function()
    resetAll()
    startSession()
    RAl:Feed(obsDe({ { "nameplate1", 1, "ENGAGED" } }), 1)
    truthy(EET:Current() ~= nil, "episodio abierto")
    bus:Emit("MITZU_KEY_COMPLETED")
    equal(EET:Current(), nil, "cortado")
    equal(RAl:Get(), nil, "sin hipotesis colgando")
    TEL:EndSession("TEST")
end)

test("E8b alignmentdetail combina señales sin autoridad lateral", function()
    resetAll()
    startSession()
    local antesPull = rpTotal()
    local antesFlechas = RAmock._stats.acquired
    local pack = { {
        token = "nameplate1", gen = 1, engagement = "ENGAGED",
        castState = "CHANNELING", recentEvent = "RECENT_EVENT",
        tokenLink = "SOFTENEMY",
    } }
    RAl:Feed(pack, 1)
    RAl:Feed(pack, 2.1)
    local h = RAl:Get()
    truthy(h, "hay hipotesis diagnostica")
    near(h.components.castActivity, 1, 0.001, "cast combinado")
    near(h.components.eventEngagement, 1, 0.001, "evento combinado")
    near(h.components.tokenLinkage, 1, 0.001, "linkage combinado")
    equal(rpTotal(), antesPull, "sin autoridad de progreso")
    equal(RAmock._stats.acquired, antesFlechas, "sin efecto en flechas")

    local detalle = table.concat(RAl:DetailLines(), "\n")
    truthy(detalle:find("bestCandidate=", 1, true), "best candidate")
    truthy(detalle:find("runnerUp=", 1, true), "runner up")
    truthy(detalle:find("margin=", 1, true), "margen")
    truthy(detalle:find("signal.eventEngagement", 1, true), "breakdown evento")
    truthy(detalle:find("TEMPORAL_ACTIVITY_ONLY", 1, true), "rol temporal explicito")
    truthy(detalle:find("reasons=", 1, true), "razones")
    TEL:EndSession("TEST")
end)

-- ── El ancla propia ────────────────────────────────────────────────────────
--
-- Construye la observacion de un pull REAL de Ruby: un token por unidad, con
-- el npcID que la ruta dice que le toca.

local genSeq = 1000
local function obsDelPullReal(indice)
    local sig = RS:ForPull(RUBY, indice)
    local out = {}
    local ids = {}
    for id in pairs(sig.npcMultiset) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        for _ = 1, sig.npcMultiset[id] do
            genSeq = genSeq + 1
            local tok = "nameplate" .. (#out + 1)
            world.npcID[tok] = id
            out[#out + 1] = { token = tok, gen = genSeq, engagement = "ENGAGED" }
        end
    end
    return out
end

local function calmaDe(pack)
    local out = {}
    for _, o in ipairs(pack) do
        out[#out + 1] = { token = o.token, gen = o.gen, engagement = "NOT_ENGAGED" }
    end
    return out
end

-- Pelea un pull entero y deja que el episodio cierre. Devuelve la hipotesis.
local function pelear(indice, t)
    local pack = obsDelPullReal(indice)
    for i = 0, 6 do RAl:Feed(pack, t + i * 0.5) end
    local calma = calmaDe(pack)
    for i = 0, 12 do RAl:Feed(calma, t + 4 + i * 0.5) end
    return RAl:History()[#RAl:History()]
end

test("E10 con RouteProgress clavado en 1, el ancla propia sigue la ruta", function()
    resetAll()
    startSession()
    local t = 10
    local resultados = {}
    for pull = 1, 5 do
        resultados[pull] = pelear(pull, t)
        t = t + 30
    end
    -- Lo que de verdad paso en la M+ grabada: la ruta nunca se movio.
    equal(world.pull, 1, "RouteProgress sigue en el pull 1")
    equal(rpCalls.SetPull, 0, "nadie lo ha tocado")
    -- Y aun asi la inferencia ha ido siguiendo los packs.
    for pull = 1, 5 do
        local r = resultados[pull]
        truthy(r, "hay hipotesis del episodio " .. pull)
        equal(r.label, tostring(pull), "episodio " .. pull .. " apunta al pull " .. pull)
        truthy(r.state == "STRONG" or r.state == "PROBABLE",
            "episodio " .. pull .. " en " .. r.state)
    end
    equal(RAl._inferredPull, 6, "el ancla queda en el pull siguiente")
    local c = TEL:GetRun(nil).counters
    equal(c.automaticRouteProgress, 0, "sin progreso automatico")
    truthy(c.alignmentAnchorAdvances >= 4, "el ancla avanzo sola")
    TEL:EndSession("TEST")
end)

test("E10b el mismo recorrido con el npcID SECRETO sigue siendo util", function()
    -- El escenario que mas miedo da: en 12.1 los spellID llegan secretos y
    -- el GUID podria llegar igual. Aqui se comprueba que la capa no se rompe
    -- y que sigue diciendo algo, solo que con menos confianza.
    resetAll()
    startSession()
    local t, res = 10, {}
    for pull = 1, 5 do
        local pack = obsDelPullReal(pull)
        for _, o in ipairs(pack) do world.npcID[o.token] = "SECRET" end
        for i = 0, 6 do RAl:Feed(pack, t + i * 0.5) end
        for i = 0, 12 do RAl:Feed(calmaDe(pack), t + 4 + i * 0.5) end
        res[pull] = RAl:History()[#RAl:History()]
        t = t + 30
    end
    local aciertos, fuertes = 0, 0
    for pull = 1, 5 do
        truthy(res[pull], "hay hipotesis del episodio " .. pull)
        if res[pull].label == tostring(pull) then aciertos = aciertos + 1 end
        if res[pull].state == "STRONG" then fuertes = fuertes + 1 end
    end
    -- No se exige perfeccion: se exige que no mienta y que aun sirva.
    truthy(aciertos >= 3, "acierta la mayoria: " .. aciertos .. "/5")
    local c = TEL:GetRun(nil).counters
    equal(c.npcIDSecretPeak > 0, true, "la telemetria MIDE que llegaron secretos")
    equal(c.npcIDAvailablePeak, 0, "y que no hubo ni uno publico")
    equal(c.automaticRouteProgress, 0, "sin progreso automatico")
    equal(rpCalls.SetPull, 0, "sin escrituras en la ruta")
    TEL:EndSession("TEST")
end)

test("E11 si el jugador mueve el pull a mano, el ancla le hace caso", function()
    resetAll()
    startSession()
    pelear(1, 10)
    pelear(2, 40)
    equal(RAl._inferredPull, 3, "el ancla iba por 3")
    -- El jugador dice que en realidad va por el 9.
    world.pull = 9
    local pack = obsDelPullReal(9)
    RAl:Feed(pack, 80)
    equal(RAl._inferredPull, 9, "el ancla se resincroniza con el jugador")
    RAl:Feed(pack, 82)   -- el primer feed abre el episodio; el segundo puntua
    equal(RAl:Get().anchorPull, 9, "y la hipotesis se evalua desde ahi")
    equal(RAl:Get().label, "9", "que es donde de verdad estamos")
    TEL:EndSession("TEST")
end)

test("E12 dos episodios a ciegas devuelven el ancla al numero de verdad", function()
    resetAll()
    startSession()
    pelear(1, 10)
    equal(RAl._inferredPull, 2, "ancla en 2")
    -- Dos episodios con 30 mobs sin identificar: no se parecen a ningun pull
    -- cercano de Ruby (13, 12, 1, 5) y no se puede decir nada util.
    local raro, calmaRara = {}, {}
    for i = 1, 30 do
        raro[i] = { token = "nameplateX" .. i, gen = 90000 + i, engagement = "ENGAGED" }
        calmaRara[i] = { token = "nameplateX" .. i, gen = 90000 + i, engagement = "NOT_ENGAGED" }
    end
    for vuelta = 1, 2 do
        local base = 50 + vuelta * 30
        for i = 0, 4 do RAl:Feed(raro, base + i * 0.5) end
        for i = 0, 12 do RAl:Feed(calmaRara, base + 3 + i * 0.5) end
    end
    equal(RAl._inferredPull, world.pull, "vuelve al pull de verdad")
    equal(world.pull, 1, "que sigue siendo 1")
    TEL:EndSession("TEST")
end)

test("E13 un episodio AMBIGUOUS no mueve el ancla", function()
    resetAll()
    startSession()
    pelear(1, 10)
    local antes = RAl._inferredPull
    -- Los pulls 6 y 7 de Ruby tienen composicion identica: empate real.
    world.pull = 6
    RAl:Feed({}, 50)
    pelear(6, 60)
    local ultimo = RAl:History()[#RAl:History()]
    equal(ultimo.state, "AMBIGUOUS", "empate entre el 6 y el 7")
    equal(RAl._inferredPull, 6, "con dudas el ancla no avanza")
    truthy(antes ~= nil, "habia ancla antes")
    TEL:EndSession("TEST")
end)

test("E9 las lineas de diagnostico no revientan sin datos", function()
    resetAll()
    truthy(#RAl:StatusLines() >= 3, "status sin hipotesis")
    truthy(#RAl:CandidateLines() >= 1, "candidatos vacios")
    truthy(#RAl:HistoryLines() >= 1, "historial vacio")
    truthy(#EET:StatusLines() >= 2, "episodios vacios")
    startSession()
    RAl:Feed(obsDe({ { "nameplate1", 1, "ENGAGED" } }), 1)
    RAl:Feed(obsDe({ { "nameplate1", 1, "ENGAGED" } }), 3)
    truthy(#RAl:CandidateLines() >= 2, "candidatos con datos")
    for _, l in ipairs(RAl:StatusLines()) do
        equal(type(l), "string", "linea de texto")
    end
    TEL:EndSession("TEST")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- F · TELEMETRIA: formato y seguridad
-- ═══════════════════════════════════════════════════════════════════════════

test("F1 NEW_RUN es inicializacion, no progreso automatico", function()
    resetAll()
    startSession()
    TEL:OnPullChanged(1, 2, "NEW_RUN")
    TEL:OnPullChanged(2, 1, "MANUAL")
    TEL:OnPullChanged(3, 2, "SOMETHING_ELSE")
    local c = TEL:GetRun(nil).counters
    equal(c.routeProgressInit, 1, "el NEW_RUN se clasifica aparte")
    equal(c.manualNext, 1, "el manual, manual")
    equal(c.automaticRouteProgress, 1, "solo lo que de verdad es automatico")
    TEL:EndSession("TEST")
end)

test("F2 los codigos nuevos estan en el vocabulario cerrado", function()
    for _, code in ipairs({ "PHYSICAL_EPISODE_START", "PHYSICAL_EPISODE_END",
                            "OBSERVATION", "PULL_CANDIDATE", "ALIGNMENT",
                            "POSSIBLE_WIPE" }) do
        equal(TEL.CODES[code], code, "codigo " .. code)
    end
    resetAll()
    startSession()
    equal(TEL:Log("NO_EXISTE_ESTE_CODIGO", {}), false, "un codigo inventado se rechaza")
    equal(TEL:GetRun(nil).counters.inconsistencies, 1, "y queda anotado")
    TEL:EndSession("TEST")
end)

test("F3 el export sigue siendo determinista y sin el escape de WoW", function()
    resetAll()
    startSession()
    world.npcID["nameplate1"] = 188244
    local pack = obsDe({ { "nameplate1", 1, "ENGAGED" } })
    for t = 1, 8 do RAl:Feed(pack, t) end
    TEL:EndSession("TEST")
    local run = TEL:GetRun(1)
    truthy(run, "hay run guardada")
    local a = TEL:Export(run)
    local b = TEL:Export(run)
    equal(a, b, "byte a byte igual")
    falsy(a:find("|", 1, true), "ni un solo caracter de escape")
    truthy(a:find("summary.alignmentEvaluations=", 1, true), "clave nueva en el resumen")
    truthy(a:find("summary.physicalEpisodes=", 1, true), "episodios en el resumen")
    truthy(a:find("summary.npcIDSecretPeak=", 1, true), "medicion de identidad")
    truthy(a:find("summary.pullsVisited=", 1, true), "las claves viejas siguen")
    truthy(a:find("PHYSICAL_EPISODE_START", 1, true), "el evento esta")
end)

test("F4 el informe menciona alineacion e identidad", function()
    local run = TEL:GetRun(1)
    local texto = table.concat(TEL:ReportLines(run), "\n")
    truthy(texto:find("Alignment:", 1, true), "bloque de alineacion")
    truthy(texto:find("npcIDSecret=", 1, true), "medicion de npcID")
    truthy(texto:find("routeProgressInit=", 1, true), "inicializacion separada")
    truthy(texto:find("automaticRouteProgress=0", 1, true), "invariante a la vista")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- G · INVARIANTES DE LA FASE, LEIDAS DEL CODIGO
-- ═══════════════════════════════════════════════════════════════════════════

local function leer(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    -- Los comentarios no son codigo: una prohibicion no puede impedir
    -- explicarla. Se quitan antes de buscar.
    return (s:gsub("%-%-[^\n]*", ""))
end

test("G1 ningun modulo de la fase 4 escribe en RouteProgress", function()
    for _, nombre in ipairs({ "RouteSignature", "ExecutionEpisodeTracker",
                              "RoutePullCandidateScorer", "RouteAlignment" }) do
        local src = leer("modules/AdaptiveRoute/" .. nombre .. ".lua")
        for _, prohibido in ipairs({ "SetPull", "NextPull", "PreviousPull",
                                     "RestorePull", "MITZU_PULL_CHANGED" }) do
            falsy(src:find(prohibido, 1, true), nombre .. " toca " .. prohibido)
        end
    end
end)

test("G2 ningun modulo de la fase 4 toca flechas ni identidad canonica", function()
    for _, nombre in ipairs({ "RouteSignature", "ExecutionEpisodeTracker",
                              "RoutePullCandidateScorer", "RouteAlignment" }) do
        local src = leer("modules/AdaptiveRoute/" .. nombre .. ".lua")
        for _, prohibido in ipairs({ "RouteArrows", "MarkUnit", "UnmarkUnit",
                                     "RouteArrowPresenter", "ResolveForGuidance",
                                     "GuidanceEngine", "UnitGUID", "UnitName",
                                     "COMBAT_LOG_EVENT_UNFILTERED" }) do
            falsy(src:find(prohibido, 1, true), nombre .. " usa " .. prohibido)
        end
    end
end)

test("G3 el scorer es puro: sin estado propio ni acceso al cliente", function()
    local src = leer("modules/AdaptiveRoute/RoutePullCandidateScorer.lua")
    for _, prohibido in ipairs({ "GetTime", "CreateFrame", "C_Timer",
                                 "RegisterEvent", "issecretvalue", "pcall" }) do
        falsy(src:find(prohibido, 1, true), "el scorer usa " .. prohibido)
    end
    -- Ni un solo campo mutable en el modulo mas alla de la configuracion.
    for k, v in pairs(SC) do
        if type(v) ~= "function" and type(k) == "string" then
            truthy(k == "CONFIG" or k == "STATES" or k == "STATE_ORDER"
                   or k == "REASONS" or k == "COMPONENTS"
                   or k == "EVIDENCE_COMPONENTS",
                   "campo inesperado en el scorer: " .. k)
        end
    end
end)

test("G4 todos los umbrales viven en AlignmentConfig", function()
    local C = SC.CONFIG
    truthy(type(C.weights) == "table", "pesos")
    for _, comp in ipairs(SC.COMPONENTS) do
        truthy(type(C.weights[comp]) == "number", "peso de " .. comp)
    end
    for _, k in ipairs({ "strongThreshold", "probableThreshold", "weakThreshold",
                         "ambiguousMargin", "minPersistenceMs",
                         "minCoverageForStrong", "chainMinExcess", "maxCandidates" }) do
        truthy(type(C[k]) == "number", "umbral " .. k)
    end
    truthy(C.strongThreshold > C.probableThreshold, "orden de umbrales")
    truthy(C.probableThreshold > C.weakThreshold, "orden de umbrales (2)")
    -- Y los otros ficheros de la fase no traen numeros magicos de decision.
    for _, nombre in ipairs({ "ExecutionEpisodeTracker", "RouteAlignment" }) do
        local src = leer("modules/AdaptiveRoute/" .. nombre .. ".lua")
        falsy(src:find("Threshold", 1, true), nombre .. " define umbrales por su cuenta")
    end
end)

test("G5 el TOC carga los cuatro modulos y en orden", function()
    local toc = leer("MitzuMPlus_Historial.toc")
    local orden = {
        [[modules\AdaptiveRoute\ArrowDemo.lua]],
        [[modules\AdaptiveRoute\RouteSignature.lua]],
        [[modules\AdaptiveRoute\ExecutionEpisodeTracker.lua]],
        [[modules\AdaptiveRoute\RoutePullCandidateScorer.lua]],
        [[modules\AdaptiveRoute\RouteAlignment.lua]],
    }
    local anterior = 0
    for _, entrada in ipairs(orden) do
        local pos = toc:find(entrada, 1, true)
        truthy(pos, "falta en el TOC: " .. entrada)
        truthy(pos > anterior, "fuera de orden: " .. entrada)
        anterior = pos
    end
end)

test("G6 ArrowDemo alimenta la capa, y de forma opcional", function()
    local src = leer("modules/AdaptiveRoute/ArrowDemo.lua")
    truthy(src:find("RouteAlignment", 1, true), "ArrowDemo conoce la capa")
    truthy(src:find("pcall(RAl.Feed", 1, true), "y la llama protegida")
    -- Lo contrario no: la capa puede MIRAR si la demo esta encendida (lo dice
    -- en /emp align), pero lo unico que tiene permitido llamarle es eso.
    local ali = leer("modules/AdaptiveRoute/RouteAlignment.lua")
    local llamadas = 0
    for metodo in ali:gmatch("ArrowDemo[^T][^\n]-:([%w_]+)") do
        llamadas = llamadas + 1
        equal(metodo, "IsEnabled", "la capa llama a ArrowDemo:" .. metodo)
    end
    equal(llamadas, 1, "una sola lectura de la demo")
end)

return { tests = tests, assertions = assertions }
