"""Build the CurseForge zip for MitzuMPlus.

    python tools/package_mitzumplus.py            -> dist/MitzuMPlus-<version>.zip
    python tools/package_mitzumplus.py --check    -> build, then validate the zip

Only the MitzuMPlus/ folder is packaged, as a single top-level folder named
exactly like its .toc. Tests, docs, tools, CI files and the experimental
MitzuRouteArrows addon never enter the zip. The repository LICENSE is copied
into the package so the release carries it.

This script does NOT upload anything.
"""

import argparse
import re
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ADDON = "MitzuMPlus"
SOURCE = ROOT / ADDON
DIST = ROOT / "dist"

# Runtime file types WoW loads from an addon folder.
ALLOWED_SUFFIXES = {".lua", ".toc", ".xml", ".tga", ".blp", ".ogg", ".mp3", ".ttf", ".otf"}
# License files may travel with the addon; internal documentation may not.
ALLOWED_NAMES = {"LICENSE.txt"}
# Never packaged, whatever their extension.
EXCLUDED_PARTS = {".git", ".github", "tests", "docs", "tools", "dist", "screenshots",
                  "__pycache__", ".vscode", ".idea"}
EXCLUDED_NAMES = {".DS_Store", "Thumbs.db", ".pkgmeta", ".gitignore", ".gitattributes"}


def toc_version() -> str:
    toc = (SOURCE / f"{ADDON}.toc").read_text(encoding="utf-8-sig")
    match = re.search(r"^##\s*Version\s*:\s*(\S+)", toc, re.MULTILINE)
    if not match:
        raise SystemExit("MitzuMPlus.toc has no ## Version")
    return match.group(1)


def package_files() -> list[Path]:
    files = []
    for path in sorted(SOURCE.rglob("*")):
        if not path.is_file():
            continue
        parts = set(path.relative_to(SOURCE).parts)
        if parts & EXCLUDED_PARTS or path.name in EXCLUDED_NAMES:
            continue
        if path.suffix.lower() in ALLOWED_SUFFIXES or path.name in ALLOWED_NAMES:
            files.append(path)
        else:
            raise SystemExit(f"unexpected file in the addon folder: {path.relative_to(ROOT)}")
    return files


def build() -> Path:
    version = toc_version()
    DIST.mkdir(exist_ok=True)
    target = DIST / f"{ADDON}-{version}.zip"
    if target.exists():
        target.unlink()
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in package_files():
            arcname = f"{ADDON}/{path.relative_to(SOURCE).as_posix()}"
            zf.write(path, arcname)
        zf.write(ROOT / "LICENSE", f"{ADDON}/LICENSE")
    return target


def toc_entries(toc_text: str) -> list[str]:
    return [line.strip().replace("\\", "/") for line in toc_text.splitlines()
            if line.strip() and not line.strip().startswith("#")]


def validate(target: Path) -> list[str]:
    problems = []
    with zipfile.ZipFile(target) as zf:
        names = zf.namelist()
        bad = zf.testzip()
        if bad:
            problems.append(f"corrupt member: {bad}")
        tops = {n.split("/", 1)[0] for n in names}
        if tops != {ADDON}:
            problems.append(f"zip must contain exactly one top-level folder {ADDON}/, found {sorted(tops)}")
        toc_name = f"{ADDON}/{ADDON}.toc"
        if toc_name not in names:
            problems.append(f"missing {toc_name}")
            return problems
        toc_text = zf.read(toc_name).decode("utf-8-sig")
        members = set(names)
        for entry in toc_entries(toc_text):
            if f"{ADDON}/{entry}" not in members:
                problems.append(f"TOC entry not in zip: {entry}")
        for required in [f"{ADDON}/LICENSE", f"{ADDON}/Bindings.xml",
                         f"{ADDON}/Media/Icons/mitzu_logo_small_32.tga"]:
            if required not in members:
                problems.append(f"missing {required}")
        for retired in ["1_addon.tga", "10_minimap.tga", "logo_64.tga", "2_settings.tga", "3_close.tga",
                        "5a_tab_historial.tga", "5b_tab_stats.tga", "5e_tab_config.tga"]:
            if f"{ADDON}/Media/Icons/{retired}" in members:
                problems.append(f"retired icon still packaged: {retired}")
        if "IconTexture: Interface\\AddOns\\MitzuMPlus\\Media\\Icons\\mitzu_logo_small_32" not in toc_text:
            problems.append("TOC IconTexture does not point to mitzu_logo_small_32")
        for name in names:
            lowered = name.lower()
            if any(f"/{part}/" in f"/{lowered}" for part in ("tests", "docs", "tools", ".git", ".github")):
                problems.append(f"development path in zip: {name}")
            if "mitzuroutearrows" in lowered:
                problems.append(f"experimental addon file in zip: {name}")
            if lowered.endswith((".py", ".spec.lua", ".bak", ".tmp", ".log")):
                problems.append(f"development file in zip: {name}")
        experimental = ("RouteArrows", "RouteProgress", "RouteManager", "RouteAdvisor",
                        "RouteSchema", "AdaptiveRoute", "MDTImporter", "MDTEnemyData",
                        "CoachAdvice", "PullUnitResolver", "GuidanceEngine", "Evidence",
                        "RouteAlignment", "ArrowDemo", "NameplateAnchorProvider",
                        "MDTPhysicalGroupData")
        for name in names:
            if any(word in name for word in experimental):
                problems.append(f"experimental module in zip: {name}")
    return problems


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="validate the zip after building it")
    args = parser.parse_args()

    target = build()
    with zipfile.ZipFile(target) as zf:
        count = len(zf.namelist())
        raw = sum(i.file_size for i in zf.infolist())
    size = target.stat().st_size
    print(f"{target.relative_to(ROOT).as_posix()}: {count} files, "
          f"{size / 1024:.1f} KiB compressed, {raw / 1024:.1f} KiB uncompressed")
    if args.check:
        problems = validate(target)
        if problems:
            print(f"Package: {len(problems)} problems")
            for problem in problems:
                print("  " + problem)
            sys.exit(1)
        print("Package: OK (single MitzuMPlus/ folder, every TOC entry present, "
              "no tests/docs/tools/experimental files)")


if __name__ == "__main__":
    main()
