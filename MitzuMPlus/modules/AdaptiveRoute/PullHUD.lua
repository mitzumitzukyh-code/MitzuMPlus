-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · PullHUD  —  adaptador hacia el Coach HUD V2
--
-- Hasta la 7.13 aquí vivía un frame propio que pintaba "PULL 4 / 21" leyendo
-- PullNavigator. Desde la 7.14 el HUD es uno solo, el Coach HUD V2
-- (modules/CoachHUD.lua), que lee el pull de RouteProgress, la autoridad.
--
-- Se conserva `AR.PullHUD` con los mismos métodos para que ningún llamante
-- existente se rompa, pero ya NO crea ningún frame: todo se delega en el HUD
-- V2, que se resuelve en la llamada (este fichero carga antes que él).
--
-- La posición que el jugador tuviera guardada (pullHudPoint/X/Y en
-- MPlusAdaptiveRouteDB) la copia el HUD V2 la primera vez; no se borra.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local PullHUD = {}
AR.PullHUD = PullHUD

local function hud() return MitzuMPlus.CoachHUD end

function PullHUD:Update()
    local H = hud()
    if H then H:Refresh("PULLHUD_UPDATE") end
end

function PullHUD:Show()
    local H = hud()
    return H and H:SetEnabled(true) or false
end

function PullHUD:Hide()
    local H = hud()
    if H then H:SetEnabled(false) end
    return true
end

function PullHUD:IsShown()
    local H = hud()
    return H ~= nil and H:IsVisible()
end

-- Alterna el HUD activado/desactivado. Devuelve si queda activado.
function PullHUD:Toggle()
    local H = hud()
    if not H then return false end
    return H:SetEnabled(not H:IsEnabled())
end

function PullHUD:ResetPosition()
    local H = hud()
    return H and H:ResetPosition() or false
end

return PullHUD
