# MitzuMPlus

Este repositorio contiene **dos addons de World of Warcraft independientes**
(Retail, Midnight 12.1, `## Interface: 120100`):

| Addon | Carpeta | Versión | Estado |
|---|---|---|---|
| **MitzuMPlus** | `MitzuMPlus/` | `7.13.0-rc1` | **RELEASE CANDIDATE** · **CURSEFORGE READY** |
| **MitzuRouteArrows** | `MitzuRouteArrows/` | `0.1.0-dev` | **EXPERIMENTAL** · **IN DEVELOPMENT** · **NOT READY FOR CURSEFORGE** |

La diferencia de estabilidad es deliberada y está en las versiones: MitzuMPlus
es un candidato a release; MitzuRouteArrows es una versión de desarrollo (`-dev`)
que puede cambiar o romperse entre commits.

```
MitzuMPlus  ──►  MitzuMPlusAPI (solo lectura)  ──►  MitzuRouteArrows  ──►  Threat Plates / Plater / ElvUI / placas de Blizzard
 (producto)                                           (experimental)
```

MitzuMPlus no sabe que MitzuRouteArrows existe y funciona exactamente igual con
o sin él. MitzuRouteArrows solo lee MitzuMPlus a través de la API pública; no
puede mover el pull, escribir identidad, cambiar el progreso de la ruta ni tocar
la sesión de la run.

---

## MitzuMPlus — el producto

Historial de Mythic+, rutas nativas de la temporada y Coach en vivo.

- Detección de mazmorra y de llave (`PRE_KEY` / `RUNNING` / `COMPLETED` / `RESET`), modo desafío.
- Rutas nativas de la temporada empaquetadas (8 mazmorras, 104 pulls). **MDT no hace falta.**
- `RouteManager` y `RouteProgress` (autoridad única del pull actual).
- Sesión de la run y recuperación tras `/reload`.
- Coach, recomendaciones, historial, estadísticas, perfiles de compañeros.
- Rol y especialización del grupo, diagnósticos.
- Importación opcional de rutas desde Mythic Dungeon Tools.
- API pública de solo lectura para otros addons: `MitzuMPlusAPI`.

**Dependencias:** ninguna obligatoria. `OptionalDeps: MythicDungeonTools, LibSharedMedia-3.0`.

**Comandos:** `/emp` (o `/mitzumplus`). `/emp help` lista todos. Los más usados:

| Comando | Qué hace |
|---|---|
| `/emp` | Abre la ventana |
| `/emp config` | Configuración |
| `/emp dungeon` · `/emp lifecycle` · `/emp session` | Estado de mazmorra, llave y sesión |
| `/emp route` · `/emp routes` | Ruta activa y rutas disponibles |
| `/emp next` · `/emp prev` · `/emp pull <n>` | Mover el pull de la ruta |
| `/emp hud` | HUD del pull |
| `/emp version` · `/emp bugreport` | Versión e informe de errores |

### Actualizar desde `MitzuMPlus_Historial` (7.12 o anterior)

La carpeta del addon cambió de nombre: `MitzuMPlus_Historial` → `MitzuMPlus`.
WoW guarda las SavedVariables en un fichero con el nombre de la carpeta, así que
el historial **no se carga solo** en la carpeta nueva. Una vez, con el juego cerrado:

1. Borra la carpeta antigua `Interface/AddOns/MitzuMPlus_Historial`.
2. Copia `WTF/Account/<CUENTA>/SavedVariables/MitzuMPlus_Historial.lua`
   como `WTF/Account/<CUENTA>/SavedVariables/MitzuMPlus.lua`.

Los nombres de las variables (`MitzuMPlusDB`, `MPlusAdaptiveRouteDB`) no cambian,
así que el contenido se aprovecha tal cual. La tecla de la pestaña de historial
se renombró (`MitzuMPlus_HistoryTabBinding`) y hay que volver a asignarla.
Detalles en [docs/RELEASE.md](docs/RELEASE.md).

---

## MitzuRouteArrows — experimental

> **EXPERIMENTAL / IN DEVELOPMENT / NOT READY FOR CURSEFORGE.**
> No se empaqueta ni se publica. Puede cambiar o romperse sin aviso.

Todo lo que se estaba investigando sobre guía visual de pulls:

- `RouteArrows`, `NameplateAnchorProvider` (Threat Plates, Plater, ElvUI, Blizzard), `NameplateGenerations`, pooling.
- `PullUnitResolver`, `LiveEnemyResolver`, `GuidanceEngine`, `RouteArrowPresenter`.
- Evidence Layer: `EngagementEvidence`, `UnitLinkEvidence`, `CastEvidence`, `AuraEvidence`, `EventCastEvidence`, `PackEvidence`, `PhysicalGroupMetadata`, `PhysicalGroupCorrelation`.
- Alignment (diagnóstico pasivo): `RouteSignature`, `ExecutionEpisodeTracker`, `RoutePullCandidateScorer`, `RouteAlignment`.
- `ArrowDemo` y su telemetría.

**Dependencias:** `OptionalDeps: MitzuMPlus, ThreatPlates, Plater, ElvUI`.
MitzuMPlus se declara opcional a propósito: así, si falta, MitzuRouteArrows
carga igualmente, avisa una vez en el chat y queda inerte en lugar de ser
descartado en silencio por WoW. Sin MitzuMPlus no dibuja nada.

**Comandos:** `/mra` (o `/mitzuroutearrows`). `/mra help` lista todos.

| Comando | Qué hace |
|---|---|
| `/mra status` | Estado del addon, conexión con MitzuMPlus y addon de placas detectado |
| `/mra debug` | Diagnóstico de flechas, asignaciones y Guidance |
| `/mra alignment ...` · `/mra alignmentdetail` | Inferencia pasiva del pull (no mueve nada) |
| `/mra evidence` · `/mra castevidence` · `/mra eventcast` · `/mra packevidence` | Evidence Layer |
| `/mra plates` | A qué frame se ancla cada flecha |
| `/mra arrowdemo ...` | Demo de flechas aproximadas + telemetría |

Guarda sus ajustes en `MitzuRouteArrowsDB`. Nunca lee ni escribe las
SavedVariables de MitzuMPlus.

---

## Repositorio

```
MitzuMPlus/            addon producto (lo único que va al zip de CurseForge)
MitzuRouteArrows/      addon experimental
tests/                 bancos Lua (lupa) y comprobaciones estáticas
  core/                MitzuMPlus
  routearrows/         MitzuRouteArrows
  harness/             cliente de WoW simulado que carga los addons por su .toc
tools/                 empaquetado y generadores de datos
docs/                  arquitectura, release e historial
```

### Pruebas

Requiere Python 3 con `lupa` (`pip install lupa`).

```bash
python tests/run_lua_tests.py
```

```bash
python tests/run_static_checks.py
```

### Empaquetar MitzuMPlus

```bash
python tools/package_mitzumplus.py --check
```

Genera `dist/MitzuMPlus-<versión>.zip` con una única carpeta `MitzuMPlus/` y lo
valida. Ver [docs/RELEASE.md](docs/RELEASE.md).

Arquitectura, API y eventos: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
Procedencia y licencia de los datos: [MitzuMPlus/DATA_SOURCES.md](MitzuMPlus/DATA_SOURCES.md).

## Licencia

MIT, ver [LICENSE](LICENSE). Los datos de rutas y enemigos derivan de Mythic
Dungeon Tools (GPL-2.0); ver `DATA_SOURCES.md` de cada addon antes de distribuir.
