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
    c.check(meta.get("Version") == "7.14.0-rc1", "version changed during cleanup")
    c.check(meta.get("SavedVariables") == "MitzuMPlusDB", "unexpected SavedVariables")
    optional = meta.get("OptionalDeps", "")
    c.check("MythicDungeonTools" not in optional, "MDT remains an optional runtime dependency")
    c.check("MitzuRouteArrows" not in optional, "MitzuRouteArrows remains a runtime dependency")
    c.check(meta.get("X-License") == "MIT", "package license metadata is not MIT")
    c.check(meta.get("IconTexture", "").endswith("Media\\Icons\\logo_64"), "official logo is not configured")
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
    c.check('arrow:SetText("▼")' in dropdown, "dropdown does not use a clear down indicator")
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
    expected = {"logo_64.tga", "2_settings.tga", "3_close.tga", "5a_tab_historial.tga",
                "5b_tab_stats.tga", "5e_tab_config.tga"}
    actual = {p.name for p in (ADDON / "Media" / "Icons").iterdir() if p.is_file()}
    c.check(actual == expected, f"media set differs from referenced assets: {sorted(actual)}")

def main():
    c = Checks(); lua_files = compile_lua(c)
    check_manifest(c, lua_files); check_product_boundary(c); check_ui_and_commands(c)
    check_savedvariables_and_media(c)
    if c.failures:
        print(f"Static: {c.count} checks, {len(c.failures)} failures ({len(lua_files)} product Lua files parsed)")
        for failure in c.failures: print(failure)
        raise SystemExit(1)
    print(f"Static: {c.count} checks, 0 failures ({len(lua_files)} product Lua files parsed)")

if __name__ == "__main__": main()
