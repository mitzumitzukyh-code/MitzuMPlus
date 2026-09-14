-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Database Defaults & Configuration (v2.1)
-- ÚNICA definición de defaults.
-- CAMBIOS v2.1:
--   • Añadido global.activeSeason  — temporada activa sincronizada
--   • Añadido global.seasonHistory — historial de temporadas anteriores
--   • Añadidos campos tank/heal en tracking settings
-- ═══════════════════════════════════════════════════════════════════════════

MitzuMPlusDB_Defaults = {
    global = {
        runs       = {},
        nextRunID  = 1,
        -- FIX BUG-12: la versión se actualiza en OnInitialize leyendo MitzuMPlus.VERSION
        -- para que siempre refleje la versión instalada real.
        version    = "UNSET",

        -- ── Log de errores del addon (gestionado por modules/ErrorLogger.lua)
        -- Máximo MAX_ERRORS entradas; las más antiguas se rotan automáticamente.
        -- Limpiar con: /emp clearerrors
        errorLog = {},

        personalBests = {},   -- [charKey][dungeonKey] = { bestTime, bestDPS, etc. }
        dungeonRegistry = { byInstanceMapID = {}, byUIMapID = {} },
        activeRunSession = nil,
    },
    profile = {
        notifyOnComplete = true,
        notifyNewRecord = true,
        notifyPersonalBest = true,
        chatOutput = false,
        settings = {
            -- LibSharedMedia (opcional): nombre de fuente elegido por el
            -- usuario. nil = la del tema. Si LSM no esta instalada o la
            -- fuente desaparece, se cae al tema sin avisar.
            uiFont = nil,
            minimapIcon      = { hide = false },
            lootTracking     = true,
            lootMinQuality   = 2,
            lootMinIlvl      = 0,
            showToasts       = true,
            pageSize         = 20,
            defaultTab       = "historial",
            windowOpacity    = 1.0,
            windowWidth      = nil,
            windowHeight     = nil,
            closeWithEscape  = true,
            enableAnimations = true,
            windowLocked     = false,
            windowScale      = 1.0,
            -- Escala independiente del texto de la UI. 115% evita que los
            -- captions/tablas queden microscópicos con UI Scale de WoW.
            textScale        = 1.15,
            debugMode        = false,

            -- ── v7.14.0: Key Prediction HUD (modules/KeyPredictionHUD.lua) ─
            -- El único HUD en vivo: solo predice +3/+2/+1/OVERTIME.
            -- Los ajustes históricos retirados no se leen ni se borran.
            hud = {
                enabled        = true,
                locked         = false,
                scale          = 1.0,
                alpha          = 1.0,
                showConfidence = true,
                showETA        = true,
            },

        },

        position = {
            point         = "TOPLEFT",
            relativePoint = "BOTTOMLEFT",
            x = nil,
            y = nil,
        },
    },
    char = {
        lastRunID               = nil,
    },
}
