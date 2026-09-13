-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · ChallengeClock v1  —  el reloj de la llave, y solo uno
--
-- ═════════════════════════════════════════════════════════════════════════
-- BUG CLK-1 — el Coach contaba desde el /reload
--
-- Visto en vivo, Guarida de Nalorakk +13:
--     reload a los 9:35 (challengeElapsed=575s)
--     Coach mostrando "Tiempo 21:33 / 32:00 · quedan 9:12 · +1"
--     la llave acabó en 34:34, fuera de tiempo por 2:34
-- Y 9:35 + 21:33 = 31:08, que era el tiempo REAL en ese momento. El Coach no
-- iba retrasado: contaba desde cero desde el reload.
--
-- CAUSA: `KeystoneTracker:GetElapsed()` calculaba `now - self._startTime`, y
-- `_startTime` viene de `run.startTime`, que Core fija con `Now()` al crear la
-- run (Core.lua:633). Tras un /reload la run se recrea y ese instante es el
-- del reload, no el del inicio de la llave. Todo lo que cuelga de ahí
-- —proyección, margen, tiempo restante, predicción de subida— heredaba el
-- error sin saberlo.
--
-- ARREGLO: el servidor ya lleva la cuenta y sobrevive al /reload. Es la misma
-- fuente que hizo funcionar RunSession en vivo:
--     GetWorldElapsedTimers()  ->  ids
--     GetWorldElapsedTime(id)  ->  _, elapsedTime, type
--     type == LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE
-- ═════════════════════════════════════════════════════════════════════════
--
-- REGLA: si no se sabe el tiempo, se dice que no se sabe. NUNCA se devuelve 0
-- fingiendo que la llave acaba de empezar — eso es justo lo que produjo un
-- "+1" sobre una llave que ya estaba fuera de tiempo.
--
-- SUAVIDAD: el temporizador del servidor tiene resolución de un segundo. Para
-- que el HUD no vaya a saltos se interpola con GetTime() desde la última
-- lectura, y se recalibra en cada lectura nueva. La precisión la pone el
-- servidor; la fluidez, la interpolación.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local ChallengeClock = {}
MitzuMPlus.ChallengeClock = ChallengeClock

local AVAILABLE, PENDING, UNAVAILABLE = "AVAILABLE", "PENDING", "UNAVAILABLE"
ChallengeClock.STATES = { AVAILABLE = AVAILABLE, PENDING = PENDING, UNAVAILABLE = UNAVAILABLE }

ChallengeClock._lastElapsed = nil   -- último valor del servidor
ChallengeClock._lastAt      = nil   -- GetTime() de esa lectura
ChallengeClock._timerID     = nil
ChallengeClock._state       = UNAVAILABLE

local function ahoraMono() return (GetTime and GetTime()) or 0 end
local function ahoraEpoch() return (time and time()) or 0 end

local function challengeActive()
    local DC = MitzuMPlus.DungeonContext
    if DC then return DC:GetState() == "RUNNING" end
    local api = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
    if type(api) ~= "function" then return false end
    local ok, v = pcall(api)
    return ok and v == true
end

-- Lee el temporizador del servidor. Devuelve segundos e id, o nil.
local function leerServidor()
    if type(GetWorldElapsedTimers) ~= "function"
       or type(GetWorldElapsedTime) ~= "function" then
        return nil
    end
    local tipoCM = rawget(_G, "LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE")
    local ok, timers = pcall(function() return { GetWorldElapsedTimers() } end)
    if not ok or type(timers) ~= "table" then return nil end
    for _, id in ipairs(timers) do
        local okT, _, elapsed, tipo = pcall(GetWorldElapsedTime, id)
        if okT and tonumber(elapsed) then
            if tipoCM == nil or tipo == tipoCM then
                return tonumber(elapsed), id
            end
        end
    end
    return nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- API
-- ─────────────────────────────────────────────────────────────────────────

-- Segundos jugados, o nil si no se saben. nil es una respuesta legítima.
function ChallengeClock:GetElapsed()
    if not challengeActive() then
        self._state = UNAVAILABLE
        self._lastElapsed, self._lastAt = nil, nil
        return nil
    end

    local elapsed, id = leerServidor()
    if elapsed then
        self._lastElapsed, self._lastAt = elapsed, ahoraMono()
        self._timerID = id
        self._state = AVAILABLE
        return elapsed
    end

    -- El temporizador tarda unos segundos en poblarse tras un /reload. Si ya
    -- teníamos una lectura, se interpola desde ella en vez de perderla.
    if self._lastElapsed and self._lastAt then
        self._state = AVAILABLE
        return self._lastElapsed + (ahoraMono() - self._lastAt)
    end

    -- Challenge activa pero sin lectura todavía: no se inventa un cero.
    self._state = PENDING
    return nil
