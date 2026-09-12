-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · ArrowDemo v1.0  —  DEMO VISUAL, NO PRODUCCIÓN
--
-- UNA PREGUNTA DE EXPERIENCIA, NO DE IDENTIDAD:
--
--     "Si Mitzu supiera qué enemigo es cada placa, ¿cómo se sentiría jugar
--      una ruta entera guiado por flechas?"
--
-- Para responderla hacen falta flechas durante una llave completa. Y como
-- Midnight no deja saber qué enemigo es cada placa (GUID, npcID, tropas por
-- unidad y spellID llegan secretos), esas flechas se ponen con una
-- heurística visual. APROXIMADA. Que NO representa identidad.
--
-- ═════════════════════════════════════════════════════════════════════════
-- LO QUE ESTE MÓDULO NO TOCA, Y POR QUÉ ES UN PIPELINE APARTE
--
--   producción:  LiveEnemyResolver -> GuidanceEngine -> Presenter -> RouteArrows
--   demo:                           ArrowDemo       ------------->  RouteArrows
--
-- La demo no llama al resolver, ni a Guidance, ni al Presenter. No escribe
-- ningún estado de identidad, no produce la palabra MATCH en ningún sitio y
-- no mueve el pull: RouteProgress solo se LEE. Lo único que comparte con
-- producción es el pool de frames de RouteArrows, a través de su API pública.
--
-- PROPIEDAD DE LAS FLECHAS: la misma solución que ya usa el Presenter, un
-- registro propio (_marks). La demo solo retira las flechas que puso ella, y
-- CEDE cualquier placa que reclame producción (Presenter o anotaciones
-- manuales de PullUnitResolver). Producción nunca queda bloqueada por la demo.
-- ═════════════════════════════════════════════════════════════════════════
--
-- LA HEURÍSTICA (función pura Decide, abajo, con todas sus reglas):
--   · Fuera de una llave corriendo: ninguna flecha.
--   · Con combate (alguna placa ENGAGED): flecha sobre las placas enganchadas,
--     como mucho tantas como espera el pull (tope duro 12). Estables: una
--     flecha puesta no salta a otra placa porque cambie el orden.
--   · Sin combate: flecha sobre la placa a la que APUNTAS (softenemy o
--     target), si no está peleando. Es lo más cerca que se puede estar de
--     "el pack que vas a coger" sin posiciones de mobs.
--   · Gracia contra el parpadeo: una placa que deja de estar ENGAGED conserva
--     la flecha 1,5 s; una en UNKNOWN, 3 s. Nunca se AÑADE sobre UNKNOWN.
--
-- NUNCA DENTRO DE NAME_PLATE_UNIT_ADDED: RouteArrows libera en ese mismo
-- evento cualquier flecha que encuentre en el token, y el orden entre frames
-- no está garantizado. La demo marca en su propio tick.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local ArrowDemo = {}
AR.ArrowDemo = ArrowDemo

ArrowDemo.BANNER = "ARROW DEMO ACTIVO — asignación aproximada; no representa identidad."

-- ─────────────────────────────────────────────────────────────────────────
-- VOCABULARIO CERRADO
-- ─────────────────────────────────────────────────────────────────────────

local DEMO_CANDIDATE, DEMO_MARKED, DEMO_SKIPPED, DEMO_UNKNOWN =
      "DEMO_CANDIDATE", "DEMO_MARKED", "DEMO_SKIPPED", "DEMO_UNKNOWN"
ArrowDemo.STATES = {
    DEMO_CANDIDATE = DEMO_CANDIDATE, DEMO_MARKED = DEMO_MARKED,
    DEMO_SKIPPED = DEMO_SKIPPED, DEMO_UNKNOWN = DEMO_UNKNOWN,
}

local REASON_LIST = {
    -- por qué se quiere una flecha
    "ENGAGED_IN_EXECUTION", "POINTED_SOFTENEMY", "POINTED_TARGET",
    -- por qué se conserva
    "KEPT_ENGAGED", "GRACE_NOT_ENGAGED", "HOLD_UNKNOWN", "KEPT_POINTED",
    -- por qué se retira
    "NOT_ENGAGED_AFTER_GRACE", "UNKNOWN_TIMEOUT", "NO_LONGER_POINTED",
    "PHASE_EXECUTION", "NAMEPLATE_REMOVED", "GENERATION_CHANGED",
    "PULL_CHANGED", "CHALLENGE_END", "DEMO_OFF", "NOT_RUNNING",
    "ZONE_CHANGED", "PRODUCTION_TOOK_OVER", "STALE_TRACK", "ORPHAN_CLEANUP",
    -- por qué no se pone
    "OVER_CAP", "NO_GENERATION", "UNKNOWN_ENGAGEMENT",
    "PRODUCTION_OWNS", "ARROWS_DISABLED", "NO_PLATE",
    "ROUTE_ARROWS_MISSING", "MARK_FAILED",
}
ArrowDemo.REASONS = {}
for _, r in ipairs(REASON_LIST) do ArrowDemo.REASONS[r] = r end
local R = ArrowDemo.REASONS

