# MitzuMPlus final product audit — local cleanup

Version inspected: `7.14.0-rc1`. No version bump, commit, push, merge, tag or release.

## Module inventory and decision

| Module | Old purpose | Current consumers | Decision | Reason |
|---|---|---|---|---|
| `Constants` | Shared limits and season metadata | Core, history services, UI | KEEP | Stable product constants |
| `Database` | Run persistence and queries | History, Stats, Players, Core | KEEP | Product authority for history |
| `DataManager` | Notes, favorites, validation, retention | History and Config | KEEP | Visible history/data operations |
| `Validation` | Validate run records | Database/DataManager | KEEP | Protects stored history |
| `RunMetrics` | Normalize stored metrics | History, Stats, Players | KEEP | Distinguishes valid/partial data |
| `PersonalBest` | PB and record calculations | Core notifications/Footer | KEEP | Visible history outcome |
| `Export` | Existing CSV/Code/copy UI | History, Config, Bug Report | KEEP | Existing export contract |
| `StaticPopups` | Destructive confirmations | History and Config | KEEP | Prevents accidental deletion |
| `EventBus` | Internal lifecycle callbacks | Runtime modules and QA | KEEP | Decouples valid product areas |
| `DungeonRegistry` | Map identity convergence | DungeonContext | SIMPLIFY | Persisted only in `MitzuMPlusDB`; route storage removed |
| `DungeonContext` | Dungeon/key lifecycle | Core, clock, tracker, QA | SIMPLIFY | Route availability and preparation removed |
| `ChallengeClock` | Server-backed key clock | Prediction and tracker | KEEP | Reliable live source and reload basis |
| `RunSession` | Session plus former progress recovery | Core and QA | SIMPLIFY | Now identity, reload and deduplication only |
| `Core` | Capture/finalize runs and legacy tracking | Product runtime | SIMPLIFY | Removed route hooks and 816 lines shadowed by Midnight tracking |
| `MidnightSafeTracking` | Supported combat-meter collection | Core, RunMetrics | KEEP | Single supported implementation |
| `KeystoneTracker` | Aggregate forces/boss/death snapshot | PredictionEngine/Core | SIMPLIFY | Route/advice integration removed |
| `PredictionEngine` | Result projection and old route hints | KeyPredictionHUD, QA | SIMPLIFY | Output limited to real aggregate inputs |
| `KeyPredictionHUD` | Replaces route Coach HUD | Config, QA, keybindings | KEEP | One discreet `+3/+2/+1/OVERTIME` view |
| `PartyProfiler` | Party identity/spec cache | Core, Players, Bug Report | SIMPLIFY | Route consumers removed; roster diagnostics retained |
| `InspectQueue` | Async party spec enrichment | PartyProfiler/Core | KEEP | Improves player profiles without inventing data |
| `SpecDatabase` | Spec/role metadata | PartyProfiler | KEEP | Player analysis |
| `LootTracker` | Capture group loot | Players profile | KEEP | Has a visible consumer and real settings |
| `RuntimeCapabilities` | Capability matrix | Bug Report | SIMPLIFY | Only final-product capabilities remain |
| `RuntimeVersion` | Runtime compatibility metadata | Initialization | KEEP | Load diagnostics |
| `ErrorLogger` | Sanitized errors/debug ring | Bug Report and QA | KEEP | User-support surface |
| `QA/SafeValue` | Secret/private value sanitization | QA modules | KEEP | Safe copying of reports |
| `QA/FlightRecorder` | Bounded lifecycle trace | Bug Report | SIMPLIFY | Route/pull subscriptions removed |
| `QA/Invariants` | Runtime consistency checks | Bug Report | SIMPLIFY | Replaced route rules with product rules |
| `QA/BugReport` | Diagnostic export | Config and `/emp bugreport` | SIMPLIFY | Final product sections only |
| `MinimapIcon` | Launcher and debug capture menu | User launcher | SIMPLIFY | Debug capture action and old branding removed |
| `Keybindings` / `Bindings.xml` | UI, progress and overlay bindings | WoW keybinding UI | SIMPLIFY | Progress bindings removed; UI/tracker remain |
| `UI_Common` | Shared frames, buttons, notifications | All panels | KEEP | Shared presentation primitives |
| `UI_SimpleDropdown` | Custom dropdown | History, Stats, Players | SIMPLIFY | Uses a clear `▼` indicator |
| `Theme`, `Colors`, `WidgetsCompat` | Visual system and compatibility | All UI | KEEP | Shared readable styling |
| `RenderizadoNuevo` | Window geometry | Init and all panels | SIMPLIFY | Responsive min/max sizing and saved dimensions |
| `Tabs` | Product navigation | Init/panels | SIMPLIFY | Exactly four final tabs |
| `Footer` | Status/debug footer | Main window | SIMPLIFY | Product summary only |
| `Panels/Historial` | Dense legacy table | User | SIMPLIFY | Rebuilt as History V2, 65/35 list/detail |
| `Panels/Stats` | Aggregate statistics | User | SIMPLIFY | Ambiguous labels replaced by explicit units |
| `Panels/Players` | Companion index/profile | User | SIMPLIFY | Success defined; unknown/truncated identities handled |
| `Panels/Config` | Mixed product/development settings | User | SIMPLIFY | Real settings grouped by product responsibility |
| `RouteSchema` | Route data schema | None in final product | REMOVE | Route system is outside product scope |
| `RouteManager` | Route loading/selection | None in final product | REMOVE | Tracker does not require routes |
| `RouteProgress` | Manual progress authority | None in final product | REMOVE | Manual progress explicitly retired |
| `RouteAdvisor` | Tactical route advice | None in final product | REMOVE | Tactical Coach is not a product feature |
| `MDTImporter` | Import MDT routes | None in final product | REMOVE | Dependency and license surface removed |
| `AdaptiveRoute/*` | Learning, navigation and progress UI | None in final product | REMOVE | Responsibility belongs to separate experiments |
| `CoachAdvice` | Tactical next-action rules | None in final product | REMOVE | Tracker predicts result only |
| `CoachHUD` / `UI_Overlay_v2` | Route/pull Coach overlays | None | REMOVE | Replaced by Key Prediction HUD |
| `Calibration` | Internal prediction sampling/debug command | None after command cleanup | REMOVE | No visible consumer; saved setting removed |
| `API/PublicAPI` | Bridge to route experiment | None in final product | REMOVE | Core must be standalone |
| `data/Routes/*` | Bundled native routes | None | REMOVE | Dead and MDT-derived distribution surface |
| `data/MDTEnemyData` | Per-enemy MDT-derived values | None | REMOVE | Dead and GPL blocker |
| `Panels/Coach` | Route/MDT/manual settings UI | None | REMOVE | Final product has no Coach tab |
| `UI/Window` | Duplicate window implementation | None | REMOVE | `RenderizadoNuevo` is the single owner |
| Ten old role/record/divider textures | Legacy presentation | None | REMOVE | No runtime references |

