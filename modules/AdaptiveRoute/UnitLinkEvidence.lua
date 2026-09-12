-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · UnitLinkEvidence v1.0  —  FASE 3, EVIDENCIA
--
-- UNA SOLA PREGUNTA: ¿esta placa es la misma unidad que mi target, mi
-- mouseover, mi focus o mi softenemy?
--
-- Nada más. No conoce RouteProgress, GuidanceEngine, RouteArrows ni MDT, y no
-- debe conocerlos.
--
-- ═════════════════════════════════════════════════════════════════════════
-- LA REGLA QUE MANDA: SAME_UNIT NO ES MATCH
--
-- Por eso el vocabulario de este fichero es SAME_UNIT / DIFFERENT_UNIT y no
-- MATCH / NO_MATCH. Si dijera MATCH, tarde o temprano alguien lo enchufaría a
-- Guidance creyendo que ya está resuelto, y lo que dice de verdad es:
--
--     "la placa 3 y mi objetivo son la misma criatura del mundo"
--
-- que no contiene ni una pizca de identidad de ruta. Sigue sin saberse qué
-- npcID es, ni de qué pull, ni qué clon. Es un ENLACE entre dos punteros del
-- cliente, no un nombre.
--
-- PARA QUÉ SIRVE ENTONCES
-- Para que el jugador pueda señalar. Un enlace de estos, combinado con una
-- acción deliberada suya, es la única identidad que Midnight no ha cerrado.
-- Pero eso es la fase siguiente: aquí solo se mide que el enlace existe.
-- ═════════════════════════════════════════════════════════════════════════
--
-- LO QUE NO SE PREGUNTA, Y ES DELIBERADO
-- Ni targettarget, ni focustarget, ni partyXtarget, ni bossX. Los tokens
-- compuestos preguntan por la unidad de OTRA unidad: más superficie, misma
-- respuesta, y abren la puerta a construir cadenas de identidad indirecta.
-- Tampoco se comparan GUIDs ni nombres: UnitIsUnit contesta lo mismo sin
-- devolver nada que pueda ser secreto.
--
-- VALORES SECRETOS
-- UnitIsUnit devuelve un booleano, que hoy no llega secreto. "Hoy" no es una
-- garantía: el resultado pasa por issecretvalue ANTES de compararse con true,
-- porque comparar un Secret Value es justo una de las operaciones prohibidas.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local UnitLinkEvidence = {}
AR.UnitLinkEvidence = UnitLinkEvidence

-- ─────────────────────────────────────────────────────────────────────────
-- VOCABULARIO CERRADO
-- ─────────────────────────────────────────────────────────────────────────

local SAME_UNIT, DIFFERENT_UNIT, UNKNOWN =
      "SAME_UNIT", "DIFFERENT_UNIT", "UNKNOWN"

UnitLinkEvidence.STATES = {
    SAME_UNIT = SAME_UNIT, DIFFERENT_UNIT = DIFFERENT_UNIT, UNKNOWN = UNKNOWN,
}

local TARGET, MOUSEOVER, FOCUS, SOFTENEMY =
      "TARGET", "MOUSEOVER", "FOCUS", "SOFTENEMY"

UnitLinkEvidence.LINKS = {
    TARGET = TARGET, MOUSEOVER = MOUSEOVER, FOCUS = FOCUS, SOFTENEMY = SOFTENEMY,
}

-- Orden fijo: es el que sale en el informe, y que no baile ayuda a comparar
-- dos capturas de dos pulls distintos.
local ORDEN = { TARGET, MOUSEOVER, FOCUS, SOFTENEMY }
UnitLinkEvidence.ORDER = ORDEN

-- Clase de enlace -> token del cliente. El token vive AQUÍ y no sale de aquí:
-- fuera solo circula la clase, que es constante nuestra.
local TOKEN_DE = {
    [TARGET]    = "target",
    [MOUSEOVER] = "mouseover",
    [FOCUS]     = "focus",
    [SOFTENEMY] = "softenemy",
}

-- ─────────────────────────────────────────────────────────────────────────
-- LECTURA SEGURA
--
-- Duplicada a propósito, igual que en EngagementEvidence: un módulo de
-- evidencia no depende de otro módulo de evidencia.
-- ─────────────────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────────────────
-- UN ENLACE
--
-- true seguro  -> SAME_UNIT
-- false seguro -> DIFFERENT_UNIT   (incluye "no tienes objetivo": el cliente
--                                   contesta que no, y eso es una respuesta)
-- secreto      -> UNKNOWN
-- nil          -> UNKNOWN          (no contestó; no es lo mismo que un "no")
-- sin API      -> UNKNOWN
-- ─────────────────────────────────────────────────────────────────────────

function UnitLinkEvidence:Evaluate(unitToken, link)
    if type(unitToken) ~= "string" or type(link) ~= "string" then return UNKNOWN end

    local ref = TOKEN_DE[link] or TOKEN_DE[link:upper()]
    if not ref then return UNKNOWN end

    local API = rawget(_G, "UnitIsUnit")
    if type(API) ~= "function" then return UNKNOWN end

    local ok, res = pcall(API, unitToken, ref)
    if not ok then return UNKNOWN end
    if res == nil then return UNKNOWN end

    -- La comprobación va ANTES de comparar con true. Este orden es el fichero.
    if not esValorSeguro(res) then return UNKNOWN end
    if type(res) ~= "boolean" then return UNKNOWN end

    if res == true then return SAME_UNIT end
    return DIFFERENT_UNIT
end

-- Los cuatro enlaces de una placa, en el orden de ORDEN.
function UnitLinkEvidence:EvaluateAll(unitToken)
    local out = {}
    for _, k in ipairs(ORDEN) do
        out[k] = self:Evaluate(unitToken, k)
    end
    return out
end

-- ─────────────────────────────────────────────────────────────────────────
-- VARIAS PLACAS DE GOLPE
--
-- Los tokens los trae quien llama. Aquí no hay registro de placas: el de
-- GuidanceEngine ya existe y dos registros de lo mismo acaban discrepando.
-- ─────────────────────────────────────────────────────────────────────────

function UnitLinkEvidence:EvaluateTokens(tokens)
    local out = {}
    local resumen = { total = 0 }
    for _, k in ipairs(ORDEN) do resumen[k] = 0 end
    if type(tokens) ~= "table" then return out, resumen end

    for _, tok in ipairs(tokens) do
        if type(tok) == "string" then
            local r = self:EvaluateAll(tok)
            out[tok] = r
            resumen.total = resumen.total + 1
            for _, k in ipairs(ORDEN) do
                -- Solo se cuenta el enlace POSITIVO. Un DIFFERENT_UNIT no es
                -- un enlace, y un UNKNOWN tampoco: sumarlos daría un contador
                -- que parece decir algo y no dice nada.
                if r[k] == SAME_UNIT then resumen[k] = resumen[k] + 1 end
            end
        end
    end
    return out, resumen
end

return UnitLinkEvidence
