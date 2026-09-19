# TrackerState (1.1.0, fase 2)

`MitzuMPlus/modules/Tracker/TrackerState.lua` guarda un snapshot normalizado de
la llave. Es la entrada de PaceEngine, PredictionEngine y
BlizzardTrackerEnhancer. En esta fase no tiene consumidores visuales.

```
Blizzard API -> TrackerAdapter -> TrackerState -> Pace/Prediction -> Enhancer
```

## Reglas
- Lee **solo** `TrackerAdapter:GetSnapshot()`. `tests/run_static_checks.py`
  falla si el fichero menciona `C_ChallengeMode`, `C_Scenario*`,
  `GetWorldElapsedTime(s)` o `quantityString` fuera de comentarios.
- Los eventos de Blizzard solo disparan lecturas: `PLAYER_ENTERING_WORLD`,
  `CHALLENGE_MODE_START|COMPLETED|RESET|DEATH_COUNT_UPDATED`,
  `SCENARIO_CRITERIA_UPDATE`, `SCENARIO_UPDATE`, `SCENARIO_COMPLETED`,
  `WORLD_STATE_TIMER_START|STOP`. Se validan con `C_EventUtils.IsEventValid` y
  se registran en `pcall`.
- Rafagas de eventos se funden (0,2 s). Resync con ticker de 1 s en `PENDING` y
  5 s en `RUNNING`; sin ticker en `IDLE`/`COMPLETED`. En `COMPLETING`, un ticker
  propio de 0,25 s que se cancela al congelar. Sin OnUpdate.

## Ciclo de vida
| Estado | Significado |
|---|---|
| `IDLE` | sin llave activa |
| `PENDING` | llave activa sin temporizador del servidor (arranque, hueco tras `/reload`) |
| `RUNNING` | llave activa con temporizador |
| `COMPLETING` | `CHALLENGE_MODE_COMPLETED` visto; tiempo final congelado, criterios en convergencia (máx. 3 s) |
| `COMPLETED` | snapshot final congelado hasta `START`/`RESET`, inactiva→activa u otro `mapID` |

Una llave nueva empieza desde `IDLE`, tras `COMPLETED` o si cambia el `mapID`.
`RESET` o pasar a inactiva sin completar → `IDLE` (`RUN_ENDED`).
`IsActive()` es falso en `COMPLETING`; `IsCompleting()` lo distingue.

## Convergencia del final (1.1.0-dev.5)

Motivo: en Retail (dev.4, Altar de Colmillos +12, 29:43) la llave se completó
pero TrackerState congeló `bosses=2/3` con `forces stale=true bosses stale=true`.
La lectura hecha en el propio evento ya no devolvía criterios, y el último boss
nunca llegó a leerse.

Algoritmo exacto:
1. `CHALLENGE_MODE_COMPLETED` en `RUNNING`/`PENDING`: se toma
   `finalElapsed = GetElapsed()` (servidor interpolado **antes** de leer) y
   `completedAt = time()`; lectura inmediata del adaptador.
2. Se entra en `COMPLETING` partiendo del último snapshot bueno de la llave
   (no de la lectura del evento) y esa lectura se mezcla (intento 1).
3. Mezcla (cada intento): solo mejora.
   - fuerzas: se aceptan si `forcesPercent` no es nil y no baja;
   - bosses: se aceptan si `bossesTotal > 0`, igual al conocido y
     `bossesCompleted` no baja (con la lista por boss);
   - muertes: si no son nil y no bajan; identidad (`mapID`, nivel, límite): solo
     rellena huecos;
   - lecturas nil, cero o que retroceden se ignoran
     (`completionRegressionsIgnored`); un error del adaptador cuenta como
     intento.
4. Convergido = `forcesPercent >= 100` **y** `bossesCompleted == bossesTotal > 0`
   con valores leídos de Blizzard (antes o durante la ventana). Si converge,
   se congela en ese intento.
5. Si no: ticker de `COMPLETION_INTERVAL = 0.25 s`; `SCENARIO_*` y demás eventos
   también disparan intentos. Se congela al converger, al pasar
   `COMPLETION_WINDOW = 3 s` o a los `COMPLETION_MAX_ATTEMPTS = 16` intentos.
   `START`/`RESET` u otra llave en otro mapa cierran la ventana en el acto.
6. Al congelar: `completionConverged`, `completionCriteriaIncomplete = not converged`,
   `completionAttempts`, `completionConvergenceMs`, ticker cancelado,
   `STATE_RUN_COMPLETED` y `MITZU_TRACKER_RUN_COMPLETED` una sola vez.
   `timerStale=false`; `forcesStale`/`bossesStale` son falsos si el valor se
   confirmó en la ventana **o** es terminal (100 %, todos los bosses: ya no
   puede cambiar). Un `2/3` no confirmado queda `bossesStale=true`.
7. `CHALLENGE_MODE_COMPLETED` repetido en `COMPLETING`/`COMPLETED`: ignorado,
   `duplicateCompletions += 1`, `STATE_COMPLETION_DUPLICATE`.

Nunca se escribe `bossesCompleted = bossesTotal` sin leerlo. Un final no
convergido no es un aviso ni un error: puede ser una limitación de tiempos del
cliente tras completar.

## Autoridad del final (1.1.0-dev.6)

Motivo: Retail dev.5 (Reposo de los Reyes 249 +12): evento con `3/4` y 100 %,
primera relectura `active=false forces=nil bosses=nil criteria=nil`; la ventana
terminó con `completionConverged=false completionCriteriaIncomplete=true` en una
llave terminada correctamente.

