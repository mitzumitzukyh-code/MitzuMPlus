-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · PartyProfiler v1.0
--
-- QUIÉN VA EN EL GRUPO: los cinco, con clase, rol y especialización.
--
-- Trae tres piezas en un solo fichero, y es deliberado:
--   · PartyContext   el estado (quién hay ahora mismo)
--   · SpecCache      lo que ya sabemos de cada GUID
--   · la cola de inspección
-- Separarlas en tres ficheros habría obligado a exponer estado interno entre
-- ellas sin que nadie más lo use. Se separarán el día que alguien de fuera
-- necesite una sin las otras.
--
-- ═════════════════════════════════════════════════════════════════════════
-- POR QUÉ NO SE REUTILIZA modules/InspectQueue.lua
--
-- Aquel existe y funciona, pero está atado al historial: `StartForRun(run)`
-- enriquece `run.group`, se enciende al empezar una llave y se apaga al
-- terminarla. Aquí hace falta lo contrario — algo vivo fuera de la llave y
-- direccionado por GUID, no por posición en la run.
--
-- NotifyInspect es global y solo admite una petición en vuelo, así que dos
-- colas compitiendo se pisarían. Esta cede el paso: si la del historial está
-- activa, no lanza nada y reintenta luego. Ver `otraColaOcupada()`.
-- ═════════════════════════════════════════════════════════════════════════
--
-- RENDIMIENTO: cero OnUpdate. Todo cuelga de eventos, y la cola usa un
-- temporizador que solo corre mientras queda trabajo.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local PartyProfiler = {}
MitzuMPlus.PartyProfiler = PartyProfiler

local PartyContext = { members = {}, updatedAt = 0 }
MitzuMPlus.PartyContext = PartyContext

local SpecCache = {}
MitzuMPlus.SpecCache = SpecCache

local _issecretvalue = rawget(_G, "issecretvalue")

-- Estados de spec
local KNOWN, PENDING, OUT_OF_RANGE = "KNOWN", "PENDING", "OUT_OF_RANGE"
local FAILED, THROTTLED, UNKNOWN   = "FAILED", "THROTTLED", "UNKNOWN"

-- ─────────────────────────────────────────────────────────────────────────
-- LECTURA SEGURA
--
-- En party los datos no deberían venir restringidos, pero Midnight marca
-- UnitName con SecretWhenUnitNameIdentityRestricted y no cuesta nada tratarlo
-- igual que a un enemigo: si es secreto, no se toca.
-- ─────────────────────────────────────────────────────────────────────────

