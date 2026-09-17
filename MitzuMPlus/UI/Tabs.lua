-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Tabs System
-- FIXES v2.0.1:
--   BUG1: CreateContentArea anclaba al TOPLEFT del body (mismo punto que la
--         barra de pestañas), haciendo que todo el contenido de los paneles
--         quedara DETRÁS de las pestañas. Ahora se ancla al BOTTOMLEFT de
--         tabsBar para que empiece DEBAJO de ellas.
--   BUG2: Todos los paneles llamaban RegisterPanel("xxx", parent) siendo
--         parent el MISMO contentArea compartido. Al ocultar un panel se
--         ocultaba el frame compartido, borrando TODOS los paneles a la vez.
--         Ahora CreateContentArea expone un helper CreatePanelContainer() que
--         cada panel usa para obtener su propio frame hijo dedicado.
-- v2.1: Añadida pestaña TEMPORADA (seasonsync) entre COMPARATIVA y CONFIGURACION
-- v5.5.0: eliminadas las pestañas ESTADISTICAS y COMPARATIVA.
-- v6.0.0: ESTADISTICAS vuelve con filtros y sin métricas fabricadas.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local Theme = MitzuMPlus.Theme
local L = MitzuMPlus.L
local Tabs = {}
-- SYNC-2 FIX: UI/MainFrame.lua excluido del TOC. Esta es la única asignación
-- de MitzuMPlus.Tabs en todo el addon. Sin doble asignación ni race condition.
MitzuMPlus.Tabs = Tabs

Tabs.activeTab = "historial"
Tabs.buttons = {}
Tabs.panels = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- TAB DEFINITIONS
-- ═══════════════════════════════════════════════════════════════════════════

local ICON_PATH = "Interface\\AddOns\\MitzuMPlus\\Media\\Icons\\"

-- Tab icon layout shared by every tab. 20 px keeps the icon on whole pixels
-- inside the 40 px tab; inactive icons are slightly dimmed, hover and the
-- active tab show them at full alpha.
local TAB_ICON_SIZE       = 20
local TAB_ICON_GAP        = 6
local TAB_PADDING_X       = 10
local TAB_ICON_IDLE_ALPHA = 0.85

