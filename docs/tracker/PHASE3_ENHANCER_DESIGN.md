# Fase 3 — BlizzardTrackerEnhancer: diseño para revisión

Estado: **BORRADOR PARA REVISIÓN. No implementado.** Ningún hook, frame ni
región existe todavía. Base: `BLIZZARD_TRACKER_ENHANCER.md` (auditoría del
Objective Tracker 12.1.0/12.1.5), `TRACKER_STATE.md` (fase 2 / 2.1) y
`ROADMAP.md` (compuertas y política Retail-first).

Precondiciones para empezar a implementar (ROADMAP → Compuertas):
- dev.5 validado en Retail: final de llave con `completionConverged=true`, o
  `completionCriteriaIncomplete=true` explicado; historial una vez; 0 errores.
- Línea base de taint tras `/reload` con llave activa: `tainted=none`.

## 1. Objetivo

Mejorar el bloque Mythic+ **nativo** de Blizzard, al estilo de Angry Keystones
(referencia solo de comportamiento/UX; no se copia código), en vez de volver
al HUD táctico independiente de 1.0.

Contenido objetivo:
| Dato | Fuente |
|---|---|
| Timer mejorado: restante, umbrales +3/+2 con su tiempo restante | TrackerState (`GetElapsed`, `timeLimit`) |
| Fuerzas con porcentaje preciso (`57.23%`) | TrackerState (`forcesPercent`) |
| Fuerzas restantes absolutas (`350 / 817`, `faltan 350`) | TrackerState (`forcesCurrent/Total/Remaining`) |
| Progreso de bosses (`2/3`) | TrackerState (`bossesCompleted/Total`) |
| Muertes y penalización (`9 · -2:15`) | TrackerState (`deaths`, `deathTimeLost`) |
| Predicción Mitzu: `+3 / +2 / +1 / OVERTIME` | PredictionEngine 1.1 sobre TrackerState |
| ETA y margen frente al umbral mostrado | PredictionEngine 1.1 |
| Confianza | PredictionEngine 1.1 (nil = "—", nunca inventada) |

Fuera de alcance (sin excepción): rutas, pulls, flechas, MDT, placas de nombre,
tácticas, splits de otras llaves, HUD flotante nuevo, ocultar/reemplazar el
Objective Tracker, timer duplicado.

## 2. Arquitectura

```
Blizzard API ──► TrackerAdapter ──► TrackerState ──► PaceEngine ──► PredictionEngine
                 (única frontera)   (snapshot)        (ritmo)        (+3/+2/+1/OVERTIME, ETA, confianza)
                                        │                                  │
                                        └──────────► PresentationModel ◄───┘
                                                     (texto + color, puro)
                                                            │
                                                  BlizzardTrackerEnhancer
                                                  (hooks + regiones propias)
                                                            │
                                                  Objective Tracker NATIVO
```

Reglas de capa (se amplía el static check `check_tracker_layers`):
- `PaceEngine.lua`, `PredictionEngine11.lua` (nombre provisional),
  `TrackerPresentation.lua` y `BlizzardTrackerEnhancer.lua` **no** pueden
  contener `C_ChallengeMode`, `C_Scenario*`, `GetWorldElapsedTime(s)` ni
  `quantityString`. El enhancer tampoco puede leer datos del texto de los
  frames de Blizzard (`GetText` sobre regiones nativas prohibido por test).
- El enhancer solo toca frames de Blizzard para: `hooksecurefunc`, anclar
  regiones propias y (en modo STANDALONE) `Bar.Label:SetText`.
- La presentación es una función pura `Build(snapshot, prediction, settings)
  -> { timerLine, thresholdsLine, forcesLabel, bossesLine, deathsLine,
  predictionLine, tooltip }` testeable sin cliente.
- `PredictionEngine` 1.0 queda como está (lo usa el HUD legacy congelado). La
  versión 1.1 reutiliza sus **ideas medidas** (estimador trash/boss separado,
  suavizado asimétrico τ 20/60 s, histéresis de 20 s, `hasBasis`, confianza por
  evidencia) pero consume TrackerState, no `KeystoneTracker`.

## 3. PaceEngine / PredictionEngine 1.1 (sin UI)

Entrada: `TrackerState:GetLiveSnapshot()` y eventos del bus
(`MITZU_TRACKER_STATE_CHANGED`, `RUN_STARTED`, `RUN_COMPLETED`, `RUN_ENDED`).
Tiempo de boss: `ENCOUNTER_START/END` (eventos, no datos de API de M+).

