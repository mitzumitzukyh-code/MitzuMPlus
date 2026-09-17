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
    -- A final count WITHOUT the completion event behind it is not an authority
    -- either: only bossCountSource may promote it.
    s.terminalStateConfirmed = true
    for _, source in ipairs({ "OBSERVED", "CRITERIA", "UNKNOWN" }) do
        s.bossCountSource = source
        m = build("COMPLETED", s, 1677, nil, { summary = true })
        equal(m.bosses.text, "3/4", "bossCountSource=" .. source .. " must not infer a boss")
        equal(m.bosses.inferred, nil, "bossCountSource=" .. source)
        equal(m.bosses.list[4].completed, false, "bossCountSource=" .. source)
    end
    s.bossCountSource = nil
    m = build("COMPLETED", s, 1677, nil, { summary = true })
    equal(m.bosses.text, "3/4", "no source at all: nothing is inferred")
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

-- ---------------------------------------------------------------------------
-- EMBEDDED MODEL (dev.7): what Mitzu adds to Blizzard's Mythic+ block.
-- ---------------------------------------------------------------------------

local function glyphs(text) return #(text:gsub("[\128-\191]", "")) * 6 end

test("FitText is deterministic: first candidate that fits, shortest without a width, empty if nothing fits", function()
    local c = { "+3 6:25  +2 13:01  +1 19:37", "+3 6:25  +2 13:01", "+3 6:25" }
    equal(TP.FitText(c, 200, glyphs), c[1]); equal(select(2, TP.FitText(c, 200, glyphs)), 1)
    equal(TP.FitText(c, 102, glyphs), c[2]); equal(TP.FitText(c, 101, glyphs), c[3])
    equal(TP.FitText(c, 42, glyphs), c[3]); equal(TP.FitText(c, 41, glyphs), "")
    equal(TP.FitText(c, nil, glyphs), c[3], "unknown width: the most compact")
    equal(TP.FitText({}, 500, glyphs), ""); equal(TP.FitText(nil, 500, glyphs), "")
    for _ = 1, 3 do equal(TP.FitText(c, 150, glyphs), c[2], "same input, same output") end
end)

-- Guarida de Nalorakk +10 (Retail dev.7): limit 32:00 -> +3 at 19:12, +2 at 25:36.
local function nalorakk(elapsed, forces, deaths)
    return { status = "RUNNING", mapName = "Guarida de Nalorakk", keystoneLevel = 10, timeLimit = 1920,
             forcesCurrent = forces, forcesTotal = 729, forcesPercent = forces / 729 * 100,
             forcesRemaining = 729 - forces, bossesCompleted = 1, bossesTotal = 4,
             deaths = deaths or 0, deathTimeLost = (deaths or 0) * 5, warnings = {}, bosses = {} }
end
local function nalorakkModel(elapsed, forces, deaths, prediction, settings)
    return TP.Build({ enabled = true, status = "RUNNING", state = nalorakk(elapsed, forces, deaths), elapsed = elapsed,
                      prediction = prediction, constants = RATIOS,
                      settings = settings or { showConfidence = true, showETA = true } })
end
local function pred(result, confidence, confident, projected)
    return { result = result, confidence = confidence, resultConfident = confident == true,
             projectedTime = projected, effectiveElapsed = 675, timeLimit = 1920 }
end

test("next relevant threshold: +3 -> +2 -> +1 -> none, margin from the centralized thresholds", function()
    local cases = {
        { 675, "+3", 477 },   -- real run: "+3 7:57"
        { 1151, "+3", 1 }, { 1152, "+3", 0 }, { 1153, "+2", 383 },
        { 1200, "+2", 336 }, { 1536, "+2", 0 }, { 1537, "+1", 383 },
        { 1600, "+1", 320 }, { 1920, "+1", 0 },
    }
    for _, c in ipairs(cases) do
        local n = TP.GetNextRelevantUpgradeThreshold(nalorakkModel(c[1], 329))
        truthy(n, "threshold at " .. c[1]); equal(n.upgrade, c[2], "upgrade at " .. c[1]); equal(n.time, c[3], "time at " .. c[1])
    end
    equal(TP.GetNextRelevantUpgradeThreshold(nalorakkModel(1921, 700)), nil, "overtime: no upgrade left")
    equal(TP.GetNextRelevantUpgradeThreshold(nalorakkModel(nil, 329)), nil, "no clock yet")
    equal(TP.GetNextRelevantUpgradeThreshold(TP.Build({ status = "RUNNING", state = {}, elapsed = 60 })), nil, "no limit")
    equal(TP.GetNextRelevantUpgradeThreshold(nil), nil)
    -- Engine thresholds win over the ratios (same source the prediction uses).
    local m = nalorakkModel(675, 329, 0, { result = "+1", plus3Time = 1100, plus2Time = 1500, timeLimit = 1920 })
    equal(TP.GetNextRelevantUpgradeThreshold(m).time, 425)
end)

