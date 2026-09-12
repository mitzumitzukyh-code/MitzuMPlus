-- MitzuMPlus RouteAdvisor v5.2
-- Optional imported pull plan + autonomous pull learning from Enemy Forces deltas.
local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local RouteAdvisor = {}
MitzuMPlus.RouteAdvisor = RouteAdvisor

RouteAdvisor._active = false
RouteAdvisor._lastPct = 0
RouteAdvisor._openPullGain = 0
RouteAdvisor._lastGainAt = 0
RouteAdvisor._pulls = {}
RouteAdvisor._route = nil
RouteAdvisor._routeIndex = 1
RouteAdvisor._dungeonKey = nil

local function now()
    return (GetTime and GetTime()) or 0
end
local function clamp(v,a,b) return math.max(a, math.min(b,v)) end
local function dungeonKey(run)
    local id = tonumber(run and (run.mapChallengeModeID or run.challengeModeID or run.mapID))
    if id and id > 0 then return tostring(id) end
    return tostring(run and run.dungeonName or 'unknown'):lower():gsub('%s+','_')
end
local function ensureDB()
    if not MitzuMPlus.db or not MitzuMPlus.db.profile then return nil end
    MitzuMPlus.db.profile.routes = MitzuMPlus.db.profile.routes or {}
    return MitzuMPlus.db.profile.routes
end

function RouteAdvisor:Start(run)
    self._active = true
    self._lastPct = 0
    self._openPullGain = 0
    self._lastGainAt = 0
    self._pulls = {}
    self._routeIndex = 1
    self._dungeonKey = dungeonKey(run)
    local routes = ensureDB()
    self._route = routes and routes[self._dungeonKey] or nil
    if not self._route and routes and type(routes.pending_mdt) == 'table' then
        local pending=routes.pending_mdt
        pending.pending=nil
        pending.challengeModeID=tonumber(run and (run.mapChallengeModeID or run.challengeModeID or run.mapID))
        routes[self._dungeonKey]=pending
        routes.pending_mdt=nil
        self._route=pending
        if MitzuMPlus.Print then
            MitzuMPlus:Print('|cFF21de66Ruta MDT vinculada automáticamente|r a esta M+.')
        end
    end
end

function RouteAdvisor:Stop()
    if self._openPullGain > 0.05 then self:_FinalizePull() end
    self._active = false
end

