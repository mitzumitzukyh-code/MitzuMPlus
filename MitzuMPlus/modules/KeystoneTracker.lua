-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - KeystoneTracker
-- Real-time tracking of boss encounters, enemy forces, and timer thresholds
-- during active Mythic+ runs (Angry Keystones-style functionality)
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local KeystoneTracker = {}
MitzuMPlus.KeystoneTracker = KeystoneTracker

-- Secret value guard (Midnight 12.0+)
local _issecretvalue = rawget(_G, "issecretvalue")

-- Safe string extraction: handles secret values and non-string types
local function safeStr(v)
    if v == nil then return "" end
    if _issecretvalue and _issecretvalue(v) then return "" end
    local ok, s = pcall(tostring, v)
    return ok and s or ""
end

-- Safe number extraction: handles secret values
local function safeNum(v)
    if v == nil then return 0 end
    if _issecretvalue and _issecretvalue(v) then return 0 end
    return tonumber(v) or 0
end

-- Igual que safeNum pero devuelve nil cuando el valor NO es legible, para poder
-- distinguir "vale 0 de verdad" de "no lo puedo leer". safeNum devuelve 0 en
-- ambos casos y eso no sirve para decidir de que fuente fiarse.
local function readableNum(v)
    if v == nil then return nil end
    if _issecretvalue and _issecretvalue(v) then return nil end
    return tonumber(v)
end

-- ─────────────────────────────────────────────────────────────────────────
-- HELPERS — Normalize C_Scenario API (handles both struct and multi-return)
-- ─────────────────────────────────────────────────────────────────────────

-- Como AngryKeystones: preferimos C_ScenarioInfo.GetCriteriaInfo (struct) y
-- fallback a C_Scenario.GetCriteriaInfo (multi-return legacy).
local function GetStepNumCriteria()
    -- AK usa: select(3, C_Scenario.GetStepInfo())
    if C_Scenario and C_Scenario.GetStepInfo then
        local ok, r1, r2, r3 = pcall(C_Scenario.GetStepInfo)
        if ok then
            if type(r1) == "table" then
                return tonumber(r1.numCriteria) or 0
            end
            return tonumber(r3) or 0
        end
    end
    return 0
end

local function GetCriteriaData(index)
    -- Primera opción (moderna, AngryKeystones): C_ScenarioInfo.GetCriteriaInfo
    if _G.C_ScenarioInfo and _G.C_ScenarioInfo.GetCriteriaInfo then
        local ok, info = pcall(_G.C_ScenarioInfo.GetCriteriaInfo, index)
        if ok and type(info) == "table" then return info end
    end
    -- Fallback legacy: C_Scenario.GetCriteriaInfo (multi-return)
    if C_Scenario and C_Scenario.GetCriteriaInfo then
        local ok, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13 =
            pcall(C_Scenario.GetCriteriaInfo, index)
        if not ok or r1 == nil then return nil end
        if type(r1) == "table" then return r1 end
        return {
            description        = r1,
            criteriaType       = r2,
            completed          = r3,
            quantity           = r4  or 0,
            totalQuantity      = r5  or 0,
            flags              = r6,
            assetID            = r7,
            quantityString     = r8  or "",
            criteriaID         = r9,
            duration           = r10 or 0,
            elapsed            = r11 or 0,
            failed             = r12,
            isWeightedProgress = r13,
        }
    end
    return nil
end

-- Gate por scenario type = CHALLENGE_MODE, como hace AngryKeystones.
local CHALLENGE_MODE_SCENARIO_TYPE = _G.LE_SCENARIO_TYPE_CHALLENGE_MODE or 2
local function IsChallengeModeActive()
    if not C_Scenario or not C_Scenario.GetInfo then return true end
    local ok, scenarioType = pcall(function()
        return select(10, C_Scenario.GetInfo())
    end)
    if not ok or scenarioType == nil then return true end
    return scenarioType == CHALLENGE_MODE_SCENARIO_TYPE
end

-- ─────────────────────────────────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────────────────────────────────

KeystoneTracker._active        = false
KeystoneTracker._bosses        = {}
KeystoneTracker._enemyForces   = { current = 0, total = 0, pct = 0, quantityString = "" }
KeystoneTracker._timeLimit     = 0
KeystoneTracker._plus2Time     = 0
KeystoneTracker._plus3Time     = 0
KeystoneTracker._deathCount    = 0
KeystoneTracker._deathTimeLost = 0

