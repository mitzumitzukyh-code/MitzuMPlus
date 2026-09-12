-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · RunSession v1  —  ¿sigo en LA MISMA ejecución?
--
-- La pregunta que responde este módulo no es "¿estoy en Ruby con una +2?".
-- Es "¿esta es exactamente la misma partida que estaba jugando hace un minuto,
-- antes del /reload?". Dos +2 seguidas de Ruby son indistinguibles por
-- mazmorra y nivel, y restaurar el pull 7 de la anterior sería peor que no
-- restaurar nada.
--
-- ═════════════════════════════════════════════════════════════════════════
-- LA HUELLA: EL INSTANTE DE INICIO, NO LA MAZMORRA
--
-- Blizzard no da un identificador de ejecución de Challenge Mode. Pero sí da
-- el CRONÓMETRO, y lo mantiene el servidor:
--
--     GetWorldElapsedTimers()  ->  ids de temporizador
--     GetWorldElapsedTime(id)  ->  _, elapsedTime, type
--     type == LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE
--
-- (así lo usa AngryKeystones en Splits.lua:7 y Gossip.lua:28)
--
-- De ahí sale  startedAt = time() - elapsed,  que es:
--   · ESTABLE entre reloads — el cronómetro sigue corriendo, así que la resta
--     da el mismo instante antes y después
--   · DISTINTO en cada ejecución — dos +2 de la misma mazmorra empiezan en
--     momentos distintos
--
-- Eso es lo que convierte "misma mazmorra y mismo nivel" en "misma partida".
-- ═════════════════════════════════════════════════════════════════════════
--
-- REGLA QUE MANDA SOBRE TODAS: ante la duda, NO se restaura. Pedirle al
-- jugador que elija el pull es una molestia; devolverle el progreso de una
-- partida de ayer es un dato falso que además parece correcto.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local RunSession = {}
MitzuMPlus.RunSession = RunSession

RunSession.SCHEMA = 1

-- Estados de recuperación
local NONE, PENDING, RESTORED = "NONE", "PENDING", "RESTORED"
local REJECTED, EXPIRED, CLEARED = "REJECTED", "EXPIRED", "CLEARED"
RunSession.STATES = {
    NONE = NONE, PENDING = PENDING, RESTORED = RESTORED,
    REJECTED = REJECTED, EXPIRED = EXPIRED, CLEARED = CLEARED,
}

-- Margen de la huella. El cronómetro se lee con un segundo de resolución y
-- entre el reload y la lectura pasan unos segundos, así que dos medidas de la
-- MISMA partida pueden separarse un poco. 15 s es holgado para eso y sigue
-- siendo muchísimo menor que el hueco entre dos partidas distintas, que
-- incluye salir, reformar y volver a meter la piedra.
local TOLERANCIA = 15

-- Caducidad defensiva. Una M+ con su cronómetro no pasa de ~45 minutos; dos
-- horas cubre una partida larguísima con pausas y sigue impidiendo resucitar
-- basura de ayer si algún borrado falló. No se mide en días a propósito.
local CADUCIDAD = 2 * 60 * 60

RunSession._state  = NONE
RunSession._reason = "NO_SNAPSHOT"
RunSession._lastRestoredPull = nil

local function bus() return MitzuMPlus.EventBus end
local function ahora() return (time and time()) or 0 end

-- ─────────────────────────────────────────────────────────────────────────
-- ALMACÉN
--
-- Vive junto a los ajustes de ruta. Es estado de EJECUCIÓN, no historial: el
-- historial de partidas terminadas es otra cosa y tiene su propio sistema
-- (Core + Database). Mezclarlos habría creado un segundo historial paralelo.
-- ─────────────────────────────────────────────────────────────────────────

local function store(crear)
    local db = _G.MPlusAdaptiveRouteDB
    if type(db) ~= "table" then return nil end
    if crear and type(db.activeRouteSession) ~= "table" then
        db.activeRouteSession = {}
    end
    return db.activeRouteSession
end

-- ─────────────────────────────────────────────────────────────────────────
-- HUELLA
-- ─────────────────────────────────────────────────────────────────────────

