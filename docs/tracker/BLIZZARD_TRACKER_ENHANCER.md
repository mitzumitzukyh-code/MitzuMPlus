# BlizzardTrackerEnhancer — auditoría y diseño (1.1.0)

**Principio: ENHANCE, DON'T REPLACE.** MitzuMPlus 1.1 no crea HUD propio, no
oculta ni reemplaza el Objective Tracker y no duplica el timer. Decora el bloque
Mythic+ nativo de Blizzard.

```
Blizzard APIs -> TrackerAdapter -> TrackerState -> PaceEngine / PredictionEngine
              -> BlizzardTrackerEnhancer -> Objective Tracker NATIVO
```

## 1. Auditoría estática (código fuente de la UI)

Fuente: volcado público de la UI de Blizzard (`Gethe/wow-ui-source`).

| Cliente | Rama | Build |
|---|---|---|
| PTR | `ptr2` | 12.1.5.69594 (= build instalado en `_xptr_`) |
| Retail | `live` | 12.1.0.69814 (= build de Retail) |

`Interface/AddOns/Blizzard_ObjectiveTracker` es **idéntico byte a byte** en
ambos builds. Un mismo enhancer sirve para Retail y PTR.

- `Blizzard_ObjectiveTracker.toc` no es LoadOnDemand: carga con la UI.
- `ScenarioObjectiveTracker` (frame global, `ScenarioObjectiveTrackerMixin`,
  hereda `ObjectiveTrackerModuleMixin`).
  - `:LayoutContents()` reconstruye el módulo en cada `MarkDirty`
    (`SCENARIO_CRITERIA_UPDATE`, `SCENARIO_UPDATE`, ...). En Challenge Mode hace
    `LayoutBlock(ChallengeModeBlock)` y `UpdateCriteria(numCriteria)`.
  - `:UpdateCriteria(n)` añade una línea por criterio con
    `C_ScenarioInfo.GetCriteriaInfo`; si `isWeightedProgress` y no completado,
    `ObjectivesBlock:AddProgressBar`.
  - `.usedProgressBars[line]` → `ScenarioProgressBarTemplate`
    (`ScenarioTrackerProgressBarMixin`). `OnGet` pone
    `percentage = criteriaInfo.quantity` y `SetValue` escribe
    `Bar.Label = PERCENTAGE_STRING` → **porcentaje entero truncado**.
- `ScenarioObjectiveTracker.ChallengeModeBlock`
  (`ScenarioObjectiveTrackerChallengeModeMixin`, 251×87, `height` fijo):
  - `:Activate(timerID, elapsedTime, timeLimit)`: nivel, afijos, muertes,
    `StatusBar:SetMinMaxValues(0, timeLimit)`, arranca `ScenarioTimerFrame`.
  - `:UpdateTime(elapsedTime)`: llamado **cada frame** desde
    `ScenarioTimerFrame:OnUpdate` con `floor(elapsed)`; pinta `TimeLeft` y la barra.
  - `:UpdateDeathCount()` en `CHALLENGE_MODE_DEATH_COUNT_UPDATED`.
  - Regiones: `Level`, `TimeLeft`, `StatusBar`, `DeathCount`, `TimerBG`,
    `StartedDepleted`, `TimesUpLootStatus`; campos `timerID`, `timeLimit`,
    `deathCount`, `timeLost`.
- `ScenarioTimerFrame` (`ScenarioTimerMixin`): `CheckTimers` filtra con
  `Enum.WorldElapsedTimerTypes.ChallengeMode` (= 1). La constante
  `LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE` no aparece en la UI → el
  TrackerAdapter ahora usa el Enum primero.

API documentada en `Blizzard_APIDocumentationGenerated` (12.1.5):
`C_ScenarioInfo.GetCriteriaInfo` / `GetScenarioStepInfo` / `GetScenarioInfo`,
`C_ChallengeMode.IsChallengeModeActive` / `GetActiveChallengeMapID` /
`GetActiveKeystoneInfo` / `GetMapUIInfo` / `GetDeathCount`, eventos
`CHALLENGE_MODE_START|COMPLETED|RESET|DEATH_COUNT_UPDATED`,
`SCENARIO_CRITERIA_UPDATE`, `WORLD_STATE_TIMER_START|STOP`. Ningún campo de
`ScenarioCriteriaInfo` está marcado como secreto. `C_Scenario.GetInfo` /
`GetStepInfo` (heredadas) no están documentadas pero el propio tracker las usa.

