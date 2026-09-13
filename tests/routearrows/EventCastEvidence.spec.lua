-- FASE 3E: seguridad, ciclo de vida y aislamiento de casts por evento.

local assertions, tests, failures = 0, 0, {}
local function equal(actual, expected, label)
    assertions = assertions + 1
    if actual ~= expected then
        error(string.format("%s: esperado %s, recibido %s", label,
            tostring(expected), tostring(actual)), 2)
    end
end
local function test(name, fn)
    tests = tests + 1
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end

local SECRET_VALUE = {}
local clock = 100
function issecretvalue(value) return rawequal(value, SECRET_VALUE) end
function GetTime() return clock end
function UnitExists(token) return token == "nameplate1" end

local castReturns = {}
function UnitCastingInfo(token)
    local r = castReturns[token]
    if not r then return nil end
    return r[1], nil, nil, nil, nil, nil, nil, nil, r[2]
end
function UnitChannelInfo() return nil end

local registered, onEvent = {}, nil
function CreateFrame()
    return {
        RegisterEvent = function(_, event) registered[event] = true end,
        SetScript = function(_, kind, fn) if kind == "OnEvent" then onEvent = fn end end,
    }
end

-- Espacio de nombres de MitzuRouteArrows con una fachada vacia: estos
-- modulos no leen nada de MitzuMPlus.
_G.MitzuRouteArrows = { Host = {} }
dofile("MitzuRouteArrows/Evidence/CastEvidence.lua")
dofile("MitzuRouteArrows/Evidence/EventCastEvidence.lua")
local CE = _G.MitzuRouteArrows.CastEvidence
local ECE = _G.MitzuRouteArrows.EventCastEvidence

local function reset()
    ECE:Clear()
    ECE._spellIDEventSafeObserved = false
    castReturns = {}
    clock = 100
end

test("A safe spellID in START is positive event evidence", function()
    reset()
    ECE:Observe("NAME_PLATE_UNIT_ADDED", "nameplate1")
    ECE:Observe("UNIT_SPELLCAST_START", "nameplate1", SECRET_VALUE, 123456)
    local e = ECE:InspectToken("nameplate1")
    equal(e.eventState, "SEEN", "A event")
    equal(e.eventType, "START", "A type")
    equal(e.castState, "CASTING", "A cast")
    equal(e.spellIDState, "AVAILABLE", "A id state")
    equal(e.safeSpellID, "YES", "A safe")
    equal(e.safeSpellIDValue, 123456, "A value")
end)

test("B secret spellID is neither stored nor exposed", function()
    reset()
    ECE:Observe("UNIT_SPELLCAST_START", "nameplate1", SECRET_VALUE, SECRET_VALUE)
    local e = ECE:InspectToken("nameplate1")
    equal(e.spellIDState, "SECRET", "B state")
    equal(e.safeSpellID, "NO", "B safe")
    equal(e.safeSpellIDValue, nil, "B no value")
    equal(select(2, ECE:Get("nameplate1")), nil, "B cache has no id")
end)

test("C event without spellID remains EVENT_ONLY", function()
    reset()
    ECE:Observe("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", SECRET_VALUE, nil)
    local e = ECE:InspectToken("nameplate1")
    local _, r = ECE:Snapshot()
    equal(e.eventState, "SEEN", "C event")
    equal(e.eventType, "SUCCEEDED", "C type")
    equal(e.spellIDState, "UNAVAILABLE", "C id")
    equal(r.eventOnly, 1, "C event only")
end)

test("D STOP clears active spell immediately but keeps terminal event briefly", function()
    reset()
    ECE:Observe("UNIT_SPELLCAST_START", "nameplate1", SECRET_VALUE, 321)
    clock = 101
    ECE:Observe("UNIT_SPELLCAST_STOP", "nameplate1", SECRET_VALUE, 321)
    local e = ECE:InspectToken("nameplate1")
    equal(e.eventType, "STOP", "D type")
    equal(e.castState, "NONE", "D inactive")
    equal(e.spellIDState, "UNAVAILABLE", "D id cleared")
    equal(e.safeSpellIDValue, nil, "D value cleared")
    clock = 107
    equal(ECE:InspectToken("nameplate1").eventState, "NONE", "D expires")
end)

