-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · QA/BugReport  —  Bug Report V2
--
-- Un solo bloque de texto que se pueda copiar y pegar para diagnosticar una
-- prueba en vivo: build, contexto de la llave, ruta, sesión, HUD, Coach,
-- capacidades del cliente, invariantes, últimos hechos de la caja negra y
-- errores.
--
-- FAIL-SAFE: cada sección se construye en su propio pcall. Si RouteManager
-- devuelve nil, si el HUD está roto o si una SavedVariable está a medias, esa
-- sección dice ERROR y las demás salen igual. El informe NUNCA lanza.
--
-- COPY-SAFE: todo valor pasa por QASafe antes de entrar al texto. Un valor
-- secreto de Blizzard sale como SECRET; nada se concatena a ciegas.
--
-- PRIVADO: sin nombres de personaje, sin GUIDs, sin BattleTags, sin rutas
-- locales. El grupo sale como player/party1..party4 con clase y rol.
--
-- Inspirado en la idea de BugGrabber/BugSack (capturar y copiar), sin código
-- ni dependencia de ellos.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local BR = {}
MitzuMPlus.BugReport = BR

BR.REPORT_VERSION = 2
BR.RECENT_EVENTS  = 80
BR.MAX_ERRORS     = 10

-- Si QASafe no cargara, una versión mínima que no concatena valores raros.
local function S()
    return MitzuMPlus.QASafe or {
        Text = function(v)
            local t = type(v)
            if t == "string" or t == "number" or t == "boolean" then
                local ok, s = pcall(tostring, v)
                return ok and s:gsub("|", "/") or "UNAVAILABLE"
            end
            return v == nil and "nil" or ("<" .. t .. ">")
        end,
    }
end

local function call(obj, name, ...)
    if type(obj) ~= "table" then return nil, "MODULE_NIL" end
    if type(obj[name]) ~= "function" then return nil, "METHOD_NIL" end
    local r = { pcall(obj[name], obj, ...) }
    if not r[1] then return nil, "ERROR" end
    return r[2], r[3], r[4], r[5]
end

-- ─────────────────────────────────────────────────────────────────────────
-- SECCIONES
-- Cada una recibe `add(k, v)` y `line(texto)`. Nada más.
-- ─────────────────────────────────────────────────────────────────────────

local SECTIONS = {}

SECTIONS[#SECTIONS + 1] = { "BUILD", function(add)
    add("ReportVersion", BR.REPORT_VERSION)
    add("Addon", MitzuMPlus.VERSION)
    local ok, version, build, bdate, iface = pcall(GetBuildInfo)
    if ok then
        add("WoW", version); add("Build", build); add("BuildDate", bdate); add("Interface", iface)
    else
        add("WoW", "UNAVAILABLE")
    end
    local okL, loc = pcall(GetLocale)
    add("Locale", okL and loc or "UNAVAILABLE")
    local okD, when = pcall(date, "%Y-%m-%d %H:%M:%S")
    add("Generated", okD and when or "UNAVAILABLE")
    local API = rawget(_G, "MitzuMPlusAPI")
    add("PublicAPI", API and (select(2, pcall(function() return API.GetAPIVersion() end))) or "absent")
    -- Solo presencia de otros addons relevantes. No se lee nada de ellos.
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
    for _, name in ipairs({ "MitzuRouteArrows", "MythicDungeonTools" }) do
        local okA, loaded = pcall(isLoaded, name)
        add("addon." .. name, okA and (loaded and "loaded" or "absent") or "UNKNOWN")
    end
end }

SECTIONS[#SECTIONS + 1] = { "CONTEXT", function(add)
    local DC = MitzuMPlus.DungeonContext
    if not DC then add("DungeonContext", "MODULE_NIL") return end
    add("dungeonKey", call(DC, "GetDungeonKey"))
    add("dungeonName", call(DC, "GetDungeonName"))
    add("lifecycle", call(DC, "GetState"))
    add("previousState", rawget(DC, "_previousState"))
    add("lastTransition", rawget(DC, "_lastTransition"))
    add("lastEvent", rawget(DC, "_lastEvent"))
    add("challengeActive", call(DC, "IsChallengeActive"))
    add("challengeMapID", call(DC, "GetChallengeMapID"))
    add("keystoneLevel", call(DC, "GetKeystoneLevel"))
    add("identitySource", call(DC, "GetIdentitySource"))
    add("instanceMapID", call(DC, "GetInstanceMapID"))
    add("pendingActivationChecks", rawget(DC, "_pendingChecks"))
    local CC = MitzuMPlus.ChallengeClock
    add("clock.state", call(CC, "GetState"))
    add("clock.elapsed", call(CC, "GetElapsed"))
    add("clock.limit", call(CC, "GetTimeLimit"))
    add("clock.remaining", call(CC, "GetRemaining", false))
end }

