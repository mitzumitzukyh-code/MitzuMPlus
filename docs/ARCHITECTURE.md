# Arquitectura

## Antes y después de la separación

### Antes (7.12, carpeta `MitzuMPlus_Historial`)

Un único addon. El código experimental de guía visual vivía dentro del producto:

```
MitzuMPlus_Historial.toc
├── modules/                          core (DungeonContext, RouteManager, RouteProgress, RunSession, Coach...)
├── modules/GuidanceEngine.lua        ┐
├── modules/RouteArrowPresenter.lua   │
├── modules/AdaptiveRoute/            │  experimental, cargado SIEMPRE por el producto:
│   ├── RouteArrows, PullUnitResolver │  flechas, placas (Threat Plates...), resolutores,
│   ├── NameplateAnchorProvider, ...  │  Evidence Layer, Alignment y ArrowDemo, mezclados
│   ├── *Evidence, PhysicalGroup*     │  con los módulos adaptativos del core
│   ├── RouteSignature, RouteAlignment│
│   └── ArrowDemo, ArrowDemoTelemetry ┘
├── data/MDTPhysicalGroupData.lua     solo lo usaba la capa experimental
└── Init.lua                          /emp con ~70 comandos, 23 de ellos experimentales
```

Acoplamientos que había que cortar (auditados en el código, no supuestos por nombre):

| Dónde (core) | Qué hacía con código experimental |
|---|---|
| `modules/RuntimeCapabilities.lua` | sondeaba `RouteArrows._lastAnchor` para el informe de capacidades |
| `modules/RouteManager.lua` | `GetPullSignature` para el alignment |
| `modules/Keybindings.lua` + `Bindings.xml` | tecla `MARK_TARGET` y `PullUnitResolver:ResolveCurrentPull` al mover el pull |
| `modules/AdaptiveRoute/Bootstrap.lua` | `PullUnitResolver:Clear` / `RouteArrows:ClearAll` en el ciclo de la run; líneas de estado de flechas |
| `modules/AdaptiveRoute/ProfileManager.lua` | ajustes de flechas en `MPlusAdaptiveRouteDB` |
| `modules/AdaptiveRoute/DataStructure.lua` | índice físico desde `MDTPhysicalGroupData` |
| `Init.lua` | 23 comandos experimentales y `_VisibleNameplates` |
| `modules/EventBus.lua` | `_G.MitzuMPlusEventBus`: bus del core escribible desde cualquier addon |

Y en sentido contrario, lo que la capa experimental leía del core: `RouteProgress`
(`GetRoute`, `GetPullIndex`, `GetPullCount`, `GetState`, `GetCurrentPull`),
`RouteManager:GetActiveRoute`, `DungeonContext` (estado, mapa, nivel, nombre),
`ChallengeClock`, `DataStructure` (`Get`, `EnemiesOf`), `PullNavigator:GetCurrentPull`,
`ProfileManager` (`GetContext`, `Settings`), `MDTEnemyData`, `NativeRouteDB`,
`EventBus:On`, `Print`, `Export:CopyToClipboard` y `MPlusAdaptiveRouteDB.arrowDemo`.

### Después

```
MitzuMPlus/  (producto)                          MitzuRouteArrows/  (experimental)
├── MitzuMPlus.toc                               ├── MitzuRouteArrows.toc
├── modules/  core                               ├── Core/
│   ├── RouteManager, RouteProgress, RunSession  │   ├── Bootstrap.lua  espacio de nombres, DB propia, estado del host
│   ├── DungeonContext, ChallengeClock, Coach... │   ├── Host.lua       fachada de SOLO LECTURA sobre MitzuMPlusAPI
│   └── AdaptiveRoute/ (Bootstrap, DataStructure,│   ├── CopyBox.lua    caja de exportación propia
│       EventTracker, ProfileManager, PullHUD,   │   ├── Lifecycle.lua  limpieza de flechas por eventos públicos
│       PullNavigator, SolverAlgorithm)          │   └── Commands.lua   /mra
├── data/  rutas nativas y enemigos              ├── Data/MDTPhysicalGroupData.lua
├── UI/  Locales/  Media/  libs/                 ├── Evidence/   8 módulos
├── API/PublicAPI.lua   ──── MitzuMPlusAPI ────► ├── Modules/    flechas, placas, resolutores, Guidance, ArrowDemo
└── Init.lua  /emp                               └── Alignment/  RouteSignature, episodios, scorer, RouteAlignment
```

