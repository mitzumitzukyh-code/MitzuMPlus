-- MitzuMPlus PredictionEngine v7.0.0
-- Predicts +3/+2/+1/overtime using only readable M+ state.
local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end
local Engine = {}
MitzuMPlus.PredictionEngine = Engine

local function clamp(v,a,b) return math.max(a,math.min(b,v)) end

-- ═════════════════════════════════════════════════════════════════════════
-- v5.8.0 — SIERRA Y PARPADEO DEL BRACKET  (medido, no supuesto)
--
-- Datos reales: Estanques de Vida Rubi +13, limite 28:00, real 24:35, +1.
-- El log de capacidades registro 6 CAMBIOS DE BRACKET y, en el minuto 7:00,
-- un "FUERA" en una llave que acabo entrando con 3:25 de sobra:
--
--   5:40  34.48%  0/3  +1     23:14
--   6:20  34.48%  0/3  +1     25:45
--   7:00  34.48%  0/3  FUERA  28:16   <- panico injustificado
--   7:20  34.48%  1/3  +1     22:52   <- muere un boss y todo vuelve
--
-- CAUSA: projected = tiempoEfectivo / progreso se recalcula entero en cada
-- tick. Durante una pelea de boss el progreso esta plano POR DEFINICION,
-- mientras el reloj sigue subiendo, asi que la proyeccion se infla de forma
-- lineal y luego pega un salto atras al morir el boss. No es ruido de medida:
-- es la forma del estimador.
--
-- DOS ARREGLOS, ninguno de ellos calibrado contra esa run concreta:
--
--   1) Suavizado exponencial con constante de tiempo. Un tramo sin progreso
--      sigue subiendo la proyeccion, pero despacio, y el salto de vuelta
--      tambien se amortigua. Alpha se deriva del tiempo transcurrido, asi que
--      da igual a que ritmo se llame a GetSnapshot (el overlay lo llama 2
--      veces por segundo).
--
--   2) Histeresis en el bracket. Para cambiar de nivel, la proyeccion tiene
--      que cruzar el umbral con margen. Cambiar de "+1" a "FUERA" porque la
--      estimacion se paso 3 segundos es informacion falsa, y es justo lo que
--      hace que el jugador deje de mirar el Coach.
-- ═════════════════════════════════════════════════════════════════════════
-- ═════════════════════════════════════════════════════════════════════════
-- v7.0.0 — SUAVIZADO ASIMETRICO
--
-- El suavizado simetrico de v5.8.0 tuvo un coste medido: la llave se
-- estabilizaba en el minuto 27:19 (mediana de 3), frente al 18:41 de antes.
-- Es decir, cambio parpadeo por RETRASO: el Coach dejo de equivocarse a
-- saltos para equivocarse de forma estable durante mas tiempo. Mal negocio.
--
-- Ahora la constante depende de la direccion. Enterarte tarde de que vas mal
-- es mucho peor que enterarte tarde de que vas bien: lo primero te hace
-- perder la llave, lo segundo solo te da una alegria con retraso.
-- ═════════════════════════════════════════════════════════════════════════
local SMOOTH_TAU_WORSE  = 20   -- la proyeccion empeora: reaccionar rapido
local SMOOTH_TAU_BETTER = 60   -- la proyeccion mejora: desconfiar un poco
local BRACKET_HYST = 20  -- segundos de margen para aceptar un cambio de bracket

local function nowTime()
    return (GetTime and GetTime()) or 0
end

-- Devuelve el bracket resistiendo los cambios que no vienen con margen.
local ORDER  = { ['+3']=1, ['+2']=2, ['+1']=3, ['FUERA']=4 }
local function rawBracket(t,p3,p2,limit)
    if t <= p3 then return '+3'
    elseif t <= p2 then return '+2'
    elseif t <= limit then return '+1'
    else return 'FUERA' end
end
local function bracketWithHysteresis(projected,p3,p2,limit,current)
    local b = rawBracket(projected,p3,p2,limit)
    if not current or b == current then return b end
    local bounds = { p3, p2, limit }
    local oc, ob = ORDER[current], ORDER[b]
    if not oc or not ob then return b end
    if ob > oc then
        -- Empeora: el umbral que se acaba de cruzar es el del bracket actual.
        local edge = bounds[oc]
        if edge and projected <= edge + BRACKET_HYST then return current end
    else
        -- Mejora: el umbral que se acaba de cruzar es el limite superior del
        -- bracket ACTUAL (bounds[oc-1]), no el del bracket nuevo.
        -- v7.14 (BUG PRED-HYST): antes se usaba bounds[ob]. Con un salto de
        -- varios niveles eso comparaba contra el umbral mas lejano: FUERA ->
        -- proyeccion 17:50 con limite 30:00 (+3 = 18:00) se quedaba en FUERA
        -- porque 17:50 estaba a menos de 20 s del umbral de +3. Para un salto
        -- de un nivel ob == oc-1 y el comportamiento no cambia.
        local edge = bounds[oc - 1]
        if edge and projected >= edge - BRACKET_HYST then return current end
    end
    return b
