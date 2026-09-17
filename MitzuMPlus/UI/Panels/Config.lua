-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - UI/Panels/Config.lua  (FIX v3 - layout dinámico)
-- Panel de configuración — misma arquitectura que los demás paneles:
--   ScrollFrame de WidgetsCompat + frames WoW + Widgets nativas.
-- Conserva todos los callbacks y rutas db.profile.* del original.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

-- Referencias lazy (se resuelven en tiempo de ejecución, no de carga)
local function TH() return MitzuMPlus.Colors or MitzuMPlus.Theme end
local function WG() return MitzuMPlus.Widgets end

local PanelConfig = {}
MitzuMPlus.PanelConfig = PanelConfig

-- ─────────────────────────────────────────────────────────────────────────
-- HELPERS de acceso seguro al perfil
-- ─────────────────────────────────────────────────────────────────────────

local function S()
    if not MitzuMPlus.db then return {} end
    local p = MitzuMPlus.db.profile
    if not p.settings then p.settings = {} end
    return p.settings
end

local function P()
    if not MitzuMPlus.db then return {} end
    return MitzuMPlus.db.profile
end

-- ─────────────────────────────────────────────────────────────────────────
-- SECCIÓN: marco con cabecera dorada
-- ─────────────────────────────────────────────────────────────────────────

local function MakeSection(parent, title, sectionHeight)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    f:SetHeight(sectionHeight or 200)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true, tileSize=32, edgeSize=10,
            insets = {left=3,right=3,top=3,bottom=3},
        })
        f:SetBackdropColor(0.06, 0.06, 0.06, 0.85)
        f:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)
    end

    -- Fase 2.6: cabecera uniforme — 11px mono caps dorado
    -- IMPORTANTE: la fuente debe asignarse ANTES de SetText() en WoW
    local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")  -- fallback seguro
    hdr:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -14)
    local th = TH()
    if th and th.ApplyFont then
        th:ApplyFont(hdr, "mono", 11)
    end
    hdr:SetText(title or "")
    hdr:SetTextColor(0.784, 0.620, 0.188, 1)  -- gold3

    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT",  hdr, "BOTTOMLEFT",  0, -4)
    sep:SetPoint("TOPRIGHT", f,   "TOPRIGHT",  -14, -28)
    sep:SetHeight(1)
    sep:SetColorTexture(0.40, 0.36, 0.14, 0.55)

    f.hdr    = hdr
    f.innerY = -44    -- primer yOffset disponible bajo la cabecera
    return f
end

-- Calcula la altura real de una sección a partir de las filas creadas.
-- Evita que una sección pise a la siguiente cuando se agregan/quitan opciones.
local function FinishSection(section, bottomPadding)
    if not section then return 0 end
    local used = math.abs(tonumber(section.innerY) or -44) + (bottomPadding or 10)
    section:SetHeight(math.max(72, used))
    return section:GetHeight()
end

-- ─────────────────────────────────────────────────────────────────────────
-- FILA: toggle (checkbox) + label + descripción
-- ─────────────────────────────────────────────────────────────────────────

local function MakeToggleRow(section, labelText, descText, getState, onChanged)
    local row = CreateFrame("Frame", nil, section)
    row:SetHeight(44)
    row:SetPoint("TOPLEFT",  section,"TOPLEFT",  14, section.innerY)
    row:SetPoint("TOPRIGHT", section,"TOPRIGHT", -14, section.innerY)
    section.innerY = section.innerY - 48

    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(24,24)
    cb:SetPoint("RIGHT", row,"RIGHT", 0, 0)
    cb:SetChecked(getState())
    cb:SetScript("OnClick", function(self)
        onChanged(self:GetChecked())
    end)
    row.toggle = cb
    row.toggle.SetState = function(self,v) self:SetChecked(v) end

    -- Fase 2.6: label 13px normal primario, descripción 12px secondary
    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)
    lbl:SetPoint("RIGHT", cb, "LEFT", -10, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    TH():ApplyFont(lbl, "normal", 13)
    lbl:SetText(labelText or "")
    lbl:SetTextColor(0.95, 0.95, 0.95, 1)

    local dsc = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dsc:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -2)
    dsc:SetPoint("RIGHT", cb, "LEFT", -10, 0)
    dsc:SetJustifyH("LEFT")
    dsc:SetWordWrap(false)
    TH():ApplyFont(dsc, "normal", 12)
    dsc:SetText(descText or "")
    dsc:SetTextColor(0.72, 0.72, 0.72, 1)

    return row
