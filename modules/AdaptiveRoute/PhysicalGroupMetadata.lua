-- ==========================================================================
-- MitzuMPlus - AdaptiveRoute - PhysicalGroupMetadata v1
--
-- Lectura y diagnostico de la geometria estatica de MDT. Describe donde fue
-- colocado un clon y con que grupo visual fue dibujado. No observa unidades,
-- no resuelve identidad y no conoce Guidance, RouteProgress ni RouteArrows.
--
-- INVARIANTE: `g` es contexto fisico de MDT. No significa combat pack,
-- identidad de ruta, MATCH ni una orden de mostrar flecha.
-- ==========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local PhysicalGroupMetadata = {}
AR.PhysicalGroupMetadata = PhysicalGroupMetadata

local function dungeonData(dungeonIdx)
    local all = MitzuMPlus.MDTPhysicalGroupData
    return all and all[tonumber(dungeonIdx) or -1] or nil
end

-- La tabla devuelta pertenece al snapshot y es de solo lectura.
function PhysicalGroupMetadata:Get(dungeonIdx, enemyIdx, cloneIdx)
    local dungeon = dungeonData(dungeonIdx)
    local enemy = dungeon and dungeon[tonumber(enemyIdx) or -1]
    return enemy and enemy[tonumber(cloneIdx) or -1] or nil
end

local function groupKey(meta)
    if type(meta) ~= "table" or tonumber(meta.g) == nil then return nil end
    return tostring(tonumber(meta.sublevel) or 0) .. ":" .. tostring(tonumber(meta.g))
end

local function universeFor(dungeonIdx)
    local groups = {}
    for _, enemy in pairs(dungeonData(dungeonIdx) or {}) do
        for _, meta in pairs(enemy) do
            local key = groupKey(meta)
            if key then
                local group = groups[key]
                if not group then
                    group = {
                        g = tonumber(meta.g), sublevel = tonumber(meta.sublevel), clones = 0,
                    }
                    groups[key] = group
                end
                group.clones = group.clones + 1
            end
        end
    end
    return groups
end

local function metadataFor(self, route, mob, cloneIdx)
    -- Formato extensible: una ruta futura puede traer su propia fotografia.
    -- Las rutas actuales caen al snapshot empaquetado, sin depender de MDT.
    local embedded = type(mob.cloneMetadata) == "table" and mob.cloneMetadata[cloneIdx] or nil
    return embedded or self:Get(route.mdtDungeonIdx, mob.enemyIdx, cloneIdx)
end