test("embedded model: one threshold, pace with secondary parts, forces without %, penalty only when published", function()
    local m = nalorakkModel(675, 329, 4, pred("+1", 30, true, 1790))
    local e = TP.BuildEmbedded(m, { showConfidence = true, showETA = true })
    equal(e.active, true)
    equal(e.threshold.text, "+3 7:57"); equal(e.threshold.upgrade, "+3"); equal(e.threshold.timeText, "7:57")
    equal(e.paceText, "RITMO +1"); equal(e.paceValue, "+1"); equal(e.confidenceText, "30%"); equal(e.etaText, "~29:50")
    equal(e.forcesPrimary, "329 / 729"); equal(e.forcesPrimaryCompact, "329/729"); equal(e.forcesSecondary, "faltan 400")
    equal(e.penaltyText, "-0:20")
    for k, v in pairs(e) do
        if type(v) == "string" then
            if k:find("^forces") then truthy(not v:find("%%"), "no percentage duplicated in " .. k .. "=" .. v) end
            truthy(not v:find(TP.TEXT.DEATHS, 1, true), "Blizzard already shows the death count: " .. k)
        end
    end
    -- Disabled confidence (settings) and ETA (options) never leak through.
    m = nalorakkModel(675, 329, 4, pred("+1", 30, true, 1790), { showConfidence = false, showETA = true })
    e = TP.BuildEmbedded(m, { showConfidence = false, showETA = false })
    equal(e.confidenceText, nil); equal(e.etaText, nil); equal(e.paceText, "RITMO +1")
    -- Missing confidence / ETA (unconfident engine): pace alone.
    e = TP.BuildEmbedded(nalorakkModel(675, 329, 0, pred("+1", nil, false, 1790)), {})
    equal(e.confidenceText, nil); equal(e.etaText, nil)
    -- No deaths / no published time lost: no placeholder.
    equal(TP.BuildEmbedded(nalorakkModel(675, 329, 0, nil), {}).penaltyText, nil)
    local d = nalorakk(675, 329, 4); d.deathTimeLost = 0
    equal(TP.BuildEmbedded(TP.Build({ status = "RUNNING", state = d, elapsed = 675, constants = RATIOS }), {}).penaltyText, nil)
    -- Toggles.
    e = TP.BuildEmbedded(m, { showUpgradeTimes = false, showPrediction = false, showForcesCount = false, showDeaths = false })
    equal(e.threshold, nil); equal(e.paceText, nil); equal(e.forcesPrimary, nil); equal(e.forcesSecondary, "faltan 400")
    equal(e.penaltyText, nil)
end)

