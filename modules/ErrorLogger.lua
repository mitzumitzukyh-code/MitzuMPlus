-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - ErrorLogger (v2.1)
-- Sistema de logging de errores en producción.
--
-- QUÉ HACE:
--   • Intercepta el error handler global de WoW (seterrorhandler).
--   • Filtra sólo errores originados dentro de este addon.
--   • Persiste hasta MAX_ERRORS entradas en db.global.errorLog (SavedVariables).
--   • Expone /MitzuMPlus bugreport → abre el clipboard con el log completo.
--
-- POR QUÉ ES SEGURO:
--   • Siempre llama al handler original de WoW (el cuadro rojo sigue apareciendo).
--   • Usa pcall en toda operación que acceda a la DB para evitar errores recursivos.
--   • No se registra si seterrorhandler no existe (versiones antiguas del cliente).
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

-- ─────────────────────────────────────────────────────────────────────────────
-- CONFIGURACIÓN
-- ─────────────────────────────────────────────────────────────────────────────

local MAX_ERRORS      = 20      -- máximo de entradas de error guardadas
local MAX_DEBUG_EVENTS = 100     -- máximo de entradas de diagnóstico guardadas
local ADDON_ID_PATTERN = "MitzuMPlus"  -- cadena que debe aparecer en el error

-- ─────────────────────────────────────────────────────────────────────────────
-- MÓDULO
-- ─────────────────────────────────────────────────────────────────────────────

local ErrorLogger = {}
MitzuMPlus.ErrorLogger = ErrorLogger

-- ─────────────────────────────────────────────────────────────────────────────
-- UTILIDADES INTERNAS
-- ─────────────────────────────────────────────────────────────────────────────

-- Devuelve true si el mensaje de error pertenece a este addon.
local function IsOurError(msg)
    return type(msg) == "string" and msg:find(ADDON_ID_PATTERN, 1, true) ~= nil
end

-- Intenta obtener el nombre de la zona actual de forma segura.
local function GetSafeZone()
    if GetRealZoneText then
        local ok, zone = pcall(GetRealZoneText)
        if ok and zone and zone ~= "" then return zone end
    end
    return "desconocida"
end

-- Trunca un string a `max` caracteres añadiendo "…" si se corta.
local function Truncate(s, max)
    if type(s) ~= "string" then return tostring(s) end
    if #s <= max then return s end
    return s:sub(1, max) .. "…"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CORE: guardar un error en la DB
-- ─────────────────────────────────────────────────────────────────────────────

