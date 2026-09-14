-- MitzuMPlus History V2: compact filters, run list and contextual detail.
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon("MitzuMPlus")
local Theme = MitzuMPlus.Theme
local Panel = {}
MitzuMPlus.PanelHistorial = Panel

Panel.filters = {
    search = "", dungeon = "", result = "", character = "", role = "",
    week = "", extra = "", season = "", sortBy = "date", page = 1, pageSize = 20,
}
Panel.detailTab = "summary"
Panel.ROWS = 50
Panel.COLUMNS = {
    { key = "index", title = "#", min = 28, weight = 0 },
    { key = "dungeon", title = "MAZMORRA", min = 142, weight = 3 },
    { key = "level", title = "NIVEL", min = 48, weight = 0 },
    { key = "result", title = "RESULTADO", min = 112, weight = 2 },
    { key = "duration", title = "DURACIÓN", min = 76, weight = 1 },
    { key = "character", title = "PERSONAJE", min = 100, weight = 2 },
    { key = "role", title = "ROL", min = 50, weight = 0 },
    { key = "date", title = "FECHA", min = 82, weight = 1 },
}

local function backdrop(frame, r, g, b, a, border)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(r, g, b, a)
    frame:SetBackdropBorderColor(border or 0.16, border or 0.16, border or 0.16, 1)
