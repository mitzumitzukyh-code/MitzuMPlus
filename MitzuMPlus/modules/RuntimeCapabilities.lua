-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · RuntimeCapabilities v1.0
--
-- QUÉ PUEDE HACER EL ADDON DE VERDAD, AQUÍ Y AHORA.
--
-- En Midnight 12.1 la pregunta "¿puedo leer esto?" ya no tiene una respuesta
-- fija: depende del mapa, del combate, de si la unidad tiene la identidad
-- restringida y de si Blizzard devuelve un Secret Value. Un addon que asume
-- que sí puede acaba con features que fallan en silencio o, peor, que se
-- inventan el dato.
--
-- Este módulo SONDEA y responde con uno de estos estados:
--
--   AVAILABLE        se puede usar ahora
--   AVAILABLE_ASYNC  se puede, pero la respuesta llega más tarde
--   LIMITED          se puede en parte, con condiciones documentadas
--   SECRET           existe pero devuelve un Secret Value: no se puede
--                    comparar, concatenar ni convertir
--   UNAVAILABLE      no existe o el cliente lo prohíbe
--   UNKNOWN          todavía no se ha podido comprobar
--
-- REGLA: nada aquí dentro convierte UNKNOWN en AVAILABLE por conveniencia. Si
-- no se ha podido sondear, se dice que no se ha podido sondear.
--
-- QUÉ NO ES: no decide nada, no registra eventos de juego y no toca la UI.
-- Es una respuesta a una pregunta. Quien decide qué hacer con la respuesta
-- vive fuera.
--
-- SEGURIDAD CON SECRET VALUES
-- Sondear una capacidad no puede romper el addon. Todas las llamadas van en
-- pcall, y ningún valor sondeado se compara, concatena ni pasa por tonumber:
-- solo se le pregunta a `issecretvalue` y se mira su `type`. Ese es el único
-- trato seguro con un valor que puede ser secreto.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local RuntimeCapabilities = {}
MitzuMPlus.RuntimeCapabilities = RuntimeCapabilities

local _issecretvalue = rawget(_G, "issecretvalue")

local AVAILABLE       = "AVAILABLE"
local AVAILABLE_ASYNC = "AVAILABLE_ASYNC"
local LIMITED         = "LIMITED"
local SECRET          = "SECRET"
local UNAVAILABLE     = "UNAVAILABLE"
local UNKNOWN         = "UNKNOWN"

RuntimeCapabilities.STATES = {
    AVAILABLE = AVAILABLE, AVAILABLE_ASYNC = AVAILABLE_ASYNC, LIMITED = LIMITED,
    SECRET = SECRET, UNAVAILABLE = UNAVAILABLE, UNKNOWN = UNKNOWN,
}

-- Un estado es USABLE si se puede actuar sobre él sin inventarse nada.
-- LIMITED entra: significa "se puede, con condiciones", y quien lo consulta
-- ya sabe cuáles. SECRET y UNKNOWN no entran nunca.
local USABLE = {
    [AVAILABLE] = true,
    [AVAILABLE_ASYNC] = true,
    [LIMITED] = true,
}

-- [clave] = { state, why, probedAt }
RuntimeCapabilities._caps = {}
RuntimeCapabilities._lastProbe = nil

local function set(key, state, why)
    RuntimeCapabilities._caps[key] = {
        state = state,
        why   = why,
        probedAt = (GetTime and GetTime()) or 0,
    }
    return state
end

function RuntimeCapabilities:Get(key)
    local c = self._caps[key]
    return c and c.state or UNKNOWN
end

function RuntimeCapabilities:Why(key)
    local c = self._caps[key]
    return c and c.why or "sin sondear"
end

function RuntimeCapabilities:IsUsable(key)
    return USABLE[self:Get(key)] == true
end

-- Para que otros módulos anoten lo que OBSERVAN en vivo, que siempre gana al
-- sondeo teórico: si el resolver ve que un GUID llega secreto, eso es más
-- cierto que cualquier comprobación de existencia de la API.
function RuntimeCapabilities:SetObservedState(key, state, why)
    if not self.STATES[state] then return false, "estado no válido" end
    local antes = self:Get(key)
    set(key, state, why or "observado en vivo")
    -- Solo los CAMBIOS van a la caja negra de QA: una degradación en vivo es
    -- exactamente lo que se quiere ver en un informe, repetirla no.
    local FR = MitzuMPlus.FlightRecorder
    if antes ~= state and FR and FR.Record then
        FR:Record("CAPABILITY", "CHANGED", { key = key, from = antes, to = state })
    end
    return true
end

-- ─────────────────────────────────────────────────────────────────────────
-- HERRAMIENTAS DE SONDEO
-- ─────────────────────────────────────────────────────────────────────────

local function esSecreto(v)
    if not _issecretvalue then return false end
    local ok, res = pcall(_issecretvalue, v)
    return ok and res == true
