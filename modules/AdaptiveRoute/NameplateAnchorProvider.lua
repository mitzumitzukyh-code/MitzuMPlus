-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · NameplateAnchorProvider v1.0
--
-- UNA SOLA PREGUNTA: dado un unitToken, ¿a qué frame anclo la flecha?
--
-- Nada más. No decide a quién marcar, no crea flechas, no conoce pulls, ni
-- rutas, ni GuidanceEngine, ni MDT. Devuelve un frame y unos metadatos
-- VISUALES fabricados aquí.
--
-- POR QUÉ EXISTE
-- RouteArrows llevaba dentro la cascada de Threat Plates. Funcionaba, pero
-- ataba el addon a un addon de placas concreto: quien juega con Plater, con
-- ElvUI o con las placas de Blizzard a secas quedaba fuera. Sacar esa decisión
-- a un módulo propio permite añadir adaptadores nuevos sin volver a tocar el
-- renderizador, que es código que YA funciona en vivo.
--
-- ═════════════════════════════════════════════════════════════════════════
-- REGLA QUE MANDA: SIEMPRE HAY FLECHA
--
-- Si no se reconoce ningún addon, o el que hay ha cambiado su estructura, o
-- alguien instala mañana algo que no existe hoy, la resolución CAE a la placa
-- base de Blizzard. Puede quedar peor alineada. Aparece igual.
--
-- Lo contrario — "no reconozco el addon, no pinto" — es el fallo que hace
-- inservible una herramienta de ruta.
-- ═════════════════════════════════════════════════════════════════════════
--
-- POR PLACA, NUNCA GLOBAL
-- Que ElvUI esté cargado no significa que ElvUI controle las placas: puede
-- tener sus nameplates apagadas y llevarlas Plater. Por eso no hay ninguna
-- variable "currentProvider": se mira la ESTRUCTURA de cada placa concreta.
-- Un addon cargado no es prueba de nada; un frame con la forma esperada sí.
--
-- TAINT Y COMBATE
-- No se modifica ni un frame ajeno. Se leen campos, se pregunta GetObjectType
-- y se comprueba IsForbidden. Ningún SetParent, SetSize, SetScale ni hook
-- sobre nada que no sea nuestro. Es seguro en combate porque no toca nada.
--
-- VALORES SECRETOS
-- No se llama a ninguna API de unidad. Aquí solo entran tokens ("nameplate3"),
-- que son cadenas normales del cliente, y salen constantes de este fichero.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local NAP = {}
AR.NameplateAnchorProvider = NAP

-- Vocabulario cerrado. Todo lo que sale de este módulo sale de aquí.
local THREAT_PLATES, PLATER, ELVUI, BLIZZARD, NONE =
      "THREAT_PLATES", "PLATER", "ELVUI", "BLIZZARD", "NONE"

NAP.PROVIDERS = {
    THREAT_PLATES = THREAT_PLATES, PLATER = PLATER, ELVUI = ELVUI,
    BLIZZARD = BLIZZARD, NONE = NONE,
}

local K_TP_ANCHOR, K_TP_FRAME, K_HEALTHBAR, K_UNITFRAME, K_PLATE_BASE, K_NONE =
      "TP_ANCHOR", "TP_FRAME", "HEALTHBAR", "UNITFRAME", "PLATE_BASE", "NONE"

NAP.ANCHOR_KINDS = {
    TP_ANCHOR = K_TP_ANCHOR, TP_FRAME = K_TP_FRAME, HEALTHBAR = K_HEALTHBAR,
    UNITFRAME = K_UNITFRAME, PLATE_BASE = K_PLATE_BASE, NONE = K_NONE,
}

-- Etiqueta legible de cada combinación. Las de Threat Plates y Blizzard son
-- LAS MISMAS cadenas de antes a propósito: RouteArrows las enseña en
-- /emp arrow y hay pruebas que las verifican. Cambiarlas sería romper algo
-- que funciona por gusto.
local COMO = {
    [THREAT_PLATES] = { [K_TP_ANCHOR] = "ThreatPlates:GetAnchor",
                        [K_TP_FRAME]  = "ThreatPlates:TPFrame" },
    [PLATER]        = { [K_HEALTHBAR] = "Plater:healthBar",
                        [K_UNITFRAME] = "Plater:unitFrame" },
    [ELVUI]         = { [K_HEALTHBAR] = "ElvUI:Health",
                        [K_UNITFRAME] = "ElvUI:unitFrame" },
    [BLIZZARD]      = { [K_UNITFRAME]  = "Blizzard:UnitFrame",
                        [K_PLATE_BASE] = "Blizzard:placa" },
}

