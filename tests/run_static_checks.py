"""Static release gate for the MitzuMPlus CurseForge product."""
from pathlib import Path
import re
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "MitzuMPlus"
TOC = ADDON / "MitzuMPlus.toc"
RUNTIME_SUFFIXES = {".lua", ".xml", ".toc", ".tga", ".blp", ".ogg", ".mp3", ".ttf", ".otf"}
RETIRED_NAMES = {"RouteSchema.lua", "RouteManager.lua", "RouteProgress.lua", "RouteAdvisor.lua",
    "MDTImporter.lua", "MDTEnemyData.lua", "CoachAdvice.lua", "CoachHUD.lua",
    "UI_Overlay_v2.lua", "PublicAPI.lua", "Coach.lua", "Window.lua", "Calibration.lua"}
FORBIDDEN_DIRS = {"AdaptiveRoute", "Routes", "Evidence", "Alignment"}

class Checks:
    def __init__(self): self.count, self.failures = 0, []
    def check(self, value, message):
        self.count += 1
        if not value: self.failures.append(message)

def read(path): return path.read_text(encoding="utf-8-sig")
def relative(path): return path.relative_to(ROOT).as_posix()
def toc_files():
    return [line.strip().replace("\\", "/") for line in read(TOC).splitlines()
            if line.strip() and not line.lstrip().startswith("#")]
def metadata():
    return {m.group(1): m.group(2).strip() for m in
            re.finditer(r"^##\s*([\w-]+)\s*:\s*(.*?)\s*$", read(TOC), re.MULTILINE)}

def compile_lua(c):
    lua = LuaRuntime(unpack_returned_tuples=True)
    compile_one = lua.eval("function(s,n) local f,e=load(s,n); return f~=nil,e end")
    files = sorted(p for p in ADDON.rglob("*.lua") if "libs" not in p.relative_to(ADDON).parts)
    tests = sorted((ROOT / "tests" / "core").glob("*.spec.lua"))
    # Pending specs (contracts for later phases) must at least parse.
    tests += sorted((ROOT / "tests" / "pending").glob("*.spec.lua"))
    for path in files + tests:
        ok, error = compile_one(read(path), "@" + relative(path))
        c.check(ok, f"{relative(path)}: {error}")
    return files

def check_manifest(c, lua_files):
    meta, entries = metadata(), toc_files()
    c.check(meta.get("Title") == "MitzuMPlus", "TOC title is not MitzuMPlus")
    c.check(meta.get("SavedVariables") == "MitzuMPlusDB", "unexpected SavedVariables")
    optional = meta.get("OptionalDeps", "")
    c.check("MythicDungeonTools" not in optional, "MDT remains an optional runtime dependency")
    c.check("MitzuRouteArrows" not in optional, "MitzuRouteArrows remains a runtime dependency")
    c.check(meta.get("X-License") == "MIT", "package license metadata is not MIT")
    c.check(meta.get("IconTexture", "").endswith("Media\\Icons\\mitzu_logo_small_32"), "official logo is not configured")
    for entry in entries: c.check((ADDON / entry).exists(), f"missing TOC entry: {entry}")
    listed = {(ADDON / entry).resolve() for entry in entries if entry.lower().endswith(".lua")}
    for path in lua_files: c.check(path.resolve() in listed, f"orphan Lua file outside TOC: {relative(path)}")

def check_product_boundary(c):
    for path in ADDON.rglob("*"):
        if not path.is_file(): continue
        parts = set(path.relative_to(ADDON).parts)
        c.check(path.name not in RETIRED_NAMES, f"retired module still packaged: {relative(path)}")
        c.check(not (parts & FORBIDDEN_DIRS), f"retired subsystem directory still packaged: {relative(path)}")
        c.check(path.suffix.lower() in RUNTIME_SUFFIXES or path.name == "LICENSE.txt",
                f"non-runtime file in addon folder: {relative(path)}")
    toc = read(TOC)
    for word in ["MythicDungeonTools", "MitzuRouteArrows", "AdaptiveRoute", "MDTImporter", "RouteProgress"]:
        c.check(word not in toc, f"{word} remains in the runtime manifest")
    for name in TRACKER_VISUAL_FILES:
        code = re.sub(r"--[^\n]*", "", read(ADDON / "modules" / "Tracker" / name))
        for access in ["MitzuMPlus.RouteProgress", "MitzuMPlus.RouteManager", "MitzuMPlus.RouteAdvisor",
                       "MitzuMPlus.CoachAdvice", "C_NamePlate", "CombatLogGetCurrentEventInfo", "MDT"]:
            c.check(access not in code, f"tracker {name} reads retired/unreliable source: {access}")
    presenter = read(ADDON / "modules" / "Tracker" / "TrackerPresenter.lua")
    for result in ['["+3"] = "+3"', '["+2"] = "+2"', '["+1"] = "+1"', '["FUERA"] = "OVERTIME"']:
        c.check(result in presenter, f"tracker result contract missing {result}")
    c.check(not (ADDON / "modules" / "KeyPredictionHUD.lua").exists(),
            "retired KeyPredictionHUD.lua is back: Mitzu Tracker replaced it in 1.1.0-dev.6")

