# TrackerAdapter (1.1.0)

`MitzuMPlus/modules/Tracker/TrackerAdapter.lua` — la única capa del tracker 1.1
que habla con las APIs de Blizzard.

```
Blizzard API -> TrackerAdapter -> TrackerState (fase 2) -> PaceEngine / PredictionEngine -> HUD
```

## Qué hace y qué no

- Lee, protege (`pcall`, valores secretos) y normaliza. Devuelve `nil` cuando no
  sabe; nunca un `0` inventado.
- No guarda estado entre lecturas, no registra eventos de Blizzard, no predice,
  no pinta. Solo escucha el bus interno (`MITZU_PRE_KEY`, `MITZU_KEY_STARTED`,
  `MITZU_KEY_COMPLETED`) para dejar constancia en el FlightRecorder.
- Sin rutas, pulls, NPCs, placas ni combat log.

## APIs y de dónde sale cada dato

| Dato | Método | API de Blizzard | Fallback |
|---|---|---|---|
| Llave activa | `IsChallengeActive()` | `C_ChallengeMode.IsChallengeModeActive` | `nil` |
| challengeMapID | `GetMapID()` | `C_ChallengeMode.GetActiveChallengeMapID` | `nil` (0 = sin llave) |
| Nivel / afijos | `GetKeystoneLevel()` | `C_ChallengeMode.GetActiveKeystoneInfo` | `nil` (0 = sin llave) |
| Nombre / límite | `GetMapInfo()` / `GetTimeLimit()` | `C_ChallengeMode.GetMapUIInfo` | `nil` (mapa desconocido) |
| Muertes | `GetDeathCount()` | `C_ChallengeMode.GetDeathCount` | `nil` |
| Tiempo | `GetElapsedTime()` | `GetWorldElapsedTimers` + `GetWorldElapsedTime`, tipo `LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE` | `nil`; sin la constante, primer timer marcado `UNTYPED` |
| Escenario | `GetScenarioInfo()` | `C_ScenarioInfo.GetScenarioInfo` | `C_Scenario.GetInfo` (10.º retorno = tipo) |
| Paso / nº criterios | `GetStepInfo()` | `C_ScenarioInfo.GetScenarioStepInfo` | `C_Scenario.GetStepInfo` (3.er retorno) |
| Criterios | `GetCriteria()` | `C_ScenarioInfo.GetCriteriaInfo` | `C_Scenario.GetCriteriaInfo` (multi-retorno) |
| Fuerzas | `GetEnemyForces()` | primer criterio con `isWeightedProgress=true` | ver abajo |
| Bosses | `GetBossProgress()` | criterios con `isWeightedProgress=false` | `UNKNOWN` si falta la marca |

`GetSnapshot()` hace una lectura completa y devuelve todos los campos (cualquiera
puede ser `nil`) más `warnings`.

## Fuerzas enemigas

Formato medido en llaves reales de Retail 12.1.0 (SavedVariables de 1.0.0-beta.1):

```
quantityString = "183%"   recuento crudo, con "%" pegado
totalQuantity  = 729      total crudo
quantity       = 25       porcentaje entero truncado
```

- `COUNT_TOTAL`: `percent = recuento / total * 100` (lo normal).
- `QUANTITY_PERCENT`: si la cadena es ilegible/secreta o el recuento supera el
  total, se usa `quantity` como porcentaje; `current` y `remaining` quedan `nil`.
- `COMPLETED_FLAG`: criterio completado sin cadena ni cantidad legibles → 100%.
- Si `COUNT_TOTAL` y `quantity` difieren más de 3 puntos: `PERCENT_MISMATCH`.
- Solo el primer criterio ponderado cuenta (BUG EF-2 de 1.0).

## Warnings del snapshot

`CHALLENGE_STATE_UNKNOWN`, `ACTIVE_WITHOUT_MAP`, `ACTIVE_WITHOUT_TIMER` (normal
unos segundos tras `/reload`), `ACTIVE_WITHOUT_CRITERIA` (normal al arrancar),
`ACTIVE_WITHOUT_FORCES`, `CRITERIA_PARTIAL`, `MULTIPLE_WEIGHTED_CRITERIA`,
`UNCLASSIFIED_CRITERIA`, `FORCES_PERCENT_MISMATCH`, `FORCES_COUNT_EXCEEDS_TOTAL`.

## Capacidades y diagnóstico

- Resumen: `requiredMissing` (imprescindibles ausentes; `none` = el tracker
  puede funcionar), `optionalMissing` y `legacyFallbacksAbsent` (redes
  `C_Scenario.*` / `LE_` innecesarias porque su API principal existe:
  `OPTIONAL_FALLBACK_MISSING`).
- `ProbeCapabilities()`: `AVAILABLE` / `MISSING` / `UNKNOWN` por función,
  constante y evento (eventos vía `C_EventUtils.IsEventValid`), con el resultado
  de la última llamada real (`OK`, `EMPTY`, `ERROR`).
- `/emp dev tracker` [DEV]: informe copiable con snapshot, criterios crudos,
  paridad contra los módulos 1.0 (`DungeonContext`, `ChallengeClock`,
  `KeystoneTracker`) y capacidades.
- `/emp dev caps` [DEV]: APIs no disponibles en el chat.
- Bug Report: sección `[TRACKER ADAPTER]`.

## Duplicación temporal con 1.0

`ChallengeClock` y `KeystoneTracker` siguen leyendo las mismas APIs porque son
la build estable. Cuando el PTR confirme paridad (`[PARITY vs 1.0]` sin `DIFF`
en una llave real), TrackerState pasará a ser la fuente y esos módulos
delegarán en el adaptador.
