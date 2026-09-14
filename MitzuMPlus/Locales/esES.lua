-- ===========================================================================
-- MitzuMPlus M+ Historial - Localization: Español (esES / esMX)
-- ===========================================================================

local L = LibStub("AceLocale-3.0"):NewLocale("MitzuMPlus", "esES")
if not L then
    L = LibStub("AceLocale-3.0"):NewLocale("MitzuMPlus", "esMX")
    if not L then return end
end

-- -- General -------------------------------------------------------------
L["ADDON_LOADED"]           = "|cFFD4A43CMitzuMPlus M+ Historial|r v%s cargado. /MitzuMPlus para abrir."
L["ADDON_TITLE"]            = "MitzuMPlus M+ HISTORIAL"
L["ADDON_SUBTITLE"]         = "Historial y Análisis de Mythic+"

-- -- Tabs ----------------------------------------------------------------
L["TAB_HISTORIAL"]          = "Historial"
L["TAB_STATS"]              = "Estadísticas"
L["TAB_DETAIL"]             = "Detalle"
L["TAB_COMPARE"]            = "Comparar"
L["TAB_CONFIG"]             = "Configuración"
L["TAB_SEASON"]             = "Temporada"

-- -- Sidebar -------------------------------------------------------------
L["SIDEBAR_GLOBAL_SUMMARY"] = ">> RESUMEN GLOBAL (%d)"
L["SIDEBAR_TOTAL_RUNS"]     = "Runs totales"
L["SIDEBAR_IN_TIME"]        = "En tiempo"
L["SIDEBAR_OUT_OF_TIME"]    = "Fuera de tiempo"
L["SIDEBAR_THIS_WEEK"]      = "Esta semana"
L["SIDEBAR_BEST_KEY"]       = "MEJOR LLAVE"
L["SIDEBAR_AVG_DPS"]        = ">> DPS PROMEDIO (%s)"
L["SIDEBAR_AVERAGE"]        = "Promedio"
L["SIDEBAR_PEAK_10S"]       = "Pico 10s"
L["SIDEBAR_WEEKLY"]         = ">> ESTA SEMANA"
L["SIDEBAR_WEEKLY_RUNS"]    = "Runs"
L["SIDEBAR_WEEKLY_INTIME"]  = "En tiempo"
L["SIDEBAR_WEEKLY_DEATHS"]  = "Muertes totales"
L["SIDEBAR_BEST_PER_DUNG"]  = ">> MEJOR POR MAZMORRA"

-- -- Filter Bar ----------------------------------------------------------
L["FILTER_SEARCH"]          = "Buscar mazmorra..."
L["FILTER_ALL_DUNGEONS"]    = "Todas"
L["FILTER_ALL_RESULTS"]     = "Todas"
L["FILTER_IN_TIME_ONLY"]    = "En tiempo"
L["FILTER_OUT_TIME_ONLY"]   = "Fuera de tiempo"
L["FILTER_SORT_DATE"]       = "Fecha"
L["FILTER_SORT_LEVEL"]      = "Nivel"
L["FILTER_SORT_DPS"]        = "DPS"
L["FILTER_SORT_TIME"]       = "Tiempo"
L["FILTER_SORT_DEATHS"]     = "Muertes"

-- -- Buttons -------------------------------------------------------------
L["BTN_EXPORT_CSV"]         = "Exportar CSV"
L["BTN_EXPORT_CODE"]        = "Exportar Code"
L["BTN_EXPORT_WEB"]         = "Exportar Web"
L["BTN_COMPARE"]            = "Comparar"
L["BTN_CLOSE"]              = "Cerrar"
L["BTN_BACK"]               = "<-- Volver"
L["BTN_DELETE"]              = "Eliminar"
L["BTN_FAVORITE"]           = "Favorito"

-- -- Run States ----------------------------------------------------------
L["RUN_IN_TIME"]            = "EN TIEMPO"
L["RUN_OUT_OF_TIME"]        = "FUERA DE TIEMPO"
L["RUN_STARTED"]            = "|cFF21de66M+ Iniciada:|r %s +%d | Rol: %s (%s) | Fuente: %s"
L["RUN_COMPLETED"]          = "%s +%d - %s"
L["RUN_PRACTICE"]           = "Run de práctica detectada, no se guardará."
L["RUN_DUPLICATE"]          = "Duplicado ignorado: Esta run ya fue registrada."

