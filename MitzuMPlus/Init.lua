-- ===========================================================================
-- MitzuMPlus M+ Historial - Init.lua
-- Initialization & Entry Point
-- Corrected by: Bug audit v2.1.2
-- ===========================================================================

local ADDON_NAME = "MitzuMPlus"
-- FIX BUG-6: eliminada la versión hardcodeada "2.1.5". La única fuente de verdad
-- es MitzuMPlus.VERSION, que Bootstrap.lua lee dinámicamente del .toc.
-- Se mantiene el local solo como alias de emergencia usando el valor real.
local ADDON_VERSION_FALLBACK = "5.0.0"

-- FIX RUNTIME-1: Bootstrap.lua llama NewAddon() antes que este archivo.
-- Aquí solo recuperamos la referencia con GetAddon(); llamar NewAddon() de
-- nuevo causaría un error "addon already registered".
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
-- _G[ADDON_NAME] y _G.MitzuMPlus ya fueron asignados en Bootstrap.lua.

-- ===========================================================================
-- DATABASE INITIALIZATION
-- ===========================================================================

function MitzuMPlus:OnInitialize()
    -- BUG-FIX-8: MitzuMPlusDB_Defaults viene de MitzuMPlus_main.lua
    -- (carga antes que Init.lua en el TOC). Si no llegó, AceDB recibiría nil
    -- y la DB no tendría defaults. Lo detectamos y fallamos con un mensaje claro.
    if not MitzuMPlusDB_Defaults then
        error("[MitzuMPlus] FATAL: MitzuMPlusDB_Defaults no definido. " ..
              "Verifica que MitzuMPlus_main.lua carga antes que Init.lua en el TOC.")
    end

    self.db = LibStub("AceDB-3.0"):New("MitzuMPlusDB", MitzuMPlusDB_Defaults, true)

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

    self:Print("|cFFD4A43CMitzuMPlus|r v" .. (self.VERSION or ADDON_VERSION_FALLBACK) .. " cargado. /MitzuMPlus para abrir.")

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
    -- Caja negra de QA: conectada a la DB ya existente. Primer hecho anotado.
    if self.FlightRecorder then
        pcall(function()
            self.FlightRecorder:Attach()
            self.FlightRecorder:Record("ADDON", "INITIALIZED", { version = self.VERSION })
        end)
    end
    if self.InitMinimapIcon then
        self:InitMinimapIcon()
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
    -- El handler se registra una sola vez, pero consulta la configuración en
    -- cada pulsación. Así el toggle "Cerrar con Escape" funciona al instante
    -- tanto al activarlo como al desactivarlo, sin requerir /reload.
    if self.UpdateEscapeHandling then self:UpdateEscapeHandling() end
end

function MitzuMPlus:UpdateEscapeHandling()
    local settings = self.db and self.db.profile and self.db.profile.settings
    local enabled = not settings or settings.closeWithEscape ~= false

    if RegisterEscapeHandler then
        if not self._escapeRegistered then
            RegisterEscapeHandler(function()
                local st = MitzuMPlus.db and MitzuMPlus.db.profile and MitzuMPlus.db.profile.settings
                local on = not st or st.closeWithEscape ~= false
                if on and MitzuMPlus.Window and MitzuMPlus.Window:IsShown() then
                    MitzuMPlus.Window:Hide()
                    return true
                end
                return false
            end)
            self._escapeRegistered = true
        end
        return
    end

    -- Fallback para clientes antiguos: UISpecialFrames sí necesita insertar o
    -- retirar el nombre del frame según el estado actual del toggle.
    if UISpecialFrames then
        local name = "MitzuMPlusMainWindow"
        local found
        for i = #UISpecialFrames, 1, -1 do
            if UISpecialFrames[i] == name then
                found = true
                if not enabled then table.remove(UISpecialFrames, i) end
            end
        end
        if enabled and not found then table.insert(UISpecialFrames, name) end
    end
end

function MitzuMPlus:OnDisable()
    -- Cleanup when addon is disabled
end

-- ===========================================================================
-- DEFAULT PROFILE
-- BUG-M7 FIX: GetDefaultProfile() eliminado - era código muerto desincronizado.
-- La única fuente de verdad es MitzuMPlusDB_Defaults (definido en MitzuMPlus_main.lua).
-- ===========================================================================