## Before / after

| Metric | Before | After |
|---|---:|---:|
| Lua files | 87 | 60 |
| Module Lua files | 47 | 33 |
| TOC runtime entries | 87 | 60 |
| Default SavedVariable fields | 78 | 46 |
| Slash-command branches | 63 | 11 |
| Event registrations | 51 | 21 |
| Package files | 115 | 78 |
| Package bytes, uncompressed | 1,621,919 | 971,587 |

The package is 650,332 bytes smaller (40.1%). Its compressed validation archive
is 284,059 bytes. The active addon has 77 files because the package adds the
repository `LICENSE` as its 78th member.

## SavedVariables classification

- **ACTIVE:** runs, nextRunID, personalBests, error/debug/QA rings,
  dungeonRegistry, activeRunSession, position, window/history/loot/tracker and
  notification settings.
- **LEGACY_READ_ONLY:** old route, Coach, overlay, calibration and sharing fields
  may remain in an existing user file, but the addon no longer initializes,
  reads or writes them.
- **OBSOLETE:** `MPlusAdaptiveRouteDB` is no longer declared by the product.
- **UNKNOWN:** no unknown field is used as an authority. Existing unknown keys
  are preserved rather than destructively migrated.

## Distribution flags

```text
ORPHANED_REMOVED=true
LEGACY_REMOVED=true
ROUTE_SYSTEM_PRESENT=false
ROUTEPROGRESS_PRESENT=false
ADAPTIVEROUTE_PRESENT=false
MDT_RUNTIME_PRESENT=false
MDT_DERIVED_DATA_PRESENT=false
GPL_BLOCKER_PRESENT=false
ROUTEARROWS_DEPENDENCY_PRESENT=false
COACH_TACTICAL_PRESENT=false
LOOT_TRACKER_PRESENT=true
```

Loot tracking remains because the Players profile displays recorded loot. The
source repository can still contain the separate MitzuRouteArrows experiment;
the MitzuMPlus runtime folder and package do not.

## Real bugs fixed

1. **Duplicate run finalization.** A completed challenge could be interpreted as
   a new start while Blizzard still exposed the old completion data, then write
   an identical second run. `RunSession` now persists a stable challenge identity,
   restores reloads, closes the identity on completion and rejects recycled
   completion data. The real Nalorakk +4 timing is a regression fixture. Existing
   history is not automatically deleted.
2. **History filters with omitted fields.** Programmatic/default filters whose
   keys were absent compared `nil` as if it were an active selection, producing
   an empty result. Filters now normalize all optional values.
3. **Bug Report section headings.** Both list insertions in a multiple assignment
   resolved to the same index, so the heading was overwritten. Headings are now
   appended in separate statements and covered by QA tests.

## UI result

- **History:** dense all-in-one table → compact two-row toolbar, responsive
  list/detail split, integrated result margin, selected-row accent, four detail
  views, unified export, pagination and explicit empty states.
- **Statistics:** ambiguous `Rendimiento`/`Utilidad` → explicit
  `DPS/HPS/DTPS` and `KICKS/DISPELS`, with missing data shown as `—`.
- **Players:** existing table/profile retained → success is explicitly defined as
  in-time percentage; full name/realm appears in tooltip; partial metrics stay
  visibly partial.
- **Configuration:** mixed route/development surface → General, Tracker M+,
  Interface, History/Data, Notifications, Advanced/QA and About.
- **Tracker:** route/pull/tactical Coach → compact live key-result prediction only;
  hidden outside and before a key, with optional confidence and ETA.