local TAB_DEFS = {
    {
        id   = "historial",
        icon = ICON_PATH .. "tab_history_64",
        text = L["TABBAR_HISTORY"],
        badge = nil,
    },
    {
        id   = "stats",
        icon = ICON_PATH .. "tab_statistics_64",
        text = L["TABBAR_STATS"],
        badge = nil,
    },
    {
        id   = "players",
        icon = ICON_PATH .. "tab_players_64",
        text = L["TABBAR_PLAYERS"],
        badge = nil,
    },
    {
        id   = "settings",
        icon = ICON_PATH .. "tab_settings_64",
        text = L["TABBAR_SETTINGS"],
        badge = nil,
    },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE TABS BAR
-- ═══════════════════════════════════════════════════════════════════════════

function Tabs:Create(parent)
    local tabsBar = CreateFrame("Frame", nil, parent.body, BackdropTemplateMixin and "BackdropTemplate")
    tabsBar:ClearAllPoints()
    tabsBar:SetPoint("TOPLEFT",  parent.body, "TOPLEFT",  0, 0)
    tabsBar:SetPoint("TOPRIGHT", parent.body, "TOPRIGHT", 0, 0)
    tabsBar:SetHeight(Theme.LAYOUT.tabHeight)

    tabsBar:SetBackdrop(Theme.BACKDROPS.simple)
    Theme:SetBackdropColor(tabsBar, Theme.BG.void)

    local bottomBorder = tabsBar:CreateTexture(nil, "BORDER")
    bottomBorder:SetPoint("BOTTOMLEFT",  tabsBar, "BOTTOMLEFT",  0, 0)
    bottomBorder:SetPoint("BOTTOMRIGHT", tabsBar, "BOTTOMRIGHT", 0, 0)
    bottomBorder:SetHeight(1)
    bottomBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(bottomBorder, Theme.GOLD.gold0)

    local xOffset = 0

    for i, tabDef in ipairs(TAB_DEFS) do
        local tabBtn = self:CreateTabButton(tabsBar, tabDef, i)
        tabBtn:SetPoint("TOPLEFT", tabsBar, "TOPLEFT", xOffset, 0)
        self.buttons[tabDef.id] = tabBtn
        xOffset = xOffset + tabBtn:GetWidth()
    end

    self.container = tabsBar
    parent.tabsBar  = tabsBar

    -- CreateContentArea asigna parent.contentArea para que Init.lua pueda
    -- usarlo al crear los paneles. NO llamar SetActiveTab aquí porque los
    -- paneles aún no existen — Init.lua llama SetActiveTab después de crearlos.
    self:CreateContentArea(parent)

    return tabsBar
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE INDIVIDUAL TAB BUTTON
-- ═══════════════════════════════════════════════════════════════════════════

function Tabs:CreateTabButton(parent, tabDef, index)
    local btn = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    btn:SetHeight(Theme.LAYOUT.tabHeight)

    btn:SetBackdrop(Theme.BACKDROPS.simple)
    Theme:SetBackdropColor(btn, Theme.BG.void)

    local rightBorder = btn:CreateTexture(nil, "BORDER")
    rightBorder:SetPoint("TOPRIGHT",    btn, "TOPRIGHT",    0, 0)
    rightBorder:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    rightBorder:SetWidth(1)
    rightBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(rightBorder, Theme.BORDER.separator)

    local iconTex = btn:CreateTexture(nil, "OVERLAY")
    iconTex:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)
    iconTex:SetPoint("LEFT", btn, "LEFT", TAB_PADDING_X, 0)
    iconTex:SetTexture(tabDef.icon)
    iconTex:SetAlpha(TAB_ICON_IDLE_ALPHA)

    local text = btn:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", iconTex, "RIGHT", TAB_ICON_GAP, 0)
    Theme:ApplyFont(text, "normal", 13)
    text:SetText(tabDef.text)
    Theme:SetTextColor(text, Theme.TEXT.tertiary)

    btn.iconTex = iconTex
    btn.text    = text
    btn.tabId   = tabDef.id

    local textWidth = text:GetStringWidth()
    btn:SetWidth(TAB_PADDING_X + TAB_ICON_SIZE + TAB_ICON_GAP + textWidth + TAB_PADDING_X)

    if tabDef.badge then
        local badge = CreateFrame("Frame", nil, btn, BackdropTemplateMixin and "BackdropTemplate")
        badge:SetPoint("LEFT", text, "RIGHT", 6, 0)
        badge:SetSize(24, 16)
        badge:SetBackdrop(Theme.BACKDROPS.simple)
        Theme:SetBackdropColor(badge, Theme.GOLD.gold2)

        local badgeText = badge:CreateFontString(nil, "OVERLAY")
        badgeText:SetPoint("CENTER")
        Theme:ApplyFont(badgeText, "mono", 12)
        badgeText:SetText(tostring(tabDef.badge))
        badgeText:SetTextColor(0, 0, 0, 1)

        btn.badge     = badge
        btn.badgeText = badgeText
        btn:SetWidth(btn:GetWidth() + 30)
    end

    -- ── Indicador activo: glow gradient de 3 partes ─────────────────────────
    -- Izquierda: transparente → dorado
    local indLeft = btn:CreateTexture(nil, "OVERLAY")
    indLeft:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    indLeft:SetHeight(3)
    indLeft:SetWidth(20)
    indLeft:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetGradientH(indLeft,
        Theme.BG.void.r, Theme.BG.void.g, Theme.BG.void.b, 0,
        Theme.GOLD.gold4.r, Theme.GOLD.gold4.g, Theme.GOLD.gold4.b, 1)
    indLeft:Hide()

    -- Derecha: dorado → transparente
    local indRight = btn:CreateTexture(nil, "OVERLAY")
    indRight:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    indRight:SetHeight(3)
    indRight:SetWidth(20)
    indRight:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetGradientH(indRight,
        Theme.GOLD.gold4.r, Theme.GOLD.gold4.g, Theme.GOLD.gold4.b, 1,
        Theme.BG.void.r, Theme.BG.void.g, Theme.BG.void.b, 0)
    indRight:Hide()

    -- Centro: dorado sólido entre los dos gradientes
    local indCenter = btn:CreateTexture(nil, "OVERLAY")
    indCenter:SetPoint("BOTTOMLEFT",  indLeft,  "BOTTOMRIGHT", 0, 0)
    indCenter:SetPoint("BOTTOMRIGHT", indRight, "BOTTOMLEFT",  0, 0)
    indCenter:SetHeight(3)
    indCenter:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(indCenter, Theme.GOLD.gold4)
    indCenter:Hide()

    -- Wrapper para Show/Hide los 3 de golpe
    local activeIndicator = {
        _left   = indLeft,
        _center = indCenter,
        _right  = indRight,
    }
    function activeIndicator:Show()
        self._left:Show(); self._center:Show(); self._right:Show()
    end
    function activeIndicator:Hide()
        self._left:Hide(); self._center:Hide(); self._right:Hide()
    end

    btn.activeIndicator = activeIndicator

    btn:SetScript("OnEnter", function(self)
        if self.tabId ~= Tabs.activeTab then
            Theme:SetTextColor(self.text, Theme.GOLD.gold4)
            Theme:SetBackdropColor(self, { r = 0.118, g = 0.086, b = 0.024, a = 0.65 })
            self.iconTex:SetAlpha(1)
        end
    end)

    btn:SetScript("OnLeave", function(self)
        if self.tabId ~= Tabs.activeTab then
            Theme:SetTextColor(self.text, Theme.TEXT.tertiary)
            Theme:SetBackdropColor(self, Theme.BG.void)
            self.iconTex:SetAlpha(TAB_ICON_IDLE_ALPHA)
        end
    end)

    btn:SetScript("OnClick", function(self)
        Tabs:SetActiveTab(self.tabId)
    end)

    return btn
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE CONTENT AREA
-- FIX BUG1: se ancla al BOTTOMLEFT de tabsBar, no al TOPLEFT del body.
-- ═══════════════════════════════════════════════════════════════════════════

