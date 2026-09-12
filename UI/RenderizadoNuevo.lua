-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - RenderizadoNuevo.lua
-- Sistema de Renderizado basado en PaseDeBatallaMitzuMPlus (PROBADO Y FUNCIONAL)
-- Maneja: Drag, Resize, Scale, Posición, Guardado en DB
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local Render = {}
MitzuMPlus.Renderizado = Render

-- ─────────────────────────────────────────────────────────────────────────────
-- HELPERS
-- ─────────────────────────────────────────────────────────────────────────────

local function _Clamp(v, minV, maxV)
    if v < minV then return minV end
    if v > maxV then return maxV end
    return v
end

local function _RoundToStep(v, step)
    if step <= 0 then return v end
    return math.floor((v / step) + 0.5) * step
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CONFIGURACIÓN POR DEFECTO
-- ─────────────────────────────────────────────────────────────────────────────

local DEFAULTS = {
    ancho = 1000,
    alto = 600,
    escala = 1.0,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- RESETEAR VENTANA A VALORES PREDETERMINADOS
-- ─────────────────────────────────────────────────────────────────────────────

local function ResetearVentana(frame, claveDB)
    local def = DEFAULTS
    frame:SetSize(def.ancho, def.alto)
    if frame.SetScale then
        frame:SetScale(def.escala)
    end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    local db = MitzuMPlus.db
    if db and db.profile and db.profile.settings then
        db.profile.settings.windowWidth = def.ancho
        db.profile.settings.windowHeight = def.alto
        db.profile.settings.windowScale = def.escala
        db.profile.position = nil
    end

    if MitzuMPlus.Print then
        MitzuMPlus:Print("|cFF21de66Ventana reseteada a valores por defecto.|r")
    end
end

Render.ResetearVentana = ResetearVentana

-- ─────────────────────────────────────────────────────────────────────────────
-- CONFIGURAR RESIZE, DRAG, SCALE
-- ─────────────────────────────────────────────────────────────────────────────

function Render:ConfigurarResize(frame, minW, minH, maxW, maxH)
    minW = minW or 520
    minH = minH or 380
    maxW = maxW or 1600
    maxH = maxH or 1200

    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minW, minH, maxW, maxH)
    else
        if frame.SetMinResize then frame:SetMinResize(minW, minH) end
        if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
    end

    -- ✅ Crear el resize handle
    local resizeHandle = CreateFrame("Button", nil, frame)
    resizeHandle:SetSize(20, 20)
    resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    resizeHandle:SetFrameLevel(frame:GetFrameLevel() + 100)
    if resizeHandle.RegisterForClicks then
        resizeHandle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end

    -- ✅ Crear líneas del grip (visual)
    local gripLines = {}
    local lineData = {
        { w = 12, xOff = -1, yOff = 1 },
        { w = 8, xOff = -1, yOff = 5 },
        { w = 4, xOff = -1, yOff = 9 },
    }
    for _, ld in ipairs(lineData) do
        local ln = resizeHandle:CreateTexture(nil, "OVERLAY")
        ln:SetSize(ld.w, 2)
        ln:SetPoint("BOTTOMRIGHT", resizeHandle, "BOTTOMRIGHT", ld.xOff, ld.yOff)
        ln:SetColorTexture(0.78, 0.66, 0.29, 0.85)
        table.insert(gripLines, ln)
    end

    -- ✅ OnEnter: mostrar tooltip + highlight
    resizeHandle:SetScript("OnEnter", function(self)
        if not (GameTooltip and GameTooltip.SetOwner) then return end
        for _, ln in ipairs(gripLines) do
            ln:SetColorTexture(1, 0.9, 0.5, 1)
        end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Click and drag to resize this window.", 1, 1, 1)
        GameTooltip:AddLine("Hold SHIFT while dragging to scale the window instead.", 1, 1, 1)
        GameTooltip:AddLine("Right-Click to reset the window size, scale, and position to their defaults.", 1, 1, 1)
        GameTooltip:Show()
    end)

    -- ✅ OnLeave: restablecer color
    resizeHandle:SetScript("OnLeave", function()
        for _, ln in ipairs(gripLines) do
            ln:SetColorTexture(0.78, 0.66, 0.29, 0.85)
        end
        if GameTooltip and GameTooltip.Hide then
            GameTooltip:Hide()
        end
    end)

    -- ✅ Manejo de scaling con SHIFT
    local scaling = false
    local startX, startY, startScale

    local function _StopScaling()
        scaling = false
        resizeHandle:SetScript("OnUpdate", nil)
    end

    -- ✅ OnMouseDown: iniciar resize o scale
    resizeHandle:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        for _, ln in ipairs(gripLines) do
            ln:SetColorTexture(1, 0.5, 0.1, 1)
        end
        if IsShiftKeyDown and IsShiftKeyDown() then
            -- ✅ SCALE CON SHIFT
            scaling = true
            startScale = frame.GetScale and frame:GetScale() or 1.0
            startX, startY = GetCursorPosition()
            resizeHandle:SetScript("OnUpdate", function()
                if not scaling then return end
                if not (GetCursorPosition and frame.GetEffectiveScale and frame.SetScale) then return end
                local x, y = GetCursorPosition()
                local dx = (x - (startX or x)) / (frame:GetEffectiveScale() or 1)
                local s = (startScale or 1.0) + (dx / 600)
                s = _Clamp(s, 0.5, 2.0)
                s = _RoundToStep(s, 0.05)
                frame:SetScale(s)
            end)
        else
            -- ✅ RESIZE NORMAL (BOTTOMRIGHT)
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)

    -- ✅ OnMouseUp: terminar resize/scale + guardar
    resizeHandle:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            _StopScaling()
            frame:StopMovingOrSizing()

            local w = frame:GetWidth()
            local h = frame:GetHeight()
            w = math.max(minW, math.min(maxW, w))
            h = math.max(minH, math.min(maxH, h))
            frame:SetSize(w, h)

            for _, ln in ipairs(gripLines) do
                ln:SetColorTexture(0.78, 0.66, 0.29, 0.85)
            end

            -- ✅ Guardar en DB
            if MitzuMPlus.db and MitzuMPlus.db.profile and MitzuMPlus.db.profile.settings then
                MitzuMPlus.db.profile.settings.windowWidth = w
                MitzuMPlus.db.profile.settings.windowHeight = h
                MitzuMPlus.db.profile.settings.windowScale = frame.GetScale and frame:GetScale() or 1.0
            end
        elseif button == "RightButton" then
            -- ✅ RIGHT-CLICK PARA RESETEAR
            ResetearVentana(frame)
        end
    end)

    -- ✅ OnSizeChanged: validar límites
    local prevOnSizeChanged = frame:GetScript("OnSizeChanged")
    frame:SetScript("OnSizeChanged", function(self, w, h)
        if prevOnSizeChanged then
            pcall(prevOnSizeChanged, self, w, h)
        end
        local cw = math.max(minW, math.min(maxW, w))
        local ch = math.max(minH, math.min(maxH, h))
        if cw ~= w or ch ~= h then
            self:SetSize(cw, ch)
        end
    end)

    return resizeHandle
