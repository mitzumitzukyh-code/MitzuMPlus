# MitzuMPlus architecture

MitzuMPlus is split by product responsibility rather than by experiments.

| Area | Authorities and views |
|---|---|
| Run lifecycle | `DungeonRegistry`, `DungeonContext`, `ChallengeClock`, `Core` |
| Stable identity | `RunSession` persists one active identity, restores reloads and rejects duplicate finalization |
| History | `Database`, `DataManager`, `RunMetrics`, `PersonalBest`, `Export` |
| Party and loot | `PartyProfiler`, `InspectQueue`, `LootTracker` |
| Prediction | `KeystoneTracker`, `PredictionEngine`, `KeyPredictionHUD` |
| UI | History, Statistics, Players and Configuration panels |
| QA | `SafeValue`, `FlightRecorder`, `Invariants`, `BugReport` |

## Boundaries

The prediction tracker reads only the live dungeon context, server-backed clock
and prediction snapshot. It is a view and never changes the run lifecycle.
Its output is allowlisted to `+3`, `+2`, `+1` and `OVERTIME`.

Routes, manual progress, enemy identity, navigation, tactical advice, native
route datasets and MDT-derived datasets are outside this product. There is no
public bridge to the separate MitzuRouteArrows experiment and no optional or
required runtime dependency on it.

## Persistence

`MitzuMPlusDB.global` stores runs, personal bests, the dungeon identity registry,
QA logs and `activeRunSession`. Profile settings store presentation, notification,
history, loot and tracker preferences. Removed fields are treated as untouched
legacy data: the addon does not initialize or consume them.

## Duplicate prevention

Every live key receives an identity based on dungeon, level and the authoritative
challenge start time. Reload restores that identity. Completion marks it closed.
A repeated completion for the same identity, or recycled identical completion
data immediately after the prior run, is rejected before history is written.
Legitimate similar runs with independent start times remain valid.

## Release gates

The Lua suite covers history models, tracker models, session recovery,
deduplication, diagnostics and the product boundary. Static checks compile every
product Lua file, validate the TOC, ensure every product Lua file is loaded,
inspect commands/settings/media and reject retired runtime modules.