- Umbrales: `p3 = floor(limit * 0.6)`, `p2 = floor(limit * 0.8)`, `p1 = limit`.
- Estados de salida: `NO_BASIS` (progreso < 8 % o < 20 s), `+3`, `+2`, `+1`,
  `OVERTIME`; en `COMPLETING`/`COMPLETED` el resultado es el **real**
  (`finalElapsed` frente a umbrales) y no una predicción.
- Pausa: si `timerStale` o `forcesStale` persisten, la confianza baja y el
  motor no cambia de bracket con datos obsoletos.
- **Pregunta abierta (verificar en Retail antes de fijar la fórmula):** 1.0
  suma `timeLost` al tiempo transcurrido. Si el temporizador del servidor ya
  incluye la penalización por muerte, eso la cuenta dos veces. Prueba: anotar
  `elapsed` justo antes y después de una muerte (`/emp dev state`) y ver si
  salta `deathTimeLost` de golpe. El PaceEngine usará lo que diga esa prueba.

## 4. Puntos de enganche

Todos `hooksecurefunc` (post-hook), instalados una vez, cada callback en
`pcall`. Nunca se reemplaza una función de Blizzard.

| Hook | Frecuencia | Uso |
|---|---|---|
| `ScenarioObjectiveTracker.ChallengeModeBlock:Activate` | inicio de llave / reload | crear (una vez) regiones propias; refrescar umbrales |
| `ScenarioObjectiveTracker.ChallengeModeBlock:UpdateTime` | cada frame | salir si el segundo entero no cambió; actualizar timer/umbrales |
| `ScenarioObjectiveTracker:UpdateCriteria` o `:LayoutContents` | cada rebuild | re-aplicar decoración de fuerzas/bosses tras el layout nativo |
| `ScenarioObjectiveTracker.ObjectivesBlock:AddProgressBar` | al crear/reusar barra | hook de instancia `bar:SetValue` una sola vez (`bar.__mitzuHooked`) |
| `bar:SetValue` (instancia) | por actualización de barra | etiqueta precisa de fuerzas (solo modo STANDALONE) |

Además: el enhancer escucha `MITZU_TRACKER_STATE_CHANGED` para repintar sin
esperar al siguiente `UpdateTime`. Sin `OnUpdate` propio.

Son los mismos puntos que usa Angry Keystones (observados en el cliente de
Retail): por eso la coexistencia (§5) es parte del diseño, no un extra.

## 5. Coexistencia con Angry Keystones

Detección: `C_AddOns.IsAddOnLoaded("AngryKeystones")` al activar y en
`ADDON_LOADED` (puede cargar después). Se registra en Bug Report
(`[BLIZZARD TRACKER] angryKeystones=loaded|absent`, modo elegido).

| Región | STANDALONE (sin AK) | COEXIST (AK cargado, por defecto) |
|---|---|---|
| `Bar.Label` de fuerzas | Mitzu escribe `57.23%` (o `468/817 · 57.23%`) | **AK** (Mitzu no escribe) |
| Umbrales +3/+2 junto a `TimeLeft` | Mitzu | **AK** (Mitzu no los dibuja) |
| Marcas +3/+2 sobre `StatusBar` | Mitzu (texturas propias) | ninguna de Mitzu |
| Fuerzas restantes absolutas | línea propia | línea propia (AK no la muestra) |
| Predicción / ETA / confianza | línea propia + tooltip | línea propia + tooltip |
| Muertes / penalización | tooltip del bloque | tooltip (AK ya pinta el suyo) |

- Nunca se escribe en una región que AK controla: dos post-hooks sobre
  `Bar.Label` = el último gana y el texto parpadea.
- Ajuste explícito `enhancer.coexist = "AUTO" | "FORCE_MITZU" | "MITZU_MINIMAL"`
  (fase 8). `AUTO` = tabla anterior.
- Prueba obligatoria en Retail con AK activado **y** desactivado.

## 6. Regiones propias y layout

- `ChallengeModeBlock` mide 251×87 con `height` fijo: **no** se cambia
  `height`, `usedLines`, `timeLimit` ni ningún campo que lea el layout nativo.
- Regiones creadas una vez como hijas del bloque (`CreateFontString`,
  `CreateTexture`), nombres con prefijo `Mitzu`, ancladas a regiones nativas
  (`TimeLeft`, `StatusBar`, `DeathCount`). Si no caben en 87 px, la línea de
  predicción va al **tooltip** del bloque (`HookScript("OnEnter")`), no a una
  ventana nueva.
