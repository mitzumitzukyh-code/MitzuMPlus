-- ============================================================================
-- MitzuMPlus M+ Historial - MidnightSafeTracking.lua (v5.1.0)
-- Uses only Blizzard APIs currently exposed to addons in Midnight.
-- No CLEU, no aura scanning, no UNIT_COMBAT inference, no fake combat metrics.
-- ============================================================================
local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
if not MitzuMPlus then return end

local _issecretvalue = rawget(_G, "issecretvalue")
local _canaccessvalue = rawget(_G, "canaccessvalue")

local function readable(v)
    if v == nil then return false end
    if _issecretvalue and _issecretvalue(v) then return false end
    if _canaccessvalue then
        local ok, can = pcall(_canaccessvalue, v)
        if ok and not can then return false end
    end
    return true
end

local function safeField(t, k)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[k] end)
    if not ok or not readable(v) then return nil end
    return v
end

local function safeNum(v)
    if not readable(v) then return 0 end
    local ok, n = pcall(tonumber, v)
    return ok and n or 0
end

local function safeStr(v)
    if not readable(v) then return nil end
    local ok, x = pcall(tostring, v)
    return ok and x or nil
end

local DM = Enum and Enum.DamageMeterType or {}
local ST = Enum and Enum.DamageMeterSessionType or {}
local TYPES = {
    damage    = DM.DamageDone or 0,
    dps       = DM.Dps or 1,
    healing   = DM.HealingDone or 2,
    hps       = DM.Hps or 3,
    absorbs   = DM.Absorbs or 4,
    kicks     = DM.Interrupts or 5,
    dispels   = DM.Dispels or 6,
    taken     = DM.DamageTaken or 7,
    avoidable = DM.AvoidableDamageTaken or 8,
    deaths    = DM.Deaths or 9,
}
local OVERALL = ST.Overall or 0

-- Orden canonico de metricas. Se usa tanto para capturar la linea base al
-- arrancar la key como para el refresco posterior, de modo que ambos recorren
-- exactamente el mismo conjunto.
local METRIC_ORDER = {"damage","healing","absorbs","taken","avoidable","kicks","dispels","deaths"}

-- Segundos de COMBATE acumulados en la sesion indicada. Details usa la misma
-- llamada (GetSessionDurationSeconds(0/1)) para medir la duracion de segmento.
local function sessionDuration(sessionType)
    local cdm = _G.C_DamageMeter
    if not cdm or not cdm.GetSessionDurationSeconds then return nil end
    local ok, d = pcall(cdm.GetSessionDurationSeconds, sessionType)
    if not ok or not readable(d) then return nil end
    return tonumber(d)
end

local function getSession(metricType)
    local cdm = _G.C_DamageMeter
    if not cdm or not cdm.GetCombatSessionFromType then return nil end
    if cdm.IsDamageMeterAvailable then
        local ok, available = pcall(cdm.IsDamageMeterAvailable)
        if ok and available == false then return nil end
    end
    local ok, session = pcall(cdm.GetCombatSessionFromType, OVERALL, metricType)
    if not ok or not readable(session) or type(session) ~= "table" then return nil end
    return session
end

local function sourceKey(src)
    local guid = safeStr(safeField(src, "sourceGUID"))
    if guid and guid ~= "" then return "g:" .. guid, guid end
    local name = safeStr(safeField(src, "name"))
    if name and name ~= "" then return "n:" .. name, nil end
    return nil, nil
end



-- Linea base de la sesion Overall al arrancar la key.
--
-- v5.4.2 (BUG A2): Enum.DamageMeterSessionType.Overall es la sesion ACUMULADA,
-- no el segmento de la M+. Nadie la reseteaba al empezar la key, asi que
-- run.stats.damageTotal podia arrastrar todo lo hecho desde el login.
-- NO llamamos a C_DamageMeter.ResetAllCombatSessions(): Details la envuelve
-- (core/parser_nocleu1.lua) y le romperiamos los segmentos al usuario.
-- En su lugar guardamos el valor de cada fuente al inicio y restamos.
local function baselineFor(baseline, metricName, key)
    if not baseline or not baseline.valid then return 0 end
    local perMetric = baseline.metrics and baseline.metrics[metricName]
    if not perMetric or not key then return 0 end
    return tonumber(perMetric[key]) or 0