end

function ChallengeClock:GetState()
    self:GetElapsed()
    return self._state
end

function ChallengeClock:IsAvailable()
    return self:GetElapsed() ~= nil
end

-- Instante absoluto en que empezó la llave, o nil.
function ChallengeClock:GetStartedAt()
    local e = self:GetElapsed()
    if not e then return nil end
    return ahoraEpoch() - math.floor(e)
end

-- Límite oficial de la mazmorra, en segundos.
function ChallengeClock:GetTimeLimit()
    local DC = MitzuMPlus.DungeonContext
    local mapID = DC and DC:GetChallengeMapID()
    if not mapID then
        local api = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID
        if type(api) == "function" then
            local ok, id = pcall(api)
            mapID = ok and tonumber(id) or nil
        end
    end
    if not mapID then return nil end
    local api = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo
    if type(api) ~= "function" then return nil end
    local ok, _, _, limit = pcall(api, mapID)
    return ok and tonumber(limit) or nil
end

-- Tiempo que queda. Puede ser NEGATIVO, y eso es información, no un error:
-- es exactamente lo que distingue "vas justo" de "ya se acabó".
function ChallengeClock:GetRemaining(includeDeathPenalty)
    local e = self:GetElapsed()
    local limit = self:GetTimeLimit()
    if not e or not limit then return nil end
    local penalty = 0
    if includeDeathPenalty then
        local KT = MitzuMPlus.KeystoneTracker
        if KT and KT.GetDeathInfo then
            local _, lost = KT:GetDeathInfo()
            penalty = tonumber(lost) or 0
        end
    end
    return limit - e - penalty
end

-- nil si no se sabe. Un "no lo sé" NO puede tratarse como "no, hay tiempo".
function ChallengeClock:IsOvertime()
    local r = self:GetRemaining(false)
    if r == nil then return nil end
    return r <= 0
end

-- ─────────────────────────────────────────────────────────────────────────
-- INFORME
-- ─────────────────────────────────────────────────────────────────────────

local function fmt(s)
    if not s then return "—" end
    local neg = s < 0
    s = math.abs(math.floor(s))
    return string.format("%s%d:%02d", neg and "-" or "", math.floor(s / 60), s % 60)
end
ChallengeClock.Format = fmt

function ChallengeClock:StatusLines()
    local e = self:GetElapsed()
    local limit = self:GetTimeLimit()
    local KT = MitzuMPlus.KeystoneTracker
    local L = {}
    L[#L + 1] = "challengeActive=" .. tostring(challengeActive())
    L[#L + 1] = "timerState=" .. tostring(self._state)
    L[#L + 1] = "timerID=" .. tostring(self._timerID)
    L[#L + 1] = "elapsed=" .. (e and (math.floor(e) .. "s (" .. fmt(e) .. ")") or "nil")
    L[#L + 1] = "timeLimit=" .. (limit and (limit .. "s (" .. fmt(limit) .. ")") or "nil")
    local r = self:GetRemaining(false)
    L[#L + 1] = "remaining=" .. (r and fmt(r) or "nil")
    local rp = self:GetRemaining(true)
    L[#L + 1] = "remainingWithDeaths=" .. (rp and fmt(rp) or "nil")
    L[#L + 1] = "overtime=" .. tostring(self:IsOvertime())
    L[#L + 1] = "startedAt=" .. tostring(self:GetStartedAt())
    L[#L + 1] = "source=WORLD_ELAPSED_TIMER"

    -- La comparación que hace visible el BUG CLK-1 de un vistazo.
    local localStart = KT and KT._startTime or nil
    L[#L + 1] = "localRunStart=" .. tostring(localStart)
    if localStart and localStart > 0 and e then
        local localElapsed
        if localStart > 1000000 then
            localElapsed = ahoraEpoch() - localStart
        else
            localElapsed = ahoraMono() - localStart
        end
        L[#L + 1] = "localElapsed=" .. fmt(localElapsed)
        L[#L + 1] = "driftVsLocal=" .. fmt(e - localElapsed) ..
                    "  |cFF999999(si no es ~0, el reloj local va desincronizado)|r"
    else
        L[#L + 1] = "driftVsLocal=—"
    end
    return L
end

return ChallengeClock
