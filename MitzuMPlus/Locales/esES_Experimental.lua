-- MitzuMPlus experimental Native UI localization for esES/esMX.
local function fill(L)
    if not L then return end
    L["KEY_READY_CHECK"] = "Comprobar grupo"
    L["KEY_READY_CHECK_TIP"] = "Inicia la comprobacion de grupo de Blizzard. Solo lider o asistente."
    L["KEY_PULL_TIMER"] = "Temporizador"
    L["KEY_PULL_TIMER_TIP"] = "Inicia la cuenta atras de Blizzard de %d segundos. No inicia la piedra."

    L["SEASON_PROGRESS"] = "Mazmorras con registro"
    L["SEASON_PROGRESS_VALUE"] = "%d / %d mazmorras"
    L["SEASON_GOAL"] = "Objetivo de temporada"
    L["SEASON_GOAL_VALUE"] = "Meta: %d   Actual: %d\nFaltan: %d"
    L["SEASON_GOAL_DISABLED"] = "Objetivo desactivado"
    L["SEASON_BEST_WEEKLY"] = "Mejor tiempo semanal"
    L["SEASON_RUNS_THIS_WEEK"] = "Runs esta semana: %d"
    L["SEASON_OPEN_HISTORY"] = "Abrir historial"
    L["SEASON_TELEPORT_HINT"] = "Iconos de mazmorra: teleport al desbloquearlo."

    L["SEASON_TARGET"] = "Meta"
    L["SEASON_CURRENT"] = "Actual"
    L["SEASON_MISSING"] = "Faltan"
    L["SEASON_WEEK_SHORT"] = "Mejor en tiempo"
    L["SEASON_PROGRESS_SHORT"] = "Con registro"
    L["SEASON_RUNS_SHORT"] = "Runs"
    L["SEASON_RECORDS_SHORT"] = "Con registro"
    L["SEASON_NO_TIMED_WEEK_SHORT"] = "Ninguna"
    L["SEASON_GOAL_COMPLETE_SHORT"] = "Objetivo cumplido"
    L["NO_DATA_SHORT"] = "Sin datos"
    L["CFG_NATIVE_UI_SECTION"] = "UI DE BLIZZARD"
    L["CFG_PULL_TIMER"] = "Duracion del temporizador"
    L["CFG_PULL_TIMER_D"] = "Elige la cuenta atrás nativa de Blizzard que usa el botón Temporizador."
    L["CFG_SEASON_GOAL"] = "Usar objetivo de temporada"
    L["CFG_SEASON_GOAL_D"] = "Activa una meta de puntaje solo para este personaje."
    L["CFG_SEASON_GOAL_TARGET"] = "Meta de puntaje mítico+"
    L["CFG_SEASON_GOAL_TARGET_D"] = "Escribe el puntaje que quieres alcanzar con este personaje."
    L["CFG_SEASON_GOAL_REQUIRED"] = "Define primero una meta mayor que 0."

    L["TELEPORT_STATE_AVAILABLE"] = "Teletransporte disponible. Haz clic para viajar."
    L["TELEPORT_STATE_COOLDOWN"] = "Teletransporte en reutilizacion."
    L["TELEPORT_STATE_LOCKED"] = "Teletransporte no desbloqueado en este personaje."
    L["TELEPORT_STATE_COMBAT_LOCKED"] = "Teletransporte no disponible durante combate."
    L["TELEPORT_STATE_UNAVAILABLE"] = "Teletransporte no disponible."
    L["TELEPORT_COOLDOWN_REMAINING"] = "Restante: %s"

    L["LFG_NEEDS_PREFIX"] = "Falta en el grupo"
    L["LFG_COVERAGE_READY"] = "Cobertura basica lista"
    L["LFG_NEED_TANK"] = "Tanque"
    L["LFG_NEED_HEALER"] = "Sanador"
    L["LFG_NEED_LUST"] = "Heroismo"
    L["LFG_NEED_LUST_CONDITIONAL"] = "Heroismo (mascota de cazador)"
    L["LFG_NEED_BREZ"] = "Resurreccion en combate"
    L["LFG_NEED_DPS_N"] = "DPS x%d"
    L["LFG_COVERAGE_PREFIX"] = "Cobertura"
    L["LFG_COVERAGE_LUST"] = "Heroísmo"
    L["LFG_COVERAGE_BREZ"] = "Brez"
    L["LFG_COVERAGE_SOOTHE"] = "Soothe"

    L["LFG_TILE_LUST"] = "HEROÍSMO"
    L["LFG_TILE_BREZ"] = "BREZ"
    L["LFG_TILE_SOOTHE"] = "SOOTHE"
end

fill(LibStub("AceLocale-3.0"):NewLocale("MitzuMPlusExperimental", "esES"))
fill(LibStub("AceLocale-3.0"):NewLocale("MitzuMPlusExperimental", "esMX"))
