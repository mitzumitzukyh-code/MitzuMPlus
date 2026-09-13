-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · Calibration v1.0
--
-- Mide la EXACTITUD real de la predicción, y nada más.
--
-- Sustituye al antiguo CapabilityLog quedándose solo con la mitad que aportaba
-- valor. Aquel guardaba 110 muestras por llave para poder mirar la evolución
-- entera; esto guarda 12 números por llave. La diferencia importa porque el
-- registro pesado vivía en SavedVariables y se escribía en cada guardado.
--
-- POR QUÉ EXISTE
-- En v5.9.0 se cambió el motor a partir de 4 llaves medidas: se metió el
-- suavizado, la histéresis del bracket y la puerta de confianza (por debajo de
-- 50 el resultado no se afirma, se marca provisional). Ninguno de esos tres
-- cambios se ha comprobado nunca, porque el instrumento que produjo los
-- números se borró justo después. Sin esto, "acierto final 2 de 4" se queda
-- congelado como el último dato conocido para siempre.
--
-- LO QUE MIDE, Y POR QUÉ ESA MÉTRICA
-- Además del error de proyección clásico, mide la PRECISIÓN DE LAS
-- AFIRMACIONES: de las veces que el addon dijo el resultado con seguridad
-- (resultConfident), ¿cuántas acertó? Esa es la métrica que decide si la
-- puerta de confianza funciona. Un addon que acierta poco pero solo afirma
-- cuando está seguro es útil; uno que afirma siempre y acierta la mitad, no.
--
--   /emp capcalib   exactitud acumulada
--   /emp capclear   borrar
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local Calibration = {}
MitzuMPlus.Calibration = Calibration

local SAMPLE_EVERY = 5      -- segundos; solo lee, casi nunca guarda
local MAX_RECORDS  = 40     -- 12 numeros por llave: cabe de sobra
local CHECKPOINTS  = { 25, 50, 75 }

-- ─────────────────────────────────────────────────────────────────────────
-- ALMACÉN
-- ─────────────────────────────────────────────────────────────────────────

local function store()
    if not (MitzuMPlus.db and MitzuMPlus.db.global) then return nil end
    local g = MitzuMPlus.db.global
    if type(g.calibration) ~= "table" then g.calibration = { runs = {} } end
    if type(g.calibration.runs) ~= "table" then g.calibration.runs = {} end
    return g.calibration
end

local function fmtTime(s)
    s = math.max(0, math.floor(tonumber(s) or 0))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function signedTime(s)
    local v = tonumber(s) or 0
    return (v >= 0 and "+" or "-") .. fmtTime(math.abs(v))
end

local function median(t)
    if #t == 0 then return nil end
    table.sort(t)
    local n = #t
    if n % 2 == 1 then return t[(n + 1) / 2] end
    return (t[n / 2] + t[n / 2 + 1]) / 2
end

function Calibration:IsEnabled()
    local st = MitzuMPlus.db and MitzuMPlus.db.profile and MitzuMPlus.db.profile.settings
    if not st or st.calibrationEnabled == nil then return true end
    return st.calibrationEnabled == true
end

-- ─────────────────────────────────────────────────────────────────────────
-- CAPTURA
-- ─────────────────────────────────────────────────────────────────────────

function Calibration:Start(run)
    if not self:IsEnabled() then return end
    run = run or _G.MitzuMPlusCurrentRun
    if not run then return end

    self._cur = {
        dungeon = tostring(run.dungeonName or "?"),
        level   = tonumber(run.keyLevel) or 0,
        limit   = tonumber(run.timeLimit) or 0,
        when    = (time and time()) or 0,
        version = tostring(MitzuMPlus.VERSION or "?"),
        cps     = {},            -- [pct] = {t, proj, bracket, conf, confident}
        flips   = 0,
        -- Historial mínimo del bracket afirmado, para medir la precisión de
        -- las afirmaciones sin guardar muestras.
        assertions = { total = 0, byBracket = {} },
        lastBracket = nil,
        stableSince = nil,
    }
    self._active = true

    self:_StopTicker()
    if C_Timer and C_Timer.NewTicker then
        self._ticker = C_Timer.NewTicker(SAMPLE_EVERY, function()
            pcall(function() Calibration:_Sample() end)
        end)
    end
end

