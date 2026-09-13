-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuRouteArrows · Core/Bootstrap  —  EXPERIMENTAL / IN DEVELOPMENT
--
-- Crea el espacio de nombres del addon, su base de datos propia y el acceso
-- a MitzuMPlus. Carga PRIMERO: todos los demás ficheros cuelgan de aquí.
--
-- RELACIÓN CON MitzuMPlus
-- Este addon lee MitzuMPlus exclusivamente a través de `MitzuMPlusAPI`, la
-- API pública de solo lectura. No nombra `_G.MitzuMPlus`, no toca sus
-- SavedVariables y no puede mover el pull, escribir identidad ni tocar la
-- sesión de la run: la API no ofrece ninguna forma de hacerlo.
--
-- SI FALTA MitzuMPlus
-- El .toc lo declara como OptionalDeps (solo orden de carga), no como
-- dependencia obligatoria. Así, si MitzuMPlus falta o está desactivado, este
-- addon SÍ carga, lo dice claramente en el chat y se queda inerte: sin la API
-- no hay estado de llave válido y ningún módulo llega a pintar una flecha.
-- Con una dependencia obligatoria WoW lo descartaría en silencio.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuRouteArrows"

local MRA = {}
_G.MitzuRouteArrows = MRA

MRA.NAME   = ADDON_NAME
MRA.STATUS = "EXPERIMENTAL"

-- Versión del contrato de MitzuMPlusAPI con la que se escribió este addon.
MRA.REQUIRED_API_VERSION = 1

local function tocVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or rawget(_G, "GetAddOnMetadata")
    if type(get) ~= "function" then return nil end
    local ok, v = pcall(get, ADDON_NAME, "Version")
    return ok and v or nil
end
MRA.VERSION = tocVersion() or "0.1.0-dev"

-- ─────────────────────────────────────────────────────────────────────────
-- CHAT
-- ─────────────────────────────────────────────────────────────────────────

local PREFIJO = "|cFFFF6600[MRA]|r "

function MRA:Print(msg)
    local frame = rawget(_G, "DEFAULT_CHAT_FRAME")
    local texto = PREFIJO .. tostring(msg)
    if frame and frame.AddMessage then
        pcall(frame.AddMessage, frame, texto)
    else
        print(texto)
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- ACCESO A MitzuMPlus
-- ─────────────────────────────────────────────────────────────────────────

MRA.HOST_STATES = {
    OK           = "OK",            -- API presente, versión compatible y lista
    NOT_READY    = "NOT_READY",     -- API presente pero el core no ha inicializado
    INCOMPATIBLE = "INCOMPATIBLE",  -- API con otra versión de contrato
    MISSING      = "MISSING",       -- MitzuMPlus no está cargado
}

-- La API tal cual, o nil si no se puede usar. Nunca guarda la referencia:
-- se consulta en cada llamada, así un /reload o un addon desactivado a mitad
-- de sesión no deja un puntero colgando.
function MRA:GetAPI()
    local api = rawget(_G, "MitzuMPlusAPI")
    if api == nil then return nil, self.HOST_STATES.MISSING end
    local okV, v = pcall(function() return api.GetAPIVersion() end)
    if not okV or v ~= self.REQUIRED_API_VERSION then
        return nil, self.HOST_STATES.INCOMPATIBLE
    end
    return api, self.HOST_STATES.OK
end

function MRA:HostState()
    local api, st = self:GetAPI()
    if not api then return st end
    local okR, listo = pcall(function() return api.IsReady() end)
    if not okR or listo ~= true then return self.HOST_STATES.NOT_READY end
    return self.HOST_STATES.OK
end

-- ¿Puede este addon trabajar ahora mismo? Todo lo que pinte flechas o
-- escuche combate pasa por aquí.
function MRA:CanOperate()
    return self:HostState() == self.HOST_STATES.OK
end

function MRA:HostMessage()
    local st = self:HostState()
    if st == self.HOST_STATES.MISSING then
        return "MitzuRouteArrows necesita |cFFf7d470MitzuMPlus|r y no está cargado " ..
               "(falta o está desactivado). El addon queda inactivo."
    elseif st == self.HOST_STATES.INCOMPATIBLE then
        return "La versión de MitzuMPlus instalada no es compatible con esta " ..
               "versión de MitzuRouteArrows (API " .. self.REQUIRED_API_VERSION ..
               "). El addon queda inactivo."
    elseif st == self.HOST_STATES.NOT_READY then
        return "MitzuMPlus aún no ha terminado de cargar."
    end
    return "MitzuMPlus conectado."
