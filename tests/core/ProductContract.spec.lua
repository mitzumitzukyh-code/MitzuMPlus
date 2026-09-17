-- Release-facing product boundary: runtime manifest, commands and package content.
local tests, assertions, failures=0,0,{}
local function truthy(v,l)assertions=assertions+1;if not v then error(l or "expected true",2)end end
local function equal(a,b,l)assertions=assertions+1;if a~=b then error((l or "equal")..": "..tostring(a).." ~= "..tostring(b),2)end end
local function test(n,f)tests=tests+1;local ok,e=pcall(f);if not ok then failures[#failures+1]=n..": "..tostring(e)end end
local function read(path)local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local toc=read("MitzuMPlus/MitzuMPlus.toc")
local init=read("MitzuMPlus/Init.lua")

test("manifest defines the final product",function()
    truthy(toc:find("## Title: MitzuMPlus",1,true));truthy(toc:find("history, statistics, player analysis and live key prediction",1,true))
    truthy(not toc:find("MythicDungeonTools",1,true));truthy(not toc:find("MitzuRouteArrows",1,true))
end)
test("retired systems are not loaded",function()
    for _,word in ipairs({"RouteProgress","RouteManager","RouteAdvisor","RouteSchema","MDTImporter","AdaptiveRoute","CoachAdvice","PanelCoach","PublicAPI"})do
        truthy(not toc:find(word,1,true),word.." remains in TOC")
    end
end)
test("only four product tabs remain, and their labels are localized",function()
    local tabs=read("MitzuMPlus/UI/Tabs.lua")
    -- 1.1.0-dev.10: la barra ya no escribe texto; nombra claves de AceLocale.
    for _,key in ipairs({"TABBAR_HISTORY","TABBAR_STATS","TABBAR_PLAYERS","TABBAR_SETTINGS"})do
        truthy(tabs:find('L["'..key..'"]',1,true),key)
    end
    truthy(not tabs:find("M+ COACH",1,true))
    for _,label in ipairs({"HISTORIAL","ESTADÍSTICAS","JUGADORES","CONFIGURACIÓN"})do
        truthy(not tabs:find('"'..label..'"',1,true),label.." must not be hardcoded")
    end
end)
test("release commands are intentionally small",function()
    for _,cmd in ipairs({'RegisterChatCommand("emp"','cmd == "tracker"','cmd == "bugreport"','cmd == "historial"'})do truthy(init:find(cmd,1,true),cmd)end
    for _,cmd in ipairs({'cmd == "route"','cmd == "pull"','cmd == "next"','cmd == "mdt"','cmd == "alignment"','cmd == "evidence"','cmd == "coach"'})do truthy(not init:find(cmd,1,true),cmd)end
end)
test("tracker source has no retired dependency access",function()
    local presenter=read("MitzuMPlus/modules/Tracker/TrackerPresenter.lua")
    for _,name in ipairs({"TrackerPresenter","TrackerView","MitzuTracker"})do
        local src=read("MitzuMPlus/modules/Tracker/"..name..".lua")
        for _,pattern in ipairs({"MitzuMPlus%.RouteProgress","MitzuMPlus%.RouteManager","MitzuMPlus%.RouteAdvisor","MitzuMPlus%.CoachAdvice","C_NamePlate","MDT"})do truthy(not src:find(pattern),name.." "..pattern)end
    end
    for _,code in ipairs({'["+3"] = "+3"','["+2"] = "+2"','["+1"] = "+1"','["FUERA"] = "OVERTIME"'})do truthy(presenter:find(code,1,true),code)end
    truthy(toc:find("modules\\Tracker\\MitzuTracker.lua",1,true),"Mitzu Tracker loaded")
    truthy(not toc:find("KeyPredictionHUD.lua",1,true),"legacy HUD retired from the manifest")
end)
test("route and MDT runtime files are absent",function()
    for _,path in ipairs({"MitzuMPlus/modules/RouteProgress.lua","MitzuMPlus/modules/RouteManager.lua","MitzuMPlus/modules/MDTImporter.lua","MitzuMPlus/data/MDTEnemyData.lua","MitzuMPlus/API/PublicAPI.lua"})do
        local f=io.open(path,"rb");if f then f:close()end;equal(f,nil,path)
    end
end)
if #failures>0 then error(string.format("ProductContract: %d failures\n%s",#failures,table.concat(failures,"\n")),0)end
return{tests=tests,assertions=assertions}
