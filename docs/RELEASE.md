# Local release-candidate checklist

Current candidate: `7.14.0-rc1`. This cleanup does not change the version and is
not authorization to publish.

## Runtime contract

- One addon folder and one TOC: `MitzuMPlus/MitzuMPlus.toc`.
- No required dependencies.
- Optional dependency: `LibSharedMedia-3.0` only.
- SavedVariables: `MitzuMPlusDB` only.
- Official icons: the approved `Media/Icons/` set (`mitzu_logo_*`, `tab_*_64`, `btn_*_64`); the addon list uses `mitzu_logo_small_32.tga`.
- No route modules, route datasets, MDT-derived datasets or MitzuRouteArrows files.
- Package license: MIT; `GPL_BLOCKER_PRESENT=false` for this package.

## Validation before publication

1. Run the complete product Lua suite.
2. Run static checks and `git diff --check`.
3. Validate the package archive and inspect its member list.
4. Complete the five-step live test from the cleanup report, including a reload
   during an active key and one real completion.
5. Inspect the generated Bug Report for zero errors and zero failed invariants.

Publishing, tagging, merging and pushing require separate explicit authorization.