local function como(provider, kind)
    local t = COMO[provider]
    return (t and t[kind]) or (tostring(provider) .. ":" .. tostring(kind))
end

-- ─────────────────────────────────────────────────────────────────────────
-- VALIDACIÓN DE FRAMES
--
-- `if frame then` no basta. Un campo puede ser una tabla cualquiera, un
-- objeto de otro addon sin métodos de región, o un frame PROHIBIDO — de esos
-- que existen pero revientan en cuanto se les llama. Anclarse a cualquiera de
-- los tres deja un error de Lua en mitad de una llave.
--
-- Se comprueba lo mínimo que hace falta para SetPoint: que sea una región de
-- verdad y que no esté vetada. Ni una operación protegida de más.
-- ─────────────────────────────────────────────────────────────────────────
local function esAnclable(f)
    if type(f) ~= "table" then return false end
    if type(f.GetObjectType) ~= "function" then return false end
    local ok, kind = pcall(f.GetObjectType, f)
    if not ok or type(kind) ~= "string" then return false end
    -- Un frame prohibido responde a GetObjectType y falla en todo lo demás.
    if type(f.IsForbidden) == "function" then
        local okF, forb = pcall(f.IsForbidden, f)
        if okF and forb == true then return false end
    end
    -- SetPoint es literalmente lo único que se le va a pedir.
    return type(f.SetPoint) == "function" or type(f.GetCenter) == "function"
end
NAP.IsAnchorable = function(_, f) return esAnclable(f) end

-- ─────────────────────────────────────────────────────────────────────────
-- ADAPTADORES
--
-- Cada uno recibe la placa base de Blizzard y contesta dos cosas: si esta
-- placa concreta lleva su firma, y qué frame prefiere como anclaje.
--
-- Devuelven: detectado(bool), anchor(frame|nil), anchorKind
-- Detectado SIN anchor es un resultado válido y significa exactamente
-- "es mío pero su estructura no me sirve": el que llama caerá a Blizzard.
-- ─────────────────────────────────────────────────────────────────────────

-- THREAT PLATES — el único cuyo nombre de campo es inequívoco. TPFrame no lo
-- pone nadie más. Es la integración que ya estaba validada en vivo; aquí solo
-- ha cambiado de fichero.
local function adaptadorThreatPlates(plate)
    local tp = rawget(plate, "TPFrame")
    if type(tp) ~= "table" then return false end
    if type(tp.GetAnchor) == "function" then
        local ok, a = pcall(tp.GetAnchor, tp)
        if ok and esAnclable(a) then return true, a, K_TP_ANCHOR end
    end
    if esAnclable(tp) then return true, tp, K_TP_FRAME end
    return true, nil, K_NONE          -- es TP, pero roto: que caiga a Blizzard
end

-- PLATER — best-effort, y detectado por ESTRUCTURA.
--
-- Cuidado con `plate.UnitFrame.healthBar`: eso también existe en las placas de
-- Blizzard, así que como firma de Plater es una trampa. Lo que sí es suyo es
-- `unitFramePlater`, `PlaterAnchorFrame`, y el `unitFrame` en MINÚSCULA con un
-- `healthBar` dentro. Esa minúscula es la que lo separa de ElvUI, que en el
-- mismo sitio pone `Health` con mayúscula.
local function adaptadorPlater(plate)
    local uf = rawget(plate, "unitFramePlater")
    if type(uf) ~= "table" then
        local candidato = rawget(plate, "unitFrame")
        -- Solo cuenta si trae la firma de Plater. Un unitFrame a secas puede
        -- ser de ElvUI o de cualquier otro.
        if type(candidato) == "table" and type(rawget(candidato, "healthBar")) == "table" then
            uf = candidato
        end
    end

    if type(uf) == "table" then
        local hb = rawget(uf, "healthBar")
        if esAnclable(hb) then return true, hb, K_HEALTHBAR end
        if esAnclable(uf) then return true, uf, K_UNITFRAME end
        return true, nil, K_NONE
    end

    local anchor = rawget(plate, "PlaterAnchorFrame")
    if type(anchor) == "table" then
        if esAnclable(anchor) then return true, anchor, K_UNITFRAME end
        return true, nil, K_NONE
    end
    return false
