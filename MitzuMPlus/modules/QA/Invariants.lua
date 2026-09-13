-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · QA/Invariants  —  lo que tiene que ser verdad a la vez
--
-- Cada invariante sale de la arquitectura real, no de un deseo:
--   · DungeonContext decide RUNNING solo con IsChallengeModeActive().
--   · RouteManager descarga la ruta al salir, y RouteProgress se resetea.
--   · RouteProgress no puede estar PREPARED/ACTIVE/COMPLETED sin ruta.
--   · El pull está dentro de la ruta.
--   · RunSession, una vez decidida la partida, anota cada cambio de pull.
--   · El HUD pinta el pull de RouteProgress.
--   · Ningún módulo de MitzuRouteArrows vive dentro del core.
--
-- Dos partes separadas a propósito:
--   Gather()        lee el estado en una tabla plana (con pcall por campo)
--   Evaluate(state) decide PASS/WARN/FAIL/SKIP. Es PURA: los bancos le pasan
--                   estados inconsistentes fabricados a mano.
--
-- WARN es para lo que puede ser transitorio y legítimo (una cuenta atrás, un
-- /reload en el que el cronómetro aún no ha llegado). FAIL es para lo que la
-- arquitectura no permite nunca.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local Inv = {}
MitzuMPlus.QAInvariants = Inv

Inv.EXPERIMENTAL_MODULES = {
    "RouteArrows", "NameplateAnchorProvider", "NameplateGenerations",
    "PullUnitResolver", "LiveEnemyResolver", "ArrowDemo", "ArrowDemoTelemetry",
    "GuidanceEngine", "RouteArrowPresenter",
    "EngagementEvidence", "UnitLinkEvidence", "CastEvidence", "AuraEvidence",
    "EventCastEvidence", "PackEvidence", "PhysicalGroupMetadata",
    "PhysicalGroupCorrelation", "MDTPhysicalGroupData",
    "RouteSignature", "ExecutionEpisodeTracker", "RoutePullCandidateScorer",
    "RouteAlignment",
}

local function call(obj, name, ...)
    if type(obj) ~= "table" or type(obj[name]) ~= "function" then return nil end
    local ok, a, b = pcall(obj[name], obj, ...)
    if not ok then return nil end
    return a, b
end

local function plain(v)
    local S = MitzuMPlus.QASafe
    if S and S.IsSecret(v) then return nil end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
    return nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- RECOGIDA
-- ─────────────────────────────────────────────────────────────────────────

