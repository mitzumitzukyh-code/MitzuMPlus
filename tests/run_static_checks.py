"""Static checks for the two addons in this repository.

MitzuMPlus        -> the product (CurseForge). Must not contain experimental code.
MitzuRouteArrows  -> experimental. Reads MitzuMPlus only through MitzuMPlusAPI.

Every Lua file is compiled, both TOCs are validated, and the architectural
rules of the split are read straight from the source code. Comments are
stripped before searching: a file must be able to explain why it does NOT do
something without the check mistaking the explanation for the act.
"""

import re
from pathlib import Path

from lupa import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "MitzuMPlus"
MRA = ROOT / "MitzuRouteArrows"

EXPERIMENTAL_MODULES = [
    "RouteArrows", "NameplateAnchorProvider", "NameplateGenerations",
    "PullUnitResolver", "LiveEnemyResolver", "ArrowDemo", "ArrowDemoTelemetry",
    "GuidanceEngine", "RouteArrowPresenter",
    "EngagementEvidence", "UnitLinkEvidence", "CastEvidence", "AuraEvidence",
    "EventCastEvidence", "PackEvidence", "PhysicalGroupMetadata",
    "PhysicalGroupCorrelation", "MDTPhysicalGroupData",
    "RouteSignature", "ExecutionEpisodeTracker", "RoutePullCandidateScorer",
    "RouteAlignment",
]


class Checks:
    def __init__(self) -> None:
        self.count = 0
        self.failures: list[str] = []

    def check(self, ok: bool, message: str) -> None:
        self.count += 1
        if not ok:
            self.failures.append(message)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def lua_code(source: str, keep_strings: bool = True) -> str:
    """Lua source without comments; string contents blanked if keep_strings is False."""
    out: list[str] = []
    i, n = 0, len(source)
    while i < n:
        c = source[i]
        if source.startswith("--", i):
            m = re.match(r"--\[(=*)\[", source[i:])
            if m:
                end = source.find("]" + m.group(1) + "]", i + len(m.group(0)))
                i = n if end < 0 else end + len(m.group(1)) + 2
            else:
                end = source.find("\n", i)
                i = n if end < 0 else end
            out.append(" ")
        elif c in "\"'":
            j = i + 1
            while j < n and source[j] != c and source[j] != "\n":
                j += 2 if source[j] == "\\" else 1
            out.append(source[i:j + 1] if keep_strings else '""')
            i = j + 1
        elif c == "[" and re.match(r"\[=*\[", source[i:]):
            m = re.match(r"\[(=*)\[", source[i:])
            end = source.find("]" + m.group(1) + "]", i + len(m.group(0)))
            stop = n if end < 0 else end + len(m.group(1)) + 2
            out.append(source[i:stop] if keep_strings else '""')
            i = stop
        else:
            out.append(c)
            i += 1
    return "".join(out)


def toc_files(toc: Path) -> list[str]:
    files = []
    for line in read(toc).splitlines():
        entry = line.strip()
        if entry and not entry.startswith("#"):
            files.append(entry.replace("\\", "/"))
    return files


def toc_meta(toc: Path) -> dict[str, str]:
    meta = {}
    for line in read(toc).splitlines():
        m = re.match(r"^##\s*([\w\-]+)\s*:\s*(.*?)\s*$", line)
        if m:
            meta[m.group(1)] = m.group(2)
    return meta


def in_order(files: list[str], names: list[str]) -> bool:
    positions = []
    for name in names:
        matches = [i for i, f in enumerate(files) if f.endswith(name)]
        if not matches:
            return False
        positions.append(matches[0])
    return positions == sorted(positions)


def compile_all(c: Checks) -> list[Path]:
    lua = LuaRuntime(unpack_returned_tuples=True)
    compile_lua = lua.eval(
        "function(source, name) local f, err = load(source, name); "
        "return f ~= nil, err end"
    )
    lua_files = sorted(
        p for p in ROOT.rglob("*.lua")
        if ".git" not in p.parts and "dist" not in p.parts
    )
    for path in lua_files:
        ok, error = compile_lua(read(path), "@" + rel(path))
        c.check(ok, f"{rel(path)}: {error}")
    return lua_files