end

-- ELVUI — también best-effort. ElvUI monta sus placas sobre la infraestructura
-- de Blizzard y cuelga un `unitFrame` (minúscula) de estilo oUF, con `Health`
-- en mayúscula. Si ElvUI está instalado pero con las nameplates apagadas, ese
-- campo no existe y aquí no se detecta nada: que es justo lo correcto.
local function adaptadorElvUI(plate)
    local uf = rawget(plate, "unitFrame")
    if type(uf) ~= "table" then return false end
    local health = rawget(uf, "Health")
    if type(health) ~= "table" then return false end
    if esAnclable(health) then return true, health, K_HEALTHBAR end
    if esAnclable(uf) then return true, uf, K_UNITFRAME end
    return true, nil, K_NONE
end

-- El orden importa, y no es arbitrario: primero el que tiene firma
-- inequívoca, después los que comparten el nombre `unitFrame` y se separan por
-- lo que llevan dentro. Plater antes que ElvUI porque `healthBar` es más
-- específico que `Health`.
local ADAPTADORES = {
    { name = THREAT_PLATES, fn = adaptadorThreatPlates },
    { name = PLATER,        fn = adaptadorPlater },
    { name = ELVUI,         fn = adaptadorElvUI },
}

-- Blizzard no es un adaptador más: es el suelo. Siempre contesta algo.
local function suelo(plate)
    local uf = rawget(plate, "UnitFrame")
    if type(uf) == "table" then
        local hb = rawget(uf, "healthBar")
        -- Se prefiere el UnitFrame entero y no la barra: es lo que lleva
        -- meses funcionando en vivo y está centrado sobre la placa.
        if esAnclable(uf) then return uf, K_UNITFRAME end
        if esAnclable(hb) then return hb, K_HEALTHBAR end
    end
    if esAnclable(plate) then return plate, K_PLATE_BASE end
    return nil, K_NONE
end

-- ─────────────────────────────────────────────────────────────────────────
-- CACHÉ
--
-- Guarda METADATOS, nunca frames. Un frame guardado es una referencia que
-- sobrevive a la placa y acaba anclando una flecha a algo que ya no está;
-- resolver el frame otra vez cuesta dos lecturas de campo.
--
-- Se borra en NAME_PLATE_UNIT_REMOVED, que significa "esta placa dejó de
-- verse" y NADA más. No se infiere muerte, ni salida del pull, ni nada.
-- ─────────────────────────────────────────────────────────────────────────
NAP._cache = {}
NAP._stats = { resolved = 0, cacheHits = 0, fallbacks = 0, failed = 0 }

function NAP:InvalidateToken(token)
    if type(token) ~= "string" then return false end
    if self._cache[token] == nil then return false end
    self._cache[token] = nil
    return true
end

function NAP:ClearCache()
    local n = 0
    for k in pairs(self._cache) do self._cache[k] = nil; n = n + 1 end
    return n
end

function NAP:GetCached(token)
    return self._cache[token]
end

-- ─────────────────────────────────────────────────────────────────────────
-- RESOLUCIÓN
-- ─────────────────────────────────────────────────────────────────────────

function NAP:GetPlate(unitToken)
    if type(unitToken) ~= "string" then return nil end
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unitToken)
    if not ok or type(plate) ~= "table" then return nil end
    return plate
end

-- Solo detección: qué addon controla ESTA placa y qué frame preferiría.
-- Separada de Resolve porque /emp plates quiere saber quién manda aunque el
-- jugador tenga el anclaje forzado a la placa base.
function NAP:Detect(plate)
    if type(plate) ~= "table" then return NONE, nil, K_NONE end
    for _, ad in ipairs(ADAPTADORES) do
        local ok, detectado, anchor, kind = pcall(ad.fn, plate)
        if ok and detectado then
            return ad.name, anchor, kind or K_NONE
        end
    end
    return BLIZZARD, nil, K_NONE
end

