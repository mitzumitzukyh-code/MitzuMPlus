# MitzuForeverProfessions

**Plan B**  
**Status:** Experimental / pre-beta scaffold  
**Version:** `0.1.0-dev`

A World of Warcraft: Forever companion for professions and Camping.

## Why this exists

Blizzard has officially announced more than 600 new recipes, profession-specific Camping objects, utility/buff stations, and advanced Blueprint recipes from specific dungeon bosses. This creates a durable information/planning problem that is largely outside combat-addon restrictions.

## Product direction

- recipe and material tracker;
- Blueprint source tracker;
- dungeon boss -> Blueprint lookup;
- Camping object catalog;
- party-buff planning that avoids duplicate class/camp buffs;
- profession progression checklist;
- verified data only.

## Beta validation

1. Verify `.toc` Interface/project identity.
2. Probe `C_TradeSkillUI`, item/container APIs and any Camping-related APIs.
3. Capture real recipe/Blueprint IDs and sources.
4. Determine what Blizzard already surfaces natively.
5. Build only the missing planning/search layer.

## Opportunity gate

**Continue** if recipe/Blueprint/Camping discovery remains fragmented or hard to search.  
**Pivot** if Blizzard exposes complete native planning/search.  
**Drop** if a dominant Forever-specific addon fully solves this before launch.

No combat automation and no speculative IDs/data.