-- ═════════════════════════════════════════════════════════════════════════
-- COSTE REAL DE UNA MUERTE  (v7.8.0)
--
-- La penalizacion oficial (timeLost de C_ChallengeMode) NO es lo que cuesta
-- morir. Es solo lo que el juego resta del reloj. Lo que de verdad se pierde
-- es eso MAS la carrera de vuelta: el grupo entero deja de avanzar mientras
-- corre desde la entrada.
--
-- Ese tiempo ya lo cuenta el reloj —y por tanto la proyeccion— pero NO estaba
-- en el "margen de muertes", que dividia el margen solo entre la penalizacion.
-- Resultado: decia "te caben 8 muertes mas" cuando ocho muertes son uno o dos
-- wipes con sus carreras, varios minutos. Optimista, el mismo defecto que ya
-- tenia la proyeccion.
--
-- Aqui se MIDE, no se asume: se acumula el tiempo que el jugador pasa muerto o
-- en espiritu, muestreado por el ticker de 1 s que ya existe.
--
-- LIMITE HONESTO: mide TU inactividad, no la del grupo. Si mueres tu solo y el
-- resto sigue empujando, el coste real para la llave es menor que tu tiempo
-- muerto. En un wipe, que es el caso caro, ambos coinciden.
-- ═════════════════════════════════════════════════════════════════════════
KeystoneTracker._deadTime      = 0     -- segundos acumulados muerto/en espiritu
KeystoneTracker._deadSince     = nil
KeystoneTracker._startTime     = 0
KeystoneTracker._numCriteria   = 0
KeystoneTracker._dungeonName   = ""
KeystoneTracker._keyLevel      = 0
KeystoneTracker._affixNames    = {}

-- ─────────────────────────────────────────────────────────────────────────
-- START / RESET
-- ─────────────────────────────────────────────────────────────────────────

function KeystoneTracker:Start(run)
    self._active        = true
    self._bosses        = {}
    self._enemyForces   = { current = 0, total = 0, pct = 0, quantityString = "" }
    self._timeLimit     = (run.timeLimit or 0)
    local C = MitzuMPlus.Constants or {}
    self._plus2Time     = math.floor(self._timeLimit * (C.KEY_UPGRADE_PLUS2_RATIO or 0.8))
    self._plus3Time     = math.floor(self._timeLimit * (C.KEY_UPGRADE_PLUS3_RATIO or 0.6))
    self._deathCount    = 0
    self._deathTimeLost = 0
    self._startTime     = run.startTime or 0
    self._numCriteria   = 0
    self._dungeonName   = run.dungeonName or ""
    self._keyLevel      = run.keyLevel or 0

    -- Resolve affix names
    self._affixNames = {}
    if run.affixes and type(run.affixes) == "table" then
        for _, affix in ipairs(run.affixes) do
            if type(affix) == "table" and affix.name then
                table.insert(self._affixNames, affix.name)
            elseif type(affix) == "number" then
                local name = C_ChallengeMode and C_ChallengeMode.GetAffixInfo
                             and C_ChallengeMode.GetAffixInfo(affix)
                table.insert(self._affixNames, name or ("Affix " .. affix))
            end
        end
    end

    -- Initial poll
    self:Update()

    -- v5.4.2 (BUG A5): antes Update() solo se disparaba con
    -- SCENARIO_CRITERIA_UPDATE, es decir, solo cuando subia Enemy Forces. Un
    -- wipe en un boss sin matar trash dejaba las muertes y el tiempo perdido
    -- congelados en el Coach. No usamos CHALLENGE_MODE_DEATH_COUNT_UPDATED
    -- porque no esta verificado en este cliente y un RegisterEvent con un
    -- nombre inexistente aborta el registro de eventos entero.
    self:_StartPolling()
end

function KeystoneTracker:_StartPolling()
    self:_StopPolling()
    if not (C_Timer and C_Timer.NewTicker) then return end
    self._pollTicker = C_Timer.NewTicker(1.0, function()
        if not KeystoneTracker._active then
            KeystoneTracker:_StopPolling()
            return
        end
        KeystoneTracker:Update()
    end)
end

function KeystoneTracker:_StopPolling()
    if self._pollTicker then
        if self._pollTicker.Cancel then self._pollTicker:Cancel() end
        self._pollTicker = nil
    end
end

