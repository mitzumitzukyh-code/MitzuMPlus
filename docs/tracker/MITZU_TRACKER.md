# Mitzu Tracker (1.1.0-dev.7)

- **dev.6**: prototipo visual independiente (ventana flotante durante la llave).
- **dev.7**: arquitectura de **Blizzard Objective Tracker enhancement**. Durante
  una Mítica+ real no hay ventana de Mitzu: sus datos se integran en el bloque
  M+ nativo. La ventana flotante queda solo para vista previa y resumen.

## Capas

```
Blizzard APIs
   -> TrackerAdapter          (única capa que lee APIs M+)
   -> TrackerState            (fuente de verdad)
   -> MitzuTracker            (controlador: State + PredictionEngine + RUN_COMPLETED)
   -> TrackerPresenter        (función pura: modelo visual + modelo integrado)
        -> BlizzardTrackerEnhancer   llave real: PENDING / RUNNING / COMPLETING
        -> TrackerView               PREVIEW y SUMMARY (ventana flotante)
```

`MT.RENDER_ROUTE` decide el destino; `run_static_checks.py` exige que
PENDING/RUNNING/COMPLETING vayan a `EMBEDDED` y que solo PREVIEW/SUMMARY usen
la ventana flotante. Nunca hay dos renderizadores activos a la vez.

## Objective Tracker de Blizzard en 12.1.0

Fuente: `Gethe/wow-ui-source`, rama `live`, commit `12.1.0 (69814)`
(2026-09-12), `Interface/AddOns/Blizzard_ObjectiveTracker`.

| Pieza | Hallazgo |
|---|---|
| `ObjectiveTrackerFrame` | contenedor (Edit Mode); aloja los módulos |
| `ScenarioObjectiveTracker` | módulo de escenario (`ScenarioObjectiveTrackerMixin` sobre `ObjectiveTrackerModuleMixin`). `Update` = `BeginLayout` → `LayoutContents` → `EndLayout` en cada `MarkDirty` (`SCENARIO_CRITERIA_UPDATE`, `SCENARIO_UPDATE`, ...) |
| `.ChallengeModeBlock` | **bloque M+**. Frame fijo de XML (`parentArray="FixedBlocks"`), 251×87, `height` fijo. No se recicla: `LayoutContents` lo añade solo si `IsActive()` y `FreeUnusedBlocks` lo oculta si no |
| `:Activate(timerID, elapsed, limit)` | lo llama `ScenarioTimerFrame:CheckTimers` (`PLAYER_ENTERING_WORLD`, `CHALLENGE_MODE_START`, `WORLD_STATE_TIMER_START`) con `Enum.WorldElapsedTimerTypes.ChallengeMode` |
| `:UpdateTime(elapsed)` | **cada frame** desde `ScenarioTimerFrame:OnUpdate`; escribe `TimeLeft` (tiempo restante) y `StatusBar` |
| `StopTimer` | `timerID=nil` + `MarkDirty` → el bloque se oculta en el siguiente layout (final de llave, reset) |
| Regiones | `Level` (TOPLEFT 28,-18), `TimeLeft` (bajo `Level`, `GameFontHighlightHuge`), `DeathCount` (TOPLEFT en BOTTOMRIGHT -47,43; icono + `Count`; tiempo perdido solo en tooltip), `StatusBar` (207×13, abajo), `TimesUpLootStatus` (a la derecha de `TimeLeft` al agotarse), afijos arriba a la derecha |
| Fuerzas | línea del `ObjectivesBlock` + barra de **pool** (`usedProgressBars[line]`, `ScenarioProgressBarTemplate` 192×38, `Bar` 191×17, `Bar.Label` = `%d%%`). Solo existe mientras `isWeightedProgress and not completed`: al 100 % se libera |
| Jefes | líneas de `ObjectivesBlock` con check/nub |

## Enganche

- **Descubrimiento**: `ScenarioObjectiveTracker.ChallengeModeBlock` (dos lecturas
  de tabla) en cada render; sin búsquedas por la UI ni `OnUpdate`.
- **Hooks** (solo `hooksecurefunc(tabla, "Método", fn)`, una vez por instancia):
  `ChallengeModeBlock.Activate` (el timer arranca tarde o tras `/reload`) y
  `ScenarioObjectiveTracker.EndLayout` (Blizzard reconstruyó el módulo: barras
  liberadas, bloque mostrado/oculto). Cada callback en `pcall`.
- **Elementos propios** (`BlizzardTrackerEnhancer.elements`): `root` y
  `forcesRoot` son frames de Mitzu **hijos del bloque M+** → siguen su
  visibilidad, escala y posición de Edit Mode. FontStrings `upgrade`, `pace`,
  `penalty`, `forces` y un medidor oculto. Se crean una vez y se reutilizan.
- **Attach**: primer bloque encontrado (`CHALLENGE_BLOCK_FOUND`, generación 1).
  **Reattach**: otro objeto de bloque (`CHALLENGE_BLOCK_REBUILT`, generación +1,
  mismos elementos con `SetParent`). **Detach**: sin tracker/bloque → ocultar,
  `ClearAllPoints`, `SetParent(nil)`, soltar referencias.
