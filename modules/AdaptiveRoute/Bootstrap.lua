-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · Bootstrap v1.0
--
-- Cablea los cinco módulos con el ciclo de vida de la llave. Vive aparte para
-- que los otros cinco sigan siendo piezas sin dependencias entre sí: el solver
-- no sabe qué es una llave, el ProfileManager no sabe qué es un nameplate.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local AR = MitzuMPlus.AdaptiveRoute
if not AR then return end

-- ═════════════════════════════════════════════════════════════════════════
-- TEXTO PARA JUGADORES vs TEXTO PARA DEPURAR
--
-- Este parte sale SOLO al entrar a la mazmorra, sin que nadie lo pida. Todo lo
-- que hay dentro tiene que ser legible para alguien que solo quiere jugar la
-- llave. Los indices internos, las vias de integracion y los volcados de API
-- se enseñan unicamente con modo debug activado (/emp debugmode).
-- ═════════════════════════════════════════════════════════════════════════
local function learnMode()
    local st = MitzuMPlus.db and MitzuMPlus.db.profile and MitzuMPlus.db.profile.settings
    return st and tostring(st.uiLevel or "PRO"):upper() == "LEARN"
end

local function dbg()
    local st = MitzuMPlus.db and MitzuMPlus.db.profile and MitzuMPlus.db.profile.settings
    return st and st.debugMode == true
end

-- ─────────────────────────────────────────────────────────────────────────
-- ARRANQUE DE LLAVE
-- ─────────────────────────────────────────────────────────────────────────

function AR:StartForRun(run)
    local PM, DS, ET = self.ProfileManager, self.DataStructure, self.EventTracker
    if not (PM and DS and ET) then return false, "módulos incompletos" end
    if not PM._ready then return false, "DB aún no cargada" end

    local st = PM:Settings()
    if st and st.enabled == false then return false, "desactivado en ajustes" end

    -- 1) Perfil guardado para esta mazmorra + nivel + afijos.
    local profile, key, how = PM:LoadNearest()

    -- 2) Si no hay, se intenta la ruta que el RouteAdvisor ya tenga vinculada
    --    (import MDT del addon). Reimportar cada semana era justo lo que se
    --    quería evitar, así que la primera vez que aparezca una ruta se guarda
    --    como perfil y a partir de ahí sale sola.
    if not profile and self.RouteAdvisorBridge then
        profile = self.RouteAdvisorBridge()
        if profile then
            key = PM:BuildProfileKey()
            how = "importada de MDT"
            if key then PM:Save(key, profile) end
        end
    end

    if not profile then
        self._lastStatus    = "sin ruta para esta llave"
        self._lastStatusKey = key
        return false, self._lastStatus
    end

    -- El navegador es estado de la llave, no del perfil: cada arranque empieza
    -- en el pull 1. Si no se reiniciara, entrar a una mazmorra de 11 pulls
    -- despues de otra de 21 dejaria el HUD diciendo "PULL 18 / 11".
    if self.PullNavigator then self.PullNavigator:Reset() end
    if self.PullUnitResolver then self.PullUnitResolver:Clear() end

    local ok, err = ET:Start(profile)
    -- La clave autoritativa es esta, la del arranque. profile.challengeMapID
    -- solo existe en los perfiles importados de MDT; los que vienen del puente
    -- del RouteAdvisor no lo traen y el tracker se quedaba sin saber de donde era.
    --
    -- (v7.9.1) Esta linea estaba metida DENTRO del bloque de "no hay perfil",
    -- donde 'ok' aun no existia como local: leia un global nil, la condicion
    -- era siempre falsa y _startedKey no se actualizaba jamas. De ahi que el
    -- informe siguiera diciendo "ruta 249 activa" estando en la 586.
    if ok and ET then ET._startedKey = key and tostring(key) or ET._startedKey end
    self._lastStatus = ok and string.format("ruta %s activa (%s)", tostring(key), tostring(how))
                          or tostring(err)
    -- Se apunta la clave a la que pertenece el estado. Sin esto, el informe
    -- repetia el ultimo arranque como si fuera el actual: en Reposo de los
    -- Reyes decia "ruta 250 activa (exacto)" a la vez que "sin ruta indexada".
    self._lastStatusKey = key
    if ok and MitzuMPlus.Print then
        local idx = DS:Get()
        MitzuMPlus:Print(string.format(
            "|cFF21de66Ruta adaptativa:|r %d pulls · perfil %s (%s)%s",
            idx and idx.pullCount or 0, tostring(key), tostring(how),
            (idx and not idx.hasCloneData) and " |cFFff9922· sin identidad de clones: reimporta la ruta|r" or ""))
    end
    return ok, err
end

function AR:StopForRun(save)
    local PM, ET, DS = self.ProfileManager, self.EventTracker, self.DataStructure
    if ET then ET:Stop() end
    -- Sin esto quedarian flechas y anotaciones de la llave anterior colgando
    -- al salir de la mazmorra. PLAYER_ENTERING_WORLD tambien las limpia, pero
    -- depender de eso seria dejar la limpieza al azar del orden de eventos.
    if self.PullUnitResolver then self.PullUnitResolver:Clear() end
    if self.RouteArrows then self.RouteArrows:ClearAll() end
    if self.PullNavigator then self.PullNavigator:Reset() end
    if save and PM then
        local st = PM:Settings()
        if not st or st.autoSaveOnFinish ~= false then
            local profile, key = PM:GetActive()
            if profile and key then PM:Save(key, profile) end
        end
    end
    if DS then DS:Reset() end
end

-- Puente con el RouteAdvisor/MDTImporter que ya existen en el addon: convierte
-- su ruta al formato de perfil y le añade los npcIDs si MDT está cargado.
function AR.RouteAdvisorBridge()
    local RA = MitzuMPlus.RouteAdvisor
    local route = RA and RA.GetImportedRoute and RA:GetImportedRoute() or nil
    if type(route) ~= "table" or type(route.pulls) ~= "table" or #route.pulls == 0 then
        return nil
    end
    local profile = {
        name         = route.name or "Ruta MDT",
        pulls        = route.pulls,
        plannedPulls = route.plannedPulls,
        totalForces  = route.totalForces,
        mdtDungeonIdx = route.mdtDungeonIdx,
        source       = route.source or "RouteAdvisor",
    }
    -- Los npcIDs no los extrae el importador existente; se sacan de MDT sin
    -- tocarlo. Si MDT no está cargado el perfil sigue sirviendo para el delta,
    -- solo que sin marcas en los nameplates.
    if AR.DataStructure and AR.DataStructure.EnrichFromMDT then
        pcall(function()
            AR.DataStructure:EnrichFromMDT(profile, route.mdtPreset)
        end)
    end
    return profile
