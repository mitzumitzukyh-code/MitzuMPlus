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
    },
    profile = {
        shareData = false,
        routes = {},
        settings = {
            -- v6.8.0: medicion de exactitud de la prediccion. Local, barata
            -- (una lectura cada 5 s) y guarda 12 numeros por llave completada.
            -- Nivel de interfaz: "PRO" (denso, datos) o "LEARN" (dice que
            -- hacer y explica cada numero). PRO por defecto para no cambiarle
            -- la interfaz a quien ya tenia el addon instalado.
            uiLevel = "PRO",
            calibrationEnabled = true,
            -- LibSharedMedia (opcional): nombre de fuente elegido por el
            -- usuario. nil = la del tema. Si LSM no esta instalada o la
            -- fuente desaparece, se cae al tema sin avisar.
            uiFont = nil,
            minimapIcon      = { hide = false },
            showToasts       = true,
            pageSize         = 20,
            defaultTab       = "historial",
            windowOpacity    = 1.0,
            windowWidth      = nil,
            windowHeight     = nil,
            rememberPosition = true,
            closeWithEscape  = true,
            showWatermark    = true,
            showResizeHandle = true,
            enableAnimations = true,
            windowLocked     = false,
            windowScale      = 1.0,
            -- Escala independiente del texto de la UI. 115% evita que los
            -- captions/tablas queden microscópicos con UI Scale de WoW.
            textScale        = 1.15,
            debugMode        = false,

            -- FIX BUG-7: overlay settings ausentes de los defaults.
            -- Sin estos, db:ResetProfile() los descarta y la posición/visibilidad
            -- del overlay no se restaura correctamente.
            overlayEnabled   = true,
            autoTrackOnEnter = false,
            coachEnabled     = true,
            coachAnchorBlizzard = true,
            -- COMPLEMENT conserva el tracker oficial (predeterminado seguro).
            -- REPLACE lo sustituye visualmente; COMPACT reduce el Coach.
            coachDisplayMode = "COMPLEMENT",
            -- v5.4.3: escala del overlay del Coach (0.7 - 2.0). El tamano base
            -- de 250x104 con fuentes *Small resultaba ilegible en pantallas
            -- grandes; ahora la base es 320x134 y esto lo ajusta por usuario.
            coachScale       = 1.0,
            -- v5.4.4: con el Coach bloqueado se desactiva EnableMouse, asi que
            -- no intercepta ningun clic sobre el mundo durante la llave.
            coachLocked      = false,

            -- ── v5.5.0: aspecto del Coach ─────────────────────────────────
            -- Sin fondo el texto lleva contorno negro y colores saturados. Se
            -- lee sobre el mundo sin tapar la mazmorra con un rectangulo negro.
            coachTransparent      = true,
            -- Lineas opcionales del Coach en vivo.
            coachShowPace         = true,   -- ritmo real vs ritmo necesario
            coachShowClock        = true,   -- reloj y tiempo restante
            coachShowDeathBudget  = true,   -- cuantas muertes mas caben

            -- ── v7.14.0: Coach HUD V2 (modules/CoachHUD.lua) ──────────────
            -- Vista principal durante la llave. replaceClassic evita tener el
            -- overlay clasico del Coach duplicado en pantalla; overlayEnabled
            -- y el resto de ajustes del Coach NO se tocan.
            hud = {
                enabled        = true,
                locked         = false,
                scale          = 1.0,
                alpha          = 1.0,
                compact        = false,
                showPreKey     = true,
                replaceClassic = true,
            },

            routeAutoLearn   = true,
            predictionEnabled = true,

            -- ── Tracking por rol ──────────────────────────────────────────
            tracking = {
                -- DPS / general
                damage      = true,
                damageSplit = true,
                peakDPS     = true,

                -- Healer
                healing     = true,
                healingBreakdown = true,
                peakHPS     = true,

                -- Tank
                damageTaken      = true,
                mitigation       = true,
                peakDTPS         = true,
                defensiveUptime  = true,
                avoidance        = true,

                -- Comunes
                deaths      = true,
                interrupts  = true,
                dispels     = true,
                equipment   = true,
                timeline    = true,
                groupComp   = true,
            },

            -- ── Qué columnas mostrar en el historial ──────────────────────
            visibleColumns = {
                dps          = true,
                deaths       = true,
                kicks        = true,
                dispels      = true,
                ilvl         = true,
                role         = true,
                -- Columnas de tank (visibles si el personaje es tank)
                tankDtps     = true,
                tankMitPct   = true,
                -- Columnas de healer
                healHps      = true,
                overhealPct  = true,
            },

            -- ── Alertas ─────────────────────────────────────────────────────
            alerts = {
                onDeath      = true,
                onComplete   = true,
                onBossKill   = true,
                timeWarning  = 5,
            },

            notifyPersonalBest  = true,
            shareData           = false,
        },

        position = {
            point         = "TOPLEFT",
            relativePoint = "BOTTOMLEFT",
            x = nil,
            y = nil,
        },
        -- FIX BUG-7: posición del overlay al nivel profile (no dentro de settings)
        -- para que AceDB lo persista y lo restaure en ResetProfile correctamente.
        -- v5.4.4: la posicion manual del Coach. `point` se rellena al arrastrar;
        -- mientras sea nil se usa la posicion por defecto.
        overlayPosition = {
            point    = nil,
            relPoint = nil,
            x = -20,
            y = -100,
        },
    },
    char = {
        lastRunID               = nil,
    },
}
