-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial — modules/InspectQueue.lua
-- Enriquece run.group[i] con specID/spec vía NotifyInspect + INSPECT_READY.
-- Desde experimental.5 las peticiones pasan por InspectArbiter, que comparte
-- throttle/ownership con PartyProfiler y cede al InspectFrame nativo.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local InspectQueue = {}
MitzuMPlus.InspectQueue = InspectQueue

-- ── Constantes ──────────────────────────────────────────────────────────────
local INSPECT_RETRY    = 1.0   -- reintento local; el throttle global vive en InspectArbiter
local INSPECT_TIMEOUT  = 3.0   -- segundos para esperar INSPECT_READY por miembro
local DEFERRED_RETRY   = 10.0  -- segundos para reintentar después de M+ activa

-- FIX BUG-INSPECT-1 (Midnight 12.0.5): NotifyInspect durante M+/encuentro/PvP
-- causa taint en Blizzard_InspectUI → InspectPVPFrame_Update → UnitFactionGroup(nil).
-- Detectamos contexto restringido y diferimos la inspección.
local function IsInRestrictedContext()
    -- M+ activa
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive() then
        return true
    end
    -- En combate (lockdown)
    if InCombatLockdown and InCombatLockdown() then
        return true
    end
    return false
end

-- ── Estado interno ──────────────────────────────────────────────────────────
InspectQueue._frame   = nil    -- frame de eventos (singleton)
InspectQueue._active  = false  -- hay una campaña de inspección en curso
InspectQueue._queue   = nil    -- lista de tareas pendientes
InspectQueue._current = nil    -- tarea actual en espera de INSPECT_READY
InspectQueue._ticker  = nil    -- C_Timer ticker para procesar la siguiente tarea

local function arbiter()
    return MitzuMPlus.InspectArbiter
end

local function scheduleNext(delay)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or INSPECT_RETRY, function() InspectQueue:_ProcessNext() end)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

local function GetSpecInfo(specID)
    if not specID or specID == 0 then return nil, nil end
    if GetSpecializationInfoByID then
        local id, name, _, _, role = GetSpecializationInfoByID(specID)
        if id then return name, role end
    end
    return nil, nil
end

-- Resuelve un GUID + nombre a un unitID de grupo en el momento actual.
-- Devuelve el unitID ("player", "partyN", "raidN") o nil si el miembro ya no está.
local function ResolveUnitID(targetName, targetGUID)
    if UnitGUID and targetGUID and UnitGUID("player") == targetGUID then
        return "player"
    end
    if UnitName and targetName and UnitName("player") == targetName then
        return "player"
    end
    local isRaid = IsInRaid and IsInRaid()
    local prefix = isRaid and "raid" or "party"
    local n = isRaid and 40 or 4
    for i = 1, n do
        local unit = prefix .. i
        if UnitExists and UnitExists(unit) then
            if targetGUID and UnitGUID(unit) == targetGUID then
                return unit
            elseif targetName and UnitName(unit) == targetName then
                return unit
            end
        end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FRAME Y EVENTOS
-- ═══════════════════════════════════════════════════════════════════════════

function InspectQueue:EnsureFrame()
    if self._frame then return self._frame end
    local f = CreateFrame("Frame", "MitzuMPlusInspectQueueFrame")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "INSPECT_READY" then
            local guid = ...
            InspectQueue:HandleInspectReady(guid)
        end
    end)
    self._frame = f
    return f
end

function InspectQueue:HandleInspectReady(guid)
    local current = self._current
    if not current then return end
    if current.targetGUID and current.targetGUID ~= guid then
        -- El INSPECT_READY corresponde a otro GUID (quizá una inspección de la UI).
        return
    end

    -- Reintentamos resolver el unit (por si cambió la composición)
    local unit = ResolveUnitID(current.targetName, current.targetGUID)
    if unit and GetInspectSpecialization then
        local specID = GetInspectSpecialization(unit)
        if specID and specID > 0 then
            local specName, role = GetSpecInfo(specID)
            local m = current.member
            if m then
                m.specID = specID
                if specName and specName ~= "" then m.spec = specName end
                if role and role ~= "" and (not m.role or m.role == "" or m.role == "NONE") then
                    m.role = role
                end
            end
        end
    end

    -- Liberamos solo NUESTRO ownership. Nunca se limpia la caché global de
    -- inspección: Blizzard InspectFrame puede estar consumiéndola al mismo tiempo.
    local A = arbiter()
    if A and A.Complete then A:Complete("InspectQueue", guid) end
    self._current = nil
    if self._active then scheduleNext(INSPECT_RETRY) end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

-- Arranca la captura de specs para todos los miembros del grupo de la run.
-- Debe llamarse DESPUÉS de que run.group esté poblado en OnChallengeStart.
function InspectQueue:StartForRun(run)
    if not run or type(run.group) ~= "table" then return end

    -- Construir cola: sólo miembros sin specID válido
    local queue = {}
    for _, m in ipairs(run.group) do
        local hasSpec = (tonumber(m.specID) or 0) > 0
        if not hasSpec and m.name and m.name ~= "" then
            local unit = ResolveUnitID(m.name, nil)
            local guid = unit and UnitGUID and UnitGUID(unit) or nil
            queue[#queue+1] = {
                member      = m,
                targetName  = m.name,
                targetGUID  = guid,
            }
        end
    end

    if #queue == 0 then return end

    self._queue   = queue
    self._current = nil
    self._active  = true

    local f = self:EnsureFrame()
    if not f:IsEventRegistered("INSPECT_READY") then
        f:RegisterEvent("INSPECT_READY")
    end

    self:_ProcessNext()