function KeystoneTracker:Reset()
    self:_StopPolling()
    self._active        = false
    self._bosses        = {}
    self._enemyForces   = { current = 0, total = 0, pct = 0, quantityString = "" }
    self._timeLimit     = 0
    self._plus2Time     = 0
    self._plus3Time     = 0
    self._deathCount    = 0
    self._deathTimeLost = 0
    self._deadTime      = 0
    self._deadSince     = nil
    self._startTime     = 0
    self._numCriteria   = 0
    self._dungeonName   = ""
    self._keyLevel      = 0
    self._affixNames    = {}
    self._efDiagLogged  = nil
    self._efDiagLogged2 = nil
    self._efMismatchWarned = nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- UPDATE — Poll C_Scenario for current state
-- ─────────────────────────────────────────────────────────────────────────

function KeystoneTracker:Update(force)
    if not force and not self._active then return end

    -- Gate como AngryKeystones: sólo procesar si estamos en CHALLENGE_MODE.
    -- En el cierre de la run, el escenario puede ya no reportar CHALLENGE_MODE,
    -- pero igual queremos hacer una última lectura.
    if not force and not IsChallengeModeActive() then return end

    local numCriteria = GetStepNumCriteria()
    if numCriteria == 0 then return end
    self._numCriteria = numCriteria

    local bosses = {}
    -- v5.4.5 (BUG EF-2, CRITICO): antes cada criterio con isWeightedProgress
    -- sobrescribia self._enemyForces, asi que ganaba el ULTIMO. Si el escenario
    -- expone mas de un criterio ponderado (p.ej. uno ya completado, que da
    -- 100%), el porcentaje real quedaba machacado.
    -- Observado en Reposo de los Reyes +11: el Coach mostraba 100.00% mientras
    -- el tracker de Blizzard marcaba 29.44%.
    -- AngryKeystones se queda con el PRIMERO y hace break (ProgressTracker.lua:48).
    local weightedSeen = 0
    for i = 1, numCriteria do
        local info = GetCriteriaData(i)
        if info then
            -- Detección ESTRICTA como AngryKeystones: isWeightedProgress es la
            -- señal canónica. Los fallbacks anteriores (desc match, total>100,
            -- '%' en string) producían falsos positivos con bosses.
            local isEnemyForces = info.isWeightedProgress == true
            if isEnemyForces then
                weightedSeen = weightedSeen + 1
                -- Solo el primero manda. Los siguientes ni se leen ni cuentan
                -- como boss (no son un boss, son otro criterio ponderado).
                if weightedSeen > 1 then isEnemyForces = nil end
            end

            if isEnemyForces then
                -- BUG FIX (SECRET-EF): quantityString y quantity pueden ser
                -- Secret Values en Midnight 12.0+. Usar safeStr/safeNum guards.
                local quantityString = safeStr(info.quantityString)
                local totalQuantity  = safeNum(info.totalQuantity)

                -- ─────────────────────────────────────────────────────────
                -- ENEMY FORCES. Dos intentos fallidos antes de este; el motivo
                -- de los dos era el mismo: suponer en vez de comprobar.
                --
                -- REGLA REAL, para un criterio con isWeightedProgress:
                --   quantityString -> contiene el RECUENTO crudo de tropas
                --   totalQuantity  -> el total crudo de la mazmorra
                --   quantity       -> YA ES EL PORCENTAJE (entero, truncado);
                --                     NO esta en las mismas unidades que
                --                     totalQuantity y dividirlos no significa
                --                     nada.
                --
                -- porcentaje = recuento(quantityString) / totalQuantity * 100
                --
                -- Es literalmente lo que hace AngryKeystones en este mismo
                -- cliente (ProgressTracker.lua:58), y coincide con el cambio que
                -- hizo Carrot Objective Tracker: parsear desde quantityString en
                -- lugar de calcular con quantity/totalQuantity, "que no esta
                -- normalizado a 100 para weighted progress".
                --
                -- COMPROBACION ARITMETICA con datos reales medidos:
                --   Estanques de Vida Rubi: 59/551  = 10.71%  = lo que marcaba
                --       Blizzard. La v5.4.2 pintaba 59.00% (el recuento como
                --       porcentaje) porque bastaba con que hubiera un '%' en la
                --       cadena para tomar el primer numero como pct.
                --   El Valle Enceguecedor: quantity=35 (el porcentaje entero),
                --       totalQuantity=686. La v5.4.7 hacia 35/686 = 5.10% y
                --       Blizzard marcaba 35.57%. Unidades mezcladas.
                -- ─────────────────────────────────────────────────────────
                local currentQuantity, pct, pctSource

                -- %d+ como AngryKeystones: el recuento es entero.
                local okNum, numStr = pcall(string.match, quantityString, "%d+")
                local countFromString = (okNum and numStr) and tonumber(numStr) or nil
                -- quantity ya viene en porcentaje: sirve de red y de contraste.
                local pctFromQuantity = readableNum(info.quantity)

                if countFromString and totalQuantity > 0 then
                    currentQuantity = countFromString
                    pct = (currentQuantity / totalQuantity) * 100
                    pctSource = "count/total"
                elseif pctFromQuantity then
                    -- Sin cadena utilizable. quantity es el porcentaje ya hecho,
                    -- solo que truncado a entero.
                    pct = pctFromQuantity
                    currentQuantity = (totalQuantity > 0) and (pct / 100) * totalQuantity or 0
                    pctSource = "quantity-as-pct"
                else
                    currentQuantity = 0
                    pct = 0
                    pctSource = "unreadable"
                end

                if pct > 100 then pct = 100 end
                if pct < 0 then pct = 0 end
                self._efPctSource = pctSource

                -- CANARIO. quantity es el mismo porcentaje truncado a entero, o
                -- sea que ambos calculos deben ir de la mano. Si se separan mas
                -- de 3 puntos, el formato ha cambiado y lo que se esta pintando
                -- no vale. Se avisa UNA vez por run con los valores en crudo, en
                -- vez de enseñar un numero incorrecto en silencio como ha pasado
                -- dos veces ya.
                if pctFromQuantity and pctSource == "count/total"
                    and math.abs(pct - pctFromQuantity) > 3 then
                    if not self._efMismatchWarned then
                        self._efMismatchWarned = true
                        if MitzuMPlus.Print then
                            MitzuMPlus:Print(string.format(
                                "|cFFFF9922Enemy Forces:|r discrepancia (calculado %.2f%% vs quantity %d%%). "
                                .. "Run /emp forces and send me the output.", pct, pctFromQuantity))
                        end
                        if MitzuMPlus.ErrorLogger and MitzuMPlus.ErrorLogger.LogEvent then
                            MitzuMPlus.ErrorLogger:LogEvent("ENEMY_FORCES_MISMATCH", "Unexpected format", {
                                quantityString = quantityString,
                                quantity = pctFromQuantity,
                                totalQuantity = totalQuantity,
                                computed = pct,
                            })
                        end
                    end
                end

                self._enemyForces.current        = currentQuantity
                self._enemyForces.total          = totalQuantity
                self._enemyForces.quantityString = quantityString
                self._enemyForces.pct            = pct

                -- Diagnostic log: se emite en la PRIMERA lectura con progreso
                -- real, no en el poll inicial de la run (que siempre daba 0 y no
                -- servia para diagnosticar nada).
                -- Se registran DOS lecturas con progreso real: la primera y
                -- otra ya avanzada (>=25%). Con una sola muestra baja, recuento
                -- y porcentaje pueden parecerse; separadas se distinguen sin
                -- ambiguedad.
                local slot
                if not self._efDiagLogged and pct > 0 then
                    slot = "ENEMY_FORCES"; self._efDiagLogged = true
                elseif not self._efDiagLogged2 and pct >= 25 then
                    slot = "ENEMY_FORCES_MID"; self._efDiagLogged2 = true
                end
                if slot and MitzuMPlus.ErrorLogger and MitzuMPlus.ErrorLogger.LogEvent then
                    MitzuMPlus.ErrorLogger:LogEvent(slot, "Parsing enemy forces", {
                        quantityString = quantityString,
                        -- CAMPO DISCRIMINANTE: si `quantity` va parejo al pct
                        -- calculado, es el porcentaje; si va parejo a `current`,
                        -- es el recuento. Sin el no se puede cerrar la duda.
                        quantityRaw = pctFromQuantity,
                        pctSource = pctSource,
                        weightedCriteria = weightedSeen,
                        numCriteria = numCriteria,
                        current = currentQuantity,
                        total = totalQuantity,
                        pct = self._enemyForces.pct,
                        elapsed = self:GetElapsed(),
                        qtyIsSecret = (_issecretvalue and _issecretvalue(info.quantity)) and true or false,
                        qsIsSecret  = (_issecretvalue and _issecretvalue(info.quantityString)) and true or false,
                    })
                end
            elseif isEnemyForces == false then
                -- Boss encounter criteria
                local elapsed = safeNum(info.elapsed)
                local duration = safeNum(info.duration)
                table.insert(bosses, {
                    name      = info.description or ("Boss " .. i),
                    completed = info.completed or false,
                    elapsed   = elapsed,
                    duration  = duration,
                })
            end
        end
    end
    self._bosses = bosses
    self._weightedCriteria = weightedSeen

    -- NO USAR C_ScenarioInfo.GetUnitCriteriaProgressValues AQUI.
    -- v5.4.2 (BUG CRITICO EF-1): esa API devuelve cuanto APORTA la unidad
    -- consultada al criterio (AngryKeystones la usa con "mouseover" para
    -- mostrar "+3.2%" encima de un mob). NO es el progreso de la run.
    -- Con "player" devolvia 0 y, como la guarda aceptaba cualquier string no
    -- vacia, machacaba el pct correcto que el parseo de isWeightedProgress
    -- acababa de calcular arriba -> enemyForcesFinalPct=0 con total>0.
    -- La unica fuente valida de Enemy Forces es el criterio isWeightedProgress.

    -- Muestreo de inactividad por muerte. Va en Update(), que ya corre cada
    -- segundo, para no añadir otro ticker.
    if UnitIsDeadOrGhost then
        local okDead, dead = pcall(UnitIsDeadOrGhost, "player")
        local now = (GetTime and GetTime()) or 0
        if okDead and dead then
            if not self._deadSince then self._deadSince = now end
        elseif self._deadSince then
            self._deadTime  = (self._deadTime or 0) + math.max(0, now - self._deadSince)
            self._deadSince = nil
        end
    end

    -- Update death count from C_ChallengeMode
    if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
        local ok, numDeaths, timeLost = pcall(C_ChallengeMode.GetDeathCount)
        if ok then
            self._deathCount    = safeNum(numDeaths)
            self._deathTimeLost = safeNum(timeLost)
        end
    end

    -- v5.4.4: con muertes > 0 y tiempo perdido 0 el dato es sospechoso. Blizzard
    -- publica su propio computo en el bloque de Challenge Mode del tracker, que
    -- es lo que lee AngryKeystones. Usarlo NO es fabricar nada: es el numero que
    -- el juego ya te esta enseñando. Lo que sigue prohibido es inventarse
    -- muertes*5 cuando no hay dato en ninguna de las dos fuentes.
    if self._deathCount > 0 and self._deathTimeLost == 0 then
        local ok, lost = pcall(function()
            local block = _G.ScenarioObjectiveTracker and _G.ScenarioObjectiveTracker.ChallengeModeBlock
            return block and block.timeLost
        end)
        if ok then
            local n = safeNum(lost)
            if n > 0 then self._deathTimeLost = n end
        end
    end

