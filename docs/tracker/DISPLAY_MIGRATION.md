# Migración de visualización M+ (1.1.0) — decisión y contrato

**Estado:** decisión cerrada (2026-09-15). **Implementación: fase 8.** Aquí solo
el contrato y los requisitos; el spec preparado vive en
`tests/pending/DisplayMigration.spec.lua` y el runner todavía no lo ejecuta.

## Decisión

- Toda instalación de 1.1.0 (nueva **o** actualizada desde 1.0.0-beta.1) usa
  `BlizzardTrackerEnhancer` como interfaz principal de Mythic+.
- `KeyPredictionHUD` deja de ser la interfaz activa por defecto tras actualizar.
- No se borra, no se modifica (`KeyPredictionHUD.lua` congelado por hash) y sus
  SavedVariables (`profile.settings.hud`) se conservan íntegras para rollback.

## Modelo

```
profile.settings.mplusDisplay = "ENHANCER" | "LEGACY_HUD"   -- preferencia persistente
global.migrations.mplusDisplay110 = { done = true, schema = 1, from = <versión previa | "NEW_INSTALL">, at = <epoch> }
```

- Default AceDB de `mplusDisplay`: `"ENHANCER"`. Así cualquier perfil sin la
  clave (otros personajes/perfiles, que la migración no recorre) resuelve a
  ENHANCER. **Este default no debe cambiar nunca**: AceDB no persiste valores
  iguales al default, así que cambiarlo movería en silencio a todo el que no
  eligió explícitamente. Si algún día hay que cambiar la preferencia de todos,
  se hace con una migración nueva y versionada que escriba valores explícitos.
- `hud.enabled` y el resto de `settings.hud` no se leen para decidir nada y no
  se escriben durante la migración.

## Contrato previsto (`MitzuMPlus/modules/Tracker/DisplayMode.lua`, fase 8)

| Función | Contrato |
|---|---|
| `DisplayMode.MODES` | `{ ENHANCER = "ENHANCER", LEGACY_HUD = "LEGACY_HUD" }` |
| `DisplayMode.DEFAULT` | `"ENHANCER"` |
| `DisplayMode.MIGRATION_KEY` | `"mplusDisplay110"` |
| `DisplayMode.CapturePreviousVersion(global)` | Devuelve `global.version` (string no vacía) o `nil`. No modifica nada. `Init.lua` la llama **antes** de `self.db.global.version = self.VERSION`. |
| `DisplayMode.Migrate(db, previousVersion, now)` | `db = { global, profile }` (AceDB). Si ya hay marcador → `false, "ALREADY_MIGRATED"` sin tocar nada. Si no: fija `profile.settings.mplusDisplay = "ENHANCER"` solo cuando falta o es inválido (un valor válido existente se respeta), escribe el marcador y devuelve `true, "NEW_INSTALL"` o `true, "UPGRADE"`. Nunca toca `global.version`, `settings.hud` ni otros ajustes. |
| `DisplayMode.Resolve(settings, probe)` | `probe = { enhanceable = bool, missing = {...} }`. Devuelve `{ preferred, active, fallback, reason }` **sin modificar** `settings`. `LEGACY_HUD` elegido → `active = LEGACY_HUD`. `ENHANCER` + probe OK → `ENHANCER`. `ENHANCER` + probe KO → `active = LEGACY_HUD`, `fallback = true`, `reason = "ENHANCER_UNAVAILABLE:<missing>"`. Valor ausente o inválido → preferencia `ENHANCER`. |
| `DisplayMode.LegacyHudSettings(settings)` | La tabla histórica `settings.hud` tal cual (misma referencia). |
| `DisplayMode.RecordFallback(recorder, result)` | Si `result.fallback`, registra una entrada `DISPLAY / ENHANCER_FALLBACK` con el motivo en el FlightRecorder; si no, no registra nada. |

## Requisitos

| # | Requisito |
|---|---|
| R1 | La versión previa se captura antes de sobrescribir `global.version`. |
| R2 | Instalación existente < 1.1.0 sin marcador → `mplusDisplay = ENHANCER`. |
| R3 | Instalación nueva → `mplusDisplay = ENHANCER`. |
| R4 | Marcador explícito `global.migrations.mplusDisplay110` con origen. |
| R5 | `hud.enabled` no se usa para decidir. |
| R6 | El default histórico de `hud.enabled` no cambia. |
| R7 | `settings.hud` se conserva íntegro. |
| R8 | `LEGACY_HUD` elegido manualmente usa la configuración histórica. |
| R9 | ENHANCER con capability check KO → no tocar el tracker de Blizzard, registrar el motivo, LEGACY_HUD solo como fallback de runtime, **sin** cambiar `mplusDisplay`. |
| R10 | Si en una sesión posterior el check vuelve a pasar → ENHANCER automáticamente. |
| R11 | Versionada, idempotente, no destructiva: repetirla no cambia nada. |
| R12 | Tests: nueva, upgrade, versión previa preservada, repetición, ajustes existentes, legacy preservado, enhancer disponible/no disponible, fallback runtime, recuperación. |

Matriz de tests (spec pendiente): cada requisito tiene al menos un caso con su
`R#` en el nombre.

## Detalles a resolver al implementar (fase 8)

- **Ocultar el HUD legacy en modo ENHANCER sin tocar `KeyPredictionHUD.lua` ni
  `hud.enabled`**: envolver en memoria `KeyPredictionHUD.IsEnabled` desde
  `DisplayMode` (`original(self) and active == LEGACY_HUD`). No persiste nada.
- En fallback, el HUD legacy respeta su configuración: si el usuario lo tenía
  desactivado en 1.0 (`hud.enabled = false` guardado), seguirá oculto.
- `/emp tracker on|off`, la tecla `MITZUMPLUS_OVERLAY` y las opciones del HUD
  en Configuración escriben `hud.enabled`. En modo ENHANCER deben avisar de que
  el HUD legacy no está activo (o agruparse bajo "LEGACY") en vez de fallar en
  silencio.
- Invariante `HUD_PREDICTION_ONLY` y sección `[TRACKER]` del Bug Report: con el
  HUD oculto por modo no debe aparecer como fallo; añadir `mplusDisplay`,
  `activeDisplay` y `fallbackReason` al Bug Report.
- Al activar el spec: moverlo a `tests/core/` y añadir la entrada del TOC.
