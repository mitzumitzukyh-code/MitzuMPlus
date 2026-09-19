# Mitzu Tracker (1.1.0-dev.11)

- **dev.6**: prototipo visual independiente (ventana flotante durante la llave).
- **dev.7**: arquitectura integrada (**Blizzard Objective Tracker enhancement**).
  Durante una Mítica+ real no hay ventana de Mitzu: sus datos se integran en el
  bloque M+ nativo. Validada en Retail (Guarida de Nalorakk +10).
- **dev.8**: pasada de densidad y jerarquía visual. Menos texto, un solo umbral,
  secundarios en gris, fuerzas en dos columnas. Sin cambios de lógica.
- **dev.9**: pulido final y diagnóstico del render integrado. RITMO legible en
  combate, fuerzas ancladas a la geometría real de la barra y snapshot QA del
  último render `EMBEDDED`. Sin funciones nuevas ni cambios de backend. dev.8
  validado en Retail (Guarida de Nalorakk +4: `attachmentHealthy=true`,
  `tainted=none`, `enhancerErrors=0`, `/reload` con la misma sesión).
- **dev.10**: localización automática. El tracker (y todo el addon) habla el
  idioma del cliente; ni una cadena visible queda escrita en el código. Sin
  cambios de geometría, predicción, umbrales, fuerzas, enganche ni taint.
- **dev.11**: pase de tipografía. Una jerarquía de fuentes nativas en vez de la
  regla plana «todo Small» de dev.9. Sin funciones nuevas, sin cambios de
  cálculo, de localización, de enganche ni de taint.

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
  visibilidad, escala y posición de Edit Mode. FontStrings `threshold`, `pace`,
  `paceExtra`, `penalty`, `forcesPrimary`, `forcesSecondary` y un medidor oculto
  por fuente. Se crean una vez y se reutilizan.
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

## Qué se añade (dev.8)

```
Guarida de Nalorakk            <- Blizzard
  Nivel 10                     <- Blizzard
  20:45  +3 7:57               <- TimeLeft Blizzard + UN umbral (código en color)
         RITMO +1  30%    -0:20 [calavera]4
  [barra de tiempo]            <- Blizzard
  Fuerzas enemigas             <- Blizzard
  [========= 45% =========]    <- barra y % de Blizzard (o de Angry Keystones)
  329 / 729        faltan 400  <- Mitzu (recuento blanco, restantes en gris)
```

| Blizzard (se conserva) | Mitzu añade |
|---|---|
| Nombre, nivel, afijos, jefes | — |
| Temporizador `TimeLeft` | el **próximo umbral** que se puede perder y debajo `RITMO +N` (confianza/ETA en gris) |
| Barra de fuerzas y su % | debajo, en dos columnas: recuento exacto y restantes. Nunca otro % |
| Contador de muertes | a su izquierda: `-0:20` solo con tiempo perdido publicado |

Jerarquía: TimeLeft > umbral (`GameFontHighlight`) > ritmo
(`GameFontHighlightSmall`) > fuerzas > restantes/penalización > confianza/ETA
(`GameFontDisableSmall`). Solo objetos de fuente de Blizzard; el color refuerza
el código (`+3` verde, `+2` dorado, `+1` naranja, `OVERTIME` rojo) pero el texto
siempre está. `run_static_checks.py` congela esa jerarquía: ritmo, fuerzas,
penalización y secundarios tienen que seguir siendo fuentes `*Small`, el
secundario `GameFontDisable*`, y no puede aparecer ninguna fuente `Huge`.

### Jerarquía tipográfica (dev.11)

dev.9 dejó todo el texto de Mitzu en fuentes `Small` para no competir con el
reloj de Blizzard. Funcionó demasiado bien: en combate no se leía. dev.11 lo
sustituye por una escalera explícita, declarada en `E.FONT` y ordenada en
`E.FONT_ORDER`:

