-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · RouteArrowPresenter v1  —  traducir decisiones a flechas
--
-- La única capa entre GuidanceEngine y RouteArrows. Recibe decisiones y llama
-- a la API pública de RouteArrows. Nada más.
--
-- NO decide qué mob es del pull. NO lee rutas. NO interpreta MDT. NO identifica
-- enemigos. NO lleva progreso. Si alguna vez necesita saber cualquiera de esas
-- cosas, es que la decisión se ha colado en la capa equivocada.
--
-- POR QUÉ EXISTE, si RouteArrows ya sabe marcar y desmarcar: porque alguien
-- tiene que escuchar los eventos, mantener qué placas llevan flecha NUESTRA, y
-- reaccionar a los cambios de pull. Meter eso en RouteArrows lo convertiría en
-- un módulo que sabe qué es un pull, y RouteArrows lleva funcionando en vivo
-- precisamente porque no sabe nada de eso.
--
-- RouteArrows NO SE TOCA. Se usa su API pública tal cual:
--     MarkUnit · UnmarkUnit · IsMarked · CountActive
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local RouteArrowPresenter = {}
MitzuMPlus.RouteArrowPresenter = RouteArrowPresenter

-- [unitToken] = true. Solo las flechas que ha puesto ESTE presenter. Sin este
-- registro no se podría distinguir una flecha nuestra de una de
-- /emp marktarget, y ClearAll se llevaría por delante las del jugador.
RouteArrowPresenter._tracked = {}
RouteArrowPresenter._stats   = { shown = 0, hidden = 0, reevaluations = 0 }

local function arrows()
    local AR = MitzuMPlus.AdaptiveRoute
    return AR and AR.RouteArrows or nil
end
local function guidance() return MitzuMPlus.GuidanceEngine end

-- ─────────────────────────────────────────────────────────────────────────
-- APLICAR UNA DECISIÓN
-- ─────────────────────────────────────────────────────────────────────────

function RouteArrowPresenter:Apply(unitToken, decision)
    local RA = arrows()
    if not RA or type(unitToken) ~= "string" or type(decision) ~= "table" then
        return false
    end

    if decision.shouldMark then
        local ok = RA:MarkUnit(unitToken)
        if ok then
            if not self._tracked[unitToken] then
                self._stats.shown = self._stats.shown + 1
            end
            self._tracked[unitToken] = true
        end
        return ok == true
    end

    -- Sin flecha. Solo se retira si la habíamos puesto nosotros.
    if self._tracked[unitToken] then
        RA:UnmarkUnit(unitToken)
        self._tracked[unitToken] = nil
        self._stats.hidden = self._stats.hidden + 1
    end
    return false
end

function RouteArrowPresenter:ShowForNameplate(unitToken)
    local G = guidance()
    if not G then return false end
    return self:Apply(unitToken, G:Evaluate(unitToken))
end

function RouteArrowPresenter:HideForNameplate(unitToken)
    local RA = arrows()
    if not RA or type(unitToken) ~= "string" then return false end
    if not self._tracked[unitToken] then return false end
    RA:UnmarkUnit(unitToken)
    self._tracked[unitToken] = nil
    self._stats.hidden = self._stats.hidden + 1
    return true
end

function RouteArrowPresenter:ClearAll()
    local RA = arrows()
    local n = 0
    for token in pairs(self._tracked) do
        if RA then RA:UnmarkUnit(token) end
        n = n + 1
    end
    self._tracked = {}
    self._stats.hidden = self._stats.hidden + n
    return n
end

