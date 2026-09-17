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
    for label in ["HISTORIAL", "ESTADÍSTICAS", "JUGADORES", "CONFIGURACIÓN"]:
        c.check(label in tabs, f"missing final tab {label}")
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
    for label in ["MAZMORRA", "NIVEL", "RESULTADO", "DURACIÓN", "PERSONAJE", "ROL", "FECHA"]:
        c.check(label in history, f"History V2 column missing: {label}")
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
    paths = [p for p in ADDON.rglob("*") if p.suffix.lower() in {".lua", ".toc", ".xml"}]
    paths += list((ROOT / "tests").rglob("*.lua")) + list((ROOT / "tests").rglob("*.py"))
    paths += list((ROOT / "tools").rglob("*.py"))
    for path in sorted(paths):
        for number, line in enumerate(read(path).splitlines(), 1):
            c.check(not emoji.search(line), f"emoji in source: {relative(path)}:{number}")

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
# Font hierarchy: Blizzard's TimeLeft stays the only large text. Pace, forces,
# penalty and the secondary parts stay Small, and the secondary stays dimmed.
ENHANCER_SMALL_FONTS = ["pace", "secondary", "forces", "penalty"]
RUN_MODES = ["PENDING", "RUNNING", "COMPLETING"]


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
        c.check(global_name in {"ScenarioObjectiveTracker", "hooksecurefunc", "CreateFrame"},
                f"{name}: unexpected global read: {global_name}")
    # dev.9: no background of its own behind the embedded lines.
    for token in ENHANCER_NO_BACKGROUND:
        c.check(token not in code, f"{name}: embedded mode must stay text-only: {token}")
    # dev.9: never write into the regions Blizzard owns, whatever they are called.
    for region in ENHANCER_READ_ONLY_REGIONS:
        c.check(re.search(rf"\w*{region}\w*\s*:\s*(Set|Show|Hide|Clear)\w*\s*\(", code) is None,
                f"{name}: writes into Blizzard's {region}")
    # dev.9: font hierarchy. RITMO gets a readable colour, never a bigger font.
    fonts_block = re.search(r"E\.FONT\s*=\s*\{(.*?)\}", code, re.DOTALL)
    c.check(fonts_block is not None, f"{name}: E.FONT table missing")
    fonts = dict(re.findall(r"(\w+)\s*=\s*\"(\w+)\"", fonts_block.group(1))) if fonts_block else {}
    for kind in ENHANCER_SMALL_FONTS:
        c.check(fonts.get(kind, "").endswith("Small"),
                f"{name}: {kind} must keep a Small font, not {fonts.get(kind)!r}")
    c.check(fonts.get("secondary", "").startswith("GameFontDisable"),
            f"{name}: confidence/ETA must stay a disabled (grey) font, not {fonts.get('secondary')!r}")

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

def main():
    c = Checks(); lua_files = compile_lua(c)
    check_tracker_layers(c); check_enhancer_safety(c); check_qa_snapshot(c)
    check_manifest(c, lua_files); check_product_boundary(c); check_ui_and_commands(c)
    check_savedvariables_and_media(c); check_icon_textures(c); check_no_emoji(c); check_version_consistency(c)
    if c.failures:
        print(f"Static: {c.count} checks, {len(c.failures)} failures ({len(lua_files)} product Lua files parsed)")
        for failure in c.failures: print(failure)
        raise SystemExit(1)
    print(f"Static: {c.count} checks, 0 failures ({len(lua_files)} product Lua files parsed)")

if __name__ == "__main__": main()
