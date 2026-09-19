-- ===========================================================================
-- MitzuMPlus - Tracker/TrackerPresenter  (1.1.0-dev.6, Mitzu Tracker V1)
--
--     TrackerAdapter -> TrackerState -> TrackerPresenter -> TrackerView
--                       PredictionEngine ----^
--
-- Convierte estado tecnico en un MODELO VISUAL listo para pintar. Es una
-- funcion pura: recibe tablas, devuelve una tabla. No crea frames, no lee
-- APIs de Blizzard, no llama a TrackerState ni a PredictionEngine (eso lo hace
-- MitzuTracker, que le pasa las entradas). Por eso se prueba sin cliente.
--
-- REGLAS
--   * "No lo se" es nil / "--". Nunca un 0 ni un +1 tranquilizador.
--   * La prediccion NO se calcula aqui: se traduce el bracket del motor con
--     una lista blanca (+3 / +2 / +1 / OVERTIME / NONE).
--   * Dos conceptos separados que la vista ensena a la vez sin contradecirse:
--       timer.bracket     -> lo que el RELOJ aun permite (umbral matematico)
--       prediction.code   -> lo que el RITMO proyecta (PredictionEngine)
--   * Lo inferido del evento oficial de final se marca (bosses.inferred).
--
-- ENTRADA  (todas opcionales)
--   enabled, preview, summary     booleanos del controlador
--   status                        estado de TrackerState
--   state                         TrackerState:GetSnapshot() (solo lectura)
--   elapsed                       TrackerState:GetElapsed() (interpolado)
--   prediction                    PredictionEngine:GetSnapshot(run)
--   final                         TP.FinalFromRun(run, ultimaPrediccion)
--   settings                      { showConfidence, showETA }
--   constants                     { KEY_UPGRADE_PLUS2_RATIO, ... }
-- ===========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local TP = {}
MitzuMPlus.TrackerPresenter = TP

TP.VERSION = 1

TP.MODES = { HIDDEN = "HIDDEN", PREVIEW = "PREVIEW", PENDING = "PENDING", RUNNING = "RUNNING",
             COMPLETING = "COMPLETING", SUMMARY = "SUMMARY" }

-- Traduccion del bracket de PredictionEngine. Lista blanca: cualquier otra
-- cosa (nil, secreto, texto raro) es NONE, nunca un valor pintado a ciegas.
TP.RESULT_CODE = { ["+3"] = "+3", ["+2"] = "+2", ["+1"] = "+1", ["FUERA"] = "OVERTIME" }
TP.NONE = "NONE"

-- Textos visibles. NINGUNO se escribe aqui en un idioma concreto: cada uno es
-- una clave de AceLocale que se resuelve al leerse (MitzuMPlus.L), asi que el
-- tracker habla el idioma del cliente sin que este fichero sepa cual es.
-- Ingles por defecto; espanol solo en clientes espanoles (ver Bootstrap.lua).
TP.TEXT_KEYS = {
    DUNGEON      = "TRACKER_DUNGEON",
    PENDING      = "TRACKER_PENDING",
    FORCES       = "TRACKER_FORCES",
    REMAINING    = "TRACKER_REMAINING",
    FORCES_DONE  = "TRACKER_FORCES_DONE",
    BOSSES       = "TRACKER_BOSSES",
    DEATHS       = "TRACKER_DEATHS",
    PACE         = "TRACKER_PACE",
    RESULT       = "TRACKER_RESULT",
    ETA          = "TRACKER_ETA",
    KEY_COMPLETE = "TRACKER_KEY_COMPLETE",
    KEY_OVERTIME = "TRACKER_KEY_OVERTIME",
    KEY_DONE     = "TRACKER_KEY_DONE",
    OFFICIAL     = "TRACKER_OFFICIAL",
    LAST_PACE    = "TRACKER_LAST_PACE",
    PREVIEW      = "TRACKER_PREVIEW",
    LEVEL        = "TRACKER_LEVEL",
    BOSS_N       = "TRACKER_BOSS_N",
    SUMMARY_PB   = "TRACKER_SUMMARY_PB",
    SUMMARY_LEVEL= "TRACKER_SUMMARY_BEST_LEVEL",
    SUMMARY_SCORE= "TRACKER_SUMMARY_SCORE_GAIN",
}