end

-- ─────────────────────────────────────────────────────────────────────────
-- GETTERS
-- ─────────────────────────────────────────────────────────────────────────

function KeystoneTracker:IsActive()
    return self._active
end

function KeystoneTracker:GetBosses()
    return self._bosses
end

function KeystoneTracker:GetEnemyForces()
    return self._enemyForces
end

function KeystoneTracker:GetTimerThresholds()
    return self._timeLimit, self._plus2Time, self._plus3Time
end

-- Segundos que el jugador ha pasado muerto o corriendo de vuelta, incluyendo
-- el tramo en curso si esta muerto ahora mismo.
function KeystoneTracker:GetDeathDowntime()
    local total = self._deadTime or 0
    if self._deadSince then
        local now = (GetTime and GetTime()) or 0
        total = total + math.max(0, now - self._deadSince)
    end
    return total
end

function KeystoneTracker:GetDeathInfo()
    return self._deathCount, self._deathTimeLost
end

function KeystoneTracker:GetElapsed()
    -- BUG CLK-1: el reloj local cuenta desde que se creo la run, y tras un
    -- /reload esa run se recrea. El servidor SI mantiene el tiempo real de la
    -- llave, asi que manda el suyo siempre que lo tenga.
    local CC = MitzuMPlus.ChallengeClock
    if CC then
        local e = CC:GetElapsed()
        if e then return e end
    end
    if self._startTime == 0 then return 0 end
    -- Use GetTime() for smoother sub-second updates, fall back to time()
    local now = GetTime and GetTime() or (time and time() or 0)
    -- If startTime was stored as epoch (time()), convert for comparison
    if self._startTime > 1000000 then
        now = time and time() or 0
    end
    return math.max(0, now - self._startTime)
