-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · SolverAlgorithm v1.0
--
-- FUNCIÓN PURA. No lee estado global, no escribe SavedVariables, no toca la UI.
-- Entra una lista de pulls candidatos y un delta; sale un conjunto de índices
-- a saltar. Que sea pura no es decoración: permite probarla con datos
-- inventados sin arrancar el juego, que es exactamente lo que no se ha podido
-- hacer con el resto del addon.
--
-- EL PROBLEMA
-- Vas con `delta` tropas de sobra respecto a lo que la ruta esperaba a estas
-- alturas (pulls extra, adds no planeados, un patrol que se pegó). Ese exceso
-- se puede "gastar" saltando paquetes futuros. Se quiere saltar los que más
-- tiempo ahorran, sin que la suma de sus tropas supere el delta — porque si te
-- pasas, no llegas al 100% y la llave se muere por conteo.
--
-- Es una mochila 0/1: capacidad = delta, peso = tropas del pull, valor = coste
-- de movimiento que te ahorras. Con 20-40 pulls y capacidad de unas cientos de
-- tropas, la programación dinámica exacta es barata. Por encima de ese tamaño
-- se degrada a voraz por densidad de valor, que para este problema queda
-- razonablemente cerca del óptimo y nunca se cuelga.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local Solver = {}
AR.Solver = Solver

-- Límites por encima de los cuales se usa voraz en vez de DP exacta.
local MAX_DP_ITEMS    = 32
local MAX_DP_CAPACITY = 600

local floor, sort = math.floor, table.sort

