-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · EventTracker v1.0
--
-- Captura de muertes y sincronización de red.
--
-- RENDIMIENTO — el requisito duro
-- COMBAT_LOG_EVENT_UNFILTERED dispara cientos de veces por segundo en un pull
-- grande. Aquí se sale del handler en la PRIMERA comparación cuando el evento
-- no es UNIT_DIED, antes de tocar ninguna tabla. Solo entonces se extrae el
-- npcID del destGUID y se consulta el hash del DataStructure: una lectura,
-- sin bucles. Cero asignaciones de tabla en el camino caliente.
--
-- MIDNIGHT — valores secretos
-- Este cliente devuelve secret values en varios campos (UnitPower, UnitHealth).
-- Las identidades NO están restringidas (C_Secrets.ShouldUnitIdentityBeSecret
-- = false, medido), así que destGUID debería llegar limpio — pero "debería" ya
-- falló dos veces en este addon, así que el GUID se valida antes de usarlo y
-- un fallo apaga el módulo en vez de reventar cada muerte.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local EventTracker = {}
AR.EventTracker = EventTracker

local COMM_PREFIX   = "MMPARoute"
local COMM_VERSION  = 1
local MAX_MSG_BODY  = 200      -- margen bajo el límite de 255 bytes por mensaje
local RESOLVE_DELAY = 1.5      -- segundos de agrupación antes de recalcular

local _issecretvalue = rawget(_G, "issecretvalue")
local strsplit = strsplit
local tonumber = tonumber

-- ─────────────────────────────────────────────────────────────────────────
-- ESTADO
-- ─────────────────────────────────────────────────────────────────────────

EventTracker._active      = false
EventTracker._activeSkips = {}     -- [npcID] = true
EventTracker._pullIndex   = 1      -- pull esperado actualmente
EventTracker._observed    = 0      -- tropas observadas (de nuestro conteo)
EventTracker._dirty       = false
EventTracker._blocked     = nil    -- motivo si el cliente impide leer GUIDs

-- ═════════════════════════════════════════════════════════════════════════
-- APRENDIZAJE DE npcIDs POR PULL (v7.2.0)
--
-- MDT no publica dungeonEnemies, asi que no hay forma de saber DE ANTEMANO
-- que mobs lleva cada pull. Pero jugando la ruta se ve: los pulls llegan en
-- rafagas de muertes separadas por el tiempo de desplazamiento entre packs.
--
-- Se segmenta por huecos: muertes a menos de LEARN_GAP segundos = mismo pull;
-- un hueco mayor cierra el segmento. Es exactamente el criterio que ya usa
-- RouteAdvisor para medir el tamano de los pulls, asi que los dos coinciden.
--
-- LIMITE HONESTO: esto asume que sigues la ruta en orden. Si te la saltas, el
-- segmento 5 no sera el pull 5. Por eso NO se marca nada con una sola vuelta:
-- hace falta ver el mismo npcID en el mismo segmento en 2 llaves distintas.
-- Con una sola, se aprende y se calla.
-- ═════════════════════════════════════════════════════════════════════════
local LEARN_GAP = 5.0     -- segundos de silencio que cierran un pull

EventTracker._learn = nil

function EventTracker:GetActiveSkips()
    return self._activeSkips
end

function EventTracker:IsSkipped(npcID)
    return self._activeSkips[npcID] == true
end

