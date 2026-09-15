# MitzuMPlus 1.1.0 — roadmap

Objetivo: **Blizzard Tracker Enhancer + Enemy Forces**. Enhance, don't replace.

## Fuera de alcance
- Rutas, pulls, MDT, navegación, placas, tácticas (→ MitzuRouteArrows).
- **Retirado por decisión de diseño (2026-09-15):** HUD V2 independiente, modos
  Compacto/Normal/Avanzado, opción "Ocultar tracker Blizzard", reemplazo del
  Objective Tracker, timer duplicado, ventana M+ separada.

## Fases
| Fase | Contenido | Estado |
|---|---|---|
| 0 | Auditoría, rama, baseline | Hecho |
| 1 | TrackerAdapter + capacidades | Hecho; pendiente PRUEBA PTR #1 |
| 1b | Auditoría del Objective Tracker (fuente 12.1.5) + `BlizzardTrackerProbe` solo lectura | Hecho; se confirma en PRUEBA PTR #1 |
| 2 | TrackerState (snapshot normalizado, eventos, throttling) | Tras PRUEBA PTR #1 |
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
