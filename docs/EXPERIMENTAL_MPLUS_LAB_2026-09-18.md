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
