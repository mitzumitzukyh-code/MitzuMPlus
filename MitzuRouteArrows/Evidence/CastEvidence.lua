-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuRouteArrows · CastEvidence v1.0  —  FASE 3, EXPERIMENTAL
--
-- UNA SOLA PREGUNTA: ¿esta placa está lanzando algo, y puedo saber el qué?
--
-- Son DOS preguntas y se responden por separado a propósito, porque el
-- cliente las contesta por separado:
--
--     ¿HAY cast?      -> solo se afirma si el primer retorno no es secreto.
--     ¿QUÉ cast?      -> casi seguro que no. Ver el bloque de abajo.
--
-- ═════════════════════════════════════════════════════════════════════════
-- LO QUE YA SE SABE ANTES DE PROBARLO EN VIVO
--
-- Leído en addons de terceros ya adaptados a Midnight, no supuesto:
--
--   · DandersFrames (Features/TargetedSpells.lua, "gotcha #0"): sobre placas
--     y en combate de instancia, UnitCastingInfo y UnitChannelInfo devuelven
--     valores SECRETOS en los campos de tiempo, y su propio comentario añade
--     que "spellID, texture y durationObject están tainted en nameplates".
--     También: "Can't compare spellID (it's a secret)".
--   · El mismo addon dice que el spellID SÍ llega limpio en el payload del
--     EVENTO UNIT_SPELLCAST_START. Aquí no se usan eventos (esta subfase es
--     bajo demanda), así que ese camino queda anotado para después.
--   · BetterBlizzPlates (build midnight) y DBM-Core siguen llamando a
--     UnitCastingInfo sobre unidades enemigas: la API existe y contesta.
--
-- Conclusión de partida, a confirmar en vivo: se espera CASTING/CHANNELING
-- legibles y spellID = nil dentro de una llave. Si sale un spellID seguro,
-- mejor; el módulo lo dará. Lo que no hará nunca es fabricarlo.
-- ═════════════════════════════════════════════════════════════════════════
--
-- ESTO NO ES IDENTIDAD. Un spellID legible significa CAST_SIGNATURE_AVAILABLE
-- y nada más. Que un hechizo sea único entre los candidatos del pull es otra
-- pregunta, de otra fase, y este fichero no la hace: no conoce RouteProgress,
-- ni RouteArrows, ni el Presenter, ni MDT, ni la política de Guidance.
--
-- POR QUÉ NO SE USA tonumber() SOBRE UN SECRETO
-- Core.lua lo hace en OnSpellcastSucceeded (FIX BUG-SECRET-4) para el cast
-- DEL PROPIO JUGADOR. Aquí no se copia ese patrón: convertir un secreto es
-- tocarlo. Si el spellID no se puede demostrar seguro, no sale. FAIL CLOSED.
-- ═══════════════════════════════════════════════════════════════════════════

local MRA = _G.MitzuRouteArrows
if not MRA then return end

-- AR: los demas modulos de este mismo addon.
-- Host: fachada de SOLO LECTURA sobre MitzuMPlusAPI (Core/Host.lua).
local AR = MRA
local Host = MRA.Host

local CastEvidence = {}
AR.CastEvidence = CastEvidence

-- ─────────────────────────────────────────────────────────────────────────
-- VOCABULARIO CERRADO
-- ─────────────────────────────────────────────────────────────────────────

local CASTING, CHANNELING, NOT_CASTING, UNKNOWN =
      "CASTING", "CHANNELING", "NOT_CASTING", "UNKNOWN"
local AVAILABLE, SECRET, UNAVAILABLE = "AVAILABLE", "SECRET", "UNAVAILABLE"

CastEvidence.STATES = {
    CASTING = CASTING, CHANNELING = CHANNELING,
    NOT_CASTING = NOT_CASTING, UNKNOWN = UNKNOWN,
}
CastEvidence.SPELL_ID_STATES = {
    AVAILABLE = AVAILABLE, SECRET = SECRET, UNAVAILABLE = UNAVAILABLE,
}

-- Posición del spellID en cada tupla. Son DISTINTAS, y equivocarse aquí
-- devolvería el flag de interrumpible como si fuera un hechizo:
--   UnitCastingInfo -> name, text, texture, startMS, endMS, isTradeSkill,
--                      castID, notInterruptible, spellID          (9)
--   UnitChannelInfo -> name, text, texture, startMS, endMS, isTradeSkill,
--                      notInterruptible, spellID                  (8)
local POS_SPELLID_CAST    = 9
local POS_SPELLID_CHANNEL = 8

-- ─────────────────────────────────────────────────────────────────────────
-- LECTURA SEGURA
--
-- Duplicada, como en las otras evidencias: un módulo de evidencia no depende
-- de otro módulo de evidencia.
-- ─────────────────────────────────────────────────────────────────────────

local function estadoSecreto(v)
    local iss = rawget(_G, "issecretvalue")
    if type(iss) ~= "function" then return nil end
    local ok, res = pcall(iss, v)
    if not ok then return nil end
    if res == true then return true end
    if res == false then return false end
    return nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- ¿HAY CAST? — la pregunta barata
