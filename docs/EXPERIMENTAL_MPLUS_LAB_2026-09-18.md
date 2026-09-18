# MitzuMPlus Experimental M+ Lab — 2026-09-18

> Experimental branch only. Do not merge into main/develop or publish to CurseForge until Retail validation.

## Baseline and isolation

- Stable user artifact: `MitzuMPlus-1.1.0-dev.12.zip`.
- Experimental branch: `experiment/mplus-lab-2026-09-18`.
- The final experimental package must preserve every dev.12 correction before adding lab features.
- Character panel (C) is explicitly out of scope for this experiment.
- Route guidance, pull navigation, MDT import and MitzuRouteArrows remain out of core.
- Never auto-activate a Mythic+ keystone after a countdown.

## Product principle

Extend Blizzard's native Mythic+ surfaces instead of replacing them.

Each addition must answer one of these questions with less friction than the stock UI:
1. What should I run next?
2. Is this group ready?
3. What does this applicant add to my group?
4. Have I played with this person before?
5. How is this key progressing right now?

Blizzard = official/current data.
Raider.IO = optional external player intelligence.
MitzuMPlus = personal history, context and workflow tools.

## Research evidence collected

### Native Mythic+ / season UI

Current addons show sustained demand for:
- per-dungeon score and best-key information in Blizzard's Mythic+ journal;
- teleport buttons directly on dungeon entries;
- exact enemy-forces information and timing context;
- low-clutter overlays rather than separate replacement windows.

Implementation reliability lessons from current addons:
- Blizzard challenge-map data may not be ready when the frame first opens;
- refresh on `CHALLENGE_MODE_MAPS_UPDATE` and defer rendering when map data is empty;
- overlays must sit above Blizzard's dungeon icon frame level;
- refresh after tab changes rather than assuming the first render is final.

### Keystone receptacle

Current addons commonly add:
- automatic keystone slotting;
- Ready Check;
- countdown controls.

Public source inspection confirms the native frame can be extended by parenting addon-owned widgets to `ChallengesKeystoneFrame`. Current API patterns include `C_PartyInfo.DoCountdown` and native keystone receptacle events.

Mitzu decision:
- Ready Check and Pull Timer are high-value.
- No automatic challenge activation after countdown.
- Avoid full consumable/readiness dashboards because dedicated addons already cover that well.
- Keep the original Activate button authoritative.

### Group Finder / applicants

Community requests repeatedly include:
- sorting applicants by official Mythic+ rating;
- dungeon-specific best key;
- quick visibility of Lust/Battle Rez/role needs;
- preserving native context-menu behavior;
- reducing list jumping and repeated cognitive scanning;
- remembering prior experience with players.

Public source inspection of modern LFG addons confirms useful current APIs:
- `C_LFGList.GetApplicantInfo(applicantID)`;
- `C_LFGList.GetApplicantMemberInfo(applicantID, memberIndex)`;
- applicant member data includes item level, roles/spec and dungeon score in current clients;
- some LFG data arrives asynchronously and should be re-read at render/tooltip time.

Mitzu differentiation:
- do not replace Raider.IO's row/player hover;
- add a tiny Mitzu history affordance only when local history exists;
- hovering the Mitzu affordance shows only local history: runs together, timed/depleted, best together, last run;
- party-needs summary should be factual composition support, never an automatic “good/bad player” verdict.

### Community pain points that should influence architecture

- LFG users repeatedly complain about constant refresh/apply/cancel loops and limited active applications. Addons cannot safely automate all of this; Mitzu should reduce scanning, not promise automation Blizzard disallows.
- Users request Lust/BRez filters and composition context.
- Users value “played with before” memory.
- Users complain when LFG addons consume excessive memory or cause FPS drops.
- API churn breaks addons week-to-week.

Engineering consequence:
- event-driven updates;
- no permanent high-frequency OnUpdate loops;
- cache only stable derived data;
- re-read async Blizzard data only at bounded render/tooltip points;
- every enhancer feature independently gated and fail-closed;
- protected actions remain user-initiated;
- compatibility mode when Raider.IO/other UI enhancers are present.

## Fresh evidence — iteration 1

Public sources checked on 2026-09-18 reinforce the same narrow opportunity rather than a full LFG replacement:

- A current Reddit M+ thread recommends filtering for leaders near the player's own rating and groups that still need the player's role, showing that the scanning problem is primarily contextual rather than a need for automatic applicant decisions.
- NZT Group exposes filters for role, Bloodlust and battle resurrection and explicitly stays read-only/local; this validates utility coverage as a useful factual signal. Its project is MIT, but Mitzu did not copy its implementation.
- LFG Mythic+ describes a companion panel centered on live party composition and missing utility, independently validating the same demand.
- OAK LFG Sorter's current changelog emphasizes combat-safe disabling of protected actions and explanatory tooltips. Its code/license is treated as reference-only; no source is copied.
- CompMatcher now advises compositions from external meta data. Mitzu intentionally does not follow that direction: Party Needs reports capabilities only and avoids meta/spec ranking.

### Implemented in iteration 1: pure PartyNeeds engine

Added `modules/Experimental/PartyNeeds.lua`, loaded after `PartyProfiler`.

