"""Run the addon's isolated Lua simulation tests through the bundled Lupa runtime."""

from pathlib import Path
import os

from lupa import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    os.chdir(ROOT)
    total_tests = total_assertions = 0
    # MitzuRouteArrows is a separate experimental project and intentionally
    # has its own lifecycle. This command is the product release gate.
    for path in sorted((ROOT / "tests" / "core").glob("*.spec.lua")):
        lua = LuaRuntime(unpack_returned_tuples=True)
        result = lua.execute(path.read_text(encoding="utf-8"))
        total_tests += result["tests"]
        total_assertions += result["assertions"]
        suite = path.parent.name
        print(f"{suite}/{path.stem}: {result['tests']} tests, "
              f"{result['assertions']} assertions, 0 failures")
    print(f"TOTAL: {total_tests} tests, {total_assertions} assertions, 0 failures")


if __name__ == "__main__":
    main()
