# Local release-candidate checklist

Current candidate: `1.1.0` (first stable release). This checklist is not authorization to publish.

The version lives in `## Version` of `MitzuMPlus/MitzuMPlus.toc`; the packager
names the ZIP from it, and `tests/run_static_checks.py` checks that this file,
`release/CHANGELOG.md`, `release/CURSEFORGE_PAGE.md` and the root `CHANGELOG.md`
name the same version.

## Runtime contract

- One addon folder and one TOC: `MitzuMPlus/MitzuMPlus.toc`.
- The addon folder holds runtime files only (`.lua`, `.toc`, `.xml`, `.tga`,
  `.blp`, audio, fonts, `libs/LICENSE.txt`). No Markdown, PNG or loose `LICENSE`.
- No required dependencies.
- Optional dependency: `LibSharedMedia-3.0` only.
- SavedVariables: `MitzuMPlusDB` only.
- Official icons: the approved `Media/Icons/` set (`mitzu_logo_*`, `tab_*_64`, `btn_*_64`); the addon list uses `mitzu_logo_small_32.tga`.
- No route modules, route datasets, MDT-derived datasets or MitzuRouteArrows files.
- Package license: MIT; `GPL_BLOCKER_PRESENT=false` for this package.

## Package layout

`python tools/package_mitzumplus.py --check` builds `dist/MitzuMPlus-<version>.zip`
with a single `MitzuMPlus/` folder: the runtime files plus the root `LICENSE`.
The ZIP carries no README or changelog; CurseForge shows its own description and
file changelog.

Release material outside the runtime folder, in `release/`:

- `README.md`: player-facing readme (features, installation, first-run checks).
- `CHANGELOG.md`: public changelog to paste into the CurseForge file upload.
- `CURSEFORGE_PAGE.md`: project page draft.
- `assets/MitzuMPlus_Logo_512.png`: project avatar/logo for CurseForge.

## Validation before publication

1. Run the complete product Lua suite.
2. Run static checks and `git diff --check`.
3. Validate the package archive and inspect its member list.
4. Complete the five-step live test from the cleanup report, including a reload
   during an active key and one real completion.
5. Inspect the generated Bug Report for zero errors and zero failed invariants.

Publishing, tagging, merging and pushing require separate explicit authorization.
