-- MitzuMPlus M+ Historial - indice agregado de companeros y perfil individual.
local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local Theme, Widgets = MitzuMPlus.Theme, MitzuMPlus.Widgets
local L = MitzuMPlus.L
local wipe = wipe

local PanelPlayers = {}
MitzuMPlus.PanelPlayers = PanelPlayers

-- 1.1.0-dev.10: los nombres de clase los da Blizzard ya traducidos al idioma
-- del cliente (LOCALIZED_CLASS_NAMES_*). Mitzu no mantiene su propia lista:
-- un cliente ingles veria "Paladin" y uno espanol "Paladin de la Luz" sin que
-- este fichero sepa nada de idiomas.
local function ClassName(classFile)
    if type(classFile) ~= "string" or classFile == "" then return nil end
    local male = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
    local female = rawget(_G, "LOCALIZED_CLASS_NAMES_FEMALE")
    return (type(male) == "table" and male[classFile])
        or (type(female) == "table" and female[classFile])
        or classFile
end

local CLASS_TOKENS = {
    "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK",
    "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}
local CLASS_COLOR = {
    DEATHKNIGHT={r=.77,g=.12,b=.23}, DEMONHUNTER={r=.64,g=.19,b=.79},
    DRUID={r=1,g=.49,b=.04}, EVOKER={r=.2,g=.58,b=.5}, HUNTER={r=.67,g=.83,b=.45},
    MAGE={r=.25,g=.78,b=.92}, MONK={r=0,g=1,b=.59}, PALADIN={r=.96,g=.55,b=.73},
    PRIEST={r=1,g=1,b=1}, ROGUE={r=1,g=.96,b=.41}, SHAMAN={r=0,g=.44,b=.87},
    WARLOCK={r=.53,g=.53,b=.93}, WARRIOR={r=.78,g=.61,b=.43},
}
local ROLE_LABEL = {TANK="Tank", HEALER="Healer", DAMAGER="DPS", NONE="DPS"}
local ROLE_COLOR = {TANK={r=.3,g=.7,b=1}, HEALER={r=.25,g=.95,b=.45}, DAMAGER={r=1,g=.45,b=.4}}
local ROLE_SORT = {TANK=1, HEALER=2, DAMAGER=3, NONE=3}
local QUALITY_COLOR = {
    [0]={.62,.62,.62}, [1]={1,1,1}, [2]={.12,1,0}, [3]={0,.44,.87},
    [4]={.64,.21,.93}, [5]={1,.5,0}, [6]={.9,.8,.5},
}

local LIST_COLS = {
    {key="identity",text=L["COL_PLAYER"],w=.27}, {key="role",text=L["COL_ROLE"],w=.08},
    {key="rio",text=L["PLR_SCORE"],w=.12,numeric=true}, {key="runs",text=L["COL_RUNS"],w=.07,numeric=true},
    {key="success",text=L["COL_SUCCESS"],w=.09,numeric=true}, {key="best",text=L["COL_BEST"],w=.08,numeric=true},
    {key="deaths",text=L["COL_DEATHS"],w=.12,numeric=true}, {key="last",text=L["PLR_LAST"],w=.17,numeric=true},
}
local RUN_COLS = {
    {key="dungeon",text=L["COL_DUNGEON"],w=.28}, {key="level",text=L["COL_LEVEL"],w=.08,numeric=true},
    {key="result",text=L["COL_RESULT"],w=.13}, {key="duration",text=L["COL_TIME"],w=.11,numeric=true},
    {key="metric",text="DPS/HPS/DTPS",w=.18,numeric=true}, {key="deaths",text=L["COL_DEATHS"],w=.10,numeric=true},
    {key="date",text=L["COL_DATE"],w=.12,numeric=true},
}
local ROW_H, RUN_ROW_H = 40, 34

local function GetClassColor(class)
    return (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]) or CLASS_COLOR[class] or {r=.8,g=.8,b=.8}
end
local function Role(role) return (role == "TANK" or role == "HEALER") and role or "DAMAGER" end
local function FNum(value)
    value = tonumber(value) or 0
    if MitzuMPlus.Formatters and MitzuMPlus.Formatters.FormatDPS then
        return MitzuMPlus.Formatters:FormatDPS(value)
    end
    return tostring(math.floor(value + .5))
end
local function MMSS(sec)
    sec = tonumber(sec) or 0
    return sec > 0 and string.format("%02d:%02d", math.floor(sec/60), math.floor(sec%60)) or "-"
end
local function ShortDate(ts)
    ts = tonumber(ts) or 0
    if ts <= 0 then return "-" end
    local delta = math.max(0, (time and time() or ts) - ts)
    if delta < 86400 then return "Hoy" elseif delta < 172800 then return "Ayer" end
    local ok, value = pcall(date, "%d/%m", ts)
    return ok and value or "-"
end
local function PlayerKey(name, realm)
    name, realm = tostring(name or ""), tostring(realm or "")
    if realm == "" then
        local n, r = name:match("^(.-)%-(.+)$")
        if n and r then name, realm = n, r end
    end
    return string.lower(name.."-"..realm), name, realm
end

local function RaiderIOScore(player)
    if type(player) ~= "table" then return nil, "NO_PLAYER" end
    if player._rioChecked then return player.rioScore, player.rioState end
    player._rioChecked = true

    local function SavedOr(state)
        local saved = tonumber(player.savedRaiderIOScore) or 0
        if saved > 0 then
            player.rioScore = saved
            player.rioState = "SAVED"
            return saved, player.rioState
        end
        player.rioState = state
        return nil, player.rioState
    end

    local rio = _G.RaiderIO
    if type(rio) ~= "table" or type(rio.GetProfile) ~= "function" then
        return SavedOr("NO_ADDON")
    end

    local realm = tostring(player.realm or "")
    if realm == "" and GetNormalizedRealmName then
        realm = tostring(GetNormalizedRealmName() or "")
    end
    if tostring(player.name or "") == "" or realm == "" then
        return SavedOr("NO_IDENTITY")
    end

    -- Raider.IO exposes a supported in-game API backed by its local snapshot.
    local ok, profile = pcall(rio.GetProfile, player.name, realm)
    if not ok or type(profile) ~= "table" or profile.success == false then
        return SavedOr("NO_PROFILE")
    end
    local mplus = profile.mythicKeystoneProfile
    if type(mplus) ~= "table" or mplus.hasRenderableData == false then
        return SavedOr("NO_DATA")
    end
    local score = tonumber(mplus.currentScore)
    if not score then return SavedOr("NO_SCORE") end
    player.rioScore = score
    player.rioProfile = profile
    player.rioState = "OK"
    return score, player.rioState