def check_ui_and_commands(c):
    tabs = read(ADDON / "UI" / "Tabs.lua")
    # 1.1.0-dev.10: the bar names locale keys; the words live in Locales/.
    for key in ["TABBAR_HISTORY", "TABBAR_STATS", "TABBAR_PLAYERS", "TABBAR_SETTINGS"]:
        c.check(f'L["{key}"]' in tabs, f"missing final tab {key}")
    c.check("M+ COACH" not in tabs, "retired M+ Coach tab remains")
    init = read(ADDON / "Init.lua")
    c.check('RegisterChatCommand("emp"' in init, "/emp is not registered")
    for command in ["route", "routes", "pull", "next", "prev", "mdt", "alignment", "evidence", "coach"]:
        c.check(f'cmd == "{command}"' not in init, f"legacy command remains: {command}")
    dropdown = read(ADDON / "modules" / "UI_SimpleDropdown.lua")
    # WoW fonts can draw Unicode arrows as empty squares, so the indicator is the
    # ASCII "v" (see UI_SimpleDropdown.lua), never a glyph such as U+25BC.
    arrow = re.search(r'arrow:SetText\("([^"]*)"\)', dropdown)
    c.check(arrow is not None and arrow.group(1) == "v", "dropdown does not use the ASCII down indicator")
    history = read(ADDON / "UI" / "Panels" / "Historial.lua")
    for key in ["COL_DUNGEON", "COL_LEVEL", "COL_RESULT", "HIST_COL_DURATION", "COL_CHARACTER",
                "COL_ROLE", "COL_DATE"]:
        c.check(f'L["{key}"]' in history, f"History V2 column missing: {key}")
    c.check("Panel.FilterRuns" in history and "Panel.Paginate" in history, "History V2 model helpers missing")

def check_savedvariables_and_media(c):
    defaults = read(ADDON / "MitzuMPlus_main.lua")
    for legacy in ["routeAutoLearn", "shareData", "routeData", "tracking =", "visibleColumns", "calibrationEnabled"]:
        c.check(legacy not in defaults, f"obsolete default remains initialized: {legacy}")
    for active in ["activeRunSession", "dungeonRegistry", "lootTracking", "showConfidence", "showETA"]:
        c.check(active in defaults, f"active setting/storage missing: {active}")
    expected = {"mitzu_logo_header_64.tga", "mitzu_logo_minimap_64.tga", "mitzu_logo_small_32.tga",
                "tab_history_64.tga", "tab_statistics_64.tga", "tab_players_64.tga", "tab_settings_64.tga",
                "btn_minimize_64.tga", "btn_options_64.tga", "btn_close_64.tga"}
    actual = {p.name for p in (ADDON / "Media" / "Icons").iterdir() if p.is_file()}
    c.check(actual == expected, f"media set differs from referenced assets: {sorted(actual)}")
    sources = [TOC] + sorted(p for p in ADDON.rglob("*.lua") if "libs" not in p.relative_to(ADDON).parts)
    referenced = set()
    for path in sources:
        text = read(path)
        referenced |= {m.lower() for m in re.findall(r"Media\\+Icons\\+(\w+)", text)}
        # Names joined to an icon path prefix, e.g. ICON_PATH .. "tab_history_64"
        # or CreateWindowControl(parent, "btn_close_64").
        stems = {Path(a).stem.lower() for a in actual}
        referenced |= {m.lower() for m in re.findall(r"ICON_PATH\s*\.\.\s*\"(\w+)\"", text)}
        referenced |= {m.lower() for m in re.findall(r"\"(\w+)\"", text) if m.lower() in stems}
    missing = sorted(name for name in referenced if f"{name}.tga" not in {a.lower() for a in actual})
    c.check(not missing, f"referenced icon texture missing from Media/Icons: {missing}")
    c.check(expected - {"btn_minimize_64.tga"} <= {f"{name}.tga" for name in referenced},
            "approved icon asset is not referenced by the UI")

def tga_alpha(path):
    """Header fields and alpha rows (top row first) of an uncompressed TGA."""
    data = path.read_bytes()
    id_len, cmap_type, image_type = data[0], data[1], data[2]
    width, height = int.from_bytes(data[12:14], "little"), int.from_bytes(data[14:16], "little")
    bpp, flags = data[16], data[17]
    rows = []
    if image_type == 2 and cmap_type == 0 and bpp == 32:
        start = 18 + id_len
        for y in range(height):
            row = data[start + y * width * 4:start + (y + 1) * width * 4]
            rows.append(row[3::4])
        if not flags & 0x20: rows.reverse()
    return image_type, width, height, bpp, flags, rows

def check_icon_textures(c):
    # Approved icons must stay WoW-safe (uncompressed 32-bit RGBA, square,
    # power of two) and keep the visible art (alpha >= 32) at 88-94% of the
    # canvas, so no icon slides back to heavy transparent padding. The minimap
    # logo keeps ~87.5% on purpose: LibDBIcon trims 5% per side of its texture.
    for path in sorted((ADDON / "Media" / "Icons").glob("*.tga")):
        low, high = (0.86, 0.90) if path.name == "mitzu_logo_minimap_64.tga" else (0.88, 0.94)
        image_type, width, height, bpp, flags, rows = tga_alpha(path)
        name = relative(path)
        c.check(image_type == 2 and bpp == 32 and flags & 0x0F == 8, f"icon is not uncompressed 32-bit RGBA: {name}")
        c.check(width == height and width & (width - 1) == 0, f"icon canvas is not a square power of two: {name}")
        if not rows: continue
        c.check(min(min(r) for r in rows) == 0, f"icon has no transparent pixels: {name}")
        xs = [x for row in rows for x, a in enumerate(row) if a >= 32]
        ys = [y for y, row in enumerate(rows) if max(row) >= 32]
        occupancy = max(max(xs) - min(xs) + 1, max(ys) - min(ys) + 1) / width if xs else 0
        c.check(low <= occupancy <= high,
                f"icon art fills {occupancy:.1%} of the canvas ({low:.0%}-{high:.0%} expected): {name}")