test("E removed nameplate invalidates evidence", function()
    reset()
    ECE:Observe("UNIT_SPELLCAST_START", "nameplate1", SECRET_VALUE, 111)
    ECE:Observe("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    equal(ECE:InspectToken("nameplate1").eventState, "NONE", "E removed")
end)

test("F reused token starts a clean generation", function()
    reset()
    ECE:Observe("NAME_PLATE_UNIT_ADDED", "nameplate1")
    ECE:Observe("UNIT_SPELLCAST_START", "nameplate1", SECRET_VALUE, 111)
    local oldGeneration = ECE:InspectToken("nameplate1").generation
    ECE:Observe("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    ECE:Observe("NAME_PLATE_UNIT_ADDED", "nameplate1")
    local e = ECE:InspectToken("nameplate1")
    equal(e.eventState, "NONE", "F no inheritance")
    equal(ECE._generation.nameplate1 > oldGeneration, true, "F generation advanced")
end)

test("G SAME_UNIT does not change cast evidence into identity", function()
    reset()
    _G.MitzuRouteArrows.UnitLinkEvidence = { Compare = function() return "SAME_UNIT" end }
    ECE:Observe("UNIT_SPELLCAST_START", "nameplate1", SECRET_VALUE, 222)
    local e = ECE:InspectToken("nameplate1")
    equal(e.eventState, "SEEN", "G event stays event")
    equal(e.identityState, "UNKNOWN", "G identity remains unknown")
    equal(e.matchState, nil, "G no match")
end)

test("H cast evidence exposes no MATCH operation or result", function()
    reset()
    castReturns.nameplate1 = { "casting", 333 }
    local state, id, idState = CE:Evaluate("nameplate1")
    equal(state, "CASTING", "H cast")
    equal(id, 333, "H safe id")
    equal(idState, "AVAILABLE", "H id state")
    castReturns.nameplate1 = { "casting", SECRET_VALUE }
    local _, secretID, secretState = CE:Evaluate("nameplate1")
    equal(secretID, nil, "H polling secret not exposed")
    equal(secretState, "SECRET", "H polling secret state")
    equal(CE.MATCH, nil, "H CE no MATCH")
    equal(ECE.MATCH, nil, "H ECE no MATCH")
end)

test("I absence of cast is not negative identity evidence", function()
    reset()
    local state, id, idState = CE:Evaluate("nameplate1")
    equal(state, "NOT_CASTING", "I no cast")
    equal(id, nil, "I no id")
    equal(idState, "UNAVAILABLE", "I unavailable")
    equal(ECE:InspectToken("nameplate1").eventState, "NONE", "I no event")
end)

test("event wiring includes token lifecycle and requested cast events", function()
    reset()
    equal(registered.NAME_PLATE_UNIT_ADDED, true, "wire add")
    equal(registered.NAME_PLATE_UNIT_REMOVED, true, "wire remove")
    equal(registered.UNIT_SPELLCAST_START, true, "wire start")
    equal(registered.UNIT_SPELLCAST_CHANNEL_START, true, "wire channel")
    equal(registered.UNIT_SPELLCAST_SUCCEEDED, true, "wire succeeded")
    equal(registered.UNIT_SPELLCAST_STOP, true, "wire stop")
    equal(registered.UNIT_SPELLCAST_INTERRUPTED, true, "wire interrupted")
    equal(type(onEvent), "function", "wire handler")
    onEvent(nil, "UNIT_SPELLCAST_START", "nameplate2", SECRET_VALUE, 777)
    equal(ECE:InspectToken("nameplate2").eventType, "START", "wire token forwarded")
    equal(ECE:InspectToken("nameplate2").safeSpellIDValue, 777, "wire payload forwarded")
end)

if #failures > 0 then
    error(string.format("EventCastEvidence: %d tests, %d assertions, %d failures\n%s",
        tests, assertions, #failures, table.concat(failures, "\n")), 0)
end
return { tests = tests, assertions = assertions }