end

local function RaiderIOColor(score)
    local rio = _G.RaiderIO
    if score and type(rio) == "table" and type(rio.GetScoreColor) == "function" then
        local ok, r, g, b = pcall(rio.GetScoreColor, score)
        if ok and tonumber(r) and tonumber(g) and tonumber(b) then
            return {r=r,g=g,b=b}
        end
    end
    return Theme.GOLD.gold4
end
local function IsLocal(member, run)
    if member.isPlayer then return true end
    local _, mn, mr = PlayerKey(member.name or member.playerName, member.realm)
    local _, pn, pr = PlayerKey(run.playerName, run.playerRealm)
    if mn == "" or pn == "" or string.lower(mn) ~= string.lower(pn) then return false end
    return mr == "" or pr == "" or string.lower(mr) == string.lower(pr)
end
local function StatsLookup(run)
    local out = {}
    for _, s in ipairs(type(run.groupStats) == "table" and run.groupStats or {}) do
        if type(s) == "table" then
            local key, name = PlayerKey(s.name or s.playerName, s.realm)
            if name ~= "" then out[key], out[string.lower(name)] = s, out[string.lower(name)] or s end
        end
    end
    return out
end
local function NormalizeMember(raw, run, lookup)
    local key, name, realm = PlayerKey(raw.name or raw.playerName, raw.realm)
    local s = lookup[key] or lookup[string.lower(name)] or {}
    local function Pick(field, alt1, alt2)
        local v = tonumber(s[field]) or tonumber(raw[field])
        if not v and alt1 then v = tonumber(s[alt1]) or tonumber(raw[alt1]) end
        if not v and alt2 then v = tonumber(s[alt2]) or tonumber(raw[alt2]) end
        return v or 0
    end
    local m = {
        key=key,name=name,realm=realm,class=raw.class or s.class or "",role=Role(raw.role or s.role),
        spec=raw.spec or s.spec or "",specID=tonumber(raw.specID or s.specID) or 0,
        rating=tonumber(raw.mythicRating or s.mythicRating) or 0,
        raiderIOScore=tonumber(raw.raiderIOScore or s.raiderIOScore) or 0,
        damage=Pick("damage","damageDone","damageTotal"), healing=Pick("healing","healingDone","healingTotal"),
        taken=Pick("damageTaken","damageReceived","takenDamage"), deaths=Pick("deaths"),
        run=run,isPlayer=IsLocal(raw,run),
    }
    m.hasMetrics = m.damage>0 or m.healing>0 or m.taken>0 or m.deaths>0
    return m
