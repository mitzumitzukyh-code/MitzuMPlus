-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Panel Historial
-- Panel principal con sidebar + filtros + tabla + paginación (mockup completo)
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local Theme = MitzuMPlus.Theme
local Widgets = MitzuMPlus.Widgets
-- BUG-L6 FIX: NO capturar Formatters al cargar el módulo (puede ser nil en ese momento).
-- Usar MitzuMPlus.Formatters inline en cada función que lo necesite.
local Formatters  -- referencia local actualizada en tiempo de uso (ver helpers abajo)

-- ── Rutas de iconos personalizados ──────────────────────────────────────────
local MEDIA = "Interface\\AddOns\\MitzuMPlus_Historial\\Media\\Icons\\"

-- Mapa rol → textura spec icon
local SPEC_ICON = {
    TANK    = MEDIA .. "7a_spec_tank",
    HEALER  = MEDIA .. "7b_spec_heal",
    DAMAGER = MEDIA .. "7c_spec_dps1",
    DAMAGER2 = MEDIA .. "7d_spec_dps2",
    DAMAGER3 = MEDIA .. "7e_spec_dps3",
}

local RECORD_ICON = MEDIA .. "8_record"
local COL_DPS_ICON  = MEDIA .. "6a_col_dps"
local COL_TANK_ICON = MEDIA .. "6b_col_tank"
local COL_HEAL_ICON = MEDIA .. "6c_col_heal"

-- Iconos de rol oficiales del cliente. SetAtlas es la vía preferida; el
-- recorte de UI-LFG-ICON-PORTRAITROLES mantiene compatibilidad con clientes
-- donde alguno de los atlas cambie de nombre.
local ROLE_ATLAS = {
    TANK    = "groupfinder-icon-role-large-tank",
    HEALER  = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps",
}
local ROLE_TEXCOORD = {
    TANK    = { 0/64, 19/64, 22/64, 41/64 },
    HEALER  = { 20/64, 39/64, 1/64, 20/64 },
    DAMAGER = { 20/64, 39/64, 22/64, 41/64 },
}
local ROLE_LABEL = { TANK = "Tanque", HEALER = "Sanador", DAMAGER = "DPS" }

local function SetNativeRoleIcon(texture, role)
    role = (role == "TANK" or role == "HEALER") and role or "DAMAGER"
    local atlasOK = texture.SetAtlas and pcall(texture.SetAtlas, texture, ROLE_ATLAS[role], false)
    if not atlasOK then
        local c=ROLE_TEXCOORD[role]
        texture:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        texture:SetTexCoord(c[1],c[2],c[3],c[4])
    end
end

local function IsMidnightRun(run)
    if not MitzuMPlus.RunMetrics then return false end
    local key,label=MitzuMPlus.RunMetrics:GetSeason(run)
    key=tostring(key or ""):lower();label=tostring(label or ""):lower()
    return key:match("^exp11_s%d+")~=nil
        or key:find("midnight",1,true)~=nil
        or label:find("midnight",1,true)~=nil
end

local PanelHistorial = {}
MitzuMPlus.PanelHistorial = PanelHistorial

-- BUG-L6 FIX: función helper para acceder a Formatters de forma segura en tiempo de ejecución
local function F()
    Formatters = Formatters or MitzuMPlus.Formatters
    return Formatters
end

PanelHistorial.currentPage = 1
PanelHistorial.runsPerPage = 20
PanelHistorial.filteredRuns = {}
PanelHistorial.selectedRunIndex = nil
PanelHistorial.sortColumn = "date"
PanelHistorial.sortDescending = true

-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE PANEL
-- ═══════════════════════════════════════════════════════════════════════════

function PanelHistorial:Create(parent)
    local container
    if MitzuMPlus.Tabs and MitzuMPlus.Tabs.CreatePanelContainer then
        container = MitzuMPlus.Tabs:CreatePanelContainer(parent)
    else
        container = CreateFrame("Frame", nil, parent)
        container:SetAllPoints(parent)
    end

    self:CreateContentArea(container)

    self.panel = container

    if MitzuMPlus.Tabs then
        MitzuMPlus.Tabs:RegisterPanel("historial", container)
    end

    return container
end



-- ═══════════════════════════════════════════════════════════════════════════
-- SIDEBAR (210px left panel)
-- ═══════════════════════════════════════════════════════════════════════════

function PanelHistorial:CreateSidebar(parent)
    local sidebar = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    
    -- ✅ FIX: Sidebar tiene ancho FIJO del Theme, no escalado con la ventana.
    --    Multiplicar por windowScale causaba que el sidebar se solapara con
    --    el contenido cuando la escala no era exactamente 1.0.
    sidebar:SetWidth(Theme.LAYOUT.sidebarWidth)
    
    sidebar:SetBackdrop(Theme.BACKDROPS.simple)
    Theme:SetBackdropColor(sidebar, Theme.BG.void)
    
    local rightBorder = sidebar:CreateTexture(nil, "BORDER")
    rightBorder:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    rightBorder:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    rightBorder:SetWidth(1)
    rightBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(rightBorder, Theme.GOLD.gold0)
    
    local scrollFrame = Widgets:CreateScrollFrame(sidebar, Theme.LAYOUT.sidebarWidth - 20, 500)
    scrollFrame:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 10, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -10, 12)
    
    local content = scrollFrame.scrollChild
    content:SetWidth(Theme.LAYOUT.sidebarWidth - 20)
    
    local yOffset = 0

    -- ── CORRECCIÓN: Datos dinámicos en lugar de estáticos
    local runs = MitzuMPlus:GetAllRuns() or {}
    local totalRuns = #runs
    local inTime = 0
    local bestKey = 0
    local weeklyRuns = 0

    -- Calcular estadísticas reales
    for _, run in ipairs(runs) do
        if run.inTime then inTime = inTime + 1 end
        if run.keyLevel and run.keyLevel > bestKey then bestKey = run.keyLevel end
        -- BUG-C1 FIX: run.timestamp → run.startTime
        if run.startTime and (time() - run.startTime) < 604800 then
            weeklyRuns = weeklyRuns + 1
        end
    end

    -- ── FASE 1.3: Estado de bienvenida cuando no hay ninguna run ────────────
    if totalRuns == 0 then
        local welcomeFrame = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate")
        welcomeFrame:SetPoint("TOPLEFT",  content, "TOPLEFT",  10, -20)
        welcomeFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -20)
        welcomeFrame:SetHeight(160)
        welcomeFrame:SetBackdrop(Theme.BACKDROPS.panel)
        Theme:SetBackdropColor(welcomeFrame, Theme.BG.btnPrim)
        Theme:SetBackdropBorderColor(welcomeFrame, Theme.GOLD.gold0)

        local iconTex = welcomeFrame:CreateTexture(nil, "OVERLAY")
        iconTex:SetPoint("TOP", welcomeFrame, "TOP", 0, -18)
        iconTex:SetSize(32, 32)
        iconTex:SetTexture(RECORD_ICON)
        iconTex:SetAlpha(0.6)

        local hi = welcomeFrame:CreateFontString(nil, "OVERLAY")
        hi:SetPoint("TOP", iconTex, "BOTTOM", 0, -8)
        hi:SetWidth(welcomeFrame:GetWidth() - 20)
        hi:SetWordWrap(true)
        hi:SetJustifyH("CENTER")
        Theme:ApplyFont(hi, "mono", 12)
        Theme:SetTextColor(hi, Theme.GOLD.gold4)
        hi:SetText(">> Bienvenido a MitzuMPlus")

        local desc = welcomeFrame:CreateFontString(nil, "OVERLAY")
        desc:SetPoint("TOP", hi, "BOTTOM", 0, -8)
        desc:SetWidth(welcomeFrame:GetWidth() - 24)
        desc:SetWordWrap(true)
        desc:SetJustifyH("CENTER")
        Theme:ApplyFont(desc, "normal", 11)
        Theme:SetTextColor(desc, Theme.TEXT.tertiary)
        desc:SetText("Completa tu primera M+ con el addon activo para ver tus estadísticas aquí.")

        self.sidebar = sidebar
        self.sidebarContent = content
        content:SetHeight(200)
        scrollFrame:UpdateScrollRange()
        return sidebar
    end

    local outTime = totalRuns - inTime
    local successRate = totalRuns > 0 and ((inTime / totalRuns) * 100) or 0
    
    local block1 = self:CreateStatBlock(content, string.format(">> RESUMEN GLOBAL (%d)", totalRuns))
    block1:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
    block1:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)
    local block1_addrow = block1.AddRow
    block1_addrow("Total Runs", tostring(totalRuns), "normal")
    block1_addrow("En tiempo", string.format("%d (%.0f%%)", inTime, successRate), "ok")
    block1_addrow("Fuera tiempo", string.format("%d (%.0f%%)", outTime, 100 - successRate), "bad")
    block1_addrow("Esta semana", string.format("%d runs", weeklyRuns), "normal")
    self.block1 = block1
    yOffset = yOffset - block1:GetHeight() - 15  -- ✅ CORRECCIÓN: aumentar espacio entre bloques
    
    -- Mejor llave (si hay datos)
    local bestKeyText = bestKey > 0 and string.format("+%d", bestKey) or "N/A"
    local bestKeyDungeon = "N/A"
    local bestKeyResult = "N/A"
    local bestKeyDate = "N/A"
    
    -- Encontrar detalles de la mejor llave
    for _, run in ipairs(runs) do
        if run.keyLevel == bestKey and bestKey > 0 then
            bestKeyDungeon = run.dungeonName or "Unknown"
            bestKeyResult = run.inTime and "En tiempo" or "Fuera tiempo"
            -- FIX BUG-DATE: run.timestamp no existe, el campo correcto es run.startTime
            local ts = run.startTime or run.timestamp
            if ts and ts > 0 then
                local days = math.floor((time() - ts) / 86400)
                if days == 0 then
                    bestKeyDate = "Hoy"
                elseif days == 1 then
                    bestKeyDate = "Ayer"
                else
                    bestKeyDate = string.format("Hace %d días", days)
                end
            end
            break
        end
    end
    
    local block2 = self:CreateStatBlock(content, bestKey > 0 and string.format(">> MEJOR LLAVE (+%d)", bestKey) or ">> MEJOR LLAVE")
    block2:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
    block2:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)
    local block2_addrow = block2.AddRow
    block2_addrow("Mazmorra", bestKeyDungeon, "normal")
    block2_addrow("Nivel", bestKeyText, "gold")
    block2_addrow("Resultado", bestKeyResult, bestKeyResult == "En tiempo" and "ok" or "bad")
    block2_addrow("Fecha", bestKeyDate, "normal")
    self.block2 = block2
    yOffset = yOffset - block2:GetHeight() - 15  -- ✅ CORRECCIÓN: aumentar espacio entre bloques
    
    -- DPS promedio con datos oficiales de C_DamageMeter cuando están disponibles
    local totalDPS = 0
    local dpsRunCount = 0
    for _, run in ipairs(runs) do
        local dmg = (run.stats and run.stats.damageTotal) or 0
        local ct  = tonumber(run.completionTime) or 0
        if ct > 0 and dmg > 0 then
            totalDPS = totalDPS + (dmg / ct)
            dpsRunCount = dpsRunCount + 1
        end
    end
    
    local avgDPS = dpsRunCount > 0 and (totalDPS / dpsRunCount) or 0
    
    local block3 = self:CreateStatBlock(content, string.format(">> DPS PROMEDIO (%s)", F():FormatDPS(avgDPS)))
    block3:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
    block3:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)
    local block3_addrow = block3.AddRow
    block3_addrow("DPS prom.", F():FormatDPS(avgDPS), "gold")
    block3_addrow("Runs con daño", tostring(dpsRunCount), "normal")
    -- HPS y DTPS promedio reales (si el jugador fue heal/tank en alguna run)
    do
        local H = MitzuMPlus.Helpers
        local totalHPS, hpsN, totalDTPS, dtpsN = 0, 0, 0, 0
        for _, r in ipairs(runs) do
            local hps  = H and H:GetRunHPS(r)  or 0
            local dtps = H and H:GetRunDTPS(r) or 0
            if hps  > 0 then totalHPS  = totalHPS  + hps;  hpsN  = hpsN  + 1 end
            if dtps > 0 then totalDTPS = totalDTPS + dtps; dtpsN = dtpsN + 1 end
        end
        local avgHPS  = hpsN  > 0 and (totalHPS  / hpsN ) or 0
        local avgDTPS = dtpsN > 0 and (totalDTPS / dtpsN) or 0
        block3_addrow("HPS prom.",  F():FormatDPS(avgHPS),  "ok")
        block3_addrow("DTPS prom.", F():FormatDPS(avgDTPS), "bad")
    end
    self.block3 = block3
    yOffset = yOffset - block3:GetHeight() - 15  -- ✅ CORRECCIÓN: aumentar espacio entre bloques
    
    -- Esta semana (ya calculado arriba como weeklyRuns)
    local weeklyInTime = 0
    local weeklyDeaths = 0
    for _, run in ipairs(runs) do
        -- BUG-C1 FIX: run.startTime (no run.timestamp)
        -- BUG-C2 FIX: run.stats.deaths (no run.stats.deathCount)
        if run.startTime and (time() - run.startTime) < 604800 then
            if run.inTime then weeklyInTime = weeklyInTime + 1 end
            weeklyDeaths = weeklyDeaths + ((run.stats and run.stats.deaths) or 0)
        end
    end
    
    local block4 = self:CreateStatBlock(content, ">> ESTA SEMANA")
    block4:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
    block4:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)
    local block4_addrow = block4.AddRow
    block4_addrow("Runs", tostring(weeklyRuns), "normal")
    block4_addrow("En tiempo", tostring(weeklyInTime), "ok")
    block4_addrow("Muertes total", tostring(weeklyDeaths), "bad")
    self.block4 = block4
    yOffset = yOffset - block4:GetHeight() - 15  -- ✅ CORRECCIÓN: aumentar espacio entre bloques
    
    -- Mejores por mazmorra (datos reales)
    local block5 = self:CreateStatBlock(content, ">> MEJORES POR MAZMORRA")
    block5:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
    block5:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)
    local block5_addrow = block5.AddRow
    
    -- Calcular mejor llave por mazmorra
    local dungeonBestKeys = {}
    for _, run in ipairs(runs) do
        if run.keyLevel and run.keyLevel > 0 and run.dungeonName then
            if not dungeonBestKeys[run.dungeonName] or run.keyLevel > dungeonBestKeys[run.dungeonName] then
                dungeonBestKeys[run.dungeonName] = run.keyLevel
            end
        end
    end
    
    -- Mostrar hasta 5 mazmorras con mejores llaves
    local count = 0
    for dungeon, key in pairs(dungeonBestKeys) do
        if count < 5 then
            block5_addrow(dungeon, string.format("+%d", key), "gold")
            count = count + 1
        end
    end
    self.block5 = block5
    yOffset = yOffset - block5:GetHeight() - 15  -- ✅ CORRECCIÓN: aumentar espacio entre bloques
    
    content:SetHeight(math.abs(yOffset) + 20)
    scrollFrame:UpdateScrollRange()
    
    self.sidebar = sidebar
    self.sidebarContent = content
    
    return sidebar
end