end

-- ─────────────────────────────────────────────────────────────────────────
-- FILA: slider + label + descripción
-- ─────────────────────────────────────────────────────────────────────────

local _slN = 0
local function MakeSliderRow(section, labelText, minV, maxV, getVal, onChanged)
    _slN = _slN + 1
    local row = CreateFrame("Frame", nil, section)
    row:SetHeight(44)
    row:SetPoint("TOPLEFT",  section,"TOPLEFT",  14, section.innerY)
    row:SetPoint("TOPRIGHT", section,"TOPRIGHT", -14, section.innerY)
    section.innerY = section.innerY - 48

    local lbl = row:CreateFontString(nil,"OVERLAY","GameFontNormal")
    lbl:SetPoint("TOPLEFT", row,"TOPLEFT", 0, -4)
    TH():ApplyFont(lbl, "normal", 13)
    lbl:SetText(labelText)
    lbl:SetTextColor(0.93, 0.93, 0.93, 1)

    local s = CreateFrame("Slider","MitzuCfgSl".._slN, row,"OptionsSliderTemplate")
    s:SetPoint("RIGHT", row,"RIGHT", -8, -8)
    s:SetWidth(200)
    s:SetMinMaxValues(minV or 0, maxV or 100)
    s:SetValueStep(1)
    s:SetValue(getVal())
    local sn = s:GetName()
    if sn then
        if _G[sn.."Low"]  then TH():ApplyFont(_G[sn.."Low"], "mono", 11); _G[sn.."Low"]:SetText(tostring(minV or 0)) end
        if _G[sn.."High"] then TH():ApplyFont(_G[sn.."High"], "mono", 11); _G[sn.."High"]:SetText(tostring(maxV or 100)) end
        if _G[sn.."Text"] then TH():ApplyFont(_G[sn.."Text"], "mono", 12); _G[sn.."Text"]:SetText(tostring(getVal())) end
    end
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v)
        if sn and _G[sn.."Text"] then _G[sn.."Text"]:SetText(tostring(v)) end
        onChanged(v)
    end)

    row.slider = s
    return row
end

-- ─────────────────────────────────────────────────────────────────────────
-- FILA: desplegable
--
-- Usa Widgets:CreateDropdown, el mismo que la pestaña Historial, para que los
-- desplegables del addon se vean y se comporten igual en todas partes.
-- ─────────────────────────────────────────────────────────────────────────

local function MakeDropdownRow(section, labelText, descText, items, currentIndex, onSelect)
    local row = CreateFrame("Frame", nil, section)
    row:SetHeight(46)
    row:SetPoint("TOPLEFT",  section, "TOPLEFT",  14, section.innerY)
    row:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, section.innerY)
    section.innerY = section.innerY - 50

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    TH():ApplyFont(lbl, "normal", 13)
    lbl:SetText(labelText or "")
    lbl:SetTextColor(0.95, 0.95, 0.95, 1)

    local dsc = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dsc:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -2)
    dsc:SetJustifyH("LEFT")
    dsc:SetWordWrap(false)
    TH():ApplyFont(dsc, "normal", 12)
    dsc:SetText(descText or "")
    dsc:SetTextColor(0.72, 0.72, 0.72, 1)

    local W = WG()
    if W and W.CreateDropdown then
        local dd = W:CreateDropdown(row, 190, items, currentIndex or 1, onSelect)
        if dd then dd:SetPoint("RIGHT", row, "RIGHT", 0, -6) end
        row.dropdown = dd
    end
    return row
end

-- ─────────────────────────────────────────────────────────────────────────
-- FILA: label + valor (solo lectura, tipo estadística)
-- ─────────────────────────────────────────────────────────────────────────