## 2. Confirmación en el cliente real (pendiente)

`modules/Tracker/BlizzardTrackerProbe.lua` es **solo lectura**: comprueba que
esos frames/métodos/regiones existen, lee el estado visible y guarda una línea
base de taint (`issecurevariable`) antes de que exista ningún hook.
`/emp dev blizzard` [DEV] y sección `[BLIZZARD TRACKER]` del Bug Report.

## 2b. Coexistencia con Angry Keystones (hallazgo 2026-09-15)

La prueba de Retail mostró `Bar.Label = "23.68%"` con `percentage = 23`.
Blizzard escribe `%d%%` (`23%`); ese texto lo pone **Angry Keystones**
(instalado y activo en ese cliente). Su código hace exactamente los enganches
previstos aquí:

- `hooksecurefunc(ScenarioObjectiveTracker.ChallengeModeBlock, "UpdateTime" | "Activate")`
- `hooksecurefunc(ScenarioObjectiveTracker.ObjectivesBlock, "AddProgressBar")` y
  `hooksecurefunc(bar, "SetValue")` → `Bar.Label:SetFormattedText("%.2f%%", ...)`
- `hooksecurefunc(ScenarioObjectiveTracker, "UpdateCriteria")` (splits)

Consecuencias para el diseño:
- El texto de la barra **no** es fuente de datos (ya era regla) y la sonda no
  puede asumir que el texto visible es el nativo.
- Dos addons escribiendo `Bar.Label` = el último hook gana y el texto parpadea
  según el orden. El enhancer debe **detectar** AK (`C_AddOns.IsAddOnLoaded`) y
  no escribir sobre regiones que AK ya controla (por defecto: ceder la barra y
  el bloque de umbrales a AK y limitarse a lo que AK no muestra), con opción
  explícita del usuario.
- Probar siempre en dos configuraciones: con y sin Angry Keystones.

## 3. Diseño propuesto del enhancer (no implementado)

### Puntos de enganche (solo `hooksecurefunc`, post-hook)
| Hook | Frecuencia | Uso |
|---|---|---|
| `ChallengeModeBlock:Activate` | inicio de llave / reload | crear (una vez) las regiones propias, recalcular umbrales |
| `ChallengeModeBlock:UpdateTime` | cada frame | actuar **solo** cuando cambia el segundo entero; texto de umbrales/margen |
| `ScenarioObjectiveTracker:LayoutContents` | cada rebuild | re-aplicar la decoración de la barra de fuerzas |
| instancia de barra `:SetValue` | por barra, hook una vez (`bar.__mitzuHooked`) | porcentaje preciso tras cada `SetValue` de Blizzard |

### Qué decorar, por orden de riesgo
1. **Barra de fuerzas**: `Bar.Label` → `50.00%` (o `343/686 · 50.00%`) y
   restantes. Sin cambiar alturas.
2. **Bloque M+**: FontStrings **propias** hijas del bloque, ancladas a
   `TimeLeft`: `+3 4:12  +2 10:12`; marcas de +3/+2 sobre `StatusBar`
   (texturas propias al 60 % / 80 %). Sin tocar `height` ni el layout.
3. **Predicción / ETA / pace / confianza**: tooltip del bloque
   (`HookScript("OnEnter")`) o una línea propia dentro de los 87 px si cabe.
   Añadir líneas al `ObjectivesBlock` (`AddObjective`) queda **descartado**
   hasta demostrar en el PTR que no propaga taint al contenedor.

### Reglas
- Nunca reemplazar funciones de Blizzard ni escribir `height`, `usedLines`,
  `timeLimit` u otros campos que su layout lee.
- Toda región propia se crea una vez, se reutiliza y se oculta al salir.
- Cada callback en `pcall`; si falla N veces, el enhancer se desactiva solo y el
  tracker de Blizzard sigue intacto (sus hooks quedan como no-op).
- Guardas: el enhancer solo arranca si `BlizzardTrackerProbe:IsEnhanceable()`.
  Si no, no toca el tracker de Blizzard, registra el fallo (FlightRecorder y
  Bug Report) y, si corresponde, activa el fallback al `KeyPredictionHUD` legacy
  (congelado en 1.0; ver ROADMAP.md).
- Datos solo desde TrackerState/Pace/Prediction, nunca desde el texto de Blizzard.
- Criterio de aceptación en PTR: `/emp dev blizzard` con `tainted=none` durante
  y después de una llave completa, sin `ADDON_ACTION_BLOCKED` en combate.
