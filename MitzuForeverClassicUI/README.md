# MitzuForeverClassicUI

**Plan C**  
**Status:** Experimental / pre-beta scaffold  
**Version:** `0.1.0-dev`

A cosmetic/readability/accessibility layer for World of Warcraft: Forever, focused on players who want a more authentic Classic presentation without losing modern usability.

## Why this exists

Community discussion repeatedly asks for a true Vanilla-style interface. Blizzard has confirmed visual presets and native gamepad support, but current BlizzCon feedback indicates the available Classic-style layout does not fully recreate the original UI.

## Product direction

- Classic visual preset for unit frames, bars, cast bars and common panels where allowed;
- readable party/raid layouts;
- scalable text/buttons;
- optional accessibility presets;
- gamepad-aware layouts that complement, not replace, Blizzard's native controller support;
- no combat automation and no hidden protected-action tricks.

## Beta validation

1. Verify what Blizzard's Classic preset already covers.
2. Test protected frame restrictions in/out of combat.
3. Confirm Edit Mode hooks and layout persistence.
4. Check controller/action-targeting interactions.
5. Avoid duplicating features Blizzard already ships natively.

## Opportunity gate

**Continue** if there is sustained demand for a more authentic Classic UI and Blizzard's native preset remains incomplete.  
**Pivot** toward accessibility/layout packs if established UI addons solve full reskinning.  
**Drop** if Blizzard adds a genuine one-click Vanilla UI before launch.
