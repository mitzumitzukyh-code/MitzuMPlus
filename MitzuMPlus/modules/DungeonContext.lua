-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · DungeonContext v1.0
--
-- DÓNDE ESTOY Y EN QUÉ PUNTO DE LA LLAVE. Fuente única de verdad.
--
-- Antes esta pregunta se contestaba en tres sitios a la vez (Core, Helpers y
-- ProfileManager), cada uno con su matiz, y ninguno distinguía "estoy dentro
-- de la mazmorra" de "la llave está corriendo". De ahí el bug que se vio en
-- vivo: "M+ Iniciada: Estanques de Vida Rubí +4" ANTES de meter la piedra.
--
-- ═════════════════════════════════════════════════════════════════════════
-- BUG CTX-1 — CHALLENGE_MODE_START NO SIGNIFICA QUE LA LLAVE HAYA EMPEZADO
--
--   expected: CHALLENGE_MODE_START se dispara al arrancar la llave.
--   observed: se dispara al ENTRAR a la mazmorra en modo piedra, antes de
--             insertarla. Core:OnChallengeStart colgaba de él y creaba la run
--             entera —con nombre y nivel— sin que hubiera llave.
--   decision: el evento pasa a ser un DISPARADOR DE COMPROBACIÓN, no una
--             autoridad. Quien decide es C_ChallengeMode.IsChallengeModeActive().
--             Y como entre el evento y el arranque real hay una cuenta atrás,
--             se vuelve a comprobar con un temporizador acotado en vez de
--             creerse el evento o perder el arranque.
-- ═════════════════════════════════════════════════════════════════════════
--
-- ESTADOS
--   OUTSIDE                 fuera de cualquier mazmorra
--   IN_UNSUPPORTED_DUNGEON  dentro, pero no es una M+ que conozcamos
--   PRE_KEY                 dentro de la mazmorra, la llave NO ha empezado
--   RUNNING                 la llave está corriendo de verdad
--   COMPLETED               la llave terminó
--   RESET                   la llave se reinició o se abandonó
--
-- En PRE_KEY se puede precargar la ruta, construir el grupo y preparar la UI.
-- Lo que NO se puede es decir que la llave ha empezado ni contar progreso.
--
-- QUÉ NO HACE: no toca RouteArrows, no mueve pulls, no cuenta tropas. Solo
-- sabe dónde estás y lo publica.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local DungeonContext = {}
MitzuMPlus.DungeonContext = DungeonContext

local OUTSIDE      = "OUTSIDE"
local UNSUPPORTED  = "IN_UNSUPPORTED_DUNGEON"
local PRE_KEY      = "PRE_KEY"
local RUNNING      = "RUNNING"
local COMPLETED    = "COMPLETED"
local RESET        = "RESET"

DungeonContext.STATES = {
    OUTSIDE = OUTSIDE, IN_UNSUPPORTED_DUNGEON = UNSUPPORTED, PRE_KEY = PRE_KEY,
    RUNNING = RUNNING, COMPLETED = COMPLETED, RESET = RESET,
}

DungeonContext._state          = OUTSIDE
DungeonContext._previousState  = nil
DungeonContext._lastEvent      = nil
DungeonContext._lastTransition = nil
DungeonContext._challengeMapID = nil
DungeonContext._instanceMapID  = nil
DungeonContext._keystoneLevel  = nil
DungeonContext._dungeonName    = nil
DungeonContext._pendingChecks  = 0

-- ─────────────────────────────────────────────────────────────────────────
-- LECTURA DEL CLIENTE
-- ─────────────────────────────────────────────────────────────────────────

