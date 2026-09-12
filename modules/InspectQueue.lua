-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial — modules/InspectQueue.lua
-- Enriquece run.group[i] con specID/spec vía NotifyInspect + INSPECT_READY.
-- Rate-limited para respetar el límite de Blizzard (~1 inspección / 2s).
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local InspectQueue = {}
MitzuMPlus.InspectQueue = InspectQueue

-- ── Constantes ──────────────────────────────────────────────────────────────
local INSPECT_INTERVAL = 2.5   -- segundos entre inspecciones (límite Blizzard ≈ 2s)
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

    -- Liberamos y pasamos al siguiente inmediatamente (respetando intervalo global)
    if ClearInspectPlayer then pcall(ClearInspectPlayer) end
    self._current = nil
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
    self._current = nil
    if self._ticker and self._ticker.Cancel then
        pcall(self._ticker.Cancel, self._ticker)
    end
    self._ticker = nil
    if self._frame and self._frame:IsEventRegistered("INSPECT_READY") then
        self._frame:UnregisterEvent("INSPECT_READY")
    end
    if ClearInspectPlayer then pcall(ClearInspectPlayer) end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCESAMIENTO INTERNO
-- ═══════════════════════════════════════════════════════════════════════════

function InspectQueue:_ProcessNext()
    if not self._active then return end
    if not self._queue or #self._queue == 0 then
        self:Stop()
        return
    end

    -- Si ya hay una inspección en curso, dejar que termine o expire vía timeout.
    if self._current then return end

    local task = table.remove(self._queue, 1)
    if not task or not task.member then
        -- Programar siguiente intento
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, function() InspectQueue:_ProcessNext() end)
        end
        return
    end

    -- Caso rápido: si es el jugador local, leer el spec directamente
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
        -- Pasar al siguiente sin gastar el cooldown de inspect
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, function() InspectQueue:_ProcessNext() end)
        end
        return
    end

    -- Resolver unitID actualizado (el miembro puede haberse movido, desconectado, etc.)
    local unit = ResolveUnitID(task.targetName, task.targetGUID)
    if not unit then
        -- Saltamos: intentaremos siguiente miembro sin gastar rate-limit
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, function() InspectQueue:_ProcessNext() end)
        end
        return
    end

    -- Verificaciones de pre-requisito (misma realm/zona, visible, inspeccionable)
    if CanInspect and not CanInspect(unit) then
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, function() InspectQueue:_ProcessNext() end)
        end
        return
    end

    task.targetGUID = (UnitGUID and UnitGUID(unit)) or task.targetGUID
    self._current   = task

    -- FIX BUG-INSPECT-1: No inspeccionar durante contexto restringido (M+/combate).
    -- NotifyInspect causa taint en InspectPVPFrame en Midnight 12.0.5.
    if IsInRestrictedContext() then
        -- Re-encolar la tarea y reintentar después
        table.insert(self._queue, 1, task)
        self._current = nil
        if C_Timer and C_Timer.After then
            C_Timer.After(DEFERRED_RETRY, function()
                if InspectQueue._active and not IsInRestrictedContext() then
                    InspectQueue:_ProcessNext()
                end
            end)
        end
        return
    end

    if NotifyInspect then
        pcall(NotifyInspect, unit)
    end

    -- Timeout: si INSPECT_READY no llega en N segundos, forzamos avanzar.
    if C_Timer and C_Timer.After then
        local snapshot = task
        C_Timer.After(INSPECT_TIMEOUT, function()
            if InspectQueue._current == snapshot then
                InspectQueue._current = nil
            end
        end)
    end

    -- Programamos el siguiente procesamiento en INSPECT_INTERVAL
    if C_Timer and C_Timer.After then
        C_Timer.After(INSPECT_INTERVAL, function()
            InspectQueue:_ProcessNext()
        end)
    end
end

return InspectQueue