-- Los que no llevan palabras son universales: un reloj y un porcentaje se leen
-- igual en cualquier cliente, asi que no pasan por el traductor.
TP.TEXT = setmetatable({
    NO_VALUE   = "--",
    NO_TIMER   = "--:--",
    CONFIDENCE = "%d%%",
    OF_LIMIT   = "%s / %s",
}, {
    __index = function(_, name)
        local key = TP.TEXT_KEYS[name]
        if not key then return nil end
        local L = MitzuMPlus.L
        -- Sin AceLocale (modulo cargado suelto en un banco) devuelve la clave:
        -- nunca un idioma escrito a mano, y el fallo se ve en el acto.
        return L and L[key] or key
    end,
})

-- ---------------------------------------------------------------------------
-- FORMATO
-- ---------------------------------------------------------------------------

local floor, abs = math.floor, math.abs

local function num(v)
    local S = MitzuMPlus.QASafe
    if S and S.Number then return S.Number(v) end
    return type(v) == "number" and v or nil
end

-- 83 -> "1:23", 3725 -> "1:02:05". Negativo con signo.
function TP.FormatClock(sec)
    sec = num(sec)
    if not sec then return nil end
    local neg = sec < 0
    sec = floor(abs(sec))
    local h, m, s = floor(sec / 3600), floor(sec / 60) % 60, sec % 60
    local body = h > 0 and string.format("%d:%02d:%02d", h, m, s) or string.format("%d:%02d", floor(sec / 60), s)
    return (neg and "-" or "") .. body
end