-- ═════════════════════════════════════════════════════════════════════════
-- BUG CTX-3 — instanceMapID salia SIEMPRE nil.
--
-- Este helper devolvia solo TRES valores (`local ok, a, b, c = pcall(...)`) y
-- el instanceID es el OCTAVO retorno de GetInstanceInfo. En vivo se veia asi:
--     instanceMapID=nil   keystoneLevel=0
-- Sin instanceID no habia forma de reconocer la mazmorra antes de la llave, y
-- el estado caia a IN_UNSUPPORTED_DUNGEON estando dentro de Ruby Life Pools.
--
-- Ahora se recogen TODOS los retornos en una tabla y se nombran por su
-- posicion real, documentada justo encima de instanceInfo().
-- ═════════════════════════════════════════════════════════════════════════
-- WoW usa Lua 5.1, donde `unpack` es global. Los bancos de pruebas corren
-- sobre 5.4, donde vive en table. El alias cubre los dos.
local unpack = rawget(_G, "unpack") or table.unpack

local function pcallAll(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if not r[1] then return nil end
    return unpack(r, 2)
end

local function pcallOr(fn, ...)
    return (pcallAll(fn, ...))
end

-- La autoridad, y la unica. Todo lo demas es contexto.
local function challengeActive()
    local api = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
    return pcallOr(api) == true
end

local function activeChallengeMapID()
    local api = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID
    local id = tonumber(pcallOr(api))
    if id and id > 0 then return id end
    return nil
end

local function keystoneLevel()
    local api = C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo
    local lvl = tonumber(pcallOr(api))
    -- Fuera de la llave devuelve 0, que no es un nivel: es "no hay llave".
    if lvl and lvl > 0 then return lvl end
    return nil
end

-- GetInstanceInfo devuelve, en orden:
--   name, instanceType, difficultyID, difficultyName, maxPlayers,
--   dynamicDifficulty, isDynamic, instanceID, instanceGroupSize, LfgDungeonID
local function instanceInfo()
    local name, kind, difficultyID, _, _, _, _, instanceID, groupSize =
        pcallAll(GetInstanceInfo)
    return name, kind, difficultyID, tonumber(instanceID), tonumber(groupSize)
end

local function bestMapForPlayer()
    local api = C_Map and C_Map.GetBestMapForUnit
    return tonumber(pcallOr(api, "player"))
end


-- ─────────────────────────────────────────────────────────────────────────
-- IDENTIDAD DE MAZMORRA
-- ─────────────────────────────────────────────────────────────────────────

function DungeonContext:IsSupportedDungeon(mapID)
    mapID = mapID or self._dungeonKey
    return mapID ~= nil
end

function DungeonContext:IsRecognizedDungeon()
    return self._dungeonKey ~= nil
end

-- La identidad canonica de la mazmorra: existe con y sin llave puesta.
-- NO es lo mismo que challengeMapID, que solo existe con la llave activa.
function DungeonContext:GetDungeonKey()
    return self._dungeonKey and tostring(self._dungeonKey) or nil
end

function DungeonContext:GetUIMapID()        return self._uiMapID end
function DungeonContext:GetIdentitySource() return self._identitySource or "UNKNOWN" end

function DungeonContext:GetChallengeMapID() return self._challengeMapID end
function DungeonContext:GetInstanceMapID()  return self._instanceMapID end
function DungeonContext:GetKeystoneLevel()  return self._keystoneLevel end
function DungeonContext:GetDungeonName()    return self._dungeonName end
function DungeonContext:GetState()          return self._state end
function DungeonContext:IsChallengeActive() return challengeActive() end

-- ─────────────────────────────────────────────────────────────────────────
-- TRANSICIONES
--
-- Un cambio de estado emite UN evento. Si Refresh() no cambia nada, no se
-- emite nada: sin esto, dos eventos del cliente que describen la misma
-- situación producirían dos avisos idénticos, que es justo el "Todo listo
-- para esta mazmorra" duplicado que se vio en vivo (BUG CTX-2).
-- ─────────────────────────────────────────────────────────────────────────

local EVENTO_DE_ESTADO = {
    [PRE_KEY]   = "MITZU_PRE_KEY",
    [RUNNING]   = "MITZU_KEY_STARTED",
    [COMPLETED] = "MITZU_KEY_COMPLETED",
    [RESET]     = "MITZU_KEY_RESET",
}

function DungeonContext:_Transition(newState, why)
    if newState == self._state then return false end
    self._previousState  = self._state
    self._state          = newState
    self._lastTransition = string.format("%s -> %s (%s)",
        tostring(self._previousState), tostring(newState), tostring(why or "?"))

    local bus = MitzuMPlus.EventBus
    if bus then
        local ev = EVENTO_DE_ESTADO[newState]
        if ev then bus:Emit(ev, self) end
        bus:Emit("MITZU_DUNGEON_STATE_CHANGED", newState, self._previousState, self)
    end
    return true
end

-- ─────────────────────────────────────────────────────────────────────────
-- REFRESH
-- ─────────────────────────────────────────────────────────────────────────

function DungeonContext:Refresh(why)
    -- BUG CTX-5: esto comparaba contra _challengeMapID, que es nil mientras no
    -- hay llave. Sin piedra puesta, `key ~= prevMap` era siempre cierto y
    -- MITZU_DUNGEON_CHANGED se emitia en CADA refresco -> volvia el informe
    -- duplicado por otra puerta. Lo que hay que comparar es la identidad
    -- canonica anterior.
    local prevKey = self._dungeonKey

    local iname, kind, _, instanceID, groupSize = instanceInfo()
    self._instanceMapID = instanceID
    self._instanceName  = iname
    self._instanceGroupSize = groupSize
    self._difficultyID  = nil

    local inDungeon = (kind == "party" or kind == "scenario")
    if not inDungeon then
        self._challengeMapID = nil
        self._dungeonKey     = nil
        self._keystoneLevel  = nil
        self._dungeonName    = nil
        self._uiMapID        = nil
        self._identitySource = "UNKNOWN"
        self:_Transition(OUTSIDE, why or "fuera de instancia")
        return self._state
    end

    self._uiMapID = bestMapForPlayer()

    -- ── PRIORIDAD DE RESOLUCION ──────────────────────────────────────────
    -- 1) Con la llave corriendo, C_ChallengeMode es exacto y ademas ENSEÑA:
    --    ahi es cuando se aprende el par instanceID <-> challengeMapID.
    -- 2) Sin llave, la identidad sale del mapa fisico via DungeonRegistry.
    --
    -- "¿esta activa la challenge?" NUNCA decide "¿es una mazmorra soportada?".
    -- Confundir esas dos preguntas fue el BUG CTX-4: dentro de Ruby Life Pools
    -- sin piedra, el addon decia IN_UNSUPPORTED_DUNGEON.
    local activeID = activeChallengeMapID()
    local REG = MitzuMPlus.DungeonRegistry
    local key, name, source

    if activeID then
        key, source = activeID, "ACTIVE_CHALLENGE"
        name = REG and REG:GetName(activeID)
        if REG then REG:Learn(activeID, self._instanceMapID, self._uiMapID) end
    elseif REG then
        key, name, source = REG:Resolve(self._instanceMapID, self._uiMapID, iname)
    end

    self._challengeMapID = activeID
    self._dungeonKey     = key
    self._dungeonName    = name or iname
    self._identitySource = source or "UNKNOWN"
    self._keystoneLevel  = keystoneLevel()

    if key and key ~= prevKey then
        local bus = MitzuMPlus.EventBus
        if bus then bus:Emit("MITZU_DUNGEON_CHANGED", key, prevKey, self) end
    end

    if not key then
        self:_Transition(UNSUPPORTED, why or "mazmorra no reconocida")
        return self._state
    end

    if challengeActive() then
        self:_Transition(RUNNING, why or "IsChallengeModeActive()")
    else
        -- COMPLETED no se degrada a PRE_KEY: terminar una llave y seguir
        -- dentro de la instancia no es estar esperando a empezarla.
        if self._state ~= COMPLETED then
            self:_Transition(PRE_KEY, why or "dentro, sin llave activa")
        end
    end
    return self._state
