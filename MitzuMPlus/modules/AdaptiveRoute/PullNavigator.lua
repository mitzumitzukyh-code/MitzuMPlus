-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · PullNavigator v1.0
--
-- Dónde crees que estás dentro de la ruta. Nada más.
--
-- Un número entre 1 y el total de pulls, movido a mano. NO avanza solo, y esa
-- es una decisión, no una carencia: para avanzar solo haría falta saber que el
-- pull actual ha muerto, y en Midnight el combat log está cerrado a los addons
-- (ver BUG CLEU-1 en EventTracker). Un avance automático a base de suponer
-- daría un "PULL 7 / 21" convencido y equivocado, que es peor que no tenerlo.
--
-- Quien quiera enterarse de los cambios se suscribe con OnChange. El HUD lo
-- hace; el navegador no sabe que existe un HUD.
--
-- El estado NO se guarda en la DB a propósito: es de esta llave, no del
-- perfil. Al arrancar o parar la llave vuelve a 1.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local PullNavigator = {}
AR.PullNavigator = PullNavigator

PullNavigator._current   = 1
PullNavigator._listeners = {}

-- Total de pulls de la ruta cargada. Sin ruta devuelve 0, y con 0 el navegador
-- se deja mover igualmente entre 1 y 1: así los comandos contestan algo
-- sensato antes de entrar a la mazmorra en vez de fallar.
function PullNavigator:GetPullCount()
    local DS = AR.DataStructure
    local idx = DS and DS:Get()
    return (idx and idx.pullCount) or 0
end

function PullNavigator:GetCurrentPull()
    return self._current
end

function PullNavigator:OnChange(fn)
    if type(fn) == "function" then self._listeners[#self._listeners + 1] = fn end
end

function PullNavigator:_Notify()
    for _, fn in ipairs(self._listeners) do
        pcall(fn, self._current, self:GetPullCount())
    end
end

function PullNavigator:SetCurrentPull(index)
    local n = tonumber(index)
    if not n then return false, "eso no es un número de pull" end
    n = math.floor(n)
    local total = self:GetPullCount()
    local max = math.max(1, total)
    if n < 1 or n > max then
        return false, string.format("fuera de la ruta (1 a %d)", max)
    end
    if n == self._current then return true, n end
    self._current = n
    self:_Notify()
    return true, n
end

function PullNavigator:NextPull()
    local total = math.max(1, self:GetPullCount())
    if self._current >= total then
        return false, "ya estás en el último pull"
    end
    return self:SetCurrentPull(self._current + 1)
end

function PullNavigator:PreviousPull()
    if self._current <= 1 then
        return false, "ya estás en el primer pull"
    end
    return self:SetCurrentPull(self._current - 1)
end

function PullNavigator:Reset()
    self._current = 1
    self:_Notify()
    return true
end

-- Los enemigos del pull actual, tal cual los guardó la ruta. Es lo que consume
-- PullUnitResolver.
function PullNavigator:GetCurrentEnemies()
    local DS = AR.DataStructure
    return DS and DS:EnemiesOf(self._current) or nil
end

function PullNavigator:StatusLines()
    local total = self:GetPullCount()
    local out = {
        "|cFFd9b33e[PullNavigator]|r",
        string.format("  pull actual: |cFFf7d470%d|r de %s",
            self._current, total > 0 and tostring(total) or "? (sin ruta cargada)"),
    }
    local enemies = self:GetCurrentEnemies()
    if enemies then
        local grupos, clones = #enemies, 0
        for _, e in ipairs(enemies) do clones = clones + #(e.clones or {}) end
        out[#out + 1] = string.format("  en este pull: %d grupos · %d clones marcados en la ruta",
            grupos, clones)
    elseif total > 0 then
        out[#out + 1] = "  este pull no trae identidad de clones (ruta importada antes de la 7.10.0)"
    end
    out[#out + 1] = "  avance automático: |cFFff9922no|r — el combat log está cerrado en Midnight"
    return out
end

return PullNavigator
