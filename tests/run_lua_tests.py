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
# WoW's Lua 5.1 xpcall forwards extra arguments to the called function (Ace3's
# safecall relies on it); stock 5.1 drops them, which silently skipped
# AceAddon OnInitialize (no MitzuMPlus.db) on the 5.1 run until 1.1.0-dev.5.
LUA51_PRELUDE = """
table.unpack = table.unpack or unpack
do
    local base = xpcall
    xpcall = function(f, handler, ...)
        local n = select('#', ...)
        if n == 0 then return base(f, handler) end
        local args = { ... }
        return base(function() return f(unpack(args, 1, n)) end, handler)
    end
end
"""
RUNTIMES = [("5.4", LuaRuntime, ""), ("5.1", lua51.LuaRuntime, LUA51_PRELUDE)]


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
    # Specs for phases not implemented yet: parsed by the static checks, never run.
    for path in sorted((ROOT / "tests" / "pending").glob("*.spec.lua")):
        print(f"PENDING (not executed): {path.parent.name}/{path.stem}")


if __name__ == "__main__":
    main()
