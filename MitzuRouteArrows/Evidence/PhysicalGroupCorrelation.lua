-- ==========================================================================
-- MitzuRouteArrows · PhysicalGroupCorrelation v1 - FASE 3C
--
-- Correlacion diagnostica entre el NUMERO de placas engaged y los tamanos de
-- los grupos fisicos del pull. No identifica unidades ni grupos, no modifica
-- sus fuentes y no conoce Resolver, Guidance, RouteProgress ni RouteArrows.
--
-- MISMO TAMANO NO ES MISMO GRUPO. `g` tampoco es un combat pack. El resultado
-- mas fuerte de este modulo se llama HYPOTHESIS y identityState siempre queda
-- UNKNOWN.
-- ==========================================================================

local MRA = _G.MitzuRouteArrows
if not MRA then return end

-- AR: los demas modulos de este mismo addon.
-- Host: fachada de SOLO LECTURA sobre MitzuMPlusAPI (Core/Host.lua).
local AR = MRA
local Host = MRA.Host

local Correlation = {}
AR.PhysicalGroupCorrelation = Correlation

local UNKNOWN, HYPOTHESIS, AMBIGUOUS, NONE =
      "UNKNOWN", "HYPOTHESIS", "AMBIGUOUS", "NONE"

Correlation.STATES = {
    UNKNOWN = UNKNOWN, HYPOTHESIS = HYPOTHESIS,
    AMBIGUOUS = AMBIGUOUS, NONE = NONE,
}

Correlation.REASONS = {
    RUNTIME_NOT_RUNNING = "RUNTIME_NOT_RUNNING",
    NO_ROUTE = "NO_ROUTE",
    NO_PULL = "NO_PULL",
    NO_METADATA = "NO_METADATA",
    NO_ENGAGED = "NO_ENGAGED",
    UNIQUE_SIZE_CANDIDATE = "UNIQUE_SIZE_CANDIDATE",
    MULTIPLE_SIZE_CANDIDATES = "MULTIPLE_SIZE_CANDIDATES",
    NO_SIZE_CANDIDATE = "NO_SIZE_CANDIDATE",
    PARTIAL_GROUP_PRESENT = "PARTIAL_GROUP_PRESENT",
    UNGROUPED_CLONES_PRESENT = "UNGROUPED_CLONES_PRESENT",
    UNKNOWN_ENGAGEMENT = "UNKNOWN_ENGAGEMENT",
}

local function groupLabel(group)
    if (group.sublevel or 1) == 1 then return "g" .. tostring(group.g) end
    return "s" .. tostring(group.sublevel or "?") .. ":g" .. tostring(group.g)
end

local function baseResult(runtimeState, route, pullIndex)
    return {
        runtimeState = runtimeState or UNKNOWN,
        route = type(route) == "table" and route.id or nil,
        pull = tonumber(pullIndex),
        visible = 0, engaged = 0, notEngaged = 0, unknownEngagement = 0,
        physicalGroups = {}, clonesWithoutG = 0,
        candidateGroups = {}, candidateCount = 0,
        groupState = UNKNOWN,
        reasonCode = Correlation.REASONS.NO_METADATA,
        identityState = UNKNOWN,
    }
end

