-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Init.lua
-- Initialization & Entry Point
-- Corrected by: Bug audit v2.1.2
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
-- FIX BUG-6: eliminada la versión hardcodeada "2.1.5". La única fuente de verdad
-- es MitzuMPlus.VERSION, que Bootstrap.lua lee dinámicamente del .toc.
-- Se mantiene el local solo como alias de emergencia usando el valor real.
local ADDON_VERSION_FALLBACK = "5.0.0"

-- FIX RUNTIME-1: Bootstrap.lua llama NewAddon() antes que este archivo.
-- Aquí solo recuperamos la referencia con GetAddon(); llamar NewAddon() de
-- nuevo causaría un error "addon already registered".
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
-- _G[ADDON_NAME] y _G.MitzuMPlus ya fueron asignados en Bootstrap.lua.

-- ═══════════════════════════════════════════════════════════════════════════
-- DATABASE INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

function MitzuMPlus:OnInitialize()
    -- BUG-FIX-8: MitzuMPlusDB_Defaults viene de MitzuMPlus_Historial_main.lua
    -- (carga antes que Init.lua en el TOC). Si no llegó, AceDB recibiría nil
    -- y la DB no tendría defaults. Lo detectamos y fallamos con un mensaje claro.
    if not MitzuMPlusDB_Defaults then
        error("[MitzuMPlus] FATAL: MitzuMPlusDB_Defaults no definido. " ..
              "Verifica que MitzuMPlus_Historial_main.lua carga antes que Init.lua en el TOC.")
    end

    self.db = LibStub("AceDB-3.0"):New("MitzuMPlusDB", MitzuMPlusDB_Defaults, true)

    -- Compatibilidad con perfiles antiguos: shareData fue movido al nivel
    -- profile, pero builds previas lo escribían en profile.settings.
    do
        local profile = self.db and self.db.profile
        local settings = profile and profile.settings
        if profile and profile.shareData == nil then
            if settings and settings.shareData ~= nil then
                profile.shareData = settings.shareData == true
            else
                profile.shareData = false
            end
        end
    end

    -- FIX BUG-12: actualizar global.version al cargar para que refleje la versión
    -- real del addon (leída del .toc por Bootstrap.lua) y no quede hardcodeada.
    if self.db.global then
        self.db.global.version = self.VERSION or "UNKNOWN"
        if self.RuntimeVersion then
            local ci=self.RuntimeVersion:Refresh()
            self.db.global.client = {
                patch=ci.patch, build=ci.build, buildDate=ci.buildDate,
                interface=ci.interface, season=ci.season, detectedAt=ci.detectedAt,
            }
        end
    end
    self:RegisterChatCommand("MitzuMPlus", "HandleSlashCommand")
    self:RegisterChatCommand("emp", "HandleSlashCommand")

    -- Instalar el error handler lo antes posible (DB ya está lista).
    if self.ErrorLogger and self.ErrorLogger.Install then
        self.ErrorLogger:Install()
    end

    -- BUG-FIX-4 + BUG-FIX-5:
    -- Antes: si InCombatLockdown() era true, RegisterCoreEvents() nunca se llamaba
    -- y no había ningún evento para recuperarse después del combate.
    -- Ahora: registramos PLAYER_REGEN_ENABLED como fallback de una sola vez.
    if not InCombatLockdown() then
        self:_SafeRegisterCoreEvents()
    else
        self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            self:_SafeRegisterCoreEvents()
        end)
    end

    self:Print("|cFFD4A43CMitzuMPlus M+ Historial|r v" .. (self.VERSION or ADDON_VERSION_FALLBACK) .. " cargado. /MitzuMPlus para abrir.")

    -- FIX BUG-2: instalar el listener de debug-fingerprint ahora que EventBus existe.
    if type(self.InstallFingerprintDebugListener) == "function" then
        self:InstallFingerprintDebugListener()
    end
end

-- BUG-FIX-4: Wrapper seguro para RegisterCoreEvents.
-- Core.lua extiende MitzuMPlus con esa función. Si no cargó, avisamos.
function MitzuMPlus:_SafeRegisterCoreEvents()
    if type(self.RegisterCoreEvents) == "function" then
        self:RegisterCoreEvents()
    else
        self:Print("|cFFee3333[MitzuMPlus] ADVERTENCIA: RegisterCoreEvents() no encontrado. " ..
                   "Verifica que modules/Core.lua está incluido en el TOC.|r")
    end
end

function MitzuMPlus:OnEnable()
    if self.InitMinimapIcon then
        self:InitMinimapIcon()
    end
    -- Iniciar overlay en pantalla (si está habilitado) durante las runs.
    if self.InitOverlay then
        self:InitOverlay()
    end

    -- DataManager: solo remover runs corruptas, sin backups
    if self.DataManager then
        self.DataManager:RemoveCorruptRuns()
    end


    -- PersonalBest: Rebuild silencioso si es primer load
    if self.PersonalBest and self.db and self.db.global then
        if not self.db.global.personalBests or not next(self.db.global.personalBests) then
            self.PersonalBest:RebuildFromHistory()
        end
    end
    local settings = self.db and self.db.profile and self.db.profile.settings
    if settings and settings.closeWithEscape and not self._escapeRegistered then
        -- API-7 FIX: UISpecialFrames fue deprecado en 11.0.
        -- RegisterEscapeHandler es la API correcta en Midnight.
        -- Se mantiene el fallback a UISpecialFrames para clientes pre-TWW.
        if RegisterEscapeHandler then
            RegisterEscapeHandler(function()
                if self.Window and self.Window:IsShown() then
                    self.Window:Hide()
                    return true  -- consumir el escape
                end
                return false
            end)
        elseif UISpecialFrames then
            table.insert(UISpecialFrames, "MitzuMPlusMainWindow")
        end
        self._escapeRegistered = true
    end
end

function MitzuMPlus:OnDisable()
    -- Cleanup when addon is disabled
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DEFAULT PROFILE
-- BUG-M7 FIX: GetDefaultProfile() eliminado — era código muerto desincronizado.
-- La única fuente de verdad es MitzuMPlusDB_Defaults (definido en MitzuMPlus_Historial_main.lua).
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- UI INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

function MitzuMPlus:InitializeUI()
    -- BUG-FIX-6a: error() en Lua lanza excepción; el return siguiente era código muerto.
    -- Reemplazado por Print + return para no crashear el addon entero.
    if not self or not self.db then
        if self and self.Print then
            self:Print("|cFFee3333[MitzuMPlus] InitializeUI: DB no inicializada.|r")
        end
        return
    end

    if not self.Window then
        self.Window = self:CreateMainWindow()
    end

    -- BUG-FIX-6b: mismo patrón — error() + return era código muerto.
    if not self.Window then
        self:Print("|cFFee3333[MitzuMPlus] InitializeUI: No se pudo crear la ventana principal.|r")
        return
    end

    if not self._uiBuilt then
        -- Tabs:Create() va PRIMERO porque asigna self.Window.contentArea.
        -- NOTA: Tabs:Create ya NO llama SetActiveTab internamente.
        if self.Tabs and self.Tabs.Create then
            self.Tabs:Create(self.Window)
        end
        if self.Footer and self.Footer.Create then
            self.Footer:Create(self.Window)
        end

        -- FIX BUG5: contentArea es asignado por Tabs:Create()
        local contentArea = self.Window and self.Window.contentArea
        if contentArea then
            if self.PanelHistorial  and self.PanelHistorial.Create  then self.PanelHistorial:Create(contentArea)  end
            if self.PanelStats      and self.PanelStats.Create      then self.PanelStats:Create(contentArea)      end
            if self.PanelConfig     and self.PanelConfig.Create     then self.PanelConfig:Create(contentArea)     end
            if self.PanelPlayers   and self.PanelPlayers.Create   then self.PanelPlayers:Create(contentArea)   end
            if self.PanelCoach     and self.PanelCoach.Create     then self.PanelCoach:Create(contentArea)     end
        end

        -- Mostrar la ventana ANTES de SetActiveTab para que GetWidth() en los
        -- paneles devuelva valores reales (WoW resuelve el layout al Show).
        -- Se oculta inmediatamente si el caller no quiere que se vea todavía.
        local wasVisible = self.Window:IsShown()
        self.Window:Show()

        if self.Tabs and self.Tabs.SetActiveTab then
            local defaultTab = (self.db and self.db.profile and
                                self.db.profile.settings and
                                self.db.profile.settings.defaultTab) or "historial"
            -- Un perfil guardado puede apuntar a una pestaña que ya no existe
            -- (por ejemplo compare). SetActiveTab devuelve sin hacer nada ante
            -- un id desconocido, asi que la ventana se abriria en blanco.
            if not self.Tabs.buttons or not self.Tabs.buttons[defaultTab] then
                defaultTab = "historial"
                if self.db and self.db.profile and self.db.profile.settings then
                    self.db.profile.settings.defaultTab = defaultTab
                end
            end
            self.Tabs:SetActiveTab(defaultTab)
        end

        -- Ocultar de nuevo si no estaba visible — ToggleWindow la mostrará
        if not wasVisible then
            self.Window:Hide()
        end

        self._uiBuilt = true
    end

    -- Apply opacity
    local alpha = (self.db and self.db.profile and
                   self.db.profile.settings and
                   self.db.profile.settings.windowOpacity) or 1.0
    if type(alpha) ~= "number" then alpha = 1.0 end
    alpha = math.max(0.2, math.min(1.0, alpha))
    self.Window:SetAlpha(alpha)
end

