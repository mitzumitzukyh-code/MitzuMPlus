# MitzuForeverLegacy

**Plan D**  
**Status:** Experimental / pre-beta scaffold  
**Version:** `0.1.0-dev`

A World of Warcraft: Forever account/alt planner for the new Legacy progression system.

## Why this exists

Blizzard has confirmed account-shared Legacy Points, per-character spending, three initial Legacy trees (Professions, Adventure, Resourcefulness), and repeat-journey challenges. That creates a planning problem across many alts even if the native UI is adequate for one character at a time.

## Product direction

- account-wide earned-point summary;
- per-character spend plans;
- challenge checklist;
- alt comparison;
- tree planning and saved templates;
- reminders for unspent points or unfinished account goals;
- verified data only.

## Beta validation

1. Identify the actual Legacy APIs/events, if exposed.
2. Confirm account-wide vs per-character SavedVariables needs.
3. Capture real node/challenge IDs and costs.
4. Measure what Blizzard's native UI already provides.
5. Keep the addon useful without automating gameplay.

## Opportunity gate

**Continue** if cross-alt planning/progress remains fragmented.  
**Pivot** to an alt dashboard if the native Legacy planner is already excellent.  
**Drop** if Blizzard ships complete account-level planning and searchable challenge tracking.