-- API pura: las dependencias de estado (ruta, pull, runtime y tokens visibles)
-- las entrega el comando diagnostico. Este modulo no registra eventos.
function Correlation:Correlate(route, pullIndex, tokens, runtimeState)
    local result = baseResult(runtimeState, route, pullIndex)
    local EE = AR.EngagementEvidence
    local PG = AR.PhysicalGroupMetadata

    if EE and type(EE.EvaluateTokens) == "function" then
        local _, summary = EE:EvaluateTokens(tokens or {})
        if type(summary) == "table" then
            result.visible = tonumber(summary.total) or 0
            result.engaged = tonumber(summary.engaged) or 0
            result.notEngaged = tonumber(summary.notEngaged) or 0
            result.unknownEngagement = tonumber(summary.unknown) or 0
        end
    end

    if not route then
        result.reasonCode = self.REASONS.NO_ROUTE
        return result
    end
    if not result.pull or type(route.pulls) ~= "table" or not route.pulls[result.pull] then
        result.reasonCode = self.REASONS.NO_PULL
        return result
    end
    if not PG or type(PG.AnalyzePull) ~= "function" then
        result.reasonCode = self.REASONS.NO_METADATA
        return result
    end

    local physical = PG:AnalyzePull(route, result.pull)
    if type(physical) ~= "table" or physical.state ~= "AVAILABLE" then
        result.reasonCode = self.REASONS.NO_METADATA
        return result
    end
    result.physicalGroups = physical.groups or {}
    result.clonesWithoutG = tonumber(physical.clonesWithoutG) or 0

    if result.runtimeState ~= "RUNNING" then
        result.reasonCode = self.REASONS.RUNTIME_NOT_RUNNING
        return result
    end
    if result.unknownEngagement > 0 then
        result.reasonCode = self.REASONS.UNKNOWN_ENGAGEMENT
        return result
    end
    if result.engaged == 0 then
        result.reasonCode = self.REASONS.NO_ENGAGED
        return result
    end

    local partialCompatible = false
    for _, group in ipairs(result.physicalGroups) do
        local selected = tonumber(group.selected)
        local total = tonumber(group.total)
        local compatible = false
        if group.state == "COMPLETE_GROUP" then
            compatible = selected == result.engaged
        elseif group.state == "PARTIAL_GROUP" then
            -- En un parcial ni selected ni physical describen necesariamente
            -- el combate observado. Solo se registra compatibilidad contextual.
            compatible = selected == result.engaged or total == result.engaged
            partialCompatible = partialCompatible or compatible
        end
        if compatible then
            result.candidateGroups[#result.candidateGroups + 1] = {
                label = groupLabel(group), g = group.g,
                sublevel = group.sublevel, selected = selected,
                total = total, physicalState = group.state,
            }
        end
    end
    result.candidateCount = #result.candidateGroups

    if result.clonesWithoutG > 0 then
        -- Puede haber grupos desconocidos de cualquier tamano. Los candidatos
        -- conocidos no forman un universo exhaustivo.
        result.groupState = UNKNOWN
        result.reasonCode = self.REASONS.UNGROUPED_CLONES_PRESENT
    elseif partialCompatible then
        result.groupState = AMBIGUOUS
        result.reasonCode = self.REASONS.PARTIAL_GROUP_PRESENT
    elseif result.candidateCount == 0 then
        result.groupState = NONE
        result.reasonCode = self.REASONS.NO_SIZE_CANDIDATE
    elseif result.candidateCount == 1 then
        result.groupState = HYPOTHESIS
        result.reasonCode = self.REASONS.UNIQUE_SIZE_CANDIDATE
    else
        result.groupState = AMBIGUOUS
        result.reasonCode = self.REASONS.MULTIPLE_SIZE_CANDIDATES
    end
    return result
end

function Correlation:StatusLines(result)
    result = type(result) == "table" and result or baseResult()
    local lines = {
        "runtimeState=" .. tostring(result.runtimeState or UNKNOWN),
        "route=" .. tostring(result.route or "-"),
        "pull=" .. tostring(result.pull or "-"),
        "visible=" .. tostring(result.visible or 0),
        "engaged=" .. tostring(result.engaged or 0),
        "notEngaged=" .. tostring(result.notEngaged or 0),
        "unknownEngagement=" .. tostring(result.unknownEngagement or 0),
        " ",
        "physicalGroups:",
    }

    for _, group in ipairs(result.physicalGroups or {}) do
        if group.state == "PARTIAL_GROUP" then
            lines[#lines + 1] = string.format("%s selected=%d physical=%s PARTIAL",
                groupLabel(group), tonumber(group.selected) or 0,
                tostring(group.total or "?"))
        else
            lines[#lines + 1] = string.format("%s size=%d %s",
                groupLabel(group), tonumber(group.selected) or 0,
                group.state == "COMPLETE_GROUP" and "COMPLETE" or "UNKNOWN")
        end
    end
    if (result.clonesWithoutG or 0) > 0 then
        lines[#lines + 1] = "UNGROUPED size=" .. tostring(result.clonesWithoutG)
    end

    local labels = {}
    for _, group in ipairs(result.candidateGroups or {}) do
        labels[#labels + 1] = group.label
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = "candidateGroups=" .. (#labels > 0 and table.concat(labels, ",") or "-")
    lines[#lines + 1] = "candidateCount=" .. tostring(result.candidateCount or 0)
    lines[#lines + 1] = "groupState=" .. tostring(result.groupState or UNKNOWN)
    lines[#lines + 1] = "reasonCode=" .. tostring(result.reasonCode or "NO_METADATA")
    lines[#lines + 1] = "identityState=UNKNOWN"
    lines[#lines + 1] = "|cFF999999(correlacion estructural; no identidad, decisiones ni flechas)|r"
    return lines
end

return Correlation
