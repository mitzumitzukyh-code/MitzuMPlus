# Changelog

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