function PanelHistorial:CreateStatBlock(parent, title)
    local block = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    -- ✅ FIX BUG6: altura inicial pequeña; se recalcula dinámicamente al añadir filas
    block:SetHeight(44)
    block:SetBackdrop(Theme.BACKDROPS.panel)
    Theme:SetBackdropColor(block, Theme.BG.panel)
    Theme:SetBackdropBorderColor(block, Theme.BORDER.panel)
    
    local header = block:CreateFontString(nil, "OVERLAY")
    header:SetPoint("TOPLEFT", block, "TOPLEFT", 10, -10)
    Theme:ApplyFont(header, "mono", 12)
    header:SetText(title)
    Theme:SetTextColor(header, Theme.GOLD.gold3)
    
    local headerLine = block:CreateTexture(nil, "ARTWORK")
    headerLine:SetPoint("TOPLEFT",  header, "BOTTOMLEFT", 0, -5)
    headerLine:SetPoint("TOPRIGHT", block,  "TOPRIGHT",  -10, -27)
    headerLine:SetHeight(1)
    headerLine:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(headerLine, Theme.GOLD.gold0)

    -- ── Gem ornament en el centro de la línea divisoria ──────────────────────
    local gemIcon = block:CreateTexture(nil, "OVERLAY")
    gemIcon:SetSize(10, 10)
    gemIcon:SetPoint("CENTER", headerLine, "CENTER", 0, 0)
    -- Usar la textura gem_divider del addon si existe, o un cuadrado rotado como fallback
    local gemPath = "Interface\\AddOns\\MitzuMPlus_Historial\\Media\\Icons\\gem_divider"
    gemIcon:SetTexture(gemPath)
    Theme:SetVertexColor(gemIcon, Theme.GOLD.gold3)

    -- Línea izquierda (se acorta para dejar espacio al gem)
    local lineLeft = block:CreateTexture(nil, "ARTWORK")
    lineLeft:SetPoint("LEFT",   headerLine, "LEFT",   0, 0)
    lineLeft:SetPoint("RIGHT",  gemIcon,    "LEFT",  -3, 0)
    lineLeft:SetHeight(1)
    lineLeft:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(lineLeft, Theme.GOLD.gold0)

    -- Línea derecha
    local lineRight = block:CreateTexture(nil, "ARTWORK")
    lineRight:SetPoint("LEFT",  gemIcon,    "RIGHT",  3, 0)
    lineRight:SetPoint("RIGHT", headerLine, "RIGHT",  0, 0)
    lineRight:SetHeight(1)
    lineRight:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(lineRight, Theme.GOLD.gold0)

    -- Ocultar la línea original (ya tenemos las dos partes + gem)
    headerLine:SetAlpha(0)
    
    block.header = header
    block.rows   = {}
    
    local yOffset = -35
    
    local function AddRow(labelText, valueText, valueColor)
        local row = CreateFrame("Frame", nil, block)
        row:SetPoint("TOPLEFT",  block, "TOPLEFT",  10, yOffset)
        row:SetPoint("TOPRIGHT", block, "TOPRIGHT", -10, yOffset)
        row:SetHeight(20)  -- ✅ CORRECCIÓN: subir de 18 a 20px para evitar solapamiento
        
        local label = row:CreateFontString(nil, "OVERLAY")
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -80, 0)  -- ✅ CORRECCIÓN: reservar 80px para el value
        label:SetWordWrap(false)
        label:SetNonSpaceWrap(false)
        Theme:ApplyFont(label, "mono", 13)
        label:SetText(labelText)
        Theme:SetTextColor(label, Theme.TEXT.tertiary)
        
        local value = row:CreateFontString(nil, "OVERLAY")
        value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        value:SetWidth(75)  -- ✅ CORRECCIÓN: ancho fijo para evitar solapamiento
        value:SetJustifyH("RIGHT")
        value:SetWordWrap(false)
        Theme:ApplyFont(value, "mono", 13)
        value:SetText(valueText)
        
        if valueColor == "ok" then
            Theme:SetTextColor(value, Theme.STATUS.ok)
        elseif valueColor == "bad" then
            Theme:SetTextColor(value, Theme.STATUS.bad)
        elseif valueColor == "gold" then
            Theme:SetTextColor(value, Theme.GOLD.gold4)
        elseif valueColor == "info" then
            Theme:SetTextColor(value, Theme.STATUS.info)
        else
            Theme:SetTextColor(value, Theme.TEXT.primary)
        end
        
        row.label = label
        row.value = value
        row.valFS = value   -- alias para AnimateCounter (Fase 4.2)

        table.insert(block.rows, row)
        yOffset = yOffset - 20  -- ✅ CORRECCIÓN: usar -20 para coincidir con altura de fila

        -- ✅ Recalcular altura del bloque después de cada fila añadida
        block:SetHeight(math.abs(yOffset) + 10)
        
        return row
    end
    
    block.AddRow = AddRow
    
    return block
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CONTENT AREA (right side)
-- ═══════════════════════════════════════════════════════════════════════════

function PanelHistorial:CreateContentArea(parent)
    local content = CreateFrame("Frame", nil, parent)
    content:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    content:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

    self:CreateFilterBar(content)
    self:CreateInfoBar(content)
    self:CreateArchiveBar(content)
    self:CreateTable(content)
    self:CreatePagination(content)
    self:CreateTableEmptyState(content)

    self.content = content

    return content
end

