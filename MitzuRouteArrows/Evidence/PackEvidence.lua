-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuRouteArrows · PackEvidence v1.0  —  FASE 3, EXPERIMENTAL
--
-- UNA SOLA PREGUNTA: ¿cuántos enemigos espera este pull, y cuántas placas
-- están peleando ahora mismo con el grupo?
--
-- Es la pregunta que queda después de que Midnight cerrara todas las demás.
-- No se puede saber QUIÉN es nameplate3. Sí se puede saber CUÁNTOS son, y
-- comparar ese número con el que dice la ruta.
--
-- ═════════════════════════════════════════════════════════════════════════
-- LA REGLA QUE MANDA: ALIGNED NO ES MATCH
--
-- El pull espera 4. Hay exactamente 4 ENGAGED. Eso significa:
--
--     "el número cuadra"
--
-- y NO significa "estos cuatro son los cuatro de la ruta". Un jugador puede
-- haber puleado el pack de al lado, que también tiene cuatro. Por eso el
-- vocabulario de este fichero es UNDER / ALIGNED / OVER y la palabra MATCH no
-- aparece: dentro de Mitzu, MATCH significa identidad, y aquí no hay ninguna.
--
-- Esta capa produce EVIDENCIA DE FORMA. Nunca identidad.
-- ═════════════════════════════════════════════════════════════════════════
--
-- VISIBLE NO ES ENGAGED. Comparar el número de placas visibles con el tamaño
-- del pull sería un contador de cámara: se ven los mobs del pack siguiente, se
-- ve el pack de la patrulla, se ve lo que haya al fondo del pasillo. El
-- conjunto de combate lo da EngagementEvidence y nadie más.
--
-- SIN ESTADO. Este módulo no guarda nada entre llamadas: ni el pull, ni los
-- tokens, ni el último resultado. RouteProgress sigue siendo la única
-- autoridad del pull y aquí no se copia su índice. Cada Evaluate se calcula
-- entero y se tira.
--
-- SIN APIS DE UNIDAD. No llama a UnitGUID, UnitName, UnitHealth,
-- UnitClassification ni al recuento de tropas por unidad. Solo consume los
-- enums canónicos de EngagementEvidence y UnitLinkEvidence.
-- ═══════════════════════════════════════════════════════════════════════════

local MRA = _G.MitzuRouteArrows
if not MRA then return end

-- AR: los demas modulos de este mismo addon.
-- Host: fachada de SOLO LECTURA sobre MitzuMPlusAPI (Core/Host.lua).
local AR = MRA
local Host = MRA.Host

local PackEvidence = {}
AR.PackEvidence = PackEvidence

-- ─────────────────────────────────────────────────────────────────────────
-- VOCABULARIO CERRADO
-- ─────────────────────────────────────────────────────────────────────────

local UNDER, ALIGNED, OVER, UNKNOWN, INACTIVE =
      "UNDER", "ALIGNED", "OVER", "UNKNOWN", "INACTIVE"

PackEvidence.STATES = {
    UNDER = UNDER, ALIGNED = ALIGNED, OVER = OVER,
    UNKNOWN = UNKNOWN, INACTIVE = INACTIVE,
}

local AVAILABLE = "AVAILABLE"
PackEvidence.COUNT_STATES = { AVAILABLE = AVAILABLE, UNKNOWN = UNKNOWN }

-- Aunque esta capa describa la forma del conjunto, nunca resuelve identidad.
-- El campo se exporta para que cualquier consumidor futuro tenga que ignorar
-- activamente esta advertencia, en vez de inferir MATCH a partir de ALIGNED.
PackEvidence.IDENTITY_STATES = { UNKNOWN = UNKNOWN }

