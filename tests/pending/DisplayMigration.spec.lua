-- PENDING (phase 8): Mythic+ display migration 1.0 -> 1.1.
-- Contract: docs/tracker/DISPLAY_MIGRATION.md. The module does not exist yet;
-- tests/run_lua_tests.py only runs tests/core, so this spec is parsed by the
-- static checks but not executed. Move it to tests/core when DisplayMode lands.
local tests, assertions, failures = 0, 0, {}
local function equal(a, b, l)
    assertions = assertions + 1
    if a ~= b then error((l or "equal") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function truthy(v, l) equal(not not v, true, l) end
local function test(n, f) tests = tests + 1; local ok, e = pcall(f); if not ok then failures[#failures + 1] = n .. ": " .. tostring(e) end end

local function deepEqual(a, b, path)
    path = path or "value"
    if type(a) ~= type(b) then error(path .. ": type " .. type(a) .. " ~= " .. type(b), 0) end
    if type(a) ~= "table" then
        if a ~= b then error(path .. ": " .. tostring(a) .. " ~= " .. tostring(b), 0) end
        return true
    end
    for k, v in pairs(a) do deepEqual(v, b[k], path .. "." .. tostring(k)) end
    for k in pairs(b) do if a[k] == nil then error(path .. "." .. tostring(k) .. ": missing", 0) end end
    return true
end
local function same(a, b, l) assertions = assertions + 1; local ok, e = pcall(deepEqual, a, b, l); if not ok then error(e, 2) end end

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

local MODULE = rawget(_G, "DISPLAY_MODE_PATH") or "MitzuMPlus/modules/Tracker/DisplayMode.lua"
_G.MitzuMPlus = {}
dofile(MODULE)
local DM = _G.MitzuMPlus.DisplayMode

-- A 1.0.0-beta.1 install as AceDB leaves it on disk: hud.enabled=true was the
-- default, so it was NOT persisted; only non-default HUD options exist.
local function beta1Db()
    return {
        global = { version = "1.0.0-beta.1", runs = { { sessionID = "a" } }, nextRunID = 2,
                   client = { patch = "12.1.0" } },
        profile = { settings = { windowWidth = 1280, windowHeight = 760,
                                 hud = { locked = true, scale = 1.25, alpha = 0.8, x = 120, y = -40, point = "TOP" } } },
    }
end

local function freshDb()
    return { global = {}, profile = { settings = {} } }
end

-- What Init.lua must do, in this order (R1).
local function initSequence(db, newVersion, now)
    local previous = DM.CapturePreviousVersion(db.global)
    local changed, reason = DM.Migrate(db, previous, now)
    db.global.version = newVersion
    return changed, reason, previous
end

local OK = { enhanceable = true, missing = {} }
local KO = { enhanceable = false, missing = { "cmUpdateTime", "cmTimeLeft" } }

test("contract constants", function()
    equal(DM.MODES.ENHANCER, "ENHANCER"); equal(DM.MODES.LEGACY_HUD, "LEGACY_HUD")
    equal(DM.DEFAULT, "ENHANCER"); equal(DM.MIGRATION_KEY, "mplusDisplay110")
end)

test("R3 new install migrates to ENHANCER with a NEW_INSTALL marker", function()
    local db = freshDb()
    local changed, reason, previous = initSequence(db, "1.1.0", 1000)
    equal(previous, nil); equal(changed, true); equal(reason, "NEW_INSTALL")
    equal(db.profile.settings.mplusDisplay, "ENHANCER")
    local m = db.global.migrations.mplusDisplay110
    equal(m.done, true); equal(m.schema, 1); equal(m.from, "NEW_INSTALL"); equal(m.at, 1000)
end)

test("R2 upgrade from 1.0.0-beta.1 migrates to ENHANCER", function()
    local db = beta1Db()
    local changed, reason = initSequence(db, "1.1.0", 2000)
    equal(changed, true); equal(reason, "UPGRADE")
    equal(db.profile.settings.mplusDisplay, "ENHANCER")
    equal(db.global.migrations.mplusDisplay110.from, "1.0.0-beta.1")
end)

test("R1 previous global.version is captured before it is overwritten", function()
    local db = beta1Db()
    equal(DM.CapturePreviousVersion(db.global), "1.0.0-beta.1")
    equal(db.global.version, "1.0.0-beta.1", "capture does not mutate")
    local _, _, previous = initSequence(db, "1.1.0", 1)
    equal(previous, "1.0.0-beta.1")
    equal(db.global.version, "1.1.0", "Init overwrites only after migrating")
    equal(db.global.migrations.mplusDisplay110.from, "1.0.0-beta.1")
    -- Migrate itself never writes global.version.
    local db2 = beta1Db()
    DM.Migrate(db2, "1.0.0-beta.1", 1)
    equal(db2.global.version, "1.0.0-beta.1")
    equal(DM.CapturePreviousVersion({ version = "" }), nil, "empty version is not a version")
end)

test("R11 repeated migration is a no-op", function()
    local db = beta1Db()
    initSequence(db, "1.1.0", 10)
    local snapshot = copy(db)
    for i = 1, 3 do
        local changed, reason = initSequence(db, "1.1.0", 10 + i)
        equal(changed, false); equal(reason, "ALREADY_MIGRATED")
    end
    same(db, snapshot, "db after repeated runs")
    -- A later user choice survives further startups.
    db.profile.settings.mplusDisplay = "LEGACY_HUD"
    initSequence(db, "1.1.1", 99)
    equal(db.profile.settings.mplusDisplay, "LEGACY_HUD")
    equal(db.global.migrations.mplusDisplay110.from, "1.0.0-beta.1")
end)

test("R11 existing settings are untouched and a valid prior choice is respected", function()
    local db = beta1Db()
    local before = copy(db.profile.settings)
    initSequence(db, "1.1.0", 5)
    before.mplusDisplay = "ENHANCER"
    same(db.profile.settings, before, "settings")
    same(db.global.runs, { { sessionID = "a" } }, "history")
    equal(db.global.nextRunID, 2)

    local dev = { global = { version = "1.1.0-dev.4" }, profile = { settings = { mplusDisplay = "LEGACY_HUD" } } }
    initSequence(dev, "1.1.0", 6)
    equal(dev.profile.settings.mplusDisplay, "LEGACY_HUD", "valid existing value kept")
    local bad = { global = { version = "1.0.0-beta.1" }, profile = { settings = { mplusDisplay = "COMPACT" } } }
    initSequence(bad, "1.1.0", 7)
    equal(bad.profile.settings.mplusDisplay, "ENHANCER", "invalid value replaced")
end)

test("R7 legacy HUD configuration is preserved exactly", function()
    local db = beta1Db()
    local hud = db.profile.settings.hud
    local before = copy(hud)
    initSequence(db, "1.1.0", 1)
    equal(db.profile.settings.hud, hud, "same table")
    same(hud, before, "hud settings")
    DM.Resolve(db.profile.settings, OK); DM.Resolve(db.profile.settings, KO)
    same(hud, before, "hud settings after resolve")
    equal(hud.enabled, nil, "migration does not materialize hud.enabled")
end)

test("R5 R6 migration never reads or writes hud.enabled", function()
    local accessed = {}
    local raw = { scale = 1 }
    local proxy = setmetatable({}, {
        __index = function(_, k) accessed[#accessed + 1] = k; return raw[k] end,
        __newindex = function(_, k, v) accessed[#accessed + 1] = "write:" .. tostring(k); raw[k] = v end,
    })
    local db = { global = { version = "1.0.0-beta.1" }, profile = { settings = { hud = proxy } } }
    initSequence(db, "1.1.0", 1)
    DM.Resolve(db.profile.settings, OK); DM.Resolve(db.profile.settings, KO)
    equal(#accessed, 0, "hud accessed: " .. table.concat(accessed, ","))
end)

test("R8 manual LEGACY_HUD uses the preserved historical configuration", function()
    local db = beta1Db()
    initSequence(db, "1.1.0", 1)
    db.profile.settings.mplusDisplay = "LEGACY_HUD"
    for _, probe in ipairs({ OK, KO }) do
        local r = DM.Resolve(db.profile.settings, probe)
        equal(r.preferred, "LEGACY_HUD"); equal(r.active, "LEGACY_HUD"); equal(r.fallback, false)
    end
    equal(DM.LegacyHudSettings(db.profile.settings), db.profile.settings.hud)
    equal(DM.LegacyHudSettings(db.profile.settings).scale, 1.25)
end)

test("enhancer available: ENHANCER is active", function()
    local db = beta1Db(); initSequence(db, "1.1.0", 1)
    local r = DM.Resolve(db.profile.settings, OK)
    equal(r.preferred, "ENHANCER"); equal(r.active, "ENHANCER"); equal(r.fallback, false); equal(r.reason, nil)
end)

test("R9 enhancer unavailable: runtime fallback without changing the preference", function()
    local db = beta1Db(); initSequence(db, "1.1.0", 1)
    local before = copy(db.profile.settings)
    local r = DM.Resolve(db.profile.settings, KO)
    equal(r.preferred, "ENHANCER"); equal(r.active, "LEGACY_HUD"); equal(r.fallback, true)
    equal(r.reason, "ENHANCER_UNAVAILABLE:cmUpdateTime,cmTimeLeft")
    same(db.profile.settings, before, "settings unchanged by fallback")
    equal(DM.Resolve(db.profile.settings, nil).active, "LEGACY_HUD", "no probe result counts as unavailable")
end)

test("R9 fallback reason is recorded once per resolution, nothing when not falling back", function()
    local rec = { entries = {} }
    function rec:Record(s, e, d) self.entries[#self.entries + 1] = { s = s, e = e, d = d } end
    DM.RecordFallback(rec, DM.Resolve({ mplusDisplay = "ENHANCER" }, OK))
    equal(#rec.entries, 0)
    DM.RecordFallback(rec, DM.Resolve({ mplusDisplay = "ENHANCER" }, KO))
    equal(#rec.entries, 1); equal(rec.entries[1].s, "DISPLAY"); equal(rec.entries[1].e, "ENHANCER_FALLBACK")
    truthy(tostring(rec.entries[1].d.reason):find("cmUpdateTime", 1, true))
    DM.RecordFallback(nil, DM.Resolve({}, KO))   -- no recorder: must not throw
end)

test("R10 a later session with a working enhancer returns to ENHANCER", function()
    local db = beta1Db(); initSequence(db, "1.1.0", 1)
    local session1 = DM.Resolve(db.profile.settings, KO)
    equal(session1.active, "LEGACY_HUD")
    -- /reload or next login: persisted data is whatever session 1 left.
    local persisted = copy(db)
    initSequence(persisted, "1.1.0", 2)
    local session2 = DM.Resolve(persisted.profile.settings, OK)
    equal(session2.active, "ENHANCER"); equal(session2.fallback, false)
    equal(persisted.profile.settings.mplusDisplay, "ENHANCER")
end)

test("profiles the migration never visited resolve to the ENHANCER default", function()
    equal(DM.Resolve({}, OK).preferred, "ENHANCER")
    equal(DM.Resolve({ hud = { enabled = true } }, OK).active, "ENHANCER")
    equal(DM.Resolve(nil, OK).active, "ENHANCER")
end)

if #failures > 0 then error(string.format("DisplayMigration: %d failures\n%s", #failures, table.concat(failures, "\n")), 0) end
return { tests = tests, assertions = assertions }
