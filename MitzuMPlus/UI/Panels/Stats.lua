-- MitzuMPlus M+ Historial - Estadisticas v6
-- Solo usa datos medidos; filtros por personaje, temporada, rol, mazmorra y nivel.
local ADDON_NAME="MitzuMPlus"
local MitzuMPlus=LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local Theme,Widgets=MitzuMPlus.Theme,MitzuMPlus.Widgets
local L = MitzuMPlus.L
local wipe=wipe
local PanelStats={}
MitzuMPlus.PanelStats=PanelStats

local ROLE_LABEL={TANK="Tank",HEALER="Healer",DAMAGER="DPS",NONE="DPS"}
local LEVEL_ITEMS={
    {text=L["STATS_ALL_LEVELS"],value="ALL"},{text=L["STATS_LEVEL_1_6"],value="LOW"},
    {text=L["STATS_LEVEL_7_11"],value="MID"},{text=L["STATS_LEVEL_12"],value="HIGH"},
}
local TREND_COLS={
    {key="date",text=L["COL_DATE"],w=.09},{key="dungeon",text=L["COL_DUNGEON"],w=.28},
    {key="level",text=L["COL_LEVEL"],w=.08},{key="result",text=L["COL_RESULT"],w=.14},
    {key="margin",text=L["COL_MARGIN"],w=.13},{key="metric",text="DPS/HPS/DTPS",w=.18},
    {key="deaths",text=L["COL_DEATHS"],w=.10},
}
local DUNGEON_COLS={
    {key="dungeon",text=L["COL_DUNGEON"],w=.32},{key="runs",text=L["COL_RUNS"],w=.10},
    {key="success",text=L["COL_SUCCESS"],w=.13},{key="best",text=L["COL_BEST"],w=.11},
    {key="margin",text=L["STATS_MED_MARGIN"],w=.17},{key="deaths",text=L["STATS_DEATHS_RUN"],w=.17},
}

local function FNum(v)
    v=tonumber(v)or 0
    if MitzuMPlus.Formatters and MitzuMPlus.Formatters.FormatDPS then return MitzuMPlus.Formatters:FormatDPS(v) end
    return tostring(math.floor(v+.5))
end
local function FTime(sec,signed)
    sec=tonumber(sec)or 0;local sign=""
    if signed then sign=sec>=0 and "+" or "-";sec=math.abs(sec) end
    return string.format("%s%d:%02d",sign,math.floor(sec/60),math.floor(sec%60))
end
local function DateText(ts)
    if not ts or ts<=0 then return "-" end
    local ok,s=pcall(date,"%d/%m/%y",ts);return ok and s or "-"