The module:
- accepts normalized party/applicant records rather than reading or writing LFG itself;
- counts Tank/Healer/DPS slots;
- reports class-level Bloodlust and battle-resurrection coverage conservatively;
- reports which currently missing capabilities a candidate would add;
- emits language-neutral tokens for a later localized presenter;
- never ranks players, auto-invites, auto-declines or touches protected frames;
- has no OnUpdate loop and no SavedVariables footprint.

Class-level capability is deliberately conservative. It means “this class can provide this group utility”, not “this character has the relevant talent/pet configured right now”. The eventual UI must label it accordingly and must not overstate certainty.

Added `tests/core/PartyNeeds.spec.lua` covering empty groups, complete role/utility detection, unknown data fail-closed behavior, candidate delta coverage and language-neutral summary tokens. No user-visible strings were introduced in this iteration, so enUS/esES key parity is unchanged.

## Fresh evidence — iteration 2

Public sources checked on 2026-09-18 show the composition problem is still active in Midnight Season 2:

- A high-engagement r/wow thread describes leaders receiving very large DPS applicant queues and explicitly filling missing Bloodlust or battle resurrection first.
- Current addons NZT Group, LFGBuddy, OAK LFG Sorter and KIC LFG Sorter all expose some form of role/utility composition context. This confirms demand, but most solutions either add a full filter panel or replace/re-sort significant parts of the applicant workflow.
- PremadeGroupsQOL documents a deliberately narrow compatibility strategy: post-hook Blizzard presentation code and avoid the secure listing path. Its repository is MIT. Source inspection of `ApplicationViewer.lua` confirms a current pattern of post-hooking Blizzard applicant presentation rather than replacing protected actions. Mitzu uses that only as architectural evidence; no source was copied.
- LFM+ still lists player-history memory and utility filtering as desired/WIP functionality, reinforcing Mitzu's planned local-history differentiator.

### Implemented in iteration 2: localized, read-only Party Needs hint

Added `modules/Experimental/LFGCompositionHint.lua` plus isolated experimental locale extensions.

Behavior:
- attaches one addon-owned FontString to Blizzard's applicant viewer only after that UI exists;
- appears only while the player has an active LFG listing;
- reads the current party through `UnitExists`, `UnitClassBase`/`UnitClass` and `UnitGroupRolesAssigned`;
- delegates all composition decisions to the pure `PartyNeeds` engine;
- shows missing Tank/Healer/DPS slots plus class-level Bloodlust/Battle Rez coverage in one compact line;
- refreshes only on bounded events (`ADDON_LOADED`, `GROUP_ROSTER_UPDATE`, `PLAYER_ENTERING_WORLD`, `LFG_LIST_ACTIVE_ENTRY_UPDATE`);
- never filters, sorts, invites, declines, auto-starts, calls protected listing actions, or installs an `OnUpdate` loop;
- fails closed if the Blizzard frame, active-entry API or PartyNeeds engine is unavailable.

Localization:
- English remains the base/default locale;
- Spanish has exact key parity in `esES_Experimental.lua`;
- all visible feature text comes from AceLocale keys; dungeon/class names remain Blizzard-owned where applicable;
- `LFGCompositionHint.spec.lua` includes an explicit enUS/esES experimental-key parity gate.

Testing note: the new pure presenter tests are wired into the repository's automatic `tests/core/*.spec.lua` discovery. The automation environment used for this iteration does not contain the repository's Lupa dependency or a Lua interpreter, and outbound git clone is unavailable, so the full suite could not be executed here. This is recorded as an environment limitation, not reported as a passing test. Final packaging must run the repository suite before the ZIP is accepted.

## Candidate experimental modules

### 1. KeystoneQuickActions

Native-looking addon-owned controls anchored to the keystone receptacle:
- Ready Check;
- Pull Timer (default 10s; configurable 5/10/15);
- countdown number rendered inside the Mitzu control;
- disable/desaturate when permission/API state disallows the action;
- no automatic Activate.

### 2. ChallengesEnhancer

Minimal additions to Blizzard's Mythic+ season window:
- optional Season Goal: current / target / missing;
- per-dungeon Mitzu PB/history context when available;
- safe teleport affordance if the teleport spell is known;
- future-affix planner only if future rotation data is deterministic/reliable; inferred data must be labeled as forecast;
- never duplicate current-week affixes already shown by Blizzard.

### 3. LFGApplicantEnhancer

Preserve Blizzard applicant rows and Raider.IO hover behavior:
- sortable official rating where technically safe;
- dungeon-specific best column/indicator where API data is available;
- compact Party Needs summary (roles, Lust, Battle Rez);
- tiny `M` marker only for applicants found in Mitzu's local player history;
- Mitzu marker hover = local history only;
- no automatic invite/decline ranking.

## Explicit non-goals tonight

- Character panel modifications.
- Route arrows or automatic dungeon navigation.
- MDT route import.
- Auto-activation of the keystone.
- Copying source code from All Rights Reserved addons.
- Replacing Raider.IO tooltips.
- Automated “best applicant” decisions.
- Shipping directly to stable or CurseForge.

## Acceptance gates for the experimental ZIP

- dev.12 fixes preserved;
- no stable branch mutation;
- no protected-frame taint known from static review;
- no Lua syntax errors;
- addon loads with enhancer features disabled by default if confidence is incomplete;
- each enhancer can fail independently without breaking Blizzard UI;
- tests/static checks updated for every implemented pure-data component;
- Retail live-test checklist included with package report.
