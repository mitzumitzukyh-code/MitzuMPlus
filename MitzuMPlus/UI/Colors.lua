-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - UI/Colors.lua
-- Reemplaza Theme.lua.
-- Conserva exactamente la misma API pública (Theme.STATUS, Theme.CLASS,
-- Theme.GOLD, Theme.TEXT, Theme.BG, Theme.BORDER, Theme.BACKDROPS,
-- Theme.LAYOUT, Theme:SetBackdropColor(), Theme:ApplyFont(), …) para que
-- los paneles de datos no necesiten cambios.
-- La diferencia clave es que los BACKDROPS usan texturas nativas de Blizzard
-- y los BG/BORDER son tonos neutros grises en lugar del fondo void/gold oscuro.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local Colors = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- BUG FUENTES-1 (v7.8.2)
--
-- Theme.lua se carga JUSTO ANTES que este archivo y hace `MitzuMPlus.Theme =
-- Theme`. La linea de abajo lo pisa entero, asi que la tabla de Theme.lua —y
-- todo lo que colgaba de ella— quedaba inalcanzable.
--
-- Ahi vivian GetLSM, GetFontList y ResolveFontPath. Resultado: la lista de
-- fuentes salia SIEMPRE vacia y el addon culpaba a LibSharedMedia de no estar
-- instalada, con quince copias de la libreria en la carpeta. Y peor: elegir una
-- fuente con /emp fuente no hacia nada, porque ApplyFont busca el resolver en
-- MitzuMPlus.Theme, que ya era esta misma tabla y no lo tenia.
--
-- No se duplica el codigo: se recoge la tabla anterior antes de pisarla y se
-- heredan las utilidades que aqui no existen. Si mañana Theme.lua gana otra,
-- basta con nombrarla en la lista.
-- ═══════════════════════════════════════════════════════════════════════════
local PrevTheme = MitzuMPlus.Theme

-- Colors.lua es el tema definitivo y fuente de verdad.
-- Todos los módulos que hacen local Theme = MitzuMPlus.Theme reciben este objeto.
MitzuMPlus.Theme  = Colors
MitzuMPlus.Colors = Colors

if type(PrevTheme) == "table" then
    for _, k in ipairs({ "GetLSM", "LSMDiagnosis", "GetFontList", "ResolveFontPath" }) do
        if Colors[k] == nil and type(PrevTheme[k]) == "function" then
            Colors[k] = PrevTheme[k]
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- STATUS COLORS  (semánticos: verde=en tiempo, rojo=fuera de tiempo, etc.)
-- Idénticos al original — son datos, no chrome.
-- ─────────────────────────────────────────────────────────────────────────

Colors.STATUS = {
    ok     = { r = 0.129, g = 0.871, b = 0.400, a = 1.0 },
    okD    = { r = 0.059, g = 0.200, b = 0.125, a = 1.0 },
    bad    = { r = 0.933, g = 0.200, b = 0.200, a = 1.0 },
    badD   = { r = 0.180, g = 0.039, b = 0.039, a = 1.0 },
    warn   = { r = 1.000, g = 0.600, b = 0.133, a = 1.0 },
    info   = { r = 0.533, g = 0.733, b = 0.933, a = 1.0 },
    purple = { r = 0.733, g = 0.533, b = 0.933, a = 1.0 },
    dim    = { r = 0.420, g = 0.420, b = 0.420, a = 1.0 },
}

-- ─────────────────────────────────────────────────────────────────────────
-- GOLD PALETTE  (usada en cabeceras de columna, llaves, highlights)
-- Se preserva para que los textos resaltados sigan siendo dorados.
-- ─────────────────────────────────────────────────────────────────────────

Colors.GOLD = {
    gold0 = { r = 0.290, g = 0.235, b = 0.094, a = 1.0 },
    gold1 = { r = 0.420, g = 0.333, b = 0.125, a = 1.0 },
    gold2 = { r = 0.541, g = 0.408, b = 0.157, a = 1.0 },
    gold3 = { r = 0.784, g = 0.620, b = 0.188, a = 1.0 },
    gold4 = { r = 0.910, g = 0.722, b = 0.290, a = 1.0 },
    gold5 = { r = 0.969, g = 0.831, b = 0.439, a = 1.0 },
    highlight   = { r = 0.910, g = 0.722, b = 0.290, a = 1.0 },
    sectionHead = { r = 0.784, g = 0.620, b = 0.188, a = 1.0 },
    borderFocus = { r = 0.784, g = 0.620, b = 0.188, a = 1.0 },
}

