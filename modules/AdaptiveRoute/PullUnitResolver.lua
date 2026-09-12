-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · PullUnitResolver v1.0
--
-- El puente entre "qué clones son del pull" y "qué placa viva es ese clon".
-- Son dos problemas distintos y este módulo existe para que no se mezclen:
--
--   PROBLEMA A — resuelto. La ruta de MDT dice enemyIdx + cloneIdx por pull, y
--                desde la 7.10.0 eso llega intacto a DataStructure.routeClones.
--   PROBLEMA B — NO resuelto, y hoy no se puede resolver de forma fiable.
--
-- ═════════════════════════════════════════════════════════════════════════
-- POR QUÉ NO HAY RESOLVER AUTOMÁTICO (las tres vías, una por una)
--
-- 1) Combat log. COMBAT_LOG_EVENT_UNFILTERED está cerrado a los addons en
--    Midnight (BUG CLEU-1, EventTracker). Ni siquiera se puede registrar.
--
-- 2) GUID. Aunque UnitGUID conteste y no venga como valor secreto, de él sale
--    npcID + spawnUID. El spawnUID es del servidor y no tiene ninguna relación
--    con el cloneIdx de MDT, que es un índice de su editor. Y el npcID por sí
--    solo NO identifica una copia: el NPC 261553 puede estar en el pull 1 con
--    los clones 1 y 4, y en el pull 8 con el 7. Marcar por npcID pondría
--    flecha a los cuatro. Es exactamente el fallo del sistema [SKIP] viejo.
--
-- 3) Posición. MDT guarda las coordenadas de cada clon, así que emparejar por
--    distancia sería lo correcto. Pero no hay API para la posición de un mob
--    arbitrario: UnitPosition solo responde de tu grupo, y C_Map da la tuya.
--    Sin coordenadas del mob no hay nada que comparar.
--
-- Conclusión: 0 flechas antes que 5 flechas bonitas sobre mobs equivocados.
-- ResolveCurrentPull() devuelve `automatico = false` y dice por qué. El día
-- que aparezca una vía sólida se implementa aquí dentro y nada más cambia.
-- ═════════════════════════════════════════════════════════════════════════
--
-- MIENTRAS TANTO: MODO MANUAL.
-- El jugador apunta a un mob y lo asigna al pull actual. La anotación es
-- token de placa -> pull, y se BORRA en cuanto esa placa se recicla: un token
-- reutilizado es otro mob, y heredar la anotación sería inventarse el dato.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local PullUnitResolver = {}
AR.PullUnitResolver = PullUnitResolver

PullUnitResolver._manual   = {}   -- [unitToken] = pullIndex  (anotación manual)
PullUnitResolver._resolved = {}   -- [unitToken] = true       (última resolución)
PullUnitResolver._stats    = { manuales = 0, caducadas = 0 }

local NO_AUTO = "sin resolver automático: en 12.1 no hay forma fiable de decir " ..
                "qué placa es cada clon (combat log cerrado, el GUID no lleva " ..
                "cloneIdx, y no hay posición de mobs)"

local function navigator()
    return AR.PullNavigator
end

local function arrows()
    return AR.RouteArrows
end

-- ─────────────────────────────────────────────────────────────────────────
-- MODO MANUAL
-- ─────────────────────────────────────────────────────────────────────────

function PullUnitResolver:MarkTarget()
    local RA = arrows()
    if not RA then return false, "RouteArrows no está cargado" end
    if not UnitExists("target") then return false, "no tienes objetivo" end

    local token = RA:TokenFor("target")
    if not token then return false, "el objetivo no tiene placa visible" end

    local PN = navigator()
    local pull = PN and PN:GetCurrentPull() or 1
    self._manual[token] = pull
    self._stats.manuales = self._stats.manuales + 1

    local ok, why = RA:MarkUnit(token)
    if not ok then
        self._manual[token] = nil
        return false, tostring(why)
    end
    self._resolved[token] = true
    return true, token, pull
end

function PullUnitResolver:UnmarkTarget()
    local RA = arrows()
    if not RA then return false, "RouteArrows no está cargado" end
    if not UnitExists("target") then return false, "no tienes objetivo" end

    local token = RA:TokenFor("target")
    if not token then return false, "el objetivo no tiene placa visible" end
    if not self._manual[token] then return false, "ese mob no estaba asignado" end

    self._manual[token]   = nil
    self._resolved[token] = nil
    RA:UnmarkUnit(token)
    return true, token
