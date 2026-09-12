"""Generate the bundled MDT clone-geometry snapshot.

The generated Lua file is runtime-independent. Mythic Dungeon Tools is only a
development-time source and is never loaded or queried by MitzuMPlus at play
time.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from lupa import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
SOURCES = (
    (17, "KingsRest", "Kings' Rest"),
    (20, "TempleOfSethraliss", "Temple of Sethraliss"),
    (42, "RubyLifePools", "Ruby Life Pools"),
    (160, "MurderRow", "Murder Row"),
    (161, "DenOfNalorakk", "Den of Nalorakk"),
    (162, "TheBlindingVale", "The Blinding Vale"),
    (163, "VoidscarArena", "Voidscar Arena"),
    (164, "AltarOfFangs", "Altar of Fangs"),
)


def lua_number(value: object) -> str:
    number = float(value)
    if number.is_integer():
        return str(int(number))
    return format(number, ".15g")


def load_dungeon(lua: LuaRuntime, path: Path, dungeon_idx: int):
    mdt = lua.table()
    mdt.AddonName = "MythicDungeonTools"
    locale = lua.table()
    lua.eval("setmetatable")(locale, lua.table(__index=lua.eval("function(_, k) return k end")))
    mdt.L = locale
    for field in (
        "dungeonList", "mapInfo", "zoneIdToDungeonIdx", "dungeonMaps",
        "dungeonSubLevels", "mapPOIs", "dungeonTotalCount", "dungeonEnemies",
    ):
        setattr(mdt, field, lua.table())

    source = path.read_text(encoding="utf-8-sig")
    declared = re.search(r"local dungeonIndex\s*=\s*(\d+)", source)
    if not declared or int(declared.group(1)) != dungeon_idx:
        raise RuntimeError(f"Unexpected dungeonIndex in {path}")
    loader = lua.execute("return function(...) " + source + " end")
    loader("MythicDungeonTools", mdt)
    enemies = mdt.dungeonEnemies[dungeon_idx]
    if enemies is None:
        raise RuntimeError(f"No dungeonEnemies[{dungeon_idx}] in {path}")
    return enemies


def render_clone(clone) -> str:
    fields: list[str] = []
    for name in ("g", "sublevel", "x", "y"):
        value = clone[name]
        if value is not None:
            fields.append(f"{name}={lua_number(value)}")

    patrol = clone["patrol"]
    if patrol is not None:
        points = []
        for index in sorted(int(key) for key, _ in patrol.items()):
            point = patrol[index]
            points.append(
                "{x=" + lua_number(point["x"]) + ",y=" + lua_number(point["y"]) + "}"
            )
        fields.append("patrol={" + ",".join(points) + "}")
    return "{" + ",".join(fields) + "}"


def generate(mdt_root: Path, output: Path) -> None:
    toc = (mdt_root / "MythicDungeonTools.toc").read_text(encoding="utf-8-sig")
    version_match = re.search(r"^## Version:\s*(.+)$", toc, re.MULTILINE)
    version = version_match.group(1).strip() if version_match else "UNKNOWN"
    lua = LuaRuntime(unpack_returned_tuples=True)

    lines = [
        "-- ==========================================================================",
        "-- MitzuMPlus - data/MDTPhysicalGroupData.lua - GENERADO, NO EDITAR A MANO",
        "--",
        "-- Fuente: Mythic Dungeon Tools " + version + " (GPL-2.0), ficheros de datos.",
        "-- Generador: tools/generate_physical_group_data.py",
        "-- Clave: [mdtDungeonIdx][enemyIdx][cloneIdx].",
        "-- g es contexto fisico de MDT; NO implica combat pack, identidad ni MATCH.",
        "-- ==========================================================================",
        "",
        "local MitzuMPlus = _G.MitzuMPlus",
        "if not MitzuMPlus then return end",
        "",
        f'MitzuMPlus.MDTPhysicalGroupDataVersion = "MDT {version}"',
        "MitzuMPlus.MDTPhysicalGroupData = {",
    ]

    for dungeon_idx, filename, display_name in SOURCES:
        enemies = load_dungeon(lua, mdt_root / "Midnight" / f"{filename}.lua", dungeon_idx)
        lines.append(f"  -- {display_name}")
        lines.append(f"  [{dungeon_idx}] = {{")
        for enemy_idx in sorted(int(key) for key, _ in enemies.items()):
            clones = enemies[enemy_idx].clones
            if clones is None:
                continue
            rendered = []
            for clone_idx in sorted(int(key) for key, _ in clones.items()):
                rendered.append(f"[{clone_idx}]={render_clone(clones[clone_idx])}")
            lines.append(f"    [{enemy_idx}]={{" + ",".join(rendered) + "},")
        lines.append("  },")
    lines.extend(("}", ""))
    output.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--mdt-root", type=Path, default=ROOT.parent / "MythicDungeonTools",
        help="Path to a development checkout/install of MythicDungeonTools",
    )
    parser.add_argument(
        "--output", type=Path, default=ROOT / "data" / "MDTPhysicalGroupData.lua",
    )
    args = parser.parse_args()
    generate(args.mdt_root.resolve(), args.output.resolve())


if __name__ == "__main__":
    main()