end

local function applyMetric(run, metricName, session, baseline)
    local sources = safeField(session, "combatSources")
    if type(sources) ~= "table" then return false, nil end
    local foundAny = false
    local localAmount = nil
    for _, src in ipairs(sources) do
        if type(src) == "table" and readable(src) then
            local raw = safeNum(safeField(src, "totalAmount"))
            local aps = safeNum(safeField(src, "amountPerSecond"))
            local isLocal = safeField(src, "isLocalPlayer") == true
            local key = sourceKey(src)

            -- Acotar a la key restando lo que esta fuente ya tenia al empezar.
            local amount = raw - baselineFor(baseline, metricName, key)
            if amount < 0 then amount = raw end



            if isLocal and run and run.stats then
                foundAny = true
                localAmount = amount
                local st = run.stats
                if metricName == "damage" then st.damageTotal = math.max(st.damageTotal or 0, amount)
                elseif metricName == "healing" then st.healingTotal = math.max(st.healingTotal or 0, amount)
                elseif metricName == "absorbs" then st.absorbTotal = math.max(st.absorbTotal or 0, amount)
                elseif metricName == "taken" then st.damageTaken = math.max(st.damageTaken or 0, amount); st.tankDamageTakenTotal = st.damageTaken
                elseif metricName == "avoidable" then st.avoidableDmg = math.max(st.avoidableDmg or 0, amount)
                elseif metricName == "kicks" then st.kicks = math.max(st.kicks or 0, amount); st.kicksSelf = st.kicks
                elseif metricName == "dispels" then st.dispels = math.max(st.dispels or 0, amount); st.dispelsSelf = st.dispels
                elseif metricName == "deaths" then st.deathsSelf = math.max(st.deathsSelf or 0, amount) end
                -- amountPerSecond viene calculado sobre TODA la ventana Overall,
                -- asi que no es valido cuando restamos linea base. El DPS/HPS/DTPS
                -- acotado a la key se calcula en RefreshSupportedCombatStats a
                -- partir de los segundos de combate transcurridos.
                if not (baseline and baseline.valid) then
                    if metricName == "damage" then st.dpsOfficial = aps
                    elseif metricName == "healing" then st.hpsOfficial = aps
                    elseif metricName == "taken" then st.dtpsOfficial = aps end
                end
            end
        end
    end
    return foundAny, localAmount
end

-- Captura la linea base al arrancar la key. Se llama desde OnChallengeStart,
-- fuera de combate, que es cuando los campos de C_DamageMeter son legibles.
function MitzuMPlus:CaptureCombatBaseline(run)
    run = run or _G.MitzuMPlusCurrentRun
    if not run or not _G.C_DamageMeter then return false end

    local baseline = {
        runStart = run.startTime,
        duration = sessionDuration(OVERALL) or 0,
        metrics  = {},
        valid    = true,
        readable = 0,
    }
    for _, name in ipairs(METRIC_ORDER) do
        local perMetric = {}
        local session = getSession(TYPES[name])
        local sources = session and safeField(session, "combatSources")
        if type(sources) == "table" then
            for _, src in ipairs(sources) do
                if type(src) == "table" and readable(src) then
                    local key = sourceKey(src)
                    if key then
                        perMetric[key] = safeNum(safeField(src, "totalAmount"))
                        baseline.readable = baseline.readable + 1
                    end
                end
            end
        end
        baseline.metrics[name] = perMetric
    end

    self._meterBaseline = baseline
    if self.ErrorLogger and self.ErrorLogger.LogEvent then
        self.ErrorLogger:LogEvent("METER_BASELINE", "C_DamageMeter baseline captured", {
            duration = baseline.duration,
            sources  = baseline.readable,
        })
    end
    return true
