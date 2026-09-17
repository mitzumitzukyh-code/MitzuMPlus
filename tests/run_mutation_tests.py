"""Mutation gate for the Mitzu Tracker visual layer.

Every entry below breaks ONE promise the tracker makes on purpose, then checks
that the suite actually notices. A mutant that survives means the promise is
only written in a comment, not tested.

Each mutant names the guard expected to catch it: a spec (run on Lua 5.4, the
same harness as run_lua_tests.py) or tests/run_static_checks.py. The source file
is restored whatever happens, including on Ctrl+C.

    python tests/run_mutation_tests.py            # every mutant
    python tests/run_mutation_tests.py dev.9      # only the ones tagged dev.9

Mutants introduced by a release are kept forever: dev.6/dev.7/dev.8 promises
(no floating HUD during a key, one threshold, no invented data, no duplicated
percentage) are re-checked on every run alongside the dev.9 polish.
"""

from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

from lupa import LuaRuntime

NL = chr(10)
ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "MitzuMPlus" / "modules" / "Tracker"
QA = ROOT / "MitzuMPlus" / "modules" / "QA"

PRESENTER = ADDON / "TrackerPresenter.lua"
ENHANCER = ADDON / "BlizzardTrackerEnhancer.lua"
CONTROLLER = ADDON / "MitzuTracker.lua"

VISUAL = "tests/core/TrackerVisual.spec.lua"
PRESENTER_SPEC = "tests/core/TrackerPresenter.spec.lua"
STATE_SPEC = "tests/core/TrackerState.spec.lua"
LOCALE_SPEC = "tests/core/Localization.spec.lua"
HISTORY_SPEC = "tests/core/HistoryModel.spec.lua"

LOCALES = ROOT / "MitzuMPlus" / "Locales"
EN = LOCALES / "enUS.lua"
ES = LOCALES / "esES.lua"
BOOTSTRAP = ROOT / "MitzuMPlus" / "Bootstrap.lua"
TABS = ROOT / "MitzuMPlus" / "UI" / "Tabs.lua"
HISTORY = ROOT / "MitzuMPlus" / "UI" / "Panels" / "Historial.lua"
DATABASE = ROOT / "MitzuMPlus" / "modules" / "Database.lua"
PLAYERS = ROOT / "MitzuMPlus" / "UI" / "Panels" / "Players.lua"


@dataclass
class Mutant:
    tag: str
    name: str
    path: Path
    find: str
    replace: str
    specs: list[str] = field(default_factory=list)
    static: bool = False


