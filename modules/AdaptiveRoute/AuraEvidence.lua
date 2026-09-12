-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · AuraEvidence v1.0  —  FASE 3, EXPERIMENTAL
--
-- UNA SOLA PREGUNTA: ¿esta placa tiene auras, y puedo leer algún spellID?
--
-- No devuelve auras. Devuelve un estado y, como mucho, una lista corta de
-- números que se ha DEMOSTRADO que son seguros. Ni nombres, ni iconos, ni
-- duraciones, ni sourceUnit, ni la tabla original.
--
-- ═════════════════════════════════════════════════════════════════════════
-- LO QUE SE ENCONTRÓ AL INSPECCIONAR EL CLIENTE 12.1
--
-- Leído en los addons instalados que ya están adaptados a Midnight, no
-- supuesto. Existe un espacio de nombres nuevo, C_Secrets, que responde a la
-- pregunta directamente en vez de obligar a deducirla:
--
--   C_Secrets.ShouldAurasBeSecret()          -> política global de auras
--   C_Secrets.ShouldSpellAuraBeSecret(id)    -> por hechizo
--   C_Secrets.GetSpellAuraSecrecy(id)        -> Enum.SecrecyLevel.NeverSecret
--   C_Secrets.ShouldUnitIdentityBeSecret()   -> por qué el GUID llega secreto
--
-- (BetterBlizzPlates/midnight/modules/auras.lua, EnhanceQoL, SweepyBoop,
--  DandersFrames, BetterBlizzFrames. 37 usos de ShouldAurasBeSecret entre
--  ellos: no es una API oscura, es LA puerta.)
--
-- Y el modelo nuevo de Blizzard para auras secretas es un contenedor propio,
-- Blizzard_AuraContainer / CustomAuraContainerTemplate, al que el addon le
-- pasa un FILTRO y que pinta él: el addon no llega a ver los datos. Eso es lo
-- que hace pensar que enumerar auras de un enemigo devolverá poco o nada.
--
-- Por eso este módulo hace las dos cosas: PREGUNTA la política (barato y
-- concluyente) y ADEMÁS intenta enumerar (que es lo que hay que medir en
-- vivo). Si la política dice SECRET y la enumeración devuelve algo seguro,
-- quiero verlo con mis ojos antes de creérmelo.
-- ═════════════════════════════════════════════════════════════════════════
--
-- ESTO NO ES IDENTIDAD. Un spellID de aura legible no dice qué mob es. La
-- correlación spellID -> npcID no se hace aquí ni en esta fase.
--
-- TRABAJO ACOTADO: 10 auras por filtro, 20 por placa, y solo bajo demanda.
-- Ni un OnUpdate, ni un UNIT_AURA, ni un recorrido de cientos de auras.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local AuraEvidence = {}
AR.AuraEvidence = AuraEvidence

-- ─────────────────────────────────────────────────────────────────────────
-- VOCABULARIO CERRADO
-- ─────────────────────────────────────────────────────────────────────────

local AVAILABLE, NONE, UNKNOWN = "AVAILABLE", "NONE", "UNKNOWN"

AuraEvidence.STATES = { AVAILABLE = AVAILABLE, NONE = NONE, UNKNOWN = UNKNOWN }

-- Política de secreto del cliente, tal y como la contesta C_Secrets.
local POL_SECRET, POL_OPEN, POL_UNKNOWN = "SECRET", "OPEN", "UNKNOWN"
AuraEvidence.POLICIES = {
    SECRET = POL_SECRET, OPEN = POL_OPEN, UNKNOWN = POL_UNKNOWN,
}

-- Qué camino de lectura ofrece este cliente.
local BY_INDEX, BY_SLOT, NO_API = "BY_INDEX", "BY_SLOT", "NONE"
AuraEvidence.APIS = { BY_INDEX = BY_INDEX, BY_SLOT = BY_SLOT, NONE = NO_API }