end

-- ─────────────────────────────────────────────────────────────────────────
-- COMPROBACIÓN DIFERIDA TRAS CHALLENGE_MODE_START
--
-- Entre el evento y el arranque real hay una cuenta atrás. Ni creerse el
-- evento (arrancaría antes de tiempo, BUG CTX-1) ni ignorarlo (se perdería el
-- arranque). Se comprueba varias veces, espaciado y con final: nada de
-- OnUpdate ni de sondeo infinito.
-- ─────────────────────────────────────────────────────────────────────────

local MAX_CHECKS = 15   -- ~15 s, de sobra para una cuenta atrás de 10

function DungeonContext:_ScheduleActivationCheck()
    if not (C_Timer and C_Timer.After) then return end
    if self._pendingChecks > 0 then return end   -- ya hay una campaña en curso
    self._pendingChecks = MAX_CHECKS

    local function tick()
        self._pendingChecks = self._pendingChecks - 1
        if self._state == RUNNING then
            self._pendingChecks = 0
            return
        end
        self:Refresh("sondeo tras CHALLENGE_MODE_START")
        if self._state ~= RUNNING and self._pendingChecks > 0 then
            C_Timer.After(1, tick)
        else
            self._pendingChecks = 0
        end
    end
    C_Timer.After(1, tick)
