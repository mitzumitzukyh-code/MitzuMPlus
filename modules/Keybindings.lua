-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Keybindings (v1.0)
-- Keybinding support for opening window, tabs, overlay toggle
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"

-- Register binding category header
BINDING_HEADER_MITZUMPLUS = "MitzuMPlus M+ Historial"

-- Binding names (these correspond to Bindings.xml)
BINDING_NAME_MITZUMPLUS_TOGGLE     = "Toggle MitzuMPlus Window"
BINDING_NAME_MITZUMPLUS_HISTORIAL  = "Open History Tab"
BINDING_NAME_MITZUMPLUS_STATS      = "Open M+ Coach Tab"
BINDING_NAME_MITZUMPLUS_OVERLAY    = "Toggle Overlay"
BINDING_NAME_MITZUMPLUS_ROUTE_MARK_TARGET   = "Route: mark target for current pull"
BINDING_NAME_MITZUMPLUS_ROUTE_NEXT_PULL     = "Route: next pull"
BINDING_NAME_MITZUMPLUS_ROUTE_PREVIOUS_PULL = "Route: previous pull"

-- ─────────────────────────────────────────────────────────────────────────
-- BINDING ACTIONS (called from Bindings.xml)
-- ─────────────────────────────────────────────────────────────────────────

function MitzuMPlus_ToggleBinding()
    local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
    if MitzuMPlus and MitzuMPlus.ToggleWindow then
        MitzuMPlus:ToggleWindow()
    end
end

function MitzuMPlus_HistorialBinding()
    local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
    if MitzuMPlus and MitzuMPlus.ShowTab then
        MitzuMPlus:ShowTab("historial")
    end
end

-- v5.5.0: la pestaña ESTADISTICAS ya no existe. La tecla se conserva (borrarla
-- dejaria un binding huerfano en el perfil del usuario) pero ahora abre M+ COACH,
-- que es lo que se consulta de verdad entre llave y llave.
function MitzuMPlus_StatsBinding()
    local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
    if MitzuMPlus and MitzuMPlus.ShowTab then
        MitzuMPlus:ShowTab("coach")
    end
end


function MitzuMPlus_OverlayBinding()
    local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
    if MitzuMPlus and MitzuMPlus.ToggleOverlay then
        MitzuMPlus:ToggleOverlay()
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- RUTA ADAPTATIVA
--
-- Sin tecla asignada de fabrica: el jugador las pone desde Key Bindings. Fijar
-- aqui un ALT+K cualquiera pisaria lo que ya tenga puesto, y en una M+ eso se
-- paga caro.
--
-- Se resuelven los modulos EN LA LLAMADA, no al cargar: este fichero carga
-- antes que AdaptiveRoute y guardar la referencia aqui daria siempre nil.
-- ─────────────────────────────────────────────────────────────────────────

local function AR()
    local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME, true)
    return MitzuMPlus and MitzuMPlus.AdaptiveRoute or nil
end

function MitzuMPlus_RouteMarkTargetBinding()
    local ar = AR()
    local PUR = ar and ar.PullUnitResolver
    if not PUR then return end
    local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME, true)
    local ok, info, pull = PUR:MarkTarget()
    if MitzuMPlus and MitzuMPlus.Print then
        MitzuMPlus:Print(ok
            and string.format("|cFF21de66Objetivo asignado|r al pull %d.", pull)
            or ("|cFFff9922No se pudo asignar:|r " .. tostring(info)))
    end
end

-- Las dos de navegacion comparten cuerpo: mover el indice y repintar las
-- flechas del pull nuevo. Sin el repintado la tecla solo cambiaria un numero.
local function moverPull(fn)
    local ar = AR()
    local PN = ar and ar.PullNavigator
    if not PN then return end
    local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME, true)
    local ok, info = fn(PN)
    if ok and ar.PullUnitResolver then ar.PullUnitResolver:ResolveCurrentPull() end
    if MitzuMPlus and MitzuMPlus.Print then
        if ok then
            local total = PN:GetPullCount()
            MitzuMPlus:Print(string.format("|cFF21de66Pull|r %d de %s", info,
                total > 0 and tostring(total) or "?"))
        else
            MitzuMPlus:Print("|cFFff9922" .. tostring(info) .. "|r")
        end
    end
end

function MitzuMPlus_RouteNextPullBinding()
    moverPull(function(PN) return PN:NextPull() end)
end

function MitzuMPlus_RoutePreviousPullBinding()
    moverPull(function(PN) return PN:PreviousPull() end)
end