function MitzuMPlus:CreateMainWindow()
    local Theme = MitzuMPlus.Theme
    if not Theme then
        -- BUG-FIX-6c: error() aquí SÍ es correcto (no hay UI sin Theme).
        -- El return muerto que existía después fue eliminado.
        error("[MitzuMPlus] Theme no cargó. Verifica el orden en el TOC.")
    end

    if not Theme.LAYOUT then
        local C = MitzuMPlus.Constants or {}
        Theme.LAYOUT = {
            windowWidth    = C.UI_HISTORIAL_DEFAULT_WIDTH  or C.UI_WINDOW_MIN_WIDTH  or 1100,
            windowHeight   = C.UI_HISTORIAL_DEFAULT_HEIGHT or C.UI_WINDOW_MIN_HEIGHT or 680,
            titlebarHeight = C.TITLEBAR_HEIGHT or 44,
            footerHeight   = C.FOOTER_HEIGHT or 28,
        }
    end

    local frame = CreateFrame("Frame", "MitzuMPlusMainWindow", UIParent,
        BackdropTemplateMixin and "BackdropTemplate")

    frame:SetSize(Theme.LAYOUT.windowWidth, Theme.LAYOUT.windowHeight)
    frame:SetScale(1.0)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(10)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    if frame.SetResizable then frame:SetResizable(false) end
    frame:SetClampedToScreen(false)
    frame:Hide()

    frame:SetBackdrop(Theme.BACKDROPS.window)
    Theme:SetBackdropColor(frame, Theme.BG.window)
    Theme:SetBackdropBorderColor(frame, Theme.BORDER.window)

    local mainContainer = CreateFrame("Frame", nil, frame)
    mainContainer:SetAllPoints(frame)
    mainContainer:Show()

    -- ── OnShow ──────────────────────────────────────────────────────────────
    frame:SetScript("OnShow", function()
        local settings    = MitzuMPlus.db and MitzuMPlus.db.profile and MitzuMPlus.db.profile.settings
        local targetAlpha = (settings and settings.windowOpacity) or 1.0
        if type(targetAlpha) ~= "number" then targetAlpha = 1.0 end
        targetAlpha = math.max(0.2, math.min(1.0, targetAlpha))

        if frame._showAnim then frame._showAnim:Stop() end

        if settings and settings.enableAnimations then
            if not frame._showAnim then
                local anim = frame:CreateAnimationGroup()
                local fade = anim:CreateAnimation("Alpha")
                fade:SetFromAlpha(0)
                fade:SetToAlpha(1.0)
                fade:SetDuration(0.2)
                fade:SetSmoothing("OUT")
                anim:SetScript("OnFinished", function()
                    frame:SetAlpha(targetAlpha)
                end)
                frame._showAnim = anim
            end
            frame:SetAlpha(0)
            frame._showAnim:Play()
        else
            frame:SetAlpha(targetAlpha)
        end
    end)

    -- ── OnHide ───────────────────────────────────────────────────────────────
    frame:SetScript("OnHide", function()
        if frame._showAnim then
            frame._showAnim:Stop()
            -- BUG-M8 FIX: NO asignar nil — preservar grupo de animación para reusar.
        end
    end)

    -- ── Titlebar ─────────────────────────────────────────────────────────────
    local titlebar = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate")
    titlebar:SetHeight(Theme.LAYOUT.titlebarHeight or 52)
    titlebar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    titlebar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    titlebar:SetBackdrop(Theme.BACKDROPS.titlebar)
    Theme:SetBackdropColor(titlebar, Theme.BG.titlebar)
    Theme:SetBackdropBorderColor(titlebar, Theme.BORDER.titlebar)

    local addonIcon = titlebar:CreateTexture(nil, "OVERLAY")
    addonIcon:SetSize(28, 28)
    addonIcon:SetPoint("LEFT", titlebar, "LEFT", 6, 0)
    addonIcon:SetTexture("Interface\\AddOns\\MitzuMPlus_Historial\\Media\\Icons\\1_addon")
    addonIcon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local titleText = titlebar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Theme:ApplyFont(titleText,"title",17)
    titleText:SetPoint("LEFT", addonIcon, "RIGHT", 12, 4)
    titleText:SetText("MitzuMPlus M+ HISTORIAL")
    titleText:SetTextColor(Theme.GOLD.gold4.r, Theme.GOLD.gold4.g, Theme.GOLD.gold4.b, Theme.GOLD.gold4.a)

    local subtitleText = titlebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Theme:ApplyFont(subtitleText,"normal",12)
    subtitleText:SetPoint("LEFT", titleText, "RIGHT", 12, 0)
    subtitleText:SetText("Mythic+ Run History & Analysis")
    subtitleText:SetTextColor(Theme.TEXT.secondary.r, Theme.TEXT.secondary.g, Theme.TEXT.secondary.b, Theme.TEXT.secondary.a)

    -- Settings button (punto asignado DESPUÉS de definir closeBtn)
    local settingsBtn = CreateFrame("Button", nil, titlebar, BackdropTemplateMixin and "BackdropTemplate")
    settingsBtn:SetSize(24, 24)
    settingsBtn:SetBackdrop(Theme.BACKDROPS.button)
    Theme:SetBackdropColor(settingsBtn, Theme.BG.btnSec)
    Theme:SetBackdropBorderColor(settingsBtn, Theme.BORDER.btnSec)

    local settingsIcon = settingsBtn:CreateTexture(nil, "OVERLAY")
    settingsIcon:SetAllPoints(settingsBtn)
    settingsIcon:SetTexture("Interface\\AddOns\\MitzuMPlus_Historial\\Media\\Icons\\2_settings")
    settingsIcon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    settingsBtn:SetScript("OnEnter", function()
        Theme:SetBackdropColor(settingsBtn, Theme.BG.btnSecHover)
        Theme:SetBackdropBorderColor(settingsBtn, Theme.BORDER.btnSecHover)
    end)
    settingsBtn:SetScript("OnLeave", function()
        Theme:SetBackdropColor(settingsBtn, Theme.BG.btnSec)
        Theme:SetBackdropBorderColor(settingsBtn, Theme.BORDER.btnSec)
    end)
    settingsBtn:SetScript("OnClick", function()
        if MitzuMPlus.ShowTab then MitzuMPlus:ShowTab("settings") end
    end)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titlebar, BackdropTemplateMixin and "BackdropTemplate")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("RIGHT", titlebar, "RIGHT", -10, 0)
    -- Cadena de anclaje: settingsBtn → LEFT de closeBtn
    settingsBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)

    -- Version text — BUG-FIX-7: siempre leer MitzuMPlus.VERSION
    local versionText = titlebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Theme:ApplyFont(versionText,"mono",11)
    versionText:SetPoint("RIGHT", settingsBtn, "LEFT", -10, 0)
    versionText:SetText("v" .. (MitzuMPlus.VERSION or ADDON_VERSION_FALLBACK))
    versionText:SetTextColor(Theme.TEXT.dim.r, Theme.TEXT.dim.g, Theme.TEXT.dim.b, Theme.TEXT.dim.a)

    closeBtn:SetBackdrop(Theme.BACKDROPS.button)
    Theme:SetBackdropColor(closeBtn, Theme.BG.btnClose)
    Theme:SetBackdropBorderColor(closeBtn, Theme.BORDER.btnClose)

    local closeIcon = closeBtn:CreateTexture(nil, "OVERLAY")
    closeIcon:SetAllPoints(closeBtn)
    closeIcon:SetTexture("Interface\\AddOns\\MitzuMPlus_Historial\\Media\\Icons\\3_close")
    closeIcon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    closeBtn:SetScript("OnEnter", function()
        Theme:SetBackdropColor(closeBtn, Theme.BG.btnCloseHover)
        Theme:SetBackdropBorderColor(closeBtn, Theme.BORDER.btnCloseHover)
        closeIcon:SetVertexColor(1.3, 0.3, 0.3, 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        Theme:SetBackdropColor(closeBtn, Theme.BG.btnClose)
        Theme:SetBackdropBorderColor(closeBtn, Theme.BORDER.btnClose)
        closeIcon:SetVertexColor(1, 1, 1, 1)
    end)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- ── Footer container (creado ANTES que body para que body pueda anclarse) ──
    local footerHeight = Theme.LAYOUT.footerHeight or 28
    local footerContainer = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate")
    footerContainer:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  0, 0)
    footerContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    footerContainer:SetHeight(footerHeight)

    -- ── Body container ───────────────────────────────────────────────────────
    local body = CreateFrame("Frame", nil, frame)
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT",     titlebar,        "BOTTOMLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", footerContainer, "TOPRIGHT",   0, 0)

    -- contentArea = nil → Tabs:Create() lo asignará
    frame.body            = body
    frame.footerContainer = footerContainer
    frame.contentArea     = nil
    frame.titlebar        = titlebar
    frame.titleText       = titleText
    frame.subtitleText    = subtitleText
    frame.versionText     = versionText

    -- BUG-M4 FIX: statusDot y statusText asignados al frame para UpdateWindowStatus()
    local statusDot = titlebar:CreateTexture(nil, "OVERLAY")
    statusDot:SetSize(6, 6)
    statusDot:SetPoint("RIGHT", versionText, "LEFT", -10, 0)
    statusDot:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(statusDot, Theme.STATUS.ok)

    local statusText = titlebar:CreateFontString(nil, "OVERLAY")
    statusText:SetPoint("LEFT", statusDot, "RIGHT", 4, 0)
    Theme:ApplyFont(statusText, "mono", 10)
    statusText:SetText("ACTIVA")
    Theme:SetTextColor(statusText, Theme.STATUS.ok)

    frame.statusDot  = statusDot
    frame.statusText = statusText

    if self.Renderizado then
        self.Renderizado:InitializeWindow(frame)
    end

    self.Window = frame
    return frame
end

-- ═══════════════════════════════════════════════════════════════════════════
-- WINDOW HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

function MitzuMPlus:SaveWindowSize()
    if not self.Window or not self.db or not self.db.profile or
       not self.db.profile.settings then return end
    self.db.profile.settings.windowWidth  = self.Window:GetWidth()
    self.db.profile.settings.windowHeight = self.Window:GetHeight()
end

function MitzuMPlus:EnsureWindowVisible()
    if not self.Window then return end
    if self.Renderizado then
        self.Renderizado:EnsureVisible(self.Window)
    else
        self.Window:ClearAllPoints()
        self.Window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SLASH COMMANDS
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- PLACAS VISIBLES PARA LOS INFORMES DE EVIDENCIAS
--
-- El registro es el de GuidanceEngine, que ya existe y es el que ve el motor.
-- No se crea otro: dos registros de lo mismo acaban discrepando y entonces
-- ninguno de los dos sirve de nada.
--
-- El respaldo a C_NamePlate no es un registro, es una consulta puntual, y solo
-- se usa cuando el de Guidance está vacío — por ejemplo tras un /reload con
-- placas ya en pantalla, que nunca dispararon un NAME_PLATE_UNIT_ADDED.
--
-- Vive aquí, y no dentro de los módulos de evidencia, porque ninguno de ellos
-- puede conocer a GuidanceEngine: son sus invariantes.
-- ═══════════════════════════════════════════════════════════════════════════
function MitzuMPlus:_VisibleNameplates()
    local visibles = {}
    local G = self.GuidanceEngine
    if G and G.GetVisible then visibles = G:GetVisible() end
    if #visibles == 0 and C_NamePlate and C_NamePlate.GetNamePlates then
        local okP, placas = pcall(C_NamePlate.GetNamePlates)
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

