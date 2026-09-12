-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · LiveEnemyResolver v1.0  —  SPIKE, NO PRODUCCIÓN
--
-- PREGUNTA QUE RESPONDE ESTE FICHERO
-- ¿Cuánto se puede saber de una placa viva en una M+ de 12.1 sin tocar nada
-- prohibido? Es un experimento instrumentado, no el RouteMatcher definitivo.
--
-- GuidanceEngine lo consulta exclusivamente por ResolveForGuidance, su frontera
-- canónica. RouteArrowPresenter puede convertir un MATCH de esa frontera en una
-- flecha; por eso cualquier MATCH de este fichero es una decisión de seguridad,
-- aunque el resto de la observación siga siendo diagnóstico.
--
-- ═════════════════════════════════════════════════════════════════════════
-- LA REGLA QUE MANDA: forceCount NO ES IDENTIDAD
--
-- Es una FIRMA PARCIAL. Dos mobs distintos de 4 tropas son indistinguibles
-- por tropas, y punto. Nunca se elige uno de varios candidatos "porque hay que
-- elegir": eso es exactamente el falso positivo que hundió al sistema [SKIP].
--
-- Medido sobre las 8 rutas ya importadas (907 unidades):
--   · dentro del pull, la firma identifica a una sola unidad en el 9.4%
--   · entre pulls, la firma es exclusiva de un pull en el 2.0%
-- Altar of Fangs es el peor caso: 5 firmas distintas para 103 unidades, y
-- forces=5 aparece en 11 de sus 12 pulls.
--
-- Por eso este módulo prefiere el npcID SIEMPRE que el GUID sea legible, y
-- solo cae a las tropas cuando no lo es. Y cuando cae, casi siempre dirá
-- AMBIGUOUS. Decirlo es el resultado; disimularlo sería el fallo.
--
-- INVARIANTES DE IDENTIDAD (FASE 3A)
--   · npcID compatible no identifica un clon.
--   · estar presente en el pull actual no basta para MATCH.
--   · dos asignaciones de clon compatibles son AMBIGUOUS.
--   · MATCH exige una sola asignación compatible en toda la mazmorra conocida.
--   · una placa visible no se presume del pull; ENGAGED/NOT_ENGAGED no entran
--     en este resolver baseline.
-- ═════════════════════════════════════════════════════════════════════════
--
-- SECRET VALUES: ningún valor leído de una unidad se compara, concatena,
-- ordena ni pasa por tonumber antes de preguntar a `issecretvalue`. Lo que
-- resulte secreto se reporta como SECRET y no se toca nunca más.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local LiveEnemyResolver = {}
AR.LiveEnemyResolver = LiveEnemyResolver

-- ═════════════════════════════════════════════════════════════════════════
-- BUG SEC-2 — una frontera de seguridad no puede fallar ABIERTA
--
-- Antes: `local _issecretvalue = rawget(_G, "issecretvalue")` resuelto AL
-- CARGAR, y `if not _issecretvalue then return false end`. Si ese global no
-- existiera con ese nombre exacto, la guarda diria "no es secreto" SIEMPRE y
-- los valores crudos saldrian marcados como AVAILABLE.
--
-- Ahora se resuelve en cada llamada y se falla CERRADO: si no se puede
-- demostrar que un valor es seguro, se trata como no disponible. Nunca al
-- reves. No poder demostrar que algo es seguro no es lo mismo que serlo.
-- ═════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- LECTURA SEGURA
-- ─────────────────────────────────────────────────────────────────────────

-- Pregunta PRIMERO a Blizzard, antes incluso de comparar con nil o consultar
-- el tipo. El resultado de esta funcion ya es un booleano local y seguro.
local function secretoSegunCliente(v)
    local iss = rawget(_G, "issecretvalue")
    if type(iss) ~= "function" then return nil end
    local ok, res = pcall(iss, v)
    if not ok then return nil end
    if res == true then return true end
    if res == false then return false end
    return nil
end

-- ¿Se puede DEMOSTRAR que este valor es seguro de tocar?
-- Devuelve false ante cualquier duda. Solo despues de recibir "no secreto"
-- se permite comparar, inspeccionar el tipo o transportar el valor.
local function esValorSeguro(v)
    if secretoSegunCliente(v) ~= false then return false end
    if v == nil then return true end
    local t = type(v)
    return t == "string" or t == "number" or t == "boolean"
