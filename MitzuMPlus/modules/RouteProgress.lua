-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · RouteProgress v1  —  por dónde vas de la ruta
--
-- Ruta activa, pull actual, y qué falta de ese pull. No decide identidad de
-- mobs ni cuenta muertos: eso necesita saber QUÉ mob es cada placa, y en 12.1
-- eso está cerrado (enemyIdentity=SECRET, forces=SECRET, confirmado en vivo).
--
-- ESTADOS
--   INACTIVE   no hay ruta
--   PREPARED   ruta cargada, pull 1 listo. Es el estado de PRE_KEY.
--   ACTIVE     la llave corre
--   COMPLETED  se acabó
--
-- PREPARED existe para que entrar a la mazmorra sin piedra ya deje la ruta
-- lista. Al poner la llave no hay que redescubrir nada: solo Start().
--
-- AVANCE AUTOMÁTICO: no. Ni una línea. La API para saber qué mob ha muerto no
-- existe hoy, y un avance adivinado da un "pull 7 de 11" convencido y falso,
-- que es peor que no tener contador. El avance es manual y de verdad.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local RouteProgress = {}
MitzuMPlus.RouteProgress = RouteProgress

local INACTIVE, PREPARED, ACTIVE, COMPLETED =
      "INACTIVE", "PREPARED", "ACTIVE", "COMPLETED"

RouteProgress.STATES = {
    INACTIVE = INACTIVE, PREPARED = PREPARED, ACTIVE = ACTIVE, COMPLETED = COMPLETED,
}

RouteProgress._state     = INACTIVE
RouteProgress._route     = nil
RouteProgress._pullIndex = 1
RouteProgress._cache     = nil   -- índices del pull actual
RouteProgress._lastReason = nil

local function bus() return MitzuMPlus.EventBus end

-- ─────────────────────────────────────────────────────────────────────────
-- ÍNDICES DEL PULL ACTUAL
--
-- Se construyen UNA vez al cambiar de pull, no en cada evento de unidad. Un
-- evento de nameplate debe resolverse con un acceso a tabla, no recorriendo
-- la ruta entera: en un pull grande eso serían cientos de recorridos por
-- segundo.
-- ─────────────────────────────────────────────────────────────────────────

