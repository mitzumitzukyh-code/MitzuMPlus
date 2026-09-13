-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · DataStructure v1.0
--
-- Índice en memoria de la ruta activa. Se construye UNA vez al arrancar la
-- llave y a partir de ahí toda consulta es O(1).
--
-- Esto existe porque el requisito duro del EventTracker es no recorrer nada en
-- el frame de combate: cuando muere un mob hay que saber a qué pull pertenece
-- con un único acceso a tabla. Recorrer los pulls buscando el npcID sería
-- O(pulls * mobs) por cada muerte, con 200+ muertes por llave y varias por
-- segundo en un pull grande.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local DataStructure = {}
AR.DataStructure = DataStructure

-- Índice activo. Campos:
--   npcToPull   [npcID]     = pullIndex        (el primero que lo contiene)
--   npcCount    [npcID]     = tropas por unidad
--   pulls       [i]         = { index, count, npcs = {npcID,...}, cost }
--   cumulative  [i]         = tropas acumuladas al TERMINAR el pull i
--   totalForces             = tropas totales de la mazmorra
--   killed      [npcID]     = nº de muertes vistas esta llave
DataStructure._index = nil

function DataStructure:Get()
    return self._index
end

function DataStructure:IsReady()
    return self._index ~= nil and self._index.pullCount > 0
end

function DataStructure:Reset()
    self._index = nil
end

-- Coste de movimiento de un pull. Si el perfil trae coordenadas de MDT se usa
-- la distancia real al pull anterior y siguiente; si no, un coste plano.
--
-- El coste representa "lo que ahorras si NO vas a por él". Un pull que está en
-- el camino cuesta poco saltarlo (no ahorras nada); uno que obliga a un desvío
-- ahorra mucho. Sin coordenadas no se puede distinguir, y el solver lo trata
-- todo igual: es peor, pero no inventa una geometría que no tiene.
local function movementCost(planned)
    if type(planned) ~= "table" then return 1 end
    local c = tonumber(planned.cost or planned.detour or planned.distance)
    if c and c > 0 then return c end
    return 1
end