-- ─────────────────────────────────────────────────────────────────────────
-- EXTRACCIÓN DE npcID
--
-- Formato: "Creature-0-1234-5678-90-<npcID>-<spawnUID>"
-- strsplit sobre una cadena corta y fija; no hay búsqueda ni iteración.
-- ─────────────────────────────────────────────────────────────────────────
-- ═════════════════════════════════════════════════════════════════════════
-- TROPAS POR MOB, via API oficial de MDT (v6.9.0)
--
-- MDT no publica dungeonEnemies, asi que no se puede saber de antemano que
-- npcIDs lleva cada pull. Pero SI publica:
--   MythicDungeonToolsAPI:GetEnemyForces(npcId) -> count, maxCountNormal
-- (MDT/Modules/API.lua). Con eso, cada muerte aporta su valor real en tropas
-- aunque la ruta no traiga npcIDs, que es lo que hace que el delta signifique
-- algo. Se cachea porque en un pull grande esto se consulta muchas veces.
-- ═════════════════════════════════════════════════════════════════════════
local forceCache = {}
local function npcForce(npcID)
    local c = forceCache[npcID]
    if c ~= nil then return c or nil end
    local API = rawget(_G, "MythicDungeonToolsAPI")
    if type(API) ~= "table" or type(API.GetEnemyForces) ~= "function" then
        forceCache[npcID] = false
        return nil
    end
    local ok, count = pcall(API.GetEnemyForces, API, npcID)
    local v = (ok and tonumber(count)) or false
    forceCache[npcID] = v
    return v or nil
end

local function npcIDFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local unitType, _, _, _, _, id = strsplit("-", guid)
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end
    return tonumber(id)
end

-- ─────────────────────────────────────────────────────────────────────────
-- CAMINO CALIENTE
-- ─────────────────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame")

local function onCombatLog()
    -- Primera línea: la bandera. Va ANTES de CombatLogGetCurrentEventInfo()
    -- porque esa llamada devuelve ~20 valores y el evento queda registrado de
    -- por vida (ver BUG TAINT-1 en Stop()). Fuera de una llave, el coste de
    -- este handler es leer un booleano.
    local self = EventTracker
    if not self._active then return end

    -- Segunda: si no es una muerte, fuera, sin tocar ninguna tabla.
    local _, subEvent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
    if subEvent ~= "UNIT_DIED" then return end

    if _issecretvalue and _issecretvalue(destGUID) then
        -- El cliente bloquea la identidad. Sin GUID no hay npcID y el módulo
        -- entero no tiene sentido: se apaga y lo dice una vez.
        self._blocked = "destGUID secreto"
        self:Stop()
        if MitzuMPlus.Print then
            MitzuMPlus:Print("|cFFff9922AdaptiveRoute:|r este cliente no permite leer los GUID del combat log. Módulo desactivado.")
        end
        return
    end

    local npcID = npcIDFromGUID(destGUID)
    if not npcID then return end

    local DS = AR.DataStructure
    local idx = DS and DS:Get()
    if not idx then return end

    -- Aprendizaje: se anota SIEMPRE, incluso si el mob no esta en la ruta
    -- conocida. Es barato (dos escrituras de tabla) y es justo lo que permite
    -- construir el mapa que hoy falta.
    local L = self._learn
    if L then
        local t = (GetTime and GetTime()) or 0
        if L.lastAt > 0 and (t - L.lastAt) > LEARN_GAP and next(L.current) then
            L.segments[#L.segments + 1] = L.current
            L.current = {}
        end
        L.current[npcID] = true
        L.lastAt = t
    end

    local pullIndex = idx.npcToPull[npcID]
    if not pullIndex then return end     -- mob fuera de ruta: no cuenta como plan

    -- Contabilidad barata: sumar y marcar. El recálculo NO se hace aquí.
    idx.killed[npcID] = (idx.killed[npcID] or 0) + 1
    self._observed = self._observed + (idx.npcCount[npcID] or npcForce(npcID) or 0)
    if pullIndex > self._pullIndex then self._pullIndex = pullIndex end
    self._dirty = true
end

-- onCombatLog y el aprendizaje de npcIDs que cuelga de el quedan sin usar:
-- el evento no se puede registrar (ver BUG CLEU-1). No se borran porque si
-- Blizzard reabre el combat log basta con volver a registrarlo, pero HOY son
-- codigo muerto y conviene que se lea asi en vez de aparentar que corre.
local _ = onCombatLog

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        EventTracker:_OnAddonMessage(...)
    end
end)

