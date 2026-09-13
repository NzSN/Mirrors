"""Fail-closed comparison of observations; this alone reads expectations."""
from __future__ import annotations

from collections import Counter
from corpus import ENGINES, FACT_IDS, validate_contract, validate_registry
from normalize import ordered
from capture import fixture_input_digest
from pathlib import Path
import hashlib


_STAGE_ORDER = {"lex": 0, "parse": 1, "moduleGraph": 2, "nameResolution": 3, "substitution": 4, "level": 5, "sourceEvidence": 6}


def fact_value(observation, fact):
    item = observation.get("facts", {}).get(fact, {})
    if item.get("capability") != "supported":
        raise ValueError(f"{fact} is not observed")
    return item["value"]


def projection(fact, value):
    if fact == "variables":
        return ordered([{key: row[key] for key in ("name", "declaredIn", "declaredName")} for row in value])
    if fact == "resolution":
        return {key: ordered(value[key]) for key in ("dependencies", "operators")}
    return ordered(value) if isinstance(value, list) else value


def compare_corpus(captured, observations, registry, identities=None):
    """Return comparison rows, coverage and verdict with fixed denominators.

    Reviewed entries have exact per-engine expected values per fact:
    expected[fact] = {"mirrors": value, "sany"|"apalache": value}.
    No entry can excuse an execution failure or missing observation.
    """
    validate_registry(registry, captured.fixtures)
    rows = []

    def add(fixture, engine, fact, status, detail, expected=None, actual=None):
        rows.append({"fixture": fixture, "engine": engine, "fact": fact,
                     "status": status, "detail": detail, "expected": expected, "actual": actual})

    by_key = {}
    fixture_map = {fixture.id: fixture for fixture in captured.fixtures}
    for observation in observations:
        try:
            if not isinstance(observation, dict):
                raise ValueError("observation must be an object")
            validate_contract("observation", observation)
            key = (observation["fixture"], observation["engine"])
            if key in by_key or key[0] not in fixture_map:
                raise ValueError("duplicate or unknown observation row")
            if observation["provider"] != fixture_map[key[0]].provider:
                raise ValueError("observation provider differs from captured provider")
            if identities is not None:
                if observation["inputDigest"] != fixture_input_digest(fixture_map[key[0]]):
                    raise ValueError("observation input digest differs from frozen capture")
                if observation["execution"] == "completed":
                    if observation["tool"] != identities["tools"].get(key[1]):
                        raise ValueError("observation tool differs from verified tool identity")
                    artifacts = observation["rawArtifacts"]
                    if not any("stdout" in ref["path"] for ref in artifacts) or not any("stderr" in ref["path"] for ref in artifacts):
                        raise ValueError("completed observation lacks stdout/stderr evidence")
                    evidence_root = Path(identities["evidenceRoot"]).resolve()
                    for ref in artifacts:
                        path = evidence_root / ref["path"]
                        if not path.resolve().is_relative_to(evidence_root) or path.is_symlink() or not path.is_file():
                            raise ValueError("invalid raw evidence path")
                        if hashlib.sha256(path.read_bytes()).hexdigest() != ref["sha256"]:
                            raise ValueError("raw evidence hash mismatch")
            by_key[key] = observation
        except (ValueError, KeyError, TypeError) as error:
            fixture = observation.get("fixture", "?") if isinstance(observation, dict) else "?"
            engine = observation.get("engine", "?") if isinstance(observation, dict) else "?"
            add(fixture, engine, "observation", "fail", str(error))

    used = set()
    reviewed = registry["reviewed"]
    valid_entries = []
    entry_ids = {entry["id"] for entry in registry["candidates"]}
    for entry in reviewed:
        required = {"id", "fixtureIds", "fields", "expected", "profile", "sourceDigests", "enginePins", "rationale", "evidence", "review", "revisit"}
        try:
            if not isinstance(entry, dict) or set(entry) != required or not entry["fixtureIds"] or not entry["fields"]:
                raise ValueError("invalid reviewed entry fields")
            if entry["id"] in entry_ids:
                raise ValueError("duplicate difference ID")
            entry_ids.add(entry["id"])
            if len(set(entry["fixtureIds"])) != len(entry["fixtureIds"]) or len(set(entry["fields"])) != len(entry["fields"]) or not entry["revisit"]:
                raise ValueError("duplicate scope or missing revisit condition")
            if entry["profile"] != captured.profile or not entry["rationale"] or not entry["evidence"]:
                raise ValueError("missing profile/rationale/evidence")
            if not entry["review"].get("artifact") or not entry["review"].get("commit"):
                raise ValueError("missing review provenance")
            if set(entry["fields"]) - set(FACT_IDS) or set(entry["fixtureIds"]) - set(fixture_map):
                raise ValueError("unknown fixture/field")
            for fid in entry["fixtureIds"]:
                expected_sources = {source.logical_path: source.sha256 for source in fixture_map[fid].supplied_sources}
                if entry["sourceDigests"].get(fid) != expected_sources:
                    raise ValueError("stale source digests")
            if set(entry["expected"]) != set(entry["fields"]) or len(entry["enginePins"]) != 2 or "mirrors" not in entry["enginePins"]:
                raise ValueError("difference expected/pin scope is not exact")
            for field in entry["fields"]:
                if set(entry["expected"][field]) != set(entry["enginePins"]):
                    raise ValueError("difference expected engine scope mismatch")
            if identities is not None:
                for engine, fingerprint in entry["enginePins"].items():
                    known = identities["tools"].get(engine) or identities.get("expectedTools", {}).get(engine)
                    if known is not None and known.get("fingerprint") != fingerprint:
                        raise ValueError("difference pins differ from verified artifacts")
                review_root = Path(identities["reviewRoot"]).resolve()
                refs = entry["evidence"] + [{"path": entry["review"]["artifact"], "sha256": entry["review"].get("sha256")}]
                for ref in refs:
                    if not isinstance(ref, dict) or set(ref) != {"path", "sha256"}:
                        raise ValueError("review evidence requires exact path and hash")
                    path = review_root / ref["path"]
                    if Path(ref["path"]).is_absolute() or not path.resolve().is_relative_to(review_root) or path.is_symlink() or not path.is_file():
                        raise ValueError("review evidence path is invalid")
                    if hashlib.sha256(path.read_bytes()).hexdigest() != ref["sha256"]:
                        raise ValueError("review evidence hash mismatch")
            valid_entries.append(entry)
        except (ValueError, KeyError, TypeError) as error:
            label = entry.get("id", "?") if isinstance(entry, dict) else "?"
            add("registry", "registry", "reviewed", "fail", f"{label}: {error}")

    def compare(fid, engine, fact, left, right):
        if left == right:
            add(fid, engine, fact, "match", "equal", left, right)
            return
        for entry in valid_entries:
            if fid not in entry["fixtureIds"] or fact not in entry["fields"]:
                continue
            pair = entry["expected"].get(fact)
            obs = by_key[(fid, engine)]
            mirror = by_key[(fid, "mirrors")]
            if pair == {"mirrors": left, engine: right} and entry["enginePins"] == {
                "mirrors": mirror["tool"]["fingerprint"], engine: obs["tool"]["fingerprint"]}:
                used.add((entry["id"], fid, engine, fact))
                add(fid, engine, fact, "reviewed_difference", entry["id"], left, right)
                return
        add(fid, engine, fact, "fail", "unreviewed disagreement", left, right)

    for fixture in captured.fixtures:
        available = {}
        for engine in ENGINES:
            observation = by_key.get((fixture.id, engine))
            if observation is None:
                add(fixture.id, engine, "observation", "incomplete", "missing required fixture row")
            elif observation["execution"] != "completed" or observation["outcome"] == "unknown":
                add(fixture.id, engine, "outcome", "incomplete", observation["execution"])
            else:
                available[engine] = observation
        digests = {o["inputDigest"] for engine in ENGINES if (o := by_key.get((fixture.id, engine))) is not None}
        if len(digests) > 1:
            add(fixture.id, "all", "input", "fail", "engines observed different inputs")
        mirror = available.get("mirrors")
        if mirror:
            add(fixture.id, "mirrors", "outcome", "match" if mirror["outcome"] == fixture.kind else "fail",
                "manifest outcome", fixture.kind, mirror["outcome"])
            try:
                actual = fact_value(mirror, "stage")
                expected = {"stage": fixture.expected_stage, "reason": fixture.reason}
                if fixture.kind == "accepted":
                    matches = actual.get("reason") is None and _STAGE_ORDER.get(actual.get("stage"), -1) >= _STAGE_ORDER[fixture.expected_stage]
                    detail = "completed pipeline reaches exercised stage"
                else:
                    matches, detail = expected == actual, "manifest stage/reason"
                add(fixture.id, "mirrors", "stage", "match" if matches else "fail", detail, expected, actual)
            except (ValueError, KeyError) as error:
                add(fixture.id, "mirrors", "stage", "incomplete", str(error))
            if fixture.summary and mirror["outcome"] == "accepted":
                try:
                    golden_facts = [
                        ("variables", fixture.summary["effectiveVariables"], fact_value(mirror, "variables")),
                        ("source_closure", ordered([{"module": source["logicalPath"][:-4], "path": source["logicalPath"], "sha256": source["sha256"]} for source in fixture.summary["sources"]]), projection("source_closure", fact_value(mirror, "source_closure"))),
                    ]
                    local_dependencies = [{"owner": edge["owner"], "dependency": edge["module"], "kind": edge["kind"], "local": edge["local"]}
                                          for edge in fixture.summary.get("dependencies", []) if edge["resolution"] == "local"]
                    golden_facts.append(("dependencies", ordered(local_dependencies), projection("resolution", fact_value(mirror, "resolution"))["dependencies"]))
                    if fixture.summary.get("levels") is not None:
                        expected_levels = fixture.summary["levels"]
                        actual_levels = {item["name"]: item["level"] for item in fact_value(mirror, "levels") if item["name"] in expected_levels}
                        golden_facts.append(("levels", expected_levels, actual_levels))
                    for fact, expected, actual in golden_facts:
                        add(fixture.id, "mirrors", fact, "match" if expected == actual else "fail", "frozen summary", expected, actual)
                except (ValueError, KeyError, TypeError) as error:
                    add(fixture.id, "mirrors", "summary", "incomplete", str(error))
        for engine in ("sany", "apalache"):
            other = available.get(engine)
            if not mirror or not other:
                continue
            compare(fixture.id, engine, "outcome", mirror["outcome"], other["outcome"])
            # Native stage mapping is independently calibrated, never guessed.
            if other["stage"] is None:
                add(fixture.id, engine, "stage", "unsupported", "native stages have no qualified Mirrors mapping")
            elif mirror["outcome"] == other["outcome"] == "rejected":
                compare(fixture.id, engine, "stage", mirror["stage"], other["stage"])
            for requirement in fixture.requirements[engine]:
                fact = requirement.id
                if fact in ("outcome", "stage") or not requirement.applicable:
                    continue
                if mirror["outcome"] != "accepted" or other["outcome"] != "accepted":
                    add(fixture.id, engine, fact, "not_applicable", "no mutually accepted semantic graph")
                    continue
                try:
                    compare(fixture.id, engine, fact, projection(fact, fact_value(mirror, fact)), projection(fact, fact_value(other, fact)))
                except (ValueError, KeyError, TypeError) as error:
                    add(fixture.id, engine, fact, "incomplete" if requirement.required else "unsupported", str(error))
        if "sany" in available and "apalache" in available:
            left, right = available["sany"]["outcome"], available["apalache"]["outcome"]
            add(fixture.id, "oracles", "outcome", "match" if left == right else "oracle_disagreement", "reference-to-reference", left, right)
    for entry in valid_entries:
        required_uses = {(entry["id"], fid, engine, field) for fid in entry["fixtureIds"] for engine in entry["enginePins"] if engine != "mirrors" for field in entry["fields"]}
        for use in required_uses - used:
            _, fid, engine, _ = use
            evaluable = all(by_key.get((fid, side), {}).get("execution") == "completed" and
                by_key.get((fid, side), {}).get("outcome") != "unknown" for side in ("mirrors", engine))
            add(fid, engine, "reviewed", "fail" if evaluable else "incomplete",
                f"unused reviewed difference: {entry['id']}" if evaluable else f"reviewed difference could not execute: {entry['id']}")
    counts = Counter(row["status"] for row in rows)
    coverage = {"fixtures": len(captured.fixtures), "branches": len(captured.branch_ids), "expectedObservations": len(captured.fixtures) * len(ENGINES),
                "observations": len(observations), "comparisons": dict(sorted(counts.items())),
                "byEngine": {engine: dict(Counter(row["status"] for row in rows if row["engine"] == engine)) for engine in ENGINES},
                "branchFixtures": {branch: [f.id for f in captured.fixtures if branch in f.branches] for branch in captured.branch_ids}}
    verdict = "fail" if counts["fail"] else "incomplete" if counts["incomplete"] else "pass"
    return rows, coverage, verdict