- El core **no nombra** ningún módulo experimental, ni `MitzuRouteArrows`, ni Threat Plates.
- MitzuRouteArrows **no nombra** `MitzuMPlus`, sus SavedVariables ni `LibStub`/AceAddon.
  Solo localiza `MitzuMPlusAPI`, y en un único sitio (`Core/Bootstrap.lua`, `MRA:GetAPI()`).
- `docs/archive/NameplateHooks.lua` es el antiguo marcado `[SKIP]` sobre placas, que
  ya no cargaba ningún `.toc`; se conserva como referencia fuera de los addons.

Ambas reglas las verifican `tests/run_static_checks.py` y los bancos
`tests/core/CoreStandalone.spec.lua` y `tests/routearrows/HostIsolation.spec.lua`.

## MitzuMPlusAPI

`MitzuMPlus/API/PublicAPI.lua`. Contrato versión `1` (`GetAPIVersion()`), independiente de la versión del addon.

**Garantías**

- Solo getters. No hay ninguna función que escriba.
- Las tablas se devuelven como **copias profundas** sin metatablas ni funciones.
- `_G.MitzuMPlusAPI` es un proxy: asignar un campo lanza `MitzuMPlusAPI es de solo lectura`
  y `getmetatable` devuelve `false`.
- Si el core no está listo o algo falla, devuelve `nil`; nunca propaga un error al consumidor.
- Los callbacks reciben solo escalares y se ejecutan **después** de todos los manejadores
  del core. El error de un callback se queda en el consumidor (no aparece como error de MitzuMPlus).

**No es** una barrera de seguridad: en WoW todos los addons comparten el entorno Lua y
`_G.MitzuMPlus` sigue existiendo. La garantía de que MitzuRouteArrows no escribe se
sostiene en que la API no ofrece cómo hacerlo y en las comprobaciones estáticas.

### Funciones

| Grupo | Función | Devuelve |
|---|---|---|
| Identidad | `GetAPIVersion()` | número de contrato |
| | `GetVersion()` | versión del addon (`7.13.0-rc1`) |
| | `IsReady()` | `true` cuando la base de datos del core existe |
| Mazmorra | `IsChallengeActive()` | booleano |
| | `GetDungeonState()` | `OUTSIDE` / `IN_UNSUPPORTED_DUNGEON` / `PRE_KEY` / `RUNNING` / `COMPLETED` / `RESET` |
| | `GetCurrentDungeonKey()` | clave de mazmorra (texto, p. ej. `"399"`) |
| | `GetChallengeMapID()` · `GetKeystoneLevel()` · `GetDungeonName()` | escalares |
| | `GetChallengeElapsed()` · `GetChallengeStartedAt()` | tiempo de `ChallengeClock` |
| Ruta | `GetRouteRevision()` | sube cuando `RouteProgress` cambia de tabla de ruta |
| | `GetCurrentRouteID()` · `GetCurrentPull()` · `GetPullCount()` · `GetRouteState()` | escalares |
| | `GetCurrentRoute()` · `GetActiveRoute()` | copia de la ruta (MitzuRoute v1) |
| | `GetCurrentPullData()` · `GetPullData(i)` | copia de un pull |
| | `GetRouteProgress()` | `{ routeID, state, pull, pullCount, recovered }` nueva |
| Ruta adaptativa | `GetNavigatorPull()` · `GetNavigatorPullCount()` | contador de `PullNavigator` |
| | `GetAdaptiveRouteRevision()` · `GetAdaptiveRouteIndex()` · `GetAdaptiveEnemiesOf(i)` | índice de `DataStructure` (copia) |
| | `GetProfileContext()` | copia del contexto de perfil |
| Datos | `GetEnemySnapshot(mdtDungeonIdx)` · `GetEnemySnapshotRevision(idx)` | datos de enemigos empaquetados (copia) |
| | `GetNativeRouteKeys()` · `GetNativeRoutesForDungeon(key)` | rutas nativas (copia) |
| Jugador | `GetPlayerRole()` · `GetPlayerSpec()` | rol; specID y nombre |
| Eventos | `GetEvents()` · `RegisterCallback(evento, fn, prioridad)` · `UnregisterCallback(id)` | ver abajo |

### Eventos