| Nivel | Texto | Plantilla nativa | px |
|---|---|---|---|
| 1 | reloj | *(de Blizzard)* `GameFontHighlightHuge` | 20 |
| 2 | umbral `+3 4:12` | `GameFontHighlightLarge` | 16 |
| 3 | ritmo `RITMO +2` | `GameFontHighlight` | 12 |
| 4 | recuento `449 / 551` | `GameFontHighlight` | 12 |
| 5 | restantes `faltan 102` | `GameFontHighlightSmall` | 10 |
| 6 | penalización `-0:10` | `GameFontHighlightSmall` | 10 |
| 7 | confianza `50%` | `GameFontDisableSmall` | 10, atenuada |

Colores: oro `1.00, 0.843, 0.00` para el umbral (un dato, un color), blanco para
el recuento, plata `0.78, 0.78, 0.812` para todo lo secundario. El código del
ritmo conserva su color contextual porque ahí sí informa de un cambio.

Ninguna fuente es propia y no se llama nunca a `SetFont`: solo plantillas de
Blizzard. La escala (`SetScale`) sigue siendo la preferencia del usuario sobre
los frames de Mitzu, nunca una forma de agrandar texto.

Cada texto se mide con **su** fuente. Hasta dev.10 los restantes se medían con la
fuente de la confianza y se pintaban con otra; medir pequeño y pintar grande es
como el texto acaba saliéndose de la barra.

### Idioma (dev.10)

Ningún texto del tracker está escrito en este código. `TP.TEXT` es una tabla con
metatabla: cada nombre (`PACE`, `FORCES`, `REMAINING`, `KEY_COMPLETE`, …) se
resuelve contra `MitzuMPlus.L` (AceLocale) en el momento de leerlo, así que el
mismo binario pinta `PACE +2 / 227 remaining` en un cliente inglés y
`RITMO +2 / faltan 227` en uno español, sin ninguna rama por idioma.

Lo que **no** se traduce, porque es universal: el reloj (`5:18`), el recuento
(`502 / 729`), el porcentaje (`50%`) y los códigos `+3/+2/+1/OVERTIME`.

`LayoutEmbedded` mide el texto **ya traducido** con su fuente real, así que el
ancho no se codifica por idioma: con la barra a 130 px el inglés
(`227 remaining`, 78 px) sacrifica los restantes y el español (`faltan 227`,
60 px) todavía cabe. Es la misma decisión pura, con otra entrada.

### Legibilidad del ritmo (dev.9)

dev.8 dejaba `RITMO +2` demasiado tenue durante el combate: la etiqueta iba en
`a8a8b0` y, además, toda la línea bajaba a `alpha 0.8` cuando el bracket era
provisional. dev.9 sube la etiqueta a `c8c8d2` y quita esa atenuación: la
provisionalidad ya la cuenta la confianza, que es la parte secundaria y va en
gris. No se toca el tamaño y no se añade fondo, borde, recuadro ni brillo.

### Fuerzas ancladas a la barra (dev.9)

`forcesRoot` es una fila propia de 12 px anclada `TOPLEFT/TOPRIGHT` a
`BOTTOMLEFT/BOTTOMRIGHT` de la `StatusBar` de fuerzas de Blizzard, con una sola
separación vertical (`FORCES_GAP_Y`). Dentro, `forcesPrimary` va a `BOTTOMLEFT`
y `forcesSecondary` a `BOTTOMRIGHT` de esa fila con el mismo margen
(`FORCES_INSET`): comparten base y altura, quedan pegadas a los extremos reales
de la barra y no dependen de ninguna coordenada absoluta. La barra de Blizzard
solo se lee (`GetWidth`), nunca se reancla ni se reescribe. `TrackerView` usa la
misma fila para que la vista previa no diverja del render real.

### Umbral único

`TrackerPresenter.GetNextRelevantUpgradeThreshold(model)` recorre los umbrales
del modelo (los del motor `plus3Time/plus2Time`; sin motor,
`Constants.KEY_UPGRADE_PLUS3/2_RATIO`; `+1` = límite) y devuelve el primero no
perdido con su margen: `{ upgrade = "+3", time = 477 }`. En el segundo exacto
del umbral todavía cuenta (`0:00`); después pasa al siguiente. Fuera de tiempo
devuelve `nil` y no se pinta nada (Blizzard ya pone el reloj en rojo). Es el
margen del reloj, no una proyección: el ritmo sigue siendo del motor.

