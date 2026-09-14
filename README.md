# MitzuMPlus

**Mythic+ History & Key Prediction** for World of Warcraft Retail.

MitzuMPlus keeps a local history of Mythic+ runs, turns that history into clear
statistics and player profiles, and displays a discreet live prediction of the
likely key result: **+3, +2, +1 or OVERTIME**.

## Product areas

- **History:** searchable, filterable run list with selection, detail, notes,
  group data, existing metrics, export and pagination.
- **Statistics:** completion rate, best key, valid-data coverage, recent results
  and role-specific DPS/HPS/DTPS where those values were captured.
- **Players:** runs together, in-time success rate, best key, deaths, interrupts,
  last appearance and recorded loot.
- **Key prediction:** elapsed time, prediction, optional confidence and ETA.
- **Configuration and QA:** real settings only, sanitized Bug Report and product
  invariants.

The addon does not provide routes, pull navigation, enemy guidance or tactical
advice. It has no runtime dependency on Mythic Dungeon Tools or MitzuRouteArrows.

## Commands

- `/emp` — open or close MitzuMPlus.
- `/emp historial|stats|jugadores|config` — open a product tab.
- `/emp tracker on|off|preview|lock|unlock|scale|alpha|reset|status` — tracker controls.
- `/emp bugreport` — create a sanitized diagnostic report.
- `/emp help` and `/emp version` — help and build information.

## Local data

User data lives only in `MitzuMPlusDB`. Existing historical records are read
without destructive migration. Obsolete settings may remain in an existing
SavedVariables file but are no longer initialized, read or written.

## Development checks

```text
python tests/run_lua_tests.py
python tests/run_static_checks.py
git diff --check
python tools/package_mitzumplus.py --check
```

The packaging command creates one validation archive containing only the
`MitzuMPlus/` runtime folder and the MIT license. It does not upload or publish.

Release material that must not ship inside the addon folder (player README,
public changelog, CurseForge page draft and the 512 px logo) lives in `release/`.
See `docs/RELEASE.md`.

## License

MIT. See [LICENSE](LICENSE). The distributable product contains no bundled route
data or MDT-derived enemy data.
