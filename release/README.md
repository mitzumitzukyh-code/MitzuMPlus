# MitzuMPlus

**Mythic+ History & Key Prediction for World of Warcraft.**

MitzuMPlus is a lightweight Mythic+ companion focused on post-run history, player tracking, personal bests, live key prediction, and clean run summaries. It is designed to work without route-arrow modules or heavy combat-log dependence.

## Features

- Mythic+ run history with filters, sorting, pagination, favorites, notes, copy/export tools, and deletion controls.
- Player profiles built from runs you have completed with group members.
- Optional Mythic score display through the Raider.IO addon when installed.
- Personal best tracking for best key, best timed runs, performance milestones, and flawless runs.
- Live Mythic+ key prediction HUD with configurable scale, opacity, lock state, ETA, confidence, and preview mode.
- End-of-run notifications and optional chat summaries.
- Loot tracking for group loot announced during a run, with configurable minimum item quality and item level.
- Bug report window for easier live testing and issue reporting.

## Optional integrations

MitzuMPlus can use optional addons when available, but it should still load without them:

- **Raider.IO**: used to display and store Mythic score for players.
- **LibSharedMedia-3.0**: used when available for richer media/font support.

## What MitzuMPlus is not

MitzuMPlus does not automate gameplay, does not play the game for you, and does not depend on a separate route-arrow addon. Route arrows and experimental route alignment should remain in a separate development addon.

## Installation

1. Download the ZIP file.
2. Extract the `MitzuMPlus` folder into:
   `World of Warcraft/_retail_/Interface/AddOns/`
3. Restart WoW or run `/reload`.
4. Open the addon from the minimap button or use the addon commands.

## First-run checklist

- Open MitzuMPlus and check the **History**, **Statistics**, **Players**, and **Configuration** tabs.
- In Configuration, test the notification button.
- If Raider.IO is installed, open **Players** and verify that Mythic score appears where available.
- Run a Mythic+ dungeon, then confirm that the run appears in History and that player profiles update.

## Distribution status

Current build: **1.0.0-rc1** (release candidate). Recommended public file type: **Beta** first, then promote to **Release** after live validation across several Mythic+ runs.

## License

MIT. See [`LICENSE`](../LICENSE). The distributed ZIP includes the same `LICENSE` file.
