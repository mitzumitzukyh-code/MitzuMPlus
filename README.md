# MitzuMPlus

Este repositorio contiene **dos addons de World of Warcraft independientes**
(Retail, Midnight 12.1, `## Interface: 120100`):

| Addon | Carpeta | Versión | Estado |
|---|---|---|---|
| **MitzuMPlus** | `MitzuMPlus/` | `7.14.0-rc1` | **RELEASE CANDIDATE** · pendiente de prueba en vivo · **publicación BLOQUEADA por licencia** |
| **MitzuRouteArrows** | `MitzuRouteArrows/` | `0.1.0-dev` | **EXPERIMENTAL** · **IN DEVELOPMENT** · **NOT READY FOR CURSEFORGE** |

La diferencia de estabilidad es deliberada y está en las versiones: MitzuMPlus
es un candidato a release; MitzuRouteArrows es una versión de desarrollo (`-dev`)
que puede cambiar o romperse entre commits.

- **Baseline validada en WoW real:** `05a4d77` (MitzuMPlus `7.13.0-rc1`), probada en
  Retail 12.1.0 build 69814. Detalle en [docs/RELEASE.md](docs/RELEASE.md#1-baseline-validada-en-wow-real-05a4d77).
- **Bloqueo de publicación:** las rutas nativas y `data/MDTEnemyData.lua` derivan de
  Mythic Dungeon Tools (GPL-2.0) y el repositorio es MIT. No se publica en CurseForge
  hasta resolverlo ([docs/RELEASE.md §6](docs/RELEASE.md#6-bloqueo-de-licencia)).

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
- **Coach HUD V2**: la vista principal durante la llave (pull, ruta, siguiente pull, reloj y Coach).
- **Bug Report V2**: un único informe copiable con todo el contexto de una prueba en vivo.
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
| `/emp hud` | Activa/desactiva el Coach HUD |
| `/emp hud test` · `/emp hud test off` | Vista previa del HUD con datos de ejemplo (marcada PREVIEW) |
| `/emp hud lock` · `unlock` · `scale N` · `alpha N` · `compact` · `reset` · `status` | Ajustes del HUD |
| `/emp bugreport` | Informe QA completo para copiar y enviar |
| `/emp bugreport status` · `clear` | Resumen en el chat · limpiar caja negra y errores |
| `/emp version` | Versión |

### Coach HUD V2

Un panel compacto que aparece solo cuando hace falta:

| Estado de la llave | HUD |
|---|---|
| Fuera de mazmorra | oculto |
| Dentro, sin piedra | preparación: ruta y `PULL 1 / N` |
| Llave en marcha | completo: mazmorra y nivel, reloj, `PULL x / N`, % planificado de ruta, pull actual, siguiente pull, Coach |
| Completada | resumen corto y se oculta a los 20 s |
| Reinicio | oculto |

El HUD **es una vista, no una autoridad**: el pull que enseña es siempre el de
`RouteProgress`. Tras un `/reload` se reconstruye solo al pull recuperado. No
escanea placas ni mobs y no muestra datos que no estén disponibles (sin nombres de
mobs inventados, sin fuerzas secretas). Se configura con `/emp hud ...` o en la
pestaña Coach. Por defecto sustituye al overlay clásico del Coach para no
duplicarse en pantalla.

### Bug Report V2 y prueba en vivo

Durante una llave no hace falta escribir comandos: una caja negra de QA anota las
transiciones, la ruta, los cambios de pull, las decisiones de recuperación, el HUD,
el Coach y los errores. Al terminar, o al ver algo raro:

```
/emp bugreport
```

Abre una ventana con **un solo bloque** (build, contexto, ruta, sesión, HUD, Coach,
capacidades, invariantes PASS/WARN/FAIL, últimos eventos y errores). Ctrl+A, Ctrl+C
y se pega tal cual. Es seguro de copiar: los valores secretos de Blizzard salen como
`SECRET` y no incluye nombres de personaje, GUIDs, BattleTags ni rutas locales.

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

Icono: fuente en `docs/assets/logo/`, conversión con `python tools/convert_logo.py`.

Arquitectura, API y eventos: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
Procedencia y licencia de los datos: [MitzuMPlus/DATA_SOURCES.md](MitzuMPlus/DATA_SOURCES.md).

## Licencia

MIT, ver [LICENSE](LICENSE). **Bloqueo abierto:** los datos de rutas y enemigos
derivan de Mythic Dungeon Tools (GPL-2.0). Lista exacta de ficheros y vías de
resolución en [docs/RELEASE.md §6](docs/RELEASE.md#6-bloqueo-de-licencia).
