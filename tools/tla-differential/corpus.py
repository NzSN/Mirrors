"""Frozen DV0 corpus capture and closed JSON contract validation.

This module deliberately captures normalized bytes before a runner is introduced.
It never infers a reachable closure from an expected summary: that is an adapter
observation in DV2/DV3.  Expected summaries only validate the corpus declaration.
"""
from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

CORPUS_SCHEMA = "mirrors.tla-frontend-corpus/1"
SUMMARY_SCHEMA = "mirrors.tla-frontend-summary/1"
OBSERVATION_SCHEMA = "mirrors.tla-differential-observation/v1"
REPORT_SCHEMA = "mirrors.tla-differential-report/v1"
REGISTRY_SCHEMA = "mirrors.tla-differential-differences/v1"
LOCK_SCHEMA = "mirrors.tla-differential-toolchain-lock/v1"
FACT_IDS = ("outcome", "stage", "source_closure", "variables", "resolution", "substitution", "levels")
ENGINES = ("mirrors", "sany", "apalache")
_STAGES = {"lex", "parse", "moduleGraph", "nameResolution", "substitution", "level", "sourceEvidence"}
MAX_SOURCE_BYTES = 1 * 1024 * 1024
MAX_JSON_BYTES = 8 * 1024 * 1024
MAX_CAPTURE_BYTES = 64 * 1024 * 1024


class CorpusError(ValueError):
    pass


@dataclass(frozen=True)
class SourceFile:
    logical_path: str
    sha256: str
    byte_length: int
    normalized_bytes: bytes


@dataclass(frozen=True)
class FactRequirement:
    id: str
    applicable: bool
    required: bool


@dataclass(frozen=True)
class FixtureCapture:
    id: str
    kind: str
    expected_stage: str
    reason: str | None
    provider: str
    root: str
    source_root: str | None
    inline_source_map: tuple[Mapping[str, str], ...]
    branches: tuple[str, ...]
    manifest_expectation: Mapping[str, Any]
    summary: Mapping[str, Any] | None
    summary_sha256: str | None
    supplied_sources: tuple[SourceFile, ...]
    expected_reachable_sources: tuple[SourceFile, ...] | None
    requirements: Mapping[str, tuple[FactRequirement, ...]]


@dataclass(frozen=True)
class CorpusCapture:
    profile: str
    fixtures: tuple[FixtureCapture, ...]
    branch_ids: tuple[str, ...]
    manifest_sha256: str
    profile_sha256: str
    summary_sha256: str
    registry_sha256: str


def _digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _read_limited(path: Path, limit: int, label: str) -> bytes:
    try:
        if path.stat().st_size > limit:
            raise CorpusError(f"{label} exceeds {limit} byte bound: {path}")
        raw = path.read_bytes()
    except OSError as error:
        raise CorpusError(f"cannot read {label} {path}: {error}") from error
    if len(raw) > limit:
        raise CorpusError(f"{label} exceeds {limit} byte bound: {path}")
    return raw


def _read_json(path: Path) -> tuple[dict[str, Any], bytes]:
    try:
        raw = _read_limited(path, MAX_JSON_BYTES, "JSON input")
        data = json.loads(raw)
    except (CorpusError, json.JSONDecodeError) as error:
        raise CorpusError(f"cannot read JSON {path}: {error}") from error
    if not isinstance(data, dict):
        raise CorpusError(f"{path}: root must be an object")
    return data, raw


def _relative(path: str, label: str) -> None:
    value = Path(path)
    if not path or value.is_absolute() or ".." in value.parts:
        raise CorpusError(f"{label}: path must be nonempty and relative: {path!r}")


def _normalized(data: bytes) -> bytes:
    return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def _source(root: Path, logical_path: str, label: str) -> SourceFile:
    _relative(logical_path, label)
    path = root
    for component in Path(logical_path).parts:
        path /= component
        if path.is_symlink():
            raise CorpusError(f"{label}: symlink source component: {logical_path}")
    try:
        if not path.is_file():
            raise OSError("source is not a regular file")
        raw = _read_limited(path, MAX_SOURCE_BYTES, "source")
    except OSError as error:
        raise CorpusError(f"{label}: missing source {logical_path}") from error
    normalized = _normalized(raw)
    try:
        normalized.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise CorpusError(f"{label}: source is not valid UTF-8: {logical_path}") from error
    return SourceFile(logical_path, _digest(normalized), len(normalized), normalized)