-- Repasa TODAS las placas visibles con el pull que haya AHORA. Es lo que hace
-- que cambiar de pull surta efecto sin esperar a que las placas se reciclen.
function RouteArrowPresenter:Reevaluate()
    local G = guidance()
    if not G then return 0 end
    self._stats.reevaluations = self._stats.reevaluations + 1

    local decisiones = G:EvaluateAll()
    local marcadas = 0
    for token, d in pairs(decisiones) do
        if self:Apply(token, d) then marcadas = marcadas + 1 end
    end

    -- Una flecha nuestra sobre una placa que ya no se ve es basura: se retira.
    -- Puede pasar si un REMOVED se perdió.
    local visibles = {}
    for _, t in ipairs(G:GetVisible()) do visibles[t] = true end
    for token in pairs(self._tracked) do
        if not visibles[token] then self:HideForNameplate(token) end
    end
    return marcadas
end

function RouteArrowPresenter:CountTracked()
    local n = 0
    for _ in pairs(self._tracked) do n = n + 1 end
    return n
end

function RouteArrowPresenter:IsTracked(unitToken)
    return unitToken ~= nil and self._tracked[unitToken] == true
end

-- ─────────────────────────────────────────────────────────────────────────
-- EVENTOS DEL CLIENTE
--
-- Frame propio. Los ganchos RouteArrows.OnNameplateAdded/Removed son de
-- asignación única y ya los usa PullUnitResolver; reasignarlos lo habría
-- roto en silencio.
-- ─────────────────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

frame:SetScript("OnEvent", function(_, event, unit)
    if type(unit) ~= "string" then return end
    local G = guidance()
    if not G then return end

    if event == "NAME_PLATE_UNIT_ADDED" then
        local d = G:OnNameplateAdded(unit)
        if d then RouteArrowPresenter:Apply(unit, d) end

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        -- La placa dejó de verse. Se suelta la flecha y se olvida el token.
        -- NADA MÁS: ni muerte, ni tropas, ni avance de pull. RouteArrows
        -- también libera por su cuenta al reciclarse la placa; esto mantiene
        -- coherente el registro del presenter.
        RouteArrowPresenter:HideForNameplate(unit)
        G:OnNameplateRemoved(unit)
    end
end)

-- ─────────────────────────────────────────────────────────────────────────
-- EVENTOS INTERNOS
-- ─────────────────────────────────────────────────────────────────────────

if MitzuMPlus.EventBus then
    local bus = MitzuMPlus.EventBus

    -- Cambio de pull: lo que valía para el pull 3 no vale para el 4.
    bus:On("MITZU_PULL_CHANGED", function()
        pcall(function()
            -- La prueba visual no sobrevive a un cambio de pull: es de usar y
            -- tirar, y dejarla puesta daría flechas sin explicación.
            local G = guidance()
            if G then G:ClearDebugForced() end
            RouteArrowPresenter:Reevaluate()
        end)
    end, 40)

    -- La llave arranca: hay placas ya visibles que nunca dispararán un ADDED.
    bus:On("MITZU_ROUTE_STARTED", function()
        pcall(function() RouteArrowPresenter:Reevaluate() end)
    end, 40)

    -- Tras recuperar sesión, RouteProgress ya trae el pull restaurado. Aquí
    -- solo se relee: el pull NO se toca desde el presenter.
    bus:On("MITZU_ROUTE_RECOVERED", function()
        pcall(function() RouteArrowPresenter:Reevaluate() end)
    end, 40)

    local function limpiar()
        pcall(function()
            local G = guidance()
            if G then G:ClearDebugForced() end
            RouteArrowPresenter:ClearAll()
        end)
    end
    bus:On("MITZU_KEY_COMPLETED", limpiar)
    bus:On("MITZU_KEY_RESET", limpiar)
    bus:On("MITZU_ROUTE_UNLOADED", limpiar)
end

-- ─────────────────────────────────────────────────────────────────────────
-- INFORME
-- ─────────────────────────────────────────────────────────────────────────

function RouteArrowPresenter:StatusLines()
    local RA = arrows()
    return {
        "tracked=" .. self:CountTracked(),
        "arrowsActive=" .. tostring(RA and RA:CountActive() or "?"),
        string.format("shown=%d hidden=%d reevaluations=%d",
            self._stats.shown, self._stats.hidden, self._stats.reevaluations),
    }
end

return RouteArrowPresenter