end

function KeystoneTracker:GetDungeonName()
    return self._dungeonName
end

function KeystoneTracker:GetKeyLevel()
    return self._keyLevel
end

function KeystoneTracker:GetAffixNames()
    return self._affixNames
end

-- Snapshot autoritativo de lo que Blizzard expone durante la llave. La UI no
-- debe volver a interpretar criterios ni mezclar aqui datos predictivos.
function KeystoneTracker:GetOfficialSnapshot()
    local limit, plus2, plus3 = self:GetTimerThresholds()
    local deaths, timeLost = self:GetDeathInfo()
    local ef = self:GetEnemyForces() or {}
    local bosses = {}
    for _, boss in ipairs(self:GetBosses() or {}) do
        bosses[#bosses + 1] = {
            name = boss.name,
            completed = boss.completed == true,
            elapsed = tonumber(boss.elapsed) or 0,
            duration = tonumber(boss.duration) or 0,
        }
    end
    local affixes = {}
    for _, name in ipairs(self:GetAffixNames() or {}) do affixes[#affixes + 1] = name end
    return {
        dungeonName = self:GetDungeonName() or "",
        keyLevel = tonumber(self:GetKeyLevel()) or 0,
        elapsed = tonumber(self:GetElapsed()) or 0,
        timeLimit = tonumber(limit) or 0,
        plus2Time = tonumber(plus2) or 0,
        plus3Time = tonumber(plus3) or 0,
        enemyCurrent = tonumber(ef.current) or 0,
        enemyTotal = tonumber(ef.total) or 0,
        enemyPct = tonumber(ef.pct) or 0,
        enemySource = self._efPctSource,
        deaths = tonumber(deaths) or 0,
        deathTimeLost = tonumber(timeLost) or 0,
        bosses = bosses,
        affixes = affixes,
    }
end

-- Volcado de diagnostico de los criterios CRUDOS del escenario.
-- Existe porque adivinar por que un porcentaje sale mal es perder el tiempo:
-- esto ensena exactamente lo que devuelve la API, incluido que campos son
-- Secret Values. Devuelve una lista de lineas listas para imprimir.
function KeystoneTracker:DumpCriteria()
    local out = {}
    local function add(s) out[#out+1] = s end

    local isSecret = function(v)
        return (_issecretvalue and _issecretvalue(v)) and "SECRET" or nil
    end

    local n = GetStepNumCriteria()
    if n == 0 then
        add("|cFFFF9922No active scenario.|r Run /emp forces INSIDE")
        add("a Mythic+, with Blizzard timer on screen.")
        return out
    end
    add(string.format("|cFFd9b33eScenario criteria:|r %d  weighted: %s",
        n, tostring(self._weightedCriteria or "?")))

    for i = 1, n do
        local info = GetCriteriaData(i)
        if not info then
            add(string.format("  [%d] (no data)", i))
        else
            local desc = isSecret(info.description) or tostring(info.description or "?")
            local qs   = isSecret(info.quantityString) or ("'" .. tostring(safeStr(info.quantityString)) .. "'")
            local q    = isSecret(info.quantity) or tostring(info.quantity)
            local tq   = isSecret(info.totalQuantity) or tostring(info.totalQuantity)
            add(string.format("  [%d] weighted=%s completed=%s", i,
                tostring(info.isWeightedProgress), tostring(info.completed)))
            add(string.format("      desc=%s", desc))
            add(string.format("      quantityString=%s  quantity=%s  totalQuantity=%s", qs, q, tq))
        end
    end

    local ef = self._enemyForces or {}
    add(string.format("|cFFd9b33eMitzuMPlus computes:|r pct=%.2f%%  current=%s  total=%s",
        tonumber(ef.pct) or 0, tostring(ef.current), tostring(ef.total)))
    add(string.format("      via=%s  str='%s'",
        tostring(self._efPctSource), tostring(ef.quantityString)))
    add("With progress > 0: if `quantity` looks like the computed pct, quantity is")
    add("the percentage; if it looks like `current`, it is the count.")
    add("Rule: pct = count(quantityString) / totalQuantity * 100.")
    add("`quantity` is already the integer percentage: do NOT divide by totalQuantity.")
    add("Compare that pct with the Enemy Forces bar of the Blizzard tracker.")
    return out
end