function RouteAdvisor:_FinalizePull()
    local gain = tonumber(self._openPullGain) or 0
    if gain <= 0.05 then self._openPullGain = 0 return end
    self._pulls[#self._pulls+1] = gain
    self._openPullGain = 0
    self._routeIndex = math.min((self._routeIndex or 1) + 1, 999)
end

function RouteAdvisor:Update(enemyPct)
    if not self._active then return end
    local st = MitzuMPlus.db and MitzuMPlus.db.profile and MitzuMPlus.db.profile.settings
    if st and st.routeAutoLearn == false then return end
    local pct = tonumber(enemyPct) or 0
    pct = clamp(pct, 0, 100)
    if self._lastPct == 0 and pct > 0 then
        self._lastPct = pct
        return
    end
    local delta = pct - (self._lastPct or 0)
    if delta > 0.01 and delta < 35 then
        self._openPullGain = (self._openPullGain or 0) + delta
        self._lastGainAt = now()
        self._lastPct = pct
    elseif pct >= self._lastPct then
        self._lastPct = pct
    end
    -- No new forces for a short window => treat accumulated gain as one pull.
    if self._openPullGain > 0.05 and (now() - (self._lastGainAt or 0)) >= 4.0 then
        self:_FinalizePull()
    end
end

function RouteAdvisor:GetAveragePullPct()
    local total, n = 0, 0
    for _,v in ipairs(self._pulls) do
        if v > 0.2 then total=total+v; n=n+1 end
    end
    if self._openPullGain > 0.2 then total=total+self._openPullGain; n=n+1 end
    if n == 0 then return nil, 0 end
    return total/n, n
end

function RouteAdvisor:GetImportedRoute()
    return self._route
end

function RouteAdvisor:GetNextPullTarget(currentPct)
    currentPct = tonumber(currentPct) or 0
    if self._route and type(self._route.pulls) == 'table' and #self._route.pulls > 0 then
        local idx = math.max(1, math.min(self._routeIndex or 1, #self._route.pulls))
        local gain = tonumber(self._route.pulls[idx]) or 0
        local pp = self._route.plannedPulls and self._route.plannedPulls[idx]
        if pp and pp.estimated then
            local learned = self:GetAveragePullPct()
            if learned and learned > 0.5 then gain = learned end
        end
        return gain, 'route', idx, #self._route.pulls
    end
    local avg, n = self:GetAveragePullPct()
    if avg and avg > 0 then return avg, 'auto', n, nil end
    -- Conservative cold-start fallback. It is labelled low confidence by PredictionEngine.
    return 7.0, 'auto', 0, nil
end

function RouteAdvisor:GetRemainingPulls(currentPct)
    local remaining = math.max(0, 100 - (tonumber(currentPct) or 0))
    if self._route and type(self._route.pulls) == 'table' and #self._route.pulls > 0 then
        local left = math.max(0, #self._route.pulls - (self._routeIndex or 1) + 1)
        return left, 'route'
    end
    local avg = self:GetAveragePullPct()
    if not avg or avg < 0.5 then avg = 7.0 end
    return math.max(0, math.ceil(remaining / avg)), 'auto'
end

-- Generic import format: a comma-separated list of pull Enemy Forces percentages.
-- Example: /emp route 7.2,8.6,6.4,9.1,7.8
function RouteAdvisor:ImportSimpleRoute(text, run)
    if type(text) ~= 'string' then return false, 'Formato inválido' end
    local pulls = {}
    for token in text:gmatch('[^,;]+') do
        local n = tonumber((token:gsub('%%',''):gsub('%s+','')))
        if n and n > 0 and n <= 35 then pulls[#pulls+1]=n end
    end
    if #pulls == 0 then return false, 'No se encontraron pulls válidos' end
    local routes = ensureDB(); if not routes then return false, 'DB no disponible' end
    local key = dungeonKey(run or _G.MitzuMPlusCurrentRun or {})
    routes[key] = { pulls=pulls, name='Ruta importada', updated=(time and time() or 0) }
    self._route = routes[key]; self._routeIndex = 1; self._dungeonKey = key
    return true, #pulls
end


function RouteAdvisor:SaveImportedMDTRoute(route, run)
    if type(route) ~= 'table' or type(route.pulls) ~= 'table' or #route.pulls == 0 then
        return false, 'Ruta MDT inválida'
    end
    local routes=ensureDB(); if not routes then return false, 'DB no disponible' end
    local activeRun = run or _G.MitzuMPlusCurrentRun
    local key
    if tonumber(route.challengeModeID) then
        key=tostring(tonumber(route.challengeModeID))
    elseif activeRun and tonumber(activeRun.mapChallengeModeID or activeRun.challengeModeID or activeRun.mapID) then
        key=dungeonKey(activeRun)
        route.challengeModeID=tonumber(activeRun.mapChallengeModeID or activeRun.challengeModeID or activeRun.mapID)
    else
        -- Si no tenemos MDT cargado ni una dungeon activa, conservamos la ruta pendiente.
        -- Se vinculará automáticamente al iniciar la próxima M+; no se pierde el import.
        key='pending_mdt'
        route.pending=true
    end
    routes[key]=route
    if key ~= 'pending_mdt' then
        self._route=route; self._routeIndex=1; self._dungeonKey=key
    end
    return true, #route.pulls
end

function RouteAdvisor:ClearRoute(run)
    local routes=ensureDB(); if not routes then return false end
    local key=dungeonKey(run or _G.MitzuMPlusCurrentRun or {})
    routes[key]=nil
    if key==self._dungeonKey then self._route=nil; self._routeIndex=1 end
    return true
end

if MitzuMPlus.EventBus and MitzuMPlus.EventBus.On then
    MitzuMPlus.EventBus:On('RUN_COMPLETED', function() RouteAdvisor:Stop() end, 90)
    MitzuMPlus.EventBus:On('RUN_RESET', function() RouteAdvisor:Stop() end, 90)
end