end

-- ─────────────────────────────────────────────────────────────────────────
-- BASE DE DATOS PROPIA  (MitzuRouteArrowsDB)
--
-- No se crea al cargar el fichero: WoW asigna el SavedVariable DESPUÉS de
-- ejecutar los ficheros del addon, justo antes de ADDON_LOADED, y una tabla
-- creada antes quedaría sustituida. Por eso nadie guarda una referencia: se
-- pide con MRA:DB() cada vez.
-- ─────────────────────────────────────────────────────────────────────────

MRA.DEFAULT_SETTINGS = {
    routeArrowsEnabled = true,
    arrowSize          = 56,       -- ALTURA; el ancho sale de la proporcion del atlas
    arrowAnchor        = "placa",  -- el anchor de Threat Plates no va centrado
    arrowOffsetX       = 0,
    arrowOffsetY       = 8,
    arrowAlpha         = 1,
    arrowAnimate       = true,
}

local function fusionar(destino, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(destino[k]) ~= "table" then destino[k] = {} end
            fusionar(destino[k], v)
        elseif destino[k] == nil then
            destino[k] = v
        end
    end
end

function MRA:DB()
    local db = rawget(_G, "MitzuRouteArrowsDB")
    if type(db) ~= "table" then
        db = {}
        _G.MitzuRouteArrowsDB = db
    end
    if type(db.settings) ~= "table" then db.settings = {} end
    fusionar(db.settings, self.DEFAULT_SETTINGS)
    return db
end

function MRA:Settings()
    return self:DB().settings
end

-- ─────────────────────────────────────────────────────────────────────────
-- PLACAS VISIBLES
--
-- La lista de tokens de nameplate que se ven ahora mismo. Primero la de
-- GuidanceEngine, que conoce el registro por eventos; si está vacía (tras un
-- /reload con placas ya en pantalla, que nunca dispararon ADDED), se pide al
-- cliente. Antes vivía en el Init.lua del core como MitzuMPlus:_VisibleNameplates.
-- ─────────────────────────────────────────────────────────────────────────

function MRA:VisibleNameplates()
    local visibles = {}
    local G = self.GuidanceEngine
    if G and G.GetVisible then
        local ok, l = pcall(G.GetVisible, G)
        if ok and type(l) == "table" then visibles = l end
    end
    local NP = rawget(_G, "C_NamePlate")
    if #visibles == 0 and NP and NP.GetNamePlates then
        local okP, placas = pcall(NP.GetNamePlates)
        if okP and type(placas) == "table" then
            for _, np in ipairs(placas) do
                local t = (type(np) == "table")
                    and (np.namePlateUnitToken or np.unitToken) or nil
                if type(t) == "string" then visibles[#visibles + 1] = t end
            end
            table.sort(visibles)
        end
    end
    return visibles
end

-- ─────────────────────────────────────────────────────────────────────────
-- ARRANQUE
--
-- En PLAYER_LOGIN ya están cargados todos los addons: es el primer momento en
-- que se puede saber con certeza si MitzuMPlus está o no. El aviso sale una
-- sola vez por sesión.
-- ─────────────────────────────────────────────────────────────────────────

MRA._warned = false

function MRA:OnLogin()
    self:DB()
    local st = self:HostState()
    if st == self.HOST_STATES.MISSING or st == self.HOST_STATES.INCOMPATIBLE then
        if not self._warned then
            self._warned = true
            self:Print("|cFFff9922" .. self:HostMessage() .. "|r")
        end
        return
    end
    if self.Lifecycle and self.Lifecycle.Attach then
        pcall(self.Lifecycle.Attach, self.Lifecycle)
    end
end

if type(CreateFrame) == "function" then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then
            local ok = pcall(MRA.OnLogin, MRA)
            if not ok then MRA:Print("|cFFff5555Error al arrancar.|r") end
        end
    end)
    MRA._loginFrame = frame
end

return MRA