-- Segundos transcurridos de la challenge, según el servidor. nil si no hay
-- ninguna corriendo.
-- La lectura del temporizador vive ahora en ChallengeClock, que es la fuente
-- canonica. Aqui se delega SIN cambiar la semantica: la huella sigue siendo
-- startedAt = time() - elapsed con tolerancia 15 s, que es lo que funciono en
-- vivo. Si ChallengeClock no estuviera, se lee igual que antes.
function RunSession:ChallengeElapsed()
    local CC = MitzuMPlus.ChallengeClock
    if CC then return CC:GetElapsed() end

    if type(GetWorldElapsedTimers) ~= "function"
       or type(GetWorldElapsedTime) ~= "function" then
        return nil
    end
    local tipoCM = rawget(_G, "LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE")
    local ok, timers = pcall(function() return { GetWorldElapsedTimers() } end)
    if not ok or type(timers) ~= "table" then return nil end
    for _, id in ipairs(timers) do
        local okT, _, elapsed, tipo = pcall(GetWorldElapsedTime, id)
        if okT and tonumber(elapsed) then
            if tipoCM == nil or tipo == tipoCM then
                return tonumber(elapsed)
            end
        end
    end
    return nil
end


-- La huella de la ejecución ACTUAL, o nil si no hay ninguna corriendo.
function RunSession:Fingerprint()
    local DC = MitzuMPlus.DungeonContext
    if not DC or DC:GetState() ~= "RUNNING" then return nil, "NO_CHALLENGE" end

    local elapsed = self:ChallengeElapsed()
    if not elapsed then return nil, "NO_TIMER" end

    return {
        dungeonKey    = tonumber(DC:GetDungeonKey()),
        keystoneLevel = DC:GetKeystoneLevel(),
        startedAt     = ahora() - math.floor(elapsed),
    }
end

-- ─────────────────────────────────────────────────────────────────────────
-- ESCRITURA
--
-- Solo en cambios de estado, nunca en bucle: empezar la partida, cambiar de
-- pull, terminar. Un SavedVariables no es un sitio donde escribir por frame.
-- ─────────────────────────────────────────────────────────────────────────

function RunSession:Begin(route, pullIndex)
    local fp = self:Fingerprint()
    if not fp or not route then return false, "sin partida activa o sin ruta" end
    local s = store(true)
    if not s then return false, "sin DB" end

    s.schemaVersion  = self.SCHEMA
    s.createdAt      = ahora()
    s.dungeonKey     = fp.dungeonKey
    s.keystoneLevel  = fp.keystoneLevel
    s.startedAt      = fp.startedAt
    s.routeID        = route.id
    s.pullIndex      = tonumber(pullIndex) or 1
    s.lastChangeReason = "BEGIN"
    s.updatedAt      = ahora()
    self._state, self._reason = PENDING, "NEW_RUN"
    return true
end

function RunSession:UpdatePull(pullIndex, reason)
    local s = store(false)
    if not s or not s.startedAt then return false end
    -- Solo se anota si seguimos en la MISMA partida que abrió el snapshot. Si
    -- no, escribir aquí contaminaría el snapshot de otra ejecución.
    local fp = self:Fingerprint()
    if not fp or fp.startedAt == nil
       or math.abs(fp.startedAt - s.startedAt) > TOLERANCIA then
        return false, "la partida activa no es la del snapshot"
    end
    s.pullIndex = tonumber(pullIndex) or s.pullIndex
    s.lastChangeReason = reason or "MANUAL"
    s.updatedAt = ahora()
    return true
end

function RunSession:Clear(reason)
    local db = _G.MPlusAdaptiveRouteDB
    if type(db) == "table" then db.activeRouteSession = nil end
    self._state  = CLEARED
    self._reason = reason or "CLEARED"
    self._lastRestoredPull = nil
    if reason == "COMPLETED" or reason == "RESET" then
        -- La partida acabo: el proximo MITZU_KEY_STARTED sera de una nueva.
        self._decided = false
        self._retries = 0
    end
    return true
end

-- ─────────────────────────────────────────────────────────────────────────
-- LECTURA Y RECUPERACIÓN
--
-- Cada comprobación que falla devuelve su propio motivo. Un "no se pudo"
-- genérico obligaría a adivinar por qué, que es justo lo que no queremos en
-- algo que decide si se restaura progreso.
-- ─────────────────────────────────────────────────────────────────────────

function RunSession:GetSnapshot() return store(false) end