-- ═════════════════════════════════════════════════════════════════════════
-- BUG TAINT-2 (v7.8.1) — RegisterEvent tampoco. El registro va AQUI.
--
--   [ADDON_ACTION_FORBIDDEN] 'MitzuMPlus_Historial' intento llamar a la
--   funcion protegida 'Frame:RegisterEvent()'
--   EventTracker:Start -> Bootstrap:StartForRun -> handler de evento
--
-- Es exactamente el mismo fallo que ya documente para UnregisterEvent en
-- Stop(), y lo repeti en el otro extremo del ciclo de vida: Start() colgaba de
-- una ruta de eventos contaminada (Core emite RUN_STARTED desde dentro del
-- handler del cliente), y en ese contexto REGISTRAR un evento esta tan
-- prohibido como desregistrarlo.
--
-- La regla, ahora sin excepciones: este frame se registra UNA vez, al cargar
-- el archivo — que es codigo limpio, sin taint — y no se toca nunca mas.
-- Encender y apagar es la bandera _active, que onCombatLog lee en su primera
-- linea. Start()/Stop() ya no llaman a nada protegido.
-- ═════════════════════════════════════════════════════════════════════════
-- ═════════════════════════════════════════════════════════════════════════
-- BUG CLEU-1 (v7.9.0) — el registro de combate NO existe para addons.
--
-- Mover este RegisterEvent al main chunk no arreglo nada: el cliente lo
-- siguio rechazando seis veces por sesion desde codigo limpio, sin taint.
-- Eso descarta mi diagnostico anterior y deja el de verdad:
--
--   COMBAT_LOG_EVENT_UNFILTERED esta cerrado a los addons en Midnight.
--
-- Lo que duele es que el propio addon ya lo sabia. MidnightSafeTracking.lua
-- declara combatLog=false y existe justo para sustituir el combat log por
-- C_DamageMeter. Construi todo el EventTracker contando UNIT_DIED sin leer
-- ese archivo, sobre una premisa que aqui al lado ya estaba descartada.
--
-- Asi que el conteo de bajas se va entero. En su lugar se usa el recuento
-- OFICIAL de tropas (C_ScenarioInfo), que KeystoneTracker ya extrae. Es mejor
-- fuente en todos los sentidos: es exacta, cuenta al grupo entero y no al
-- jugador, incluye patrullas y packs fuera de ruta, y no depende de que el
-- GUID sea legible (que en Midnight tambien puede ser secreto).
--
-- Solo se registra CHAT_MSG_ADDON, que el cliente si permite.
-- ═════════════════════════════════════════════════════════════════════════
frame:RegisterEvent("CHAT_MSG_ADDON")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, COMM_PREFIX)
end