-- ─────────────────────────────────────────────────────────────────────────
-- CLASS COLORS  (idénticos a WoW API; se usan en nombres de miembros)
-- ─────────────────────────────────────────────────────────────────────────

Colors.CLASS = {
    WARRIOR     = { r = 0.780, g = 0.612, b = 0.431, a = 1.0 },
    PALADIN     = { r = 0.957, g = 0.549, b = 0.729, a = 1.0 },
    HUNTER      = { r = 0.671, g = 0.831, b = 0.384, a = 1.0 },
    ROGUE       = { r = 1.000, g = 0.957, b = 0.408, a = 1.0 },
    PRIEST      = { r = 1.000, g = 1.000, b = 1.000, a = 1.0 },
    DEATHKNIGHT = { r = 0.769, g = 0.118, b = 0.227, a = 1.0 },
    SHAMAN      = { r = 0.000, g = 0.439, b = 0.867, a = 1.0 },
    MAGE        = { r = 0.251, g = 0.890, b = 0.961, a = 1.0 },
    WARLOCK     = { r = 0.529, g = 0.529, b = 0.937, a = 1.0 },
    MONK        = { r = 0.000, g = 1.000, b = 0.596, a = 1.0 },
    DRUID       = { r = 1.000, g = 0.490, b = 0.039, a = 1.0 },
    DEMONHUNTER = { r = 0.639, g = 0.188, b = 0.788, a = 1.0 },
    EVOKER      = { r = 0.204, g = 0.576, b = 0.498, a = 1.0 },
}

-- ─────────────────────────────────────────────────────────────────────────
-- ROLE COLORS
-- ─────────────────────────────────────────────────────────────────────────

Colors.ROLE = {
    TANK    = { r = 0.200, g = 0.600, b = 1.000, a = 1.0 },
    HEALER  = { r = 0.400, g = 1.000, b = 0.533, a = 1.0 },
    DAMAGER = { r = 0.769, g = 0.118, b = 0.227, a = 1.0 },
}

-- ─────────────────────────────────────────────────────────────────────────
-- TEXT COLORS  (neutros, inspirados en Blizzard)
-- ─────────────────────────────────────────────────────────────────────────

Colors.TEXT = {
    primary   = { r = 1.000, g = 1.000, b = 1.000, a = 1.0 },
    secondary = { r = 0.840, g = 0.840, b = 0.840, a = 1.0 },
    tertiary  = { r = 0.690, g = 0.690, b = 0.690, a = 1.0 },
    dim       = { r = 0.560, g = 0.560, b = 0.560, a = 1.0 },
    watermark = { r = 0.500, g = 0.500, b = 0.500, a = 0.82 },
}

-- ─────────────────────────────────────────────────────────────────────────
-- BACKGROUND COLORS  (tonos neutros Blizzard; los paneles los usan en rows)
-- ─────────────────────────────────────────────────────────────────────────