def check_no_emoji(c):
    # Project policy: WoW fonts do not render emoji reliably, so no emoji anywhere
    # in addon code, comments, manifests or the repo's tests/tools. Ranges are
    # built with chr() to keep this file ASCII-only.
    emoji = re.compile("[" + chr(0x1F000) + "-" + chr(0x1FFFF) + chr(0x2600) + "-" + chr(0x27BF)
                       + chr(0x2B00) + "-" + chr(0x2BFF) + chr(0xFE0F) + "]")
    # U+2713 CHECK MARK is a plain dingbat, not emoji: WoW's fonts render it and
    # the season panel uses it as the "goal reached" mark. Keep it allowed.
    allowed = {chr(0x2713)}
    paths = [p for p in ADDON.rglob("*") if p.suffix.lower() in {".lua", ".toc", ".xml"}]
    paths += list((ROOT / "tests").rglob("*.lua")) + list((ROOT / "tests").rglob("*.py"))
    paths += list((ROOT / "tools").rglob("*.py"))
    for path in sorted(paths):
        for number, line in enumerate(read(path).splitlines(), 1):
            bad = [m.group(0) for m in emoji.finditer(line) if m.group(0) not in allowed]
            c.check(not bad, f"emoji in source: {relative(path)}:{number}")

def check_version_consistency(c):
    version = metadata().get("Version", "")
    c.check(re.fullmatch(r"1\.\d+\.\d+(-(dev\.\d+|alpha\.\d+|beta\.\d+|rc\d+))?", version) is not None,
            f"TOC version is not in the 1.x release series: {version!r}")
    c.check(re.search(rf"^### {re.escape(version)}\b", read(ROOT / "CHANGELOG.md"), re.MULTILINE) is not None,
            f"root CHANGELOG.md has no entry for {version}")
    # Internal dev/alpha builds only run on the PTR and are never published, so
    # the public release material keeps naming the last public version.
    if re.search(r"-(dev|alpha)\.\d+$", version) is None:
        release_changelog = read(ROOT / "release" / "CHANGELOG.md")
        first = re.search(r"^## (\S+)", release_changelog, re.MULTILINE)
        c.check(first is not None and first.group(1) == version,
                f"release/CHANGELOG.md top entry does not match TOC version {version}")
        c.check(f"Current candidate: `{version}`" in read(ROOT / "docs" / "RELEASE.md"),
                f"docs/RELEASE.md does not name candidate {version}")
        c.check(f"MitzuMPlus-{version}.zip" in read(ROOT / "release" / "CURSEFORGE_PAGE.md"),
                f"release/CURSEFORGE_PAGE.md does not name MitzuMPlus-{version}.zip")
    # The PTR and Retail may run different interface numbers; the TOC lists
    # every supported client so one build loads on both.
    interfaces = [v.strip() for v in metadata().get("Interface", "").split(",")]
    c.check(all(re.fullmatch(r"\d{6}", v) for v in interfaces) and interfaces != [""],
            f"TOC Interface is not a list of six-digit versions: {interfaces!r}")
    author = "Mutzuki Mizt"
    c.check(metadata().get("Author") == author, f"TOC Author is not {author}")
    c.check(f"Copyright (c) 2026 {author}" in read(ROOT / "LICENSE"), f"LICENSE copyright holder is not {author}")
    identity_files = [ROOT / "LICENSE", ROOT / "README.md", ROOT / "docs" / "RELEASE.md", TOC]
    identity_files += sorted((ROOT / "release").glob("*.md")) + [ADDON / "modules" / "UI_Common.lua"]
    for path in identity_files:
        c.check("Mutzukyhs" not in read(path), f"old author name remains: {relative(path)}")
    for asset in ["README.md", "CURSEFORGE_PAGE.md", "assets/MitzuMPlus_Logo_512.png"]:
        c.check((ROOT / "release" / asset).is_file(), f"release material missing: release/{asset}")

# KeyPredictionHUD (the 1.0 floating HUD, frozen at v1.0.0-beta.1) was retired
# in 1.1.0-dev.6 by user decision: Mitzu Tracker replaces it and reuses its
# settings. Rollback lives in git (tag v1.0.0-beta.1). See docs/tracker/ROADMAP.md.
TRACKER_VISUAL_FILES = ["TrackerPresenter.lua", "TrackerView.lua", "BlizzardTrackerEnhancer.lua", "MitzuTracker.lua"]

# 1.1.0-dev.7: during a real key Mitzu lives inside Blizzard's Mythic+ block.
# The enhancer may only READ Blizzard frames (references named blizz*), install
# the two documented post-hooks and move/show its own elements.
ENHANCER_ALLOWED_HOOKS = {"Activate", "EndLayout"}
ENHANCER_OWN_PARENTED = {"el.root", "el.forcesRoot"}
ENHANCER_FORBIDDEN = ["HookScript", "SetScript", "OnUpdate", "EnableMouse", "RegisterForDrag", "StartMoving",
                      "ObjectiveTrackerFrame", "SetHeightModifier", "MarkDirty", "hooksecurefunc(\"",
                      "RouteArrows", "MDT", "C_AddOns"]
# 1.1.0-dev.9: the embedded lines are text only. A backdrop, a texture or a
# badge behind them would turn Blizzard's block into a Mitzu panel.
ENHANCER_NO_BACKGROUND = ["SetBackdrop", "SetBackdropColor", "CreateTexture", "SetColorTexture",
                          "SetTexture", "SetAtlas"]