-- ─────────────────────────────────────────────────────────────────────────
-- Voraz: ordena por valor/peso y mete lo que quepa.
-- ─────────────────────────────────────────────────────────────────────────
local function solveGreedy(items, capacity)
    local ordered = {}
    for i = 1, #items do ordered[i] = items[i] end
    sort(ordered, function(a, b)
        local da = (a.cost or 1) / math.max(1, a.weight)
        local db = (b.cost or 1) / math.max(1, b.weight)
        if da == db then return a.weight < b.weight end
        return da > db
    end)

    local chosen, used, saved = {}, 0, 0
    for _, it in ipairs(ordered) do
        if used + it.weight <= capacity then
            chosen[#chosen + 1] = it.index
            used = used + it.weight
            saved = saved + (it.cost or 1)
        end
    end
    return chosen, used, saved, "greedy"
end

-- ─────────────────────────────────────────────────────────────────────────
-- DP exacta 0/1. Tabla `keep` para reconstruir la solución.
-- ─────────────────────────────────────────────────────────────────────────
local function solveDP(items, capacity)
    local n = #items
    local best = {}
    for c = 0, capacity do best[c] = 0 end
    local keep = {}

    for i = 1, n do
        local w, v = items[i].weight, (items[i].cost or 1)
        keep[i] = {}
        local ki = keep[i]
        -- Recorrido descendente: sin él cada objeto podría usarse varias veces.
        for c = capacity, w, -1 do
            local cand = best[c - w] + v
            if cand > best[c] then
                best[c] = cand
                ki[c] = true
            end
        end
    end

    -- Reconstrucción hacia atrás desde la mejor capacidad alcanzada.
    local bestC, bestV = 0, -1
    for c = 0, capacity do
        if best[c] > bestV then bestV, bestC = best[c], c end
    end

    local chosen, used, saved = {}, 0, 0
    local c = bestC
    for i = n, 1, -1 do
        if keep[i] and keep[i][c] then
            chosen[#chosen + 1] = items[i].index
            used = used + items[i].weight
            saved = saved + (items[i].cost or 1)
            c = c - items[i].weight
        end
    end
    -- Se devuelven en orden de ruta, no de reconstrucción.
    sort(chosen)
    return chosen, used, saved, "dp"
end

-- ─────────────────────────────────────────────────────────────────────────
-- API PÚBLICA
--
-- candidates : { {index=, count=, cost=}, ... }  pulls que aún quedan
-- delta      : tropas de sobra disponibles para gastar (>0)
-- opts       : { minKeep = nº mínimo de pulls que NO se pueden saltar,
--                protect = { [pullIndex]=true } pulls intocables (bosses,
--                          paquetes obligatorios de camino) }
--
-- Devuelve: skipIndices(array), usedCount, savedCost, method
-- ─────────────────────────────────────────────────────────────────────────
function Solver.Solve(candidates, delta, opts)
    opts = opts or {}
    delta = tonumber(delta) or 0
    if type(candidates) ~= "table" or #candidates == 0 or delta <= 0 then
        return {}, 0, 0, "noop"
    end

    -- El delta se trunca a entero: las tropas son discretas y una capacidad
    -- fraccionaria haría que la DP indexase con decimales.
    local capacity = floor(delta)
    if capacity <= 0 then return {}, 0, 0, "noop" end

    local items = {}
    for _, c in ipairs(candidates) do
        local w = floor(tonumber(c.count) or 0)
        local idx = c.index
        -- Un pull de peso 0 no aporta conteo: saltarlo es gratis y siempre
        -- cabe, pero tampoco consume delta. Se excluye del knapsack y se
        -- decide aparte para no ensuciar la DP con pesos nulos.
        if idx and w > 0 and not (opts.protect and opts.protect[idx]) then
            items[#items + 1] = { index = idx, weight = w, cost = tonumber(c.cost) or 1 }
        end
    end
    if #items == 0 then return {}, 0, 0, "noop" end

    -- Nunca vaciar la ruta entera: si se pudieran saltar todos los pulls
    -- restantes, el delta estaba mal calculado y el resultado sería una ruta
    -- sin nada que matar.
    local minKeep = tonumber(opts.minKeep) or 1
    if #items <= minKeep then return {}, 0, 0, "noop" end

    local chosen, used, saved, method
    if #items <= MAX_DP_ITEMS and capacity <= MAX_DP_CAPACITY then
        chosen, used, saved, method = solveDP(items, capacity)
    else
        chosen, used, saved, method = solveGreedy(items, capacity)
    end

    -- Respetar minKeep: si la solución deja menos pulls de los permitidos, se
    -- quitan los saltos de menor valor hasta cumplirlo.
    local maxSkips = #items - minKeep
    if #chosen > maxSkips then
        local byValue = {}
        for _, i in ipairs(chosen) do
            local w, v = 0, 1
            for _, it in ipairs(items) do
                if it.index == i then w, v = it.weight, it.cost; break end
            end
            byValue[#byValue + 1] = { index = i, weight = w, cost = v }
        end
        sort(byValue, function(a, b) return (a.cost or 1) > (b.cost or 1) end)
        local trimmed, u, s = {}, 0, 0
        for k = 1, maxSkips do
            local e = byValue[k]
            if e then
                trimmed[#trimmed + 1] = e.index
                u = u + e.weight
                s = s + (e.cost or 1)
            end
        end
        sort(trimmed)
        chosen, used, saved = trimmed, u, s
    end

    return chosen, used, saved, method
end

-- Convierte los índices de pull en la tabla hash que consumen los nameplates.
-- Se devuelve una tabla NUEVA en cada llamada: reutilizar y vaciar la anterior
-- dejaría a los nameplates leyendo una tabla a medio construir.
-- ═════════════════════════════════════════════════════════════════════════
-- BUG SOLVER-1 (v7.2.0) — marcar por npcID puede marcar packs que SI hay que
-- matar.
--
-- El mismo npcID aparece en varios pulls: las mazmorras repiten packs
-- identicos. Si el solver decide saltar el pull 7 y ese npcID tambien esta en
-- el pull 9 —que no se salta—, marcar el npcID pinta [SKIP] sobre mobs que el
-- grupo necesita. Eso es peor que no marcar nada: manda al grupo a dejarse
-- tropas que hacen falta para el 100%.
--
-- REGLA: solo se marca un npcID si NO pertenece a ningun pull restante que no
-- se vaya a saltar. Los ambiguos se cuentan y se reportan.
-- ═════════════════════════════════════════════════════════════════════════
function Solver.BuildSkipSet(skipIndices, dataIndex, fromPullIndex)
    local set, excluded = {}, 0
    if type(skipIndices) ~= "table" or type(dataIndex) ~= "table" then return set, 0 end

    local skipping = {}
    for _, i in ipairs(skipIndices) do skipping[i] = true end

    -- npcIDs que viven en pulls restantes que NO se saltan.
    local needed = {}
    local from = tonumber(fromPullIndex) or 1
    for i = from, (dataIndex.pullCount or 0) do
        if not skipping[i] then
            local p = dataIndex.pulls and dataIndex.pulls[i]
            if p and type(p.npcs) == "table" then
                for _, npcID in ipairs(p.npcs) do needed[npcID] = true end
            end
        end
    end

    for _, pullIndex in ipairs(skipIndices) do
        local pull = dataIndex.pulls and dataIndex.pulls[pullIndex]
        if pull and type(pull.npcs) == "table" then
            for _, npcID in ipairs(pull.npcs) do
                if needed[npcID] then
                    excluded = excluded + 1
                else
                    set[npcID] = true
                end
            end
        end
    end
    return set, excluded
end

return Solver