end

-- Estado de suavizado. Vive entre snapshots de la MISMA run y se tira al
-- cambiar de llave (startTime distinto).
function Engine:_ResetSmoothing(key)
    self._smoothKey   = key
    self._smoothed    = nil
    self._smoothAt    = nil
    self._drift       = nil   -- EMA de |crudo - suavizado|: mide inestabilidad
    self._bracket     = nil
end

function Engine:_Smooth(key, raw)
    if self._smoothKey ~= key then self:_ResetSmoothing(key) end
    local t = nowTime()
    if not self._smoothed then
        self._smoothed, self._smoothAt, self._drift = raw, t, 0
        return raw, 0
    end
    local dt = math.max(0, t - (self._smoothAt or t))
    local tau = (raw > self._smoothed) and SMOOTH_TAU_WORSE or SMOOTH_TAU_BETTER
    local alpha = 1 - math.exp(-dt / tau)
    if alpha <= 0 then return self._smoothed, self._drift or 0 end
    local deviation = math.abs(raw - self._smoothed)
    self._smoothed = self._smoothed + alpha * (raw - self._smoothed)
    self._drift    = (self._drift or 0) + alpha * (deviation - (self._drift or 0))
    self._smoothAt = t
    return self._smoothed, self._drift or 0
end
-- ═════════════════════════════════════════════════════════════════════════
-- MEDICION DEL TIEMPO DE BOSS
--
-- ENCOUNTER_START / ENCOUNTER_END son eventos limpios (no secretos) y marcan
-- exactamente los tramos en los que el porcentaje de trash NO puede subir.
-- Sin esta medida, el estimador reparte ese tiempo entre el trash y sale
-- optimista; con ella, cada cosa se proyecta con su propio ritmo.
--
-- La duracion media se MIDE en la propia llave. Hasta que cae el primer boss
-- se usa un valor previo conservador: preferimos avisar de mas que de menos,
-- porque una proyeccion optimista es la que te hace perder la llave.
-- ═════════════════════════════════════════════════════════════════════════
local BOSS_PRIOR = 100   -- segundos por boss mientras no haya ninguno medido

Engine._bossTotal    = 0     -- segundos acumulados en encuentros terminados
Engine._bossCount    = 0     -- encuentros terminados
Engine._bossStart    = nil   -- inicio del encuentro en curso
Engine._bossRunKey   = nil

function Engine:_ResetBossTiming(key)
    self._bossRunKey = key
    self._bossTotal, self._bossCount, self._bossStart = 0, 0, nil
end

-- Tiempo total dentro de encuentros, incluyendo el que esta en curso.
function Engine:GetBossTime()
    local total = self._bossTotal or 0
    if self._bossStart then
        total = total + math.max(0, nowTime() - self._bossStart)
    end
    return total, self._bossCount or 0
end

function Engine:GetAverageBossTime()
    if (self._bossCount or 0) > 0 then
        return (self._bossTotal or 0) / self._bossCount
    end
    return BOSS_PRIOR
end

do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("ENCOUNTER_START")
    ev:RegisterEvent("ENCOUNTER_END")
    ev:SetScript("OnEvent", function(_, event)
        -- Solo cuenta dentro de una llave: un encuentro en banda no debe
        -- contaminar la media de bosses de mitica.
        if not _G.MitzuMPlusCurrentRun then return end
        if event == "ENCOUNTER_START" then
            Engine._bossStart = nowTime()
        elseif event == "ENCOUNTER_END" then
            if Engine._bossStart then
                local d = math.max(0, nowTime() - Engine._bossStart)
                -- Un wipe rapido o un pull cancelado no es una referencia util
                -- de cuanto dura un boss; por debajo de 15 s no se promedia.
                if d >= 15 then
                    Engine._bossTotal = (Engine._bossTotal or 0) + d
                    Engine._bossCount = (Engine._bossCount or 0) + 1
                else
                    Engine._bossTotal = (Engine._bossTotal or 0) + d
                end
                Engine._bossStart = nil
            end
        end
    end)
