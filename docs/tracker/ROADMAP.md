# MitzuMPlus 1.1.0 — roadmap

Objetivo: **Blizzard Tracker Enhancer + Enemy Forces**. Enhance, don't replace.

## Política de validación (desde 2026-09-16, 1.1.0-dev.5)

| Prioridad | Cliente | Papel |
|---|---|---|
| **PRINCIPAL** | Retail 12.1.0.69814 (cliente live) | Validación en runtime de cada build `dev.N`. Una fase avanza con evidencia de Retail. |
| OPCIONAL / FUTURO | PTR 12.1.5.69594 | Validación adicional cuando sea práctica. **No bloquea** ninguna fase. |

Motivo: en el PTR casi no hay grupos de Mítica+, así que una llave completa y
repetible allí no es viable. Retail ofrece llaves reales cada día y el
`Blizzard_ObjectiveTracker` es idéntico byte a byte en ambos builds
(`BLIZZARD_TRACKER_ENHANCER.md` §1), por lo que Retail representa bien el
código que se va a decorar.

Reglas:
- La evidencia existente del PTR no se borra. Cada fila distingue **Retail
  validado**, **PTR validado** y **no probado en PTR**.
- Un dato validado en Retail **no** se marca como validado en PTR.
- Si más adelante aparece una diferencia en PTR (12.1.5), se registra como bug
  de compatibilidad, no como bloqueo retroactivo de fases cerradas.
- Despliegue de desarrollo en Retail: `python tools/deploy_ptr.py --retail`
  (backup previo, solo con `Wow.exe` cerrado). El público de CurseForge sigue en
  `1.0.0-beta.1`; los artefactos de release no se tocan.

## Matriz de validación en cliente real

| Qué | Retail 12.1.0.69814 | PTR 12.1.5.69594 |
|---|---|---|
| Carga del addon, APIs y capacidades | Retail validado | No probado en PTR |
| Llave activa: mapa 249, nivel 6, límite 1980 | Retail validado | No probado en PTR |
| Fuerzas no nulas: `quantity=23` (% entero), `quantityString="144%"` (recuento), `totalQuantity=608` → 144/608 = 23.684 % | Retail validado | No probado en PTR |
| Bosses 1/4 (primero completado) | Retail validado | No probado en PTR |
| Paridad adaptador vs 1.0 | Retail validado, sin DIFF (dev.2 y dev.4) | No probado en PTR |
| Final de llave (1.0): RUNNING → COMPLETED, historial una vez, 0 duplicados, 0 errores, invariantes 9/0/0 | Retail validado (dev.2 y dev.4) | No probado en PTR |
| `/reload` con llave activa (dev.3, Reposo de los Reyes +13): `recovered=true`, elapsed 4:08 y 5:08 un minuto después, fuerzas 166/608 = 27.30 %, sin stale, adapterErrors=0 | Retail validado | No probado en PTR |
| TrackerState RUNNING (dev.3): 66/608 = 10.86 %, bosses 0/4, paridad sin DIFF, coincide con el tracker de Blizzard | Retail validado | No probado en PTR |
| Capacidades explícitas (dev.4): `requiredMissing=none optionalMissing=none legacyFallbacksAbsent=1` | Retail validado | No probado en PTR |
| Arranque transitorio (dev.4): `ACTIVE_WITHOUT_FORCES` resuelto en ~1.0 s, `ACTIVE_WITHOUT_TIMER` en ~8.6 s, sin avisos persistentes | Retail validado | No probado en PTR |
| TrackerState RUNNING → COMPLETED (dev.4, Altar de Colmillos 588 +12, 29:43/30:00, 9 muertes, 135 s): llega a COMPLETED, pero congela `bosses=2/3` con `forces stale=true bosses stale=true` | **Fallo encontrado** → corregido en dev.5 | No probado en PTR |
| Convergencia del final (dev.5, Reposo de los Reyes 249 +12, 27:57/33:00, 14 muertes): historial una vez (`runs` 46→47, `duplicateSessionIDs=0`), `/reload` recuperado con la misma sesión; **pero** Blizzard retiró los criterios antes de leer `4/4` (`completionConverged=false`, `3/4`) | **Fallo encontrado** → autoridad terminal en dev.6 | No probado en PTR |
| Autoridad del final (dev.6): `terminalStateConfirmed=true`, `bossCountSource` correcto, sin avisos; Bug Report `[PARTY]` con clase/rol; Mitzu Tracker visible y sin errores | **Pendiente (Retail)** | No probado en PTR |
| Sonda del tracker de Blizzard: `enhanceable=true tainted=none` | Retail validado (dev.4, sesión normal) | No probado en PTR |
| Taint baseline tras `/reload` con llave activa (`/emp dev blizzard`) | Pendiente (Retail) | No probado en PTR |

