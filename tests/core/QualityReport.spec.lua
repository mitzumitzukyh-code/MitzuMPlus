-- Final product Bug Report and invariant sections remain complete and sanitized.
local tests, assertions, failures=0,0,{}
local function truthy(v,l)assertions=assertions+1;if not v then error(l or "expected true",2)end end
local function equal(a,b,l)assertions=assertions+1;if a~=b then error((l or "equal")..": "..tostring(a).." ~= "..tostring(b),2)end end
local function test(n,f)tests=tests+1;local ok,e=pcall(f);if not ok then failures[#failures+1]=n..": "..tostring(e)end end
_G.GetBuildInfo=function()return "12.1.0","69814","Sep 10 2026",120100 end
_G.GetLocale=function()return "esMX"end
_G.date=function()return "2026-09-13 18:00:00"end
_G.UnitClass=function()return "Monk","MONK"end
_G.MitzuMPlus={VERSION="7.14.0-rc1",db={global={runs={},nextRunID=1}},
    QASafe={Text=function(v,max)local s=v==nil and "nil" or tostring(v):gsub("|","/");return max and s:sub(1,max)or s end},
    DungeonContext={GetState=function()return "OUTSIDE"end,IsChallengeActive=function()return false end},
    ChallengeClock={GetState=function()return "UNAVAILABLE"end},
    PartyProfiler={GetMembers=function()return{}end,GetRosterDiagnostics=function()return{expectedGroupSize=1,cachedSize=1,lastRosterAge=0}end},
    KeyPredictionHUD={GetMode=function()return "HIDDEN"end,IsVisible=function()return false end,IsPreview=function()return false end,GetDisplayed=function()return{prediction="NONE"}end,
        DiagnosticFields=function()return{{"mode","HIDDEN"},{"prediction","NONE"}}end},
    RuntimeCapabilities={Matrix=function()return{"challengeMode=AVAILABLE"}end},
    FlightRecorder={Count=function()return 0 end,Capacity=function()return 200 end,Lines=function()return{}end,Clear=function()end},
    ErrorLogger={Entries=function()return{}end,Count=function()return 0 end,DebugCount=function()return 0 end},
}
dofile("MitzuMPlus/modules/QA/Invariants.lua")
dofile("MitzuMPlus/modules/QA/BugReport.lua")
local B=_G.MitzuMPlus.BugReport
test("report has only final product sections",function()
    local text=B:Build()
    for _,name in ipairs({"BUILD","CONTEXT","PLAYER","PARTY","RUN","HISTORY","TRACKER","PREDICTION","CAPABILITIES","INVARIANTS","RECENT EVENTS","ERRORS"})do truthy(text:find("["..name.."]",1,true),name)end
    for _,name in ipairs({"[ROUTE]","[COACH]","[ALIGNMENT]","[EVIDENCE]"})do truthy(not text:find(name,1,true),name)end
    truthy(text:find("sectionsFailed=none",1,true));truthy(text:find("Addon=7.14.0%-rc1"))
end)
test("healthy outside state passes every invariant",function()
    local I=_G.MitzuMPlus.QAInvariants;local results=I:Evaluate(I:Gather());local totals=I:Summary(results)
    equal(totals.FAIL,0);equal(totals.WARN,0);equal(totals.PASS,9)
end)
test("duplicate session IDs are diagnosed but not removed",function()
    _G.MitzuMPlus.db.global.runs={{sessionID="same"},{sessionID="same"}}
    local I=_G.MitzuMPlus.QAInvariants;local results=I:Evaluate(I:Gather());local found
    for _,r in ipairs(results)do if r.name=="HISTORY_NO_DUPLICATE_FINALIZATION"then found=r end end
    equal(found.status,"FAIL");equal(#_G.MitzuMPlus.db.global.runs,2)
end)
if #failures>0 then error(string.format("QualityReport: %d failures\n%s",#failures,table.concat(failures,"\n")),0)end
return{tests=tests,assertions=assertions}
