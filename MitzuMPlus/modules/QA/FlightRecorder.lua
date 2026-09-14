-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · QA/FlightRecorder  —  caja negra de alto nivel
--
-- Para poder jugar una llave entera sin escribir diez comandos y, al final,
-- entregar UN informe (/emp bugreport) que cuente qué pasó.
--
-- QUÉ REGISTRA: solo hechos de MitzuMPlus, ya decididos por sus autoridades
-- (transiciones de DungeonContext, sesión, run, tracker y errores).
-- QUÉ NO REGISTRA: combat log, unidades, placas, nada por frame. No es CLEU y
-- no intenta reconstruirlo.
--
-- FORMA: anillo de tamaño fijo. Escribir es O(1) y nunca crece: una llave de
-- 40 minutos no puede llenar las SavedVariables. Entradas idénticas seguidas
-- se funden en una con contador.
--
-- PERSISTENCIA: el anillo vive en MitzuMPlusDB.global.qaFlight, así que
-- sobrevive al /reload, que es justo el momento que más interesa ver. Hasta
-- que la base de datos existe se escribe en memoria y se vuelca al conectar.
-- Un anillo guardado con forma inválida se descarta (y se anota), nunca rompe.
--
-- El recorder es observador: no llama a ningún escritor de ninguna autoridad.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local FR = {}
MitzuMPlus.FlightRecorder = FR

FR.CAPACITY = 200
FR.SCHEMA   = 1

local function Safe() return MitzuMPlus.QASafe end
local function epoch() return (time and time()) or 0 end
local function mono()
    local ok, v = pcall(function() return GetTime and GetTime() end)
    return (ok and tonumber(v)) or 0
end

local function nuevoAnillo(cap)
    return { schema = FR.SCHEMA, cap = cap, head = 0, count = 0, entries = {} }
end

-- Un anillo válido tiene los números en rango. Cualquier otra cosa se descarta.
local function anilloValido(r)
    if type(r) ~= "table" or r.schema ~= FR.SCHEMA then return false end
    if type(r.entries) ~= "table" then return false end
    local cap, head, count = tonumber(r.cap), tonumber(r.head), tonumber(r.count)
    if not cap or not head or not count then return false end
    if cap < 1 or head < 0 or head >= cap or count < 0 or count > cap then return false end
    return true
end

FR._ring     = nuevoAnillo(FR.CAPACITY)
FR._attached = false
FR._session  = 0

local function empujar(ring, entry)
    local last = ring.count > 0 and ring.entries[ring.head + 1] or nil
    if last and last.s == entry.s and last.e == entry.e and last.d == entry.d then
        last.n = (last.n or 1) + 1
        last.t2 = entry.t
        return
    end
    ring.head = ring.count == 0 and 0 or ((ring.head + 1) % ring.cap)
    ring.entries[ring.head + 1] = entry
    if ring.count < ring.cap then ring.count = ring.count + 1 end
end

-- Datos compactos "k=v k=v" con los valores saneados y las claves ordenadas,
-- para que dos entradas iguales den el mismo texto y se fundan.
local function compacto(data)
    if data == nil then return "" end
    local S = Safe()
    if type(data) ~= "table" then return S and S.Text(data, 160) or "" end
    local keys = {}
    for k in pairs(data) do
        if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = tostring(k) .. "=" .. (S and S.Text(data[k], 60) or "?")
    end
    local out = table.concat(parts, " ")
    if #out > 200 then out = out:sub(1, 200) .. "..." end
    return out
end

-- Anota un hecho. Nunca lanza: una caja negra que se rompe no sirve de nada.
function FR:Record(subsystem, event, data)
    pcall(function()
        local S = Safe()
        local entry = {
            t = epoch(),
            u = math.floor(mono() * 10) / 10,
            s = S and S.Text(subsystem, 24) or tostring(subsystem),
            e = S and S.Text(event, 40) or tostring(event),
            d = compacto(data),
        }
        empujar(self._ring, entry)
        if not self._attached then self:Attach() end
    end)
end

-- Conecta el anillo con las SavedVariables. Idempotente.
function FR:Attach()
    if self._attached then return true end
    local g = MitzuMPlus.db and MitzuMPlus.db.global
    if type(g) ~= "table" then return false end

    local previo = g.qaFlight
    local pendiente = self._ring
    local descartado = false
    if anilloValido(previo) then
        -- Si la capacidad cambió entre versiones, se rehace respetando el orden.
        if previo.cap ~= FR.CAPACITY then
            local lista = self:_Entries(previo)
            previo = nuevoAnillo(FR.CAPACITY)
            for _, e in ipairs(lista) do empujar(previo, e) end
        end
    else
        descartado = previo ~= nil
        previo = nuevoAnillo(FR.CAPACITY)
    end
    g.qaFlight = previo
    self._ring = previo
    self._attached = true
    self._session = (tonumber(previo.session) or 0) + 1
    previo.session = self._session

    empujar(previo, { t = epoch(), u = math.floor(mono() * 10) / 10, s = "QA",
                      e = "SESSION_START", d = "session=" .. self._session })
    if descartado then
        empujar(previo, { t = epoch(), u = 0, s = "QA", e = "WARN_RING_DISCARDED",
                          d = "reason=invalid_saved_shape" })
    end
    for _, e in ipairs(self:_Entries(pendiente)) do empujar(previo, e) end
    return true