## Compuertas de BlizzardTrackerEnhancer

Revisadas el 2026-09-16 con la política Retail-first. Antes de escribir hooks:
1. Recuperación con `/reload` en llave activa. **Retail: OK (dev.3).**
2. ~~Fuerzas no nulas confirmadas en PTR 12.1.5.69594.~~ Sustituida por:
   fuerzas no nulas confirmadas en Retail. **Retail: OK.** PTR queda como
   validación opcional.
3. TrackerState estable de punta a punta, incluido el final de llave:
   **dev.5 en Retail pendiente** (convergencia del final).
4. Línea base de taint en runtime tras `/reload` (`tainted=none`). Pendiente en
   Retail; se puede recoger en la misma prueba que la compuerta 3.

La falta de pruebas en PTR ya no bloquea la fase 3 (enhancer). Solo la bloquean
las compuertas 3 y 4 en Retail. El diseño está listo para revisión en
`docs/tracker/PHASE3_ENHANCER_DESIGN.md`; no hay código de hooks.

## Fuera de alcance
- Rutas, pulls, MDT, navegación, placas, tácticas (→ MitzuRouteArrows).
- Modos Compacto/Normal/Avanzado y reemplazo del Objective Tracker.
- ~~HUD V2 independiente (retirado 2026-09-15)~~: **revertido por decisión del
  usuario el 2026-09-16** (ver "Decisión: Mitzu Tracker"). Ocultar el bloque M+
  de Blizzard sigue fuera hasta poder hacerlo sin taint.

## Fases

Numeración del sprint (2026-09-16): **Fase 2** = TrackerState, **Fase 2.1** =
convergencia del final, **Fase 3** = BlizzardTrackerEnhancer (agrupa las filas
3-7 de la tabla original, que se conserva debajo como referencia).

| Fase sprint | Contenido | Estado |
|---|---|---|
| 0 | Auditoría, rama, baseline | Hecho |
| 1 | TrackerAdapter + capacidades | Hecho; Retail validado |
| 1b | Auditoría del Objective Tracker + `BlizzardTrackerProbe` solo lectura | Hecho; Retail validado (`enhanceable=true`) |
| 2 | TrackerState (snapshot normalizado, eventos, throttling) — `TRACKER_STATE.md` | Hecho; RUNNING, `/reload` y arranque Retail validados |
| 2.1 | Convergencia del final de llave (dev.5) | Implementado y testeado; **pendiente llave real en Retail** |
| 3 | BlizzardTrackerEnhancer + pace/predicción sobre TrackerState — `PHASE3_ENHANCER_DESIGN.md` | Diseño listo para revisión; sin implementar |

Tabla original (referencia):

| Fase | Contenido | Estado |
|---|---|---|
| 3 | Enemy Forces en TrackerState | Cubierto por la fase 2 |
| 4 | Boss state | Cubierto por la fase 2 / 2.1 |
| 5 | PaceEngine | → fase 3 del sprint |
| 6 | PredictionEngine sobre TrackerState (+3/+2/+1/OVERTIME, ETA, margen, confianza) | → fase 3 del sprint |
| 7 | **BlizzardTrackerEnhancer** (interfaz principal) | → fase 3 del sprint |
| 8 | Configuración mínima + migración versionada de SavedVariables | |
| 9 | Bug Report 1.1 | |
| 10 | Llave completa de validación final (Retail; PTR opcional) | |
| 11 | Hardening / regresión / taint | |
| 12 | 1.1.0-beta.1 candidata | |

## Decisión: Mitzu Tracker (2026-09-16, sustituye a la de 2026-09-15)

El usuario decide construir un tracker propio (Mitzu Tracker) como interfaz de
Mythic+ de 1.1, en lugar de centrar 1.1 en decorar el bloque de Blizzard.

- `KeyPredictionHUD.lua` **retirado en 1.1.0-dev.6**. Se migraron todos sus
  consumidores (comandos, configuración, atajo, popups, invariantes, Bug Report)
  a `MitzuTracker` y se comprobó que no queda ninguna dependencia. Rollback:
  git (`v1.0.0-beta.1`). El hash congelado de `run_static_checks.py` se
  sustituye por el contrato de capas del tracker visual.
- Ajustes: los mismos `profile.settings.hud` (sin migración; no cambia ningún
  default, así AceDB no pierde nada).
- Tracker de Blizzard: coexiste. Ocultar solo el bloque M+ queda pendiente de
  una implementación sin taint validada en Retail.
- `BlizzardTrackerEnhancer` / `PHASE3_ENHANCER_DESIGN.md`: en pausa; su
  capa de estado (TrackerState) es la misma que usa Mitzu Tracker.
- Arquitectura y datos: `docs/tracker/MITZU_TRACKER.md`.

## Decisión histórica: KeyPredictionHUD (2026-09-15, sustituida)

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