-- ===========================================================================
-- UI INITIALIZATION
-- ===========================================================================

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

    -- BUG-FIX-6b: mismo patrón - error() + return era código muerto.
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

        -- Ocultar de nuevo si no estaba visible - ToggleWindow la mostrará
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
            windowWidth    = C.UI_HISTORIAL_DEFAULT_WIDTH  or 1280,
            windowHeight   = C.UI_HISTORIAL_DEFAULT_HEIGHT or 760,
            titlebarHeight = C.TITLEBAR_HEIGHT or 64,
            footerHeight   = C.FOOTER_HEIGHT or 36,
        }
    end

    local frame = CreateFrame("Frame", "MitzuMPlusMainWindow", UIParent,
        BackdropTemplateMixin and "BackdropTemplate")

    frame:SetSize(Theme.LAYOUT.windowWidth, Theme.LAYOUT.windowHeight)
    frame:SetScale(1.0)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:Hide()

    frame:SetBackdrop(Theme.BACKDROPS.window)
    Theme:SetBackdropColor(frame, Theme.BG.window)
    Theme:SetBackdropBorderColor(frame, Theme.BORDER.window)

    local mainContainer = CreateFrame("Frame", nil, frame)
    mainContainer:SetAllPoints(frame)
    mainContainer:Show()

    -- -- OnShow --------------------------------------------------------------
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

    -- -- OnHide ---------------------------------------------------------------
    frame:SetScript("OnHide", function()
        if frame._showAnim then
            frame._showAnim:Stop()
            -- BUG-M8 FIX: NO asignar nil - preservar grupo de animación para reusar.
        end
    end)

    -- -- Titlebar -------------------------------------------------------------
    local titlebar = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate")
    titlebar:SetHeight(Theme.LAYOUT.titlebarHeight or 64)
    titlebar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    titlebar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    titlebar:SetBackdrop(Theme.BACKDROPS.titlebar)
    Theme:SetBackdropColor(titlebar, Theme.BG.titlebar)
    Theme:SetBackdropBorderColor(titlebar, Theme.BORDER.titlebar)

    -- Logo 28x28 (textura 64x64), centrado con el bloque titulo+subtitulo.
    local addonIcon = titlebar:CreateTexture(nil, "OVERLAY")
    addonIcon:SetSize(28, 28)
    addonIcon:SetPoint("LEFT", titlebar, "LEFT", 14, 2)
    addonIcon:SetTexture("Interface\\AddOns\\MitzuMPlus\\Media\\Icons\\mitzu_logo_header_64")

    local titleText = titlebar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Theme:ApplyFont(titleText,"title",17)
    titleText:SetPoint("TOPLEFT", titlebar, "TOPLEFT", 48, -10)
    titleText:SetText("MitzuMPlus")
    titleText:SetTextColor(Theme.GOLD.gold4.r, Theme.GOLD.gold4.g, Theme.GOLD.gold4.b, Theme.GOLD.gold4.a)

    local subtitleText = titlebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Theme:ApplyFont(subtitleText,"normal",12)
    subtitleText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
    subtitleText:SetPoint("RIGHT", titlebar, "RIGHT", -245, 0)
    subtitleText:SetJustifyH("LEFT")
    subtitleText:SetWordWrap(false)
    subtitleText:SetText("Mythic+ History & Key Prediction")
    subtitleText:SetTextColor(Theme.TEXT.secondary.r, Theme.TEXT.secondary.g, Theme.TEXT.secondary.b, Theme.TEXT.secondary.a)

    -- Settings button (punto asignado DESPUÉS de definir closeBtn)
    -- Area de click 24x24. El icono ya trae su propio marco, asi que el
    -- backdrop queda transparente en reposo y solo se pinta en hover.
    local CONTROL_REST = { r = 0, g = 0, b = 0, a = 0 }
    local settingsBtn = CreateFrame("Button", nil, titlebar, BackdropTemplateMixin and "BackdropTemplate")
    settingsBtn:SetSize(24, 24)
    settingsBtn:SetBackdrop(Theme.BACKDROPS.button)
    Theme:SetBackdropColor(settingsBtn, CONTROL_REST)
    Theme:SetBackdropBorderColor(settingsBtn, CONTROL_REST)

    local settingsIcon = settingsBtn:CreateTexture(nil, "OVERLAY")
    settingsIcon:SetSize(21, 21)
    settingsIcon:SetPoint("CENTER", settingsBtn, "CENTER", 0, 0)
    settingsIcon:SetTexture("Interface\\AddOns\\MitzuMPlus\\Media\\Icons\\btn_options_64")

    settingsBtn:SetScript("OnEnter", function()
        Theme:SetBackdropColor(settingsBtn, Theme.BG.btnSecHover)
        Theme:SetBackdropBorderColor(settingsBtn, Theme.BORDER.btnSecHover)
    end)
    settingsBtn:SetScript("OnLeave", function()
        Theme:SetBackdropColor(settingsBtn, CONTROL_REST)
        Theme:SetBackdropBorderColor(settingsBtn, CONTROL_REST)
    end)
    settingsBtn:SetScript("OnClick", function()
        if MitzuMPlus.ShowTab then MitzuMPlus:ShowTab("settings") end
    end)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titlebar, BackdropTemplateMixin and "BackdropTemplate")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("RIGHT", titlebar, "RIGHT", -10, 0)
    -- Cadena de anclaje: settingsBtn -> LEFT de closeBtn
    settingsBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)

    -- Version text - BUG-FIX-7: siempre leer MitzuMPlus.VERSION
    local versionText = titlebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Theme:ApplyFont(versionText,"mono",11)
    versionText:SetPoint("RIGHT", settingsBtn, "LEFT", -10, 0)
    versionText:SetText("v" .. (MitzuMPlus.VERSION or ADDON_VERSION_FALLBACK))
    versionText:SetTextColor(Theme.TEXT.dim.r, Theme.TEXT.dim.g, Theme.TEXT.dim.b, Theme.TEXT.dim.a)

    closeBtn:SetBackdrop(Theme.BACKDROPS.button)
    Theme:SetBackdropColor(closeBtn, CONTROL_REST)
    Theme:SetBackdropBorderColor(closeBtn, CONTROL_REST)

    local closeIcon = closeBtn:CreateTexture(nil, "OVERLAY")
    closeIcon:SetSize(21, 21)
    closeIcon:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeIcon:SetTexture("Interface\\AddOns\\MitzuMPlus\\Media\\Icons\\btn_close_64")

    closeBtn:SetScript("OnEnter", function()
        Theme:SetBackdropColor(closeBtn, Theme.BG.btnCloseHover)
        Theme:SetBackdropBorderColor(closeBtn, Theme.BORDER.btnCloseHover)
    end)
    closeBtn:SetScript("OnLeave", function()
        Theme:SetBackdropColor(closeBtn, CONTROL_REST)
        Theme:SetBackdropBorderColor(closeBtn, CONTROL_REST)
    end)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- -- Footer container (creado ANTES que body para que body pueda anclarse) --
    local footerHeight = Theme.LAYOUT.footerHeight or 36
    local footerContainer = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate")
    footerContainer:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  0, 0)
    footerContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    footerContainer:SetHeight(footerHeight)

    -- -- Body container -------------------------------------------------------
    local body = CreateFrame("Frame", nil, frame)
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT",     titlebar,        "BOTTOMLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", footerContainer, "TOPRIGHT",   0, 0)

    -- contentArea = nil -> Tabs:Create() lo asignará
    frame.body            = body
    frame.footerContainer = footerContainer
    frame.contentArea     = nil
    frame.titlebar        = titlebar
    frame.titleText       = titleText
    frame.subtitleText    = subtitleText
    frame.versionText     = versionText

    if self.Renderizado then
        self.Renderizado:InitializeWindow(frame)
    end

    self.Window = frame
    return frame