end

function InspectQueue:Stop()
    self._active = false
    self._queue  = nil
    local current = self._current
    self._current = nil
    if current then
        local A = arbiter()
        if A and A.Abandon then A:Abandon("InspectQueue", current.targetGUID, "STOP") end
    end
    if self._ticker and self._ticker.Cancel then
        pcall(self._ticker.Cancel, self._ticker)
    end
    self._ticker = nil
    if self._frame and self._frame:IsEventRegistered("INSPECT_READY") then
        self._frame:UnregisterEvent("INSPECT_READY")
    end
    -- PLAYER-INSPECT-001: no ClearInspectPlayer aquí. La caché es compartida
    -- con Blizzard InspectFrame y limpiarla puede vaciar sus slots de equipo.
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCESAMIENTO INTERNO
-- ═══════════════════════════════════════════════════════════════════════════

function InspectQueue:_ProcessNext()
    if not self._active then return end
    local A = arbiter()

    -- Si el jugador abrió el InspectFrame nativo mientras Mitzu esperaba una
    -- respuesta, esa inspección tiene prioridad. Reencolamos nuestra tarea sin
    -- tocar la caché global y esperamos a que Blizzard termine.
    if self._current and A and A.IsNativeInspectBusy then
        local nativeBusy = A:IsNativeInspectBusy()
        if nativeBusy then
            local current = self._current
            self._current = nil
            if A.Abandon then A:Abandon("InspectQueue", current.targetGUID, "NATIVE_UI_TAKEOVER") end
            if self._queue then table.insert(self._queue, 1, current) end
            scheduleNext(INSPECT_RETRY)
            return
        end
    end

    if not self._queue or #self._queue == 0 then
        self:Stop()
        return
    end

    -- Si ya hay una inspección en curso, dejar que termine o expire vía timeout.
    if self._current then return end

    -- Ceder antes de retirar trabajo de la cola.
    if A and A.IsNativeInspectBusy then
        local busy = A:IsNativeInspectBusy()
        if busy then
            scheduleNext(INSPECT_RETRY)
            return
        end
        local owner = A.CurrentOwner and A:CurrentOwner() or nil
        if owner ~= nil and owner ~= "InspectQueue" then
            scheduleNext(INSPECT_RETRY)
            return
        end
    end

    local task = table.remove(self._queue, 1)
    if not task or not task.member then
        scheduleNext(0.1)
        return
    end

    -- Caso rápido: si es el jugador local, leer el spec directamente.
    if task.member.name and UnitName and UnitName("player") == task.member.name then
        if GetSpecializationInfoByID and GetSpecialization then
            local specIdx = GetSpecialization()
            if specIdx and GetSpecializationInfo then
                local id, name, _, _, role = GetSpecializationInfo(specIdx)
                if id and id > 0 then
                    task.member.specID = id
                    task.member.spec   = name or task.member.spec or ""
                    if role and role ~= "" then task.member.role = role end
                end
            end
        end
        scheduleNext(0.05)
        return
    end

    -- Resolver unitID actualizado (el miembro puede haberse movido, desconectado, etc.)
    local unit = ResolveUnitID(task.targetName, task.targetGUID)
    if not unit then
        scheduleNext(0.1)
        return
    end

    if CanInspect and not CanInspect(unit) then
        scheduleNext(0.1)
        return
    end

    -- No inspeccionar durante contexto restringido (M+/combate).
    if IsInRestrictedContext() then
        table.insert(self._queue, 1, task)
        if C_Timer and C_Timer.After then
            C_Timer.After(DEFERRED_RETRY, function()
                if InspectQueue._active then InspectQueue:_ProcessNext() end
            end)
        end
        return
    end

    task.targetGUID = (UnitGUID and UnitGUID(unit)) or task.targetGUID

    -- Safety-first: toda petición debe pasar por el árbitro. Si no existe, no
    -- hacemos fallback directo a NotifyInspect porque recrearía PLAYER-INSPECT-001.
    if not (A and type(A.Request) == "function") then
        scheduleNext(INSPECT_RETRY)
        return
    end

    local ok, reason = A:Request("InspectQueue", unit, task.targetGUID)
    if not ok then
        if self._queue then table.insert(self._queue, 1, task) end
        scheduleNext(reason == "GLOBAL_THROTTLE" and INSPECT_RETRY or INSPECT_RETRY)
        return
    end

    self._current = task

    -- Timeout: abandonar sólo el ownership Mitzu. NUNCA ClearInspectPlayer.
    if C_Timer and C_Timer.After then
        local snapshot = task
        C_Timer.After(INSPECT_TIMEOUT, function()
            if InspectQueue._current == snapshot then
                InspectQueue._current = nil
                local arb = arbiter()
                if arb and arb.Abandon then
                    arb:Abandon("InspectQueue", snapshot.targetGUID, "TIMEOUT")
                end
                if InspectQueue._active then InspectQueue:_ProcessNext() end
            end
        end)
    end

    -- El arbiter impone el intervalo global entre PartyProfiler e InspectQueue.
    scheduleNext(INSPECT_RETRY)
end

return InspectQueue
