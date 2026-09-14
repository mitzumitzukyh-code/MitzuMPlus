# Changelog

## 1.0.0-rc1

### Changed
- On-screen notifications are now floating text only: no panel, border, backdrop or background texture. Readability comes from a thin outline and a light shadow.
- Notification text colors by type: run completed (soft green), new record (gold), personal best (light gold), out of time (soft red).
- Short fade-in and fade-out inside the existing duration; queue, timers, position and triggers are unchanged.
- New approved icon set: Mitzu "M" logo in the title bar (24 px), minimap button and addon list; History / Statistics / Players / Settings tab icons (17 px); options (18 px) and close (19 px) title-bar buttons. The old logo and tab/button textures were removed.
- The addon folder now contains runtime files only. The ZIP carries the addon plus `LICENSE`; README, changelog, CurseForge page and the 512 px logo live in the repository `release/` folder.
- Removed the unloaded `modules/SpecDatabase.lua` scaffold from the addon folder.

### Fixed
- Long notifications such as "NUEVO RECORD! Mejor llave en ..." were cut at 80 characters. They now use up to 640 px and wrap to a second line when needed.

## 1.0.0-beta.1

Initial CurseForge beta candidate.

### Added
- Mythic+ history interface with search, filters, sorting, pagination, favorites, notes, copy/export, and delete actions.
- Player profile interface based on previous Mythic+ group members.
- Optional Mythic score display using Raider.IO when available.
- Live key prediction HUD with configurable appearance and behavior.
- End-of-run notifications and chat summaries.
- Group loot tracking with minimum quality and item level filters.
- Bug report window for live testing and issue collection.
- Original MitzuMPlus logo asset for distribution.

### Changed
- Removed an unused SpecDatabase development scaffold from the public package.
- Internal metric-source names remain available in Bug Report/QA but are no longer printed in normal run-start chat.
- Removed the placeholder CurseForge project URL until the project has a real approved page.
- Route-arrow functionality is intentionally kept out of this addon and should remain in a separate development addon.
- Player interface uses the user-facing label **Puntaje mítico** instead of the technical Raider.IO label.
- Technical data-source labels are hidden from normal UI and should remain in debug/bug reports only.

### Fixed
- Multiple History UI layout issues: truncated headers, oversized role icons, long metric numbers, and small dungeon icon presentation.
- Minimap right-click menu opacity and positioning.
- Notification placement, visibility, and queueing.
- Bug Report window layering so it opens above the main addon.
- Loot item-level filtering using detailed item level information when available.
- Filter refresh behavior and stale filter state.