-- -- Stats Panel ---------------------------------------------------------
L["STATS_TOTAL_RUNS"]       = "RUNS TOTALES"
L["STATS_SUCCESS_RATE"]     = "TASA DE ÉXITO"
L["STATS_BEST_KEY"]         = "MEJOR LLAVE"
L["STATS_DPS_WEEKLY"]       = "DPS POR SEMANA"
L["STATS_TOTAL_DEATHS"]     = "MUERTES TOTALES"
L["STATS_INTERRUPTS"]       = "INTERRUPCIONES"
L["STATS_DUNGEON_PERF"]     = "RENDIMIENTO POR MAZMORRA"
L["STATS_COMMON_AFFIXES"]   = "AFIJOS MÁS COMUNES"
L["STATS_TOTAL_DISPELS"]    = "TOTAL DISPELS"
L["STATS_REGISTERED"]       = "registradas"
L["STATS_AVERAGE"]          = "promedio"
L["STATS_PER_RUN"]          = "%.1f por run"
L["STATS_DUNGEONS"]         = "mazmorras"
L["STATS_RUNS_ANALYZED"]    = "runs analizadas"

-- -- Detail Panel --------------------------------------------------------
L["DETAIL_NO_RUN"]          = "Ninguna Run Seleccionada"
L["DETAIL_SELECT_RUN"]      = "Selecciona una run del Historial para ver detalles."

-- -- Compare Panel -------------------------------------------------------
L["COMPARE_TITLE"]          = "Comparación de Runs"
L["COMPARE_SELECT"]         = "Selecciona dos runs para compararlas lado a lado"
L["COMPARE_NEED_2"]         = "Necesitas al menos 2 runs para comparar"
L["COMPARE_RUN1"]           = "RUN 1"
L["COMPARE_RUN2"]           = "RUN 2"
L["COMPARE_SUMMARY"]        = ">> RESUMEN"
L["COMPARE_STATS"]          = ">> ESTADÍSTICAS COMPARADAS"
L["COMPARE_PERFORMANCE"]    = ">> RENDIMIENTO GENERAL"

-- -- Config Panel --------------------------------------------------------
L["CONFIG_GENERAL"]         = ">> CONFIGURACIÓN GENERAL"
L["CONFIG_AUTO_RECORD"]     = "Registrar automáticamente"
L["CONFIG_AUTO_RECORD_D"]   = "Registra las runs completadas de forma automática"
L["CONFIG_INTIME_ONLY"]     = "Solo runs en tiempo"
L["CONFIG_INTIME_ONLY_D"]   = "Registra únicamente runs completadas dentro del tiempo límite"
L["CONFIG_FULL_DETAILS"]    = "Registrar detalles completos"
L["CONFIG_FULL_DETAILS_D"]  = "Incluye estadísticas de combate: DPS, healing, muertes, etc."
L["CONFIG_SHARE_DATA"]      = "Compartir datos con grupo"
L["CONFIG_SHARE_DATA_D"]    = "Permite que otros jugadores vean tus estadísticas"
L["CONFIG_MIN_KEY"]         = "Nivel mínimo de llave"
L["CONFIG_UI"]              = ">> INTERFAZ"
L["CONFIG_MINIMAP"]         = "Mostrar botón de minimapa"
L["CONFIG_MINIMAP_D"]       = "Muestra el ícono de MitzuMPlus en el minimapa"
L["CONFIG_LOCK_WINDOW"]     = "Bloquear ventana"
L["CONFIG_LOCK_WINDOW_D"]   = "Evita que la ventana se mueva accidentalmente"
L["CONFIG_ANIMATIONS"]      = "Habilitar animaciones"
L["CONFIG_ANIMATIONS_D"]    = "Animación de aparición al abrir la ventana"
L["CONFIG_ESC_CLOSE"]       = "Cerrar con Escape"
L["CONFIG_ESC_CLOSE_D"]     = "Permite cerrar la ventana presionando la tecla Escape"
L["CONFIG_OPACITY"]         = "Opacidad de ventana (%)"
L["CONFIG_NOTIF"]           = ">> NOTIFICACIONES"
L["CONFIG_NOTIF_COMPLETE"]  = "Notificar al completar run"
L["CONFIG_NOTIF_COMPLETE_D"]= "Muestra un mensaje en pantalla al terminar una Mythic+"
L["CONFIG_NOTIF_RECORD"]    = "Notificar nuevo récord"
L["CONFIG_NOTIF_RECORD_D"]  = "Alerta cuando superas tu mejor tiempo en una mazmorra"
L["CONFIG_SOUND"]           = "Alertas sonoras"
L["CONFIG_SOUND_D"]         = "Reproduce sonidos para las notificaciones del addon"
L["CONFIG_CHAT"]            = "Resumen en chat"
L["CONFIG_CHAT_D"]          = "Muestra un resumen de la run en el chat al terminar"
L["CONFIG_DATA"]            = ">> GESTIÓN DE DATOS"
L["CONFIG_RUNS_STORED"]     = "Runs registradas:"
L["CONFIG_IN_DATABASE"]     = "%d en base de datos"
L["CONFIG_EXPORT_CSV"]      = "Exportar a CSV"
L["CONFIG_RESET_CONFIG"]    = "Restablecer configuración"
L["CONFIG_DELETE_ALL"]      = "Borrar todos los datos"
L["CONFIG_ABOUT"]           = ">> ACERCA DE"