end

function MitzuMPlus:ClearCombatBaseline()
    self._meterBaseline = nil
end

-- Devuelve la linea base solo si pertenece a ESTA run.
--
-- SOBRE EL RESET DE Overall
-- -------------------------
-- Details imprime "the overall data has been reset." al empezar una M+, pero eso
-- es Details.historico:ResetOverallData(), que solo destruye SU tabla overall
-- interna. La ruta que si resetearia las sesiones de Blizzard (ResetServerDM)
-- no se llama ahi. Verificado en Details/functions/mythicdungeon/mythicdungeon.lua
-- y Details/classes/container_segments.lua. Conclusion: la sesion Overall de
-- C_DamageMeter NO se resetea al empezar la llave y sigue acumulando desde el
-- login, que es justo por lo que existe esta linea base.
--
-- Aun asi el reset puede ocurrir (el usuario lo pide a mano, u otro addon).
-- Si pasa, los valores crudos ya arrancan de cero: la linea base correcta pasa
-- a ser cero, no "invalida".
function MitzuMPlus:_GetCombatBaseline(run)
    local b = self._meterBaseline
    if not b or not run then return nil end
    if b.runStart ~= run.startTime then return nil end

    local nowDuration = sessionDuration(OVERALL)
    if nowDuration and nowDuration + 1 < (b.duration or 0) then
        if not b.resetSeen then
            b.resetSeen = true
            b.resetAtElapsed = (time and run.startTime) and math.max(0, time() - run.startTime) or 0
        end
        -- Overall arranca de nuevo desde 0: todo lo que hay ahora es posterior
        -- al reset, asi que no hay nada que restar.
        b.metrics  = {}
        b.duration = 0
        b.valid    = true
    end

    b.nowDuration = nowDuration
    return b
end

function MitzuMPlus:RefreshSupportedCombatStats(run)
    run = run or _G.MitzuMPlusCurrentRun
    if not run or not run.stats then return false end
    if not _G.C_DamageMeter then return false end

    local baseline = self:_GetCombatBaseline(run)
    local any = false
    local amounts = {}
    for _, name in ipairs(METRIC_ORDER) do
        local session = getSession(TYPES[name])
        if session then
            local found, localAmount = applyMetric(run, name, session, baseline)
            if found then any = true end
            if localAmount then amounts[name] = localAmount end
        end
    end

    if any then
        local st = run.stats
        st.dmgDataSource  = "C_DamageMeter"
        st.healDataSource = "C_DamageMeter"
        run.dataSource    = "C_DamageMeter"

        -- Alcance real de los numeros: honesto con el usuario. Si no pudimos
        -- capturar/aplicar la linea base, estos totales incluyen combate previo
        -- a la key y hay que decirlo, no presentarlos como si fueran de la run.
        if baseline and baseline.valid then
            -- "key"         -> acotado a la llave desde el principio.
            -- "key-partial" -> hubo un reset de Overall a mitad; los totales
            --                  cubren desde ese momento, no la llave entera.
            if baseline.resetSeen and (baseline.resetAtElapsed or 0) > 30 then
                st.meterScope = "key-partial"
                st.meterResetAtElapsed = baseline.resetAtElapsed
            else
                st.meterScope = "key"
                st.meterResetAtElapsed = nil
            end
            local combatSeconds = (baseline.nowDuration or 0) - (baseline.duration or 0)
            if combatSeconds > 0 then
                st.meterCombatSeconds = combatSeconds
                if amounts.damage  then st.dpsOfficial = amounts.damage  / combatSeconds end
                if amounts.healing then st.hpsOfficial = amounts.healing / combatSeconds end
                if amounts.taken   then st.dtpsOfficial = amounts.taken  / combatSeconds end
            else
                -- Sin ventana de combate medible no inventamos un ratio.
                st.meterCombatSeconds = nil
                st.dpsOfficial, st.hpsOfficial, st.dtpsOfficial = nil, nil, nil
            end
        else
            st.meterScope = "overall-unscoped"
            st.meterCombatSeconds = nil
        end

        -- Fields that are intentionally unsupported are left nil, never inferred.
        st.damagePeak10s = nil
        st.damageBoss = nil
        st.damageTrash = nil
        st.healingOverheal = nil
        st.healingPeak = nil
        st.healingGroupTotal = nil
        st.healingSelfTotal = nil
        st.healingCastEfficiency = nil
        st.healingCrisisEvents = nil
        st.healingBrezCount = nil
        st.healingCDUptimeSec = nil
        st.tankDamageMitigated = nil
        st.tankMitigationPct = nil
        st.tankPeakDTPS10s = nil
        st.tankSelfHealTotal = nil
        st.tankAvoidEvents = nil
        st.tankParryEvents = nil
        st.tankDodgeEvents = nil
        st.tankBlockEvents = nil
        st.tankMissEvents = nil
        st.tankDefensiveUptimeSec = nil
        st.tankDefensiveUptimePct = nil
        st.cc = nil
        st.brez = nil
    end
    return any
