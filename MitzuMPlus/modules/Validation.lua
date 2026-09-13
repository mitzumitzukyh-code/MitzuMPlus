-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Validation
-- Validación y sanitización de datos de runs
--
-- FIX: eliminadas las definiciones de MitzuMPlus:FormatTime() y
--   MitzuMPlus:FormatNumber() que duplicaban (con comportamiento ligeramente
--   diferente) las versiones canónicas definidas en UI_Common.lua.
--   UI_Common.lua carga después y sobreescribía estas, por lo que la
--   existencia aquí era confusa y podría causar comportamiento inesperado
--   si el orden de carga cambiara. La fuente de verdad es UI_Common.lua.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

-- ─────────────────────────────────────────────────────────────────────────────
-- VALIDAR DATOS DE RUN
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:ValidateRunData(run)
    if type(run) ~= "table" then
        return false, "run no es tabla"
    end

    if not run.dungeonID or run.dungeonID == 0 then
        return false, "dungeonID inválido"
    end

    if not run.keyLevel or run.keyLevel < 2 then
        return false, "keyLevel inválido"
    end

    if not run.startTime or run.startTime == 0 then
        return false, "startTime inválido"
    end

    if not run.dungeonName or run.dungeonName == "" then
        if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
            local name = C_ChallengeMode.GetMapUIInfo(run.dungeonID)
            if name then
                run.dungeonName = name
            else
                return false, "dungeonName vacío y no se pudo recuperar"
            end
        else
            return false, "dungeonName vacío"
        end
    end

    if run.completionTime and run.completionTime < 0 then
        return false, "completionTime negativo"
    end

    if not run.stats then
        run.stats = {}
    end

    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- SANITIZAR DATOS DE RUN
