-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Window Components
-- Componentes auxiliares para la ventana principal
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local Theme = MitzuMPlus.Theme

-- ═══════════════════════════════════════════════════════════════════════════
-- WINDOW COMPONENTS (usados por CreateMainWindow en Init.lua)
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- TITLEBAR
-- ═══════════════════════════════════════════════════════════════════════════

function MitzuMPlus:CreateTitlebar(parent)
    local titlebar = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    titlebar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    titlebar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    titlebar:SetHeight(Theme.LAYOUT.titlebarHeight)
    
    titlebar:SetBackdrop(Theme.BACKDROPS.simple)
    Theme:SetBackdropColor(titlebar, Theme.BG.titlebar)
    
    -- ── Glow gradient en el borde inferior del titlebar ─────────────────────
    -- Izquierda: transparente → dorado
    local glowLeft = titlebar:CreateTexture(nil, "BORDER")
    glowLeft:SetPoint("BOTTOMLEFT", titlebar, "BOTTOMLEFT", 0, 0)
    glowLeft:SetHeight(2)
    glowLeft:SetWidth(160)
    glowLeft:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetGradientH(glowLeft,
        Theme.BG.void.r, Theme.BG.void.g, Theme.BG.void.b, 0,
        Theme.GOLD.gold3.r, Theme.GOLD.gold3.g, Theme.GOLD.gold3.b, 1)

    -- Centro: dorado sólido (se extiende entre los dos gradientes)
    local glowRight = titlebar:CreateTexture(nil, "BORDER")
    glowRight:SetPoint("BOTTOMRIGHT", titlebar, "BOTTOMRIGHT", 0, 0)
    glowRight:SetHeight(2)
    glowRight:SetWidth(160)
    glowRight:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetGradientH(glowRight,
        Theme.GOLD.gold3.r, Theme.GOLD.gold3.g, Theme.GOLD.gold3.b, 1,
        Theme.BG.void.r, Theme.BG.void.g, Theme.BG.void.b, 0)

    local glowCenter = titlebar:CreateTexture(nil, "BORDER")
    glowCenter:SetPoint("BOTTOMLEFT",  glowLeft,  "BOTTOMRIGHT", 0, 0)
    glowCenter:SetPoint("BOTTOMRIGHT", glowRight, "BOTTOMLEFT",  0, 0)
    glowCenter:SetHeight(2)
    glowCenter:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(glowCenter, Theme.GOLD.gold3)
    
    titlebar:EnableMouse(true)
    titlebar:RegisterForDrag("LeftButton")
    titlebar:SetScript("OnDragStart", function() parent:StartMoving() end)
    titlebar:SetScript("OnDragStop", function() parent:StopMovingOrSizing() end)
    
    local icon = titlebar:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", titlebar, "LEFT", 14, 0)
    icon:SetSize(28, 28)
    icon:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(icon, Theme.GOLD.gold3)
    
    local titleText = titlebar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Theme:ApplyFont(titleText,"title",17)
    titleText:SetPoint("LEFT", icon, "RIGHT", 12, 4)
    titleText:SetText("MitzuMPlus M+ HISTORIAL")
    titleText:SetTextColor(Theme.GOLD.gold4.r, Theme.GOLD.gold4.g, Theme.GOLD.gold4.b, Theme.GOLD.gold4.a)

    -- ── Glow layer: misma posición, +1px offset, color dorado brillante 25% alpha
    local titleGlow = titlebar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    Theme:ApplyFont(titleGlow,"title",17)
    titleGlow:SetPoint("LEFT", icon, "RIGHT", 11, 3)   -- 1px offset → halo
    titleGlow:SetText("MitzuMPlus M+ HISTORIAL")
    titleGlow:SetTextColor(
        Theme.GOLD.gold5.r,
        Theme.GOLD.gold5.g,
        Theme.GOLD.gold5.b,
        0.28)   -- alpha bajo = halo sutil, no distorsiona legibilidad
    -- SetShadow() no existe en WoW API, eliminado
    local subtitle = titlebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Theme:ApplyFont(subtitle,"normal",12)
    subtitle:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
    subtitle:SetText("by Mutzukyhs · Mythic+ Tracker Pro")
    subtitle:SetTextColor(Theme.TEXT.dim.r, Theme.TEXT.dim.g, Theme.TEXT.dim.b, Theme.TEXT.dim.a)
    
    local versionPill = CreateFrame("Frame", nil, titlebar, BackdropTemplateMixin and "BackdropTemplate")
    versionPill:SetPoint("LEFT", subtitle, "RIGHT", 180, 0)
    versionPill:SetSize(60, 18)
    versionPill:SetBackdrop(Theme.BACKDROPS.panel)
    Theme:SetBackdropColor(versionPill, Theme.BG.btnPrim)
    Theme:SetBackdropBorderColor(versionPill, Theme.GOLD.gold1)
    
    local versionText = versionPill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Theme:ApplyFont(versionText,"mono",11)
    versionText:SetPoint("CENTER")
    versionText:SetText("v" .. MitzuMPlus.VERSION)
    versionText:SetTextColor(Theme.GOLD.gold5.r, Theme.GOLD.gold5.g, Theme.GOLD.gold5.b, Theme.GOLD.gold5.a)
    
    local statusDot = titlebar:CreateTexture(nil, "OVERLAY")
    statusDot:SetPoint("RIGHT", titlebar, "RIGHT", -180, 0)
    statusDot:SetSize(6, 6)
    statusDot:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(statusDot, Theme.STATUS.ok)
    
    local animGroup = statusDot:CreateAnimationGroup()
    animGroup:SetLooping("REPEAT")
    local alpha1 = animGroup:CreateAnimation("Alpha")
    alpha1:SetFromAlpha(1)
    alpha1:SetToAlpha(0.4)
    alpha1:SetDuration(1)
    alpha1:SetSmoothing("IN_OUT")
    local alpha2 = animGroup:CreateAnimation("Alpha")
    alpha2:SetOrder(2)
    alpha2:SetFromAlpha(0.4)
    alpha2:SetToAlpha(1)
    alpha2:SetDuration(1)
    alpha2:SetSmoothing("IN_OUT")
    animGroup:Play()
    
    local statusText = titlebar:CreateFontString(nil, "OVERLAY")
    statusText:SetPoint("LEFT", statusDot, "RIGHT", 5, 0)
    Theme:ApplyFont(statusText, "mono", 10)
    statusText:SetText("ACTIVA")
    Theme:SetTextColor(statusText, Theme.STATUS.ok)
    
    local settingsBtn = CreateFrame("Button", nil, titlebar, BackdropTemplateMixin and "BackdropTemplate")
    settingsBtn:SetPoint("RIGHT", titlebar, "RIGHT", -60, 0)
    settingsBtn:SetSize(22, 22)
    settingsBtn:SetBackdrop(Theme.BACKDROPS.panel)
    Theme:SetBackdropColor(settingsBtn, Theme.BG.button)
    Theme:SetBackdropBorderColor(settingsBtn, Theme.GOLD.gold0)
    
    local settingsBtnText = settingsBtn:CreateFontString(nil, "OVERLAY")
    settingsBtnText:SetPoint("CENTER")
    Theme:ApplyFont(settingsBtnText, "mono", 11)
    settingsBtnText:SetText("CFG")
    Theme:SetTextColor(settingsBtnText, Theme.TEXT.tertiary)
    
    settingsBtn:SetScript("OnEnter", function(self)
        Theme:SetBackdropColor(self, Theme.BG.btnPrim)
        Theme:SetBackdropBorderColor(self, Theme.GOLD.gold3)
        Theme:SetTextColor(settingsBtnText, Theme.GOLD.gold4)
    end)
    
    settingsBtn:SetScript("OnLeave", function(self)
        Theme:SetBackdropColor(self, Theme.BG.button)
        Theme:SetBackdropBorderColor(self, Theme.GOLD.gold0)
        Theme:SetTextColor(settingsBtnText, Theme.TEXT.tertiary)
    end)
    
    settingsBtn:SetScript("OnClick", function()
        if MitzuMPlus.Tabs then
            MitzuMPlus.Tabs:SetActiveTab("settings")
        end
    end)
    
    local closeBtn = CreateFrame("Button", nil, titlebar, BackdropTemplateMixin and "BackdropTemplate")
    closeBtn:SetPoint("RIGHT", titlebar, "RIGHT", -28, 0)
    closeBtn:SetSize(22, 22)
    closeBtn:SetBackdrop(Theme.BACKDROPS.panel)
    Theme:SetBackdropColor(closeBtn, Theme.BG.button)
    Theme:SetBackdropBorderColor(closeBtn, Theme.GOLD.gold0)
    
    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY")
    closeBtnText:SetPoint("CENTER")
    Theme:ApplyFont(closeBtnText, "mono", 11)
    closeBtnText:SetText("X")
    Theme:SetTextColor(closeBtnText, Theme.TEXT.tertiary)
    
    closeBtn:SetScript("OnEnter", function(self)
        Theme:SetBackdropColor(self, Theme.STATUS.badD)
        Theme:SetBackdropBorderColor(self, Theme.STATUS.bad)
        Theme:SetTextColor(closeBtnText, Theme.STATUS.bad)
    end)
    
    closeBtn:SetScript("OnLeave", function(self)
        Theme:SetBackdropColor(self, Theme.BG.button)
        Theme:SetBackdropBorderColor(self, Theme.GOLD.gold0)
        Theme:SetTextColor(closeBtnText, Theme.TEXT.tertiary)
    end)
    
    closeBtn:SetScript("OnClick", function()
        parent:Hide()
    end)
    
    parent.titlebar = titlebar
    parent.statusDot = statusDot
    parent.statusText = statusText
    
    -- ── Ornamentos de esquina en la ventana principal ────────────────────────
    MitzuMPlus:CreateCornerOrnaments(parent)
    
    return titlebar
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BODY CONTAINER (tabs + content + footer will attach here)
-- ═══════════════════════════════════════════════════════════════════════════