def _requirements(kind: str) -> Mapping[str, tuple[FactRequirement, ...]]:
    accepted = kind == "accepted"
    out: dict[str, tuple[FactRequirement, ...]] = {}
    for engine in ENGINES:
        facts = [FactRequirement("outcome", True, True), FactRequirement("stage", True, engine == "mirrors")]
        for fact in FACT_IDS[2:]:
            # SANY structural facts are initially required for accepted cases;
            # Apalache remains applicable but unqualified until DV1 publishes capability evidence.
            facts.append(FactRequirement(fact, accepted, engine == "sany" and accepted))
        out[engine] = tuple(facts)
    return out


def validate_manifest(manifest: Mapping[str, Any], fixture_root: Path) -> tuple[FixtureCapture, ...]:
    if manifest.get("schema") != CORPUS_SCHEMA:
        raise CorpusError("unknown corpus schema")
    profile = manifest.get("profile")
    if not isinstance(profile, str) or not profile:
        raise CorpusError("manifest profile must be a nonempty string")
    stages = manifest.get("stages")
    if not isinstance(stages, list) or not stages or len(stages) != len(set(stages)) or set(stages) - _STAGES:
        raise CorpusError("manifest stages are invalid")
    branches = manifest.get("branches")
    if not isinstance(branches, list):
        raise CorpusError("manifest branches must be an array")
    branch_ids = [row.get("id") for row in branches if isinstance(row, dict)]
    if len(branch_ids) != len(branches) or any(not isinstance(x, str) or not x for x in branch_ids) or len(set(branch_ids)) != len(branch_ids):
        raise CorpusError("manifest branch IDs are invalid")
    fixtures = manifest.get("fixtures")
    if not isinstance(fixtures, list):
        raise CorpusError("manifest fixtures must be an array")
    captures: list[FixtureCapture] = []
    seen: set[str] = set()
    for row in fixtures:
        if not isinstance(row, dict):
            raise CorpusError("fixture must be an object")
        fixture_id, kind, stage = row.get("id"), row.get("kind"), row.get("stage")
        if not isinstance(fixture_id, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", fixture_id) or fixture_id in seen:
            raise CorpusError(f"duplicate or invalid fixture ID: {fixture_id!r}")
        seen.add(fixture_id)
        if kind not in {"accepted", "rejected"} or stage not in stages:
            raise CorpusError(f"fixture {fixture_id}: invalid kind or stage")
        reason = row.get("reason")
        if (kind == "accepted" and reason is not None) or (kind == "rejected" and reason not in {"malformed", "limit", "profile_limit"}):
            raise CorpusError(f"fixture {fixture_id}: invalid reason")
        provider, root = row.get("provider"), row.get("root")
        if provider not in {"borrowed-directory", "inline-source-map"} or not isinstance(root, str) or not root:
            raise CorpusError(f"fixture {fixture_id}: invalid provider or root")
        source_root = row.get("sourceRoot")
        if provider == "borrowed-directory" and not isinstance(source_root, str):
            raise CorpusError(f"fixture {fixture_id}: borrowed provider needs sourceRoot")
        if provider == "inline-source-map" and "sourceRoot" in row:
            raise CorpusError(f"fixture {fixture_id}: inline provider cannot carry sourceRoot")
        if source_root is not None:
            if not isinstance(source_root, str):
                raise CorpusError(f"fixture {fixture_id}: invalid sourceRoot")
            _relative(source_root, f"fixture {fixture_id}")
        paths = row.get("files")
        if not isinstance(paths, list) or not paths or any(not isinstance(x, str) for x in paths) or len(set(paths)) != len(paths):
            raise CorpusError(f"fixture {fixture_id}: source files must be unique nonempty paths")
        for source_path in paths:
            _relative(source_path, f"fixture {fixture_id}")
        if provider == "borrowed-directory":
            assert isinstance(source_root, str)
            for source_path in paths:
                try:
                    Path(source_path).relative_to(source_root)
                except ValueError as error:
                    raise CorpusError(f"fixture {fixture_id}: borrowed source is outside sourceRoot: {source_path}") from error
        supplied = tuple(_source(fixture_root, path, f"fixture {fixture_id}") for path in paths)
        if provider == "borrowed-directory" and "inlineSourceMap" in row:
            raise CorpusError(f"fixture {fixture_id}: borrowed provider cannot carry inlineSourceMap")
        inline = row.get("inlineSourceMap", [])
        if not isinstance(inline, list) or (provider == "inline-source-map" and not inline):
            raise CorpusError(f"fixture {fixture_id}: invalid inline source map")
        maps: list[Mapping[str, str]] = []
        logical_names: set[str] = set()
        mapped_files: set[str] = set()
        for entry in inline:
            if not isinstance(entry, dict) or set(entry) != {"file", "logicalName"} or entry["file"] not in paths or not isinstance(entry["logicalName"], str) or not entry["logicalName"] or entry["logicalName"] in logical_names:
                raise CorpusError(f"fixture {fixture_id}: invalid inline source map entry")
            _relative(f"{entry['logicalName']}.tla", f"fixture {fixture_id}")
            logical_names.add(entry["logicalName"])
            mapped_files.add(entry["file"])
            maps.append({"file": entry["file"], "logicalName": entry["logicalName"]})
        if provider == "inline-source-map" and mapped_files != set(paths):
            raise CorpusError(f"fixture {fixture_id}: inline source map must cover every source exactly once")
        fixture_branches = row.get("branches")
        if not isinstance(fixture_branches, list) or not fixture_branches or any(x not in branch_ids for x in fixture_branches):
            raise CorpusError(f"fixture {fixture_id}: unknown branch")
        summary: Mapping[str, Any] | None = None
        summary_sha256: str | None = None
        expected_reachable: tuple[SourceFile, ...] | None = None
        summary_path = row.get("summary")
        if kind == "accepted":
            if not isinstance(summary_path, str):
                raise CorpusError(f"fixture {fixture_id}: accepted fixture needs summary")
            _relative(summary_path, f"fixture {fixture_id}")
            summary, summary_raw = _read_json(fixture_root / summary_path)
            summary_sha256 = _digest(summary_raw)
            if summary.get("schema") != SUMMARY_SCHEMA or summary.get("fixture") != fixture_id or summary.get("root") != root or summary.get("profile") != profile:
                raise CorpusError(f"fixture {fixture_id}: summary identity mismatch")
            source_rows = summary.get("sources")
            if not isinstance(source_rows, list):
                raise CorpusError(f"fixture {fixture_id}: summary has no sources")
            supplied_by_name = {Path(x.logical_path).name: x for x in supplied}
            reachable: list[SourceFile] = []
            for source_row in source_rows:
                if not isinstance(source_row, dict) or set(source_row) != {"logicalPath", "sha256"}:
                    raise CorpusError(f"fixture {fixture_id}: malformed summary source")
                logical_path, digest = source_row["logicalPath"], source_row["sha256"]
                actual = supplied_by_name.get(logical_path)
                if actual is None or digest != actual.sha256:
                    raise CorpusError(f"fixture {fixture_id}: summary source hash mismatch for {logical_path}")
                reachable.append(actual)
            if len({x.logical_path for x in reachable}) != len(reachable):
                raise CorpusError(f"fixture {fixture_id}: duplicate summary source")
            expected_reachable = tuple(reachable)
        elif summary_path is not None:
            raise CorpusError(f"fixture {fixture_id}: rejected fixture carries summary")
        captures.append(FixtureCapture(fixture_id, kind, stage, reason, provider, root, source_root, tuple(maps), tuple(fixture_branches), dict(row), summary, summary_sha256, supplied, expected_reachable, _requirements(kind)))
    return tuple(captures)


def load_corpus(repo_root: Path | str) -> CorpusCapture:
    repo = Path(repo_root)
    fixture_root = repo / "test/fixtures/tla-frontend"
    manifest, manifest_raw = _read_json(fixture_root / "manifest.json")
    captures = validate_manifest(manifest, fixture_root)
    profile_path = repo / "Docs/model-interface-compiler/tla-language-profile.md"
    registry_path = fixture_root / "differential/differences.json"
    try:
        profile_raw = _read_limited(profile_path, MAX_JSON_BYTES, "profile")
        registry, registry_raw = _read_json(registry_path)
    except OSError as error:
        raise CorpusError(f"missing DV0 input: {error.filename}") from error
    validate_registry(registry, captures)
    captured_bytes = sum({source.logical_path: source.byte_length for fixture in captures for source in fixture.supplied_sources}.values())
    if captured_bytes > MAX_CAPTURE_BYTES:
        raise CorpusError(f"captured sources exceed {MAX_CAPTURE_BYTES} byte bound")
    listed = {source.logical_path for fixture in captures for source in fixture.supplied_sources}
    # Evidence may contain native output directories named Module.tla. Only
    # accepted/rejected source namespaces are fixture inputs, never reports.
    physical = {path.relative_to(fixture_root).as_posix()
        for directory in (fixture_root / "accepted", fixture_root / "rejected")
        for path in directory.rglob("*.tla") if path.is_file() or path.is_symlink()}
    if listed != physical:
        raise CorpusError(f"manifest files do not account for fixture sources: {sorted(listed ^ physical)}")
    summary_digest = hashlib.sha256()
    for fixture in captures:
        if fixture.summary_sha256 is not None:
            summary_digest.update(fixture.summary_sha256.encode())
    return CorpusCapture(str(manifest["profile"]), captures, tuple(row["id"] for row in manifest["branches"]), _digest(manifest_raw), _digest(profile_raw), summary_digest.hexdigest(), _digest(registry_raw))


def validate_corpus(repo_root: Path | str) -> CorpusCapture:
    return load_corpus(repo_root)


def validate_contract(name: str, value: Mapping[str, Any]) -> None:
    """Small closed-schema validator for DV0 boundaries, with no third-party dependency."""
    if not isinstance(value, dict):
        raise CorpusError(f"{name}: root must be an object")
    schemas = {
        "observation": (OBSERVATION_SCHEMA, {"schema", "fixture", "engine", "provider", "inputDigest", "adapter", "tool", "invocation", "execution", "outcome", "nativePhase", "stage", "diagnostics", "facts", "rawArtifacts"}, {"schema", "fixture", "engine", "provider", "inputDigest", "adapter", "tool", "invocation", "execution", "outcome", "nativePhase", "stage", "diagnostics", "facts", "rawArtifacts"}),
        "report": (REPORT_SCHEMA, {"schema", "inputs", "observations", "comparisons", "coverage", "verdict"}, {"schema", "inputs", "observations", "comparisons", "coverage", "verdict"}),
        "registry": (REGISTRY_SCHEMA, {"schema", "candidates", "reviewed"}, {"schema", "candidates", "reviewed"}),
        "lock": (LOCK_SCHEMA, {"schema", "tools"}, {"schema", "tools"}),
    }
    if name not in schemas:
        raise CorpusError(f"unknown contract {name}")
    schema, allowed, required = schemas[name]
    if value.get("schema") != schema or set(value) - allowed or not required <= set(value):
        raise CorpusError(f"{name}: wrong schema, missing field, or unknown field")
    if name == "registry":
        candidates = value["candidates"]
        if not isinstance(candidates, list): raise CorpusError("registry: candidates must be an array")
        ids: set[str] = set()
        for candidate in candidates:
            required_candidate = {"id", "fixtureIds", "fields", "expected", "profile", "sourceDigests", "rationale", "revisit", "reviewStatus"}
            if not isinstance(candidate, dict) or set(candidate) - (required_candidate | {"evidence"}) or not required_candidate <= set(candidate) or candidate["reviewStatus"] != "unreviewed" or candidate["id"] in ids:
                raise CorpusError("registry: invalid or non-unreviewed candidate")
            ids.add(candidate["id"])
        reviewed = value["reviewed"]
        if not isinstance(reviewed, list): raise CorpusError("registry: reviewed must be an array")
    elif name == "observation":
        if value["engine"] not in ENGINES or value["provider"] not in {"borrowed-directory", "inline-source-map"} or value["execution"] not in {"completed", "unavailable", "timeout", "crash", "invalid_output", "resource_exhausted"} or value["outcome"] not in {"accepted", "rejected", "unknown"}:
            raise CorpusError("observation: invalid engine, provider, execution, or outcome")
        if not isinstance(value["inputDigest"], str) or len(value["inputDigest"]) != 64 or any(char not in "0123456789abcdef" for char in value["inputDigest"]):
            raise CorpusError("observation: inputDigest must be lowercase SHA-256")
        _identity(value["adapter"], {"id", "version"}, "adapter")
        _identity(value["tool"], {"id", "version", "fingerprint"}, "tool")
        invocation = value["invocation"]
        if not isinstance(invocation, dict) or set(invocation) != {"argv", "exitCode"} or not isinstance(invocation["argv"], list) or not all(isinstance(arg, str) for arg in invocation["argv"]) or (invocation["exitCode"] is not None and (not isinstance(invocation["exitCode"], int) or isinstance(invocation["exitCode"], bool))):
            raise CorpusError("observation: invalid invocation")
        if value["nativePhase"] is not None and not isinstance(value["nativePhase"], str) or value["stage"] is not None and not isinstance(value["stage"], str):
            raise CorpusError("observation: invalid native phase or stage")
        if not isinstance(value["diagnostics"], list) or not all(isinstance(item, dict) for item in value["diagnostics"]):
            raise CorpusError("observation: diagnostics must be objects")
        _artifacts(value["rawArtifacts"])
        if value["execution"] != "completed" and value["outcome"] != "unknown":
            raise CorpusError("observation: incomplete execution cannot have a language outcome")
        facts = value["facts"]
        if not isinstance(facts, dict): raise CorpusError("observation: facts must be an object")
        for fact_id, fact in facts.items():
            if fact_id not in FACT_IDS or not isinstance(fact, dict) or set(fact) - {"capability", "value"} or "capability" not in fact or fact["capability"] not in {"supported", "unsupported", "unqualified"} or (fact["capability"] == "supported" and "value" not in fact) or (fact["capability"] != "supported" and "value" in fact):
                raise CorpusError("observation: invalid fact observation")
            if fact["capability"] == "supported":
                _fact_value(fact_id, fact["value"])
                if fact_id == "outcome" and fact["value"] != value["outcome"]:
                    raise CorpusError("observation: outcome fact disagrees with outcome")
                if fact_id == "stage" and (not isinstance(fact["value"], dict) or fact["value"]["stage"] != value["stage"]):
                    raise CorpusError("observation: stage fact disagrees with stage")
                if value["outcome"] == "rejected" and fact_id not in {"outcome", "stage"}:
                    raise CorpusError("observation: rejected output cannot carry semantic facts")
        if value["execution"] == "completed" and value["outcome"] != "unknown":
            outcome_fact = facts.get("outcome")
            if not isinstance(outcome_fact, dict) or outcome_fact.get("capability") != "supported":
                raise CorpusError("observation: completed known outcome needs supported outcome fact")


def _identity(value: Any, keys: set[str], label: str) -> None:
    if not isinstance(value, dict) or set(value) != keys or not all(isinstance(value[key], str) and value[key] for key in keys):
        raise CorpusError(f"observation: invalid {label}")


def _exact_object(value: Any, keys: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise CorpusError(f"observation: invalid {label}")
    return value


def _string(value: Any, label: str) -> None:
    if not isinstance(value, str):
        raise CorpusError(f"observation: invalid {label}")


def _boolean(value: Any, label: str) -> None:
    if not isinstance(value, bool):
        raise CorpusError(f"observation: invalid {label}")


def _artifacts(value: Any) -> None:
    if not isinstance(value, list):
        raise CorpusError("observation: rawArtifacts must be an array")
    for artifact in value:
        row = _exact_object(artifact, {"path", "sha256"}, "raw artifact")
        path, digest = row["path"], row["sha256"]
        if not isinstance(path, str) or not path or Path(path).is_absolute() or ".." in Path(path).parts or not isinstance(digest, str) or len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
            raise CorpusError("observation: invalid raw artifact")


def _fact_value(fact: str, value: Any) -> None:
    if fact == "outcome":
        if value not in {"accepted", "rejected", "unknown"}: raise CorpusError("observation: invalid outcome fact")
    elif fact == "stage":
        row = _exact_object(value, {"stage", "reason"}, "stage fact"); _string(row["stage"], "stage")
        if row["reason"] is not None: _string(row["reason"], "stage reason")
    elif fact == "variables":
        _variables(value)
    elif fact == "source_closure":
        _closure(value)
    elif fact == "resolution":
        _resolution(value)
    elif fact == "levels":
        _levels(value)
    elif fact == "substitution":
        _substitutions(value)


def _variables(value: Any) -> None:
    if not isinstance(value, list): raise CorpusError("observation: variables must be an array")
    for row in value:
        item = _exact_object(row, {"name", "declaredIn", "declaredName"} | ({"importPath"} if isinstance(row, dict) and "importPath" in row else set()), "variable")
        for key in ("name", "declaredIn", "declaredName"): _string(item[key], key)
        if "importPath" in item and (not isinstance(item["importPath"], list) or not all(isinstance(part, str) for part in item["importPath"])): raise CorpusError("observation: invalid importPath")


def _closure(value: Any) -> None:
    if not isinstance(value, list): raise CorpusError("observation: source closure must be an array")
    for row in value:
        item = _exact_object(row, {"module", "path", "sha256"}, "source closure")
        _string(item["module"], "module"); _string(item["path"], "source path")
        digest = item["sha256"]
        if not isinstance(digest, str) or len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest): raise CorpusError("observation: invalid source digest")


def _resolution(value: Any) -> None:
    root = _exact_object(value, {"dependencies", "operators"}, "resolution")
    if not isinstance(root["dependencies"], list) or not isinstance(root["operators"], list): raise CorpusError("observation: invalid resolution collections")
    for row in root["dependencies"]:
        item = _exact_object(row, {"owner", "dependency", "kind", "local"}, "dependency")
        for key in ("owner", "dependency", "kind"): _string(item[key], key)
        if item["kind"] not in {"extends", "namedInstance", "unnamedInstance"}: raise CorpusError("observation: invalid dependency kind")
        _boolean(item["local"], "dependency local")
    for row in root["operators"]:
        item = _exact_object(row, {"name", "declaredIn", "arity", "local"}, "operator")
        _string(item["name"], "operator name"); _string(item["declaredIn"], "operator declaredIn"); _boolean(item["local"], "operator local")
        if type(item["arity"]) is not int or item["arity"] < 0: raise CorpusError("observation: invalid operator arity")


def _levels(value: Any) -> None:
    if not isinstance(value, list): raise CorpusError("observation: levels must be an array")
    for row in value:
        item = _exact_object(row, {"name", "declaredIn", "level"}, "level")
        _string(item["name"], "level name"); _string(item["declaredIn"], "level declaredIn")
        if item["level"] not in {"constant", "state", "action", "temporal"}: raise CorpusError("observation: invalid operator level")


def _substitutions(value: Any) -> None:
    if not isinstance(value, list): raise CorpusError("observation: substitutions must be an array")
    for row in value:
        item = _exact_object(row, {"owner", "name", "module", "local", "line", "substitutions"}, "instance")
        for key in ("owner", "module"): _string(item[key], key)
        if item["name"] is not None: _string(item["name"], "instance name")
        _boolean(item["local"], "instance local")
        if type(item["line"]) is not int or item["line"] < 1 or not isinstance(item["substitutions"], list): raise CorpusError("observation: invalid instance")
        for substitution in item["substitutions"]:
            sub = _exact_object(substitution, {"formal", "actual", "implicit"}, "substitution")
            _string(sub["formal"], "substitution formal"); _boolean(sub["implicit"], "substitution implicit")
            actual = _exact_object(sub["actual"], {"kind", "value"}, "substitution actual")
            expected_type = {"name": str, "integer": int, "boolean": bool, "string": str}.get(actual["kind"])
            if expected_type is None or type(actual["value"]) is not expected_type or (actual["kind"] == "name" and not actual["value"]):
                raise CorpusError("observation: invalid substitution actual value")


def validate_registry(registry: Mapping[str, Any], fixtures: tuple[FixtureCapture, ...]) -> None:
    validate_contract("registry", registry)
    fixture_ids = {fixture.id for fixture in fixtures}
    for candidate in registry["candidates"]:
        if any(fixture_id not in fixture_ids for fixture_id in candidate["fixtureIds"]):
            raise CorpusError("registry: unknown fixture")
        if any(field not in FACT_IDS for field in candidate["fields"]):
            raise CorpusError("registry: unknown required fact")


def canonical_json(value: Mapping[str, Any]) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