-- Convierte todos los campos a sus tipos correctos y rellena los que falten.
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:SanitizeRunData(run)
    if type(run) ~= "table" then return nil end

    run.dungeonID      = tonumber(run.dungeonID)      or 0
    run.keyLevel       = tonumber(run.keyLevel)       or 0
    run.startTime      = tonumber(run.startTime)      or 0
    run.endTime        = tonumber(run.endTime)        or 0
    run.completionTime = tonumber(run.completionTime) or 0
    run.timeLimit      = tonumber(run.timeLimit)      or 0
    run.playerIlvl     = tonumber(run.playerIlvl)     or 0
    run.playerSpecID   = tonumber(run.playerSpecID)   or 0
    run.playerMythicRating = tonumber(run.playerMythicRating) or 0

    run.inTime     = run.inTime     and true or false
    run.isFavorite = run.isFavorite and true or false

    run.dungeonName  = tostring(run.dungeonName  or "")
    run.playerName   = tostring(run.playerName   or "")
    run.playerRealm  = tostring(run.playerRealm  or "")
    run.playerClass  = tostring(run.playerClass  or "")
    run.playerSpec   = tostring(run.playerSpec   or "")
    run.playerRole   = tostring(run.playerRole   or "")

    if type(run.affixes)       ~= "table" then run.affixes       = {} end
    if type(run.group)         ~= "table" then run.group         = {} end
    if type(run.equippedItems) ~= "table" then run.equippedItems = {} end
    if type(run.stats)         ~= "table" then run.stats         = {} end

    local stats = run.stats
    stats.damageTotal      = tonumber(stats.damageTotal)      or 0
    stats.damageBoss       = tonumber(stats.damageBoss)       or 0
    stats.damageTrash      = tonumber(stats.damageTrash)      or 0
    stats.damagePeak10s    = tonumber(stats.damagePeak10s)    or 0
    stats.healingTotal     = tonumber(stats.healingTotal)     or 0
    stats.healingOverheal  = tonumber(stats.healingOverheal)  or 0
    stats.healingPeak      = tonumber(stats.healingPeak)      or 0
    stats.damageTaken      = tonumber(stats.damageTaken)      or 0
    stats.damageMitigated  = tonumber(stats.damageMitigated)  or 0
    stats.absorbTotal      = tonumber(stats.absorbTotal)      or 0
    -- deaths = muertes del GRUPO; deathsSelf = muertes del JUGADOR.
    stats.deaths           = tonumber(stats.deaths)           or 0
    stats.deathsSelf       = tonumber(stats.deathsSelf)       or 0
    stats.kicks            = tonumber(stats.kicks)            or 0
    stats.dispels          = tonumber(stats.dispels)          or 0
    stats.kicksSelf         = tonumber(stats.kicksSelf)        or 0
    stats.kicksGroup        = tonumber(stats.kicksGroup)       or 0
    stats.dispelsSelf       = tonumber(stats.dispelsSelf)      or 0
    stats.dispelsGroup      = tonumber(stats.dispelsGroup)     or 0
    stats.cc               = tonumber(stats.cc)               or 0
    stats.brez             = tonumber(stats.brez)             or 0

    stats.avoidableDmg     = tonumber(stats.avoidableDmg)     or 0

    -- Campos legitimos que C_DamageMeter si puede rellenar.
    stats.healingAbsorbTotal       = tonumber(stats.healingAbsorbTotal)       or 0
    stats.healingDispelCount       = tonumber(stats.healingDispelCount)       or 0
    stats.tankDamageTakenTotal     = tonumber(stats.tankDamageTakenTotal)     or 0
    stats.tankDamageTakenEffective = tonumber(stats.tankDamageTakenEffective) or 0

    -- Enemy Forces (progreso de trash/mobs) — datos capturados desde
    -- KeystoneTracker al terminar la run. Permite al panel Historial mostrar
    -- si terminaste al 100% o saliste con porcentaje bajo.
    stats.enemyForcesFinalPct    = tonumber(stats.enemyForcesFinalPct)    or 0
    stats.enemyForcesFinalCount  = tonumber(stats.enemyForcesFinalCount)  or 0
    stats.enemyForcesTotal       = tonumber(stats.enemyForcesTotal)       or 0
    stats.deathTimeLostSec       = tonumber(stats.deathTimeLostSec)       or 0

    if type(run.timeline) ~= "table" then run.timeline = {} end
    if type(run.tags)     ~= "table" then run.tags     = {} end

    run.notes      = tostring(run.notes      or "")
    run.dataSource = tostring(run.dataSource or "")
    run.seasonKey  = tostring(run.seasonKey  or "")
    run.seasonName = tostring(run.seasonName or "")

    -- Premium fields (v5.0)
    run.score    = tonumber(run.score) or 0
    run.imported = run.imported and true or false
    if type(run.groupStats) ~= "table" then run.groupStats = {} end

    -- ─────────────────────────────────────────────────────────────────────
    -- v5.4.2 (BUG SANITIZE-1): este bloque estaba ANTES de una tanda de
    -- `tonumber(...) or 0` que volvia a crear exactamente los mismos campos.
    -- El resultado era justo lo que la regla prohibe: metricas que Blizzard ya
    -- no expone guardadas como 0, indistinguibles de una medicion real.
    -- Va AL FINAL a proposito. No mover hacia arriba.
    -- ─────────────────────────────────────────────────────────────────────
    stats.damagePeak10s = nil
    stats.damageBoss = nil
    stats.damageTrash = nil
    stats.healingOverheal = nil
    stats.healingPeak = nil
    stats.healingGroupTotal = nil
    stats.healingSelfTotal = nil
    stats.healingCastEfficiency = nil
    stats.healingCrisisEvents = nil
    stats.healingBrezCount = nil
    stats.healingCDUptimeSec = nil
    stats.tankDamageMitigated = nil
    stats.tankMitigationPct = nil
    stats.tankPeakDTPS10s = nil
    stats.tankSelfHealTotal = nil
    stats.tankAvoidEvents = nil
    stats.tankParryEvents = nil
    stats.tankDodgeEvents = nil
    stats.tankBlockEvents = nil
    stats.tankMissEvents = nil
    stats.tankDefensiveUptimeSec = nil
    stats.tankDefensiveUptimePct = nil
    stats.cc = nil
    stats.brez = nil
    stats.deadTime = nil

    return run
end

-- NOTA: FormatTime y FormatNumber NO se definen aquí.
-- Sus versiones canónicas están en UI_Common.lua y se asignan a MitzuMPlus:FormatTime()
-- y MitzuMPlus:FormatNumber() cuando ese archivo carga.
