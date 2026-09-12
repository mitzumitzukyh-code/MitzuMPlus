-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - UI/Panels/Config.lua  (FIX v3 - layout dinámico)
-- Panel de configuración — misma arquitectura que los demás paneles:
--   ScrollFrame de WidgetsCompat + frames WoW + Widgets nativas.
-- Conserva todos los callbacks y rutas db.profile.* del original.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
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
    local container
    if MitzuMPlus.Tabs and MitzuMPlus.Tabs.CreatePanelContainer then
        container = MitzuMPlus.Tabs:CreatePanelContainer(parent)
    else
        container = CreateFrame("Frame", nil, parent)
        container:SetAllPoints(parent)
    end

    -- ScrollFrame (mismo patrón que los demás paneles)
    local scrollFrame = WG():CreateScrollFrame(container)
    scrollFrame:SetPoint("TOPLEFT",     container,"TOPLEFT",     16, -16)
    scrollFrame:SetPoint("BOTTOMRIGHT", container,"BOTTOMRIGHT", -16,  16)

    local content = scrollFrame.scrollChild
    content:SetWidth(1)

    scrollFrame:SetScript("OnSizeChanged", function(self)
        if not self.scrollChild then return end
        local w = self:GetWidth() or 0
        self.scrollChild:SetWidth(math.max(1, w - 20))
        self:UpdateScrollRange()
    end)
    scrollFrame:HookScript("OnShow", function(self)
        if not self.scrollChild then return end
        local w = self:GetWidth() or 0
        self.scrollChild:SetWidth(math.max(1, w - 20))
        self:UpdateScrollRange()
    end)

    local yOff = 0

    -- ── SECCIÓN: GENERAL ─────────────────────────────────────────────────
    local secGeneral = MakeSection(content, ">> CONFIGURACIÓN GENERAL", 290)
    secGeneral:SetPoint("TOPLEFT",  content,"TOPLEFT",  0, yOff)
    secGeneral:SetPoint("TOPRIGHT", content,"TOPRIGHT", 0, yOff)

    MakeToggleRow(secGeneral,
        "Registrar automáticamente",
        "Registra las runs completadas de forma automática",
        function() return S().autoActivateTracking ~= false end,
        function(v) S().autoActivateTracking = v end)

    MakeToggleRow(secGeneral,
        "Solo runs en tiempo",
        "Registra únicamente runs completadas dentro del tiempo límite",
        function() return P().onlyInTime or false end,
        function(v) P().onlyInTime = v end)

    MakeToggleRow(secGeneral,
        "Registrar detalles completos",
        "Incluye estadísticas de combate: DPS, healing, muertes, etc.",
        function()
            local t = S().tracking
            return t == nil or t.damage ~= false
        end,
        function(v)
            if not S().tracking then S().tracking = {} end
            S().tracking.damage = v
        end)

    MakeToggleRow(secGeneral,
        "Compartir datos con grupo",
        "Permite que otros jugadores vean tus estadísticas",
        function() return P().shareData or false end,
        function(v) P().shareData = v end)

    MakeSliderRow(secGeneral,
        "Nivel mínimo de llave",
        1, 25,
        function() return P().minKeyLevel or 2 end,
        function(v) P().minKeyLevel = v end)

    FinishSection(secGeneral)
    yOff = yOff - secGeneral:GetHeight() - 14

    -- ── SECCIÓN: INTERFAZ ─────────────────────────────────────────────────
    local secUI = MakeSection(content, ">> INTERFAZ", 315)
    secUI:SetPoint("TOPLEFT",  content,"TOPLEFT",  0, yOff)
    secUI:SetPoint("TOPRIGHT", content,"TOPRIGHT", 0, yOff)

    MakeToggleRow(secUI,
        "Mostrar botón de minimapa",
        "Muestra el ícono de MitzuMPlus en el minimapa",
        function()
            return S().minimap == nil or (S().minimap and S().minimap.show ~= false)
        end,
        function(v)
            if not S().minimap then S().minimap = {} end
            S().minimap.show = v
            local ico = LibStub and LibStub("LibDBIcon-1.0", true)
            if ico then
                if v then ico:Show("MitzuMPlus_Historial")
                else       ico:Hide("MitzuMPlus_Historial") end
            end
        end)

    MakeToggleRow(secUI,
        "Bloquear ventana",
        "Evita que la ventana se mueva accidentalmente",
        function() return S().windowLocked or false end,
        function(v)
            S().windowLocked = v
            if MitzuMPlus.Window then MitzuMPlus.Window:SetMovable(not v) end
        end)

    MakeToggleRow(secUI,
        "Habilitar animaciones",
        "Animación de aparición al abrir la ventana",
        function() return S().enableAnimations ~= false end,
        function(v) S().enableAnimations = v end)

    MakeToggleRow(secUI,
        "Cerrar con Escape",
        "Permite cerrar la ventana presionando la tecla Escape",
        function() return S().closeWithEscape ~= false end,
        function(v) S().closeWithEscape = v end)

    MakeSliderRow(secUI,
        "Tamaño del texto de la interfaz  (%)",
        90, 140,
        function() return math.floor(((S().textScale or 1.15) * 100) + 0.5) end,
        function(v)
            S().textScale = v / 100
            local th = TH()
            if th and th.RefreshFonts then th:RefreshFonts() end
        end)

    -- ── Nivel de interfaz ────────────────────────────────────────────────
    -- Va el PRIMERO de la seccion a proposito: es el ajuste que mas cambia lo
    -- que ve el jugador, y el unico que alguien que empieza necesita tocar.
    do
        local LEVELS  = { "Aprendiendo", "Pro" }
        local current = (tostring(S().uiLevel or "PRO"):upper() == "LEARN") and 1 or 2

        MakeDropdownRow(secUI,
            "Nivel de interfaz",
            "Aprendiendo: te dice qué hacer y explica cada dato · Pro: todos los números",
            LEVELS, current,
            function(index)
                S().uiLevel = (index == 1) and "LEARN" or "PRO"
                -- Se repinta al momento para que se vea el cambio sin tener
                -- que entrar a una mazmorra a comprobarlo.
                if MitzuMPlus.OverlayFrame and MitzuMPlus.OverlayFrame.Refresh then
                    pcall(function() MitzuMPlus.OverlayFrame:Refresh() end)
                end
                MitzuMPlus:Print(index == 1
                    and "|cFF21de66Modo Aprendiendo:|r el Coach dirá qué hacer y explicará cada número."
                    or  "|cFF21de66Modo Pro:|r el Coach muestra todos los datos.")
            end)
    end

    -- ── Fuente de la interfaz (LibSharedMedia) ───────────────────────────
    -- La lista se construye AQUI, al crear el panel, no al cargar el archivo:
    -- LibSharedMedia la rellenan otros addons y en tiempo de carga puede estar
    -- todavia vacia. Al abrir Configuracion ya estan todos dentro.
    do
        -- OJO: no llamar a esta local `TH`. Arriba hay `local function TH()`
        -- y dentro de este bloque la tapaba, asi que las lineas de mas abajo
        -- que hacen `TH():ApplyFont(...)` intentaban invocar una tabla.
        local ThemeTbl = MitzuMPlus.Theme
        local fonts = (ThemeTbl and ThemeTbl.GetFontList) and ThemeTbl:GetFontList() or {}

        if #fonts == 0 then
            -- Sin LSM no se pinta un desplegable vacio que no hace nada: se
            -- dice por que no esta y como conseguirlo.
            local note = secUI:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            note:SetPoint("TOPLEFT",  secUI, "TOPLEFT",  14, secUI.innerY)
            note:SetPoint("TOPRIGHT", secUI, "TOPRIGHT", -14, secUI.innerY)
            note:SetJustifyH("LEFT")
            TH():ApplyFont(note, "normal", 12)
            local why = (ThemeTbl and ThemeTbl.LSMDiagnosis) and ThemeTbl:LSMDiagnosis() or nil
            note:SetText("Fuente de la interfaz: no hay lista que mostrar. " ..
                (why or "Requiere LibSharedMedia-3.0.") ..
                "  Escribe /emp fuentes para el detalle.")
            note:SetTextColor(0.55, 0.55, 0.55, 1)
            secUI.innerY = secUI.innerY - 34
        else
            -- Se antepone la opcion de volver al tema, para que se pueda
            -- deshacer sin tener que recordar cual era la fuente original.
            local items, current = { "(fuente del tema)" }, 1
            local chosen = S().uiFont
            for i, name in ipairs(fonts) do
                items[i + 1] = name
                if chosen and name == chosen then current = i + 1 end
            end

            MakeDropdownRow(secUI,
                "Fuente de la interfaz",
                "Se aplica al instante a toda la ventana; no hace falta recargar",
                items, current,
                function(index, value)
                    if index == 1 then
                        S().uiFont = nil
                    else
                        S().uiFont = value
                    end
                    -- Colors es quien tiene el registro debil de FontStrings,
                    -- asi que es el unico que puede repintar lo ya creado.
                    local C = MitzuMPlus.Colors
                    if C and C.RefreshFonts then C:RefreshFonts() end
                end)
        end
    end

    MakeSliderRow(secUI,
        "Opacidad de ventana  (%)",
        20, 100,
        function() return math.floor((S().windowOpacity or 0.92) * 100) end,
        function(v)
            local alpha = v / 100
            S().windowOpacity = alpha
            if MitzuMPlus.Window then MitzuMPlus.Window:SetAlpha(alpha) end
        end)

    FinishSection(secUI)
    yOff = yOff - secUI:GetHeight() - 14

    -- ── SECCIÓN: NOTIFICACIONES ───────────────────────────────────────────
    local secNotif = MakeSection(content, ">> NOTIFICACIONES", 228)
    secNotif:SetPoint("TOPLEFT",  content,"TOPLEFT",  0, yOff)
    secNotif:SetPoint("TOPRIGHT", content,"TOPRIGHT", 0, yOff)

    MakeToggleRow(secNotif,
        "Notificar al completar run",
        "Muestra un mensaje en pantalla al terminar una Mythic+",
        function() return P().notifyOnComplete ~= false end,
        function(v) P().notifyOnComplete = v end)

    MakeToggleRow(secNotif,
        "Notificar nuevo récord",
        "Alerta cuando superas tu mejor tiempo en una mazmorra",
        function() return P().notifyNewRecord ~= false end,
        function(v) P().notifyNewRecord = v end)

    MakeToggleRow(secNotif,
        "Notificar Personal Best",
        "Muestra un mensaje en chat cuando superas tu mejor marca",
        function() return P().notifyPersonalBest ~= false end,
        function(v) P().notifyPersonalBest = v end)

    MakeToggleRow(secNotif,
        "Resumen en chat",
        "Muestra un resumen de la run en el chat al terminar",
        function() return P().chatOutput or false end,
        function(v) P().chatOutput = v end)

    FinishSection(secNotif)
    yOff = yOff - secNotif:GetHeight() - 14

    -- ── SECCIÓN: M+ COACH ────────────────────────────────────────────────
    -- v6.0.0: incluye selector de modo, opciones del Coach y acceso al panel.
    local secCoach = MakeSection(content, ">> M+ COACH", 773)
    secCoach:SetPoint("TOPLEFT",  content,"TOPLEFT",  0, yOff)
    secCoach:SetPoint("TOPRIGHT", content,"TOPRIGHT", 0, yOff)

    MakeToggleRow(secCoach,
        "Coach en vivo",
        "Muestra la proyección de la key junto al tracker oficial de Blizzard",
        function() return S().overlayEnabled ~= false end,
        function(v)
            S().overlayEnabled = v
            if not v and MitzuMPlus.HideOverlay then MitzuMPlus:HideOverlay()
            elseif v and MitzuMPlus.ShowOverlay and C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then MitzuMPlus:ShowOverlay() end
        end)

    local modeLabel = { COMPLEMENT="Complemento", REPLACE="Reemplazo", COMPACT="Compacto" }
    local modeNext  = { COMPLEMENT="REPLACE", REPLACE="COMPACT", COMPACT="COMPLEMENT" }
    MakeButtonRow(secCoach, "Modo del tracker: " .. (modeLabel[S().coachDisplayMode or "COMPLEMENT"] or "Complemento"), function(btn)
        local current = tostring(S().coachDisplayMode or "COMPLEMENT"):upper()
        local nextMode = modeNext[current] or "COMPLEMENT"
        S().coachDisplayMode = nextMode
        if nextMode == "REPLACE" then S().coachAnchorBlizzard = true end
        btn:SetText("Modo del tracker: " .. modeLabel[nextMode])
        local overlay = MitzuMPlus.OverlayFrame
        if overlay then
            if nextMode ~= "REPLACE" and overlay.RestoreBlizzardTracker then overlay:RestoreBlizzardTracker() end
            overlay._anchorKey = nil
            if overlay.ApplyBackground then overlay:ApplyBackground(true) end
            if overlay.Reanchor then overlay:Reanchor(true) end
            if overlay:IsShown() and overlay.Refresh then overlay:Refresh() end
        end
    end, "primary")

    MakeToggleRow(secCoach,
        "Anclar al tracker de Blizzard",
        "Mantiene el Coach pegado al bloque oficial de Challenge Mode",
        function() return S().coachAnchorBlizzard ~= false end,
        function(v)
            S().coachAnchorBlizzard = v
            if MitzuMPlus.OverlayFrame and MitzuMPlus.OverlayFrame.Reanchor then MitzuMPlus.OverlayFrame:Reanchor(true) end
        end)

    MakeToggleRow(secCoach,
        "Bloquear posición del Coach",
        "Bloqueado no se arrastra y no intercepta clics sobre el mundo",
        function() return S().coachLocked == true end,
        function(v)
            S().coachLocked = v
            if MitzuMPlus.OverlayFrame and MitzuMPlus.OverlayFrame.ApplyMouse then
                MitzuMPlus.OverlayFrame:ApplyMouse()
            end
        end)

    -- v5.5.0: sin fondo el texto va con contorno negro y colores saturados.
    -- El rectángulo negro tapaba media mazmorra y era lo primero que molestaba.
    MakeToggleRow(secCoach,
        "Coach sin fondo",
        "Quita el recuadro negro: solo texto con contorno y color llamativo",
        function() return S().coachTransparent ~= false end,
        function(v)
            S().coachTransparent = v
            if MitzuMPlus.RefreshOverlayStyle then MitzuMPlus:RefreshOverlayStyle() end
        end)

    MakeToggleRow(secCoach,
        "Línea de ritmo",
        "Compara tu %/min real de fuerzas con el %/min necesario para entrar en tiempo",
        function() return S().coachShowPace ~= false end,
        function(v) S().coachShowPace = v end)

    MakeToggleRow(secCoach,
        "Línea de reloj",
        "Tiempo transcurrido / límite y cuánto queda (en rojo bajo 2 minutos)",
        function() return S().coachShowClock ~= false end,
        function(v) S().coachShowClock = v end)

    MakeToggleRow(secCoach,
        "Margen de muertes",
        "Cuántas muertes más caben antes de perder el nivel de llave proyectado",
        function() return S().coachShowDeathBudget ~= false end,
        function(v) S().coachShowDeathBudget = v end)

    MakeSliderRow(secCoach,
        "Tamaño del Coach  (%)",
        70, 200,
        function() return math.floor(((S().coachScale or 1.0) * 100) + 0.5) end,
        function(v)
            S().coachScale = v / 100
            if MitzuMPlus.OverlayFrame then
                if MitzuMPlus.OverlayFrame.ApplyScale then MitzuMPlus.OverlayFrame:ApplyScale() end
                MitzuMPlus.OverlayFrame:Reanchor(true)
            end
        end)

    FinishSection(secCoach)
    yOff = yOff - secCoach:GetHeight() - 14

    -- ── SECCIÓN: LOOT TRACKER ───────────────────────────────
    local secLoot = MakeSection(content, ">> LOOT TRACKER", 230)
    secLoot:SetPoint("TOPLEFT",  content,"TOPLEFT",  0, yOff)
    secLoot:SetPoint("TOPRIGHT", content,"TOPRIGHT", 0, yOff)

    MakeToggleRow(secLoot,
        "Registrar loot de compañeros",
        "Guarda los items que obtiene cada miembro del grupo durante la M+",
        function() return S().lootTracking ~= false end,
        function(v)
            S().lootTracking = v
            if MitzuMPlus.LootTracker then
                MitzuMPlus.LootTracker.enabled = v
            end
        end)

    MakeSliderRow(secLoot,
        "Nivel de objeto mínimo (ilvl)",
        0, 700,
        function() return S().lootMinIlvl or 0 end,
        function(v)
            S().lootMinIlvl = v
            if MitzuMPlus.LootTracker then
                MitzuMPlus.LootTracker.minIlvl = v
            end
        end)

    MakeSliderRow(secLoot,
        "Calidad mínima de item",
        0, 5,
        function() return S().lootMinQuality or 2 end,
        function(v)
            S().lootMinQuality = v
            if MitzuMPlus.LootTracker then
                MitzuMPlus.LootTracker.minQuality = v
            end
        end)

    -- Etiqueta aclaratoria de calidades
    do
        local qNote = secLoot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        qNote:SetPoint("TOPLEFT", secLoot, "TOPLEFT", 14, secLoot.innerY)
        qNote:SetText("Calidades: 0=Basura  1=Normal  2=Poco común  3=Raro  4=Épico  5=Legendario")
        qNote:SetTextColor(0.50, 0.50, 0.50, 1)
        secLoot.innerY = secLoot.innerY - 20
    end

    FinishSection(secLoot)
    yOff = yOff - secLoot:GetHeight() - 14

    -- ── SECCIÓN: GESTIÓN DE DATOS ─────────────────────────────────────────
    -- BUG FIX: runs is a hash table (non-consecutive numeric keys), not an array.
    -- #table only works for arrays. Use pairs() to count correctly.
    local runsCount = 0
    if MitzuMPlus.db and MitzuMPlus.db.global and MitzuMPlus.db.global.runs then
        for _ in pairs(MitzuMPlus.db.global.runs) do
            runsCount = runsCount + 1
        end
    end

    local secData = MakeSection(content, ">> GESTIÓN DE DATOS", 260)
    secData:SetPoint("TOPLEFT",  content,"TOPLEFT",  0, yOff)
    secData:SetPoint("TOPRIGHT", content,"TOPRIGHT", 0, yOff)

    MakeInfoRow(secData, "Runs registradas:", tostring(runsCount) .. " en base de datos")

    MakeButtonRow(secData, "Exportar a CSV",
        function()
            if MitzuMPlus.Export and MitzuMPlus.Export.ExportToCSV then
                MitzuMPlus.Export:ExportToCSV()
            else
                MitzuMPlus:Print("Exportación no disponible.")
            end
        end, "primary")

    MakeButtonRow(secData, "Restablecer configuracion",
        function() if StaticPopup_Show then StaticPopup_Show("MITZUMPLUS_CONFIRM_RESET_CONFIG") end end, "bad")

    MakeButtonRow(secData, "Borrar todos los datos",
        function() if StaticPopup_Show then StaticPopup_Show("MITZUMPLUS_CONFIRM_CLEAR_ALL") end end, "bad")

    MakeButtonRow(secData, "Validar integridad",
        function()
            if MitzuMPlus.DataManager then
                local valid, invalid = MitzuMPlus.DataManager:ValidateAllRuns()
                MitzuMPlus:Print(string.format(
                    "|cFFe8b84a[DataManager]|r %d válidas, %d corruptas.", valid, invalid))
                if invalid > 0 then
                    MitzuMPlus.DataManager:RemoveCorruptRuns()
                end
            end
        end, "primary")

    FinishSection(secData)
    yOff = yOff - secData:GetHeight() - 14

    -- ── SECCIÓN: ACERCA DE ────────────────────────────────────────────────
    local secAbout = MakeSection(content, ">> ACERCA DE", 130)
    secAbout:SetPoint("TOPLEFT",  content,"TOPLEFT",  0, yOff)
    secAbout:SetPoint("TOPRIGHT", content,"TOPRIGHT", 0, yOff)

    local titleFS = secAbout:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOPLEFT", secAbout, "TOPLEFT", 14, secAbout.innerY)
    titleFS:SetText("|cffFFD700MitzuMPlus M+ Historial|r")
    secAbout.innerY = secAbout.innerY - 22

    -- API-2 FIX: GetAddOnMetadata deprecada en 11.0 → C_AddOns.GetAddOnMetadata
    -- MitzuMPlus.VERSION ya contiene el valor correcto (Bootstrap.lua lo lee con
    -- la función correcta). Este fallback queda solo como seguro extra.
    local function _ReadVer(name)
        if C_AddOns and C_AddOns.GetAddOnMetadata then return C_AddOns.GetAddOnMetadata(name, "Version") end
        if GetAddOnMetadata then return GetAddOnMetadata(name, "Version") end
        return nil
    end
    local addonVer = MitzuMPlus.VERSION or _ReadVer("MitzuMPlus_Historial") or "?.?.?"

    local verFS = secAbout:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    verFS:SetPoint("TOPLEFT", secAbout, "TOPLEFT", 14, secAbout.innerY)
    verFS:SetText("Versión " .. addonVer ..
                  "  ·  Pro Player Edition  ·  Desarrollado por Mutzukyhs")
    verFS:SetTextColor(0.65, 0.65, 0.65, 1)
    secAbout.innerY = secAbout.innerY - 20

    local helpFS = secAbout:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    helpFS:SetPoint("TOPLEFT", secAbout,"TOPLEFT", 14, secAbout.innerY)
    helpFS:SetText("Comandos: |cffFFD700/MitzuMPlus help|r   ·   /emp help")
    helpFS:SetTextColor(0.55, 0.55, 0.55, 1)

    FinishSection(secAbout)
    yOff = yOff - secAbout:GetHeight() - 14

    -- Altura total del contenido
    content:SetHeight(math.abs(yOff) + 20)
    scrollFrame:UpdateScrollRange()

    self.panel       = container
    self.scrollFrame = scrollFrame
    self.content     = content

    if MitzuMPlus.Tabs then
        MitzuMPlus.Tabs:RegisterPanel("settings", container)
    end

    return container
end

-- ─────────────────────────────────────────────────────────────────────────
-- REFRESH
-- ─────────────────────────────────────────────────────────────────────────

function PanelConfig:Refresh()
    -- Los widgets leen S()/P() en tiempo de click, no necesitan refresh.
end

return PanelConfig
