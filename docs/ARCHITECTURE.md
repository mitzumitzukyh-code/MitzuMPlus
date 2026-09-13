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
| | `GetVersion()` | versión del addon (p. ej. `7.14.0-rc1`) |
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

## Coach HUD V2 y capa de QA (7.14)

### Grafo de estado: autoridad → eventos → vista

```
DungeonContext ──MITZU_DUNGEON_STATE_CHANGED / MITZU_DUNGEON_CHANGED──┐
RouteManager  ──MITZU_ROUTE_LOADED / UNLOADED─────────────────────────┤
RouteProgress ──MITZU_ROUTE_PREPARED / STARTED / COMPLETED────────────┤
              ──MITZU_ROUTE_RECOVERED / MITZU_PULL_CHANGED────────────┼──► CoachHUD:Refresh(reason)
Core          ──RUN_STARTED / RUN_TEARDOWN────────────────────────────┤        │  BuildModel()  (solo lectura)
WoW           ──PLAYER_ENTERING_WORLD─────────────────────────────────┘        ▼
ChallengeClock ◄── ticker de 1 s solo en RUNNING (reloj; cada 2 s modelo) ── Render(model)
RunSession / KeystoneTracker / PredictionEngine + CoachAdvice ◄── lecturas del modelo
```

- **Autoridades** (sin cambios de responsabilidad): DungeonContext (ciclo de vida),
  ChallengeClock (tiempo), RouteManager (ruta), **RouteProgress (pull)**, RunSession
  (snapshot y recuperación), PartyProfiler (grupo), PredictionEngine (proyección).
- **CoachHUD** es una vista. `BuildModel()` construye una tabla nueva en cada refresco
  leyendo a las autoridades; `Render()` la pinta con cambios diferenciales de texto.
  Solo recuerda lo que pintó (`_displayed`), que el Bug Report compara con la autoridad.
  No existe ningún `HUDCurrentPull`.
- El HUD se suscribe con prioridad 5 (después de las autoridades, 10-90); la caja
  negra con prioridad 1000 (antes que todas, para anotar causa antes que efecto).

### Visibilidad

| `DungeonContext` | Modo del HUD |
|---|---|
| `OUTSIDE`, `IN_UNSUPPORTED_DUNGEON` | `HIDDEN` |
| `PRE_KEY` | `PREPARE` (si `hud.showPreKey`) |
| `RUNNING` | `RUN` (ticker activo) |
| `COMPLETED` | `SUMMARY` durante 20 s, luego `HIDDEN` |
| `RESET` | `HIDDEN` y memoria visual limpia |

Con la vista previa (`/emp hud test`) el modelo sale de `PreviewModel()`: datos
fijos, marcados PREVIEW, sin leer ni escribir ninguna autoridad. Se apaga sola al
entrar en `RUNNING`.

**Recuperación tras /reload:** mientras RunSession tiene un snapshot sin decidir
(esperando el cronómetro del servidor), el modelo marca `recovering` y el HUD pinta
`PULL — / N · recuperando la sesión` en lugar del pull 1 provisional. En cuanto
RunSession restaura, `MITZU_PULL_CHANGED (RECOVERY)` repinta el pull real.

### Módulos

| Módulo | Papel |
|---|---|
| `modules/CoachHUD.lua` | Vista principal. Ajustes en `MitzuMPlusDB.profile.settings.hud` (enabled, locked, scale, alpha, compact, showPreKey, replaceClassic, posición). En combate aplaza escala/alfa/posición/ratón a `PLAYER_REGEN_ENABLED`. Sin plantillas seguras. |
| `modules/AdaptiveRoute/PullHUD.lua` | Adaptador: conserva `AR.PullHUD` y delega en CoachHUD. Ya no crea frame. |
| `modules/CoachAdvice.lua` | Regla única de prioridad del Coach (pura). `Evaluate(snapshot, {requireBasis})`; cada regla declara su evidencia (`TIME` o `PROJECTION`). El HUD exige base; el overlay clásico conserva su comportamiento. |
| `modules/QA/SafeValue.lua` | Saneado copy-safe: `issecretvalue` antes de tocar, `pcall` en cada conversión, `SECRET` / `UNAVAILABLE` / `REDACTED`, sin `"\|"`, sin rutas locales, BattleTags ni GUIDs. |
| `modules/QA/FlightRecorder.lua` | Caja negra: anillo de 200 entradas en `MitzuMPlusDB.global.qaFlight`, O(1), funde repetidos, sobrevive al /reload, descarta un anillo guardado corrupto. Solo hechos de alto nivel; nada de combat log. |
| `modules/QA/Invariants.lua` | `Gather()` lee el estado; `Evaluate(state)` es pura y devuelve PASS/WARN/FAIL/SKIP. |
| `modules/QA/BugReport.lua` | Informe V2: 12 secciones, cada una en su `pcall`; caja de copia de `Export` (sin auto-cierre) con caída a chat. |

