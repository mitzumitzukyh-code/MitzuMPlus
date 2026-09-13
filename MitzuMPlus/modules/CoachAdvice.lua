-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · CoachAdvice  —  UNA regla de prioridad, dos vistas
--
-- La recomendación de prioridad ("quedan menos de 2 minutos", "acelera
-- fuerzas"...) vivía escrita dentro del overlay del Coach. El Coach HUD V2
-- necesita la misma decisión; copiarla habría creado dos reglas que acaban
-- divergiendo. Aquí queda una sola, pura: recibe el snapshot de
-- PredictionEngine y devuelve qué decir, sin tocar frames ni estado.
--
-- DATO DISPONIBLE ≠ RECOMENDACIÓN POSIBLE
-- Cada regla declara en qué se apoya:
--   TIME        el reloj oficial (limite - transcurrido). Es un dato.
--   PROJECTION  la proyección de PredictionEngine. Solo vale con hasBasis.
-- Con `requireBasis` (lo que usa el HUD V2) una regla de PROJECTION sin base
-- no produce nada: mejor callar que convertir datos incompletos de Midnight en
-- una recomendación fuerte. El overlay clásico conserva su comportamiento de
-- siempre llamando sin `requireBasis`.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local CoachAdvice = {}
MitzuMPlus.CoachAdvice = CoachAdvice

CoachAdvice.SEVERITY = { CRITICAL = "CRITICAL", WARN = "WARN", INFO = "INFO", GOOD = "GOOD" }

local function num(v)
    local S = MitzuMPlus.QASafe
    if S then return S.Number(v) end
    return tonumber(v)
end

-- Devuelve { key, severity, text, evidence } o nil si no hay nada que decir.
function CoachAdvice.Evaluate(s, opts)
    if type(s) ~= "table" then return nil end
    opts = opts or {}
    local basis = s.hasBasis == true
    local requireBasis = opts.requireBasis == true

    local remaining = num(s.timeRemaining)
    local limit = num(s.timeLimit)
    if remaining and (not requireBasis or (limit and limit > 0)) and remaining <= 120 then
        return { key = "TIME_CRITICAL", severity = "CRITICAL", evidence = "TIME",
                 text = "quedan menos de 2 minutos" }
    end

    if requireBasis and not basis then return nil end

    local budget = num(s.deathBudget)
    if budget and budget <= 1 then
        return { key = "DEATH_BUDGET", severity = "CRITICAL", evidence = "PROJECTION",
                 text = "casi sin margen para otra muerte" }
    end

    local pace, needed = num(s.pacePct), num(s.neededPct)
    if pace and needed and pace < needed then
        return { key = "PACE", severity = "WARN", evidence = "PROJECTION",
                 text = string.format("acelera fuerzas (faltan %.1f%%/min)", needed - pace) }
    end

    local done, total = num(s.bossesDone) or 0, num(s.bossesTotal) or 0
    if done < total then
        return { key = "NEXT_BOSS", severity = "INFO", evidence = "PROJECTION",
                 text = "siguiente boss y supervivencia" }
    end

    return { key = "STEADY", severity = "GOOD", evidence = "PROJECTION",
             text = "completa fuerzas sin asumir riesgos" }
end

return CoachAdvice