MUTANTS: list[Mutant] = [
    # -- dev.9: the QA snapshot of the last embedded render -------------------
    Mutant(
        "dev.9", "hiding the tracker erases the QA snapshot", CONTROLLER,
        'if route ~= "EMBEDDED" or type(emb) ~= "table" or emb.active ~= true then return false end',
        'if route ~= "EMBEDDED" or type(emb) ~= "table" or emb.active ~= true then\n'
        '        self._lastEmbedded = nil\n'
        '        return false\n'
        '    end',
        specs=[VISUAL], static=True,
    ),
    Mutant(
        "dev.9", "the floating summary overwrites the QA snapshot", CONTROLLER,
        'if route ~= "EMBEDDED" or type(emb) ~= "table" or emb.active ~= true then return false end',
        'if type(emb) ~= "table" then return false end',
        specs=[VISUAL], static=True,
    ),
    Mutant(
        "dev.9", "an unhealthy / disabled render still refreshes the snapshot", CONTROLLER,
        'if emb.attachmentHealthy ~= true or not self:IsEmbeddedVisible() then return false end',
        'if emb.attachmentHealthy ~= true and not self:IsEmbeddedVisible() then return false end',
        specs=[VISUAL],
    ),
    Mutant(
        "dev.9", "a false value is stored as nil (angryKeystones, attachmentHealthy)", CONTROLLER,
        'if t == "string" or t == "number" or t == "boolean" then\n            snap[pair[1]] = v',
        'if t == "string" or t == "number" then\n            snap[pair[1]] = v',
        specs=[VISUAL],
    ),
    Mutant(
        "dev.9", "current and last render share the same field names", CONTROLLER,
        'MT.LAST_EMBEDDED_PREFIX = "lastEmbedded."',
        'MT.LAST_EMBEDDED_PREFIX = ""',
        specs=[VISUAL], static=True,
    ),
    # -- dev.9: RITMO legibility ---------------------------------------------
    Mutant(
        "dev.9", "the pace line is dimmed again during combat", ENHANCER,
        'setText(self, "pace", el.pace, paceText)',
        'setText(self, "pace", el.pace, paceText)\n    el.pace:SetAlpha(0.8)',
        specs=[VISUAL],
    ),
    Mutant(
        "dev.9", "RITMO grows into a second main timer", ENHANCER,
        '    pace      = "GameFontHighlightSmall",',
        '    pace      = "GameFontHighlightHuge",',
        specs=[VISUAL], static=True,
    ),
    Mutant(
        "dev.9", "the confidence stops being a secondary (grey) font", ENHANCER,
        '    secondary = "GameFontDisableSmall",',
        '    secondary = "GameFontHighlightSmall",',
        static=True,
    ),
    Mutant(
        "dev.9", "the confidence is kept where the pace no longer fits", PRESENTER,
        '        elseif fits(base) then\n            pc.mode = "COMPACT"',
        '        elseif fits(base) then\n            pc.mode, pc.confidence = "COMPACT", e.confidenceText',
        specs=[PRESENTER_SPEC],
    ),
    # -- dev.9: forces alignment ---------------------------------------------
    Mutant(
        "dev.9", "the remaining count is anchored to the wrong end of the bar", ENHANCER,
        'el.forcesSecondary:SetPoint("BOTTOMRIGHT", el.forcesRoot, "BOTTOMRIGHT", -L.FORCES_INSET, 0)',
        'el.forcesSecondary:SetPoint("BOTTOMLEFT", el.forcesRoot, "BOTTOMLEFT", L.FORCES_INSET, 0)',
        specs=[VISUAL],
    ),
    Mutant(
        "dev.9", "the two forces columns stop sharing one baseline", ENHANCER,
        'el.forcesPrimary:SetPoint("BOTTOMLEFT", el.forcesRoot, "BOTTOMLEFT", L.FORCES_INSET, 0)',
        'el.forcesPrimary:SetPoint("TOPLEFT", el.forcesRoot, "TOPLEFT", L.FORCES_INSET, 0)',
        specs=[VISUAL],
    ),
    Mutant(
        "dev.9", "the forces row no longer follows the real ends of the bar", ENHANCER,
        'el.forcesRoot:SetPoint("TOPRIGHT", blizzInner, "BOTTOMRIGHT", 0, L.FORCES_GAP_Y)',
        'el.forcesRoot:SetWidth(120)',
        specs=[VISUAL],
    ),
    # -- dev.9: death penalty -------------------------------------------------
    Mutant(
        "dev.9", "a sub-second penalty is painted as -0:00", PRESENTER,
        'and d.timeLost and d.timeLost >= TP.MIN_PENALTY_SECONDS then',
        'and d.timeLost and d.timeLost >= 0 then',
        specs=[PRESENTER_SPEC],
    ),
    Mutant(
        "dev.9", "the death count is repeated next to Blizzard's own", PRESENTER,
        'e.penaltyText = "-" .. TP.FormatClock(d.timeLost)',
        'e.penaltyText = floor(d.count) .. "  -" .. TP.FormatClock(d.timeLost)',
        specs=[PRESENTER_SPEC, VISUAL],
    ),
    Mutant(
        "dev.9", "Mitzu writes into Blizzard's death counter", ENHANCER,
        'el.penalty:SetPoint("RIGHT", blizzDeath, "LEFT", -2, 0)',
        'blizzDeath:SetAlpha(0.5)',
        specs=[VISUAL], static=True,
    ),
    # -- dev.9: Angry Keystones coexistence -----------------------------------
    Mutant(
        "dev.9", "Mitzu repeats the threshold while Angry Keystones shows it", PRESENTER,
        '    elseif sp.deferThreshold then\n        th.mode = "DEFERRED"',
        '    elseif sp.deferThreshold and false then\n        th.mode = "DEFERRED"',
        specs=[PRESENTER_SPEC, VISUAL],
    ),
    Mutant(
        "dev.9", "the forces percentage is duplicated under the bar", PRESENTER,
        'if o.showForcesRemaining ~= false then e.forcesSecondary = f.remainingText end',
        'if o.showForcesRemaining ~= false then e.forcesSecondary = f.percentText end',
        specs=[PRESENTER_SPEC, VISUAL], static=True,
    ),
    # -- dev.9: Blizzard's frames are read-only, our lines are text-only ------
    Mutant(
        "dev.9", "Mitzu re-anchors Blizzard's forces StatusBar", ENHANCER,
        'el.forcesRoot:SetPoint("TOPLEFT", blizzInner, "BOTTOMLEFT", 0, L.FORCES_GAP_Y)',
        'blizzInner:SetPoint("TOPLEFT", el.forcesRoot, "BOTTOMLEFT", 0, L.FORCES_GAP_Y)',
        specs=[VISUAL], static=True,
    ),
    Mutant(
        "dev.9", "the embedded lines get a background of their own", ENHANCER,
        '    root:Hide(); forcesRoot:Hide()',
        '    root:CreateTexture(nil, "BACKGROUND"):SetColorTexture(0, 0, 0, 0.5)\n    root:Hide(); forcesRoot:Hide()',
        static=True,
    ),
    # -- dev.6 / dev.7 / dev.8 promises, kept forever -------------------------
    Mutant(
        "dev.7", "a floating HUD comes back during a real key", CONTROLLER,
        'PENDING = "EMBEDDED", RUNNING = "EMBEDDED", COMPLETING = "EMBEDDED",',
        'PENDING = "EMBEDDED", RUNNING = "FLOATING", COMPLETING = "EMBEDDED",',
        specs=[VISUAL], static=True,
    ),
    Mutant(
        "dev.7", "duplicate post-hooks on every Blizzard layout", ENHANCER,
        'if blizzBlock and self._hookedBlock ~= blizzBlock and type(get(blizzBlock, "Activate")) == "function" then',
        'if blizzBlock and type(get(blizzBlock, "Activate")) == "function" then',
        specs=[VISUAL],
    ),
    Mutant(
        "dev.8", "a lost threshold is still offered as the next one", PRESENTER,
        'if seg.left and not seg.lost then return { upgrade = seg.code, time = seg.left } end',
        'if seg.left then return { upgrade = seg.code, time = seg.left } end',
        specs=[PRESENTER_SPEC, VISUAL],
    ),
    Mutant(
        "dev.8", "secondary data survives where the threshold did not fit", PRESENTER,
        'if e.paceText and th.mode ~= "TOO_NARROW" then',
        'if e.paceText then',
        specs=[PRESENTER_SPEC, VISUAL],
    ),
    Mutant(
        "dev.6", "an unknown engine result is painted as a reassuring +1", PRESENTER,
        'local code = type(result) == "string" and TP.RESULT_CODE[result] or nil',
        'local code = type(result) == "string" and TP.RESULT_CODE[result] or "+1"',
        specs=[PRESENTER_SPEC],
    ),
    # -- dev.10: the addon must speak the client's language, always ----------
    Mutant(
        "dev.10", "RITMO comes back hardcoded instead of a locale key", PRESENTER,
        '    PACE         = "TRACKER_PACE",',
        '    PACE         = "RITMO_HARDCODED",',
        specs=[LOCALE_SPEC], static=True,
    ),
    Mutant(
        "dev.10", "the tab bar writes Spanish straight into the UI", TABS,
        'text = L["TABBAR_HISTORY"],',
        'text = "HISTORIAL",',
        specs=[LOCALE_SPEC], static=True,
    ),
    Mutant(
        "dev.10", "English stops being the default locale (deDE would get nothing)", EN,
        'NewLocale("MitzuMPlus", "enUS", true)',
        'NewLocale("MitzuMPlus", "enUS")',
        specs=[LOCALE_SPEC], static=True,
    ),
    Mutant(
        "dev.10", "enGB stops being served by the English fallback", BOOTSTRAP,
        'MitzuMPlus.L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)',
        'MitzuMPlus.L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)'
        + NL + 'if GetLocale() == "enGB" then MitzuMPlus.L = setmetatable({}, { __index = function(_, k) return k end }) end',
        specs=[LOCALE_SPEC], static=True,
    ),
    Mutant(
        "dev.10", "a Spanish translation goes missing", ES,
        'L["TRACKER_FORCES"]        = "Fuerzas enemigas"',
        '-- L["TRACKER_FORCES"] = "Fuerzas enemigas"',
        specs=[LOCALE_SPEC], static=True,
    ),
    Mutant(
        "dev.10", "a key goes missing from the canonical English file", EN,
        'L["TRACKER_REMAINING"]     = "%s remaining"',
        '-- L["TRACKER_REMAINING"] = "%s remaining"',
        specs=[LOCALE_SPEC], static=True,
    ),
    Mutant(
        "dev.10", 'the English UI shows "faltan" through a mistranslated key', EN,
        'L["TRACKER_REMAINING"]     = "%s remaining"',
        'L["TRACKER_REMAINING"]     = "faltan %s"',
        specs=[LOCALE_SPEC],
    ),
    Mutant(
        "dev.10", "a manual language selector appears", BOOTSTRAP,
        'MitzuMPlus.FALLBACK_LOCALE = "enUS"',
        'MitzuMPlus.FALLBACK_LOCALE = "enUS"' + NL
        + 'MitzuMPlus.settings = { locale = "esES" }' + NL
        + 'function MitzuMPlus:SetLocale(v) self.settings.locale = v end',
        static=True,
    ),
    Mutant(
        "dev.10", "the runtime stores translated text instead of an ID", DATABASE,
        '        seasonKey = string.format("exp%d_s%d", expansionLevel, seasonID),',
        '        seasonKey = string.format("exp%d_s%d", expansionLevel, seasonID),' + NL
        + '        seasonName = string.format("%s - Temporada %d", "Expansion", seasonID),',
        static=True,
    ),
    Mutant(
        "dev.10", "a run result becomes a translated word again, so filters break", HISTORY,
        'local code = run.inTime and (levels >= 3 and "+3" or (levels == 2 and "+2" or "+1")) or "OUT"',
        'local code = run.inTime and (levels >= 3 and "+3" or (levels == 2 and "+2" or "+1")) or L["RESULT_OUT"]',
        specs=[HISTORY_SPEC, LOCALE_SPEC], static=True,
    ),
    Mutant(
        "dev.10", "the preview title stops going through the translator", PRESENTER,
        '    PREVIEW      = "TRACKER_PREVIEW",',
        '    PREVIEW      = "VISTA PREVIA",',
        specs=[LOCALE_SPEC], static=True,
    ),
    Mutant(
        "dev.10", "the summary title stops going through the translator", PRESENTER,
        '    KEY_COMPLETE = "TRACKER_KEY_COMPLETE",',
        '    KEY_COMPLETE = "LLAVE COMPLETADA",',
        specs=[LOCALE_SPEC], static=True,
    ),
    Mutant(
        "dev.10", "a settings row shows a raw locale key to the player", ES,
        'L["CFG_SHOW_PACE"]         = "Mostrar ritmo"',
        'L["CFG_SHOW_PACE"]         = "CFG_SHOW_PACE"',
        specs=[LOCALE_SPEC],
    ),
    Mutant(
        "dev.10", "class names are translated by hand instead of read from Blizzard", PLAYERS,
        'local male = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")',
        'local male = { PALADIN = "Paladin de la Luz" }',
        static=True,
    ),
    Mutant(
        "dev.10", "a format specifier changes between languages (%d -> %s)", ES,
        'L["POPUP_DELETE_RUN"]        = "\u00bfEliminar run #%d? Esta acci\u00f3n no se puede deshacer."',
        'L["POPUP_DELETE_RUN"]        = "\u00bfEliminar run #%s? Esta acci\u00f3n no se puede deshacer."',
        specs=[LOCALE_SPEC],
    ),
    Mutant(
        "dev.6", "bosses are inferred without the official completion event", PRESENTER,
        'if terminal and s.bossCountSource == "INFERRED_FROM_COMPLETION_EVENT" and num(s.bossesCompletedFinal) then',
        'if terminal and num(s.bossesCompletedFinal) then',
        specs=[PRESENTER_SPEC, STATE_SPEC, VISUAL],
    ),
]


