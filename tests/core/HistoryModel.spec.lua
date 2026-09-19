-- Pure model tests for History V2 filtering, sorting, result and pagination.
local tests, assertions, failures = 0, 0, {}
local function equal(a,b,label) assertions=assertions+1;if a~=b then error((label or "equal")..": "..tostring(a).." ~= "..tostring(b),2) end end
local function test(name,fn) tests=tests+1;local ok,e=pcall(fn);if not ok then failures[#failures+1]=name..": "..tostring(e) end end

local newLocale = dofile("tests/harness/locale_stub.lua")
_G.MitzuMPlus={Theme={},L=newLocale("enUS")}
_G.LibStub=function() return {GetAddon=function() return _G.MitzuMPlus end} end
_G.time=function() return 2000000 end
_G.date=os.date
dofile("MitzuMPlus/UI/Panels/Historial.lua")
local H=_G.MitzuMPlus.PanelHistorial
local function run(id, fields)
    local r={runID=id,dungeonName="Dungeon "..id,keyLevel=10,inTime=true,
        keystoneUpgradeLevels=1,timeLimit=1800,completionTime=1700,startTime=1900000-id,
        playerName="Player"..id,playerRealm="Realm",playerRole="DAMAGER",seasonKey="S2",group={}}
    for k,v in pairs(fields or {}) do r[k]=v end
    return r
end

test("result enum and margins",function()
    local c,m=H.FormatResult(run(1,{keystoneUpgradeLevels=3,completionTime=900}));equal(c,"+3");equal(math.floor(m),180)
    c,m=H.FormatResult(run(2,{keystoneUpgradeLevels=2,completionTime=1300}));equal(c,"+2");equal(math.floor(m),140)
    c,m=H.FormatResult(run(3,{keystoneUpgradeLevels=1,completionTime=1700}));equal(c,"+1");equal(math.floor(m),100)
    c,m=H.FormatResult(run(4,{inTime=false,completionTime=1880}));equal(c,"OUT");equal(math.floor(m),-80)
end)

test("empty and single run pagination",function()
    local page,p,pages=H.Paginate({},1,20);equal(#page,0);equal(p,1);equal(pages,1)
    page,p,pages=H.Paginate({run(1)},9,20);equal(#page,1);equal(p,1);equal(pages,1)
end)

test("42 and more than 100 runs paginate",function()
    local list={};for i=1,42 do list[i]=run(i) end
    local page,p,pages=H.Paginate(list,3,20);equal(#page,2);equal(p,3);equal(pages,3)
    for i=43,105 do list[i]=run(i) end
    page,p,pages=H.Paginate(list,6,20);equal(#page,5);equal(pages,6)
end)

test("search matches dungeon character and party",function()
    local list={run(1,{dungeonName="Guarida de Nalorakk",group={{name="Compañero",realm="Luna"}}})}
    equal(#H.FilterRuns(list,{search="nalorakk"}),1)
    equal(#H.FilterRuns(list,{search="player1"}),1)
    equal(#H.FilterRuns(list,{search="compañero"}),1)
    equal(#H.FilterRuns(list,{search="ausente"}),0)
end)

test("all primary filters combine",function()
    local target=run(9,{dungeonName="Arena",playerName="Mina",playerRole="TANK",inTime=false,
        seasonKey="S2",isFavorite=true,notes="nota"})
    local other=run(10,{dungeonName="Otra",playerName="Mina",playerRole="TANK",inTime=false})
    local f={search="mina",dungeon="Arena",result="OUT",character="Mina-Realm",role="TANK",season="S2",extra="favorite"}
    local out=H.FilterRuns({other,target},f);equal(#out,1);equal(out[1],target)
    f.extra="notes";equal(#H.FilterRuns({target},f),1)
end)

test("sorting date level result and dungeon",function()
    local a=run(1,{startTime=10,keyLevel=2,keystoneUpgradeLevels=1,dungeonName="A"})
    local b=run(2,{startTime=20,keyLevel=15,keystoneUpgradeLevels=3,dungeonName="B"})
    equal(H.FilterRuns({a,b},{sortBy="date"})[1],b)
    equal(H.FilterRuns({a,b},{sortBy="level"})[1],b)
    equal(H.FilterRuns({a,b},{sortBy="result"})[1],b)
    equal(H.FilterRuns({a,b},{sortBy="dungeon"})[1],b)
end)

test("partial data stays readable",function()
    -- Sin completionTime la run no termino: el codigo es "INCOMPLETE" (neutral,
    -- lo usan filtros y orden) y lo pintado es su etiqueta ya traducida.
    local partial={runID=88,inTime=false}
    local code,margin,display=H.FormatResult(partial);equal(code,"INCOMPLETE");equal(margin,nil)
    equal(type(display),"string")
    equal(display:find(H.ResultLabel("INCOMPLETE"),1,true)~=nil,true,display)
    equal(H.ResultLabel("INCOMPLETE"),"Incomplete","enUS label")
    equal(H.ResultLabel("OUT"),"Out"); equal(H.ResultLabel("+3"),"+3","codes stay neutral")
    equal(#H.FilterRuns({partial},{}),1)
    equal(#H.FilterRuns({partial},{result="INCOMPLETE"}),1);equal(#H.FilterRuns({partial},{result="OUT"}),0)
end)

test("similar legitimate runs are both visible",function()
    local a=run(41,{completionTime=1849,startTime=1000});local b=run(42,{completionTime=1849,startTime=5000})
    local out=H.FilterRuns({a,b},{});equal(#out,2);equal(out[1],b);equal(out[2],a)
end)

if #failures>0 then error(string.format("HistoryModel: %d failures\n%s",#failures,table.concat(failures,"\n")),0)end
return{tests=tests,assertions=assertions}