Instrumentación añadida a autoridades: solo **anotaciones** (`FlightRecorder:Record`)
en RunSession, ErrorLogger y RuntimeCapabilities. Ninguna decisión cambió.

### Invariantes

| Id | Regla | Resultado si se incumple |
|---|---|---|
| `CHALLENGE_IMPLIES_RUNNING` | llave activa ⇒ `RUNNING` | FAIL; WARN durante la cuenta atrás o en `RESET` |
| `RUNNING_IMPLIES_CHALLENGE` | `RUNNING` ⇒ llave activa | FAIL |
| `ROUTE_STATE_HAS_ROUTE` | `PREPARED/ACTIVE/COMPLETED` ⇒ hay ruta | FAIL |
| `PULL_IN_RANGE` | 1 ≤ pull ≤ total | FAIL |
| `ROUTE_MATCHES_MANAGER` | RouteProgress y RouteManager, misma ruta | FAIL (WARN si el manager no tiene) |
| `OUTSIDE_NO_PROGRESS` | fuera ⇒ RouteProgress `INACTIVE` | FAIL |
| `RUNNING_ROUTE_ACTIVE` | llave con ruta ⇒ `ACTIVE` | WARN |
| `SNAPSHOT_MATCHES_PULL` | sesión decidida ⇒ snapshot = pull | WARN (el snapshot exige la huella del cronómetro) |
| `HUD_MATCHES_AUTHORITY` | HUD visible ⇒ pull pintado = RouteProgress | FAIL (SKIP en preview o recuperando) |
| `PREVIEW_NOT_DURING_RUN` | sin preview durante la llave | WARN |
| `NAVIGATOR_FOLLOWS_PROGRESS` | PullNavigator = RouteProgress | WARN |
| `NO_ROUTEARROWS_IN_CORE` | ningún módulo experimental en el core | FAIL |
| `PUBLIC_API_READ_ONLY` | `MitzuMPlusAPI` es el proxy de solo lectura | FAIL |

`Invariants.lua` es la **única** excepción a "el core no nombra módulos
experimentales": los nombra solo para `rawget(tabla, name) ~= nil`. La excepción
está acotada por `tests/run_static_checks.py` y por el test `C4`.

### Teclas de pull

`MitzuMPlus_RouteNextPullBinding` / `...PreviousPullBinding` mueven RouteProgress
cuando hay ruta (como `/emp pull`) y PullNavigator solo como respaldo. Antes movían
solo PullNavigator, y el HUD V2, que lee la autoridad, no se habría enterado.

## Pruebas

| Banco | Qué demuestra |
|---|---|
| `tests/core/CoreStandalone.spec.lua` | A: el core carga por su `.toc` y juega una llave solo · B: sin MDT (y con MDT) · C: sin módulos, globales ni referencias experimentales · H: orden del `.toc` · I: `/emp` ya no atiende comandos movidos |
| `tests/core/PublicAPI.spec.lua` | proxy de solo lectura, sin escritores, copias, eventos saneados y ordenados, aislamiento de errores |
| `tests/core/RouteData.spec.lua` | datos de ruta del core sin la fotografía física |
| `tests/core/CoachHUD.spec.lua` | A visibilidad por ciclo de vida · B refleja RouteProgress (comandos, teclas, navegador) · C no escribe autoridades · D /reload reconstruye el pull · E sin segunda autoridad · F preview sin efectos · configuración, combate, migración y ventana principal |
| `tests/core/BugReport.spec.lua` | G informe completo · H módulos nil · I errores internos y datos corruptos · J saneado · K anillo y persistencia · L invariantes con estados fabricados |
| `tests/core/BaselineRegression.spec.lua` | **regresión obligatoria** de la baseline `05a4d77` validada en vivo, detalles A y B, y llave nueva sin restauración falsa |
| `tests/routearrows/HostIsolation.spec.lua` | D: solo `MitzuMPlusAPI` · E: no puede escribir estado del core · F: resultado idéntico del core con y sin MRA · G: con/sin MitzuMPlus y con/sin Threat Plates · H: orden del `.toc` · I: barras y bindings sin colisión |
| resto de `tests/routearrows/` | Evidence, Guidance, ArrowDemo y Alignment, ya adaptados a `Host` |
| `tests/run_static_checks.py` | compilación de todo el Lua y las reglas de dependencia leídas del código |

`tests/harness/` contiene un cliente de WoW simulado (`wow_mock.lua`) que carga cada addon
por su `.toc` real, expandiendo los `.xml` de las librerías, y un escenario que entra en
Ruby Life Pools y arranca una llave (`core_scenario.lua`). `S.isolated` restaura `_G`
entre arranques, de modo que un mismo banco puede comparar dos partidas.
