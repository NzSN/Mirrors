#!/usr/bin/env python3
"""Finalize an E2 staging envelope into an immutable local evidence bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import sys
import uuid
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

from store import (
    create_owner_directory,
    create_owner_directory_exclusive,
    ensure_owner_directory,
    fsync_directory,
    logical_path,
    publish_exclusive,
    read_regular,
    write_exclusive,
)
from validate import ROOT, load_json, loads_json_bytes, validate_document


MAX_ENVELOPE_BYTES = 4 * 1024 * 1024
MAX_BUNDLE_BYTES = 512 * 1024 * 1024


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _qualification(envelope: dict[str, Any]) -> dict[str, Any]:
    reasons: list[str] = []
    behavior = envelope["outcomes"]["behavior"]["status"]
    if behavior != "passed":
        reasons.append(f"behavior-{behavior}")
    for tier in envelope["tiers"]:
        if tier["requirement"] == "required" and tier["status"] != "passed":
            reasons.append(f"tier-{tier['tierId']}-{tier['status']}")
    for cleanup in envelope["outcomes"]["cleanup"]:
        if cleanup["requirement"] == "required" and cleanup["status"] != "confirmed":
            reasons.append(f"cleanup-{cleanup['scope']}-{cleanup['status']}")
    if not reasons:
        return {"status": "qualified", "reasonCodes": []}
    incomplete = behavior in {"inconclusive", "not_run"} or any(
        tier["requirement"] == "required" and tier["status"] in {"skipped", "unavailable", "blocked", "not_run"}
        for tier in envelope["tiers"]
    )
    return {"status": "incomplete" if incomplete else "not_qualified", "reasonCodes": sorted(set(reasons))}


def finalized_envelope(staging: dict[str, Any]) -> dict[str, Any]:
    envelope = json.loads(json.dumps(staging))
    persistence = envelope["outcomes"]["persistence"]
    if persistence["missingArtifactIds"]:
        raise ValueError("cannot finalize evidence with missing required artifacts")
    if persistence.get("reasonCode") == "component-changed-during-collection":
        raise ValueError("cannot finalize evidence from a changing component checkout")
    if persistence["status"] == "failed":
        raise ValueError("cannot finalize failed persistence")
    persistence["status"] = "complete"
    persistence.pop("reasonCode", None)
    envelope["qualification"] = _qualification(envelope)
    metadata = envelope.setdefault("privateMetadata", {})
    notes = metadata.setdefault("operatorNotes", [])
    notes[:] = [note for note in notes if note != "Unfinalized E2 staging envelope."]
    notes.append("Finalized through mirrors.evidence-bundle-index/v1.")
    return envelope


def public_summary(envelope: dict[str, Any]) -> dict[str, Any]:
    public_artifacts = [artifact for artifact in envelope["artifacts"] if artifact["visibility"] == "public"]
    public_ids = {artifact["artifactId"] for artifact in public_artifacts}
    components = []
    for component in envelope["components"]:
        projected = {
            "componentId": component["componentId"],
            "repository": component["repository"],
            "revision": component["revision"],
            "dirty": component["dirty"],
        }
        if component["dirty"]:
            dirty = component["dirtyContent"]
            projected["dirtyContent"] = {
                "algorithm": dirty["algorithm"],
                "digest": dirty["digest"],
                "method": dirty["method"],
            }
        components.append(projected)
    commands = [{
        "commandId": command["commandId"],
        "tierId": command["tierId"],
        "requirement": command["requirement"],
        "approvedArgs": [],
        "exit": command["exit"],
    } for command in envelope["commands"]]
    tiers = [{
        **{key: value for key, value in tier.items() if key != "artifactIds"},
        "artifactIds": [artifact_id for artifact_id in tier["artifactIds"] if artifact_id in public_ids],
    } for tier in envelope["tiers"]]
    producer_results = [result for result in envelope["producerResults"] if result["artifactId"] in public_ids]
    behavior = json.loads(json.dumps(envelope["outcomes"]["behavior"]))
    if behavior.get("producerResult", {}).get("artifactId") not in public_ids:
        behavior.pop("producerResult", None)
    cleanup = [{
        **{key: value for key, value in entry.items() if key != "artifactIds"},
        "artifactIds": [artifact_id for artifact_id in entry["artifactIds"] if artifact_id in public_ids],
    } for entry in envelope["outcomes"]["cleanup"]]
    required_count = len(envelope["releaseRequirements"]["requiredArtifactIds"]) + 2
    return {
        "schemaVersion": "mirrors.evidence-public-summary/v1.0",
        "projectionKind": "public",
        "runId": envelope["runId"],
        "releaseProfile": envelope["releaseProfile"],
        "catalogSelectionRef": envelope["catalogSelectionRef"],
        "components": components,
        "timestamps": envelope["timestamps"],
        "environment": {
            "platformProfile": envelope["environment"]["platformProfile"],
            "os": envelope["environment"]["os"],
            "architecture": envelope["environment"]["architecture"],
            "tools": envelope["environment"]["tools"],
        },
        "commands": commands,
        "tiers": tiers,
        "artifacts": public_artifacts,
        "producerResults": producer_results,
        "outcomes": {
            "behavior": behavior,
            "cleanup": cleanup,
            "persistence": {
                "requirement": envelope["outcomes"]["persistence"]["requirement"],
                "status": "complete",
                "requiredArtifactCount": required_count,
                "persistedArtifactCount": required_count,
                "missingRequiredArtifactCount": 0,
            },
        },
        "qualification": envelope["qualification"],
    }


def _record(role: str, path: str, data: bytes, visibility: str, required: bool, artifact_id: str | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {
        "role": role,
        "path": path,
        "bytes": len(data),
        "sha256": sha256(data),
        "visibility": visibility,
        "required": required,
    }
    if artifact_id is not None:
        result["artifactId"] = artifact_id
    return result


def _mkdir_owner_chain(root: Path, relative_parent: Path) -> Path:
    current = root
    for part in relative_parent.parts:
        current = current / part
        create_owner_directory(current)
    return current


def finalize(staging_root: Path, store_root: Path | None = None) -> tuple[Path, dict[str, Any]]:
    staging_root = Path(os.path.abspath(staging_root))
    ensure_owner_directory(staging_root)
    store_root = Path(os.path.abspath(store_root)) if store_root is not None else staging_root.parent.parent
    ensure_owner_directory(store_root)
    staging_path = staging_root / "envelope.staging.json"
    staging_bytes, _ = read_regular(staging_path, max_bytes=MAX_ENVELOPE_BYTES)
    staging = loads_json_bytes(staging_bytes)
    errors = validate_document(staging)
    if errors:
        raise ValueError("invalid staging envelope: " + "; ".join(errors))
    envelope = finalized_envelope(staging)

    records: list[dict[str, Any]] = []
    payload_sources: list[tuple[Path, Path]] = []
    total_bytes = 0
    seen_paths: set[str] = set()
    for artifact in envelope["artifacts"]:
        location = artifact["location"]
        if location["kind"] != "bundle":
            raise ValueError("local finalization does not admit external artifact locators")
        relative = logical_path(location["path"])
        text = relative.as_posix()
        if not text.startswith("artifacts/"):
            raise ValueError(f"payload must be beneath artifacts/: {text}")
        if text in {"envelope.json", "public-summary.json", "bundle-index.json"} or text in seen_paths:
            raise ValueError(f"duplicate or reserved bundle path: {text}")
        seen_paths.add(text)
        source = staging_root / relative
        current = staging_root
        for part in relative.parts[:-1]:
            current = current / part
            ensure_owner_directory(current)
        total_bytes += artifact["bytes"]
        if total_bytes > MAX_BUNDLE_BYTES:
            raise ValueError("bundle exceeds 512 MiB")
        data, digest = read_regular(source)
        if stat.S_IMODE(source.lstat().st_mode) != 0o600:
            raise ValueError(f"staging artifact must use mode 0600: {artifact['artifactId']}")
        if len(data) != artifact["bytes"] or digest != artifact["sha256"]:
            raise ValueError(f"staging artifact identity mismatch: {artifact['artifactId']}")
        payload_sources.append((source, relative))
        records.append(_record(
            "payload", text, data, artifact["visibility"], artifact["requirement"] == "required", artifact["artifactId"]
        ))

    envelope_bytes = canonical_json(envelope)
    summary = public_summary(envelope)
    summary_errors = validate_document(summary)
    if summary_errors:
        raise ValueError("public projection rejected: " + "; ".join(summary_errors))
    summary_bytes = canonical_json(summary)
    if len(envelope_bytes) > MAX_ENVELOPE_BYTES or len(summary_bytes) > MAX_ENVELOPE_BYTES:
        raise ValueError("structural evidence record exceeds 4 MiB")
    total_bytes += len(envelope_bytes) + len(summary_bytes)
    if total_bytes > MAX_BUNDLE_BYTES:
        raise ValueError("bundle exceeds 512 MiB")

    records = [
        _record("private-envelope", "envelope.json", envelope_bytes, "private", True),
        _record("public-summary", "public-summary.json", summary_bytes, "public", True),
        *records,
    ]
    if len(records) > 2047:
        raise ValueError("bundle exceeds 2048 files")
    index = {
        "schemaVersion": "mirrors.evidence-bundle-index/v1",
        "runId": envelope["runId"],
        "state": "finalized",
        "jsonEncoding": "mirrors-evidence-json/v1",
        "records": records,
    }
    index_schema = load_json(ROOT / "schema" / "bundle-index-v1.schema.json")
    errors = list(Draft202012Validator(index_schema).iter_errors(index))
    if errors:
        raise ValueError("invalid bundle index: " + "; ".join(error.message for error in errors))
    index_bytes = canonical_json(index)
    if total_bytes + len(index_bytes) > MAX_BUNDLE_BYTES:
        raise ValueError("bundle exceeds 512 MiB")

    runs = store_root / "runs"
    create_owner_directory(runs)
    destination = runs / envelope["runId"]
    create_owner_directory_exclusive(destination)
    for source, relative in payload_sources:
        target = destination / relative
        _mkdir_owner_chain(destination, relative.parent)
        data, digest = read_regular(source)
        record = next(record for record in records if record["role"] == "payload" and record["path"] == relative.as_posix())
        if len(data) != record["bytes"] or digest != record["sha256"]:
            raise ValueError(f"artifact changed before publication: {relative}")
        write_exclusive(target, data)
    expected_records = {record["path"]: record for record in records if record["role"] == "payload"}
    for _, relative in payload_sources:
        record = expected_records[relative.as_posix()]
        data, digest = read_regular(destination / relative)
        if len(data) != record["bytes"] or digest != record["sha256"]:
            raise ValueError(f"artifact changed during publication: {relative}")
    write_exclusive(destination / "envelope.json", envelope_bytes)
    write_exclusive(destination / "public-summary.json", summary_bytes)
    payload_directories: set[Path] = set()
    for _, relative in payload_sources:
        current = destination / relative.parent
        while current != destination:
            payload_directories.add(current)
            current = current.parent
    for parent in sorted(payload_directories, key=lambda path: len(path.parts), reverse=True):
        fsync_directory(parent)
    fsync_directory(destination)
    temporary_index = destination / f".bundle-index-{uuid.uuid4()}.tmp"
    write_exclusive(temporary_index, index_bytes)
    fsync_directory(destination)
    publish_exclusive(destination, temporary_index.name, "bundle-index.json")
    fsync_directory(runs)
    return destination, {
        "schemaVersion": "mirrors.evidence-finalize-result/v1",
        "privateRunRef": {
            "schemaVersion": envelope["schemaVersion"],
            "runId": envelope["runId"],
            "envelopeSha256": sha256(envelope_bytes),
            "projectionKind": "private",
        },
        "publicRunRef": {
            "schemaVersion": summary["schemaVersion"],
            "runId": summary["runId"],
            "envelopeSha256": sha256(summary_bytes),
            "projectionKind": "public",
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("staging", type=Path)
    parser.add_argument("--store", type=Path)
    args = parser.parse_args(argv)
    try:
        destination, result = finalize(args.staging, args.store)
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as error:
        print(f"evidence finalization failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({**result, "bundle": str(destination)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
