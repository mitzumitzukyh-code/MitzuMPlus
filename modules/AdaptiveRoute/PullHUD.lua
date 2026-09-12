-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · PullHUD v1.0
--
-- "PULL 4 / 21" y nada más.
--
-- Vive aparte de PullNavigator porque el navegador es estado y esto es pintura:
-- mezclarlos obligaría a cargar el frame para poder consultar el número, que
-- es justo lo que hace intestable un módulo.
--
-- Se suscribe con PullNavigator:OnChange. No pregunta en un OnUpdate.
--
-- TAINT: frame propio colgado de UIParent, movible por el jugador. No se mueve
-- ni se crea nada en combate: el frame se crea al mostrarlo por primera vez y
-- la posición la arrastra el jugador, que es una acción suya, no del addon.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local PullHUD = {}
AR.PullHUD = PullHUD

local FONT = "Fonts\\FRIZQT__.TTF"

local function settings()
    local PM = AR.ProfileManager
    return PM and PM.Settings and PM:Settings() or nil
end

function PullHUD:_Build()
    if self._frame then return self._frame end

    local f = CreateFrame("Frame", "MitzuMPlusPullHUD", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(150, 40)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)

    -- La posición guardada se aplica si existe; si no, centro-arriba, que es
    -- donde no tapa ni la barra de acción ni las placas.
    local st = settings()
    if st and st.pullHudPoint then
        f:SetPoint(st.pullHudPoint, UIParent, st.pullHudPoint,
            tonumber(st.pullHudX) or 0, tonumber(st.pullHudY) or 0)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -200)
    end

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0, 0, 0, 0.45)
    f.bg = bg

    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetFont(FONT, 18, "OUTLINE")   -- la fuente ANTES del primer SetText
    text:SetPoint("CENTER", f, "CENTER", 0, 0)
    text:SetTextColor(0.96, 0.83, 0.44, 1)
    text:SetText("PULL - / -")
    f.text = text

    f:SetScript("OnDragStart", function(self_) self_:StartMoving() end)
    f:SetScript("OnDragStop", function(self_)
        self_:StopMovingOrSizing()
        local point, _, _, x, y = self_:GetPoint()
        local s = settings()
        if s then
            s.pullHudPoint = point
            s.pullHudX = x
            s.pullHudY = y
        end
    end)

    f:Hide()
    self._frame = f
    return f
end

function PullHUD:Update(current, total)
    local f = self._frame
    if not f then return end
    local PN = AR.PullNavigator
    current = current or (PN and PN:GetCurrentPull()) or 1
    total   = total   or (PN and PN:GetPullCount())   or 0
    f.text:SetText(string.format("PULL %d / %s", current,
        total > 0 and tostring(total) or "?"))
end

function PullHUD:Show()
    local f = self:_Build()
    self:Update()
    f:Show()
    local st = settings()
    if st then st.pullHudShown = true end
    return true
end

function PullHUD:Hide()
    if self._frame then self._frame:Hide() end
    local st = settings()
    if st then st.pullHudShown = false end
    return true
end

function PullHUD:IsShown()
    return self._frame ~= nil and self._frame:IsShown()
end

function PullHUD:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
    return self:IsShown()
end

function PullHUD:ResetPosition()
    local st = settings()
    if st then
        st.pullHudPoint, st.pullHudX, st.pullHudY = nil, nil, nil
    end
    if self._frame then
        self._frame:ClearAllPoints()
        self._frame:SetPoint("TOP", UIParent, "TOP", 0, -200)
    end
    return true
end

-- El HUD se entera por suscripción, no preguntando. PullNavigator ya existe
-- cuando este fichero carga porque el .toc lo pone antes.
if AR.PullNavigator then
    AR.PullNavigator:OnChange(function(current, total)
        PullHUD:Update(current, total)
    end)
end

return PullHUD