- **Refresco**: ticker de 1 s de MitzuTracker durante la llave,
  `MITZU_TRACKER_STATE_CHANGED` y el hook de `EndLayout`. Textos, anclas y
  visibilidad cacheados.
- **Kill switch**: 3 errores de render → enhancer desactivado, lo suyo oculto,
  Blizzard intacto.

### Por qué no introduce taint

- No se reemplaza ninguna función de Blizzard; `hooksecurefunc` añade un
  post-hook que no altera la seguridad del original.
- Sobre frames de Blizzard solo lecturas (`Get*`, `Is*`, campos). Ni
  `SetPoint`/`SetText`/`Show`/`Hide`, ni `SetScript`/`HookScript`, ni escrituras
  de campos (`height`, `timeLimit`...), ni `MarkDirty`/`SetHeightModifier`, ni
  `ObjectiveTrackerFrame`. Lo verifican `run_static_checks.py` (referencias
  `blizz*` solo con `Get`/`Is`) y los tests (el mock registra cualquier llamada
  mutadora externa sobre sus frames: siempre 0).
- `Bar.Label` no se toca (además lo usa Angry Keystones).
- `SetParent` solo sobre `el.root` / `el.forcesRoot` (frames de Mitzu).

## Qué se añade (y qué no)

| Blizzard (se conserva) | Mitzu añade |
|---|---|
| Nombre, nivel, afijos | — |
| Temporizador `TimeLeft` | a su derecha: tiempos de mejora `+3 6:25  +2 13:01  +1 19:37` (los que quepan, del más cercano) y debajo `RITMO +2  50%` |
| Barra de fuerzas `73%` | debajo: `449 / 608 · 73.85% · faltan 159` (el `%` solo sin Angry Keystones; se acorta a lo que quepa); nada al 100 % |
| Contador de muertes | a su izquierda: `-0:15` si Blizzard publica tiempo perdido |
| Lista de jefes | — |

Adaptativo y determinista: el Presenter da candidatos de más completo a más
corto (`UpgradeCandidates`, `BuildEmbedded`) y `TrackerPresenter.FitText` elige
el primero que cabe. Ancho disponible en la fila del temporizador =
`anchoBloque − 47 − 4 − penalización − (28 + anchoTimeLeft + 8 [+24 fuera de tiempo])`.
Umbrales del reloj ≠ ritmo del motor: pueden decir `+3 …` y `RITMO +2` a la vez.

## Estados

| Estado | Render |
|---|---|
| IDLE / OUTSIDE | nada |
| PENDING | integrado: solo línea de fuerzas si hay criterios; sin tiempos ni ritmo |
| RUNNING | integrado completo |
| COMPLETING | integrado, último estado válido, reloj congelado |
| SUMMARY | **ventana flotante** 20 s. Decisión: Blizzard retira el bloque M+ en cuanto para el timer (`StopTimer`), así que no hay dónde integrarlo |
| PREVIEW | ventana flotante (datos sintéticos); rechazada con llave en curso |

Sin bloque de Blizzard: **no** hay fallback flotante. `attached=false`,
`attachReason=BLIZZARD_TRACKER_NOT_LOADED|CHALLENGE_BLOCK_NOT_FOUND`,
FlightRecorder `EMBED_UNAVAILABLE`; el tracker nativo sigue normal. Si el
bloque aparece después, se engancha en el siguiente tick (≤1 s) o en `Activate`.

`/reload`: estado nuevo; en el primer render con llave se descubre el bloque,
se instalan los hooks sobre la instancia actual y `Activate` muestra las líneas.

## Ajustes (`profile.settings.hud`, sin migración)

Integrado: `enabled`, `showPrediction`, `showConfidence`, `showUpgradeTimes`,
`showForcesCount`, `showForcesRemaining`, `showDeaths`; `scale` acotada 0.8–1.25
y `alpha` solo sobre los elementos de Mitzu. Ventana (preview/resumen):
`locked`, `scale`, `alpha`, `point/relPoint/x/y`, `showETA`. La posición en la
llave es la del Objective Tracker.

## Diagnóstico

Bug Report `[TRACKER VISUAL]`: `implementation=BLIZZARD_TRACKER_ENHANCER`,
`renderMode=EMBEDDED|PREVIEW_FLOATING|NONE`, `trackerVisible`,
`floatingVisible`, `embeddedVisible`, `predictionDisplayed`,
`confidenceDisplayed`, `upgradeTimesDisplayed`, `forcesCountDisplayed`,
`forcesRemainingDisplayed`, `deathsDisplayed`, `blizzardTrackerLoaded`,
`challengeBlockFound`, `challengeBlockShown`, `challengeBlockActive`, `attached`,
`attachGeneration`, `attachReason`, `attachmentHealthy`, `hooksInstalled`,
`forcesBarFound`, `forcesBarReason`, `availableWidth`, `lastLayoutReason`,
`enhancerErrors`, `enhancerDisabled`, `lastRenderError`. Sin referencias a frames.
Invariante `NO_FLOATING_HUD_DURING_KEY`.

## Pendiente de validar en Retail

Anchos reales de fuente (el mock usa 6 px/carácter), solape con afijos largos y
con Angry Keystones activo, línea de fuerzas bajo la barra, `tainted=none` tras
`/reload` (`/emp dev blizzard`).