### Layout adaptativo (`TrackerPresenter.LayoutEmbedded`, puro)

Entradas: modelo integrado, `timerWidth`, `forcesWidth`, `deferThreshold` y una
función `measure(texto, tipo)`. Salida con modos:

| Parte | Modos |
|---|---|
| umbral | `NEXT`, `DEFERRED` (Angry Keystones), `OVERTIME`, `DISABLED`, `TOO_NARROW`, `NONE` |
| ritmo | `WIDE` (+confianza +ETA), `STANDARD` (+uno), `COMPACT` (solo ritmo), `TOO_NARROW`, `NONE` |
| fuerzas | `SPLIT`, `PRIMARY`, `PRIMARY_COMPACT` (`329/729`), `SECONDARY`, `TOO_NARROW`, `NONE`/`NO_BAR` |

Orden de sacrificio: ETA → confianza → restantes → recuento → ritmo. Si el
umbral no cabe, el ritmo tampoco se pinta. No se usan abreviaturas (`R +1`,
`-400`): antes se oculta. Los textos se miden con su fuente real (cacheado),
así una traducción más larga se adapta sola.

`timerWidth = anchoBloque − 47 − 4 − penalización − (28 + anchoTimeLeft + 8 [+24 fuera de tiempo]) [− 44 con Angry Keystones]`.

### Angry Keystones

Detección robusta y sin internals: `C_AddOns.IsAddOnLoaded("AngryKeystones")`.
Con AK: el umbral junto al reloj es suyo (`thresholdMode=DEFERRED`), el ritmo se
alinea a la derecha (junto al contador de muertes) para no pisar su texto.
Mitzu nunca escribe un porcentaje, así que no se duplica el de AK ni el de
Blizzard. Tampoco se leen frames, globales, funciones privadas ni
SavedVariables de AK: si AK cambia por dentro, Mitzu no se entera. El Bug
Report lo deja por escrito con `angryKeystonesLoaded` y `thresholdMode`.
Pendiente de confirmar a ojo en Retail con AK activo.

## Snapshot QA del último render integrado (dev.9)

Cuando la llave termina, Blizzard retira el `ChallengeModeBlock`: a partir de
ahí `thresholdDisplayed`, `paceDisplayed`, `forces*Displayed` y `availableWidth`
son `nil`, y un `/emp bugreport` posterior no podía contar nada de lo que se vio
DURANTE la run. No era un fallo visual, era una limitación de observabilidad.

`MitzuTracker._lastEmbedded` guarda una copia **plana** (solo cadenas, números y
booleanos ya calculados) de lo último que Mitzu pintó de verdad dentro del
bloque. Solo diagnóstico:

- **Se actualiza** cuando la ruta es `EMBEDDED`, el render es válido
  (`active`), el enganche está sano (`attachmentHealthy`) y las líneas están
  visibles (`IsEmbeddedVisible`). Se reutiliza la misma tabla y se reescriben
  todos los campos, así que un valor que deja de mostrarse no se queda pegado.
- **No se toca** al ocultarse el tracker, con el resumen flotante, con la vista
  previa, al pasar a `COMPLETED`, al salir de la mazmorra ni cuando el enhancer
  se apaga solo por errores. Una llave nueva la reemplaza en cuanto pinta su
  primer render integrado válido.
- **No es estado de juego**: no escribe `TrackerState`, ni sesiones, ni
  historial, ni SavedVariables; no mide texto extra, no copia tablas de Blizzard
  y no guarda referencias a frames. Desaparece con `/reload`.

`run_static_checks.py` exige que `MT:_CaptureEmbedded` no nombre `TrackerState`,
`RunSession`, `PredictionEngine`, `db.global`, `db.profile` ni las medidas de
texto, que solo acepte renders `EMBEDDED` y que ningún camino ponga el snapshot
a `nil`.