-- Parámetros de la heurística. Todos visibles en /emp arrowdemo status.
ArrowDemo.PARAMS = {
    TICK              = 0.4,   -- segundos entre evaluaciones
    DEFAULT_CAP       = 6,     -- tope si el pull no dice cuántos espera
    HARD_CAP          = 12,    -- nunca más flechas simultáneas que esto
    GRACE_NOT_ENGAGED = 1.5,   -- s que dura una flecha tras dejar de pelear
    GRACE_UNKNOWN     = 3.0,   -- s que se sostiene una flecha en UNKNOWN
    POINT_GRACE       = 0.8,   -- s que se sostiene tras dejar de apuntarla
    IDLE_MAX          = 2,     -- flechas por apuntado, sin combate
    IDLE_POINTING     = true,
}
local P = ArrowDemo.PARAMS

-- Traducción de vocabularios ajenos. Se devuelve el valor de NUESTRA tabla,
-- nunca el que llegó (SEC-2: validar no es sanear).
local ENG_CANON  = { ENGAGED = "ENGAGED", NOT_ENGAGED = "NOT_ENGAGED", UNKNOWN = "UNKNOWN" }
local LINK_CANON = { SAME_UNIT = "SAME_UNIT", DIFFERENT_UNIT = "DIFFERENT_UNIT", UNKNOWN = "UNKNOWN" }
local function canon(v, tabla)
    if type(v) ~= "string" then return nil end
    local ok, res = pcall(function() return tabla[v] end)
    return ok and res or nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- ESTADO — nada de esto es identidad, y nada se guarda en SavedVariables
-- salvo la bandera enabled.
-- ─────────────────────────────────────────────────────────────────────────

ArrowDemo._enabled      = false
ArrowDemo._marks        = {}   -- [token] = { gen, reason, since, lastEngagedAt, ... }
ArrowDemo._firstEngaged = {}   -- [gen] = instante en que se vio ENGAGED por primera vez
ArrowDemo._wanted       = {}   -- [gen] = true: WANTED ya anotado
ArrowDemo._skipped      = {}   -- [gen] = reason: SKIPPED ya anotado
ArrowDemo._lastPlan     = nil
ArrowDemo._ticker       = nil
ArrowDemo._indicator    = nil
ArrowDemo._peak         = 0

local function T() return AR.ArrowDemoTelemetry end
local function NG() return AR.NameplateGenerations end
local function RA() return AR.RouteArrows end

local function ahora()
    local f = rawget(_G, "GetTime")
    if type(f) ~= "function" then return 0 end
    local ok, t = pcall(f)
    return (ok and type(t) == "number") and t or 0
end

local function log(code, fields)
    local tel = T()
    if tel then tel:Log(code, fields) end
end
local function count(key, n)
    local tel = T()
    if tel then tel:Count(key, n) end
end

function ArrowDemo:IsEnabled() return self._enabled == true end

-- ─────────────────────────────────────────────────────────────────────────
-- LA HEURÍSTICA — FUNCIÓN PURA
--
-- Entrada:
--   now          segundos (reloj local)
--   running      la llave está corriendo
--   expected     nº de enemigos que espera el pull (dato estático) o nil
--   obs          { { token, gen, engagement, pointed }, ... }
--                engagement: ENGAGED | NOT_ENGAGED | UNKNOWN
--                pointed:    SOFTENEMY | TARGET | nil
--   marks        flechas de la demo ahora mismo: [token] = meta
--   firstEngaged [gen] = instante del primer ENGAGED visto
--   blocked      [token] = true: placas con flecha de producción o ajena. No
--                cuentan para el tope: si no, una placa que la demo no puede
--                tocar le robaría el hueco a otra que sí.
--
-- Salida: un plan. No toca el cliente, ni RouteArrows, ni la telemetría.
--
-- REGLAS, EN ESTE ORDEN:
--   1. Sin llave corriendo -> se retira todo (NOT_RUNNING).
--   2. Una flecha cuyo ocupante ya no está -> fuera (NAMEPLATE_REMOVED) o, si
--      el token lo ocupa otro, fuera (GENERATION_CHANGED). Ninguna flecha
--      sobrevive a un cambio de generación.
--   3. Fase EXECUTION si hay alguna placa ENGAGED; IDLE si no.
--   4. Tope = lo que espera el pull (o 6), entre 1 y 12.
--   5. Flechas existentes: se conservan mientras sigan cumpliendo, con las
--      gracias de arriba. Primero se decide lo que ya hay: una flecha puesta
--      nunca se cambia por otra candidata nueva (estabilidad).
--   6. EXECUTION: nuevas sobre placas ENGAGED, por orden de primer enganche
--      y luego de generación, hasta el tope. El resto, DEMO_SKIPPED/OVER_CAP.
--   7. IDLE: nuevas sobre la placa apuntada (softenemy, luego target) si no
--      está peleando, hasta IDLE_MAX.
--   8. UNKNOWN nunca recibe una flecha nueva: DEMO_UNKNOWN.
-- ─────────────────────────────────────────────────────────────────────────