-- Devuelve: plate, anchor, meta
--
-- meta = {
--     provider   = de quién es el frame al que nos hemos anclado
--     detected   = quién controla la placa (puede diferir si el suyo falló)
--     anchorKind = qué clase de frame es
--     fallback   = true si hubo que bajar de escalón
--     forced     = true si el jugador fijó el modo a mano
--     supported  = true si hay flecha posible
--     how        = etiqueta legible
-- }
--
-- `mode`: "auto" cascada completa · "placa" siempre la base de Blizzard ·
-- "tp" fuerza Threat Plates. El default del addon es "placa" porque en el
-- cliente del usuario el anchor de Threat Plates dejaba la flecha desplazada
-- sobre el icono de amenaza; forzar la base NO es un fallo, es una elección.
function NAP:Resolve(unitToken, mode)
    self._stats.resolved = self._stats.resolved + 1

    local plate = self:GetPlate(unitToken)
    if not plate then
        self._stats.failed = self._stats.failed + 1
        return nil, nil, {
            provider = NONE, detected = NONE, anchorKind = K_NONE,
            fallback = false, forced = false, supported = false,
            how = "sin placa",
        }
    end

    local detected, preferido, kindPreferido = self:Detect(plate)

    -- Modo forzado a la placa base: se respeta sin discutir, pero se sigue
    -- informando de quién controla la placa.
    if mode == "placa" then
        -- La placa base LITERAL, no su UnitFrame: es la que está centrada, y
        -- es exactamente lo que el jugador pidió al forzar el modo.
        local anchor = esAnclable(plate) and plate or nil
        if not anchor then
            self._stats.failed = self._stats.failed + 1
            return plate, nil, {
                provider = NONE, detected = detected, anchorKind = K_NONE,
                fallback = true, forced = true, supported = false,
                how = "placa inservible",
            }
        end
        return plate, anchor, {
            provider = BLIZZARD, detected = detected, anchorKind = K_PLATE_BASE,
            fallback = false, forced = true, supported = true,
            how = "Blizzard:placa (forzado)",
        }
    end

    -- Modo "tp": solo Threat Plates. Si no está o está roto, al suelo.
    if mode == "tp" then
        local ok, det, a, k = pcall(adaptadorThreatPlates, plate)
        if ok and det and esAnclable(a) then
            return plate, a, {
                provider = THREAT_PLATES, detected = detected, anchorKind = k,
                fallback = false, forced = true, supported = true,
                how = como(THREAT_PLATES, k),
            }
        end
        preferido = nil
    elseif detected ~= BLIZZARD and esAnclable(preferido) then
        -- Camino normal: el addon que controla la placa tiene un frame válido.
        return plate, preferido, {
            provider = detected, detected = detected, anchorKind = kindPreferido,
            fallback = false, forced = false, supported = true,
            how = como(detected, kindPreferido),
        }
    end

    -- Suelo. Aquí acaban: las placas de Blizzard a pelo, los addons que no
    -- reconocemos, y los que reconocemos pero han cambiado por dentro.
    local anchor, kind = suelo(plate)
    if not anchor then
        self._stats.failed = self._stats.failed + 1
        return plate, nil, {
            provider = NONE, detected = detected, anchorKind = K_NONE,
            fallback = true, forced = false, supported = false,
            how = "placa inservible",
        }
    end

    -- `fallback` significa UNA cosa: hemos bajado de escalón. Que la placa sea
    -- de Blizzard y usemos su UnitFrame no es bajar de escalón, es el camino
    -- previsto. Que Threat Plates estuviera ahí y hayamos acabado en la placa
    -- base, sí lo es.
    local bajamos = (detected ~= BLIZZARD) or (kind == K_PLATE_BASE)
    if bajamos then self._stats.fallbacks = self._stats.fallbacks + 1 end

    return plate, anchor, {
        provider = BLIZZARD, detected = detected, anchorKind = kind,
        fallback = bajamos, forced = (mode == "tp"), supported = true,
        how = como(BLIZZARD, kind),
    }
end

-- Igual que Resolve pero apoyándose en la caché para los METADATOS. El frame
-- se vuelve a resolver siempre; lo que se ahorra es la cascada de detección.
-- Existe para /emp plates, que recorre todas las placas de golpe.
function NAP:ResolveCached(unitToken, mode)
    local plate, anchor, meta = self:Resolve(unitToken, mode)
    if meta and meta.supported then
        local prev = self._cache[unitToken]
        if prev and prev.provider == meta.provider
           and prev.anchorKind == meta.anchorKind then
            self._stats.cacheHits = self._stats.cacheHits + 1
        end
        -- Copia con solo cadenas y booleanos nuestros.
        self._cache[unitToken] = {
            provider = meta.provider, detected = meta.detected,
            anchorKind = meta.anchorKind, fallback = meta.fallback,
            forced = meta.forced, supported = meta.supported, how = meta.how,
        }
    else
        self._cache[unitToken] = nil
    end
    return plate, anchor, meta