function RunSession:Evaluate()
    local s = store(false)
    if type(s) ~= "table" or not s.startedAt then
        return NONE, "NO_SNAPSHOT"
    end
    if s.schemaVersion ~= self.SCHEMA then
        return REJECTED, "SCHEMA_MISMATCH"
    end
    if (ahora() - (tonumber(s.updatedAt) or 0)) > CADUCIDAD then
        return EXPIRED, "EXPIRED"
    end

    local fp, why = self:Fingerprint()
    if not fp then
        -- Estar en PRE_KEY no invalida el snapshot: puede que la partida siga
        -- y aún no se haya leído el cronómetro. Simplemente no se restaura.
        return PENDING, why or "NO_CHALLENGE"
    end
    if fp.dungeonKey ~= tonumber(s.dungeonKey) then
        return REJECTED, "DUNGEON_MISMATCH"
    end
    if fp.keystoneLevel and s.keystoneLevel
       and fp.keystoneLevel ~= s.keystoneLevel then
        return REJECTED, "KEY_LEVEL_MISMATCH"
    end
    -- LA comprobación. Sin esta, dos +2 seguidas de la misma mazmorra
    -- pasarían por la misma partida.
    if math.abs(fp.startedAt - tonumber(s.startedAt)) > TOLERANCIA then
        return REJECTED, "SESSION_MISMATCH"
    end

    local RM = MitzuMPlus.RouteManager
    local activa = RM and RM:GetActiveRoute()
    if activa and s.routeID and activa.id ~= s.routeID then
        -- No se traducen índices entre rutas distintas: el pull 5 de una no es
        -- el pull 5 de otra.
        return REJECTED, "ROUTE_MISMATCH"
    end

    local RP = MitzuMPlus.RouteProgress
    local n = tonumber(s.pullIndex)
    if not n or n < 1 or (RP and RP:GetPullCount() > 0 and n > RP:GetPullCount()) then
        return REJECTED, "INVALID_PULL"
    end
    return PENDING, "SESSION_MATCH"
end

-- Intenta recuperar. Devuelve estado, motivo y pull.
function RunSession:TryRestore()
    local estado, motivo = self:Evaluate()
    self._state, self._reason = estado, motivo
    if estado ~= PENDING or motivo ~= "SESSION_MATCH" then
        return estado, motivo, nil
    end

    local s = store(false)
    local RP = MitzuMPlus.RouteProgress
    if not RP or not RP.RestorePull then
        self._state, self._reason = REJECTED, "NO_ROUTE_PROGRESS"
        return self._state, self._reason, nil
    end

    local ok, info = RP:RestorePull(s.pullIndex, { source = "RUN_SESSION", reason = motivo })
    if not ok then
        self._state, self._reason = REJECTED, tostring(info)
        return self._state, self._reason, nil
    end
    self._state, self._reason = RESTORED, "SESSION_MATCH"
    self._lastRestoredPull = s.pullIndex
    return RESTORED, motivo, s.pullIndex
end

function RunSession:GetState()  return self._state end
function RunSession:GetReason() return self._reason end
function RunSession:GetRestoredPull() return self._lastRestoredPull end

-- ═════════════════════════════════════════════════════════════════════════
-- ORQUESTACIÓN — BUG RS-1: nos destruíamos el snapshot antes de leerlo
--
-- Visto en vivo: pull 5, /reload, y el informe decía
--     challengeElapsed=230s   snapshotPull=1   snapshotAge=6s
-- El cronómetro identificaba bien la partida (SESSION_MATCH), pero el
-- snapshot ya valía 1. Lo habíamos reescrito nosotros seis segundos antes.
--
-- CAUSA: el handler de MITZU_KEY_STARTED trataba PENDING igual que REJECTED.
-- Y PENDING no significa "no es la misma partida": significa "todavía no lo
-- sé". En un /reload dentro de una llave activa, GetWorldElapsedTimers()
-- aún no está poblado cuando llega PLAYER_ENTERING_WORLD, así que Fingerprint
-- devolvía nil, Evaluate devolvía PENDING/NO_TIMER, y el código hacía
-- Clear + SetPull(1) + Begin. Destruía la prueba antes de mirarla.
--
-- INVARIANTE: un snapshot válido NO se reemplaza hasta que haya una decisión
-- POSITIVA. Solo se escribe con:
--     NONE      no hay snapshot
--     REJECTED  sé que no es esta partida
--     EXPIRED   demasiado viejo
-- Con PENDING no se toca nada y se vuelve a intentar.
--
-- Y MITZU_KEY_STARTED NO equivale a "partida nueva": DungeonContext lo emite
-- también al reconstruir RUNNING tras un /reload de una llave que llevaba
-- minutos corriendo. Quien decide si es nueva es la huella, no el evento.
-- ═════════════════════════════════════════════════════════════════════════

