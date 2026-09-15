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
  `SCENARIO_CRITERIA_UPDATE`, `WORLD_STATE_TIMER_START|STOP`. Se validan con
  `C_EventUtils.IsEventValid` y se registran en `pcall`.
- Rafagas de eventos se funden (0,2 s). Resync con ticker de 1 s en `PENDING` y
  5 s en `RUNNING`; sin ticker en `IDLE`/`COMPLETED`. Sin OnUpdate.

## Ciclo de vida
| Estado | Significado |
|---|---|
| `IDLE` | sin llave activa |
| `PENDING` | llave activa sin temporizador del servidor (arranque, hueco tras `/reload`) |
| `RUNNING` | llave activa con temporizador |
| `COMPLETED` | `CHALLENGE_MODE_COMPLETED`; snapshot final congelado hasta `START`/`RESET` o inactiva→activa |

Una llave nueva empieza desde `IDLE`, tras `COMPLETED` o si cambia el `mapID`.
`RESET` o pasar a inactiva sin completar → `IDLE` (`RUN_ENDED`).

## Snapshot (`GetSnapshot()`, solo lectura por contrato)
`status, active, mapID, mapName, keystoneLevel, timeLimit, deaths, deathTimeLost,
forcesCurrent, forcesTotal, forcesPercent, forcesRemaining, forcesRemainingPercent,
forcesSource, bossesCompleted, bossesTotal, bosses[{index,name,completed}],
elapsedBase, elapsedAt, timerSource, timerStale, forcesStale, bossesStale,
recovered, firstSeenAt, completedAt, finalElapsed, warnings, runWarnings,
revision, timestamp, reason` y reservados `pace, prediction, eta, confidence`
(nil hasta las fases 5-6).

- `GetElapsed()`: base del servidor + `GetTime()` transcurrido; congelado en
  `COMPLETED`. `GetTimeRemaining()` puede ser negativo.
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
contenido; el reloj que avanza no cuenta), `MITZU_TRACKER_RUN_COMPLETED`,
`MITZU_TRACKER_RUN_ENDED`.

## Diagnóstico
`/emp dev state` [DEV] y sección `[TRACKER STATE]` del Bug Report. FlightRecorder:
`STATE_RUN_STARTED`, `STATE_STATUS`, `STATE_RUN_RECOVERED`, `STATE_WARN`, `STATE_SYNC`,
`STATE_RUN_COMPLETED`, `STATE_RUN_ENDED`, `STATE_ADAPTER_ERROR`.