`CHALLENGE_MODE_COMPLETED` es la autoridad terminal (una Mítica+ solo se
completa con todos sus criterios). La ventana de convergencia sigue igual; al
congelar se añaden, sin tocar lo observado:

| Campo | Significado |
|---|---|
| `completionConverged` | convergencia de API: alguna lectura mostró 100 % y N/N |
| `terminalStateConfirmed` | la llave terminó (hoy siempre `true`: la ventana solo la abre el evento) |
| `completionSource` | `CHALLENGE_MODE_COMPLETED` |
| `criteriaUnavailableAfterCompletion` | ninguna lectura de la ventana trajo fuerzas ni bosses |
| `completionCriteriaIncomplete` | `not (converged or terminal)`; por compatibilidad, ya nunca `true` tras el evento |
| `bossesCompletedObserved` | = `bossesCompleted` (lo leído) |
| `bossesCompletedFinal`, `bossCountSource` | `OBSERVED` si se leyó N/N; `INFERRED_FROM_COMPLETION_EVENT` → `bossesTotal`; `UNAVAILABLE` sin total |
| `forcesPercentFinal`, `forcesCompletionSource` | igual para fuerzas (100 % inferido si no se leyó) |

`STATE_RUN_COMPLETED` anota `terminal`, `source`, `bossSource`,
`criteriaUnavailable`. Un `RESET`/abandono sin evento no es terminal.

El historial 1.0 (`Core:OnChallengeCompleted` + `RunSession`) es independiente
y sigue finalizando una vez; `tests/core/TrackerIntegration.spec.lua` lo
comprueba con el addon completo durante la ventana.

## Snapshot (`GetSnapshot()`, solo lectura por contrato)
`status, active, mapID, mapName, keystoneLevel, timeLimit, deaths, deathTimeLost,
forcesCurrent, forcesTotal, forcesPercent, forcesRemaining, forcesRemainingPercent,
forcesSource, bossesCompleted, bossesTotal, bosses[{index,name,completed}],
elapsedBase, elapsedAt, timerSource, timerStale, forcesStale, bossesStale,
recovered, firstSeenAt, completedAt, finalElapsed, completionConverged,
completionAttempts, completionConvergenceMs, completionCriteriaIncomplete,
completionRegressionsIgnored, completionSource, terminalStateConfirmed,
criteriaUnavailableAfterCompletion, bossesCompletedObserved, bossesCompletedFinal,
bossCountSource, forcesPercentFinal, forcesCompletionSource, warnings, runWarnings,
transient, revision,
timestamp, reason` y reservados `pace, prediction, eta, confidence`
(nil hasta las fases de pace/predicción).

- `GetElapsed()`: base del servidor + `GetTime()` transcurrido; congelado en
  `COMPLETING`/`COMPLETED`. `GetTimeRemaining()` puede ser negativo.
- `GetLiveSnapshot()`: copia con `elapsed` y `timeRemaining` calculados.
- Lectura parcial de la misma llave (timer, fuerzas o bosses a nil): se conserva
  el último valor y se marca `*Stale = true`. Nunca se sustituye por 0.
- `recovered = true` si la primera lectura del temporizador supera 15 s.
- Avisos: `TIMER_REGRESSION`, `FORCES_DECREASED`, `BOSSES_DECREASED`,
  `CHALLENGE_STATE_UNKNOWN` y los del adaptador con prefijo `ADAPTER_`.
  `warnings` = esta lectura; `runWarnings` = todo lo visto en la llave.
- Sincronización normal del cliente: `ACTIVE_WITHOUT_TIMER|CRITERIA|FORCES|MAP`
  del adaptador (arranque de la llave, hueco tras `/reload`) van a `transient`
  durante 10 s y no son avisos. Si se resuelven, FlightRecorder anota
  `STATE_SYNC code=... seconds=...`; si persisten, pasan a `warnings` y
  `runWarnings`.

## Bus interno
`MITZU_TRACKER_RUN_STARTED`, `MITZU_TRACKER_STATE_CHANGED` (solo si cambia el
contenido; el reloj que avanza no cuenta), `MITZU_TRACKER_RUN_COMPLETED` (al
congelar, no al recibir el evento), `MITZU_TRACKER_RUN_ENDED`.

## Diagnóstico
`/emp dev state` [DEV] y sección `[TRACKER STATE]` del Bug Report:
`status`, `finalElapsed`, `completionConverged`, `completionAttempts`,
`completionConvergenceMs`, `completionCriteriaIncomplete`,
`completionRegressionsIgnored`, `completionWindowOpen`, `duplicateCompletions`,
`completionSource`, `terminalStateConfirmed`, `criteriaUnavailableAfterCompletion`,
`bossesCompletedObserved`, `bossesCompletedFinal`, `bossCountSource`,
`forcesPercentFinal`, `forcesCompletionSource`.

FlightRecorder: `STATE_RUN_STARTED`, `STATE_STATUS`, `STATE_RUN_RECOVERED`,
`STATE_WARN`, `STATE_SYNC`, `STATE_COMPLETION_BEGIN`, `STATE_COMPLETION_READ`
(qué expone Blizzard en cada lectura distinta de la ventana: `active`, fuerzas,
bosses, nº de criterios; máx. 8), `STATE_COMPLETION_DUPLICATE`,
`STATE_RUN_COMPLETED` (con `converged`, `attempts`, `ms`), `STATE_RUN_ENDED`,
`STATE_ADAPTER_ERROR`.