RunSession._decided    = false
RunSession._waitingFor = "NONE"
RunSession._retries    = 0

-- Qué falta para poder DECIDIR. Mientras haya algo, no se escribe nada.
function RunSession:WaitingFor()
    local DC = MitzuMPlus.DungeonContext
    if not DC or DC:GetState() ~= "RUNNING" then return "CHALLENGE" end
    -- El cronómetro es lo último que llega tras un reload, y sin él no hay
    -- huella con la que comparar.
    if not self:ChallengeElapsed() then return "CHALLENGE_TIMER" end
    local RM = MitzuMPlus.RouteManager
    if not (RM and RM:GetActiveRoute()) then return "ROUTE" end
    local RP = MitzuMPlus.RouteProgress
    local st = RP and RP:GetState()
    if st ~= "PREPARED" and st ~= "ACTIVE" then return "ROUTE_PROGRESS" end
    return "NONE"
end

function RunSession:GetWaitingFor() return self._waitingFor end
function RunSession:IsDecided()     return self._decided end

local MAX_RETRIES = 20   -- ~20 s: de sobra para que el cronómetro aparezca

-- El cronómetro no tiene evento propio al que suscribirse, así que ese caso
-- concreto necesita reintentar en el tiempo. Los otros tres (ruta, progreso,
-- challenge) SÍ tienen evento y se reintentan por ahí; el temporizador es la
-- red de seguridad, no el mecanismo principal.
function RunSession:_ScheduleRetry()
    if self._decided then return end
    if not (C_Timer and C_Timer.After) then return end
    if self._retryPending then return end
    if self._retries >= MAX_RETRIES then return end
    self._retryPending = true
    C_Timer.After(1, function()
        self._retryPending = false
        self._retries = self._retries + 1
        self:TryRecoverWhenReady()
    end)
end

local function beginNew(route, motivo)
    RunSession:Clear(motivo)
    local RP = MitzuMPlus.RouteProgress
    if RP then RP:SetPull(1, "NEW_RUN") end
    RunSession:Begin(route, 1)
    RunSession._state, RunSession._reason = PENDING, "NEW_RUN"
end

-- Punto de entrada único. Idempotente: una vez decidido, no vuelve a tocar
-- nada aunque lo llamen diez eventos más.
function RunSession:TryRecoverWhenReady()
    -- El estado se mira ANTES del corte por _decided: si ya no estamos en
    -- RUNNING, la decision anterior caduca y la proxima llave habra que
    -- decidirla de nuevo. Rearmar aqui, en vez de depender de que llegue un
    -- evento concreto (completar, resetear, salir), cubre tambien los finales
    -- que no emiten ninguno.
    local falta = self:WaitingFor()
    self._waitingFor = falta
    if falta == "CHALLENGE" then
        self._decided = false
        self._retries = 0
        self._state, self._reason = PENDING, "WAITING_CHALLENGE"
        return self._state, self._reason
    end

    if self._decided then return self._state, self._reason end

    if falta ~= "NONE" then
        -- NO se escribe el snapshot. Este es el arreglo del BUG RS-1.
        self._state, self._reason = PENDING, "WAITING_" .. falta
        self:_ScheduleRetry()
        return self._state, self._reason
    end

    local RM = MitzuMPlus.RouteManager
    local route = RM and RM:GetActiveRoute()
    local estado, motivo = self:Evaluate()

    if estado == PENDING and motivo == "SESSION_MATCH" then
        local e, r = self:TryRestore()
        self._decided = (e == RESTORED)
        if not self._decided and route then
            -- La restauración falló por algo concreto (pull inválido, etc.):
            -- eso sí es una decisión, y se empieza de cero.
            beginNew(route, tostring(r))
            self._decided = true
        end
        return self._state, self._reason
    end

    if estado == NONE or estado == REJECTED or estado == EXPIRED then
        -- Decisión positiva: ahora sí se puede escribir.
        if route then beginNew(route, motivo) end
        self._decided = true
        return self._state, self._reason
    end

    -- Cualquier otro PENDING: seguir esperando, sin tocar nada.
    self._state, self._reason = estado, motivo
    self:_ScheduleRetry()
    return self._state, self._reason
end