-- Barra operativa: Historial administra runs; los agregados pertenecen a
-- Estadísticas. Aquí solo se informa la muestra y se actúa sobre una selección.
function PanelHistorial:CreateArchiveBar(parent)
    local bar=CreateFrame("Frame",nil,parent,BackdropTemplateMixin and "BackdropTemplate")
    bar:SetPoint("TOPLEFT",self.infoBar or self.filterBar,"BOTTOMLEFT",0,0)
    bar:SetPoint("TOPRIGHT",self.infoBar or self.filterBar,"BOTTOMRIGHT",0,0)
    bar:SetHeight(44);bar:SetBackdrop(Theme.BACKDROPS.simple);Theme:SetBackdropColor(bar,Theme.BG.titlebar)

    -- ═══════════════════════════════════════════════════════════════════
    -- BUG UI-BTN1 — "EXPORTAR", "COMPARAR" y "ELIMINAR" se salían del botón
    -- y ELIMINAR se salía de la ventana entera.
    --
    -- Los anchos eran fijos (86, 88, 72) y estaban calculados a ojo para la
    -- fuente de Blizzard. Con la del tema a tamaño 13, el texto pinta más
    -- largo. Ahora cada botón se mide y se ajusta a su propio texto, con la
    -- fuente un punto más pequeña: cinco botones en una barra son etiquetas,
    -- no titulares. El ancho mínimo mantiene la fila pareja.
    --
    -- Y el hueco del texto de la izquierda ya no es un "-535" a ojo: se ata
    -- al primer botón, así que sigue siendo correcto aunque los botones
    -- cambien de tamaño, de idioma o de fuente.
    -- ═══════════════════════════════════════════════════════════════════
    local ACTION_FONT, ACTION_MIN, ACTION_MAX, ACTION_PAD = 12, 70, 110, 11

    local status=bar:CreateFontString(nil,"OVERLAY")
    status:SetPoint("LEFT",bar,"LEFT",12,0);status:SetJustifyH("LEFT");Theme:ApplyFont(status,"mono",11);Theme:SetTextColor(status,Theme.TEXT.tertiary)
    if status.SetWordWrap then status:SetWordWrap(false) end
    if status.SetMaxLines then status:SetMaxLines(1) end
    status:SetText("0 partidas · ninguna seleccionada")
    self.archiveStatusText=status

    local deleteBtn=Widgets:CreateButton(bar,"ELIMINAR",86,26,"normal",ACTION_FONT)
    deleteBtn:SetPoint("RIGHT",bar,"RIGHT",-10,0)
    deleteBtn:SetScript("OnClick",function()
        local id=self.selectedRunID
        if not id then return end
        if StaticPopup_Show then StaticPopup_Show("MITZUMPLUS_CONFIRM_DELETE",id,nil,id) end
    end)
    local favoriteBtn=Widgets:CreateButton(bar,"FAVORITA",88,26,"normal",ACTION_FONT)
    favoriteBtn:SetPoint("RIGHT",deleteBtn,"LEFT",-7,0)
    favoriteBtn:SetScript("OnClick",function()
        local id=self.selectedRunID;if not id then return end
        local run=MitzuMPlus.RunMetrics and MitzuMPlus.RunMetrics:FindRunByID(id)
        if not run then return end
        if MitzuMPlus.DataManager and MitzuMPlus.DataManager.ToggleFavorite then
            MitzuMPlus.DataManager:ToggleFavorite(id)
        else run.isFavorite=not run.isFavorite end
        self:Refresh()
    end)
    local editBtn=Widgets:CreateButton(bar,"EDITAR",72,26,"normal",ACTION_FONT)
    editBtn:SetPoint("RIGHT",favoriteBtn,"LEFT",-7,0)
    editBtn:SetScript("OnClick",function() self:OpenMetadataEditor() end)
    local compareBtn=Widgets:CreateButton(bar,"COMPARAR",88,26,"normal",ACTION_FONT)
    compareBtn:SetPoint("RIGHT",editBtn,"LEFT",-7,0)
    compareBtn:SetScript("OnClick",function() self:CompareSelection() end)
    local exportBtn=Widgets:CreateButton(bar,"EXPORTAR",88,26,"primary",ACTION_FONT)
    exportBtn:SetPoint("RIGHT",compareBtn,"LEFT",-7,0)
    exportBtn:SetScript("OnClick",function() self:ExportSelection() end)
    -- Cada uno al ancho de SU texto. Se hace despues de crearlos todos: los
    -- puntos de anclaje son relativos de derecha a izquierda, asi que la fila
    -- se recoloca sola en cuanto cambian los anchos.
    for _,b in ipairs({deleteBtn,favoriteBtn,editBtn,compareBtn,exportBtn}) do
        if b.FitToText then b:FitToText(ACTION_MIN,ACTION_MAX,ACTION_PAD) end
    end
    -- El texto de estado termina donde empieza el primer boton, no en un
    -- margen fijo inventado.
    status:SetPoint("RIGHT",exportBtn,"LEFT",-12,0)

    self.archiveBar=bar;self.singleButtons={favoriteBtn,deleteBtn,editBtn}
    self.compareBtn=compareBtn;self.exportBtn=exportBtn;self.deleteBtn=deleteBtn
    local function ActionTip(btn,titleText,description)
        btn:SetScript("OnEnter",function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self,"ANCHOR_TOP")
            GameTooltip:SetText(titleText,1,.8,.2)
            GameTooltip:AddLine(description,.78,.78,.78,true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    end
    ActionTip(exportBtn,"Exportar selección","Crea un CSV con la partida seleccionada o con la selección múltiple.")
    ActionTip(compareBtn,"Comparar partidas","Requiere al menos dos partidas seleccionadas con Ctrl+clic.")
    ActionTip(editBtn,"Editar partida","Edita la nota y las etiquetas de una sola partida.")
    ActionTip(favoriteBtn,"Favorita","Marca o desmarca una sola partida como favorita.")
    ActionTip(deleteBtn,"Eliminar partida","Elimina una sola partida después de pedir confirmación.")
    self.selectedRunIDs=self.selectedRunIDs or {}
    return bar
end

function PanelHistorial:UpdateArchiveBar()
    if not self.archiveStatusText then return end
    local total=#(self.filteredRuns or {})
    local run=self.selectedRunID and MitzuMPlus.RunMetrics and MitzuMPlus.RunMetrics:FindRunByID(self.selectedRunID) or nil
    if self.selectedRunID and not run then self.selectedRunID=nil end
    local selectedCount=0;for id in pairs(self.selectedRunIDs or {}) do if MitzuMPlus.RunMetrics:FindRunByID(id) then selectedCount=selectedCount+1 else self.selectedRunIDs[id]=nil end end
    local singleRun=(selectedCount==1) and run or nil
    if selectedCount>1 then
        self.archiveStatusText:SetText(string.format("%d partidas · %d seleccionadas",total,selectedCount))
    elseif singleRun then
        local qualityLabel="Sin evaluar"
        if MitzuMPlus.RunMetrics then local _,label=MitzuMPlus.RunMetrics:GetQuality(singleRun);qualityLabel=label end
        self.archiveStatusText:SetText(string.format("%d partidas · %s +%d · %s",total,singleRun.dungeonName or "?",tonumber(singleRun.keyLevel) or 0,qualityLabel))
    else self.archiveStatusText:SetText(string.format("%d partidas · selecciona una fila (Ctrl+clic: varias)",total)) end

    local function SetEnabled(btn,enabled,r,g,b)
        btn:SetEnabled(enabled);btn:SetAlpha(enabled and 1 or .32)
        local fs=btn.GetFontString and btn:GetFontString()
        if fs then
            if enabled and r then fs:SetTextColor(r,g,b,1)
            elseif enabled then fs:SetTextColor(.9,.9,.9,1)
            else fs:SetTextColor(.42,.42,.42,1) end
        end
    end
    for _,btn in ipairs(self.singleButtons or {}) do SetEnabled(btn,singleRun~=nil) end
    SetEnabled(self.compareBtn,selectedCount>=2)
    SetEnabled(self.exportBtn,selectedCount>=1,1,.82,0)
    SetEnabled(self.deleteBtn,singleRun~=nil,.93,.30,.30)
end

function PanelHistorial:GetSelectedRuns()
    local result={}
    for _,run in ipairs(MitzuMPlus:GetAllRuns() or {}) do
        if self.selectedRunIDs and self.selectedRunIDs[tonumber(run.runID)] then result[#result+1]=run end
    end
    return result
end

function PanelHistorial:OpenMetadataEditor()
    local run=self.selectedRunID and MitzuMPlus.RunMetrics:FindRunByID(self.selectedRunID)
    if not run then return end
    if not self.metadataEditor then
        local f=CreateFrame("Frame","MitzuMPlusRunMetadataEditor",UIParent,BackdropTemplateMixin and "BackdropTemplate")
        f:SetSize(440,250);f:SetPoint("CENTER");f:SetFrameStrata("DIALOG");f:SetBackdrop(Theme.BACKDROPS.panel)
        Theme:SetBackdropColor(f,Theme.BG.panel);Theme:SetBackdropBorderColor(f,Theme.GOLD.gold2);f:EnableMouse(true)
        local title=f:CreateFontString(nil,"OVERLAY");title:SetPoint("TOPLEFT",16,-14);Theme:ApplyFont(title,"title",16);Theme:SetTextColor(title,Theme.GOLD.gold4);f.title=title
        local nl=f:CreateFontString(nil,"OVERLAY");nl:SetPoint("TOPLEFT",16,-48);Theme:ApplyFont(nl,"mono",11);nl:SetText("NOTA");Theme:SetTextColor(nl,Theme.TEXT.dim)
        local notes=CreateFrame("EditBox",nil,f,"InputBoxTemplate");notes:SetPoint("TOPLEFT",16,-66);notes:SetSize(405,70);notes:SetMultiLine(true);notes:SetAutoFocus(false);notes:SetMaxLetters(500);notes:SetFontObject(GameFontHighlightSmall);f.notes=notes
        Theme:ApplyFont(notes,"normal",13)
        local tl=f:CreateFontString(nil,"OVERLAY");tl:SetPoint("TOPLEFT",16,-145);Theme:ApplyFont(tl,"mono",11);tl:SetText("ETIQUETAS (separadas por coma)");Theme:SetTextColor(tl,Theme.TEXT.dim)
        local tags=CreateFrame("EditBox",nil,f,"InputBoxTemplate");tags:SetPoint("TOPLEFT",16,-165);tags:SetSize(405,24);tags:SetAutoFocus(false);tags:SetMaxLetters(160);f.tags=tags
        Theme:ApplyFont(tags,"normal",13)
        local cancel=Widgets:CreateButton(f,"CANCELAR",90,26,"normal");cancel:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-16,14);cancel:SetScript("OnClick",function() f:Hide() end)
        local save=Widgets:CreateButton(f,"GUARDAR",90,26,"primary");save:SetPoint("RIGHT",cancel,"LEFT",-8,0);save:SetScript("OnClick",function()
            local id=f.runID;if not id then return end
            MitzuMPlus.DataManager:SetRunNotes(id,f.notes:GetText() or "")
            MitzuMPlus.DataManager:SetRunTags(id,f.tags:GetText() or "")
            f.notes:ClearFocus();f.tags:ClearFocus();f:Hide();PanelHistorial:Refresh()
        end)
        notes:SetScript("OnEscapePressed",function(self) self:ClearFocus();f:Hide() end);tags:SetScript("OnEscapePressed",function(self) self:ClearFocus();f:Hide() end)
        self.metadataEditor=f
    end
    local f=self.metadataEditor;f.runID=tonumber(run.runID);f.title:SetText(string.format("EDITAR RUN #%d · %s +%d",f.runID or 0,run.dungeonName or "?",tonumber(run.keyLevel) or 0))
    f.notes:SetText(tostring(run.notes or ""));f.tags:SetText(type(run.tags)=="table" and table.concat(run.tags,", ") or "");f:Show();f.notes:SetFocus()
end

function PanelHistorial:CompareSelection()
    local runs=self:GetSelectedRuns();if #runs<2 then return end
    local lines={"COMPARACION DE RUNS SELECCIONADAS","Fecha | Mazmorra | Nivel | Resultado | Margen | Rol | Metrica"}
    for _,run in ipairs(runs) do
        local RM=MitzuMPlus.RunMetrics;local margin=RM:GetMargin(run);local metric,label=RM:GetRoleMetric(run)
        local marginText=margin and string.format("%s%d:%02d",margin>=0 and "+" or "-",math.floor(math.abs(margin)/60),math.floor(math.abs(margin)%60)) or "-"
        lines[#lines+1]=string.format("%s | %s | +%d | %s | %s | %s | %s %s",F():FormatDate(run.startTime,"absolute"),run.dungeonName or "?",tonumber(run.keyLevel) or 0,run.inTime and "EN TIEMPO" or "FUERA",marginText,select(2,RM:GetRole(run)),label or "Metrica",metric and F():FormatDPS(metric) or "-")
    end
    MitzuMPlus.Export:CopyToClipboard(table.concat(lines,"\n"))
end

function PanelHistorial:ExportSelection()
    local runs=self:GetSelectedRuns();if #runs<1 then return end
    if MitzuMPlus.Export and MitzuMPlus.Export.ExportToCSV then MitzuMPlus.Export:ExportToCSV(runs) end
end


-- ═══════════════════════════════════════════════════════════════════════════
-- EMPTY STATE — visible cuando no hay runs (filtradas o totales)
-- ═══════════════════════════════════════════════════════════════════════════

function PanelHistorial:CreateTableEmptyState(parent)
    -- Anclar al área de tabla, debajo de la barra operativa.
    -- NO usar parent completo (incluye sidebar) — eso desplaza el centro visualmente
    local es = CreateFrame("Frame", nil, parent)
    es:SetPoint("TOPLEFT",     self.archiveBar, "BOTTOMLEFT",  0,  0)
    es:SetPoint("BOTTOMRIGHT", parent,          "BOTTOMRIGHT", 0, 42)
    es:Hide()

    -- Icono central (textura de llave de M+)
    local iconFrame = CreateFrame("Frame", nil, es, BackdropTemplateMixin and "BackdropTemplate")
    iconFrame:SetSize(64, 64)
    iconFrame:SetPoint("CENTER", es, "CENTER", 0, 48)
    iconFrame:SetBackdrop(Theme.BACKDROPS.panel)
    Theme:SetBackdropColor(iconFrame, Theme.BG.btnPrim)
    Theme:SetBackdropBorderColor(iconFrame, Theme.GOLD.gold0)

    local iconTex = iconFrame:CreateTexture(nil, "OVERLAY")
    iconTex:SetPoint("CENTER")
    iconTex:SetSize(40, 40)
    iconTex:SetTexture(RECORD_ICON)
    iconTex:SetAlpha(0.7)

    -- Título
    local title = es:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", iconFrame, "BOTTOM", 0, -14)
    Theme:ApplyFont(title, "title", 16)
    Theme:SetTextColor(title, Theme.TEXT.primary)
    title:SetText("Sin runs registradas")
    es.title = title

    -- Subtítulo (cambia según contexto: sin datos vs filtros vacíos)
    local subtitle = es:CreateFontString(nil, "OVERLAY")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -8)
    subtitle:SetWidth(360)
    subtitle:SetWordWrap(true)
    subtitle:SetJustifyH("CENTER")
    Theme:ApplyFont(subtitle, "normal", 13)
    Theme:SetTextColor(subtitle, Theme.TEXT.tertiary)
    subtitle:SetText("Completa tu primera Mythic+ con el addon activo para verla aquí.")
    es.subtitle = subtitle

    -- CTA — solo aparece cuando no hay runs en absoluto (no filtros)
    local cta = Widgets:CreateButton(es, "Como registrar una run", 200, 28, "primary")
    cta:SetPoint("TOP", subtitle, "BOTTOM", 0, -16)
    cta:SetScript("OnClick", function()
        MitzuMPlus:Print("|cFFe8b84aActiva el addon antes de entrar a un Mythic+.|r  Al terminar, la run se guarda automáticamente. Asegúrate de que |cFF21de66'Registrar automáticamente'|r esté marcado en Configuración.")
    end)
    cta:SetScript("OnEnter", function()
        GameTooltip:SetOwner(cta, "ANCHOR_TOP")
        GameTooltip:SetText("Cómo registrar tu primera run", 1, 0.8, 0.2)
        GameTooltip:AddLine("1. Entra a cualquier dungeon Mythic+", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("2. El addon registra la run al terminar", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("3. Vuelve aquí para ver tu historial", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    cta:SetScript("OnLeave", function() GameTooltip:Hide() end)
    es.cta = cta

    self.tableEmptyState = es
    return es
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FILTER BAR
-- ═══════════════════════════════════════════════════════════════════════════

function PanelHistorial:CreateFilterBar(parent)
    local filterBar = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    filterBar:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, 0)
    filterBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    filterBar:SetHeight(104)
    filterBar:SetBackdrop(Theme.BACKDROPS.simple)
    Theme:SetBackdropColor(filterBar, Theme.BG.titlebar)

    local bottomBorder = filterBar:CreateTexture(nil, "BORDER")
    bottomBorder:SetPoint("BOTTOMLEFT",  filterBar, "BOTTOMLEFT",  0, 0)
    bottomBorder:SetPoint("BOTTOMRIGHT", filterBar, "BOTTOMRIGHT", 0, 0)
    bottomBorder:SetHeight(1)
    bottomBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(bottomBorder, Theme.GOLD.gold0)

    local midBorder = filterBar:CreateTexture(nil, "BORDER")
    midBorder:SetPoint("BOTTOMLEFT",  filterBar, "BOTTOMLEFT",  0, 48)
    midBorder:SetPoint("BOTTOMRIGHT", filterBar, "BOTTOMRIGHT", 0, 48)
    midBorder:SetHeight(1)
    midBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(midBorder, Theme.BORDER.separator)

    -- ─── HELPER PILL: bordes redondeados con Tooltip border ───────────
    -- FIX: usar UI-Tooltip-Border (edgeSize 8) para esquinas suaves
    local PILL_BACKDROP_OFF = {
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 0, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    }
    local PILL_BACKDROP_ON = {
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 0, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    }

    local function CreatePill(parent, label, isActive)
        local pill = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
        pill:SetHeight(22)
        pill:SetBackdrop(PILL_BACKDROP_OFF)

        local fs = pill:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("CENTER")
        Theme:ApplyFont(fs, "mono", 12)
        fs:SetText(label)
        pill._label = fs
        pill._active = isActive or false

        local function Refresh()
            if pill._active then
                pill:SetBackdrop(PILL_BACKDROP_ON)
                Theme:SetBackdropColor(pill,       Theme.BG.btnPrim)
                Theme:SetBackdropBorderColor(pill, Theme.GOLD.gold3)
                Theme:SetTextColor(fs,             Theme.GOLD.gold5)
            else
                pill:SetBackdrop(PILL_BACKDROP_OFF)
                Theme:SetBackdropColor(pill,       Theme.BG.button)
                Theme:SetBackdropBorderColor(pill, Theme.BORDER.panel)
                Theme:SetTextColor(fs,             Theme.TEXT.tertiary)
            end
        end

        pill.SetActive = function(self, state)
            self._active = state
            Refresh()
        end

        pill:SetScript("OnEnter", function(self)
            if not self._active then
                Theme:SetBackdropBorderColor(self, Theme.GOLD.gold1)
                Theme:SetTextColor(fs, Theme.GOLD.gold3)
            end
        end)
        pill:SetScript("OnLeave", function(self) Refresh() end)

        local tw = fs:GetStringWidth() + 20
        pill:SetWidth(math.max(tw, 54))
        Refresh()
        return pill
    end

    -- ═══════════════════════════════════════════════════════════════════
    -- FILA 1: búsqueda y dimensiones principales. Las exportaciones globales
    -- no pertenecen a esta franja; queda solo la acción contextual inferior.
    -- ═══════════════════════════════════════════════════════════════════
    local orderDropdown = Widgets:CreateDropdown(filterBar, 160, {
        "Fecha: reciente",
        "Nivel: mayor",
        "Margen: mayor",
        "Mazmorra: A-Z",
    }, 1, function(value, text)
        local cols = {"date","level","margin","dungeon"}
        self.sortColumn = cols[value] or "date"
        self.sortDescending = value ~= 4
        self:ApplyFilters()
    end)
    orderDropdown:SetPoint("RIGHT", filterBar, "RIGHT", -12, 20)
    self.orderDropdown = orderDropdown

    local orderLabel=filterBar:CreateFontString(nil,"OVERLAY")
    orderLabel:SetPoint("RIGHT",orderDropdown,"LEFT",-8,0)
    Theme:ApplyFont(orderLabel,"mono",11);orderLabel:SetText("ORDENAR")
    Theme:SetTextColor(orderLabel,Theme.TEXT.dim)

    local sepR = self:CreateSeparator(filterBar)
    sepR:SetPoint("RIGHT", orderLabel, "LEFT", -10, 0)

    -- Izquierda fila 1
    local searchInput = Widgets:CreateInput(filterBar, 180, "Buscar mazmorra...")
    searchInput:SetPoint("LEFT", filterBar, "LEFT", 12, 20)
    self.searchInput = searchInput

    -- BUG-C7 FIX: searchInput nunca estaba conectado a self.activeSearch.
    -- Widgets:CreateInput() devuelve directamente un EditBox, así que podemos
    -- HookScript sobre los eventos existentes sin destruir el placeholder logic.
    local PLACEHOLDER = "Buscar mazmorra..."
    local function OnSearchChanged()
        local text = searchInput:GetText() or ""
        if text == PLACEHOLDER then text = "" end
        self.activeSearch = (text ~= "") and text or nil
        self:ApplyFilters()
    end

    searchInput:HookScript("OnTextChanged",   function() OnSearchChanged() end)
    searchInput:HookScript("OnEnterPressed",  function() OnSearchChanged() end)
    searchInput:HookScript("OnEditFocusLost", function() OnSearchChanged() end)

    local sep1 = self:CreateSeparator(filterBar)
    sep1:SetPoint("LEFT", searchInput, "RIGHT", 8, 0)

    local dungeonLabel = filterBar:CreateFontString(nil, "OVERLAY")
    dungeonLabel:SetPoint("LEFT", sep1, "RIGHT", 8, 0)
    Theme:ApplyFont(dungeonLabel, "mono", 11)
    dungeonLabel:SetText("MAZMORRA")
    Theme:SetTextColor(dungeonLabel, Theme.TEXT.dim)

    local dungeonOptions = {"Todas"}
    local dungeonSet = {}
    local runs = MitzuMPlus:GetAllRuns() or {}
    for _, run in ipairs(runs) do
        if run.dungeonName and run.dungeonName ~= "" and not dungeonSet[run.dungeonName] then
            dungeonSet[run.dungeonName] = true
            table.insert(dungeonOptions, run.dungeonName)
        end
    end
    table.sort(dungeonOptions, function(a, b)
        if a == "Todas" then return true end
        if b == "Todas" then return false end
        return a:lower() < b:lower()
    end)

    -- El ancho definitivo lo pone AutoSizeToItems midiendo el nombre más
    -- largo que de verdad haya en el historial de este jugador. 180 es solo
    -- el punto de partida: fijarlo a ojo es lo que dejaba "El Frontal de la
    -- Muerte" partido en dos renglones.
    local dungeonDropdown = Widgets:CreateDropdown(filterBar, 180, dungeonOptions, 1, function(index, value)
        self.activeDungeon = (index > 1) and dungeonOptions[index] or ""
        -- BUG-L3 FIX: limpiar activeSearch al cambiar mazmorra para que la búsqueda
        -- de texto no persista cuando el usuario selecciona una mazmorra distinta.
        self.activeSearch = nil
        if self.searchInput and self.searchInput.SetText then
            self.searchInput:SetText("")
        end
        self:ApplyFilters()
    end)
    dungeonDropdown:SetPoint("LEFT", dungeonLabel, "RIGHT", 6, 0)
    -- Entre 150 y 230: por debajo de 150 el botón queda ridículo y por encima
    -- de 230 se come el sitio de PERSONAJE y TEMPORADA en la misma barra.
    -- Lo que no quepa se recorta con puntos y sale entero en el tooltip; el
    -- MENÚ, en cambio, se ensancha hasta el nombre más largo.
    if dungeonDropdown.AutoSizeToItems then
        dungeonDropdown:AutoSizeToItems(150, 230)
    end
    self.dungeonDropdown = dungeonDropdown

    -- ── Character filter (alts) ───────────────────────────────────────────
    local charSep = self:CreateSeparator(filterBar)
    charSep:SetPoint("LEFT", dungeonDropdown, "RIGHT", 8, 0)

    local charLabel = filterBar:CreateFontString(nil, "OVERLAY")
    charLabel:SetPoint("LEFT", charSep, "RIGHT", 8, 0)
    Theme:ApplyFont(charLabel, "mono", 11)
    charLabel:SetText("PERSONAJE")
    Theme:SetTextColor(charLabel, Theme.TEXT.dim)

    local charOptions = {"Todos"}
    local charSet = {}
    for _, run in ipairs(runs) do
        local pn = run.playerName or ""
        local pr = run.playerRealm or ""
        local key = pn
        if pr ~= "" then key = pn .. " - " .. pr end
        if pn ~= "" and not charSet[key] then
            charSet[key] = true
            table.insert(charOptions, key)
        end
    end
    table.sort(charOptions, function(a, b)
        if a == "Todos" then return true end
        if b == "Todos" then return false end
        return a:lower() < b:lower()
    end)

    local charDropdown = Widgets:CreateDropdown(filterBar, 160, charOptions, 1, function(index, value)
        self.activeCharFilter = (index > 1) and charOptions[index] or nil
        self:ApplyFilters()
    end)
    charDropdown:SetPoint("LEFT", charLabel, "RIGHT", 6, 0)
    self.charDropdown = charDropdown
    self.activeCharFilter = nil

    local seasonLabel=filterBar:CreateFontString(nil,"OVERLAY")
    seasonLabel:SetPoint("LEFT",charDropdown,"RIGHT",10,0);Theme:ApplyFont(seasonLabel,"mono",11)
    seasonLabel:SetText("TEMPORADA");Theme:SetTextColor(seasonLabel,Theme.TEXT.dim)
    -- La vista Historial está acotada a la expansión actual. Al ser una única
    -- opción no se presenta un desplegable que sugiera alternativas inexistentes.
    local seasonBadge=CreateFrame("Frame",nil,filterBar,BackdropTemplateMixin and "BackdropTemplate")
    seasonBadge:SetPoint("LEFT",seasonLabel,"RIGHT",6,0);seasonBadge:SetSize(120,26)
    seasonBadge:SetBackdrop(Theme.BACKDROPS.panel)
    Theme:SetBackdropColor(seasonBadge,Theme.BG.btnPrim)
    Theme:SetBackdropBorderColor(seasonBadge,Theme.GOLD.gold1)
    local seasonText=seasonBadge:CreateFontString(nil,"OVERLAY")
    seasonText:SetPoint("CENTER");Theme:ApplyFont(seasonText,"normal",13)
    seasonText:SetText("Midnight");Theme:SetTextColor(seasonText,Theme.GOLD.gold4)
    self.seasonBadge=seasonBadge;self.seasonDropdown=nil;self.activeSeasonFilter="MIDNIGHT"

    -- ═══════════════════════════════════════════════════════════════════
    -- FILA 2: RESULTADO pills | ─ | SEMANA pills
    -- Pills centradas verticalmente en el bloque inferior (y = -20)
    -- ═══════════════════════════════════════════════════════════════════

    -- RESULTADO
    local resLabel = filterBar:CreateFontString(nil, "OVERLAY")
    resLabel:SetPoint("LEFT", filterBar, "LEFT", 12, -27)
    Theme:ApplyFont(resLabel, "mono", 11)
    resLabel:SetText("RESULTADO:")
    Theme:SetTextColor(resLabel, Theme.TEXT.dim)

    local pillResAll = CreatePill(filterBar, "Todos", true)
    pillResAll:SetPoint("LEFT", resLabel, "RIGHT", 8, 0)

    local pillResIn = CreatePill(filterBar, "En tiempo", false)
    pillResIn:SetPoint("LEFT", pillResAll, "RIGHT", 5, 0)

    local pillResOut = CreatePill(filterBar, "Fuera", false)
    pillResOut:SetPoint("LEFT", pillResIn, "RIGHT", 5, 0)

    local function SetResultFilter(mode)
        self.activeResultFilter = mode
        pillResAll:SetActive(mode == 1)
        pillResIn:SetActive(mode == 2)
        pillResOut:SetActive(mode == 3)
        self:ApplyFilters()
    end
    pillResAll:SetScript("OnClick", function() SetResultFilter(1) end)
    pillResIn:SetScript("OnClick",  function() SetResultFilter(2) end)
    pillResOut:SetScript("OnClick", function() SetResultFilter(3) end)
    self.activeResultFilter = 1

    local sep2 = self:CreateSeparator(filterBar)
    sep2:SetPoint("LEFT", pillResOut, "RIGHT", 14, 0)

    -- SEMANA
    local weekLabel = filterBar:CreateFontString(nil, "OVERLAY")
    weekLabel:SetPoint("LEFT", sep2, "RIGHT", 14, 0)
    Theme:ApplyFont(weekLabel, "mono", 11)
    weekLabel:SetText("SEMANA:")
    Theme:SetTextColor(weekLabel, Theme.TEXT.dim)

    local pillWkAll  = CreatePill(filterBar, "Todo",     true)
    pillWkAll:SetPoint("LEFT", weekLabel, "RIGHT", 8, 0)

    local pillWkThis = CreatePill(filterBar, "Esta sem.", false)
    pillWkThis:SetPoint("LEFT", pillWkAll, "RIGHT", 5, 0)

    local pillWkLast = CreatePill(filterBar, "Anterior",  false)
    pillWkLast:SetPoint("LEFT", pillWkThis, "RIGHT", 5, 0)

    local function SetWeekFilter(mode)
        self.activeWeekFilter = mode
        pillWkAll:SetActive(mode == 1)
        pillWkThis:SetActive(mode == 2)
        pillWkLast:SetActive(mode == 3)
        self:ApplyFilters()
    end
    pillWkAll:SetScript("OnClick",  function() SetWeekFilter(1) end)
    pillWkThis:SetScript("OnClick", function() SetWeekFilter(2) end)
    pillWkLast:SetScript("OnClick", function() SetWeekFilter(3) end)
    self.activeWeekFilter = 1

    local roleLabel=filterBar:CreateFontString(nil,"OVERLAY")
    roleLabel:SetPoint("LEFT",pillWkLast,"RIGHT",14,0);Theme:ApplyFont(roleLabel,"mono",11)
    roleLabel:SetText("ROL:");Theme:SetTextColor(roleLabel,Theme.TEXT.dim)
    local roleValues={"ALL","TANK","HEALER","DAMAGER"}
    local roleDropdown=Widgets:CreateDropdown(filterBar,105,{"Todos","Tanque","Sanador","DPS"},1,function(index)
        self.activeRoleFilter=roleValues[index] or "ALL";self:ApplyFilters()
    end)
    roleDropdown:SetPoint("LEFT",roleLabel,"RIGHT",6,0);self.activeRoleFilter="ALL"

    local qualityLabel=filterBar:CreateFontString(nil,"OVERLAY")
    qualityLabel:SetPoint("LEFT",roleDropdown,"RIGHT",12,0);Theme:ApplyFont(qualityLabel,"mono",11)
    qualityLabel:SetText("DATOS:");Theme:SetTextColor(qualityLabel,Theme.TEXT.dim)
    local qualityValues={"ALL","COMPLETE","PARTIAL","STRUCTURAL","INVALID"}
    local qualityDropdown=Widgets:CreateDropdown(filterBar,140,{"Todos","Completos","Parciales","Estructurales","Incompletos"},1,function(index)
        self.activeQualityFilter=qualityValues[index] or "ALL";self:ApplyFilters()
    end)
    qualityDropdown:SetPoint("LEFT",qualityLabel,"RIGHT",6,0);self.activeQualityFilter="ALL"

    self.weekDropdown   = nil
    self.resultDropdown = nil
    self.filterBar = filterBar

    -- ═══════════════════════════════════════════════════════════════════
    -- BUG UI-FB1 — TEMPORADA y ORDENAR se pisaban
    --
    -- La fila 1 se monta en DOS cadenas que crecen la una hacia la otra:
    --   izquierda: buscador → MAZMORRA → PERSONAJE → TEMPORADA
    --   derecha:   ORDENAR, anclado al borde derecho de la barra
    -- y nada impedía que se encontrasen en medio. Con la ventana estrecha,
    -- o con la fuente un punto más grande, "Midnight" acababa debajo de
    -- "ORDENAR" y de "Fecha: reciente" — que es justo lo que se ve en la
    -- captura.
    --
    -- Sumar píxeles a mano no arregla esto: el ancho de "MAZMORRA" o de
    -- "PERSONAJE" depende de la fuente del tema, y la barra cambia de tamaño
    -- con la ventana. Así que el reparto se calcula, no se fija: se mide una
    -- vez lo que ocupa cada cosa, se ve cuánto queda para los desplegables y
    -- se reparte. Si no llega ni al mínimo, se van soltando piezas por orden
    -- de menos valor. Se recalcula en cada cambio de tamaño.
    -- ═══════════════════════════════════════════════════════════════════
    self._row = {
        bar        = filterBar,
        dungeon    = { frame = dungeonDropdown, pref = dungeonDropdown:GetWidth(), min = 110 },
        char       = { frame = charDropdown,    pref = charDropdown:GetWidth(),    min = 100 },
        order      = { frame = orderDropdown,   pref = orderDropdown:GetWidth(),   min = 110 },
        seasonLabel = seasonLabel,
        seasonBadge = seasonBadge,
        rightEdge   = sepR,
    }
    filterBar:SetScript("OnSizeChanged", function() self:LayoutFilterRow() end)
    if C_Timer and C_Timer.After then
        -- La primera pasada necesita que los marcos ya tengan coordenadas.
        C_Timer.After(0, function() self:LayoutFilterRow() end)
    end

    return filterBar
end

-- Reparte el ancho de la fila 1 de la barra de filtros. Idempotente: parte
-- siempre de los anchos preferidos, así que llamarla mil veces da lo mismo
-- que llamarla una.
function PanelHistorial:LayoutFilterRow()
    local r = self._row
    if not r or not r.bar then return end
    local barW = r.bar:GetWidth()
    local barLeft = r.bar:GetLeft()
    if not barW or barW < 80 or not barLeft then return end

    -- MEDIR UNA VEZ. `base`, `temporadaW` y `ordenExtra` solo dependen del
    -- ancho de las etiquetas y de los márgenes: no cambian al redimensionar
    -- la ventana. Se calculan en la primera pasada —cuando los desplegables
    -- aún están a su ancho preferido y la lectura es coherente— y se guardan.
    -- Leerlos otra vez después de haber cambiado anchos sería pedir un valor
    -- que el cliente quizá no haya recalculado todavía.
    if not r.metrics then
        local finSinTemporada = r.char.frame:GetRight()
        local finConTemporada = r.seasonBadge:GetRight()
        local iniDerecha      = r.rightEdge:GetLeft()
        if not (finSinTemporada and finConTemporada and iniDerecha) then return end
        r.metrics = {
            -- buscador, separadores y las etiquetas MAZMORRA y PERSONAJE
            base       = (finSinTemporada - barLeft)
                         - (r.dungeon.frame:GetWidth() or r.dungeon.pref)
                         - (r.char.frame:GetWidth()    or r.char.pref),
            temporadaW = finConTemporada - finSinTemporada,
            -- etiqueta ORDENAR, su separador y el margen derecho
            ordenExtra = barW - (iniDerecha - barLeft)
                         - (r.order.frame:GetWidth() or r.order.pref),
        }
    end

    local m = r.metrics

    -- El reparto en sí es aritmética pura y vive en Widgets:SplitRow, donde
    -- se puede probar sin abrir el juego. Aquí solo se le dan los números y
    -- se aplican los anchos que devuelve.
    --
    -- Orden de prioridad: MAZMORRA primero (los nombres largos viven ahí) y
    -- PERSONAJE después. La TEMPORADA es lo primero que se suelta: en
    -- Historial es una insignia fija que siempre pone "Midnight" y la
    -- temporada ya tiene su propia columna en la tabla.
    local anchos, oW, conTemporada = Widgets:SplitRow({
        total     = barW,
        base      = m.base,
        optional  = m.temporadaW,
        tailExtra = m.ordenExtra,
        gap       = 14,
        tail      = { pref = r.order.pref,   min = r.order.min },
        flex      = { { pref = r.dungeon.pref, min = r.dungeon.min },
                      { pref = r.char.pref,    min = r.char.min } },
    })

    r.dungeon.frame:SetWidth(math.floor(anchos[1] + 0.5))
    r.char.frame:SetWidth(math.floor(anchos[2] + 0.5))
    r.order.frame:SetWidth(math.floor(oW + 0.5))
    r.seasonLabel:SetShown(conTemporada)
    r.seasonBadge:SetShown(conTemporada)
end

function PanelHistorial:CreateSeparator(parent)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetSize(1, 18)
    sep:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(sep, Theme.BORDER.separator)
    return sep
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INFO BAR (M+ Score + key del personaje)
-- ═══════════════════════════════════════════════════════════════════════════

function PanelHistorial:CreateInfoBar(parent)
    local infoBar = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    infoBar:SetPoint("TOPLEFT",  self.filterBar, "BOTTOMLEFT",  0, 0)
    infoBar:SetPoint("TOPRIGHT", self.filterBar, "BOTTOMRIGHT", 0, 0)
    infoBar:SetHeight(32)
    infoBar:SetBackdrop(Theme.BACKDROPS.simple)
    Theme:SetBackdropColor(infoBar, { r = 0.067, g = 0.055, b = 0.102, a = 1.0 })

    local sep = infoBar:CreateTexture(nil, "BORDER")
    sep:SetPoint("BOTTOMLEFT",  infoBar, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", infoBar, "BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)
    sep:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(sep, Theme.BORDER.separator)

    -- ── M+ Score (izquierda) ─────────────────────────────────────────────
    local scoreLabel = infoBar:CreateFontString(nil, "OVERLAY")
    scoreLabel:SetPoint("LEFT", infoBar, "LEFT", 16, 0)
    Theme:ApplyFont(scoreLabel, "mono", 13)
    scoreLabel:SetText("|cFFc17cffM+|r  Puntaje:")
    Theme:SetTextColor(scoreLabel, Theme.TEXT.dim)

    local scoreValue = infoBar:CreateFontString(nil, "OVERLAY")
    scoreValue:SetPoint("LEFT", scoreLabel, "RIGHT", 6, 0)
    Theme:ApplyFont(scoreValue, "mono", 15)
    scoreValue:SetText("—")
    Theme:SetTextColor(scoreValue, Theme.GOLD.gold4)
    self._mplusScoreText = scoreValue

    -- Key en mochila
    local keyLabel = infoBar:CreateFontString(nil, "OVERLAY")
    keyLabel:SetPoint("LEFT", scoreValue, "RIGHT", 18, 0)
    Theme:ApplyFont(keyLabel, "mono", 12)
    keyLabel:SetText("")
    Theme:SetTextColor(keyLabel, Theme.GOLD.gold3)
    self._keystoneText = keyLabel

    self.infoBar = infoBar
    self:UpdateMPlusScore()
    -- Registrar evento para actualizar la key cuando cambia el inventario
    if infoBar.RegisterEvent then
        infoBar:RegisterEvent("PLAYER_ENTERING_WORLD")
        infoBar:RegisterEvent("BAG_UPDATE")
        infoBar:SetScript("OnEvent", function()
            if MitzuMPlus.PanelHistorial and MitzuMPlus.PanelHistorial.UpdateMPlusScore then
                MitzuMPlus.PanelHistorial:UpdateMPlusScore()
            end
        end)
    end
    return infoBar
end

function PanelHistorial:UpdateMPlusScore()
    if not self._mplusScoreText then return end
    local score = 0
    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, "player")
        if ok and type(summary) == "table" then
            score = tonumber(summary.currentSeasonScore) or 0
        end
    end
    -- Fallback: usar el más alto de las runs guardadas
    if score == 0 then
        local runs = (MitzuMPlus.GetAllRuns and MitzuMPlus:GetAllRuns()) or {}
        for _, r in ipairs(runs) do
            local rs = tonumber(r.playerMythicRating) or 0
            if rs > score then score = rs end
        end
    end
    if score > 0 then
        self._mplusScoreText:SetText(tostring(score))
        Theme:SetTextColor(self._mplusScoreText, Theme.GOLD.gold4)
    else
        self._mplusScoreText:SetText("Sin datos")
        Theme:SetTextColor(self._mplusScoreText, Theme.TEXT.dim)
    end

    -- Key en mochila: escanear bolsas buscando el link |Hkeystone:MAPID:LEVEL|h[Nombre]|h
    -- Este método funciona en todas las versiones (Dragonflight, Midnight 12.0+) y
    -- devuelve el nombre en el idioma del cliente sin depender de C_ChallengeMode.GetMapUIInfo.
    if self._keystoneText then
        local dungeonName, keystoneLevel = nil, nil

        local getSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
        local getLink  = (C_Container and C_Container.GetContainerItemLink)  or GetContainerItemLink

        if getSlots and getLink then
            for bag = 0, 4 do
                local slots = getSlots(bag) or 0
                for slot = 1, slots do
                    local link = getLink(bag, slot)
                    if link and link:find("|Hkeystone:", 1, true) then
                        -- Extraer nivel del link: |Hkeystone:MAPID:LEVEL:...|h
                        local lvl = link:match("|Hkeystone:%d+:(%d+)")
                        -- Extraer nombre del link: entre [ y ] al final
                        local fullName = link:match("%[(.-)%]")
                        if fullName and lvl then
                            keystoneLevel = tonumber(lvl)
                            -- Quitar prefijo localizado "Xxxx xxxx: " (p.ej. "Piedra angular: " / "Mythic Keystone: ")
                            dungeonName = fullName:match("^[^:]+:%s*(.+)$") or fullName
                        end
                        break
                    end
                end
                if dungeonName then break end
            end
        end

        -- Fallback: usar C_MythicPlus APIs si el bag scan no encontró nada
        if not dungeonName then
            local keyMapID = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneMapID and C_MythicPlus.GetOwnedKeystoneMapID()
            keystoneLevel  = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
            if keyMapID and keyMapID > 0 then
                if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
                    local ok, n = pcall(C_ChallengeMode.GetMapUIInfo, keyMapID)
                    if ok and n and n ~= "" then dungeonName = n end
                end
            end
        end

        if dungeonName and keystoneLevel and keystoneLevel > 0 then
            self._keystoneText:SetText(string.format("|cFF888888Mochila:|r %s |cFFFFD700+%d|r", dungeonName, keystoneLevel))
        elseif keystoneLevel and keystoneLevel > 0 then
            self._keystoneText:SetText(string.format("|cFF888888Mochila:|r Key |cFFFFD700+%d|r", keystoneLevel))
        else
            self._keystoneText:SetText("|cFF555555Sin llave en mochila|r")
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SUMMARY BAR
-- ═══════════════════════════════════════════════════════════════════════════

function PanelHistorial:CreateSummaryBar(parent)
    local summaryBar = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    summaryBar:SetPoint("TOPLEFT",  self.infoBar or self.filterBar, "BOTTOMLEFT",  0, 0)
    summaryBar:SetPoint("TOPRIGHT", self.infoBar or self.filterBar, "BOTTOMRIGHT", 0, 0)
    summaryBar:SetHeight(34)

    summaryBar:SetBackdrop(Theme.BACKDROPS.simple)
    Theme:SetBackdropColor(summaryBar, { r = 0.039, g = 0.039, b = 0.071, a = 1.0 })

    local bottomBorder = summaryBar:CreateTexture(nil, "BORDER")
    bottomBorder:SetPoint("BOTTOMLEFT",  summaryBar, "BOTTOMLEFT",  0, 0)
    bottomBorder:SetPoint("BOTTOMRIGHT", summaryBar, "BOTTOMRIGHT", 0, 0)
    bottomBorder:SetHeight(1)
    bottomBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(bottomBorder, Theme.BORDER.separator)

    -- ✅ FIX: cada item se posiciona usando SetPoint("LEFT", summaryBar) con
    --    un offset calculado en tiempo real cuando el bar tiene su ancho definitivo.
    --    Así nunca hay solapamiento independientemente del ancho de la barra.
    local NUM_ITEMS = 6
    local items = {}

    local SUMMARY_TOOLTIPS = {
        ["Mostrando"]       = "Número de runs actualmente mostradas tras aplicar los filtros.",
        ["En tiempo"]       = "Runs completadas dentro del tiempo límite de la llave.",
        ["Fuera de tiempo"] = "Runs terminadas fuera del tiempo límite (aún cuentan, pero no dan +).",
        ["DPS promedio"]    = "Promedio de daño por segundo de las runs filtradas (damageTotal/tiempo).",
        ["Muertes total"]   = "Suma total de muertes del grupo en las runs filtradas.",
        ["Kicks total"]     = "Total de interrupciones realizadas por el grupo.",
    }

    local function CreateSummaryItem(labelText, valueText, valueColor)
        local item = CreateFrame("Frame", nil, summaryBar)
        item:SetHeight(26)
        -- Ancho inicial; se recalculará en RepositionSummaryItems
        item:SetWidth(140)
        item:EnableMouse(true)
        item._labelText = labelText

        local dot = item:CreateTexture(nil, "OVERLAY")
        dot:SetPoint("LEFT", item, "LEFT", 0, 0)
        dot:SetSize(6, 6)
        dot:SetTexture("Interface\\Buttons\\WHITE8X8")

        local label = item:CreateFontString(nil, "OVERLAY")
        label:SetPoint("LEFT", dot, "RIGHT", 5, 0)
        Theme:ApplyFont(label, "mono", 13)
        label:SetText(labelText .. ":")
        Theme:SetTextColor(label, Theme.TEXT.dim)

        local value = item:CreateFontString(nil, "OVERLAY")
        value:SetPoint("LEFT", label, "RIGHT", 4, 0)
        Theme:ApplyFont(value, "mono", 13)
        value:SetText(valueText)

        -- ── Barra de progreso en el fondo (premium) ──────────────────────────
        local barBg = item:CreateTexture(nil, "BACKGROUND")
        barBg:SetPoint("BOTTOMLEFT",  item, "BOTTOMLEFT",  0,  0)
        barBg:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 0,  0)
        barBg:SetHeight(2)
        barBg:SetTexture("Interface\\Buttons\\WHITE8X8")
        barBg:SetVertexColor(0.067, 0.067, 0.125, 1)  -- oscuro base

        local barFill = item:CreateTexture(nil, "ARTWORK")
        barFill:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, 0)
        barFill:SetHeight(2)
        barFill:SetWidth(2)
        barFill:SetTexture("Interface\\Buttons\\WHITE8X8")
        item.barFill = barFill

        -- Actualizar ancho de la barra (llamar tras conocer el ancho del item)
        function item:SetBarPercent(percent)
            local w = self:GetWidth()
            if w and w > 4 then
                local fillW = math.max(2, math.floor(w * math.min(1.0, percent)))
                self.barFill:SetWidth(fillW)
            end
        end

        if valueColor == "ok" then
            Theme:SetVertexColor(dot, Theme.STATUS.ok)
            Theme:SetTextColor(value, Theme.STATUS.ok)
            barFill:SetVertexColor(Theme.STATUS.ok.r,  Theme.STATUS.ok.g,  Theme.STATUS.ok.b,  0.8)
        elseif valueColor == "bad" then
            Theme:SetVertexColor(dot, Theme.STATUS.bad)
            Theme:SetTextColor(value, Theme.STATUS.bad)
            barFill:SetVertexColor(Theme.STATUS.bad.r, Theme.STATUS.bad.g, Theme.STATUS.bad.b, 0.8)
        elseif valueColor == "gold" then
            Theme:SetVertexColor(dot, Theme.GOLD.gold3)
            Theme:SetTextColor(value, Theme.GOLD.gold4)
            barFill:SetVertexColor(Theme.GOLD.gold3.r, Theme.GOLD.gold3.g, Theme.GOLD.gold3.b, 0.8)
        elseif valueColor == "info" then
            Theme:SetVertexColor(dot, Theme.STATUS.info)
            Theme:SetTextColor(value, Theme.STATUS.info)
            barFill:SetVertexColor(Theme.STATUS.info.r, Theme.STATUS.info.g, Theme.STATUS.info.b, 0.8)
        elseif valueColor == "purple" then
            Theme:SetVertexColor(dot, Theme.STATUS.purple)
            Theme:SetTextColor(value, Theme.STATUS.purple)
            barFill:SetVertexColor(Theme.STATUS.purple.r, Theme.STATUS.purple.g, Theme.STATUS.purple.b, 0.8)
        else
            Theme:SetVertexColor(dot, Theme.TEXT.tertiary)
            Theme:SetTextColor(value, Theme.TEXT.primary)
            barFill:SetVertexColor(Theme.TEXT.tertiary.r, Theme.TEXT.tertiary.g, Theme.TEXT.tertiary.b, 0.6)
        end

        item.dot   = dot
        item.label = label
        item.value = value

        -- Tooltip informativo explicando qué representa cada métrica.
        item:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(self._labelText or "Resumen", 1, 0.8, 0.2)
            local desc = SUMMARY_TOOLTIPS[self._labelText]
            if desc then
                GameTooltip:AddLine(desc, 0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        end)
        item:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        return item
    end

    self.summaryItems = {}
    self.summaryItems.showing  = CreateSummaryItem("Mostrando",       "0 runs", "normal")
    self.summaryItems.inTime   = CreateSummaryItem("En tiempo",       "0",      "ok")
    self.summaryItems.outTime  = CreateSummaryItem("Fuera de tiempo", "0",      "bad")
    self.summaryItems.avgDps   = CreateSummaryItem("DPS promedio",    "0k",     "gold")
    self.summaryItems.deaths   = CreateSummaryItem("Muertes total",   "0",      "info")
    self.summaryItems.kicks    = CreateSummaryItem("Kicks total",     "0",      "purple")

    items = {
        self.summaryItems.showing,
        self.summaryItems.inTime,
        self.summaryItems.outTime,
        self.summaryItems.avgDps,
        self.summaryItems.deaths,
        self.summaryItems.kicks,
    }

    -- ✅ Distribuir items equitativamente cuando el bar tenga su ancho real
    local function RepositionSummaryItems()
        local barW = summaryBar:GetWidth()
        if not barW or barW < 10 then return end
        local step = math.floor(barW / NUM_ITEMS)
        for i, item in ipairs(items) do
            item:ClearAllPoints()
            item:SetWidth(step - 4)
            item:SetPoint("LEFT", summaryBar, "LEFT", (i - 1) * step + 6, 0)
        end
    end

    summaryBar:SetScript("OnSizeChanged", function() RepositionSummaryItems() end)
    summaryBar:SetScript("OnShow",        function() RepositionSummaryItems() end)

    -- Primera pasada (el frame puede no tener ancho aún, pero es seguro)
    RepositionSummaryItems()

    self.summaryBar = summaryBar
    return summaryBar
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE
-- ═══════════════════════════════════════════════════════════════════════════

-- Hueco que se le deja a la barra de desplazamiento en el borde derecho.
local SCROLLBAR_GUTTER = 8

function PanelHistorial:CreateTable(parent)
    local tableContainer = CreateFrame("Frame", nil, parent)
    tableContainer:SetPoint("TOPLEFT", self.archiveBar, "BOTTOMLEFT", 0, 0)
    tableContainer:SetPoint("TOPRIGHT", self.archiveBar, "BOTTOMRIGHT", 0, 0)
    tableContainer:SetPoint("BOTTOM", parent, "BOTTOM", 0, 42)
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, tableContainer)
    scrollFrame:SetAllPoints(tableContainer)
    scrollFrame:EnableMouseWheel(true)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetHeight(1)
    -- El ancho se ajusta dinámicamente con OnSizeChanged
    
    local tableHeader = self:CreateTableHeader(scrollChild)
    tableHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    tableHeader:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, 0)
    
    self.tableRows = {}
    
    for i = 1, 20 do
        local row = self:CreateTableRow(scrollChild, i)
        if i == 1 then
            row:SetPoint("TOPLEFT", tableHeader, "BOTTOMLEFT", 0, 0)
            row:SetPoint("TOPRIGHT", tableHeader, "BOTTOMRIGHT", 0, 0)
        else
            row:SetPoint("TOPLEFT", self.tableRows[i-1], "BOTTOMLEFT", 0, 0)
            row:SetPoint("TOPRIGHT", self.tableRows[i-1], "BOTTOMRIGHT", 0, 0)
        end
        row:Hide()
        self.tableRows[i] = row
    end
    local tableContentHeight=36+(#self.tableRows*32)
    scrollChild:SetHeight(tableContentHeight)
    
    local scrollBar = CreateFrame("Slider", nil, scrollFrame, BackdropTemplateMixin and "BackdropTemplate")
    scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -2, -2)
    scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -2, 2)
    scrollBar:SetWidth(4)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetMinMaxValues(0, 100)
    scrollBar:SetValue(0)
    scrollBar:SetBackdrop(Theme.BACKDROPS.simple)
    Theme:SetBackdropColor(scrollBar, Theme.BG.void)
    
    local thumbTexture = scrollBar:CreateTexture(nil, "OVERLAY")
    thumbTexture:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumbTexture:SetSize(4, 40)
    Theme:SetVertexColor(thumbTexture, Theme.GOLD.gold1)
    scrollBar:SetThumbTexture(thumbTexture)
    
    scrollBar:SetScript("OnValueChanged", function(self, value)
        scrollFrame:SetVerticalScroll(value)
    end)
    
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = scrollBar:GetValue()
        local minVal, maxVal = scrollBar:GetMinMaxValues()
        local newVal = math.max(minVal, math.min(maxVal, current - (delta * 30)))
        scrollBar:SetValue(newVal)
    end)
    
    self.tableContainer = tableContainer
    self.scrollFrame = scrollFrame
    self.scrollChild = scrollChild
    self.scrollBar = scrollBar
    
    -- Ajuste dinámico al redimensionar
    scrollFrame:SetScript("OnSizeChanged", function(self, w, h)
        scrollChild:SetWidth(w)
        local maxScroll=math.max(0,tableContentHeight-(h or 0))
        scrollBar:SetMinMaxValues(0,maxScroll)
        if scrollBar:GetValue()>maxScroll then scrollBar:SetValue(maxScroll) end
        if w > 50 then
            -- La barra de desplazamiento vive en el borde derecho: si las
            -- columnas llegan hasta ahi, la ultima queda debajo de ella.
            PanelHistorial:ResizeColumns(w - SCROLLBAR_GUTTER)
        end
    end)

    -- También disparar cuando el panel se muestre por primera vez
    tableContainer:SetScript("OnShow", function(self)
        local w = scrollFrame:GetWidth()
        if w > 50 then
            scrollChild:SetWidth(w)
            PanelHistorial:ResizeColumns(w - SCROLLBAR_GUTTER)
        end
    end)
    self.tableHeader = tableHeader
    
    return tableContainer
