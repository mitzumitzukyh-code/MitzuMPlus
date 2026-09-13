-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuRouteArrows · RouteSignature  —  QUÉ ESPERA LA RUTA
--
-- Traduce un pull de la ruta estática a la forma que el comparador necesita:
-- cuántas unidades y de qué npcIDs, con sus multiplicidades.
--
--   { pull = 4, mobCount = 7, npcMultiset = { [123456] = 3, [123457] = 4 } }
--
-- DE DÓNDE SALEN LOS DATOS
-- Exclusivamente de `route.pulls[i].mobs`, o sea de los ficheros empaquetados
-- en data/Routes/Season2/. Ni MDT, ni SavedVariables, ni nada vivo. Por eso
-- `tonumber` sobre estos campos es seguro: no pueden ser valores secretos,
-- igual que en RouteProgress:_BuildCache y en PackEvidence.
--
-- EL RECUENTO ES EL MISMO QUE EL DE PACKEVIDENCE, A PROPÓSITO
-- `amount`, y si no vale, `#cloneIDs`. Dos módulos que digan "este pull
-- espera 7" y "este pull espera 9" para el mismo pull son un bug esperando
-- su turno. Si se cambia aquí, hay que cambiarlo allí.
--
-- LO QUE ESTO NO ES
-- Una firma de ruta NO es identidad de nada vivo. Es el lado ESTÁTICO de la
-- comparación: lo que la ruta dice que debería haber. El lado observado lo
-- construye ExecutionEpisodeTracker, y compararlos NO produce identidad de
-- mobs: produce una hipótesis sobre en qué punto de la ruta estamos.
-- ═══════════════════════════════════════════════════════════════════════════

local MRA = _G.MitzuRouteArrows
if not MRA then return end

-- AR: los demas modulos de este mismo addon.
-- Host: fachada de SOLO LECTURA sobre MitzuMPlusAPI (Core/Host.lua).
local AR = MRA
local Host = MRA.Host

local RouteSignature = {}
AR.RouteSignature = RouteSignature

local AVAILABLE, PARTIAL, UNKNOWN = "AVAILABLE", "PARTIAL", "UNKNOWN"
RouteSignature.STATES = { AVAILABLE = AVAILABLE, PARTIAL = PARTIAL, UNKNOWN = UNKNOWN }

-- ─────────────────────────────────────────────────────────────────────────
-- LECTURA DEFENSIVA
--
-- `rawget` en todas partes: una ruta podría llegar de una importación con
-- metatabla, y leer dentro de un __index ajeno no es asunto de este módulo.
-- ─────────────────────────────────────────────────────────────────────────

local function campo(t, k)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(rawget, t, k)
    if not ok then return nil end
    return v
end

local function enteroPositivo(v)
    local n = tonumber(v)
    if type(n) ~= "number" or n <= 0 or n == math.huge or n == -math.huge then
        return nil
    end
    if n ~= math.floor(n) then return nil end
    return n
end

-- Unidades de una entrada de mob. Misma regla que PackEvidence.
local function unidadesDe(m)
    local n = enteroPositivo(campo(m, "amount"))
    if n then return n end
    local clones = campo(m, "cloneIDs")
    if type(clones) == "table" then
        local c = #clones
        if c > 0 then return c end
    end
    return nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- FIRMA DE UN PULL
-- ─────────────────────────────────────────────────────────────────────────

local function vacia(pullIndex)
    return {
        pull = pullIndex, pulls = { pullIndex },
        mobCount = nil, npcMultiset = {}, npcTypes = 0,
        entries = 0, unresolvedUnits = 0, identifiedUnits = 0,
        forcesCount = nil, noForces = false,
        state = UNKNOWN,
    }
end