-- 1234 -> "1,234". Solo enteros; nunca notacion cientifica.
function TP.FormatCount(n)
    n = num(n)
    if not n then return nil end
    local s = tostring(floor(abs(n) + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then out = out:sub(2) end
    return (n < 0 and "-" or "") .. out
end

function TP.FormatPercent(p)
    p = num(p)
    if not p then return nil end
    return string.format("%.2f%%", p)
end

local function clamp01(v)
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end

-- ---------------------------------------------------------------------------
-- PIEZAS
-- ---------------------------------------------------------------------------

-- Umbrales +3/+2/+1. Primero los del motor (los mismos con los que predice);
-- si no hay motor, las fracciones centralizadas en Constants. Sin limite o sin
-- fracciones no hay umbrales: no se inventan.
function TP.Thresholds(limit, prediction, constants)
    limit = num(limit)
    if not limit or limit <= 0 then return nil end
    local p = type(prediction) == "table" and prediction or {}
    local c = type(constants) == "table" and constants or {}
    local p2 = num(p.plus2Time)
    local p3 = num(p.plus3Time)
    if not (p2 and p2 > 0) and num(c.KEY_UPGRADE_PLUS2_RATIO) then p2 = floor(limit * c.KEY_UPGRADE_PLUS2_RATIO) end
    if not (p3 and p3 > 0) and num(c.KEY_UPGRADE_PLUS3_RATIO) then p3 = floor(limit * c.KEY_UPGRADE_PLUS3_RATIO) end
    if not (p2 and p3) then return nil end
    return { ["+3"] = p3, ["+2"] = p2, ["+1"] = limit }
end

local ORDER = { "+3", "+2", "+1" }

-- Lo que el reloj todavia permite. Independiente de la prediccion.
-- `live` es el tiempo interpolado (TrackerState:GetElapsed); sin el se usa
-- state.elapsed. Congelado (final de llave) manda finalElapsed.
function TP.BuildTimer(state, prediction, constants, frozen, live)
    local s = type(state) == "table" and state or {}
    local elapsed = frozen and num(s.finalElapsed) or nil
    if not elapsed then elapsed = num(live) or num(s.elapsed) end
    local limit = num(s.timeLimit)
    local t = { elapsed = elapsed, limit = limit, stale = s.timerStale == true, frozen = frozen == true }

    if elapsed and limit and limit > 0 then
        t.remaining = limit - elapsed
        t.overtime = t.remaining < 0
        -- Fuera de tiempo: "-1:23" (nunca "+1:23", que se confundiria con un +1).
        t.text = TP.FormatClock(t.remaining)
        t.subText = string.format(TP.TEXT.OF_LIMIT, TP.FormatClock(elapsed), TP.FormatClock(limit))
        t.fraction = clamp01(elapsed / limit)
    elseif elapsed then
        t.text = TP.FormatClock(elapsed)
        t.fraction = nil
    else
        t.text = TP.TEXT.NO_TIMER
        t.subText = limit and TP.FormatClock(limit) or nil
    end

    local th = TP.Thresholds(limit, prediction, constants)
    t.segments = {}
    t.bracket = nil
    if th then
        for i, code in ipairs(ORDER) do
            local at = th[code]
            local seg = { code = code, at = at, fraction = clamp01(at / limit) }
            if elapsed then
                seg.left = at - elapsed
                seg.lost = seg.left < 0
                seg.text = seg.lost and code or (code .. " " .. TP.FormatClock(seg.left))
                if not seg.lost and not t.bracket then t.bracket = code; seg.current = true end
            else
                seg.text = code .. " " .. TP.FormatClock(at)
            end
            t.segments[i] = seg
        end
        if elapsed and not t.bracket then t.bracket = "OVERTIME" end
    end
    return t
end

-- Solo lo que la vista ensena del motor. Sin bracket reconocible no hay
-- prediccion: ni confianza ni final estimado.
function TP.BuildPrediction(prediction, settings)
    local st = type(settings) == "table" and settings or {}
    local out = { code = TP.NONE, text = TP.TEXT.NO_VALUE, label = TP.TEXT.PACE }
    if type(prediction) ~= "table" then return out end
    local result = prediction.result
    local code = type(result) == "string" and TP.RESULT_CODE[result] or nil
    if not code then return out end
    out.code, out.text = code, code
    -- Por debajo de la confianza del motor el bracket es provisional.
    out.provisional = prediction.resultConfident ~= true
    local conf = num(prediction.confidence)
    if conf and st.showConfidence ~= false then
        out.confidence = floor(conf + 0.5)
        out.confidenceText = string.format(TP.TEXT.CONFIDENCE, out.confidence)
    end
    local projected = num(prediction.projectedTime)
    local eff, limit = num(prediction.effectiveElapsed), num(prediction.timeLimit)
    if st.showETA ~= false and prediction.resultConfident == true and projected and eff and limit
       and limit > 0 and eff < limit then
        out.eta = projected
        out.etaText = string.format(TP.TEXT.ETA, TP.FormatClock(projected))
    end
    return out
end

function TP.BuildForces(state, terminal)
    local s = type(state) == "table" and state or {}
    local cur, total, pct = num(s.forcesCurrent), num(s.forcesTotal), num(s.forcesPercent)
    local f = { current = cur, total = total, percent = pct, stale = s.forcesStale == true }
    if terminal and s.forcesCompletionSource == "INFERRED_FROM_COMPLETION_EVENT" and num(s.forcesPercentFinal) then
        -- El evento oficial implica el 100 %: se ensena, marcado como inferido.
        pct, f.inferred = s.forcesPercentFinal, true
        f.percent = pct
        if total then cur = total end
    end
    if not pct then
        f.available = false
        f.percentText, f.countText, f.fraction = TP.TEXT.NO_VALUE, nil, 0
        return f
    end
    f.available = true
    f.fraction = clamp01(pct / 100)
    f.complete = pct >= 100 - 1e-6
    f.percentText = TP.FormatPercent(pct)
    if cur and total then
        f.countText = TP.FormatCount(cur) .. " / " .. TP.FormatCount(total)
        f.remaining = math.max(0, total - cur)
    end
    if f.complete then
        f.remaining = 0
        f.remainingText = TP.TEXT.FORCES_DONE
    elseif f.remaining then
        f.remainingText = string.format(TP.TEXT.REMAINING, TP.FormatCount(f.remaining))
    end
    return f
end

function TP.BuildBosses(state, terminal)
    local s = type(state) == "table" and state or {}
    local done, total = num(s.bossesCompleted), num(s.bossesTotal)
    local b = { completed = done, total = total, stale = s.bossesStale == true, label = TP.TEXT.BOSSES, list = {} }
    if terminal and s.bossCountSource == "INFERRED_FROM_COMPLETION_EVENT" and num(s.bossesCompletedFinal) then
        done, b.inferred = s.bossesCompletedFinal, true
        b.completed = done
    end
    if not total or total <= 0 then
        b.available = false
        b.text = TP.TEXT.NO_VALUE
        return b
    end
    b.available = true
    done = done or 0
    b.complete = done >= total
    b.text = string.format("%d/%d", done, total)
    -- Nombres solo si Blizzard los dio; nunca una lista inventada.
    for i, boss in ipairs(type(s.bosses) == "table" and s.bosses or {}) do
        if type(boss) == "table" then
            b.list[#b.list + 1] = { name = type(boss.name) == "string" and boss.name or nil,
                                    completed = boss.completed == true or (b.inferred and true) or false,
                                    index = boss.index or i }
        end
    end
    return b
end

function TP.BuildDeaths(state)
    local s = type(state) == "table" and state or {}
    local count, lost = num(s.deaths), num(s.deathTimeLost)
    local d = { count = count, timeLost = lost, label = TP.TEXT.DEATHS }
    d.text = count and tostring(floor(count)) or TP.TEXT.NO_VALUE
    -- La penalizacion solo si Blizzard la publica (C_ChallengeMode.GetDeathCount
    -- via adaptador). No se calcula con una regla fija.
    if count and count > 0 and lost and lost > 0 then
        d.penaltyText = "+" .. TP.FormatClock(lost)
    end
    return d
end

-- Resultado de una llave terminada. Oficial solo si Core lo leyo de la API de
-- finalizacion (run.completionInfoSource). Sin esa marca, inTime=false y
-- keystoneUpgradeLevels=0 son valores por defecto de Core, no un dato.
function TP.FinalFromRun(run, lastCode)
    if type(run) ~= "table" then return nil end
    local levels = num(run.keystoneUpgradeLevels) or 0
    local t = num(run.completionTime)
    if t and t <= 0 then t = nil end
    local extra = {
        achievements = type(run._summaryAchievements) == "table" and run._summaryAchievements or nil,
        scoreGain = num(run._summaryScoreGain),
    }
    if type(run.completionInfoSource) == "string" and (run.inTime == true or run.inTime == false) then
        local code = "OVERTIME"
        if run.inTime == true then
            code = levels >= 3 and "+3" or (levels == 2 and "+2" or "+1")
        end
        extra.code, extra.source, extra.time = code, "OFFICIAL", t
        return extra
    end
    extra.code, extra.source, extra.time = lastCode, "LAST_PREDICTION", t
    return extra
end

-- ---------------------------------------------------------------------------
-- MODELO
-- ---------------------------------------------------------------------------

function TP.ModeFor(input)
    local i = type(input) == "table" and input or {}
    if i.preview == true then return TP.MODES.PREVIEW end
    if i.enabled == false then return TP.MODES.HIDDEN end
    local st = i.status
    if st == "PENDING" then return TP.MODES.PENDING end
    if st == "RUNNING" then return TP.MODES.RUNNING end
    if st == "COMPLETING" then return TP.MODES.COMPLETING end
    if st == "COMPLETED" and i.summary == true then return TP.MODES.SUMMARY end
    return TP.MODES.HIDDEN
end

function TP.Build(input)
    local i = type(input) == "table" and input or {}
    local mode = TP.ModeFor(i)
    local m = { mode = mode, preview = mode == TP.MODES.PREVIEW, version = TP.VERSION }
    if mode == TP.MODES.HIDDEN then
        m.prediction = { code = TP.NONE }
        return m
    end
    local s = type(i.state) == "table" and i.state or {}
    local constants = i.constants or MitzuMPlus.Constants
    local finished = mode == TP.MODES.COMPLETING or mode == TP.MODES.SUMMARY
    local terminal = finished and s.terminalStateConfirmed == true

    m.dungeonName = type(s.mapName) == "string" and s.mapName ~= "" and s.mapName or TP.TEXT.DUNGEON
    m.keyLevel = num(s.keystoneLevel)
    m.keyText = m.keyLevel and ("+" .. floor(m.keyLevel)) or nil

    m.timer = TP.BuildTimer(s, i.prediction, constants, finished, i.elapsed)
    m.forces = TP.BuildForces(s, terminal)
    m.bosses = TP.BuildBosses(s, terminal)
    m.deaths = TP.BuildDeaths(s)

    if mode == TP.MODES.PENDING then
        m.prediction = TP.BuildPrediction(nil, i.settings)
        m.timer.subText = m.timer.elapsed and m.timer.subText or TP.TEXT.PENDING
    elseif mode == TP.MODES.SUMMARY then
        local f = type(i.final) == "table" and i.final or {}
        local code = TP.RESULT_CODE[f.code] or (f.code == "OVERTIME" and "OVERTIME") or nil
        m.prediction = { code = code or TP.NONE, text = code or TP.TEXT.NO_VALUE, label = TP.TEXT.RESULT,
                         sourceText = f.source == "OFFICIAL" and TP.TEXT.OFFICIAL or (code and TP.TEXT.LAST_PACE or nil) }
        local a = type(f.achievements) == "table" and f.achievements or {}
        local noteText
        if a.newBestLevel then
            noteText = TP.TEXT.SUMMARY_LEVEL
        elseif a.personalBest then
            noteText = TP.TEXT.SUMMARY_PB
        end
        local scoreGain = num(f.scoreGain)
        m.summary = {
            title = code == "OVERTIME" and TP.TEXT.KEY_OVERTIME or (code and TP.TEXT.KEY_COMPLETE or TP.TEXT.KEY_DONE),
            official = f.source == "OFFICIAL",
            timeText = m.timer.subText,
            noteText = noteText,
            scoreText = scoreGain and scoreGain > 0 and string.format(TP.TEXT.SUMMARY_SCORE, floor(scoreGain + 0.5)) or nil,
        }
    else
        m.prediction = TP.BuildPrediction(i.prediction, i.settings)
    end
    return m
end

-- ---------------------------------------------------------------------------
-- MODELO INTEGRADO (dev.7 arquitectura, dev.8 densidad y jerarquia)
--
-- Lo que el BlizzardTrackerEnhancer anade al bloque M+ nativo. Blizzard ya
-- pinta nombre, nivel, temporizador, jefes, barra de fuerzas (con su %) y
-- contador de muertes: aqui solo va lo que Blizzard NO ensena, y poco.
--
-- Jerarquia (de mas a menos peso):
--   1 TimeLeft (Blizzard)  2 proximo umbral  3 RITMO  4 fuerzas exactas
--   5 fuerzas restantes    6 penalizacion    7 confianza  8 ETA
-- Orden de sacrificio cuando falta espacio: ETA, confianza, restantes,
-- recuento, ritmo. El umbral nunca cae antes que un dato secundario.
-- ---------------------------------------------------------------------------

TP.EMBEDDED_MODES = { PENDING = true, RUNNING = true, COMPLETING = true }
TP.SEPARATOR = " · "
TP.GAP = 6             -- px entre partes de una misma linea
TP.SPLIT_GAP = 12      -- px minimos entre recuento y restantes
-- Penalizacion de muertes: por debajo de un segundo no hay nada que ensenar.
-- Sin este minimo un tiempo perdido de 0,4 s se pintaria como "-0:00".
TP.MIN_PENALTY_SECONDS = 1

-- Primer candidato cuyo ancho medido cabe. Determinista. Sin ancho conocido
-- se elige el mas corto. Si ni el mas corto cabe, nada ("").
function TP.FitText(candidates, maxWidth, measure)
    local list = type(candidates) == "table" and candidates or {}
    if #list == 0 then return "", 0 end
    if type(maxWidth) ~= "number" or type(measure) ~= "function" then return list[#list], #list end
    for i, text in ipairs(list) do
        if measure(text) <= maxWidth then return text, i end
    end
    return "", 0
end

-- El umbral que el reloj aun permite y esta mas cerca de perderse, con el
-- margen que queda. Sale de los umbrales centralizados (TP.Thresholds via
-- BuildTimer); aqui no hay matematica nueva. nil si no hay reloj, no hay
-- umbrales o ya no queda ninguno (fuera de tiempo).
--   { upgrade = "+3", time = 385 }
function TP.GetNextRelevantUpgradeThreshold(model)
    local m = type(model) == "table" and model or {}
    local t = type(m.timer) == "table" and m.timer or m
    if type(t.segments) ~= "table" or not t.elapsed then return nil end
    for _, seg in ipairs(t.segments) do
        if seg.left and not seg.lost then return { upgrade = seg.code, time = seg.left } end
    end
    return nil
end

function TP.BuildEmbedded(model, opts)
    local m = type(model) == "table" and model or {}
    local o = type(opts) == "table" and opts or {}
    -- `simulate`: la vista previa flotante reproduce el mismo contenido.
    local e = { mode = m.mode, active = TP.EMBEDDED_MODES[m.mode] == true or (o.simulate == true and m.mode == "PREVIEW") }
    if not e.active then return e end
    local running = m.mode ~= "PENDING"

    local t = m.timer or {}
    e.overtime = t.overtime == true
    e.thresholdEnabled = o.showUpgradeTimes ~= false
    if e.thresholdEnabled and running then
        local next = TP.GetNextRelevantUpgradeThreshold(m)
        if next then
            e.threshold = { upgrade = next.upgrade, time = next.time,
                            timeText = TP.FormatClock(next.time) }
            e.threshold.text = next.upgrade .. " " .. e.threshold.timeText
        end
    end

    local p = m.prediction or {}
    e.paceCode, e.provisional = p.code or TP.NONE, p.provisional == true
    if o.showPrediction ~= false and running then
        -- experimental.12: no se pinta "Ritmo --". Sin una prediccion real,
        -- la fila permanece vacia; un placeholder solo anade ruido y hace que
        -- el bloque parezca desalineado al empezar una llave.
        local code = (p.code and p.code ~= TP.NONE) and p.code or nil
        if code then
            e.paceLabel, e.paceValue = TP.TEXT.PACE, code
            e.paceText = TP.TEXT.PACE .. " " .. code
            -- Secundarios: solo con bracket del motor y con su opcion activa.
            if o.showConfidence ~= false and p.confidence then e.confidenceText = string.format(TP.TEXT.CONFIDENCE, p.confidence) end
            if o.showETA ~= false and p.eta then e.etaText = "~" .. TP.FormatClock(p.eta) end
        end
    end

    -- Fuerzas: la barra y su % son de Blizzard (o de Angry Keystones). Mitzu
    -- anade el recuento exacto y lo que falta; nunca vuelve a escribir el %.
    local f = m.forces or {}
    e.forcesComplete = f.available == true and f.complete == true
    if f.available and not f.complete then
        if o.showForcesCount ~= false and f.current and f.total then
            e.forcesPrimary = f.countText
            e.forcesPrimaryCompact = TP.FormatCount(f.current) .. "/" .. TP.FormatCount(f.total)
        end
        if o.showForcesRemaining ~= false then e.forcesSecondary = f.remainingText end
    end

    -- Muertes: Blizzard ya ensena icono y numero; Mitzu solo el tiempo perdido
    -- publicado (el reloj de Blizzard es tiempo restante: "-").
    local d = m.deaths or {}
    if o.showDeaths ~= false and d.count and d.count > 0
       and d.timeLost and d.timeLost >= TP.MIN_PENALTY_SECONDS then
        e.penaltyText = "-" .. TP.FormatClock(d.timeLost)
    end
    return e
end

-- Decide que cabe. Puro y determinista.
--   space.timerWidth   ancho a la derecha del temporizador de Blizzard
--   space.forcesWidth  ancho de la barra de fuerzas de Blizzard (nil = sin barra)
--   space.deferThreshold  otro addon (Angry Keystones) ya pinta el umbral ahi
--   measure(text, kind)   kind: "threshold" | "pace" | "secondary" | "forces"
function TP.LayoutEmbedded(emb, space, measure)
    local e = type(emb) == "table" and emb or {}
    local sp = type(space) == "table" and space or {}
    local w = function(text, kind) return text and measure(text, kind) or 0 end
    local out = { threshold = { mode = "NONE" }, pace = { mode = "NONE" }, forces = { mode = "NONE" } }
    -- experimental.12: el reloj y el ritmo ya no comparten un unico
    -- presupuesto horizontal. El umbral vive en su columna derecha fija y
    -- Ritmo dispone de la fila completa inferior. `timerWidth` se conserva
    -- como fallback para pruebas/vistas antiguas.
    local thresholdW = sp.thresholdWidth or sp.timerWidth
    local paceW = sp.paceWidth or sp.timerWidth

    -- 1. Umbral
    local th = out.threshold
    if not e.active then
        th.mode = "NONE"
    elseif not e.thresholdEnabled then
        th.mode = "DISABLED"
    elseif sp.deferThreshold then
        th.mode = "DEFERRED"
    elseif e.overtime then
        th.mode = "OVERTIME"
    elseif not e.threshold then
        th.mode = "NONE"
    elseif type(thresholdW) == "number" and w(e.threshold.text, "threshold") > thresholdW then
        th.mode = "TOO_NARROW"
    else
        th.mode, th.text, th.upgrade, th.timeText = "NEXT", e.threshold.text, e.threshold.upgrade, e.threshold.timeText
    end

    -- 2. Ritmo (+ confianza + ETA). Si el umbral no cupo, el ritmo tampoco se
    -- ensena: nunca un dato de menos prioridad donde falta el principal.
    local pc = out.pace
    if e.paceText and th.mode ~= "TOO_NARROW" then
        local base = w(e.paceText, "pace")
        local conf = e.confidenceText and (TP.GAP + w(e.confidenceText, "secondary")) or nil
        local eta = e.etaText and (TP.GAP + w(e.etaText, "secondary")) or nil
        local fits = function(x) return type(paceW) ~= "number" or x <= paceW end
        if conf and eta and fits(base + conf + eta) then
            pc.mode, pc.confidence, pc.eta = "WIDE", e.confidenceText, e.etaText
        elseif conf and fits(base + conf) then
            pc.mode, pc.confidence = "STANDARD", e.confidenceText
        elseif (not conf) and eta and fits(base + eta) then
            pc.mode, pc.eta = "STANDARD", e.etaText
        elseif fits(base) then
            pc.mode = "COMPACT"
        else
            pc.mode = "TOO_NARROW"
        end
        if pc.mode ~= "TOO_NARROW" then pc.text, pc.label, pc.value = e.paceText, e.paceLabel, e.paceValue end
    end

    -- 3. Fuerzas: "329 / 729      faltan 400" -> "329 / 729" -> "329/729".
    -- dev.11: los restantes se miden con `forcesSecondary`, su propia fuente
    -- legible, no con la de la confianza. Medir con una fuente mas pequena que
    -- la que se va a pintar hacia caber texto que luego se salia de la barra.
    -- El orden de sacrificio no cambia: el recuento principal NUNCA encoge para
    -- conservar los restantes.
    local fo = out.forces
    local fw = sp.forcesWidth
    if type(fw) == "number" and (e.forcesPrimary or e.forcesSecondary) then
        local p1, p2 = e.forcesPrimary, e.forcesSecondary
        if p1 and p2 and w(p1, "forces") + TP.SPLIT_GAP + w(p2, "forcesSecondary") <= fw then
            fo.mode, fo.primary, fo.secondary = "SPLIT", p1, p2
        elseif p1 and w(p1, "forces") <= fw then
            fo.mode, fo.primary = "PRIMARY", p1
        elseif p1 and e.forcesPrimaryCompact and w(e.forcesPrimaryCompact, "forces") <= fw then
            fo.mode, fo.primary = "PRIMARY_COMPACT", e.forcesPrimaryCompact
        elseif not p1 and p2 and w(p2, "forcesSecondary") <= fw then
            fo.mode, fo.secondary = "SECONDARY", p2
        else
            fo.mode = "TOO_NARROW"
        end
    end
    return out
end

-- Datos de VISTA PREVIA: realistas (Reposo de los Reyes +12 al 74 %), solo
-- visuales. No salen de ninguna autoridad ni se escriben en ninguna.
function TP.PreviewInput(settings)
    return {
        preview = true, enabled = true, status = "RUNNING", settings = settings,
        constants = { KEY_UPGRADE_PLUS2_RATIO = 0.8, KEY_UPGRADE_PLUS3_RATIO = 0.6 },
        state = {
            mapName = TP.TEXT.DUNGEON, keystoneLevel = 12, timeLimit = 1980, elapsed = 803,
            forcesCurrent = 449, forcesTotal = 608, forcesPercent = 449 / 608 * 100,
            bossesCompleted = 2, bossesTotal = 4, deaths = 3, deathTimeLost = 15,
        },
        prediction = { result = "+2", confidence = 50, resultConfident = false,
                       plus2Time = 1584, plus3Time = 1188, timeLimit = 1980 },
    }
end

return TP