function MitzuMPlus:HandleSlashCommand(input)

    local raw = tostring(input or "")
    if raw == "version" or raw == "patch" then
        if self.RuntimeVersion then self:Print(self.RuntimeVersion:GetDisplayString()) end
        return
    end
    if raw == "forces" or raw == "fuerzas" then
        if not self.KeystoneTracker or not self.KeystoneTracker.DumpCriteria then
            self:Print("KeystoneTracker no cargado.")
            return
        end
        for _, line in ipairs(self.KeystoneTracker:DumpCriteria()) do
            self:Print(line)
        end
        return
    end
    if raw == "coach" then
        local active = _G.MitzuMPlusCurrentRun ~= nil
        local status = self.GetOverlayAnchorStatus and self:GetOverlayAnchorStatus() or "sin overlay"
        self:Print(string.format("Coach: run=%s · anchor=%s", active and "ACTIVA" or "NO", tostring(status)))
        if active and self.ShowOverlay then self:ShowOverlay() end
        if self.OverlayFrame and self.OverlayFrame.Refresh then self.OverlayFrame:Refresh() end
        return
    end
    if raw == "mdt" and self.MDTImporter then
        self.MDTImporter:ShowDialog()
        return
    end
    local mdtPayload = raw:match("^mdt%s+(.+)$")
    if mdtPayload and self.MDTImporter then
        local ok, info, route = self.MDTImporter:Import(mdtPayload, _G.MitzuMPlusCurrentRun)
        if ok then
            self:Print(string.format("|cFF21de66Ruta MDT guardada:|r %d pulls · %s", tonumber(info) or 0, route.forcePrecision == "exact-mdt-data" and "% exacto" or "AUTO learning"))
        else
            self:Print("|cFFee5555Ruta MDT no importada:|r "..tostring(info))
        end
        return
    end
    if raw == "route clear" and self.RouteAdvisor then
        self.RouteAdvisor:ClearRoute(_G.MitzuMPlusCurrentRun)
        self:Print("Ruta eliminada para la mazmorra actual.")
        return
    end
    local routePayload = raw:match("^route%s+(.+)$")
    if routePayload and self.RouteAdvisor then
        local ok, info = self.RouteAdvisor:ImportSimpleRoute(routePayload, _G.MitzuMPlusCurrentRun)
        if ok then self:Print("|cFF21de66Ruta guardada:|r " .. tostring(info) .. " pulls.")
        else self:Print("|cFFee5555Ruta no importada:|r " .. tostring(info)) end
        return
    end
    local args = { strsplit(" ", (input or ""):lower()) }
    local cmd  = args[1]

    if not cmd or cmd == "" or cmd == "show" or cmd == "open" then
        self:ToggleWindow()
    elseif cmd == "hide" or cmd == "close" then
        if self.Window then self.Window:Hide() end
    elseif cmd == "historial" or cmd == "history" then
        self:ShowTab("historial")
    elseif cmd == "config" or cmd == "settings" or cmd == "configuracion" then
        self:ShowTab("settings")
    elseif cmd == "activar" or cmd == "activate" then
        if InCombatLockdown() then
            self:Print("|cFFff9922No se puede activar el tracking durante combate.|r")
            return
        end
        self:_SafeRegisterCoreEvents()
        self:Print("|cFF21de66Tracking de M+ activado.|r")
    elseif cmd == "desactivar" or cmd == "deactivate" then
        self:UnregisterCoreEvents()
    elseif cmd == "reset" then
        self:Print("|cFFff9922Usa /MitzuMPlus resetconfig o /MitzuMPlus resetdata para resetear.|r")
    elseif cmd == "resetconfig" then
        self.db:ResetProfile()
        self:Print("|cFF21de66Configuración reseteada a valores por defecto.|r")
        ReloadUI()
    elseif cmd == "resetsize" then
        if not self.db.profile.settings then self.db.profile.settings = {} end
        self.db.profile.settings.windowWidth  = nil
        self.db.profile.settings.windowHeight = nil
        self.db.profile.settings.windowScale  = 1.0
        if self.Window then
            local Theme = MitzuMPlus.Theme
            if Theme then
                self.Window:SetSize(Theme.LAYOUT.windowWidth, Theme.LAYOUT.windowHeight)
                self.Window:SetScale(1.0)
                self.Window:ClearAllPoints()
                self.Window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
        self:Print("|cFF21de66Tamaño y escala de ventana restaurados a valores por defecto.|r")
    elseif cmd == "resetdata" then
        self:Print("|cFFee3333¿Estás seguro? Escribe /MitzuMPlus confirmreset para borrar todos los datos.|r")
    elseif cmd == "confirmreset" then
        self.db.global.runs = {}
        self:Print("|cFFee3333Todos los datos de runs han sido borrados.|r")
        if self.Window and self.Window:IsShown() then
            self:RefreshActivePanel()
        end
    elseif cmd == "version" or cmd == "v" then
        -- BUG-FIX-7: usar MitzuMPlus.VERSION como única fuente de verdad.
        self:Print(string.format("MitzuMPlus M+ Historial |cFFe8b84av%s|r", MitzuMPlus.VERSION or ADDON_VERSION_FALLBACK))
    elseif cmd == "bugreport" then
        if self.ErrorLogger then
            local count = self.ErrorLogger:Count()
            if count == 0 then
                self:Print("|cFF21de66No hay errores registrados. ¡Todo en orden!|r")
            else
                self:Print(string.format(
                    "|cFFe8b84a[ErrorLogger]|r %d error(es) encontrado(s). Abriendo clipboard…", count))
                local report = self.ErrorLogger:GetReport()
                if self.Export and self.Export.CopyToClipboard then
                    self.Export:CopyToClipboard(report)
                else
                    -- Fallback: imprimir en chat si el clipboard no está disponible.
                    self:Print(report)
                end
            end
        else
            self:Print("|cFFee3333[ErrorLogger] Módulo no cargado. Verifica el TOC.|r")
        end
    elseif cmd == "clearerrors" then
        if self.ErrorLogger then
            self.ErrorLogger:Clear()
        else
            self:Print("|cFFee3333[ErrorLogger] Módulo no cargado.|r")
        end
    elseif cmd == "debuglog" then
        if self.ErrorLogger and self.ErrorLogger.GetDebugReport then
            local count = self.ErrorLogger:DebugCount()
            if count == 0 then
                self:Print("|cFF21de66No hay eventos de diagnóstico registrados.|r")
            else
                self:Print(string.format(
                    "|cFF88CCFF[DebugLog]|r %d evento(s). Abriendo clipboard…", count))
                local report = self.ErrorLogger:GetDebugReport()
                if self.Export and self.Export.CopyToClipboard then
                    self.Export:CopyToClipboard(report)
                else
                    self:Print(report)
                end
            end
        else
            self:Print("|cFFee3333[ErrorLogger] Módulo no cargado.|r")
        end
    elseif cmd == "cleardebug" then
        if self.ErrorLogger and self.ErrorLogger.ClearDebugLog then
            self.ErrorLogger:ClearDebugLog()
        else
            self:Print("|cFFee3333[ErrorLogger] Módulo no cargado.|r")
        end
    elseif cmd == "debugmode" then
        if self.db and self.db.profile and self.db.profile.settings then
            local s = self.db.profile.settings
            s.debugMode = not s.debugMode
            self:Print(string.format(
                "|cFF88CCFF[DebugMode]|r %s",
                s.debugMode and "|cFF21de66ACTIVADO|r" or "|cFFee3333DESACTIVADO|r"))
        end
    elseif cmd == "meterinfo" then
        -- Enumerate C_DamageMeter to discover available methods/fields
        local cdm = _G.C_DamageMeter
        if not cdm then
            self:Print("|cFFee3333[MeterInfo]|r C_DamageMeter = nil (no existe en este cliente)")
        elseif type(cdm) ~= "table" then
            self:Print(string.format("|cFFee3333[MeterInfo]|r C_DamageMeter = %s (tipo: %s)", tostring(cdm), type(cdm)))
        else
            local keys = {}
            for k, v in pairs(cdm) do
                keys[#keys + 1] = string.format("  |cFFf7d470%s|r = %s", tostring(k), type(v))
            end
            if #keys == 0 then
                self:Print("|cFFff9922[MeterInfo]|r C_DamageMeter existe pero es una tabla VACÍA (0 keys)")
            else
                table.sort(keys)
                self:Print(string.format("|cFF88CCFF[MeterInfo]|r C_DamageMeter tiene %d keys:", #keys))
                for _, line in ipairs(keys) do
                    self:Print(line)
                end
            end
            -- Also try metatable enumeration
            local mt = getmetatable(cdm)
            if mt then
                local mtKeys = {}
                for k, v in pairs(mt) do
                    mtKeys[#mtKeys + 1] = string.format("  |cFFf7d470%s|r = %s", tostring(k), type(v))
                end
                if #mtKeys > 0 then
                    table.sort(mtKeys)
                    self:Print(string.format("|cFF88CCFF[MeterInfo]|r Metatable tiene %d keys:", #mtKeys))
                    for _, line in ipairs(mtKeys) do
                        self:Print(line)
                    end
                end
                -- Check __index
                if mt.__index and type(mt.__index) == "table" then
                    local idxKeys = {}
                    for k, v in pairs(mt.__index) do
                        idxKeys[#idxKeys + 1] = string.format("  |cFFf7d470%s|r = %s", tostring(k), type(v))
                    end
                    if #idxKeys > 0 then
                        table.sort(idxKeys)
                        self:Print(string.format("|cFF88CCFF[MeterInfo]|r __index table tiene %d keys:", #idxKeys))
                        for _, line in ipairs(idxKeys) do
                            self:Print(line)
                        end
                    end
                end
            else
                self:Print("|cFF888888[MeterInfo]|r Sin metatable")
            end
        end
    elseif cmd == "meterexplore" then
        -- Deep exploration of C_DamageMeter real API
        local cdm = _G.C_DamageMeter
        if not cdm then
            self:Print("|cFFee3333[MeterExplore]|r C_DamageMeter = nil")
            return
        end
        local _isSecret = rawget(_G, "issecretvalue")
        local function safeDump(val, depth)
            if val == nil then return "nil" end
            if _isSecret and _isSecret(val) then return "<SECRET>" end
            if type(val) == "table" then
                if depth and depth > 1 then return "{...}" end
                local parts = {}
                local n = 0
                for k, v in pairs(val) do
                    n = n + 1
                    if n > 20 then parts[#parts + 1] = "..."; break end
                    parts[#parts + 1] = tostring(k) .. "=" .. safeDump(v, (depth or 0) + 1)
                end
                return "{" .. table.concat(parts, ", ") .. "}"
            end
            local s = tostring(val)
            if #s > 80 then s = s:sub(1, 77) .. "..." end
            return s .. "(" .. type(val) .. ")"
        end

        -- 1) IsDamageMeterAvailable
        self:Print("|cFF88CCFF[MeterExplore]|r ── IsDamageMeterAvailable ──")
        if cdm.IsDamageMeterAvailable then
            local ok, res = pcall(cdm.IsDamageMeterAvailable)
            self:Print("  " .. (ok and safeDump(res) or ("ERROR: " .. tostring(res))))
        else
            self:Print("  nil")
        end

        -- 2) GetAvailableCombatSessions
        self:Print("|cFF88CCFF[MeterExplore]|r ── GetAvailableCombatSessions ──")
        local sessions
        if cdm.GetAvailableCombatSessions then
            local ok, res = pcall(cdm.GetAvailableCombatSessions)
            if ok then
                sessions = res
                if type(res) == "table" then
                    self:Print(string.format("  Returned table with %d entries", #res))
                    for i, s in ipairs(res) do
                        if i > 5 then self:Print("  ..."); break end
                        self:Print(string.format("  [%d] = %s", i, safeDump(s)))
                    end
                    -- Also dump as key-value if not array
                    if #res == 0 then
                        local n = 0
                        for k, v in pairs(res) do
                            n = n + 1
                            if n > 10 then self:Print("  ..."); break end
                            self:Print(string.format("  .%s = %s", tostring(k), safeDump(v)))
                        end
                    end
                else
                    self:Print("  " .. safeDump(res))
                end
            else
                self:Print("  ERROR: " .. tostring(res))
            end
        else
            self:Print("  nil")
        end

        -- 3) GetSessionDurationSeconds
        self:Print("|cFF88CCFF[MeterExplore]|r ── GetSessionDurationSeconds ──")
        if cdm.GetSessionDurationSeconds then
            local ok, res = pcall(cdm.GetSessionDurationSeconds)
            self:Print("  " .. (ok and safeDump(res) or ("ERROR: " .. tostring(res))))
            -- Try with session ID if we have sessions
            if sessions and type(sessions) == "table" then
                for i, s in ipairs(sessions) do
                    if i > 3 then break end
                    local ok2, res2 = pcall(cdm.GetSessionDurationSeconds, s)
                    self:Print(string.format("  (arg=%s) → %s", safeDump(s), ok2 and safeDump(res2) or ("ERROR: " .. tostring(res2))))
                end
            end
        else
            self:Print("  nil")
        end

        -- 4) GetCombatSessionFromType — try common type values
        self:Print("|cFF88CCFF[MeterExplore]|r ── GetCombatSessionFromType ──")
        if cdm.GetCombatSessionFromType then
            for _, tryType in ipairs({0, 1, 2, 3, "dungeon", "raid", "party", "mythicplus"}) do
                local ok, res = pcall(cdm.GetCombatSessionFromType, tryType)
                if ok and res ~= nil then
                    self:Print(string.format("  type=%s → %s", tostring(tryType), safeDump(res)))
                end
            end
        else
            self:Print("  nil")
        end

        -- 5) GetCombatSessionFromID(sessionID, damageMeterType) — TWO-arg
        self:Print("|cFF88CCFF[MeterExplore]|r ── GetCombatSessionFromID(sid, dmgType) ──")
        if cdm.GetCombatSessionFromID and sessions and type(sessions) == "table" then
            local probeDmgTypes = {0, 2, 7}  -- DamageDone, HealingDone, DamageTaken
            for i, s in ipairs(sessions) do
                if i > 2 then break end
                local sid = type(s) == "table" and (s.sessionID or s.id or s[1]) or s
                for _, dt in ipairs(probeDmgTypes) do
                    local ok, res = pcall(cdm.GetCombatSessionFromID, sid, dt)
                    if ok and res ~= nil then
                        self:Print(string.format("  sid=%s, type=%d → %s", tostring(sid), dt, safeDump(res)))
                    end
                end
            end
        else
            self:Print("  " .. (cdm.GetCombatSessionFromID and "(no sessions)" or "nil"))
        end

        -- 6) GetCombatSessionSourceFromType
        self:Print("|cFF88CCFF[MeterExplore]|r ── GetCombatSessionSourceFromType ──")
        if cdm.GetCombatSessionSourceFromType then
            for _, tryType in ipairs({0, 1, 2, 3}) do
                local ok, res = pcall(cdm.GetCombatSessionSourceFromType, tryType)
                if ok and res ~= nil then
                    self:Print(string.format("  type=%s → %s", tostring(tryType), safeDump(res)))
                    -- If it's a table, dump first entry's keys
                    if type(res) == "table" then
                        for j, entry in ipairs(res) do
                            if j > 3 then break end
                            if type(entry) == "table" then
                                local eKeys = {}
                                for ek in pairs(entry) do eKeys[#eKeys + 1] = tostring(ek) end
                                table.sort(eKeys)
                                self:Print(string.format("    [%d] keys: %s", j, table.concat(eKeys, ", ")))
                                -- Dump values
                                for _, ek in ipairs(eKeys) do
                                    local ev = entry[ek]
                                    self:Print(string.format("      .%s = %s", ek, safeDump(ev)))
                                end
                            end
                        end
                    end
                end
            end
        else
            self:Print("  nil")
        end

        -- 7) GetCombatSessionSourceFromID(sessionID, damageMeterType) — TWO-arg
        self:Print("|cFF88CCFF[MeterExplore]|r ── GetCombatSessionSourceFromID(sid, dmgType) ──")
        if cdm.GetCombatSessionSourceFromID and sessions and type(sessions) == "table" then
            local probeDmgTypes = {0, 2, 7}  -- DamageDone, HealingDone, DamageTaken
            local dtNames = {[0]="DamageDone", [2]="HealingDone", [7]="DamageTaken"}
            for i, s in ipairs(sessions) do
                if i > 2 then break end
                local sid = type(s) == "table" and (s.sessionID or s.id or s[1]) or s
                local sName = type(s) == "table" and s.name or "?"
                for _, dt in ipairs(probeDmgTypes) do
                    local ok, res = pcall(cdm.GetCombatSessionSourceFromID, sid, dt)
                    if ok and res ~= nil then
                        local count = type(res) == "table" and #res or 0
                        self:Print(string.format("  sid=%s (%s), %s → %d entries",
                            tostring(sid), sName, dtNames[dt] or tostring(dt), count))
                        if type(res) == "table" then
                            for j, entry in ipairs(res) do
                                if j > 2 then break end
                                if type(entry) == "table" then
                                    local eKeys = {}
                                    for ek in pairs(entry) do eKeys[#eKeys + 1] = tostring(ek) end
                                    table.sort(eKeys)
                                    self:Print(string.format("    [%d] keys: %s", j, table.concat(eKeys, ", ")))
                                    for _, ek in ipairs(eKeys) do
                                        self:Print(string.format("      .%s = %s", ek, safeDump(entry[ek])))
                                    end
                                end
                            end
                        end
                    elseif not ok then
                        self:Print(string.format("  sid=%s, %s → ERROR: %s",
                            tostring(sid), dtNames[dt] or tostring(dt), tostring(res)))
                    end
                end
            end
        else
            self:Print("  " .. (cdm.GetCombatSessionSourceFromID and "(no sessions)" or "nil"))
        end

        self:Print("|cFF88CCFF[MeterExplore]|r ── Exploración completa ──")

        -- Show saved exploration data from last M+ run (auto-captured)
        local saved = self.db and self.db.global and self.db.global.meterExploreData
        if saved then
            self:Print(" ")
            self:Print("|cFF21de66[MeterExplore]|r ── Datos guardados (auto-captura durante M+) ──")
            self:Print(string.format("  Capturado: %s | Dungeon: %s | Version: %s",
                saved.timestamp and date("%Y-%m-%d %H:%M", saved.timestamp) or "?",
                saved.dungeon or "?",
                tostring(saved.version or 1)))
            if saved.sessions then
                local sc = 0
                if type(saved.sessions) == "table" then
                    for _ in pairs(saved.sessions) do sc = sc + 1 end
                end
                self:Print(string.format("  Sessions disponibles: %d", sc))
            end

            -- Duration by session type
            if saved.durationBySessionType then
                local parts = {}
                for st, d in pairs(saved.durationBySessionType) do
                    local stName = (st == 0 and "Overall") or (st == 1 and "Current") or (st == 2 and "Expired") or tostring(st)
                    parts[#parts + 1] = stName .. "=" .. tostring(d) .. "s"
                end
                self:Print("  Duration: " .. (#parts > 0 and table.concat(parts, ", ") or "ninguno"))
            end

            -- TWO-ARG source results (the important ones!)
            local dmgTypeNames = {
                [0]="DamageDone", [1]="Dps", [2]="HealingDone", [3]="Hps",
                [4]="Absorbs", [5]="Interrupts", [6]="Dispels", [7]="DamageTaken",
                [8]="AvoidableDmgTaken", [9]="Deaths", [10]="EnemyDmgTaken"
            }
            if saved.source2arg then
                local hits = {}
                for k in pairs(saved.source2arg) do hits[#hits + 1] = k end
                table.sort(hits)
                self:Print(string.format("  |cFF00FF00source2arg|r: %d hits: %s", #hits, #hits > 0 and table.concat(hits, ", ") or "ninguno"))
                -- Dump first 2 entries from each hit
                for _, hk in ipairs(hits) do
                    local src = saved.source2arg[hk]
                    if type(src) == "table" then
                        -- Parse key: "t0_s1" → dmgType=0, sessType=1
                        local dt, st2 = hk:match("t(%d+)_s(%d+)")
                        local dtName = dmgTypeNames[tonumber(dt)] or dt
                        local stName = (st2 == "0" and "Overall") or (st2 == "1" and "Current") or (st2 == "2" and "Expired") or st2
                        local entryCount = 0
                        for _ in pairs(src) do entryCount = entryCount + 1 end
                        self:Print(string.format("    %s (%s/%s): %d entries", hk, dtName, stName, entryCount))
                        -- Show first 2 entries with their keys/values
                        local shown = 0
                        for j, entry in ipairs(src) do
                            if shown >= 2 then break end
                            shown = shown + 1
                            if type(entry) == "table" then
                                local eKeys = {}
                                for ek in pairs(entry) do eKeys[#eKeys + 1] = tostring(ek) end
                                table.sort(eKeys)
                                self:Print(string.format("      [%d] keys: %s", j, table.concat(eKeys, ", ")))
                                for _, ek in ipairs(eKeys) do
                                    local ev = entry[ek]
                                    local vs = (type(ev) == "table") and "{...}" or tostring(ev)
                                    if #vs > 60 then vs = vs:sub(1, 57) .. "..." end
                                    self:Print(string.format("        .%s = %s", ek, vs))
                                end
                            else
                                self:Print(string.format("      [%d] = %s", j, safeDump(entry)))
                            end
                        end
                    end
                end
            end

            -- ID-BASED source results (the REAL data path!)
            if saved.sourceFromID then
                local hits = {}
                for k in pairs(saved.sourceFromID) do hits[#hits + 1] = k end
                table.sort(hits)
                self:Print(string.format("  |cFF00FF00sourceFromID|r: %d hits: %s",
                    #hits, #hits > 0 and table.concat(hits, ", ") or "ninguno"))
                -- Dump first 2 entries from each hit
                for _, hk in ipairs(hits) do
                    local src = saved.sourceFromID[hk]
                    if type(src) == "table" then
                        -- Parse key: "sid1_t0" → sessionID=1, dmgType=0
                        local sidStr, dtStr = hk:match("sid(%d+)_t(%d+)")
                        local dtName = dmgTypeNames[tonumber(dtStr)] or dtStr
                        local entryCount = 0
                        if type(src) == "table" then
                            for _ in pairs(src) do entryCount = entryCount + 1 end
                        end
                        self:Print(string.format("    %s (session=%s, %s): %d entries",
                            hk, sidStr or "?", dtName, entryCount))
                        local shown = 0
                        for j, entry in ipairs(src) do
                            if shown >= 2 then break end
                            shown = shown + 1
                            if type(entry) == "table" then
                                local eKeys = {}
                                for ek in pairs(entry) do eKeys[#eKeys + 1] = tostring(ek) end
                                table.sort(eKeys)
                                self:Print(string.format("      [%d] keys: %s", j, table.concat(eKeys, ", ")))
                                for _, ek in ipairs(eKeys) do
                                    local ev = entry[ek]
                                    local vs = (type(ev) == "table") and "{...}" or tostring(ev)
                                    if #vs > 60 then vs = vs:sub(1, 57) .. "..." end
                                    self:Print(string.format("        .%s = %s", ek, vs))
                                end
                            else
                                self:Print(string.format("      [%d] = %s", j, safeDump(entry)))
                            end
                        end
                    end
                end
            end

            -- ID-BASED session results
            if saved.sessionFromID then
                local hits = {}
                for k in pairs(saved.sessionFromID) do hits[#hits + 1] = k end
                table.sort(hits)
                self:Print(string.format("  |cFF88CCFFsessionFromID|r: %d hits: %s",
                    #hits, #hits > 0 and table.concat(hits, ", ") or "ninguno"))
                for _, hk in ipairs(hits) do
                    local sess = saved.sessionFromID[hk]
                    if type(sess) == "table" then
                        local sKeys = {}
                        for sk in pairs(sess) do sKeys[#sKeys + 1] = tostring(sk) end
                        table.sort(sKeys)
                        self:Print(string.format("    %s keys: %s", hk, table.concat(sKeys, ", ")))
                        for _, sk in ipairs(sKeys) do
                            local sv2 = sess[sk]
                            local vs2 = (type(sv2) == "table") and "{...}" or tostring(sv2)
                            if #vs2 > 60 then vs2 = vs2:sub(1, 57) .. "..." end
                            self:Print(string.format("      .%s = %s", sk, vs2))
                        end
                        break -- Only show first
                    end
                end
            end

            -- Single-arg / type-based results (likely empty)
            if saved.source1arg then
                local hits = {}
                for k in pairs(saved.source1arg) do hits[#hits + 1] = tostring(k) end
                self:Print("  source1arg: " .. (#hits > 0 and table.concat(hits, ", ") or "ninguno"))
            end
            if saved.source2arg then
                local hits = {}
                for k in pairs(saved.source2arg) do hits[#hits + 1] = k end
                self:Print("  source2arg: " .. (#hits > 0 and table.concat(hits, ", ") or "ninguno"))
            end
        else
            self:Print(" ")
            self:Print("|cFF888888[MeterExplore]|r No hay datos guardados de runs anteriores.")
            self:Print("  Los datos se capturan automáticamente durante una M+.")
        end
    elseif cmd == "pb" or cmd == "personalbest" then
        if self.PersonalBest then
            local pbs = self.PersonalBest:GetAllDungeonPBs()
            if not next(pbs) then
                self:Print("|cFFe8b84aPersonal Best:|r Sin records aún.")
            else
                self:Print("|cFFe8b84a═════ Personal Bests ═════|r")
                for dKey, data in pairs(pbs) do
                    if data.highestKey then
                        self:Print(string.format("  |cFFe8b84a%s|r — Mejor: +%d",
                            dKey, data.highestKey.keyLevel))
                    end
                end
            end
        else
            self:Print("|cFFee3333Módulo de Personal Best no disponible.|r")
        end
    elseif cmd == "rebuild" or cmd == "reconstruir" then
        if self.PersonalBest then
            local count = self.PersonalBest:RebuildFromHistory()
            self:Print(string.format("|cFF21de66[PersonalBest]|r Reconstruidos %d records.", count))
        end
    elseif cmd == "echotest" then
        -- Diagnostico decisivo para el "todo sale dos veces".
        -- Imprime UNA linea con un contador que sube en cada invocacion:
        --   "echo #1" seguido de "echo #1"  -> Print esta duplicando la salida
        --   "echo #1" seguido de "echo #2"  -> el comando se ejecuto dos veces
        -- Sin esto solo se puede especular sobre cual de las dos cosas pasa.
        self._echoN = (self._echoN or 0) + 1
        self:Print(string.format("|cFF88CCFFecho #%d|r  (si ves este numero repetido, Print duplica; si sube, el comando corrio dos veces)", self._echoN))
    elseif cmd == "capcalib" or cmd == "calib" then
        if self.Calibration then
            for _, line in ipairs(self.Calibration:Lines()) do self:Print(line) end
        else
            self:Print("|cFFff9922Modulo de calibracion no cargado.|r")
        end
    elseif cmd == "capclear" then
        if self.Calibration then self.Calibration:Clear() end
    elseif cmd == "rutastodas" or cmd == "importarrutas" then
        local AR = self.AdaptiveRoute
        if not (AR and AR.ImportAllFromMDT) then
            self:Print("|cFFff9922Motor de ruta adaptativa no cargado.|r")
        else
            local ok, info = AR:ImportAllFromMDT()
            if not ok then
                self:Print("|cFFff5555Rutas MDT:|r " .. tostring(info))
            else
                self:Print(string.format("|cFF21de66Rutas importadas:|r %d · omitidas %d",
                    info.imported, info.skipped))
                for _, l in ipairs(info.lines) do self:Print(l) end
            end
        end
    elseif cmd == "fuentes" then
        local TH = self.Theme
        local list = TH and TH.GetFontList and TH:GetFontList() or {}
        if #list == 0 then
            self:Print("|cFFff9922Sin lista de fuentes.|r Se usa la del tema.")
            local why = (TH and TH.LSMDiagnosis) and TH:LSMDiagnosis() or nil
            self:Print("  Motivo: " .. (why or "desconocido."))
            self:Print("  LibSharedMedia la traen BugSack, Plater, Details o ThreatPlates.")
        else
            self:Print(string.format("|cFFd9b33e%d fuentes disponibles|r (|cFFf7d470/emp fuente <nombre>|r):", #list))
            local line = {}
            for i, n in ipairs(list) do
                line[#line + 1] = n
                if #line == 4 or i == #list then
                    self:Print("  " .. table.concat(line, "  |  "))
                    line = {}
                end
            end
            local cur = self.db and self.db.profile and self.db.profile.settings
                        and self.db.profile.settings.uiFont
            self:Print("Actual: |cFFffffff" .. tostring(cur or "(la del tema)") .. "|r")
        end
    elseif cmd == "fuente" then
        -- El nombre se saca del input ORIGINAL, no de args: las fuentes llevan
        -- espacios y mayusculas ("Accidental Presidency") y args viene en
        -- minusculas y troceado por espacios.
        local name = (input or ""):match("^%s*%S+%s+(.-)%s*$")
        local st = self.db and self.db.profile and self.db.profile.settings
        if not st then
            self:Print("|cFFff5555Configuracion no disponible.|r")
        elseif not name or name == "" then
            self:Print("Uso: |cFFf7d470/emp fuente <nombre>|r  ·  |cFFf7d470/emp fuente reset|r")
        elseif name:lower() == "reset" then
            st.uiFont = nil
            if self.Colors and self.Colors.RefreshFonts then self.Colors:RefreshFonts() end
            self:Print("|cFF21de66Fuente restaurada|r a la del tema.")
        else
            -- Se comprueba que la fuente EXISTA antes de darla por buena:
            -- guardar un nombre invalido dejaria la UI en el fallback sin que
            -- el usuario supiera por que.
            local TH = self.Theme
            local lsm = TH and TH.GetLSM and TH:GetLSM()
            local found = nil
            if lsm then
                for _, n in ipairs(TH:GetFontList()) do
                    if n:lower() == name:lower() then found = n; break end
                end
            end
            if not lsm then
                self:Print("|cFFff9922LibSharedMedia no disponible|r: no se puede cambiar la fuente.")
            elseif not found then
                self:Print("|cFFff9922No existe una fuente llamada|r '" .. name .. "'. Mira |cFFf7d470/emp fuentes|r.")
            else
                st.uiFont = found
                if self.Colors and self.Colors.RefreshFonts then self.Colors:RefreshFonts() end
                self:Print("|cFF21de66Fuente aplicada:|r " .. found)
            end
        end
    elseif cmd == "sync" or cmd == "sincro" then
        local AR = self.AdaptiveRoute
        if AR and AR.SyncReport then AR:SyncReport(false)
        else self:Print("|cFFff9922Motor de ruta adaptativa no cargado.|r") end
    elseif cmd == "mdtprobe" then
        local AR = self.AdaptiveRoute
        if AR and AR.ProbeMDT then
            for _, line in ipairs(AR:ProbeMDT()) do self:Print(line) end
        else
            self:Print("|cFFff9922Motor de ruta adaptativa no cargado.|r")
        end
    elseif cmd == "rutamdt" or cmd == "cargarruta" then
        local AR = self.AdaptiveRoute
        if not (AR and AR.ImportFromOpenMDT) then
            self:Print("|cFFff9922Motor de ruta adaptativa no cargado.|r")
        else
            local ok, info = AR:ImportFromOpenMDT()
            if not ok then
                self:Print("|cFFff5555Ruta MDT:|r " .. tostring(info))
            else
                self:Print(string.format(
                    "|cFF21de66Ruta MDT cargada:|r %d pulls · perfil |cFFffffff%s|r%s",
                    info.pulls, tostring(info.key),
                    info.started and " · |cFF21de66activa en esta llave|r" or ""))
                if info.mapped then
                    self:Print("  npcIDs mapeados: las marcas |cffffcc00[SKIP]|r funcionaran.")
                else
                    self:Print("  |cFFff9922Sin npcIDs|r (" .. tostring(info.npcWhy or "MDT no dio datos de enemigos") ..
                               "): habra delta y skips calculados, pero SIN marcas en las placas.")
                end
            end
        end
    elseif cmd == "skipstatus" or cmd == "ruta" then
        local AR = self.AdaptiveRoute
        if AR and AR.StatusLines then
            for _, line in ipairs(AR:StatusLines()) do self:Print(line) end
        else
            self:Print("|cFFff9922Motor de ruta adaptativa no cargado.|r")
        end
    elseif cmd == "skiptest" then
        -- Prueba en seco del solver: es la unica pieza verificable sin entrar
        -- a una M+, asi que conviene poder mirarla en cualquier momento.
        local AR = self.AdaptiveRoute
        if AR and AR.TestSolver then
            for _, line in ipairs(AR:TestSolver(tonumber(args[2]))) do self:Print(line) end
        else
            self:Print("|cFFff9922Motor de ruta adaptativa no cargado.|r")
        end
    -- ═══════════════════════════════════════════════════════════════════
    -- NAVEGADOR DE PULLS
    --
    -- Manual a proposito. Avanzar solo exigiria saber que el pack actual ha
    -- muerto, y el combat log esta cerrado en Midnight: un avance adivinado
    -- daria un numero convencido y falso.
    -- ═══════════════════════════════════════════════════════════════════
    elseif cmd == "dungeon" or cmd == "mazmorra" then
        local DC = self.DungeonContext
        if not DC then
            self:Print("|cFFff9922DungeonContext no esta cargado.|r")
            return
        end
        DC:Refresh("comando")
        self:Print("|cFFe8b84a--- dungeon ---|r")
        for _, line in ipairs(DC:StatusLines()) do self:Print(line) end
    elseif cmd == "lifecycle" or cmd == "ciclo" then
        local DC = self.DungeonContext
        if not DC then
            self:Print("|cFFff9922DungeonContext no esta cargado.|r")
            return
        end
        self:Print("|cFFe8b84a--- lifecycle ---|r")
        for _, line in ipairs(DC:LifecycleLines()) do self:Print(line) end
    elseif cmd == "party" or cmd == "grupo" then
        local PP = self.PartyProfiler
        if not PP then
            self:Print("|cFFff9922PartyProfiler no esta cargado.|r")
            return
        end
        PP:Refresh("comando")
        self:Print("|cFFe8b84a--- party ---|r")
        for _, line in ipairs(PP:StatusLines()) do self:Print(line) end
    elseif cmd == "runtime" or cmd == "capacidades" then
        local RC = self.RuntimeCapabilities
        if not RC then
            self:Print("|cFFff9922RuntimeCapabilities no esta cargado.|r")
            return
        end
        RC:Probe()
        for _, line in ipairs(RC:StatusLines(args[2] == "todo" or args[2] == "verbose")) do
            self:Print(line)
        end
        if args[2] ~= "todo" and args[2] ~= "verbose" then
            self:Print("|cFF999999Usa |cFFf7d470/emp runtime todo|r para ver el motivo de cada estado.|r")
        end
    -- ═══════════════════════════════════════════════════════════════════
    -- SPIKE FASE S — cuanto se puede resolver de una placa viva.
    -- Solo diagnostico. No cambia el comportamiento del addon.
    -- ═══════════════════════════════════════════════════════════════════
    elseif cmd == "probe" or cmd == "sondeo" then
        local LER = self.AdaptiveRoute and self.AdaptiveRoute.LiveEnemyResolver
        if not LER then
            self:Print("|cFFff9922LiveEnemyResolver no esta cargado.|r")
            return
        end
        local unit = args[2] or "target"
        self:Print("|cFFe8b84a--- probe " .. tostring(unit) .. " ---|r")
        for _, line in ipairs(LER:UnitLines(unit)) do self:Print(line) end
    elseif cmd == "plates" or cmd == "placas" then
        -- Informe de ANCLAJE, no de identidad. Aqui no se lee ni una API de
        -- unidad: solo tokens de placa y constantes del provider. El volcado
        -- del spike, que si mira tropas e identidad, vive en probeplates.
        local NAP = self.AdaptiveRoute and self.AdaptiveRoute.NameplateAnchorProvider
        if not NAP then
            self:Print("|cFFff9922NameplateAnchorProvider no esta cargado.|r")
            return
        end
        for _, line in ipairs(NAP:StatusLines()) do self:Print(line) end
    -- ═══════════════════════════════════════════════════════════════════
    -- CAPA DE EVIDENCIAS (fase 3)
    --
    -- Informe de INVESTIGACION. Estas evidencias no llegan a Guidance ni
    -- producen flechas: solo se miden. Aqui no se imprime GUID, nombre,
    -- vida, tropas, npcID ni el numero de threat — unicamente los enums de
    -- EngagementEvidence y UnitLinkEvidence, que son literales nuestros.
    --
    -- ENGAGED no es MATCH y SAME_UNIT tampoco. Por eso el informe usa el
    -- vocabulario de cada modulo tal cual, sin traducirlo al de Guidance:
    -- una traduccion invitaria a confundirlos.
    -- ═══════════════════════════════════════════════════════════════════
    elseif cmd == "evidence" or cmd == "evidencia" then
        local ARe = self.AdaptiveRoute
        local EE  = ARe and ARe.EngagementEvidence
        local UL  = ARe and ARe.UnitLinkEvidence
        if not (EE and UL) then
            self:Print("|cFFff9922La capa de evidencias no esta cargada.|r")
            return
        end

        local visibles = self:_VisibleNameplates()

        self:Print("|cFFe8b84a--- evidence ---|r")
        self:Print("visible=" .. #visibles)
        if #visibles == 0 then
            self:Print("|cFFff9922No hay placas visibles.|r Acercate a unos mobs.")
            return
        end

        local eng,   rE = EE:EvaluateTokens(visibles)
        local links, rL = UL:EvaluateTokens(visibles)

        if args[2] == "summary" or args[2] == "resumen" then
            self:Print("engaged=" .. rE.engaged)
            self:Print("notEngaged=" .. rE.notEngaged)
            self:Print("unknownEngagement=" .. rE.unknown)
            self:Print(" ")
            self:Print("targetLinked=" .. rL.TARGET)
            self:Print("mouseoverLinked=" .. rL.MOUSEOVER)
            self:Print("focusLinked=" .. rL.FOCUS)
            self:Print("softenemyLinked=" .. rL.SOFTENEMY)
            self:Print("|cFF999999(enlace = SAME_UNIT; DIFFERENT_UNIT y UNKNOWN no cuentan)|r")
            return
        end

        for _, tok in ipairs(visibles) do
            local l = links[tok] or {}
            self:Print(" ")
            self:Print("|cFFf7d470" .. tok .. "|r")
            self:Print("engagement=" .. tostring(eng[tok]))
            self:Print("target=" .. tostring(l.TARGET))
            self:Print("mouseover=" .. tostring(l.MOUSEOVER))
            self:Print("focus=" .. tostring(l.FOCUS))
            self:Print("softenemy=" .. tostring(l.SOFTENEMY))
        end
        self:Print(" ")
        self:Print("|cFF999999(investigacion: estas evidencias NO producen flechas)|r")
    -- ═══════════════════════════════════════════════════════════════════
    -- CASTS (fase 3, experimental)
    --
    -- Combina el sondeo actual con los eventos escuchados. Ningun valor del
    -- cliente se imprime sin haber pasado primero la guarda de secreto.
    -- ═══════════════════════════════════════════════════════════════════
    elseif cmd == "castevidence" or cmd == "castevidencia" then
        local CE = self.AdaptiveRoute and self.AdaptiveRoute.CastEvidence
        local ECE = self.AdaptiveRoute and self.AdaptiveRoute.EventCastEvidence
        if not CE or not ECE then
            self:Print("|cFFff9922CastEvidence/EventCastEvidence no estan cargados.|r")
            return
        end
        local visibles = self:_VisibleNameplates()
        self:Print("|cFFe8b84a--- cast evidence ---|r")
        self:Print("visible=" .. #visibles)
        if #visibles == 0 then
            self:Print("|cFFff9922No hay placas visibles.|r Acercate a unos mobs.")
        end

        local mapa = CE:EvaluateTokens(visibles)
        local resumen = { tokensWithCast = 0, tokensWithSafeSpellID = 0,
            tokensWithSecretSpellID = 0, tokensWithEventOnly = 0 }
        for _, tok in ipairs(visibles) do
            local polled = mapa[tok] or {}
            local event = ECE:InspectToken(tok)
            local castState = polled.state
            if castState == "NOT_CASTING" then castState = "NONE" end
            if (castState == "NONE" or castState == "UNKNOWN") and
               (event.castState == "CASTING" or event.castState == "CHANNELING") then
                castState = event.castState
            end
            if castState == "CASTING" or castState == "CHANNELING" then
                resumen.tokensWithCast = resumen.tokensWithCast + 1
            end
            if event.spellIDState == "AVAILABLE" then
                resumen.tokensWithSafeSpellID = resumen.tokensWithSafeSpellID + 1
            elseif event.spellIDState == "SECRET" then
                resumen.tokensWithSecretSpellID = resumen.tokensWithSecretSpellID + 1
            end
            if event.eventState == "SEEN" and event.spellIDState ~= "AVAILABLE" then
                resumen.tokensWithEventOnly = resumen.tokensWithEventOnly + 1
            end
            if args[2] ~= "summary" and args[2] ~= "resumen" then
                self:Print(" ")
                self:Print("|cFFf7d470" .. tok .. "|r")
                self:Print("unitExists=" .. CE:UnitExistsState(tok))
                self:Print("castState=" .. castState)
                self:Print("eventState=" .. event.eventState)
                self:Print("tokenLinked=" .. event.tokenLinked)
                self:Print("spellIDState=" .. event.spellIDState)
                self:Print("safeSpellID=" .. event.safeSpellID)
                self:Print("eventType=" .. event.eventType)
                self:Print("identityState=" .. event.identityState)
                self:Print("ageMs=" .. (event.ageMs and string.format("%d", event.ageMs) or "-"))
                -- Este campo solo existe cuando EventCastEvidence ya probo
                -- que el valor es un numero publico.
                if event.safeSpellIDValue then
                    self:Print("safeSpellIDValue=" .. string.format("%d", event.safeSpellIDValue))
                end
            end
        end
        self:Print(" ")
        self:Print("tokensWithCast=" .. resumen.tokensWithCast)
        self:Print("tokensWithSafeSpellID=" .. resumen.tokensWithSafeSpellID)
        self:Print("tokensWithSecretSpellID=" .. resumen.tokensWithSecretSpellID)
        self:Print("tokensWithEventOnly=" .. resumen.tokensWithEventOnly)
        self:Print("|cFF999999(CAST EVENT + SAFE SPELLID + TOKEN LINKED != IDENTITY RESOLVED)|r")
    -- ═══════════════════════════════════════════════════════════════════
    -- AURAS (fase 3, experimental)
    --
    -- Cabecera con la POLITICA del cliente (C_Secrets.ShouldAurasBeSecret) y
    -- con que API de lectura existe. Esas dos lineas valen mas que el resto
    -- del informe: contestan la pregunta de la subfase de una sola vez.
    -- ═══════════════════════════════════════════════════════════════════
    elseif cmd == "auraevidence" or cmd == "auraevidencia" then
        local AE = self.AdaptiveRoute and self.AdaptiveRoute.AuraEvidence
        if not AE then
            self:Print("|cFFff9922AuraEvidence no esta cargado.|r")
            return
        end
        local visibles = self:_VisibleNameplates()
        self:Print("|cFFe8b84a--- aura evidence ---|r")
        self:Print("policy=" .. AE:SecrecyPolicy())
        self:Print("api=" .. AE:APIStatus())
        self:Print("visible=" .. #visibles)
        if #visibles == 0 then
            self:Print("|cFFff9922No hay placas visibles.|r Acercate a unos mobs.")
            return
        end

        local mapa, r = AE:EvaluateTokens(visibles)
        if args[2] == "summary" or args[2] == "resumen" then
            self:Print("available=" .. r.available)
            self:Print("none=" .. r.none)
            self:Print("unknown=" .. r.unknown)
            self:Print("safeSpellIDs=" .. r.safeSpellIDs)
            return
        end
        for _, tok in ipairs(visibles) do
            local e = mapa[tok] or {}
            local ids = e.spellIDs or {}
            self:Print(" ")
            self:Print("|cFFf7d470" .. tok .. "|r")
            self:Print("state=" .. tostring(e.state))
            self:Print("safeSpellIDs=" .. #ids)
            if #ids > 0 then
                -- Solo numeros ya comprobados. Se formatean con %d, que
                -- reventaria con cualquier cosa que no fuera un numero.
                local partes = {}
                for i = 1, #ids do partes[i] = string.format("%d", ids[i]) end
                self:Print("ids=" .. table.concat(partes, ","))
            end
        end
        self:Print(" ")
        self:Print("|cFF999999(no hay correlacion spellID -> npcID: eso es otra fase)|r")
    -- ═══════════════════════════════════════════════════════════════════
    -- CASTS POR EVENTO (fase 3, experimental)
    --
    -- Aqui NO se consultan las placas visibles: se enseña lo que el modulo
    -- lleva escuchado, que es otra cosa. Una placa puede haber dejado de
    -- verse y su cast seguir en la cache hasta que caduque.
    --
    -- spellIDEventSafeObserved es la respuesta de la subfase en una linea:
    -- si alguna vez un evento trajo un spellID que se pudo tocar.
    -- ═══════════════════════════════════════════════════════════════════
    elseif cmd == "eventcast" or cmd == "eventocast" then
        local ECE = self.AdaptiveRoute and self.AdaptiveRoute.EventCastEvidence
        if not ECE then
            self:Print("|cFFff9922EventCastEvidence no esta cargado.|r")
            return
        end
        local lista, r = ECE:Snapshot()
        self:Print("|cFFe8b84a--- event cast evidence ---|r")
        self:Print("tracked=" .. r.tracked)
        self:Print("spellIDEventSafeObserved=" ..
            (ECE:HasSafeSpellID() and "true" or "false"))

        if args[2] == "summary" or args[2] == "resumen" then
            self:Print("castStart=" .. r.castStart)
            self:Print("channelStart=" .. r.channelStart)
            self:Print("succeeded=" .. r.succeeded)
            self:Print("stopped=" .. r.stopped)
            self:Print("interrupted=" .. r.interrupted)
            self:Print("safeSpellIDs=" .. r.safeSpellIDs)
            self:Print("secretSpellIDs=" .. r.secretSpellIDs)
            self:Print("eventOnly=" .. r.eventOnly)
            self:Print("unknown=" .. r.unknown)
            return
        end

        if r.tracked == 0 then
            self:Print("|cFFff9922Nada escuchado.|r Haz un pull y repite mientras castean.")
            return
        end
        for _, e in ipairs(lista) do
            self:Print(" ")
            self:Print("|cFFf7d470" .. e.unitToken .. "|r")
            self:Print("eventType=" .. e.eventType)
            self:Print("tokenLinked=" .. e.tokenLinked)
            self:Print("castState=" .. e.castState)
            self:Print("spellIDState=" .. e.spellIDState)
            self:Print("safeSpellID=" .. e.safeSpellID)
            self:Print("identityState=" .. e.identityState)
            self:Print("ageMs=" .. (e.ageMs and string.format("%d", e.ageMs) or "-"))
            if e.safeSpellIDValue then
                self:Print("safeSpellIDValue=" .. string.format("%d", e.safeSpellIDValue))
            end
        end
        self:Print(" ")
        self:Print("|cFF999999(TTL " .. tostring(ECE.TTL) .. "s · un spellID legible seria una firma, no un MATCH)|r")
    -- ═══════════════════════════════════════════════════════════════════
    -- FORMA DEL PACK (fase 3, experimental)
    --
    -- Aqui se juntan las dos mitades: cuantos espera la ruta (dato estatico,
    -- de RouteProgress, que sigue siendo el dueño del pull) y cuantos estan
    -- peleando (EngagementEvidence). PackEvidence no conoce a ninguno de los
    -- dos: se le pasan los numeros ya hechos.
    --
    -- ALIGNED NO ES MATCH. Ni marca, ni avanza pull, ni pinta nada.
    -- ═══════════════════════════════════════════════════════════════════
    elseif cmd == "packevidence" or cmd == "pack" then
        local PE = self.AdaptiveRoute and self.AdaptiveRoute.PackEvidence
        if not PE then
            self:Print("|cFFff9922PackEvidence no esta cargado.|r")
            return
        end
        local RP = self.RouteProgress
        local DC = self.DungeonContext
        local runtimeState = DC and DC.GetState and DC:GetState() or nil
        local route = RP and RP.GetRoute and RP:GetRoute() or nil
        local pull  = RP and RP.GetCurrentPull and RP:GetCurrentPull() or nil
        local esperado, estadoCuenta = PE:ExpectedFromPull(pull)

        local res = PE:Evaluate({
            expectedCount      = esperado,
            expectedCountState = estadoCuenta,
            visibleTokens      = self:_VisibleNameplates(),
            runtimeState       = runtimeState,
        })

        local pullTxt = "-"
        if RP and RP.GetPullIndex and RP:GetPullIndex() then
            pullTxt = tostring(RP:GetPullIndex()) .. "/" .. tostring(RP:GetPullCount())
        end

        self:Print("|cFFe8b84a--- pack evidence ---|r")
        self:Print("runtimeState=" .. tostring(runtimeState or "-"))
        self:Print("route=" .. tostring(route and route.id or "-"))
        self:Print("pull=" .. pullTxt)
        self:Print("expectedCount=" .. tostring(res.expectedCount or "-"))
        self:Print("expectedCountState=" .. tostring(res.expectedCountState))
        self:Print("identityState=" .. tostring(res.identityState))
        self:Print("reasonCode=" .. tostring(res.reasonCode or "-"))

        if args[2] == "summary" or args[2] == "resumen" then
            self:Print("visible=" .. res.visible)
            self:Print("engaged=" .. res.engaged)
            self:Print("notEngaged=" .. res.notEngaged)
            self:Print("unknownEngagement=" .. res.unknownEngagement)
            self:Print("packState=" .. res.packState)
            self:Print("targetInEngaged=" .. tostring(res.links.TARGET))
            return
        end

        self:Print("visible=" .. res.visible)
        self:Print("engaged=" .. res.engaged)
        self:Print("notEngaged=" .. res.notEngaged)
        self:Print("unknownEngagement=" .. res.unknownEngagement)
        self:Print("packState=" .. res.packState)
        self:Print(" ")
        self:Print("targetInEngaged=" .. tostring(res.links.TARGET))
        self:Print("mouseoverInEngaged=" .. tostring(res.links.MOUSEOVER))
        self:Print("focusInEngaged=" .. tostring(res.links.FOCUS))
        self:Print("softenemyInEngaged=" .. tostring(res.links.SOFTENEMY))

        if #res.engagedTokens > 0 then
            self:Print(" ")
            self:Print("candidateTokens:")
            for _, tok in ipairs(res.engagedTokens) do self:Print(tok) end
        end
        self:Print(" ")
        self:Print("|cFFff9922ALIGNED no significa MATCH de ruta.|r|cFF999999 Un pack")
        self:Print("equivocado con el mismo numero de mobs dice ALIGNED igual.|r")
    elseif cmd == "probeplates" then
        local LER = self.AdaptiveRoute and self.AdaptiveRoute.LiveEnemyResolver
        if not LER then
            self:Print("|cFFff9922LiveEnemyResolver no esta cargado.|r")
            return
        end
        for _, line in ipairs(LER:PlateLines()) do self:Print(line) end
    elseif cmd == "resolverdump" then
        local LER = self.AdaptiveRoute and self.AdaptiveRoute.LiveEnemyResolver
        if not LER then
            self:Print("|cFFff9922LiveEnemyResolver no esta cargado.|r")
            return
        end
        self:Print("|cFFe8b84a--- resolverdump ---|r")
        for _, line in ipairs(LER:ResolverDumpLines()) do self:Print(line) end
    elseif cmd == "physicalgroups" then
        local PG = self.AdaptiveRoute and self.AdaptiveRoute.PhysicalGroupMetadata
        local RM = self.RouteManager
        local route = RM and RM:GetActiveRoute() or nil
        if not PG then
            self:Print("|cFFff9922PhysicalGroupMetadata no esta cargado.|r")
            return
        end
        if not route then
            self:Print("|cFFff9922No hay una ruta activa.|r")
            return
        end
        local RP = self.RouteProgress
        local pullIndex = tonumber(args[2]) or (RP and RP:GetPullIndex()) or 1
        self:Print("|cFFe8b84a--- physicalgroups ---|r")
        for _, line in ipairs(PG:StatusLines(route, pullIndex)) do self:Print(line) end
    elseif cmd == "groupcorrelation" then
        local ARc = self.AdaptiveRoute
        local GC = ARc and ARc.PhysicalGroupCorrelation
        local RM = self.RouteManager
        local RP = self.RouteProgress
        local DC = self.DungeonContext
        if not GC then
            self:Print("|cFFff9922PhysicalGroupCorrelation no esta cargado.|r")
            return
        end
        local route = RM and RM:GetActiveRoute() or nil
        local pullIndex = RP and RP:GetPullIndex() or nil
        local runtimeState = DC and DC:GetState() or "UNKNOWN"
        local result = GC:Correlate(route, pullIndex, self:_VisibleNameplates(), runtimeState)
        self:Print("|cFFe8b84a--- group correlation ---|r")
        for _, line in ipairs(GC:StatusLines(result)) do self:Print(line) end
    elseif cmd == "forcemap" then
        local LER = self.AdaptiveRoute and self.AdaptiveRoute.LiveEnemyResolver
        if not LER then
            self:Print("|cFFff9922LiveEnemyResolver no esta cargado.|r")
            return
        end
        for _, line in ipairs(LER:ForceMapLines()) do self:Print(line) end
    elseif cmd == "resolveplates" then
        local LER = self.AdaptiveRoute and self.AdaptiveRoute.LiveEnemyResolver
        if not LER then
            self:Print("|cFFff9922LiveEnemyResolver no esta cargado.|r")
            return
        end
        local marcadas, total, err, r = LER:MarkMatchesOnly()
        if err then
            self:Print("|cFFff9922" .. tostring(err) .. "|r")
            return
        end
        self:Print(string.format(
            "|cFF21de66Resolve:|r %d flecha(s) sobre %d placa(s) — SOLO los MATCH.",
            marcadas, total))
        if r then
            self:Print(string.format("  match=%d ambiguous=%d no_match=%d unknown=%d",
                r.match or 0, r.ambiguous or 0, r.no_match or 0, r.unknown or 0))
        end
    elseif cmd == "route" or cmd == "ruta2" then
        local RM = self.RouteManager
        if not RM then
            self:Print("|cFFff9922RouteManager no esta cargado.|r")
            return
        end
        self:Print("|cFFe8b84a--- route ---|r")
        for _, line in ipairs(RM:StatusLines()) do self:Print(line) end
    elseif cmd == "guidance" then
        local G = self.GuidanceEngine
        if not G then
            self:Print("|cFFff9922GuidanceEngine no esta cargado.|r")
            return
        end
        self:Print("|cFFe8b84a--- guidance ---|r")
        for _, line in ipairs(G:StatusLines()) do self:Print(line) end
    elseif cmd == "guidancedetail" then
        local G = self.GuidanceEngine
        if not G then
            self:Print("|cFFff9922GuidanceEngine no esta cargado.|r")
            return
        end
        self:Print("|cFFe8b84a--- guidance detail ---|r")
        for _, line in ipairs(G:DetailLines()) do self:Print(line) end
    -- ═══════════════════════════════════════════════════════════════════
    -- ARROW DEMO (experimental)
    --
    -- Pipeline visual APARTE del de produccion: asigna flechas por una
    -- heuristica aproximada y registra telemetria de toda la llave. No es
    -- identidad, no es MATCH y no mueve el pull. Ver ArrowDemo.lua.
    -- ═══════════════════════════════════════════════════════════════════
    elseif cmd == "arrowdemo" then
        local ARd = self.AdaptiveRoute
        local AD  = ARd and ARd.ArrowDemo
        local TEL = ARd and ARd.ArrowDemoTelemetry
        if not (AD and TEL) then
            self:Print("|cFFff9922Arrow Demo no esta cargado.|r")
            return
        end
        local sub = args[2]
        if sub == "on" then
            AD:SetEnabled(true)
        elseif sub == "off" then
            if not AD:SetEnabled(false) then self:Print("Arrow Demo ya estaba apagado.") end
        elseif sub == "report" or sub == "informe" then
            local run = TEL:GetRun(args[3] and tonumber(args[3]) or nil)
            for _, line in ipairs(TEL:ReportLines(run)) do self:Print(line) end
        elseif sub == "log" then
            local run = TEL:GetRun(nil)
            local lineas = TEL:LogLines(run, tonumber(args[3]) or 15)
            if #lineas == 0 then
                self:Print("|cFFff9922Sin eventos registrados.|r")
            else
                self:Print("|cFFe8b84a--- arrow demo log ---|r")
                for _, line in ipairs(lineas) do self:Print(line) end
            end
        elseif sub == "export" or sub == "exportar" then
            local run = TEL:GetRun(args[3] and tonumber(args[3]) or nil)
            local texto = TEL:Export(run)
            if not texto then
                self:Print("|cFFff9922No hay ninguna run de Arrow Demo que exportar.|r")
            elseif self.Export and self.Export.CopyToClipboard then
                self.Export:CopyToClipboard(texto)
            else
                self:Print("|cFFff9922La ventana de exportacion no esta disponible.|r")
            end
        elseif sub == "clear" or sub == "borrar" then
            local n = TEL:ClearStored()
            self:Print(string.format("Arrow Demo: %d run(s) guardada(s) borrada(s).", n))
        else
            for _, line in ipairs(AD:StatusLines()) do self:Print(line) end
            if sub ~= "status" and sub ~= "estado" then
                self:Print("Uso: /emp arrowdemo on | off | status | report [n] | log [n] | export [n] | clear")
            end
        end
    -- ═══════════════════════════════════════════════════════════════════
    -- ALINEACION RUTA <-> EJECUCION FISICA (fase 4). SOLO DIAGNOSTICO.
    -- Nada de lo que se imprima aqui ha movido el pull ni ha pintado nada.
    -- ═══════════════════════════════════════════════════════════════════
    elseif cmd == "alignmentdetail" or cmd == "alignedetail" then
        local RAl = self.AdaptiveRoute and self.AdaptiveRoute.RouteAlignment
        if not RAl then
            self:Print("|cFFff9922La capa de alineacion no esta cargada.|r")
            return
        end
        for _, line in ipairs(RAl:DetailLines()) do self:Print(line) end
    elseif cmd == "align" or cmd == "alineacion" then
        local ARd = self.AdaptiveRoute
        local RAl = ARd and ARd.RouteAlignment
        if not RAl then
            self:Print("|cFFff9922La capa de alineacion no esta cargada.|r")
            return
        end
        local sub = args[2]
        if sub == "detail" or sub == "detalle" then
            for _, line in ipairs(RAl:DetailLines()) do self:Print(line) end
        elseif sub == "candidates" or sub == "candidatos" then
            for _, line in ipairs(RAl:CandidateLines()) do self:Print(line) end
        elseif sub == "history" or sub == "historial" then
            for _, line in ipairs(RAl:HistoryLines()) do self:Print(line) end
        elseif sub == "episodes" or sub == "episodios" then
            local EET = ARd.ExecutionEpisodeTracker
            if not EET then
                self:Print("|cFFff9922ExecutionEpisodeTracker no esta cargado.|r")
            else
                for _, line in ipairs(EET:StatusLines()) do self:Print(line) end
            end
        elseif sub == "signature" or sub == "firma" then
            local RM = self.RouteManager
            local RP = self.RouteProgress
            local n = tonumber(args[3]) or (RP and RP:GetPullIndex()) or 1
            local sig, err = RM and RM:GetPullSignature(nil, n)
            if not sig then
                self:Print("|cFFff9922" .. tostring(err or "sin ruta") .. "|r")
            else
                self:Print("|cFFe8b84a--- Firma estatica del pull " .. n .. " ---|r")
                for _, line in ipairs(ARd.RouteSignature:Lines(RM:GetActiveRoute(), n)) do
                    self:Print(line)
                end
            end
        elseif sub == "on" then
            RAl:SetEnabled(true)
            self:Print("Inferencia de alineacion ACTIVADA (sigue sin mover la ruta).")
        elseif sub == "off" then
            RAl:SetEnabled(false)
            self:Print("Inferencia de alineacion APAGADA.")
        else
            for _, line in ipairs(RAl:StatusLines()) do self:Print(line) end
            if sub ~= "status" and sub ~= "estado" then
                self:Print("Uso: /emp align [status] | detail | candidates | history | episodes | signature [n] | on/off")
            end
        end
    -- ═══════════════════════════════════════════════════════════════════
    -- PRUEBA VISUAL DEL PIPELINE
    --
    -- Recorre RouteProgress -> GuidanceEngine -> RouteArrowPresenter ->
    -- RouteArrows con decisiones DEBUG_FORCED. NO llama a RouteArrows
    -- directamente: si lo hiciera, no probaria nada del camino.
    -- ═══════════════════════════════════════════════════════════════════
    elseif cmd == "arrowpulltest" then
        local G  = self.GuidanceEngine
        local P  = self.RouteArrowPresenter
        local RP = self.RouteProgress
        local RM = self.RouteManager
        if not (G and P) then
            self:Print("|cFFff9922GuidanceEngine o RouteArrowPresenter no cargados.|r")
            return
        end
        if args[2] == "clear" or args[2] == "limpiar" then
            local n = G:ClearDebugForced()
            P:Reevaluate()
            self:Print(string.format("|cFF21de66Prueba visual apagada|r (%d placas forzadas).", n))
            return
        end

        -- Las placas se toman del registro de Guidance, no de una consulta
        -- propia: asi la prueba usa exactamente lo que el motor ve.
        local visibles = G:GetVisible()
        if #visibles == 0 then
            self:Print("|cFFff9922No hay placas visibles.|r Acercate a unos mobs.")
            return
        end
        local cuantas = tonumber(args[2]) or 3
        local elegidas = {}
        for i = 1, math.min(cuantas, #visibles) do elegidas[i] = visibles[i] end
        G:SetDebugForced(elegidas)
        local marcadas = P:Reevaluate()

        local route = RM and RM:GetActiveRoute()
        self:Print("|cFFe8b84aMitzuMPlus ARROW PULL TEST|r")
        self:Print("mode=|cFFf7d470DEBUG_VISUAL|r")
        self:Print("route=" .. tostring(route and route.id or "ninguna"))
        self:Print("pull=" .. tostring(RP and RP:GetPullIndex() or "?"))
        self:Print("visible=" .. #visibles)
        self:Print("forcedGuidance=" .. G:CountForced())
        self:Print("arrowsVisible=" .. tostring(marcadas))
        self:Print("realEnemyMatching=|cFFff9922false|r")
        self:Print("|cFF999999Esto NO es identificacion automatica: son decisiones")
        self:Print("DEBUG_FORCED que recorren Guidance y Presenter para demostrar")
        self:Print("el pipeline. Se apagan solas al cambiar de pull, o con")
        self:Print("|cFFf7d470/emp arrowpulltest clear|r.|r")
    elseif cmd == "clock" or cmd == "reloj" then
        local CC = self.ChallengeClock
        if not CC then
            self:Print("|cFFff9922ChallengeClock no esta cargado.|r")
            return
        end
        self:Print("|cFFe8b84a--- challenge clock ---|r")
        for _, line in ipairs(CC:StatusLines()) do self:Print(line) end
    elseif cmd == "session" or cmd == "sesion" then
        local RS = self.RunSession
        if not RS then
            self:Print("|cFFff9922RunSession no esta cargado.|r")
            return
        end
        self:Print("|cFFe8b84a--- run session ---|r")
        for _, line in ipairs(RS:StatusLines()) do self:Print(line) end
    elseif cmd == "testnative" then
        local RM = self.RouteManager
        if not RM then
            self:Print("|cFFff9922RouteManager no esta cargado.|r")
            return
        end
        for _, line in ipairs(RM:SelfTestNativeLines()) do self:Print(line) end
    elseif cmd == "routes" or cmd == "rutas" then
        local RM = self.RouteManager
        if not RM then
            self:Print("|cFFff9922RouteManager no esta cargado.|r")
            return
        end
        for _, line in ipairs(RM:RoutesLines(args[2])) do self:Print(line) end
    elseif cmd == "next" or cmd == "siguiente" then
        local RP = self.RouteProgress
        if not RP then
            self:Print("|cFFff9922RouteProgress no esta cargado.|r")
            return
        end
        local antes = RP:GetPullIndex()
        local ok, info = RP:NextPull("MANUAL")
        if ok then
            self:Print(string.format("|cFF21de66Pull %s -> %s|r de %d",
                tostring(antes), tostring(info), RP:GetPullCount()))
        else
            self:Print("|cFFff9922" .. tostring(info) .. "|r")
        end
    elseif cmd == "prev" or cmd == "anterior" then
        local RP = self.RouteProgress
        if not RP then
            self:Print("|cFFff9922RouteProgress no esta cargado.|r")
            return
        end
        local antes = RP:GetPullIndex()
        local ok, info = RP:PreviousPull("MANUAL")
        if ok then
            self:Print(string.format("|cFF21de66Pull %s -> %s|r de %d",
                tostring(antes), tostring(info), RP:GetPullCount()))
        else
            self:Print("|cFFff9922" .. tostring(info) .. "|r")
        end
    -- ═══════════════════════════════════════════════════════════════════
    -- /emp pull  — ahora lo sirve RouteProgress, que es el dueño del pull.
    -- PullNavigator queda como respaldo mientras existan rutas cargadas por
    -- el camino viejo; se sincroniza solo via MITZU_PULL_CHANGED.
    -- ═══════════════════════════════════════════════════════════════════
    elseif cmd == "pull" then
        local RP = self.RouteProgress
        local sub = args[2]
        if RP and RP:GetRoute() then
            if sub == nil then
                self:Print("|cFFe8b84a--- current pull ---|r")
                for _, line in ipairs(RP:StatusLines()) do self:Print(line) end
                return
            elseif sub == "next" or sub == "siguiente" then
                local ok, info = RP:NextPull("MANUAL")
                self:Print(ok and string.format("|cFF21de66Pull actual:|r %s de %d",
                        tostring(info), RP:GetPullCount())
                    or ("|cFFff9922" .. tostring(info) .. "|r"))
                return
            elseif sub == "prev" or sub == "anterior" then
                local ok, info = RP:PreviousPull("MANUAL")
                self:Print(ok and string.format("|cFF21de66Pull actual:|r %s de %d",
                        tostring(info), RP:GetPullCount())
                    or ("|cFFff9922" .. tostring(info) .. "|r"))
                return
            elseif sub == "reset" then
                RP:SetPull(1, "MANUAL")
                self:Print("|cFF21de66Pull actual:|r 1 de " .. RP:GetPullCount())
                return
            else
                local ok, info = RP:SetPull(sub, "MANUAL")
                self:Print(ok and string.format("|cFF21de66Pull actual:|r %s de %d",
                        tostring(info), RP:GetPullCount())
                    or ("|cFFff9922" .. tostring(info) .. "|r"))
                return
            end
        end
        -- Sin ruta nativa cargada: el navegador viejo sigue contestando.
        local PN = self.AdaptiveRoute and self.AdaptiveRoute.PullNavigator
        if not PN then
            self:Print("|cFFff9922No hay ninguna ruta cargada.|r")
            return
        end
        for _, line in ipairs(PN:StatusLines()) do self:Print(line) end
    elseif cmd == "pullinfo" then
        local DS = self.AdaptiveRoute and self.AdaptiveRoute.DataStructure
        local idx = DS and DS:Get()
        if not idx then
            self:Print("|cFFff9922No hay ninguna ruta indexada.|r Entra a la mazmorra o usa |cFFf7d470/emp rutamdt|r.")
            return
        end
        local n = tonumber(args[2]) or (self.AdaptiveRoute.PullNavigator
                  and self.AdaptiveRoute.PullNavigator:GetCurrentPull()) or 1
        local enemies = DS:EnemiesOf(n)
        self:Print(string.format("|cFFe8b84aPull %d|r de %d", n, idx.pullCount or 0))
        if not enemies or #enemies == 0 then
            self:Print("  Sin identidad de clones. Reimporta la ruta con |cFFf7d470/emp rutastodas|r.")
            return
        end
        -- Solo datos de la RUTA: indices y npcIDs del preset de MDT. Nada que
        -- venga de una unidad viva, asi que no hay valores secretos que tocar.
        local totalClones = 0
        for _, e in ipairs(enemies) do
            local clones = e.clones or {}
            totalClones = totalClones + #clones
            self:Print(string.format("  enemyIdx |cFFf7d470%d|r · npcID %s · tropas %s · clones: %s",
                e.enemyIdx,
                e.npcID and tostring(e.npcID) or "|cFFff9922desconocido|r",
                e.forceCount and tostring(e.forceCount) or "?",
                #clones > 0 and table.concat(clones, ", ") or "(ninguno)"))
        end
        self:Print(string.format("  total: %d grupos · %d clones", #enemies, totalClones))
    elseif cmd == "marktarget" then
        local PUR = self.AdaptiveRoute and self.AdaptiveRoute.PullUnitResolver
        if not PUR then
            self:Print("|cFFff9922PullUnitResolver no esta cargado.|r")
            return
        end
        local ok, info, pull = PUR:MarkTarget()
        self:Print(ok and string.format("|cFF21de66Objetivo asignado|r al pull %d (%s).",
                                        pull, tostring(info))
                      or ("|cFFff9922No se pudo asignar:|r " .. tostring(info)))
    elseif cmd == "unmarktarget" then
        local PUR = self.AdaptiveRoute and self.AdaptiveRoute.PullUnitResolver
        if not PUR then
            self:Print("|cFFff9922PullUnitResolver no esta cargado.|r")
            return
        end
        local ok, info = PUR:UnmarkTarget()
        self:Print(ok and "|cFF21de66Asignacion retirada del objetivo.|r"
                      or ("|cFFff9922No se pudo retirar:|r " .. tostring(info)))
    elseif cmd == "hud" then
        local HUD = self.AdaptiveRoute and self.AdaptiveRoute.PullHUD
        if not HUD then
            self:Print("|cFFff9922PullHUD no esta cargado.|r")
            return
        end
        if args[2] == "reset" then
            HUD:ResetPosition()
            self:Print("|cFF21de66Posicion del HUD restaurada.|r")
        else
            self:Print("HUD de pulls: " ..
                (HUD:Toggle() and "|cFF21de66visible|r (arrastralo donde quieras)"
                              or "|cFFff9922oculto|r"))
        end
    -- ═══════════════════════════════════════════════════════════════════
    -- ROUTE ARROWS (fase 1) — capa visual aislada.
    --
    -- Estos comandos no tocan MDT, ni npcIDs, ni el solver. Sirven para
    -- demostrar que el renderizado funciona por si solo antes de conectarle
    -- nada. /emp arrowall es DEPURACION y desaparecera cuando lo este.
    -- ═══════════════════════════════════════════════════════════════════
    elseif cmd == "arrow" or cmd == "flecha" then
        local RA = self.AdaptiveRoute and self.AdaptiveRoute.RouteArrows
        if not RA then
            self:Print("|cFFff9922RouteArrows no esta cargado.|r")
            return
        end
        local sub = args[2]
        if sub == "clear" or sub == "limpiar" then
            self:Print(string.format("|cFF21de66Flechas retiradas:|r %d", RA:ClearAll()))
        elseif sub == "debug" then
            local on = RA:SetDebug(not RA._debug)
            self:Print("Debug de RouteArrows: " ..
                (on and "|cFF21de66activado|r" or "|cFFff9922desactivado|r"))
            for _, line in ipairs(RA:StatusLines()) do self:Print(line) end
        elseif sub == "size" or sub == "tamano" then
            if args[3] == nil then
                self:Print(string.format("Tamano actual: |cFFf7d470%s|r. Usa |cFFf7d470/emp arrow size 48|r (10 a 120).",
                    tostring(RA:GetOption("arrowSize"))))
                return
            end
            local ok, info = RA:SetOption("arrowSize", args[3])
            self:Print(ok and string.format("|cFF21de66Tamano de flecha:|r %s", tostring(info))
                          or ("|cFFff9922No se pudo cambiar:|r " .. tostring(info)))
        elseif sub == "offset" then
            if args[3] == nil then
                self:Print(string.format("Offset actual: |cFFf7d470%s, %s|r. Usa |cFFf7d470/emp arrow offset 0 14|r.",
                    tostring(RA:GetOption("arrowOffsetX")), tostring(RA:GetOption("arrowOffsetY"))))
                return
            end
            local okX, infoX = RA:SetOption("arrowOffsetX", args[3])
            if not okX then
                self:Print("|cFFff9922No se pudo cambiar:|r " .. tostring(infoX))
                return
            end
            local infoY = RA:GetOption("arrowOffsetY")
            if args[4] ~= nil then
                local okY, r = RA:SetOption("arrowOffsetY", args[4])
                if not okY then
                    self:Print("|cFFff9922No se pudo cambiar:|r " .. tostring(r))
                    return
                end
                infoY = r
            end
            self:Print(string.format("|cFF21de66Offset de flecha:|r %s, %s", tostring(infoX), tostring(infoY)))
        elseif sub == "alpha" or sub == "opacidad" then
            if args[3] == nil then
                self:Print(string.format("Opacidad actual: |cFFf7d470%s|r. Usa |cFFf7d470/emp arrow alpha 0.8|r (0.1 a 1).",
                    tostring(RA:GetOption("arrowAlpha"))))
                return
            end
            local ok, info = RA:SetOption("arrowAlpha", args[3])
            self:Print(ok and string.format("|cFF21de66Opacidad de flecha:|r %s", tostring(info))
                          or ("|cFFff9922No se pudo cambiar:|r " .. tostring(info)))
        elseif sub == "anchor" or sub == "anclaje" then
            if args[3] == nil then
                self:Print(string.format("Anclaje actual: |cFFf7d470%s|r. Modos: |cFFf7d470auto|r (Threat Plates si esta), |cFFf7d470placa|r (centrado en el nameplate de Blizzard), |cFFf7d470tp|r.",
                    tostring(RA:GetOption("arrowAnchor"))))
                return
            end
            local ok, info = RA:SetAnchorMode(args[3])
            self:Print(ok and string.format("|cFF21de66Anclaje de flecha:|r %s", tostring(info))
                          or ("|cFFff9922No se pudo cambiar:|r " .. tostring(info)))
        elseif sub == "anim" or sub == "animacion" then
            local on = RA:ToggleAnimate()
            if on == nil then
                self:Print("|cFFff9922La DB de ajustes aun no esta lista.|r")
            else
                self:Print("Animacion de flechas: " ..
                    (on and "|cFF21de66activada|r" or "|cFFff9922desactivada|r"))
            end
        elseif sub == "reset" then
            if RA:ResetOptions() then
                self:Print("|cFF21de66Aspecto de las flechas restaurado|r (tamano 40, offset 0/8, opacidad 1, anclaje auto).")
            else
                self:Print("|cFFff9922La DB de ajustes aun no esta lista.|r")
            end
        elseif sub == "off" or sub == "quitar" then
            if not UnitExists("target") then
                self:Print("|cFFff9922No tienes objetivo.|r")
                return
            end
            self:Print(RA:UnmarkUnit("target")
                and "|cFF21de66Flecha quitada del objetivo.|r"
                or "|cFFff9922El objetivo no tenia flecha.|r")
        else
            if not UnitExists("target") then
                self:Print("|cFFff9922No tienes objetivo.|r Apunta a un mob y repite |cFFf7d470/emp arrow|r.")
                return
            end
            local ok, info = RA:MarkUnit("target")
            if ok then
                self:Print("|cFF21de66Flecha puesta|r sobre " .. tostring(info) .. ".")
            else
                self:Print("|cFFff9922No se pudo poner la flecha:|r " .. tostring(info))
            end
        end
    elseif cmd == "arrowall" then
        local RA = self.AdaptiveRoute and self.AdaptiveRoute.RouteArrows
        if not RA then
            self:Print("|cFFff9922RouteArrows no esta cargado.|r")
            return
        end
        local marcadas, placas = RA:DebugMarkAllPlates()
        self:Print(string.format(
            "|cFF21de66Route Arrows:|r %d flechas sobre %d placas visibles.",
            marcadas, placas))
        if placas == 0 then
            self:Print("  No hay ninguna placa visible ahora mismo. Acercate a unos mobs.")
        elseif marcadas < placas then
            self:Print("  Alguna placa se rechazo. Usa |cFFf7d470/emp arrow debug|r para ver por que.")
        end
    elseif cmd == "help" or cmd == "?" then
        self:PrintHelp()
    else
        self:Print("|cFFff9922Comando desconocido.|r Usa |cFFf7d470/MitzuMPlus help|r para ver la ayuda.")
    end
end

function MitzuMPlus:PrintHelp()
    self:Print("|cFFe8b84a═════ MitzuMPlus M+ HISTORIAL ═════|r")
    self:Print("|cFFf7d470/MitzuMPlus|r o |cFFf7d470/emp|r  - Abre/cierra la ventana")
    self:Print("|cFFf7d470/MitzuMPlus historial|r          - Pestaña Historial")
    self:Print("|cFFf7d470/MitzuMPlus config|r             - Configuración")
    self:Print("|cFFf7d470/MitzuMPlus echotest|r           - Diagnostico de mensajes duplicados en el chat")
    self:Print("|cFFf7d470/MitzuMPlus activar|r            - Activa tracking manual")
    self:Print("|cFFf7d470/MitzuMPlus desactivar|r         - Desactiva tracking")
    self:Print("|cFFf7d470/MitzuMPlus resetsize|r          - Restaura tamaño/escala de ventana")
    self:Print("|cFFf7d470/MitzuMPlus resetconfig|r        - Resetea configuración")
    self:Print("|cFFf7d470/MitzuMPlus capcalib|r           - Exactitud acumulada de la prediccion")
    self:Print("|cFFf7d470/MitzuMPlus rutastodas|r         - Importa TODAS las rutas de MDT de golpe")
    self:Print("|cFFf7d470/MitzuMPlus sync|r               - Confirma que ruta + los 3 addons estan sincronizados")
    self:Print("|cFFf7d470/MitzuMPlus rutamdt|r            - Carga la ruta que tengas abierta en MDT")
    self:Print("|cFFf7d470/MitzuMPlus mdtprobe|r           - Diagnostico: por que no se encuentra MDT")
    self:Print("|cFFf7d470/MitzuMPlus ruta|r               - Estado de la ruta adaptativa y los SKIP")
    self:Print("|cFFf7d470/MitzuMPlus skiptest [delta]|r   - Prueba en seco del solver de skips")
    self:Print("|cFFf7d470/MitzuMPlus arrow|r              - Pone una flecha de ruta sobre tu objetivo")
    self:Print("|cFFf7d470/MitzuMPlus arrow off|r          - Quita la flecha del objetivo")
    self:Print("|cFFf7d470/MitzuMPlus arrow clear|r        - Quita todas las flechas")
    self:Print("|cFFf7d470/MitzuMPlus arrow size N|r       - Tamano de la flecha (10-120, por defecto 40)")
    self:Print("|cFFf7d470/MitzuMPlus arrow offset X Y|r   - Desplazamiento de la flecha")
    self:Print("|cFFf7d470/MitzuMPlus arrow alpha N|r      - Opacidad de la flecha (0.1-1)")
    self:Print("|cFFf7d470/MitzuMPlus arrow anchor M|r     - Anclaje: auto / placa / tp")
    self:Print("|cFFf7d470/MitzuMPlus arrow anim|r         - Activa/desactiva el rebote")
    self:Print("|cFFf7d470/MitzuMPlus arrow reset|r        - Restaura el aspecto por defecto")
    self:Print("|cFFf7d470/MitzuMPlus arrow debug|r        - Diagnostico de Route Arrows")
    self:Print("|cFFf7d470/MitzuMPlus arrowall|r           - DEBUG: flecha sobre todas las placas visibles")
    self:Print(" ")
    self:Print("|cFFf7d470/MitzuMPlus pull|r               - Estado del pull actual")
    self:Print("|cFFf7d470/MitzuMPlus pull next|r          - Avanza un pull")
    self:Print("|cFFf7d470/MitzuMPlus pull prev|r          - Retrocede un pull")
    self:Print("|cFFf7d470/MitzuMPlus pull 7|r             - Salta al pull 7")
    self:Print("|cFFf7d470/MitzuMPlus pullinfo [N]|r       - Que clones trae ese pull segun MDT")
    self:Print("|cFFf7d470/MitzuMPlus marktarget|r         - Asigna tu objetivo al pull actual")
    self:Print("|cFFf7d470/MitzuMPlus unmarktarget|r       - Quita esa asignacion")
    self:Print("|cFFf7d470/MitzuMPlus hud|r                - Muestra/oculta PULL 4 / 21")
    self:Print("|cFFf7d470/MitzuMPlus dungeon|r            - Donde estoy y en que punto de la llave")
    self:Print("|cFFf7d470/MitzuMPlus lifecycle|r          - Ultima transicion de estado")
    self:Print("|cFFf7d470/MitzuMPlus party|r              - Los cinco del grupo: clase, rol y spec")
    self:Print("|cFFf7d470/MitzuMPlus route|r              - Ruta nativa cargada y su estado")
    self:Print("|cFFf7d470/MitzuMPlus routes|r             - Rutas disponibles para esta mazmorra")
    self:Print("|cFFf7d470/MitzuMPlus testnative|r         - Comprueba las 8 rutas de fabrica sin MDT ni SavedVariables")
    self:Print("|cFFf7d470/MitzuMPlus session|r            - Estado de recuperacion de la partida actual")
    self:Print("|cFFf7d470/MitzuMPlus clock|r              - Tiempo real de la llave y desfase del reloj local")
    self:Print("|cFFf7d470/MitzuMPlus guidance|r           - Que decide el motor sobre las placas visibles")
    self:Print("|cFFf7d470/MitzuMPlus guidancedetail|r     - Decision placa por placa")
    self:Print("|cFFf7d470/MitzuMPlus arrowpulltest [n]|r  - Prueba VISUAL del pipeline completo")
    self:Print("|cFFf7d470/MitzuMPlus arrowdemo on/off|r     - DEMO de flechas aproximadas + telemetria")
    self:Print("|cFFf7d470/MitzuMPlus arrowdemo report|r     - Resumen de la ultima run de la demo")
    self:Print("|cFFf7d470/MitzuMPlus arrowdemo export|r     - Copiar la telemetria (caja seleccionable)")
    self:Print("|cFFf7d470/MitzuMPlus align|r               - En que pull cree estar la inferencia (diagnostico)")
    self:Print("|cFFf7d470/MitzuMPlus align candidates|r    - Todos los candidatos y sus puntuaciones")
    self:Print("|cFFf7d470/MitzuMPlus alignmentdetail|r     - Best/runner-up, margen y desglose pasivo")
    self:Print("|cFFf7d470/MitzuMPlus next|r / |cFFf7d470prev|r       - Avanza/retrocede un pull")
    self:Print("|cFFf7d470/MitzuMPlus runtime [todo]|r    - Que puede leer el addon en este cliente")
    self:Print("|cFFf7d470/MitzuMPlus probe [unidad]|r    - SPIKE: todo lo legible de una placa")
    self:Print("|cFFf7d470/MitzuMPlus plates|r             - A que frame se ancla cada flecha")
    self:Print("|cFFf7d470/MitzuMPlus evidence|r           - Engagement y enlaces de cada placa visible")
    self:Print("|cFFf7d470/MitzuMPlus evidence summary|r   - Solo los contadores")
    self:Print("|cFFf7d470/MitzuMPlus castevidence|r       - Que esta casteando cada placa visible")
    self:Print("|cFFf7d470/MitzuMPlus auraevidence|r       - Auras legibles de cada placa visible")
    self:Print("|cFFf7d470/MitzuMPlus eventcast|r          - Casts escuchados por evento (no por sondeo)")
    self:Print("|cFFf7d470/MitzuMPlus packevidence|r       - Cuantos espera el pull vs cuantos pelean")
    self:Print("|cFFf7d470/MitzuMPlus packevidence summary|r - Resumen para copiar antes/durante/despues")
    self:Print("|cFFf7d470/MitzuMPlus probeplates|r        - SPIKE: una linea por placa visible")
    self:Print("|cFFf7d470/MitzuMPlus resolverdump|r       - Resolver por placa (solo estados seguros)")
    self:Print("|cFFf7d470/MitzuMPlus physicalgroups [pull]|r - Grupos fisicos MDT (solo diagnostico)")
    self:Print("|cFFf7d470/MitzuMPlus groupcorrelation|r   - Engaged vs grupos fisicos (diagnostico)")
    self:Print("|cFFf7d470/MitzuMPlus forcemap|r           - SPIKE: colisiones de tropas por pull")
    self:Print("|cFFf7d470/MitzuMPlus resolveplates|r      - SPIKE: flecha solo sobre los MATCH")
    self:Print("|cFFf7d470/MitzuMPlus version|r            - Muestra versión")
    self:Print("|cFFf7d470/MitzuMPlus bugreport|r          - Copia el log de errores al clipboard")
    self:Print("|cFFf7d470/MitzuMPlus clearerrors|r        - Limpia el log de errores")
    self:Print("|cFFf7d470/MitzuMPlus debuglog|r          - Copia el log de diagnóstico al clipboard")
    self:Print("|cFFf7d470/MitzuMPlus cleardebug|r        - Limpia el log de diagnóstico")
    self:Print("|cFFf7d470/MitzuMPlus debugmode|r         - Activa/desactiva modo debug")
    self:Print(" ")
    self:Print("|cFFf7d470/MitzuMPlus pb|r                 - Muestra Personal Bests")
    self:Print("|cFFf7d470/MitzuMPlus rebuild|r            - Reconstruir Personal Bests")
    self:Print(" ")
    self:Print("|cFFf7d470/MitzuMPlus meterinfo|r          - Enumera C_DamageMeter API disponible")
    self:Print("|cFFf7d470/MitzuMPlus meterexplore|r       - Explora C_DamageMeter sessions/sources")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- WINDOW MANAGEMENT
-- ═══════════════════════════════════════════════════════════════════════════

function MitzuMPlus:ToggleWindow()
    if not self.Window or not self._uiBuilt then
        self:InitializeUI()
    end
    if not self.Window then return end

    if self.Window:IsShown() then
        self.Window:Hide()
    else
        self.Window:Show()
        self:EnsureWindowVisible()
        -- Defer Refresh one frame: WoW resuelve GetWidth/GetHeight en el
        -- siguiente ciclo de render tras Show(). Sin el delay, paneles que
        -- dependen del ancho real (SeasonSync cards, Historial sidebar)
        -- pueden recibir 0 y quedar vacíos.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if self.Window and self.Window:IsShown() then
                    self:RefreshActivePanel()
                end
            end)
        else
            self:RefreshActivePanel()
        end
    end
end

function MitzuMPlus:ShowTab(tabName)
    if not self.Window or not self._uiBuilt then
        self:InitializeUI()
    end
    if not self.Window then return end
    self.Window:Show()
    self:EnsureWindowVisible()
    if self.Tabs and self.Tabs.SetActiveTab then
        self.Tabs:SetActiveTab(tabName)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if self.Window and self.Window:IsShown() then
                self:RefreshActivePanel()
            end
        end)
    else
        self:RefreshActivePanel()
    end
end

function MitzuMPlus:RefreshActivePanel()
    if not self.Tabs then return end
    local activeTab = self.Tabs.activeTab or "historial"
    if activeTab == "historial"  and self.PanelHistorial  and self.PanelHistorial.Refresh  then self.PanelHistorial:Refresh()
    elseif activeTab == "stats"  and self.PanelStats      and self.PanelStats.Refresh      then self.PanelStats:Refresh()
    elseif activeTab == "players"  and self.PanelPlayers   and self.PanelPlayers.Refresh   then self.PanelPlayers:Refresh()
    elseif activeTab == "coach"    and self.PanelCoach     and self.PanelCoach.Refresh     then self.PanelCoach:Refresh()
    elseif activeTab == "settings" and self.PanelConfig   and self.PanelConfig.Refresh     then self.PanelConfig:Refresh()
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CORE EVENTS (stub — implemented in modules/Core.lua)
-- ═══════════════════════════════════════════════════════════════════════════

function MitzuMPlus:UnregisterCoreEvents()
    if self._eventFrame then
        pcall(function() self._eventFrame:UnregisterAllEvents() end)
    end
    -- v4.0.0: desregistrar ambas rutas de tracking
    if self.IS_MIDNIGHT then
        pcall(function() self:UnregisterMidnightCombatTracking() end)
    else
    end
    self._eventsRegistered = false
    _G.MitzuMPlusCurrentRun = nil
    if self.Print then
        self:Print("|cFFee3333Tracking de M+ desactivado.|r")
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- COMPATIBILITY BRIDGES
-- Los módulos UI_Historial/Stats/Detalle/Config fueron eliminados del TOC
-- porque duplicaban el sistema UI/Panels/. Sus métodos únicos que otros
-- módulos siguen llamando (StaticPopups, MinimapIcon, Export) se definen aquí.
-- ═══════════════════════════════════════════════════════════════════════════

-- StaticPopups.lua llama RefreshHistorialTable() tras borrar runs.
-- Redirige al nuevo PanelHistorial:Refresh() que Init.lua ya conoce.
function MitzuMPlus:RefreshHistorialTable()
    if self.PanelHistorial and self.PanelHistorial.Refresh then
        self.PanelHistorial:Refresh()
    end
end

-- Export.lua llama MitzuMPlus:FormatDate(ts).
function MitzuMPlus:FormatDate(ts)
    if not ts or ts == 0 then return "--" end
    local ok, d = pcall(date, "*t", ts)
    if not ok or not d then return "--" end
    local meses = { "Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic" }
    return string.format("%02d %s %02d",
        d.day  or 1,
        meses[d.month or 1] or "?",
        (d.year or 2000) % 100)
end

-- MinimapIcon.lua llama MitzuMPlus:ShowConfig().
-- Redirige a la pestaña de configuración del sistema nuevo.
function MitzuMPlus:ShowConfig()
    self:ShowTab("settings")
end

return MitzuMPlus