test("embedded model: pending, completing, overtime, complete forces and non-run modes", function()
    for _, mode in ipairs({ "HIDDEN", "PREVIEW", "SUMMARY" }) do
        equal(TP.BuildEmbedded({ mode = mode }).active, false, mode)
    end
    equal(TP.BuildEmbedded({ mode = "PREVIEW" }, { simulate = true }).active, true, "preview simulation")
    local s = reposo(nil, 136, 0); s.status = "PENDING"
    local e = TP.BuildEmbedded(build("PENDING", s, nil, engine("+1", 10, false)))
    equal(e.threshold, nil); equal(e.paceText, nil, "nothing invented before the timer"); equal(e.forcesPrimary, "136 / 608")
    e = TP.BuildEmbedded(build("RUNNING", reposo(60, 10, 0), 60, nil))
    equal(e.paceText, "RITMO --"); equal(e.confidenceText, nil)
    local c = reposo(1677, 600, 3, 14); c.finalElapsed = 1677
    e = TP.BuildEmbedded(build("COMPLETING", c, 1677, engine("+1", 70, true)))
    equal(e.threshold.text, "+1 5:03"); equal(e.paceValue, "+1")
    e = TP.BuildEmbedded(build("RUNNING", reposo(2045, 600, 3), 2045, engine("FUERA", 99, true)))
    equal(e.overtime, true); equal(e.threshold, nil); equal(e.paceValue, "OVERTIME")
    for _, full in ipairs({ { 608, 608 }, { 729, 729 } }) do
        local st = { timeLimit = 1920, forcesCurrent = full[1], forcesTotal = full[2], forcesPercent = 100 }
        e = TP.BuildEmbedded(TP.Build({ status = "RUNNING", state = st, elapsed = 900, constants = RATIOS }), {})
        equal(e.forcesPrimary, nil, "complete forces: Blizzard's check is enough"); equal(e.forcesSecondary, nil)
    end
end)

local function layoutOf(model, opts, space)
    return TP.LayoutEmbedded(TP.BuildEmbedded(model, opts), space, glyphs)
end

test("adaptive layout: real Nalorakk space (114 px) is wide enough for threshold, pace and split forces", function()
    local m = nalorakkModel(675, 329, 4, pred("+1", 30, false))
    local lay = layoutOf(m, { showConfidence = true }, { timerWidth = 114, forcesWidth = 191 })
    equal(lay.threshold.mode, "NEXT"); equal(lay.threshold.text, "+3 7:57")
    equal(lay.pace.mode, "STANDARD"); equal(lay.pace.text, "RITMO +1"); equal(lay.pace.confidence, "30%")
    equal(lay.forces.mode, "SPLIT"); equal(lay.forces.primary, "329 / 729"); equal(lay.forces.secondary, "faltan 400")
    -- Later in the same run: 565 / 729.
    lay = layoutOf(nalorakkModel(1300, 565, 5, pred("+1", 40, false)), {}, { timerWidth = 114, forcesWidth = 191 })
    equal(lay.threshold.text, "+2 3:56"); equal(lay.forces.primary, "565 / 729"); equal(lay.forces.secondary, "faltan 164")
end)

test("adaptive layout: sacrifice order ETA -> confidence -> pace, never the threshold first", function()
    local m = nalorakkModel(675, 329, 0, pred("+1", 30, true, 1790))
    local opts = { showConfidence = true, showETA = true }
    -- "RITMO +1"=48, gap 6, "30%"=18, gap 6, "~29:50"=36
    equal(layoutOf(m, opts, { timerWidth = 114 }).pace.mode, "WIDE")
    local lay = layoutOf(m, opts, { timerWidth = 113 })
    equal(lay.pace.mode, "STANDARD"); equal(lay.pace.eta, nil, "ETA goes first"); equal(lay.pace.confidence, "30%")
    lay = layoutOf(m, opts, { timerWidth = 71 })
    equal(lay.pace.mode, "COMPACT"); equal(lay.pace.confidence, nil, "then confidence"); equal(lay.threshold.mode, "NEXT")
    lay = layoutOf(m, opts, { timerWidth = 47 })
    equal(lay.pace.mode, "TOO_NARROW"); equal(lay.threshold.mode, "NEXT", "threshold survives the pace")
    lay = layoutOf(m, opts, { timerWidth = 41 })
    equal(lay.threshold.mode, "TOO_NARROW"); equal(lay.pace.mode, "NONE", "no pace where the threshold did not fit")
    -- Confidence off but ETA on: ETA is the only secondary.
    lay = layoutOf(nalorakkModel(675, 329, 0, pred("+1", 30, true, 1790), { showConfidence = false, showETA = true }),
        { showConfidence = false }, { timerWidth = 90 })
    equal(lay.pace.mode, "STANDARD"); equal(lay.pace.eta, "~29:50"); equal(lay.pace.confidence, nil)
    -- Unknown width: everything the options allow.
    equal(layoutOf(m, opts, {}).pace.mode, "WIDE")
    -- Deterministic.
    for _ = 1, 3 do equal(layoutOf(m, opts, { timerWidth = 71 }).pace.mode, "COMPACT") end
end)