| Evento público | Evento interno | Argumentos |
|---|---|---|
| `KEY_STARTED` · `KEY_COMPLETED` · `KEY_RESET` | `MITZU_KEY_*` | — |
| `DUNGEON_STATE_CHANGED` | `MITZU_DUNGEON_STATE_CHANGED` | nuevo, anterior |
| `ROUTE_STARTED` · `ROUTE_UNLOADED` | `MITZU_ROUTE_*` | routeID |
| `ROUTE_RECOVERED` | `MITZU_ROUTE_RECOVERED` | routeID, pull |
| `PULL_CHANGED` | `MITZU_PULL_CHANGED` | pull, anterior, motivo |
| `RUN_TEARDOWN` | `RUN_TEARDOWN` | motivo |
| `NAVIGATOR_PULL_CHANGED` | `PullNavigator:OnChange` | pull, total |

Los eventos internos pasan objetos del core (la propia ruta, módulos con `SetPull`...).
La API los reduce a escalares. `priority` (0–100) solo ordena entre consumidores; se
registran en el `EventBus` con `priority/1000`, por debajo de las prioridades enteras
(10–90) del core.

`RouteProgress` es la única autoridad del pull. `PullNavigator` es un contador aparte que
las teclas de siguiente/anterior pull mueven directamente; se expone como vista del
navegador, sin fingir que es lo mismo.

## MitzuRouteArrows por dentro

- **`Core/Bootstrap.lua`** — `_G.MitzuRouteArrows`. Estado del host: `OK`, `NOT_READY`,
  `INCOMPATIBLE` (contrato distinto de `REQUIRED_API_VERSION`), `MISSING`.
  `CanOperate()` es la puerta de todos los comandos salvo `status` y `help`. En
  `PLAYER_LOGIN` avisa una vez si falta MitzuMPlus.
- **`Core/Host.lua`** — fachada anticorrupción. Los módulos experimentales se escribieron
  contra `RouteProgress:GetPullIndex()`, `DungeonContext:GetState()`, etc. `Host` ofrece
  esos mismos nombres, solo lectores, implementados sobre `MitzuMPlusAPI`, con cachés
  invalidadas por revisión (`GetRouteRevision`, `GetAdaptiveRouteRevision`,
  `GetEnemySnapshotRevision`). Las copias en caché son compartidas dentro del addon y se
  tratan como solo lectura.
  `Host.EventBus` solo tiene `On`: traduce los nombres internos a los públicos y deja en
  espera lo que se pida antes de que exista la API.
- **`Core/Lifecycle.lua`** — lo que antes hacía el core por estos módulos: limpiar
  asignaciones al arrancar la llave, quitar flechas al terminar/resetear/desmontar la run y
  recolocar asignaciones cuando se mueve el navegador. Tecla `MITZUMPLUS_ROUTE_MARK_TARGET`
  (mismo nombre de binding que tenía, para conservar la tecla asignada).
- **`Core/Commands.lua`** — `/mra` y `/mitzuroutearrows`. No reasigna `SlashCmdList`.
- **SavedVariables** — `MitzuRouteArrowsDB` (ajustes de flechas y telemetría de ArrowDemo).

## Pruebas

| Banco | Qué demuestra |
|---|---|
| `tests/core/CoreStandalone.spec.lua` | A: el core carga por su `.toc` y juega una llave solo · B: sin MDT (y con MDT) · C: sin módulos, globales ni referencias experimentales · H: orden del `.toc` · I: `/emp` ya no atiende comandos movidos |
| `tests/core/PublicAPI.spec.lua` | proxy de solo lectura, sin escritores, copias, eventos saneados y ordenados, aislamiento de errores |
| `tests/core/RouteData.spec.lua` | datos de ruta del core sin la fotografía física |
| `tests/routearrows/HostIsolation.spec.lua` | D: solo `MitzuMPlusAPI` · E: no puede escribir estado del core · F: resultado idéntico del core con y sin MRA · G: con/sin MitzuMPlus y con/sin Threat Plates · H: orden del `.toc` · I: barras y bindings sin colisión |
| resto de `tests/routearrows/` | Evidence, Guidance, ArrowDemo y Alignment, ya adaptados a `Host` |
| `tests/run_static_checks.py` | compilación de todo el Lua y las reglas de dependencia leídas del código |

`tests/harness/` contiene un cliente de WoW simulado (`wow_mock.lua`) que carga cada addon
por su `.toc` real, expandiendo los `.xml` de las librerías, y un escenario que entra en
Ruby Life Pools y arranca una llave (`core_scenario.lua`). `S.isolated` restaura `_G`
entre arranques, de modo que un mismo banco puede comparar dos partidas.
