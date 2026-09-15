# MitzuForeverAtlas

**Status:** Experimental / pre-beta scaffold  
**Version:** `0.1.0-dev`  
**Target:** World of Warcraft: Forever

MitzuForeverAtlas is a data-driven dungeon atlas and preparation companion for WoW Forever. It is intentionally designed to remain useful even if combat addons are heavily restricted.

## Why this addon

Blizzard confirmed nine new dungeons for WoW Forever. BlizzCon demo reports also indicate that dungeon maps were not available in the demo, creating a practical gap for players who want navigation and preparation information without combat automation.

The addon will focus on:

- static dungeon maps and floor references;
- entrances and navigation notes;
- verified boss and loot data;
- pre-pull CC / threat preparation notes;
- profession Blueprint drops from dungeon bosses;
- optional party-preparation information that does not automate combat decisions.

## Current state

The scaffold contains the nine officially announced dungeon names, a safe UI shell, SavedVariables, and `/mfa probe` for beta capability checks. Runtime map IDs, bosses, NPC IDs, loot, coordinates, routes, and API assumptions are deliberately not guessed before beta validation.

## Commands

- `/mfa` — open/close the atlas.
- `/mfa status` — print addon status.
- `/mfa probe` — print basic client/API capability information for beta validation.

## Beta checklist

When the Forever beta opens:

1. Validate the `.toc` Interface value and `WOW_PROJECT_ID`.
2. Confirm whether `C_Map` exposes useful dungeon map/floor metadata.
3. Record dungeon map IDs and entrances.
4. Verify boss/encounter/loot data in-client or from official data.
5. Test restricted APIs inside and outside combat.
6. Keep the product useful without WeakAura-style combat computation.
7. Package only after verified Forever compatibility.

## Official references

- Blizzard — World of Warcraft: Forever What’s Next Panel Recap: https://worldofwarcraft.blizzard.com/en-us/news/24303862/world-of-warcraft-forever-whats-next-panel-recap
- Blizzard — World of Warcraft: Forever Deep Dive Panel Recap: https://worldofwarcraft.blizzard.com/en-us/news/24303313

## License

MIT. Copyright 2026 Mutzuki Mizt.