PackEvidence.REASONS = {
    RUNTIME_NOT_RUNNING      = "RUNTIME_NOT_RUNNING",
    RUNTIME_UNKNOWN          = "RUNTIME_UNKNOWN",
    EXPECTED_COUNT_UNKNOWN   = "EXPECTED_COUNT_UNKNOWN",
    ENGAGEMENT_UNKNOWN       = "ENGAGEMENT_UNKNOWN",
    ENGAGED_OVER_EXPECTED    = "ENGAGED_OVER_EXPECTED",
    ENGAGED_COUNT_ALIGNED    = "ENGAGED_COUNT_ALIGNED",
    ENGAGED_UNDER_EXPECTED   = "ENGAGED_UNDER_EXPECTED",
}

-- Para los enlaces: sí / no / no se sabe. Tres valores, porque "no lo sé" no
-- es "no" y tratarlo como tal sería afirmar de más.
local YES, NO = "YES", "NO"
PackEvidence.LINK_STATES = { YES = YES, NO = NO, UNKNOWN = UNKNOWN }

-- Los cuatro enlaces, en el orden en que se informan.
local LINKS = { "TARGET", "MOUSEOVER", "FOCUS", "SOFTENEMY" }
PackEvidence.LINKS = LINKS

-- Vocabularios ajenos que este módulo acepta. Se usan como TABLA DE
-- TRADUCCIÓN, no como lista blanca: lo que se devuelve es el valor guardado
-- aquí, nunca el que vino de fuera. Validar y luego transportar sigue siendo
-- transportar — es la lección de SEC-2 y vale igual entre módulos nuestros.
local ENGAGEMENT_CANON = {
    ENGAGED = "ENGAGED", NOT_ENGAGED = "NOT_ENGAGED", UNKNOWN = UNKNOWN,
}
local LINK_CANON = {
    SAME_UNIT = "SAME_UNIT", DIFFERENT_UNIT = "DIFFERENT_UNIT", UNKNOWN = UNKNOWN,
}

-- Traduce un valor venido de otro módulo. Devuelve nil si no lo reconoce.
-- El índice va dentro de pcall: si algún día llegara aquí algo hostil o
-- secreto, reventaría ahí dentro y la respuesta sería "no lo reconozco".
local function canon(v, tabla)
    if type(v) ~= "string" then return nil end
    local ok, res = pcall(function() return tabla[v] end)
    if not ok then return nil end
    return res
end

-- ─────────────────────────────────────────────────────────────────────────
-- CUÁNTOS ESPERA EL PULL
--
-- ═════════════════════════════════════════════════════════════════════════
-- EL DATO ES `amount`, NO LOS CLONES VÁLIDOS
--
-- La tentación es contar clones resueltos, y es un error. En el esquema
-- MitzuRoute v1, "unresolved" significa que el índice de clon cae fuera del
-- rango que declara MDTEnemyData — es decir, que ese mob NO SE PUEDE SITUAR
-- EN EL MAPA. El propio validador lo dice: "la ruta es utilizable, pero esos
-- clones no se pueden situar".
--
-- El mob EXISTE igual y hay que matarlo igual. Contar solo los válidos haría
-- que Ruby Life Pools esperase 77 unidades en vez de 86, y el pull donde
-- cayera un clon sin resolver diría UNDER para siempre.
--
-- `amount` sale de RouteSchema.FromLegacyProfile como #clones, así que los
-- dos números coinciden en las ocho rutas empaquetadas (907 unidades). Se usa
-- `amount` y los cloneIDs quedan de reserva por si un día no coincidieran.
-- ═════════════════════════════════════════════════════════════════════════
--
-- Sale EXCLUSIVAMENTE de la ruta estática. Ni tropas, ni GUID, ni npcID en
-- vivo, ni placas, ni combat log.
-- ─────────────────────────────────────────────────────────────────────────

local function enteroPositivo(v)
    local n = tonumber(v)
    if type(n) ~= "number" or n <= 0 or n == math.huge or n == -math.huge then
        return nil
    end
    if n ~= math.floor(n) then return nil end
    return n
end