end

-- ═════════════════════════════════════════════════════════════════════════
-- IMPORTAR LA RUTA QUE YA TIENES ABIERTA EN MDT
--
-- El camino clasico es exportar una cadena en MDT y pegarla aqui. Si MDT esta
-- cargado eso sobra: la ruta ya esta en memoria, con sus pulls Y sus npcIDs,
-- que es justo lo que hace falta para las marcas [SKIP]. Exportar e importar
-- solo anade dos pasos donde se puede perder la seleccion de dungeon.
--
-- Se lee el preset ACTIVO tal cual lo tengas en pantalla.
-- ═════════════════════════════════════════════════════════════════════════
-- ═════════════════════════════════════════════════════════════════════════
-- BUG MDT-1 (v6.8.3) — el global no siempre se llama "MDT".
--
-- Medido: con MDT v6.2.15 ABIERTO en pantalla, rawget(_G,"MDT") devolvia nil
-- y el addon respondia "MDT no esta cargado". El objeto existe; el nombre no
-- es el que se daba por hecho. (El MDTImporter que ya traia el addon hace la
-- misma suposicion, asi que probablemente lleva tiempo fallando en silencio y
-- cayendo al reparto "structure-auto-learn" en vez de usar % exactos.)
--
-- Se busca por CAPACIDADES, no por nombre: cualquier tabla que exponga
-- dungeonEnemies o GetCurrentPreset es MDT, se llame como se llame. Es la
-- misma disciplina que resolvio lo de unitToken y lo de los secret values.
-- ═════════════════════════════════════════════════════════════════════════
local MDT_MARKERS = { "dungeonEnemies", "GetCurrentPreset", "dungeonTotalCount", "dungeonList" }

local function looksLikeMDT(t)
    if type(t) ~= "table" then return false end
    local hits = 0
    for _, m in ipairs(MDT_MARKERS) do
        local ok, v = pcall(function() return t[m] end)
        if ok and v ~= nil then hits = hits + 1 end
    end
    return hits >= 2, hits
end

-- ═════════════════════════════════════════════════════════════════════════
-- BUG MDT-2 (v6.9.0) — MDT NO expone ningun global con sus datos.
--
-- Leido en su codigo (MDT 6.2.15):
--   MythicDungeonTools.lua:2   local _, MDT = ...
-- Es la tabla privada del addon. Nunca se publica en _G, asi que
-- rawget(_G,"MDT") jamas iba a funcionar — ni ahora ni antes. Tampoco es
-- LoadOnDemand: mi teoria anterior era falsa.
--
-- Lo que SI hay es una API oficial pensada para esto:
--   BuildCheck.lua:3     _G.MythicDungeonToolsAPI = API
--   BuildCheck.lua:48    function MDT:ExportAPI(methodName)  -- reenvia a MDT
-- Metodos exportados relevantes:
--   API:GetDB()               -> db con presets, currentDungeonIdx, currentPreset
--   API:GetEnemyForces(npcId) -> count, maxCountNormal
--   API:GetDungeonName(idx)
--
-- Y la ruta activa sale de:
--   Modules/Presets.lua:99
--     db.presets[db.currentDungeonIdx][db.currentPreset[db.currentDungeonIdx]]
--
-- NOTA IMPORTANTE: el MDTImporter que ya traia este addon tambien busca
-- rawget(_G,"MDT"), asi que lleva fallando desde siempre y cayendo al reparto
-- uniforme "structure-auto-learn" en vez de usar porcentajes exactos. Eso
-- explica parte del sesgo optimista que vimos en la calibracion.
-- ═════════════════════════════════════════════════════════════════════════
function AR.GetMDTAPI()
    local API = rawget(_G, "MythicDungeonToolsAPI")
    if type(API) ~= "table" then return nil, "MythicDungeonToolsAPI no existe (MDT no cargado)" end
    if type(API.GetDB) ~= "function" then return nil, "MythicDungeonToolsAPI sin GetDB" end
    return API
end

-- Devuelve preset, dungeonIdx, db  a partir de la API oficial.
function AR.GetMDTCurrentPreset()
    local API, why = AR.GetMDTAPI()
    if not API then return nil, nil, nil, why end

    local ok, db = pcall(API.GetDB, API)
    if not ok or type(db) ~= "table" then return nil, nil, nil, "GetDB no devolvio la DB" end

    local idx = db.currentDungeonIdx
    if not idx then return nil, nil, db, "MDT no tiene mazmorra seleccionada" end

    local presets = db.presets and db.presets[idx]
    local sel = db.currentPreset and db.currentPreset[idx]
    local preset = presets and sel and presets[sel]
    if type(preset) ~= "table" then
        return nil, idx, db, "no hay preset activo para esa mazmorra"
    end
    return preset, idx, db
end

-- Compatibilidad: algunos sitios del modulo esperaban una tabla tipo MDT.
-- Ya no existe tal cosa, asi que devuelve nil y el motivo.
function AR.FindMDT()
    return nil, "MDT no expone tabla global; se usa MythicDungeonToolsAPI"
end

function AR.EnsureMDT()
    return AR.FindMDT()
end