def check_core_toc(c: Checks) -> None:
    toc = CORE / "MitzuMPlus.toc"
    c.check(toc.exists(), "MitzuMPlus/MitzuMPlus.toc is missing (TOC name must match folder)")
    meta = toc_meta(toc)
    files = toc_files(toc)
    c.check(meta.get("Title") == "MitzuMPlus", "core TOC: Title must be MitzuMPlus")
    for key in ["Interface", "Version", "Author", "Notes", "SavedVariables", "IconTexture"]:
        c.check(bool(meta.get(key)), f"core TOC: missing ## {key}")
    c.check("dev" not in meta.get("Version", ""), "core TOC: release version must not be -dev")
    c.check("Dependencies" not in meta and "RequiredDeps" not in meta,
            "core TOC: the product must not have required dependencies")
    c.check("MythicDungeonTools" in meta.get("OptionalDeps", ""),
            "core TOC: MythicDungeonTools must be optional")
    c.check("MitzuRouteArrows" not in meta.get("OptionalDeps", "") + meta.get("Dependencies", ""),
            "core TOC: core must not depend on MitzuRouteArrows")
    c.check("Historial" not in meta.get("Title", "") and "Historial" not in meta.get("IconTexture", ""),
            "core TOC: old MitzuMPlus_Historial name remains")
    c.check("MitzuMPlus\\" in meta.get("IconTexture", ""), "core TOC: IconTexture must point to the MitzuMPlus folder")

    for entry in files:
        c.check((CORE / entry).exists(), f"core TOC: listed file missing: {entry}")
    for name in EXPERIMENTAL_MODULES:
        c.check(not any(f.endswith("/" + name + ".lua") or f == name + ".lua" for f in files),
                f"core TOC: experimental module loaded by the product: {name}")
    c.check(not any(f.startswith(("Evidence/", "Alignment/")) for f in files),
            "core TOC: Evidence/Alignment folders loaded by the product")
    c.check(in_order(files, ["modules/EventBus.lua", "modules/RouteProgress.lua",
                             "AdaptiveRoute/PullNavigator.lua", "API/PublicAPI.lua", "Init.lua"]),
            "core TOC: PublicAPI must load after RouteProgress/PullNavigator and before Init")

    # No Lua file of the product lives outside its TOC (dead files).
    listed = {(CORE / f).resolve() for f in files}
    xml_dirs = [(CORE / f).parent.resolve() for f in files if f.endswith(".xml")]
    for path in CORE.rglob("*.lua"):
        covered = path.resolve() in listed or any(d in path.resolve().parents for d in xml_dirs)
        c.check(covered, f"core: Lua file not loaded by the TOC (dead file): {rel(path)}")

    # Only runtime files in the package folder.
    for path in CORE.rglob("*"):
        if path.is_file():
            ok = path.suffix.lower() in {".lua", ".toc", ".xml", ".tga", ".blp", ".ogg", ".ttf"} \
                or path.name in {"DATA_SOURCES.md", "LICENSE.txt"}
            c.check(ok, f"core: development file inside the package folder: {rel(path)}")


def check_core_isolation(c: Checks) -> None:
    forbidden_ids = set(EXPERIMENTAL_MODULES) | {
        "MitzuRouteArrows", "MitzuRouteArrowsDB", "ThreatPlates", "TidyPlatesThreat", "Plater",
        "MitzuMPlusEventBus",
    }
    for path in sorted(CORE.rglob("*.lua")):
        if "libs" in path.relative_to(CORE).parts:
            continue
        code = lua_code(read(path), keep_strings=False)
        ids = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", code))
        hits = sorted(ids & forbidden_ids)
        c.check(not hits, f"{rel(path)}: core references experimental code: {hits}")
        strings = set(re.findall(r"[\"']([A-Za-z]+)[\"']", lua_code(read(path))))
        by_name = sorted(strings & set(EXPERIMENTAL_MODULES))
        c.check(not by_name, f"{rel(path)}: core looks up experimental module by name: {by_name}")
        c.check(not re.search(r"(^|[^.\w])SlashCmdList\s*=", code),
                f"{rel(path)}: reassigns the Blizzard global SlashCmdList (taint)")

    bindings = read(CORE / "Bindings.xml")
    c.check("MARK_TARGET" not in bindings, "core Bindings.xml: mark-target binding belongs to MitzuRouteArrows")

    core_lua = read(CORE / "modules" / "Core.lua")
    c.check("pcall(tonumber, spellID)" not in core_lua, "Core: secret spellID conversion path remains")

    api = lua_code(read(CORE / "API" / "PublicAPI.lua"), keep_strings=False)
    names = re.findall(r"function API\.(\w+)\s*\(", api)
    c.check(len(names) >= 30, "PublicAPI: API functions not found")
    writers = [n for n in names if re.match(r"(Set|Next|Prev|Restore|Start|Stop|Complete|Clear|Import|Load|Write)", n)
               or "Reset" in n]
    c.check(not writers, f"PublicAPI: writer in the read-only API: {writers}")
    c.check("__newindex" in api and "__metatable = false" in api,
            "PublicAPI: export must be a read-only proxy")
    for internal_writer in ["SetPull", "NextPull", "PreviousPull", "RestorePull", "SetCurrentPull",
                            ":Emit", ":Save", ":Prepare", ":Start", ":Complete", ":Reset"]:
        c.check(internal_writer not in api, f"PublicAPI: calls a core writer: {internal_writer}")