local function MakeInfoRow(section, labelText, valueText, valueR, valueG, valueB)
    local row = CreateFrame("Frame", nil, section)
    row:SetHeight(28)
    row:SetPoint("TOPLEFT",  section,"TOPLEFT",  14, section.innerY)
    row:SetPoint("TOPRIGHT", section,"TOPRIGHT", -14, section.innerY)
    section.innerY = section.innerY - 30

    local lbl = row:CreateFontString(nil,"OVERLAY","GameFontNormal")
    lbl:SetPoint("LEFT", row,"LEFT", 0, 0)
    TH():ApplyFont(lbl, "normal", 12)
    lbl:SetText(labelText or "")
    lbl:SetTextColor(0.72, 0.72, 0.72, 1)

    local val = row:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    val:SetPoint("RIGHT", row,"RIGHT", 0, 0)
    TH():ApplyFont(val, "mono", 12)
    val:SetText(valueText or "")
    val:SetTextColor(valueR or 1, valueG or 0.82, valueB or 0, 1)

    row.valueFS = val
    return row
end

-- ─────────────────────────────────────────────────────────────────────────
-- FILA: botón de acción
-- ─────────────────────────────────────────────────────────────────────────

local function MakeButtonRow(section, btnText, onClick, btnStyle)
    local row = CreateFrame("Frame", nil, section)
    row:SetHeight(34)
    row:SetPoint("TOPLEFT",  section,"TOPLEFT",  14, section.innerY)
    row:SetPoint("TOPRIGHT", section,"TOPRIGHT", -14, section.innerY)
    section.innerY = section.innerY - 38

    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetHeight(26)
    btn:SetPoint("TOPLEFT",  row, "TOPLEFT",  0, -4)
    btn:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -4)
    btn:SetText(btnText or "")
    if btn:GetFontString() then TH():ApplyFont(btn:GetFontString(), "normal", 12) end
    if btnStyle == "bad" then
        local fs = btn:GetFontString()
        if fs then fs:SetTextColor(0.93, 0.30, 0.30, 1) end
    end
    btn:SetScript("OnClick", onClick or function() end)
    row.btn = btn
    return row
end

-- ─────────────────────────────────────────────────────────────────────────
-- CREATE PANEL
-- ─────────────────────────────────────────────────────────────────────────

