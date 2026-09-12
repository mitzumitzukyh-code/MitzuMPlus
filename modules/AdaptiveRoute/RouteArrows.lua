-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · RouteArrows v1.0
--
-- RENDERIZADOR Y NADA MÁS.
--
-- Pone una flecha flotante encima de la placa de una unidad. No sabe qué es un
-- pull, ni un npcID, ni un cloneIdx, ni MDT. Su API entera es:
--     RouteArrows:MarkUnit(unitToken)
--     RouteArrows:UnmarkUnit(unitToken)
--     RouteArrows:RefreshUnit(unitToken)
--     RouteArrows:ClearAll()
-- Quien decide A QUÉ unidad se le pone flecha vive fuera (PullUnitResolver, en
-- su momento). Esa separación es deliberada: el problema "qué clones son del
-- pull" y el problema "qué placa viva es ese clon" son distintos, y mezclarlos
-- fue lo que hizo intratable el sistema [SKIP] anterior.
--
-- POR QUÉ NO ES UNA EVOLUCIÓN DE NameplateHooks
-- Aquel módulo decidía QUÉ marcar leyendo UnitGUID -> strsplit -> npcID. En
-- Midnight eso es, en el mejor caso, un dato que puede venir secreto, y en el
-- peor una identidad equivocada: el mismo npcID aparece en varios pulls y
-- todas sus copias se marcaban por igual. Aquí no se mira el GUID ni una vez.
--
-- LO QUE SÍ SE RECICLA DE NameplateHooks (ideas que estaban bien):
--   · NAME_PLATE_UNIT_ADDED / REMOVED como único motor. Cero OnUpdate.
--   · C_NamePlate.GetNamePlateForUnit para localizar la placa.
--   · Detectar la estructura de la placa en vez de suponerla. Eso ahora vive
--     en NameplateAnchorProvider, que cubre TP, Plater, ElvUI y Blizzard.
--   · Regiones PROPIAS: nunca se escribe sobre nada de otro addon.
--   · Limpieza al reciclarse la placa.
--   · StatusLines para diagnóstico.
--
-- TAINT
-- No se llama a ninguna función protegida. Se crea un frame propio, se le hace
-- SetParent al nameplate y SetPoint contra el frame de anclaje. Leer
-- GetFrameLevel y anclarse a un frame ajeno no requiere permisos.
--
-- VALORES SECRETOS
-- Este módulo no lee UnitGUID, no llama a UnitName, no compara ni concatena
-- nada que venga de una unidad. Solo maneja tokens ("nameplate3"), que son
-- cadenas normales generadas por el cliente.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local RouteArrows = {}
AR.RouteArrows = RouteArrows

-- ─────────────────────────────────────────────────────────────────────────
-- AJUSTES
-- ─────────────────────────────────────────────────────────────────────────

-- Valores confirmados en el cliente del usuario (2026-09-08): 56 se lee bien
-- sin tapar la placa, y "placa" centra — el anchor de Threat Plates dejaba la
-- flecha desplazada a la derecha, encima del icono de amenaza.
local DEFAULTS = {
    arrowSize    = 56,     -- ALTURA en pixeles. El ancho sale de la proporcion
                           -- real del atlas, ver applySize().
    arrowOffsetX = 0,
    arrowOffsetY = 8,
    arrowAlpha   = 1,
    arrowAnimate = true,
    -- "auto"  = Threat Plates si esta, Blizzard si no
    -- "placa" = siempre el nameplate base de Blizzard, que esta centrado
    -- "tp"    = forzar el anclaje de Threat Plates
    arrowAnchor  = "placa",
}