def check_mra_toc(c: Checks) -> list[str]:
    toc = MRA / "MitzuRouteArrows.toc"
    c.check(toc.exists(), "MitzuRouteArrows/MitzuRouteArrows.toc is missing")
    meta = toc_meta(toc)
    core_meta = toc_meta(CORE / "MitzuMPlus.toc")
    files = toc_files(toc)
    c.check("EXPERIMENTAL" in meta.get("Title", ""), "MRA TOC: Title must say EXPERIMENTAL")
    c.check(meta.get("X-Status") == "EXPERIMENTAL", "MRA TOC: X-Status must be EXPERIMENTAL")
    c.check("dev" in meta.get("Version", ""), "MRA TOC: version must be a development version")
    c.check(meta.get("Interface") == core_meta.get("Interface"), "MRA TOC: Interface differs from core")
    c.check(meta.get("SavedVariables") == "MitzuRouteArrowsDB", "MRA TOC: own SavedVariables only")
    c.check("MitzuMPlus" in meta.get("OptionalDeps", ""), "MRA TOC: MitzuMPlus must load first (OptionalDeps)")
    for entry in files:
        c.check((MRA / entry).exists(), f"MRA TOC: listed file missing: {entry}")
    c.check(files[:2] == ["Core/Bootstrap.lua", "Core/Host.lua"], "MRA TOC: Bootstrap and Host must load first")
    c.check(files[-2:] == ["Core/Lifecycle.lua", "Core/Commands.lua"], "MRA TOC: Lifecycle and Commands must load last")
    c.check(in_order(files, [
        "Data/MDTPhysicalGroupData.lua", "Evidence/PhysicalGroupMetadata.lua",
        "Evidence/PhysicalGroupCorrelation.lua", "Evidence/PackEvidence.lua",
        "Modules/GuidanceEngine.lua", "Modules/RouteArrowPresenter.lua",
    ]), "MRA TOC: Evidence/Guidance load order is missing or invalid")
    c.check(in_order(files, [
        "Evidence/EngagementEvidence.lua", "Evidence/UnitLinkEvidence.lua",
        "Evidence/PhysicalGroupCorrelation.lua",
    ]), "MRA TOC: correlation must load after engagement and token-link evidence")
    c.check(in_order(files, [
        "Modules/ArrowDemo.lua", "Alignment/RouteSignature.lua",
        "Alignment/ExecutionEpisodeTracker.lua", "Alignment/RoutePullCandidateScorer.lua",
        "Alignment/RouteAlignment.lua", "Core/Lifecycle.lua",
    ]), "TOC: phase-4 alignment load order is missing or invalid")
    listed = {(MRA / f).resolve() for f in files}
    for path in MRA.rglob("*.lua"):
        c.check(path.resolve() in listed, f"MRA: Lua file not loaded by the TOC: {rel(path)}")
    return files