Colors.BG = {
    void        = { r = 0.04,  g = 0.04,  b = 0.05,  a = 1.0  },
    window      = { r = 0.06,  g = 0.06,  b = 0.07,  a = 0.97 },
    panel       = { r = 0.08,  g = 0.08,  b = 0.09,  a = 0.97 },
    rowOdd      = { r = 0.11,  g = 0.11,  b = 0.12,  a = 0.95 },
    rowEven     = { r = 0.07,  g = 0.07,  b = 0.08,  a = 0.95 },
    rowHover    = { r = 0.22,  g = 0.20,  b = 0.12,  a = 1.0  },
    rowSel      = { r = 0.28,  g = 0.24,  b = 0.12,  a = 1.0  },
    titlebar    = { r = 0.05,  g = 0.05,  b = 0.06,  a = 1.0  },
    button      = { r = 0.18,  g = 0.18,  b = 0.18,  a = 1.0  },
    btnPrim     = { r = 0.25,  g = 0.20,  b = 0.06,  a = 1.0  },
    btnSec      = { r = 0.18,  g = 0.18,  b = 0.18,  a = 1.0  },
    btnSecHover = { r = 0.25,  g = 0.20,  b = 0.06,  a = 1.0  },
    btnClose    = { r = 0.20,  g = 0.06,  b = 0.06,  a = 1.0  },
    btnCloseHover = { r = 0.32, g = 0.06, b = 0.06,  a = 1.0  },
    input       = { r = 0.05,  g = 0.05,  b = 0.06,  a = 1.0  },
    tooltip     = { r = 0.04,  g = 0.04,  b = 0.05,  a = 0.98 },
    panelHeader   = { r = 0.08, g = 0.08, b = 0.09,  a = 0.97 },
    bottomBar     = { r = 0.04, g = 0.04, b = 0.05,  a = 0.98 },
    tableHeader   = { r = 0.10, g = 0.10, b = 0.11,  a = 0.97 },
    tableHeaderBorder = { r = 0.40, g = 0.35, b = 0.15, a = 1.0 },
}

-- ─────────────────────────────────────────────────────────────────────────
-- BORDER COLORS
-- ─────────────────────────────────────────────────────────────────────────

Colors.BORDER = {
    panel       = { r = 0.28, g = 0.28, b = 0.28, a = 1.0 },
    separator   = { r = 0.22, g = 0.22, b = 0.22, a = 1.0 },
    window      = { r = 0.40, g = 0.40, b = 0.40, a = 1.0 },
    titlebar    = { r = 0.35, g = 0.35, b = 0.35, a = 1.0 },
    btnSec      = { r = 0.30, g = 0.30, b = 0.30, a = 1.0 },
    btnSecHover = { r = 0.70, g = 0.55, b = 0.20, a = 1.0 },
    btnClose    = { r = 0.35, g = 0.10, b = 0.10, a = 1.0 },
    btnCloseHover = { r = 0.60, g = 0.10, b = 0.10, a = 1.0 },
    tableHeader   = { r = 0.40, g = 0.35, b = 0.15, a = 0.90 },
}

-- ─────────────────────────────────────────────────────────────────────────
-- BACKDROP TEMPLATES  ← clave para el look nativo Blizzard
-- Usan las mismas texturas que los diálogos y tooltips del juego.
-- ─────────────────────────────────────────────────────────────────────────

Colors.BACKDROPS = {
    -- Fondo estándar sin borde visible (filter bars, sidebars, etc.)
    simple = {
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        tile     = true,
        tileSize = 32,
        edgeSize = 0,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    },
    -- Panel con borde de tooltip Blizzard
    panel = {
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 10,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    },
    -- Ventana principal (misma textura de dialog)
    window = {
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 26,
        insets   = { left = 8, right = 6, top = 8, bottom = 8 },
    },
    -- Titlebar
    titlebar = {
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Header",
        tile     = false,
        tileSize = 0,
        edgeSize = 0,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    },
    -- Botón (borde sólido 1px)
    button = {
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile     = false,
        tileSize = 0,
        edgeSize = 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    },
    -- Sin borde (filas de tabla, etc.)
    none = {
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        tile     = false,
        tileSize = 0,
        edgeSize = 0,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    },
}

-- ─────────────────────────────────────────────────────────────────────────
-- LAYOUT CONSTANTS  (idénticos al original para que los paneles no cambien)
-- ─────────────────────────────────────────────────────────────────────────

Colors.LAYOUT = {
    -- Debe coincidir con Constants.lua, Theme.lua y RenderizadoNuevo.lua.
    -- Colors.lua reemplaza a Theme.lua en el TOC y, por tanto, es el valor
    -- efectivo que recibe la ventana al crearse.
    windowWidth    = 1280,
    windowHeight   = 760,
    titlebarHeight = 64,
    tabHeight      = 40,
    sidebarWidth   = 220,
    footerHeight   = 36,
    padding        = 12,
    paddingSmall   = 8,
    paddingTiny    = 4,
    gap            = 6,
    gapSmall       = 4,
    rowHeight      = 28,
    rowHeightSmall = 22,
    rowHeightLarge = 32,
    borderWidth    = 1,
    buttonHeight   = 25,
    buttonHeightSmall = 22,
    buttonHeightLarge = 28,
}