-- ═════════════════════════════════════════════════════════════════════════
-- LOS CLONES DE UN PACK: SE LEE EL VALOR, NO LA CLAVE
--
-- BUG CLONE-1 (v7.10.1). MDT guarda los clones de un pack como una LISTA de
-- indices, no como un mapa marcado:
--     pull[enemyIdx] = { 3, 7, 12 }         <- lo que hay de verdad
--     pull[enemyIdx] = { [3]=true, [7]=true } <- lo que creiamos que habia
--
-- Leido en su codigo, no supuesto:
--   MythicDungeonTools/Modules/Pulls.lua:29
--       for k, v in pairs(clones) do ... enemy.clones[v] ...
--   MythicDungeonTools/Modules/DungeonEnemies.lua:1039  (IsCloneInPulls)
--       for _, pullCloneIndex in pairs(pull[enemyIdx]) do
--           if pullCloneIndex == cloneIdx then return true end
-- En los dos, el cloneIdx es el VALOR.
--
-- Nosotros leiamos la CLAVE, que es la posicion dentro de la lista. Asi todo
-- pack salia con los clones 1..n. Se veia a simple vista en /emp pullinfo
-- —todos los grupos empezando en 1 y consecutivos— y en los "40 clones
-- repetidos" de una ruta de 11 pulls: si el enemigo 10 siempre da {1,2},
-- cualquier otro pack que lo use choca con el.
--
-- El CONTEO no estaba afectado: la lista tiene el mismo numero de elementos se
-- lea como se lea. O sea que el reparto de tropas y el solver nunca mintieron.
-- Lo unico que estaba mal era la identidad, que es justo para lo que sirve.
--
-- Se aceptan los dos formatos: valor numerico -> ese es el cloneIdx (MDT
-- actual); valor `true` -> el cloneIdx es la clave (presets antiguos).
-- ═════════════════════════════════════════════════════════════════════════
function DataStructure.SelectedClones(clones)
    local sel = {}
    if type(clones) ~= "table" then return sel end
    local vistos = {}
    for k, v in pairs(clones) do
        local ci
        if type(v) == "number" then
            ci = v
        elseif v == true then
            ci = tonumber(k)
        end
        -- Sin el filtro de repetidos, una lista con el mismo indice dos veces
        -- inflaria el recuento de tropas del pack.
        if ci and not vistos[ci] then
            vistos[ci] = true
            sel[#sel + 1] = ci
        end
    end
    table.sort(sel)
    return sel
end

-- Construye el índice desde un perfil. `profile` es lo que devuelve el
-- MDTImporter (pulls numéricos + plannedPulls) enriquecido con npcs por pull.
function DataStructure:Build(profile)
    if type(profile) ~= "table" or type(profile.pulls) ~= "table" then
        return nil, "perfil sin pulls"
    end

    local idx = {
        npcToPull  = {},
        npcCount   = {},
        pulls      = {},
        cumulative = {},
        killed     = {},
        totalForces = tonumber(profile.totalForces) or 0,
        -- Procedencia del mismo perfil que se esta indexando. El resolver la
        -- necesita para no contrastar clones contra otra mazmorra/ruta activa.
        mdtDungeonIdx = tonumber(profile.mdtDungeonIdx),
        pullCount  = 0,
        hasNpcData = false,
        -- ─────────────────────────────────────────────────────────────────
        -- IDENTIDAD DE RUTA (v7.10.0)
        --
        -- routeClones[enemyIdx][cloneIdx] = pullIndex.
        --
        -- No sustituye a npcToPull: son dos preguntas distintas. npcToPull
        -- responde "un mob de este tipo, ¿de que pull cuenta?" y sirve para el
        -- delta. routeClones responde "esta copia concreta de la ruta, ¿a que
        -- pull pertenece?", que es lo unico que puede decidir una flecha.
        --
        -- Y sigue SIN resolver quien es esa copia en el mundo: eso es
        -- PullUnitResolver, y es otro problema.
        -- ─────────────────────────────────────────────────────────────────
        routeClones  = {},
        cloneCount   = 0,
        hasCloneData = false,
    }

    local planned = type(profile.plannedPulls) == "table" and profile.plannedPulls or {}
    local running = 0

    for i = 1, #profile.pulls do
        local pctOrCount = tonumber(profile.pulls[i]) or 0
        local p = planned[i] or {}

        -- El perfil puede traer el peso en porcentaje (MDT) o en tropas. Se
        -- normaliza a TROPAS porque el delta del solver se mide en tropas: el
        -- porcentaje cambia con el total de la mazmorra y mezclarlos daría
        -- restas sin sentido.
        local count = tonumber(p.count)
        if not count and idx.totalForces > 0 then
            count = (pctOrCount / 100) * idx.totalForces
        end
        count = count or pctOrCount

        local entry = {
            index = i,
            count = count,
            pct   = tonumber(p.pct) or pctOrCount,
            cost  = movementCost(p),
            npcs  = {},
            enemies = {},
        }

        -- enemies: identidad de ruta del pack, tal cual la importo MDT.
        if type(p.enemies) == "table" then
            for _, en in ipairs(p.enemies) do
                local ei = tonumber(type(en) == "table" and en.enemyIdx or nil)
                if ei then
                    local clones = {}
                    local cloneMetadata = {}
                    if type(en.clones) == "table" then
                        for _, c in ipairs(en.clones) do
                            local ci = tonumber(c)
                            if ci then
                                clones[#clones + 1] = ci
                                idx.routeClones[ei] = idx.routeClones[ei] or {}
                                -- Un clon no deberia estar en dos packs. Si la
                                -- ruta lo repite se cuenta el conflicto y gana
                                -- el primero, en vez de callarlo: un numero de
                                -- conflictos distinto de cero es la señal de
                                -- que la ruta esta mal editada.
                                if idx.routeClones[ei][ci] == nil then
                                    idx.routeClones[ei][ci] = i
                                    idx.cloneCount = idx.cloneCount + 1
                                else
                                    idx.cloneConflicts = (idx.cloneConflicts or 0) + 1
                                end

                                -- Geometria de MDT que la ruta traiga EMBEBIDA: se
                                -- conserva tal cual, como hace RouteSchema, para no
                                -- perder datos del perfil. La foto externa por clon
                                -- (MDTPhysicalGroupData) y sus consultas ya no son
                                -- del core: solo las usa MitzuRouteArrows.
                                local embedded = type(en.cloneMetadata) == "table"
                                                 and en.cloneMetadata[ci] or nil
                                if type(embedded) == "table" then
                                    cloneMetadata[ci] = embedded
                                end
                            end
                        end
                    end
                    entry.enemies[#entry.enemies + 1] = {
                        enemyIdx   = ei,
                        npcID      = tonumber(en.npcID),
                        forceCount = tonumber(en.forceCount),
                        clones     = clones,
                        cloneMetadata = cloneMetadata,
                    }
                end
            end
        end

        -- npcs: lista de npcIDs de este pull, si el perfil los trae.
        if type(p.npcs) == "table" then
            for _, n in ipairs(p.npcs) do
                local npcID = tonumber(type(n) == "table" and n.id or n)
                if npcID then
                    entry.npcs[#entry.npcs + 1] = npcID
                    -- Primero gana: un mismo npcID puede repetirse en varios
                    -- pulls (packs idénticos). Asociarlo al primero mantiene el
                    -- avance monótono; asociarlo al último haría que matar el
                    -- primer pack marcase progreso del final de la ruta.
                    if idx.npcToPull[npcID] == nil then
                        idx.npcToPull[npcID] = i
                    end
                    if type(n) == "table" and tonumber(n.count) then
                        idx.npcCount[npcID] = tonumber(n.count)
                    end
                    idx.hasNpcData = true
                end
            end
        end

        running = running + (count or 0)
        idx.pulls[i] = entry
        idx.cumulative[i] = running
        idx.pullCount = i
    end

    idx.plannedTotal  = running
    idx.hasCloneData  = idx.cloneCount > 0

    -- ─────────────────────────────────────────────────────────────────────
    -- v7.9.2 — un perfil sirve para calcular o no sirve, y hay que saberlo.
    --
    -- Los perfiles importados antes de la 7.9.2 guardaban el peso de cada pack
    -- como 100/nºpacks, en PORCENTAJE, y sin totalForces. Al normalizar a
    -- tropas ese 5.88 se tomaba como 5.88 tropas: el acumulado de la ruta
    -- entera sumaba ~100 y cualquier recuento real lo superaba. En vivo se vio
    -- asi: "pack~17 de 17, tropas 196/729, plan restante 0".
    --
    -- No es recuperable: el dato que falta (que mobs hay en cada pack) nunca
    -- estuvo en el perfil. Se marca y se pide reimportar en vez de seguir
    -- calculando sobre pesos inventados.
    -- ─────────────────────────────────────────────────────────────────────
    idx.exact = (idx.hasNpcData == true) and (idx.totalForces > 0)
                and (profile.forcePrecision == "npc-exact")

    -- ═════════════════════════════════════════════════════════════════════
    -- MAPA APRENDIDO (v7.2.0)
    --
    -- Si MDT no dio npcIDs —que es lo normal, porque dungeonEnemies es
    -- privado— se usa lo aprendido en vueltas anteriores. Solo rellena huecos:
    -- un npcID que ya venia de MDT nunca se pisa, porque ese dato es exacto y
    -- el aprendido es una inferencia.
    -- ═════════════════════════════════════════════════════════════════════
    if not idx.hasNpcData and AR.BuildLearnedMap then
        local learned, ambiguous, runs = AR.BuildLearnedMap(profile)
        local added = 0
        for npcID, pullIdx in pairs(learned) do
            if idx.npcToPull[npcID] == nil and idx.pulls[pullIdx] then
                idx.npcToPull[npcID] = pullIdx
                local e = idx.pulls[pullIdx]
                e.npcs[#e.npcs + 1] = npcID
                added = added + 1
            end
        end
        idx.learnedRuns      = runs
        idx.learnedAmbiguous = ambiguous
        idx.learnedCount     = added
        if added > 0 then idx.hasNpcData = true; idx.npcSource = "aprendido" end
    elseif idx.hasNpcData then
        idx.npcSource = "MDT"
    end

    self._index = idx
    return idx
end

-- ─────────────────────────────────────────────────────────────────────────
-- CONSULTAS O(1)
-- ─────────────────────────────────────────────────────────────────────────

function DataStructure:PullOf(npcID)
    local idx = self._index
    if not idx then return nil end
    return idx.npcToPull[npcID]
end

-- Identidad de RUTA, no del mundo: "el clon 4 del enemigo 7, ¿de que pull es?"
function DataStructure:PullOfClone(enemyIdx, cloneIdx)
    local idx = self._index
    if not idx then return nil end
    local byEnemy = idx.routeClones[tonumber(enemyIdx) or -1]
    return byEnemy and byEnemy[tonumber(cloneIdx) or -1] or nil
end

-- Los enemigos (enemyIdx + npcID + clones) de un pull, para quien tenga que
-- recorrerlos. Devuelve la tabla viva del indice: no escribir en ella.
function DataStructure:EnemiesOf(pullIndex)
    local idx = self._index
    if not idx then return nil end
    local p = idx.pulls[tonumber(pullIndex) or -1]
    return p and p.enemies or nil
end

function DataStructure:CountOf(npcID)
    local idx = self._index
    if not idx then return nil end
    return idx.npcCount[npcID]
end

-- Tropas que la ruta esperaba tener acumuladas al terminar `pullIndex`.
function DataStructure:ExpectedAt(pullIndex)
    local idx = self._index
    if not idx or not pullIndex then return nil end
    return idx.cumulative[math.max(1, math.min(pullIndex, idx.pullCount))]
end

-- Pulls que quedan a partir de `fromIndex` (incluido), en el formato que come
-- el solver: { {index=, count=, cost=}, ... }
function DataStructure:RemainingPulls(fromIndex, excludeSet)
    local idx = self._index
    if not idx then return {} end
    fromIndex = math.max(1, tonumber(fromIndex) or 1)
    local out = {}
    for i = fromIndex, idx.pullCount do
        if not (excludeSet and excludeSet[i]) then
            local p = idx.pulls[i]
            out[#out + 1] = { index = i, count = p.count or 0, cost = p.cost or 1 }
        end
    end
    return out
end

function DataStructure:RegisterKill(npcID)
    local idx = self._index
    if not idx then return end
    idx.killed[npcID] = (idx.killed[npcID] or 0) + 1
end

-- ─────────────────────────────────────────────────────────────────────────
-- ENRIQUECIMIENTO DESDE MDT
--
-- El MDTImporter existente extrae porcentajes por pull pero no los npcIDs, que
-- son justo lo que necesita el nameplate y el combat log. Esto los saca de la
-- misma fuente (MDT.dungeonEnemies) sin tocar el importador.
-- ─────────────────────────────────────────────────────────────────────────

function DataStructure:EnrichFromMDT(profile, preset)
    local MDT = rawget(_G, "MDT")
    if type(MDT) ~= "table" or type(profile) ~= "table" then return false, "MDT no cargado" end

    local value = preset
    if type(value) == "table" and type(value.value) == "table" then value = value.value end
    if type(value) ~= "table" or type(value.pulls) ~= "table" then return false, "preset sin pulls" end

    local dungeonIdx = tonumber(value.currentDungeonIdx or profile.mdtDungeonIdx)
    local enemies = dungeonIdx and type(MDT.dungeonEnemies) == "table" and MDT.dungeonEnemies[dungeonIdx] or nil
    if type(enemies) ~= "table" then return false, "sin dungeonEnemies" end

    local totals = type(MDT.dungeonTotalCount) == "table" and MDT.dungeonTotalCount[dungeonIdx] or nil
    profile.totalForces = totals and tonumber(totals.normal) or profile.totalForces

    profile.plannedPulls = profile.plannedPulls or {}
    -- v7.10.0 — misma correccion que en Bootstrap:_ProfileFromPreset: los
    -- cloneIdx concretos se conservan en pp.enemies. Este camino solo entra si
    -- MDT.dungeonEnemies llega a ser accesible algun dia; se deja coherente
    -- con el otro para que no vuelva a divergir.
    for i, pull in ipairs(value.pulls) do
        local pp = profile.plannedPulls[i] or {}
        pp.npcs = {}
        pp.enemies = {}
        local count = 0
        for enemyIdx, clones in pairs(pull) do
            local ei = tonumber(enemyIdx)
            local enemy = enemies[ei or enemyIdx]
            local sel = ei and DataStructure.SelectedClones(clones) or {}
            local n = #sel
            if ei and n > 0 then
                local id = type(enemy) == "table" and tonumber(enemy.id) or nil
                pp.enemies[#pp.enemies + 1] = {
                    enemyIdx   = ei,
                    npcID      = id,
                    forceCount = type(enemy) == "table" and tonumber(enemy.count) or nil,
                    clones     = sel,
                }
                if id then
                    pp.npcs[#pp.npcs + 1] = { id = id, count = tonumber(enemy.count) or 0, n = n }
                    count = count + (tonumber(enemy.count) or 0) * n
                end
            end
        end
        table.sort(pp.enemies, function(a, b) return a.enemyIdx < b.enemyIdx end)
        pp.count = count
        profile.plannedPulls[i] = pp
    end
    return true
end

return DataStructure
