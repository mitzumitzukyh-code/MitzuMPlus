-- ===========================================================================
-- MitzuMPlus M+ Historial - Constants (v2.1)
-- Constantes y configuración global del addon
-- CAMBIOS v2.1:
--   • Añadidos EXPANSION_NAMES para todas las expansiones (future-proof)
--   • Añadidos SEASON_FINGERPRINTS para auto-detectar temporadas conocidas
--   • Añadidos ROLE_METRICS: qué métricas mostrar por rol
--   • Añadidos TRACKER_ROLES: qué trackers activar por rol
-- ===========================================================================

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus    = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local L = MitzuMPlus.L

MitzuMPlus.Constants = {

    -- -- Versión --------------------------------------------------------------
    -- FIX BUG-11: VERSION e INTERFACE_VERSION eliminadas de aquí - eran código
    -- muerto que nunca se leía. La versión real vive en MitzuMPlus.VERSION
    -- (asignada por Bootstrap.lua desde el .toc). La interfaz se declara en
    -- el propio .toc. Dejar copias aquí solo confundía.

    -- -- Límites de juego -----------------------------------------------------
    MAX_KEY_LEVEL   = 30,
    MIN_KEY_LEVEL   = 2,
    MAX_RUNS_STORED = 1000,
    DEFAULT_PAGE_SIZE = 20,

    -- -- Mejora de piedra -------------------------------------------------------
    -- Fraccion del limite de tiempo que da +2 / +3. Unica definicion: la usan
    -- KeystoneTracker (umbrales del motor de prediccion) y TrackerPresenter.
    KEY_UPGRADE_PLUS2_RATIO = 0.8,
    KEY_UPGRADE_PLUS3_RATIO = 0.6,

    -- -- Tiempos del sistema ---------------------------------------------------
    -- FIX BUG-3: En Lua, date("%w") devuelve 0=Dom,1=Lun,2=Mar,3=Mié,4=JUE.
    -- El valor anterior era 4 (Jueves). Corregido a 3 (Miércoles).
    -- Además se alinea con Database.RESET_HOUR (9). El 7 anterior era incorrecto
    -- Solo fallback para clientes sin C_DateAndTime.GetWeeklyResetStartTime.
    -- Retail usa siempre la API regional real; no depender de estos valores.
    WEEK_RESET_HOUR = 9,
    WEEK_RESET_WDAY = 3,

    -- -- Tracking -------------------------------------------------------------
    COMBAT_LOG_THROTTLE = 0.05,
    PEAK_DPS_WINDOW     = 10,   -- segundos para la ventana de pico
    PEAK_HEAL_WINDOW    = 10,
    PEAK_DTPS_WINDOW    = 10,

    -- -- UI -------------------------------------------------------------------
    TOAST_DURATION    = 3,
    SEARCH_DEBOUNCE   = 0.3,
    SLOT_COUNT        = 19,

    -- Contrato único de la ventana principal. El panel de Historial necesita
    -- este mínimo para mostrar filtros, tabla y detalle sin solapamientos.
    UI_WINDOW_MIN_WIDTH         = 1240,
    UI_WINDOW_MIN_HEIGHT        = 700,
    UI_HISTORIAL_DEFAULT_WIDTH  = 1280,
    UI_HISTORIAL_DEFAULT_HEIGHT = 760,
    UI_OVERLAY_DEFAULT_WIDTH    = 200,
    UI_OVERLAY_DEFAULT_HEIGHT   = 120,

    ROW_HEIGHT    = 26,
    HEADER_HEIGHT = 28,
    FOOTER_HEIGHT = 36,
    TITLEBAR_HEIGHT = 64,

    -- -- Roles -----------------------------------------------------------------
    ROLE_TANK    = "TANK",
    ROLE_HEALER  = "HEALER",
    ROLE_DAMAGER = "DAMAGER",

    -- -- Afijos conocidos (IDs de The War Within y anteriores) -----------------
    AFFIXES = {
        FORTIFIED  = 10,
        TYRANNICAL = 9,
        -- Temporada 1 TWW
        XALATATH_BARGAIN_ASCENDANT = 148,
        XALATATH_BARGAIN_VOIDBOUND = 149,
        XALATATH_BARGAIN_OBLIVION  = 150,
        XALATATH_BARGAIN_DEVOURED  = 151,
        -- Clásicos que rotan
        BOLSTERING   = 7,
        SANGUINE     = 8,
        RAGING       = 6,
        STORMING     = 124,
        SPITEFUL     = 123,
        VOLCANIC     = 3,
        BURSTING     = 11,
        GRIEVOUS     = 12,
        INSPIRING    = 122,
        ENTANGLING   = 158,
        INCORPOREAL  = 159,
        AFFLICTED    = 135,
    },

    -- ------------------------------------------------------------------------
    -- EXPANSIONES
    -- GetExpansionLevel() devuelve un número entero.
    -- Mantener este mapa actualizado al salir cada expansión.
    -- ------------------------------------------------------------------------
    EXPANSION_NAMES = {
        [0]  = "Classic",
        [1]  = "The Burning Crusade",
        [2]  = "Wrath of the Lich King",
        [3]  = "Cataclysm",
        [4]  = "Mists of Pandaria",
        [5]  = "Warlords of Draenor",
        [6]  = "Legion",
        [7]  = "Battle for Azeroth",
        [8]  = "Shadowlands",
        [9]  = "Dragonflight",
        [10] = "The War Within",
        [11] = "Midnight",          -- Expansión 11 (API-11 FIX: confirmado nombre oficial)
        [12] = "The Last Titan",    -- Expansión 12
        -- Añadir futuras expansiones aquí sin tocar otra lógica
    },

    -- ------------------------------------------------------------------------
    -- FINGERPRINTS DE TEMPORADAS CONOCIDAS
    -- Clave = IDs de mazmorras ordenados y concatenados con "_"
    -- Valor = { name = "...", key = "..." }
    --
    -- CÓMO AÑADIR UNA TEMPORADA NUEVA:
    --   1. Ejecutar /MitzuMPlus sync para abrir el panel de temporada.
    --   2. Activar debug mode: /MitzuMPlus debug (o en Config).
    --   3. El addon imprimirá en chat el fingerprint exacto al hacer RE-ESCANEAR.
    --   4. Copiar ese fingerprint aquí con el nombre de la temporada.
    -- ------------------------------------------------------------------------
    SEASON_FINGERPRINTS = {
        -- The War Within - Temporada 1 (8 mazmorras)
        -- Ara-Kara, City of Threads, Mists of Tirna Scithe, The Necrotic Wake
        -- Siege of Boralus, Grim Batol, The Dawnbreaker, The Stonevault
        ["507_1001_1002_1003_1004_1005_1006_1007"] = {
            key  = "tww_s1",
        },

        -- The War Within - Temporada 2 (actualizar cuando se anuncie)
        -- ["XXX_XXX_XXX..."] = { key = "tww_s2" },

        -- Dragonflight - Temporada 4 (referencia)
        ["12092_12095_12096_12097_12098_12099_12100_12101"] = {
            key  = "df_s4",
        },

        -- -- Midnight - Temporada 1 ---------------------------------------
        -- FIX BUG-7: Temporada 17 (Midnight S1). Los mapIDs exactos se deben
        -- obtener ejecutando /MitzuMPlus sync con debugMode = true. El addon
        -- imprimirá en chat la línea exacta a copiar aquí.
        -- PLACEHOLDER - reemplazar cuando se confirmen los IDs:
        -- ["XXXX_XXXX_XXXX_XXXX_XXXX_XXXX_XXXX_XXXX"] = {
        --     name = "Midnight - Temporada 1",
        --     key  = "midnight_s1",
        -- },
    },

    -- ------------------------------------------------------------------------
    -- MÉTRICAS POR ROL
    -- Define qué stats son relevantes para cada rol en los paneles de UI.
    -- NOTA: Actualmente no se leen dinámicamente - sirven como documentación
    -- y como fuente de verdad para futuras implementaciones de columnas por rol.
    -- ------------------------------------------------------------------------
    ROLE_METRICS = {
        DAMAGER = {
            primary   = { "damageTotal", "damagePeak10s" },
            secondary = { "deaths", "kicks", "dispels" },
            tank      = false,
            heal      = false,
        },
        HEALER = {
            primary   = { "healingTotal", "healingPeak", "healingAbsorbTotal" },
            secondary = { "healingOverheal", "healingCastEfficiency",
                          "healingBrezCount", "healingDispelCount",
                          "healingCrisisEvents", "healingCDUptimeSec" },
            tank      = false,
            heal      = true,
        },
        TANK = {
            primary   = { "tankDamageTakenTotal", "tankDamageMitigated",
                          "tankMitigationPct", "tankPeakDTPS10s" },
            secondary = { "tankAvoidEvents", "tankDefensiveUptimeSec",
                          "tankDefensiveUptimePct", "tankSelfHealTotal" },
            tank      = true,
            heal      = false,
        },
    },

    -- ------------------------------------------------------------------------
    -- TRACKERS A ACTIVAR POR ROL
    -- NOTA: Actualmente no se leen dinámicamente - sirven como documentación
    -- y referencia para inicializar trackers por rol en futuras versiones.
    -- Core.lua inicializa los tres trackers siempre por simplicidad.
    -- ------------------------------------------------------------------------
    TRACKER_ROLES = {
        DAMAGER = { dps = true,  heal = false, tank = false },
        HEALER  = { dps = true,  heal = true,  tank = false },
        TANK    = { dps = true,  heal = false, tank = true  },
    },
}