# Blizzard already owns the death counter and the forces bar: Mitzu never
# writes their text, their visibility or their anchors.
ENHANCER_READ_ONLY_REGIONS = ["DeathCount", "StatusBar", "TimeLeft", "Label"]
# 1.1.0-dev.11 font ladder. Blizzard's TimeLeft (Huge) stays the biggest text on
# screen; below it Mitzu has one strictly descending ladder of NATIVE Blizzard
# font objects. The heights are Blizzard's own, so the gate reasons in pixels
# instead of in string suffixes and cannot be fooled by renaming a template.
BLIZZARD_FONT_HEIGHT = {
    "GameFontNormalSmall": 10, "GameFontHighlightSmall": 10, "GameFontDisableSmall": 10,
    "GameFontNormal": 12, "GameFontHighlight": 12, "GameFontDisable": 12,
    "GameFontHighlightMedium": 12, "GameFontNormalMed1": 12, "GameFontNormalMed2": 14,
    "GameFontNormalLarge": 16, "GameFontHighlightLarge": 16, "GameFontDisableLarge": 16,
    "GameFontNormalHuge": 20, "GameFontHighlightHuge": 20,
}
# Strictly descending, top first. Equal heights are allowed only where the list
# says so (penalty and the confidence share the smallest step).
ENHANCER_FONT_LADDER = ["threshold", "pace", "forces", "forcesSecondary"]
# The player reads these two at a glance; a dimmed font is what broke dev.10.
ENHANCER_LEGIBLE_KINDS = ["threshold", "pace", "forces", "forcesSecondary"]
# Nothing in the visual layer may branch on the client language: the width is
# measured from the translated string, never assumed per locale.
VISUAL_LOCALE_TOKENS = ["GetLocale", "esES", "esMX", "enGB", "SpanishWidth", "EnglishWidth"]
RUN_MODES = ["PENDING", "RUNNING", "COMPLETING"]


def check_font_ladder(c, name, fonts, allow_huge=frozenset()):
    """Every font is a known native Blizzard template and the ladder descends."""
    for kind, font in fonts.items():
        c.check(font in BLIZZARD_FONT_HEIGHT,
                f"{name}: {kind} uses an unknown font object: {font!r}")
        if kind not in allow_huge:
            c.check("Huge" not in font, f"{name}: {kind} must not use a Huge font: {font!r}")
    for kind in ENHANCER_LEGIBLE_KINDS:
        font = fonts.get(kind, "")
        c.check(font != "GameFontDisableSmall",
                f"{name}: {kind} is read at a glance and must not use the dimmed font")
    # The threshold carries the run's headline number: never a Small font.
    threshold = fonts.get("threshold", "")
    c.check("Small" not in threshold,
            f"{name}: the threshold must not use a Small font, got {threshold!r}")
    heights = [(k, BLIZZARD_FONT_HEIGHT.get(fonts.get(k, ""), 0)) for k in ENHANCER_FONT_LADDER if k in fonts]
    for (upper, hi), (lower, lo) in zip(heights, heights[1:]):
        c.check(hi >= lo, f"{name}: {lower} ({lo}px) must not outweigh {upper} ({hi}px)")
    # The confidence must stay strictly below the pace: it is the least important
    # number on the line and must never read as loud as the pace.
    pace = BLIZZARD_FONT_HEIGHT.get(fonts.get("pace", ""), 0)
    conf = BLIZZARD_FONT_HEIGHT.get(fonts.get("secondary", ""), 0)
    c.check(pace > conf, f"{name}: the confidence ({conf}px) must stay under the pace ({pace}px)")
    # The threshold must actually outweigh the pace, or the hierarchy is flat.
    c.check(BLIZZARD_FONT_HEIGHT.get(threshold, 0) > pace,
            f"{name}: the threshold must outweigh the pace")