def run_spec(spec: str) -> bool:
    """True when the spec passes."""
    try:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute((ROOT / spec).read_text(encoding="utf-8"))
        return True
    except Exception:
        return False


def run_static() -> bool:
    result = subprocess.run([sys.executable, str(ROOT / "tests" / "run_static_checks.py")],
                            cwd=ROOT, capture_output=True, text=True)
    return result.returncode == 0


def detect(mutant: Mutant) -> str | None:
    """The first guard that notices the mutant, or None if it survives."""
    if mutant.static and not run_static():
        return "static checks"
    for spec in mutant.specs:
        if not run_spec(spec):
            return Path(spec).stem
    return None


def main() -> None:
    wanted = sys.argv[1] if len(sys.argv) > 1 else None
    mutants = [m for m in MUTANTS if wanted is None or m.tag == wanted]
    if not mutants:
        raise SystemExit(f"no mutants tagged {wanted!r}")

    survivors, detected = [], 0
    for mutant in mutants:
        original = mutant.path.read_text(encoding="utf-8")
        if original.count(mutant.find) != 1:
            survivors.append(f"[{mutant.tag}] {mutant.name}: the mutated source no longer exists "
                             f"({original.count(mutant.find)} matches in {mutant.path.name})")
            continue
        mutant.path.write_text(original.replace(mutant.find, mutant.replace), encoding="utf-8")
        try:
            caught = detect(mutant)
        finally:
            mutant.path.write_text(original, encoding="utf-8")
        if caught:
            detected += 1
            print(f"DETECTED [{mutant.tag}] {mutant.name}  ->  {caught}")
        else:
            survivors.append(f"[{mutant.tag}] {mutant.name}: SURVIVED ({mutant.path.name})")

    total = len(mutants)
    print(f"Mutation: {detected}/{total} detected, {len(survivors)} survivors")
    if survivors:
        for line in survivors:
            print(line)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