def check_mra_isolation(c: Checks, files: list[str]) -> None:
    api_sites = []
    for entry in files:
        path = MRA / entry
        source = read(path)
        code = lua_code(source, keep_strings=False)
        ids = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", code))
        for forbidden in ["MitzuMPlus", "MitzuMPlusDB", "MPlusAdaptiveRouteDB", "MitzuMPlusEventBus", "LibStub"]:
            c.check(forbidden not in ids, f"{rel(path)}: MitzuRouteArrows uses {forbidden} (only MitzuMPlusAPI is allowed)")
        literal = lua_code(source)
        for forbidden in ['"MitzuMPlus"', "'MitzuMPlus'", "MitzuMPlusDB", "MPlusAdaptiveRouteDB", "AceAddon-3.0"]:
            c.check(forbidden not in literal, f"{rel(path)}: MitzuRouteArrows names {forbidden}")
        if "MitzuMPlusAPI" in ids or '"MitzuMPlusAPI"' in literal:
            api_sites.append(entry)
        for writer in ["SetPull", "NextPull", "PreviousPull", "RestorePull", "SetCurrentPull",
                       "routeCurrentPull", "RunSession"]:
            c.check(writer not in ids, f"{rel(path)}: MitzuRouteArrows names core writer {writer}")
        c.check(not re.search(r"(^|[^.\w])SlashCmdList\s*=", code),
                f"{rel(path)}: reassigns the Blizzard global SlashCmdList (taint)")
        c.check(not re.search(r"(rawset|setfenv|debug\.setmetatable)|setmetatable\s*\(\s*_G", code),
                f"{rel(path)}: raw writes could bypass the read-only API proxy")
    c.check(api_sites == ["Core/Bootstrap.lua"], f"MRA: MitzuMPlusAPI must be located only in Core/Bootstrap, found {api_sites}")

    host = lua_code(read(MRA / "Core" / "Host.lua"), keep_strings=False)
    host_methods = re.findall(r"(\w+)\s*=\s*function\s*\(", host) + re.findall(r"function\s+Host[:.](\w+)\s*\(", host)
    c.check(len(host_methods) >= 15, "Host: facade methods not found")
    writers = [m for m in host_methods if re.match(r"(Set|Next|Prev|Restore|Start|Complete|Mark|Save|Emit|Write)", m)
               or "Reset" in m]
    c.check(not writers, f"Host: facade exposes writers: {writers}")

    commands = lua_code(read(MRA / "Core" / "Commands.lua"))
    c.check('SLASH_MITZUROUTEARROWS1 = "/mra"' in commands, "MRA: /mra slash command missing")
    core_init = lua_code(read(CORE / "Init.lua"))
    c.check('RegisterChatCommand("emp"' in core_init, "core: /emp slash command missing")
    c.check('"/mra"' not in core_init and '"mra"' not in core_init, "core: registers /mra")
    for moved in ["alignmentdetail", "alignment", "evidence", "castevidence", "eventcast", "plates",
                  "arrowdemo", "marktarget", "guidance"]:
        c.check(f'cmd == "{moved}"' not in core_init, f"core: still handles moved command /emp {moved}")
        c.check(f'COMANDOS["{moved}"]' in commands, f"MRA: /mra {moved} missing")