-- ─────────────────────────────────────────────────────────────────────────
-- ENGANCHE
--
-- Las cuatro señales que pueden completar las condiciones llaman al MISMO
-- punto de entrada. Así el módulo no depende del orden en que lleguen, que
-- tras un /reload no está garantizado.
-- ─────────────────────────────────────────────────────────────────────────

if MitzuMPlus.EventBus then
    local function intentar() pcall(function() RunSession:TryRecoverWhenReady() end) end

    MitzuMPlus.EventBus:On("MITZU_KEY_STARTED",    intentar, 30)
    MitzuMPlus.EventBus:On("MITZU_ROUTE_LOADED",   intentar, 30)
    MitzuMPlus.EventBus:On("MITZU_ROUTE_PREPARED", intentar, 30)
    MitzuMPlus.EventBus:On("MITZU_ROUTE_STARTED",  intentar, 30)

    MitzuMPlus.EventBus:On("MITZU_PULL_CHANGED", function(nuevo, _, reason)
        -- La recuperación no se re-anota a sí misma: ya está en el snapshot.
        if reason == "RECOVERY" then return end
        -- Y mientras no haya decisión, un SetPull ajeno no debe tocar el
        -- snapshot: es exactamente por donde se colaba el pull=1.
        if not RunSession._decided then return end
        pcall(function() RunSession:UpdatePull(nuevo, reason) end)
    end, 20)

    MitzuMPlus.EventBus:On("MITZU_KEY_COMPLETED", function()
        pcall(function() RunSession:Clear("COMPLETED") end)
    end)
    MitzuMPlus.EventBus:On("MITZU_KEY_RESET", function()
        pcall(function() RunSession:Clear("RESET") end)
    end)
    -- Salir de la mazmorra rearma la decisión para la próxima entrada, sin
    -- borrar el snapshot: la partida puede seguir viva y volveremos.
    MitzuMPlus.EventBus:On("MITZU_DUNGEON_STATE_CHANGED", function(nuevoEstado)
        if nuevoEstado == "OUTSIDE" then
            RunSession._decided = false
            RunSession._retries = 0
            RunSession._waitingFor = "CHALLENGE"
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────
-- INFORME
-- ─────────────────────────────────────────────────────────────────────────

function RunSession:StatusLines()
    local s = store(false)
    local DC = MitzuMPlus.DungeonContext
    local RM = MitzuMPlus.RouteManager
    local L = {}
    L[#L + 1] = "snapshotExists=" .. tostring(s ~= nil and s.startedAt ~= nil)
    if s then
        L[#L + 1] = "snapshotDungeonKey=" .. tostring(s.dungeonKey)
        L[#L + 1] = "snapshotRouteID=" .. tostring(s.routeID)
        L[#L + 1] = "snapshotPull=" .. tostring(s.pullIndex)
        L[#L + 1] = "snapshotKeystoneLevel=" .. tostring(s.keystoneLevel)
        L[#L + 1] = "snapshotCreatedAt=" .. tostring(s.createdAt)
    L[#L + 1] = "snapshotUpdatedAt=" .. tostring(s.updatedAt)
    L[#L + 1] = "snapshotAge=" .. tostring(ahora() - (tonumber(s.updatedAt) or 0)) .. "s"
    L[#L + 1] = "snapshotStartedAt=" .. tostring(s.startedAt)
    end
    L[#L + 1] = "currentDungeonKey=" .. tostring(DC and DC:GetDungeonKey())
    L[#L + 1] = "currentRouteID=" .. tostring(RM and RM:GetActiveRoute() and RM:GetActiveRoute().id)
    L[#L + 1] = "currentChallengeActive=" .. tostring(DC and DC:IsChallengeActive())
    local elapsed = self:ChallengeElapsed()
    L[#L + 1] = "challengeElapsed=" .. (elapsed and (math.floor(elapsed) .. "s") or "nil")
    local estado, motivo = self:Evaluate()
    L[#L + 1] = "matchState=" .. tostring(motivo)
    L[#L + 1] = "restoreState=" .. tostring(self._state)
    L[#L + 1] = "restoreReason=" .. tostring(self._reason)
    L[#L + 1] = "recoveryWaitingFor=" .. tostring(self._waitingFor)
    L[#L + 1] = "recoveryDecided=" .. tostring(self._decided)
    if elapsed then
        L[#L + 1] = "derivedStartedAt=" .. tostring(ahora() - math.floor(elapsed))
    end
    return L
end

return RunSession