local MAX_POR_FILTRO = 10
local MAX_TOTAL      = 20
local FILTROS        = { "HARMFUL", "HELPFUL" }

AuraEvidence.MAX_POR_FILTRO = MAX_POR_FILTRO
AuraEvidence.MAX_TOTAL      = MAX_TOTAL

-- ─────────────────────────────────────────────────────────────────────────
-- LECTURA SEGURA
-- ─────────────────────────────────────────────────────────────────────────

local function esValorSeguro(v)
    if v == nil then return true end
    local t = type(v)
    if t ~= "string" and t ~= "number" and t ~= "boolean" then return false end
    local iss = rawget(_G, "issecretvalue")
    if type(iss) ~= "function" then return false end
    local ok, res = pcall(iss, v)
    if not ok then return false end
    return res ~= true
end

-- ─────────────────────────────────────────────────────────────────────────
-- QUÉ OFRECE ESTE CLIENTE
--
-- Se pregunta cada vez, no al cargar: un /reload con otro parche por medio no
-- debe encontrarse una respuesta vieja cacheada.
-- ─────────────────────────────────────────────────────────────────────────

function AuraEvidence:APIStatus()
    local A = rawget(_G, "C_UnitAuras")
    if type(A) ~= "table" then return NO_API end
    if type(rawget(A, "GetAuraDataByIndex")) == "function" then return BY_INDEX end
    if type(rawget(A, "GetAuraSlots")) == "function"
       and type(rawget(A, "GetAuraDataBySlot")) == "function" then return BY_SLOT end
    return NO_API
end

-- La política global. Es la respuesta más valiosa de toda esta subfase: un
-- solo booleano del cliente vale más que veinte enumeraciones a ciegas.
function AuraEvidence:SecrecyPolicy()
    local S = rawget(_G, "C_Secrets")
    if type(S) ~= "table" then return POL_UNKNOWN end
    local fn = rawget(S, "ShouldAurasBeSecret")
    if type(fn) ~= "function" then return POL_UNKNOWN end
    local ok, v = pcall(fn)
    if not ok then return POL_UNKNOWN end
    if not esValorSeguro(v) or type(v) ~= "boolean" then return POL_UNKNOWN end
    if v == true then return POL_SECRET end
    return POL_OPEN
end

-- ─────────────────────────────────────────────────────────────────────────
-- UN spellID DE UNA AURA
--
-- El objeto de aura entra aquí y NO sale. Se le pide un campo, se comprueba,
-- y lo que se devuelve es un número o nada. Indexar puede reventar si el
-- objeto es secreto: por eso va dentro de pcall.
-- ─────────────────────────────────────────────────────────────────────────

local function idDeAura(data)
    if type(data) ~= "table" then return nil end
    local ok, id = pcall(function() return data.spellId end)
    if not ok then return nil end
    if id == nil then
        -- Algunas versiones lo escriben con I mayúscula. Se prueba, y si
        -- tampoco está, no hay ID y punto.
        local ok2, id2 = pcall(function() return data.spellID end)
        if not ok2 then return nil end
        id = id2
    end
    if id == nil then return nil end
    if not esValorSeguro(id) then return nil end
    if type(id) ~= "number" then return nil end
    return id
end

-- ─────────────────────────────────────────────────────────────────────────
-- RECORRIDOS
--
-- Devuelven: nº de auras vistas, lista de IDs seguros, y si hubo algún
-- tropiezo. "Vista" significa que el cliente devolvió un objeto, no que se
-- haya podido leer nada de él.
-- ─────────────────────────────────────────────────────────────────────────