end
local function text(parent, font, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
    if Theme and Theme.ApplyFont then Theme:ApplyFont(fs, "normal", size or 12) end
    return fs
end
local function fmtTime(seconds)
    seconds = tonumber(seconds)
    if not seconds then return "-" end
    local sign = seconds < 0 and "-" or ""
    seconds = math.abs(math.floor(seconds + 0.5))
    return string.format("%s%d:%02d", sign, math.floor(seconds / 60), seconds % 60)
end
local function roleText(role)
    return ({ TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" })[role] or "-"
end

-- Blizzard role atlases used by the Group Finder. Keeping the role column as
-- an icon frees horizontal space and mirrors the visual language players
-- already know from the default UI.
local ROLE_ATLAS = {
    TANK = "groupfinder-icon-role-large-tank",
    HEALER = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps",
}

local function setRoleIcon(texture, role)
    if not texture then return end
    local atlas
    if _G.GetIconForRole then
        local ok, value = pcall(_G.GetIconForRole, role, false)
        if ok then atlas = value end
    end
    atlas = atlas or ROLE_ATLAS[role]
    texture:SetShown(atlas ~= nil)
    if not atlas then return end
    -- Never let SetAtlas adopt the atlas native dimensions. The large role
    -- atlases are intentionally high resolution and useAtlasSize=true makes
    -- them overflow our compact history rows.
    local ok = pcall(texture.SetAtlas, texture, atlas, false)
    if not ok then
        texture:Hide()
        return
    end
    texture:SetSize(14, 14)
end

local function compactMetric(value)
    local n = tonumber(value)
    if n == nil then return "-" end
    local absn = math.abs(n)
    local divisor, suffix
    if absn >= 1000000000 then
        divisor, suffix = 1000000000, "B"
    elseif absn >= 1000000 then
        divisor, suffix = 1000000, "M"
    elseif absn >= 1000 then
        divisor, suffix = 1000, "K"
    else
        return tostring(math.floor(n + (n >= 0 and 0.5 or -0.5)))
    end
    local out = string.format("%.1f%s", n / divisor, suffix)
    local compact = out:gsub("%.0([KMB])$", "%1")
    return compact
end
local function charName(run)
    local name, realm = tostring(run.playerName or ""), tostring(run.playerRealm or "")
    if name == "" then return "Desconocido" end
    return realm ~= "" and (name .. "-" .. realm) or name
end
local function dateText(timestamp)
    if not date or not tonumber(timestamp) then return "-" end
    local ok, value = pcall(date, "%d/%m/%y", tonumber(timestamp))
    return ok and value or "-"
end
local function resetStart()
    if not (time and date) then return 0 end
    local now, day = time(), 86400
    local h = tonumber(date("%H")) or 0
    local m = tonumber(date("%M")) or 0
    local s = tonumber(date("%S")) or 0
    local weekday = tonumber(date("%w")) or 0
    local target = (MitzuMPlus.Constants and MitzuMPlus.Constants.WEEK_RESET_WDAY) or 3
    local hour = (MitzuMPlus.Constants and MitzuMPlus.Constants.WEEK_RESET_HOUR) or 9
    local back = (weekday - target + 7) % 7
    if back == 0 and h < hour then back = 7 end
    return now - (h * 3600 + m * 60 + s) - back * day + hour * 3600
end

function Panel.FormatResult(run)
    run = type(run) == "table" and run or {}
    local limit, actual = tonumber(run.timeLimit), tonumber(run.completionTime)
    if not actual or actual <= 0 then
        return "Incompleta", nil, "|cFF999999Incompleta|r"
    end
    local levels = tonumber(run.keystoneUpgradeLevels) or 0
    local code = run.inTime and (levels >= 3 and "+3" or (levels == 2 and "+2" or "+1")) or "Fuera"
    local threshold
    if limit and limit > 0 then
        threshold = code == "+3" and limit * 0.6 or (code == "+2" and limit * 0.8 or limit)
    end
    local margin = threshold and (threshold - actual) or nil
    local prefix = run.inTime and "|cFF55DD88" or "|cFFFF6666"
    return code, margin, prefix .. code .. (margin and (" (" .. (margin >= 0 and "+" or "") .. fmtTime(margin) .. ")") or "") .. "|r"
end

local function contains(haystack, needle)
    return tostring(haystack or ""):lower():find(needle, 1, true) ~= nil
end
local function groupContains(run, needle)
    for _, member in ipairs(type(run.group) == "table" and run.group or {}) do
        if contains(member.name, needle) or contains(member.realm, needle) then return true end
    end
    return false
end

function Panel.FilterRuns(runs, filters, nowEpoch)
    filters = filters or {}
    local out, search = {}, tostring(filters.search or ""):lower()
    local dungeon, resultFilter = tostring(filters.dungeon or ""), tostring(filters.result or "")
    local character, role = tostring(filters.character or ""), tostring(filters.role or "")
    local season, week, extra = tostring(filters.season or ""), tostring(filters.week or ""), tostring(filters.extra or "")
    local weekStart = resetStart()
    local lastStart = weekStart - 7 * 86400
    for _, run in ipairs(runs or {}) do
        local code = Panel.FormatResult(run)
        local currentChar = charName(run)
        local ok = type(run) == "table"
        if ok and dungeon ~= "" and run.dungeonName ~= dungeon then ok = false end
        if ok and resultFilter ~= "" and code ~= resultFilter then ok = false end
        if ok and character ~= "" and currentChar ~= character then ok = false end
        if ok and role ~= "" and run.playerRole ~= role then ok = false end
        if ok and season ~= "" and tostring(run.seasonKey or "") ~= season then ok = false end
        local started = tonumber(run.startTime) or 0
        if ok and week == "this" and started < weekStart then ok = false end
        if ok and week == "last" and (started < lastStart or started >= weekStart) then ok = false end
        if ok and extra == "favorite" and run.isFavorite ~= true then ok = false end
        if ok and extra == "notes" and tostring(run.notes or "") == "" then ok = false end
        if ok and search ~= "" and not contains(run.dungeonName, search)
           and not contains(currentChar, search) and not groupContains(run, search) then ok = false end
        if ok then out[#out + 1] = run end
    end
    local sortBy = filters.sortBy or "date"
    table.sort(out, function(a, b)
        local av, bv
        if sortBy == "level" then av, bv = tonumber(a.keyLevel) or 0, tonumber(b.keyLevel) or 0
        elseif sortBy == "result" then
            local rank = { ["+3"] = 5, ["+2"] = 4, ["+1"] = 3, Fuera = 2, Incompleta = 1 }
            av, bv = rank[Panel.FormatResult(a)] or 0, rank[Panel.FormatResult(b)] or 0
        elseif sortBy == "dungeon" then av, bv = tostring(a.dungeonName or ""), tostring(b.dungeonName or "")
        else av, bv = tonumber(a.startTime) or 0, tonumber(b.startTime) or 0 end
        if av == bv then return (tonumber(a.runID) or 0) > (tonumber(b.runID) or 0) end
        return av > bv
    end)
    return out
end

function Panel.Paginate(runs, page, pageSize)
    pageSize = math.max(1, tonumber(pageSize) or 20)
    local pages = math.max(1, math.ceil(#runs / pageSize))
    page = math.max(1, math.min(pages, tonumber(page) or 1))
    local result, first = {}, (page - 1) * pageSize + 1
    for i = first, math.min(#runs, first + pageSize - 1) do result[#result + 1] = runs[i] end
    return result, page, pages
end

local function uniqueItems(runs, getter, allLabel)
    local seen, values = {}, {}
    for _, run in ipairs(runs or {}) do
        local value = getter(run)
        if value and value ~= "" and not seen[value] then seen[value] = true; values[#values + 1] = value end
    end
    table.sort(values)
    local items = { { text = allLabel, value = "" } }
    for _, value in ipairs(values) do items[#items + 1] = { text = value, value = value } end
    return items
end

-- All geometry is expressed in this panel's local units. No sibling-relative
-- shorthand anchors, and no rows outside a clipped scroll viewport.
Panel.ROW_HEIGHT = 28
Panel.COLUMN_WIDTHS = { 30, 160, 58, 120, 82, 110, 48, 80 }
Panel.COLUMN_WEIGHTS = { 0, 4, 0, 2, 0, 2, 0, 1 }
Panel.FILTER_WIDTHS = { 220, 125, 210, 95, 155, 130, 120 }
Panel.FILTER_WEIGHTS = { 1, 0, 0, 0, 0, 0, 0 }

-- Distributes the available width without allowing rounding errors to make
-- the last column overflow the list. The fallback scale also keeps the
-- geometry finite if a caller probes the panel below its normal minimum.
local function distributeWidths(minimums, weights, available)
    local count, result = #minimums, {}
    available = math.max(count, math.floor(tonumber(available) or 0))

    local minTotal, weightTotal = 0, 0
    for i, minimum in ipairs(minimums) do
        minTotal = minTotal + minimum
        weightTotal = weightTotal + (tonumber(weights[i]) or 0)
    end

    local used = 0
    if available < minTotal then
        local scale = available / math.max(1, minTotal)
        for i, minimum in ipairs(minimums) do
            local width
            if i == count then
                width = available - used
            else
                width = math.max(1, math.floor(minimum * scale))
            end
            result[i] = width
            used = used + width
        end
    else
        local extra = available - minTotal
        for i, minimum in ipairs(minimums) do
            local width
            if i == count then
                width = available - used
            else
                width = minimum + math.floor(extra * (tonumber(weights[i]) or 0) /
                    math.max(1, weightTotal))
            end
            result[i] = width
            used = used + width
        end
    end
    return result
end

function Panel.ComputeLayout(width, height)
    width, height = tonumber(width) or 0, tonumber(height) or 0
    local inner = math.max(1, width - 32)
    local mainWidth = math.max(1, inner - 10)
    local left = math.floor(mainWidth * 0.685)
    local right = math.max(1, mainWidth - left)
    local mainHeight = math.max(1, height - 152)
    local viewport = math.max(1, mainHeight - 112)

    -- The last column receives the rounding remainder, so the row and its
    -- header have identical bounds and can never spill into the detail pane.
    local available = math.max(1, left - 22)
    local columnWidths = distributeWidths(Panel.COLUMN_WIDTHS,
        Panel.COLUMN_WEIGHTS, available)
    local columns, x = {}, 0
    for i, w in ipairs(columnWidths) do
        columns[i] = { x = x, width = w, textWidth = math.max(8, w - 10) }
        x = x + w
    end

    local filterGap = 8
    local filterAvailable = math.max(#Panel.FILTER_WIDTHS,
        inner - 20 - filterGap * (#Panel.FILTER_WIDTHS - 1))
    local filterWidths = distributeWidths(Panel.FILTER_WIDTHS,
        Panel.FILTER_WEIGHTS, filterAvailable)
    return { width = width, height = height, inner = inner, left = left, right = right,
        mainY = 140, mainHeight = mainHeight, viewportHeight = viewport,
        visibleRows = math.max(1, math.floor(viewport / Panel.ROW_HEIGHT)),
        rowWidth = available, columns = columns, filterWidths = filterWidths,
        searchWidth = math.max(320, inner - 324), seasonWidth = 212 }
end

-- View formatting only: old default zeros cannot prove that data was captured.
function Panel.DisplayMeasured(run, key)
    local st = type(run.stats) == "table" and run.stats or {}
    local n = tonumber(st[key])
    if n == nil or n < 0 then return "-" end
    local measured
    if key == "enemyForcesFinalPct" then
        measured = (tonumber(st.enemyForcesTotal) or 0) > 0
    elseif key == "deaths" then
        measured = run.completionInfoSource ~= nil
    else
        measured = run.dataSource == "C_DamageMeter"
    end
    if n == 0 and not measured then return "-" end
    if key == "enemyForcesFinalPct" then return string.format("%.1f%%", n) end
    return tostring(math.floor(n + 0.5))
end

local function place(frame, parent, x, y, width, height)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    frame:SetSize(width, height)
end

local function label(parent, value, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if Theme and Theme.ApplyFont then
        Theme:ApplyFont(fs, "normal", size or 13)
    else
        fs:SetFont("Fonts\\FRIZQT__.TTF", size or 13, "")
    end
    fs:SetTextColor(unpack(color or { 0.86, 0.86, 0.87 }))
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("MIDDLE"); fs:SetWordWrap(false)
    fs:SetText(value or "")
    return fs
end

local function button(parent, value, onClick, destructive)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    backdrop(b, destructive and 0.25 or 0.09, 0.075, 0.075, 1, destructive and 0.4 or 0.28)
    b.caption = label(b, value, 13, destructive and {1, 0.5, 0.5} or {0.88, 0.85, 0.74})
    b.caption:SetPoint("LEFT", b, "LEFT", 6, 0); b.caption:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    b.caption:SetJustifyH("CENTER")
    function b:SetText(v) self.caption:SetText(v) end
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function() b:SetBackdropBorderColor(0.7, 0.56, 0.27, 1) end)
    b:SetScript("OnLeave", function() b:SetBackdropBorderColor(destructive and 0.4 or 0.28, 0.25, 0.21, 1) end)
    b:SetScript("OnDisable", function() b.caption:SetAlpha(0.4) end)
    b:SetScript("OnEnable", function() b.caption:SetAlpha(1) end)
    return b
end

local function tooltip(frame, getText)
    frame:HookScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
            GameTooltip:SetText(getText(), 0.92, 0.9, 0.82, 1, true); GameTooltip:Show()
        end
    end)
    frame:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function scrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1); scroll:SetScrollChild(child)
    scroll:SetClipsChildren(true)
    return scroll, child
end

local function dropdown(parent, items, value, onSelect)
    local dd = MitzuMPlus:CreateSimpleDropdown(parent, 160, items, onSelect)
    dd:SetSelectedValue(value)
    return dd
end

function Panel:Create(parent)
    local container = MitzuMPlus.Tabs:CreatePanelContainer(parent)
    self.container = container
    self.searchBar = CreateFrame("Frame", nil, container, "BackdropTemplate")
    self.filterBar = CreateFrame("Frame", nil, container, "BackdropTemplate")
    backdrop(self.searchBar, 0.035, 0.035, 0.042, 1)
    backdrop(self.filterBar, 0.035, 0.035, 0.042, 1)

    self.search = CreateFrame("EditBox", nil, self.searchBar, "BackdropTemplate")
    backdrop(self.search, 0.018, 0.018, 0.022, 1, 0.28)
    if Theme and Theme.ApplyFont then
        Theme:ApplyFont(self.search, "normal", 14)
    else
        self.search:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    end
    self.search:SetAutoFocus(false); self.search:SetTextInsets(10, 10, 0, 0)
    self.searchHint = label(self.search, "Buscar run, mazmorra o jugador...", 14, {0.55,0.55,0.57})
    self.searchHint:SetPoint("LEFT", self.search, "LEFT", 10, 0)
    self.search:SetText(self.filters.search)
    self.search:SetScript("OnTextChanged", function(box, userInput)
        self.searchHint:SetShown((box:GetText() or "") == "")
        if userInput then
            self.filters.search = box:GetText() or ""
            self.filters.page = 1
            self:Refresh()
        end
    end)
    self.searchHint:SetShown((self.search:GetText() or "") == "")
    self.search:SetScript("OnEnterPressed", function(box) box:ClearFocus(); self:ApplyFilters() end)
    self.search:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    self.seasonCaption = label(self.searchBar, "Temporada:", 12)
    self.seasonDD = dropdown(self.searchBar, {{text="Todas",value=""}}, "", function(v)
        self.filters.season, self.filters.page = v, 1; self:Refresh()
    end)

    local function changed(key)
        return function(v) self.filters[key], self.filters.page = v, 1; self:Refresh() end
    end
    local configs = {
        {"dungeon","Mazmorra",{{text="Todas",value=""}}},
        {"result","Resultado",{{text="Todos",value=""},{text="+3",value="+3"},{text="+2",value="+2"},{text="+1",value="+1"},{text="Fuera",value="Fuera"},{text="Incompleta",value="Incompleta"}}},
        {"character","Personaje",{{text="Todos",value=""}}},
        {"role","Rol",{{text="Todos",value=""},{text="Tank",value="TANK"},{text="Healer",value="HEALER"},{text="DPS",value="DAMAGER"}}},
        {"week","Semana",{{text="Todas",value=""},{text="Esta semana",value="this"},{text="Semana pasada",value="last"}}},
        {"extra","Más filtros",{{text="Sin filtro",value=""},{text="Favoritas",value="favorite"},{text="Con notas",value="notes"}}},
    }
    self.filterControls, self.filterCaptions = {}, {}
    for i, def in ipairs(configs) do
        self.filterCaptions[i] = label(self.filterBar, def[2], 12, {0.65,0.65,0.67})
        local dd = dropdown(self.filterBar, def[3], self.filters[def[1]], changed(def[1]))
        self.filterControls[i], self[def[1].."DD"] = dd, dd
    end
    self.exportDD = dropdown(self.filterBar, {{text="Exportar",value=""},{text="CSV",value="csv"},{text="Code",value="code"}}, "", function(v)
        if v == "csv" then MitzuMPlus.Export:ExportToCSV(self.filteredRuns)
        elseif v == "code" then MitzuMPlus.Export:ExportToCode() end
        self.exportDD:SetSelectedValue("")
    end)
    self.filterControls[7] = self.exportDD

    self.main = CreateFrame("Frame", nil, container)
    self.list = CreateFrame("Frame", nil, self.main, "BackdropTemplate")
    self.detail = CreateFrame("Frame", nil, self.main, "BackdropTemplate")
    backdrop(self.list, 0.025, 0.025, 0.03, 1, 0.22)
    backdrop(self.detail, 0.04, 0.038, 0.032, 1, 0.30)
    self.countText = label(self.list, "", 13)
    self.sortCaption = label(self.list, "Ordenar por:", 12, {0.65,0.65,0.67})
    self.sortDD = dropdown(self.list, {
        {text="Fecha (más reciente)",value="date"}, {text="Nivel",value="level"},
        {text="Resultado",value="result"},{text="Mazmorra",value="dungeon"}
    }, self.filters.sortBy, changed("sortBy"))
    self.header = CreateFrame("Frame", nil, self.list, "BackdropTemplate")
    backdrop(self.header, 0.09, 0.077, 0.045, 1, 0.25)
    self.header.cells = {}
    for i, col in ipairs(self.COLUMNS) do
        self.header.cells[i] = label(self.header, col.title, 12, {0.82,0.72,0.47})
        if col.key == "role" then self.header.cells[i]:SetJustifyH("CENTER") end
    end
    self.rowScroll, self.rowChild = scrollArea(self.list)
    self.rows = {}
    for i = 1, self.ROWS do
        local row = CreateFrame("Button", nil, self.rowChild, "BackdropTemplate")
        row.cells = {}
        for c = 1, #self.COLUMNS do row.cells[c] = label(row, "", 13) end
        row.roleIcon = row:CreateTexture(nil, "ARTWORK")
        row.roleIcon:SetSize(14, 14)
        row.roleIcon:Hide()
        row:SetScript("OnClick", function() if row.run then self:SelectRun(row.run) end end)
        tooltip(row, function()
            local run = row.run or {}
            return (run.dungeonName or "-") .. "\n" .. charName(run) .. "\n" .. (select(3, self.FormatResult(run)))
        end)
        self.rows[i] = row
    end
    self.empty = label(self.list, "", 14)
    self.empty:SetJustifyH("CENTER")
    self.pager = CreateFrame("Frame", nil, self.list, "BackdropTemplate")
    backdrop(self.pager, 0.04, 0.04, 0.047, 1, 0.18)
    self.prev = button(self.pager, "<", function() self.filters.page=self.filters.page-1; self:Refresh() end)
    self.next = button(self.pager, ">", function() self.filters.page=self.filters.page+1; self:Refresh() end)
    self.pageButtons = {}
    for i=1,5 do
        local b = button(self.pager, "", function() self.filters.page=self.pageButtons[i].page; self:Refresh() end)
        self.pageButtons[i]=b
    end
    self.pageText = label(self.pager, "", 12)
    self.perCaption = label(self.pager, "Por página:", 12)
    self.pageSizeDD = dropdown(self.pager, {{text="10",value=10},{text="20",value=20},{text="50",value=50}}, self.filters.pageSize, function(v)
        self.filters.pageSize, self.filters.page = tonumber(v) or 20, 1
        self:Refresh()
    end)
    self:CreateDetail()
    container:SetScript("OnSizeChanged", function() self:Layout() end)
    container:SetScript("OnShow", function() self:Layout(); self:Refresh() end)
    MitzuMPlus.Tabs:RegisterPanel("historial", container)
    self:Layout()
    return container
end

function Panel:CreateDetail()
    local d = self.detail
    self.dungeonIcon = d:CreateTexture(nil,"ARTWORK")
    self.detailTitle = label(d, "Detalle de run", 17, {0.91,0.79,0.49})
    self.detailTitle:SetWordWrap(true)
    self.detailLevel = label(d, "", 13)
    self.detailResult = label(d, "-", 27, {0.36,0.86,0.5})
    self.detailResult:SetJustifyH("CENTER")
    self.detailMargin = label(d, "", 14)
    self.detailMargin:SetJustifyH("CENTER")
    self.cards = {}
    for i,name in ipairs({"Duración","Resultado","Fuerzas","Muertes"}) do
        local card=CreateFrame("Frame",nil,d,"BackdropTemplate")
        backdrop(card,0.025,0.025,0.029,1,0.19)
        card.caption=label(card,name,12,{0.6,0.6,0.62})
        card.value=label(card,"-",14)
        card.caption:SetPoint("TOP",card,"TOP",0,-7)
        card.caption:SetJustifyH("CENTER")
        card.value:SetPoint("BOTTOM",card,"BOTTOM",0,8)
        card.value:SetJustifyH("CENTER")
        self.cards[i]=card
    end
    self.detailTabs = CreateFrame("Frame",nil,d)
    self.detailButtons={}
    for i,def in ipairs({{"summary","Resumen"},{"group","Grupo"},{"metrics","Métricas"},{"notes","Notas"}}) do
        local id=def[1]
        local b=button(self.detailTabs,def[2],function() self.detailTab=id; self:RefreshDetail() end)
        self.detailButtons[id]=b; b.order=i
    end
    self.detailScroll,self.detailBody=scrollArea(d)
    self.detailLines={}
    for i=1,18 do
        local fs=label(self.detailBody,"",13)
        fs:SetWordWrap(true); fs:SetJustifyV("TOP")
        self.detailLines[i]=fs
    end
    self.notePanel=CreateFrame("Frame",nil,d,"BackdropTemplate")
    backdrop(self.notePanel,0.02,0.02,0.025,1,0.3)
    self.noteScroll=CreateFrame("ScrollFrame",nil,self.notePanel,"UIPanelScrollFrameTemplate")
    self.notesBox=CreateFrame("EditBox",nil,self.noteScroll)
    self.notesBox:SetMultiLine(true); self.notesBox:SetAutoFocus(false)
    if Theme and Theme.ApplyFont then
        Theme:ApplyFont(self.notesBox, "normal", 14)
    else
        self.notesBox:SetFont("Fonts\\FRIZQT__.TTF",14,"")
    end
    self.notesBox:SetTextInsets(4,4,4,4)
    self.notesBox:SetScript("OnEscapePressed",function(box) box:ClearFocus() end)
    self.noteScroll:SetScrollChild(self.notesBox)
    self.saveNote=button(d,"Guardar nota",function()
        if self.selectedRun then
            local saved = MitzuMPlus.DataManager:SetRunNotes(self.selectedRun.runID,self.notesBox:GetText() or "")
            self.notesBox:ClearFocus()
            if saved then self:Refresh() end
        end
    end)
    self.actions=CreateFrame("Frame",nil,d,"BackdropTemplate")
    backdrop(self.actions,0.035,0.032,0.027,1,0.2)
    self.favorite=button(self.actions,"Favorita",function()
        if self.selectedRun then MitzuMPlus.DataManager:ToggleFavorite(self.selectedRun.runID); self:Refresh() end
    end)
    self.noteAction=button(self.actions,"Añadir nota",function() self.detailTab="notes"; self:RefreshDetail(); self.notesBox:SetFocus() end)
    self.copy=button(self.actions,"Copiar",function()
        if self.selectedRun then MitzuMPlus.Export:ExportToCSV({self.selectedRun}) end
    end)
    self.delete=button(self.actions,"Eliminar",function()
        if self.selectedRun then StaticPopup_Show("MITZUMPLUS_CONFIRM_DELETE",self.selectedRun.runID,nil,self.selectedRun.runID) end
    end,true)
end

function Panel:Layout()
    if not self.container then return end
    local w,h=self.container:GetWidth(),self.container:GetHeight()
    -- RenderizadoNuevo enforces 1240x700, which gives this panel a 560 px
    -- content area after the titlebar, tabs and footer. Wait for that minimum
    -- during the transient zero-size phase after /reload.
    if not w or w < 900 or not h or h < 560 then return end
    local g=self.ComputeLayout(w,h); self.geometry=g
    place(self.searchBar,self.container,16,12,g.inner,46)
    place(self.search,self.searchBar,10,8,g.searchWidth,30)
    place(self.seasonCaption,self.searchBar,g.searchWidth+24,8,78,30)
    place(self.seasonDD,self.searchBar,g.searchWidth+102,8,212,30)
    place(self.filterBar,self.container,16,66,g.inner,62)
    local x=10
    for i,dd in ipairs(self.filterControls) do
        local width=g.filterWidths[i]
        if self.filterCaptions[i] then place(self.filterCaptions[i],self.filterBar,x,5,width,17) end
        place(dd,self.filterBar,x,26,width,28); x=x+width+8
        if i == #self.filterControls then x = x - 8 end
    end
    place(self.main,self.container,16,g.mainY,g.inner,g.mainHeight)
    place(self.list,self.main,0,0,g.left,g.mainHeight)
    place(self.detail,self.main,g.left+10,0,g.right,g.mainHeight)
    place(self.countText,self.list,10,4,g.left-310,30)
    place(self.sortCaption,self.list,g.left-296,4,80,30)
    place(self.sortDD,self.list,g.left-212,5,202,28)
    place(self.header,self.list,1,38,g.rowWidth,30)
    place(self.rowScroll,self.list,1,68,g.rowWidth,g.viewportHeight)
    self.rowChild:SetWidth(g.rowWidth)
    for i,col in ipairs(g.columns) do
        place(self.header.cells[i],self.header,col.x+5,0,col.textWidth,30)
    end
    for i,row in ipairs(self.rows) do
        place(row,self.rowChild,0,(i-1)*self.ROW_HEIGHT,g.rowWidth,self.ROW_HEIGHT)
        for c,col in ipairs(g.columns) do place(row.cells[c],row,col.x+5,0,col.textWidth,self.ROW_HEIGHT) end
        local roleCol = g.columns[7]
        if roleCol and row.roleIcon then
            row.roleIcon:ClearAllPoints()
            row.roleIcon:SetPoint("CENTER", row, "TOPLEFT", roleCol.x + math.floor(roleCol.width / 2), -math.floor(self.ROW_HEIGHT / 2))
            row.roleIcon:SetSize(14,14)
        end
    end
    place(self.empty,self.list,12,90,g.left-24,70)
    place(self.pager,self.list,1,g.mainHeight-44,g.left-2,43)
    place(self.prev,self.pager,8,7,30,28)
    for i,b in ipairs(self.pageButtons) do place(b,self.pager,42+(i-1)*32,7,28,28) end
    place(self.next,self.pager,206,7,30,28)
    place(self.pageText,self.pager,248,7,120,28)
    place(self.perCaption,self.pager,g.left-182,7,88,28)
    place(self.pageSizeDD,self.pager,g.left-92,7,80,28)

    local dw=g.right
    place(self.dungeonIcon,self.detail,14,12,54,54)
    place(self.detailTitle,self.detail,78,9,dw-92,42)
    place(self.detailLevel,self.detail,78,53,dw-92,22)
    place(self.detailResult,self.detail,14,82,dw-28,34)
    place(self.detailMargin,self.detail,14,117,dw-28,22)
    local cw=(dw-46)/4
    for i,card in ipairs(self.cards) do place(card,self.detail,14+(i-1)*(cw+6),148,cw,54) end
    place(self.detailTabs,self.detail,14,214,dw-28,30)
    local tw=(dw-40)/4
    for _,b in pairs(self.detailButtons) do place(b,self.detailTabs,(b.order-1)*(tw+4),0,tw,30) end
    local bodyHeight=math.max(1,g.mainHeight-318)
    place(self.detailScroll,self.detail,14,256,dw-46,bodyHeight)
    self.detailBody:SetWidth(dw-46)
    -- En la altura mínima el botón de guardar debe seguir debajo del editor;
    -- el cálculo anterior imponía 90 px al panel y lo hacía solaparse.
    local saveY = math.max(312, g.mainHeight-96)
    local noteHeight = math.max(48, saveY-256-8)
    local noteViewport = math.max(32, noteHeight-16)
    place(self.notePanel,self.detail,14,256,dw-28,noteHeight)
    place(self.noteScroll,self.notePanel,8,8,dw-70,noteViewport)
    self.notesBox:SetWidth(dw-70); self.notesBox:SetHeight(noteViewport)
    place(self.saveNote,self.detail,14,saveY,130,28)
    place(self.actions,self.detail,1,g.mainHeight-52,dw-2,51)
    local usable = math.max(1, dw - 16)
    local favW, noteW, copyW, deleteW = 84, 96, 68, 74
    local gaps = 12
    local fixed = favW + noteW + copyW + deleteW + gaps
    if usable > fixed then
        local extra = usable - fixed
        favW = favW + math.floor(extra * 0.25)
        noteW = noteW + math.floor(extra * 0.45)
        copyW = copyW + math.floor(extra * 0.15)
        deleteW = deleteW + (extra - math.floor(extra * 0.25) - math.floor(extra * 0.45) - math.floor(extra * 0.15))
    elseif usable < fixed then
        local scale = math.max(0.55, (usable - gaps) / math.max(1, fixed - gaps))
        favW = math.floor(favW * scale)
        noteW = math.floor(noteW * scale)
        copyW = math.floor(copyW * scale)
        deleteW = math.floor(deleteW * scale)
    end
    local ax = 8
    place(self.favorite,self.actions,ax,11,favW,30); ax=ax+favW+4
    place(self.noteAction,self.actions,ax,11,noteW,30); ax=ax+noteW+4
    place(self.copy,self.actions,ax,11,copyW,30); ax=ax+copyW+4
    place(self.delete,self.actions,ax,11,math.min(deleteW, dw-ax-8),30)
    self:RefreshDetail()
end

function Panel:StyleRows()
    for i,row in ipairs(self.rows or {}) do
        local selected=row.run and row.run==self.selectedRun
        backdrop(row,selected and 0.13 or (i%2==0 and 0.045 or 0.027),
            selected and 0.105 or 0.035,selected and 0.055 or 0.04,1,0.10)
        if selected then row:SetBackdropBorderColor(0.54,0.43,0.19,1) end
    end
end

function Panel:SelectRun(run)
    self.selectedRun=run; self:StyleRows(); self:RefreshDetail()
end

function Panel:Refresh()
    if not self.container then return end
    local runs=MitzuMPlus.GetAllRuns and MitzuMPlus:GetAllRuns() or {}
    local dungeonItems=uniqueItems(runs,function(r)return r.dungeonName end,"Todas")
    local characterItems=uniqueItems(runs,charName,"Todos")
    local seasons={{text="Todas las temporadas",value=""}}; local seen={}
    for _,run in ipairs(runs) do
        local key=run.seasonKey
        if key and key~="" and not seen[key] then
            seen[key]=true; seasons[#seasons+1]={text=run.seasonName or key,value=key}
        end
    end
    table.sort(seasons,function(a,b)
        if a.value=="" then return true end
        if b.value=="" then return false end
        return tostring(a.text or a.value)<tostring(b.text or b.value)
    end)

    local function validValue(items,value)
        if value==nil or value=="" then return true end
        for _,item in ipairs(items) do if item.value==value then return true end end
        return false
    end
    if not validValue(dungeonItems,self.filters.dungeon) then self.filters.dungeon="" end
    if not validValue(characterItems,self.filters.character) then self.filters.character="" end
    if not validValue(seasons,self.filters.season) then self.filters.season="" end

    self.dungeonDD:SetItems(dungeonItems)
    self.characterDD:SetItems(characterItems)
    self.seasonDD:SetItems(seasons)
    for _,key in ipairs({"dungeon","character","season"}) do
        self[key.."DD"]:SetSelectedValue(self.filters[key])
    end
    self.filteredRuns=self.FilterRuns(runs,self.filters)
    local pageRuns,page,pages=self.Paginate(self.filteredRuns,self.filters.page,self.filters.pageSize)
    self.filters.page=page
    self.countText:SetText(string.format("%d runs encontradas",#self.filteredRuns))
    self.pageText:SetText(string.format("%d / %d",page,pages))
    self.prev:SetEnabled(page>1); self.next:SetEnabled(page<pages)
    local first=math.max(1,math.min(page-2,pages-4))
    for i,b in ipairs(self.pageButtons) do
        b.page=first+i-1; b:SetText(tostring(b.page)); b:SetShown(b.page<=pages)
        b:SetEnabled(b.page~=page)
        b:SetBackdropColor(b.page==page and 0.2 or 0.07,b.page==page and 0.16 or 0.07,0.06,1)
    end
    for i,row in ipairs(self.rows) do
        local run=pageRuns[i]; row.run=run
        if run then
            local result=select(3,self.FormatResult(run))
            local values={tostring((page-1)*self.filters.pageSize+i),run.dungeonName or "-",
                (tonumber(run.keyLevel) or 0)>0 and ("+"..run.keyLevel) or "-",result,
                (tonumber(run.completionTime) or 0)>0 and fmtTime(run.completionTime) or "-",
                charName(run),"",dateText(run.startTime)}
            for c,v in ipairs(values) do row.cells[c]:SetText(v) end
            setRoleIcon(row.roleIcon, run.playerRole)
            row:Show()
        else
            if row.roleIcon then row.roleIcon:Hide() end
            row:Hide()
        end
    end
    self.rowChild:SetHeight(math.max(1,#pageRuns*self.ROW_HEIGHT))
    self.rowScroll:SetVerticalScroll(0)
    self.empty:SetText(#runs==0 and "Aún no hay runs registradas." or "No hay runs que coincidan con estos filtros.")
    self.empty:SetShown(#pageRuns==0)
    -- Selection must correspond to a row on this page.
    local selected
    for _,run in ipairs(pageRuns) do
        if self.selectedRun and run.runID==self.selectedRun.runID then selected=run end
    end
    self.selectedRun=selected or pageRuns[1]
    self:StyleRows(); self:RefreshDetail()
end

function Panel:RefreshDetail()
    if not self.detailTitle then return end
    local run=self.selectedRun
    for _,fs in ipairs(self.detailLines) do fs:Hide() end
    local notes=self.detailTab=="notes" and run~=nil
    self.notePanel:SetShown(notes); self.saveNote:SetShown(notes)
    self.detailScroll:SetShown(not notes)
    for id,b in pairs(self.detailButtons) do
        b:SetEnabled(id~=self.detailTab)
        b:SetBackdropColor(id==self.detailTab and 0.18 or 0.07,id==self.detailTab and 0.14 or 0.07,0.05,1)
    end
    for _,b in ipairs({self.favorite,self.noteAction,self.copy,self.delete}) do b:SetEnabled(run~=nil) end
    if not run then
        self.detailTitle:SetText("Detalle de run"); self.detailLevel:SetText("Selecciona una run")
        self.detailResult:SetText("-"); self.detailMargin:SetText("")
        self.dungeonIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        for _,card in ipairs(self.cards) do card.value:SetText("-") end
        return
    end
    local code,margin=self.FormatResult(run)
    self.detailTitle:SetText(run.dungeonName or "Mazmorra desconocida")
    self.detailLevel:SetText("Nivel de llave "..((tonumber(run.keyLevel) or 0)>0 and ("+"..run.keyLevel) or "-"))
    self.detailResult:SetText(code)
    if code=="Incompleta" then
        self.detailResult:SetTextColor(0.62,0.62,0.62,1)
    else
        self.detailResult:SetTextColor(run.inTime and 0.35 or 0.95,run.inTime and 0.84 or 0.35,0.4,1)
    end
    self.detailMargin:SetText(margin and ("("..(margin>=0 and "+" or "")..fmtTime(margin)..")") or "Margen no registrado")
    local icon=run.dungeonIcon
    if not icon and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and run.dungeonID then
        local ok,_,_,_,texture=pcall(C_ChallengeMode.GetMapUIInfo,run.dungeonID)
        if ok then icon=texture end
    end
    self.dungeonIcon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local cards={(tonumber(run.completionTime) or 0)>0 and fmtTime(run.completionTime) or "-",
        code,self.DisplayMeasured(run,"enemyForcesFinalPct"),self.DisplayMeasured(run,"deaths")}
    for i,v in ipairs(cards) do self.cards[i].value:SetText(v) end
    local lines={}
    if self.detailTab=="summary" then
        lines={"Temporada: "..tostring(run.seasonName or run.seasonKey or "-"),
            "Fecha: "..dateText(run.startTime),"Personaje: "..charName(run),"Rol: "..roleText(run.playerRole),
            "Nota: "..(run.notes and run.notes~="" and run.notes or "-"),
            "Etiquetas: "..(type(run.tags)=="table" and #run.tags>0 and table.concat(run.tags,", ") or "-")}
    elseif self.detailTab=="group" then
        local group=type(run.group)=="table" and run.group or {}
        lines[1]=#group<5 and "Datos parciales" or "Grupo registrado"
        for _,m in ipairs(group) do
            lines[#lines+1]=(m.name or "Desconocido")..(m.realm and m.realm~="" and ("-"..m.realm) or "")..
                "\n"..tostring(m.class or "-").."  -  "..roleText(m.role)
        end
        if #group==0 then lines[2]="No hay miembros registrados." end
    elseif self.detailTab=="metrics" then
        for _,entry in ipairs({{"Daño total","damageTotal",true},{"Sanación total","healingTotal",true},{"Daño recibido","damageTaken",true},
            {"Interrupciones","kicks",false},{"Disipaciones","dispels",false},{"Muertes del grupo","deaths",false}}) do
            local raw = self.DisplayMeasured(run,entry[2])
            if entry[3] and raw ~= "-" then raw = compactMetric(raw) end
            lines[#lines+1]=entry[1]..": "..raw
        end
        if MitzuMPlus.RunMetrics then
            local value,unit=MitzuMPlus.RunMetrics:GetRoleMetric(run)
            if value then lines[#lines+1]=tostring(unit)..": "..compactMetric(value) end
        end
    elseif notes then
        self.notesBox:SetText(run.notes or "")
    end
    local y=0; local width=self.geometry and self.geometry.right-46 or 350
    for i,v in ipairs(lines) do
        local fs=self.detailLines[i]
        if fs then
            fs:ClearAllPoints(); fs:SetPoint("TOPLEFT",self.detailBody,"TOPLEFT",0,-y)
            fs:SetWidth(width); fs:SetText(v); fs:Show()
            y=y+math.max(18,fs:GetStringHeight())+10
        end
    end
    self.detailBody:SetHeight(math.max(1,y)); self.detailScroll:SetVerticalScroll(0)
    self.favorite:SetText(run.isFavorite and "Favorita: Sí" or "Favorita")
end

function Panel:RefreshTable() self:Refresh() end
function Panel:ApplyFilters()
    self.filters.search=self.search and self.search:GetText() or ""
    self.filters.page=1; self:Refresh()
end
return Panel