end

-- ─────────────────────────────────────────────────────────────────────────
-- INFORME  (/emp plates)
--
-- SECRET-SAFE por construcción, no por filtrado: aquí dentro no entra ni un
-- valor de unidad. Lo único que sale son tokens de placa y constantes de este
-- fichero. No hay nada que sanear porque no hay nada ajeno.
-- ─────────────────────────────────────────────────────────────────────────

local function tokenDe(np)
    if type(np) ~= "table" then return nil end
    local t = rawget(np, "namePlateUnitToken") or rawget(np, "unitToken")
    return type(t) == "string" and t or nil
end

function NAP:ProbeAllPlates(mode)
    local out = {}
    local resumen = { total = 0, fallbacks = 0, failed = 0,
                      [THREAT_PLATES] = 0, [PLATER] = 0, [ELVUI] = 0,
                      [BLIZZARD] = 0, [NONE] = 0 }
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then
        return out, resumen, "sin API de nameplates"
    end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then
        return out, resumen, "GetNamePlates falló"
    end
    for _, np in ipairs(plates) do
        local tok = tokenDe(np)
        if tok then
            local _, _, meta = self:ResolveCached(tok, mode)
            meta.unitToken = tok
            out[#out + 1] = meta
            resumen.total = resumen.total + 1
            resumen[meta.provider] = (resumen[meta.provider] or 0) + 1
            if meta.fallback then resumen.fallbacks = resumen.fallbacks + 1 end
            if not meta.supported then resumen.failed = resumen.failed + 1 end
        end
    end
    return out, resumen
end

function NAP:StatusLines()
    local RA = AR.RouteArrows
    local mode = (RA and RA.GetOption and RA:GetOption("arrowAnchor")) or "auto"
    local metas, r, err = self:ProbeAllPlates(mode)

    local L = { "|cFFd9b33e--- nameplates ---|r",
                string.format("modo de anclaje: %s", tostring(mode)) }
    if err then
        L[#L + 1] = "|cFFff9922" .. err .. "|r"
        return L
    end
    L[#L + 1] = string.format("visible=%d", r.total)
    if r.total == 0 then
        L[#L + 1] = "|cFFff9922No hay ninguna placa visible.|r Acércate a unos mobs."
        return L
    end

    for _, m in ipairs(metas) do
        L[#L + 1] = ""
        L[#L + 1] = m.unitToken
        L[#L + 1] = "provider=" .. m.provider
        L[#L + 1] = "anchorKind=" .. m.anchorKind
        L[#L + 1] = "fallback=" .. tostring(m.fallback)
        L[#L + 1] = "supported=" .. tostring(m.supported)
        -- Solo cuando aporta: si quien manda en la placa no es de quien
        -- colgamos la flecha, hay que verlo.
        if m.detected ~= m.provider then
            L[#L + 1] = "detected=" .. m.detected
        end
        if m.forced then L[#L + 1] = "forced=true" end
    end

    L[#L + 1] = ""
    L[#L + 1] = "providers:"
    L[#L + 1] = string.format("%s=%d", PLATER, r[PLATER] or 0)
    L[#L + 1] = string.format("%s=%d", THREAT_PLATES, r[THREAT_PLATES] or 0)
    L[#L + 1] = string.format("%s=%d", ELVUI, r[ELVUI] or 0)
    L[#L + 1] = string.format("%s=%d", BLIZZARD, r[BLIZZARD] or 0)
    L[#L + 1] = ""
    L[#L + 1] = string.format("fallbacks=%d", r.fallbacks)
    L[#L + 1] = string.format("failed=%d", r.failed)
    return L
end

-- ─────────────────────────────────────────────────────────────────────────
-- EVENTOS
--
-- Frame propio. RouteArrows tiene OnNameplateAdded/Removed, pero son ganchos
-- de UNA sola función y ya los ocupa PullUnitResolver: engancharse ahí sería
-- desconectarlo. Registrar los eventos por separado no cuesta nada.
-- ─────────────────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        if type(unit) == "string" then NAP:InvalidateToken(unit) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Cambio de zona o /reload: ninguna de las placas de antes existe ya.
        NAP:ClearCache()
    end
end)

return NAP
