#!/usr/bin/env python3
"""Validate an E1 draft evidence envelope or public summary.

This is a contract validator only. It does not hash artifacts, follow locators,
project public data, finalize a bundle, or establish execution provenance.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

try:
    from jsonschema import Draft202012Validator, FormatChecker
except ImportError as error:  # pragma: no cover - exercised by the CLI environment
    raise SystemExit("evidence validation requires the Python 'jsonschema' package") from error


ROOT = Path(__file__).resolve().parent
SCHEMAS = {
    "mirrors.evidence-envelope/v1.0": ROOT / "schema" / "evidence-envelope-v1.schema.json",
    "mirrors.evidence-public-summary/v1.0": ROOT / "schema" / "public-summary-v1.schema.json",
}
PRIVATE_CANARY = "MIRRORS_PRIVATE_CANARY_"
MAX_DOCUMENT_BYTES = 4 * 1024 * 1024
MAX_ARTIFACT_BYTES = 512 * 1024 * 1024
MAX_DEPTH = 32
MAX_NODES = 65_536
MAX_STRING_BYTES = 65_536
MAX_SAFE_INTEGER = 9_007_199_254_740_991
_VALIDATORS: dict[Path, Draft202012Validator] = {}


class DuplicateKeyError(ValueError):
    pass


def _closed_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _reject_float(value: str) -> Any:
    raise ValueError(f"non-integer JSON number is forbidden: {value}")


def _reject_constant(value: str) -> Any:
    raise ValueError(f"non-finite JSON number is forbidden: {value}")


def load_json(path: Path) -> Any:
    data = path.read_bytes()
    if len(data) > MAX_DOCUMENT_BYTES:
        raise ValueError(f"document exceeds {MAX_DOCUMENT_BYTES} byte limit")
    return loads_json_bytes(data)


def loads_json_bytes(data: bytes) -> Any:
    if len(data) > MAX_DOCUMENT_BYTES:
        raise ValueError(f"document exceeds {MAX_DOCUMENT_BYTES} byte limit")
    value = json.loads(
        data.decode("utf-8"),
        object_pairs_hook=_closed_object,
        parse_float=_reject_float,
        parse_constant=_reject_constant,
    )
    errors = _bounded_value_errors(value)
    if errors:
        raise ValueError(errors[0])
    return value


def _json_path(parts: Iterable[Any]) -> str:
    result = "$"
    for part in parts:
        result += f"[{part}]" if isinstance(part, int) else f".{part}"
    return result


def _walk(value: Any, path: tuple[Any, ...] = ()) -> Iterable[tuple[tuple[Any, ...], Any]]:
    yield path, value
    if isinstance(value, dict):
        for key, child in value.items():
            yield from _walk(key, path + (f"<key:{key}>",))
            yield from _walk(child, path + (key,))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _walk(child, path + (index,))


def _duplicates(values: Iterable[str]) -> set[str]:
    seen: set[str] = set()
    duplicates: set[str] = set()
    for value in values:
        if value in seen:
            duplicates.add(value)
        seen.add(value)
    return duplicates


def _referenced_artifacts(document: dict[str, Any]) -> Iterable[tuple[str, str]]:
    for index, tier in enumerate(document["tiers"]):
        for artifact_id in tier["artifactIds"]:
            yield f"$.tiers[{index}].artifactIds", artifact_id
    for index, cleanup in enumerate(document["outcomes"]["cleanup"]):
        for artifact_id in cleanup["artifactIds"]:
            yield f"$.outcomes.cleanup[{index}].artifactIds", artifact_id
    for index, producer in enumerate(document["producerResults"]):
        yield f"$.producerResults[{index}].artifactId", producer["artifactId"]
    producer = document["outcomes"]["behavior"].get("producerResult")
    if producer is not None:
        yield "$.outcomes.behavior.producerResult.artifactId", producer["artifactId"]


def _schema_errors(document: Any, schema_path: Path) -> list[str]:
    validator = _VALIDATORS.get(schema_path)
    if validator is None:
        schema = load_json(schema_path)
        Draft202012Validator.check_schema(schema)
        validator = Draft202012Validator(schema, format_checker=FormatChecker())
        _VALIDATORS[schema_path] = validator
    return [
        f"{_json_path(error.absolute_path)}: {error.message}"
        for error in sorted(
            validator.iter_errors(document),
            key=lambda item: (tuple(f"{type(part).__name__}:{part}" for part in item.absolute_path), item.message),
        )
    ]


def _bounded_value_errors(value: Any) -> list[str]:
    errors: list[str] = []
    stack: list[tuple[Any, int, str]] = [(value, 0, "$")]
    active: set[int] = set()
    nodes = 0
    while stack:
        current, depth, path = stack.pop()
        nodes += 1
        if nodes > MAX_NODES:
            return [f"$: document exceeds {MAX_NODES} node limit"]
        if depth > MAX_DEPTH:
            return [f"{path}: document exceeds depth {MAX_DEPTH}"]
        if isinstance(current, bool) or current is None:
            continue
        if isinstance(current, int):
            if abs(current) > MAX_SAFE_INTEGER:
                errors.append(f"{path}: integer exceeds safe JSON range")
            continue
        if isinstance(current, float):
            errors.append(f"{path}: non-integer JSON number is forbidden")
            continue
        if isinstance(current, str):
            if len(current.encode("utf-8")) > MAX_STRING_BYTES:
                errors.append(f"{path}: string exceeds {MAX_STRING_BYTES} byte limit")
            continue
        if isinstance(current, (dict, list)):
            identity = id(current)
            if identity in active:
                return [f"{path}: cyclic input is forbidden"]
            active.add(identity)
            if isinstance(current, dict):
                children = [(child, depth + 1, f"{path}.{key}") for key, child in current.items()]
                children.extend((key, depth + 1, f"{path}.<key:{key}>") for key in current)
            else:
                children = [(child, depth + 1, f"{path}[{index}]") for index, child in enumerate(current)]
            stack.extend(children)
            # JSON is a tree. Removing here still catches direct/self cycles and
            # avoids treating an intentionally shared programmatic value as JSON.
            active.remove(identity)
            continue
        errors.append(f"{path}: non-JSON value is forbidden")
    return errors


def _common_semantic_errors(document: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    artifact_ids = [artifact["artifactId"] for artifact in document["artifacts"]]
    artifact_set = set(artifact_ids)
    for duplicate in sorted(_duplicates(artifact_ids)):
        errors.append(f"$.artifacts: duplicate artifactId: {duplicate}")

    component_ids = [component["componentId"] for component in document["components"]]
    for duplicate in sorted(_duplicates(component_ids)):
        errors.append(f"$.components: duplicate componentId: {duplicate}")

    tier_ids = [tier["tierId"] for tier in document["tiers"]]
    for duplicate in sorted(_duplicates(tier_ids)):
        errors.append(f"$.tiers: duplicate tierId: {duplicate}")
    command_ids = [command["commandId"] for command in document["commands"]]
    for duplicate in sorted(_duplicates(command_ids)):
        errors.append(f"$.commands: duplicate commandId: {duplicate}")
    tier_set = set(tier_ids)
    for index, command in enumerate(document["commands"]):
        if command["tierId"] not in tier_set:
            errors.append(f"$.commands[{index}].tierId: tierId does not resolve: {command['tierId']}")

    cleanup_scopes = [cleanup["scope"] for cleanup in document["outcomes"]["cleanup"]]
    for duplicate in sorted(_duplicates(cleanup_scopes)):
        errors.append(f"$.outcomes.cleanup: duplicate cleanup scope: {duplicate}")

    for index, component in enumerate(document["components"]):
        dirty = component.get("dirtyContent")
        if dirty is None:
            continue
        included = dirty.get("includedPaths")
        excluded_entries = dirty.get("excludedPaths")
        if included is None or excluded_entries is None:
            continue
        excluded = [entry["path"] for entry in excluded_entries]
        if included != sorted(included):
            errors.append(f"$.components[{index}].dirtyContent.includedPaths: paths must be sorted")
        if excluded != sorted(excluded):
            errors.append(f"$.components[{index}].dirtyContent.excludedPaths: paths must be sorted")
        if len(excluded) != len(set(excluded)):
            errors.append(f"$.components[{index}].dirtyContent.excludedPaths: paths must be unique")
        overlap = sorted(set(included) & set(excluded))
        if overlap:
            errors.append(f"$.components[{index}].dirtyContent: included and excluded paths overlap: {overlap[0]}")

    started = datetime.fromisoformat(document["timestamps"]["startedAtUtc"].replace("Z", "+00:00"))
    finished = datetime.fromisoformat(document["timestamps"]["finishedAtUtc"].replace("Z", "+00:00"))
    if finished < started:
        errors.append("$.timestamps.finishedAtUtc: must not precede startedAtUtc")
    if sum(artifact["bytes"] for artifact in document["artifacts"]) > MAX_ARTIFACT_BYTES:
        errors.append(f"$.artifacts: aggregate artifact bytes exceed {MAX_ARTIFACT_BYTES}")

    qualified = document["qualification"]["status"] == "qualified"
    if qualified and document["outcomes"]["behavior"]["status"] != "passed":
        errors.append("$.qualification.status: qualified requires passed behavior")
    if qualified:
        for index, tier in enumerate(document["tiers"]):
            if tier["requirement"] == "required" and tier["status"] != "passed":
                errors.append(f"$.tiers[{index}].status: qualified requires every required tier to pass")
        for index, cleanup in enumerate(document["outcomes"]["cleanup"]):
            if cleanup["requirement"] == "required" and cleanup["status"] != "confirmed":
                errors.append(f"$.outcomes.cleanup[{index}].status: qualified requires confirmed cleanup")
        if document["outcomes"]["persistence"]["status"] != "complete":
            errors.append("$.outcomes.persistence.status: qualified requires complete persistence")
    return errors


def _private_semantic_errors(document: dict[str, Any]) -> list[str]:
    errors = _common_semantic_errors(document)
    artifacts = {artifact["artifactId"]: artifact for artifact in document["artifacts"]}
    required = document["releaseRequirements"]["requiredArtifactIds"]
    persistence = document["outcomes"]["persistence"]
    missing = sorted(set(required) - set(artifacts))

    if set(required) != set(persistence["requiredArtifactIds"]):
        errors.append("$.outcomes.persistence.requiredArtifactIds: must equal releaseRequirements.requiredArtifactIds")
    if sorted(persistence["missingArtifactIds"]) != missing:
        errors.append("$.outcomes.persistence.missingArtifactIds: must exactly name absent required artifacts")
    if persistence["status"] == "complete" and missing:
        errors.append(f"$.outcomes.persistence.status: complete bundle is missing required artifact: {missing[0]}")
    for artifact_id in required:
        artifact = artifacts.get(artifact_id)
        if artifact is not None and artifact["requirement"] != "required":
            errors.append(f"$.artifacts: release-required artifact is labeled optional: {artifact_id}")
    required_labeled = {artifact_id for artifact_id, artifact in artifacts.items() if artifact["requirement"] == "required"}
    unexpected_required = sorted(required_labeled - set(required))
    if unexpected_required:
        errors.append(f"$.artifacts: required artifact is absent from releaseRequirements: {unexpected_required[0]}")

    permitted_missing = set(persistence["missingArtifactIds"])
    for path, artifact_id in _referenced_artifacts(document):
        if artifact_id not in artifacts and artifact_id not in permitted_missing:
            errors.append(f"{path}: artifactId does not resolve: {artifact_id}")

    required_scopes = set(document["releaseRequirements"]["requiredCleanupScopes"])
    cleanup = {entry["scope"]: entry for entry in document["outcomes"]["cleanup"]}
    for scope in sorted(required_scopes):
        if scope not in cleanup or cleanup[scope]["requirement"] != "required":
            errors.append(f"$.releaseRequirements.requiredCleanupScopes: required scope not recorded as required: {scope}")
    receipt_roles = {"cleanup-receipt", "recovery-receipt", "producer-result"}
    for index, entry in enumerate(document["outcomes"]["cleanup"]):
        if entry["requirement"] == "required" and entry["status"] == "confirmed":
            receipts = [artifacts.get(artifact_id) for artifact_id in entry["artifactIds"]]
            if not any(artifact is not None and artifact["role"] in receipt_roles for artifact in receipts):
                errors.append(f"$.outcomes.cleanup[{index}].artifactIds: confirmed required cleanup needs a receipt artifact")

    for index, command in enumerate(document["commands"]):
        artifact_id = command.get("logArtifactId")
        if artifact_id is None:
            continue
        artifact = artifacts.get(artifact_id)
        if artifact is not None and artifact["role"] != "command-log":
            errors.append(f"$.commands[{index}].logArtifactId: referenced artifact is not a command-log")
        if artifact is None and artifact_id not in permitted_missing:
            errors.append(f"$.commands[{index}].logArtifactId: artifactId does not resolve: {artifact_id}")

    for index, producer in enumerate(document["producerResults"]):
        artifact = artifacts.get(producer["artifactId"])
        if artifact is not None and artifact["role"] != "producer-result":
            errors.append(f"$.producerResults[{index}].artifactId: referenced artifact is not a producer-result")
    return errors


def _public_semantic_errors(document: dict[str, Any]) -> list[str]:
    errors = _common_semantic_errors(document)
    artifact_ids = {artifact["artifactId"] for artifact in document["artifacts"]}
    for path, artifact_id in _referenced_artifacts(document):
        if artifact_id not in artifact_ids:
            errors.append(f"{path}: public artifactId does not resolve to a public artifact: {artifact_id}")
    for path, value in _walk(document):
        if isinstance(value, str) and PRIVATE_CANARY in value:
            errors.append(f"{_json_path(path)}: private canary is forbidden in public evidence")
    persistence = document["outcomes"]["persistence"]
    if persistence["persistedArtifactCount"] + persistence["missingRequiredArtifactCount"] != persistence["requiredArtifactCount"]:
        errors.append("$.outcomes.persistence: persisted plus missing counts must equal required count")
    return errors


def validate_document(document: Any) -> list[str]:
    bounded_errors = _bounded_value_errors(document)
    if bounded_errors:
        return bounded_errors
    if not isinstance(document, dict):
        return ["$: evidence document must be an object"]
    version = document.get("schemaVersion")
    if not isinstance(version, str):
        return ["$.schemaVersion: evidence schema must be a string"]
    schema_path = SCHEMAS.get(version)
    if schema_path is None:
        return [f"$.schemaVersion: unsupported evidence schema: {version!r}"]
    errors = _schema_errors(document, schema_path)
    if errors:
        return errors
    if version == "mirrors.evidence-envelope/v1.0":
        errors.extend(_private_semantic_errors(document))
    else:
        errors.extend(_public_semantic_errors(document))
    return sorted(set(errors))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("document", type=Path)
    args = parser.parse_args(argv)
    try:
        document = load_json(args.document)
        errors = validate_document(document)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"{args.document}: {error}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"{args.document}: {error}", file=sys.stderr)
        return 1
    print(f"{args.document}: valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