local function contar(pull)
    if type(pull) ~= "table" then return nil end
    local mobs = rawget(pull, "mobs")
    -- Un pull sin mobs no vale 0: vale "no lo sé". Inventar un 0 haría que
    -- cualquier pull vacío o corrupto saliera ALIGNED sin un solo enemigo.
    if type(mobs) ~= "table" or #mobs == 0 then return nil end

    local total = 0
    for i = 1, #mobs do
        local m = mobs[i]
        if type(m) ~= "table" then return nil end
        -- tonumber sobre datos de NUESTROS ficheros de ruta, que no vienen de
        -- ninguna API del cliente y no pueden ser secretos. Es lo mismo que
        -- hace RouteProgress:_BuildCache con este campo.
        local n = enteroPositivo(rawget(m, "amount"))
        if not n or n <= 0 then
            local clones = rawget(m, "cloneIDs")
            n = (type(clones) == "table") and #clones or nil
        end
        if not n or n <= 0 then return nil end
        total = total + n
    end
    if total <= 0 then return nil end
    return total
end

-- Devuelve: número o nil, y el estado del cálculo.
function PackEvidence:ExpectedFromPull(pull)
    local ok, n = pcall(contar, pull)
    if not ok or type(n) ~= "number" then return nil, UNKNOWN end
    return n, AVAILABLE
end

-- ─────────────────────────────────────────────────────────────────────────
-- EL CONJUNTO DE COMBATE
--
-- Un token cuenta como ENGAGED solo si EngagementEvidence lo dice con esa
-- palabra exacta. Cualquier otra cosa —incluido que el módulo no esté, que
-- reviente o que devuelva algo que no se reconoce— cuenta como duda.
-- ─────────────────────────────────────────────────────────────────────────