--
-- Antes de cualquier comparación se pregunta a issecretvalue. Si no puede
-- demostrarse que el retorno es público, la respuesta es UNKNOWN.
--
-- Devuelve true / false / nil, donde nil significa "no se pudo preguntar".
-- ─────────────────────────────────────────────────────────────────────────

local function hayCast(fn, unitToken)
    if type(fn) ~= "function" then return nil end
    local ok, primero = pcall(fn, unitToken)
    if not ok then return nil end
    if estadoSecreto(primero) ~= false then return nil end
    return primero ~= nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- ¿QUÉ CAST? — la pregunta cara
--
-- Saca UNA posición de la tupla y la descarta si no se puede demostrar que es
-- un número seguro. Las otras ocho posiciones no se atan a ninguna variable:
-- el select() las deja donde estaban.
-- ─────────────────────────────────────────────────────────────────────────

local function spellIDSeguro(fn, unitToken, pos)
    if type(fn) ~= "function" then return nil, UNAVAILABLE end
    local ok, id = pcall(function() return (select(pos, fn(unitToken))) end)
    if not ok then return nil, UNAVAILABLE end
    local secreto = estadoSecreto(id)
    if secreto == true then return nil, SECRET end
    if secreto ~= false then return nil, SECRET end
    if id == nil then return nil, UNAVAILABLE end
    if type(id) ~= "number" then return nil, UNAVAILABLE end
    return id, AVAILABLE
end

-- ─────────────────────────────────────────────────────────────────────────
-- UNA PLACA
--
-- Devuelve TRES valores: estado, spellID seguro y estado de ese ID.
-- meterle dentro el resto de la tupla, y el resto de la tupla es justo lo que
-- no debe viajar.
--
--   state   = CASTING | CHANNELING | NOT_CASTING | UNKNOWN
--   spellID      = número seguro, o nil
--   spellIDState = AVAILABLE | SECRET | UNAVAILABLE
--
-- CASTING con spellID nil es un resultado NORMAL y esperado, no un fallo.
-- ─────────────────────────────────────────────────────────────────────────

function CastEvidence:Evaluate(unitToken)
    if type(unitToken) ~= "string" then return UNKNOWN, nil, UNAVAILABLE end

    local apiCast = rawget(_G, "UnitCastingInfo")
    local apiChan = rawget(_G, "UnitChannelInfo")
    if type(apiCast) ~= "function" and type(apiChan) ~= "function" then
        return UNKNOWN, nil, UNAVAILABLE
    end

    local cast = hayCast(apiCast, unitToken)
    local chan = hayCast(apiChan, unitToken)

    -- El cast manda sobre el canalizado: si el cliente contesta a los dos, es
    -- un cast normal y el canalizado es residuo del anterior.
    if cast == true then
        local id, idState = spellIDSeguro(apiCast, unitToken, POS_SPELLID_CAST)
        return CASTING, id, idState
    end
    if chan == true then
        local id, idState = spellIDSeguro(apiChan, unitToken, POS_SPELLID_CHANNEL)
        return CHANNELING, id, idState
    end

    -- Las dos preguntas contestaron "no hay nada". Eso sí es un dato.
    if cast == false and chan == false then return NOT_CASTING, nil, UNAVAILABLE end

    -- Alguna no se pudo hacer. No se sabe.
    return UNKNOWN, nil, UNAVAILABLE
end

function CastEvidence:UnitExistsState(unitToken)
    local fn = rawget(_G, "UnitExists")
    if type(fn) ~= "function" then return "UNKNOWN" end
    local ok, value = pcall(fn, unitToken)
    if not ok then return "UNKNOWN" end
    if estadoSecreto(value) ~= false then return "UNKNOWN" end
    if value == true then return "YES" end
    if value == false or value == nil then return "NO" end
    return "UNKNOWN"
end

-- ─────────────────────────────────────────────────────────────────────────
-- VARIAS PLACAS
--
-- Los tokens los trae quien llama. Aquí no hay registro de placas: el de
-- GuidanceEngine ya existe.
-- ─────────────────────────────────────────────────────────────────────────

function CastEvidence:EvaluateTokens(tokens)
    local out = {}
    local resumen = { total = 0, casting = 0, channeling = 0,
                      notCasting = 0, unknown = 0, safeSpellIDs = 0 }
    if type(tokens) ~= "table" then return out, resumen end

    for _, tok in ipairs(tokens) do
        if type(tok) == "string" then
            local st, id, idState = self:Evaluate(tok)
            -- La tabla la construimos NOSOTROS con dos campos comprobados.
            -- No es el retorno de ninguna API.
            out[tok] = { state = st, spellID = id, spellIDState = idState }
            resumen.total = resumen.total + 1
            if st == CASTING then
                resumen.casting = resumen.casting + 1
            elseif st == CHANNELING then
                resumen.channeling = resumen.channeling + 1
            elseif st == NOT_CASTING then
                resumen.notCasting = resumen.notCasting + 1
            else
                resumen.unknown = resumen.unknown + 1
            end
            if id ~= nil then resumen.safeSpellIDs = resumen.safeSpellIDs + 1 end
        end
    end
    return out, resumen
end

return CastEvidence