-- Diagnostico de la conexion con MDT, ya sobre la API real.
function AR:ProbeMDT()
    local out = {}
    local function add(s) out[#out + 1] = s end
    add("|cFFd9b33e── Sondeo de MDT ──|r")

    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local ok, l = pcall(C_AddOns.IsAddOnLoaded, "MythicDungeonTools")
        add("MythicDungeonTools cargado: " .. tostring(ok and l))
    end
    add("_G.MDT (privado, NO deberia existir): " .. type(rawget(_G, "MDT")))

    local API, why = AR.GetMDTAPI()
    if not API then
        add("|cFFff5555" .. tostring(why) .. "|r")
        return out
    end
    add("|cFF21de66MythicDungeonToolsAPI encontrada.|r")

    local methods = {}
    for _, m in ipairs({ "GetDB", "GetEnemyForces", "GetDungeonName", "ShowInterface" }) do
        methods[#methods + 1] = m .. "=" .. type(API[m])
    end
    add("  " .. table.concat(methods, " "))

    local preset, idx, db, err = AR.GetMDTCurrentPreset()
    if not preset then
        add("|cFFff9922Preset activo:|r " .. tostring(err))
        if db then
            add(string.format("  currentDungeonIdx=%s  presets=%s",
                tostring(db.currentDungeonIdx), type(db.presets)))
        end
        return out
    end
    local value = preset.value or preset
    add(string.format("|cFF21de66Preset activo:|r '%s' · mazmorra idx %s · pulls %d",
        tostring(preset.text), tostring(idx),
        type(value.pulls) == "table" and #value.pulls or 0))

    -- GetEnemyForces con el objetivo actual, si hay: es la via para saber
    -- cuantas tropas vale cada mob sin acceder a las tablas privadas.
    if UnitExists and UnitExists("target") and type(API.GetEnemyForces) == "function" then
        local guid = UnitGUID("target")
        local npcID = guid and select(6, strsplit("-", guid))
        npcID = tonumber(npcID)
        if npcID then
            local ok, count, total = pcall(API.GetEnemyForces, API, npcID)
            add(string.format("GetEnemyForces(objetivo %d): %s de %s",
                npcID, tostring(ok and count), tostring(ok and total)))
        end
    else
        add("Selecciona un mob y repite para probar GetEnemyForces.")
    end
    return out
end

-- ═════════════════════════════════════════════════════════════════════════
-- MAPA  indice de MDT  <->  ID de mazmorra de Blizzard
--
-- MDT numera sus mazmorras con un indice propio (Altar de Colmillos = 164) que
-- no tiene nada que ver con el challengeMapID que devuelve
-- C_ChallengeMode.GetActiveChallengeMapID(). Sin puente entre los dos, una
-- ruta importada se archiva bajo un ID que al entrar no existe: es justo el
-- bug del perfil "250_12_..." guardado para Altar de Colmillos.
--
-- MDT.mapInfo (que tiene el mapID) es privado, asi que el puente se construye
-- por NOMBRE, con APIs publicas de los dos lados:
--   MythicDungeonToolsAPI:GetDungeonName(idx)   -> nombre segun MDT
--   C_ChallengeMode.GetMapUIInfo(mapID)         -> nombre segun Blizzard
-- Se normaliza (minusculas, sin acentos ni signos) porque el cliente esta en
-- esMX y las dos fuentes puntuan distinto.
-- ═════════════════════════════════════════════════════════════════════════
local ACCENTS = {
    ["á"]="a",["é"]="e",["í"]="i",["ó"]="o",["ú"]="u",["ü"]="u",["ñ"]="n",
    ["Á"]="a",["É"]="e",["Í"]="i",["Ó"]="o",["Ú"]="u",["Ü"]="u",["Ñ"]="n",
}
local function normalizeName(name)
    if type(name) ~= "string" then return nil end
    local out = name:lower()
    for k, v in pairs(ACCENTS) do out = out:gsub(k, v) end
    out = out:gsub("[^%w]", "")
    return (out ~= "" and out) or nil
end

function AR:BuildDungeonMap(force)
    if self._dungeonMap and not force then return self._dungeonMap end

    local API = self.GetMDTAPI and self.GetMDTAPI() or nil
    if not API or type(API.GetDungeonName) ~= "function" then
        return nil, "MDT no disponible"
    end
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapUIInfo) then
        return nil, "C_ChallengeMode sin GetMapTable/GetMapUIInfo"
    end

    -- Lado Blizzard: nombre normalizado -> challengeMapID
    local byName = {}
    local okT, maps = pcall(C_ChallengeMode.GetMapTable)
    if not okT or type(maps) ~= "table" then return nil, "GetMapTable fallo" end
    for _, mapID in ipairs(maps) do
        local okI, name = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
        local n = okI and normalizeName(name)
        if n then byName[n] = mapID end
    end

    -- Lado MDT: se recorren indices hasta agotar nombres. MDT no publica
    -- cuantas mazmorras tiene, asi que se para tras varios huecos seguidos.
    local map, rev, misses = {}, {}, 0
    for idx = 1, 500 do
        local okN, name = pcall(API.GetDungeonName, API, idx)
        local n = okN and normalizeName(name)
        if n then
            misses = 0
            local mapID = byName[n]
            if mapID then
                map[idx] = mapID
                rev[mapID] = idx
            end
        else
            misses = misses + 1
            if misses >= 40 then break end
        end
    end

    self._dungeonMap = { mdtToMap = map, mapToMdt = rev, built = (time and time()) or 0 }
    return self._dungeonMap
end

function AR:MDTIndexForMap(mapID)
    local m = self:BuildDungeonMap()
    return m and m.mapToMdt[mapID] or nil
end

-- ═════════════════════════════════════════════════════════════════════════
-- IMPORTAR TODAS LAS RUTAS DE MDT DE UNA VEZ
--
-- Cada preset se archiva bajo SU mazmorra, no bajo la llave que lleves encima.
-- ═════════════════════════════════════════════════════════════════════════
function AR:ImportAllFromMDT()
    -- MDT solo hace falta AQUI: importar. Si no esta, se dice claro y no pasa
    -- nada mas — el Route Engine nativo sigue funcionando sin el.
    if not (self.GetMDTAPI and self.GetMDTAPI()) then
        return false, "MDT no esta instalado; esta funcion de importacion no esta disponible. " ..
                      "El motor de ruta nativo no lo necesita."
    end
    local API, why = self.GetMDTAPI and self.GetMDTAPI() or nil
    if not API then return false, tostring(why or "MDT no disponible") end
    local okDB, db = pcall(API.GetDB, API)
    if not okDB or type(db) ~= "table" or type(db.presets) ~= "table" then
        return false, "MDT no devolvio presets"
    end

    local dmap = self:BuildDungeonMap(true)
    if not dmap then return false, "no se pudo mapear los indices de MDT a mazmorras" end

    local PM = self.ProfileManager
    if not PM or not PM._ready then return false, "DB de perfiles no lista" end

    local imported, skipped, report = 0, 0, {}
    for idx, presets in pairs(db.presets) do
        local mapID = dmap.mdtToMap[idx]
        local sel = db.currentPreset and db.currentPreset[idx]
        local preset = (type(presets) == "table") and sel and presets[sel] or nil

        -- Si el preset seleccionado esta vacio se busca el primero con pulls:
        -- MDT crea siempre un preset "Default" vacio en el indice 1.
        if type(preset) ~= "table" or type((preset.value or {}).pulls) ~= "table"
           or #((preset.value or {}).pulls or {}) == 0 then
            preset = nil
            if type(presets) == "table" then
                for _, cand in ipairs(presets) do
                    local v = type(cand) == "table" and (cand.value or cand) or nil
                    if type(v) == "table" and type(v.pulls) == "table" and #v.pulls > 0 then
                        preset = cand; break
                    end
                end
            end
        end

        if mapID and preset then
            local profile, err = self:_ProfileFromPreset(preset, idx, API)
            if profile then
                profile.challengeMapID = mapID
                PM:Save(tostring(mapID), profile)
                imported = imported + 1
                report[#report + 1] = string.format("  %s · %d pulls",
                    tostring(profile.dungeonName or mapID), #profile.pulls)
            else
                skipped = skipped + 1
                report[#report + 1] = "  idx " .. idx .. ": " .. tostring(err)
            end
        elseif preset and not mapID then
            skipped = skipped + 1
            report[#report + 1] = "  idx " .. idx .. ": sin equivalencia de mazmorra"
        end
    end

    return true, { imported = imported, skipped = skipped, lines = report }
end

-- Convierte un preset de MDT en un perfil. Compartido por las dos rutas de
-- importacion para que no haya dos formatos distintos rondando.
-- ═════════════════════════════════════════════════════════════════════════
-- CONTRASTE DE data/MDTEnemyData.lua (v7.9.2)
--
-- Ese fichero es una FOTO de los datos de MDT, sacada de sus ficheros porque
-- no hay forma de leerlos en caliente. Si MDT se actualiza y cambia npcIDs o
-- valores, la foto miente y el addon marcaria packs equivocados.
--
-- Contrastar es barato: se cogen unos cuantos enemigos y se le pregunta a
-- MythicDungeonToolsAPI:GetEnemyForces(npcID), que devuelve las tropas de ese
-- npc y el total de la mazmorra. Si algo no cuadra, los datos se descartan
-- enteros. Mejor sin marcas de SKIP que con marcas mintiendo.
-- ═════════════════════════════════════════════════════════════════════════
function AR:VerifyEnemyData(dungeonIdx)
    local ED = MitzuMPlus.MDTEnemyData and MitzuMPlus.MDTEnemyData[dungeonIdx]
    if not (ED and ED.e) then return false, "sin datos de enemigos para esta mazmorra" end

    self._edCheck = self._edCheck or {}
    local c = self._edCheck[dungeonIdx]
    if c then return c.ok, c.why end

    local API = self.GetMDTAPI and self.GetMDTAPI() or nil
    if not API or type(API.GetEnemyForces) ~= "function" then
        -- Sin MDT cargado no hay contra que contrastar. Se usan igualmente:
        -- son los datos que MDT traia al generarlos, y negarse a usarlos por no
        -- poder confirmarlo dejaria el addon sin rutas con MDT descargado.
        return true, "sin contrastar (MDT no cargado)"
    end

    local checked, bad = 0, 0
    for _, e in pairs(ED.e) do
        if checked >= 8 then break end
        if e[2] and e[2] > 0 then
            local ok, cnt, maxNormal = pcall(API.GetEnemyForces, API, e[1])
            if ok and cnt then
                checked = checked + 1
                if cnt ~= e[2] then bad = bad + 1 end
                if maxNormal and ED.total and ED.total > 0 and maxNormal ~= ED.total then
                    bad = bad + 1
                end
            end
        end
    end

    local ok, why
    if checked == 0 then
        ok, why = true, "sin contrastar (MDT no respondio)"
    elseif bad > 0 then
        ok, why = false, string.format(
            "los datos de enemigos no cuadran con MDT (%d de %d fallos). "
            .. "Regenera data/MDTEnemyData.lua.", bad, checked)
    else
        ok, why = true, string.format("contrastados %d de %d", checked, checked)
    end
    self._edCheck[dungeonIdx] = { ok = ok, why = why }
    return ok, why
end

function AR:_ProfileFromPreset(preset, dungeonIdx, API)
    local value = preset.value or preset
    if type(value) ~= "table" or type(value.pulls) ~= "table" or #value.pulls == 0 then
        return nil, "preset sin pulls"
    end

    -- ─────────────────────────────────────────────────────────────────────
    -- v7.9.2 — packs con npcIDs y tropas de verdad.
    --
    -- Lo de antes repartia el 100% a partes iguales entre los packs
    -- (even = 100/#pulls) y dejaba npcs = {} vacio. O sea que el solver decidia
    -- que saltar con pesos inventados, y sin npcIDs no habia marcas de SKIP
    -- posibles. Eso es lo que se veia como "aun sin reconocer mobs".
    --
    -- Ahora los indices de enemigo del preset se resuelven contra los datos de
    -- MDT (data/MDTEnemyData.lua). Si no estan, se cae al reparto plano de
    -- antes pero MARCADO como estimado, para que el informe no presuma de una
    -- precision que no tiene.
    -- ─────────────────────────────────────────────────────────────────────
    local ED   = MitzuMPlus.MDTEnemyData and MitzuMPlus.MDTEnemyData[dungeonIdx]
    local emap = ED and ED.e
    if emap then
        local okData, whyData = self:VerifyEnemyData(dungeonIdx)
        if not okData then
            emap = nil          -- foto vieja: no se usa
            if MitzuMPlus.Print then
                MitzuMPlus:Print("|cFFff5555Ruta adaptativa:|r " .. tostring(whyData))
            end
        end
    end

    local pulls, planned = {}, {}
    local even = 100 / #value.pulls
    local totalForces = ED and ED.total or nil
    local resolved, unknown = 0, 0
    local outOfRange = 0
    local DS = self.DataStructure
    if not DS or not DS.SelectedClones then return nil, "DataStructure no cargado" end

    -- ─────────────────────────────────────────────────────────────────────
    -- v7.10.0 — se conservan enemyIdx y cloneIdx.
    --
    -- Lo de antes contaba los clones seleccionados y tiraba CUALES eran:
    -- quedaba { id = 261553, n = 3 }. Con eso es imposible decir que copia
    -- fisica del mob pertenece al pull, porque el mismo npcID vive en varios
    -- pulls a la vez. La identidad de MDT es enemyIdx + cloneIdx, y es la que
    -- ahora va en plannedPulls[i].enemies.
    --
    -- `npcs` se mantiene intacto: el solver, el delta y DataStructure.npcToPull
    -- siguen leyendolo. Esta migracion añade, no sustituye.
    --
    -- OJO: `enemies` se rellena AUNQUE no haya MDTEnemyData. El npcID depende
    -- de la foto de datos, pero enemyIdx y cloneIdx vienen del preset y se
    -- conocen siempre. Atarlos a emap habria repetido el error de antes.
    -- ─────────────────────────────────────────────────────────────────────
    for i, pull in ipairs(value.pulls) do
        local groups, npcs, count, enemies = 0, {}, 0, {}
        if type(pull) == "table" then
            for enemyIdx, clones in pairs(pull) do
                -- Los packs de MDT llevan tambien claves que no son enemigos
                -- ("color", "sublevel"...). Se saltan sin contarlas como
                -- indices sin resolver, que si no el aviso saldria siempre.
                local ei = tonumber(enemyIdx)
                local e = ei and emap and emap[ei] or nil
                if ei then groups = groups + 1 end

                -- Que clones concretos marca la ruta para este enemigo.
                -- Lo lee DataStructure.SelectedClones y solo ella: leer esto a
                -- mano fue el BUG CLONE-1 (se tomaba la clave en vez del valor).
                local sel = ei and DS.SelectedClones(clones) or {}
                local n = #sel

                -- Chivato barato: MDTEnemyData sabe cuantos clones tiene cada
                -- enemigo (el tercer campo). Un cloneIdx por encima de ese
                -- numero es imposible, y es exactamente lo que producia el bug
                -- de leer la clave. Si vuelve a pasar, se ve en /emp ruta en
                -- vez de tardar dias en salir a la luz.
                if e and tonumber(e[3]) then
                    for _, ci in ipairs(sel) do
                        if ci > e[3] then outOfRange = outOfRange + 1 end
                    end
                end

                if ei and n > 0 then
                    enemies[#enemies + 1] = {
                        enemyIdx   = ei,
                        npcID      = e and e[1] or nil,
                        forceCount = e and e[2] or nil,
                        clones     = sel,
                    }
                end

                if e then
                    if n > 0 then
                        npcs[#npcs + 1] = { id = e[1], count = e[2], n = n }
                        count = count + (e[2] or 0) * n
                        resolved = resolved + 1
                    end
                elseif ei then
                    unknown = unknown + 1
                end
            end
        end
        -- Orden estable: pairs() no lo garantiza y un volcado que cambia de
        -- orden entre llamadas es imposible de comparar cuando algo falla.
        table.sort(enemies, function(a, b) return a.enemyIdx < b.enemyIdx end)
        planned[i] = { enemyGroups = groups, npcs = npcs, count = count,
                       enemies = enemies, estimated = (emap == nil) }
        -- El peso del pack en % del 100% necesario. Sin datos, reparto plano.
        pulls[i] = (emap and totalForces and totalForces > 0)
                   and (count / totalForces * 100) or even
    end

    local profile = {
        name           = tostring(preset.text or "Ruta MDT"),
        pulls          = pulls,
        plannedPulls   = planned,
        mdtDungeonIdx  = dungeonIdx,
        totalForces    = totalForces,
        source         = "MDT-API",
        forcePrecision = emap and "npc-exact" or "structure-only",
        npcResolved    = resolved,
        npcUnknown     = unknown,
        cloneOutOfRange = outOfRange,
    }
    if API and type(API.GetDungeonName) == "function" then
        local ok, n = pcall(API.GetDungeonName, API, dungeonIdx)
        if ok and n then profile.dungeonName = n end
    end
    return profile
end

function AR:ImportFromOpenMDT()
    -- MDT solo hace falta AQUI: importar. Si no esta, se dice claro y no pasa
    -- nada mas — el Route Engine nativo sigue funcionando sin el.
    if not (self.GetMDTAPI and self.GetMDTAPI()) then
        return false, "MDT no esta instalado; esta funcion de importacion no esta disponible. " ..
                      "El motor de ruta nativo no lo necesita."
    end
    local preset, dungeonIdx, db, why = AR.GetMDTCurrentPreset()
    if not preset then return false, tostring(why or "no se pudo leer la ruta de MDT") end

    local API = AR.GetMDTAPI()
    local profile, err = self:_ProfileFromPreset(preset, dungeonIdx, API)
    if not profile then return false, tostring(err) end

    -- BUG v7.1.0: antes se guardaba bajo la clave del CONTEXTO (la llave que
    -- llevas encima), no bajo la mazmorra de la ruta. Por eso una ruta de
    -- Altar de Colmillos acababa archivada como "250_12_...". La mazmorra sale
    -- del indice de MDT del propio preset.
    -- (v7.8.1) Esto era una linea ilegible que ademas no compilaba:
    -- `self:MDTIndexForMap and ...` es sintaxis de LLAMADA a metodo sin
    -- argumentos, no una comprobacion de existencia. Lua lo rechaza en tiempo
    -- de carga y el ARCHIVO ENTERO se cae, con el, todo AdaptiveRoute.
    -- Aqui va lo que de verdad hacia falta: el indice de MDT -> challengeMapID.
    local mapID
    do
        local dmap = self:BuildDungeonMap()
        mapID = dmap and dmap.mdtToMap and dmap.mdtToMap[dungeonIdx] or nil
    end

    if not mapID then
        return false, string.format(
            "no se pudo emparejar la mazmorra de MDT (indice %s) con ninguna mitica+. Prueba /emp rutastodas.",
            tostring(dungeonIdx))
    end
    profile.challengeMapID = mapID

    local PM = self.ProfileManager
    if not PM or not PM._ready then return false, "DB de perfiles no lista" end
    local key = tostring(mapID)
    if not PM:Save(key, profile) then return false, "no se pudo guardar el perfil" end

    local started = false
    if _G.MitzuMPlusCurrentRun and self.EventTracker then
        started = self.EventTracker:Start(profile) and true or false
    end

    local idx = self.DataStructure and self.DataStructure:Get()
    return true, {
        key = key, pulls = #profile.pulls, dungeon = profile.dungeonName,
        started = started, mapped = idx and idx.hasNpcData or false,
    }
end

-- ═════════════════════════════════════════════════════════════════════════
-- AVISO DE SINCRONIZACION
--
-- Un unico mensaje que responde a la pregunta que de verdad importa al entrar:
-- "¿los tres addons estan de acuerdo sobre ESTA mazmorra?". Se comprueba cada
-- pieza de verdad en vez de asumirla, y se dice cual falla.
-- Vale para cualquier nivel de llave: la ruta es por mazmorra.
-- ═════════════════════════════════════════════════════════════════════════
function AR:SyncReport(quiet)
    local PM, DS, ET = self.ProfileManager, self.DataStructure, self.EventTracker
    local lines, allOk = {}, true
    local function add(s) lines[#lines + 1] = s end
    local function mark(ok) return ok and "|cFF21de66OK|r" or "|cFFff5555FALTA|r" end

    local ctx = PM and PM:GetContext()
    local dungeonName
    if ctx and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local ok, n = pcall(C_ChallengeMode.GetMapUIInfo, ctx.dungeonID)
        if ok then dungeonName = n end
    end

    add(string.format("|cFFe8b84a═══ RUTA · %s%s ═══|r",
        tostring(dungeonName or (ctx and ctx.dungeonID) or "sin mazmorra"),
        (ctx and (ctx.keyLevel or 0) > 0) and (" +" .. ctx.keyLevel) or ""))

    if not ctx then
        add("|cFFff9922Sin mazmorra activa ni llave en la bolsa.|r")
        if not quiet then for _, l in ipairs(lines) do MitzuMPlus:Print(l) end end
        return false, lines
    end

    -- 1) MitzuMPlus (este addon)
    local trackerOk = (ET ~= nil) and (DS ~= nil)
    add(string.format("MitzuMPlus     %s%s", mark(trackerOk),
        (ET and ET._active) and " · siguiendo la ruta" or ""))
    allOk = allOk and trackerOk

    -- ═════════════════════════════════════════════════════════════════════
    -- 2) RUTA NATIVA — lo que de verdad decide si se puede jugar la ruta
    --
    -- Este bloque va ANTES que MDT a proposito. El Route Engine nativo carga
    -- desde MPlusAdaptiveRouteDB y data/MDTEnemyData.lua, los dos dentro del
    -- addon. Comprobado en vivo con MDT desactivado: 11 pulls, PREPARED.
    -- ═════════════════════════════════════════════════════════════════════
    local RM = MitzuMPlus.RouteManager
    local RP = MitzuMPlus.RouteProgress
    local nativa = RM and RM:GetActiveRoute() or nil
    if nativa then
        add(string.format("Ruta nativa      |cFF21de66OK|r · %s · %d pulls",
            tostring(nativa.name), #nativa.pulls))
        local v = RM:GetValidation()
        if v and v.clones and v.clones.unresolved > 0 then
            add(string.format("                 %d de %d clones sin resolver (la ruta sigue siendo utilizable)",
                v.clones.unresolved, v.clones.total))
        end
    else
        add("Ruta nativa      |cFFff9922sin cargar|r")
    end
    add(string.format("Route Engine     %s · %s",
        mark(RP ~= nil and RP:GetRoute() ~= nil),
        tostring(RP and RP:GetState() or "no cargado")))

    -- ═════════════════════════════════════════════════════════════════════
    -- 3) MDT — OPCIONAL, no requisito
    --
    -- Antes esta linea hacia `allOk = allOk and (API ~= nil)`: sin MDT el
    -- informe terminaba en "Faltan piezas" aunque la ruta, las tropas y la
    -- identidad estuvieran las tres OK. Era falso, y ademas desinformaba
    -- justo sobre lo que acabamos de conseguir.
    --
    -- MDT solo hace falta para IMPORTAR una ruta o para contrastar la foto de
    -- datos. Nada de eso es jugar. dataOrigin=MDT no es runtimeDependency=MDT.
    -- ═════════════════════════════════════════════════════════════════════
    local API = self.GetMDTAPI and self.GetMDTAPI() or nil
    local mdtIdx = API and self:MDTIndexForMap(ctx.dungeonID) or nil
    add(string.format("MDT              |cFF999999OPCIONAL|r · %s",
        API and ("disponible" .. ((mdtIdx and dbg()) and (" · indice " .. mdtIdx) or ""))
             or "no instalado (solo hace falta para importar rutas)"))

    -- 3) Flechas de ruta
    --
    -- Antes esta linea informaba de Threat Plates porque el sistema [SKIP]
    -- pintaba DENTRO de su frame y sin el no habia marcas. RouteArrows no
    -- depende de Threat Plates: usa el nameplate de Blizzard, que siempre
    -- esta. Asi que lo que importa aqui es si las flechas estan encendidas;
    -- Threat Plates pasa a ser un detalle de anclaje, no un requisito.
    local RA = self.RouteArrows
    local raOk = RA ~= nil and RA:IsEnabled()
    local tpName
    for _, n in ipairs({ "ThreatPlates", "TidyPlatesThreat", "TidyPlates_ThreatPlates" }) do
        if type(rawget(_G, n)) == "table" then tpName = n break end
    end
    add(string.format("Flechas de ruta %s%s", mark(raOk),
        RA and (raOk and (dbg() and (" · anclaje " .. tostring(RA:GetOption("arrowAnchor"))
                                     .. (tpName and (" · " .. tpName .. " detectado") or ""))
                                or "")
                     or " · desactivadas en ajustes")
             or " · modulo no cargado"))

    -- 3b) Los datos de enemigos (npcIDs y tropas por pack)
    --
    -- La foto vive en el addon; MDT solo sirve para CONTRASTARLA. Sin MDT no
    -- se puede contrastar, y eso no es un fallo: es que falta el arbitro.
    if mdtIdx then
        local okED, whyED = self:VerifyEnemyData(mdtIdx)
        add(string.format("Datos de mobs    %s · %s", mark(okED),
            okED and (MitzuMPlus.MDTEnemyDataVersion or "?") .. " · " .. tostring(whyED)
                  or tostring(whyED)))
        allOk = allOk and okED
    else
        add(string.format("Datos de mobs    |cFF21de66OK|r · %s · sin contrastar (MDT no esta)",
            MitzuMPlus.MDTEnemyDataVersion or "?"))
    end

    -- 4) La ruta de ESTA mazmorra
    local profile, key = PM:LoadNearest(ctx)
    if profile then
        local n = type(profile.pulls) == "table" and #profile.pulls or 0
        local npcs = false
        local idx = DS and DS:Get()
        if idx then npcs = idx.hasNpcData end
        add(string.format("Ruta           |cFF21de66OK|r · '%s' · %d pulls",
            tostring(profile.name or "?"), n))

        -- ─────────────────────────────────────────────────────────────────
        -- v7.9.3 — se cuentan los npcIDs QUE HAY, no los aprendidos.
        --
        -- Este contador leia learnedCount, que solo cuenta los npcIDs sacados
        -- a base de vueltas. Con los npcIDs viniendo de MDT ese numero es 0, y
        -- el parte se contradecia en la misma linea: "LISTAS · 0 mobs
        -- reconocidos". Lo que importa es cuantos conoce el indice.
        --
        -- Las ramas de "APRENDIENDO · falta otra vuelta" tambien se van: el
        -- aprendizaje necesitaba el combat log, que en Midnight esta cerrado
        -- (ver BUG CLEU-1). Prometer que aprendera solo era mentira.
        -- ─────────────────────────────────────────────────────────────────
        local known = 0
        if idx and type(idx.npcToPull) == "table" then
            for _ in pairs(idx.npcToPull) do known = known + 1 end
        end

        -- Dos datos distintos, y conviene no confundirlos:
        --   npcIDs  -> sirven para el delta de tropas del solver.
        --   clones  -> identidad de ruta (enemyIdx+cloneIdx), lo unico que
        --              puede decidir que copia lleva flecha.
        if npcs and known > 0 then
            add(string.format("Tropas por pack  |cFF21de66OK|r · %d mobs reconocidos (%s)",
                known, (idx and idx.npcSource) or "MDT"))
        else
            add("Tropas por pack  |cFFff9922SIN DATOS|r · la ruta guardada no trae npcIDs.")
            add("               Reimportala con |cFFf7d470/emp rutastodas|r con MDT abierto.")
        end

        if idx and idx.hasCloneData then
            add(string.format("Identidad de ruta |cFF21de66OK|r · %d clones repartidos en %d pulls%s",
                idx.cloneCount or 0, idx.pullCount or 0,
                idx.cloneConflicts and string.format(" · |cFFff9922%d repetidos|r", idx.cloneConflicts) or ""))
            -- Un cloneIdx mayor que el numero de clones que el enemigo tiene de
            -- verdad no es una ruta rara: es un dato imposible, y significa que
            -- la ruta se importo con el BUG CLONE-1. Se pide reimportar.
            if tonumber(profile.cloneOutOfRange) and profile.cloneOutOfRange > 0 then
                add(string.format("               |cFFff5555%d clones con indice imposible|r · reimporta con |cFFf7d470/emp rutastodas|r",
                    profile.cloneOutOfRange))
            end
        else
            add("Identidad de ruta |cFFff9922FALTA|r · ruta importada antes de la 7.10.0.")
            add("               Reimportala con |cFFf7d470/emp rutastodas|r para tener flechas por pull.")
        end
    else
        allOk = false
        add("Ruta           |cFFff5555FALTA|r · no hay ruta guardada para esta mazmorra")
        if API then add("               Usa |cFFf7d470/emp rutastodas|r con MDT cargado.") end
    end

    add(allOk and "|cFF21de66Todo listo para esta mazmorra.|r"
               or "|cFFff9922Faltan piezas: mira las marcadas arriba.|r")

    -- En modo Aprendiendo, si TODO esta bien no hace falta el desglose: seis
    -- lineas de "OK" al entrar a cada mazmorra son ruido. Si algo falla se
    -- enseña entero, porque ahi si hay que actuar.
    if not quiet then
        if learnMode() and allOk then
            MitzuMPlus:Print(string.format(
                "|cFF21de66Ruta lista|r para %s. El Coach te irá guiando.",
                tostring(dungeonName or "esta mazmorra")))
        else
            for _, l in ipairs(lines) do MitzuMPlus:Print(l) end
        end
    end
    return allOk, lines
end

-- Al entrar en la mazmorra (antes de arrancar la llave) se carga la ruta y se
-- da el parte. Se hace con un pequeño retraso porque al cruzar el portal las
-- APIs de challenge mode aun no responden.
function AR:OnEnterDungeon()
    if not (self.ProfileManager and self.ProfileManager._ready) then return end
    local ctx = self.ProfileManager:GetContext()
    if not ctx then return end
    if self._lastSyncDungeon == ctx.dungeonID then return end
    self._lastSyncDungeon = ctx.dungeonID

    -- (v7.9.1) El estado del arranque anterior pertenece a la mazmorra
    -- anterior. Sin esto, /emp ruta seguia enseñando "ruta 249 activa" recien
    -- llegado a otra mazmorra distinta.
    self._lastStatus, self._lastStatusKey = nil, nil

    -- ─────────────────────────────────────────────────────────────────────
    -- (v7.9.1) Aqui se INDEXA la ruta, no solo se imprime el parte.
    --
    -- Antes el indice solo se construia en RUN_STARTED, o sea al meter la
    -- piedra. Entre cruzar el portal y arrancar la llave, /emp ruta decia "Sin
    -- ruta indexada. Importa una ruta MDT" teniendo el perfil guardado y
    -- emparejado dos lineas mas arriba en el mismo informe. Se contradecia solo.
    --
    -- Indexar no arranca nada: el EventTracker sigue parado hasta RUN_STARTED.
    -- Solo deja la ruta lista y consultable.
    -- ─────────────────────────────────────────────────────────────────────
    local PM, DS = self.ProfileManager, self.DataStructure
    if PM and DS then
        local profile, key = PM:LoadNearest()
        if profile then
            local okBuild = pcall(function() return DS:Build(profile) end)
            self._preloadedKey = okBuild and key or nil
        else
            self._preloadedKey = nil
        end
    end

    self:SyncReport(false)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BUG CTX-2 (v7.11.0) — el informe de entrada salia DOS veces.
--
-- Aqui habia un frame propio registrado a PLAYER_ENTERING_WORLD **y** a
-- ZONE_CHANGED_NEW_AREA. Al entrar a una mazmorra llegan los dos, cada uno
-- programaba su C_Timer.After(3), y OnEnterDungeon corria dos veces: de ahi el
-- "Todo listo para esta mazmorra." duplicado que se vio en vivo.
--
-- Silenciar el segundo print habria tapado el sintoma. La causa era tener dos
-- fuentes para el mismo hecho. Ahora la fuente es una: DungeonContext emite
-- MITZU_DUNGEON_CHANGED UNA vez por mazmorra —si el mapa no cambia, no emite—
-- y este modulo solo escucha.
-- ═══════════════════════════════════════════════════════════════════════════
if MitzuMPlus.EventBus then
    MitzuMPlus.EventBus:On("MITZU_DUNGEON_CHANGED", function()
        -- El retardo se conserva: MDT puede tardar en tener su API lista y el
        -- informe la consulta.
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function() pcall(function() AR:OnEnterDungeon() end) end)
        else
            pcall(function() AR:OnEnterDungeon() end)
        end
    end)
    -- Al salir de la mazmorra se rearma para la proxima.
    MitzuMPlus.EventBus:On("MITZU_DUNGEON_STATE_CHANGED", function(nuevo)
        if nuevo == "OUTSIDE" then AR._lastSyncDungeon = nil end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────
-- ENGANCHE AL CICLO DE VIDA
-- ─────────────────────────────────────────────────────────────────────────

if MitzuMPlus.EventBus and MitzuMPlus.EventBus.On then
    MitzuMPlus.EventBus:On("RUN_STARTED", function(run)
        pcall(function() AR:StartForRun(run) end)
    end, 60)
    MitzuMPlus.EventBus:On("RUN_COMPLETED", function()
        pcall(function() AR:StopForRun(true) end)
    end, 60)
    MitzuMPlus.EventBus:On("RUN_RESET", function()
        pcall(function() AR:StopForRun(false) end)
    end, 60)
    MitzuMPlus.EventBus:On("RUN_TEARDOWN", function()
        pcall(function() AR:StopForRun(false) end)
    end, 60)
end

-- ─────────────────────────────────────────────────────────────────────────
-- DIAGNÓSTICO
-- ─────────────────────────────────────────────────────────────────────────

function AR:StatusLines()
    local out = {}
    local function add(s) out[#out + 1] = s end

    local PM = self.ProfileManager
    add("|cFFe8b84a═════ RUTA ADAPTATIVA ═════|r")
    if not PM or not PM._ready then
        add("|cFFff5555DB de perfiles no inicializada.|r")
        return out
    end

    local ctx = PM:GetContext()
    if ctx then
        -- Antes: "Contexto: mazmorra 588 · +9 · afijos 10-160 (active)".
        -- Numeros internos donde deberia ir el nombre de la mazmorra.
        local dn
        if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
            local okN, n = pcall(C_ChallengeMode.GetMapUIInfo, ctx.dungeonID)
            if okN then dn = n end
        end
        add(string.format("Mazmorra: %s%s", tostring(dn or ctx.dungeonID),
            (ctx.keyLevel or 0) > 0 and (" +" .. ctx.keyLevel) or ""))
        if dbg() then
            add(string.format("  [debug] id=%d afijos=%s fuente=%s clave=%s",
                ctx.dungeonID, ctx.affixes, tostring(ctx.source),
                tostring(PM:BuildProfileKey(ctx))))
        end
    else
        add("Sin mazmorra activa ni llave en la bolsa: no hay clave de perfil.")
    end

    -- La clave que toca AHORA. Todo lo de abajo se juzga contra ella.
    local curKey = ctx and PM:BuildProfileKey(ctx) or nil

    local profiles = PM:List()
    add(string.format("Perfiles guardados: %d", #profiles))

    -- Se enseñan hasta 8 y se dice cuantos quedan. Antes cortaba en 5 sin
    -- avisar, asi que con 8 perfiles guardados la respuesta a "¿tengo ruta
    -- para esta mazmorra?" podia estar entre los tres que no se veian.
    local shown = math.min(8, #profiles)
    for i = 1, shown do
        local p = profiles[i]
        -- Ojo: no llamarlo 'mark'. Esta funcion ya tiene un mark() local para
        -- los OK/FALTA y taparlo aqui dentro es pedir un fallo silencioso.
        local here = (curKey and p.key == curKey) and "  |cFF21de66<- esta mazmorra|r" or ""
        add(string.format("  %s · %d pulls · %s%s", p.key, p.pulls,
            date and p.updated > 0 and date("%Y-%m-%d", p.updated) or "?", here))
    end
    if #profiles > shown then
        add(string.format("  ... y %d mas.", #profiles - shown))
    end

    if curKey and not PM:Load(curKey) then
        add("|cFFff9922No hay ruta guardada para esta mazmorra.|r Abre MDT en ella y usa |cFFf7d470/emp cargarruta|r.")
    end

    if self._lastStatus then
        -- El ultimo arranque puede ser de OTRA mazmorra: es lo ultimo que paso,
        -- no lo que pasa ahora. Decirlo a secas hacia creer que la ruta cargada
        -- era la de aqui.
        local suffix = ""
        if self._lastStatusKey and curKey and self._lastStatusKey ~= curKey then
            suffix = string.format("  |cFFff9922(de la mazmorra %s, no de esta)|r",
                tostring(self._lastStatusKey))
        end
        add("Último arranque: " .. tostring(self._lastStatus) .. suffix)
    end

    if self.EventTracker then
        for _, l in ipairs(self.EventTracker:StatusLines()) do add(l) end
    end
    if self.RouteArrows then
        for _, l in ipairs(self.RouteArrows:StatusLines()) do add(l) end
    end
    if self.PullNavigator then
        for _, l in ipairs(self.PullNavigator:StatusLines()) do add(l) end
    end
    if self.PullUnitResolver then
        for _, l in ipairs(self.PullUnitResolver:StatusLines()) do add(l) end
    end
    return out
end

-- Prueba en seco del solver, sin necesidad de estar en una llave. Existe
-- porque es la unica pieza que se puede verificar sin entrar al juego: si el
-- reparto que saca aqui no tiene sentido, no lo va a tener en una M+.
function AR:TestSolver(delta)
    delta = tonumber(delta) or 12
    local Solver = self.Solver
    if not Solver then return { "Solver no cargado" } end

    -- Ruta de juguete: 8 pulls con pesos y costes distintos.
    local candidates = {
        { index = 1, count = 4,  cost = 1 },
        { index = 2, count = 6,  cost = 5 },   -- caro de ir a por el: buen skip
        { index = 3, count = 10, cost = 1 },
        { index = 4, count = 5,  cost = 4 },
        { index = 5, count = 8,  cost = 2 },
        { index = 6, count = 3,  cost = 6 },   -- barato en tropas, muy desviado
        { index = 7, count = 12, cost = 1 },
        { index = 8, count = 7,  cost = 3 },
    }
    local skips, used, saved, method = Solver.Solve(candidates, delta, { minKeep = 1 })
    local out = {
        string.format("|cFFd9b33eSolver|r delta=%d · metodo=%s", delta, tostring(method)),
        string.format("  saltar pulls: %s", #skips > 0 and table.concat(skips, ", ") or "(ninguno)"),
        string.format("  tropas gastadas: %d de %d · coste ahorrado: %d", used, delta, saved),
    }
    return out
end

return AR