-- ─────────────────────────────────────────────────────────────────────────
-- FONT CONSTANTS  (rutas nativas WoW)
-- ─────────────────────────────────────────────────────────────────────────

Colors.FONTS = {
    -- Friz conserva la identidad Warcraft en títulos y encabezados.
    title  = { path = "Fonts\\FRIZQT__.TTF", size = 17, flags = "OUTLINE" },
    -- Cuerpo: Arial Narrow sigue siendo compacta, pero ahora se renderiza
    -- con escala tipográfica global y una sombra más fuerte para no perderse.
    normal = { path = "Fonts\\ARIALN.TTF", size = 15, flags = "" },
    -- Datos/tablas: contorno para separar letras y números del fondo del juego.
    mono   = { path = "Fonts\\ARIALN.TTF", size = 14, flags = "OUTLINE" },
    -- Tamaños numéricos (usan FRIZQT por ser el fallback de normal)
    tiny   = 11,
    small  = 12,
    medium = 13,
    large  = 15,
    xlarge = 18,
    huge   = 22,
    giant  = 32,
}

-- ─────────────────────────────────────────────────────────────────────────
-- UTILITY METHODS  (misma API que el Theme original)
-- ─────────────────────────────────────────────────────────────────────────

function Colors:SetBackdropColor(frame, c)
    if not frame or not c then return end
    pcall(function()
        frame:SetBackdropColor(c.r, c.g, c.b, c.a or 1.0)
    end)
end

function Colors:SetBackdropBorderColor(frame, c)
    if not frame or not c then return end
    pcall(function()
        frame:SetBackdropBorderColor(c.r, c.g, c.b, c.a or 1.0)
    end)
end

function Colors:SetTextColor(fs, c)
    if not fs or not c then return end
    pcall(function()
        fs:SetTextColor(c.r, c.g, c.b, c.a or 1.0)
    end)
end

function Colors:SetVertexColor(tex, c)
    if not tex or not c then return end
    pcall(function()
        tex:SetVertexColor(c.r, c.g, c.b, c.a or 1.0)
    end)
end

-- ApplyFont: misma firma que el original
--   ApplyFont(fontString, fontType, size)
--   fontType puede ser "title", "normal", "mono", o un número (=tamaño, usa normal)
function Colors:GetTextScale()
    local db = MitzuMPlus.db
    local settings = db and db.profile and db.profile.settings
    local scale = settings and tonumber(settings.textScale) or 1.15
    if scale < 0.90 then scale = 0.90 end
    if scale > 1.40 then scale = 1.40 end
    return scale
end

-- Registro débil: permite cambiar el tamaño de texto en vivo sin recrear paneles.
Colors._fontRegistry = Colors._fontRegistry or setmetatable({}, { __mode = "k" })