def check_enhancer_safety(c):
    path = ADDON / "modules" / "Tracker" / "BlizzardTrackerEnhancer.lua"
    name = relative(path)
    code = re.sub(r"--[^\n]*", "", read(path))
    for token in ENHANCER_FORBIDDEN:
        c.check(token not in code, f"{name}: forbidden in the enhancer: {token}")
    # Blizzard references are only read: Get*/Is* methods.
    for method in re.findall(r"\bblizz\w*\s*:\s*(\w+)\s*\(", code):
        c.check(method.startswith(("Get", "Is")), f"{name}: mutating call on a Blizzard frame: :{method}()")
    # No writes into Blizzard tables.
    c.check(re.search(r"\bblizz\w*(\.\w+|\[[^\]]*\])+\s*=(?!=)", code) is None,
            f"{name}: assignment into a Blizzard frame field")
    # Hooks: only hooksecurefunc(table, "Activate"|"EndLayout", fn).
    hooks = re.findall(r"\bhook\s*\(\s*blizz\w+\s*,\s*\"(\w+)\"", code)
    c.check(len(hooks) == 2 and set(hooks) == ENHANCER_ALLOWED_HOOKS,
            f"{name}: unexpected post-hooks {hooks}")
    c.check(code.count("hook(") == len(hooks), f"{name}: hook call without a documented target")
    # Only Mitzu's own frames are re-parented.
    for receiver in re.findall(r"([\w\.]+)\s*:\s*SetParent\s*\(", code):
        c.check(receiver in ENHANCER_OWN_PARENTED, f"{name}: SetParent on a frame Mitzu does not own: {receiver}")
    # dev.8: no second main timer (Blizzard's TimeLeft uses the Huge font) and
    # the embedded model never re-writes the forces percentage under the bar.
    c.check("Huge" not in code, f"{name}: a second big timer font in the enhancer")
    presenter_src = read(ADDON / "modules" / "Tracker" / "TrackerPresenter.lua")
    embedded = re.search(r"function TP\.BuildEmbedded\(.*?\nend\n", presenter_src, re.DOTALL)
    c.check(embedded is not None and "percentText" not in embedded.group(0),
            "TrackerPresenter.BuildEmbedded must not add a forces percentage (Blizzard/AK already show it)")
    for global_name in re.findall(r"rawget\(\s*_G\s*,\s*\"(\w+)\"", code):
        # C_Timer: experimental.11 defers the post-EndLayout remeasure one loop
        # turn so text metrics have converged. Read-only namespace lookup.
        c.check(global_name in {"ScenarioObjectiveTracker", "hooksecurefunc", "CreateFrame", "C_Timer"},
                f"{name}: unexpected global read: {global_name}")
    # dev.9: no background of its own behind the embedded lines.
    for token in ENHANCER_NO_BACKGROUND:
        c.check(token not in code, f"{name}: embedded mode must stay text-only: {token}")
    # dev.9: never write into the regions Blizzard owns, whatever they are called.
    for region in ENHANCER_READ_ONLY_REGIONS:
        c.check(re.search(rf"\w*{region}\w*\s*:\s*(Set|Show|Hide|Clear)\w*\s*\(", code) is None,
                f"{name}: writes into Blizzard's {region}")
    # dev.11: the font ladder. Readability comes from picking the right native
    # font object, never from scaling the root or inventing a font.
    fonts_block = re.search(r"E\.FONT\s*=\s*\{(.*?)\}", code, re.DOTALL)
    c.check(fonts_block is not None, f"{name}: E.FONT table missing")
    fonts = dict(re.findall(r"(\w+)\s*=\s*\"(\w+)\"", fonts_block.group(1))) if fonts_block else {}
    check_font_ladder(c, name, fonts)
    c.check(fonts.get("secondary", "").startswith("GameFontDisable"),
            f"{name}: confidence/ETA must stay a disabled (grey) font, not {fonts.get('secondary')!r}")
    # The declared ladder is what the tests and this gate walk; keep it in sync.
    order = re.search(r"E\.FONT_ORDER\s*=\s*\{(.*?)\}", code, re.DOTALL)
    c.check(order is not None, f"{name}: E.FONT_ORDER missing")
    if order:
        declared = re.findall(r"\"(\w+)\"", order.group(1))
        c.check(set(declared) == set(fonts),
                f"{name}: FONT_ORDER and FONT disagree: {sorted(set(declared) ^ set(fonts))}")
    # Readability is never bought with SetScale or a hand-built font.
    for token in ["SetFont(", "SetFontObject(", "CreateFont("]:
        c.check(token not in code, f"{name}: fonts come from Blizzard templates only: {token}")
    # Scale stays the user's preference applied to Mitzu's own roots, and only
    # ever with the clamped setting: never a constant used to fake a bigger font.
    scaled = re.findall(r"(\S+?):SetScale\(([^)]*)\)", code)
    for receiver, value in scaled:
        c.check(receiver in ENHANCER_OWN_PARENTED,
                f"{name}: SetScale on a frame Mitzu does not own: {receiver}")
        c.check(value.strip() == "s",
                f"{name}: scale must come from the clamped user setting, not {value.strip()!r}")
    c.check(len(scaled) == 2, f"{name}: unexpected SetScale calls: {scaled}")
    # dev.11: exact colours, so "it looks grey" stays a testable claim.
    c.check(re.search(r"threshold\s*=\s*\{\s*1\.00,\s*0\.843,\s*0\.00\s*\}", code) is not None,
            f"{name}: the threshold must use the agreed gold 1.00/0.843/0.00")
    c.check(re.search(r"secondary\s*=\s*\{\s*0\.78,\s*0\.78,\s*0\.812\s*\}", code) is not None,
            f"{name}: secondary text must use the agreed silver 0.78/0.78/0.812")

    # dev.11: the preview must promise what the key delivers. Same ladder.
    view_src = read(ADDON / "modules" / "Tracker" / "TrackerView.lua")
    view_fonts_block = re.search(r"TV\.FONT\s*=\s*\{(.*?)\}", view_src, re.DOTALL)
    c.check(view_fonts_block is not None, "TrackerView.lua: TV.FONT table missing")
    view_fonts = dict(re.findall(r"(\w+)\s*=\s*\"(\w+)\"", view_fonts_block.group(1))) if view_fonts_block else {}
    for kind, font in fonts.items():
        c.check(view_fonts.get(kind) == font,
                f"TrackerView.lua: preview {kind} is {view_fonts.get(kind)!r}, embedded is {font!r}")
    check_font_ladder(c, "TrackerView.lua", view_fonts, allow_huge={"timer"})

    # dev.11: the layout decides by measured width, never by the client language.
    for visual in ["BlizzardTrackerEnhancer.lua", "TrackerView.lua", "TrackerPresenter.lua"]:
        src = re.sub(r"--[^\n]*", "", read(ADDON / "modules" / "Tracker" / visual))
        for token in VISUAL_LOCALE_TOKENS:
            c.check(token not in src, f"{visual}: visual layout must not branch on locale: {token}")
    # The remainder is measured in the font it is painted with, not in a smaller
    # one: measuring small and painting big is how text overflows the bar.
    layout = re.search(r"function TP\.LayoutEmbedded\(.*?\nend\n",
                       read(ADDON / "modules" / "Tracker" / "TrackerPresenter.lua"), re.DOTALL)
    c.check(layout is not None, "TrackerPresenter.lua: LayoutEmbedded missing")
    if layout:
        forces = layout.group(0)[layout.group(0).find("local fo = out.forces"):]
        c.check('"secondary"' not in forces,
                "TrackerPresenter.lua: the forces remainder must be measured with forcesSecondary")
        c.check(forces.count('"forcesSecondary"') >= 2,
                "TrackerPresenter.lua: every remainder measurement uses its own font")
        # Sacrifice order: the count is never compacted while the full one fits.
        order_seen = [m for m in re.findall(r'"(SPLIT|PRIMARY|PRIMARY_COMPACT|SECONDARY|TOO_NARROW)"', forces)]
        c.check(order_seen[:3] == ["SPLIT", "PRIMARY", "PRIMARY_COMPACT"],
                f"TrackerPresenter.lua: forces must degrade SPLIT -> PRIMARY -> PRIMARY_COMPACT, got {order_seen}")

    # The floating view never knows about Blizzard's tracker; the presenter has no frames.
    view = re.sub(r"--[^\n]*", "", read(ADDON / "modules" / "Tracker" / "TrackerView.lua"))
    for token in ["ScenarioObjectiveTracker", "hooksecurefunc", "ChallengeModeBlock"]:
        c.check(token not in view, f"TrackerView.lua must stay independent of Blizzard's tracker: {token}")
    presenter = re.sub(r"--[^\n]*", "", read(ADDON / "modules" / "Tracker" / "TrackerPresenter.lua"))
    for token in ["CreateFrame", "UIParent", "hooksecurefunc", "ScenarioObjectiveTracker", ":SetText("]:
        c.check(token not in presenter, f"TrackerPresenter.lua must stay pure: {token}")

    # No second run HUD: live key modes are routed to the embedded enhancer only.
    tracker = read(ADDON / "modules" / "Tracker" / "MitzuTracker.lua")
    block = re.search(r"MT\.RENDER_ROUTE\s*=\s*\{(.*?)\}", tracker, re.DOTALL)
    c.check(block is not None, "MitzuTracker.lua: RENDER_ROUTE table missing")
    routes = dict(re.findall(r"(\w+)\s*=\s*\"(\w+)\"", block.group(1))) if block else {}
    for mode in RUN_MODES:
        c.check(routes.get(mode) == "EMBEDDED", f"MitzuTracker.lua: {mode} must render EMBEDDED, not {routes.get(mode)}")
    c.check(set(k for k, v in routes.items() if v == "FLOATING") <= {"PREVIEW", "SUMMARY"},
            f"MitzuTracker.lua: floating view allowed only for PREVIEW/SUMMARY: {routes}")

