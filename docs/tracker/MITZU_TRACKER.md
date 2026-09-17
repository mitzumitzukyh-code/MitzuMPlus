# Mitzu Tracker V1 (1.1.0-dev.6)

Tracker de Mítica+ propio de MitzuMPlus. Sustituye a la ventana provisional de
1.0 (`KeyPredictionHUD`, retirada) y coexiste con el tracker de Blizzard.

## Capas

```
Blizzard APIs
   -> TrackerAdapter        (única capa que lee APIs M+)
   -> TrackerState          (snapshot normalizado, fuente de verdad)
   -> MitzuTracker          (controlador: junta State + PredictionEngine + RUN_COMPLETED)
   -> TrackerPresenter      (función pura: entradas -> modelo visual)
   -> TrackerView           (frames creados una vez; solo pinta el modelo)
```

- `TrackerPresenter.lua`, `TrackerView.lua` y `MitzuTracker.lua` no contienen
  tokens de API M+ (`C_ChallengeMode`, `C_ScenarioInfo`, `C_Scenario`,
  `GetWorldElapsedTime*`, `quantityString`): lo exige `run_static_checks.py`.
- La predicción no se calcula en la UI: el Presenter traduce el bracket de
  `PredictionEngine` con una lista blanca (`+3`, `+2`, `+1`, `FUERA→OVERTIME`,
  resto `NONE`).
- Umbrales +3/+2/+1: los del motor (`plus3Time`, `plus2Time`); sin motor, las
  fracciones de `Constants.KEY_UPGRADE_PLUS3/2_RATIO`. Sin límite, no hay umbrales.

## Datos mostrados

| Zona | Dato | Origen |
|---|---|---|
| Cabecera | nombre de mazmorra (truncado, nunca empuja la placa), `+nivel` | TrackerState `mapName`, `keystoneLevel` |
| Temporizador | tiempo restante (`-m:ss` fuera de tiempo, rojo), `transcurrido / límite` | TrackerState `GetElapsed()`, `timeLimit` |
| Barra de tiempo | progreso del reloj con marcas en +3 y +2 | idem |
| Umbrales | `+3 m:ss`, `+2 m:ss`, `+1 m:ss` restantes; perdidos en gris; el vigente en color | reloj (no la predicción) |
| Ritmo | `RITMO +2` (o `--`), confianza `50%` y `final ~m:ss` si el motor es fiable | PredictionEngine; opciones *Mostrar confianza* / *Mostrar ETA* |
| Fuerzas | `73.85%`, barra, `449 / 608`, `faltan 159` / `completo` | TrackerState |
| Jefes | `Jefes 2/4` + marcas por jefe (solo con total real) | TrackerState |
| Muertes | `Muertes 3` y `+0:15` solo si Blizzard publica el tiempo perdido | TrackerState `deaths`, `deathTimeLost` |

Reloj y ritmo son conceptos distintos y se ven a la vez: los umbrales dicen lo
que el reloj aún permite; `RITMO` dice lo que proyecta el motor.

## Estados

| Modo | Cuándo | Qué se ve |
|---|---|---|
| `HIDDEN` | sin llave, desactivado, o `COMPLETED` tras el resumen | nada |
| `PENDING` | llave activa sin temporizador del servidor | `--:--`, "Esperando temporizador", criterios ya conocidos, sin ritmo |
| `RUNNING` | llave con temporizador | todo |
| `COMPLETING` | ventana de convergencia del final (máx. 3 s) | último estado válido, reloj congelado, sin parpadeo |
| `SUMMARY` | 20 s tras `COMPLETED` | `LLAVE COMPLETADA` / `FUERA DE TIEMPO`, `RESULTADO` oficial (o último ritmo, marcado), tiempo final, fuerzas, jefes (inferido si procede), muertes |
| `PREVIEW` | vista previa | datos sintéticos de Reposo de los Reyes +12 |

Vista previa aislada: no lee TrackerState, PredictionEngine, RunSession ni
historial. Una llave real la apaga.

## Rendimiento

Frames, texturas y FontStrings se crean una vez. La View cachea texto, color,
ancho y visibilidad y solo escribe lo que cambia. Ticker de 1 s solo con llave
visible (el motor de predicción se consulta cada 2 s); en resumen, preview u
oculto no hay ticker. Los cambios de TrackerState llegan por
`MITZU_TRACKER_STATE_CHANGED`. Altura fija: nada salta entre estados.

## Ajustes (sin migración)

`profile.settings.hud`: `enabled`, `locked` (bloqueado = sin ratón), `scale`
(0.6–2.0), `alpha` (0.2–1.0), `showConfidence`, `showETA`, `point/relPoint/x/y`.
Posición/escala/alfa se aplican fuera de combate y nunca desde un refresco.
Comandos: `/emp tracker on|off|preview [off]|lock|unlock|scale N|alpha N|reset|status`.

## Diagnóstico

Bug Report `[TRACKER VISUAL]`: `implementation`, `version`, `enabled`,
`visible`, `mode`, `preview`, `stateRevision`, `renderRevision`,
`predictionDisplayed`, `confidenceDisplayed`, `timerDisplayed`,
`forcesDisplayed`, `bossesDisplayed` (con `(inferred)`), `deathsDisplayed`,
`lastRenderReason`, `lastRenderError`, `ticker`, ajustes y
`blizzardTracker=COEXIST`. FlightRecorder categoría `TRACKER_VISUAL`.

## Pendiente (fuera de V1)

Ocultar solo el bloque M+ de Blizzard sin taint; opción de tiempo transcurrido;
lista de nombres de jefes; toggles por sección.