-- Los ajustes viven en la DB del ProfileManager, pero este módulo tiene que
-- poder funcionar aunque la DB aún no esté (por ejemplo antes de ADDON_LOADED,
-- o en una prueba en seco). De ahí la caída a DEFAULTS en vez de un error.
-- Migración puntual del tamaño por defecto.
--
-- El primer default fue 28 px y en vivo se veía perdido sobre la placa: el
-- atlas no es cuadrado, así que de esos 28 solo una parte era flecha. Subirlo
-- en DEFAULTS no basta, porque la fusión del ProfileManager solo rellena
-- huecos y quien ya cargó el addon tiene el 28 escrito en la DB. Se sube solo
-- a quien tenga exactamente el valor viejo, y se marca para no volver a
-- hacerlo si mañana elige 28 a propósito.
-- V3 hace lo mismo con la segunda tanda: 40 px y anclaje "auto" fueron
-- defaults intermedios que en pantalla no valian. Cada escalon comprueba su
-- valor exacto, asi que una eleccion del jugador nunca se pisa.
local function migrateOnce(st)
    if not st then return end
    if not st.arrowDefaultsV2 then
        st.arrowDefaultsV2 = true
        if st.arrowSize == 28 then st.arrowSize = 40 end
    end
    if not st.arrowDefaultsV3 then
        st.arrowDefaultsV3 = true
        if st.arrowSize == 40 then st.arrowSize = DEFAULTS.arrowSize end
        if st.arrowAnchor == "auto" or st.arrowAnchor == nil then
            st.arrowAnchor = DEFAULTS.arrowAnchor
        end
    end
end

local function settings()
    local PM = AR.ProfileManager
    local st = PM and PM.Settings and PM:Settings() or nil
    if st then migrateOnce(st) end
    return st
end