function Colors:ApplyFont(fs, fontType, size)
    if not fs then return end
    local font
    local baseSize = size
    local resolvedType = fontType
    if type(fontType) == "number" then
        baseSize = fontType
        resolvedType = "normal"
        font = self.FONTS.normal
    elseif self.FONTS[fontType] then
        font = self.FONTS[fontType]
        if type(font) == "number" then
            baseSize = font
            resolvedType = "normal"
            font = self.FONTS.normal
        end
    else
        resolvedType = "normal"
        font = self.FONTS.normal
    end

    baseSize = baseSize or (type(font) == "table" and font.size) or 14
    self._fontRegistry[fs] = { fontType = resolvedType, size = baseSize }

    -- Escala de accesibilidad independiente de la escala de la ventana.
    -- Además fijamos un piso real para captions y tablas; 9-11 px eran
    -- técnicamente compactos pero ilegibles a 1080p/1440p con UI Scale de WoW.
    local scale = self:GetTextScale()
    local sz = math.floor((baseSize * scale) + 0.5)
    if resolvedType == "title" then
        if sz < 14 then sz = 14 end
    else
        if baseSize <= 10 and sz < 12 then sz = 12 end
        if baseSize == 11 and sz < 13 then sz = 13 end
        if baseSize == 12 and sz < 14 then sz = 14 end
        if baseSize >= 13 and sz < 15 then sz = 15 end
    end

    local flags = (type(font) == "table" and font.flags) or ""
    -- LibSharedMedia (opcional): si el usuario eligio una fuente y la
    -- libreria esta disponible, se usa la suya; si no, la del tema. El
    -- resolver vive en Theme para no duplicarlo, y si Theme no estuviera
    -- cargado se cae a la ruta del tema sin ruido.
    local path  = (type(font) == "table" and font.path)  or "Fonts\\FRIZQT__.TTF"
    local TH = MitzuMPlus.Theme
    if TH and TH.ResolveFontPath then
        local okPath, resolved = pcall(TH.ResolveFontPath, TH, path)
        if okPath and type(resolved) == "string" and resolved ~= "" then
            path = resolved
        end
    end
    local callOK, fontOK = pcall(function() return fs:SetFont(path, sz, flags) end)
    if not callOK or fontOK == false then
        pcall(function() fs:SetFont("Fonts\\FRIZQT__.TTF", sz, flags) end)
    end
    pcall(function()
        fs:SetShadowColor(0, 0, 0, resolvedType == "title" and 1.0 or 0.95)
        fs:SetShadowOffset(1, -1)
    end)
end

function Colors:RefreshFonts()
    if not self._fontRegistry then return end
    for fs, meta in pairs(self._fontRegistry) do
        if fs and meta then
            self:ApplyFont(fs, meta.fontType, meta.size)
        end
    end
end

function Colors:GetClassColor(classToken)
    return self.CLASS[classToken] or self.TEXT.primary
end

function Colors:GetStatusColor(status)
    if status == "ok" or status == "success" then return self.STATUS.ok
    elseif status == "bad" or status == "error" then return self.STATUS.bad
    elseif status == "warn" or status == "warning" then return self.STATUS.warn
    elseif status == "info" then return self.STATUS.info
    else return self.TEXT.primary end
end

