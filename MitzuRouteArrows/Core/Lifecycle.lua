-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuRouteArrows · Core/Lifecycle
--
-- Lo que antes hacía MitzuMPlus por estos módulos, ahora lo hace este addon
-- por sí mismo, escuchando la API pública:
--
--   · Al arrancar la llave, las asignaciones manuales de la llave anterior se
--     descartan (antes: AdaptiveRoute:StartForRun -> PullUnitResolver:Clear).
--   · Al terminar, resetear o desmontar la run, se quitan flechas y
--     asignaciones (antes: AdaptiveRoute:StopForRun).
--   · Al moverse el pull del navegador, las flechas de las asignaciones se
--     recolocan en el pull nuevo (antes: la tecla de siguiente/anterior pull
--     llamaba a PullUnitResolver:ResolveCurrentPull). Ahora se hace ante
--     CUALQUIER cambio del navegador, no solo con la tecla; sin asignaciones
--     manuales es una operación vacía.
--
-- El core no sabe que esto existe. Carga DESPUÉS de todos los módulos.
-- ═══════════════════════════════════════════════════════════════════════════

local MRA = _G.MitzuRouteArrows
if not MRA then return end

local Host = MRA.Host
local Lifecycle = {}
MRA.Lifecycle = Lifecycle

local function llamar(modulo, metodo)
    local m = MRA[modulo]
    if m and type(m[metodo]) == "function" then pcall(m[metodo], m) end
end

local function alArrancar()
    llamar("PullUnitResolver", "Clear")
end

local function alTerminar()
    llamar("PullUnitResolver", "Clear")
    llamar("RouteArrows", "ClearAll")
end

local function alMoverNavegador()
    llamar("PullUnitResolver", "ResolveCurrentPull")
end

Host.EventBus:On("MITZU_KEY_STARTED",   alArrancar, 60)
Host.EventBus:On("MITZU_KEY_COMPLETED", alTerminar, 60)
Host.EventBus:On("MITZU_KEY_RESET",     alTerminar, 60)
Host.EventBus:On("RUN_TEARDOWN",        alTerminar, 60)
Host.EventBus:On("NAVIGATOR_PULL_CHANGED", alMoverNavegador, 60)

-- Llamado desde Core/Bootstrap en PLAYER_LOGIN. Registra las suscripciones
-- que al cargar no pudieron hacerse (API aún ausente) e informa de cuántas
-- quedaron activas.
function Lifecycle:Attach()
    return Host:Attach()
end

-- ─────────────────────────────────────────────────────────────────────────
-- TECLAS  (Bindings.xml)
--
-- MITZUMPLUS_ROUTE_MARK_TARGET conserva el nombre que tenía cuando vivía en
-- MitzuMPlus: WoW guarda la tecla asignada por NOMBRE de binding, así que
-- mantenerlo preserva la tecla de quien ya la tuviera puesta.
-- ─────────────────────────────────────────────────────────────────────────

BINDING_HEADER_MITZUROUTEARROWS = "MitzuRouteArrows (EXPERIMENTAL)"
BINDING_NAME_MITZUMPLUS_ROUTE_MARK_TARGET = "Route: mark target for current pull"

function MitzuRouteArrows_MarkTargetBinding()
    if not MRA:CanOperate() then
        MRA:Print("|cFFff9922" .. MRA:HostMessage() .. "|r")
        return
    end
    local PUR = MRA.PullUnitResolver
    if not PUR then return end
    local ok, info, pull = PUR:MarkTarget()
    MRA:Print(ok
        and string.format("|cFF21de66Objetivo asignado|r al pull %d.", pull)
        or ("|cFFff9922No se pudo asignar:|r " .. tostring(info)))
end

return Lifecycle
