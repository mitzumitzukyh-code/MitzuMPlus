"""Sync the MitzuMPlus runtime files into the WoW PTR AddOns folder.

    python tools/deploy_ptr.py --dry-run     -> show what would change, touch nothing
    python tools/deploy_ptr.py               -> back up the PTR copy, then replace it
    python tools/deploy_ptr.py --verify      -> only compare the PTR copy with the repo

Rules:
  * Only the PTR (`_xptr_`) is a valid target. A path under `_retail_` is refused.
  * The existing PTR copy is backed up before it is replaced.
  * Only runtime files (same allowlist as the CurseForge packager) are copied:
    no .git, tests, docs, tools, zips or temporary files.
  * The result must be AddOns/MitzuMPlus/MitzuMPlus.toc, never a nested
    AddOns/MitzuMPlus/MitzuMPlus/ folder, and every TOC entry must exist.

This script never uploads, tags or publishes anything.
"""

import argparse
import datetime
import filecmp
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import package_mitzumplus as pkg  # noqa: E402  (shared runtime allowlist)

ROOT = pkg.ROOT
SOURCE = pkg.SOURCE
ADDON = pkg.ADDON
DEFAULT_TARGET = Path(r"D:\World of Warcraft\_xptr_\Interface\AddOns") / ADDON
DEFAULT_BACKUPS = Path(r"D:\Mitzu_Backups")


def runtime_files() -> dict[str, Path]:
    return {p.relative_to(SOURCE).as_posix(): p for p in pkg.package_files()}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def toc_version(toc: Path) -> str:
    for line in toc.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("## Version:"):
            return line.split(":", 1)[1].strip()
    return "unknown"


def wow_ptr_running() -> bool:
    try:
        out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq WowT.exe"], capture_output=True, text=True).stdout
    except OSError:
        return False
    return "WowT.exe" in out


def guard_target(target: Path) -> None:
    parts = [p.lower() for p in target.resolve().parts]
    if "_retail_" in parts or "_classic_" in parts or "_beta_" in parts:
        raise SystemExit(f"refused: {target} is not a PTR install")
    if "_xptr_" not in parts and "_ptr_" not in parts:
        raise SystemExit(f"refused: {target} is not under a PTR folder (_xptr_ / _ptr_)")
    if target.name != ADDON or target.parent.name.lower() != "addons":
        raise SystemExit(f"refused: target must be .../Interface/AddOns/{ADDON}, got {target}")
    if not target.parent.is_dir():
        raise SystemExit(f"refused: AddOns folder does not exist: {target.parent}")


def compare(target: Path) -> tuple[list[str], list[str], list[str]]:
    """(missing or changed in target, extra in target, identical)."""
    source = runtime_files()
    changed, same = [], []
    for rel, path in source.items():
        dest = target / rel
        if not dest.is_file() or not filecmp.cmp(path, dest, shallow=False):
            changed.append(rel)
        else:
            same.append(rel)
    extra = []
    if target.is_dir():
        for dest in target.rglob("*"):
            if dest.is_file() and dest.relative_to(target).as_posix() not in source:
                extra.append(dest.relative_to(target).as_posix())
    return sorted(changed), sorted(extra), same


def validate(target: Path) -> list[str]:
    problems = []
    toc = target / f"{ADDON}.toc"
    if not toc.is_file():
        problems.append(f"missing {toc}")
        return problems
    if (target / ADDON).exists():
        problems.append(f"nested addon folder: {target / ADDON}")
    for entry in pkg.toc_entries(toc.read_text(encoding="utf-8-sig")):
        if not (target / entry).is_file():
            problems.append(f"TOC entry missing in PTR copy: {entry}")
    source = runtime_files()
    for dest in target.rglob("*"):
        if dest.is_file():
            rel = dest.relative_to(target).as_posix()
            if rel not in source:
                problems.append(f"non-runtime or stale file in PTR copy: {rel}")
            elif sha256(dest) != sha256(source[rel]):
                problems.append(f"content differs from repo: {rel}")
    for rel in source:
        if not (target / rel).is_file():
            problems.append(f"repo runtime file missing in PTR copy: {rel}")
    return problems


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET)
    parser.add_argument("--backups", type=Path, default=DEFAULT_BACKUPS)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()

    target = args.target
    guard_target(target)
    version = toc_version(SOURCE / f"{ADDON}.toc")
    installed = toc_version(target / f"{ADDON}.toc") if (target / f"{ADDON}.toc").is_file() else None
    changed, extra, same = compare(target)
    print(f"repo {ADDON} {version} -> {target}")
    print(f"installed: {installed or 'none'}; runtime files: {len(changed) + len(same)}; "
          f"changed/new: {len(changed)}; extra in PTR: {len(extra)}")
    for rel in changed:
        print(f"  + {rel}")
    for rel in extra:
        print(f"  - {rel}")

    if args.verify:
        problems = validate(target) if target.is_dir() else [f"missing {target}"]
        print("PTR copy: OK" if not problems else f"PTR copy: {len(problems)} problems")
        for problem in problems:
            print("  " + problem)
        sys.exit(1 if problems else 0)
    if args.dry_run:
        print("dry run: nothing changed")
        return
    if not changed and not extra:
        print("PTR copy already matches the repo; nothing to do")
        return

    if wow_ptr_running():
        print("note: WowT.exe is running. Files are replaced on disk; the client only "
              "reads them on /reload, and TOC changes need a full client restart.")

    staging = target.with_name(f"{ADDON}.__staging")
    if staging.exists():
        shutil.rmtree(staging)
    for rel, path in runtime_files().items():
        dest = staging / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
    if not (staging / f"{ADDON}.toc").is_file():
        shutil.rmtree(staging)
        raise SystemExit("staging has no TOC; aborted before touching the PTR copy")

    if target.exists():
        stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        backup = args.backups / f"{stamp}_ptr_{ADDON}_{installed or 'unknown'}" / ADDON
        backup.parent.mkdir(parents=True, exist_ok=False)
        shutil.copytree(target, backup)
        print(f"backup: {backup}")
        shutil.rmtree(target)
    staging.rename(target)

    problems = validate(target)
    if problems:
        print(f"deployed with {len(problems)} problems:")
        for problem in problems:
            print("  " + problem)
        sys.exit(1)
    print(f"deployed {ADDON} {version} to PTR: OK ({len(runtime_files())} runtime files, "
          f"TOC at {target / (ADDON + '.toc')})")


if __name__ == "__main__":
    main()