local function repartir(tokens)
    local r = { visible = 0, engaged = 0, notEngaged = 0, unknown = 0,
                engagedTokens = {} }
    if type(tokens) ~= "table" then return r end

    local EE = AR.EngagementEvidence
    for _, tok in ipairs(tokens) do
        if type(tok) == "string" then
            r.visible = r.visible + 1
            local estado = nil
            if EE and type(EE.Evaluate) == "function" then
                local ok, v = pcall(function() return EE:Evaluate(tok) end)
                if ok then estado = canon(v, ENGAGEMENT_CANON) end
            end
            if estado == "ENGAGED" then
                r.engaged = r.engaged + 1
                r.engagedTokens[#r.engagedTokens + 1] = tok
            elseif estado == "NOT_ENGAGED" then
                r.notEngaged = r.notEngaged + 1
            else
                r.unknown = r.unknown + 1
            end
        end
    end
    table.sort(r.engagedTokens)
    return r
end

-- ─────────────────────────────────────────────────────────────────────────
-- LOS ENLACES, MIRADOS SOLO DENTRO DEL CONJUNTO DE COMBATE
--
-- La pregunta no es "¿tengo un objetivo?" sino "¿mi objetivo es uno de los
-- que están peleando?". Un target sobre un mob que NO está enganchado
-- responde NO, y es la respuesta correcta.
-- ─────────────────────────────────────────────────────────────────────────

local function enlaces(engagedTokens)
    local out = {}
    local UL = AR.UnitLinkEvidence
    local hayModulo = UL and type(UL.Evaluate) == "function"

    for _, clase in ipairs(LINKS) do
        if not hayModulo then
            out[clase] = UNKNOWN
        elseif #engagedTokens == 0 then
            -- Sin conjunto de combate no hay nada dentro de lo que mirar.
            out[clase] = NO
        else
            local encontrado, duda = false, false
            for _, tok in ipairs(engagedTokens) do
                local ok, v = pcall(function() return UL:Evaluate(tok, clase) end)
                local est = ok and canon(v, LINK_CANON) or nil
                if est == "SAME_UNIT" then
                    encontrado = true
                    break            -- un positivo basta y corta
                elseif est ~= "DIFFERENT_UNIT" then
                    duda = true
                end
            end
            out[clase] = encontrado and YES or (duda and UNKNOWN or NO)
        end
    end
    return out
end

-- ─────────────────────────────────────────────────────────────────────────
-- LA FORMA DEL PACK
--
-- ORDEN DE LAS REGLAS, Y NO OTRO:
--
--   1. Estado conocido fuera de llave corriendo -> INACTIVE
--      Estado de runtime desconocido             -> UNKNOWN
--   2. Sin saber cuántos espera el pull          -> UNKNOWN
--   3. Más enganchados que esperados           -> OVER
--      (una duda solo puede SUMAR enganchados, nunca restar: si ya hay más
--       de los que tocan, más dudas no lo van a arreglar. Es seguro.)
--   4. Queda alguna duda                       -> UNKNOWN
--   5. Tantos como esperados                   -> ALIGNED
--   6. Menos                                   -> UNDER
--
-- El punto 4 es el que impide el error del que avisa la especificación:
-- esperados 4, enganchados 4, dudas 2 NO es ALIGNED, porque podrían ser seis.
-- ─────────────────────────────────────────────────────────────────────────

function PackEvidence:Evaluate(context)
    context = (type(context) == "table") and context or {}

    local tokens   = rawget(context, "visibleTokens")
    local okEsperado, esperado = pcall(enteroPositivo, rawget(context, "expectedCount"))
    if not okEsperado then esperado = nil end
    local estadoCuenta = rawget(context, "expectedCountState")
    if estadoCuenta ~= AVAILABLE then
        -- Si quien llama no lo dice, se deduce de si hay número.
        estadoCuenta = esperado and AVAILABLE or UNKNOWN
    end
    if not esperado then estadoCuenta = UNKNOWN end

    local runtimeState = rawget(context, "runtimeState")
    local r = repartir(tokens)

    local resultado = {
        packState          = UNKNOWN,
        identityState      = UNKNOWN,
        evidenceKind       = "PACK_SHAPE",
        reasonCode         = nil,
        expectedCount      = (estadoCuenta == AVAILABLE) and esperado or nil,
        expectedCountState = estadoCuenta,
        runtimeState       = (type(runtimeState) == "string") and runtimeState or nil,
        visible            = r.visible,
        engaged            = r.engaged,
        notEngaged         = r.notEngaged,
        unknownEngagement  = r.unknown,
        engagedTokens      = r.engagedTokens,
        links              = enlaces(r.engagedTokens),
    }

    -- 1. Fuera de una llave corriendo no se opina sobre la forma del pack. Si
    -- ni siquiera conocemos el runtime, tampoco asumimos que este corriendo.
    if resultado.runtimeState == nil then
        resultado.reasonCode = PackEvidence.REASONS.RUNTIME_UNKNOWN
        return resultado
    elseif resultado.runtimeState ~= "RUNNING" then
        resultado.packState = INACTIVE
        resultado.reasonCode = PackEvidence.REASONS.RUNTIME_NOT_RUNNING
        return resultado
    end

    if estadoCuenta ~= AVAILABLE then
        resultado.reasonCode = PackEvidence.REASONS.EXPECTED_COUNT_UNKNOWN
        return resultado
    end

    if r.engaged > esperado then
        resultado.packState = OVER                            -- 3
        resultado.reasonCode = PackEvidence.REASONS.ENGAGED_OVER_EXPECTED
    elseif r.unknown > 0 then
        resultado.packState = UNKNOWN                         -- 4
        resultado.reasonCode = PackEvidence.REASONS.ENGAGEMENT_UNKNOWN
    elseif r.engaged == esperado then
        resultado.packState = ALIGNED                         -- 5
        resultado.reasonCode = PackEvidence.REASONS.ENGAGED_COUNT_ALIGNED
    else
        resultado.packState = UNDER                           -- 6
        resultado.reasonCode = PackEvidence.REASONS.ENGAGED_UNDER_EXPECTED
    end
    return resultado
end

return PackEvidence