end

-- Llama a una API y clasifica lo que devuelve SIN tocar el valor. Nunca se
-- compara ni se convierte: solo se mira si es secreto y de qué tipo es.
local function sondear(fn, ...)
    if type(fn) ~= "function" then return UNAVAILABLE, "la API no existe" end
    local ok, v = pcall(fn, ...)
    if not ok then return UNAVAILABLE, "la llamada falló" end
    if v == nil then return UNKNOWN, "devolvió nil" end
    if esSecreto(v) then return SECRET, "devolvió un Secret Value" end
    return AVAILABLE, "devolvió " .. type(v)
end

-- Una placa enemiga cualquiera, para sondear lo que solo se puede sondear
-- sobre un enemigo de verdad.
local function algunaPlaca()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return nil end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return nil end
    for _, np in ipairs(plates) do
        local t = type(np) == "table" and (np.namePlateUnitToken or np.unitToken) or nil
        if type(t) == "string" then return t end
    end
    return nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- SONDEO
-- ─────────────────────────────────────────────────────────────────────────

function RuntimeCapabilities:Probe()
    self._lastProbe = (GetTime and GetTime()) or 0

    -- ── Combat log ────────────────────────────────────────────────────────
    -- No es un sondeo: es un hecho ya verificado en este cliente. Registrar
    -- COMBAT_LOG_EVENT_UNFILTERED se rechazó seis veces por sesión desde
    -- código limpio y sin taint (BUG CLEU-1, EventTracker). La función
    -- CombatLogGetCurrentEventInfo sigue existiendo, y por eso comprobar su
    -- existencia daría un falso AVAILABLE: lo que está cerrado es el EVENTO.
    set("combatLog", UNAVAILABLE,
        "COMBAT_LOG_EVENT_UNFILTERED está cerrado a addons en Midnight (BUG CLEU-1)")

    -- ── Challenge mode ────────────────────────────────────────────────────
    if C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
        set("challengeMode", AVAILABLE, "C_ChallengeMode.GetActiveChallengeMapID")
    else
        set("challengeMode", UNAVAILABLE, "C_ChallengeMode no disponible")
    end

    -- ── Identidad del grupo ───────────────────────────────────────────────
    do
        local st, why = sondear(UnitGUID, "player")
        set("partyIdentity", st, "UnitGUID('player'): " .. why)
    end

    -- ── Roles ─────────────────────────────────────────────────────────────
    if type(UnitGroupRolesAssigned) == "function" then
        set("partyRoles", AVAILABLE, "UnitGroupRolesAssigned")
    else
        set("partyRoles", UNAVAILABLE, "UnitGroupRolesAssigned no existe")
    end

    -- ── Clase ─────────────────────────────────────────────────────────────
    -- UnitClassBase es la forma estable: devuelve el classFile ("DEATHKNIGHT"),
    -- que no depende del idioma del cliente.
    if type(UnitClassBase) == "function" then
        set("partyClass", AVAILABLE, "UnitClassBase")
    elseif type(UnitClass) == "function" then
        set("partyClass", LIMITED, "solo UnitClass: el nombre viene localizado")
    else
        set("partyClass", UNAVAILABLE, "sin API de clase")
    end

    -- ── Spec propia ───────────────────────────────────────────────────────
    if C_SpecializationInfo and type(C_SpecializationInfo.GetSpecialization) == "function" then
        set("playerSpec", AVAILABLE, "C_SpecializationInfo.GetSpecialization")
    elseif type(rawget(_G, "GetSpecialization")) == "function" then
        set("playerSpec", LIMITED, "solo el global GetSpecialization, que está deprecado")
    else
        set("playerSpec", UNAVAILABLE, "sin API de especialización")
    end

    -- ── Specs ajenas ──────────────────────────────────────────────────────
    -- Siempre ASYNC: NotifyInspect va y vuelve por el servidor, que además
    -- puede throttlear la petición y no contestar nunca.
    do
        local tieneInspect = (C_SpecializationInfo
                              and type(C_SpecializationInfo.GetInspectSpecialization) == "function")
                             or type(rawget(_G, "GetInspectSpecialization")) == "function"
        if tieneInspect and type(NotifyInspect) == "function" then
            set("partySpecs", AVAILABLE_ASYNC,
                "NotifyInspect + INSPECT_READY; el servidor puede throttlear")
        else
            set("partySpecs", UNAVAILABLE, "sin API de inspección")
        end
    end

    -- ── Nameplates ────────────────────────────────────────────────────────
    if C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function" then
        set("nameplates", AVAILABLE, "C_NamePlate.GetNamePlateForUnit")
    else
        set("nameplates", UNAVAILABLE, "C_NamePlate no disponible")
    end

    -- El anclaje de flechas ya no se sondea aqui: las flechas viven en el addon
    -- aparte MitzuRouteArrows (/mra plates), y MitzuMPlus no las conoce.

    -- ── Lo que solo se puede sondear sobre un enemigo real ────────────────
    local placa = algunaPlaca()
    if not placa then
        set("enemyIdentity", UNKNOWN, "no hay ninguna placa visible para sondear")
        set("enemyForcesPerUnit", UNKNOWN, "no hay ninguna placa visible para sondear")
        set("enemyCastTracking", UNKNOWN, "no hay ninguna placa visible para sondear")
    else
        -- Identidad del enemigo. Aquí es donde Midnight aprieta: el GUID puede
        -- llegar como Secret Value y entonces no se puede partir ni comparar.
        local st, why = sondear(UnitGUID, placa)
        set("enemyIdentity", st, string.format("UnitGUID('%s'): %s", placa, why))

        -- Tropas que aporta ESA unidad. Ojo con lo que significa: no es el
        -- progreso de la run (BUG EF-1, KeystoneTracker), es cuánto suma ese
        -- mob concreto. Como firma para emparejar es justo lo que hace falta.
        if C_ScenarioInfo and type(C_ScenarioInfo.GetUnitCriteriaProgressValues) == "function" then
            local st2, why2 = sondear(C_ScenarioInfo.GetUnitCriteriaProgressValues, placa)
            -- Fuera de una llave la API existe pero no tiene criterio que
            -- devolver. Eso es UNKNOWN, no UNAVAILABLE: dentro de una M+
            -- puede contestar perfectamente.
            if st2 == UNKNOWN then
                why2 = why2 .. " (¿estás fuera de una llave?)"
            end
            set("enemyForcesPerUnit", st2,
                "C_ScenarioInfo.GetUnitCriteriaProgressValues: " .. why2)
        else
            set("enemyForcesPerUnit", UNAVAILABLE,
                "C_ScenarioInfo.GetUnitCriteriaProgressValues no existe")
        end

        -- Casts del enemigo: la API existe siempre; lo que no siempre hay es
        -- un cast en curso. Por eso no se puede concluir nada de un nil.
        if type(UnitCastingInfo) == "function" then
            set("enemyCastTracking", LIMITED,
                "UnitCastingInfo sobre la placa; hay que sondearlo, no hay evento propio")
        else
            set("enemyCastTracking", UNAVAILABLE, "UnitCastingInfo no existe")
        end
    end

    -- ── Muerte de enemigos ────────────────────────────────────────────────
    -- Sin combat log no hay ningún evento que diga "este mob ha muerto".
    -- NAME_PLATE_UNIT_REMOVED NO es eso: una placa desaparece por rango,
    -- cámara, reciclaje o phasing. Lo más cerca que se puede estar es ver
    -- subir el recuento oficial de tropas, que dice CUÁNTO ha muerto pero no
    -- QUIÉN.
    set("enemyDeathTracking", LIMITED,
        "sin CLEU; solo el recuento oficial de tropas, que dice cuánto pero no quién")

    return self._caps