end

function PanelHistorial:CreateTableHeader(parent)
    local header = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    header:SetHeight(36)
    header:SetBackdrop(Theme.BACKDROPS.simple)
    Theme:SetBackdropColor(header, Theme.BG.titlebar)
    
    local bottomBorder = header:CreateTexture(nil, "BORDER")
    bottomBorder:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    bottomBorder:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    bottomBorder:SetHeight(1)
    bottomBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(bottomBorder, Theme.GOLD.gold0)
    
    local columns = {
        { key = "favorite", text = "FAV.", width = 42 },
        { key = "dungeon", text = "MAZMORRA", width = 140 },
        { key = "level", text = "NIVEL", width = 50 },
        { key = "season", text = "TEMPORADA", width = 100 },
        { key = "result", text = "RESULTADO", width = 110 },
        { key = "margin", text = "MARGEN", width = 70 },
        { key = "character", text = "PERSONAJE", width = 105 },
        { key = "role", text = "ROL", width = 55 },
        { key = "quality", text = "DATOS", width = 70 },
        { key = "notes", text = "NOTA", width = 55 },
        { key = "tags", text = "ETIQUETA", width = 90 },
        { key = "group", text = "GRUPO", width = 90 },
        { key = "date", text = "FECHA", width = 90 },
        { key = "actions", text = "", width = 30 },
    }
    
    local xOffset = 0
    header.columns = {}
    
    for i, col in ipairs(columns) do
        local colHeader = CreateFrame("Button", nil, header)
        -- Sin SetPoint ni SetSize fijo — ResizeColumns lo hará dinámicamente
        colHeader:SetHeight(32)
        
        -- Sin iconos TGA (no siempre renderizan): usamos solo texto.
        -- Columnas numéricas se centran; las demás quedan a la izquierda.
        local isNumeric = (col.key == "margin" or col.key == "level" or col.key == "favorite")

        local colText = colHeader:CreateFontString(nil, "OVERLAY")
        colText:SetWordWrap(false)
        colText:SetNonSpaceWrap(false)
        if colText.SetMaxLines then colText:SetMaxLines(1) end
        Theme:ApplyFont(colText, "mono", 12)
        colText:SetText(col.text)
        Theme:SetTextColor(colText, Theme.GOLD.gold3)
        if isNumeric then
            colText:SetPoint("LEFT",  colHeader, "LEFT",  4, 0)
            colText:SetPoint("RIGHT", colHeader, "RIGHT", -4, 0)
            colText:SetJustifyH("CENTER")
        else
            colText:SetPoint("LEFT", colHeader, "LEFT", 10, 0)
            colText:SetPoint("RIGHT",colHeader,"RIGHT",-6,0)
            colText:SetJustifyH("LEFT")
        end
        
        local rightBorder = colHeader:CreateTexture(nil, "BORDER")
        rightBorder:SetPoint("TOPRIGHT", colHeader, "TOPRIGHT", 0, 0)
        rightBorder:SetPoint("BOTTOMRIGHT", colHeader, "BOTTOMRIGHT", 0, 0)
        rightBorder:SetWidth(1)
        rightBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
        Theme:SetVertexColor(rightBorder, Theme.BORDER.separator)
        
        colHeader.text = colText
        colHeader.key = col.key
        
        if col.key ~= "actions" then
            colHeader:SetScript("OnClick", function()
                if self.sortColumn == col.key then
                    self.sortDescending = not self.sortDescending
                else
                    self.sortColumn = col.key
                    self.sortDescending = true
                end
                self:ApplyFilters()
            end)

            -- Fase 3.2 — Tooltips descriptivos en columnas
            local COL_TOOLTIPS = {
                favorite= {"Favorita", "Una estrella encendida identifica una partida favorita"},
                dungeon = {"Mazmorra", "Nombre del dungeon Mythic+"},
                level   = {"Nivel de llave", "Nivel del Mythic+ completado (ej: +10)"},
                season  = {"Temporada", "Temporada guardada en la run; nunca se infiere para runs históricas"},
                result  = {"Resultado", "Si la run se completó dentro del tiempo límite"},
                margin  = {"Margen", "Diferencia entre límite guardado y duración; positivo entró en tiempo"},
                character={"Personaje", "Personaje con el que se registró la run"},
                role    = {"Rol", "Rol del personaje en esa run"},
                quality = {"Calidad de datos", "Completa, parcial, estructural o incompleta"},
                notes   = {"Nota", "Indica si la run tiene una nota guardada"},
                tags    = {"Etiquetas", "Etiquetas operativas de la run"},
                group   = {"Grupo", "Composición del grupo (clase y rol de cada miembro)"},
                date    = {"Fecha", "Fecha y hora en que comenzó la run"},
            }
            local tip = COL_TOOLTIPS[col.key]
            colHeader:SetScript("OnEnter", function(self)
                Theme:SetTextColor(self.text, Theme.GOLD.gold5)
                if tip then
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                    GameTooltip:SetText(tip[1], 1, 0.8, 0.2)
                    GameTooltip:AddLine(tip[2], 0.75, 0.75, 0.75, true)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Clic para ordenar por esta columna", 0.5, 0.5, 0.5, true)
                    GameTooltip:Show()
                end
            end)
            colHeader:SetScript("OnLeave", function(self)
                Theme:SetTextColor(self.text, Theme.GOLD.gold3)
                GameTooltip:Hide()
            end)
        end
        
        header.columns[col.key] = colHeader
    end
    
    return header
