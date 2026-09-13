-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Keybindings (v1.0)
-- Keybinding support for opening window, tabs, overlay toggle
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"

-- Register binding category header
BINDING_HEADER_MITZUMPLUS = "MitzuMPlus M+ Historial"

-- Binding names (these correspond to Bindings.xml)
BINDING_NAME_MITZUMPLUS_TOGGLE     = "Toggle MitzuMPlus Window"
BINDING_NAME_MITZUMPLUS_HISTORIAL  = "Open History Tab"
BINDING_NAME_MITZUMPLUS_STATS      = "Open M+ Coach Tab"
BINDING_NAME_MITZUMPLUS_OVERLAY    = "Toggle Overlay"
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

function MitzuMPlus_HistoryTabBinding()
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

-- La tecla "marcar objetivo para el pull actual" asignaba una placa a un clon
-- de la ruta para pintarle flecha. Es de flechas, asi que se fue con ellas al
-- addon MitzuRouteArrows (su propio Bindings.xml).

-- Las dos de navegacion comparten cuerpo: mover el indice del pull.
--
-- Antes, tras mover, se llamaba aqui a PullUnitResolver para repintar las
-- flechas del pull nuevo. Ese modulo ya no es del core: MitzuRouteArrows se
-- entera del cambio por la API publica (PullNavigator:OnChange, expuesto como
-- NAVIGATOR_PULL_CHANGED) y repinta por su cuenta.
--
-- v7.14.0: las teclas movian SOLO PullNavigator, mientras /emp next y
-- /emp pull movian RouteProgress. Con el Coach HUD V2 leyendo la autoridad
-- (RouteProgress), pulsar la tecla no cambiaba el HUD. Ahora hacen lo mismo
-- que /emp pull: RouteProgress si hay ruta cargada (PullNavigator se
-- sincroniza solo via MITZU_PULL_CHANGED) y PullNavigator solo como respaldo.
local function moverPull(fn)
    local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME, true)
    local RP = MitzuMPlus and MitzuMPlus.RouteProgress
    local ar = AR()
    local PN = ar and ar.PullNavigator
    local mover
    if RP and RP.GetRoute and RP:GetRoute() then
        mover = RP
    elseif PN then
        mover = PN
    else
        return
    end
    local ok, info = fn(mover)
    if MitzuMPlus and MitzuMPlus.Print then
        if ok then
            local total = mover:GetPullCount()
            MitzuMPlus:Print(string.format("|cFF21de66Pull|r %d de %s", info,
                total > 0 and tostring(total) or "?"))
        else
            MitzuMPlus:Print("|cFFff9922" .. tostring(info) .. "|r")
        end
    end
end

function MitzuMPlus_RouteNextPullBinding()
    moverPull(function(m) return m:NextPull("KEYBIND") end)
end

function MitzuMPlus_RoutePreviousPullBinding()
    moverPull(function(m) return m:PreviousPull("KEYBIND") end)
end