# 1.1.0-dev.9: the QA snapshot of the last embedded render is diagnostics only.
# It may never write game state, and it may only copy flat values.
SNAPSHOT_FORBIDDEN = ["TrackerState", "RunSession", "PredictionEngine", "db.global", "db.profile",
                      "MitzuMPlusCurrentRun", "GetStringWidth", "Measure"]


def check_qa_snapshot(c):
    path = ADDON / "modules" / "Tracker" / "MitzuTracker.lua"
    name = relative(path)
    code = re.sub(r"--[^\n]*", "", read(path))
    c.check("MT.LAST_EMBEDDED_FIELDS" in code, f"{name}: the lastEmbedded field list is missing")
    capture = re.search(r"function MT:_CaptureEmbedded\(.*?\nend\n", code, re.DOTALL)
    c.check(capture is not None, f"{name}: MT:_CaptureEmbedded is missing")
    body = capture.group(0) if capture else ""
    for token in SNAPSHOT_FORBIDDEN:
        c.check(token not in body, f"{name}: the QA snapshot must not touch {token}")
    # Only EMBEDDED renders feed it, and nothing ever clears it.
    c.check('route ~= "EMBEDDED"' in body, f"{name}: the QA snapshot must only store EMBEDDED renders")
    # Only the module-level declaration may be nil; no code path clears it.
    c.check(re.search(r"^[ \t]+[\w.:]*_lastEmbedded\s*=\s*nil", code, re.MULTILINE) is None,
            f"{name}: the QA snapshot must survive hide / summary / preview / leaving the dungeon")
    report = read(ADDON / "modules" / "QA" / "BugReport.lua")
    c.check('"LAST EMBEDDED RENDER"' in report, "BugReport.lua: the [LAST EMBEDDED RENDER] section is missing")
    c.check('MT.LAST_EMBEDDED_PREFIX = "lastEmbedded."' in code,
            f"{name}: lastEmbedded fields must keep their own prefix (current vs last)")


# Architecture: only TrackerAdapter talks to Blizzard's Mythic+ APIs. The layers
# above it (state, pace, prediction, enhancer) consume normalized data only.
BLIZZARD_API_TOKENS = ["C_ChallengeMode", "C_ScenarioInfo", "C_Scenario", "GetWorldElapsedTime",
                       "GetWorldElapsedTimers", "quantityString"]

def check_tracker_layers(c):
    for name in ["TrackerState.lua"] + TRACKER_VISUAL_FILES:
        path = ADDON / "modules" / "Tracker" / name
        code = re.sub(r"--[^\n]*", "", read(path))
        for token in BLIZZARD_API_TOKENS:
            c.check(token not in code, f"{relative(path)} bypasses TrackerAdapter: {token}")

# ===========================================================================
# 1.1.0-dev.10 -- LOCALIZATION_COMPLETE
#
# The addon speaks the client's language. AceLocale-3.0 is the only layer that
# chooses one, English (enUS) is the default so every untranslated client falls
# back to it, and no runtime file may carry a user-visible sentence of its own.
# ===========================================================================
LOCALE_DIR = ADDON / "Locales"
LOCALE_FILES = {"enUS": LOCALE_DIR / "enUS.lua", "esES": LOCALE_DIR / "esES.lua"}

# 1.1.0: the native-UI modules under modules/Experimental/ read a SECOND
# AceLocale namespace ("MitzuMPlusExperimental") served by its own pair of
# files. It is a separate table, so its keys must be checked against that pair
# and never against the core one.
EXPERIMENTAL_LOCALE_FILES = {"enUS": LOCALE_DIR / "enUS_Experimental.lua",
                             "esES": LOCALE_DIR / "esES_Experimental.lua"}