test("adaptive layout: forces split -> count -> compact count, large numbers never overflow", function()
    local function forcesLayout(cur, total, width, opts)
        local st = { timeLimit = 1920, forcesCurrent = cur, forcesTotal = total, forcesPercent = cur / total * 100 }
        return layoutOf(TP.Build({ status = "RUNNING", state = st, elapsed = 600, constants = RATIOS }), opts or {},
            { timerWidth = 114, forcesWidth = width }).forces
    end
    local fo = forcesLayout(1234, 1450, 191)
    equal(fo.mode, "SPLIT"); equal(fo.primary, "1,234 / 1,450"); equal(fo.secondary, "faltan 216")
    fo = forcesLayout(1234, 1450, 140)                         -- 78 + 12 + 60 = 150 > 140
    equal(fo.mode, "PRIMARY"); equal(fo.primary, "1,234 / 1,450"); equal(fo.secondary, nil, "remaining goes before the count")
    fo = forcesLayout(1234, 1450, 70)
    equal(fo.mode, "PRIMARY_COMPACT"); equal(fo.primary, "1,234/1,450")
    fo = forcesLayout(1234, 1450, 50)
    equal(fo.mode, "TOO_NARROW"); equal(fo.primary, nil)
    for _, width in ipairs({ 30, 60, 90, 120, 150, 191 }) do
        local f2 = forcesLayout(1234, 1450, width)
        local used = (f2.primary and glyphs(f2.primary) or 0) + (f2.secondary and (TP.SPLIT_GAP + glyphs(f2.secondary)) or 0)
        truthy(used <= width, "forces fit in " .. width .. " px")
    end
    fo = forcesLayout(87, 100, 191, { showForcesCount = false })
    equal(fo.mode, "SECONDARY"); equal(fo.secondary, "faltan 13")
    -- No bar (Blizzard freed it): nothing.
    equal(layoutOf(nalorakkModel(675, 329), {}, { timerWidth = 114 }).forces.mode, "NONE")
end)

test("adaptive layout: localized strings are measured, not assumed", function()
    local original = TP.TEXT.REMAINING
    TP.TEXT.REMAINING = "restantes por matar: %s"
    local ok, err = pcall(function()
        local st = { timeLimit = 1920, forcesCurrent = 329, forcesTotal = 729, forcesPercent = 329 / 729 * 100 }
        local fo = layoutOf(TP.Build({ status = "RUNNING", state = st, elapsed = 675, constants = RATIOS }), {},
            { timerWidth = 114, forcesWidth = 191 }).forces
        equal(fo.mode, "PRIMARY", "longer translation no longer fits beside the count")
    end)
    TP.TEXT.REMAINING = original
    if not ok then error(err, 0) end
end)

test("Angry Keystones: threshold deferred to it, pace kept, overtime shows no threshold", function()
    local m = nalorakkModel(675, 329, 0, pred("+1", 30, false))
    local lay = layoutOf(m, {}, { timerWidth = 80, deferThreshold = true })
    equal(lay.threshold.mode, "DEFERRED"); equal(lay.threshold.text, nil); equal(lay.pace.mode, "STANDARD")
    lay = layoutOf(m, {}, { timerWidth = 114, deferThreshold = false })
    equal(lay.threshold.mode, "NEXT")
    lay = layoutOf(nalorakkModel(1950, 729, 0, pred("FUERA", 99, true)), {}, { timerWidth = 114 })
    equal(lay.threshold.mode, "OVERTIME"); equal(lay.threshold.text, nil)
    equal(layoutOf(m, { showUpgradeTimes = false }, { timerWidth = 114 }).threshold.mode, "DISABLED")
end)

-- ---------------------------------------------------------------------------
-- 1.1.0-dev.9 -- pulido final sobre la run real de regresion
-- Guarida de Nalorakk (mapID 586) +4, limite 32:00, +3 a las 19:12.
-- Observado en vivo: 502 / 729 (68 %, faltan 227), umbral "+3 5:18",
-- "RITMO +2" con 50 % de confianza (bracket provisional).
-- ---------------------------------------------------------------------------

