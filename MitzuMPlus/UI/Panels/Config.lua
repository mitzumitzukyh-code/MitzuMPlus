-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - UI/Panels/Config.lua  (FIX v3 - layout dinámico)
-- Panel de configuración — misma arquitectura que los demás paneles:
--   ScrollFrame de WidgetsCompat + frames WoW + Widgets nativas.
-- Conserva todos los callbacks y rutas db.profile.* del original.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local L = MitzuMPlus.L
local EL = LibStub("AceLocale-3.0"):GetLocale("MitzuMPlusExperimental", true)

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
-- FILA: entrada numérica
-- ─────────────────────────────────────────────────────────────────────────

local _numN = 0
local function MakeNumericInputRow(section, labelText, descText, getValue, onChanged)
    _numN = _numN + 1
    local row = CreateFrame("Frame", nil, section)
    row:SetHeight(46)
    row:SetPoint("TOPLEFT", section, "TOPLEFT", 14, section.innerY)
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

    local edit = CreateFrame("EditBox", "MitzuCfgNum" .. _numN, row, "InputBoxTemplate")
    edit:SetSize(120, 28)
    edit:SetPoint("RIGHT", row, "RIGHT", 0, -5)
    edit:SetAutoFocus(false)
    edit:SetNumeric(true)
    edit:SetMaxLetters(5)
    local initial = math.max(0, math.floor(tonumber(getValue and getValue() or 0) or 0))
    edit:SetText(initial > 0 and tostring(initial) or "")

    local committing = false
    local function commit()
        if committing then return end
        committing = true
        local value = math.max(0, math.floor(tonumber(edit:GetText()) or 0))
        if onChanged then onChanged(value) end
        local fresh = math.max(0, math.floor(tonumber(getValue and getValue() or value) or 0))
        edit:SetText(fresh > 0 and tostring(fresh) or "")
        committing = false
    end
    edit:SetScript("OnEnterPressed", function(self) commit(); self:ClearFocus() end)
    edit:SetScript("OnEscapePressed", function(self)
        local fresh = math.max(0, math.floor(tonumber(getValue and getValue() or 0) or 0))
        self:SetText(fresh > 0 and tostring(fresh) or "")
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", commit)
    row.edit = edit
    row.Commit = commit
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
    MakeToggleRow(secGeneral, L["CFG_MINIMAP"],
        L["CFG_MINIMAP_D"],
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
    local secTracker = MakeSection(content, L["CFG_TRACKER_SECTION"], 430)
    MakeToggleRow(secTracker, L["CFG_TRACKER_ENABLED"],
        L["CFG_TRACKER_D"],
        function() return HS().enabled ~= false end,
        function(v) if HUD() then HUD():SetEnabled(v) end end)
    MakeToggleRow(secTracker, L["CFG_SHOW_PACE"],
        L["CFG_PREDICTION_D"],
        function() return HS().showPrediction ~= false end,
        function(v) if HUD() then HUD():SetOption("showPrediction", v) end end)
    MakeToggleRow(secTracker, L["CFG_UPGRADE_TIMES"],
        L["CFG_UPGRADE_TIMES_D"],
        function() return HS().showUpgradeTimes ~= false end,
        function(v) if HUD() then HUD():SetOption("showUpgradeTimes", v) end end)
    MakeToggleRow(secTracker, L["CFG_FORCES_COUNT"],
        L["CFG_FORCES_COUNT_D"],
        function() return HS().showForcesCount ~= false end,
        function(v) if HUD() then HUD():SetOption("showForcesCount", v) end end)
    MakeToggleRow(secTracker, L["CFG_FORCES_REMAINING"],
        L["CFG_FORCES_REMAINING_D"],
        function() return HS().showForcesRemaining ~= false end,
        function(v) if HUD() then HUD():SetOption("showForcesRemaining", v) end end)
    MakeToggleRow(secTracker, L["CFG_DEATHS"],
        L["CFG_DEATHS_D"],
        function() return HS().showDeaths ~= false end,
        function(v) if HUD() then HUD():SetOption("showDeaths", v) end end)
    MakeToggleRow(secTracker, L["CFG_LOCK_PREVIEW"],
        L["CFG_LOCK_PREVIEW_D"],
        function() return HS().locked == true end,
        function(v) if HUD() then HUD():SetOption("locked", v) end end)
    MakeToggleRow(secTracker, L["CFG_CONFIDENCE"],
        L["CFG_CONFIDENCE_D"],
        function() return HS().showConfidence ~= false end,
        function(v) if HUD() then HUD():SetOption("showConfidence", v) end end)
    MakeToggleRow(secTracker, L["CFG_ETA"],
        L["CFG_ETA_D"],
        function() return HS().showETA ~= false end,
        function(v) if HUD() then HUD():SetOption("showETA", v) end end)
    MakeSliderRow(secTracker, L["CFG_SCALE"], 60, 200,
        function() return math.floor(((tonumber(HS().scale) or 1) * 100) + 0.5) end,
        function(v) if HUD() then HUD():SetOption("scale", v / 100) end end)
    MakeSliderRow(secTracker, L["CFG_OPACITY"], 20, 100,
        function() return math.floor(((tonumber(HS().alpha) or 1) * 100) + 0.5) end,
        function(v) if HUD() then HUD():SetOption("alpha", v / 100) end end)
    MakeButtonRow(secTracker, L["CFG_PREVIEW_TOGGLE"], function()
        if HUD() then HUD():SetPreview(not HUD():IsPreview()) end
    end, "primary")
    MakeButtonRow(secTracker, L["CFG_RESET_POSITION"], function()
        if HUD() then HUD():ResetPosition() end
    end)
    place(secTracker)

    -- Native Blizzard UI controls. Kept inside the existing configuration window.
    if MitzuMPlus.ExperimentalNativeUI and EL then
        local function EC()
            return MitzuMPlus.ExperimentalNativeUI:GetConfig() or {}
        end
        local pullValues = { 5, 10, 20 }
        local pullLabels = { "5 s", "10 s", "20 s" }
        local current = tonumber(EC().pullTimerSeconds) or 10
        local currentIndex = current == 5 and 1 or (current == 20 and 3 or 2)
        local secNative = MakeSection(content, EL["CFG_NATIVE_UI_SECTION"], 200)
        local core = MitzuMPlus.ExperimentalNativeUI
        local function Goal() return core:GetCharacterGoal(false) or { enabled=false, target=0 } end
        local goalToggle
        goalToggle = MakeToggleRow(secNative, EL["CFG_SEASON_GOAL"], EL["CFG_SEASON_GOAL_D"],
            function() return Goal().enabled == true end,
            function(v)
                local ok = core:SetCharacterGoalEnabled(v)
                if v and not ok then
                    if goalToggle and goalToggle.toggle then goalToggle.toggle:SetChecked(false) end
                    if MitzuMPlus.Print then MitzuMPlus:Print(EL["CFG_SEASON_GOAL_REQUIRED"]) end
                end
                core:RefreshSeasonPanel("CONFIG_GOAL_ENABLE")
            end)
        MakeNumericInputRow(secNative, EL["CFG_SEASON_GOAL_TARGET"], EL["CFG_SEASON_GOAL_TARGET_D"],
            function() return Goal().target or 0 end,
            function(value)
                core:SetCharacterGoalTarget(value)
                local g = Goal()
                if goalToggle and goalToggle.toggle then goalToggle.toggle:SetChecked(g.enabled == true) end
                core:RefreshSeasonPanel("CONFIG_GOAL_TARGET")
            end)
        MakeDropdownRow(secNative, EL["CFG_PULL_TIMER"], EL["CFG_PULL_TIMER_D"],
            pullLabels, currentIndex, function(index)
                local value = pullValues[index] or 10
                local c = EC()
                c.pullTimerSeconds = value
                if MitzuMPlus.KeystoneFrameEnhancer and MitzuMPlus.KeystoneFrameEnhancer.RefreshLabels then
                    MitzuMPlus.KeystoneFrameEnhancer:RefreshLabels()
                end
            end)
        place(secNative)
    end

    local secUI = MakeSection(content, L["CFG_UI_SECTION"], 310)
    MakeToggleRow(secUI, L["CFG_LOCK_WINDOW"], L["CFG_LOCK_WINDOW_D"],
        function() return S().windowLocked == true end,
        function(v)
            S().windowLocked = v
            if MitzuMPlus.Window then MitzuMPlus.Window:SetMovable(not v) end
        end)
    MakeToggleRow(secUI, L["CFG_ANIMATIONS_LABEL"], L["CFG_ANIMATIONS_D"],
        function() return S().enableAnimations ~= false end,
        function(v) S().enableAnimations = v end)
    MakeToggleRow(secUI, L["CFG_ESC_CLOSE"], L["CFG_ESC_CLOSE_D"],
        function() return S().closeWithEscape ~= false end,
        function(v)
            S().closeWithEscape = v
            if MitzuMPlus.UpdateEscapeHandling then MitzuMPlus:UpdateEscapeHandling() end
        end)
    MakeSliderRow(secUI, L["CFG_TEXT_SIZE"], 90, 140,
        function() return math.floor(((S().textScale or 1.15) * 100) + 0.5) end,
        function(v)
            S().textScale = v / 100
            if TH() and TH().RefreshFonts then TH():RefreshFonts() end
        end)
    MakeSliderRow(secUI, L["CFG_WINDOW_OPACITY"], 20, 100,
        function() return math.floor(((S().windowOpacity or 1) * 100) + 0.5) end,
        function(v)
            S().windowOpacity = v / 100
            if MitzuMPlus.Window then MitzuMPlus.Window:SetAlpha(v / 100) end
        end)
    place(secUI)

    local secData = MakeSection(content, L["CFG_DATA_SECTION"], 390)
    MakeToggleRow(secData, L["CFG_LOOT"],
        L["CFG_LOOT_D"],
        function() return S().lootTracking ~= false end,
        function(v)
            S().lootTracking = v
            if MitzuMPlus.LootTracker then MitzuMPlus.LootTracker.enabled = v end
        end)
    -- Solo exponemos umbrales útiles para M+: Poco común, Raro y Épico.
    -- El valor guardado sigue siendo la calidad numérica nativa de WoW
    -- (2/3/4), de modo que LootTracker no necesita una traducción adicional.
    local lootQualityValues = { 2, 3, 4 }
    local lootQualityLabels = { L["QUALITY_UNCOMMON"], L["QUALITY_RARE"], L["QUALITY_EPIC"] }
    local savedLootQuality = tonumber(S().lootMinQuality) or 2
    local lootQualityIndex = savedLootQuality >= 4 and 3 or (savedLootQuality >= 3 and 2 or 1)
    -- Migrar perfiles antiguos que podían contener 0, 1 o 5 al nuevo selector.
    S().lootMinQuality = lootQualityValues[lootQualityIndex]
    if MitzuMPlus.LootTracker then
        MitzuMPlus.LootTracker.minQuality = S().lootMinQuality
    end
    MakeDropdownRow(secData, L["CFG_LOOT_QUALITY"],
        L["CFG_LOOT_QUALITY_D"],
        lootQualityLabels, lootQualityIndex,
        function(index)
            local quality = lootQualityValues[index] or 2
            S().lootMinQuality = quality
            if MitzuMPlus.LootTracker then MitzuMPlus.LootTracker.minQuality = quality end
        end)
    MakeSliderRow(secData, L["CFG_LOOT_ILVL"], 0, 700,
        function() return S().lootMinIlvl or 0 end,
        function(v)
            S().lootMinIlvl = v
            if MitzuMPlus.LootTracker then MitzuMPlus.LootTracker.minIlvl = v end
        end)
    MakeButtonRow(secData, L["CFG_VALIDATE"], function()
        if MitzuMPlus.DataManager then
            local valid, invalid = MitzuMPlus.DataManager:ValidateAllRuns()
            MitzuMPlus:Print(string.format(L["CFG_DATA_QUALITY"], valid, invalid))
        end
    end)
    place(secData)

    local secNotify = MakeSection(content, "NOTIFICACIONES", 230)
    MakeToggleRow(secNotify, L["CFG_NOTIF_RUN"], L["CFG_NOTIF_RUN_D"],
        function() return P().notifyOnComplete ~= false end,
        function(v) P().notifyOnComplete = v end)
    MakeToggleRow(secNotify, L["CFG_NOTIF_RECORD"], L["CFG_NOTIF_RECORD_D"],
        function() return P().notifyNewRecord ~= false end,
        function(v) P().notifyNewRecord = v end)
    MakeToggleRow(secNotify, L["CFG_NOTIF_PB"], L["CFG_NOTIF_PB_D"],
        function() return P().notifyPersonalBest ~= false end,
        function(v) P().notifyPersonalBest = v end)
    MakeToggleRow(secNotify, L["CFG_NOTIF_CHAT"], L["CFG_NOTIF_CHAT_D"],
        function() return P().chatOutput == true end,
        function(v) P().chatOutput = v end)
    MakeButtonRow(secNotify, L["CFG_TEST_NOTIF"], function()
        if MitzuMPlus.HandleSlashCommand then
            MitzuMPlus:HandleSlashCommand("testavisos")
        end
    end, "primary")
    place(secNotify)

    local secQA = MakeSection(content, L["CFG_QA_SECTION"], 190)
    MakeButtonRow(secQA, L["CFG_OPEN_BUGREPORT"], function()
        if MitzuMPlus.BugReport then MitzuMPlus.BugReport:Show() end
    end, "primary")
    MakeButtonRow(secQA, L["CFG_RESET_SETTINGS"], function()
        if StaticPopup_Show then StaticPopup_Show("MITZUMPLUS_CONFIRM_RESET_CONFIG") end
    end, "bad")
    MakeButtonRow(secQA, L["CFG_DELETE_HISTORY"], function()
        if StaticPopup_Show then StaticPopup_Show("MITZUMPLUS_CONFIRM_CLEAR_ALL") end
    end, "bad")
    place(secQA)

    local secAbout = MakeSection(content, L["CFG_ABOUT_SECTION"], 120)
    local title = secAbout:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", secAbout, "TOPLEFT", 14, secAbout.innerY)
    title:SetText("|cffFFD700MitzuMPlus|r")
    secAbout.innerY = secAbout.innerY - 24
    local info = secAbout:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    info:SetPoint("TOPLEFT", secAbout, "TOPLEFT", 14, secAbout.innerY)
    info:SetText(L["CFG_TAGLINE"] .. tostring(MitzuMPlus.VERSION or "?"))
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