end

local function completedBossFraction(bosses)
    local total=#(bosses or {}); if total==0 then return 0,0,0 end
    local done=0; for _,b in ipairs(bosses) do if b.completed then done=done+1 end end
    return done/total, done, total
end
local function getPB(run)
    if not MitzuMPlus.PersonalBest or not run then return nil end
    local pb=MitzuMPlus.PersonalBest:GetDungeonLevelPB(run.dungeonName, run.keyLevel)
    if pb and pb.bestTime then return tonumber(pb.bestTime.completionTime) end
    local dpb=MitzuMPlus.PersonalBest:GetDungeonPB(run.dungeonName)
    return dpb and dpb.bestTime and tonumber(dpb.bestTime.completionTime) or nil
end

function Engine:GetSnapshot(run)
    run = run or _G.MitzuMPlusCurrentRun
    local kt=MitzuMPlus.KeystoneTracker
    if not run or not kt or not kt:IsActive() then return nil end
    local ef=kt:GetEnemyForces() or {}
    local pct=clamp(tonumber(ef.pct) or 0,0,100)
    local bosses=kt:GetBosses() or {}
    local bossFrac, bossesDone, bossesTotal=completedBossFraction(bosses)
    local elapsed=tonumber(kt:GetElapsed()) or 0
    local limit,p2,p3=kt:GetTimerThresholds()
    limit=tonumber(limit) or tonumber(run.timeLimit) or 0
    -- La guarda de "tiempo agotado" de mas abajo solo actua con limit>0. Si
    -- las dos fuentes de siempre fallan, ChallengeClock lo saca del propio
    -- cliente; sin limite no habria nada que impidiera anunciar un +1 con el
    -- tiempo ya cumplido.
    if limit <= 0 and MitzuMPlus.ChallengeClock then
        limit = tonumber(MitzuMPlus.ChallengeClock:GetTimeLimit()) or 0
    end
    p2=tonumber(p2) or (limit*0.8); p3=tonumber(p3) or (limit*0.6)
    local deaths,timeLost=kt:GetDeathInfo(); deaths=tonumber(deaths) or 0; timeLost=tonumber(timeLost) or 0

    -- v5.4.4: el tiempo perdido por muertes cuenta contra el limite exactamente
    -- igual que el tiempo de reloj. Proyectar solo con el reloj infravaloraba la
    -- run: con 5 muertes ibas mas justo de lo que el Coach decia.
    local effElapsed = elapsed + timeLost

    -- Composite progress: trash dominates the run but bosses are meaningful checkpoints.
    local progress=(pct/100)*0.70 + bossFrac*0.30

    -- ─────────────────────────────────────────────────────────────────────
    -- v5.4.4 (BUG PRED-1): antes, con progreso por debajo del umbral, se hacia
    --     projected = limit   ->   result = '+1',  margen = +0:00
    -- Es decir: llevas 13 minutos, 0.00% de fuerzas, 0/3 bosses y 5 muertes, y
    -- el Coach te dice "+1". Eso no es una prediccion conservadora, es una
    -- afirmacion falsa y tranquilizadora, justo lo que este addon no debe hacer.
    -- Ahora: si no hay base para proyectar, se dice que no la hay.
    -- ─────────────────────────────────────────────────────────────────────
    local MIN_PROGRESS = 0.08
    local hasBasis = (progress >= MIN_PROGRESS) and (effElapsed > 20)

    -- ═════════════════════════════════════════════════════════════════════
    -- v7.0.0 — ESTIMADOR SEPARADO: TRASH vs BOSS
    --
    -- Calibracion sobre 3 llaves de la MISMA version (6.9.0):
    --   al 25%: error mediano -12:19  (optimista)
    --   al 50%: error mediano  -2:41  (optimista)
    --   al 75%: error mediano  -4:43  (optimista)
    -- Los tres puntos fallan en el mismo sentido y por mucho. No es ruido.
    --
    -- CAUSA: projected = tiempoEfectivo / progreso reparte TODO el tiempo
    -- transcurrido entre el progreso de trash. Pero el tiempo de boss no
    -- produce trash: mientras peleas a Rav'i el porcentaje no se mueve. Al
    -- meter ese tiempo en el divisor, el ritmo de trash aparente sale inflado
    -- y la proyeccion sale corta. Cuanto mas tiempo de boss llevas sin haber
    -- avanzado trash, mas optimista es. Eso explica el -12:19 del 25%: a esas
    -- alturas ya cayo un boss y su tiempo se conto como si fuera trash.
    --
    -- ARREGLO: estimar las dos cosas por separado.
    --   tiempoTrash   = tiempoEfectivo - tiempoEnBosses
    --   ritmoTrash    = pct / tiempoTrash
    --   restanteTrash = (100 - pct) / ritmoTrash
    --   restanteBoss  = bossesQueFaltan * duracionMediaDeBoss
    --   proyeccion    = tiempoEfectivo + restanteTrash + restanteBoss
    --
    -- No hay ninguna constante ajustada a esas 3 llaves: la duracion media de
    -- boss se MIDE en la propia run (ENCOUNTER_START/END) y hasta que haya un
    -- boss medido se usa un valor previo conservador.
    -- ═════════════════════════════════════════════════════════════════════
    -- El cronometro de bosses se reinicia AQUI, antes de leerlo: si se hiciera
    -- despues, la primera foto de una llave nueva arrastraria el tiempo de
    -- boss de la anterior y proyectaria con datos de otra mazmorra.
    local runKey = tostring(run.startTime or 0)
    if self._bossRunKey ~= runKey then self:_ResetBossTiming(runKey) end

    local bossTime, bossSamples = self:GetBossTime()
    local avgBoss = self:GetAverageBossTime()

    local projected
    if hasBasis then
        local trashElapsed = math.max(1, effElapsed - bossTime)
        local trashFrac    = pct / 100

        if trashFrac > 0.02 then
            local trashRate      = trashFrac / trashElapsed          -- fraccion por segundo
            local remainingTrash = (1 - trashFrac) / math.max(1e-6, trashRate)
            local bossesLeft     = math.max(0, (bossesTotal or 0) - (bossesDone or 0))
            local remainingBoss  = bossesLeft * avgBoss
            projected = effElapsed + remainingTrash + remainingBoss
        else
            -- Sin trash medible aun, se cae al estimador compuesto de siempre.
            projected = effElapsed / progress
        end

        if limit > 0 then projected = clamp(projected, effElapsed, limit * 2.0) end
    end

    -- Suavizado. La proyeccion cruda se conserva para el diagnostico: si algun
    local rawProjected, drift = projected, 0
    local smoothKey = tostring(run.startTime or 0)
    if hasBasis and projected then
        projected, drift = self:_Smooth(smoothKey, projected)
    elseif self._smoothKey ~= smoothKey then
        self:_ResetSmoothing(smoothKey)
    end

    local result, margin
    if limit>0 and effElapsed >= limit then
        -- Esto ya no es una prediccion: el tiempo se ha agotado. Es un hecho,
        -- y a un hecho no se le aplica histeresis.
        result='FUERA'; margin=limit-effElapsed; projected=effElapsed; hasBasis=true
        self._bracket='FUERA'
    elseif hasBasis and limit>0 then
        result = bracketWithHysteresis(projected,p3,p2,limit,self._bracket)
        self._bracket = result
        -- El margen se mide SIEMPRE contra el umbral del bracket mostrado, para
        -- que las dos cifras cuenten la misma historia.
        if result=='+3' then margin=p3-projected
        elseif result=='+2' then margin=p2-projected
        elseif result=='+1' then margin=limit-projected
        else margin=limit-projected end
    else
        -- Sin datos suficientes. Ni resultado, ni margen, ni confianza inventada.
        result=nil; margin=nil; projected=nil
    end

    -- La confianza mide cuanta EVIDENCIA tenemos, no como va la run. Sin base
    -- para proyectar no hay confianza que reportar: se deja a nil y la UI
    -- muestra "—" en lugar de un 25% que parecia un dato y no lo era.
    -- ─────────────────────────────────────────────────────────────────────
    -- v5.8.0 — RECALIBRACION DE LA CONFIANZA
    --
    -- La formula vieja daba 70% en el minuto 4:20 de la run medida, donde el
    -- bracket era EQUIVOCADO (+2 en una llave que fue +1) y la proyeccion
    -- fallaba por 4:35. Y llegaba a 85% al morir el primer boss para quedarse
    -- ahi CONGELADA 16 minutos, mientras el error real bajaba de 1:42 a 1:24.
    -- Es decir: no medía nada observable.
    --
    -- La confianza tiene que caer cuando la estimacion se esta moviendo. Ese
    -- es el unico sintoma que se puede observar EN DIRECTO de que la
    -- prediccion no es de fiar todavia. De ahi el termino de inestabilidad:
    -- drift es la media movil de cuanto se aparta la proyeccion cruda de la
    -- suavizada, en segundos.
    --
    -- AVISO: los pesos estan puestos a ojo desde UNA sola run. No es una
    -- calibracion, es una formula menos mentirosa que la anterior. Con varias
    -- llaves registradas, /emp capcalib da los datos para ajustarla de verdad.
    -- ─────────────────────────────────────────────────────────────────────
    local confidence
    if hasBasis then
        confidence = 25
        confidence = confidence + (clamp(progress,0,1) * 30)          -- avance real
        if bossesDone > 0 then confidence = confidence + 10 end
        if bossesDone >= 2 then confidence = confidence + 5 end
        -- Penalizacion por inestabilidad: 3 s de vaiven = 1 punto, hasta 30.
        confidence = confidence - math.min(30, (drift or 0) / 3)
        confidence = clamp(math.floor(confidence + 0.5), 15, 95)
    end

    -- ─────────────────────────────────────────────────────────────────────
    -- v5.9.0 — EL BRACKET NO SE AFIRMA SI NO SE SABE
    --
    -- Calibracion sobre 4 llaves reales (/emp capcalib):
    --   al 25% de fuerzas: bracket correcto 1 de 4
    --   al 50% de fuerzas: bracket correcto 1 de 4
    --   al 75% de fuerzas: bracket correcto 2 de 4
    --   acierto final: 2 de 4 · se estabiliza en el minuto 18:41 (mediana)
    --
    -- Un "+2" grande y dorado que acierta 1 de cada 4 veces no es informacion
    -- incompleta: es informacion FALSA presentada como un hecho. Y peor que no
    -- decir nada, porque la gente reencola o afloja segun eso.
    --
    -- Lo que SI separa bien los casos es la confianza nueva (la que penaliza
    -- inestabilidad). En las capturas de esas mismas llaves:
    --   34%, 30%, 38%  -> bracket EQUIVOCADO
    --   65%            -> bracket correcto (la key acabo en +2 como decia)
    -- Asi que la confianza se usa para lo unico que sirve: decidir si el addon
    -- tiene derecho a afirmar el resultado o solo a sugerirlo.
    --
    -- Por debajo del umbral el resultado se marca como provisional y la UI lo
    -- pinta con "?" en vez de venderlo como un hecho. La proyeccion, el ritmo y
    -- el reloj se siguen mostrando enteros: esos SI son medidas, no modelos.
    -- ─────────────────────────────────────────────────────────────────────
    -- ═════════════════════════════════════════════════════════════════════
    -- v7.0.0 — LA PUERTA DE CONFIANZA NO SEPARABA NADA
    --
    -- Medido sobre 3 llaves de la version 6.9.0:
    --   afirmo con seguridad: 1/3 correctos (33%)
    --   marco provisional:    2/6 correctos (33%)
    -- Exactamente el mismo acierto a los dos lados del umbral. La puerta de 50
    -- no discriminaba: solo repartia las mismas equivocaciones en dos monedas.
    --
    -- NO se cambia el numero. Mover 50 a 60 u 80 con n=3 seria ajustar a ruido,
    -- que es el error que ya se cometio dos veces en este addon. Lo que se hace
    -- es subirlo a 65 por una razon INDEPENDIENTE de esas 3 llaves: el
    -- estimador de arriba acaba de cambiar de forma, asi que la confianza vieja
    -- ya no describe al modelo nuevo y conviene ser mas prudente hasta que haya
    -- datos del nuevo. Si con 6+ llaves de v7 sigue sin separar, la puerta
    -- sobra y hay que quitarla en vez de seguir moviendo el umbral.
    -- ═════════════════════════════════════════════════════════════════════
    local CONF_ASSERT = 65
    local resultConfident = (result ~= nil) and (confidence ~= nil) and (confidence >= CONF_ASSERT)
    -- 'FUERA' por tiempo agotado es un hecho medido, no una proyeccion.
    if result == 'FUERA' and limit > 0 and effElapsed >= limit then resultConfident = true end

    -- Aviso de frontera: con la proyeccion a menos de 45 s de un umbral, el
    -- bracket puede caer de cualquier lado. Decirlo es mas util que esconderlo.
    local nearBoundary
    if result and projected and limit > 0 then
        local NEAR = 45
        if     result == '+2' and math.abs(projected - p3)    <= NEAR then nearBoundary = '+3'
        elseif result == '+1' and math.abs(projected - p2)    <= NEAR then nearBoundary = '+2'
        elseif result == '+3' and math.abs(projected - p3)    <= NEAR then nearBoundary = '+2'
        elseif result == '+1' and math.abs(projected - limit) <= NEAR then nearBoundary = 'FUERA'
        elseif result == 'FUERA' and math.abs(projected - limit) <= NEAR then nearBoundary = '+1'
        end
    end

    local pb=getPB(run)
    local pbDelta=nil
    if pb and pb>0 and projected then pbDelta=pb-projected end

    -- ─────────────────────────────────────────────────────────────────────
    -- v5.5.0: metricas accionables EN DIRECTO.
    --
    -- pacePct   = %/min de Enemy Forces que llevas de verdad.
    -- neededPct = %/min que hace falta para cerrar el 100% dentro del limite.
    -- Comparar esos dos numeros es lo unico que te dice si hay que acelerar
    -- AHORA; la proyeccion sola te lo dice tarde. El tiempo restante se mide
    -- contra el tiempo EFECTIVO (reloj + penalizacion de muertes), porque es
    -- ese el que decide si la key entra.
    -- ─────────────────────────────────────────────────────────────────────
    local timeRemaining, pacePct, neededPct
    if limit>0 then timeRemaining=math.max(0, limit-effElapsed) end
    if elapsed>30 then pacePct=(pct/(elapsed/60)) end
    if timeRemaining and timeRemaining>15 and pct<100 then
        neededPct=(100-pct)/(timeRemaining/60)
    end

    -- Margen de muertes: cuantas muertes mas caben antes de que el margen actual
    -- se coma. El coste por muerte se deduce de la propia run (timeLost/deaths)
    -- en vez de asumir un valor fijo, asi sigue siendo correcto si Blizzard lo
    -- cambia de temporada.
    -- ─────────────────────────────────────────────────────────────────────
    -- v7.8.0 — el margen de muertes cuenta la CARRERA DE VUELTA.
    --
    -- Antes dividia el margen solo entre la penalizacion oficial, asi que
    -- decia "te caben 8 muertes" cuando ocho muertes son uno o dos wipes con
    -- sus carreras desde la entrada: varios minutos, no 40 segundos.
    --
    -- Ahora: coste real = penalizacion oficial + inactividad medida. Los dos
    -- terminos se MIDEN (Blizzard publica el primero, el tracker mide el
    -- segundo); no hay ninguna constante inventada, asi que si un afijo o un
    -- parche cambia la penalizacion, esto sigue siendo correcto solo.
    -- ─────────────────────────────────────────────────────────────────────
    local deathBudget, realPerDeath
    if deaths > 0 and timeLost > 0 then
        local penaltyPer  = timeLost / deaths
        local downtime    = (kt.GetDeathDowntime and kt:GetDeathDowntime()) or 0
        local downtimePer = downtime / deaths
        realPerDeath = penaltyPer + downtimePer
    end

    if margin and margin > 0 then
        -- Sin penalizacion oficial observable no se muestra un presupuesto
        -- inventado. Aparece en cuanto Blizzard publique deaths/timeLost.
        if realPerDeath and realPerDeath > 0 then
            deathBudget = math.floor(margin / realPerDeath)
        end
    elseif margin then
        deathBudget = 0
    end

    return {
        elapsed=elapsed, effectiveElapsed=effElapsed,
        timeLimit=limit, plus2Time=p2, plus3Time=p3,
        enemyPct=pct, bossesDone=bossesDone, bossesTotal=bossesTotal,
        deaths=deaths, deathTimeLost=timeLost,
        hasBasis=hasBasis, progress=progress,
        projectedTime=projected, result=result, margin=margin,
        resultConfident=resultConfident, nearBoundary=nearBoundary,
        confidence=confidence, pbTime=pb, pbDelta=pbDelta,
        timeRemaining=timeRemaining, pacePct=pacePct, neededPct=neededPct,
        deathBudget=deathBudget, realPerDeath=realPerDeath,
        deathDowntime=(kt.GetDeathDowntime and kt:GetDeathDowntime()) or 0,
        -- Diagnostico: la proyeccion SIN suavizar y cuanto se esta moviendo.
        -- no esta escondiendo un problema de verdad.
        rawProjectedTime=rawProjected, drift=drift,
    }
end