local function ordenado(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function copia(m)
    local n = {}
    for k, v in pairs(m) do n[k] = v end
    return n
end

-- Toda lectura de la entrada va por rawget: un objeto con __index hostil no
-- puede ejecutar nada aquí dentro. tonumber tampoco llama a metamétodos.
local function campo(t, k)
    if type(t) ~= "table" then return nil end
    return rawget(t, k)
end

function ArrowDemo:Decide(input)
    input = type(input) == "table" and input or {}
    local now = tonumber(campo(input, "now")) or 0
    local marks = campo(input, "marks")
    marks = type(marks) == "table" and marks or {}
    local first = campo(input, "firstEngaged")
    first = type(first) == "table" and first or {}
    local blocked = campo(input, "blocked")
    blocked = type(blocked) == "table" and blocked or {}
    local obsIn = campo(input, "obs")

    local plan = {
        phase = "INACTIVE", cap = 0,
        keep = {}, remove = {}, add = {}, skipped = {}, states = {},
        counts = { visible = 0, engaged = 0, notEngaged = 0, unknown = 0, candidates = 0 },
    }

    -- 1.
    if campo(input, "running") ~= true then
        for _, tok in ipairs(ordenado(marks)) do
            plan.remove[#plan.remove + 1] = { token = tok, gen = marks[tok].gen, reason = R.NOT_RUNNING }
        end
        return plan
    end

    local byTok = {}
    for _, o in ipairs(type(obsIn) == "table" and obsIn or {}) do
        local tok, gen = campo(o, "token"), campo(o, "gen")
        if type(tok) == "string" and type(gen) == "number" then
            local e = canon(campo(o, "engagement"), ENG_CANON) or "UNKNOWN"
            local pt = campo(o, "pointed")
            local p = (pt == "SOFTENEMY" and "SOFTENEMY") or (pt == "TARGET" and "TARGET") or nil
            byTok[tok] = { token = tok, gen = gen, engagement = e, pointed = p }
            plan.counts.visible = plan.counts.visible + 1
            if e == "ENGAGED" then plan.counts.engaged = plan.counts.engaged + 1
            elseif e == "NOT_ENGAGED" then plan.counts.notEngaged = plan.counts.notEngaged + 1
            else plan.counts.unknown = plan.counts.unknown + 1 end
        end
    end

    -- 3. y 4.
    plan.phase = (plan.counts.engaged > 0) and "EXECUTION" or "IDLE"
    local cap = tonumber(campo(input, "expected")) or P.DEFAULT_CAP
    if cap < 1 then cap = 1 end
    if cap > P.HARD_CAP then cap = P.HARD_CAP end
    plan.cap = cap

    -- 2. y 5.
    local kept = 0
    for _, tok in ipairs(ordenado(marks)) do
        local m, o = marks[tok], byTok[tok]
        if not o then
            plan.remove[#plan.remove + 1] = { token = tok, gen = m.gen, reason = R.NAMEPLATE_REMOVED }
        elseif o.gen ~= m.gen then
            plan.remove[#plan.remove + 1] = { token = tok, gen = m.gen, reason = R.GENERATION_CHANGED }
        else
            local nm = copia(m)
            if o.engagement == "ENGAGED" then nm.lastEngagedAt = now; nm.unknownSince = nil end
            if o.engagement ~= "UNKNOWN" then nm.unknownSince = nil end
            if o.pointed then nm.lastPointedAt = now end

            local conservar, motivo
            if o.engagement == "ENGAGED" then
                conservar, motivo = true, R.KEPT_ENGAGED
            elseif o.engagement == "UNKNOWN" then
                nm.unknownSince = nm.unknownSince or now
                if (now - nm.unknownSince) < P.GRACE_UNKNOWN then
                    conservar, motivo = true, R.HOLD_UNKNOWN
                else
                    motivo = R.UNKNOWN_TIMEOUT
                end
            elseif nm.lastEngagedAt and (now - nm.lastEngagedAt) < P.GRACE_NOT_ENGAGED then
                conservar, motivo = true, R.GRACE_NOT_ENGAGED
            elseif plan.phase == "EXECUTION" then
                -- Hay combate en otra parte y esta placa no pelea.
                motivo = nm.lastEngagedAt and R.NOT_ENGAGED_AFTER_GRACE or R.PHASE_EXECUTION
            elseif P.IDLE_POINTING and (o.pointed or (nm.lastPointedAt and
                   (now - nm.lastPointedAt) < P.POINT_GRACE)) then
                conservar, motivo = true, R.KEPT_POINTED
            else
                motivo = nm.lastEngagedAt and R.NOT_ENGAGED_AFTER_GRACE or R.NO_LONGER_POINTED
            end

            if conservar then
                nm.keepReason = motivo
                plan.keep[tok] = nm
                plan.states[tok] = DEMO_MARKED
                kept = kept + 1
            else
                plan.remove[#plan.remove + 1] = { token = tok, gen = m.gen, reason = motivo }
            end
        end
    end

    -- 8.
    for _, tok in ipairs(ordenado(byTok)) do
        local o = byTok[tok]
        if o.engagement == "UNKNOWN" and not plan.keep[tok] then
            plan.states[tok] = DEMO_UNKNOWN
            plan.skipped[#plan.skipped + 1] = { token = tok, gen = o.gen, reason = R.UNKNOWN_ENGAGEMENT }
        end
    end

    local candidatos = {}
    if plan.phase == "EXECUTION" then
        -- 6.
        for _, o in pairs(byTok) do
            if o.engagement == "ENGAGED" and not plan.keep[o.token] then
                candidatos[#candidatos + 1] = o
            end
        end
        table.sort(candidatos, function(a, b)
            local fa, fb = first[a.gen] or now, first[b.gen] or now
            if fa ~= fb then return fa < fb end
            return a.gen < b.gen
        end)
        for _, o in ipairs(candidatos) do
            if rawget(blocked, o.token) then
                plan.skipped[#plan.skipped + 1] = { token = o.token, gen = o.gen, reason = R.PRODUCTION_OWNS }
                plan.states[o.token] = DEMO_SKIPPED
            elseif kept + #plan.add < cap then
                plan.add[#plan.add + 1] = { token = o.token, gen = o.gen, reason = R.ENGAGED_IN_EXECUTION }
                plan.states[o.token] = DEMO_CANDIDATE
            else
                plan.skipped[#plan.skipped + 1] = { token = o.token, gen = o.gen, reason = R.OVER_CAP }
                plan.states[o.token] = DEMO_SKIPPED
            end
        end
    elseif P.IDLE_POINTING then
        -- 7.
        for _, o in pairs(byTok) do
            if o.pointed and o.engagement == "NOT_ENGAGED" and not plan.keep[o.token] then
                candidatos[#candidatos + 1] = o
            end
        end
        table.sort(candidatos, function(a, b)
            if a.pointed ~= b.pointed then return a.pointed == "SOFTENEMY" end
            return a.gen < b.gen
        end)
        for _, o in ipairs(candidatos) do
            if rawget(blocked, o.token) then
                plan.skipped[#plan.skipped + 1] = { token = o.token, gen = o.gen, reason = R.PRODUCTION_OWNS }
                plan.states[o.token] = DEMO_SKIPPED
            elseif kept + #plan.add < P.IDLE_MAX then
                plan.add[#plan.add + 1] = { token = o.token, gen = o.gen,
                    reason = (o.pointed == "SOFTENEMY") and R.POINTED_SOFTENEMY or R.POINTED_TARGET,
                    pointed = true }
                plan.states[o.token] = DEMO_CANDIDATE
            else
                plan.skipped[#plan.skipped + 1] = { token = o.token, gen = o.gen, reason = R.OVER_CAP }
                plan.states[o.token] = DEMO_SKIPPED
            end
        end
    end

    table.sort(plan.add, function(a, b) return a.token < b.token end)
    table.sort(plan.skipped, function(a, b) return a.token < b.token end)
    plan.counts.candidates = kept + #plan.add
    return plan
end

-- ─────────────────────────────────────────────────────────────────────────
-- PROPIEDAD
--
-- Producción reclama una placa si el Presenter la tiene registrada, o si
-- PullUnitResolver la ha resuelto (anotación manual del jugador). Solo se
-- LEEN sus API públicas.
-- ─────────────────────────────────────────────────────────────────────────

function ArrowDemo:ProductionClaims(token)
    local Pr = MitzuMPlus.RouteArrowPresenter
    if Pr and type(Pr.IsTracked) == "function" then
        local ok, v = pcall(Pr.IsTracked, Pr, token)
        if ok and v == true then return true end
    end
    local PUR = AR.PullUnitResolver
    if PUR and type(PUR.GetResolvedUnits) == "function" then
        local ok, lista = pcall(PUR.GetResolvedUnits, PUR)
        if ok and type(lista) == "table" then
            for _, t in ipairs(lista) do
                if t == token then return true end
            end
        end
    end
    return false
end

-- ─────────────────────────────────────────────────────────────────────────
-- APLICAR — el único sitio que toca RouteArrows
-- ─────────────────────────────────────────────────────────────────────────

local MARK_WHY = { ["sin placa visible"] = "NO_PLATE", ["desactivado"] = "ARROWS_DISABLED" }

-- Placas que la demo no debe intentar marcar: las que ya llevan una flecha
-- que no es suya (producción, /emp marktarget, /emp arrow).
function ArrowDemo:_Blocked(obs)
    local out = {}
    local ra = RA()
    for _, o in ipairs(obs) do
        local tok = o.token
        if not self._marks[tok] then
            local ajena = false
            if ra and type(ra.IsMarked) == "function" then
                local ok, v = pcall(ra.IsMarked, ra, tok)
                ajena = ok and v == true
            end
            if ajena or self:ProductionClaims(tok) then out[tok] = true end
        end
    end
    return out
end

-- Un rechazo se anota UNA vez por generación y motivo. Si no, una placa que
-- producción tiene marcada durante un combate largo escribiría una línea cada
-- 0,4 s y llenaría el buffer de la run.
ArrowDemo._rejected = {}
function ArrowDemo:_Reject(token, gen, reason)
    if self._rejected[gen] == reason then return false end
    self._rejected[gen] = reason
    log("DEMO_ARROW_REJECTED", { "token", token, "gen", gen, "reason", reason })
    count("demoRejections")
    return false
end

function ArrowDemo:_Mark(token, gen, reason, now, pointed)
    if not self._wanted[gen] then
        self._wanted[gen] = true
        log("DEMO_ARROW_WANTED", { "token", token, "gen", gen, "reason", reason })
        count("demoWanted")
    end

    local ra = RA()
    if not ra or type(ra.MarkUnit) ~= "function" then
        return self:_Reject(token, gen, R.ROUTE_ARROWS_MISSING)
    end
    -- Una flecha que no es nuestra en ese token: es de producción o manual.
    local ajena = false
    local okM, marcado = pcall(ra.IsMarked, ra, token)
    if okM and marcado == true and not self._marks[token] then ajena = true end
    if ajena or self:ProductionClaims(token) then
        return self:_Reject(token, gen, R.PRODUCTION_OWNS)
    end

    local stats = type(ra._stats) == "table" and ra._stats or {}
    local creadosAntes = tonumber(stats.created) or 0
    local okCall, ok, why = pcall(ra.MarkUnit, ra, token)
    if not okCall then
        local tel = T()
        if tel then tel:Error("MARK") end
        return self:_Reject(token, gen, R.MARK_FAILED)
    end
    if ok ~= true then
        return self:_Reject(token, gen, (type(why) == "string" and MARK_WHY[why]) or R.MARK_FAILED)
    end

    self._marks[token] = {
        gen = gen, reason = reason, since = now,
        lastEngagedAt = (reason == R.ENGAGED_IN_EXECUTION) and now or nil,
        lastPointedAt = pointed and now or nil,
    }
    local nuevo = (tonumber(stats.created) or 0) > creadosAntes
    log("DEMO_ARROW_APPLIED", { "token", token, "gen", gen, "reason", reason,
        "pool", nuevo and "NEW" or "REUSED" })
    count("demoPlacements")
    if not nuevo then
        log("DEMO_ARROW_REUSED", { "token", token, "gen", gen })
        count("demoReuses")
    end
    return true
end

-- Retira una flecha de la demo. Si producción reclama ya ese token, se suelta
-- el registro SIN desmarcar: la flecha es suya desde ese momento.
function ArrowDemo:_Unmark(token, reason, now)
    local m = self._marks[token]
    if not m then return false end
    self._marks[token] = nil
    local ra = RA()
    if self:ProductionClaims(token) then
        reason = R.PRODUCTION_TOOK_OVER
    elseif ra and type(ra.IsMarked) == "function" then
        local ok, marcado = pcall(ra.IsMarked, ra, token)
        if ok and marcado == true then pcall(ra.UnmarkUnit, ra, token) end
    end
    local held = (now and m.since) and math.floor((now - m.since) * 1000 + 0.5) or nil
    log("DEMO_ARROW_REMOVED", { "token", token, "gen", m.gen, "reason", reason,
        "heldMs", held or "-" })
    count("demoRemovals")
    return true
end

function ArrowDemo:_Apply(plan, now)
    for _, r in ipairs(plan.remove) do self:_Unmark(r.token, r.reason, now) end
    for tok, nm in pairs(plan.keep) do
        if self._marks[tok] then self._marks[tok] = nm end
    end
    for _, a in ipairs(plan.add) do self:_Mark(a.token, a.gen, a.reason, now, a.pointed) end
    for _, s in ipairs(plan.skipped) do
        if self._skipped[s.gen] ~= s.reason then
            self._skipped[s.gen] = s.reason
            log("DEMO_ARROW_SKIPPED", { "token", s.token, "gen", s.gen, "reason", s.reason })
            count("demoSkipped")
        end
    end
    local n = self:CountMarks()
    if n > self._peak then self._peak = n end
    local tel = T()
    if tel then tel:Max("demoPeakSimultaneous", n) end
end

function ArrowDemo:CountMarks()
    local n = 0
    for _ in pairs(self._marks) do n = n + 1 end
    return n
end

function ArrowDemo:GetMarks()
    local out = {}
    for tok, m in pairs(self._marks) do out[#out + 1] = { token = tok, gen = m.gen, reason = m.reason } end
    table.sort(out, function(a, b) return a.token < b.token end)
    return out
end

-- Retira TODAS las flechas de la demo, y comprueba que no quede ni una
-- huérfana en RouteArrows.
function ArrowDemo:_ClearAll(reason)
    local now = ahora()
    local tokens = ordenado(self._marks)
    for _, tok in ipairs(tokens) do self:_Unmark(tok, reason, now) end
    local ra = RA()
    if ra and type(ra.IsMarked) == "function" then
        for _, tok in ipairs(tokens) do
            local ok, sigue = pcall(ra.IsMarked, ra, tok)
            if ok and sigue == true and not self:ProductionClaims(tok) then
                pcall(ra.UnmarkUnit, ra, tok)
                log("ARROW_ORPHAN", { "token", tok, "reason", R.ORPHAN_CLEANUP })
                count("orphanArrowEvents")
            end
        end
    end
    return #tokens
end

-- ─────────────────────────────────────────────────────────────────────────
-- AUDITORÍA
--
-- Rápida (cada tick): lo que la demo cree tener, ¿lo tiene?
-- Lenta (cada snapshot): ¿hay flechas en RouteArrows sin dueño conocido? ¿El
-- pool cuadra?
-- ─────────────────────────────────────────────────────────────────────────

function ArrowDemo:_AuditFast(now)
    local ra = RA()
    if not ra then return end
    for _, tok in ipairs(ordenado(self._marks)) do
        if self:ProductionClaims(tok) then
            self:_Unmark(tok, R.PRODUCTION_TOOK_OVER, now)
        else
            local ok, marcado = pcall(ra.IsMarked, ra, tok)
            if ok and marcado ~= true then
                -- RouteArrows la soltó por su cuenta (p. ej. su propio
                -- NAME_PLATE_UNIT_ADDED). No hay nada que desmarcar.
                local m = self._marks[tok]
                self._marks[tok] = nil
                log("DEMO_ARROW_REMOVED", { "token", tok, "gen", m.gen, "reason", R.STALE_TRACK })
                count("demoRemovals")
                count("staleArrowEvents")
            end
        end
    end
end

ArrowDemo._lastPoolDelta = 0
function ArrowDemo:_AuditSlow()
    local ra = RA()
    if not ra then return end
    local st = type(ra._stats) == "table" and ra._stats or nil
    if st and type(ra.CountActive) == "function" then
        local ok, activos = pcall(ra.CountActive, ra)
        local delta = (tonumber(st.acquired) or 0) - (tonumber(st.released) or 0)
        if ok and type(activos) == "number" and delta ~= activos and delta ~= self._lastPoolDelta then
            self._lastPoolDelta = delta
            log("POOL_INCONSISTENCY", { "acquiredMinusReleased", delta, "active", activos })
            count("poolInconsistencies")
        end
    end
    -- Flechas en RouteArrows sobre placas que ya no se ven y que no reclama
    -- nadie: se informan, no se tocan. Si no son nuestras, no son nuestras.
    if type(ra._active) == "table" then
        local ng = NG()
        for tok in pairs(ra._active) do
            if type(tok) == "string" and ng and ng:Current(tok) == nil
               and not self._marks[tok] and not self:ProductionClaims(tok) then
                log("ARROW_ORPHAN", { "token", tok, "owner", "UNKNOWN" })
                count("orphanArrowEvents")
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- OBSERVACIÓN — lo que el tick le da a Decide
-- ─────────────────────────────────────────────────────────────────────────

local function runtimeState()
    local DC = MitzuMPlus.DungeonContext
    local ok, st = pcall(function() return DC and DC:GetState() end)
    return (ok and type(st) == "string") and st or "UNKNOWN"
end
ArrowDemo._runtimeState = runtimeState

local function visibles()
    if type(MitzuMPlus._VisibleNameplates) == "function" then
        local ok, l = pcall(MitzuMPlus._VisibleNameplates, MitzuMPlus)
        if ok and type(l) == "table" then return l end
    end
    return {}
end

local function engagementDe(tok)
    local EE = AR.EngagementEvidence
    if not EE or type(EE.Evaluate) ~= "function" then return "UNKNOWN" end
    local ok, v = pcall(EE.Evaluate, EE, tok)
    return (ok and canon(v, ENG_CANON)) or "UNKNOWN"
end

local function apuntadaDe(tok)
    local UL = AR.UnitLinkEvidence
    if not UL or type(UL.Evaluate) ~= "function" then return nil end
    for _, clase in ipairs({ "SOFTENEMY", "TARGET" }) do
        local ok, v = pcall(UL.Evaluate, UL, tok, clase)
        if ok and canon(v, LINK_CANON) == "SAME_UNIT" then return clase end
    end
    return nil
end

-- Señales adicionales para RouteAlignment. Solo se transportan estados
-- canónicos nuestros: nunca spellID, nombre de hechizo ni GUID. La demo no
-- consulta estos campos al decidir o aplicar flechas.
local function castDe(tok)
    local CE = AR.CastEvidence
    if not CE or type(CE.Evaluate) ~= "function" then return "UNKNOWN" end
    local ok, estado = pcall(CE.Evaluate, CE, tok)
    if not ok then return "UNKNOWN" end
    if estado == "CASTING" or estado == "CHANNELING" or estado == "NOT_CASTING" then
        return estado
    end
    return "UNKNOWN"
end

local function eventCastDe(tok)
    local ECE = AR.EventCastEvidence
    if not ECE or type(ECE.InspectToken) ~= "function" then return "NONE" end
    local ok, detalle = pcall(ECE.InspectToken, ECE, tok)
    if not ok or type(detalle) ~= "table" then return "NONE" end
    -- EventCastEvidence es únicamente una huella temporal de actividad. No
    -- se leen ni se copian safeSpellIDValue/spellIDState.
    if detalle.eventState == "SEEN" then
        return "RECENT_EVENT"
    end
    return "NONE"
end

local function esperados()
    local PE, RP = AR.PackEvidence, MitzuMPlus.RouteProgress
    if not (PE and RP) then return nil end
    local ok, n = pcall(function() return PE:ExpectedFromPull(RP:GetCurrentPull()) end)
    return (ok and type(n) == "number") and n or nil
end

function ArrowDemo:_Observe(now)
    local lista = visibles()
    local ng = NG()
    if ng then ng:Seed(lista) end
    local obs, enganchados = {}, 0
    for _, tok in ipairs(lista) do
        local gen = ng and ng:Current(tok) or nil
        if gen then
            local e = engagementDe(tok)
            local enlace = apuntadaDe(tok)
            local evento = eventCastDe(tok)
            if e == "ENGAGED" then
                enganchados = enganchados + 1
                if not self._firstEngaged[gen] then self._firstEngaged[gen] = now end
            end
            obs[#obs + 1] = {
                token = tok, gen = gen, engagement = e,
                castState = castDe(tok),
                recentEvent = evento,
                tokenLink = enlace,
            }
        end
    end
    -- Solo sin combate se pregunta a quién apuntas: con combate no se usa.
    if enganchados == 0 and P.IDLE_POINTING then
        for _, o in ipairs(obs) do o.pointed = o.tokenLink end
    end
    return obs
end

-- ─────────────────────────────────────────────────────────────────────────
-- TICK
-- ─────────────────────────────────────────────────────────────────────────

function ArrowDemo:_Tick()
    if not self._enabled then return end
    local tel = T()
    local running = runtimeState() == "RUNNING"

    if running and tel and not tel:IsRecording() then
        tel:StartSession(self._pendingReason or "DEMO_ON")
        self._pendingReason = nil
    end
    if not running then
        if next(self._marks) then self:_ClearAll(R.NOT_RUNNING) end
        if tel and tel:IsRecording() then tel:EndSession("NOT_RUNNING") end
        self._lastPlan = nil
        return
    end

    local now = ahora()
    -- Primero se reconcilia con lo que RouteArrows tiene DE VERDAD: así la
    -- decisión parte de la realidad y una flecha perdida vuelve en este mismo
    -- tick, no en el siguiente.
    self:_AuditFast(now)
    local obs = self:_Observe(now)
    if tel then tel:ObserveEngagement(obs) end
    -- FASE 4. Calle de un solo sentido: la capa de alineación MIRA lo mismo
    -- que mira la demo y no devuelve nada que pueda cambiar una flecha. Si
    -- revienta, la demo sigue: la inferencia es lo prescindible de los dos.
    local RAl = AR.RouteAlignment
    if RAl and RAl.Feed then
        if not pcall(RAl.Feed, RAl, obs, now) and tel then tel:Error("ALIGNMENT") end
    end
    local plan = self:Decide({
        now = now, running = true, expected = esperados(), obs = obs,
        marks = self._marks, firstEngaged = self._firstEngaged,
        blocked = self:_Blocked(obs),
    })
    self:_Apply(plan, now)
    self._lastPlan = plan
end

function ArrowDemo:SafeTick()
    local ok = pcall(self._Tick, self)
    if not ok then
        local tel = T()
        if tel then tel:Error("TICK") end
    end
    return ok
end

-- ─────────────────────────────────────────────────────────────────────────
-- ENCENDER / APAGAR
-- ─────────────────────────────────────────────────────────────────────────

local function imprimir(msg)
    if MitzuMPlus.Print then pcall(MitzuMPlus.Print, MitzuMPlus, msg) end
end

function ArrowDemo:_Indicator(show)
    if not self._indicator then
        if not show then return end
        if type(CreateFrame) ~= "function" or not rawget(_G, "UIParent") then return end
        local ok, f = pcall(function()
            local fr = CreateFrame("Frame", nil, UIParent)
            fr:SetSize(120, 18)
            fr:SetPoint("TOP", UIParent, "TOP", 0, -6)
            fr:SetFrameStrata("HIGH")
            local fs = fr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("CENTER")
            fs:SetText("ARROW DEMO")
            fs:SetTextColor(1, 0.6, 0.13)
            fr.text = fs
            return fr
        end)
        if not ok then return end
        self._indicator = f
    end
    if show then self._indicator:Show() else self._indicator:Hide() end
end

function ArrowDemo:_StartTicker()
    self:_StopTicker()
    local CT = rawget(_G, "C_Timer")
    if type(CT) == "table" and type(CT.NewTicker) == "function" then
        self._ticker = CT.NewTicker(P.TICK, function() ArrowDemo:SafeTick() end)
    end
end

function ArrowDemo:_StopTicker()
    if self._ticker and self._ticker.Cancel then pcall(self._ticker.Cancel, self._ticker) end
    self._ticker = nil
end

function ArrowDemo:_ResetState()
    self._firstEngaged, self._wanted, self._skipped, self._rejected = {}, {}, {}, {}
    self._lastPlan, self._peak = nil, 0
    -- Sin tick no hay observación, así que un episodio abierto se quedaría
    -- colgado hasta el siguiente evento de llave. Se cierra aquí.
    local RAl = AR.RouteAlignment
    if RAl and RAl.Reset then pcall(RAl.Reset, RAl, nil) end
end

-- silent: se reactiva tras un /reload, con un recordatorio en vez del cartel.
function ArrowDemo:SetEnabled(on, silent)
    local tel = T()
    if tel then tel:Store().enabled = on and true or false end

    if on then
        if self._enabled then return true end
        self._enabled = true
        self:_ResetState()
        self:_Indicator(true)
        self:_StartTicker()
        imprimir(silent and "|cFFff9922ARROW DEMO sigue activo|r (se desactiva con /emp arrowdemo off)."
                         or ("|cFFff9922" .. self.BANNER .. "|r"))
        self:SafeTick()
        return true
    end

    if not self._enabled then return false end
    self._enabled = false
    self:_ClearAll(R.DEMO_OFF)
    if tel and tel:IsRecording() then tel:EndSession("DEMO_OFF") end
    self:_StopTicker()
    self:_Indicator(false)
    self:_ResetState()
    imprimir("|cFF21de66ARROW DEMO desactivado.|r Vuelve el comportamiento normal.")
    return true
end

-- ─────────────────────────────────────────────────────────────────────────
-- CICLO DE VIDA DE LA LLAVE Y DE LAS PLACAS
-- ─────────────────────────────────────────────────────────────────────────

-- Tras un /reload, DungeonContext vuelve a pasar a RUNNING y emite otra vez
-- MITZU_KEY_STARTED. Si la sesión ya se reanudó, cerrarla aquí partiría la
-- run en dos. Una llave NUEVA no puede empezar sin que la anterior haya
-- pasado por COMPLETED, RESET o NOT_RUNNING, que ya cierran la sesión: por
-- eso, si hay sesión, se continúa.
function ArrowDemo:OnKeyStarted()
    if not self._enabled then return end
    local tel = T()
    if tel and not tel:IsRecording() then
        self:_ClearAll(R.NOT_RUNNING)
        self:_ResetState()
        tel:StartSession("KEY_STARTED")
    end
    self:SafeTick()
end

function ArrowDemo:OnKeyEnded(status)
    if not self._enabled then return end
    self:_ClearAll(R.CHALLENGE_END)
    local tel = T()
    if tel and tel:IsRecording() then
        tel:EndSession(status)
        imprimir("|cFFe8b84aArrow Demo:|r run guardada (" .. tostring(status) ..
                 "). Resumen: |cFFf7d470/emp arrowdemo report|r · copiar: |cFFf7d470/emp arrowdemo export|r")
    end
    self:_ResetState()
end

function ArrowDemo:OnPullChanged()
    if not self._enabled then return end
    self:_ClearAll(R.PULL_CHANGED)
    self._wanted, self._skipped, self._rejected = {}, {}, {}
    self:SafeTick()
end

function ArrowDemo:OnGeneration(kind, token, gen, prevGen)
    if kind == "RESET" then
        if next(self._marks) then self:_ClearAll(R.ZONE_CHANGED) end
        self._firstEngaged, self._wanted, self._skipped, self._rejected = {}, {}, {}, {}
        return
    end
    if (kind == "REMOVED" or kind == "REPLACED") and type(token) == "string" then
        local m = self._marks[token]
        if m then
            self:_Unmark(token, (kind == "REMOVED") and R.NAMEPLATE_REMOVED or R.GENERATION_CHANGED, ahora())
        end
        if prevGen then
            self._firstEngaged[prevGen], self._wanted[prevGen] = nil, nil
            self._skipped[prevGen], self._rejected[prevGen] = nil, nil
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- INFORME
-- ─────────────────────────────────────────────────────────────────────────

function ArrowDemo:StatusLines()
    local tel = T()
    local plan = self._lastPlan
    local L = {
        "|cFFe8b84a--- arrow demo ---|r",
        "enabled=" .. (self._enabled and "true" or "false") ..
            " recording=" .. ((tel and tel:IsRecording()) and "true" or "false") ..
            " runtime=" .. runtimeState(),
        "t=" .. ((tel and tel:IsRecording()) and tel.FormatTime(tel:NowMs()) or "-") ..
            " phase=" .. (plan and plan.phase or "-") .. " cap=" .. (plan and plan.cap or "-"),
        "demoArrows=" .. self:CountMarks() .. " peak=" .. self._peak ..
            " candidates=" .. (plan and plan.counts.candidates or 0),
        "visible=" .. (plan and plan.counts.visible or 0) ..
            " engaged=" .. (plan and plan.counts.engaged or 0) ..
            " notEngaged=" .. (plan and plan.counts.notEngaged or 0) ..
            " unknown=" .. (plan and plan.counts.unknown or 0),
        string.format("params: tick=%.1fs cap=%d/%d grace=%.1fs unknownHold=%.1fs idlePointing=%s",
            P.TICK, P.DEFAULT_CAP, P.HARD_CAP, P.GRACE_NOT_ENGAGED, P.GRACE_UNKNOWN,
            P.IDLE_POINTING and "on" or "off"),
    }
    if tel then
        local lim = tel.LIMITS
        L[#L + 1] = string.format("limits: runs=%d events=%d casts=%d snapshots=%d cada %ds · guardadas=%d",
            lim.MAX_RUNS, lim.MAX_EVENTS, lim.MAX_CAST_EVENTS, lim.MAX_SNAPSHOTS,
            lim.SNAPSHOT_INTERVAL, #tel:Store().runs)
    end
    L[#L + 1] = "|cFF999999(asignación aproximada: no es identidad, no es MATCH de ruta)|r"
    return L
end

-- ─────────────────────────────────────────────────────────────────────────
-- CABLEADO — todo registrado al cargar, apagado con la bandera _enabled.
-- ─────────────────────────────────────────────────────────────────────────

local tel = T()
if tel and tel.SetSnapshotProvider then
    tel:SetSnapshotProvider(function()
        ArrowDemo:_AuditSlow()
        local plan = ArrowDemo._lastPlan
        local c = plan and plan.counts or {}
        return {
            visible = c.visible or 0, engaged = c.engaged or 0,
            notEngaged = c.notEngaged or 0, unknown = c.unknown or 0,
            candidates = c.candidates or 0, arrows = ArrowDemo:CountMarks(),
        }
    end)
end

local ng = NG()
if ng and ng.Subscribe then
    ng:Subscribe(function(kind, token, gen, prevGen)
        if not ArrowDemo._enabled then return end
        local ok = pcall(ArrowDemo.OnGeneration, ArrowDemo, kind, token, gen, prevGen)
        if not ok and T() then T():Error("GENERATION") end
    end)
end

if MitzuMPlus.EventBus then
    local bus = MitzuMPlus.EventBus
    local function seguro(fn, donde)
        return function(...)
            if not ArrowDemo._enabled then return end
            local ok = pcall(fn, ArrowDemo, ...)
            if not ok and T() then T():Error(donde) end
        end
    end
    bus:On("MITZU_KEY_STARTED",   seguro(ArrowDemo.OnKeyStarted, "KEY_STARTED"), 30)
    bus:On("MITZU_KEY_COMPLETED", seguro(function(self) self:OnKeyEnded("COMPLETED") end, "KEY_COMPLETED"), 30)
    bus:On("MITZU_KEY_RESET",     seguro(function(self) self:OnKeyEnded("RESET") end, "KEY_RESET"), 30)
    bus:On("MITZU_PULL_CHANGED",  seguro(ArrowDemo.OnPullChanged, "PULL_CHANGED"), 30)
end

-- Tras un /reload el SavedVariable ya está cargado en PLAYER_ENTERING_WORLD:
-- si la demo estaba encendida, se reactiva (con aviso, nunca en silencio).
if type(CreateFrame) == "function" then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function()
        local t = T()
        if t and t:Store().enabled == true and not ArrowDemo._enabled then
            pcall(ArrowDemo.SetEnabled, ArrowDemo, true, true)
        end
    end)
    ArrowDemo._frame = frame
end

return ArrowDemo