SECTIONS[#SECTIONS + 1] = { "PLAYER", function(add)
    local PP = MitzuMPlus.PartyProfiler
    local specID, specName, role, specState = call(PP, "GetPlayerSpec")
    add("specID", specID); add("spec", specName); add("specRole", role); add("specState", specState)
    local okR, assigned = pcall(UnitGroupRolesAssigned, "player")
    add("assignedRole", okR and assigned or "UNAVAILABLE")
    local okC, _, classFile = pcall(UnitClass, "player")
    add("class", okC and classFile or "UNAVAILABLE")
end }

SECTIONS[#SECTIONS + 1] = { "PARTY", function(add)
    local PP = MitzuMPlus.PartyProfiler
    local members = call(PP, "GetMembers")
    if type(members) ~= "table" then add("members", "UNAVAILABLE") return end
    local lista = {}
    for _, m in pairs(members) do
        if type(m) == "table" then lista[#lista + 1] = m end
    end
    table.sort(lista, function(a, b) return tostring(a.unitToken) < tostring(b.unitToken) end)
    add("size", #lista)
    for _, m in ipairs(lista) do
        -- Token de unidad en vez de nombre o GUID: suficiente para diagnosticar.
        local token = type(m.unitToken) == "string" and m.unitToken:match("^%a+%d*$") or "unit?"
        add(token, string.format("class=%s role=%s spec=%s specState=%s",
            S().Text(m.classFile), S().Text(m.effectiveRole), S().Text(m.specID), S().Text(m.specState)))
    end
end }

SECTIONS[#SECTIONS + 1] = { "ROUTE", function(add)
    local RM, RP = MitzuMPlus.RouteManager, MitzuMPlus.RouteProgress
    local active = call(RM, "GetActiveRoute")
    add("routeID", type(active) == "table" and active.id or nil)
    add("routeName", type(active) == "table" and active.name or nil)
    add("source", call(RM, "GetLoadSource"))
    add("dataOrigin", type(active) == "table" and type(active.source) == "table" and active.source.dataOrigin or nil)
    add("state", call(RP, "GetState"))
    local pull, count = call(RP, "GetPullIndex"), call(RP, "GetPullCount")
    add("pull", S().Text(pull) .. "/" .. S().Text(count))
    add("progressRouteID", (function()
        local r = call(RP, "GetRoute"); return type(r) == "table" and r.id or nil end)())
    add("lastChangeReason", RP and rawget(RP, "_lastReason") or nil)
    local v = call(RM, "GetValidation")
    if type(v) == "table" and type(v.clones) == "table" then
        add("totalClones", v.clones.total); add("validClones", v.clones.valid)
        add("unresolvedClones", v.clones.unresolved)
        add("warnings", type(v.warnings) == "table" and #v.warnings or nil)
    end
    add("mdtRuntimeRequired", call(RM, "MDTRuntimeRequired"))
    add("savedRouteDataRequired", call(RM, "SavedRouteDataRequired"))
    local PN = MitzuMPlus.AdaptiveRoute and MitzuMPlus.AdaptiveRoute.PullNavigator
    add("navigator", S().Text(call(PN, "GetCurrentPull")) .. "/" .. S().Text(call(PN, "GetPullCount")))
end }

SECTIONS[#SECTIONS + 1] = { "SESSION", function(add)
    local RS, RP = MitzuMPlus.RunSession, MitzuMPlus.RouteProgress
    local snap = call(RS, "GetSnapshot")
    local exists = type(snap) == "table" and snap.startedAt ~= nil
    add("snapshotExists", exists)
    if exists then
        add("snapshotRouteID", snap.routeID); add("snapshotPull", snap.pullIndex)
        add("snapshotDungeonKey", snap.dungeonKey); add("snapshotKeystoneLevel", snap.keystoneLevel)
        add("snapshotLastChange", snap.lastChangeReason)
        local okAge, age = pcall(function() return time() - (tonumber(snap.updatedAt) or 0) end)
        add("snapshotAge", okAge and age or "UNAVAILABLE")
        local elapsed = call(RS, "ChallengeElapsed")
        local okD, delta = pcall(function()
            if not elapsed then return nil end
            return math.abs((time() - math.floor(elapsed)) - tonumber(snap.startedAt))
        end)
        add("fingerprintDelta", okD and delta or "UNAVAILABLE")
    end
    local _, matchReason = call(RS, "Evaluate")
    add("matchState", matchReason)
    add("restoreState", call(RS, "GetState"))
    add("restoreReason", call(RS, "GetReason"))
    add("waitingFor", call(RS, "GetWaitingFor"))
    add("decided", call(RS, "IsDecided"))
    add("recovered", call(RP, "WasRecovered"))
    add("recoveryOriginalPull", call(RP, "GetRecoveryPull"))
    add("lastRestoredPull", call(RS, "GetRestoredPull"))
end }

SECTIONS[#SECTIONS + 1] = { "HUD", function(add)
    local HUD = MitzuMPlus.CoachHUD
    if not HUD then add("CoachHUD", "MODULE_NIL") return end
    local s = call(HUD, "Settings") or {}
    add("enabled", s.enabled ~= false)
    add("visible", call(HUD, "IsVisible"))
    add("mode", call(HUD, "GetMode"))
    add("preview", call(HUD, "IsPreview"))
    add("displayedPull", call(HUD, "GetDisplayedPull"))
    add("authoritativePull", call(MitzuMPlus.RouteProgress, "GetPullIndex"))
    add("lastRefreshReason", call(HUD, "GetLastRefreshReason"))
    add("lastError", call(HUD, "GetLastError"))
    add("ticker", call(HUD, "IsTickerActive"))
    add("locked", s.locked == true); add("scale", s.scale); add("alpha", s.alpha)
    add("compact", s.compact == true); add("replaceClassic", s.replaceClassic ~= false)
    local classic = MitzuMPlus.OverlayFrame
    add("classicOverlayShown", classic and classic.IsShown and classic:IsShown() or false)
end }

SECTIONS[#SECTIONS + 1] = { "COACH", function(add)
    local run = rawget(_G, "MitzuMPlusCurrentRun")
    add("runActive", run ~= nil)
    local snap = run and call(MitzuMPlus.PredictionEngine, "GetSnapshot", run) or nil
    add("prediction", type(snap) == "table" and "AVAILABLE" or "NONE")
    if type(snap) == "table" then
        add("hasBasis", snap.hasBasis == true)
        add("result", snap.result); add("confidence", snap.confidence)
        local CA = MitzuMPlus.CoachAdvice
        local ok, a = false, nil
        if CA and CA.Evaluate then ok, a = pcall(CA.Evaluate, snap, { requireBasis = true }) end
        add("advice", ok and a and (a.key .. "/" .. a.severity .. "/" .. a.evidence) or "NONE")
    end
    local official = call(MitzuMPlus.KeystoneTracker, "GetOfficialSnapshot")
    if type(official) == "table" then
        add("enemyPct", official.enemyPct); add("enemyTotal", official.enemyTotal)
        add("enemySource", official.enemySource); add("deaths", official.deaths)
    end
end }

SECTIONS[#SECTIONS + 1] = { "CAPABILITIES", function(add, line)
    local RC = MitzuMPlus.RuntimeCapabilities
    local matrix = call(RC, "Matrix")
    if type(matrix) ~= "table" then add("RuntimeCapabilities", "UNAVAILABLE") return end
    for _, l in ipairs(matrix) do line(S().Text(l)) end
end }

SECTIONS[#SECTIONS + 1] = { "INVARIANTS", function(add, line)
    local Inv = MitzuMPlus.QAInvariants
    if not Inv then add("QAInvariants", "MODULE_NIL") return end
    local results = Inv:Evaluate(Inv:Gather())
    local c = Inv:Summary(results)
    line(string.format("summary PASS=%d WARN=%d FAIL=%d SKIP=%d", c.PASS, c.WARN, c.FAIL, c.SKIP))
    for _, r in ipairs(results) do
        line(string.format("%-4s %s%s", r.result, S().Text(r.id),
            (r.detail and r.detail ~= "") and (" ; " .. S().Text(r.detail)) or ""))
    end
end }

SECTIONS[#SECTIONS + 1] = { "RECENT EVENTS", function(add, line)
    local FR = MitzuMPlus.FlightRecorder
    if not FR then add("FlightRecorder", "MODULE_NIL") return end
    add("stored", S().Text(FR:Count()) .. "/" .. S().Text(FR:Capacity()))
    for _, l in ipairs(FR:Lines(BR.RECENT_EVENTS)) do line(S().Text(l, 260)) end
end }

SECTIONS[#SECTIONS + 1] = { "ERRORS", function(add, line)
    local EL = MitzuMPlus.ErrorLogger
    local entries = call(EL, "Entries")
    if type(entries) ~= "table" then add("ErrorLogger", "UNAVAILABLE") return end
    add("count", #entries)
    add("debugEvents", call(EL, "DebugCount"))
    local desde = math.max(1, #entries - BR.MAX_ERRORS + 1)
    for i = desde, #entries do
        local e = entries[i]
        if type(e) == "table" then
            local okT, ts = pcall(date, "%Y-%m-%d %H:%M:%S", tonumber(e.time) or 0)
            line(string.format("[%d] %s x%s v%s", i, okT and ts or "?", S().Text(e.count or 1),
                S().Text(e.version)))
            line("    " .. S().Text(e.msg, 400))
        else
            line(string.format("[%d] entrada corrupta (%s)", i, type(e)))
        end
    end
end }

BR.SECTIONS = SECTIONS

-- ─────────────────────────────────────────────────────────────────────────
-- CONSTRUCCIÓN
-- ─────────────────────────────────────────────────────────────────────────

-- Devuelve la lista de líneas y cuántas secciones fallaron.
function BR:BuildLines()
    local lines = { "=== MitzuMPlus Bug Report ===" }
    local failed = {}
    for _, sec in ipairs(SECTIONS) do
        local name, fn = sec[1], sec[2]
        lines[#lines + 1] = ""
        lines[#lines + 1] = "[" .. name .. "]"
        local buffer = {}
        local function add(k, v) buffer[#buffer + 1] = S().Text(k, 60) .. "=" .. S().Text(v) end
        local function line(t) buffer[#buffer + 1] = S().Text(t, 400) end
        local ok, err = pcall(fn, add, line)
        for _, l in ipairs(buffer) do lines[#lines + 1] = l end
        if not ok then
            failed[#failed + 1] = name
            lines[#lines + 1] = "SECTION_ERROR=" .. S().Text(err, 200)
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "sectionsFailed=" .. (#failed > 0 and table.concat(failed, ",") or "none")
    lines[#lines + 1] = "=== END ==="
    return lines, #failed
end

-- El informe entero. Nunca lanza.
function BR:Build()
    local ok, lines = pcall(self.BuildLines, self)
    if not ok then
        return "=== MitzuMPlus Bug Report ===\nREPORT_ERROR=" .. S().Text(lines, 200) .. "\n=== END ==="
    end
    return table.concat(lines, "\n")
end

-- Resumen para el chat, por si la caja de copia no pudiera abrirse.
function BR:SummaryLines()
    local out = {}
    local ok = pcall(function()
        local Inv = MitzuMPlus.QAInvariants
        local c = Inv and Inv:Summary(Inv:Evaluate(Inv:Gather())) or {}
        local DC, RP = MitzuMPlus.DungeonContext, MitzuMPlus.RouteProgress
        out[#out + 1] = string.format("v%s · lifecycle=%s · pull=%s/%s · route=%s",
            S().Text(MitzuMPlus.VERSION), S().Text(call(DC, "GetState")),
            S().Text(call(RP, "GetPullIndex")), S().Text(call(RP, "GetPullCount")),
            S().Text(call(RP, "GetState")))
        out[#out + 1] = string.format("invariants PASS=%s WARN=%s FAIL=%s · errors=%s · events=%s",
            S().Text(c.PASS), S().Text(c.WARN), S().Text(c.FAIL),
            S().Text(call(MitzuMPlus.ErrorLogger, "Count")),
            S().Text(MitzuMPlus.FlightRecorder and MitzuMPlus.FlightRecorder:Count()))
    end)
    if not ok then out[#out + 1] = "resumen no disponible" end
    return out
end

-- Abre el informe en la caja de copia. Si la UI falla, lo imprime.
function BR:Show()
    local text = self:Build()
    local shown = false
    local EX = MitzuMPlus.Export
    if EX and EX.CopyToClipboard then
        shown = pcall(EX.CopyToClipboard, EX, text, {
            title = "MITZUMPLUS · BUG REPORT",
            hint = "Ctrl+A y Ctrl+C para copiar todo. Pégalo tal cual en tu mensaje.",
            autoClose = false,
            mono = true,
            clearLabel = "LIMPIAR LOGS",
            onClear = function() BR:ClearLogs() end,
        })
    end
    if not shown and MitzuMPlus.Print then
        local lines = {}
        for l in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
        for i = 1, math.min(#lines, 60) do MitzuMPlus:Print(lines[i]) end
        if #lines > 60 then MitzuMPlus:Print("... (" .. (#lines - 60) .. " líneas más)") end
    end
    return shown, text
end

-- Limpia la caja negra y el log de errores. No toca SavedVariables de juego.
function BR:ClearLogs()
    if MitzuMPlus.FlightRecorder then MitzuMPlus.FlightRecorder:Clear() end
    local g = MitzuMPlus.db and MitzuMPlus.db.global
    if type(g) == "table" then g.errorLog = {} end
    return true
end

return BR