end

-- Entradas en orden cronológico (la más antigua primero).
function FR:_Entries(ring)
    ring = ring or self._ring
    local out = {}
    if not anilloValido(ring) then return out end
    local start = ring.count < ring.cap and 0 or ((ring.head + 1) % ring.cap)
    for i = 0, ring.count - 1 do
        local e = ring.entries[((start + i) % ring.cap) + 1]
        if type(e) == "table" then out[#out + 1] = e end
    end
    return out
end

function FR:Entries() return self:_Entries(self._ring) end
function FR:Count() return self._ring and self._ring.count or 0 end
function FR:Capacity() return self._ring and self._ring.cap or FR.CAPACITY end

function FR:Clear()
    local ring = nuevoAnillo(FR.CAPACITY)
    ring.session = self._session
    self._ring = ring
    local g = MitzuMPlus.db and MitzuMPlus.db.global
    if self._attached and type(g) == "table" then g.qaFlight = ring end
    empujar(ring, { t = epoch(), u = 0, s = "QA", e = "CLEARED", d = "" })
    return true
end

-- Últimas `n` entradas como "hh:mm:ss +sesion ; SUBSISTEMA ; EVENTO ; datos".
-- Separador ";" y no "|": en la caja de copia de WoW "|" es un escape.
function FR:Lines(n)
    local lista = self:Entries()
    n = tonumber(n) or #lista
    local desde = math.max(1, #lista - n + 1)
    local out = {}
    for i = desde, #lista do
        local e = lista[i]
        local hora = "--:--:--"
        if date and tonumber(e.t) and e.t > 0 then
            local ok, h = pcall(date, "%H:%M:%S", e.t)
            if ok and type(h) == "string" then hora = h end
        end
        local rep = (tonumber(e.n) or 1) > 1 and (" x" .. e.n) or ""
        -- Hora de reloj + segundos de sesion (GetTime): la hora se repite dentro
        -- del mismo segundo; el tiempo de sesion ordena sin ambiguedad.
        out[#out + 1] = string.format("%s +%.1f ; %s ; %s%s ; %s", hora, tonumber(e.u) or 0,
            tostring(e.s), tostring(e.e), rep, tostring(e.d or ""))
    end
    return out
end

-- ─────────────────────────────────────────────────────────────────────────
-- SUSCRIPCIONES
--
-- Prioridad 1000, por encima de todo el core (10-90): la CAUSA se anota antes
-- que sus efectos. Un evento del bus dispara otros anidados (entrar en RUNNING
-- Anotando al principio, el informe se lee en el orden causal.
--
-- DungeonContext emite primero el evento de la llave (MITZU_KEY_STARTED...) y
-- después MITZU_DUNGEON_STATE_CHANGED, así que la transición se anota en el
-- primero que llegue y se ignora el duplicado.
-- ─────────────────────────────────────────────────────────────────────────

local ultimaTransicion = nil
local function anotarTransicion()
    local DC = MitzuMPlus.DungeonContext
    local t = DC and rawget(DC, "_lastTransition")
    if not t or t == ultimaTransicion then return end
    ultimaTransicion = t
    FR:Record("LIFECYCLE", "TRANSITION", {
        from = rawget(DC, "_previousState"), to = rawget(DC, "_state"),
        why = tostring(t):match("%((.*)%)$"),
    })
end

local bus = MitzuMPlus.EventBus
if bus and bus.On then
    local P = 1000
    for _, ev in ipairs({ "MITZU_PRE_KEY", "MITZU_KEY_STARTED", "MITZU_KEY_COMPLETED",
                          "MITZU_KEY_RESET", "MITZU_DUNGEON_STATE_CHANGED" }) do
        bus:On(ev, anotarTransicion, P)
    end
    bus:On("MITZU_DUNGEON_CHANGED", function(key, prev)
        local DC = MitzuMPlus.DungeonContext
        FR:Record("DUNGEON", "RECOGNIZED", { key = key, prev = prev,
            source = DC and DC.GetIdentitySource and DC:GetIdentitySource() or nil })
    end, P)
    bus:On("RUN_STARTED", function(run)
        FR:Record("RUN", "CHALLENGE_STARTED", {
            level = type(run) == "table" and (run.keyLevel or run.level) or nil })
    end, P)
    bus:On("RUN_COMPLETED", function() FR:Record("RUN", "COMPLETED") end, P)
    bus:On("RUN_RESET", function() FR:Record("RUN", "RESET") end, P)
    bus:On("RUN_TEARDOWN", function(reason) FR:Record("RUN", "TEARDOWN", { reason = reason }) end, P)
end

return FR