local function liveRun(elapsed, forces, deaths, prediction)
    local state = { status = "RUNNING", mapID = 586, mapName = "Guarida de Nalorakk", keystoneLevel = 4,
                    timeLimit = 1920, forcesCurrent = forces, forcesTotal = 729,
                    forcesPercent = forces / 729 * 100, forcesRemaining = 729 - forces,
                    bossesCompleted = 2, bossesTotal = 3, deaths = deaths or 0,
                    deathTimeLost = (deaths or 0) * 5, warnings = {}, bosses = {} }
    return TP.Build({ enabled = true, status = "RUNNING", state = state, elapsed = elapsed,
                      prediction = prediction, constants = RATIOS,
                      settings = { showConfidence = true, showETA = true } })
end

test("dev.9 live fixture: the +4 Nalorakk run reads exactly as it did in game", function()
    local m = liveRun(834, 502, 0, pred("+2", 50, false))
    local e = TP.BuildEmbedded(m, { showConfidence = true, showETA = true })
    equal(e.threshold.text, "+3 5:18", "the threshold seen on screen")
    equal(e.paceText, "RITMO +2"); equal(e.confidenceText, "50%")
    equal(e.provisional, true, "50 % is not a confident bracket")
    equal(e.forcesPrimary, "502 / 729"); equal(e.forcesSecondary, "faltan 227")
    equal(m.forces.remaining, 227); equal(math.floor(m.forces.percent), 68)
    -- The forces bar percentage belongs to Blizzard: Mitzu never repeats it.
    equal(e.forcesPercent, nil)
    for k, v in pairs(e) do
        if type(v) == "string" then
            truthy(not v:find("%%") or k == "confidenceText", "only the confidence carries a % : " .. k .. "=" .. v)
        end
    end
    local lay = TP.LayoutEmbedded(e, { timerWidth = 114, forcesWidth = 191 }, glyphs)
    equal(lay.threshold.mode, "NEXT"); equal(lay.pace.mode, "STANDARD"); equal(lay.pace.confidence, "50%")
    equal(lay.forces.mode, "SPLIT"); equal(lay.forces.primary, "502 / 729"); equal(lay.forces.secondary, "faltan 227")
end)

test("dev.9 pace hierarchy: RITMO survives, the confidence is what gives way", function()
    local m = liveRun(834, 502, 0, pred("+2", 50, true, 1800))
    local opts = { showConfidence = true, showETA = true }
    -- Wide enough: pace + confidence + ETA.
    equal(TP.LayoutEmbedded(TP.BuildEmbedded(m, opts), { timerWidth = 200 }, glyphs).pace.mode, "WIDE")
    -- Narrow: the secondary parts give way before the pace, the pace before the threshold.
    local narrow = TP.LayoutEmbedded(TP.BuildEmbedded(m, opts), { timerWidth = 60 }, glyphs)
    equal(narrow.pace.mode, "COMPACT"); equal(narrow.pace.text, "RITMO +2")
    equal(narrow.pace.confidence, nil, "the confidence gives way before the pace")
    equal(narrow.threshold.mode, "NEXT", "and the threshold before both")
    -- The confidence is never promoted over the pace value.
    local off = TP.BuildEmbedded(liveRun(834, 502, 0, pred("+2", 50, false)), { showConfidence = false })
    equal(off.paceText, "RITMO +2"); equal(off.confidenceText, nil)
    -- No engine bracket: no placeholder confidence either.
    local blind = TP.BuildEmbedded(liveRun(834, 502, 0, nil), opts)
    equal(blind.paceText, "RITMO --"); equal(blind.confidenceText, nil); equal(blind.etaText, nil)
end)