end

-- Devuelve: estado, valor, tipo.  El valor SOLO sale si es seguro tocarlo.
local function leer(fn, ...)
    if type(fn) ~= "function" then return "UNAVAILABLE", nil, nil end
    local ok, v = pcall(fn, ...)
    if not ok then return "UNAVAILABLE", nil, nil end
    local secreto = secretoSegunCliente(v)
    if secreto ~= false then return "SECRET", nil, "secret" end
    if v == nil then return "UNKNOWN", nil, nil end
    if not esValorSeguro(v) then return "SECRET", nil, "secret" end
    return "AVAILABLE", v, type(v)
end

-- npcID desde el GUID, y solo si el GUID es un string normal. Centralizado
-- aquí para que no vuelva a repartirse un strsplit por medio addon.
function LiveEnemyResolver:GetNPCID(unitToken)
    local st, guid, tipo = leer(UnitGUID, unitToken)
    if st ~= "AVAILABLE" then return nil, st, tipo end
    if type(guid) ~= "string" then return nil, "UNKNOWN", type(guid) end
    local unitType, _, _, _, _, id = strsplit("-", guid)
    if unitType ~= "Creature" and unitType ~= "Vehicle" then
        return nil, "NO_ES_CRIATURA", unitType
    end
    return tonumber(id), "AVAILABLE", "string"
end

-- ─────────────────────────────────────────────────────────────────────────
-- PASO 3 — ÍNDICE DE FIRMAS DEL PULL ACTUAL
--
-- Cada CLON de la ruta es una unidad física en el mundo. Un enemigo con
-- clones {1,4,8} y forceCount 7 son TRES candidatos de 7 tropas. Se conserva
-- enemyIdx y cloneIdx en cada candidato: son la identidad de ruta y no se
-- pierden aunque la firma no sirva para distinguirlos.
-- ─────────────────────────────────────────────────────────────────────────