local function SaveError(msg)
    -- Acceso a la DB siempre dentro de pcall para evitar errores recursivos.
    local ok = pcall(function()
        if not (MitzuMPlus and MitzuMPlus.db and MitzuMPlus.db.global) then
            return
        end

        local g = MitzuMPlus.db.global

        -- Inicializar la tabla si no existe (puede pasar en la primera sesión).
        if type(g.errorLog) ~= "table" then
            g.errorLog = {}
        end

        local log = g.errorLog

        -- Evitar duplicados exactos consecutivos (mismo mensaje que el último).
        if log[#log] and log[#log].msg == msg then
            log[#log].count = (log[#log].count or 1) + 1
            log[#log].lastSeen = time and time() or 0
            return
        end

        -- Insertar nueva entrada.
        -- FIX BUG-16: antes se guardaba g.nextRunID (el PRÓXIMO ID a usar),
        -- lo que no correlacionaba con ningún run existente. Se usa el ID del
        -- run actualmente activo (db.char.lastRunID) o "?" si no hay run.
        local currentRunID = (MitzuMPlus.db and MitzuMPlus.db.char and
                              MitzuMPlus.db.char.lastRunID) or "?"
        table.insert(log, {
            id       = currentRunID,
            time     = time and time() or 0,
            msg      = Truncate(msg, 400),
            version  = MitzuMPlus.VERSION or "?",
            zone     = GetSafeZone(),
            count    = 1,
        })

        -- Rotar: mantener sólo las últimas MAX_ERRORS entradas.
        while #log > MAX_ERRORS do
            table.remove(log, 1)
        end
    end)

    -- Si el propio pcall falló (caso extremadamente raro), lo ignoramos
    -- silenciosamente para no generar un error dentro del error handler.
    if not ok then return end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- HOOK DEL ERROR HANDLER GLOBAL
-- ─────────────────────────────────────────────────────────────────────────────

function ErrorLogger:Install()
    if self._installed then return end

    -- seterrorhandler no existe en todos los clientes/versiones.
    if not seterrorhandler then
        if MitzuMPlus.Print then
            MitzuMPlus:Print("|cFF888888[ErrorLogger] seterrorhandler no disponible en este cliente.|r")
        end
        return
    end

    local originalHandler = geterrorhandler and geterrorhandler() or nil

    seterrorhandler(function(errorMsg)
        -- 1. Filtrar: sólo guardamos errores de nuestro addon.
        if IsOurError(errorMsg) then
            SaveError(errorMsg)

            -- Notificar al usuario en chat si debugMode está activo.
            local debugMode = MitzuMPlus.db and
                              MitzuMPlus.db.profile and
                              MitzuMPlus.db.profile.settings and
                              MitzuMPlus.db.profile.settings.debugMode
            if debugMode and MitzuMPlus.Print then
                MitzuMPlus:Print(string.format(
                    "|cFFee3333[ErrorLogger]|r Error guardado. " ..
                    "Usa |cFFf7d470/emp bugreport|r para copiarlo."
                ))
            end
        end

        -- 2. Siempre pasar al handler original (el cuadro rojo de WoW).
        if originalHandler then
            originalHandler(errorMsg)
        end
    end)

    self._installed = true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- BUGREPORT: formatea el log para el clipboard
-- ─────────────────────────────────────────────────────────────────────────────

function ErrorLogger:GetReport()
    if not (MitzuMPlus.db and MitzuMPlus.db.global) then
        return "[MitzuMPlus ErrorLogger] DB no disponible."
    end

    local log = MitzuMPlus.db.global.errorLog
    if not log or #log == 0 then
        return "[MitzuMPlus ErrorLogger] No hay errores registrados. ¡Todo en orden!"
    end

    local lines = {}
    table.insert(lines, string.format(
        "=== MitzuMPlus M+ Historial v%s — Bug Report ===",
        MitzuMPlus.VERSION or "?"
    ))
    table.insert(lines, string.format("Generado: %s", date and date("%Y-%m-%d %H:%M:%S") or "?"))
    table.insert(lines, string.format("Errores registrados: %d", #log))
    table.insert(lines, "")

    for i, entry in ipairs(log) do
        local ts = (entry.time and entry.time > 0)
                   and (date and date("%Y-%m-%d %H:%M:%S", entry.time) or tostring(entry.time))
                   or  "?"
        local countStr = (entry.count and entry.count > 1)
                         and string.format(" [x%d, último: %s]",
                             entry.count,
                             (entry.lastSeen and date and date("%H:%M:%S", entry.lastSeen)) or "?")
                         or ""
        table.insert(lines, string.format("[%d] %s  |  v%s  |  Zona: %s%s",
            i, ts, entry.version or "?", entry.zone or "?", countStr))
        table.insert(lines, entry.msg or "(sin mensaje)")
        table.insert(lines, "")
    end

    return table.concat(lines, "\n")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- LIMPIAR EL LOG
-- ─────────────────────────────────────────────────────────────────────────────

function ErrorLogger:Clear()
    if MitzuMPlus.db and MitzuMPlus.db.global then
        MitzuMPlus.db.global.errorLog = {}
    end
    if MitzuMPlus.Print then
        MitzuMPlus:Print("|cFF21de66[ErrorLogger] Log de errores limpiado.|r")
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- HELPERS PÚBLICOS
-- ─────────────────────────────────────────────────────────────────────────────

-- Devuelve cuántos errores hay guardados (0 si no hay DB).
function ErrorLogger:Count()
    if not (MitzuMPlus.db and MitzuMPlus.db.global and
            type(MitzuMPlus.db.global.errorLog) == "table") then
        return 0
    end
    return #MitzuMPlus.db.global.errorLog
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SISTEMA DE DIAGNÓSTICO (Debug Log)
-- Registra eventos de flujo de datos para diagnosticar problemas como:
--   • C_DamageMeter no devuelve datos → damageTotal=0
--   • Fuente de healingTotal (C_DamageMeter vs UNIT_COMBAT fallback)
--   • Secret values encontrados en datos del meter
--   • Matching de GUID/nombre que falla
-- ═══════════════════════════════════════════════════════════════════════════

-- Log a diagnostic event. category = string tag, msg = description, data = optional table
function ErrorLogger:LogEvent(category, msg, data)
    pcall(function()
        if not (MitzuMPlus and MitzuMPlus.db and MitzuMPlus.db.global) then return end
        local g = MitzuMPlus.db.global
        if type(g.debugLog) ~= "table" then
            g.debugLog = {}
        end

        local entry = {
            t   = time and time() or 0,
            cat = tostring(category or "GENERAL"),
            msg = Truncate(tostring(msg or ""), 300),
        }

        -- Flatten data table into entry for persistence (shallow, primitives only)
        if type(data) == "table" then
            local d = {}
            for k, v in pairs(data) do
                local tv = type(v)
                if tv == "number" or tv == "string" or tv == "boolean" then
                    d[tostring(k)] = v
                end
            end
            entry.data = d
        end

        table.insert(g.debugLog, entry)

        -- Rotar: mantener sólo las últimas MAX_DEBUG_EVENTS entradas
        while #g.debugLog > MAX_DEBUG_EVENTS do
            table.remove(g.debugLog, 1)
        end
    end)
end

-- Quick helper for chat-visible debug messages (only if debugMode is on)
function ErrorLogger:DebugPrint(msg)
    local debugMode = MitzuMPlus.db and
                      MitzuMPlus.db.profile and
                      MitzuMPlus.db.profile.settings and
                      MitzuMPlus.db.profile.settings.debugMode
    if debugMode and MitzuMPlus.Print then
        MitzuMPlus:Print("|cFF88CCFF[DEBUG]|r " .. tostring(msg))
    end
end

-- Generate a diagnostic report (like GetReport but for debug events)
function ErrorLogger:GetDebugReport()
    if not (MitzuMPlus.db and MitzuMPlus.db.global) then
        return "[MitzuMPlus DebugLog] DB no disponible."
    end

    local log = MitzuMPlus.db.global.debugLog
    if not log or #log == 0 then
        return "[MitzuMPlus DebugLog] No hay eventos de diagnóstico registrados."
    end

    local lines = {}
    table.insert(lines, string.format(
        "=== MitzuMPlus M+ Historial v%s — Debug Log ===",
        MitzuMPlus.VERSION or "?"
    ))
    table.insert(lines, string.format("Generado: %s", date and date("%Y-%m-%d %H:%M:%S") or "?"))
    table.insert(lines, string.format("Eventos: %d", #log))
    table.insert(lines, "")

    for i, entry in ipairs(log) do
        local ts = (entry.t and entry.t > 0)
                   and (date and date("%H:%M:%S", entry.t) or tostring(entry.t))
                   or "?"
        local line = string.format("[%s] [%s] %s", ts, entry.cat or "?", entry.msg or "")

        -- Append data fields if present
        if type(entry.data) == "table" then
            local parts = {}
            for k, v in pairs(entry.data) do
                parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
            end
            if #parts > 0 then
                line = line .. " | " .. table.concat(parts, ", ")
            end
        end

        table.insert(lines, line)
    end

    return table.concat(lines, "\n")
end

-- Clear the debug log
function ErrorLogger:ClearDebugLog()
    if MitzuMPlus.db and MitzuMPlus.db.global then
        MitzuMPlus.db.global.debugLog = {}
    end
    if MitzuMPlus.Print then
        MitzuMPlus:Print("|cFF21de66[ErrorLogger] Debug log limpiado.|r")
    end
end

-- Count debug events
function ErrorLogger:DebugCount()
    if not (MitzuMPlus.db and MitzuMPlus.db.global and
            type(MitzuMPlus.db.global.debugLog) == "table") then
        return 0
    end
    return #MitzuMPlus.db.global.debugLog
end