function RouteProgress:_BuildCache()
    local pull = self:GetCurrentPull()
    local c = {
        requiredByNPCID = {},   -- [npcID]   = unidades esperadas
        remainingByNPCID = {},  -- copia viva; hoy nadie la decrementa
        clonesByEnemy   = {},   -- [enemyIdx] = { cloneIdx, ... }
        forcesSignatures = {},  -- [forces]  = nº de unidades con esa firma
        clones          = {},   -- lista plana, para GetCurrentPullClones
        totalUnits      = 0,
        mobEntries      = 0,
    }
    self._cache = c
    if not pull then return c end

    for _, m in ipairs(pull.mobs or {}) do
        c.mobEntries = c.mobEntries + 1
        local n = tonumber(m.amount) or 0
        c.totalUnits = c.totalUnits + n
        if m.npcID then
            c.requiredByNPCID[m.npcID]  = (c.requiredByNPCID[m.npcID] or 0) + n
            c.remainingByNPCID[m.npcID] = c.requiredByNPCID[m.npcID]
        end
        if m.enemyIdx then
            local l = c.clonesByEnemy[m.enemyIdx]
            if not l then l = {}; c.clonesByEnemy[m.enemyIdx] = l end
            for _, ci in ipairs(m.cloneIDs or {}) do l[#l + 1] = ci end
        end
        local f = tonumber(m.forces)
        if f and f > 0 then
            c.forcesSignatures[f] = (c.forcesSignatures[f] or 0) + n
        end
        for _, ci in ipairs(m.cloneIDs or {}) do
            c.clones[#c.clones + 1] = {
                enemyIdx = m.enemyIdx,
                cloneIdx = ci,
                npcID    = m.npcID,
                forces   = m.forces,
            }
        end
    end
    return c
end

function RouteProgress:_Cache()
    return self._cache or self:_BuildCache()
end

-- ─────────────────────────────────────────────────────────────────────────
-- CICLO DE VIDA
-- ─────────────────────────────────────────────────────────────────────────

function RouteProgress:Prepare(route)
    if type(route) ~= "table" or type(route.pulls) ~= "table" or #route.pulls == 0 then
        return false, "ruta vacía"
    end
    self._route     = route
    self._pullIndex = 1
    self._state     = PREPARED
    self._recovered = false
    self._recoveryContext = nil
    self:_BuildCache()
    if bus() then bus():Emit("MITZU_ROUTE_PREPARED", route, self) end
    return true
end

function RouteProgress:Start()
    if not self._route then return false, "no hay ruta preparada" end
    if self._state == ACTIVE then return true end
    self._state = ACTIVE
    if bus() then bus():Emit("MITZU_ROUTE_STARTED", self._route, self) end
    return true
end

function RouteProgress:Complete()
    if not self._route then return false end
    self._state = COMPLETED
    if bus() then bus():Emit("MITZU_ROUTE_COMPLETED", self._route, self) end
    return true
end

function RouteProgress:Reset()
    self._route, self._cache = nil, nil
    self._pullIndex = 1
    self._state = INACTIVE
    self._recovered = false
    self._recoveryContext = nil
    return true
end

-- ─────────────────────────────────────────────────────────────────────────
-- CONSULTAS
-- ─────────────────────────────────────────────────────────────────────────

function RouteProgress:GetState()     return self._state end
function RouteProgress:GetRoute()     return self._route end
function RouteProgress:GetPullIndex() return self._route and self._pullIndex or nil end
function RouteProgress:GetPullCount() return self._route and #self._route.pulls or 0 end

function RouteProgress:GetCurrentPull()
    if not self._route then return nil end
    return self._route.pulls[self._pullIndex]
end

function RouteProgress:GetRemainingByNPCID() return self:_Cache().remainingByNPCID end
function RouteProgress:GetRequiredByNPCID()  return self:_Cache().requiredByNPCID end
function RouteProgress:GetCurrentPullClones() return self:_Cache().clones end
function RouteProgress:GetForcesSignatures()  return self:_Cache().forcesSignatures end

-- ─────────────────────────────────────────────────────────────────────────
-- MOVIMIENTO
-- ─────────────────────────────────────────────────────────────────────────

function RouteProgress:SetPull(index, reason)
    if not self._route then return false, "no hay ruta cargada" end
    local n = tonumber(index)
    if not n then return false, "eso no es un número de pull" end
    n = math.floor(n)
    local total = self:GetPullCount()
    if n < 1 or n > total then
        return false, string.format("fuera de la ruta (1 a %d)", total)
    end
    -- Mismo pull: no se reconstruye el índice ni se emite nada. Sin esto, una
    -- UI que llame a SetPull en cada refresco dispararía MITZU_PULL_CHANGED en
    -- bucle y quien lo escuche repetiría trabajo.
    if n == self._pullIndex then return true, n end

    local anterior = self._pullIndex
    self._pullIndex = n
    self._lastReason = reason or "UNKNOWN"
    self:_BuildCache()
    if bus() then
        bus():Emit("MITZU_PULL_CHANGED", n, anterior, self._lastReason, self)
    end
    return true, n
end

-- ─────────────────────────────────────────────────────────────────────────
-- RECUPERACIÓN
--
-- API explícita para que nadie de fuera escriba `_pullIndex` a mano. Quien
-- restaura tiene que pasar por aquí, y aquí se valida.
--
-- La recuperación NO es un camino especial para la UI: emite el mismo
-- MITZU_PULL_CHANGED que un cambio manual (con reason "RECOVERY"), para que
-- el HUD y PullNavigator se enteren por la vía de siempre. Un segundo camino
-- solo para restaurar sería un segundo sitio donde el HUD puede quedarse
-- desincronizado.
-- ─────────────────────────────────────────────────────────────────────────

function RouteProgress:RestorePull(index, ctx)
    if not self._route then return false, "NO_ROUTE" end
    local n = tonumber(index)
    if not n then return false, "INVALID_PULL" end
    n = math.floor(n)
    if n < 1 or n > self:GetPullCount() then return false, "INVALID_PULL" end

    local anterior = self._pullIndex
    self._pullIndex  = n
    self._lastReason = "RECOVERY"
    self._recovered  = true
    self._recoveryContext = ctx
    self:_BuildCache()

    local b = bus()
    if b then
        b:Emit("MITZU_ROUTE_RECOVERED", self._route.id, n, ctx, self)
        -- Se emite aunque el pull coincida: quien escucha necesita saber que
        -- este numero viene de una recuperacion, no de haber empezado de cero.
        b:Emit("MITZU_PULL_CHANGED", n, anterior, "RECOVERY", self)
    end
    return true, n
end

function RouteProgress:WasRecovered() return self._recovered == true end
function RouteProgress:GetRecoveryContext() return self._recoveryContext end

function RouteProgress:NextPull(reason)
    if not self._route then return false, "no hay ruta cargada" end
    if self._pullIndex >= self:GetPullCount() then
        return false, "ya estás en el último pull"
    end
    return self:SetPull(self._pullIndex + 1, reason or "MANUAL")
end

function RouteProgress:PreviousPull(reason)
    if not self._route then return false, "no hay ruta cargada" end
    if self._pullIndex <= 1 then return false, "ya estás en el primer pull" end
    return self:SetPull(self._pullIndex - 1, reason or "MANUAL")
end

-- ─────────────────────────────────────────────────────────────────────────
-- ENGANCHE
-- ─────────────────────────────────────────────────────────────────────────

if MitzuMPlus.EventBus then
    -- PRE_KEY: la ruta se prepara en cuanto RouteManager la carga.
    MitzuMPlus.EventBus:On("MITZU_ROUTE_LOADED", function(route)
        -- Re-preparar la MISMA ruta que ya esta en marcha tiraria el pull al 1,
        -- y con el una recuperacion recien hecha. `Prepare` debe seguir
        -- preparando de cero cuando se le llama a proposito; lo que no puede
        -- es que un evento repetido lo provoque. La guarda va aqui.
        if route == RouteProgress:GetRoute()
           and (RouteProgress:GetState() == "ACTIVE" or RouteProgress:WasRecovered()) then
            return
        end
        pcall(function() RouteProgress:Prepare(route) end)
    end, 60)

    MitzuMPlus.EventBus:On("MITZU_ROUTE_UNLOADED", function()
        pcall(function() RouteProgress:Reset() end)
    end)

    -- RUNNING: la ruta YA está preparada. Aquí solo se activa.
    MitzuMPlus.EventBus:On("MITZU_KEY_STARTED", function()
        pcall(function() RouteProgress:Start() end)
    end, 40)   -- después de que Core cree la run

    MitzuMPlus.EventBus:On("MITZU_KEY_COMPLETED", function()
        pcall(function() RouteProgress:Complete() end)
    end)

    -- PullNavigator y su HUD siguen siendo los de la fase anterior. En vez de
    -- duplicar el número de pull en dos sitios, RouteProgress manda y el
    -- navegador se sincroniza. Dos dueños del mismo dato es como se acaba con
    -- un HUD que dice 4 mientras la ruta va por el 6.
    MitzuMPlus.EventBus:On("MITZU_PULL_CHANGED", function(nuevo)
        local PN = MitzuMPlus.AdaptiveRoute and MitzuMPlus.AdaptiveRoute.PullNavigator
        if PN and PN.GetCurrentPull and PN:GetCurrentPull() ~= nuevo then
            pcall(function() PN:SetCurrentPull(nuevo) end)
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────
-- INFORME
-- ─────────────────────────────────────────────────────────────────────────

function RouteProgress:StatusLines()
    if not self._route then
        return { "|cFFff9922No hay ninguna ruta preparada.|r" }
    end
    local c = self:_Cache()
    local L = {
        string.format("pull=%d/%d", self._pullIndex, self:GetPullCount()),
        string.format("routeState=%s", self._state),
        string.format("mobEntries=%d", c.mobEntries),
        string.format("totalUnits=%d", c.totalUnits),
    }
    local pull = self:GetCurrentPull()
    for _, m in ipairs(pull and pull.mobs or {}) do
        L[#L + 1] = string.format("  npcID=%s amount=%s enemyIdx=%s forces=%s clones=%s",
            tostring(m.npcID or "?"), tostring(m.amount),
            tostring(m.enemyIdx or "?"), tostring(m.forces or "?"),
            table.concat(m.cloneIDs or {}, ","))
    end
    if self._lastReason then
        L[#L + 1] = "lastChangeReason=" .. tostring(self._lastReason)
    end
    if self._recovered then
        L[#L + 1] = "recovered=true"
        L[#L + 1] = "recoveryPull=" .. tostring(self._pullIndex)
        L[#L + 1] = "recoveryReason=" ..
            tostring(self._recoveryContext and self._recoveryContext.reason or "?")
    end
    return L
end

return RouteProgress