end

function PanelHistorial:CreateTableRow(parent, index)
    local row = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    row:SetHeight(32)
    row:SetBackdrop(Theme.BACKDROPS.simple)
    
    if index % 2 == 1 then
        Theme:SetBackdropColor(row, Theme.BG.rowOdd)
    else
        Theme:SetBackdropColor(row, Theme.BG.rowEven)
    end
    
    local bottomBorder = row:CreateTexture(nil, "BORDER")
    bottomBorder:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    bottomBorder:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    bottomBorder:SetHeight(1)
    bottomBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(bottomBorder, Theme.BORDER.panel)
    
    row.cells = {}

    -- Favorito se expresa como estrella nativa, no como combinaciones "x*".
    -- La selección ya queda inequívoca por el fondo dorado de la fila.
    local favoriteIcon = row:CreateTexture(nil, "OVERLAY")
    favoriteIcon:SetSize(17, 17)
    favoriteIcon:SetTexture("Interface\\COMMON\\ReputationStar")
    favoriteIcon:SetVertexColor(Theme.GOLD.gold4.r,Theme.GOLD.gold4.g,Theme.GOLD.gold4.b,1)
    row.favoriteIcon = favoriteIcon

    local favoriteTipFrame = CreateFrame("Frame", nil, row)
    favoriteTipFrame:SetSize(24, 24)
    favoriteTipFrame:EnableMouse(true)
    favoriteTipFrame:SetScript("OnEnter", function(self)
        if not row.runData or not GameTooltip then return end
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:SetText(row.runData.isFavorite and "Partida favorita" or "No marcada como favorita",1,.8,.2)
        GameTooltip:AddLine("Selecciona la fila y usa Favorita para cambiarla.",.75,.75,.75,true)
        GameTooltip:Show()
    end)
    favoriteTipFrame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    favoriteTipFrame:SetScript("OnMouseDown",function(_,button) if button=="LeftButton" then PanelHistorial:SelectRow(row) end end)
    row.favoriteTipFrame = favoriteTipFrame
    
    -- ── Acento lateral dorado (aparece en hover) ─────────────────────────────
    -- 3 texturas para simular gradiente vertical: transparente → dorado → transparente
    local accentTop = row:CreateTexture(nil, "OVERLAY")
    accentTop:SetPoint("TOPLEFT",    row, "TOPLEFT", 0,  0)
    accentTop:SetSize(2, 8)
    accentTop:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetGradientH(accentTop,
        0, 0, 0, 0,
        Theme.GOLD.gold3.r, Theme.GOLD.gold3.g, Theme.GOLD.gold3.b, 0)
    -- Usamos SetGradientH (horizontal), pero para vertical necesitamos SetGradientV
    -- Workaround: usar un degradado de alpha vertical con textura rotada no es posible,
    -- así que simplemente usamos 3 texturas de altura proporcional con alphas distintos
    accentTop:SetAlpha(0.4)
    accentTop:Hide()

    local accentMid = row:CreateTexture(nil, "OVERLAY")
    accentMid:SetPoint("TOPLEFT",    accentTop, "BOTTOMLEFT", 0,  0)
    accentMid:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 8)
    accentMid:SetWidth(2)
    accentMid:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(accentMid, Theme.GOLD.gold3)
    accentMid:Hide()

    local accentBot = row:CreateTexture(nil, "OVERLAY")
    accentBot:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    accentBot:SetSize(2, 8)
    accentBot:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(accentBot, Theme.GOLD.gold3)
    accentBot:SetAlpha(0.4)
    accentBot:Hide()

    row.accentTop = accentTop
    row.accentMid = accentMid
    row.accentBot = accentBot

    -- ── Spec icon (antes del nombre de mazmorra, col 2) ──────────────────────
    local specIcon = row:CreateTexture(nil, "OVERLAY")
    specIcon:SetSize(18, 18)
    specIcon:SetTexture(SPEC_ICON.DAMAGER)  -- default; se sobreescribe en PopulateRow
    specIcon:SetAlpha(0.85)
    specIcon:Hide()
    row.specIcon = specIcon

    -- Rol: icono oficial de Blizzard y zona de tooltip accesible.
    local roleIcon = row:CreateTexture(nil, "OVERLAY")
    roleIcon:SetSize(20, 20)
    SetNativeRoleIcon(roleIcon,"DAMAGER")
    row.roleIcon = roleIcon

    local roleTipFrame = CreateFrame("Frame", nil, row)
    roleTipFrame:SetSize(28, 26)
    roleTipFrame:EnableMouse(true)
    roleTipFrame:SetScript("OnEnter", function(self)
        if not row.runData or not GameTooltip then return end
        local role = row._displayRole or "DAMAGER"
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:SetText("Rol: " .. (ROLE_LABEL[role] or "DPS"),1,.8,.2)
        GameTooltip:Show()
    end)
    roleTipFrame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    roleTipFrame:SetScript("OnMouseDown",function(_,button) if button=="LeftButton" then PanelHistorial:SelectRow(row) end end)
    row.roleTipFrame = roleTipFrame

    -- ── Record badge (sobre el nivel, col 3) ─────────────────────────────────
    local recordBadge = row:CreateTexture(nil, "OVERLAY")
    recordBadge:SetSize(14, 14)
    recordBadge:SetTexture(RECORD_ICON)
    recordBadge:Hide()
    row.recordBadge = recordBadge

    -- Fase 3.3 — Tooltip en record badge vía frame invisible encima
    local recordTipFrame = CreateFrame("Frame", nil, row)
    recordTipFrame:SetSize(20, 20)
    recordTipFrame:SetPoint("CENTER", recordBadge, "CENTER", 0, 0)
    recordTipFrame:SetScript("OnEnter", function(self)
        if recordBadge:IsShown() and row.runData then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Récord personal", 1, 0.8, 0.2)
            GameTooltip:AddLine(string.format("Mejor llave completada en %s", row.runData.dungeonName or "esta mazmorra"), 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    recordTipFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.recordTipFrame = recordTipFrame

    -- ── Abandon badge (junto al nombre de mazmorra) ────────────────────────
    local abandonBadge = row:CreateFontString(nil, "OVERLAY")
    Theme:ApplyFont(abandonBadge, "mono", 10)
    abandonBadge:SetText("[!]")
    abandonBadge:SetTextColor(1, 0.35, 0.1, 1)
    abandonBadge:SetPoint("LEFT", row, "LEFT", 0, 0)  -- reposicionado en PopulateRow
    abandonBadge:Hide()
    row.abandonBadge = abandonBadge

    local abandonTipFrame = CreateFrame("Frame", nil, row)
    abandonTipFrame:SetSize(16, 16)
    abandonTipFrame:SetPoint("CENTER", abandonBadge, "CENTER", 0, 0)
    abandonTipFrame:SetScript("OnEnter", function(self)
        if not abandonBadge:IsShown() or not row.runData then return end
        local ab = row.runData.abandoners or {}
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Jugadores que salieron", 1, 0.4, 0.1)
        for _, a in ipairs(ab) do
            local t = string.format("%d:%02d", math.floor((a.leftAt or 0)/60), (a.leftAt or 0)%60)
            local selfMark = a.isSelf and " (tú)" or ""
            GameTooltip:AddLine(string.format("%s  @ %s%s", a.name or "?", t, selfMark), 0.9, 0.7, 0.4, false)
        end
        GameTooltip:Show()
    end)
    abandonTipFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.abandonTipFrame = abandonTipFrame

    -- Keys de columna en el mismo orden que COLUMN_ORDER
    local CELL_KEYS = {
        "favorite","dungeon","level","season","result",
        "margin","character","role","quality","notes","tags","group","date","actions"
    }
    local NUMERIC = {
        favorite=true, level=true, margin=true, actions=true,
    }
    for i = 1, 14 do
        local cell = row:CreateFontString(nil, "OVERLAY")
        cell:SetWordWrap(false)
        cell:SetNonSpaceWrap(false)
        if cell.SetMaxLines then cell:SetMaxLines(1) end
        Theme:ApplyFont(cell, "mono", 14)
        Theme:SetTextColor(cell, Theme.TEXT.secondary)
        if NUMERIC[CELL_KEYS[i]] then
            cell:SetJustifyH("CENTER")
        else
            cell:SetJustifyH("LEFT")
        end
        row.cells[i] = cell
    end

    -- ── Member dots (5 pastillas de clase+rol) ────────────────────────────────
    row.memberDots = {}
    for m = 1, 5 do
        local dot = CreateFrame("Frame", nil, row, BackdropTemplateMixin and "BackdropTemplate")
        dot:SetSize(14, 16)
        dot:SetBackdrop(Theme.BACKDROPS.panel)
        Theme:SetBackdropColor(dot, Theme.BG.button)
        Theme:SetBackdropBorderColor(dot, Theme.BORDER.panel)

        local dotText = dot:CreateFontString(nil, "OVERLAY")
        dotText:SetPoint("CENTER")
        Theme:ApplyFont(dotText, "mono", 9)
        dotText:SetText("?")
        Theme:SetTextColor(dotText, Theme.TEXT.dim)

        dot.label = dotText
        dot:Hide()
        row.memberDots[m] = dot
    end
    
    -- Highlight overlay para fade suave (Fase 4.3)
    local hoverOverlay = row:CreateTexture(nil, "BACKGROUND")
    hoverOverlay:SetAllPoints(row)
    hoverOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    hoverOverlay:SetVertexColor(
        Theme.BG.rowHover.r, Theme.BG.rowHover.g, Theme.BG.rowHover.b,
        Theme.BG.rowHover.a or 0.15)
    hoverOverlay:SetAlpha(0)
    row.hoverOverlay = hoverOverlay

    row.index    = index
    row.rowIndex = index

    row:SetScript("OnEnter", function(self)
        if not self.selected then
            UIFrameFadeIn(self.hoverOverlay, 0.08, self.hoverOverlay:GetAlpha(), 1)
        end
        if self.accentTop then self.accentTop:Show() end
        if self.accentMid then self.accentMid:Show() end
        if self.accentBot then self.accentBot:Show() end
        if self.runData and GameTooltip then
            GameTooltip:SetOwner(self,"ANCHOR_TOP")
            GameTooltip:SetText(string.format("%s +%d",self.runData.dungeonName or "Run",tonumber(self.runData.keyLevel) or 0),1,.82,.2)
            local _,seasonName=MitzuMPlus.RunMetrics:GetSeason(self.runData)
            GameTooltip:AddLine(string.format("%s · %s",self.runData.playerName or "Sin personaje",seasonName or "Midnight"),.78,.78,.78,true)
            if type(self.runData.tags)=="table" and #self.runData.tags>0 then
                GameTooltip:AddLine("Etiqueta: "..table.concat(self.runData.tags,", "),.85,.72,.35,true)
            end
            if tostring(self.runData.notes or "")~="" then
                GameTooltip:AddLine("Nota: "..tostring(self.runData.notes),.75,.75,.75,true)
            end
            GameTooltip:AddLine(self.selected and "Seleccionada" or "No seleccionada",self.selected and .3 or .7,self.selected and .85 or .7,self.selected and 1 or .7)
            GameTooltip:AddLine("Clic: seleccionar · Ctrl+clic: selección múltiple",.75,.75,.75,true)
            GameTooltip:Show()
        end
    end)

    row:SetScript("OnLeave", function(self)
        if not self.selected then
            UIFrameFadeOut(self.hoverOverlay, 0.12, self.hoverOverlay:GetAlpha(), 0)
        end
        if self.accentTop then self.accentTop:Hide() end
        if self.accentMid then self.accentMid:Hide() end
        if self.accentBot then self.accentBot:Hide() end
        if GameTooltip then GameTooltip:Hide() end
    end)

    row:SetScript("OnClick", function(self)
        PanelHistorial:SelectRow(self)
    end)

    return row
end

function PanelHistorial:SelectRow(row)
    local id=row.runData and tonumber(row.runData.runID) or nil
    self.selectedRunIDs=self.selectedRunIDs or {}
    local multi=IsControlKeyDown and IsControlKeyDown()
    if multi and id then
        if self.selectedRunIDs[id] then self.selectedRunIDs[id]=nil else self.selectedRunIDs[id]=true end
    else
        wipe(self.selectedRunIDs)
        if id then self.selectedRunIDs[id]=true end
    end
    self.selectedRunID=id
    for _, r in ipairs(self.tableRows) do
        local rowID=r.runData and tonumber(r.runData.runID)
        r.selected = rowID and self.selectedRunIDs[rowID] or false
        if r.rowIndex % 2 == 1 then
            Theme:SetBackdropColor(r, Theme.BG.rowOdd)
        else
            Theme:SetBackdropColor(r, Theme.BG.rowEven)
        end
        if r.selected then Theme:SetBackdropColor(r,Theme.BG.rowSel) end
    end
    if multi and id and not self.selectedRunIDs[id] then
        self.selectedRunID=next(self.selectedRunIDs)
    end
    self.selectedRunIndex = nil -- compatibilidad: ya no se usa un índice filtrado inestable
    self:UpdateArchiveBar()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PAGINATION
-- ═══════════════════════════════════════════════════════════════════════════

function PanelHistorial:CreatePagination(parent)
    local pagination = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    pagination:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    pagination:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    pagination:SetHeight(42)
    
    pagination:SetBackdrop(Theme.BACKDROPS.simple)
    Theme:SetBackdropColor(pagination, Theme.BG.titlebar)
    
    local topBorder = pagination:CreateTexture(nil, "BORDER")
    topBorder:SetPoint("TOPLEFT", pagination, "TOPLEFT", 0, 0)
    topBorder:SetPoint("TOPRIGHT", pagination, "TOPRIGHT", 0, 0)
    topBorder:SetHeight(1)
    topBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(topBorder, Theme.GOLD.gold0)
    
    local pageInfo = pagination:CreateFontString(nil, "OVERLAY")
    pageInfo:SetPoint("LEFT", pagination, "LEFT", 12, 0)
    Theme:ApplyFont(pageInfo, "mono", 13)
    pageInfo:SetText("Página 1 de 1 · 0 runs totales")
    Theme:SetTextColor(pageInfo, Theme.TEXT.dim)
    self.pageInfo = pageInfo
    
    local prevBtn = Widgets:CreateButton(pagination, "«", 30, 24, "normal")
    prevBtn:SetPoint("LEFT", pageInfo, "RIGHT", 12, 0)
    prevBtn:SetScript("OnClick", function()
        if self.currentPage > 1 then
            self.currentPage = self.currentPage - 1
            self:RefreshTable()
        end
    end)
    self.prevBtn = prevBtn
    
    self.pageButtons = {}
    
    for i = 1, 5 do
        local pageBtn = Widgets:CreateButton(pagination, tostring(i), 30, 24, "normal")
        if i == 1 then
            pageBtn:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
        else
            pageBtn:SetPoint("LEFT", self.pageButtons[i-1], "RIGHT", 6, 0)
        end
        
        pageBtn.pageNum = i
        pageBtn:SetScript("OnClick", function(self)
            PanelHistorial.currentPage = self.pageNum
            PanelHistorial:RefreshTable()
        end)
        
        self.pageButtons[i] = pageBtn
    end
    
    local nextBtn = Widgets:CreateButton(pagination, "»", 30, 24, "normal")
    nextBtn:SetPoint("LEFT", self.pageButtons[5], "RIGHT", 6, 0)
    nextBtn:SetScript("OnClick", function()
        local totalPages = math.ceil(#self.filteredRuns / self.runsPerPage)
        if self.currentPage < totalPages then
            self.currentPage = self.currentPage + 1
            self:RefreshTable()
        end
    end)
    self.nextBtn = nextBtn
    
    local perPageLabel = pagination:CreateFontString(nil, "OVERLAY")
    perPageLabel:SetPoint("RIGHT", pagination, "RIGHT", -70, 0)
    Theme:ApplyFont(perPageLabel, "mono", 12)
    perPageLabel:SetText("POR PÁGINA")
    Theme:SetTextColor(perPageLabel, Theme.TEXT.dim)
    
    local perPageDropdown = Widgets:CreateDropdown(pagination, 55, {"20", "50", "100"}, 1, function(index, value)
        self.runsPerPage = tonumber(value) or 20
        self.currentPage = 1
        self:RefreshTable()
    end)
    perPageDropdown:SetPoint("RIGHT", pagination, "RIGHT", -8, 0)
    self.perPageDropdown = perPageDropdown
    
    self.pagination = pagination
    
    return pagination
end

-- ═══════════════════════════════════════════════════════════════════════════
-- REFRESH / UPDATE
-- ═══════════════════════════════════════════════════════════════════════════

function PanelHistorial:Refresh()
    if not self.panel then
        return
    end

    self:RefreshSeasonFilter()
    self:ApplyFilters()

    if self.UpdateMPlusScore then
        self:UpdateMPlusScore()
    end

    if MitzuMPlus.Footer and MitzuMPlus.Footer.UpdateStats then
        MitzuMPlus.Footer:UpdateStats()
    end
end

function PanelHistorial:RefreshSeasonFilter()
    self.activeSeasonFilter="MIDNIGHT"
end

-- Helper: anima un FontString de 0 → targetVal en ~0.4s (Fase 4.2)
local function AnimateCounter(fs, targetVal, prefix, suffix)
    prefix = prefix or ""
    suffix = suffix or ""
    if targetVal == 0 then fs:SetText(prefix .. "0" .. suffix); return end
    local steps    = 16
    local interval = 0.4 / steps
    local step     = 0
    if fs._counterTicker then fs._counterTicker:Cancel() end
    fs._counterTicker = C_Timer.NewTicker(interval, function()
        step = step + 1
        local val = math.floor(targetVal * (step / steps))
        fs:SetText(prefix .. tostring(val) .. suffix)
        if step >= steps then
            fs:SetText(prefix .. tostring(targetVal) .. suffix)
            if fs._counterTicker then fs._counterTicker:Cancel(); fs._counterTicker = nil end
        end
    end, steps)
end

function PanelHistorial:UpdateSidebarStats()
    if not self.block1 or not self.block2 or not self.block3 then return end

    local FormattersLocal = MitzuMPlus.Formatters
    if not FormattersLocal then return end

    local runs     = MitzuMPlus:GetAllRuns() or {}
    local total    = #runs
    local inTime   = 0
    local bestKey  = 0
    local totalDPS = 0
    local dpsRunCount = 0

    for _, run in ipairs(runs) do
        if run.inTime then inTime = inTime + 1 end
        if run.keyLevel and run.keyLevel > bestKey then bestKey = run.keyLevel end
        local dmg = run.stats and run.stats.damageTotal or 0
        local ct  = tonumber(run.completionTime) or 0
        if ct > 0 and dmg > 0 then
            totalDPS = totalDPS + (dmg / ct)
            dpsRunCount = dpsRunCount + 1
        end
    end

    local avgDPS      = dpsRunCount > 0 and (totalDPS / dpsRunCount) or 0
    local successRate = total > 0 and ((inTime / total) * 100) or 0

    -- Header labels (sin animación, texto)
    self.block1.header:SetText(string.format(">> RESUMEN GLOBAL (%d)", total))
    self.block2.header:SetText(bestKey > 0 and string.format(">> MEJOR LLAVE (+%d)", bestKey) or ">> MEJOR LLAVE")
    self.block3.header:SetText(string.format(">> DPS PROMEDIO (%s)", F():FormatDPS(avgDPS)))

    -- Animar contadores si animaciones activas (Fase 4.2)
    local animEnabled = MitzuMPlus.db and MitzuMPlus.db.profile and
                        MitzuMPlus.db.profile.settings and
                        MitzuMPlus.db.profile.settings.enableAnimations

    -- Actualizar filas dinámicas del bloque 1
    if self.block1.rows then
        local rows = self.block1.rows
        if rows[1] then
            if animEnabled then
                AnimateCounter(rows[1].valFS, total)
            else
                rows[1].valFS:SetText(tostring(total))
            end
        end
        if rows[2] then
            if animEnabled then
                AnimateCounter(rows[2].valFS, inTime,
                    "", string.format(" (%.0f%%)", successRate))
            else
                rows[2].valFS:SetText(string.format("%d (%.0f%%)", inTime, successRate))
            end
        end
        if rows[3] then
            local out = total - inTime
            if animEnabled then
                AnimateCounter(rows[3].valFS, out,
                    "", string.format(" (%.0f%%)", 100 - successRate))
            else
                rows[3].valFS:SetText(string.format("%d (%.0f%%)", out, 100 - successRate))
            end
        end
    end
end

function PanelHistorial:ApplyFilters()
    -- ✅ FIX HISTORIAL ESTÁTICO: los runs se guardan en db.GLOBAL.runs,
    --    NO en db.profile.runs. Leer la fuente correcta.
    --    Se usa GetAllRuns() que ya los ordena por fecha descendente.
    local runs = MitzuMPlus:GetAllRuns() or {}

    -- Aplicar filtro de búsqueda si existe
    local search = self.activeSearch and self.activeSearch:lower() or ""
    if search ~= "" then
        local filtered = {}
        for _, run in ipairs(runs) do
            local dn = (run.dungeonName or ""):lower()
            if dn:find(search, 1, true) then
                filtered[#filtered + 1] = run
            end
        end
        runs = filtered
    end

    -- Aplicar filtro de mazmorra si existe
    if self.activeDungeon and self.activeDungeon ~= "" then
        local filtered = {}
        for _, run in ipairs(runs) do
            if run.dungeonName == self.activeDungeon then
                filtered[#filtered + 1] = run
            end
        end
        runs = filtered
    end

    -- FIX ALT-1: Aplicar filtro de personaje (alts)
    if self.activeCharFilter and self.activeCharFilter ~= "" then
        local filtered = {}
        for _, run in ipairs(runs) do
            local pn = run.playerName or ""
            local pr = run.playerRealm or ""
            local key = pn
            if pr ~= "" then key = pn .. " - " .. pr end
            if key == self.activeCharFilter then
                filtered[#filtered + 1] = run
            end
        end
        runs = filtered
    end

    if self.activeSeasonFilter=="MIDNIGHT" then
        local filtered={}
        for _,run in ipairs(runs) do
            if IsMidnightRun(run) then filtered[#filtered+1]=run end
        end
        runs=filtered
    end

    if self.activeRoleFilter and self.activeRoleFilter~="ALL" then
        local filtered={}
        for _,run in ipairs(runs) do
            local role=MitzuMPlus.RunMetrics:GetRole(run)
            if role==self.activeRoleFilter then filtered[#filtered+1]=run end
        end
        runs=filtered
    end

    if self.activeQualityFilter and self.activeQualityFilter~="ALL" then
        local filtered={}
        for _,run in ipairs(runs) do
            local quality=MitzuMPlus.RunMetrics:GetQuality(run)
            if quality==self.activeQualityFilter then filtered[#filtered+1]=run end
        end
        runs=filtered
    end

    -- ✅ CORRECCIÓN: Aplicar filtro de semana
    if self.activeWeekFilter and self.activeWeekFilter > 1 then
        local filtered = {}
        local currentTime = time()
        -- BUG-C1 FIX: run.startTime (run.timestamp siempre era nil → filtro de semana roto)
        for _, run in ipairs(runs) do
            if run.startTime then
                local ageDays = (currentTime - run.startTime) / 86400
                if self.activeWeekFilter == 2 and ageDays <= 7 then  -- Esta semana
                    filtered[#filtered + 1] = run
                elseif self.activeWeekFilter == 3 and ageDays > 7 and ageDays <= 14 then  -- Semana pasada
                    filtered[#filtered + 1] = run
                elseif self.activeWeekFilter == 4 then  -- Todo (no filtrar)
                    filtered[#filtered + 1] = run
                end
            end
        end
        runs = filtered
    end

    -- ✅ CORRECCIÓN: Aplicar filtro de resultado
    if self.activeResultFilter and self.activeResultFilter > 1 then
        local filtered = {}
        for _, run in ipairs(runs) do
            if self.activeResultFilter == 2 and run.inTime then  -- En tiempo
                filtered[#filtered + 1] = run
            elseif self.activeResultFilter == 3 and not run.inTime then  -- Fuera de tiempo
                filtered[#filtered + 1] = run
            end
        end
        runs = filtered
    end

    -- (Filtro de nivel eliminado — activeLevelFilter/levelRanges nunca se definían)

    -- Filtro de afijo (Fortified ID 10, Tyrannical ID 9)
    if self.activeAffixFilter and self.activeAffixFilter ~= 0 then
        local targetID = self.activeAffixFilter
        local idNames = { [9] = "tyrannical", [10] = "fortified" }
        local targetName = idNames[targetID]
        local filtered = {}
        for _, run in ipairs(runs) do
            local found = false
            for _, a in ipairs(run.affixes or {}) do
                if type(a) == "number" and a == targetID then found = true; break end
                if type(a) == "table" and ((a.id or a.affixID) == targetID or
                    (a.name and targetName and a.name:lower() == targetName)) then
                    found = true; break
                end
                if type(a) == "string" and targetName and a:lower() == targetName then
                    found = true; break
                end
            end
            if found then filtered[#filtered + 1] = run end
        end
        runs = filtered
    end

    self.filteredRuns = runs

    -- Al cambiar el filtro cambia el nombre de mazmorra mas largo de la lista,
    -- y con el lo que necesita esa columna. Sin esto, filtrar a una sola
    -- mazmorra dejaria la columna del tamano que pedia la lista anterior.
    if self.scrollFrame then
        local w = self.scrollFrame:GetWidth()
        if w and w > 50 then self:ResizeColumns(w - SCROLLBAR_GUTTER) end
    end

    -- ── Calcular records por mazmorra (mejor nivel por nombre) ───────────────
    self.recordKeys = {}   -- dungeonName → max keyLevel en filteredRuns
    for _, run in ipairs(self.filteredRuns) do
        local dn = run.dungeonName or ""
        local kl = run.keyLevel or 0
        if dn ~= "" and kl > (self.recordKeys[dn] or 0) then
            self.recordKeys[dn] = kl
        end
    end

    table.sort(self.filteredRuns, function(a, b)
        local va, vb
        if self.sortColumn == "date" then
            va = a.startTime or 0
            vb = b.startTime or 0
        elseif self.sortColumn == "level" then
            va = a.keyLevel or 0
            vb = b.keyLevel or 0
        elseif self.sortColumn == "margin" then
            va = MitzuMPlus.RunMetrics and MitzuMPlus.RunMetrics:GetMargin(a) or -math.huge
            vb = MitzuMPlus.RunMetrics and MitzuMPlus.RunMetrics:GetMargin(b) or -math.huge
        elseif self.sortColumn == "dungeon" then
            va = tostring(a.dungeonName or ""):lower();vb = tostring(b.dungeonName or ""):lower()
        elseif self.sortColumn == "favorite" then
            va = a.isFavorite and 1 or 0;vb = b.isFavorite and 1 or 0
        elseif self.sortColumn == "season" then
            local _,al=MitzuMPlus.RunMetrics:GetSeason(a);local _,bl=MitzuMPlus.RunMetrics:GetSeason(b);va=al;vb=bl
        elseif self.sortColumn == "result" then
            va = a.inTime and 1 or 0;vb = b.inTime and 1 or 0
        elseif self.sortColumn == "character" then
            va=tostring(a.playerName or ""):lower();vb=tostring(b.playerName or ""):lower()
        elseif self.sortColumn == "role" then
            va=MitzuMPlus.RunMetrics:GetRole(a);vb=MitzuMPlus.RunMetrics:GetRole(b)
        elseif self.sortColumn == "quality" then
            va=MitzuMPlus.RunMetrics:GetQuality(a);vb=MitzuMPlus.RunMetrics:GetQuality(b)
        else
            va = a.startTime or 0
            vb = b.startTime or 0
        end
        -- FIX: operador precedence — and/or sin paréntesis era ambiguo
        if self.sortDescending then
            return va > vb
        else
            return va < vb
        end
    end)
    
    self.currentPage = 1
    self:RefreshTable()
    self:UpdateSummaryBar()
end

function PanelHistorial:RefreshTable()
    local startIndex = (self.currentPage - 1) * self.runsPerPage + 1
    local endIndex   = math.min(startIndex + self.runsPerPage - 1, #self.filteredRuns)
    local hasRuns    = #self.filteredRuns > 0

    -- ── Toggle tabla / empty state ───────────────────────────────────────────
    if self.tableEmptyState then
        if hasRuns then
            self.tableEmptyState:Hide()
        else
            -- Actualizar mensaje según si hay runs en db o solo los filtros vaciaron
            local totalInDB = #(MitzuMPlus:GetAllRuns() or {})
            if totalInDB == 0 then
                self.tableEmptyState.subtitle:SetText(
                    "Completa tu primera Mythic+ con el addon activo para verla aquí.")
                if self.tableEmptyState.cta then self.tableEmptyState.cta:Show() end
            else
                self.tableEmptyState.title:SetText("Sin resultados")
                self.tableEmptyState.subtitle:SetText(
                    "Ninguna run coincide con los filtros aplicados. Prueba a ampliar los criterios de búsqueda.")
                if self.tableEmptyState.cta then self.tableEmptyState.cta:Hide() end
            end
            self.tableEmptyState:Show()
        end
    end

    -- ── Ocultar/mostrar tabla y paginación ───────────────────────────────────
    if self.tableContainer then self.tableContainer:SetShown(hasRuns) end
    if self.pagination then self.pagination:SetShown(hasRuns) end

    if not hasRuns then return end

    -- ── Poblar filas con stagger de entrada (Fase 4.1) ───────────────────────
    local animEnabled = MitzuMPlus.db and MitzuMPlus.db.profile and
                        MitzuMPlus.db.profile.settings and
                        MitzuMPlus.db.profile.settings.enableAnimations

    for i, row in ipairs(self.tableRows) do
        local runIndex = startIndex + i - 1
        if runIndex <= endIndex then
            local run = self.filteredRuns[runIndex]
            self:PopulateRow(row, run, runIndex)
            if animEnabled and i <= 10 then
                row:SetAlpha(0)
                row:Show()
                C_Timer.After(i * 0.025, function()
                    if row:IsShown() then UIFrameFadeIn(row, 0.12, 0, 1) end
                end)
            else
                row:SetAlpha(1)
                row:Show()
            end
        else
            row:Hide()
        end
    end

    self:UpdatePaginationUI()
end

function PanelHistorial:PopulateRow(row, run, globalIndex)
    row.runData = run
    row.runData.index = globalIndex
    row.selected = self.selectedRunIDs and self.selectedRunIDs[tonumber(run.runID)] or false
    Theme:SetBackdropColor(row,row.selected and Theme.BG.rowSel or (row.rowIndex%2==1 and Theme.BG.rowOdd or Theme.BG.rowEven))
    
    row.cells[1]:SetText("")
    row.favoriteIcon:SetAlpha(run.isFavorite and 1 or .18)
    if row.favoriteIcon.SetDesaturated then row.favoriteIcon:SetDesaturated(not run.isFavorite) end
    
    -- ── Spec icon ────────────────────────────────────────────────────────────
    local role = (run.playerRole or run.role or "DAMAGER"):upper()
    local specTex = SPEC_ICON[role] or SPEC_ICON.DAMAGER
    row.specIcon:SetTexture(specTex)
    row.specIcon:Show()
    -- El posicionamiento horizontal se ajusta en ResizeColumns; aquí solo Y
    row.specIcon:SetPoint("LEFT", row, "LEFT",
        math.floor((self.tableHeader and self.tableHeader.columns["dungeon"] and
            self.tableHeader.columns["dungeon"]:GetLeft() and
            self.tableHeader.columns["dungeon"]:GetLeft() - row:GetLeft() or 0) or 0) + 6,
        0)

    row.cells[2]:SetText(run.dungeonName or "Unknown")
    Theme:SetTextColor(row.cells[2], Theme.TEXT.primary)
    
    local keyLevel = run.keyLevel or 0
    row.cells[3]:SetText("+" .. tostring(keyLevel))
    -- ── Color del nivel por tier de llave (premium) ──────────────────────────
    local tierTheme = Theme:GetKeyLevelTheme(keyLevel)
    Theme:SetTextColor(row.cells[3], tierTheme.text)

    -- ── Record badge ─────────────────────────────────────────────────────────
    local dn = run.dungeonName or ""
    local isRecord = (self.recordKeys and self.recordKeys[dn] == keyLevel and keyLevel > 0)
    if isRecord then
        row.recordBadge:SetPoint("TOPLEFT", row.cells[3], "TOPRIGHT", 2, 2)
        row.recordBadge:Show()
    else
        row.recordBadge:Hide()
    end
    
    local seasonLabel=""
    if MitzuMPlus.RunMetrics and IsMidnightRun(run) then
        local _,label=MitzuMPlus.RunMetrics:GetSeason(run);seasonLabel=label or "Midnight"
    end
    if #seasonLabel>20 then seasonLabel=seasonLabel:sub(1,17).."..." end
    row.cells[4]:SetText(seasonLabel);Theme:SetTextColor(row.cells[4],Theme.TEXT.secondary)
    
    if run.inTime then
        row.cells[5]:SetText("EN TIEMPO")
        Theme:SetTextColor(row.cells[5], Theme.STATUS.ok)
    else
        row.cells[5]:SetText("FUERA")
        Theme:SetTextColor(row.cells[5], Theme.STATUS.bad)
    end
    
    local margin=MitzuMPlus.RunMetrics and MitzuMPlus.RunMetrics:GetMargin(run)
    if margin then
        local sign=margin>=0 and "+" or "-";local sec=math.abs(margin)
        row.cells[6]:SetText(string.format("%s%d:%02d",sign,math.floor(sec/60),math.floor(sec%60)))
        Theme:SetTextColor(row.cells[6],margin>=0 and Theme.STATUS.ok or Theme.STATUS.bad)
    else row.cells[6]:SetText("-");Theme:SetTextColor(row.cells[6],Theme.TEXT.dim) end

    row.cells[7]:SetText(run.playerName and run.playerName~="" and run.playerName or "-")
    Theme:SetTextColor(row.cells[7],Theme.TEXT.primary)
    local role,roleLabel="DAMAGER","DPS"
    if MitzuMPlus.RunMetrics then role,roleLabel=MitzuMPlus.RunMetrics:GetRole(run) end
    row.cells[8]:SetText("")
    row._displayRole=role
    SetNativeRoleIcon(row.roleIcon,role)
    row.roleIcon:SetAlpha(1)
    local quality,qualityLabel="INVALID","Incompleta"
    if MitzuMPlus.RunMetrics then quality,qualityLabel=MitzuMPlus.RunMetrics:GetQuality(run) end
    row.cells[9]:SetText(qualityLabel)
    Theme:SetTextColor(row.cells[9],quality=="COMPLETE" and Theme.STATUS.ok or (quality=="PARTIAL" and Theme.STATUS.warn or Theme.TEXT.dim))
    local hasNote=tostring(run.notes or "")~=""
    row.cells[10]:SetText(hasNote and "SI" or "-");Theme:SetTextColor(row.cells[10],hasNote and Theme.GOLD.gold4 or Theme.TEXT.dim)
    local tagText=type(run.tags)=="table" and table.concat(run.tags,",") or ""
    if #tagText>16 then tagText=tagText:sub(1,13).."..." end
    row.cells[11]:SetText(tagText~="" and tagText or "-");Theme:SetTextColor(row.cells[11],Theme.TEXT.secondary)

    -- ── Member dots (col 12 = grupo) ─────────────────────────────────────────
    local group = (type(run.group) == "table") and run.group or {}
    -- Rol abreviado para la letra del dot
    local roleAbbrev = { TANK = "T", HEALER = "H", DAMAGER = "D", DPS = "D" }
    for m = 1, 5 do
        local dot = row.memberDots[m]
        if not dot then break end
        local member = group[m]
        if member then
            local cls   = (member.class or ""):upper()
            local role  = (member.role or "DAMAGER"):upper()
            local abbr  = roleAbbrev[role] or "D"
            local clsColor = Theme:GetClassColor(cls)

            -- Fondo oscuro de ese color de clase
            local bg = {
                r = clsColor.r * 0.18,
                g = clsColor.g * 0.18,
                b = clsColor.b * 0.18,
                a = 1.0,
            }
            local border = {
                r = clsColor.r * 0.55,
                g = clsColor.g * 0.55,
                b = clsColor.b * 0.55,
                a = 1.0,
            }
            Theme:SetBackdropColor(dot, bg)
            Theme:SetBackdropBorderColor(dot, border)
            dot.label:SetText(abbr)
            dot.label:SetTextColor(clsColor.r, clsColor.g, clsColor.b, 1)
            -- `_hasMember` es lo que permite que ResizeColumns las devuelva
            -- al ensanchar la ventana sin tener que repintar la tabla.
            dot._hasMember = true
            dot:SetShown(not self:IsColumnHidden("group"))

            -- Tooltip con nombre de clase
            dot:SetScript("OnEnter", function(self)
                if not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:ClearLines()
                local displayName = member.name and member.name ~= "" and member.name or cls
                GameTooltip:AddLine(string.format("%s — %s", displayName, role), clsColor.r, clsColor.g, clsColor.b)
                GameTooltip:Show()
            end)
            dot:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
        else
            dot._hasMember = false
            dot:Hide()
        end
    end

    -- BUG-C5 FIX: off-by-one en indices de celda.
    -- COLUMN_ORDER: ...ilvl=11, group=12, date=13, actions=14
    -- El código anterior ponía la fecha en cells[12] (slot del grupo) y ▶ en cells[13] (slot fecha).
    row.cells[13]:SetText(F():FormatDate(run.startTime, "relative"))
    Theme:SetTextColor(row.cells[13], Theme.TEXT.dim)

    row.cells[14]:SetText(">")
    Theme:SetTextColor(row.cells[14], Theme.TEXT.dim)

    -- ── Abandon badge ──────────────────────────────────────────────────────
    local ab = run.abandoners
    if row.abandonBadge then
        if type(ab) == "table" and #ab > 0 then
            row.abandonBadge:ClearAllPoints()
            row.abandonBadge:SetPoint("LEFT", row.cells[2], "RIGHT", 4, 0)
            row.abandonBadge:Show()
            if row.abandonTipFrame then
                row.abandonTipFrame:ClearAllPoints()
                row.abandonTipFrame:SetPoint("CENTER", row.abandonBadge, "CENTER", 0, 0)
            end
        else
            row.abandonBadge:Hide()
        end
    end
end

function PanelHistorial:UpdateSummaryBar()
    -- v6.1: Historial dejó de presentar agregados. Se conserva el nombre de
    -- esta función porque ApplyFilters y código legado todavía la invocan.
    if self.archiveBar then self:UpdateArchiveBar();return end
    local total = #self.filteredRuns
    local inTime = 0
    local outTime = 0
    local totalDPS = 0
    local dpsRunCount = 0
    local totalDeaths = 0
    local totalKicks = 0
    
    for _, run in ipairs(self.filteredRuns) do
        if run.inTime then inTime = inTime + 1 else outTime = outTime + 1 end
        local dmg = (run.stats and run.stats.damageTotal) or 0
        local ct  = tonumber(run.completionTime) or 0
        if ct > 0 and dmg > 0 then
            totalDPS = totalDPS + (dmg / ct)
            dpsRunCount = dpsRunCount + 1
        end
        totalDeaths = totalDeaths + ((run.stats and run.stats.deaths) or 0)
        local s = run.stats or {}
        totalKicks = totalKicks + (tonumber(s.kicksGroup) or tonumber(s.kicks) or 0)
    end
    
    local avgDPS = dpsRunCount > 0 and (totalDPS / dpsRunCount) or 0
    
    self.summaryItems.showing.value:SetText(string.format("%d runs", total))
    self.summaryItems.inTime.value:SetText(tostring(inTime))
    self.summaryItems.outTime.value:SetText(tostring(outTime))
    self.summaryItems.avgDps.value:SetText(F():FormatDPS(avgDPS))
    self.summaryItems.deaths.value:SetText(tostring(totalDeaths))
    self.summaryItems.kicks.value:SetText(tostring(totalKicks))

    -- ── Actualizar barras de progreso (premium) ──────────────────────────────
    if total > 0 then
        self.summaryItems.showing:SetBarPercent(1.0)
        self.summaryItems.inTime:SetBarPercent(inTime  / total)
        self.summaryItems.outTime:SetBarPercent(outTime / total)
        -- DPS: 200k = barra llena (valor referencia Mythic+)
        self.summaryItems.avgDps:SetBarPercent(math.min(1.0, avgDPS / 200000))
        -- Muertes: 0 = llena verde, >3/run = vacía (invertido)
        local deathRate = total > 0 and (totalDeaths / total) or 0
        self.summaryItems.deaths:SetBarPercent(math.max(0, 1.0 - (deathRate / 5)))
        -- Kicks: 8 kicks/run = barra llena
        local kickRate = total > 0 and (totalKicks / total) or 0
        self.summaryItems.kicks:SetBarPercent(math.min(1.0, kickRate / 8))
    else
        -- Sin datos: barras en 0
        for _, item in pairs(self.summaryItems) do
            if item.SetBarPercent then item:SetBarPercent(0) end
        end
    end
end

function PanelHistorial:UpdatePaginationUI()
    local totalPages = math.max(1, math.ceil(#self.filteredRuns / self.runsPerPage))
    
    self.pageInfo:SetText(string.format("Página %d de %d · %d runs totales", 
        self.currentPage, totalPages, #self.filteredRuns))
    
    local firstPage=math.max(1,math.min(self.currentPage-2,totalPages-4))
    for i, btn in ipairs(self.pageButtons) do
        local pageNum=firstPage+i-1
        if pageNum <= totalPages then
            btn.pageNum = pageNum
            btn:SetButtonText(tostring(pageNum))
            btn:SetAlpha(pageNum==self.currentPage and 1 or .72)
            btn:Show()
        else
            btn:Hide()
        end
    end
    if self.prevBtn then self.prevBtn:SetEnabled(self.currentPage>1);self.prevBtn:SetAlpha(self.currentPage>1 and 1 or .32) end
    if self.nextBtn then self.nextBtn:SetEnabled(self.currentPage<totalPages);self.nextBtn:SetAlpha(self.currentPage<totalPages and 1 or .32) end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DYNAMIC COLUMN RESIZING
-- ═══════════════════════════════════════════════════════════════════════════

-- Pesos relativos de cada columna (deben sumar 1.0)
local COLUMN_WEIGHTS = {
    favorite=0.035,dungeon=0.170,level=0.050,season=0.090,result=0.085,
    margin=0.065,character=0.105,role=0.040,quality=0.065,notes=0.040,
    tags=0.070,group=0.075,date=0.075,actions=0.035,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- BUG UI-TB1 — la tabla se salía de la ventana y los títulos aparecían
-- cortados ("TEMPORA...", "RESULTA...", "MARG...", y FECHA partida por el
-- borde derecho).
--
-- Dos causas, las dos en estos números:
--
--  1. Los mínimos suman 1255 px. El contenedor real ronda los 1040. El
--     reparto hacía `extra = max(0, total - 1255)` = 0 y le daba a cada
--     columna su mínimo... o sea 1255 px de columnas en 1040 px de hueco.
--     Los últimos 215 px caían FUERA de la ventana. El `max(0, ...)` evitaba
--     un número negativo pero no el desbordamiento: no había ningún camino
--     para el caso "no cabe".
--  2. Los mínimos estaban puestos a ojo para la fuente de Blizzard. Con la
--     del tema, "TEMPORADA" no cabe en los 115 px que tenía asignados, así
--     que se recortaba aunque la columna tuviera su ancho completo.
--
-- Ahora: el mínimo de cada columna es el mayor entre su mínimo legible y lo
-- que mide SU PROPIO TÍTULO, medido en el cliente. Y si con eso no cabe, se
-- van soltando columnas por orden de menos valor hasta que quepa.
-- ═══════════════════════════════════════════════════════════════════════════

-- Anchos mínimos legibles de los DATOS. El título puede pedir más y manda el
-- mayor de los dos; ver PanelHistorial:_ColumnMin.
local COLUMN_MIN_WIDTH = {
    favorite=45,dungeon=220,level=60,season=115,result=105,
    margin=75,character=140,role=50,quality=75,notes=50,
    tags=85,group=100,date=100,actions=35,
}

local COLUMN_ORDER = {
    "favorite","dungeon","level","season","result",
    "margin","character","role","quality","notes","tags","group","date","actions"
}

-- clave -> indice de celda. Las celdas de una fila se crean en este mismo
-- orden (CELL_KEYS en CreateTableRow), asi que el indice coincide.
local CELL_INDEX = {}
for i, key in ipairs(COLUMN_ORDER) do CELL_INDEX[key] = i end

-- Orden de sacrificio cuando no cabe todo: la primera de la lista es la
-- primera en desaparecer. El criterio es cuánta información aporta DE VERDAD
-- en la tabla:
--   TEMPORADA  pone "Midnight" en las 20 filas y ya hay un filtro para ella.
--   NOTA       un "-" en casi todas; el detalle de la fila la muestra.
--   ETIQUETA   igual.
--   DATOS      "Completa" en casi todas.
--   GRUPO      las pastillas de composición; útil, así que cae la última.
-- Lo que NUNCA se suelta: FAV, MAZMORRA, NIVEL, RESULTADO, MARGEN,
-- PERSONAJE, ROL, FECHA y la flecha de detalle.
local COLUMN_DROP_ORDER = { "season", "notes", "tags", "quality", "group" }

-- Mínimo real de una columna: el mayor entre el mínimo de sus datos y lo que
-- ocupa su título con la fuente que de verdad se está usando. Se mide una vez
-- y se guarda; solo depende de la fuente, no del tamaño de la ventana.
function PanelHistorial:_ColumnMin(key)
    self._colMin = self._colMin or {}
    local cache = self._colMin[key]
    if cache then return cache end

    local minimo = COLUMN_MIN_WIDTH[key] or 0
    local colHeader = self.tableHeader and self.tableHeader.columns
                      and self.tableHeader.columns[key]
    local fs = colHeader and colHeader.text
    local medido = false
    if fs and fs.GetStringWidth then
        local ok, w = pcall(fs.GetStringWidth, fs)
        -- 16 px son los márgenes del texto dentro de la celda (10 + 6) y 4
        -- más de holgura para que no quede el título pegado al borde.
        if ok and type(w) == "number" and w > 0 then
            medido = true
            if (w + 20) > minimo then minimo = w + 20 end
        end
    end
    -- Solo se guarda una medida VALIDA. Si el cliente aun no sabe medir ese
    -- texto devuelve 0, y cachear el minimo de fabrica en ese momento seria
    -- quedarse para siempre con el numero puesto a ojo.
    if medido then self._colMin[key] = minimo end
    return minimo
end

-- ¿Está suelta esta columna ahora mismo?
function PanelHistorial:IsColumnHidden(key)
    return self._hiddenColumns ~= nil and self._hiddenColumns[key] == true
end

-- ─────────────────────────────────────────────────────────────────────────
-- Lo que pide la columna MAZMORRA para no recortar ningún nombre
--
-- Era la truncadura más visible de la tabla: "Estanques de Vida...", "El
-- Valle Enceguece...", "Templo de Sethrali...". Un mínimo puesto a ojo no
-- puede saberlo, porque depende de la fuente Y de qué mazmorras tenga este
-- jugador en su historial. Así que se mide el nombre más largo que de verdad
-- hay en la lista, con la fuente de las celdas.
--
-- La columna es la identidad de la fila: si algo tiene que recortarse, que
-- sea otra cosa. Por eso pide sitio y las columnas de relleno se sueltan
-- antes. El tope evita que un nombre desmesurado se coma la tabla entera.
-- ─────────────────────────────────────────────────────────────────────────

local DUNGEON_ICON_ROOM  = 32   -- hueco del icono de spec + margen
local DUNGEON_MAX_SHARE  = 0.34 -- como maximo, este porcentaje de la tabla

function PanelHistorial:_DungeonNameWidth(totalWidth)
    local header = self.tableHeader
    if not header then return 0 end
    if not self._nameMeasure then
        local fs = header:CreateFontString(nil, "ARTWORK")
        Theme:ApplyFont(fs, "mono", 14)   -- la misma que las celdas
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        fs:Hide()
        self._nameMeasure = fs
    end

    local fs = self._nameMeasure
    local vistos, masLargo = {}, 0
    local runs = self.filteredRuns
    if type(runs) ~= "table" or #runs == 0 then
        runs = (MitzuMPlus.GetAllRuns and MitzuMPlus:GetAllRuns()) or {}
    end
    for _, run in ipairs(runs) do
        local nombre = run and run.dungeonName
        if type(nombre) == "string" and nombre ~= "" and not vistos[nombre] then
            vistos[nombre] = true
            fs:SetText(nombre)
            local ok, w = pcall(fs.GetStringWidth, fs)
            if ok and type(w) == "number" and w > masLargo then masLargo = w end
        end
    end
    if masLargo <= 0 then return 0 end

    local pedido = masLargo + DUNGEON_ICON_ROOM + 8
    local tope = math.floor((totalWidth or 0) * DUNGEON_MAX_SHARE)
    if tope > 0 and pedido > tope then pedido = tope end
    return pedido
end

function PanelHistorial:ResizeColumns(totalWidth)
    if not totalWidth or totalWidth < 50 then return end
    if not self.tableHeader or not self.tableHeader.columns then return end

    -- El reparto en si es aritmetica pura y vive en Widgets:FitColumns, donde
    -- se puede probar sin abrir el juego. Aqui se le dan los minimos ya
    -- medidos y se aplican los anchos que devuelve.
    local minimos = {}
    for _, key in ipairs(COLUMN_ORDER) do minimos[key] = self:_ColumnMin(key) end
    -- MAZMORRA pide lo que de verdad ocupa el nombre mas largo del historial.
    local pideMazmorra = self:_DungeonNameWidth(totalWidth)
    if pideMazmorra > minimos.dungeon then minimos.dungeon = pideMazmorra end

    local anchos, sueltas = Widgets:FitColumns({
        total     = totalWidth,
        order     = COLUMN_ORDER,
        mins      = minimos,
        weights   = COLUMN_WEIGHTS,
        dropOrder = COLUMN_DROP_ORDER,
    })
    self._hiddenColumns = sueltas

    local xOffset = 0
    for _, key in ipairs(COLUMN_ORDER) do
        local colHeader = self.tableHeader.columns[key]

        if sueltas[key] then
            if colHeader then colHeader:Hide() end
            for _, row in ipairs(self.tableRows or {}) do
                local ci = CELL_INDEX[key]
                if ci and row.cells and row.cells[ci] then row.cells[ci]:Hide() end
                if key == "group" and row.memberDots then
                    for _, dot in ipairs(row.memberDots) do dot:Hide() end
                end
            end
            -- No se avanza xOffset: la columna no ocupa sitio.
        else

        local colWidth = anchos[key] or 0
        if colHeader then
            colHeader:Show()
            colHeader:ClearAllPoints()
            colHeader:SetPoint("LEFT", self.tableHeader, "LEFT", xOffset, 0)
            colHeader:SetWidth(colWidth)
        end
        -- Actualizar celdas de cada fila
        for _, row in ipairs(self.tableRows or {}) do
            local cellIndex = CELL_INDEX[key]
            if cellIndex and row.cells and row.cells[cellIndex] then
                row.cells[cellIndex]:Show()
                row.cells[cellIndex]:ClearAllPoints()

                if key == "favorite" then
                    row.cells[cellIndex]:SetText("")
                    if row.favoriteIcon then
                        row.favoriteIcon:ClearAllPoints()
                        row.favoriteIcon:SetPoint("CENTER",row,"LEFT",xOffset+math.floor(colWidth/2),0)
                    end
                    if row.favoriteTipFrame then
                        row.favoriteTipFrame:ClearAllPoints()
                        row.favoriteTipFrame:SetPoint("CENTER",row,"LEFT",xOffset+math.floor(colWidth/2),0)
                    end
                elseif key == "dungeon" then
                    -- Dejar espacio para el spec icon (20px)
                    row.cells[cellIndex]:SetPoint("LEFT", row, "LEFT", xOffset + 26, 0)
                    row.cells[cellIndex]:SetWidth(colWidth - 32)
                    -- Posicionar spec icon
                    if row.specIcon then
                        row.specIcon:ClearAllPoints()
                        row.specIcon:SetPoint("LEFT", row, "LEFT", xOffset + 4, 0)
                    end
                elseif key == "role" then
                    row.cells[cellIndex]:SetText("")
                    if row.roleIcon then
                        row.roleIcon:ClearAllPoints()
                        row.roleIcon:SetPoint("CENTER",row,"LEFT",xOffset+math.floor(colWidth/2),0)
                    end
                    if row.roleTipFrame then
                        row.roleTipFrame:ClearAllPoints()
                        row.roleTipFrame:SetPoint("CENTER",row,"LEFT",xOffset+math.floor(colWidth/2),0)
                    end
                elseif key == "group" then
                    -- Ocultar fontstring (los dots son frames separados)
                    row.cells[cellIndex]:SetText("")
                    if row.memberDots then
                        for _, dot in ipairs(row.memberDots) do
                            dot:SetShown(dot._hasMember == true)
                        end
                    end
                    -- Posicionar los 5 member dots dentro de la columna
                    if row.memberDots then
                        local dotW    = 14
                        local dotGap  = 2
                        local totalW  = 5 * dotW + 4 * dotGap
                        local startX  = xOffset + math.max(0, math.floor((colWidth - totalW) / 2))
                        for m, dot in ipairs(row.memberDots) do
                            dot:ClearAllPoints()
                            dot:SetPoint("LEFT", row, "LEFT", startX + (m - 1) * (dotW + dotGap), 0)
                        end
                    end
                else
                    row.cells[cellIndex]:SetPoint("LEFT",  row, "LEFT",  xOffset + 6, 0)
                    row.cells[cellIndex]:SetWidth(colWidth - 12)
                end

                -- Record badge DENTRO de la columna "NIVEL", sin invadir
                -- la columna siguiente (AFIJOS). Antes se anclaba al borde
                -- derecho y la estrella aparecía pegada al nombre del afijo.
                if key == "level" and row.recordBadge then
                    row.recordBadge:ClearAllPoints()
                    row.recordBadge:SetPoint("RIGHT", row, "LEFT", xOffset + colWidth - 4, 0)
                    if row.recordTipFrame then
                        row.recordTipFrame:ClearAllPoints()
                        row.recordTipFrame:SetPoint("CENTER", row.recordBadge, "CENTER", 0, 0)
                    end
                end
            end
        end
        xOffset = xOffset + colWidth
        end   -- fin de la rama "la columna se ve"
    end
end

return PanelHistorial