-- SetGradientH: abstrae la diferencia de API entre WoW 9.x y 10.x
function Colors:SetGradientH(tex, r1, g1, b1, a1, r2, g2, b2, a2)
    if not tex then return end
    pcall(function()
        -- TWW / Retail ≥ 9.x: CreateColor objects
        if CreateColor then
            tex:SetGradient("HORIZONTAL",
                CreateColor(r1, g1, b1, a1 or 1),
                CreateColor(r2, g2, b2, a2 or 1))
        else
            tex:SetGradient("HORIZONTAL", r1, g1, b1, r2, g2, b2)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEY LEVEL TIERS (colores por rango de nivel de llave)
-- Portado desde UI/Theme.lua — Colors.lua reemplaza Theme como MitzuMPlus.Theme
-- ═══════════════════════════════════════════════════════════════════════════

Colors.KEY_TIERS = {
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

function Colors:GetKeyLevelTheme(level)
    level = tonumber(level) or 0
    for _, tier in ipairs(self.KEY_TIERS) do
        if level >= tier.min and level <= tier.max then
            return { text = tier.text, bg = tier.bg, border = tier.border }
        end
    end
    -- fallback: texto secundario si el nivel no cae en ningún tier
    return { text = self.TEXT.secondary, bg = self.BG.button, border = self.BORDER.panel }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- COMPATIBILITY ALIASES
-- Aliases de compatibilidad para módulos que usan claves del sistema Theme.
-- ═══════════════════════════════════════════════════════════════════════════

-- GOLD aliases
Colors.GOLD.title       = Colors.GOLD.gold3
Colors.GOLD.active      = Colors.GOLD.gold2
Colors.GOLD.border      = Colors.GOLD.gold0
Colors.GOLD.btnText     = Colors.GOLD.gold3
Colors.GOLD.btnPrimText = Colors.GOLD.gold5

-- BG aliases
Colors.BG.buttonHover   = Colors.BG.btnSecHover
Colors.BG.buttonPrim    = Colors.BG.btnPrim
Colors.BG.buttonPrimH   = { r = 0.220, g = 0.165, b = 0.039, a = 0.95 }
Colors.BG.rowSelected   = Colors.BG.rowSel
Colors.BG.summaryBar    = Colors.BG.panelHeader
Colors.BG.btnPrimHover  = Colors.BG.buttonPrimH

-- BORDER aliases
Colors.BORDER.inputFocus = Colors.GOLD.borderFocus

-- STATUS aliases
Colors.STATUS.okBg   = Colors.STATUS.okD
Colors.STATUS.badBg  = Colors.STATUS.badD
Colors.STATUS.warnBg = { r = 0.157, g = 0.102, b = 0.020, a = 0.80 }

-- ═══════════════════════════════════════════════════════════════════════════
-- STYLE BRIDGE METHODS  (compat with UI_Common.lua / Export.lua calls)
-- UI_Common checks `if Theme and Theme.StyleWindow then` — these ensure
-- the styled path is taken instead of the hardcoded fallback.
-- ═══════════════════════════════════════════════════════════════════════════

function Colors:StyleWindow(frame)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop(self.BACKDROPS.window)
    self:SetBackdropColor(frame, self.BG.window)
    self:SetBackdropBorderColor(frame, self.BORDER.window)
end

function Colors:StyleTitlebar(frame)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop(self.BACKDROPS.titlebar or self.BACKDROPS.simple)
    self:SetBackdropColor(frame, self.BG.titlebar)
end

function Colors:StylePanel(frame)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop(self.BACKDROPS.panel)
    self:SetBackdropColor(frame, self.BG.panel)
    self:SetBackdropBorderColor(frame, self.BORDER.panel)
end

function Colors:StyleButton(btn, isPrimary)
    if not btn or not btn.SetBackdrop then return end
    btn:SetBackdrop(self.BACKDROPS.button or self.BACKDROPS.panel)
    if isPrimary then
        self:SetBackdropColor(btn, self.BG.btnPrim)
        self:SetBackdropBorderColor(btn, self.GOLD.gold0)
        if btn.GetFontString and btn:GetFontString() then
            local fs = btn:GetFontString()
            fs:SetTextColor(self.GOLD.gold5.r, self.GOLD.gold5.g, self.GOLD.gold5.b)
        end
    else
        self:SetBackdropColor(btn, self.BG.button)
        self:SetBackdropBorderColor(btn, self.BORDER.panel)
        if btn.GetFontString and btn:GetFontString() then
            local fs = btn:GetFontString()
            fs:SetTextColor(self.GOLD.gold3.r, self.GOLD.gold3.g, self.GOLD.gold3.b)
        end
    end
    local selfRef = self
    btn:SetScript("OnEnter", function(self_btn)
        local hc = isPrimary and selfRef.BG.btnPrim or selfRef.BG.btnSecHover
        selfRef:SetBackdropColor(self_btn, hc)
        selfRef:SetBackdropBorderColor(self_btn, selfRef.GOLD.borderFocus)
    end)
    btn:SetScript("OnLeave", function(self_btn)
        local nc = isPrimary and selfRef.BG.btnPrim or selfRef.BG.button
        selfRef:SetBackdropColor(self_btn, nc)
        selfRef:SetBackdropBorderColor(self_btn, selfRef.BORDER.panel)
    end)
end

function Colors:SetTitleText(fontString, text)
    if not fontString then return end
    fontString:SetText(text)
    fontString:SetTextColor(self.GOLD.gold3.r, self.GOLD.gold3.g, self.GOLD.gold3.b)
end

function Colors:SetSectionHeader(fontString, text)
    if not fontString then return end
    fontString:SetText(text)
    fontString:SetTextColor(self.GOLD.sectionHead.r, self.GOLD.sectionHead.g, self.GOLD.sectionHead.b)
end

function Colors:SetNormalText(fontString, text)
    if not fontString then return end
    if text then fontString:SetText(text) end
    fontString:SetTextColor(self.TEXT.primary.r, self.TEXT.primary.g, self.TEXT.primary.b)
end

function Colors:SetDimText(fontString, text)
    if not fontString then return end
    if text then fontString:SetText(text) end
    fontString:SetTextColor(self.TEXT.dim.r, self.TEXT.dim.g, self.TEXT.dim.b)
end

return Colors
