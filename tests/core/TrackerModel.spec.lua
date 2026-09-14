-- Prediction tracker model contract; no frames or game client required.
local tests, assertions, failures=0,0,{}
local function equal(a,b,l) assertions=assertions+1;if a~=b then error((l or "equal")..": "..tostring(a).." ~= "..tostring(b),2)end end
local function test(n,f)tests=tests+1;local ok,e=pcall(f);if not ok then failures[#failures+1]=n..": "..tostring(e)end end
_G.MitzuMPlus={}
dofile("MitzuMPlus/modules/KeyPredictionHUD.lua")
local H=_G.MitzuMPlus.KeyPredictionHUD

test("prediction enum is a strict allowlist",function()
    for input,expected in pairs({["+3"]="+3",["+2"]="+2",["+1"]="+1",FUERA="OVERTIME"})do
        equal(H.ReadPrediction({result=input}).code,expected)
    end
    equal(H.ReadPrediction({result="NEXT_BOSS"}),nil);equal(H.ReadPrediction({result="ROUTE"}),nil);equal(H.ReadPrediction(nil),nil)
end)
test("confidence and ETA require reliable basis",function()
    local p=H.ReadPrediction({result="+2",confidence=82,resultConfident=true,projectedTime=1390,effectiveElapsed=900,timeLimit=1800})
    equal(p.code,"+2");equal(p.confidence,82);equal(p.estimatedFinish,1390)
    p=H.ReadPrediction({result="+2",resultConfident=false,projectedTime=1390,effectiveElapsed=900,timeLimit=1800})
    equal(p.estimatedFinish,nil)
end)
test("official completed results",function()
    for levels,expected in pairs({[1]="+1",[2]="+2",[3]="+3"})do
        equal(H.FinalFromRun({inTime=true,keystoneUpgradeLevels=levels,completionTime=1000,completionInfoSource="API"}).code,expected)
    end
    equal(H.FinalFromRun({inTime=false,keystoneUpgradeLevels=0,completionTime=1900,completionInfoSource="API"}).code,"OVERTIME")
end)
test("unofficial completion falls back safely",function()
    local f=H.FinalFromRun({completionTime=1000},{code="+1"});equal(f.code,"+1");equal(f.source,"LAST_PREDICTION")
end)
test("optional detail toggles have a real effect",function()
    local model={mode="RUN",dungeon="Arena",level=11,elapsed=600,limit=1800,
        prediction={code="+2",confidence=80,confident=true,estimatedFinish=1400},showConfidence=true,showETA=true}
    local lines=H:Lines(model);equal(lines.prediction,"+2");equal(lines.detail,"Confianza 80%  -  Final ~23:20")
    model.showConfidence=false;lines=H:Lines(model);equal(lines.detail,"Final ~23:20")
    model.showETA=false;lines=H:Lines(model);equal(lines.detail,nil)
end)
test("preview only uses valid product data",function()
    local m=H:PreviewModel();equal(m.mode,"RUN");equal(m.prediction.code,"+2")
    local l=H:Lines(m);equal(l.title,"Ruby Life Pools +10");equal(l.prediction,"+2")
end)
if #failures>0 then error(string.format("TrackerModel: %d failures\n%s",#failures,table.concat(failures,"\n")),0)end
return{tests=tests,assertions=assertions}