end

-- ─────────────────────────────────────────────────────────────────────────
-- EVENTOS DEL CLIENTE
-- ─────────────────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("CHALLENGE_MODE_START")
frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
frame:RegisterEvent("CHALLENGE_MODE_RESET")

frame:SetScript("OnEvent", function(_, event)
    DungeonContext._lastEvent = event

    if event == "CHALLENGE_MODE_COMPLETED" then
        DungeonContext:_Transition(COMPLETED, event)
        return
    end

    if event == "CHALLENGE_MODE_RESET" then
        DungeonContext:_Transition(RESET, event)
        -- Tras el reinicio se vuelve a mirar dónde estamos de verdad.
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() DungeonContext:Refresh("tras reset") end)
        end
        return
    end

    DungeonContext:Refresh(event)

    -- PLAYER_ENTERING_WORLD cubre el /reload durante una llave: si sigue
    -- activa, Refresh ya habrá puesto RUNNING sin necesidad de volver a ver
    -- CHALLENGE_MODE_START.
    if event == "CHALLENGE_MODE_START" and DungeonContext._state ~= RUNNING then
        DungeonContext:_ScheduleActivationCheck()
    end
end)

-- ─────────────────────────────────────────────────────────────────────────
-- INFORME
-- ─────────────────────────────────────────────────────────────────────────

function DungeonContext:StatusLines()
    local L = {}
    L[#L + 1] = "dungeonKey=" .. tostring(self:GetDungeonKey())
    L[#L + 1] = "dungeonName=" .. tostring(self._dungeonName)
    L[#L + 1] = "instanceMapID=" .. tostring(self._instanceMapID)
    L[#L + 1] = "uiMapID=" .. tostring(self._uiMapID)
    L[#L + 1] = "challengeMapID=" .. tostring(self._challengeMapID)
    L[#L + 1] = "identitySource=" .. tostring(self._identitySource)
    L[#L + 1] = "state=" .. tostring(self._state)
    L[#L + 1] = "challengeActive=" .. tostring(challengeActive())
    L[#L + 1] = "keystoneLevel=" .. tostring(self._keystoneLevel)
    L[#L + 1] = "recognizedDungeon=" .. tostring(self:IsRecognizedDungeon())
    L[#L + 1] = "recognized=" .. tostring(self:IsRecognizedDungeon())
    return L
end

function DungeonContext:LifecycleLines()
    return {
        "previousState=" .. tostring(self._previousState),
        "currentState=" .. tostring(self._state),
        "lastTransition=" .. tostring(self._lastTransition),
        "lastEvent=" .. tostring(self._lastEvent),
        "pendingActivationChecks=" .. tostring(self._pendingChecks),
    }
end

return DungeonContext