function PanelConfig:Create(parent)
    local container = MitzuMPlus.Tabs and MitzuMPlus.Tabs:CreatePanelContainer(parent)
        or CreateFrame("Frame", nil, parent)
    if not MitzuMPlus.Tabs then container:SetAllPoints(parent) end

    local scrollFrame = WG():CreateScrollFrame(container)
    scrollFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 16, -16)
    scrollFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -16, 16)
    local content = scrollFrame.scrollChild
    content:SetWidth(1)
    scrollFrame:SetScript("OnSizeChanged", function(self)
        if self.scrollChild then
            self.scrollChild:SetWidth(math.max(1, (self:GetWidth() or 0) - 20))
            self:UpdateScrollRange()
        end
    end)

    local yOff = 0
    local function place(section)
        section:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
        section:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
        FinishSection(section)
        yOff = yOff - section:GetHeight() - 14
    end

    local secGeneral = MakeSection(content, "GENERAL", 100)
    MakeToggleRow(secGeneral, "Mostrar botón del minimapa",
        "Acceso rápido a MitzuMPlus desde el minimapa",
        function()
            local icon = S().minimapIcon
            return type(icon) ~= "table" or icon.hide ~= true
        end,
        function(value)
            S().minimapIcon = S().minimapIcon or {}
            S().minimapIcon.hide = not value
            local lib = LibStub and LibStub("LibDBIcon-1.0", true)
            if lib then if value then lib:Show("MitzuMPlus") else lib:Hide("MitzuMPlus") end end
        end)
    place(secGeneral)

    local function HUD() return MitzuMPlus.MitzuTracker end
    local function HS() local h = HUD(); return h and h:Settings() or {} end
    local secTracker = MakeSection(content, "TRACKER M+", 430)
    MakeToggleRow(secTracker, "Activado",
        "Tracker de la llave: tiempo, umbrales +3/+2/+1, ritmo, fuerzas, jefes y muertes",
        function() return HS().enabled ~= false end,
        function(v) if HUD() then HUD():SetEnabled(v) end end)
    MakeToggleRow(secTracker, "Bloquear posición",
        "Bloqueado no se arrastra ni intercepta clics",
        function() return HS().locked == true end,
        function(v) if HUD() then HUD():SetOption("locked", v) end end)
    MakeToggleRow(secTracker, "Mostrar confianza",
        "Muestra el porcentaje de confianza cuando el motor dispone de base",
        function() return HS().showConfidence ~= false end,
        function(v) if HUD() then HUD():SetOption("showConfidence", v) end end)
    MakeToggleRow(secTracker, "Mostrar ETA",
        "Muestra la hora estimada de finalización cuando es fiable",
        function() return HS().showETA ~= false end,
        function(v) if HUD() then HUD():SetOption("showETA", v) end end)
    MakeSliderRow(secTracker, "Escala  (%)", 60, 200,
        function() return math.floor(((tonumber(HS().scale) or 1) * 100) + 0.5) end,
        function(v) if HUD() then HUD():SetOption("scale", v / 100) end end)
    MakeSliderRow(secTracker, "Opacidad  (%)", 20, 100,
        function() return math.floor(((tonumber(HS().alpha) or 1) * 100) + 0.5) end,
        function(v) if HUD() then HUD():SetOption("alpha", v / 100) end end)
    MakeButtonRow(secTracker, "Vista previa: activar / desactivar", function()
        if HUD() then HUD():SetPreview(not HUD():IsPreview()) end
    end, "primary")
    MakeButtonRow(secTracker, "Restablecer posición", function()
        if HUD() then HUD():ResetPosition() end
    end)
    place(secTracker)

    local secUI = MakeSection(content, "INTERFAZ", 310)
    MakeToggleRow(secUI, "Bloquear ventana", "Evita mover la ventana accidentalmente",
        function() return S().windowLocked == true end,
        function(v)
            S().windowLocked = v
            if MitzuMPlus.Window then MitzuMPlus.Window:SetMovable(not v) end
        end)
    MakeToggleRow(secUI, "Animaciones", "Transición breve al cambiar de vista",
        function() return S().enableAnimations ~= false end,
        function(v) S().enableAnimations = v end)
    MakeToggleRow(secUI, "Cerrar con Escape", "Cierra MitzuMPlus con la tecla Escape",
        function() return S().closeWithEscape ~= false end,
        function(v)
            S().closeWithEscape = v
            if MitzuMPlus.UpdateEscapeHandling then MitzuMPlus:UpdateEscapeHandling() end
        end)
    MakeSliderRow(secUI, "Tamaño del texto  (%)", 90, 140,
        function() return math.floor(((S().textScale or 1.15) * 100) + 0.5) end,
        function(v)
            S().textScale = v / 100
            if TH() and TH().RefreshFonts then TH():RefreshFonts() end
        end)
    MakeSliderRow(secUI, "Opacidad de ventana  (%)", 20, 100,
        function() return math.floor(((S().windowOpacity or 1) * 100) + 0.5) end,
        function(v)
            S().windowOpacity = v / 100
            if MitzuMPlus.Window then MitzuMPlus.Window:SetAlpha(v / 100) end
        end)
    place(secUI)

    local secData = MakeSection(content, "HISTORIAL / DATOS", 390)
    MakeToggleRow(secData, "Registrar botín del grupo",
        "Conserva el botín para el detalle visible de cada jugador",
        function() return S().lootTracking ~= false end,
        function(v)
            S().lootTracking = v
            if MitzuMPlus.LootTracker then MitzuMPlus.LootTracker.enabled = v end
        end)
    -- Solo exponemos umbrales útiles para M+: Poco común, Raro y Épico.
    -- El valor guardado sigue siendo la calidad numérica nativa de WoW
    -- (2/3/4), de modo que LootTracker no necesita una traducción adicional.
    local lootQualityValues = { 2, 3, 4 }
    local lootQualityLabels = { "Poco común", "Raro", "Épico" }
    local savedLootQuality = tonumber(S().lootMinQuality) or 2
    local lootQualityIndex = savedLootQuality >= 4 and 3 or (savedLootQuality >= 3 and 2 or 1)
    -- Migrar perfiles antiguos que podían contener 0, 1 o 5 al nuevo selector.
    S().lootMinQuality = lootQualityValues[lootQualityIndex]
    if MitzuMPlus.LootTracker then
        MitzuMPlus.LootTracker.minQuality = S().lootMinQuality
    end
    MakeDropdownRow(secData, "Calidad mínima del botín",
        "Guarda objetos de esta calidad o superior",
        lootQualityLabels, lootQualityIndex,
        function(index)
            local quality = lootQualityValues[index] or 2
            S().lootMinQuality = quality
            if MitzuMPlus.LootTracker then MitzuMPlus.LootTracker.minQuality = quality end
        end)
    MakeSliderRow(secData, "Nivel de objeto mínimo", 0, 700,
        function() return S().lootMinIlvl or 0 end,
        function(v)
            S().lootMinIlvl = v
            if MitzuMPlus.LootTracker then MitzuMPlus.LootTracker.minIlvl = v end
        end)
    MakeButtonRow(secData, "Validar integridad del historial", function()
        if MitzuMPlus.DataManager then
            local valid, invalid = MitzuMPlus.DataManager:ValidateAllRuns()
            MitzuMPlus:Print(string.format("%d válidas · %d con problemas", valid, invalid))
        end
    end)
    place(secData)

    local secNotify = MakeSection(content, "NOTIFICACIONES", 230)
    MakeToggleRow(secNotify, "Al completar run", "Aviso en pantalla al terminar la llave",
        function() return P().notifyOnComplete ~= false end,
        function(v) P().notifyOnComplete = v end)
    MakeToggleRow(secNotify, "Nuevo récord", "Aviso en pantalla y chat al superar la mejor llave",
        function() return P().notifyNewRecord ~= false end,
        function(v) P().notifyNewRecord = v end)
    MakeToggleRow(secNotify, "Marca personal", "Aviso en pantalla y chat al mejorar tiempo o rendimiento",
        function() return P().notifyPersonalBest ~= false end,
        function(v) P().notifyPersonalBest = v end)
    MakeToggleRow(secNotify, "Resumen en chat", "Escribe un resumen al finalizar",
        function() return P().chatOutput == true end,
        function(v) P().chatOutput = v end)
    MakeButtonRow(secNotify, "Probar notificaciones", function()
        if MitzuMPlus.HandleSlashCommand then
            MitzuMPlus:HandleSlashCommand("testavisos")
        end
    end, "primary")
    place(secNotify)

    local secQA = MakeSection(content, "AVANZADO / QA", 190)
    MakeButtonRow(secQA, "Abrir Bug Report", function()
        if MitzuMPlus.BugReport then MitzuMPlus.BugReport:Show() end
    end, "primary")
    MakeButtonRow(secQA, "Restablecer configuración", function()
        if StaticPopup_Show then StaticPopup_Show("MITZUMPLUS_CONFIRM_RESET_CONFIG") end
    end, "bad")
    MakeButtonRow(secQA, "Borrar todo el historial", function()
        if StaticPopup_Show then StaticPopup_Show("MITZUMPLUS_CONFIRM_CLEAR_ALL") end
    end, "bad")
    place(secQA)

    local secAbout = MakeSection(content, "ACERCA DE", 120)
    local title = secAbout:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", secAbout, "TOPLEFT", 14, secAbout.innerY)
    title:SetText("|cffFFD700MitzuMPlus|r")
    secAbout.innerY = secAbout.innerY - 24
    local info = secAbout:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    info:SetPoint("TOPLEFT", secAbout, "TOPLEFT", 14, secAbout.innerY)
    info:SetText("Mythic+ History & Key Prediction  ·  v" .. tostring(MitzuMPlus.VERSION or "?"))
    info:SetTextColor(0.65, 0.65, 0.65, 1)
    place(secAbout)

    content:SetHeight(math.abs(yOff) + 20)
    scrollFrame:UpdateScrollRange()
    self.panel, self.scrollFrame, self.content = container, scrollFrame, content
    if MitzuMPlus.Tabs then MitzuMPlus.Tabs:RegisterPanel("settings", container) end
    return container
end

-- ─────────────────────────────────────────────────────────────────────────
-- REFRESH
-- ─────────────────────────────────────────────────────────────────────────

function PanelConfig:Refresh()
    -- Los widgets leen S()/P() en tiempo de click, no necesitan refresh.
end

return PanelConfig
