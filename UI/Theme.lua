-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Theme System
-- Paleta de colores y constantes visuales basadas en el mockup HTML
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local Theme = {}
MitzuMPlus.Theme = Theme

-- ═══════════════════════════════════════════════════════════════════════════
-- BACKGROUNDS
-- ═══════════════════════════════════════════════════════════════════════════

Theme.BG = {
    void      = { r = 0.020, g = 0.020, b = 0.031, a = 1.0 },  -- #050508
    window    = { r = 0.035, g = 0.035, b = 0.063, a = 1.0 },  -- #090910
    panel     = { r = 0.059, g = 0.059, b = 0.094, a = 1.0 },  -- #0f0f18
    rowOdd    = { r = 0.067, g = 0.067, b = 0.125, a = 1.0 },  -- #111120
    rowEven   = { r = 0.047, g = 0.047, b = 0.094, a = 1.0 },  -- #0c0c18
    rowHover  = { r = 0.110, g = 0.098, b = 0.063, a = 0.85 }, -- sobrio (blizzard-like)
    rowSel    = { r = 0.145, g = 0.125, b = 0.070, a = 0.95 }, -- selección más suave
    titlebar  = { r = 0.051, g = 0.043, b = 0.020, a = 1.0 },  -- #0d0b05
    button    = { r = 0.102, g = 0.102, b = 0.149, a = 1.0 },  -- #1a1a26
    btnPrim   = { r = 0.176, g = 0.129, b = 0.031, a = 1.0 },  -- #2d2108
    btnSec    = { r = 0.102, g = 0.102, b = 0.149, a = 1.0 },  -- #1a1a26
    btnSecHover = { r = 0.176, g = 0.129, b = 0.031, a = 1.0 }, -- #2d2108
    btnClose  = { r = 0.149, g = 0.047, b = 0.047, a = 1.0 },  -- #260c0c
    btnCloseHover = { r = 0.220, g = 0.039, b = 0.039, a = 1.0 }, -- #380a0a
    input     = { r = 0.039, g = 0.039, b = 0.078, a = 1.0 },  -- #0a0a14
    tooltip   = { r = 0.024, g = 0.024, b = 0.063, a = 1.0 },  -- #060610
    panelHeader = { r = 0.051, g = 0.043, b = 0.020, a = 0.8 },
    bottomBar = { r = 0.016, g = 0.016, b = 0.027, a = 0.85 }, -- #040407

    -- Tabla / headers
    tableHeader = { r = 0.051, g = 0.043, b = 0.020, a = 0.80 },
    tableHeaderBorder = { r = 0.290, g = 0.235, b = 0.094, a = 0.90 },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- GOLD PALETTE (6 shades)
-- ═══════════════════════════════════════════════════════════════════════════

Theme.GOLD = {
    gold0 = { r = 0.290, g = 0.235, b = 0.094, a = 1.0 }, -- #4a3c18
    gold1 = { r = 0.420, g = 0.333, b = 0.125, a = 1.0 }, -- #6b5520
    gold2 = { r = 0.541, g = 0.408, b = 0.157, a = 1.0 }, -- #8a6828
    gold3 = { r = 0.784, g = 0.620, b = 0.188, a = 1.0 }, -- #c89e30
    gold4 = { r = 0.910, g = 0.722, b = 0.290, a = 1.0 }, -- #e8b84a
    gold5 = { r = 0.969, g = 0.831, b = 0.439, a = 1.0 }, -- #f7d470
    
    -- Aliases comunes
    borderFocus = { r = 0.784, g = 0.620, b = 0.188, a = 1.0 },
    highlight   = { r = 0.910, g = 0.722, b = 0.290, a = 1.0 },
    sectionHead = { r = 0.784, g = 0.620, b = 0.188, a = 1.0 },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- STATUS COLORS
-- ═══════════════════════════════════════════════════════════════════════════

Theme.STATUS = {
    ok   = { r = 0.129, g = 0.871, b = 0.400, a = 1.0 }, -- #21de66
    okD  = { r = 0.059, g = 0.200, b = 0.125, a = 1.0 }, -- #0f3320
    bad  = { r = 0.933, g = 0.200, b = 0.200, a = 1.0 }, -- #ee3333
    badD = { r = 0.180, g = 0.039, b = 0.039, a = 1.0 }, -- #2e0a0a
    warn = { r = 1.000, g = 0.600, b = 0.133, a = 1.0 }, -- #ff9922
    info = { r = 0.533, g = 0.733, b = 0.933, a = 1.0 }, -- #88bbee
    purple = { r = 0.733, g = 0.533, b = 0.933, a = 1.0 }, -- #bb88ee
}

-- ═══════════════════════════════════════════════════════════════════════════
-- TEXT COLORS
-- ═══════════════════════════════════════════════════════════════════════════

Theme.TEXT = {
    primary   = { r = 0.933, g = 0.933, b = 0.933, a = 1.0 }, -- #eeeeee
    secondary = { r = 0.722, g = 0.722, b = 0.722, a = 1.0 }, -- #b8b8b8
    tertiary  = { r = 0.533, g = 0.533, b = 0.533, a = 1.0 }, -- #888888
    dim       = { r = 0.333, g = 0.333, b = 0.400, a = 1.0 }, -- #555566
}

-- ═══════════════════════════════════════════════════════════════════════════
-- BORDERS
-- ═══════════════════════════════════════════════════════════════════════════

Theme.BORDER = {
    panel     = { r = 0.133, g = 0.133, b = 0.208, a = 1.0 }, -- #222235
    separator = { r = 0.165, g = 0.165, b = 0.229, a = 1.0 }, -- #2a2a3a
    window    = { r = 0.290, g = 0.235, b = 0.094, a = 1.0 }, -- #4a3c18 (gold0)

    -- Tabla
    tableHeader = { r = 0.290, g = 0.235, b = 0.094, a = 0.90 },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- CLASS COLORS (para miembros del grupo)
-- ═══════════════════════════════════════════════════════════════════════════

Theme.CLASS = {
    WARRIOR     = { r = 0.780, g = 0.612, b = 0.431, a = 1.0 },
    PALADIN     = { r = 0.957, g = 0.549, b = 0.729, a = 1.0 },
    HUNTER      = { r = 0.671, g = 0.831, b = 0.384, a = 1.0 },
    ROGUE       = { r = 1.000, g = 0.957, b = 0.408, a = 1.0 }, -- #fff468
    PRIEST      = { r = 1.000, g = 1.000, b = 1.000, a = 1.0 },
    DEATHKNIGHT = { r = 0.769, g = 0.118, b = 0.227, a = 1.0 },
    SHAMAN      = { r = 0.000, g = 0.439, b = 0.867, a = 1.0 },
    MAGE        = { r = 0.251, g = 0.890, b = 0.961, a = 1.0 },
    WARLOCK     = { r = 0.529, g = 0.529, b = 0.937, a = 1.0 },
    MONK        = { r = 0.000, g = 1.000, b = 0.596, a = 1.0 },
    DRUID       = { r = 1.000, g = 0.490, b = 0.039, a = 1.0 }, -- #ff7c0a
    DEMONHUNTER = { r = 0.639, g = 0.188, b = 0.788, a = 1.0 },
    EVOKER      = { r = 0.204, g = 0.576, b = 0.498, a = 1.0 },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- ROLE COLORS (para iconos)
-- ═══════════════════════════════════════════════════════════════════════════

Theme.ROLE = {
    TANK    = { r = 0.200, g = 0.600, b = 1.000, a = 1.0 }, -- #3399ff
    HEALER  = { r = 0.400, g = 1.000, b = 0.533, a = 1.0 }, -- #66ff88
    DAMAGER = { r = 0.769, g = 0.118, b = 0.227, a = 1.0 }, -- #c41e3a
}

-- ═══════════════════════════════════════════════════════════════════════════
-- LAYOUT CONSTANTS
-- ═══════════════════════════════════════════════════════════════════════════

Theme.LAYOUT = {
    -- Window (tamaño fijo — no redimensionable)
    windowWidth  = 1160,     -- fuentes extra grandes
    windowHeight = 700,      -- fuentes extra grandes
    
    -- Titlebar
    titlebarHeight = 56,     -- fuentes extra grandes

    -- Tabs
    tabHeight = 40,          -- fuentes extra grandes
    
    -- Sidebar
    sidebarWidth = 230,      -- fuentes extra grandes
    
    -- Footer
    footerHeight = 32,       -- fuentes extra grandes
    
    -- Spacing
    padding      = 12,
    paddingSmall = 8,
    paddingTiny  = 4,
    gap          = 6,
    gapSmall     = 4,
    
    -- Row heights — más altas para texto legible
    rowHeight       = 32,    -- fuentes extra grandes
    rowHeightSmall  = 24,    -- fuentes extra grandes
    rowHeightLarge  = 36,    -- fuentes extra grandes
    
    -- Borders
    borderWidth = 1,
    
    -- Buttons
    buttonHeight       = 28, -- fuentes extra grandes
    buttonHeightSmall  = 24, -- fuentes extra grandes
    buttonHeightLarge  = 32, -- fuentes extra grandes
}

-- ═══════════════════════════════════════════════════════════════════════════
-- FONTS
-- ═══════════════════════════════════════════════════════════════════════════

Theme.FONTS = {
    -- Títulos: Friz Quadrata con outline
    title = {
        path  = "Fonts\\FRIZQT__.TTF",
        size  = 16,
        flags = "OUTLINE",
    },

    -- UI general: Friz Quadrata semiserif sin outline
    normal = {
        path  = "Fonts\\FRIZQT__.TTF",
        size  = 13,
        flags = "",
    },

    -- Etiquetas/mono: Friz Quadrata tamaño menor
    mono = {
        path  = "Fonts\\FRIZQT__.TTF",
        size  = 12,
        flags = "",
    },

    -- Tamaños numéricos
    tiny   = 11,
    small  = 12,
    medium = 13,
    large  = 15,
    xlarge = 18,
    huge   = 22,
    giant  = 36,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

function Theme:SetBackdropColor(frame, colorTable)
    if not frame or not colorTable then return end
    frame:SetBackdropColor(colorTable.r, colorTable.g, colorTable.b, colorTable.a or 1.0)
end

function Theme:SetBackdropBorderColor(frame, colorTable)
    if not frame or not colorTable then return end
    frame:SetBackdropBorderColor(colorTable.r, colorTable.g, colorTable.b, colorTable.a or 1.0)
end

function Theme:SetTextColor(fontString, colorTable)
    if not fontString or not colorTable then return end

    local a = colorTable.a or 1.0

    -- Retail nueva firma: SetTextColor(color [, a])
    local ok = pcall(function()
        fontString:SetTextColor(colorTable, a)
    end)
    if ok then return end

    -- Compatibilidad clásica: SetTextColor(r, g, b [, a])
    pcall(function()
        fontString:SetTextColor(
            colorTable.r or 1,
            colorTable.g or 1,
            colorTable.b or 1,
            a
        )
    end)
end

function Theme:SetVertexColor(texture, colorTable)
    if not texture or not colorTable then return end

    local a = colorTable.a or 1.0

    -- Retail nueva firma: SetVertexColor(color [, a])
    local ok = pcall(function()
        texture:SetVertexColor(colorTable, a)
    end)
    if ok then return end

    -- Compatibilidad clásica: SetVertexColor(r, g, b [, a])
    pcall(function()
        texture:SetVertexColor(
            colorTable.r or 1,
            colorTable.g or 1,
            colorTable.b or 1,
            a
        )
    end)
end

function Theme:ApplyFont(fontString, fontType, size)
    if not fontString then return end
    
    local font = nil
    local fontSize = size
    
    -- Si fontType es un número, lo tratamos como tamaño y usamos fuente normal
    if type(fontType) == "number" then
        fontSize = fontType
        font = self.FONTS.normal
    elseif self.FONTS[fontType] then
        font = self.FONTS[fontType]
        if type(font) == "number" then
            fontSize = font
            font = self.FONTS.normal
        end
    else
        font = self.FONTS.normal
    end
    
    if not font then return end
    
    fontSize = fontSize or font.size or 11
    local flags = font.flags or ""

    fontString:SetFont(self:ResolveFontPath(font.path), fontSize, flags)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LibSharedMedia-3.0 (OPCIONAL)
--
-- LSM es el registro compartido de fuentes/texturas/sonidos que rellenan los
-- addons grandes (Details, Plater, ThreatPlates, ElvUI...). Aqui se usa SOLO
-- para fuentes, y de forma opcional: este addon NO la empaqueta.
--
-- Por que opcional y no empaquetada:
--   · Ya esta en el sistema del usuario (la traen BugSack, BetterBlizzPlates y
--     otros; ThreatPlates registra ahi sus 20+ fuentes). Empaquetar otra copia
--     solo añade peso y riesgo de servir una version mas vieja.
--   · Si no estuviera, la UI sigue funcionando exactamente igual con
--     Fonts\FRIZQT__.TTF. Una dependencia opcional no puede romper nada.
--
-- Por que se resuelve TARDE y no al cargar el archivo:
--   LibStub es global entre addons, pero el orden de carga entre addons NO
--   esta garantizado sin declararlo en el .toc. Si se pidiera la libreria al
--   cargar Theme.lua y ThreatPlates todavia no hubiera cargado, saldria nil y
--   quedaria cacheado a nil para toda la sesion. Se pide en el primer uso.
-- ═══════════════════════════════════════════════════════════════════════════

function Theme:GetLSM()
    if self._lsm then return self._lsm end
    -- (v7.8.2) NO se cachea el fallo. Antes, en cuanto IsLoggedIn() era cierto
    -- se guardaba el nil como definitivo; si la primera consulta caia antes de
    -- que el addon portador registrase la libreria, la fuente quedaba bloqueada
    -- el resto de la sesion y el addon insistia en que no estaba instalada.
    -- Consultar LibStub es un indice de tabla: no merece la pena cachear un no.
    self._lsm = LibStub and LibStub("LibSharedMedia-3.0", true) or nil
    return self._lsm
end

-- Por que no hay fuentes que ofrecer. Devuelve nil si no hay problema.
-- Existe porque el mensaje anterior era una suposicion ("instala BugSack o
-- ThreatPlates") que se le enseñaba a un usuario que ya tenia los dos, y que
-- por tanto no explicaba nada. Aqui se distingue el caso de verdad.
function Theme:LSMDiagnosis()
    if not LibStub then
        return "LibStub no esta cargado. Es un fallo del propio addon, avisa."
    end
    local lib = LibStub("LibSharedMedia-3.0", true)
    if not lib then
        return "LibStub esta, pero ningun addon ha registrado LibSharedMedia-3.0."
    end
    local ok, list = pcall(lib.List, lib, "font")
    if not ok then
        return "LibSharedMedia esta cargada pero fallo al pedirle la lista."
    end
    if type(list) ~= "table" or #list == 0 then
        return "LibSharedMedia esta cargada y no tiene ninguna fuente registrada."
    end
    return nil
end

-- Devuelve la lista de nombres de fuente disponibles, para el desplegable de
-- configuracion. Vacia si no hay LSM.
function Theme:GetFontList()
    local lsm = self:GetLSM()
    if not lsm then return {} end
    local ok, list = pcall(lsm.List, lsm, "font")
    return (ok and type(list) == "table") and list or {}
end

-- Traduce la fuente configurada por el usuario a una ruta real.
-- `fallback` es la ruta que traiga el tema; si no hay LSM, o el usuario no ha
-- elegido nada, o la fuente elegida ya no existe (desinstalo el addon que la
-- traia), se devuelve el fallback sin ruido.
function Theme:ResolveFontPath(fallback)
    fallback = fallback or "Fonts\\FRIZQT__.TTF"
    local st = MitzuMPlus.db and MitzuMPlus.db.profile and MitzuMPlus.db.profile.settings
    local name = st and st.uiFont
    if type(name) ~= "string" or name == "" then return fallback end

    local lsm = self:GetLSM()
    if not lsm then return fallback end

    local ok, path = pcall(lsm.Fetch, lsm, "font", name, true)
    if ok and type(path) == "string" and path ~= "" then return path end
    return fallback
end

function Theme:GetClassColor(classToken)
    return self.CLASS[classToken] or self.TEXT.primary
end

function Theme:GetStatusColor(status)
    if status == "ok" or status == "success" then
        return self.STATUS.ok
    elseif status == "bad" or status == "error" then
        return self.STATUS.bad
    elseif status == "warn" or status == "warning" then
        return self.STATUS.warn
    elseif status == "info" then
        return self.STATUS.info
    else
        return self.TEXT.primary
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BACKDROP TEMPLATES
-- ═══════════════════════════════════════════════════════════════════════════

Theme.BACKDROPS = {
    -- Ventana principal
    window = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    },
    
    -- Panel estándar
    panel = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    },
    
    -- Sin borde (TWW compatible)
    simple = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        tile = true,
        tileSize = 32,
        edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    },
    
    -- Tooltip
    tooltip = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- KEY LEVEL TIERS (colores por rango de nivel)
-- ═══════════════════════════════════════════════════════════════════════════

Theme.KEY_TIERS = {
    { min = 0,  max = 9,  
      text   = { r = 0.400, g = 1.000, b = 0.533, a = 1.0 },  -- verde esmeralda
      bg     = { r = 0.016, g = 0.094, b = 0.047, a = 1.0 },
      border = { r = 0.157, g = 0.533, b = 0.267, a = 1.0 } },
    { min = 10, max = 14,
      text   = { r = 0.533, g = 0.733, b = 0.933, a = 1.0 },  -- azul claro
      bg     = { r = 0.020, g = 0.055, b = 0.130, a = 1.0 },
      border = { r = 0.200, g = 0.420, b = 0.733, a = 1.0 } },
    { min = 15, max = 17,
      text   = { r = 0.533, g = 0.733, b = 0.933, a = 1.0 },  -- azul zafiro
      bg     = { r = 0.035, g = 0.090, b = 0.220, a = 1.0 },
      border = { r = 0.231, g = 0.545, b = 0.831, a = 1.0 } },
    { min = 18, max = 19,
      text   = { r = 0.969, g = 0.831, b = 0.439, a = 1.0 },  -- dorado
      bg     = { r = 0.100, g = 0.072, b = 0.012, a = 1.0 },
      border = { r = 0.784, g = 0.620, b = 0.188, a = 1.0 } },
    { min = 20, max = 99,
      text   = { r = 0.733, g = 0.533, b = 0.933, a = 1.0 },  -- morado arcano
      bg     = { r = 0.086, g = 0.035, b = 0.165, a = 1.0 },
      border = { r = 0.467, g = 0.220, b = 0.800, a = 1.0 } },
}

function Theme:GetKeyLevelTheme(level)
    level = tonumber(level) or 0
    for _, tier in ipairs(self.KEY_TIERS) do
        if level >= tier.min and level <= tier.max then
            return { text = tier.text, bg = tier.bg, border = tier.border }
        end
    end
    return { text = self.TEXT.secondary, bg = self.BG.button, border = self.BORDER.panel }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- GRADIENT HELPER (compatibilidad Retail + Classic)
-- ─────────────────────────────────────────────────────────────────────────────

function Theme:SetGradientH(tex, r1, g1, b1, a1, r2, g2, b2, a2)
    if not tex then return end
    -- Intenta API moderna (10.x+)
    local ok = pcall(function()
        tex:SetGradient("HORIZONTAL",
            CreateColor(r1, g1, b1, a1),
            CreateColor(r2, g2, b2, a2))
    end)
    if not ok then
        -- Fallback API clásica
        pcall(function()
            tex:SetGradientAlpha("HORIZONTAL", r1, g1, b1, a1, r2, g2, b2, a2)
        end)
    end
end

-- Agregar aliases después de la definición completa
Theme.BG.btnSec        = Theme.BG.button
Theme.BG.btnSecHover   = Theme.BG.btnPrim
Theme.BG.btnClose      = { r = 0.149, g = 0.047, b = 0.047, a = 1.0 }
Theme.BG.btnCloseHover = { r = 0.220, g = 0.039, b = 0.039, a = 1.0 }

Theme.BORDER.titlebar     = Theme.GOLD.gold0
Theme.BORDER.btnSec       = Theme.BORDER.panel
Theme.BORDER.btnSecHover  = Theme.GOLD.gold3
Theme.BORDER.btnClose     = { r = 0.400, g = 0.082, b = 0.082, a = 1.0 }
Theme.BORDER.btnCloseHover = Theme.STATUS.bad

Theme.BACKDROPS.titlebar = Theme.BACKDROPS.simple
Theme.BACKDROPS.button   = Theme.BACKDROPS.panel

-- ═══════════════════════════════════════════════════════════════════════════
-- ICON MAPPINGS (emojis -> WoW textures/text)
-- ═══════════════════════════════════════════════════════════════════════════

Theme.ICONS = {
    -- Roles
    TANK    = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:0:0:0:0:64:64:0:19:22:41|t",
    HEALER  = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:0:0:0:0:64:64:20:39:1:20|t",
    DAMAGER = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:0:0:0:0:64:64:20:39:22:41|t",
    
    -- Estados
    OK      = "|cFF21de66[OK]|r",
    BAD     = "|cFFee3333X|r",
    WARN    = "|cFFff9922[!]|r",
    
    -- Generales (texto ASCII seguro — WoW no renderiza emoji U+1F000+)
    SKULL    = "[X]",
    SWORD    = "|cFFe8b84a><|r",
    SHIELD   = "[D]",
    KICK     = "[INT]",
    DISPEL   = "[DISP]",
    FINISH   = "[OK]",
    FIRE     = "[!]",
    STAR     = "*",
    TROPHY   = "[#1]",
    CHART    = "[STATS]",
    SEARCH   = "[?]",
    SETTINGS = "[CFG]",
    CLOSE    = "X",
}

-- ═══════════════════════════════════════════════════════════════════════════
-- COMPATIBILITY BRIDGE v2.1
-- Aliases para módulos que usan claves del sistema de tema antiguo
-- (UI_Common, Export, MinimapIcon, etc.).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── GOLD aliases ──────────────────────────────────────────────────────────
Theme.GOLD.title      = Theme.GOLD.gold3   -- #c89e30 (0.784, 0.620, 0.188)
Theme.GOLD.active     = Theme.GOLD.gold2   -- #8a6828
Theme.GOLD.border     = Theme.GOLD.gold0   -- #4a3c18
Theme.GOLD.btnText    = Theme.GOLD.gold3
Theme.GOLD.btnPrimText= Theme.GOLD.gold5

-- ── BG aliases ────────────────────────────────────────────────────────────
Theme.BG.buttonHover   = Theme.BG.btnSecHover or { r=0.180, g=0.173, b=0.137, a=0.95 }
Theme.BG.buttonPrim    = Theme.BG.btnPrim
Theme.BG.buttonPrimH   = { r=0.220, g=0.165, b=0.039, a=0.95 }
Theme.BG.rowSelected   = Theme.BG.rowSel
Theme.BG.summaryBar    = Theme.BG.panelHeader
Theme.BG.btnPrimHover  = Theme.BG.buttonPrimH

-- ── BORDER aliases ────────────────────────────────────────────────────────
Theme.BORDER.inputFocus = Theme.GOLD.borderFocus

-- ── STATUS aliases ────────────────────────────────────────────────────────
Theme.STATUS.okBg   = Theme.STATUS.okD
Theme.STATUS.badBg  = Theme.STATUS.badD
Theme.STATUS.warnBg = { r=0.157, g=0.102, b=0.020, a=0.80 }

-- ── Method bridges (estilos legacy → Theme.lua) ────────────────────────
function Theme:StyleWindow(frame)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop(self.BACKDROPS.window)
    self:SetBackdropColor(frame, self.BG.window)
    self:SetBackdropBorderColor(frame, self.BORDER.window)
end

function Theme:StyleTitlebar(frame)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop(self.BACKDROPS.simple)
    self:SetBackdropColor(frame, self.BG.titlebar)
end

function Theme:StylePanel(frame)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop(self.BACKDROPS.panel)
    self:SetBackdropColor(frame, self.BG.panel)
    self:SetBackdropBorderColor(frame, self.BORDER.panel)
end

function Theme:StyleButton(btn, isPrimary)
    if not btn or not btn.SetBackdrop then return end
    btn:SetBackdrop(self.BACKDROPS.panel)
    if isPrimary then
        self:SetBackdropColor(btn, self.BG.btnPrim)
        self:SetBackdropBorderColor(btn, self.GOLD.border)
        if btn.GetFontString and btn:GetFontString() then
            local fs = btn:GetFontString()
            fs:SetTextColor(self.GOLD.btnPrimText.r, self.GOLD.btnPrimText.g, self.GOLD.btnPrimText.b)
        end
    else
        self:SetBackdropColor(btn, self.BG.button)
        self:SetBackdropBorderColor(btn, self.BORDER.panel)
        if btn.GetFontString and btn:GetFontString() then
            local fs = btn:GetFontString()
            fs:SetTextColor(self.GOLD.btnText.r, self.GOLD.btnText.g, self.GOLD.btnText.b)
        end
    end
    btn:SetScript("OnEnter", function(self_btn)
        local hc = isPrimary and Theme.BG.buttonPrimH or Theme.BG.buttonHover
        Theme:SetBackdropColor(self_btn, hc)
        Theme:SetBackdropBorderColor(self_btn, Theme.GOLD.borderFocus)
    end)
    btn:SetScript("OnLeave", function(self_btn)
        local nc = isPrimary and Theme.BG.btnPrim or Theme.BG.button
        Theme:SetBackdropColor(self_btn, nc)
        Theme:SetBackdropBorderColor(self_btn, Theme.BORDER.panel)
    end)
end

function Theme:SetTitleText(fontString, text)
    if not fontString then return end
    fontString:SetText(text)
    fontString:SetTextColor(self.GOLD.title.r, self.GOLD.title.g, self.GOLD.title.b)
end

function Theme:SetSectionHeader(fontString, text)
    if not fontString then return end
    fontString:SetText(text)
    fontString:SetTextColor(self.GOLD.sectionHead.r, self.GOLD.sectionHead.g, self.GOLD.sectionHead.b)
end

function Theme:SetNormalText(fontString, text)
    if not fontString then return end
    if text then fontString:SetText(text) end
    fontString:SetTextColor(self.TEXT.primary.r, self.TEXT.primary.g, self.TEXT.primary.b)
end

function Theme:SetDimText(fontString, text)
    if not fontString then return end
    if text then fontString:SetText(text) end
    fontString:SetTextColor(self.TEXT.dim.r, self.TEXT.dim.g, self.TEXT.dim.b)
end

-- Asegurarse de que _G.MitzuMPlusColors también tenga los aliases
-- (MinimapIcon y mmMenu fallback usan _G.MitzuMPlusColors)
if not _G.MitzuMPlusColors then
    _G.MitzuMPlusColors = {}
end
local C = _G.MitzuMPlusColors
C.gold0  = C.gold0  or Theme.GOLD.gold0
C.gold1  = C.gold1  or Theme.GOLD.gold1
C.gold2  = C.gold2  or Theme.GOLD.gold2
C.gold3  = C.gold3  or Theme.GOLD.gold3
C.gold4  = C.gold4  or Theme.GOLD.gold4
C.gold5  = C.gold5  or Theme.GOLD.gold5
C.t1     = C.t1     or Theme.TEXT.primary
C.t2     = C.t2     or Theme.TEXT.secondary
C.stone2 = C.stone2 or Theme.BG.panel
C.metal1 = C.metal1 or Theme.BG.btnPrim

return Theme