local function leer(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or v == nil then return nil end
    if _issecretvalue then
        local okS, s = pcall(_issecretvalue, v)
        if okS and s then return nil, "SECRET" end
    end
    return v
end

-- ─────────────────────────────────────────────────────────────────────────
-- SPEC CACHE
-- ─────────────────────────────────────────────────────────────────────────

-- BUG CACHE-1: los datos van en _data, NO en la propia tabla.
--
-- Antes las entradas se guardaban como SpecCache[guid], y Prune recorria
-- `pairs(self)` borrando toda clave string que no estuviera en el grupo. Las
-- claves "Set", "Get" y "Prune" tambien son strings: la primera purga se
-- comia sus propios metodos y la siguiente llamada reventaba con
-- "attempt to call a nil value (method 'Set')".
SpecCache._data = {}

function SpecCache:Set(guid, specID)
    if not guid or not specID then return false end
    self._data[guid] = { specID = specID, updatedAt = (GetTime and GetTime()) or 0 }
    return true
end

function SpecCache:Get(guid)
    local e = guid and self._data[guid]
    return e and e.specID or nil
end

-- Al salir del grupo se puede olvidar. No se persiste: una spec cambia entre
-- sesiones y una cache vieja mentiria con seguridad.
function SpecCache:Prune(guidsVivos)
    local fuera = 0
    for guid in pairs(self._data) do
        if not guidsVivos[guid] then
            self._data[guid] = nil
            fuera = fuera + 1
        end
    end
    return fuera
end

function SpecCache:Count()
    local n = 0
    for _ in pairs(self._data) do n = n + 1 end
    return n
end

-- ─────────────────────────────────────────────────────────────────────────
-- SPEC LOCAL
-- ─────────────────────────────────────────────────────────────────────────

local function specInfo(specIndexOrID, esIndice)
    local CSI = C_SpecializationInfo
    if esIndice then
        local fn = CSI and CSI.GetSpecializationInfo
        if type(fn) ~= "function" then return nil end
        local ok, id, name, _, _, role = pcall(fn, specIndexOrID)
        if not ok then return nil end
        return id, name, role
    end
    local fn = CSI and CSI.GetSpecializationInfoByID
    if type(fn) == "function" then
        local ok, id, name, _, _, role = pcall(fn, specIndexOrID)
        if ok then return id, name, role end
    end
    return nil
end

function PartyProfiler:GetPlayerSpec()
    local CSI = C_SpecializationInfo
    local fn = CSI and CSI.GetSpecialization
    if type(fn) ~= "function" then return nil, nil, nil, "UNAVAILABLE" end
    local ok, idx = pcall(fn)
    if not ok or not idx or idx == 0 then return nil, nil, nil, UNKNOWN end
    local id, name, role = specInfo(idx, true)
    if not id then return nil, nil, nil, UNKNOWN end
    return id, name, role, KNOWN
end

-- ─────────────────────────────────────────────────────────────────────────
-- ROSTER
-- ─────────────────────────────────────────────────────────────────────────

-- Tokens del grupo. M+ es siempre party de 5; se cubre raid por si acaso, sin
-- inventar tamaños.
local function tokensDeGrupo()
    local t = { "player" }
    local n = tonumber(leer(GetNumGroupMembers)) or 0
    if leer(IsInRaid) == true then
        for i = 1, math.max(0, n - 1) do t[#t + 1] = "raid" .. i end
    else
        for i = 1, math.max(0, n - 1) do t[#t + 1] = "party" .. i end
    end
    return t
end

-- El rol asignado y el rol que implica la spec son cosas distintas y se
-- guardan las dos. Un tanque sin rol asignado en el buscador sigue siendo un
-- tanque, y mezclarlos haría imposible saber cuál falló.
local function rolesDe(unit, esJugador)
    local asignado = leer(UnitGroupRolesAssigned, unit) or "NONE"
    local specRole
    if esJugador then
        local _, _, role = PartyProfiler:GetPlayerSpec()
        specRole = role
    end
    local efectivo = asignado
    if (asignado == "NONE" or asignado == nil) and specRole then
        efectivo = specRole
    end
    return asignado, specRole, efectivo
end

function PartyProfiler:Refresh(motivo)
    local nuevos, vivos = {}, {}

    for _, unit in ipairs(tokensDeGrupo()) do
        if leer(UnitExists, unit) == true then
            local guid = leer(UnitGUID, unit)
            if type(guid) == "string" then
                vivos[guid] = true
                local esJugador = (leer(UnitIsUnit, unit, "player") == true)

                -- UnitClassBase da el classFile ("MONK"), que no depende del
                -- idioma del cliente. El nombre localizado nunca es la clave.
                local classFile, classID = nil, nil
                if type(UnitClassBase) == "function" then
                    local ok, cf, cid = pcall(UnitClassBase, unit)
                    if ok then classFile, classID = cf, cid end
                end

                local asignado, specRole, efectivo = rolesDe(unit, esJugador)

                local specID, specName, specState
                if esJugador then
                    specID, specName, _, specState = self:GetPlayerSpec()
                else
                    specID = SpecCache:Get(guid)
                    if specID then
                        local _, nombre = specInfo(specID, false)
                        specName, specState = nombre, KNOWN
                    else
                        specState = PENDING
                    end
                end

                local anterior = PartyContext.members[guid]
                nuevos[guid] = {
                    guid         = guid,
                    unitToken    = unit,
                    name         = leer(UnitName, unit),
                    classFile    = classFile,
                    classID      = classID,
                    assignedRole = asignado,
                    specRole     = specRole,
                    effectiveRole = efectivo,
                    specID       = specID,
                    specName     = specName,
                    -- Un estado terminal (throttled, fuera de rango) no se
                    -- pisa con PENDING en cada refresco: se perdería el motivo.
                    specState    = specID and KNOWN
                                   or (anterior and anterior.specState ~= PENDING
                                       and anterior.specState)
                                   or specState,
                }
            end
        end
    end

    PartyContext.members   = nuevos
    PartyContext.updatedAt = (GetTime and GetTime()) or 0
    SpecCache:Prune(vivos)
    self:_EnqueueMissing()

    local bus = MitzuMPlus.EventBus
    if bus then bus:Emit("MITZU_GROUP_UPDATED", PartyContext, motivo) end
    return PartyContext
end

-- ─────────────────────────────────────────────────────────────────────────
-- CONSULTAS
-- ─────────────────────────────────────────────────────────────────────────

function PartyProfiler:GetMembers() return PartyContext.members end

local function porRol(rol)
    local out = {}
    for _, m in pairs(PartyContext.members) do
        if m.effectiveRole == rol then out[#out + 1] = m end
    end
    table.sort(out, function(a, b) return tostring(a.unitToken) < tostring(b.unitToken) end)
    return out
end

function PartyProfiler:GetTank()     return porRol("TANK")[1] end
function PartyProfiler:GetHealer()   return porRol("HEALER")[1] end
function PartyProfiler:GetDamagers() return porRol("DAMAGER") end

function PartyProfiler:GetPlayerProfile()
    local guid = leer(UnitGUID, "player")
    return guid and PartyContext.members[guid] or nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- COLA DE INSPECCIÓN
-- ─────────────────────────────────────────────────────────────────────────

local Q = {
    pending = {},   -- lista de guids
    active  = nil,  -- guid en vuelo
    since   = 0,
    retries = {},   -- [guid] = intentos
}
PartyProfiler._queue = Q

local TIMEOUT   = 3      -- s antes de dar por perdida una petición
local MAX_RETRY = 2
local TICK      = 1

local function otraColaOcupada()
    local otra = MitzuMPlus.InspectQueue
    return otra ~= nil and otra._active == true
end

local function unitDeGUID(guid)
    local m = PartyContext.members[guid]
    if not m or not m.unitToken then return nil end
    if leer(UnitGUID, m.unitToken) ~= guid then return nil end  -- token reciclado
    return m.unitToken
end

local function marcar(guid, estado)
    local m = PartyContext.members[guid]
    if m then m.specState = estado end
end

function PartyProfiler:_EnqueueMissing()
    for guid, m in pairs(PartyContext.members) do
        if not m.specID and m.specState ~= THROTTLED and m.specState ~= FAILED then
            local yaEsta = (Q.active == guid)
            if not yaEsta then
                for _, g in ipairs(Q.pending) do
                    if g == guid then yaEsta = true break end
                end
            end
            if not yaEsta then Q.pending[#Q.pending + 1] = guid end
        end
    end
    self:_Tick()
end

function PartyProfiler:_Tick()
    if not (C_Timer and C_Timer.After) then return end
    if Q._scheduled then return end
    if not Q.active and #Q.pending == 0 then return end
    Q._scheduled = true
    C_Timer.After(TICK, function()
        Q._scheduled = false
        PartyProfiler:_Process()
        PartyProfiler:_Tick()
    end)
end

function PartyProfiler:_Process()
    -- ¿Caducó la que estaba en vuelo?
    if Q.active then
        local ahora = (GetTime and GetTime()) or 0
        if ahora - Q.since < TIMEOUT then return end
        local guid = Q.active
        Q.active = nil
        Q.retries[guid] = (Q.retries[guid] or 0) + 1
        if Q.retries[guid] > MAX_RETRY then
            -- El servidor puede throttlear y no contestar NUNCA. Eso es un
            -- estado, no un fallo del addon.
            marcar(guid, THROTTLED)
        else
            marcar(guid, PENDING)
            Q.pending[#Q.pending + 1] = guid
        end
    end

    if #Q.pending == 0 then return end
    if otraColaOcupada() then return end   -- se cede el paso, se reintenta luego

    local guid = table.remove(Q.pending, 1)
    local unit = unitDeGUID(guid)
    if not unit then
        marcar(guid, FAILED)
        return
    end
    if type(CanInspect) == "function" and leer(CanInspect, unit) ~= true then
        marcar(guid, OUT_OF_RANGE)
        return
    end
    if type(NotifyInspect) ~= "function" then
        marcar(guid, FAILED)
        return
    end

    Q.active = guid
    Q.since  = (GetTime and GetTime()) or 0
    marcar(guid, PENDING)
    pcall(NotifyInspect, unit)
end

function PartyProfiler:OnInspectReady(guid)
    if type(guid) ~= "string" then return end
    local unit = unitDeGUID(guid)
    if unit then
        local CSI = C_SpecializationInfo
        local fn = CSI and CSI.GetInspectSpecialization
                   or rawget(_G, "GetInspectSpecialization")
        local specID = fn and leer(fn, unit) or nil
        specID = tonumber(specID)
        if specID and specID > 0 then
            SpecCache:Set(guid, specID)
            local m = PartyContext.members[guid]
            if m then
                m.specID = specID
                local _, nombre = specInfo(specID, false)
                m.specName  = nombre
                m.specState = KNOWN
            end
            local bus = MitzuMPlus.EventBus
            if bus then bus:Emit("MITZU_MEMBER_SPEC_UPDATED", guid, specID) end
        end
    end
    if Q.active == guid then Q.active = nil end
    if type(ClearInspectPlayer) == "function" then pcall(ClearInspectPlayer) end
    self:_Tick()
end

function PartyProfiler:QueueStatus()
    return #Q.pending, Q.active
end

-- ─────────────────────────────────────────────────────────────────────────
-- EVENTOS
-- ─────────────────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame")
for _, ev in ipairs({
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ROLES_ASSIGNED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "INSPECT_READY",
    "PLAYER_ENTERING_WORLD",
}) do
    pcall(function() frame:RegisterEvent(ev) end)
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "INSPECT_READY" then
        PartyProfiler:OnInspectReady(arg1)
    else
        PartyProfiler:Refresh(event)
    end
end)

-- ─────────────────────────────────────────────────────────────────────────
-- INFORME
-- ─────────────────────────────────────────────────────────────────────────

local function linea(etiqueta, m)
    if not m then return etiqueta .. "=(ninguno)" end
    return string.format("%s=%s %s %s specID=%s state=%s",
        etiqueta,
        tostring(m.classFile or "?"),
        tostring(m.specName or "?"),
        tostring(m.effectiveRole or "?"),
        tostring(m.specID or "?"),
        tostring(m.specState or "?"))
end

function PartyProfiler:StatusLines()
    local L = {}
    local yo = self:GetPlayerProfile()
    L[#L + 1] = "player:"
    L[#L + 1] = "  class=" .. tostring(yo and yo.classFile or "?")
    L[#L + 1] = "  spec=" .. tostring(yo and yo.specName or "?")
    L[#L + 1] = "  specID=" .. tostring(yo and yo.specID or "?")
    L[#L + 1] = "  assignedRole=" .. tostring(yo and yo.assignedRole or "?")
    L[#L + 1] = "  specRole=" .. tostring(yo and yo.specRole or "?")
    L[#L + 1] = "  effectiveRole=" .. tostring(yo and yo.effectiveRole or "?")
    L[#L + 1] = linea("tank", self:GetTank())
    L[#L + 1] = linea("healer", self:GetHealer())
    local dps = self:GetDamagers()
    for i = 1, 3 do L[#L + 1] = linea("dps" .. i, dps[i]) end
    local pend, act = self:QueueStatus()
    L[#L + 1] = "inspectPending=" .. tostring(pend)
    L[#L + 1] = "inspectActive=" .. tostring(act or "none")
    return L
end

return PartyProfiler
