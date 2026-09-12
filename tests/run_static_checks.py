"""Syntax and wiring checks for the addon Lua sources."""

from pathlib import Path

from lupa import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    lua_files = sorted(ROOT.rglob("*.lua"))
    failures: list[str] = []
    lua = LuaRuntime(unpack_returned_tuples=True)
    compile_lua = lua.eval(
        "function(source, name) local f, err = load(source, name); "
        "return f ~= nil, err end"
    )
    for path in lua_files:
        ok, error = compile_lua(
            path.read_text(encoding="utf-8-sig"),
            "@" + str(path.relative_to(ROOT)),
        )
        if not ok:
            failures.append(f"{path.relative_to(ROOT)}: {error}")

    toc = (ROOT / "MitzuMPlus_Historial.toc").read_text(encoding="utf-8-sig")
    required_order = [
        r"data\MDTPhysicalGroupData.lua",
        r"modules\AdaptiveRoute\DataStructure.lua",
        r"modules\AdaptiveRoute\PhysicalGroupMetadata.lua",
        r"modules\AdaptiveRoute\EngagementEvidence.lua",
        r"modules\AdaptiveRoute\UnitLinkEvidence.lua",
        r"modules\AdaptiveRoute\PhysicalGroupCorrelation.lua",
        r"modules\AdaptiveRoute\PackEvidence.lua",
        r"modules\GuidanceEngine.lua",
        r"modules\RouteArrowPresenter.lua",
    ]
    positions = [toc.find(item) for item in required_order]
    wiring_ok = all(position >= 0 for position in positions) and positions == sorted(positions)
    if not wiring_ok:
        failures.append("TOC: Evidence/Guidance load order is missing or invalid")

    correlation = (ROOT / "modules" / "AdaptiveRoute" / "PhysicalGroupCorrelation.lua").read_text(
        encoding="utf-8-sig"
    )
    forbidden_integrations = [
        "AR.LiveEnemyResolver", "MitzuMPlus.GuidanceEngine",
        "MitzuMPlus.RouteArrowPresenter", "AR.RouteArrows",
        "MitzuMPlus.RouteProgress",
    ]
    for forbidden in forbidden_integrations:
        if forbidden in correlation:
            failures.append(f"PhysicalGroupCorrelation: forbidden integration {forbidden}")

    for evidence_name in ["CastEvidence.lua", "EventCastEvidence.lua"]:
        evidence = (ROOT / "modules" / "AdaptiveRoute" / evidence_name).read_text(
            encoding="utf-8-sig"
        )
        for forbidden in ["AR.LiveEnemyResolver", "MitzuMPlus.GuidanceEngine",
                          "MitzuMPlus.RouteArrowPresenter", "AR.RouteArrows",
                          "MitzuMPlus.RouteProgress"]:
            if forbidden in evidence:
                failures.append(f"{evidence_name}: forbidden identity integration {forbidden}")

    core = (ROOT / "modules" / "Core.lua").read_text(encoding="utf-8-sig")
    if "pcall(tonumber, spellID)" in core:
        failures.append("Core: secret spellID conversion path remains")

    checks = len(lua_files) + 1
    if failures:
        print(f"Static: {checks} checks, {len(failures)} failures")
        for failure in failures:
            print(failure)
        raise SystemExit(1)
    print(f"Static: {checks} checks, 0 failures ({len(lua_files)} Lua files parsed)")


if __name__ == "__main__":
    main()
