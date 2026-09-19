# Changelog

## 1.1.0

First stable release. MitzuMPlus now works mostly *inside* Blizzard's own
Mythic+ interface instead of beside it.

### Live run
- **Native objective tracker:** the key data is rendered inside Blizzard's own
  Mythic+ block, with a layout that degrades gracefully on narrow bars and stays
  compatible with Angry Keystones.
- **Dynamic +3 / +2 / +1 prediction:** the upgrade you are currently on track
  for, next to Blizzard's timer, with an optional confidence readout.
- **Stabilized pace:** the prediction is re-measured one loop turn after
  Blizzard finishes its layout, so it no longer flickers while text metrics
  settle.
- **Enemy Forces as `current / total`,** with the remaining count shown as
  `N remaining` / `faltan N` instead of only a percentage.
- **End-of-run summary:** one final panel owns the end of the run; completion
  and personal-best toasts are suppressed while it is on screen and
  consolidated into a single line.

### Mythic+ panel
- **Per-character season goal,** opt-in. No addon-imposed default is ever
  treated as your choice; the panel hides target/current/missing until that
  character has a goal, and shows *Goal reached* once it is met.
- **Per-dungeon Mythic+ score** on Blizzard's own dungeon cards.
- **Dungeon teleports** from the panel, with cooldown state.

### Keystone frame and group
- **Keystone auto-slot,** idempotent per receptacle opening. It never starts the
  challenge: activation stays fully manual.
- **Ready Check** and a **configurable pull timer** (5 / 10 / 20 seconds) on
  Blizzard's native keystone frame.
- **LFG utility coverage:** Heroism/Bloodlust, Brez and Soothe shown as three
  readable tiles above Blizzard's native applicant headers. No Blizzard frame is
  moved or resized, and there is no automatic invite or decline.

### Correctness and safety
- **InspectArbiter:** a single owner for proactive inspect traffic. Mitzu yields
  to Blizzard's own inspect window and never calls `ClearInspectPlayer()`, so the
  shared inspect cache is left intact.
- **History and database:** run finalization no longer duplicates entries, and
  missing Enemy Forces is reported as *No data* / *Sin datos* rather than a
  fabricated `0.0%`.
- **Localization:** the whole visible surface follows the client language.
  English (enUS/enGB and every untranslated client) and Spanish (esES/esMX).

## 1.0.0-beta.1

First public beta of MitzuMPlus, a Mythic+ companion for World of Warcraft Retail.

### Features
- **Mythic+ History:** search, filters, sorting and pagination over your recorded runs, with a detail view for each key.
- **Notes, Favorites, Copy and Delete:** annotate runs, mark favorites, copy or export run data and remove entries with confirmation.
- **Statistics:** completion rate, best key, recent results and role-based performance where the data was captured.
- **Player profiles:** the players you have grouped with, runs together, in-time rate, best key and recorded loot.
- **Puntaje mítico (optional):** shown for players when the Raider.IO addon is installed.
- **Live key prediction HUD:** discreet `+3 / +2 / +1 / OVERTIME` estimate with optional confidence and estimated finish; configurable scale, opacity, lock and preview.
- **Personal bests:** best key, timed improvements and clean runs.
- **Notifications:** floating end-of-run text colored by result, plus optional chat summaries.
- **Loot tracking:** group loot seen during a run, with minimum quality and item level filters.
- **Bug Report tooling:** a copyable, sanitized report for live testing and issue reports.

### Interface
- New MitzuMPlus icon set: "M" logo in the title bar, minimap button and addon list; icons for the History, Statistics, Players and Settings tabs; options and close buttons.
- UI polish: consistent icon sizes and spacing, header alignment, readable tab states and restrained hover effects in the dark and gold theme.
- Minimap integration through LibDBIcon: left click opens the window, right click opens the menu, and the button can be dragged or hidden.

### Scope
- MitzuRouteArrows is **not** part of this package. Experimental route arrows and route tools are kept in a separate addon.
- MitzuMPlus does not automate gameplay.
