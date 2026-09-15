# MitzuMPlus 1.1.0 — roadmap

Objetivo: **Blizzard Tracker Enhancer + Enemy Forces**. Enhance, don't replace.

## Matriz de validación en cliente real

| Qué | Retail 12.1.0.69814 | PTR 12.1.5.69594 |
|---|---|---|
| Carga del addon, APIs y capacidades | OK | Pendiente |
| Llave activa: mapa 249, nivel 6, límite 1980 | OK | Pendiente |
| Fuerzas no nulas: `quantity=23` (% entero), `quantityString="144%"` (recuento), `totalQuantity=608` → 144/608 = 23.684 % | OK | **Pendiente** |
| Bosses 1/4 (primero completado) | OK | Pendiente |
| Paridad adaptador vs 1.0 | OK, sin DIFF | Pendiente |
| Final de llave: RUNNING → COMPLETED, historial una vez, 0 duplicados, 0 errores, invariantes 9/0/0 | OK | Pendiente |
| `/reload` con llave activa (dev.3, Reposo de los Reyes +13): `recovered=true`, elapsed 4:08 y 5:08 un minuto después (continuidad del servidor), fuerzas 166/608 = 27.30 %, sin stale, adapterErrors=0 | OK | Pendiente |
| TrackerState RUNNING (dev.3): 66/608 = 10.86 %, bosses 0/4, paridad sin DIFF, coincide con el tracker de Blizzard (27.30 % tras reload) | OK | Pendiente |
| TrackerState RUNNING → COMPLETED + Bug Report final (dev.3) | **Pendiente** | Pendiente |
| Taint baseline tras `/reload` (`/emp dev blizzard` → `tainted=none`) | Pendiente | Pendiente |

Un dato validado en Retail **no** cuenta como validado en PTR.

## Compuertas de BlizzardTrackerEnhancer (fase 7)
No se implementa ningún hook hasta cumplir **las tres**:
1. Prueba de recuperación con `/reload` en llave activa. (Retail: OK)
2. Fuerzas no nulas confirmadas en PTR 12.1.5.69594.
3. Línea base de taint en runtime tras `/reload`.

## Fuera de alcance
- Rutas, pulls, MDT, navegación, placas, tácticas (→ MitzuRouteArrows).
- **Retirado por decisión de diseño (2026-09-15):** HUD V2 independiente, modos
  Compacto/Normal/Avanzado, opción "Ocultar tracker Blizzard", reemplazo del
  Objective Tracker, timer duplicado, ventana M+ separada.

## Fases
| Fase | Contenido | Estado |
|---|---|---|
| 0 | Auditoría, rama, baseline | Hecho |
| 1 | TrackerAdapter + capacidades | Hecho; validado en llave real de **Retail** 12.1.0 |
| 1b | Auditoría del Objective Tracker (fuente 12.1.5) + `BlizzardTrackerProbe` solo lectura | Hecho; pendiente confirmación en PTR |
| 2 | TrackerState (snapshot normalizado, eventos, throttling) — `docs/tracker/TRACKER_STATE.md` | RUNNING y `/reload` validados en Retail (dev.3); falta COMPLETED |
| 3 | Enemy Forces en TrackerState | |
| 4 | Boss state | |
| 5 | PaceEngine | |
| 6 | PredictionEngine sobre TrackerState (+3/+2/+1/OVERTIME, ETA, margen, confianza) | |
| 7 | **BlizzardTrackerEnhancer** (interfaz principal): fuerzas precisas en la barra nativa, umbrales +3/+2 en el bloque M+, predicción/ETA/pace; capability check con fallback al HUD legacy | |
| 8 | Configuración mínima (activar mejoras, qué mostrar, opción LEGACY/fallback) + migración versionada de SavedVariables | |
| 9 | Bug Report 1.1 | |
| 10 | Llave completa en PTR | |
| 11 | Hardening / regresión / taint | |
| 12 | 1.1.0-beta.1 candidata | |

## Decisión: KeyPredictionHUD (2026-09-15)

**KEEP FOR ROLLBACK, DO NOT DEVELOP FURTHER.**

- `BlizzardTrackerEnhancer` = interfaz principal de Mythic+ en 1.1.
- `KeyPredictionHUD` (ventana flotante de 1.0) = fallback / legacy temporal.

Reglas:
1. No se borra ni su lógica, ni se reescribe, ni recibe funciones nuevas.
   `tests/run_static_checks.py` exige que `modules/KeyPredictionHUD.lua` siga
   idéntico a `v1.0.0-beta.1` (hash). Cambiarlo requiere decisión explícita
   anotada aquí.
2. Todo desarrollo visual nuevo va solo a `BlizzardTrackerEnhancer`.
3. Cuando el enhancer esté funcional y validado: HUD legacy **desactivado por
   defecto en instalaciones nuevas** de 1.1.0.
4. Durante la beta se mantiene una opción LEGACY/fallback en configuración.
5. Si el enhancer falla su capability check (`BlizzardTrackerProbe:IsEnhanceable()`):
   no toca el tracker de Blizzard, registra el fallo (FlightRecorder + Bug
   Report) y permite el fallback al HUD legacy si corresponde.
6. Sin migración destructiva de SavedVariables. Antes de la release candidate,
   migración versionada e idempotente para usuarios de 1.0.0-beta.1.
7. Retirada definitiva solo tras: M+ completa, prueba tras `/reload`, cambio de
   criterios, final de llave, cero taint/errores Lua y regresión completa de 1.0.

### Notas técnicas para la migración (fase 8/12)
- Ajustes actuales: `profile.settings.hud = { enabled=true, locked, scale, alpha,
  showConfidence, showETA, point, relPoint, x, y }` (defaults en
  `MitzuMPlus_main.lua` y `HUD.DEFAULTS`).
- **AceDB solo guarda valores distintos del default.** Un usuario de 1.0 con el
  HUD activado no tiene `hud.enabled` guardado; cambiar el default a `false`
  lo apagaría en silencio y no se distingue de "nunca lo tocó". Por tanto no se
  cambia el default de `hud.enabled`: el modo se decide con un ajuste nuevo
  (p. ej. `settings.mplusDisplay = "ENHANCER" | "LEGACY_HUD"`) más un marcador
  de migración versionado en `global`.
- `Init.lua` sobrescribe `db.global.version` al cargar. La migración debe leer
  la versión previa **antes** de esa línea para distinguir instalación nueva
  (sin `MitzuMPlusDB` previo) de actualización desde `1.0.0-beta.1`.
- Política para quien actualiza desde 1.0: **decidida (2026-09-15)**, también
  migra a ENHANCER; el HUD legacy queda solo como elección manual o fallback de
  runtime. Contrato, requisitos R1-R12 y detalles en
  `docs/tracker/DISPLAY_MIGRATION.md`; spec preparado en
  `tests/pending/DisplayMigration.spec.lua` (se activa en fase 8).