-- Alias corto para acceso rápido desde módulos
MitzuMPlus.EXPANSION_NAMES    = MitzuMPlus.Constants.EXPANSION_NAMES
MitzuMPlus.SEASON_FINGERPRINTS = MitzuMPlus.Constants.SEASON_FINGERPRINTS

-- -----------------------------------------------------------------------------
-- AUTO-LOGGER DE FINGERPRINT (debug mode)
-- FIX BUG-2 (CRÍTICO): Constants.lua carga ANTES que EventBus.lua en el TOC.
-- En este punto MitzuMPlus.EventBus es nil, así que el listener nunca se
-- registraba con la llamada directa que había antes.
-- Solución: se expone InstallFingerprintDebugListener() que Init.lua llama en
-- OnInitialize(), momento en que EventBus ya está garantizado.
-- -----------------------------------------------------------------------------
function MitzuMPlus:InstallFingerprintDebugListener()
    if not self.EventBus then return end
    if self._fingerprintListenerInstalled then return end

    self.EventBus:On("SEASON_SCAN_UPDATED", function(scanData)
        if not (MitzuMPlus.db and MitzuMPlus.db.profile and
                MitzuMPlus.db.profile.settings and
                MitzuMPlus.db.profile.settings.debugMode) then
            return
        end

        local fp = scanData and scanData.fingerprint
        if not fp or fp == "" then return end

        -- Sólo loguear si el fingerprint NO está ya registrado
        if MitzuMPlus.SEASON_FINGERPRINTS[fp] then return end

        local seasonNum = scanData.seasonNumber or scanData.seasonNum or "?"
        local expName   = scanData.expansionName or L["SEASON_UNKNOWN_EXP"]

        MitzuMPlus:Print(string.format(
            "|cFFe8b84a[Debug] New season fingerprint detected:|r\n" ..
            "  Expansion: %s  |  Season: %s\n" ..
            "  Copy this into Constants.lua -> SEASON_FINGERPRINTS:\n" ..
            '  ["%s"] = { key = "exp%s_s%s" },  -- %s / season %s',
            expName, tostring(seasonNum),
            fp,
            expName, tostring(seasonNum),
            tostring(scanData.expansionLevel or "?"), tostring(seasonNum)
        ))
    end, 10)  -- prioridad baja para no interferir con otros handlers

    self._fingerprintListenerInstalled = true
end
