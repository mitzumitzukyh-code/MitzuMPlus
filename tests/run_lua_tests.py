"""Run the addon's isolated Lua simulation tests through the bundled Lupa runtime.

Every spec runs twice: on Lua 5.4 (Lupa's default) and on Lua 5.1, the
language version the WoW client embeds, so 5.1-only breakage shows up here
instead of in the game.
"""

from pathlib import Path
import os

from lupa import LuaRuntime
from lupa import lua51


ROOT = Path(__file__).resolve().parents[1]
RUNTIMES = [("5.4", LuaRuntime, ""), ("5.1", lua51.LuaRuntime, "table.unpack = table.unpack or unpack")]


def main() -> None:
    os.chdir(ROOT)
    for label, runtime, prelude in RUNTIMES:
        total_tests = total_assertions = 0
        # MitzuRouteArrows is a separate experimental project and intentionally
        # has its own lifecycle. This command is the product release gate.
        for path in sorted((ROOT / "tests" / "core").glob("*.spec.lua")):
            lua = runtime(unpack_returned_tuples=True)
            if prelude:
                lua.execute(prelude)
            result = lua.execute(path.read_text(encoding="utf-8"))
            total_tests += result["tests"]
            total_assertions += result["assertions"]
            suite = path.parent.name
            print(f"[Lua {label}] {suite}/{path.stem}: {result['tests']} tests, "
                  f"{result['assertions']} assertions, 0 failures")
        print(f"TOTAL Lua {label}: {total_tests} tests, {total_assertions} assertions, 0 failures")


if __name__ == "__main__":
    main()