function LiveEnemyResolver:BuildCurrentPullIndex(pullIndex)
    local DS = AR.DataStructure
    local PN = AR.PullNavigator
    pullIndex = tonumber(pullIndex) or (PN and PN:GetCurrentPull()) or 1

    local enemies = DS and DS.EnemiesOf and DS:EnemiesOf(pullIndex) or nil
    local idx = {
        pullIndex   = pullIndex,
        byForces    = {},   -- [forces] = { candidato, ... }
        candidates  = {},   -- todos, en orden
        noForces    = 0,    -- mobs que no aportan tropas: sin firma posible
        byNPC       = {},   -- [npcID] = nº de candidatos
        routeByNPC  = {},   -- [npcID] = candidatos en toda la ruta
        dungeonByNPC = {},  -- [npcID] = copias en los datos completos de MDT
        routeUniverseState = "UNKNOWN",
        dungeonUniverseState = "UNKNOWN",
    }
    if not enemies then return idx, "sin identidad de clones en este pull" end

    for _, e in ipairs(enemies) do
        local clones = e.clones or {}
        for _, ci in ipairs(clones) do
            local cand = {
                enemyIdx   = e.enemyIdx,
                cloneIdx   = ci,
                npcID      = e.npcID,
                forceCount = e.forceCount,
                pullIndex  = pullIndex,
            }
            idx.candidates[#idx.candidates + 1] = cand
            if e.npcID then
                idx.byNPC[e.npcID] = (idx.byNPC[e.npcID] or 0) + 1
            end
            local f = tonumber(e.forceCount)
            if f and f > 0 then
                idx.byForces[f] = idx.byForces[f] or {}
                local l = idx.byForces[f]
                l[#l + 1] = cand
            else
                idx.noForces = idx.noForces + 1
            end
        end
    end

    -- Universo de la RUTA. El pull actual solo responde "podría estar aquí";
    -- para identidad hay que contar también los pulls pasados y futuros.
    local full = DS and type(DS.Get) == "function" and DS:Get() or nil
    if type(full) == "table" and type(full.pulls) == "table" then
        idx.routeUniverseState = "AVAILABLE"
        for _, p in pairs(full.pulls) do
            if type(p) == "table" then
                for _, e in ipairs(p.enemies or {}) do
                    local n = type(e.clones) == "table" and #e.clones or 0
                    if e.npcID and n > 0 then
                        idx.routeByNPC[e.npcID] = (idx.routeByNPC[e.npcID] or 0) + n
                    end
                end
            end
        end
    end

    -- Universo de la MAZMORRA. Una ruta puede omitir clones; sin esta segunda
    -- cuenta, "único en la ruta" seguiría confundiendo un clon seleccionado con
    -- otra copia del mismo npcID que quedó fuera de ella.
    local dungeonIdx = type(full) == "table" and tonumber(full.mdtDungeonIdx) or nil
    local snapshot = dungeonIdx and MitzuMPlus.MDTEnemyData
                     and MitzuMPlus.MDTEnemyData[dungeonIdx] or nil
    if type(snapshot) == "table" and type(snapshot.e) == "table" then
        idx.dungeonUniverseState = "AVAILABLE"
        for _, ref in pairs(snapshot.e) do
            local npcID = type(ref) == "table" and tonumber(ref[1]) or nil
            local n = type(ref) == "table" and tonumber(ref[3]) or nil
            if npcID and n and n > 0 then
                idx.dungeonByNPC[npcID] = (idx.dungeonByNPC[npcID] or 0) + n
            end
        end
    end
    return idx
end

-- ─────────────────────────────────────────────────────────────────────────
-- PASO 1 — OBSERVACIÓN DE UNA UNIDAD
--
-- Solo observa. No decide. Nada de lo que devuelve es un valor secreto.
-- ─────────────────────────────────────────────────────────────────────────

function LiveEnemyResolver:Observe(unitToken)
    local o = {
        unitToken = unitToken,
        exists     = false,
    }
    local stE, ex = leer(UnitExists, unitToken)
    if stE == "AVAILABLE" and ex == true then
        o.exists = true
        o.unitExistsState = "YES"
    elseif stE == "AVAILABLE" and ex == false then
        o.unitExistsState = "NO"
    else
        o.unitExistsState = "UNKNOWN"
    end
    if not o.exists then
        o.enemyIdentityState = "UNAVAILABLE"
        o.npcIDState         = "UNAVAILABLE"
        o.forcesState        = "UNAVAILABLE"
        return o
    end

    -- Identidad
    local npcID, st, tipo = self:GetNPCID(unitToken)
    o.enemyIdentityState = st
    o.guidType   = tipo
    o.guidSecret = (st == "SECRET")
    o.npcID      = npcID
    o.npcIDState = npcID and "AVAILABLE" or "UNAVAILABLE"

    -- Tropas que aporta ESTA unidad. No es el progreso de la run: eso ya costó
    -- el BUG EF-1 en KeystoneTracker.
    local API = C_ScenarioInfo and C_ScenarioInfo.GetUnitCriteriaProgressValues
    local stF, vF, tF = leer(API, unitToken)
    o.forcesState  = stF
    o.forcesType   = tF
    o.forcesSecret = (stF == "SECRET")
    o.forces       = (stF == "AVAILABLE") and tonumber(vF) or nil

    -- PASO 6/F — otras señales legales, para saber si alguna sobrevive a
    -- Midnight cuando el GUID no. No se usan para decidir todavía: se miden.
    local stN, vN = leer(UnitName, unitToken)
    o.nameState = stN
    o.nameKnown = (stN == "AVAILABLE" and type(vN) == "string")

    local stC, vC = leer(UnitClassification, unitToken)
    o.classificationState = stC
    o.classification = (stC == "AVAILABLE" and type(vC) == "string") and vC or nil

    local stT, vT = leer(UnitCreatureType, unitToken)
    o.creatureTypeState = stT
    o.creatureType = (stT == "AVAILABLE" and type(vT) == "string") and vT or nil

    local stL, vL = leer(UnitLevel, unitToken)
    o.levelState = stL
    o.level = (stL == "AVAILABLE") and tonumber(vL) or nil

    local stH = leer(UnitHealthMax, unitToken)
    o.healthMaxState = stH

    local stCast = leer(UnitCastingInfo, unitToken)
    o.castTrackingState = (stCast == "UNKNOWN") and "LIMITED" or stCast

    return o
end

-- ─────────────────────────────────────────────────────────────────────────
-- PASO 4 — RESOLVER
--
-- Contrato: MATCH / AMBIGUOUS / NO_MATCH / UNKNOWN. Jamás se elige un
-- candidato entre varios.
-- ─────────────────────────────────────────────────────────────────────────

function LiveEnemyResolver:Resolve(unitToken, pullIdx)
    local o = self:Observe(unitToken)
    local idx = self:BuildCurrentPullIndex(pullIdx)
    o.pullIndex = idx.pullIndex
    o.currentPullCandidates = {}
    o.candidateUniverseState =
        (idx.routeUniverseState == "AVAILABLE" and
         idx.dungeonUniverseState == "AVAILABLE") and "AVAILABLE" or "INCOMPLETE"

    if not o.exists then
        o.matchState = "UNKNOWN"; o.reason = "UNIT_DOES_NOT_EXIST"
        return o
    end
    if #idx.candidates == 0 then
        o.matchState = "UNKNOWN"; o.reason = "NO_ROUTE_LOADED"
        return o
    end

    -- ── Señal 1: npcID. Compatibilidad fuerte, pero no identidad por sí sola.
    if o.npcID then
        local n = idx.byNPC[o.npcID]
        if n and n > 0 then
            for _, c in ipairs(idx.candidates) do
                if c.npcID == o.npcID then
                    o.currentPullCandidates[#o.currentPullCandidates + 1] = c
                end
            end
            local routeN = idx.routeByNPC[o.npcID]
            local dungeonN = idx.dungeonByNPC[o.npcID]
            o.currentPullCandidateCount = n
            o.candidateCount = dungeonN or routeN or n

            -- Ya conocemos más de una asignación dentro de la propia ruta.
            if routeN and routeN > 1 then
                o.matchState = "AMBIGUOUS"
                o.reason = "NPCID_MULTIPLE_ROUTE_CLONES"
                o.confidence = "NPCID_COMPATIBLE"
                o.cloneState = "AMBIGUOUS"
                return o
            end

            -- Sin universo global no se puede convertir "aparece aquí" en
            -- "es este clon". Lo mismo si ruta y snapshot se contradicen.
            if idx.routeUniverseState ~= "AVAILABLE"
               or idx.dungeonUniverseState ~= "AVAILABLE"
               or not routeN or not dungeonN or dungeonN < routeN then
                o.matchState = "UNKNOWN"
                o.reason = "NPCID_UNIVERSE_INCOMPLETE"
                return o
            end

            -- Una copia adicional fuera de la ruta sigue siendo una asignación
            -- compatible para el nameplate y bloquea MATCH.
            if dungeonN > 1 then
                o.matchState = "AMBIGUOUS"
                o.reason = "NPCID_MULTIPLE_DUNGEON_CLONES"
                o.confidence = "NPCID_COMPATIBLE"
                o.cloneState = "AMBIGUOUS"
                return o
            end

            -- Único caso MATCH del baseline: una copia en la ruta, una copia
            -- en la mazmorra conocida y esa copia está en el pull actual.
            o.matchState = "MATCH"
            o.reason = "NPCID_GLOBALLY_UNIQUE"
            o.confidence = "NPCID_GLOBALLY_UNIQUE"
            o.cloneState = "RESOLVED"
            return o
        end
        o.matchState = "NO_MATCH"; o.reason = "NPCID_NOT_IN_CURRENT_PULL"
        o.confidence = "NPCID_EXACT"
        return o
    end

    -- ── Señal 2: tropas. Solo si la identidad no estaba disponible.
    if o.forcesState == "SECRET" then
        o.matchState = "UNKNOWN"; o.reason = "FORCES_SECRET"
        return o
    end
    if o.forcesState ~= "AVAILABLE" or not o.forces then
        o.matchState = "UNKNOWN"
        o.reason = (o.forcesState == "UNAVAILABLE") and "FORCES_UNAVAILABLE"
                                                    or "FORCES_NOT_RETURNED"
        return o
    end
    if o.forces == 0 then
        -- Un mob que no aporta tropas no tiene firma. Todos valen 0.
        o.matchState = "UNKNOWN"; o.reason = "FORCES_ZERO_NO_SIGNATURE"
        return o
    end

    local lista = idx.byForces[o.forces]
    if not lista or #lista == 0 then
        o.matchState = "NO_MATCH"; o.reason = "FORCES_NOT_IN_CURRENT_PULL"
        o.confidence = "FORCES_ONLY"
        return o
    end

    o.currentPullCandidates = lista
    o.candidateCount = #lista
    if #lista > 1 then
        o.matchState = "AMBIGUOUS"
        o.reason = "FORCES_COLLISION"
        o.confidence = "FORCES_COLLISION"
        o.cloneState = "AMBIGUOUS"
    else
        -- Ser único por tropas DENTRO del pull no excluye unidades de la misma
        -- firma en otros pulls o fuera de la ruta. La firma no da identidad.
        o.matchState = "UNKNOWN"
        o.reason = "FORCES_NOT_IDENTITY"
        o.confidence = "FORCES_ONLY"
    end
    return o
end

-- ═════════════════════════════════════════════════════════════════════════
-- FRONTERA PARA GUIDANCE (SEC-2)
--
-- Resolve() devuelve la observacion ENTERA porque /emp probe y el spike la
-- necesitan. Pero GuidanceEngine no debe verla: cualquier campo suyo puede
-- venir de una API de unidad, y transportarlo contamina lo que lo toque.
--
-- POR QUE NO BASTABA SANEAR DESPUES: el intento anterior validaba el motivo
-- contra una lista blanca y luego devolvia EL VALOR VALIDADO. Validar no es
-- sanear — comprobar que algo es aceptable y despues transportarlo sigue
-- transportandolo. Se veia en vivo: NOT_RUNNING (literal nuestro) se copiaba
-- bien; FORCES_SECRET (venido de aqui) no.
--
-- Esta funcion devuelve UNA de cuatro constantes DE ESTE FICHERO. No devuelve
-- el estado que calculo Resolve: lo compara y devuelve la constante propia.
-- Nada de la observacion cruza esta linea.
-- ═════════════════════════════════════════════════════════════════════════

local CANON_MATCH     = "MATCH"
local CANON_AMBIGUOUS = "AMBIGUOUS"
local CANON_NO_MATCH  = "NO_MATCH"
local CANON_UNKNOWN   = "UNKNOWN"

LiveEnemyResolver.GUIDANCE_STATES = {
    MATCH = CANON_MATCH, AMBIGUOUS = CANON_AMBIGUOUS,
    NO_MATCH = CANON_NO_MATCH, UNKNOWN = CANON_UNKNOWN,
}

-- Devuelve SOLO un string canonico. Ni tabla, ni motivo, ni contadores.
-- Ante cualquier problema: UNKNOWN, que no pinta nada.
function LiveEnemyResolver:ResolveForGuidance(unitToken, pullIdx)
    local ok, o = pcall(function() return self:Resolve(unitToken, pullIdx) end)
    if not ok or type(o) ~= "table" then return CANON_UNKNOWN end

    local st = rawget(o, "matchState")
    o = nil   -- la observacion muere aqui

    -- Comparar contra literales solo si se puede demostrar que es seguro:
    -- comparar un Secret Value es una de las operaciones prohibidas.
    if not esValorSeguro(st) or type(st) ~= "string" then return CANON_UNKNOWN end
    if st == "MATCH"     then return CANON_MATCH end
    if st == "AMBIGUOUS" then return CANON_AMBIGUOUS end
    if st == "NO_MATCH"  then return CANON_NO_MATCH end
    return CANON_UNKNOWN
end

-- ─────────────────────────────────────────────────────────────────────────
-- PASO 2 — SONDEO DE TODAS LAS PLACAS VISIBLES
--
-- Bajo comando, nunca por frame.
-- ─────────────────────────────────────────────────────────────────────────

local function tokenDe(np)
    if type(np) ~= "table" then return nil end
    local t = np.namePlateUnitToken or np.unitToken
    return type(t) == "string" and t or nil
end

function LiveEnemyResolver:ProbeAllPlates()
    local out, resumen = {}, { total = 0, match = 0, ambiguous = 0,
                               no_match = 0, unknown = 0, secretGUID = 0,
                               forcesOK = 0, forcesSecret = 0 }
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then
        return out, resumen, "sin API de nameplates"
    end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then
        return out, resumen, "GetNamePlates falló"
    end
    for _, np in ipairs(plates) do
        local tok = tokenDe(np)
        if tok then
            local o = self:Resolve(tok)
            out[#out + 1] = o
            resumen.total = resumen.total + 1
            local s = o.matchState or "UNKNOWN"
            resumen[s:lower()] = (resumen[s:lower()] or 0) + 1
            if o.guidSecret then resumen.secretGUID = resumen.secretGUID + 1 end
            if o.forcesState == "AVAILABLE" then resumen.forcesOK = resumen.forcesOK + 1 end
            if o.forcesSecret then resumen.forcesSecret = resumen.forcesSecret + 1 end
        end
    end
    return out, resumen
end

-- ─────────────────────────────────────────────────────────────────────────
-- INFORMES
-- ─────────────────────────────────────────────────────────────────────────

-- PASO 1: volcado por unidad. Compacto, para pegarlo en otro sitio.
-- PASO 1: volcado por unidad. SOLO ESTADOS (SEC-2).
--
-- Antes salian classification=elite, creatureType=(SECRET) y level=90: valores
-- crudos de Unit*. Ahora se imprime unicamente el ESTADO de cada lectura, que
-- es una constante nuestra. Se pierde detalle y se gana poder copiar el bloque.
function LiveEnemyResolver:UnitLines(unitToken)
    local o = self:Resolve(unitToken)
    local PM = AR.ProfileManager
    local ctx = PM and PM.GetContext and PM:GetContext() or nil

    -- Todo lo que se imprime aqui es un literal de Mitzu o un numero propio.
    -- Ni un solo valor devuelto por una API de unidad.
    local function estado(v)
        if not esValorSeguro(v) then return "SECRET" end
        if v == nil then return "UNAVAILABLE" end
        if type(v) ~= "string" then return "SECRET" end
        if v == "AVAILABLE" or v == "SECRET" or v == "UNKNOWN"
           or v == "UNAVAILABLE" or v == "LIMITED" or v == "NO_ES_CRIATURA" then
            -- Se devuelve la constante propia, no el valor comprobado.
            if v == "AVAILABLE" then return "AVAILABLE" end
            if v == "SECRET" then return "SECRET" end
            if v == "UNKNOWN" then return "UNKNOWN" end
            if v == "UNAVAILABLE" then return "UNAVAILABLE" end
            if v == "LIMITED" then return "LIMITED" end
            return "NOT_A_CREATURE"
        end
        return "UNRECOGNIZED"
    end

    local existe = (rawget(o, "exists") == true)
    local npcIDState = (rawget(o, "npcID") ~= nil) and "AVAILABLE" or "UNAVAILABLE"
    local canon = self:ResolveForGuidance(unitToken)

    local L = {}
    local function add(k, v) L[#L + 1] = k .. "=" .. v end
    add("unitToken", tostring(unitToken))
    add("UnitExists", existe and "true" or "false")
    add("enemyIdentityState", estado(rawget(o, "enemyIdentityState")))
    add("guidState", (rawget(o, "guidSecret") == true) and "SECRET" or
                     estado(rawget(o, "enemyIdentityState")))
    add("npcIDState", npcIDState)
    add("forcesState", estado(rawget(o, "forcesState")))
    add("nameState", estado(rawget(o, "nameState")))
    add("classificationState", estado(rawget(o, "classificationState")))
    add("creatureTypeState", estado(rawget(o, "creatureTypeState")))
    add("levelState", estado(rawget(o, "levelState")))
    add("healthMaxState", estado(rawget(o, "healthMaxState")))
    add("castTrackingState", estado(rawget(o, "castTrackingState")))
    add("currentDungeon", tostring(ctx and ctx.dungeonID or "nil"))
    add("currentPull", tostring(rawget(o, "pullIndex") or "nil"))
    add("matchState", canon)
    L[#L + 1] = "|cFF999999(solo estados: los valores de unidad no se imprimen)|r"
    return L
end

-- Diagnostico FASE 3A. Esta frontera devuelve exclusivamente constantes de
-- Mitzu: nunca GUID, npcID, fuerzas ni ningun otro valor de una API de unidad.
local function estadoDiagnostico(v)
    if not esValorSeguro(v) or type(v) ~= "string" then return "UNKNOWN" end
    if v == "AVAILABLE" then return "AVAILABLE" end
    if v == "SECRET" then return "SECRET" end
    if v == "UNAVAILABLE" then return "UNAVAILABLE" end
    if v == "INCOMPLETE" then return "INCOMPLETE" end
    if v == "YES" then return "YES" end
    if v == "NO" then return "NO" end
    return "UNKNOWN"
end

local function resultadoDiagnostico(v)
    if not esValorSeguro(v) or type(v) ~= "string" then return CANON_UNKNOWN end
    if v == "MATCH" then return CANON_MATCH end
    if v == "AMBIGUOUS" then return CANON_AMBIGUOUS end
    if v == "NO_MATCH" then return CANON_NO_MATCH end
    return CANON_UNKNOWN
end

local function motivoDiagnostico(v)
    if not esValorSeguro(v) or type(v) ~= "string" then return "UNAVAILABLE" end
    if v == "UNIT_DOES_NOT_EXIST" then return "UNIT_DOES_NOT_EXIST" end
    if v == "NO_ROUTE_LOADED" then return "NO_ROUTE_LOADED" end
    if v == "NPCID_MULTIPLE_ROUTE_CLONES" then return "NPCID_MULTIPLE_ROUTE_CLONES" end
    if v == "NPCID_UNIVERSE_INCOMPLETE" then return "NPCID_UNIVERSE_INCOMPLETE" end
    if v == "NPCID_MULTIPLE_DUNGEON_CLONES" then return "NPCID_MULTIPLE_DUNGEON_CLONES" end
    if v == "NPCID_NOT_IN_CURRENT_PULL" then return "NPCID_NOT_IN_CURRENT_PULL" end
    if v == "NPCID_GLOBALLY_UNIQUE" then return "NPCID_GLOBALLY_UNIQUE" end
    if v == "FORCES_SECRET" then return "FORCES_SECRET" end
    if v == "FORCES_UNAVAILABLE" then return "FORCES_UNAVAILABLE" end
    if v == "FORCES_NOT_RETURNED" then return "FORCES_NOT_RETURNED" end
    if v == "FORCES_ZERO_NO_SIGNATURE" then return "FORCES_ZERO_NO_SIGNATURE" end
    if v == "FORCES_NOT_IN_CURRENT_PULL" then return "FORCES_NOT_IN_CURRENT_PULL" end
    if v == "FORCES_COLLISION" then return "FORCES_COLLISION" end
    if v == "FORCES_NOT_IDENTITY" then return "FORCES_NOT_IDENTITY" end
    return "UNAVAILABLE"
end

function LiveEnemyResolver:ResolverDiagnosticLines(unitToken, pullIdx)
    local ok, o = pcall(function() return self:Resolve(unitToken, pullIdx) end)
    if not ok or type(o) ~= "table" then
        return {
            "unitExists=UNKNOWN",
            "guidState=UNKNOWN",
            "npcIDState=UNAVAILABLE",
            "candidateUniverseState=UNKNOWN",
            "resolverState=UNKNOWN",
            "resolverReason=UNAVAILABLE",
        }
    end

    return {
        "unitExists=" .. estadoDiagnostico(rawget(o, "unitExistsState")),
        "guidState=" .. estadoDiagnostico(rawget(o, "enemyIdentityState")),
        "npcIDState=" .. estadoDiagnostico(rawget(o, "npcIDState")),
        "candidateUniverseState=" .. estadoDiagnostico(rawget(o, "candidateUniverseState")),
        "resolverState=" .. resultadoDiagnostico(rawget(o, "matchState")),
        "resolverReason=" .. motivoDiagnostico(rawget(o, "reason")),
    }
end

function LiveEnemyResolver:ResolverDumpLines()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then
        return { "nameplates=UNAVAILABLE" }
    end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then
        return { "nameplates=UNAVAILABLE" }
    end

    local tokens = {}
    for _, np in ipairs(plates) do
        local tok = tokenDe(np)
        if tok then tokens[#tokens + 1] = tok end
    end
    table.sort(tokens)
    if #tokens == 0 then return { "nameplates=NONE" } end

    local L = {}
    for i, tok in ipairs(tokens) do
        if i > 1 then L[#L + 1] = " " end
        -- Los unit tokens de C_NamePlate no son identidad del enemigo. Aun asi,
        -- solo se imprimen despues de demostrar que son strings no secretos.
        L[#L + 1] = esValorSeguro(tok) and tok or "nameplate=UNKNOWN"
        local detail = self:ResolverDiagnosticLines(tok)
        for _, line in ipairs(detail) do L[#L + 1] = line end
    end
    L[#L + 1] = "|cFF999999(solo estados; identidad y valores de unidad omitidos)|r"
    return L
end


-- PASO 2: una línea por placa.
function LiveEnemyResolver:PlateLines()
    local obs, r, err = self:ProbeAllPlates()
    local L = {}
    if err then return { "|cFFff9922" .. err .. "|r" } end
    if r.total == 0 then
        return { "|cFFff9922No hay ninguna placa visible.|r Acércate a unos mobs." }
    end
    for _, o in ipairs(obs) do
        L[#L + 1] = string.format("%-12s forces=%-5s identity=%-11s %s%s|r%s",
            o.unitToken,
            (o.forcesState == "AVAILABLE") and tostring(o.forces or "?") or o.forcesState,
            o.npcID and ("npc:" .. o.npcID) or o.enemyIdentityState,
            (o.matchState == "MATCH" and "|cFF21de66")
              or (o.matchState == "AMBIGUOUS" and "|cFFf7d470")
              or (o.matchState == "NO_MATCH" and "|cFFff5555") or "|cFF999999",
            o.matchState,
            o.candidateCount and (" (" .. o.candidateCount .. " cand.)") or "")
    end
    L[#L + 1] = string.format(
        "|cFFe8b84atotal=%d match=%d ambiguous=%d no_match=%d unknown=%d · guidSecret=%d forcesOK=%d forcesSecret=%d|r",
        r.total, r.match or 0, r.ambiguous or 0, r.no_match or 0, r.unknown or 0,
        r.secretGUID, r.forcesOK, r.forcesSecret)
    return L
end

-- PASO 5: colisiones de firma de la ruta cargada. No necesita combate.
function LiveEnemyResolver:ForceMapLines()
    local DS = AR.DataStructure
    local i = DS and DS:Get()
    if not i then return { "|cFFff9922No hay ninguna ruta indexada.|r" } end
    local L = { "|cFFe8b84a═══ FIRMAS DE TROPAS POR PULL ═══|r" }
    local total, unicos, ambig, sinFirma = 0, 0, 0, 0
    local pullsConColision = 0

    for p = 1, (i.pullCount or 0) do
        local idx = self:BuildCurrentPullIndex(p)
        local firmas, n = {}, 0
        for f, lista in pairs(idx.byForces) do
            firmas[#firmas + 1] = { f = f, n = #lista }
            n = n + #lista
        end
        table.sort(firmas, function(a, b) return a.f < b.f end)
        if n > 0 or idx.noForces > 0 then
            local partes, hayCol = {}, false
            for _, e in ipairs(firmas) do
                partes[#partes + 1] = string.format("%d→%d%s", e.f, e.n,
                    e.n == 1 and "" or "!")
                if e.n == 1 then unicos = unicos + 1 else ambig = ambig + e.n; hayCol = true end
            end
            if idx.noForces > 0 then
                partes[#partes + 1] = string.format("0→%d(sin firma)", idx.noForces)
            end
            if hayCol then pullsConColision = pullsConColision + 1 end
            total = total + n + idx.noForces
            sinFirma = sinFirma + idx.noForces
            L[#L + 1] = string.format("Pull %-3d %s", p, table.concat(partes, "  "))
        end
    end

    L[#L + 1] = string.format("|cFFe8b84atotal=%d unicos=%d ambiguos=%d sinFirma=%d pullsConColision=%d|r",
        total, unicos, ambig, sinFirma, pullsConColision)
    L[#L + 1] = string.format("force_only_match_rate=%.1f%%",
        total > 0 and (100 * unicos / total) or 0)
    L[#L + 1] = "|cFF999999(! = varias unidades comparten esa firma en el mismo pull)|r"
    return L
end

-- PASO 9: marcar SOLO los MATCH. Diagnóstico, no comportamiento normal.
function LiveEnemyResolver:MarkMatchesOnly()
    local RA = AR.RouteArrows
    if not RA then return 0, 0, "RouteArrows no cargado" end
    local obs, r, err = self:ProbeAllPlates()
    if err then return 0, 0, err end
    RA:ClearAll()
    local marcadas = 0
    for _, o in ipairs(obs) do
        -- AMBIGUOUS, NO_MATCH y UNKNOWN NO se marcan. Cero flechas antes que
        -- una flecha equivocada.
        if o.matchState == "MATCH" then
            if RA:MarkUnit(o.unitToken) then marcadas = marcadas + 1 end
        end
    end
    return marcadas, r.total, nil, r
end

return LiveEnemyResolver