- Añadir líneas al `ObjectivesBlock` (`AddObjective`) queda descartado hasta
  demostrar en Retail que no propaga taint al contenedor.
- Al salir de la llave, en `COMPLETED` (tras mostrar el resultado real) o al
  desactivar: `Hide()` y textos vacíos; no se destruye nada.

## 7. Seguridad Midnight / taint

- `hooksecurefunc` no contamina la ejecución segura de Blizzard; escribir
  campos de sus tablas o llamar a métodos protegidos sí. El enhancer no hace
  lo segundo.
- Todo dato llega ya normalizado de TrackerState: el enhancer nunca toca
  valores secretos ni compara/formatea valores de Blizzard.
- `SetText`/`Show`/`Hide` sobre FontStrings/texturas propias no protegidas es
  válido en combate. Crear regiones: solo en `Activate`/primer uso, nunca por
  frame.
- Kill switch: contador de errores por callback; con 3 errores en una sesión
  el enhancer se desactiva, oculta sus regiones, sus hooks quedan como no-op,
  lo anota (`ENHANCER_DISABLED reason=...`) y el tracker nativo sigue intacto.
- Arranque solo si `BlizzardTrackerProbe:IsEnhanceable()` es verdadero; si no,
  no se instala ningún hook y se aplica la política de fallback de ROADMAP
  (HUD legacy congelado).
- Criterio: `/emp dev blizzard` con `tainted=none` antes, durante (combate) y
  después de una llave completa y tras `/reload`; cero `ADDON_ACTION_BLOCKED`.

## 8. Estados de TrackerState en pantalla

| Estado | Presentación |
|---|---|
| `IDLE` | nada de Mitzu visible |
| `PENDING` | regiones creadas; predicción "—"; sin umbrales hasta tener `timeLimit` |
| `RUNNING` | todo |
| `COMPLETING` | resultado provisional real (`finalElapsed`), sin predicción |
| `COMPLETED` | resultado real `+N`/`OVERTIME` con margen; si `completionCriteriaIncomplete`, sin afirmar bosses que no se leyeron |
| `*Stale=true` | valor mostrado atenuado; predicción congelada, confianza baja |

## 9. Pruebas

Unitarias (Lua 5.1 y 5.4):
- PresentationModel: 0/50/100 %, restantes, sin límite, overtime, stale,
  `COMPLETING`, `completionCriteriaIncomplete`.
- PredictionEngine 1.1: tabla de casos reales de Retail (dev.3/dev.4) con
  proyecciones esperadas; histéresis; `NO_BASIS`; resultado real al completar.
- Enhancer con mock de `ScenarioObjectiveTracker` (bloque, barra, AK
  simulado): hooks instalados una vez; `UpdateTime` por frame no escribe si el
  segundo no cambia; modo COEXIST no escribe `Bar.Label`; kill switch.
- Static: capas sin tokens de API; el enhancer no llama `GetText` sobre
  regiones de Blizzard; `KeyPredictionHUD.lua` sigue con su hash.

Retail (máx. 4 pasos por prueba guiada): llave completa con AK, llave completa
sin AK, `/reload` a mitad de llave, `/emp bugreport` + `/emp dev blizzard` al
final. PTR: opcional.

## 10. Plan de entrega

| Paso | Contenido | Visible |
|---|---|---|
| 3a | PaceEngine + PredictionEngine 1.1 sobre TrackerState; `/emp dev pace` | No |
| 3b | Enhancer "montado": detección AK, hooks instalados, regiones ocultas, kill switch, taint baseline | No |
| 3c | Fuerzas: precisión y restantes (según modo AK) | Sí |
| 3d | Timer: umbrales +3/+2 y marcas (solo STANDALONE) | Sí |
| 3e | Predicción, ETA, confianza, muertes (línea/tooltip) | Sí |
| 3f | Ajustes mínimos (activar, modo AK) → enlaza con la migración de fase 8 | Sí |

Cada paso: tests, commit local, despliegue Retail dev, prueba guiada.

## 11. Preguntas para la revisión

1. ¿La línea de predicción va dentro del bloque (si cabe) o solo en tooltip?
2. Modo COEXIST por defecto: ¿ceder a AK barra y umbrales (propuesto) o
   preferir Mitzu y avisar al usuario?
3. Formato de fuerzas en STANDALONE: `57.23%` o `468/817 · 57.23%`.
4. ¿`OVERTIME` o texto localizado (`FUERA`) en la UI en español?
5. Penalización por muerte: confirmar en Retail si el temporizador del
   servidor ya la incluye (§3) antes de fijar el PaceEngine.
