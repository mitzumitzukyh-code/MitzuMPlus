-- MitzuMPlus M+ Historial - lectura comun y conservadora de runs.
-- Una UI debe pedir los datos aqui en vez de reinterpretar campos por su cuenta.
local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local RunMetrics = {}
MitzuMPlus.RunMetrics = RunMetrics

local ROLE_LABEL = { TANK="Tank", HEALER="Healer", DAMAGER="DPS", NONE="DPS" }

local function Number(v)
    if v == nil then return nil end
    local n = tonumber(v)
    return n
end

local function FirstPositive(...)
    for i=1,select("#",...) do
        local n=Number((select(i,...)))
        if n and n>0 then return n end
    end
    return nil
end

local function BaseName(name)
    return (tostring(name or ""):match("^([^%-]+)") or ""):lower()
end

function RunMetrics:GetRole(run)
    local role=tostring(run and (run.playerRole or run.role) or ""):upper()
    if role~="TANK" and role~="HEALER" then role="DAMAGER" end
    return role,ROLE_LABEL[role]
end

function RunMetrics:GetCharacterKey(run)
    if not run then return "" end
    return tostring(run.playerName or "").."-"..tostring(run.playerRealm or "")
end

function RunMetrics:GetOwnGroupEntry(run)
    if not run then return nil end
    local own=BaseName(run.playerName)
    if own=="" then return nil end
    for _,member in ipairs(type(run.groupStats)=="table" and run.groupStats or {}) do
        if type(member)=="table" and BaseName(member.name or member.playerName)==own then return member end
    end
    return nil
end

function RunMetrics:GetDuration(run)
    local duration=Number(run and run.completionTime)
    return duration and duration>0 and duration or nil
end

function RunMetrics:GetMargin(run)
    local duration=self:GetDuration(run)
    local limit=Number(run and run.timeLimit)
    if not duration or not limit or limit<=0 then return nil end
    return limit-duration
end

function RunMetrics:GetRoleMetric(run)
    if not run then return nil,nil,nil end
    local duration=self:GetDuration(run)
    if not duration then return nil,nil,nil end
    local stats=type(run.stats)=="table" and run.stats or {}
    local own=self:GetOwnGroupEntry(run)
    local role=self:GetRole(run)
    local total,label,source
    if role=="HEALER" then
        total=FirstPositive(stats.healingTotal,own and own.healing)
        label="HPS";source=stats.healDataSource or run.dataSource
    elseif role=="TANK" then
        total=FirstPositive(stats.tankDamageTakenEffective,stats.tankDamageTakenTotal,stats.damageTaken,own and own.damageTaken)
        label="DTPS";source=stats.tankDataSource or stats.dmgDataSource or run.dataSource
    else
        total=FirstPositive(stats.damageTotal,own and own.damage)
        label="DPS";source=stats.dmgDataSource or run.dataSource
    end
    if not total then return nil,label,source end
    return total/duration,label,source
end

local function OwnValue(run,groupKey,statsKey)
    local own=RunMetrics:GetOwnGroupEntry(run)
    local value=Number(own and own[groupKey])
    if value~=nil then return value,"groupStats" end
    local stats=type(run and run.stats)=="table" and run.stats or {}
    value=Number(stats[statsKey])
    local source=tostring(run and run.dataSource or "")
    -- SanitizeRunData pone ceros en campos antiguos. Un cero sin una fuente
    -- medible no demuestra que el evento fuese realmente observado.
    if value~=nil and (value>0 or (source~="" and source~="STRUCTURAL_ONLY")) then return value,source end
    return nil,nil
end

function RunMetrics:GetOwnDeaths(run) return OwnValue(run,"deaths","deathsSelf") end
function RunMetrics:GetOwnKicks(run) return OwnValue(run,"kicks","kicksSelf") end
function RunMetrics:GetOwnDispels(run) return OwnValue(run,"dispels","dispelsSelf") end

function RunMetrics:GetGroupDeaths(run)
    local value=Number(run and run.stats and run.stats.deaths)
    return value
end

function RunMetrics:GetSeason(run)
    local key=tostring(run and run.seasonKey or "")
    if key=="" or key=="NONE" then return "UNASSIGNED","Sin temporada (histórico)" end
    local label=tostring(run and run.seasonName or "")
    if label=="" then
        local exp,season=key:match("^exp(%d+)_s(%d+)$")
        local names=MitzuMPlus.Constants and MitzuMPlus.Constants.EXPANSION_NAMES or {}
        if season then label=string.format("%s - Temporada %s",names[tonumber(exp)] or ("Expansión "..exp),season) else label=key end
    end
    return key,label
end

function RunMetrics:GetQuality(run)
    if type(run)~="table" then return "INVALID","Inválida" end
    local structural=(tostring(run.dungeonName or "")~="" and (Number(run.keyLevel) or 0)>0 and self:GetDuration(run)~=nil)
    if not structural then return "INVALID","Incompleta" end
    local metric=self:GetRoleMetric(run)
    local deaths=self:GetOwnDeaths(run)
    local kicks=self:GetOwnKicks(run)
    local dispels=self:GetOwnDispels(run)
    local observed=(deaths~=nil and 1 or 0)+(kicks~=nil and 1 or 0)+(dispels~=nil and 1 or 0)
    if metric and observed>=2 then return "COMPLETE","Completa" end
    if metric or observed>0 then return "PARTIAL","Parcial" end
    return "STRUCTURAL","Estructural" end

function RunMetrics:FindRunByID(runID)
    runID=tonumber(runID)
    if not runID then return nil end
    if MitzuMPlus.GetRun then return MitzuMPlus:GetRun(runID) end
    return MitzuMPlus.db and MitzuMPlus.db.global and MitzuMPlus.db.global.runs and MitzuMPlus.db.global.runs[runID]
end

return RunMetrics
