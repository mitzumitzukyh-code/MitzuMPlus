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
    hud = read(ADDON / "modules" / "KeyPredictionHUD.lua")
    code = re.sub(r"--[^\n]*", "", hud)
    for access in ["MitzuMPlus.RouteProgress", "MitzuMPlus.RouteManager", "MitzuMPlus.RouteAdvisor",
                   "MitzuMPlus.CoachAdvice", "C_NamePlate", "CombatLogGetCurrentEventInfo"]:
        c.check(access not in code, f"tracker reads retired/unreliable source: {access}")
    for result in ['["+3"]', '["+2"]', '["+1"]', '["FUERA"] = "OVERTIME"']:
        c.check(result in hud, f"tracker result contract missing {result}")

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
        referenced |= {m.lower() for m in re.findall(r"ICON_PATH\s*\.\.\s*\"(\w+)\"", text)}
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
    c.check(re.fullmatch(r"1\.\d+\.\d+(-(beta\.\d+|rc\d+))?", version) is not None,
            f"TOC version is not in the 1.x release series: {version!r}")
    release_changelog = read(ROOT / "release" / "CHANGELOG.md")
    first = re.search(r"^## (\S+)", release_changelog, re.MULTILINE)
    c.check(first is not None and first.group(1) == version,
            f"release/CHANGELOG.md top entry does not match TOC version {version}")
    c.check(re.search(rf"^### {re.escape(version)}\b", read(ROOT / "CHANGELOG.md"), re.MULTILINE) is not None,
            f"root CHANGELOG.md has no entry for {version}")
    c.check(f"Current candidate: `{version}`" in read(ROOT / "docs" / "RELEASE.md"),
            f"docs/RELEASE.md does not name candidate {version}")
    c.check(f"MitzuMPlus-{version}.zip" in read(ROOT / "release" / "CURSEFORGE_PAGE.md"),
            f"release/CURSEFORGE_PAGE.md does not name MitzuMPlus-{version}.zip")
    for asset in ["README.md", "CURSEFORGE_PAGE.md", "assets/MitzuMPlus_Logo_512.png"]:
        c.check((ROOT / "release" / asset).is_file(), f"release material missing: release/{asset}")

def main():
    c = Checks(); lua_files = compile_lua(c)
    check_manifest(c, lua_files); check_product_boundary(c); check_ui_and_commands(c)
    check_savedvariables_and_media(c); check_icon_textures(c); check_no_emoji(c); check_version_consistency(c)
    if c.failures:
        print(f"Static: {c.count} checks, {len(c.failures)} failures ({len(lua_files)} product Lua files parsed)")
        for failure in c.failures: print(failure)
        raise SystemExit(1)
    print(f"Static: {c.count} checks, 0 failures ({len(lua_files)} product Lua files parsed)")

if __name__ == "__main__": main()