function Tabs:CreateContentArea(parent)
    local content = CreateFrame("Frame", nil, parent.body, BackdropTemplateMixin and "BackdropTemplate")
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT",     parent.tabsBar, "BOTTOMLEFT",  0, 0)
    content:SetPoint("BOTTOMRIGHT", parent.body,    "BOTTOMRIGHT", 0, 0)

    content:SetBackdrop(Theme.BACKDROPS.simple)
    Theme:SetBackdropColor(content, Theme.BG.void)

    parent.contentArea = content

    return content
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE PANEL CONTAINER
-- FIX BUG2: cada panel obtiene su propio frame hijo dentro del contentArea
-- ═══════════════════════════════════════════════════════════════════════════

function Tabs:CreatePanelContainer(contentArea)
    local container = CreateFrame("Frame", nil, contentArea)
    container:SetAllPoints(contentArea)
    container:Hide()
    return container
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SET ACTIVE TAB
-- ═══════════════════════════════════════════════════════════════════════════

function Tabs:SetActiveTab(tabId)
    if not self.buttons[tabId] then return end

    self.activeTab = tabId

    for id, btn in pairs(self.buttons) do
        if id == tabId then
            Theme:SetTextColor(btn.text, Theme.GOLD.gold5)
            -- Fase 2.7: doble indicador — fondo dorado sutil + subrayado
            Theme:SetBackdropColor(btn, { r = 0.290, g = 0.235, b = 0.094, a = 0.15 })
            btn.activeIndicator:Show()
            btn.iconTex:SetAlpha(1)
        else
            Theme:SetTextColor(btn.text, Theme.TEXT.tertiary)
            Theme:SetBackdropColor(btn, Theme.BG.void)
            btn.activeIndicator:Hide()
            btn.iconTex:SetAlpha(btn:IsMouseOver() and 1 or TAB_ICON_IDLE_ALPHA)
        end
    end

    for id, panel in pairs(self.panels) do
        if id == tabId then
            -- Fase 2.5: animación de entrada del panel activo
            local animEnabled = MitzuMPlus.db and MitzuMPlus.db.profile and
                                MitzuMPlus.db.profile.settings and
                                MitzuMPlus.db.profile.settings.enableAnimations
            panel:Show()
            if animEnabled then
                panel:SetAlpha(0)
                UIFrameFadeIn(panel, 0.15, 0, 1)
            else
                panel:SetAlpha(1)
            end
        else
            panel:Hide()
        end
    end

    if MitzuMPlus.RefreshActivePanel then
        MitzuMPlus:RefreshActivePanel()
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- REGISTER PANEL
-- ═══════════════════════════════════════════════════════════════════════════

function Tabs:RegisterPanel(tabId, panel)
    self.panels[tabId] = panel

    -- Si esta pestaña ya es la activa (SetActiveTab corrió antes),
    -- mostrar el panel directamente. Si no, ocultarlo.
    if tabId == self.activeTab then
        panel:Show()
        panel:SetAlpha(1)
    else
        panel:Hide()
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- UPDATE TAB BADGE
-- ═══════════════════════════════════════════════════════════════════════════

function Tabs:UpdateBadge(tabId, value)
    local btn = self.buttons[tabId]
    if not btn then return end

    if value and value > 0 then
        if not btn.badge then
            local badge = CreateFrame("Frame", nil, btn, BackdropTemplateMixin and "BackdropTemplate")
            badge:SetPoint("LEFT", btn.text, "RIGHT", 6, 0)
            badge:SetSize(24, 16)
            badge:SetBackdrop(Theme.BACKDROPS.simple)
            Theme:SetBackdropColor(badge, Theme.GOLD.gold2)

            local badgeText = badge:CreateFontString(nil, "OVERLAY")
            badgeText:SetPoint("CENTER")
            Theme:ApplyFont(badgeText, "mono", 12)
            badgeText:SetTextColor(0, 0, 0, 1)

            btn.badge     = badge
            btn.badgeText = badgeText
        end

        btn.badgeText:SetText(tostring(value))
        btn.badge:Show()
    else
        if btn.badge then
            btn.badge:Hide()
        end
    end
end

return Tabs