end

-- ─────────────────────────────────────────────────────────────────────────
-- INFORME
-- ─────────────────────────────────────────────────────────────────────────

local ORDEN = {
    "combatLog", "challengeMode",
    "partyIdentity", "partyRoles", "partyClass", "playerSpec", "partySpecs",
    "nameplates",
    "enemyIdentity", "enemyForcesPerUnit", "enemyDeathTracking", "enemyCastTracking",
}

local COLOR = {
    [AVAILABLE]       = "|cFF21de66",
    [AVAILABLE_ASYNC] = "|cFF8fd3ff",
    [LIMITED]         = "|cFFf7d470",
    [SECRET]          = "|cFFff9922",
    [UNAVAILABLE]     = "|cFFff5555",
    [UNKNOWN]         = "|cFF999999",
}

function RuntimeCapabilities:StatusLines(verbose)
    if not self._lastProbe then self:Probe() end
    local out = { "|cFFe8b84a═══ CAPACIDADES EN ESTE CLIENTE ═══|r" }
    for _, key in ipairs(ORDEN) do
        local state = self:Get(key)
        out[#out + 1] = string.format("%-20s %s%s|r", key, COLOR[state] or "", state)
        if verbose then
            out[#out + 1] = "                     |cFF999999" .. tostring(self:Why(key)) .. "|r"
        end
    end
    if self:Get("enemyIdentity") == UNKNOWN or self:Get("enemyForcesPerUnit") == UNKNOWN then
        out[#out + 1] = "|cFFff9922Apunta a un mob (que se vea su placa) y repite para sondear al enemigo.|r"
    end
    return out
end

-- Formato plano, para pegarlo en un informe. Sin colores ni adornos.
function RuntimeCapabilities:Matrix()
    if not self._lastProbe then self:Probe() end
    local out = {}
    for _, key in ipairs(ORDEN) do
        out[#out + 1] = key .. "=" .. self:Get(key)
    end
    return out
end

return RuntimeCapabilities
