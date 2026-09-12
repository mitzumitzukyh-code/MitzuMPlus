-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · EngagementEvidence v1.0  —  FASE 3, EVIDENCIA
--
-- UNA SOLA PREGUNTA: ¿hay alguien del grupo enganchado con esta placa?
--
-- Nada más. No sabe qué es un pull, ni una ruta, ni un npcID. No conoce
-- RouteProgress, GuidanceEngine, RouteArrows, MDT ni DungeonContext, y no debe
-- conocerlos nunca: en el momento en que esto mire la ruta deja de ser una
-- evidencia y pasa a ser una decisión, que es trabajo de otro fichero.
--
-- ═════════════════════════════════════════════════════════════════════════
-- LA REGLA QUE MANDA: ENGAGED NO ES MATCH
--
-- Que un mob esté pegándose con el grupo NO dice qué mob es. Dice que hay
-- combate con él. Son dos preguntas distintas, y confundirlas es exactamente
-- el falso positivo que hundió a [SKIP]: "está en combate, luego es del pull".
-- No. Un pack de patrulla que se te viene encima está ENGAGED y no es del
-- pull; un mob del pull que aún no has tocado está NOT_ENGAGED y sí lo es.
--
-- Y al revés, con más cuidado todavía:
--     NOT_ENGAGED  NO significa NO_MATCH.
--     NOT_ENGAGED  significa "ahora mismo nadie le está haciendo threat".
-- Es AUSENCIA de evidencia, no evidencia de ausencia.
-- ═════════════════════════════════════════════════════════════════════════
--
-- POR QUÉ UnitThreatSituation Y NO UnitDetailedThreatSituation
-- Solo hace falta saber si hay enganche, no cuánto. La versión detallada
-- devuelve porcentajes y threatValue: más superficie secreta a cambio de un
-- dato que no se usa. Cuando algo no se necesita, no se pide.
--
-- VALORES SECRETOS
-- El número de threat NO SALE DE AQUÍ. Se lee, se comprueba con issecretvalue,
-- se clasifica contra literales de este fichero y se tira. Lo que cruza la
-- frontera son tres constantes escritas más abajo, nunca un valor de unidad.
-- Si un valor no se puede DEMOSTRAR seguro, se trata como secreto: la guarda
-- falla CERRADA, que es la lección del BUG SEC-2.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local EngagementEvidence = {}
AR.EngagementEvidence = EngagementEvidence

-- ─────────────────────────────────────────────────────────────────────────
-- VOCABULARIO CERRADO
--
-- Constantes DE ESTE FICHERO. No son el estado que devolvió ninguna API: son
-- literales nuestros que se devuelven DESPUÉS de comparar. Validar un valor y
-- luego transportarlo sigue siendo transportarlo (SEC-2).
-- ─────────────────────────────────────────────────────────────────────────

local ENGAGED, NOT_ENGAGED, UNKNOWN = "ENGAGED", "NOT_ENGAGED", "UNKNOWN"

EngagementEvidence.STATES = {
    ENGAGED = ENGAGED, NOT_ENGAGED = NOT_ENGAGED, UNKNOWN = UNKNOWN,
}

-- Las cinco fuentes, en orden. Tokens simples: ni targettarget, ni
-- partyXtarget, ni bossX. Un token compuesto es una pregunta sobre OTRA
-- unidad, y aquí solo se pregunta por la nuestra.
local SOURCES = { "player", "party1", "party2", "party3", "party4" }
EngagementEvidence.SOURCES = SOURCES

-- ─────────────────────────────────────────────────────────────────────────
-- LECTURA SEGURA
--
-- Copiada a propósito en vez de importada: este módulo no depende de ningún
-- otro, y esa independencia vale más que veinte líneas ahorradas.
-- ─────────────────────────────────────────────────────────────────────────

-- ¿Se puede DEMOSTRAR que este valor es seguro de tocar? Ante cualquier duda,
-- no. Sin la API del cliente tampoco: no poder comprobarlo no es serlo.
local function esValorSeguro(v)
    if v == nil then return true end
    local t = type(v)
    if t ~= "string" and t ~= "number" and t ~= "boolean" then return false end
    local iss = rawget(_G, "issecretvalue")
    if type(iss) ~= "function" then return false end
    local ok, res = pcall(iss, v)
    if not ok then return false end
    return res ~= true
end

-- Devuelve un ESTADO de lectura, y el valor SOLO si es seguro tocarlo.
--   AVAILABLE   -> valor legible
--   UNKNOWN     -> la API contestó nil, y ese nil es un dato
--   SECRET      -> secreto, o no demostrablemente seguro
--   UNAVAILABLE -> no hay API, o reventó
local function leer(fn, ...)
    if type(fn) ~= "function" then return "UNAVAILABLE", nil end
    local ok, v = pcall(fn, ...)
    if not ok then return "UNAVAILABLE", nil end
    if v == nil then return "UNKNOWN", nil end
    if not esValorSeguro(v) then return "SECRET", nil end
    return "AVAILABLE", v
end