function MitzuMPlus:CreateBodyContainer(parent)
    local body = CreateFrame("Frame", nil, parent)
    body:SetPoint("TOPLEFT", parent.titlebar, "BOTTOMLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, Theme.LAYOUT.footerHeight)
    
    parent.body = body
    
    return body
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FOOTER CONTAINER (placeholder for Footer.lua)
-- ═══════════════════════════════════════════════════════════════════════════

function MitzuMPlus:CreateFooterContainer(parent)
    local footer = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    footer:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(Theme.LAYOUT.footerHeight)
    
    parent.footerContainer = footer
    
    return footer
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CORNER ORNAMENTS (adorno dorado en las 4 esquinas de la ventana)
-- ═══════════════════════════════════════════════════════════════════════════

function MitzuMPlus:CreateCornerOrnaments(parent)
    local SIZE   = 18   -- largo del brazo de la L
    local THICK  = 2    -- grosor de la línea
    local COLOR  = Theme.GOLD.gold3

    -- Tabla con los 4 corners: punto de anclaje, y offsets para H y V lines
    local corners = {
        { anchor = "TOPLEFT",
          hPoint = "TOPLEFT",     hX =  0, hY =  0,
          vPoint = "TOPLEFT",     vX =  0, vY =  0 },
        { anchor = "TOPRIGHT",
          hPoint = "TOPRIGHT",    hX =  0, hY =  0,
          vPoint = "TOPRIGHT",    vX = -THICK+1, vY =  0 },
        { anchor = "BOTTOMLEFT",
          hPoint = "BOTTOMLEFT",  hX =  0, hY =  THICK-1,
          vPoint = "BOTTOMLEFT",  vX =  0, vY =  0 },
        { anchor = "BOTTOMRIGHT",
          hPoint = "BOTTOMRIGHT", hX =  0, hY =  THICK-1,
          vPoint = "BOTTOMRIGHT", vX = -THICK+1, vY =  0 },
    }

    for _, c in ipairs(corners) do
        -- Línea horizontal
        local hLine = parent:CreateTexture(nil, "OVERLAY")
        hLine:SetSize(SIZE, THICK)
        hLine:SetPoint(c.hPoint, parent, c.anchor, c.hX, c.hY)
        hLine:SetTexture("Interface\\Buttons\\WHITE8X8")
        Theme:SetVertexColor(hLine, COLOR)

        -- Línea vertical
        local vLine = parent:CreateTexture(nil, "OVERLAY")
        vLine:SetSize(THICK, SIZE)
        vLine:SetPoint(c.vPoint, parent, c.anchor, c.vX, c.vY)
        vLine:SetTexture("Interface\\Buttons\\WHITE8X8")
        Theme:SetVertexColor(vLine, COLOR)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- UPDATE STATUS INDICATOR
-- ═══════════════════════════════════════════════════════════════════════════

function MitzuMPlus:UpdateWindowStatus(active)
    if not self.Window then return end
    
    local statusDot = self.Window.statusDot
    local statusText = self.Window.statusText
    
    if not statusDot or not statusText then return end
    
    if active then
        Theme:SetVertexColor(statusDot, Theme.STATUS.ok)
        statusText:SetText("ACTIVA")
        Theme:SetTextColor(statusText, Theme.STATUS.ok)
    else
        Theme:SetVertexColor(statusDot, Theme.TEXT.dim)
        statusText:SetText("INACTIVO")
        Theme:SetTextColor(statusText, Theme.TEXT.dim)
    end
end

-- BUG-L7 FIX: UpdateWindowForScale() usaba child:GetFontString() que solo existe
-- en Button/CheckButton, no en Frame genérico. La función nunca ajustó nada y
-- podía generar errores silenciosos. La ventana usa escala fija 1.0 (ver Init.lua
-- frame:SetScale(1.0)), así que esta función es innecesaria. Se deja como stub
-- seguro para no romper llamadas externas que pudieran existir.
function MitzuMPlus:UpdateWindowForScale(scale)
    -- no-op: la ventana usa escala fija 1.0; los tamaños de fuente son constantes.
    -- Ver: Init.lua → frame:SetScale(1.0)
end

return true