function PhysicalGroupMetadata:AnalyzePull(route, pullIndex)
    local result = {
        pull = tonumber(pullIndex), groups = {}, clones = 0,
        clonesWithMetadata = 0, clonesWithG = 0, clonesWithoutG = 0,
        partialGroups = 0, state = "UNAVAILABLE",
    }
    if type(route) ~= "table" or type(route.pulls) ~= "table" then return result end
    local pull = route.pulls[result.pull or -1]
    if type(pull) ~= "table" then return result end
    result.state = dungeonData(route.mdtDungeonIdx) and "AVAILABLE" or "UNAVAILABLE"
    local universe = universeFor(route.mdtDungeonIdx)
    local selected = {}

    for _, mob in ipairs(pull.mobs or {}) do
        for _, cloneIdx in ipairs(mob.cloneIDs or {}) do
            result.clones = result.clones + 1
            local meta = metadataFor(self, route, mob, cloneIdx)
            if meta then result.clonesWithMetadata = result.clonesWithMetadata + 1 end
            local key = groupKey(meta)
            if key then
                result.clonesWithG = result.clonesWithG + 1
                local group = selected[key]
                if not group then
                    local full = universe[key]
                    group = {
                        g = tonumber(meta.g), sublevel = tonumber(meta.sublevel),
                        selected = 0, total = full and full.clones or nil,
                    }
                    selected[key] = group
                end
                group.selected = group.selected + 1
            else
                result.clonesWithoutG = result.clonesWithoutG + 1
            end
        end
    end

    for _, group in pairs(selected) do
        if group.total and group.selected < group.total then
            group.state = "PARTIAL_GROUP"
            result.partialGroups = result.partialGroups + 1
        elseif group.total and group.selected == group.total then
            group.state = "COMPLETE_GROUP"
        else
            group.state = "UNKNOWN_COVERAGE"
        end
        result.groups[#result.groups + 1] = group
    end
    table.sort(result.groups, function(a, b)
        local sa, sb = a.sublevel or 0, b.sublevel or 0
        if sa ~= sb then return sa < sb end
        return (a.g or 0) < (b.g or 0)
    end)
    result.multipleGroups = #result.groups > 1
    return result
end

function PhysicalGroupMetadata:AnalyzeRoute(route)
    local result = {
        pulls = 0, clones = 0, clonesWithMetadata = 0,
        clonesWithG = 0, clonesWithoutG = 0,
        pullsWithMultipleG = 0, partialGroups = 0,
    }
    if type(route) ~= "table" or type(route.pulls) ~= "table" then return result end
    result.pulls = #route.pulls
    for pullIndex = 1, #route.pulls do
        local pull = self:AnalyzePull(route, pullIndex)
        result.clones = result.clones + pull.clones
        result.clonesWithMetadata = result.clonesWithMetadata + pull.clonesWithMetadata
        result.clonesWithG = result.clonesWithG + pull.clonesWithG
        result.clonesWithoutG = result.clonesWithoutG + pull.clonesWithoutG
        result.partialGroups = result.partialGroups + pull.partialGroups
        if pull.multipleGroups then
            result.pullsWithMultipleG = result.pullsWithMultipleG + 1
        end
    end
    return result
end

function PhysicalGroupMetadata:GlobalCoverage()
    local total = {
        routes = 0, pulls = 0, clones = 0, clonesWithMetadata = 0,
        clonesWithG = 0, clonesWithoutG = 0,
        pullsWithMultipleG = 0, partialGroups = 0,
    }
    local db = MitzuMPlus.NativeRouteDB
    if not db then return total end
    for _, dungeonKey in ipairs(db:AllKeys()) do
        for _, route in ipairs(db:GetForDungeon(dungeonKey)) do
            local r = self:AnalyzeRoute(route)
            total.routes = total.routes + 1
            for _, field in ipairs({
                "pulls", "clones", "clonesWithMetadata", "clonesWithG",
                "clonesWithoutG", "pullsWithMultipleG", "partialGroups",
            }) do
                total[field] = total[field] + r[field]
            end
        end
    end
    return total
end

local function groupLabel(group)
    if (group.sublevel or 1) == 1 then return "g" .. tostring(group.g) end
    return "s" .. tostring(group.sublevel or "?") .. ":g" .. tostring(group.g)
end

function PhysicalGroupMetadata:StatusLines(route, pullIndex)
    local lines = {}
    if type(route) ~= "table" then return { "physicalMetadata=NO_ROUTE" } end
    pullIndex = tonumber(pullIndex) or 1
    local pull = self:AnalyzePull(route, pullIndex)
    lines[#lines + 1] = "route=" .. tostring(route.id or "UNKNOWN")
    lines[#lines + 1] = "source=" .. tostring(MitzuMPlus.MDTPhysicalGroupDataVersion or "UNAVAILABLE")
    lines[#lines + 1] = "pull=" .. tostring(pullIndex)
    lines[#lines + 1] = "metadataState=" .. pull.state
    for _, group in ipairs(pull.groups) do
        if group.state == "PARTIAL_GROUP" then
            lines[#lines + 1] = string.format("%s clones=%d/%s PARTIAL_GROUP",
                groupLabel(group), group.selected, tostring(group.total or "?"))
        else
            lines[#lines + 1] = string.format("%s clones=%d %s",
                groupLabel(group), group.selected, group.state)
        end
    end
    if pull.clonesWithoutG > 0 then
        lines[#lines + 1] = "withoutG=" .. tostring(pull.clonesWithoutG)
    end

    local routeStats = self:AnalyzeRoute(route)
    lines[#lines + 1] = string.format(
        "routeCoverage clonesWithG=%d clonesWithoutG=%d pullsWithMultipleG=%d partialGroups=%d",
        routeStats.clonesWithG, routeStats.clonesWithoutG,
        routeStats.pullsWithMultipleG, routeStats.partialGroups)
    local global = self:GlobalCoverage()
    lines[#lines + 1] = string.format(
        "globalCoverage routes=%d clonesWithG=%d clonesWithoutG=%d pullsWithMultipleG=%d partialGroups=%d",
        global.routes, global.clonesWithG, global.clonesWithoutG,
        global.pullsWithMultipleG, global.partialGroups)
    lines[#lines + 1] = "|cFF999999(g describe contexto fisico; no identidad, MATCH ni flechas)|r"
    return lines
end

return PhysicalGroupMetadata