end

-- Override legacy polling. The old implementation probes removed APIs such as
-- GetPartyData/GetCurrentSessionID and inferred combat data from UNIT_COMBAT.
function MitzuMPlus:PollDamageMeterData(run)
    return self:RefreshSupportedCombatStats(run)
end
function MitzuMPlus:PollDamageMeterDataV2(run)
    return self:RefreshSupportedCombatStats(run)
end
function MitzuMPlus:OnDamageMeterUpdate()
    if self._trackingActive and not (InCombatLockdown and InCombatLockdown()) then
        self:RefreshSupportedCombatStats(_G.MitzuMPlusCurrentRun)
    end
end

-- Do not infer successful interrupts from casting an interrupt button; a cast is
-- not proof that an enemy spell was interrupted. C_DamageMeter is authoritative.
function MitzuMPlus:OnSpellcastSucceeded() end
-- UNIT_COMBAT cannot reconstruct reliable done/healing/mitigation stats in Midnight.
function MitzuMPlus:OnUnitCombat() end
function MitzuMPlus:OnUnitHealth() end

function MitzuMPlus:RegisterMidnightCombatTracking()
    self._trackingActive = true
    if self._meterPollTicker then self._meterPollTicker:Cancel(); self._meterPollTicker=nil end
    if _G.C_DamageMeter and C_Timer and C_Timer.NewTicker then
        self._meterPollTicker = C_Timer.NewTicker(5.0, function()
            if _G.MitzuMPlusCurrentRun and not (InCombatLockdown and InCombatLockdown()) then
                MitzuMPlus:RefreshSupportedCombatStats(_G.MitzuMPlusCurrentRun)
            end
        end)
    end
end

function MitzuMPlus:UnregisterMidnightCombatTracking()
    if self._meterPollTicker then self._meterPollTicker:Cancel(); self._meterPollTicker=nil end
end

-- Replace the combat event frame with the minimum supported event surface.
function MitzuMPlus:_DoSetupCombatFrame()
    if MitzuMPlus._combatFrame then return end
    MitzuMPlus._combatFrame = CreateFrame("Frame")
    MitzuMPlus._combatFrame:SetScript("OnEvent", function(_, event, ...)
        if not MitzuMPlus._trackingActive then return end
        if event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
            pcall(MitzuMPlus.OnDamageMeterUpdate, MitzuMPlus, event, ...)
        end
    end)
    if _G.C_DamageMeter then
        pcall(function() MitzuMPlus._combatFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED") end)
    end
end

MitzuMPlus.SupportedTracking = {
    challengeMode=true, timer=true, enemyForces=true, bosses=true,
    groupComposition=true, deaths=true, deathPenalty=true,
    damage=true, dps=true, healing=true, hps=true, absorbs=true,
    damageTaken=true, avoidableDamage=true, interrupts=true, dispels=true,
    combatLog=false, defensiveUptime=false, mitigation=false, overheal=false,
    battleRez=false, crowdControl=false, peakWindows=false,
}