local function cfg(key)
    local st = settings()
    local v = st and st[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

RouteArrows._active = {}   -- [unitToken] = arrow
RouteArrows._free   = {}   -- pila de arrows libres
RouteArrows._debug  = false
RouteArrows._stats  = { created = 0, acquired = 0, released = 0, refused = 0 }
RouteArrows._art    = nil  -- se resuelve la primera vez que hace falta
RouteArrows._lastAnchor = "sin resolver"

-- Ganchos opcionales para módulos de fase posterior (PullUnitResolver). Este
-- módulo los llama pero no los define: sigue sin decidir nada, solo avisa de
-- que una placa entró o salió.
RouteArrows.OnNameplateAdded   = nil   -- function(unitToken)
RouteArrows.OnNameplateRemoved = nil   -- function(unitToken)

local function dbg(fmt, ...)
    if not RouteArrows._debug then return end
    if not MitzuMPlus.Print then return end
    MitzuMPlus:Print("|cFF8fd3ff[RouteArrows]|r " .. string.format(fmt, ...))
end

-- ─────────────────────────────────────────────────────────────────────────
-- ARTE DE LA FLECHA
--
-- No puedo comprobar desde fuera del juego qué atlas existe en 12.1, así que
-- en vez de elegir uno a ciegas se PREGUNTA al cliente: C_Texture.GetAtlasInfo
-- devuelve nil para un atlas inexistente. El primero que conteste, se usa.
--
-- Si no contesta ninguno se cae a un rombo sólido dibujado con un color plano
-- rotado 45 grados. Es feo, pero SIEMPRE se ve: para la fase 1 lo que importa
-- es poder distinguir "el atlas elegido no existe" de "el render no funciona".
-- /emp arrow debug dice cuál de las dos vías está en uso.
-- ─────────────────────────────────────────────────────────────────────────

local ATLAS_CANDIDATES = {
    "NPE_ArrowDown",
    "NPE_ArrowDownGlow",
    "Navigation-Tracked-Arrow",
    "Waypoint-MapPin-Untracked",
    "CovenantSanctum-Renown-Next-Arrow",
}

local function resolveArt()
    if RouteArrows._art then return RouteArrows._art end
    local info = C_Texture and C_Texture.GetAtlasInfo
    if info then
        for _, name in ipairs(ATLAS_CANDIDATES) do
            local ok, data = pcall(info, name)
            if ok and data then
                -- El ancho y el alto reales del atlas se guardan aquí: son lo
                -- que evita deformar la flecha al escalarla.
                RouteArrows._art = {
                    kind  = "atlas",
                    value = name,
                    w     = tonumber(data.width),
                    h     = tonumber(data.height),
                }
                return RouteArrows._art
            end
        end
    end
    RouteArrows._art = { kind = "solido", value = "rombo" }
    return RouteArrows._art
end

local function paint(tex)
    local art = resolveArt()
    if art.kind == "atlas" then
        local ok = pcall(tex.SetAtlas, tex, art.value, false)
        if ok then
            tex:SetRotation(0)
            tex:SetVertexColor(1, 1, 1, 1)
            return
        end
        -- El atlas existía al preguntar pero SetAtlas falló: se degrada en vez
        -- de dejar una textura en blanco que parecería un fallo de anclaje.
        RouteArrows._art = { kind = "solido", value = "rombo" }
    end
    tex:SetTexture(nil)
    tex:SetColorTexture(1, 0.82, 0.25, 1)
    tex:SetRotation(math.rad(45))
end

-- POR QUÉ EL TAMAÑO NO ES UN CUADRADO
--
-- La textura hace SetAllPoints sobre el frame, así que un frame cuadrado
-- estira el atlas a cuadrado. NPE_ArrowDown no lo es: forzarlo deformaba la
-- flecha y, sobre todo, dejaba la punta visible más baja que los píxeles
-- pedidos — de ahí que 28 se viera diminuto en la placa.
--
-- `arrowSize` es la ALTURA. El ancho sale de la proporción real que el propio
-- cliente declara en GetAtlasInfo. Sin datos de atlas (rombo sólido) se
-- mantiene el cuadrado, que ahí sí es la forma correcta.
local function applySize(f, size)
    size = tonumber(size) or DEFAULTS.arrowSize
    local art = resolveArt()
    local w = size
    if art.kind == "atlas" and art.w and art.h and art.w > 0 and art.h > 0 then
        w = size * (art.w / art.h)
    end
    f:SetSize(w, size)
end

-- ─────────────────────────────────────────────────────────────────────────
-- TOKENS Y ANCLAJE
-- ─────────────────────────────────────────────────────────────────────────

-- Volcado real del cliente (ver NameplateHooks, BUG NP-1): las placas exponen
-- `unitToken`, no siempre `namePlateUnitToken`. Se prueban los dos.
local function unitTokenOf(np)
    if type(np) ~= "table" then return nil end
    local t = np.namePlateUnitToken or np.unitToken
    if type(t) == "string" then return t end
    if type(np.GetUnit) == "function" then
        local ok, u = pcall(np.GetUnit, np)
        if ok and type(u) == "string" then return u end
    end
    return nil
end

-- La clave del pool tiene que ser el token de PLACA, no el que llegó.
--
-- Si se guardase "target" como clave, NAME_PLATE_UNIT_REMOVED (que siempre
-- llega con "nameplateN") jamás encontraría la entrada y la flecha quedaría
-- colgada: exactamente el bug fantasma que hay que evitar. Se traduce con
-- UnitIsUnit, que devuelve un booleano y no toca GUIDs ni valores secretos.
local function nameplateTokenFor(unit)
    if type(unit) ~= "string" then return nil end
    if unit:match("^nameplate%d+$") then return unit end
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return nil end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return nil end
    for _, np in ipairs(plates) do
        local tok = unitTokenOf(np)
        if tok then
            local okCmp, res = pcall(UnitIsUnit, unit, tok)
            if okCmp and res == true then return tok end
        end
    end
    return nil
end

-- Devuelve: placa base de Blizzard, frame al que anclar, y cómo se resolvió.
--
-- EL "QUÉ FRAME USO" YA NO VIVE AQUÍ. Lo decide NameplateAnchorProvider, que
-- sabe de Threat Plates, Plater, ElvUI y de las placas de Blizzard a secas.
-- Este módulo no debe aprender ni una línea específica de ningún addon de
-- placas: si mañana hay que soportar uno nuevo, se añade un adaptador allí y
-- este fichero no se toca.
--
-- El PADRE sigue siendo siempre la placa de Blizzard, nunca un frame interno
-- ajeno. Así la flecha sobrevive cuando el addon de turno esconde el UnitFrame
-- de Blizzard, y no hereda alpha ni escalas de nadie. El frame del provider se
-- usa solo como REFERENCIA de posición.
--
-- `mode` ("auto" / "placa" / "tp") se pasa tal cual al provider.
--
-- SI EL PROVIDER NO ESTÁ CARGADO se resuelve la placa base de Blizzard aquí
-- mismo. No es un segundo sistema de anclaje: son cuatro líneas para que un
-- fallo de orden de carga cueste una flecha peor centrada y no cero flechas.
local function anchorFor(unit, mode)
    local NAP = AR.NameplateAnchorProvider
    if NAP and type(NAP.Resolve) == "function" then
        local ok, plate, anchor, meta = pcall(function()
            return NAP:Resolve(unit, mode)
        end)
        if ok then
            local how = (type(meta) == "table" and meta.how) or "sin resolver"
            if plate and anchor then return plate, anchor, how end
            return nil, nil, how
        end
        -- El provider ha reventado. Se sigue, no se abandona.
    end

    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
        return nil, nil, "sin API de nameplates"
    end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or type(plate) ~= "table" then return nil, nil, "sin placa" end
    local uf = plate.UnitFrame
    if type(uf) == "table" and type(uf.GetObjectType) == "function" then
        return plate, uf, "Blizzard:UnitFrame (sin provider)"
    end
    return plate, plate, "Blizzard:placa (sin provider)"
end

-- ─────────────────────────────────────────────────────────────────────────
-- POOL
--
-- WoW recicla las placas y los tokens. Crear y destruir frames por cada mob
-- que entra y sale de rango es exactamente lo que no hay que hacer, así que
-- los arrows se prestan y se devuelven. Un frame de WoW no se puede destruir
-- de todas formas: sin pool solo crecerían para siempre.
-- ─────────────────────────────────────────────────────────────────────────

local function buildArrow()
    local f = CreateFrame("Frame", nil, UIParent)
    f:Hide()

    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(f)
    paint(tex)
    f.tex = tex
    applySize(f, DEFAULTS.arrowSize)

    -- Animación por AnimationGroup, no por OnUpdate: la mueve el motor del
    -- cliente y no cuesta un tick de Lua por frame y por flecha.
    local ag = f:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local up = ag:CreateAnimation("Translation")
    up:SetOffset(0, 4)
    up:SetDuration(0.55)
    up:SetOrder(1)
    up:SetSmoothing("IN_OUT")
    local down = ag:CreateAnimation("Translation")
    down:SetOffset(0, -4)
    down:SetDuration(0.55)
    down:SetOrder(2)
    down:SetSmoothing("IN_OUT")
    f.anim = ag

    RouteArrows._stats.created = RouteArrows._stats.created + 1
    return f
end

local function acquire()
    local f = table.remove(RouteArrows._free)
    if not f then f = buildArrow() end
    RouteArrows._stats.acquired = RouteArrows._stats.acquired + 1
    return f
end

-- Devolver al pool es el punto donde se evita la flecha fantasma. Hay que
-- dejar el frame como recién creado: sin animación corriendo, sin puntos de
-- anclaje al frame viejo y sin padre reciclable.
local function release(f)
    if not f then return end
    if f.anim then pcall(f.anim.Stop, f.anim) end
    f:Hide()
    f:ClearAllPoints()
    f:SetParent(UIParent)
    f.unit = nil
    RouteArrows._free[#RouteArrows._free + 1] = f
    RouteArrows._stats.released = RouteArrows._stats.released + 1
end

-- ─────────────────────────────────────────────────────────────────────────
-- API PÚBLICA
-- ─────────────────────────────────────────────────────────────────────────

function RouteArrows:IsEnabled()
    local PM = AR.ProfileManager
    local st = PM and PM.Settings and PM:Settings() or nil
    -- Migración no destructiva: quien nunca haya tocado el ajuste lo tiene a
    -- nil, y eso significa activado.
    if st and st.routeArrowsEnabled == false then return false end
    return true
end

function RouteArrows:MarkUnit(unit)
    if not self:IsEnabled() then
        self._stats.refused = self._stats.refused + 1
        dbg("marcado ignorado: routeArrowsEnabled = false")
        return false, "desactivado"
    end

    local token = nameplateTokenFor(unit)
    if not token then
        self._stats.refused = self._stats.refused + 1
        dbg("sin token de placa para %s (sin nameplate visible)", tostring(unit))
        return false, "sin placa visible"
    end

    local plate, anchor, how = anchorFor(token, cfg("arrowAnchor"))
    if not plate or not anchor then
        self._stats.refused = self._stats.refused + 1
        dbg("token %s sin placa: %s", token, tostring(how))
        return false, how
    end
    self._lastAnchor = how
    dbg("placa encontrada para %s · anchor = %s", token, how)

    local f = self._active[token]
    if not f then
        f = acquire()
        self._active[token] = f
        dbg("arrow acquired para %s", token)
    end
    f.unit = token

    f:SetParent(plate)
    f:ClearAllPoints()

    applySize(f, cfg("arrowSize"))
    f:SetAlpha(tonumber(cfg("arrowAlpha")) or DEFAULTS.arrowAlpha)

    -- Por encima de todo lo que haya en la placa, sea de Blizzard o de TP.
    local lvl = 0
    if type(plate.GetFrameLevel) == "function" then
        lvl = math.max(lvl, plate:GetFrameLevel() or 0)
    end
    if type(anchor.GetFrameLevel) == "function" then
        lvl = math.max(lvl, anchor:GetFrameLevel() or 0)
    end
    pcall(f.SetFrameLevel, f, lvl + 10)

    local offX = tonumber(cfg("arrowOffsetX")) or DEFAULTS.arrowOffsetX
    local offY = tonumber(cfg("arrowOffsetY")) or DEFAULTS.arrowOffsetY
    local okPoint = pcall(f.SetPoint, f, "BOTTOM", anchor, "TOP", offX, offY)
    if not okPoint then
        -- El anchor devuelto no servía para SetPoint. Se cae a la placa base,
        -- que siempre es un frame de verdad, antes que dejar la flecha suelta.
        f:ClearAllPoints()
        pcall(f.SetPoint, f, "BOTTOM", plate, "TOP", offX, offY)
        self._lastAnchor = how .. " (rechazado, usando la placa)"
        dbg("anchor rechazado por SetPoint, usando la placa base")
    end

    paint(f.tex)
    f:Show()
    if cfg("arrowAnimate") ~= false then
        pcall(f.anim.Play, f.anim)
    else
        pcall(f.anim.Stop, f.anim)
    end
    dbg("arrow shown en %s · arte = %s", token, resolveArt().kind)
    return true, token
end

function RouteArrows:UnmarkUnit(unit)
    local token = nameplateTokenFor(unit) or unit
    local f = self._active[token]
    if not f then return false end
    self._active[token] = nil
    release(f)
    dbg("arrow liberado de %s", tostring(token))
    return true
end

function RouteArrows:RefreshUnit(unit)
    local token = nameplateTokenFor(unit) or unit
    if not self._active[token] then return false end
    return self:MarkUnit(token)
end

-- Repinta y recoloca todas las flechas visibles. Existe para que cambiar un
-- ajuste se vea AL MOMENTO: sin esto habría que perder y recuperar cada placa
-- para que el tamaño nuevo entrase, que es justo lo que hace inutilizable un
-- comando de ajuste.
function RouteArrows:RefreshAll()
    local tokens = {}
    for token in pairs(self._active) do tokens[#tokens + 1] = token end
    for _, token in ipairs(tokens) do self:MarkUnit(token) end
    return #tokens
end

-- ─────────────────────────────────────────────────────────────────────────
-- AJUSTES EN CALIENTE
--
-- Los límites no son decorativos: un tamaño de 5000 o un alpha negativo dejan
-- la placa inservible y el jugador sin forma obvia de volver atrás. Se validan
-- aquí y no en el comando, para que cualquier UI futura herede la validación.
-- ─────────────────────────────────────────────────────────────────────────

local OPTIONS = {
    arrowSize    = { min = 10,   max = 120, etiqueta = "tamaño"    },
    arrowOffsetX = { min = -150, max = 150, etiqueta = "offset X"  },
    arrowOffsetY = { min = -150, max = 150, etiqueta = "offset Y"  },
    arrowAlpha   = { min = 0.1,  max = 1,   etiqueta = "opacidad"  },
}

function RouteArrows:GetOption(key)
    return cfg(key)
end

-- Traducir "target" (o cualquier token) al token de placa es útil fuera de
-- aquí: PullUnitResolver necesita la misma clave estable para sus anotaciones.
-- Se expone la función que ya se usa por dentro en vez de que cada módulo se
-- escriba la suya y acaben divergiendo.
function RouteArrows:TokenFor(unit)
    return nameplateTokenFor(unit)
end

function RouteArrows:SetOption(key, value)
    local rule = OPTIONS[key]
    if not rule then return false, "ajuste desconocido" end
    local v = tonumber(value)
    if not v then return false, "eso no es un número" end
    if v < rule.min or v > rule.max then
        return false, string.format("%s fuera de rango (%s a %s)",
            rule.etiqueta, tostring(rule.min), tostring(rule.max))
    end
    local st = settings()
    if not st then return false, "la DB de ajustes aún no está lista" end
    st[key] = v
    self:RefreshAll()
    return true, v
end

function RouteArrows:SetAnchorMode(mode)
    if mode ~= "auto" and mode ~= "placa" and mode ~= "tp" then
        return false, "modos válidos: auto, placa, tp"
    end
    local st = settings()
    if not st then return false, "la DB de ajustes aún no está lista" end
    st.arrowAnchor = mode
    self:RefreshAll()
    return true, mode
end

function RouteArrows:ToggleAnimate()
    local st = settings()
    if not st then return nil, "la DB de ajustes aún no está lista" end
    st.arrowAnimate = not (st.arrowAnimate ~= false)
    self:RefreshAll()
    return st.arrowAnimate
end

function RouteArrows:ResetOptions()
    local st = settings()
    if not st then return false, "la DB de ajustes aún no está lista" end
    for k, v in pairs(DEFAULTS) do st[k] = v end
    self:RefreshAll()
    return true
end

function RouteArrows:ClearAll()
    local n = 0
    for token, f in pairs(self._active) do
        self._active[token] = nil
        release(f)
        n = n + 1
    end
    dbg("ClearAll: %d flechas liberadas", n)
    return n
end

function RouteArrows:IsMarked(unit)
    local token = nameplateTokenFor(unit) or unit
    return self._active[token] ~= nil
end

function RouteArrows:CountActive()
    local n = 0
    for _ in pairs(self._active) do n = n + 1 end
    return n
end

-- Marca todas las placas visibles. Es una herramienta de DEPURACIÓN: demuestra
-- que la capa visual funciona sin MDT, sin npcIDs y sin resolver. No la usa
-- ningún camino de producción.
function RouteArrows:DebugMarkAllPlates()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return 0, 0 end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return 0, 0 end
    local n = 0
    for _, np in ipairs(plates) do
        local tok = unitTokenOf(np)
        if tok and self:MarkUnit(tok) then n = n + 1 end
    end
    return n, #plates
end

function RouteArrows:SetDebug(on)
    self._debug = (on == true)
    return self._debug
end

function RouteArrows:StatusLines()
    local art = resolveArt()
    local out = {
        "|cFFd9b33e[RouteArrows]|r",
        string.format("  activo: %s · debug: %s",
            self:IsEnabled() and "|cFF21de66sí|r" or "|cFFff9922no|r",
            self._debug and "sí" or "no"),
        string.format("  arte: %s (%s%s)", art.kind, tostring(art.value),
            (art.w and art.h) and string.format(" %dx%d", art.w, art.h) or ""),
        string.format("  tamaño: %s · offset: %s, %s · opacidad: %s · animación: %s",
            tostring(cfg("arrowSize")), tostring(cfg("arrowOffsetX")),
            tostring(cfg("arrowOffsetY")), tostring(cfg("arrowAlpha")),
            cfg("arrowAnimate") ~= false and "sí" or "no"),
        string.format("  modo de anclaje: %s · último anclaje: %s",
            tostring(cfg("arrowAnchor")), tostring(self._lastAnchor)),
        string.format("  flechas visibles: %d · en pool: %d", self:CountActive(), #self._free),
        string.format("  frames creados: %d · prestados: %d · devueltos: %d · rechazos: %d",
            self._stats.created, self._stats.acquired, self._stats.released, self._stats.refused),
    }
    return out
end

-- ─────────────────────────────────────────────────────────────────────────
-- EVENTOS
--
-- Todo cuelga de aquí. No hay OnUpdate global ni escaneo periódico de placas.
-- ─────────────────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        if type(unit) ~= "string" then return end
        -- La placa es NUEVA aunque el token se repita: si quedaba una flecha
        -- asociada a este token es basura de la unidad anterior. Fuera.
        local stale = RouteArrows._active[unit]
        if stale then
            RouteArrows._active[unit] = nil
            release(stale)
            dbg("token %s reutilizado: flecha vieja retirada", unit)
        end
        local cb = RouteArrows.OnNameplateAdded
        if cb then pcall(cb, unit) end

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if type(unit) ~= "string" then return end
        local f = RouteArrows._active[unit]
        if f then
            RouteArrows._active[unit] = nil
            release(f)
            dbg("placa %s retirada: flecha liberada", unit)
        end
        local cb = RouteArrows.OnNameplateRemoved
        if cb then pcall(cb, unit) end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Cambio de zona o /reload: las placas de antes ya no existen. Cualquier
        -- entrada que quede es huérfana por definición.
        RouteArrows:ClearAll()
    end
end)

return RouteArrows