function Inv:Gather()
    local st = {}
    local DC = MitzuMPlus.DungeonContext
    st.lifecycle       = plain(call(DC, "GetState"))
    st.challengeActive = plain(call(DC, "IsChallengeActive"))
    st.pendingActivationChecks = plain(DC and rawget(DC, "_pendingChecks"))

    local RP, RM = MitzuMPlus.RouteProgress, MitzuMPlus.RouteManager
    local route = call(RP, "GetRoute")
    st.routeState   = plain(call(RP, "GetState"))
    st.routePresent = type(route) == "table"
    st.routeID      = st.routePresent and plain(route.id) or nil
    st.pull         = plain(call(RP, "GetPullIndex"))
    st.pullCount    = plain(call(RP, "GetPullCount"))
    local active = call(RM, "GetActiveRoute")
    st.activeRouteID = type(active) == "table" and plain(active.id) or nil
    st.routeManagerAvailable = type(RM) == "table"

    local RS = MitzuMPlus.RunSession
    local snap = call(RS, "GetSnapshot")
    st.sessionDecided = plain(call(RS, "IsDecided"))
    st.snapshotExists = type(snap) == "table" and snap.startedAt ~= nil
    st.snapshotPull   = st.snapshotExists and plain(tonumber(snap.pullIndex)) or nil
    st.snapshotRouteID = st.snapshotExists and plain(snap.routeID) or nil

    local PN = MitzuMPlus.AdaptiveRoute and MitzuMPlus.AdaptiveRoute.PullNavigator
    st.navigatorPull  = plain(call(PN, "GetCurrentPull"))
    st.navigatorCount = plain(call(PN, "GetPullCount"))

    local HUD = MitzuMPlus.CoachHUD
    st.hudAvailable = type(HUD) == "table"
    st.hudVisible   = plain(call(HUD, "IsVisible"))
    st.hudPreview   = plain(call(HUD, "IsPreview"))
    st.hudDisplayedPull = plain(call(HUD, "GetDisplayedPull"))
    st.hudMode      = plain(call(HUD, "GetMode"))
    st.hudRecovering = plain(call(HUD, "IsRecovering"))

    local found = {}
    local AR = MitzuMPlus.AdaptiveRoute
    for _, name in ipairs(Inv.EXPERIMENTAL_MODULES) do
        if rawget(MitzuMPlus, name) ~= nil or (type(AR) == "table" and rawget(AR, name) ~= nil) then
            found[#found + 1] = name
        end
    end
    st.experimentalInCore = found

    local api = rawget(_G, "MitzuMPlusAPI")
    st.apiPresent = api ~= nil
    if api ~= nil then
        -- Sin intentar escribir: el proxy de solo lectura protege su metatabla
        -- (__metatable=false) y no guarda campos propios.
        local okMt, mt = pcall(getmetatable, api)
        st.apiReadOnly = okMt and mt == false and next(api) == nil
    end
    return st
end

-- ─────────────────────────────────────────────────────────────────────────
-- EVALUACIÓN (pura)
-- ─────────────────────────────────────────────────────────────────────────

local function res(id, result, detail) return { id = id, result = result, detail = detail or "" } end

function Inv:Evaluate(st)
    local out = {}
    local function add(r) out[#out + 1] = r end
    st = st or {}

    -- 1. Llave activa según el cliente => DungeonContext en RUNNING.
    if st.challengeActive == nil or st.lifecycle == nil then
        add(res("CHALLENGE_IMPLIES_RUNNING", "SKIP", "sin datos"))
    elseif st.challengeActive == true and st.lifecycle ~= "RUNNING" then
        -- La cuenta atrás y el sondeo tras CHALLENGE_MODE_START son legítimos.
        local transitorio = (tonumber(st.pendingActivationChecks) or 0) > 0
            or st.lifecycle == "RESET"
        add(res("CHALLENGE_IMPLIES_RUNNING", transitorio and "WARN" or "FAIL",
            "challengeActive=true lifecycle=" .. tostring(st.lifecycle)))
    else
        add(res("CHALLENGE_IMPLIES_RUNNING", "PASS"))
    end

    -- 2. RUNNING solo con la llave activa de verdad.
    if st.lifecycle == "RUNNING" and st.challengeActive == false then
        add(res("RUNNING_IMPLIES_CHALLENGE", "FAIL", "lifecycle=RUNNING challengeActive=false"))
    else
        add(res("RUNNING_IMPLIES_CHALLENGE", st.lifecycle == nil and "SKIP" or "PASS"))
    end

    -- 3. RouteProgress con estado de ruta => hay ruta.
    local conRuta = { PREPARED = true, ACTIVE = true, COMPLETED = true }
    if st.routeState == nil then
        add(res("ROUTE_STATE_HAS_ROUTE", "SKIP", "sin RouteProgress"))
    elseif conRuta[st.routeState] and not st.routePresent then
        add(res("ROUTE_STATE_HAS_ROUTE", "FAIL", "routeState=" .. st.routeState .. " route=nil"))
    else
        add(res("ROUTE_STATE_HAS_ROUTE", "PASS"))
    end

    -- 4. Pull dentro de la ruta.
    if st.routePresent and st.pull ~= nil then
        local n, c = tonumber(st.pull), tonumber(st.pullCount) or 0
        add(res("PULL_IN_RANGE", (n and n >= 1 and n <= c) and "PASS" or "FAIL",
            "pull=" .. tostring(st.pull) .. "/" .. tostring(st.pullCount)))
    else
        add(res("PULL_IN_RANGE", "SKIP", "sin ruta"))
    end

    -- 5. RouteProgress y RouteManager hablan de la misma ruta.
    if st.routePresent and st.routeManagerAvailable then
        if st.activeRouteID == nil then
            add(res("ROUTE_MATCHES_MANAGER", "WARN", "RouteProgress tiene ruta y RouteManager ninguna"))
        elseif st.activeRouteID ~= st.routeID then
            add(res("ROUTE_MATCHES_MANAGER", "FAIL",
                "progress=" .. tostring(st.routeID) .. " manager=" .. tostring(st.activeRouteID)))
        else
            add(res("ROUTE_MATCHES_MANAGER", "PASS"))
        end
    else
        add(res("ROUTE_MATCHES_MANAGER", "SKIP"))
    end

    -- 6. Fuera de la mazmorra no queda progreso de ruta.
    if st.lifecycle == "OUTSIDE" and st.routeState ~= nil and st.routeState ~= "INACTIVE" then
        add(res("OUTSIDE_NO_PROGRESS", "FAIL", "lifecycle=OUTSIDE routeState=" .. tostring(st.routeState)))
    else
        add(res("OUTSIDE_NO_PROGRESS", st.lifecycle == nil and "SKIP" or "PASS"))
    end

    -- 7. Llave corriendo con ruta => la ruta está ACTIVE.
    if st.lifecycle == "RUNNING" and st.routePresent then
        add(res("RUNNING_ROUTE_ACTIVE", st.routeState == "ACTIVE" and "PASS" or "WARN",
            "routeState=" .. tostring(st.routeState)))
    else
        add(res("RUNNING_ROUTE_ACTIVE", "SKIP"))
    end

    -- 8. Snapshot de la sesión sincronizado con la autoridad.
    if st.lifecycle == "RUNNING" and st.sessionDecided == true and st.snapshotExists
       and st.routePresent and st.snapshotRouteID == st.routeID then
        -- WARN y no FAIL: RunSession no anota si el cronómetro del servidor
        -- falta en ese instante (UpdatePull exige la huella), y es legítimo.
        add(res("SNAPSHOT_MATCHES_PULL", st.snapshotPull == st.pull and "PASS" or "WARN",
            "snapshotPull=" .. tostring(st.snapshotPull) .. " pull=" .. tostring(st.pull)))
    else
        add(res("SNAPSHOT_MATCHES_PULL", "SKIP", "sesión sin decidir o sin snapshot"))
    end

    -- 9. El HUD pinta el pull autoritativo.
    if st.hudVisible == true and st.hudRecovering == true then
        add(res("HUD_MATCHES_AUTHORITY", "SKIP", "HUD esperando la decision de RunSession"))
    elseif st.hudVisible == true and st.hudPreview ~= true and st.hudDisplayedPull ~= nil then
        add(res("HUD_MATCHES_AUTHORITY", st.hudDisplayedPull == st.pull and "PASS" or "FAIL",
            "displayed=" .. tostring(st.hudDisplayedPull) .. " authoritative=" .. tostring(st.pull)))
    elseif st.hudVisible == true and st.hudPreview ~= true and st.routePresent then
        add(res("HUD_MATCHES_AUTHORITY", "FAIL", "HUD visible sin pull pintado con ruta cargada"))
    else
        add(res("HUD_MATCHES_AUTHORITY", "SKIP", "HUD oculto o en preview"))
    end

    -- 10. La vista previa no convive con una llave real.
    if st.hudPreview == true and st.lifecycle == "RUNNING" then
        add(res("PREVIEW_NOT_DURING_RUN", "WARN", "preview activo con lifecycle=RUNNING"))
    else
        add(res("PREVIEW_NOT_DURING_RUN", "PASS"))
    end

    -- 11. El navegador de pulls sigue a RouteProgress (se sincroniza por evento).
    if st.routePresent and tonumber(st.navigatorCount) and st.navigatorCount > 0 and st.navigatorPull ~= nil then
        add(res("NAVIGATOR_FOLLOWS_PROGRESS", st.navigatorPull == st.pull and "PASS" or "WARN",
            "navigator=" .. tostring(st.navigatorPull) .. " progress=" .. tostring(st.pull)))
    else
        add(res("NAVIGATOR_FOLLOWS_PROGRESS", "SKIP", "sin ruta adaptativa indexada"))
    end

    -- 12. Ningún módulo experimental dentro del core.
    local found = type(st.experimentalInCore) == "table" and st.experimentalInCore or {}
    add(res("NO_ROUTEARROWS_IN_CORE", #found == 0 and "PASS" or "FAIL",
        #found > 0 and ("found=" .. table.concat(found, ",")) or ""))

    -- 13. La API pública existe y no admite escrituras.
    if st.apiPresent == nil then
        add(res("PUBLIC_API_READ_ONLY", "SKIP"))
    elseif not st.apiPresent then
        add(res("PUBLIC_API_READ_ONLY", "WARN", "MitzuMPlusAPI no publicada"))
    else
        add(res("PUBLIC_API_READ_ONLY", st.apiReadOnly == true and "PASS" or "FAIL"))
    end
    return out
end

function Inv:Summary(results)
    local c = { PASS = 0, WARN = 0, FAIL = 0, SKIP = 0 }
    for _, r in ipairs(results or {}) do c[r.result] = (c[r.result] or 0) + 1 end
    return c
end

return Inv