end

-- ─────────────────────────────────────────────────────────────────────────────
-- DRAG HANDLING (SIMPLE Y DIRECTO)
-- ─────────────────────────────────────────────────────────────────────────────

function Render:AttachDragHandlers(frame)
    if not frame or frame._dragAttached then return end
    frame._dragAttached = true

    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    -- ✅ OnDragStart
    frame:SetScript("OnDragStart", function()
        local settings = MitzuMPlus.db and MitzuMPlus.db.profile and MitzuMPlus.db.profile.settings
        if settings and settings.windowLocked then return end
        frame:StartMoving()
    end)

    -- ✅ OnDragStop: guardar posición
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        
        -- Guardar posición en DB
        if MitzuMPlus.db and MitzuMPlus.db.profile then
            local left = frame:GetLeft()
            local top = frame:GetTop()
            if left and top then
                MitzuMPlus.db.profile.position = {
                    point = "TOPLEFT",
                    relativePoint = "BOTTOMLEFT",
                    x = left,
                    y = top,
                }
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- RESTAURAR SOLO POSICIÓN (sin tocar el tamaño — ventana fija)
-- ─────────────────────────────────────────────────────────────────────────────

function Render:RestoreOnlyPosition(frame)
    if not frame then return end

    local db = MitzuMPlus.db and MitzuMPlus.db.profile
    if not db then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end

    -- ✅ Escala siempre 1.0 — ventana de tamaño fijo no escala
    frame:SetScale(1.0)

    -- ✅ Restaurar posición si fue guardada previamente
    frame:ClearAllPoints()
    local pos = db.position
    if pos and pos.x and pos.y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- RESTAURAR POSICIÓN Y TAMAÑO DESDE DB (legacy — no usado con ventana fija)