-- -- Personal Best -------------------------------------------------------
L["PB_NEW_RECORD"]          = "|cFF21de66NUEVO RÉCORD!|r Mejor llave en %s: |cFFe8b84a+%d|r"
L["PB_NEW_TIME"]            = "|cFF21de66NUEVO PB!|r Mejor tiempo en %s +%d: |cFFe8b84a%s|r"
L["PB_NEW_DPS"]             = "|cFF21de66NUEVO PB DPS!|r %s: |cFFe8b84a%s|r DPS"
L["PB_NEW_HPS"]             = "|cFF21de66NUEVO PB HPS!|r %s: |cFFe8b84a%s|r HPS"
L["PB_FLAWLESS"]            = "|cFF21de66IMPECABLE!|r %s +%d completada sin muertes"

-- -- Goals ---------------------------------------------------------------
L["GOAL_UNLOCKED"]          = "|cFFFFD700LOGRO DESBLOQUEADO!|r |cFFe8b84a%s|r - %s"

-- -- Score ---------------------------------------------------------------
L["SCORE_TITLE"]            = "Puntuación M+"
L["SCORE_TOTAL"]            = "Puntuación Total"
L["SCORE_WEEKLY_DELTA"]     = "Cambio Semanal"

-- -- Slash Commands ------------------------------------------------------
L["HELP_TITLE"]             = "|cFFe8b84a===== MitzuMPlus M+ HISTORIAL - AYUDA =====|r"
L["HELP_OPEN"]              = "|cFFf7d470/MitzuMPlus|r o |cFFf7d470/emp|r  - Abrir/cerrar ventana"
L["HELP_HISTORIAL"]         = "|cFFf7d470/MitzuMPlus historial|r          - Tab Historial"
L["HELP_STATS"]             = "|cFFf7d470/MitzuMPlus stats|r              - Tab Estadísticas"
L["HELP_COMPARE"]           = "|cFFf7d470/MitzuMPlus compare|r            - Tab Comparar"
L["HELP_CONFIG"]            = "|cFFf7d470/MitzuMPlus config|r             - Configuración"
L["HELP_SYNC"]              = "|cFFf7d470/MitzuMPlus sync|r               - Tab Temporada"
L["HELP_ACTIVATE"]          = "|cFFf7d470/MitzuMPlus activate|r           - Activar tracking"
L["HELP_DEACTIVATE"]        = "|cFFf7d470/MitzuMPlus deactivate|r         - Desactivar tracking"
L["HELP_RESETSIZE"]         = "|cFFf7d470/MitzuMPlus resetsize|r          - Resetear ventana"
L["HELP_RESETCONFIG"]       = "|cFFf7d470/MitzuMPlus resetconfig|r        - Resetear config"
L["HELP_VERSION"]           = "|cFFf7d470/MitzuMPlus version|r            - Mostrar versión"
L["HELP_BUGREPORT"]         = "|cFFf7d470/MitzuMPlus bugreport|r          - Copiar log de errores"
L["HELP_CLEARERRORS"]       = "|cFFf7d470/MitzuMPlus clearerrors|r        - Limpiar errores"

-- -- Misc ----------------------------------------------------------------
L["DUNGEON"]                = "Mazmorra"
L["KEY_LEVEL"]              = "Nivel de Llave"
L["RESULT"]                 = "Resultado"
L["TIME"]                   = "Tiempo"
L["DATE"]                   = "Fecha"
L["DPS"]                    = "DPS"
L["HPS"]                    = "HPS"
L["DEATHS"]                 = "Muertes"
L["KICKS"]                  = "Interrupciones"
L["DISPELS"]                = "Dispels"
L["ROLE"]                   = "Rol"
L["ILVL"]                   = "iLvl"
L["TANK"]                   = "Tanque"
L["HEALER"]                 = "Sanador"
L["DAMAGER"]                = "DPS"
L["TODAY"]                  = "Hoy"
L["YESTERDAY"]              = "Ayer"
L["DAYS_AGO"]               = "Hace %d días"
L["NO_DATA"]                = "Sin datos"
L["WELCOME"]                = ">> Bienvenido a MitzuMPlus"
L["WELCOME_DESC"]           = "Completa tu primera M+ con el addon activo para ver tus estadísticas aquí."
L["NO_RUNS"]                = "Sin runs registradas"
L["NO_RUNS_DESC"]           = "Completa tu primera Mythic+ con el addon activo para verla aquí."
L["STATUS_ACTIVE"]          = "ACTIVO"
L["TRACKING_ACTIVATED"]     = "|cFF21de66Tracking de M+ activado.|r"
L["TRACKING_DEACTIVATED"]   = "|cFFee3333Tracking de M+ desactivado.|r"