end

-- ===========================================================================
-- WINDOW HELPERS
-- ===========================================================================

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

-- ===========================================================================
-- SLASH COMMANDS
-- ===========================================================================


function MitzuMPlus:HandleSlashCommand(input)
    local raw = tostring(input or ""):match("^%s*(.-)%s*$")
    local args = {}
    for token in raw:gmatch("%S+") do args[#args + 1] = token:lower() end
    local cmd = args[1] or ""

    if cmd == "" or cmd == "toggle" then
        self:ToggleWindow()
        return
    end
    if cmd == "help" or cmd == "ayuda" then
        self:PrintHelp()
        return
    end
    if cmd == "open" or cmd == "abrir" then
        if not (self.Window and self.Window:IsShown()) then self:ToggleWindow() end
        return
    end
    if cmd == "close" or cmd == "hide" or cmd == "cerrar" then
        if self.Window then self.Window:Hide() end
        return
    end
    if cmd == "history" or cmd == "historial" then self:ShowTab("historial"); return end
    if cmd == "stats" or cmd == "estadisticas" then self:ShowTab("stats"); return end
    if cmd == "players" or cmd == "jugadores" then self:ShowTab("players"); return end
    if cmd == "settings" or cmd == "config" or cmd == "configuracion" then
        self:ShowTab("settings")
        return
    end

    if cmd == "tracker" or cmd == "hud" then
        local HUD = self.KeyPredictionHUD
        if not HUD then
            self:Print("|cFFff5555Tracker de predicción no disponible.|r")
            return
        end
        local sub, value = args[2], args[3]
        if sub == "on" then
            HUD:SetEnabled(true)
        elseif sub == "off" then
            HUD:SetEnabled(false)
        elseif sub == "preview" or sub == "test" then
            HUD:SetPreview(value ~= "off")
        elseif sub == "lock" or sub == "unlock" then
            HUD:SetOption("locked", sub == "lock")
        elseif sub == "scale" or sub == "alpha" then
            local ok = HUD:SetOption(sub, tonumber(value))
            if not ok then self:Print("|cFFff9922Valor inválido para " .. sub .. ".|r") end
        elseif sub == "reset" then
            HUD:ResetPosition()
        elseif sub == "status" then
            for _, line in ipairs(HUD:StatusLines()) do self:Print(line) end
        elseif sub == nil or sub == "toggle" then
            HUD:SetEnabled(not HUD:IsEnabled())
        else
            self:Print("|cFFff9922Uso: /emp tracker on|off|preview [off]|lock|unlock|scale N|alpha N|reset|status|r")
            return
        end
        if sub ~= "status" then
            self:Print("Tracker M+: " .. (HUD:IsEnabled() and "|cFF21de66activado|r" or "|cFFff5555desactivado|r"))
        end
        return
    end

    if cmd == "testnotifs" or cmd == "testavisos" then
        local states = {
            complete = (not self.NotifyEnabled) or self:NotifyEnabled("notifyOnComplete"),
            record = (not self.NotifyEnabled) or self:NotifyEnabled("notifyNewRecord"),
            personal = (not self.NotifyEnabled) or self:NotifyEnabled("notifyPersonalBest"),
            chat = self.db and self.db.profile and self.db.profile.chatOutput == true,
        }
        if states.complete and self.ShowToast then
            self:ShowToast("Prueba: run completada", "ok", 2, true)
        end
        if states.record and self.ShowToast then
            self:ShowToast("Prueba: nuevo record", "record", 2, true)
        end
        if states.personal and self.ShowToast then
            self:ShowToast("Prueba: marca personal", "personal", 2, true)
        end
        if states.chat and self.Print then
            self:Print("Prueba de resumen en chat: OK")
        end
        self:Print(string.format(
            "Avisos: completar=%s record=%s personal=%s chat=%s",
            states.complete and "ON" or "OFF", states.record and "ON" or "OFF",
            states.personal and "ON" or "OFF", states.chat and "ON" or "OFF"))
        return
    end

    if cmd == "bugreport" then
        local BR = self.BugReport
        if not BR then
            self:Print("|cFFff5555Bug Report no disponible.|r")
            return
        end
        if args[2] == "clear" then
            pcall(BR.ClearLogs, BR)
            self:Print("|cFF21de66Bug Report: logs locales limpiados.|r")
        elseif args[2] == "status" then
            local ok, lines = pcall(BR.SummaryLines, BR)
            for _, line in ipairs(ok and lines or { "resumen no disponible" }) do self:Print(line) end
        else
            local ok = pcall(BR.Show, BR)
            if not ok then self:Print("|cFFff5555No se pudo abrir el Bug Report.|r") end
        end
        return
    end

    if cmd == "version" or cmd == "v" then
        self:Print("MitzuMPlus |cFFe8b84av" .. tostring(self.VERSION or ADDON_VERSION_FALLBACK) .. "|r")
        return
    end

    self:Print("|cFFff9922Comando desconocido.|r Usa |cFFf7d470/emp help|r.")
end

function MitzuMPlus:PrintHelp()
    self:Print("|cFFe8b84aMitzuMPlus|r - Historial y predicción de llave")
    self:Print("|cFFf7d470/emp|r - abrir o cerrar MitzuMPlus")
    self:Print("|cFFf7d470/emp historial|r  -  |cFFf7d470stats|r  -  |cFFf7d470jugadores|r  -  |cFFf7d470config|r")
    self:Print("|cFFf7d470/emp tracker on|off|preview [off]|lock|unlock|scale N|alpha N|reset|status|r")
    self:Print("|cFFf7d470/emp bugreport [status|clear]|r - diagnóstico sanitizado")
    self:Print("|cFFf7d470/emp testavisos|r - probar las notificaciones configuradas")
    self:Print("|cFFf7d470/emp version|r")
end

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
    elseif activeTab == "settings" and self.PanelConfig   and self.PanelConfig.Refresh     then self.PanelConfig:Refresh()
    end
end

-- ===========================================================================
-- CORE EVENTS (stub - implemented in modules/Core.lua)
-- ===========================================================================

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

-- ===========================================================================
-- COMPATIBILITY BRIDGES
-- Los módulos UI_Historial/Stats/Detalle/Config fueron eliminados del TOC
-- porque duplicaban el sistema UI/Panels/. Sus métodos únicos que otros
-- módulos siguen llamando (StaticPopups, MinimapIcon, Export) se definen aquí.
-- ===========================================================================

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