-- ─────────────────────────────────────────────────────────────────────────────

function Render:RestorePositionAndSize(frame)
    if not frame then return end

    local db = MitzuMPlus.db and MitzuMPlus.db.profile
    if not db then return end

    -- ✅ Restaurar tamaño
    local w = db.settings and db.settings.windowWidth
    local h = db.settings and db.settings.windowHeight
    if type(w) == "number" and type(h) == "number" and w > 100 and h > 100 then
        frame:SetSize(w, h)
    else
        frame:SetSize(DEFAULTS.ancho, DEFAULTS.alto)
    end

    -- ✅ Restaurar escala
    local scale = db.settings and db.settings.windowScale
    if type(scale) == "number" then
        scale = _Clamp(scale, 0.5, 2.0)
        frame:SetScale(scale)
    else
        frame:SetScale(DEFAULTS.escala)
    end

    -- ✅ Restaurar posición
    frame:ClearAllPoints()
    local pos = db.position
    if pos and pos.x and pos.y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ASEGURAR QUE LA VENTANA SEA VISIBLE
-- ─────────────────────────────────────────────────────────────────────────────

function Render:EnsureVisible(frame)
    if not frame or not frame.GetLeft then return end

    local left = frame:GetLeft()
    local right = frame:GetRight()
    local top = frame:GetTop()
    local bottom = frame:GetBottom()

    if not left or not right or not top or not bottom then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end

    local screenW, screenH = UIParent:GetSize()
    local minOnScreen = 50

    -- Completamente fuera de pantalla
    if right < 0 or left > screenW or bottom < 0 or top > screenH then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end

    local width = right - left
    local height = top - bottom
    local centerX, centerY = frame:GetCenter()

    if not centerX or not centerY then return end

    -- Clamp al center
    local minX = minOnScreen + width / 2
    local maxX = screenW - minOnScreen - width / 2
    local minY = minOnScreen + height / 2
    local maxY = screenH - minOnScreen - height / 2

    local newCX = _Clamp(centerX, minX, maxX)
    local newCY = _Clamp(centerY, minY, maxY)

    if newCX ~= centerX or newCY ~= centerY then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", newCX, newCY)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- INICIALIZAR VENTANA (LLAMAR EN CreateMainWindow)
-- ─────────────────────────────────────────────────────────────────────────────

function Render:InitializeWindow(frame)
    if not frame then return end

    -- ✅ Solo drag — resize y scale desactivados (ventana tamaño fijo)
    self:AttachDragHandlers(frame)

    -- ✅ NO llamar ConfigurarResize — ventana es de tamaño fijo.
    --    SetResizable en false garantiza que el engine no permita resize.
    if frame.SetResizable then
        frame:SetResizable(false)
    end

    -- ✅ Restaurar SOLO la posición guardada, no el tamaño.
    --    El tamaño lo fija Theme.LAYOUT y no se sobreescribe.
    self:RestoreOnlyPosition(frame)

    -- ✅ Asegurar que sea visible en pantalla
    self:EnsureVisible(frame)
end

return Render
