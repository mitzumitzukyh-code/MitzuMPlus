-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuRouteArrows · Core/CopyBox
--
-- Caja de texto seleccionable para copiar la telemetría (/mra arrowdemo
-- export). Antes se usaba la ventana de exportación de MitzuMPlus; este addon
-- no depende de la interfaz del core, así que tiene la suya, mínima.
-- ═══════════════════════════════════════════════════════════════════════════

local MRA = _G.MitzuRouteArrows
if not MRA then return end

local CopyBox = {}
MRA.CopyBox = CopyBox

local function crear()
    local f = CreateFrame("Frame", "MitzuRouteArrowsCopyBox", UIParent,
                          BackdropTemplateMixin and "BackdropTemplate")
    f:SetSize(700, 500)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0.039, 0.039, 0.047, 0.95)
        f:SetBackdropBorderColor(0.8, 0.4, 0.0, 1)
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("MitzuRouteArrows · EXPERIMENTAL · exportar")

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", 0, -28)
    hint:SetText("Ctrl+A para seleccionar todo, luego Ctrl+C para copiar.")

    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -46)
    sf:SetPoint("BOTTOMRIGHT", -28, 36)

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetWidth(640)
    eb:SetAutoFocus(true)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)
    f.editBox = eb

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(100, 22)
    close:SetPoint("BOTTOM", 0, 8)
    close:SetText("Cerrar")
    close:SetScript("OnClick", function() f:Hide() end)

    f:Hide()
    return f
end

function CopyBox:Show(texto)
    if type(texto) ~= "string" or texto == "" then return false end
    if type(CreateFrame) ~= "function" then return false end
    if not self._frame then
        local ok, f = pcall(crear)
        if not ok then return false end
        self._frame = f
    end
    self._frame.editBox:SetText(texto)
    self._frame:Show()
    self._frame.editBox:HighlightText()
    self._frame.editBox:SetFocus()
    return true
end

return CopyBox