test("dev.9 forces: two columns that fit the bar, hidden at 100 %, never a duplicated %", function()
    local function row(cur, total, width)
        local st = { timeLimit = 1920, forcesCurrent = cur, forcesTotal = total, forcesPercent = cur / total * 100 }
        local model = TP.Build({ status = "RUNNING", state = st, elapsed = 834, constants = RATIOS })
        return TP.LayoutEmbedded(TP.BuildEmbedded(model, {}), { timerWidth = 114, forcesWidth = width }, glyphs)
    end
    local fo = row(502, 729, 191).forces
    equal(fo.mode, "SPLIT"); equal(fo.primary, "502 / 729"); equal(fo.secondary, "faltan 227")
    truthy(glyphs(fo.primary) + TP.SPLIT_GAP + glyphs(fo.secondary) <= 191, "never overflows the bar")
    -- 100 %: Blizzard's own bar already says it; Mitzu adds nothing.
    fo = row(729, 729, 191).forces
    equal(fo.mode, "NONE"); equal(fo.primary, nil); equal(fo.secondary, nil)
    -- Long counts keep the split while it fits, and drop "faltan" first.
    fo = row(1234, 1450, 191).forces
    equal(fo.mode, "SPLIT"); equal(fo.primary, "1,234 / 1,450"); equal(fo.secondary, "faltan 216")
    fo = row(1234, 1450, 140).forces
    equal(fo.mode, "PRIMARY"); equal(fo.secondary, nil, "clarity of the count comes first")
    for _, case in ipairs({ { "SPLIT", 191 }, { "PRIMARY", 140 }, { "PRIMARY_COMPACT", 70 } }) do
        local f2 = row(1234, 1450, case[2]).forces
        equal(f2.mode, case[1])
        truthy(not (f2.primary or ""):find("%%"), "no percentage in " .. case[1])
        truthy(not (f2.primary or ""):find("-", 1, true), "never a negative count in " .. case[1])
    end
end)

test("dev.9 death penalty: only the published time lost, never -0:00, never a second count", function()
    local function penalty(deaths, timeLost)
        local st = { timeLimit = 1920, forcesCurrent = 502, forcesTotal = 729, forcesPercent = 68,
                     deaths = deaths, deathTimeLost = timeLost }
        local model = TP.Build({ status = "RUNNING", state = st, elapsed = 834, constants = RATIOS })
        return TP.BuildEmbedded(model, {}).penaltyText
    end
    equal(penalty(0, 0), nil, "no deaths, no penalty")
    equal(penalty(1, 5), "-0:05"); equal(penalty(3, 15), "-0:15"); equal(penalty(12, 60), "-1:00")
    equal(penalty(3, nil), nil, "deaths without a published time lost show nothing")
    equal(penalty(3, 0), nil); equal(penalty(3, -5), nil)
    equal(penalty(3, 0.4), nil, "a sub-second penalty is never painted as -0:00")
    equal(penalty(nil, 15), nil, "no death count, no penalty")
    -- The count itself stays Blizzard's: the embedded model never carries it.
    local st = { timeLimit = 1920, deaths = 3, deathTimeLost = 15 }
    local e = TP.BuildEmbedded(TP.Build({ status = "RUNNING", state = st, elapsed = 834, constants = RATIOS }), {})
    for k, v in pairs(e) do
        if type(v) == "string" then
            truthy(not v:find(TP.TEXT.DEATHS, 1, true), "no death label in " .. k)
            truthy(v ~= "3", "no bare death count in " .. k)
        end
    end
end)

test("dev.9 Angry Keystones: the threshold is deferred, the pace and the forces are not", function()
    local m = liveRun(834, 502, 0, pred("+2", 50, false))
    local e = TP.BuildEmbedded(m, {})
    local withAK = TP.LayoutEmbedded(e, { timerWidth = 70, forcesWidth = 191, deferThreshold = true }, glyphs)
    equal(withAK.threshold.mode, "DEFERRED"); equal(withAK.threshold.text, nil); equal(withAK.threshold.upgrade, nil)
    truthy(withAK.pace.text, "the pace is Mitzu's, Angry Keystones does not show it")
    equal(withAK.forces.mode, "SPLIT", "and the forces columns stay: Angry only owns the %")
    truthy(not (withAK.forces.primary or ""):find("%%"), "no second percentage over Angry's label")
    local without = TP.LayoutEmbedded(e, { timerWidth = 114, forcesWidth = 191, deferThreshold = false }, glyphs)
    equal(without.threshold.mode, "NEXT"); equal(without.threshold.text, "+3 5:18")
    -- The model itself is identical: only the layout decision changes.
    equal(TP.BuildEmbedded(m, {}).threshold.text, "+3 5:18")
end)

if #failures > 0 then error(string.format("TrackerPresenter: %d failures\n%s", #failures, table.concat(failures, "\n")), 0) end
return { tests = tests, assertions = assertions }
