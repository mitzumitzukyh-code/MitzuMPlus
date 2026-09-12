"""Syntax and wiring checks for the addon Lua sources."""

import re
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

    # ── FASE 4: la capa de alineacion es DIAGNOSTICO. Estas prohibiciones son
    # la invariante del usuario ("identityWrites=0, resolverMatchesFabricated=0,
    # automaticRouteProgress=0") leida directamente del codigo fuente.
    # Los comentarios se quitan antes: un fichero tiene que poder explicar
    # por que no hace algo sin que la comprobacion lo confunda con hacerlo.
    def strip_lua_comments(source: str) -> str:
        return re.sub(r"--[^\n]*", "", source)

    alignment_modules = [
        "RouteSignature.lua",
        "ExecutionEpisodeTracker.lua",
        "RoutePullCandidateScorer.lua",
        "RouteAlignment.lua",
    ]
    forbidden_in_alignment = [
        "SetPull", "NextPull", "PreviousPull", "RestorePull",   # mover la ruta
        "MarkUnit", "UnmarkUnit", "RouteArrows",                # pintar flechas
        "ResolveForGuidance", "GuidanceEngine",                 # identidad canonica
        "RouteArrowPresenter",
        "UnitGUID", "UnitName",                                 # identidad cruda
        "COMBAT_LOG_EVENT_UNFILTERED",
    ]
    for module_name in alignment_modules:
        path = ROOT / "modules" / "AdaptiveRoute" / module_name
        if not path.exists():
            failures.append(f"Alignment: missing module {module_name}")
            continue
        source = strip_lua_comments(path.read_text(encoding="utf-8-sig"))
        for forbidden in forbidden_in_alignment:
            if forbidden in source:
                failures.append(f"{module_name}: forbidden phase-4 usage {forbidden}")

        # El vocabulario de identidad canónica no puede existir en la capa
        # experimental, ni siquiera como estado o literal fabricable.
        identity_free = source.replace("MISMATCH", "")
        if "MATCH" in identity_free:
            failures.append(f"{module_name}: alignment cannot produce identity MATCH")
        if "matchState" in source:
            failures.append(f"{module_name}: alignment cannot write resolver matchState")

    alignment_source = "\n".join(
        strip_lua_comments(
            (ROOT / "modules" / "AdaptiveRoute" / name).read_text(encoding="utf-8-sig")
        )
        for name in alignment_modules
    )
    progress_write_patterns = [
        r"RouteProgress\s*[:.]\s*SetPull\s*\(",
        r"RouteProgress\s*[:.]\s*NextPull\s*\(",
        r"RouteProgress\s*[:.]\s*PreviousPull\s*\(",
        r"RouteProgress\s*[:.]\s*RestorePull\s*\(",
        r"\.routeCurrentPull\s*=",
        r"rawset\s*\([^\n]*routeCurrentPull",
    ]
    for pattern in progress_write_patterns:
        if re.search(pattern, alignment_source):
            failures.append(f"Alignment: progress authority found: {pattern}")

    # EventCastEvidence puede aportar presencia temporal, nunca su payload.
    temporal_modules = "\n".join(
        strip_lua_comments(
            (ROOT / "modules" / "AdaptiveRoute" / name).read_text(encoding="utf-8-sig")
        )
        for name in ["ExecutionEpisodeTracker.lua", "RoutePullCandidateScorer.lua",
                     "RouteAlignment.lua"]
    )
    if re.search(r"spellID|safeSpellID|castGUID", temporal_modules, re.IGNORECASE):
        failures.append("Alignment: EventCast payload crossed the temporal-engagement boundary")

    init = (ROOT / "Init.lua").read_text(encoding="utf-8-sig")
    detail_contract = [
        'cmd == "alignmentdetail"', "RAl:DetailLines()",
        "progressWrites=0", "resolverResults=0", "arrowEffects=0",
        "eventCastRole=TEMPORAL_ENGAGEMENT_ONLY", "bestCandidate=",
        "runnerUp=", "margin=", "reasons=",
    ]
    detail_source = (ROOT / "modules" / "AdaptiveRoute" / "RouteAlignment.lua").read_text(
        encoding="utf-8-sig"
    )
    for required in detail_contract:
        hay = required in init or required in detail_source
        if not hay:
            failures.append(f"alignmentdetail: missing contract marker {required}")

    scorer = strip_lua_comments(
        (ROOT / "modules" / "AdaptiveRoute" / "RoutePullCandidateScorer.lua")
        .read_text(encoding="utf-8-sig")
    )
    for impure in ["GetTime", "CreateFrame", "C_Timer", "RegisterEvent"]:
        if impure in scorer:
            failures.append(f"RoutePullCandidateScorer: must stay pure, found {impure}")
    if "MATCH" in scorer.replace("MISMATCH", ""):
        failures.append("RoutePullCandidateScorer: the word MATCH means identity in Mitzu")

    alignment_order = [
        r"modules\AdaptiveRoute\ArrowDemo.lua",
        r"modules\AdaptiveRoute\RouteSignature.lua",
        r"modules\AdaptiveRoute\ExecutionEpisodeTracker.lua",
        r"modules\AdaptiveRoute\RoutePullCandidateScorer.lua",
        r"modules\AdaptiveRoute\RouteAlignment.lua",
        r"modules\AdaptiveRoute\Bootstrap.lua",
    ]
    alignment_positions = [toc.find(item) for item in alignment_order]
    if not (all(p >= 0 for p in alignment_positions)
            and alignment_positions == sorted(alignment_positions)):
        failures.append("TOC: phase-4 alignment load order is missing or invalid")

    arrow_demo = strip_lua_comments(
        (ROOT / "modules" / "AdaptiveRoute" / "ArrowDemo.lua").read_text(encoding="utf-8-sig")
    )
    if "pcall(RAl.Feed" not in arrow_demo:
        failures.append("ArrowDemo: the alignment layer is no longer fed from the tick")

    checks += len(alignment_modules) * 3 + len(progress_write_patterns) + 2
    checks += len(detail_contract) + 3

    if failures:
        print(f"Static: {checks} checks, {len(failures)} failures")
        for failure in failures:
            print(failure)
        raise SystemExit(1)
    print(f"Static: {checks} checks, 0 failures ({len(lua_files)} Lua files parsed)")


if __name__ == "__main__":
    main()