## Estados

| Estado | Render |
|---|---|
| IDLE / OUTSIDE | nada |
| PENDING | integrado: solo línea de fuerzas si hay criterios; sin tiempos ni ritmo |
| RUNNING | integrado completo |
| COMPLETING | integrado, último estado válido, reloj congelado |
| SUMMARY | **ventana flotante** 20 s. Decisión: Blizzard retira el bloque M+ en cuanto para el timer (`StopTimer`), así que no hay dónde integrarlo |
| PREVIEW | ventana flotante estrecha que simula el bloque de Blizzard (251 px) con las mismas decisiones de layout; rechazada con llave en curso |

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
`forcesBarFound`, `forcesBarReason`, `availableWidth`, `thresholdDisplayed`,
`thresholdTimeDisplayed`, `thresholdMode`, `paceDisplayed`, `paceMode`,
`etaDisplayed`, `forcesPrimaryDisplayed`, `forcesSecondaryDisplayed`,
`forcesLayoutMode`, `angryKeystonesLoaded`, `lastLayoutReason`,
`enhancerErrors`, `enhancerDisabled`, `lastRenderError`. Sin referencias a frames.
Invariante `NO_FLOATING_HUD_DURING_KEY`.

Bug Report `[LAST EMBEDDED RENDER]` (dev.9): los mismos datos, pero del último
render integrado de la llave, con el prefijo `lastEmbedded.` para que no se
confundan con el estado ACTUAL. `available`, `age`, `stateRevision`,
`renderRevision`, `thresholdDisplayed`, `thresholdTimeDisplayed`,
`thresholdMode`, `paceDisplayed`, `paceMode`, `prediction`, `provisional`,
`confidenceDisplayed`, `etaDisplayed`, `forcesPrimaryDisplayed`,
`forcesSecondaryDisplayed`, `forcesLayoutMode`, `penaltyDisplayed`,
`availableWidth`, `angryKeystonesLoaded`, `attachGeneration`,
`attachmentHealthy`, `renderReason`. Fuera de la mazmorra el informe dice a la
vez `renderMode=NONE` / `trackerVisible=false` y `lastEmbedded.available=true`.

Bug Report `[LOCALIZATION]` (dev.10): `clientLocale`, `activeLocale`,
`fallbackLocale=enUS`, `englishDefault`, `translatedClient`, `loadedKeys`,
`missingKeys`, `localizationWarnings`. Fuera de un cliente traducido dice
`activeLocale=enUS` y `localizationWarnings=ENGLISH_FALLBACK`, que es la ruta
esperada, no un fallo. `/emp dev locale` imprime lo mismo.

Puerta de mutación: `python tests/run_mutation_tests.py` rompe a propósito cada
promesa visual (borrar el snapshot al ocultar, que el resumen o la vista previa
lo sobrescriban, que la confianza gane al ritmo, anclar las fuerzas al lado
equivocado, pintar `-0:00`, duplicar muertes o porcentaje, repetir el umbral con
AK, escribir sobre la `StatusBar` o el `DeathCount` de Blizzard, meter fondo,
agrandar RITMO) y comprueba que la suite o las comprobaciones estáticas lo
cazan. Los mutantes de dev.6/7/8 se conservan.

## Pendiente de validar en Retail

Anchos reales de fuente (el mock usa 6 px/carácter), solape con afijos largos y
con Angry Keystones activo, línea de fuerzas bajo la barra, `tainted=none` tras
`/reload` (`/emp dev blizzard`).

dev.9 necesita dos pruebas en Retail: una **sin** Angry Keystones (umbral único,
RITMO legible, confianza secundaria, fuerzas alineadas con la barra, un solo
porcentaje, `/reload`, penalización si hay muertes, final de llave) y otra
**con** AK (`angryKeystonesLoaded=true`, `thresholdMode=DEFERRED`, sin umbral
duplicado, sin porcentaje duplicado, sin solapes). En ambas, `/emp bugreport`
después de que expire el resumen tiene que seguir enseñando `lastEmbedded.*`.