function Calibration:_StopTicker()
    if self._ticker then
        if self._ticker.Cancel then self._ticker:Cancel() end
        self._ticker = nil
    end
end

function Calibration:_Sample()
    if not self._active then return end
    local c = self._cur
    if not c then return end

    local Engine = MitzuMPlus.PredictionEngine
    local snap = Engine and Engine:GetSnapshot() or nil
    if not snap then return end

    local kt = MitzuMPlus.KeystoneTracker
    local elapsed = kt and tonumber(kt:GetElapsed()) or 0
    local pct = tonumber(snap.enemyPct) or 0

    -- Puntos de control: se capturan al CRUZAR el umbral, una sola vez.
    for _, cp in ipairs(CHECKPOINTS) do
        if pct >= cp and not c.cps[cp] and snap.projectedTime then
            c.cps[cp] = {
                t         = math.floor(elapsed),
                proj      = math.floor(snap.projectedTime),
                bracket   = snap.result,
                conf      = snap.confidence,
                confident = snap.resultConfident == true,
            }
        end
    end

    -- Cambios de bracket y desde cuándo se mantiene.
    if snap.result then
        if c.lastBracket and snap.result ~= c.lastBracket then
            c.flips = c.flips + 1
            c.stableSince = nil
        end
        if not c.stableSince then c.stableSince = math.floor(elapsed) end
        c.lastBracket = snap.result

        -- Afirmaciones: se cuenta cuántas veces el addon dijo cada bracket
        -- CON seguridad. Al final se compara con el real.
        if snap.resultConfident then
            local a = c.assertions
            a.total = a.total + 1
            a.byBracket[snap.result] = (a.byBracket[snap.result] or 0) + 1
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- CIERRE
-- ─────────────────────────────────────────────────────────────────────────