EXPERIMENTAL_DIR = "Experimental"

# Files that legitimately hold text a player never reads: developer dumps
# (/emp dev ...), the sanitized bug report and the flight recorder. Section 8
# of the brief allows those to stay technical -- but they are English-only.
QA_ONLY_FILES = {
    "modules/QA/BugReport.lua", "modules/QA/Invariants.lua", "modules/QA/FlightRecorder.lua",
    "modules/QA/SafeValue.lua", "modules/QA/Localization.lua", "modules/ErrorLogger.lua",
    "modules/RuntimeCapabilities.lua", "modules/KeystoneTracker.lua",
    "modules/Tracker/TrackerAdapter.lua", "modules/Tracker/TrackerState.lua",
    "modules/Tracker/BlizzardTrackerProbe.lua", "modules/DungeonRegistry.lua",
    "modules/DungeonContext.lua", "modules/ChallengeClock.lua", "modules/LootTracker.lua",
    "modules/MidnightSafeTracking.lua", "modules/PartyProfiler.lua", "modules/RunSession.lua",
    "modules/Validation.lua", "modules/EventBus.lua", "modules/RuntimeVersion.lua",
}

# Words that only exist in Spanish. A runtime file outside Locales/ must not
# contain them in a string literal: that string would reach an English player.
SPANISH_WORDS = [
    "Historial", "Estadística", "Estadistica", "Configuración", "Configuracion",
    "Fuerzas", "faltan", "RITMO", "Muertes", "Jefes", "Llave", "LLAVE",
    "Esperando", "Vista previa", "VISTA PREVIA", "Cerrar", "Eliminar", "Jugador",
    "Mazmorra", "MAZMORRA", "Temporada", "Todas", "Todos", "Buscar", "Guardar",
    "Personaje", "Mítica", "Mitica", "Duración", "Duracion", "Añadir", "Añade",
    "Restablecer", "ÉXITO", "RESULTADO", "Borrar", "Nivel de", "Expansión",
    "Puntaje", "Compañer", "Calidad", "Registrar", "Mostrar", "Bloquear",
    "Ventana", "ultimo ritmo", "último ritmo", "oficial", "completo", "Ritmo",
]
# A language setting would defeat the whole design: WoW already chose.
LOCALE_SETTING_TOKENS = ["settings.locale", "settings.language", "SetLocale", "selectedLocale",
                         "languageOverride", "localeOverride", "GAME_LOCALE"]


def locale_keys(path):
    """{key: value} exactly as the locale file declares them."""
    out = {}
    # esES_Experimental.lua declares its keys indented inside a fill() helper,
    # because it registers the same table for esES and esMX.
    for match in re.finditer(r'^[ \t]*L\["([A-Z][A-Z0-9_]*)"\]\s*=\s*(.+)$', read(path), re.MULTILINE):
        out[match.group(1)] = match.group(2).strip().rstrip(",")
    return out


def lua_string_literals(code):
    """Double-quoted literals, ignoring comments."""
    for line in code.splitlines():
        line = re.sub(r'^\s*--.*$', "", line)
        for match in re.finditer(r'"((?:[^"\\]|\\.)*)"', line):
            yield match.group(1)


