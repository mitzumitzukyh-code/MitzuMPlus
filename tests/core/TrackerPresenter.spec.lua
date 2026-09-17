-- TrackerPresenter: pure visual model for Mitzu Tracker. No frames, no client.
local tests, assertions, failures = 0, 0, {}
local function equal(a, b, l)
    assertions = assertions + 1
    if a ~= b then error((l or "equal") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function truthy(v, l) equal(not not v, true, l) end
local function test(n, f) tests = tests + 1; local ok, e = pcall(f); if not ok then failures[#failures + 1] = n .. ": " .. tostring(e) end end

_G.MitzuMPlus = {}
dofile("MitzuMPlus/modules/Tracker/TrackerPresenter.lua")
local TP = _G.MitzuMPlus.TrackerPresenter
local RATIOS = { KEY_UPGRADE_PLUS2_RATIO = 0.8, KEY_UPGRADE_PLUS3_RATIO = 0.6 }

-- Reposo de los Reyes +12 (Retail dev.5), TrackerState shape.
local function reposo(elapsed, forces, bosses, deaths)
    return { status = "RUNNING", mapID = 249, mapName = "Reposo de los Reyes", keystoneLevel = 12, timeLimit = 1980,
             elapsedBase = elapsed, forcesCurrent = forces, forcesTotal = 608, forcesPercent = forces / 608 * 100,
             forcesRemaining = 608 - forces, bossesCompleted = bosses, bossesTotal = 4, deaths = deaths or 0,
             deathTimeLost = (deaths or 0) * 5, warnings = {}, bosses = {} }
end
local function engine(result, confidence, confident, extra)
    local p = { result = result, confidence = confidence, resultConfident = confident == true,
                plus2Time = 1584, plus3Time = 1188, timeLimit = 1980 }
    for k, v in pairs(extra or {}) do p[k] = v end
    return p
end
local function build(status, state, elapsed, prediction, extra)
    local input = { enabled = true, status = status, state = state, elapsed = elapsed, prediction = prediction,
                    settings = { showConfidence = true, showETA = true }, constants = RATIOS }
    for k, v in pairs(extra or {}) do input[k] = v end
    return TP.Build(input)
end

test("modes: hidden, pending, running, completing, summary, preview, disabled", function()
    equal(TP.ModeFor({ status = "IDLE" }), "HIDDEN")
    equal(TP.ModeFor({ status = "PENDING" }), "PENDING")
    equal(TP.ModeFor({ status = "RUNNING" }), "RUNNING")
    equal(TP.ModeFor({ status = "COMPLETING" }), "COMPLETING")
    equal(TP.ModeFor({ status = "COMPLETED" }), "HIDDEN", "completed without summary window")
    equal(TP.ModeFor({ status = "COMPLETED", summary = true }), "SUMMARY")
    equal(TP.ModeFor({ status = "RUNNING", enabled = false }), "HIDDEN")
    equal(TP.ModeFor({ status = "IDLE", enabled = false, preview = true }), "PREVIEW")
    local m = TP.Build({ status = "IDLE" })
    equal(m.mode, "HIDDEN"); equal(m.prediction.code, "NONE"); equal(m.timer, nil)
end)

test("fixture T1/T2/T3: timer, thresholds, forces and bosses are exact", function()
    local cases = {
        { 152, 136, 0, "+2", 15, "30:28", "22.37%", "136 / 608", "faltan 472", "0/4", "+3 17:16" },
        { 353, 211, 1, "+2", 27, "27:07", "34.70%", "211 / 608", "faltan 397", "1/4", "+3 13:55" },
        { 804, 449, 2, "+2", 50, "19:36", "73.85%", "449 / 608", "faltan 159", "2/4", "+3 6:24" },
    }
    for _, c in ipairs(cases) do
        local m = build("RUNNING", reposo(c[1], c[2], c[3]), c[1], engine(c[4], c[5], false))
        equal(m.mode, "RUNNING"); equal(m.dungeonName, "Reposo de los Reyes"); equal(m.keyText, "+12")
        equal(m.timer.text, c[6]); equal(m.timer.remaining, 1980 - c[1]); equal(m.timer.overtime, false)
        equal(m.timer.segments[1].text, c[11]); equal(m.timer.bracket, "+3")
        equal(m.prediction.code, c[4]); equal(m.prediction.confidence, c[5]); equal(m.prediction.confidenceText, c[5] .. "%")
        equal(m.prediction.provisional, true)
        equal(m.forces.percentText, c[7]); equal(m.forces.countText, c[8]); equal(m.forces.remainingText, c[9])
        equal(m.bosses.text, c[10]); equal(m.bosses.total, 4)
    end
end)

test("clock bracket and pace prediction are separate concepts", function()
    -- 12:00 in: the clock still allows +3 (19:48), the pace projects +2.
    local m = build("RUNNING", reposo(720, 300, 1), 720, engine("+2", 70, true))
    equal(m.timer.bracket, "+3"); equal(m.prediction.code, "+2")
    equal(m.timer.segments[1].current, true); equal(m.timer.segments[1].lost, false)
    -- 28:00 in: +3 and +2 are gone on the clock.
    m = build("RUNNING", reposo(1680, 600, 3), 1680, engine("+1", 90, true))
    equal(m.timer.bracket, "+1"); equal(m.timer.segments[1].lost, true); equal(m.timer.segments[2].lost, true)
    equal(m.timer.segments[1].text, "+3"); equal(m.timer.segments[3].text, "+1 5:00")
end)

test("overtime: negative remaining, red state, OVERTIME prediction", function()
    local m = build("RUNNING", reposo(2045, 608, 3), 2045, engine("FUERA", 99, true))
    equal(m.timer.overtime, true); equal(m.timer.text, "-1:05", "never +1:05 (reads like a +1)")
    equal(m.timer.bracket, "OVERTIME"); equal(m.prediction.code, "OVERTIME"); equal(m.timer.fraction, 1)
end)

test("prediction allowlist and missing confidence", function()
    for input, expected in pairs({ ["+3"] = "+3", ["+2"] = "+2", ["+1"] = "+1", FUERA = "OVERTIME" }) do
        equal(TP.BuildPrediction({ result = input }).code, expected)
    end
    for _, bad in ipairs({ "NEXT_BOSS", "ROUTE", "OVERTIME_X", 3 }) do
        equal(TP.BuildPrediction({ result = bad }).code, "NONE")
    end
    equal(TP.BuildPrediction(nil).code, "NONE"); equal(TP.BuildPrediction(nil).text, "--")
    local p = TP.BuildPrediction({ result = "+2" })
    equal(p.confidence, nil); equal(p.confidenceText, nil, "no placeholder without confidence")
    local none = TP.BuildPrediction({ result = "ROUTE", confidence = 80 })
    equal(none.confidenceText, nil, "no confidence without a recognizable bracket")
end)

test("confidence and ETA toggles have a real effect; ETA needs a confident projection", function()
    local pred = { result = "+2", confidence = 82, resultConfident = true, projectedTime = 1390,
                   effectiveElapsed = 900, timeLimit = 1980 }
    local p = TP.BuildPrediction(pred, { showConfidence = true, showETA = true })
    equal(p.confidenceText, "82%"); equal(p.etaText, "final ~23:10")
    p = TP.BuildPrediction(pred, { showConfidence = false, showETA = true })
    equal(p.confidenceText, nil); equal(p.etaText, "final ~23:10")
    p = TP.BuildPrediction(pred, { showConfidence = true, showETA = false })
    equal(p.etaText, nil)
    pred.resultConfident = false
    equal(TP.BuildPrediction(pred).etaText, nil)
end)

test("pending: no timer, no fake prediction, criteria already known are shown", function()
    local s = reposo(nil, 136, 0)
    s.status = "PENDING"
    local m = build("PENDING", s, nil, engine("+1", 10, false))
    equal(m.mode, "PENDING"); equal(m.timer.text, "--:--"); equal(m.timer.subText, "Esperando temporizador")
    equal(m.prediction.code, "NONE", "no prediction before the server timer")
    equal(m.forces.countText, "136 / 608"); equal(m.timer.bracket, nil)
    equal(#m.timer.segments, 3); equal(m.timer.segments[1].text, "+3 19:48", "thresholds from the limit")
end)

test("missing optional fields never produce fake zeros", function()
    local m = build("RUNNING", { mapID = 9999 }, nil, nil)
    equal(m.dungeonName, "Mitica+"); equal(m.keyText, nil)
    equal(m.timer.text, "--:--"); equal(m.timer.remaining, nil); equal(#m.timer.segments, 0)
    equal(m.forces.available, false); equal(m.forces.percentText, "--"); equal(m.forces.countText, nil)
    equal(m.bosses.available, false); equal(m.bosses.text, "--")
    equal(m.deaths.text, "--"); equal(m.deaths.penaltyText, nil); equal(m.prediction.code, "NONE")
    -- Forces percent without count/total: percent only.
    m = build("RUNNING", { timeLimit = 1800, forcesPercent = 40 }, 100, nil)
    equal(m.forces.percentText, "40.00%"); equal(m.forces.countText, nil); equal(m.forces.remainingText, nil)
    -- No limit: elapsed only, no thresholds invented.
    m = build("RUNNING", {}, 125, nil)
    equal(m.timer.text, "2:05"); equal(#m.timer.segments, 0)
    -- No ratios and no engine: no thresholds invented either.
    m = TP.Build({ status = "RUNNING", state = { timeLimit = 1800 }, elapsed = 10, constants = {} })
    equal(#m.timer.segments, 0)
end)

test("deaths: count always, penalty only when Blizzard publishes it", function()
    local d = TP.BuildDeaths({ deaths = 14, deathTimeLost = 70 })
    equal(d.text, "14"); equal(d.penaltyText, "+1:10")
    d = TP.BuildDeaths({ deaths = 3 })
    equal(d.text, "3"); equal(d.penaltyText, nil)
    d = TP.BuildDeaths({ deaths = 0, deathTimeLost = 0 })
    equal(d.text, "0"); equal(d.penaltyText, nil)
end)

test("completing keeps the last valid state and freezes the final time", function()
    local s = reposo(1677, 608, 3, 14)
    s.status, s.finalElapsed = "COMPLETING", 1677
    local m = build("COMPLETING", s, 1677, engine("+1", 70, true))
    equal(m.mode, "COMPLETING"); equal(m.timer.frozen, true); equal(m.timer.text, "5:03")
    equal(m.prediction.code, "+1", "last prediction stays while the end converges")
    equal(m.forces.percentText, "100.00%"); equal(m.bosses.text, "3/4", "not yet confirmed")
    equal(m.summary, nil)
end)

test("summary of the real run: 3/4 observed + official completion shows 4/4 marked inferred", function()
    local s = reposo(1677, 608, 3, 14)
    s.status, s.finalElapsed = "COMPLETED", 1677
    s.terminalStateConfirmed, s.completionSource = true, "CHALLENGE_MODE_COMPLETED"
    s.bossCountSource, s.bossesCompletedFinal, s.bossesCompletedObserved = "INFERRED_FROM_COMPLETION_EVENT", 4, 3
    s.forcesCompletionSource, s.forcesPercentFinal = "OBSERVED", 100
    s.bosses = { { index = 1, name = "A", completed = true }, { index = 2, name = "B", completed = true },
                 { index = 3, name = "C", completed = true }, { index = 4, name = "D", completed = false } }
    local m = build("COMPLETED", s, 1677, nil, { summary = true,
        final = TP.FinalFromRun({ inTime = true, keystoneUpgradeLevels = 1, completionTime = 1677, completionInfoSource = "API" }) })
    equal(m.mode, "SUMMARY")
    equal(m.summary.title, "LLAVE COMPLETADA"); equal(m.summary.official, true); equal(m.summary.timeText, "27:57 / 33:00")
    equal(m.prediction.code, "+1"); equal(m.prediction.label, "RESULTADO"); equal(m.prediction.sourceText, "oficial")
    equal(m.bosses.text, "4/4"); equal(m.bosses.inferred, true); equal(m.bosses.complete, true)
    equal(m.bosses.list[4].completed, true)
    equal(s.bossesCompleted, 3, "the presenter never rewrites the state")
    equal(m.forces.percentText, "100.00%"); equal(m.forces.inferred, nil); equal(m.deaths.text, "14")
    -- Without the authority the observed value is shown as-is.
    s.terminalStateConfirmed = nil
    m = build("COMPLETED", s, 1677, nil, { summary = true })
    equal(m.bosses.text, "3/4"); equal(m.bosses.inferred, nil)
end)

test("summary without official result falls back to the last pace, and overtime title", function()
    local s = reposo(1677, 608, 4)
    s.finalElapsed = 1677
    local m = build("COMPLETED", s, nil, nil, { summary = true, final = TP.FinalFromRun({ completionTime = 1677 }, "+2") })
    equal(m.prediction.code, "+2"); equal(m.prediction.sourceText, "ultimo ritmo"); equal(m.summary.official, false)
    m = build("COMPLETED", s, nil, nil, { summary = true,
        final = TP.FinalFromRun({ inTime = false, completionTime = 2100, completionInfoSource = "API" }) })
    equal(m.summary.title, "LLAVE FUERA DE TIEMPO"); equal(m.prediction.code, "OVERTIME")
    m = build("COMPLETED", s, nil, nil, { summary = true })
    equal(m.prediction.code, "NONE"); equal(m.summary.title, "LLAVE TERMINADA")
end)

test("official completed results", function()
    for levels, expected in pairs({ [1] = "+1", [2] = "+2", [3] = "+3" }) do
        equal(TP.FinalFromRun({ inTime = true, keystoneUpgradeLevels = levels, completionTime = 1000,
                                completionInfoSource = "API" }).code, expected)
    end
    equal(TP.FinalFromRun({ inTime = false, completionInfoSource = "API" }).code, "OVERTIME")
    equal(TP.FinalFromRun({ inTime = false }, "+1").source, "LAST_PREDICTION", "Core defaults are not data")
    equal(TP.FinalFromRun(nil), nil)
end)

test("formatting survives large numbers and long runs", function()
    equal(TP.FormatCount(87), "87"); equal(TP.FormatCount(608), "608"); equal(TP.FormatCount(1234), "1,234")
    equal(TP.FormatCount(1450), "1,450"); equal(TP.FormatCount(1234567), "1,234,567"); equal(TP.FormatCount(nil), nil)
    equal(TP.BuildForces({ forcesCurrent = 1234, forcesTotal = 1450, forcesPercent = 1234 / 1450 * 100 }).countText, "1,234 / 1,450")
    equal(TP.BuildForces({ forcesCurrent = 87, forcesTotal = 100, forcesPercent = 87 }).countText, "87 / 100")
    local done = TP.BuildForces({ forcesCurrent = 608, forcesTotal = 608, forcesPercent = 100 })
    equal(done.percentText, "100.00%"); equal(done.remainingText, "completo"); equal(done.fraction, 1)
    equal(TP.BuildForces({ forcesCurrent = 700, forcesTotal = 608, forcesPercent = 115 }).fraction, 1, "bar never overflows")
    equal(TP.FormatClock(0), "0:00"); equal(TP.FormatClock(3725), "1:02:05"); equal(TP.FormatClock(-65), "-1:05")
end)

test("preview input is realistic and fully synthetic", function()
    local input = TP.PreviewInput({ showConfidence = true, showETA = true })
    local m = TP.Build(input)
    equal(m.mode, "PREVIEW"); equal(m.preview, true)
    equal(m.dungeonName, "Reposo de los Reyes"); equal(m.keyText, "+12")
    equal(m.timer.text, "19:37"); equal(m.prediction.code, "+2"); equal(m.prediction.confidenceText, "50%")
    equal(m.forces.countText, "449 / 608"); equal(m.forces.percentText, "73.85%"); equal(m.forces.remainingText, "faltan 159")
    equal(m.bosses.text, "2/4"); equal(m.deaths.text, "3")
    equal(TP.Build(TP.PreviewInput({ showConfidence = false })).prediction.confidenceText, nil)
end)

if #failures > 0 then error(string.format("TrackerPresenter: %d failures\n%s", #failures, table.concat(failures, "\n")), 0) end
return { tests = tests, assertions = assertions }