end
local function Median(values)
    if #values==0 then return nil end
    local copy={};for _,v in ipairs(values)do copy[#copy+1]=v end;table.sort(copy)
    local n=#copy;if n%2==1 then return copy[(n+1)/2] end
    return (copy[n/2]+copy[n/2+1])/2
end
local function Destroy(list)
    for _,f in ipairs(list or {})do f:Hide();if f.SetParent then f:SetParent(nil)end end
    if list then wipe(list)end
end
local function CharacterKey(run)return MitzuMPlus.RunMetrics:GetCharacterKey(run)end
local function SeasonInfo(run)
    return MitzuMPlus.RunMetrics:GetSeason(run)
end
local function Role(run)
    return MitzuMPlus.RunMetrics:GetRole(run)
end
local function RunSample(run)
    local RM=MitzuMPlus.RunMetrics;local role=RM:GetRole(run);local duration=RM:GetDuration(run)or 0
    local metric,label,source=RM:GetRoleMetric(run)
    local ownDeaths=RM:GetOwnDeaths(run);local ownKicks=RM:GetOwnKicks(run);local ownDispels=RM:GetOwnDispels(run)
    local groupDeaths=RM:GetGroupDeaths(run)or 0;local margin=RM:GetMargin(run)
    return{run=run,role=role,duration=duration,metric=metric,metricLabel=label,metricValid=metric~=nil and metric>0 and duration>0,
        ownDeaths=ownDeaths,ownKicks=ownKicks,ownDispels=ownDispels,groupDeaths=groupDeaths,margin=margin,
        dataSource=source}
end
local function LevelMatches(level,band)
    level=tonumber(level)or 0
    return band=="ALL"or(band=="LOW"and level>=1 and level<=6)or(band=="MID"and level>=7 and level<=11)or(band=="HIGH"and level>=12)
end
local function NewText(parent,font,size,color)
    local fs=parent:CreateFontString(nil,"OVERLAY","GameFontHighlight");Theme:ApplyFont(fs,font or "mono",size or 11)
    Theme:SetTextColor(fs,color or Theme.TEXT.primary);fs:SetWordWrap(false);return fs
end
local function SectionTitle(parent,text,y)
    local fs=NewText(parent,"normal",12,Theme.GOLD.gold3);fs:SetPoint("TOPLEFT",parent,"TOPLEFT",2,y);fs:SetText(text)
    local line=parent:CreateTexture(nil,"ARTWORK");line:SetPoint("TOPLEFT",fs,"BOTTOMLEFT",0,-5);line:SetPoint("TOPRIGHT",parent,"TOPRIGHT",-2,y-20);line:SetHeight(1)
    line:SetTexture("Interface\\Buttons\\WHITE8X8");Theme:SetVertexColor(line,Theme.GOLD.gold0)
    return fs,line
end
local function TableHeader(parent,cols,y)
    local frame=CreateFrame("Frame",nil,parent,BackdropTemplateMixin and"BackdropTemplate");frame:SetPoint("TOPLEFT",0,y);frame:SetPoint("TOPRIGHT",0,y);frame:SetHeight(28)
    frame:SetBackdrop(Theme.BACKDROPS.simple);Theme:SetBackdropColor(frame,Theme.BG.titlebar)
    local x=0
    for _,col in ipairs(cols)do
        local fs=NewText(frame,"normal",10,Theme.GOLD.gold3);fs:SetPoint("LEFT",frame,"LEFT",x+7,0);fs:SetWidth(math.max(20,(parent:GetWidth() or 1000)*col.w-10));fs:SetText(col.text);x=x+(parent:GetWidth() or 1000)*col.w
    end
    return frame
end
local function TableRow(parent,cols,values,y,index)
    local frame=CreateFrame("Frame",nil,parent,BackdropTemplateMixin and"BackdropTemplate");frame:SetPoint("TOPLEFT",0,y);frame:SetPoint("TOPRIGHT",0,y);frame:SetHeight(28)
    frame:SetBackdrop(Theme.BACKDROPS.simple);Theme:SetBackdropColor(frame,index%2==1 and Theme.BG.rowOdd or Theme.BG.rowEven)
    local x,width=0,parent:GetWidth() or 1000
    for _,col in ipairs(cols)do
        local item=values[col.key]or{};local fs=NewText(frame,"normal",10,item.color or Theme.TEXT.secondary)
        fs:SetPoint("LEFT",frame,"LEFT",x+7,0);fs:SetWidth(math.max(20,width*col.w-10));fs:SetText(item.text or"");x=x+width*col.w
    end
    return frame
end

function PanelStats:Create(parent)
    local c=MitzuMPlus.Tabs and MitzuMPlus.Tabs.CreatePanelContainer and MitzuMPlus.Tabs:CreatePanelContainer(parent)or CreateFrame("Frame",nil,parent)
    self.panel=c;self.dynamic={};self.filters={character="ALL",season="ALL",role="ALL",dungeon="ALL",level="ALL"}
    local toolbar=CreateFrame("Frame",nil,c,BackdropTemplateMixin and"BackdropTemplate");toolbar:SetPoint("TOPLEFT",10,-10);toolbar:SetPoint("TOPRIGHT",-10,-10);toolbar:SetHeight(52)
    toolbar:SetBackdrop(Theme.BACKDROPS.simple);Theme:SetBackdropColor(toolbar,Theme.BG.panel);self.toolbar=toolbar
    local defs={{"character",L["COL_CHARACTER"],220},{"season",L["STATS_SEASON_LABEL"],185},{"role",L["COL_ROLE"],145},{"dungeon",L["COL_DUNGEON"],280},{"level",L["COL_LEVEL"],190}}
    local previous
    for _,def in ipairs(defs)do
        local key,label,w=def[1],def[2],def[3]
        local dd=MitzuMPlus:CreateSimpleDropdown(toolbar,w,{},function(value)self.filters[key]=value or"ALL";self:Render()end)
        if previous then dd:SetPoint("BOTTOMLEFT",previous,"BOTTOMRIGHT",12,0)else dd:SetPoint("BOTTOMLEFT",10,7)end
        local cap=NewText(toolbar,"normal",9,Theme.TEXT.dim);cap:SetPoint("BOTTOMLEFT",dd,"TOPLEFT",0,3);cap:SetText(label)
        self[key.."Dropdown"]=dd;previous=dd
    end
    local cards=CreateFrame("Frame",nil,c);cards:SetPoint("TOPLEFT",10,-72);cards:SetPoint("TOPRIGHT",-10,-72);cards:SetHeight(78);self.cards={}
    local labels={L["COL_RUNS"],L["RUN_IN_TIME"],L["STATS_BEST_KEY_CARD"]}
    for i,label in ipairs(labels)do
        local card=CreateFrame("Frame",nil,cards,BackdropTemplateMixin and"BackdropTemplate");card:SetHeight(72)
        card:SetBackdrop(Theme.BACKDROPS.simple);Theme:SetBackdropColor(card,Theme.BG.panel);Theme:SetBackdropBorderColor(card,Theme.BORDER.panel)
        local h=NewText(card,"normal",9,Theme.TEXT.dim);h:SetPoint("TOP",0,-9);h:SetText(label)
        local v=NewText(card,"title",20,Theme.GOLD.gold4);v:SetPoint("TOP",h,"BOTTOM",0,-6);card.value=v;self.cards[i]=card
    end
    local function LayoutCards()
        local gap=8;local count=#self.cards;local width=math.max(80,((cards:GetWidth() or 0)-gap*(count-1))/count)
        for i,card in ipairs(self.cards)do
            card:ClearAllPoints();card:SetPoint("TOPLEFT",cards,"TOPLEFT",(i-1)*(width+gap),0);card:SetWidth(width)
        end
    end
    cards:SetScript("OnSizeChanged",LayoutCards);LayoutCards()
    local scroll=Widgets:CreateScrollFrame(c);scroll:SetPoint("TOPLEFT",10,-158);scroll:SetPoint("BOTTOMRIGHT",-10,10);self.scroll,self.content=scroll,scroll.scrollChild
    self.content:SetHeight(1);self.content:SetWidth(math.max(1,scroll:GetWidth()-8))
    scroll:SetScript("OnSizeChanged",function(f)self.content:SetWidth(math.max(1,f:GetWidth()-8));self:Render()end)
    if MitzuMPlus.Tabs then MitzuMPlus.Tabs:RegisterPanel("stats",c)end
    return c
end

function PanelStats:RefreshFilterItems(runs)
    local chars,seasons,dungeons={},{},{}
    for _,run in ipairs(runs)do
        if run.playerName and run.playerName~=""then chars[CharacterKey(run)]=run.playerName..((run.playerRealm and run.playerRealm~="")and(" - "..run.playerRealm)or"")end
        local season,label=SeasonInfo(run);seasons[season]=label
        if run.dungeonName and run.dungeonName~=""then dungeons[run.dungeonName]=run.dungeonName end
    end
    local function Items(map,allText)
        local out,keys={{text=allText,value="ALL"}},{};for key in pairs(map)do keys[#keys+1]=key end;table.sort(keys,function(a,b)return tostring(map[a])<tostring(map[b])end)
        for _,key in ipairs(keys)do out[#out+1]={text=map[key],value=key}end;return out,map
    end
    local configs={{self.characterDropdown,chars,L["STATS_ALL_CHARS"],"character"},{self.seasonDropdown,seasons,L["STATS_ALL_SEASONS"],"season"},{self.dungeonDropdown,dungeons,L["STATS_ALL_DUNGEONS"],"dungeon"}}
    for _,cfg in ipairs(configs)do local items,map=Items(cfg[2],cfg[3]);cfg[1]:SetItems(items);if self.filters[cfg[4]]~="ALL"and not map[self.filters[cfg[4]]]then self.filters[cfg[4]]="ALL"end;cfg[1]:SetSelectedValue(self.filters[cfg[4]])end
    self.roleDropdown:SetItems({{text=L["STATS_ALL_ROLES"],value="ALL"},{text="Tank",value="TANK"},{text="Healer",value="HEALER"},{text="DPS",value="DAMAGER"}});self.roleDropdown:SetSelectedValue(self.filters.role)
    self.levelDropdown:SetItems(LEVEL_ITEMS);self.levelDropdown:SetSelectedValue(self.filters.level)
end
function PanelStats:FilteredSamples()
    local out={}
    for _,run in ipairs(MitzuMPlus:GetAllRuns()or{})do
        local season=SeasonInfo(run)
        if(self.filters.character=="ALL"or CharacterKey(run)==self.filters.character)
          and(self.filters.season=="ALL"or season==self.filters.season)
          and(self.filters.role=="ALL"or Role(run)==self.filters.role)
          and(self.filters.dungeon=="ALL"or run.dungeonName==self.filters.dungeon)
          and LevelMatches(run.keyLevel,self.filters.level)then out[#out+1]=RunSample(run)end
    end
    table.sort(out,function(a,b)return(tonumber(a.run.startTime) or 0)>(tonumber(b.run.startTime) or 0)end);return out
end

function PanelStats:Render()
    if not self.content then return end
    Destroy(self.dynamic);local samples=self:FilteredSamples();local total=#samples;local timed,best=0,0
    for _,s in ipairs(samples)do if s.run.inTime then timed=timed+1 end;best=math.max(best,tonumber(s.run.keyLevel) or 0) end
    self.cards[1].value:SetText(total);self.cards[2].value:SetText(total>0 and string.format("%.0f%%",timed/total*100)or"-");self.cards[3].value:SetText(best>0 and("+"..best)or"-")
    local y=-4;local title,line=SectionTitle(self.content,L["STATS_TREND"],y);self.dynamic[#self.dynamic+1]=title;self.dynamic[#self.dynamic+1]=line;y=y-27
    local h=TableHeader(self.content,TREND_COLS,y);self.dynamic[#self.dynamic+1]=h;y=y-28
    for i=1,math.min(12,total)do
        local s=samples[i];local run=s.run;local result=run.inTime and L["RUN_IN_TIME"] or ((s.duration>0) and L["RESULT_OUT"] or L["RESULT_INCOMPLETE"])
        local values={date={text=DateText(run.startTime)},dungeon={text=run.dungeonName or "?",color=Theme.TEXT.primary},level={text="+"..tostring(run.keyLevel or 0),color=Theme.GOLD.gold4},
            result={text=result,color=run.inTime and Theme.STATUS.ok or Theme.STATUS.bad},margin={text=s.margin and FTime(s.margin,true)or"-",color=s.margin and(s.margin>=0 and Theme.STATUS.ok or Theme.STATUS.bad)or Theme.TEXT.dim},
            metric={text=s.metricValid and(FNum(s.metric).." "..s.metricLabel)or"-",color=s.metricValid and Theme.STATUS.info or Theme.TEXT.dim},
            deaths={text=s.ownDeaths~=nil and tostring(s.ownDeaths)or"-"}}
        local row=TableRow(self.content,TREND_COLS,values,y,i);self.dynamic[#self.dynamic+1]=row;y=y-28
    end
    if total==0 then local empty=NewText(self.content,"normal",12,Theme.TEXT.dim);empty:SetPoint("TOPLEFT",10,y-10);empty:SetText(L["STATS_NO_MATCH"]);self.dynamic[#self.dynamic+1]=empty;y=y-42 end
    y=y-18;title,line=SectionTitle(self.content,L["STATS_BY_DUNGEON"],y);self.dynamic[#self.dynamic+1]=title;self.dynamic[#self.dynamic+1]=line;y=y-27
    local dh=TableHeader(self.content,DUNGEON_COLS,y);self.dynamic[#self.dynamic+1]=dh;y=y-28
    local map={}
    for _,s in ipairs(samples)do local name=s.run.dungeonName or "?";local d=map[name]or{name=name,runs=0,timed=0,best=0,margins={},deaths=0};map[name]=d;d.runs=d.runs+1;if s.run.inTime then d.timed=d.timed+1 end;d.best=math.max(d.best,tonumber(s.run.keyLevel) or 0);if s.margin then d.margins[#d.margins+1]=s.margin end;d.deaths=d.deaths+s.groupDeaths end
    local dungeons={};for _,d in pairs(map)do d.success=d.timed/d.runs*100;d.median=Median(d.margins);dungeons[#dungeons+1]=d end
    table.sort(dungeons,function(a,b)if a.success==b.success then return a.runs>b.runs end;return a.success<b.success end)
    for i,d in ipairs(dungeons)do
        local values={dungeon={text=d.name,color=Theme.TEXT.primary},runs={text=tostring(d.runs)},success={text=string.format("%.0f%%",d.success),color=d.success>=60 and Theme.STATUS.ok or Theme.STATUS.warn},best={text="+"..d.best,color=Theme.GOLD.gold4},margin={text=d.median and FTime(d.median,true)or"-",color=d.median and(d.median>=0 and Theme.STATUS.ok or Theme.STATUS.bad)or Theme.TEXT.dim},deaths={text=string.format("%.1f",d.deaths/d.runs)}}
        local row=TableRow(self.content,DUNGEON_COLS,values,y,i);self.dynamic[#self.dynamic+1]=row;y=y-28
    end
    y=y-18;title,line=SectionTitle(self.content,L["STATS_BY_ROLE"],y);self.dynamic[#self.dynamic+1]=title;self.dynamic[#self.dynamic+1]=line;y=y-29
    -- DPS, HPS y DTPS no son unidades comparables. Nunca calculamos una
    -- mediana comun al mostrar varios roles: cada rol conserva su serie.
    local metrics={TANK={},HEALER={},DAMAGER={}};local margins={};local ownDeaths,deathN=0,0
    for _,s in ipairs(samples)do if s.metricValid then metrics[s.role][#metrics[s.role]+1]=s.metric end;if s.margin then margins[#margins+1]=s.margin end;if s.ownDeaths~=nil then ownDeaths=ownDeaths+s.ownDeaths;deathN=deathN+1 end end
    local performance
    if self.filters.role~="ALL"then
        local role=self.filters.role;performance=string.format(L["STATS_MEDIAN_PERF"],ROLE_LABEL[role]or role,Median(metrics[role])and FNum(Median(metrics[role]))or L["STATS_NO_DATA"],role=="HEALER"and"HPS"or(role=="TANK"and"DTPS"or"DPS"))
    else
        local parts={}
        for _,role in ipairs({"TANK","HEALER","DAMAGER"})do local value=Median(metrics[role]);if value then parts[#parts+1]=string.format("%s %s %s",ROLE_LABEL[role],FNum(value),role=="HEALER"and"HPS"or(role=="TANK"and"DTPS"or"DPS"))end end
        performance=L["STATS_ROLE_MEDIANS"]..(#parts>0 and table.concat(parts,"   ·   ")or L["STATS_NO_DATA"])
    end
    local lines={
        performance,
        string.format(L["STATS_OWN_DEATHS"],deathN>0 and string.format("%.2f/run",ownDeaths/deathN)or L["STATS_NO_DATA"],Median(margins)and FTime(Median(margins),true)or L["STATS_NO_DATA"]),
    }
    for _,text in ipairs(lines)do local fs=NewText(self.content,"normal",11,Theme.TEXT.secondary);fs:SetPoint("TOPLEFT",10,y);fs:SetText(text);self.dynamic[#self.dynamic+1]=fs;y=y-22 end
    self.content:SetHeight(math.max(80,math.abs(y)+18));self.scroll:UpdateScrollRange()
end
function PanelStats:Refresh()
    if not self.panel then return end
    local runs=MitzuMPlus:GetAllRuns()or{};self:RefreshFilterItems(runs);self:Render()
end
return PanelStats