def check_localization(c):
    en = locale_keys(LOCALE_FILES["enUS"])
    es = locale_keys(LOCALE_FILES["esES"])
    c.check(len(en) > 300, f"the canonical enUS locale looks too small: {len(en)} keys")
    c.check(set(en) == set(es),
            f"enUS/esES key mismatch: only-enUS={sorted(set(en) - set(es))[:5]} "
            f"only-esES={sorted(set(es) - set(en))[:5]}")

    # enUS is the DEFAULT locale: that is what makes deDE/frFR/... get English.
    en_src = read(LOCALE_FILES["enUS"])
    c.check('NewLocale("MitzuMPlus", "enUS", true)' in en_src,
            "enUS must be registered as the default locale (third argument true)")
    es_src = read(LOCALE_FILES["esES"])
    c.check('NewLocale("MitzuMPlus", "esES")' in es_src and 'NewLocale("MitzuMPlus", "esMX")' in es_src,
            "the Spanish file must serve esES and esMX")
    c.check("true)" not in es_src.split("NewLocale")[1].split(chr(10))[0],
            "the Spanish file must never be the default locale")
    # No duplicated English file just to serve enGB: AceLocale maps it to enUS.
    c.check(not (LOCALE_DIR / "enGB.lua").exists(),
            "enGB must be served by the enUS fallback, not by a copied file")

    # AceLocale is the only selection layer, and it is wired once, in Bootstrap.
    bootstrap = read(ADDON / "Bootstrap.lua")
    c.check('LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)' in bootstrap,
            "Bootstrap.lua must expose MitzuMPlus.L from AceLocale")
    toc_lines = [l.strip() for l in read(TOC).splitlines() if l.strip().lower().endswith(".lua")]
    locales = [i for i, l in enumerate(toc_lines) if l.startswith("Locales")]
    # Two namespaces, two files each: core enUS/esES plus the native-UI pair.
    c.check(len(locales) == 4, f"expected exactly four locale files in the TOC: {len(locales)}")
    bootstrap_at = toc_lines.index("Bootstrap.lua")
    c.check(max(locales) < bootstrap_at,
            "Locales must load before Bootstrap.lua, and therefore before every module")

    # The native-UI pair mirrors the same contract on its own namespace.
    xen = locale_keys(EXPERIMENTAL_LOCALE_FILES["enUS"])
    xes = locale_keys(EXPERIMENTAL_LOCALE_FILES["esES"])
    c.check(len(xen) > 20, f"the experimental enUS locale looks too small: {len(xen)} keys")
    c.check(set(xen) == set(xes),
            f"experimental enUS/esES key mismatch: only-enUS={sorted(set(xen) - set(xes))[:5]} "
            f"only-esES={sorted(set(xes) - set(xen))[:5]}")
    xen_src = read(EXPERIMENTAL_LOCALE_FILES["enUS"])
    c.check('NewLocale("MitzuMPlusExperimental", "enUS", true)' in xen_src,
            "the experimental enUS file must be that namespace's default locale")
    xes_src = read(EXPERIMENTAL_LOCALE_FILES["esES"])
    c.check('NewLocale("MitzuMPlusExperimental", "esES")' in xes_src
            and 'NewLocale("MitzuMPlusExperimental", "esMX")' in xes_src,
            "the experimental Spanish file must serve esES and esMX")
    # Every key is checked against the table the reader actually holds:
    #   L[...]  -> core, except inside modules/Experimental/ where L IS the
    #              experimental namespace;
    #   EL[...] -> the experimental namespace, from a core file such as
    #              UI/Panels/Config.lua that renders the native-UI settings.
    # The lookbehind keeps EL[...] from also being counted as L[...].
    core_reads = re.compile(r'(?<![A-Za-z0-9_])L\[\s*"([A-Z][A-Z0-9_]*)"\s*\]')
    experimental_reads = re.compile(r'(?<![A-Za-z0-9_])EL\[\s*"([A-Z][A-Z0-9_]*)"\s*\]')
    used = set()
    for path in sorted(ADDON.rglob("*.lua")):
        rel = path.relative_to(ADDON)
        parts = set(rel.parts)
        if "libs" in parts or "Locales" in parts:
            continue
        code = read(path)
        own = set(core_reads.findall(code))
        foreign = set(experimental_reads.findall(code))
        if EXPERIMENTAL_DIR in parts:
            c.check(not foreign, f"{rel.as_posix()}: a native-UI module already owns L, EL is redundant")
            experimental_keys, core = own | foreign, set()
        else:
            experimental_keys, core = foreign, own
            used |= core
        for key in sorted(core):
            c.check(key in en, f'enUS has no entry for L["{key}"] ({rel.as_posix()})')
            c.check(key in es, f'esES has no entry for L["{key}"] ({rel.as_posix()})')
        for key in sorted(experimental_keys):
            c.check(key in xen, f'experimental enUS has no entry for L["{key}"] ({rel.as_posix()})')
            c.check(key in xes, f'experimental esES has no entry for L["{key}"] ({rel.as_posix()})')
    c.check(len(used) > 150, f"the runtime barely uses the locale table: {len(used)} keys")
    # And the two namespaces stay disjoint, so nobody reads a key from the
    # wrong table and silently gets the raw key back.
    overlap = set(xen) & set(en)
    c.check(not overlap, f"a key exists in both locale namespaces: {sorted(overlap)[:5]}")

    # No Spanish sentence may live outside Locales/, and no module may decide
    # the language by itself.
    for path in sorted(ADDON.rglob("*.lua")):
        rel = path.relative_to(ADDON).as_posix()
        parts = set(path.relative_to(ADDON).parts)
        if "libs" in parts or "Locales" in parts:
            continue
        code = read(path)
        if rel not in QA_ONLY_FILES:
            for literal in lua_string_literals(code):
                for word in SPANISH_WORDS:
                    c.check(word not in literal,
                            f"{rel}: Spanish text outside Locales/: {literal[:60]!r} ({word})")
        # GetLocale() belongs to the localization bootstrap, nowhere else.
        if rel not in {"Locales/enUS.lua", "Locales/esES.lua", "modules/QA/Localization.lua"}:
            c.check("GetLocale()" not in re.sub(r"--[^\n]*", "", code),
                    f"{rel}: only the localization bootstrap may branch on GetLocale()")
        for token in LOCALE_SETTING_TOKENS:
            c.check(token not in code, f"{rel}: the addon must not offer a language setting ({token})")

    # Identity is never translated text (section 31).
    history = read(ADDON / "UI" / "Panels" / "Historial.lua")
    c.check('return "INCOMPLETE", nil' in history and 'or "OUT"' in history,
            "History result codes must stay neutral IDs, not translated words")
    c.check("Panel.ResultLabel" in history, "the localized result label must be a separate function")
    database = read(ADDON / "modules" / "Database.lua")
    c.check("seasonName = string.format" not in database,
            "Database must not persist a translated season name (store the key instead)")
    # Class names come from the client, not from a table of our own.
    players = read(ADDON / "UI" / "Panels" / "Players.lua")
    c.check("CLASS_ES" not in players, "class names must come from Blizzard, not from a Spanish table")
    c.check("LOCALIZED_CLASS_NAMES_MALE" in players, "class names must read Blizzard's localized table")
    # The bug report has to say which language the player is seeing.
    c.check('"LOCALIZATION"' in read(ADDON / "modules" / "QA" / "BugReport.lua"),
            "BugReport.lua: the [LOCALIZATION] section is missing")


def main():
    c = Checks(); lua_files = compile_lua(c)
    check_tracker_layers(c); check_enhancer_safety(c); check_qa_snapshot(c); check_localization(c)
    check_manifest(c, lua_files); check_product_boundary(c); check_ui_and_commands(c)
    check_savedvariables_and_media(c); check_icon_textures(c); check_no_emoji(c); check_version_consistency(c)
    if c.failures:
        print(f"Static: {c.count} checks, {len(c.failures)} failures ({len(lua_files)} product Lua files parsed)")
        for failure in c.failures: print(failure)
        raise SystemExit(1)
    print(f"Static: {c.count} checks, 0 failures ({len(lua_files)} product Lua files parsed)")

if __name__ == "__main__": main()