end

-- ─────────────────────────────────────────────────────────────────────────
-- API PEDIDA
-- ─────────────────────────────────────────────────────────────────────────

-- Pone flecha a las placas asignadas al pull actual y se la quita a las demás.
-- Devuelve: nº marcadas, automatico (siempre false hoy), motivo.
function PullUnitResolver:ResolveCurrentPull()
    local RA = arrows()
    if not RA then return 0, false, "RouteArrows no está cargado" end
    local PN = navigator()
    local pull = PN and PN:GetCurrentPull() or 1

    local marcadas = 0
    local nuevos = {}
    for token, asignado in pairs(self._manual) do
        if asignado == pull then
            if RA:MarkUnit(token) then
                nuevos[token] = true
                marcadas = marcadas + 1
            end
        end
    end

    -- Lo que estaba resuelto antes y ya no toca, se apaga. Sin esto, cambiar
    -- de pull acumularía flechas de todos los pulls visitados.
    for token in pairs(self._resolved) do
        if not nuevos[token] then RA:UnmarkUnit(token) end
    end
    self._resolved = nuevos

    return marcadas, false, NO_AUTO
end

function PullUnitResolver:GetResolvedUnits()
    local out = {}
    for token in pairs(self._resolved) do out[#out + 1] = token end
    table.sort(out)
    return out
end

function PullUnitResolver:Clear()
    local RA = arrows()
    local n = 0
    for token in pairs(self._resolved) do
        if RA then RA:UnmarkUnit(token) end
        n = n + 1
    end
    self._manual   = {}
    self._resolved = {}
    return n
end

-- Una anotación caduca cuando su placa se recicla: el token es el mismo pero
-- el mob no. Es el mismo bug fantasma que RouteArrows evita con sus flechas,
-- aplicado a los datos en vez de a los frames.
function PullUnitResolver:_Expire(token)
    if self._manual[token] == nil and self._resolved[token] == nil then return end
    self._manual[token]   = nil
    self._resolved[token] = nil
    self._stats.caducadas = self._stats.caducadas + 1
end

function PullUnitResolver:WhyNoAuto()
    return NO_AUTO
end

function PullUnitResolver:StatusLines()
    local PN = navigator()
    local DS = AR.DataStructure
    local idx = DS and DS:Get()
    local pull = PN and PN:GetCurrentPull() or 1

    local out = {
        "|cFFd9b33e[PullUnitResolver]|r",
        string.format("  pull actual: %d · asignaciones manuales vivas: %d",
            pull, (function() local n = 0 for _ in pairs(self._manual) do n = n + 1 end return n end)()),
        string.format("  con flecha ahora: %d · anotaciones caducadas por reciclaje: %d",
            #self:GetResolvedUnits(), self._stats.caducadas),
    }

    -- PROBLEMA A: lo que sí sabemos.
    if idx and idx.hasCloneData then
        out[#out + 1] = string.format(
            "  identidad de ruta: |cFF21de66OK|r · %d clones repartidos en %d pulls%s",
            idx.cloneCount, idx.pullCount,
            idx.cloneConflicts and (" · |cFFff9922" .. idx.cloneConflicts .. " clones repetidos en la ruta|r") or "")
    elseif idx then
        out[#out + 1] = "  identidad de ruta: |cFFff9922sin clones|r — reimporta con |cFFf7d470/emp rutastodas|r"
    else
        out[#out + 1] = "  identidad de ruta: sin ruta indexada"
    end

    -- PROBLEMA B: lo que no.
    out[#out + 1] = "  emparejar clon con placa viva: |cFFff9922no automático|r"
    out[#out + 1] = "    " .. NO_AUTO
    out[#out + 1] = "    Usa |cFFf7d470/emp marktarget|r para asignar mobs a mano."
    return out
end

-- ─────────────────────────────────────────────────────────────────────────
-- ENGANCHE CON EL RECICLAJE DE PLACAS
--
-- RouteArrows publica estos avisos sin saber para qué se usan; aquí es donde
-- se convierten en caducidad de anotaciones. El renderizador sigue sin decidir
-- nada, que era la condición del diseño.
-- ─────────────────────────────────────────────────────────────────────────

if AR.RouteArrows then
    AR.RouteArrows.OnNameplateAdded = function(token)
        PullUnitResolver:_Expire(token)
    end
    AR.RouteArrows.OnNameplateRemoved = function(token)
        PullUnitResolver:_Expire(token)
    end
end

return PullUnitResolver