local function recorrerPorIndice(A, unitToken, seguras)
    local vistas, duda = 0, false
    for _, filtro in ipairs(FILTROS) do
        for i = 1, MAX_POR_FILTRO do
            if vistas >= MAX_TOTAL then break end
            local ok, data = pcall(A.GetAuraDataByIndex, unitToken, i, filtro)
            if not ok then duda = true; break end
            if data == nil then break end       -- fin de la lista de este filtro
            vistas = vistas + 1
            local id = idDeAura(data)
            data = nil                          -- el objeto original muere aquí
            if id and #seguras < MAX_TOTAL then seguras[#seguras + 1] = id end
        end
    end
    return vistas, duda
end

-- OJO CON LA TUPLA: GetAuraSlots devuelve primero el token de continuación,
-- que puede ser nil, y después los slots. Recogerla con `{ pcall(...) }` deja
-- un agujero en el array y entonces `#` no está definido: se leerían de menos
-- o de más sin avisar. Por eso se desmonta con select() y una función que
-- recibe la tupla entera.
local function recorrerPorSlot(A, unitToken, seguras)
    local vistas, duda = 0, false

    local function conSlots(ok, _continuacion, ...)
        if not ok then duda = true; return end
        local n = select("#", ...)
        for i = 1, n do
            if vistas >= MAX_TOTAL then break end
            local slot = select(i, ...)
            if slot ~= nil then
                local okD, data = pcall(A.GetAuraDataBySlot, unitToken, slot)
                if not okD then
                    duda = true
                elseif data ~= nil then
                    vistas = vistas + 1
                    local id = idDeAura(data)
                    data = nil
                    if id and #seguras < MAX_TOTAL then
                        seguras[#seguras + 1] = id
                    end
                end
            end
        end
    end

    for _, filtro in ipairs(FILTROS) do
        conSlots(pcall(A.GetAuraSlots, unitToken, filtro, MAX_POR_FILTRO))
    end
    return vistas, duda
end

-- ─────────────────────────────────────────────────────────────────────────
-- UNA PLACA
--
--   AVAILABLE -> se sacó al menos un spellID seguro
--   NONE      -> el cliente contestó, y no había ninguna aura
--   UNKNOWN   -> había auras pero nada legible, o no se pudo preguntar
--
-- "Había auras y ninguna era legible" es UNKNOWN y no NONE. Son cosas
-- distintas y confundirlas sería decir "este mob no tiene debuffs" cuando lo
-- cierto es "no me dejan verlos".
-- ─────────────────────────────────────────────────────────────────────────

function AuraEvidence:Evaluate(unitToken)
    local seguras = {}
    if type(unitToken) ~= "string" then return UNKNOWN, seguras end

    local api = self:APIStatus()
    if api == NO_API then return UNKNOWN, seguras end

    local A = rawget(_G, "C_UnitAuras")
    local vistas, duda
    if api == BY_INDEX then
        vistas, duda = recorrerPorIndice(A, unitToken, seguras)
    else
        vistas, duda = recorrerPorSlot(A, unitToken, seguras)
    end

    if #seguras > 0 then return AVAILABLE, seguras end
    if vistas > 0 then return UNKNOWN, seguras end
    if duda then return UNKNOWN, seguras end
    return NONE, seguras
end

-- ─────────────────────────────────────────────────────────────────────────
-- VARIAS PLACAS
-- ─────────────────────────────────────────────────────────────────────────

function AuraEvidence:EvaluateTokens(tokens)
    local out = {}
    local resumen = { total = 0, available = 0, none = 0, unknown = 0,
                      safeSpellIDs = 0 }
    if type(tokens) ~= "table" then return out, resumen end

    for _, tok in ipairs(tokens) do
        if type(tok) == "string" then
            local st, ids = self:Evaluate(tok)
            out[tok] = { state = st, spellIDs = ids }
            resumen.total = resumen.total + 1
            if st == AVAILABLE then
                resumen.available = resumen.available + 1
            elseif st == NONE then
                resumen.none = resumen.none + 1
            else
                resumen.unknown = resumen.unknown + 1
            end
            resumen.safeSpellIDs = resumen.safeSpellIDs + #ids
        end
    end
    return out, resumen
end

return AuraEvidence