function RouteSignature:ForPull(route, pullIndex)
    local idx = tonumber(pullIndex)
    local sig = vacia(idx)
    if type(route) ~= "table" or idx == nil then return sig end

    local pulls = campo(route, "pulls")
    if type(pulls) ~= "table" then return sig end
    local pull = campo(pulls, idx)
    if type(pull) ~= "table" then return sig end

    local mobs = campo(pull, "mobs")
    -- Un pull sin mobs no espera 0 enemigos: no se sabe lo que espera. El 0
    -- inventado es justo lo que haría que cualquier pull corrupto pareciera
    -- encajar con una observación vacía.
    if type(mobs) ~= "table" or #mobs == 0 then return sig end

    local total, identificadas, sinNPC = 0, 0, 0
    for i = 1, #mobs do
        local m = campo(mobs, i)
        if type(m) ~= "table" then return sig end
        local n = unidadesDe(m)
        if not n then return sig end
        sig.entries = sig.entries + 1
        total = total + n
        local npcID = enteroPositivo(campo(m, "npcID"))
        if npcID then
            sig.npcMultiset[npcID] = (sig.npcMultiset[npcID] or 0) + n
            identificadas = identificadas + n
        else
            sinNPC = sinNPC + n
        end
    end
    if total <= 0 then return sig end

    for _ in pairs(sig.npcMultiset) do sig.npcTypes = sig.npcTypes + 1 end
    sig.mobCount        = total
    sig.identifiedUnits = identificadas
    sig.unresolvedUnits = sinNPC

    -- `count` del pull son las tropas que aporta. 0 significa "este pull no
    -- da tropas": típicamente un boss, pero también basura sin valor. Se
    -- expone como dato, NO como "esto es un boss": esa lectura la hace quien
    -- compara, y con poco peso. Las rutas no traen encounterID.
    local c = tonumber(campo(pull, "count"))
    if c and c == math.floor(c) and c >= 0 then
        sig.forcesCount = c
        sig.noForces    = (c == 0)
    end

    sig.state = (sinNPC > 0) and PARTIAL or AVAILABLE
    return sig
end

-- ─────────────────────────────────────────────────────────────────────────
-- FIRMA DE UNA CADENA DE PULLS  (chain pull: 4+5)
--
-- La suma de dos pulls consecutivos es lo que se ve cuando el grupo encadena.
-- No se inventa nada: es la suma de los dos multisets.
-- ─────────────────────────────────────────────────────────────────────────

function RouteSignature:ForChain(route, indices)
    if type(indices) ~= "table" or #indices == 0 then return vacia(nil) end
    if #indices == 1 then return self:ForPull(route, indices[1]) end

    local sig = vacia(nil)
    sig.pulls = {}
    local total, identificadas, sinNPC, forces = 0, 0, 0, 0
    local peorEstado = AVAILABLE

    for _, i in ipairs(indices) do
        local uno = self:ForPull(route, i)
        if uno.state == UNKNOWN or not uno.mobCount then return vacia(nil) end
        if uno.state == PARTIAL then peorEstado = PARTIAL end
        sig.pulls[#sig.pulls + 1] = uno.pull
        sig.entries = sig.entries + uno.entries
        total = total + uno.mobCount
        identificadas = identificadas + uno.identifiedUnits
        sinNPC = sinNPC + uno.unresolvedUnits
        forces = forces + (uno.forcesCount or 0)
        for npcID, n in pairs(uno.npcMultiset) do
            sig.npcMultiset[npcID] = (sig.npcMultiset[npcID] or 0) + n
        end
    end

    for _ in pairs(sig.npcMultiset) do sig.npcTypes = sig.npcTypes + 1 end
    sig.pull            = sig.pulls[1]
    sig.mobCount        = total
    sig.identifiedUnits = identificadas
    sig.unresolvedUnits = sinNPC
    sig.forcesCount     = forces
    sig.noForces        = (forces == 0)
    sig.state           = peorEstado
    return sig
end

-- Etiqueta estable para logs y comparaciones: "4" o "4+5".
function RouteSignature:Label(sig)
    if type(sig) ~= "table" or type(sig.pulls) ~= "table" or #sig.pulls == 0 then
        return "-"
    end
    local partes = {}
    for _, p in ipairs(sig.pulls) do partes[#partes + 1] = tostring(p) end
    return table.concat(partes, "+")
end

-- ─────────────────────────────────────────────────────────────────────────
-- DIAGNÓSTICO
-- ─────────────────────────────────────────────────────────────────────────

function RouteSignature:Lines(route, pullIndex)
    local sig = self:ForPull(route, pullIndex)
    local L = {
        string.format("pull=%s state=%s mobCount=%s entries=%d",
            tostring(sig.pull), sig.state, tostring(sig.mobCount), sig.entries),
        string.format("npcTypes=%d identifiedUnits=%d unresolvedUnits=%d forcesCount=%s",
            sig.npcTypes, sig.identifiedUnits, sig.unresolvedUnits,
            tostring(sig.forcesCount)),
    }
    local ids = {}
    for npcID in pairs(sig.npcMultiset) do ids[#ids + 1] = npcID end
    table.sort(ids)
    for _, npcID in ipairs(ids) do
        L[#L + 1] = string.format("  npcID=%d x%d", npcID, sig.npcMultiset[npcID])
    end
    return L
end

return RouteSignature