-- ¿Existe esta unidad? true / false / nil (no demostrable).
local function existeSeguro(unit)
    local st, v = leer(rawget(_G, "UnitExists"), unit)
    if st ~= "AVAILABLE" then
        -- Un nil seguro de UnitExists es un "no existe" legítimo.
        if st == "UNKNOWN" then return false end
        return nil
    end
    if type(v) ~= "boolean" then return nil end
    return v
end

-- ─────────────────────────────────────────────────────────────────────────
-- UNA FUENTE CONTRA UNA PLACA
--
-- Este es el único sitio donde se toca el número de threat, y solo para
-- clasificarlo. 0, 1, 2 y 3 son todos ENGAGED: la diferencia entre ellos es
-- quién lleva la aggro, y eso aquí no importa.
-- ─────────────────────────────────────────────────────────────────────────

function EngagementEvidence:EvaluateSource(sourceUnit, unitToken)
    if type(sourceUnit) ~= "string" or type(unitToken) ~= "string" then
        return UNKNOWN
    end

    local API = rawget(_G, "UnitThreatSituation")
    if type(API) ~= "function" then return UNKNOWN end

    local st, v = leer(API, sourceUnit, unitToken)

    -- Sin threat table: la unidad no está enganchada con esta fuente. Es la
    -- respuesta normal del cliente para un mob que nadie ha tocado.
    if st == "UNKNOWN" then return NOT_ENGAGED end

    -- Secreto, o la llamada reventó, o no hay con qué comprobarlo: no lo
    -- sabemos, y decirlo es la respuesta correcta.
    if st ~= "AVAILABLE" then return UNKNOWN end

    -- A partir de aquí el valor está DEMOSTRADO seguro, así que se puede
    -- comparar. Antes de esta línea no se ha comparado con nada.
    if type(v) ~= "number" then return UNKNOWN end
    if v == 0 or v == 1 or v == 2 or v == 3 then return ENGAGED end

    -- Un número fuera del rango documentado no se interpreta. Si mañana
    -- Blizzard añade un 4, aquí saldrá UNKNOWN y no una mentira.
    return UNKNOWN
end

-- ─────────────────────────────────────────────────────────────────────────
-- EL GRUPO ENTERO CONTRA UNA PLACA
--
-- DEGRADACIÓN CONSERVADORA, en este orden y no en otro:
--   1. Una sola fuente ENGAGED basta         -> ENGAGED
--      (evidencia positiva; que las otras cuatro sean secretas da igual)
--   2. Si no, y algo quedó sin poder mirarse  -> UNKNOWN
--   3. Si no, y alguien pudo mirarse          -> NOT_ENGAGED
--   4. Si nadie pudo mirarse                  -> UNKNOWN
--
-- El punto 2 es el que impide que un grupo con lecturas secretas se presente
-- como "aquí no hay nadie peleando".
-- ─────────────────────────────────────────────────────────────────────────

function EngagementEvidence:Evaluate(unitToken)
    if type(unitToken) ~= "string" then return UNKNOWN end
    if type(rawget(_G, "UnitThreatSituation")) ~= "function" then return UNKNOWN end

    -- Una placa que no existe no se evalúa. No es NOT_ENGAGED: es que no hay
    -- a quién preguntar.
    if existeSeguro(unitToken) ~= true then return UNKNOWN end

    local mirados, hayDuda = 0, false

    for i = 1, #SOURCES do
        local src = SOURCES[i]
        local ex = existeSeguro(src)
        if ex == nil then
            -- No se puede ni saber si ese compañero está. Cuenta como duda.
            hayDuda = true
        elseif ex == true then
            local r = self:EvaluateSource(src, unitToken)
            if r == ENGAGED then
                return ENGAGED            -- positivo: manda y corta
            elseif r == UNKNOWN then
                hayDuda = true
            else
                mirados = mirados + 1
            end
        end
        -- ex == false: ese hueco del grupo está vacío. Ni duda ni dato.
    end

    if hayDuda then return UNKNOWN end
    if mirados == 0 then return UNKNOWN end
    return NOT_ENGAGED
end

-- ─────────────────────────────────────────────────────────────────────────
-- VARIAS PLACAS DE GOLPE
--
-- Recibe la lista de tokens YA REUNIDA POR QUIEN LLAMA. No hay registro de
-- placas aquí dentro: GuidanceEngine ya lleva uno y duplicarlo sería tener
-- dos verdades sobre lo mismo. Este módulo no sabe de dónde salen los tokens
-- y no debe saberlo.
-- ─────────────────────────────────────────────────────────────────────────

function EngagementEvidence:EvaluateTokens(tokens)
    local out = {}
    local resumen = { total = 0, engaged = 0, notEngaged = 0, unknown = 0 }
    if type(tokens) ~= "table" then return out, resumen end

    for _, tok in ipairs(tokens) do
        if type(tok) == "string" then
            local r = self:Evaluate(tok)
            out[tok] = r
            resumen.total = resumen.total + 1
            if r == ENGAGED then
                resumen.engaged = resumen.engaged + 1
            elseif r == NOT_ENGAGED then
                resumen.notEngaged = resumen.notEngaged + 1
            else
                resumen.unknown = resumen.unknown + 1
            end
        end
    end
    return out, resumen
end

return EngagementEvidence