def check_alignment_rules(c: Checks) -> None:
    """FASE 4: alignment is DIAGNOSTIC. identityWrites=0, resolverMatchesFabricated=0,
    automaticRouteProgress=0, read from the source."""
    alignment = MRA / "Alignment"
    modules = ["RouteSignature.lua", "ExecutionEpisodeTracker.lua",
               "RoutePullCandidateScorer.lua", "RouteAlignment.lua"]
    forbidden = [
        "SetPull", "NextPull", "PreviousPull", "RestorePull",
        "MarkUnit", "UnmarkUnit", "RouteArrows",
        "ResolveForGuidance", "GuidanceEngine", "RouteArrowPresenter",
        "UnitGUID", "UnitName", "COMBAT_LOG_EVENT_UNFILTERED",
    ]
    sources = {}
    for name in modules:
        path = alignment / name
        c.check(path.exists(), f"Alignment: missing module {name}")
        if not path.exists():
            continue
        # The addon's own name contains "RouteArrows"; it is not a reference to the module.
        source = lua_code(read(path)).replace("MitzuRouteArrows", "MRA_ADDON")
        sources[name] = source
        for word in forbidden:
            c.check(word not in source, f"{name}: forbidden phase-4 usage {word}")
        c.check("MATCH" not in source.replace("MISMATCH", ""), f"{name}: alignment cannot produce identity MATCH")
        c.check("matchState" not in source, f"{name}: alignment cannot write resolver matchState")

    joined = "\n".join(sources.values())
    for pattern in [r"RouteProgress\s*[:.]\s*SetPull\s*\(", r"RouteProgress\s*[:.]\s*NextPull\s*\(",
                    r"RouteProgress\s*[:.]\s*PreviousPull\s*\(", r"RouteProgress\s*[:.]\s*RestorePull\s*\(",
                    r"\.routeCurrentPull\s*=", r"rawset\s*\([^\n]*routeCurrentPull"]:
        c.check(not re.search(pattern, joined), f"Alignment: progress authority found: {pattern}")

    temporal = "\n".join(sources.get(n, "") for n in modules[1:])
    c.check(not re.search(r"spellID|safeSpellID|castGUID", temporal, re.IGNORECASE),
            "Alignment: EventCast payload crossed the temporal-engagement boundary")

    detail_contract = [
        'COMANDOS["alignmentdetail"]', "RAl:DetailLines()",
        "authority=NONE", "progressWrites=0", "matchAuthority=NONE", "arrowWrites=0",
        "eventCastRole=TEMPORAL_ENGAGEMENT_ONLY", "bestCandidate=",
        "runnerUp=", "candidateMargin=", "candidateScore=", "episodeConfidence=",
        'candidateSignal("npcComposition"', 'candidateSignal("multiplicity"',
        'candidateSignal("bossAnchor"', 'episodeSignal("engagement"',
        'episodeSignal("recentEvent"', 'episodeSignal("tokenLink"', "reasons=",
    ]
    commands = read(MRA / "Core" / "Commands.lua")
    detail = read(alignment / "RouteAlignment.lua")
    for marker in detail_contract:
        c.check(marker in commands or marker in detail, f"alignmentdetail: missing contract marker {marker}")

    scorer = sources.get("RoutePullCandidateScorer.lua", "")
    for impure in ["GetTime", "CreateFrame", "C_Timer", "RegisterEvent"]:
        c.check(impure not in scorer, f"RoutePullCandidateScorer: must stay pure, found {impure}")
    score_one = scorer.partition("function Scorer:ScoreOne")[2].partition("function Scorer:EpisodeConfidence")[0]
    c.check(bool(score_one), "RoutePullCandidateScorer: ScoreOne not found")
    for signal in ["engagementConsistency", "castActivity", "eventEngagement", "tokenLinkage"]:
        c.check(signal not in score_one, f"RoutePullCandidateScorer: global signal entered candidateScore: {signal}")
    ranking = scorer.partition("function Scorer:Evaluate")[2]
    c.check("a.candidateScore" in ranking and "candidateMargin" in ranking,
            "RoutePullCandidateScorer: ranking is not explicitly candidate-only")

    demo = lua_code(read(MRA / "Modules" / "ArrowDemo.lua"))
    c.check("pcall(RAl.Feed" in demo, "ArrowDemo: the alignment layer is no longer fed from the tick")
    tick = demo.partition("function ArrowDemo:_Tick")[2].partition("function ArrowDemo:SafeTick")[0]
    c.check(bool(tick), "ArrowDemo: _Tick not found")
    c.check(not ("RAl:Get" in tick or re.search(r"self:Decide\([^)]*RAl", tick, re.DOTALL)),
            "ArrowDemo: alignment result crossed into arrow decision")
    bridge = demo.partition("local function eventCastDe")[2].partition("local function esperados")[0]
    c.check(bool(bridge), "ArrowDemo: EventCast bridge not found")
    c.check(not re.search(r"safeSpellID|spellIDState|castGUID|\.spellID", bridge, re.IGNORECASE),
            "ArrowDemo: EventCast identity payload crossed the bridge")


def check_evidence_rules(c: Checks) -> None:
    identity = ["AR.LiveEnemyResolver", "AR.GuidanceEngine", "AR.RouteArrowPresenter",
                "AR.RouteArrows", "MRA.LiveEnemyResolver", "MRA.GuidanceEngine",
                "MRA.RouteArrowPresenter", "MRA.RouteArrows", "RouteProgress"]
    for name in ["PhysicalGroupCorrelation.lua", "CastEvidence.lua", "EventCastEvidence.lua"]:
        source = lua_code(read(MRA / "Evidence" / name))
        for word in identity:
            c.check(word not in source, f"{name}: forbidden identity integration {word}")


def check_repo_layout(c: Checks) -> None:
    for required in ["README.md", "CHANGELOG.md", "LICENSE", "docs/ARCHITECTURE.md", "docs/RELEASE.md",
                     "tools/package_mitzumplus.py"]:
        c.check((ROOT / required).exists(), f"repo: missing {required}")
    for legacy in ["MitzuMPlus_Historial.toc", "Init.lua", "modules", "UI", "libs"]:
        c.check(not (ROOT / legacy).exists(), f"repo: legacy root entry still present: {legacy}")


def main() -> None:
    c = Checks()
    lua_files = compile_all(c)
    check_core_toc(c)
    check_core_isolation(c)
    mra_files = check_mra_toc(c)
    check_mra_isolation(c, mra_files)
    check_alignment_rules(c)
    check_evidence_rules(c)
    check_repo_layout(c)

    if c.failures:
        print(f"Static: {c.count} checks, {len(c.failures)} failures ({len(lua_files)} Lua files parsed)")
        for failure in c.failures:
            print(failure)
        raise SystemExit(1)
    print(f"Static: {c.count} checks, 0 failures ({len(lua_files)} Lua files parsed)")


if __name__ == "__main__":
    main()