end
local function RunMembers(run)
    local out, seen, lookup = {}, {}, StatsLookup(run)
    local source = type(run.group)=="table" and #run.group>0 and run.group or run.groupStats
    for _, raw in ipairs(type(source)=="table" and source or {}) do
        if type(raw)=="table" then
            local m = NormalizeMember(raw,run,lookup)
            if m.name~="" and not seen[m.key] then seen[m.key]=true; out[#out+1]=m end
        end
    end
    return out
end
local function MemberLoot(run,m)
    if type(run.loot)~="table" then return {} end
    local full = m.realm~="" and (m.name.."-"..m.realm) or m.name
    return type(run.loot[full])=="table" and run.loot[full] or (type(run.loot[m.name])=="table" and run.loot[m.name] or {})
end
local function Destroy(list)
    if not list then return end
    for _, frame in ipairs(list) do frame:Hide(); if frame.SetParent then frame:SetParent(nil) end end
    wipe(list)
end
local function StyleRow(row,index)
    row:SetBackdrop(Theme.BACKDROPS.simple)
    row._normalBG = index%2==1 and Theme.BG.rowOdd or Theme.BG.rowEven
    Theme:SetBackdropColor(row,row._normalBG)
    row:SetScript("OnEnter",function(f) Theme:SetBackdropColor(f,Theme.BG.rowHover) end)
    row:SetScript("OnLeave",function(f) Theme:SetBackdropColor(f,f._normalBG) end)
    local line=row:CreateTexture(nil,"BORDER"); line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
    line:SetTexture("Interface\\Buttons\\WHITE8X8"); Theme:SetVertexColor(line,Theme.BORDER.panel)
end
local function NewCell(row,col,offset,size)
    local fs=row:CreateFontString(nil,"OVERLAY"); Theme:ApplyFont(fs,"mono",size or 11); fs:SetWordWrap(false)
    fs:SetPoint("LEFT",row,"LEFT",offset.x+(col.numeric and 4 or 10),0)
    fs:SetWidth(math.max(8,offset.w-(col.numeric and 8 or 14))); fs:SetJustifyH(col.numeric and "CENTER" or "LEFT")
    return fs
end
local function LayoutColumns(header,cols,width)
    if not width or width<100 then return nil end
    local offsets,x={},0
    for _,col in ipairs(cols) do
        local w=math.floor(width*col.w); offsets[col.key]={x=x,w=w}
        local b=header.columns[col.key]; b:ClearAllPoints(); b:SetPoint("LEFT",header,"LEFT",x,0); b:SetWidth(w); x=x+w
    end
    return offsets
end
local function SortHeader(parent,cols,onSort)
    local h=CreateFrame("Frame",nil,parent,BackdropTemplateMixin and "BackdropTemplate"); h:SetHeight(32)
    h:SetBackdrop(Theme.BACKDROPS.simple); Theme:SetBackdropColor(h,Theme.BG.titlebar); h.columns={}
    for _,col in ipairs(cols) do
        local b=CreateFrame("Button",nil,h); b:SetHeight(32)
        local fs=b:CreateFontString(nil,"OVERLAY"); Theme:ApplyFont(fs,"mono",11); fs:SetWordWrap(false)
        fs:SetPoint("LEFT",col.numeric and 2 or 10,0); fs:SetPoint("RIGHT",col.numeric and -2 or -6,0)
        fs:SetJustifyH(col.numeric and "CENTER" or "LEFT"); fs:SetText(col.text); Theme:SetTextColor(fs,Theme.GOLD.gold3)
        b.label=fs; b:SetScript("OnClick",function() onSort(col.key) end)
        local hover=b:CreateTexture(nil,"BACKGROUND");hover:SetAllPoints();hover:SetTexture("Interface\\Buttons\\WHITE8X8")
        hover:SetVertexColor(Theme.GOLD.gold3.r,Theme.GOLD.gold3.g,Theme.GOLD.gold3.b,.16);hover:Hide()
        b:SetScript("OnEnter",function() hover:Show();Theme:SetTextColor(fs,Theme.GOLD.gold5) end)
        b:SetScript("OnLeave",function() hover:Hide();Theme:SetTextColor(fs,b.active and Theme.GOLD.gold5 or Theme.GOLD.gold3) end)
        local d=b:CreateTexture(nil,"BORDER"); d:SetPoint("TOPRIGHT"); d:SetPoint("BOTTOMRIGHT"); d:SetWidth(1)
        d:SetTexture("Interface\\Buttons\\WHITE8X8"); Theme:SetVertexColor(d,Theme.BORDER.separator)
        h.columns[col.key]=b
    end
    function h:SetSort(key,desc)
        for _,col in ipairs(cols) do
            local b=self.columns[col.key]; b.active=col.key==key
            b.label:SetText(col.text..(b.active and (desc and "  v" or "  ^") or ""))
            Theme:SetTextColor(b.label,b.active and Theme.GOLD.gold5 or Theme.GOLD.gold3)
        end
    end
    return h
end
local function ToolbarLabel(parent,text,anchor)
    local fs=parent:CreateFontString(nil,"OVERLAY"); Theme:ApplyFont(fs,"mono",9); Theme:SetTextColor(fs,Theme.TEXT.dim)
    fs:SetText(text); fs:SetPoint("BOTTOMLEFT",anchor,"TOPLEFT",0,3)
end

function PanelPlayers:Create(parent)
    local c=MitzuMPlus.Tabs and MitzuMPlus.Tabs.CreatePanelContainer and MitzuMPlus.Tabs:CreatePanelContainer(parent) or CreateFrame("Frame",nil,parent)
    self.container=c; self.listRows={}; self.listExtras={}; self.profileRows={}; self.profileExtras={}
    self.searchText=""; self.roleFilter="ALL"; self.classFilter="ALL"; self.listSortKey="runs"; self.listSortDesc=true
    self.runSortKey="date"; self.runSortDesc=true
    self:CreateListView(c); self:CreateProfileView(c)
    if MitzuMPlus.Tabs then MitzuMPlus.Tabs:RegisterPanel("players",c) end
    return c
end

function PanelPlayers:CreateListView(parent)
    local view=CreateFrame("Frame",nil,parent); view:SetAllPoints(); view:EnableMouse(true); self.listView=view
    local bar=CreateFrame("Frame",nil,view,BackdropTemplateMixin and "BackdropTemplate")
    bar:SetPoint("TOPLEFT",10,-10); bar:SetPoint("TOPRIGHT",-10,-10); bar:SetHeight(50)
    bar:SetBackdrop(Theme.BACKDROPS.simple); Theme:SetBackdropColor(bar,Theme.BG.panel)
    local search=CreateFrame("EditBox",nil,bar,BackdropTemplateMixin and "BackdropTemplate")
    search:SetPoint("BOTTOMLEFT",10,7); search:SetSize(300,25); search:SetAutoFocus(false); search:SetTextInsets(9,24,0,0)
    search:SetBackdrop(Theme.BACKDROPS.simple); Theme:SetBackdropColor(search,Theme.BG.input); Theme:SetBackdropBorderColor(search,Theme.BORDER.panel)
    Theme:ApplyFont(search,"mono",12); Theme:SetTextColor(search,Theme.TEXT.primary); ToolbarLabel(bar,L["PLR_SEARCH_LABEL"],search)
    local ph=search:CreateFontString(nil,"OVERLAY"); ph:SetPoint("LEFT",9,0)
    Theme:ApplyFont(ph,"mono",11); Theme:SetTextColor(ph,Theme.TEXT.dim); ph:SetText(L["PLR_SEARCH"])
    local clear=CreateFrame("Button",nil,search); clear:SetPoint("RIGHT",-3,0); clear:SetSize(18,18); clear:Hide()
    local x=clear:CreateFontString(nil,"OVERLAY"); x:SetAllPoints(); Theme:ApplyFont(x,"mono",11); Theme:SetTextColor(x,Theme.TEXT.dim); x:SetText("x")
    clear:SetScript("OnClick",function() search:SetText(""); search:ClearFocus() end)
    search:SetScript("OnTextChanged",function(e)
        self.searchText=string.lower(e:GetText() or ""); ph:SetShown(self.searchText==""); clear:SetShown(self.searchText~="")
        -- Evita reconstruir todas las filas en cada pulsacion cuando hay muchos jugadores.
        self._searchRevision=(self._searchRevision or 0)+1
        local revision=self._searchRevision
        if C_Timer and C_Timer.After then
            C_Timer.After(.12,function()
                if self._searchRevision==revision and self.listView and self.listView:IsShown() then self:RenderList() end
            end)
        else
            self:RenderList()
        end
    end)
    search:SetScript("OnEditFocusGained",function(e)
        Theme:SetBackdropBorderColor(e,Theme.BORDER.inputFocus or Theme.GOLD.gold3)
        Theme:SetBackdropColor(e,Theme.BG.buttonHover or Theme.BG.input)
    end)
    search:SetScript("OnEditFocusLost",function(e)
        Theme:SetBackdropBorderColor(e,Theme.BORDER.panel);Theme:SetBackdropColor(e,Theme.BG.input)
    end)
    search:SetScript("OnEnter",function(e)
        GameTooltip:SetOwner(e,"ANCHOR_TOP");GameTooltip:SetText(L["PLR_SEARCH_MATES"],1,.82,.35)
        GameTooltip:AddLine(L["PLR_SEARCH_HINT"],1,1,1,true);GameTooltip:Show()
    end)
    search:SetScript("OnLeave",function()GameTooltip:Hide()end)
    search:SetScript("OnEscapePressed",function(e)e:ClearFocus()end); search:SetScript("OnEnterPressed",function(e)e:ClearFocus()end)
    self.searchBox=search
    local roleItems={{text=L["PLR_ALL_ROLES"],value="ALL"},{text="Tank",value="TANK"},{text="Healer",value="HEALER"},{text="DPS",value="DAMAGER"}}
    local role=MitzuMPlus:CreateSimpleDropdown(bar,145,roleItems,function(v)self.roleFilter=v or "ALL";self:RenderList()end)
    role:SetPoint("BOTTOMLEFT",search,"BOTTOMRIGHT",12,0); role:SetSelectedValue("ALL"); ToolbarLabel(bar,L["COL_ROLE"],role)
    local classItems, keys = {{text=L["PLR_ALL_CLASSES"],value="ALL"}}, {}
    for _,token in ipairs(CLASS_TOKENS) do keys[#keys+1]=token end
    table.sort(keys,function(a,b)return (ClassName(a) or a)<(ClassName(b) or b) end)
    for _,token in ipairs(keys) do classItems[#classItems+1]={text=ClassName(token) or token,value=token} end
    local class=MitzuMPlus:CreateSimpleDropdown(bar,190,classItems,function(v)self.classFilter=v or "ALL";self:RenderList()end)
    class:SetPoint("BOTTOMLEFT",role,"BOTTOMRIGHT",12,0); class:SetSelectedValue("ALL"); ToolbarLabel(bar,L["PLR_CLASS_LABEL"],class)
    local function AddFilterHover(dropdown,title)
        local target=dropdown._button or dropdown
        target:HookScript("OnMouseDown",function()search:ClearFocus()end)
        target:HookScript("OnEnter",function()
            local selected=dropdown._text and dropdown._text:GetText() or ""
            GameTooltip:SetOwner(dropdown,"ANCHOR_TOP");GameTooltip:SetText(title,1,.82,.35)
            GameTooltip:AddLine(L["PLR_SELECTED"]..selected,1,1,1);GameTooltip:AddLine(L["PLR_CLICK_FILTER"],.72,.72,.72);GameTooltip:Show()
        end)
        target:HookScript("OnLeave",function()GameTooltip:Hide()end)
    end
    AddFilterHover(role,L["PLR_ROLE_FILTER"]);AddFilterHover(class,L["PLR_CLASS_FILTER"])
    view:SetScript("OnMouseDown",function()search:ClearFocus()end)
    local summary=view:CreateFontString(nil,"OVERLAY"); summary:SetPoint("TOPLEFT",bar,"BOTTOMLEFT",2,-8)
    Theme:ApplyFont(summary,"mono",11); Theme:SetTextColor(summary,Theme.TEXT.secondary); self.listSummary=summary
    local header=SortHeader(view,LIST_COLS,function(key)
        if self.searchBox then self.searchBox:ClearFocus() end
        if self.listSortKey==key then self.listSortDesc=not self.listSortDesc else self.listSortKey=key;self.listSortDesc=key~="identity" and key~="role" end
        self:RenderList()
    end)
    header:SetPoint("TOPLEFT",bar,"BOTTOMLEFT",0,-27); header:SetPoint("TOPRIGHT",bar,"BOTTOMRIGHT",0,-27); self.listHeader=header
    local scroll=Widgets:CreateScrollFrame(view); scroll:SetPoint("TOPLEFT",header,"BOTTOMLEFT"); scroll:SetPoint("BOTTOMRIGHT",view,"BOTTOMRIGHT",-10,10)
    scroll:EnableMouse(true);scroll:SetScript("OnMouseDown",function()search:ClearFocus()end)
    self.listScroll,self.listContent=scroll,scroll.scrollChild; self.listContent:SetHeight(1)
    local function Relayout()
        self.listOffsets=LayoutColumns(header,LIST_COLS,header:GetWidth()); self.listContent:SetWidth(math.max(1,scroll:GetWidth()-8))
        self:LayoutRows(self.listRows,LIST_COLS,self.listOffsets); scroll:UpdateScrollRange()
    end
    header:SetScript("OnSizeChanged",Relayout); view:SetScript("OnShow",Relayout)
    view:SetScript("OnHide",function()search:ClearFocus();GameTooltip:Hide()end)
end

function PanelPlayers:CreateProfileView(parent)
    local view=CreateFrame("Frame",nil,parent); view:SetAllPoints(); view:Hide(); self.profileView=view
    local top=CreateFrame("Frame",nil,view,BackdropTemplateMixin and "BackdropTemplate")
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(94); top:SetBackdrop(Theme.BACKDROPS.panel)
    Theme:SetBackdropColor(top,{r=.02,g=.02,b=.04,a=.96}); Theme:SetBackdropBorderColor(top,Theme.GOLD.gold0)
    local bg=top:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetAlpha(.18); self.profileBg=bg
    local back=CreateFrame("Button",nil,top,BackdropTemplateMixin and "BackdropTemplate"); back:SetPoint("TOPLEFT",9,-9); back:SetSize(88,24)
    back:SetBackdrop(Theme.BACKDROPS.simple); Theme:SetBackdropColor(back,Theme.BG.button); Theme:SetBackdropBorderColor(back,Theme.BORDER.panel)
    local bt=back:CreateFontString(nil,"OVERLAY"); bt:SetAllPoints(); Theme:ApplyFont(bt,"mono",11); Theme:SetTextColor(bt,Theme.GOLD.gold4); bt:SetText(L["PLR_BACK"])
    back:SetScript("OnClick",function()self:ShowList()end)
    local title=top:CreateFontString(nil,"OVERLAY"); title:SetPoint("TOPLEFT",112,-11); Theme:ApplyFont(title,"title",18); self.profileTitle=title
    local sub=top:CreateFontString(nil,"OVERLAY"); sub:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-5); Theme:ApplyFont(sub,"mono",11)
    Theme:SetTextColor(sub,Theme.TEXT.secondary); self.profileSubtitle=sub
    self.cards={}; local labels={L["PLR_RUNS_TOGETHER"],L["COL_SUCCESS"],L["PLR_BEST_KEY"],L["PLR_LAST_TIME"]}
    for i,labelText in ipairs(labels) do
        local card=CreateFrame("Frame",nil,top,BackdropTemplateMixin and "BackdropTemplate"); card:SetSize(126,49)
        card:SetPoint("TOPRIGHT",-10-((4-i)*134),-21); card:SetBackdrop(Theme.BACKDROPS.simple)
        Theme:SetBackdropColor(card,{r=.04,g=.04,b=.06,a=.82}); Theme:SetBackdropBorderColor(card,Theme.BORDER.panel)
        local label=card:CreateFontString(nil,"OVERLAY"); label:SetPoint("TOP",0,-6); Theme:ApplyFont(label,"mono",9); Theme:SetTextColor(label,Theme.TEXT.dim); label:SetText(labelText)
        local value=card:CreateFontString(nil,"OVERLAY"); value:SetPoint("TOP",label,"BOTTOM",0,-3); Theme:ApplyFont(value,"mono",15); Theme:SetTextColor(value,Theme.GOLD.gold4)
        card.value=value; self.cards[i]=card
    end
    local hint=view:CreateFontString(nil,"OVERLAY"); hint:SetPoint("TOPLEFT",top,"BOTTOMLEFT",12,-8)
    Theme:ApplyFont(hint,"mono",10); Theme:SetTextColor(hint,Theme.TEXT.dim); hint:SetText(L["PLR_HINT"])
    local header=SortHeader(view,RUN_COLS,function(key)
        if self.runSortKey==key then self.runSortDesc=not self.runSortDesc else self.runSortKey=key;self.runSortDesc=key~="dungeon" and key~="result" end
        self:RenderProfile()
    end)
    header:SetPoint("TOPLEFT",top,"BOTTOMLEFT",10,-27); header:SetPoint("TOPRIGHT",top,"BOTTOMRIGHT",-10,-27); self.profileHeader=header
    local scroll=Widgets:CreateScrollFrame(view); scroll:SetPoint("TOPLEFT",header,"BOTTOMLEFT"); scroll:SetPoint("BOTTOMRIGHT",view,"BOTTOMRIGHT",-10,10)
    self.profileScroll,self.profileContent=scroll,scroll.scrollChild; self.profileContent:SetHeight(1)
    local function Relayout()
        self.runOffsets=LayoutColumns(header,RUN_COLS,header:GetWidth()); self.profileContent:SetWidth(math.max(1,scroll:GetWidth()-8))
        self:LayoutRows(self.profileRows,RUN_COLS,self.runOffsets); scroll:UpdateScrollRange()
    end
    header:SetScript("OnSizeChanged",Relayout); view:SetScript("OnShow",Relayout)
end

function PanelPlayers:LayoutRows(rows,cols,offsets)
    if not offsets then return end
    for _,row in ipairs(rows or {}) do
        for _,col in ipairs(cols) do
            local cell,o=row.cells and row.cells[col.key],offsets[col.key]
            if cell and o then
                local inset = col.key == "identity" and (row.identityInset or 10) or (col.numeric and 4 or 10)
                cell:ClearAllPoints();cell:SetPoint("LEFT",row,"LEFT",o.x+inset,0);cell:SetWidth(math.max(8,o.w-inset-4))
            end
        end
    end
end

function PanelPlayers:BuildIndex()
    local map,runs={},MitzuMPlus.GetAllRuns and MitzuMPlus:GetAllRuns() or {}
    for _,run in ipairs(runs) do
        local duration=tonumber(run.completionTime) or 0
        for _,m in ipairs(RunMembers(run)) do
            if not m.isPlayer then
                local p=map[m.key]
                if not p then
                    p={key=m.key,name=m.name,realm=m.realm,class=m.class,role=m.role,spec=m.spec,specID=m.specID,runs=0,inTime=0,best=0,
                       deaths=0,damage=0,healing=0,taken=0,measured=0,duration=0,last=0,entries={},loot=0,
                       savedRaiderIOScore=0,savedRaiderIOAt=0}
                    map[m.key]=p
                end
                if p.class=="" and m.class~="" then p.class=m.class end
                if p.spec=="" and m.spec~="" then p.spec=m.spec end
                if (p.specID or 0)==0 and (m.specID or 0)>0 then p.specID=m.specID end
                if p.role=="DAMAGER" and m.role~="DAMAGER" then p.role=m.role end
                p.runs=p.runs+1; if run.inTime then p.inTime=p.inTime+1 end
                p.best=math.max(p.best,tonumber(run.keyLevel) or 0); p.deaths=p.deaths+m.deaths
                p.damage=p.damage+m.damage;p.healing=p.healing+m.healing;p.taken=p.taken+m.taken;p.duration=p.duration+duration
                if m.hasMetrics then p.measured=p.measured+1 end
                p.last=math.max(p.last,tonumber(run.startTime) or 0)
                local runTime=tonumber(run.startTime) or 0
                if (tonumber(m.raiderIOScore) or 0)>0 and runTime>=(p.savedRaiderIOAt or 0) then
                    p.savedRaiderIOScore=tonumber(m.raiderIOScore) or 0;p.savedRaiderIOAt=runTime
                end
                local loot=MemberLoot(run,m);p.loot=p.loot+#loot;p.entries[#p.entries+1]={run=run,member=m,loot=loot}
            end
        end
    end
    local out={}
    for _,p in pairs(map) do
        p.success=p.runs>0 and p.inTime/p.runs*100 or 0
        p.deathsAvg=p.measured>0 and p.deaths/p.measured or nil
        RaiderIOScore(p)
        out[#out+1]=p
    end
    return out,#runs
end
function PanelPlayers:Matches(p)
    if self.roleFilter~="ALL" and p.role~=self.roleFilter then return false end
    if self.classFilter~="ALL" and p.class~=self.classFilter then return false end
    if self.searchText~="" then
        local hay=string.lower(table.concat({p.name,p.realm,ClassName(p.class) or p.class}," "))
        if not string.find(hay,self.searchText,1,true) then return false end
    end
    return true
end
function PanelPlayers:ComparePlayers(a,b)
    local k=self.listSortKey;local av,bv
    if k=="identity" then av,bv=string.lower(a.name),string.lower(b.name)
    elseif k=="role" then av,bv=ROLE_SORT[a.role] or 9,ROLE_SORT[b.role] or 9
    elseif k=="runs" then av,bv=a.runs,b.runs elseif k=="success" then av,bv=a.success,b.success
    elseif k=="best" then av,bv=a.best,b.best elseif k=="deaths" then av,bv=a.deathsAvg or -1,b.deathsAvg or -1
    elseif k=="rio" then av,bv=a.rioScore or -1,b.rioScore or -1 else av,bv=a.last,b.last end
    if av==bv then return string.lower(a.name)<string.lower(b.name) end
    return self.listSortDesc and av>bv or (not self.listSortDesc and av<bv)
end
function PanelPlayers:CreateListRow(p,index)
    local row=CreateFrame("Button",nil,self.listContent,BackdropTemplateMixin and "BackdropTemplate");row:SetHeight(ROW_H);StyleRow(row,index)
    local cells={};for _,col in ipairs(LIST_COLS)do cells[col.key]=NewCell(row,col,(self.listOffsets or {})[col.key] or {x=0,w=100})end
    local icon=row:CreateTexture(nil,"ARTWORK");icon:SetPoint("LEFT",8,0);icon:SetSize(24,24)
    local accent=row:CreateTexture(nil,"OVERLAY");accent:SetPoint("TOPLEFT",1,-2);accent:SetPoint("BOTTOMLEFT",1,2);accent:SetWidth(3)
    accent:SetTexture("Interface\\Buttons\\WHITE8X8");accent:SetVertexColor(Theme.GOLD.gold3.r,Theme.GOLD.gold3.g,Theme.GOLD.gold3.b,1);accent:Hide()
    local iconSet=false
    if (p.specID or 0)>0 and GetSpecializationInfoByID then
        local ok,_,_,_,texture=pcall(GetSpecializationInfoByID,p.specID)
        if ok and texture then icon:SetTexture(texture);iconSet=true end
    end
    if not iconSet and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[p.class] then
        local tc=CLASS_ICON_TCOORDS[p.class];icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        icon:SetTexCoord(tc[1],tc[2],tc[3],tc[4]);iconSet=true
    end
    if not iconSet then icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
    row.identityInset=38
    local color=GetClassColor(p.class);local display=p.name..(p.realm~="" and ("  |cFF777777- "..p.realm.."|r") or "")
    local detail=ClassName(p.class) or p.class;if p.spec~="" then detail=detail.." · "..p.spec end
    cells.identity:SetText(display.."\n|cFF888888"..(detail~="" and detail or "Datos parciales").."|r");cells.identity:SetTextColor(color.r,color.g,color.b,1)
    local rc=ROLE_COLOR[p.role] or Theme.TEXT.secondary;cells.role:SetText(ROLE_LABEL[p.role] or "DPS");cells.role:SetTextColor(rc.r,rc.g,rc.b,1)
    cells.runs:SetText(p.runs);Theme:SetTextColor(cells.runs,Theme.TEXT.primary)
    cells.success:SetText(string.format("%.0f%%",p.success));Theme:SetTextColor(cells.success,p.success>=60 and Theme.STATUS.ok or (p.success>=40 and Theme.STATUS.warn or Theme.STATUS.bad))
    cells.best:SetText(p.best>0 and ("+"..p.best) or "-");Theme:SetTextColor(cells.best,Theme.GOLD.gold4)
    local rioScore=RaiderIOScore(p);cells.rio:SetText(rioScore and string.format("%.0f",rioScore) or "-")
    local rioColor=RaiderIOColor(rioScore);Theme:SetTextColor(cells.rio,rioScore and rioColor or Theme.TEXT.dim)
    cells.deaths:SetText(p.deathsAvg and string.format("%.1f/run",p.deathsAvg) or "-");Theme:SetTextColor(cells.deaths,p.deathsAvg and (p.deathsAvg<=.5 and Theme.STATUS.ok or Theme.STATUS.bad) or Theme.TEXT.dim)
    cells.last:SetText(ShortDate(p.last));Theme:SetTextColor(cells.last,Theme.TEXT.secondary);row.cells=cells
    row:SetScript("OnEnter",function(f)
        Theme:SetBackdropColor(f,Theme.BG.rowHover);accent:Show()
        GameTooltip:SetOwner(f,"ANCHOR_RIGHT");GameTooltip:SetText(p.name..(p.realm~="" and (" - "..p.realm) or ""), color.r,color.g,color.b)
        GameTooltip:AddLine(string.format(L["PLR_TOGETHER_LINE"],p.runs,p.success),1,1,1)
        local rioScore,rioState=RaiderIOScore(p)
        if rioScore then
            local rc=RaiderIOColor(rioScore)
            local suffix=rioState=="SAVED" and L["PLR_SAVED"] or ""
            GameTooltip:AddLine(L["PLR_SCORE_PREFIX"]..string.format("%.0f",rioScore)..suffix,rc.r,rc.g,rc.b)
        elseif rioState=="NO_ADDON" then
            GameTooltip:AddLine(L["PLR_SCORE_NA"],.65,.65,.65,true)
        else
            GameTooltip:AddLine(L["PLR_SCORE_NO_DATA"],.65,.65,.65,true)
        end
        GameTooltip:AddLine(L["PLR_SUCCESS_HINT"],.75,.75,.75,true)
        if p.measured<p.runs then GameTooltip:AddLine(string.format(L["PLR_METRICS_IN"],p.measured,p.runs),.7,.7,.7,true) end
        GameTooltip:AddLine(L["PLR_CLICK_PROFILE"],.9,.75,.3);GameTooltip:Show()
    end)
    row:SetScript("OnLeave",function(f)Theme:SetBackdropColor(f,f._normalBG);accent:Hide();GameTooltip:Hide()end)
    row:SetScript("OnMouseDown",function()if self.searchBox then self.searchBox:ClearFocus()end end)
    row:SetScript("OnClick",function()self:ShowProfile(p)end);return row
end
function PanelPlayers:RenderList()
    if not self.listContent then return end
    Destroy(self.listRows);Destroy(self.listExtras)
    local visible={};for _,p in ipairs(self.players or {})do if self:Matches(p)then visible[#visible+1]=p end end
    table.sort(visible,function(a,b)return self:ComparePlayers(a,b)end);self.listHeader:SetSort(self.listSortKey,self.listSortDesc)
    self.listSummary:SetText(string.format(L["PLR_VISIBLE"],#visible,#(self.players or {}),self.totalRuns or 0))
    local y=0
    for i,p in ipairs(visible)do local row=self:CreateListRow(p,i);row:SetPoint("TOPLEFT",self.listContent,"TOPLEFT",0,y);row:SetPoint("TOPRIGHT",self.listContent,"TOPRIGHT",0,y);self.listRows[#self.listRows+1]=row;y=y-ROW_H end
    if #visible==0 then
        local noRuns=(self.totalRuns or 0)==0
        local noPlayers=not noRuns and #(self.players or {})==0
        local empty=Widgets:CreateEmptyState(self.listContent,"?",noRuns and L["PLR_NO_RUNS"] or (noPlayers and L["PLR_EMPTY"] or L["PLR_NO_MATCH"]),
            noRuns and L["PLR_EMPTY_DESC"]
                or (noPlayers and L["PLR_EMPTY_UNUSABLE"] or L["PLR_NO_MATCH_DESC"]))
        empty:SetPoint("TOP",self.listContent,"TOP",0,-48);self.listExtras[#self.listExtras+1]=empty;y=-240
    end
    self.listContent:SetHeight(math.max(60,math.abs(y)+8));self:LayoutRows(self.listRows,LIST_COLS,self.listOffsets)
    self.listScroll:UpdateScrollRange();self.listScroll.scrollBar:SetValue(0)
end
function PanelPlayers:ShowList() self.profileView:Hide();self.listView:Show();self.currentPlayer=nil end

local function DungeonTexture(run)
    if not run or not run.dungeonID or not C_ChallengeMode or not C_ChallengeMode.GetMapUIInfo then return nil end
    local ok,_,_,_,icon,bg=pcall(C_ChallengeMode.GetMapUIInfo,run.dungeonID);return ok and (bg or icon) or nil
end
function PanelPlayers:ShowProfile(p)
    self.currentPlayer=p;self.listView:Hide();self.profileView:Show();self.lootExpanded=false
    local cc=GetClassColor(p.class);self.profileTitle:SetText(p.name..(p.realm~="" and (" - "..p.realm) or ""));self.profileTitle:SetTextColor(cc.r,cc.g,cc.b,1)
    local identity=ClassName(p.class) or p.class or L["PLR_UNKNOWN_CLASS"];if p.spec~="" then identity=identity.." · "..p.spec end
    identity=identity.." · "..(ROLE_LABEL[p.role] or "DPS")
    local rioScore=RaiderIOScore(p)
    if rioScore then identity=identity..L["PLR_SCORE_INLINE"]..string.format("%.0f",rioScore) end
    self.profileSubtitle:SetText(identity);self.cards[1].value:SetText(p.runs);self.cards[2].value:SetText(string.format("%.0f%%",p.success));self.cards[3].value:SetText(p.best>0 and ("+"..p.best) or "-");self.cards[4].value:SetText(ShortDate(p.last))
    local latest
    for _,e in ipairs(p.entries)do if not latest or (tonumber(e.run.startTime)or 0)>(tonumber(latest.startTime)or 0)then latest=e.run end end
    local tex=DungeonTexture(latest);if tex then self.profileBg:SetTexture(tex);self.profileBg:Show() else self.profileBg:Hide() end
    self:RenderProfile()
end
function PanelPlayers:Metric(entry)
    local m,d=entry.member,math.max(1,tonumber(entry.run.completionTime) or 0)
    if m.role=="HEALER" then return m.healing/d,"HPS" elseif m.role=="TANK" then return m.taken/d,"DTPS" end
    return m.damage/d,"DPS"
end
function PanelPlayers:CompareRuns(a,b)
    local k=self.runSortKey;local ar,br=a.run,b.run;local av,bv
    if k=="dungeon"then av,bv=string.lower(ar.dungeonName or ""),string.lower(br.dungeonName or "")
    elseif k=="level"then av,bv=tonumber(ar.keyLevel)or 0,tonumber(br.keyLevel)or 0
    elseif k=="result"then av,bv=ar.inTime and 1 or 0,br.inTime and 1 or 0
    elseif k=="duration"then av,bv=tonumber(ar.completionTime)or 0,tonumber(br.completionTime)or 0
    elseif k=="metric"then av,bv=self:Metric(a),self:Metric(b)
    elseif k=="deaths"then av,bv=a.member.deaths,b.member.deaths else av,bv=tonumber(ar.startTime)or 0,tonumber(br.startTime)or 0 end
    if av==bv then return (tonumber(ar.startTime)or 0)>(tonumber(br.startTime)or 0) end
    return self.runSortDesc and av>bv or (not self.runSortDesc and av<bv)
end
function PanelPlayers:CreateRunRow(entry,index)
    local row=CreateFrame("Frame",nil,self.profileContent,BackdropTemplateMixin and "BackdropTemplate");row:SetHeight(RUN_ROW_H);StyleRow(row,index)
    local cells={};for _,col in ipairs(RUN_COLS)do cells[col.key]=NewCell(row,col,(self.runOffsets or {})[col.key]or{x=0,w=100})end
    local run,m=entry.run,entry.member;cells.dungeon:SetText(run.dungeonName or L["HIST_UNKNOWN_DUNGEON"]);Theme:SetTextColor(cells.dungeon,Theme.TEXT.primary)
    local level=tonumber(run.keyLevel)or 0;cells.level:SetText(level>0 and ("+"..level)or"-");Theme:SetTextColor(cells.level,Theme.GOLD.gold4)
    if run.inTime then cells.result:SetText(L["RUN_IN_TIME"]);Theme:SetTextColor(cells.result,Theme.STATUS.ok)
    elseif (tonumber(run.completionTime)or 0)>0 then cells.result:SetText(L["RESULT_OUT"]);Theme:SetTextColor(cells.result,Theme.STATUS.bad)
    else cells.result:SetText(L["RESULT_INCOMPLETE"]);Theme:SetTextColor(cells.result,Theme.TEXT.dim)end
    cells.duration:SetText(MMSS(run.completionTime));Theme:SetTextColor(cells.duration,Theme.TEXT.secondary)
    local metric,label=self:Metric(entry);cells.metric:SetText(m.hasMetrics and (FNum(metric).." "..label)or"-");Theme:SetTextColor(cells.metric,m.hasMetrics and (m.role=="HEALER"and Theme.STATUS.ok or Theme.GOLD.gold4)or Theme.TEXT.dim)
    cells.deaths:SetText(m.hasMetrics and m.deaths or "-");Theme:SetTextColor(cells.deaths,m.hasMetrics and (m.deaths>0 and Theme.STATUS.bad or Theme.STATUS.ok)or Theme.TEXT.dim)
    cells.date:SetText(ShortDate(run.startTime));Theme:SetTextColor(cells.date,Theme.TEXT.dim);row.cells=cells;return row
end
function PanelPlayers:AddLoot(entries,y)
    local p=self.currentPlayer
    if p.loot<=0 then return y end
    local button=CreateFrame("Button",nil,self.profileContent,BackdropTemplateMixin and "BackdropTemplate")
    button:SetPoint("TOPLEFT",self.profileContent,"TOPLEFT",0,y-8);button:SetPoint("TOPRIGHT",self.profileContent,"TOPRIGHT",0,y-8);button:SetHeight(28)
    button:SetBackdrop(Theme.BACKDROPS.simple);Theme:SetBackdropColor(button,Theme.BG.panel);Theme:SetBackdropBorderColor(button,Theme.BORDER.panel)
    local label=button:CreateFontString(nil,"OVERLAY");label:SetPoint("LEFT",10,0);Theme:ApplyFont(label,"mono",11);Theme:SetTextColor(label,Theme.GOLD.gold3)
    label:SetText(string.format(L["PLR_LOOT"],p.loot,self.lootExpanded and "^" or "v"))
    button:SetScript("OnClick",function()self.lootExpanded=not self.lootExpanded;self:RenderProfile()end);self.profileExtras[#self.profileExtras+1]=button;y=y-36
    if not self.lootExpanded then return y end
    for _,entry in ipairs(entries)do for _,item in ipairs(entry.loot)do
        local row=CreateFrame("Frame",nil,self.profileContent,BackdropTemplateMixin and "BackdropTemplate");row:SetPoint("TOPLEFT",self.profileContent,"TOPLEFT",18,y);row:SetPoint("TOPRIGHT",self.profileContent,"TOPRIGHT",-4,y);row:SetHeight(28)
        row:SetBackdrop(Theme.BACKDROPS.simple);Theme:SetBackdropColor(row,{r=.04,g=.04,b=.06,a=.8})
        local icon=row:CreateTexture(nil,"ARTWORK");icon:SetPoint("LEFT",5,0);icon:SetSize(22,22);icon:SetTexture(tonumber(item.iconID)or 134400);icon:SetTexCoord(.08,.92,.08,.92)
        local name=row:CreateFontString(nil,"OVERLAY");name:SetPoint("LEFT",icon,"RIGHT",7,0);name:SetPoint("RIGHT",-120,0);name:SetJustifyH("LEFT");name:SetWordWrap(false);Theme:ApplyFont(name,"mono",11)
        local qc=QUALITY_COLOR[item.quality or 1]or QUALITY_COLOR[1];name:SetTextColor(qc[1],qc[2],qc[3],1)
        local itemName=tostring(item.itemName or item.itemLink or "Item");itemName=itemName:match("%[(.-)%]")or itemName;if (tonumber(item.quantity)or 1)>1 then itemName=itemName.." x"..item.quantity end;name:SetText(itemName)
        local dungeon=row:CreateFontString(nil,"OVERLAY");dungeon:SetPoint("RIGHT",-8,0);dungeon:SetWidth(108);dungeon:SetJustifyH("RIGHT");Theme:ApplyFont(dungeon,"mono",10);Theme:SetTextColor(dungeon,Theme.TEXT.dim);dungeon:SetText(entry.run.dungeonName or "")
        if item.itemLink then
            row:EnableMouse(true)
            row:SetScript("OnEnter",function(f)
                GameTooltip:SetOwner(f,"ANCHOR_RIGHT")
                local ok=pcall(GameTooltip.SetHyperlink,GameTooltip,item.itemLink)
                if not ok then GameTooltip:SetText(itemName) end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave",function()GameTooltip:Hide()end)
        end
        self.profileExtras[#self.profileExtras+1]=row;y=y-28
    end end
    return y
end
function PanelPlayers:RenderProfile()
    local p=self.currentPlayer;if not p then return end
    Destroy(self.profileRows);Destroy(self.profileExtras);local entries={}
    for _,e in ipairs(p.entries)do entries[#entries+1]=e end
    table.sort(entries,function(a,b)return self:CompareRuns(a,b)end);self.profileHeader:SetSort(self.runSortKey,self.runSortDesc)
    local y=0
    for i,e in ipairs(entries)do local row=self:CreateRunRow(e,i);row:SetPoint("TOPLEFT",self.profileContent,"TOPLEFT",0,y);row:SetPoint("TOPRIGHT",self.profileContent,"TOPRIGHT",0,y);self.profileRows[#self.profileRows+1]=row;y=y-RUN_ROW_H end
    y=self:AddLoot(entries,y);self.profileContent:SetHeight(math.max(60,math.abs(y)+12));self:LayoutRows(self.profileRows,RUN_COLS,self.runOffsets)
    self.profileScroll:UpdateScrollRange();self.profileScroll.scrollBar:SetValue(0)
end
function PanelPlayers:Refresh()
    if not self.listContent then return end
    self.players,self.totalRuns=self:BuildIndex();self:ShowList();self:RenderList()
end
return PanelPlayers