-- ═════════════════════════════════════════════════════════════════════════
-- VOLCADO DE LO APRENDIDO
--
-- Se guarda un CONTADOR por (segmento, npcID), no un simple "visto". Asi un
-- npcID que aparece siempre en el segmento 3 gana peso, y uno que salio ahi
-- por casualidad una vez no. La confianza sale de repetir, no de una foto.
--
-- Ademas se exige que el numero de segmentos se parezca al de pulls de la
-- ruta: si haces la ruta en 20 rafagas cuando MDT tiene 12 pulls, ese recorrido
-- no siguio la ruta y aprender de el ensuciaria el mapa.
-- ═════════════════════════════════════════════════════════════════════════
function EventTracker:_CommitLearning()
    local L, profile = self._learn, self._learnProfile
    self._learn, self._learnProfile = nil, nil
    if not L or not profile then return end

    -- Cerrar el segmento abierto.
    if next(L.current) then L.segments[#L.segments + 1] = L.current end
    local segs = #L.segments
    if segs == 0 then return end

    local planned = type(profile.pulls) == "table" and #profile.pulls or 0
    if planned == 0 then return end

    -- Tolerancia: +/- 40% de los pulls planeados. Fuera de ahi no se aprende.
    local lo, hi = math.floor(planned * 0.6), math.ceil(planned * 1.4)
    if segs < lo or segs > hi then
        profile.learnRejected = (profile.learnRejected or 0) + 1
        self._lastLearn = string.format("descartado: %d rafagas para %d pulls", segs, planned)
        return
    end

    profile.learned = type(profile.learned) == "table" and profile.learned or {}
    for i = 1, math.min(segs, planned) do
        local bucket = profile.learned[i]
        if type(bucket) ~= "table" then bucket = {}; profile.learned[i] = bucket end
        for npcID in pairs(L.segments[i]) do
            bucket[npcID] = (bucket[npcID] or 0) + 1
        end
    end
    profile.learnRuns = (profile.learnRuns or 0) + 1
    self._lastLearn = string.format("%d rafagas sobre %d pulls · vuelta %d",
        segs, planned, profile.learnRuns)

    -- Persistir de inmediato: si el usuario sale del juego sin cerrar sesion
    -- limpia, lo aprendido en esta llave no se pierde.
    local PM = AR.ProfileManager
    if PM then
        local _, key = PM:GetActive()
        if key then PM:Save(key, profile) end
    end
end

-- Convierte lo aprendido en el mapa npcID -> pull, aplicando la regla de
-- confianza. Devuelve tambien cuantos npcIDs quedaron fuera por ambiguos.
--
-- REGLAS:
--   · Hacen falta 2 vueltas (o todas las que haya, si solo hay 1 no se marca).
--   · Un npcID se asigna al pull donde MAS veces se le ha visto.
--   · Si empata entre dos pulls, se descarta: marcar el pack equivocado es
--     peor que no marcar nada.
function AR.BuildLearnedMap(profile, minRuns)
    local out, ambiguous = {}, 0
    if type(profile) ~= "table" or type(profile.learned) ~= "table" then
        return out, ambiguous, 0
    end
    local runs = tonumber(profile.learnRuns) or 0
    minRuns = minRuns or 2
    if runs < minRuns then return out, ambiguous, runs end

    -- npcID -> { [pullIdx] = veces }
    local byNpc = {}
    for pullIdx, bucket in pairs(profile.learned) do
        for npcID, n in pairs(bucket) do
            byNpc[npcID] = byNpc[npcID] or {}
            byNpc[npcID][pullIdx] = n
        end
    end

    for npcID, seen in pairs(byNpc) do
        local bestIdx, bestN, tie = nil, 0, false
        for pullIdx, n in pairs(seen) do
            if n > bestN then bestIdx, bestN, tie = pullIdx, n, false
            elseif n == bestN then tie = true end
        end
        if bestIdx and not tie and bestN >= minRuns then
            out[npcID] = bestIdx
        else
            ambiguous = ambiguous + 1
        end
    end
    return out, ambiguous, runs
end

-- ─────────────────────────────────────────────────────────────────────────
-- RESOLUCIÓN DIFERIDA
--
-- El recálculo no puede vivir en el handler del combat log: en un pull grande
-- se ejecutaría 30 veces en dos segundos para dar el mismo resultado. Un
-- ticker lo agrupa y solo recalcula si algo cambió.
-- ─────────────────────────────────────────────────────────────────────────

-- Recuento OFICIAL de tropas: {actuales, necesarias}. KeystoneTracker ya lo
-- extrae de C_ScenarioInfo y resuelve ahi el lio de quantityString frente a
-- quantity; no se reimplementa.
local function officialForces()
    local kt = MitzuMPlus.KeystoneTracker
    local ef = kt and kt._enemyForces
    if type(ef) ~= "table" then return nil end
    local cur, tot = tonumber(ef.current), tonumber(ef.total)
    if not cur or not tot or tot <= 0 then return nil end
    return cur, tot
end

-- Donde vamos en la ruta. Sin bajas por npcID no se puede saber la posicion
-- exacta, asi que se deduce de las tropas: el ultimo pack cuyo acumulado ya
-- hemos superado. Da por hecho que se sigue la ruta en orden — si el grupo se
-- la salta, esto va perdido, y por eso el aviso lo dice.
local function pullIndexFromForces(DS, idx, observed)
    local last = 1
    for i = 1, (idx.pullCount or 0) do
        if (idx.cumulative[i] or 0) <= observed then last = i else break end
    end
    return last
end

function EventTracker:_Resolve()
    if not self._active then return end

    local DS, Solver = AR.DataStructure, AR.Solver
    if not DS or not Solver then return end
    local idx = DS:Get()
    if not idx then return end

    local observed, required = officialForces()
    if not observed then
        self._noForces = true
        return
    end
    self._noForces = false
    self._observed = observed
    self._required = required
    self._pullIndex = pullIndexFromForces(DS, idx, observed)

    -- ─────────────────────────────────────────────────────────────────────
    -- v7.9.0 — el margen ya no es "lo que llevo de mas respecto al plan".
    --
    -- Aquella resta necesitaba saber por que pack vamos, que sin combat log no
    -- se sabe con precision; y calcularla a partir de las mismas tropas que
    -- luego se restaban daba siempre un numero pequeño y positivo, o sea
    -- proponer saltos constantemente.
    --
    -- La pregunta correcta no necesita posicion exacta:
    --
    --   sobrante = tropas que quedan planificadas - tropas que faltan
    --
    -- Si la ruta que queda por delante trae mas tropas de las que faltan para
    -- el 100%, ESE sobrante es lo que se puede tirar. Y como las tropas
    -- actuales son el recuento oficial, ya llevan dentro las patrullas, los
    -- packs de mas y todo lo que se haya matado fuera del plan.
    -- ─────────────────────────────────────────────────────────────────────
    -- Con un perfil de antes de la 7.9.2 los pesos son inventados: calcular el
    -- sobrante con ellos da numeros con pinta de buenos que no lo son.
    if not idx.exact then
        self._staleRoute = true
        if next(self._activeSkips) ~= nil then
            self._activeSkips = {}
            self:_Broadcast()
        end
        return
    end
    self._staleRoute = false

    local plannedLeft = math.max(0, (idx.plannedTotal or 0) - (DS:ExpectedAt(self._pullIndex) or 0))
    local neededLeft  = math.max(0, required - observed)
    local delta       = plannedLeft - neededLeft

    self._lastDelta       = delta
    self._lastPlannedLeft = plannedLeft
    self._lastNeededLeft  = neededLeft

    if delta <= 0 then
        if next(self._activeSkips) ~= nil then
            self._activeSkips = {}
            self:_Broadcast()
        end
        return
    end

    local candidates = DS:RemainingPulls(self._pullIndex + 1)
    local skipIndices, used, saved, method = Solver.Solve(candidates, delta, {
        minKeep = 1,
        protect = self._protected,
    })

    local excluded
    self._activeSkips, excluded = Solver.BuildSkipSet(skipIndices, idx, self._pullIndex + 1)
    self._lastExcluded = excluded
    self._lastSolve = { skips = skipIndices, used = used, saved = saved, method = method }

    self:_Broadcast()
end

-- ─────────────────────────────────────────────────────────────────────────
-- RED
--
-- Solo el líder emite. Si cada miembro recalculase y emitiese, cinco versiones
-- distintas de ActiveSkips se pisarían entre sí — y el delta de cada uno puede
-- diferir si alguien entró tarde o el combat log se le perdió un mob.
-- ─────────────────────────────────────────────────────────────────────────

local function channel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

local function isLeader()
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then return true end
    if IsInGroup and not IsInGroup() then return true end   -- en solo, mando yo
    return false
end

function EventTracker:_Broadcast()
    local pm = AR.ProfileManager
    local st = pm and pm:Settings()
    if st and st.syncWithGroup == false then return end
    if not isLeader() then return end
    local ch = channel()
    if not ch then return end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end

    -- Serialización compacta: solo npcIDs separados por comas. Cualquier
    -- serializador genérico multiplicaría por 3 el tamaño para transportar
    -- una lista de enteros.
    local ids = {}
    for npcID in pairs(self._activeSkips) do ids[#ids + 1] = npcID end
    table.sort(ids)

    local payload = table.concat(ids, ",")
    -- Troceado: un mensaje de addon no pasa de 255 bytes. Con 40 npcIDs de 6
    -- cifras se supera, así que se parte y el receptor reensambla.
    local chunks, cur = {}, ""
    for i = 1, #ids do
        local piece = tostring(ids[i])
        if #cur + #piece + 1 > MAX_MSG_BODY then
            chunks[#chunks + 1] = cur
            cur = piece
        else
            cur = (cur == "") and piece or (cur .. "," .. piece)
        end
    end
    if cur ~= "" or #chunks == 0 then chunks[#chunks + 1] = cur end

    local total = #chunks
    for i = 1, total do
        local msg = string.format("%d|S|%d|%d|%s", COMM_VERSION, i, total, chunks[i])
        pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX, msg, ch)
    end
    self._lastBroadcast = { count = #ids, chunks = total, payloadBytes = #payload }
end

function EventTracker:_OnAddonMessage(prefix, message, _, sender)
    if prefix ~= COMM_PREFIX then return end
    if type(message) ~= "string" then return end

    -- Nunca aplicar lo que emite uno mismo: ya está aplicado, y reensamblar el
    -- eco propio podría pisar un cálculo más reciente.
    local me = UnitName and UnitName("player")
    if me and sender and (sender == me or sender:match("^" .. me .. "%-")) then return end

    local ver, kind, i, total, body = message:match("^(%d+)|(%a)|(%d+)|(%d+)|(.*)$")
    if not ver or tonumber(ver) ~= COMM_VERSION or kind ~= "S" then return end
    i, total = tonumber(i), tonumber(total)
    if not i or not total then return end

    local buf = self._rxBuffer
    if not buf or buf.sender ~= sender or buf.total ~= total then
        buf = { sender = sender, total = total, parts = {}, got = 0 }
        self._rxBuffer = buf
    end
    if not buf.parts[i] then
        buf.parts[i] = body or ""
        buf.got = buf.got + 1
    end
    if buf.got < total then return end

    local set = {}
    for k = 1, total do
        for id in tostring(buf.parts[k] or ""):gmatch("(%d+)") do
            set[tonumber(id)] = true
        end
    end
    self._rxBuffer = nil
    self._activeSkips = set
    self._skipsFromLeader = sender
end

-- ─────────────────────────────────────────────────────────────────────────
-- CICLO DE VIDA
-- ─────────────────────────────────────────────────────────────────────────

function EventTracker:Start(profile)
    if self._blocked then return false, self._blocked end
    local pm = AR.ProfileManager
    local st = pm and pm:Settings()
    if st and st.enabled == false then return false, "desactivado en ajustes" end

    local DS = AR.DataStructure
    if not DS then return false, "DataStructure no cargado" end
    local idx = DS:Build(profile)
    if not idx then return false, "perfil sin ruta utilizable" end

    self._active      = true
    self._activeSkips = {}
    self._pullIndex   = 1
    self._observed    = 0
    self._dirty       = false
    self._protected   = nil
    self._learn       = { segments = {}, current = {}, lastAt = 0 }
    self._learnProfile = profile

    -- Con que mazmorra arranco. Sirve para que los informes puedan decir si lo
    -- que esta activo corresponde a donde estas, en vez de dar por hecho que si.
    self._startedKey = profile and profile.challengeMapID
                       and tostring(profile.challengeMapID) or nil

    if C_Timer and C_Timer.NewTicker and not self._ticker then
        self._ticker = C_Timer.NewTicker(RESOLVE_DELAY, function()
            -- ═════════════════════════════════════════════════════════════
            -- BUG RUTA-VIVA (v7.8.3) — la ruta sobrevivia a su llave.
            --
            -- Stop() cuelga de RUN_TEARDOWN. Si la llave acaba por una via que
            -- no pasa por ahi (salir por el portal, /reload, desconexion, o
            -- simplemente abandonar), el tracker se quedaba activo: seguia
            -- contando UNIT_DIED y atribuyendo los mobs de la mazmorra
            -- SIGUIENTE a la ruta anterior.
            --
            -- Se vio en un /emp ruta desde Templo de Sethraliss que informaba
            -- "ruta 250 activa · 11 packs". Once packs es el perfil 250, de
            -- otra mazmorra. Ese conteo contamina ademas el aprendizaje de
            -- npcIDs, que es justo lo que hace falta que sea fiable.
            --
            -- La comprobacion va aqui, en el ticker que ya existe, y no en un
            -- evento nuevo: no hay estado que registrar y funciona sea cual sea
            -- la via por la que termino la llave.
            -- ═════════════════════════════════════════════════════════════
            if _G.MitzuMPlusCurrentRun == nil then
                pcall(function() EventTracker:Stop() end)
                return
            end

            local ok, err = pcall(function() EventTracker:_Resolve() end)
            if not ok and MitzuMPlus.Print then
                local s = MitzuMPlus.db and MitzuMPlus.db.profile
                          and MitzuMPlus.db.profile.settings
                if s and s.debugMode then
                    MitzuMPlus:Print("|cFFff5555[AdaptiveRoute]|r " .. tostring(err))
                end
            end
        end)
    end
    return true
end

-- ═════════════════════════════════════════════════════════════════════════
-- BUG TAINT-1 (v6.8.1) — no se desregistran eventos. Nunca.
--
-- Este Stop() hacia frame:UnregisterEvent() y el cliente lo rechazo:
--   [ADDON_ACTION_FORBIDDEN] 'MitzuMPlus_Historial' intento llamar a la
--   funcion protegida 'Frame:UnregisterEvent()'
-- Dos veces, una por cada teardown de llave. Se dispara porque Stop() cuelga
-- de RUN_TEARDOWN, que Core emite desde dentro del handler de
-- CHALLENGE_MODE_COMPLETED: ejecucion contaminada por el addon dentro de una
-- ruta de eventos que el cliente considera protegida.
--
-- Escribi en la cabecera de NameplateHooks que este modulo no llamaria a
-- ninguna funcion protegida, y luego lo hice aqui. El registro dinamico de
-- eventos ES una llamada protegida en este cliente, igual que mover un frame
-- seguro en combate.
--
-- SOLUCION: los eventos se registran en Start() y ya no se sueltan. El
-- apagado es una bandera. Para que eso no cueste nada, onCombatLog comprueba
-- _active en su PRIMERA linea, ANTES de llamar a CombatLogGetCurrentEventInfo
-- (que devuelve ~20 valores y si era caro llamarlo por cada linea del log
-- fuera de una llave). Inactivo, el coste por evento es una lectura de
-- booleano sobre un upvalue.
-- ═════════════════════════════════════════════════════════════════════════
function EventTracker:Stop()
    -- Volcar lo aprendido ANTES de soltar el estado.
    pcall(function() EventTracker:_CommitLearning() end)
    self._active = false
    if self._ticker then
        if self._ticker.Cancel then self._ticker:Cancel() end
        self._ticker = nil
    end
    self._activeSkips = {}
end

function EventTracker:StatusLines()
    local out = {}
    local function add(s) out[#out + 1] = s end
    local st = MitzuMPlus.db and MitzuMPlus.db.profile and MitzuMPlus.db.profile.settings
    local debug = st and st.debugMode == true

    -- Si esta activa se dice DE QUE mazmorra, y se avisa cuando no es esta.
    -- "siguiendo la ruta · 11 packs" a secas, estando en otra mazmorra, se lee
    -- como que la ruta cargada es la correcta.
    local whose = ""
    if self._active and self._startedKey then
        local cur = AR.ProfileManager and AR.ProfileManager:BuildProfileKey() or nil
        if cur and cur ~= self._startedKey then
            whose = string.format(" · |cFFff5555ruta de la mazmorra %s, NO de esta|r",
                self._startedKey)
        else
            whose = " · ruta " .. self._startedKey
        end
    end
    add(string.format("|cFFd9b33eRuta|r %s%s%s",
        self._active and "|cFF21de66siguiendo la ruta|r" or "en espera", whose,
        self._blocked and (" · |cFFff5555BLOQUEADO: " .. self._blocked .. "|r") or ""))

    local DS = AR.DataStructure
    local idx = DS and DS:Get()
    if not idx then
        add("Sin ruta indexada. Importa una ruta MDT o carga un perfil.")
        return out
    end
    add(string.format("%d packs · %s",
        idx.pullCount,
        idx.hasNpcData and "mobs reconocidos" or "|cFFff9922aun sin reconocer mobs|r"))

    -- Ruta cargada pero llave sin arrancar: es lo normal entre cruzar el
    -- portal y meter la piedra, y hay que decirlo con esas palabras. El resto
    -- del informe (sobrante de tropas, packs a saltar) no significa nada
    -- todavia porque no hay recuento oficial hasta que la llave corre.
    if not idx.exact then
        add("|cFFff5555Esta ruta es de una version anterior|r y no trae los mobs de cada pack.")
        add("Vuelve a importarla con |cFFf7d470/emp rutastodas|r (con MDT abierto).")
        return out
    end

    if not self._active then
        add("|cFFd9b33eLista y esperando|r a que arranque la llave.")
        return out
    end

    -- El delta en cristiano: lo que importa es si vas sobrado o corto de
    -- tropas respecto al plan, no los tres numeros que lo producen.
    local d = self._lastDelta and math.floor(self._lastDelta) or nil
    if d == nil then
        add("Todavia sin comparar con el plan.")
    elseif d > 0 then
        add(string.format("A la ruta que queda le |cFF21de66sobran %d tropas|r: se pueden saltar packs.", d))
    elseif d < 0 then
        add(string.format("A la ruta que queda le |cFFff9922faltan %d tropas|r para el 100%%: hay que coger packs extra.", -d))
    else
        add("La ruta que queda da justo el 100%.")
    end

    if self._noForces then
        add("|cFFff9922Sin recuento oficial de tropas todavia.|r Empieza al entrar en la mazmorra.")
    end

    if debug then
        add(string.format("  [debug] pack~%d  tropas %s/%s  plan restante %s  faltan %s",
            self._pullIndex or 0,
            tostring(math.floor(self._observed or 0)), tostring(self._required or "?"),
            tostring(self._lastPlannedLeft or "?"), tostring(self._lastNeededLeft or "?")))
        add("  [debug] origen tropas: C_ScenarioInfo (oficial) · combat log no disponible")
    end

    local n = 0
    for _ in pairs(self._activeSkips) do n = n + 1 end
    add(string.format("Packs marcados para saltar: %d mob(s)%s", n,
        self._skipsFromLeader and (" · los marca " .. self._skipsFromLeader) or ""))
    if self._lastSolve and debug then
        add(string.format("  [debug] %d packs saltados · %d tropas gastadas · metodo %s",
            #(self._lastSolve.skips or {}), self._lastSolve.used or 0, self._lastSolve.method or "?"))
    end
    if self._lastExcluded and self._lastExcluded > 0 then
        add(string.format("|cFFff9922%d mob(s) sin marcar|r: son iguales a otros que si hay que matar.",
            self._lastExcluded))
    end
    if self._lastLearn and debug then
        add("  [debug] aprendizaje: " .. tostring(self._lastLearn))
    end
    if self._lastBroadcast and debug then
        add(string.format("  [debug] emision: %d ids en %d mensaje(s)",
            self._lastBroadcast.count, self._lastBroadcast.chunks))
    end
    return out
end

return EventTracker