function Calibration:Finish(run)
    if not self._active then return end
    self:_StopTicker()
    self._active = false

    local c = self._cur
    self._cur = nil
    if not c then return end

    self:_Sample()   -- no hace nada ya, pero es barato y evita perder el último cruce

    local actual = tonumber(run and run.completionTime) or 0
    local limit  = c.limit or 0
    if actual <= 0 or limit <= 0 then return end   -- llave abandonada: nada que medir

    local function bracketOf(t)
        if t <= limit * 0.6 then return "+3"
        elseif t <= limit * 0.8 then return "+2"
        elseif t <= limit then return "+1"
        else return "FUERA" end
    end
    local truth = bracketOf(actual)

    local rec = {
        dungeon = c.dungeon, level = c.level, limit = limit,
        actual = actual, truth = truth, when = c.when, version = c.version,
        flips = c.flips, finalOK = (c.lastBracket == truth),
        stable = c.stableSince,
    }

    for _, cp in ipairs(CHECKPOINTS) do
        local s = c.cps[cp]
        if s then
            rec["e" .. cp]  = s.proj - actual
            rec["ok" .. cp] = (s.bracket == truth)
            rec["cf" .. cp] = s.confident and 1 or 0
            rec["c" .. cp]  = s.conf
        end
    end

    -- Precisión de las afirmaciones: de las veces que afirmó con seguridad,
    -- ¿en cuántas el bracket afirmado era el verdadero?
    local a = c.assertions
    if a.total > 0 then
        rec.assertTotal = a.total
        rec.assertRight = a.byBracket[truth] or 0
    end

    local st = store()
    if st then
        table.insert(st.runs, rec)
        while #st.runs > MAX_RECORDS do table.remove(st.runs, 1) end
    end

    if MitzuMPlus.Print then
        MitzuMPlus:Print(string.format(
            "|cFF88CCFF[Calibración]|r llave registrada (%d en total). |cFFf7d470/emp capcalib|r",
            st and #st.runs or 1))
    end
end

function Calibration:Abort()
    self:_StopTicker()
    self._active = false
    self._cur = nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- INFORME
-- ─────────────────────────────────────────────────────────────────────────

function Calibration:Count()
    local st = store()
    return st and #st.runs or 0
end

function Calibration:Clear()
    local st = store()
    if st then st.runs = {} end
    if MitzuMPlus.Print then MitzuMPlus:Print("|cFF88CCFF[Calibración]|r registro borrado.") end
end

-- ═════════════════════════════════════════════════════════════════════════
-- VEREDICTO EN CRISTIANO  (v7.6.0)
--
-- Al terminar, el addon guardaba numeros pero no decia NADA sobre que habia
-- pasado. Un jugador que empieza no sabe leer "24:35 / 28:00 · 5 muertes": no
-- sabe si se fue por el ritmo o por las muertes.
--
-- Se compara lo que costaron las muertes con lo que faltaba o sobraba, que es
-- la unica atribucion que se puede hacer con datos reales y sin inventar.
-- ═════════════════════════════════════════════════════════════════════════
function Calibration:Verdict(actual, limit, deaths, timeLost)
    actual   = tonumber(actual) or 0
    limit    = tonumber(limit) or 0
    deaths   = tonumber(deaths) or 0
    timeLost = tonumber(timeLost) or 0
    if actual <= 0 or limit <= 0 then return nil end

    local margin = limit - actual          -- >0 entro en tiempo
    local inTime = margin >= 0

    if inTime then
        if deaths > 0 and timeLost > margin then
            -- Sin esas muertes habria entrado; con ellas, no. Entro igual, pero
            -- por los pelos y gracias a otra cosa.
            return string.format(
                "Entraste por %s. Las %d muerte(s) costaron %s: sin ellas habria sido mucho mas holgado.",
                fmtTime(margin), deaths, fmtTime(timeLost)), "warn"
        end
        if margin >= limit * 0.2 then
            return string.format("Entraste de sobra, por %s. Se podia haber ido a mas nivel.", fmtTime(margin)), "good"
        end
        return string.format("Entraste por %s.", fmtTime(margin)), "good"
    end

    local over = -margin
    if deaths > 0 and timeLost >= over then
        return string.format(
            "Se fue por %s, y las %d muerte(s) costaron %s: la llave se perdio en las muertes, no en el ritmo.",
            fmtTime(over), deaths, fmtTime(timeLost)), "bad"
    end
    if deaths > 0 then
        return string.format(
            "Se fue por %s. Las muertes costaron %s, asi que faltaba ritmo ademas de morir menos.",
            fmtTime(over), fmtTime(timeLost)), "bad"
    end
    return string.format("Se fue por %s sin morir nadie: falto ritmo, no supervivencia.", fmtTime(over)), "bad"
end

-- Imprime el veredicto al terminar. Se saca del propio run, no del snapshot,
-- porque en ese momento la llave ya cerro y el tracker puede estar reseteado.
function Calibration:PrintVerdict(run)
    if type(run) ~= "table" then return end
    local actual = tonumber(run.completionTime) or 0
    local limit  = tonumber(run.timeLimit) or 0
    if actual <= 0 or limit <= 0 then return end   -- llave no completada

    local deaths, timeLost = 0, 0
    local st = run.stats
    if type(st) == "table" then deaths = tonumber(st.deaths) or 0 end
    local kt = MitzuMPlus.KeystoneTracker
    if kt and kt.GetDeathInfo then
        local okD, d, tl = pcall(kt.GetDeathInfo, kt)
        if okD then
            deaths   = tonumber(d) or deaths
            timeLost = tonumber(tl) or 0
        end
    end

    local text, tone = self:Verdict(actual, limit, deaths, timeLost)
    if not text then return end
    local color = (tone == "good" and "|cFF21de66")
               or (tone == "warn" and "|cFFff9922")
               or "|cFFff5555"
    MitzuMPlus:Print(color .. text .. "|r")
end

function Calibration:Lines()
    local out = {}
    local function add(s) out[#out + 1] = s end

    local st = store()
    local rows = st and st.runs or {}
    if #rows == 0 then
        add("|cFFff9922[Calibración]|r sin llaves registradas todavía.")
        add("Se guarda una entrada por cada M+ COMPLETADA (hace falta el tiempo real).")
        return out
    end

    -- Versiones presentes: sin esto no se puede distinguir una llave jugada
    -- antes de un cambio del motor de otra jugada después, y la mediana
    -- mezclaría manzanas con peras. Fue el agujero del instrumento anterior.
    local versions = {}
    for _, r in ipairs(rows) do
        local v = tostring(r.version or "?")
        versions[v] = (versions[v] or 0) + 1
    end
    local vparts = {}
    for v, n in pairs(versions) do vparts[#vparts + 1] = string.format("%s(%d)", v, n) end
    table.sort(vparts)

    add(string.format("|cFFd9b33e[Calibración] %d llave(s)|r · versiones: %s",
        #rows, table.concat(vparts, " ")))

    for _, cp in ipairs(CHECKPOINTS) do
        local errs, ok, tot = {}, 0, 0
        for _, r in ipairs(rows) do
            local e = r["e" .. cp]
            if e ~= nil then
                errs[#errs + 1] = e
                tot = tot + 1
                if r["ok" .. cp] then ok = ok + 1 end
            end
        end
        if tot > 0 then
            local med = median(errs)
            local sesgo = med < 0 and "optimista" or (med > 0 and "pesimista" or "neutro")
            add(string.format("  al %d%%: se equivoca de media en %s (%s) · resultado acertado %d/%d",
                cp, signedTime(med), sesgo, ok, tot))
        end
    end

    local flips, stables, finalOK = {}, {}, 0
    for _, r in ipairs(rows) do
        flips[#flips + 1] = r.flips or 0
        if r.stable then stables[#stables + 1] = r.stable end
        if r.finalOK then finalOK = finalOK + 1 end
    end
    add(string.format("  veces que cambio de opinion (mediana): %s · acerto al final: %d/%d",
        tostring(median(flips) or "-"), finalOK, #rows))
    if #stables > 0 then
        add(string.format("  se estabiliza (mediana): minuto %s", fmtTime(median(stables))))
    end

    -- ── LA MÉTRICA QUE DECIDE SI LA PUERTA DE CONFIANZA SIRVE ──
    -- Se compara el acierto CUANDO afirmó con seguridad contra el acierto
    -- cuando no. Si el primero no es claramente mejor, la puerta no separa
    -- nada y el umbral de 50 está mal puesto.
    local confOK, confTot, provOK, provTot = 0, 0, 0, 0
    for _, r in ipairs(rows) do
        for _, cp in ipairs(CHECKPOINTS) do
            local cf = r["cf" .. cp]
            local okk = r["ok" .. cp]
            if cf ~= nil then
                if cf == 1 then
                    confTot = confTot + 1
                    if okk then confOK = confOK + 1 end
                else
                    provTot = provTot + 1
                    if okk then provOK = provOK + 1 end
                end
            end
        end
    end
    if confTot + provTot > 0 then
        add("|cFFd9b33e  Filtro de fiabilidad (lo que se cambió en v5.9.0):|r")
        add(string.format("    afirmó con seguridad: %d/%d correctos%s",
            confOK, confTot,
            confTot > 0 and string.format(" (%.0f%%)", confOK / confTot * 100) or ""))
        add(string.format("    marcó provisional:    %d/%d correctos%s",
            provOK, provTot,
            provTot > 0 and string.format(" (%.0f%%)", provOK / provTot * 100) or ""))
        if confTot >= 3 and provTot >= 3 then
            local a, b = confOK / confTot, provOK / provTot
            if a > b + 0.15 then
                add("    |cFF21de66La puerta separa bien:|r cuando afirma, acierta más.")
            elseif a < b - 0.05 then
                add("    |cFFff5555La puerta está invertida:|r acierta MENOS cuando afirma. Revisar el umbral.")
            else
                add("    |cFFff9922La puerta no separa nada|r: el umbral de 50 no discrimina.")
            end
        else
            add("    (hacen falta más llaves para juzgar la puerta)")
        end
    end

    add("Con 6+ llaves de la MISMA versión el sesgo mediano ya es corregible.")
    return out
end

-- ─────────────────────────────────────────────────────────────────────────
-- EVENTOS
-- ─────────────────────────────────────────────────────────────────────────

if MitzuMPlus.EventBus and MitzuMPlus.EventBus.On then
    MitzuMPlus.EventBus:On("RUN_STARTED", function(run)
        pcall(function() Calibration:Start(run) end)
    end, 70)
    MitzuMPlus.EventBus:On("RUN_COMPLETED", function(run)
        pcall(function() Calibration:Finish(run) end)
        pcall(function() Calibration:PrintVerdict(run) end)
    end, 70)
    MitzuMPlus.EventBus:On("RUN_RESET",    function() Calibration:Abort() end, 70)
    MitzuMPlus.EventBus:On("RUN_TEARDOWN", function() Calibration:Abort() end, 70)
end

return Calibration
