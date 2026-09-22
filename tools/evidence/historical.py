"""Validate the additive historical artifact availability sidecar."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any, Iterable

from store import logical_path, read_regular
from validate import loads_json_bytes


SCHEMA = "mirrors.historical-artifact-availability/v1"
AVAILABILITY = {"retained-and-verified", "unavailable-at-audit", "external-with-policy", "unverified"}
REQUIRED_SOURCE_RECORDS = {
    "Docs/application-integration-evidence.json",
    "Docs/client-conformance-update-evidence.json",
    "Docs/async-protocol-resource-evidence.json",
    "Docs/async-resource-lean-evidence.json",
}
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def _escape(value: str) -> str:
    return value.replace("~", "~0").replace("/", "~1")


def _walk_absolute(value: Any, pointer: str = "") -> Iterable[tuple[str, str, Any]]:
    if isinstance(value, dict):
        for key, child in value.items():
            yield from _walk_absolute(child, f"{pointer}/{_escape(key)}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _walk_absolute(child, f"{pointer}/{index}")
    elif isinstance(value, str) and value.startswith("/"):
        yield pointer, value, None


def _unescape(value: str) -> str:
    return value.replace("~1", "/").replace("~0", "~")


def _resolve(root: Any, pointer: str) -> tuple[Any, Any]:
    current = root
    parent = None
    if not pointer.startswith("/"):
        raise ValueError(f"invalid JSON pointer: {pointer}")
    for raw in pointer.split("/")[1:]:
        parent = current
        token = _unescape(raw)
        current = current[int(token)] if isinstance(current, list) else current[token]
    return current, parent


def _recorded_identity(parent: Any) -> dict[str, str] | None:
    if not isinstance(parent, dict):
        return None
    if isinstance(parent.get("logSha256"), str):
        return {"kind": "sha256", "value": parent["logSha256"]}
    if isinstance(parent.get("sha256"), str):
        return {"kind": "sha256", "value": parent["sha256"]}
    if isinstance(parent.get("commit"), str):
        return {"kind": "git-commit", "value": parent["commit"]}
    return None


def verify_historical(index_path: Path, repository_root: Path | None = None) -> dict[str, Any]:
    index_path = Path(index_path)
    repository_root = Path(repository_root or Path.cwd()).resolve()
    index_bytes, _ = read_regular(index_path, max_bytes=4 * 1024 * 1024)
    index = loads_json_bytes(index_bytes)
    if not isinstance(index, dict) or set(index) != {"schemaVersion", "audit", "sourceRecords", "entries"}:
        raise ValueError("historical index root must use the closed v1 shape")
    if index["schemaVersion"] != SCHEMA:
        raise ValueError("unsupported historical availability schema")
    audit = index["audit"]
    if not isinstance(audit, dict) or set(audit) != {"auditedAtUtc", "method", "noRuntimeRerun"}:
        raise ValueError("historical audit must use the closed v1 shape")
    if not isinstance(audit["auditedAtUtc"], str) or not audit["auditedAtUtc"].endswith("Z") or not isinstance(audit["method"], str):
        raise ValueError("historical audit time/method are malformed")
    if audit.get("noRuntimeRerun") is not True:
        raise ValueError("historical audit must state that no runtime gate was rerun")
    if not isinstance(index["sourceRecords"], list) or not isinstance(index["entries"], list):
        raise ValueError("historical sourceRecords and entries must be arrays")

    source_records: dict[str, Any] = {}
    for source in index["sourceRecords"]:
        if not isinstance(source, dict) or set(source) != {"path", "sha256"}:
            raise ValueError("sourceRecords entries must use the closed v1 shape")
        if not isinstance(source["path"], str) or not isinstance(source["sha256"], str) or SHA256.fullmatch(source["sha256"]) is None:
            raise ValueError("sourceRecords path/hash are malformed")
        relative = logical_path(source["path"])
        if source["path"] in source_records:
            raise ValueError(f"duplicate source record: {source['path']}")
        path = repository_root / relative
        data, digest = read_regular(path, max_bytes=4 * 1024 * 1024)
        if digest != source["sha256"]:
            raise ValueError(f"source record hash changed: {source['path']}")
        source_records[source["path"]] = loads_json_bytes(data)
    if set(source_records) != REQUIRED_SOURCE_RECORDS:
        missing = sorted(REQUIRED_SOURCE_RECORDS - set(source_records))
        extra = sorted(set(source_records) - REQUIRED_SOURCE_RECORDS)
        detail = f"missing {missing[0]}" if missing else f"unexpected {extra[0]}"
        raise ValueError(f"historical audit source scope is incomplete: {detail}")

    entries: dict[tuple[str, str], dict[str, Any]] = {}
    for entry in index["entries"]:
        required = {
            "sourceRecord", "pointer", "originalLocator", "recordedIdentity", "availability",
            "qualifying", "note",
        }
        allowed = required | {"retainedPath", "auditMethod"}
        if not isinstance(entry, dict) or not required.issubset(entry) or not set(entry).issubset(allowed):
            raise ValueError("historical entry must use the closed v1 shape")
        if not all(isinstance(entry[name], str) for name in ["sourceRecord", "pointer", "originalLocator", "availability", "note"]):
            raise ValueError("historical entry string field is malformed")
        if entry["qualifying"] is not False:
            raise ValueError("historical availability rows are non-qualifying")
        identity = entry["recordedIdentity"]
        if identity is not None:
            if not isinstance(identity, dict) or set(identity) != {"kind", "value"} or identity.get("kind") not in {"sha256", "git-commit"} or not isinstance(identity.get("value"), str):
                raise ValueError("historical recordedIdentity is malformed")
            length = 64 if identity["kind"] == "sha256" else 40
            if re.fullmatch(f"[0-9a-f]{{{length}}}", identity["value"]) is None:
                raise ValueError("historical recordedIdentity value is malformed")
        key = (entry["sourceRecord"], entry["pointer"])
        if key in entries:
            raise ValueError(f"duplicate historical pointer: {key[0]}#{key[1]}")
        entries[key] = entry
        if entry["availability"] not in AVAILABILITY or entry["availability"] == "fresh":
            raise ValueError(f"unsupported historical availability: {entry['availability']}")
        source = source_records.get(entry["sourceRecord"])
        if source is None:
            raise ValueError(f"entry references unknown source record: {entry['sourceRecord']}")
        try:
            locator, parent = _resolve(source, entry["pointer"])
        except (KeyError, IndexError, ValueError, TypeError) as error:
            raise ValueError(f"historical pointer does not resolve: {key[0]}#{key[1]}") from error
        if locator != entry["originalLocator"]:
            raise ValueError(f"original locator changed: {key[0]}#{key[1]}")
        if _recorded_identity(parent) != entry["recordedIdentity"]:
            raise ValueError(f"recorded identity changed: {key[0]}#{key[1]}")
        if entry["availability"] == "retained-and-verified":
            retained = entry.get("retainedPath")
            identity = entry["recordedIdentity"]
            if not isinstance(retained, str) or not isinstance(identity, dict) or identity.get("kind") != "sha256":
                raise ValueError("retained row requires retainedPath and recorded SHA-256")
            if not isinstance(retained, str):
                raise ValueError("retained row requires retainedPath and recorded SHA-256")
            retained_relative = logical_path(retained)
            data, digest = read_regular(repository_root / retained_relative)
            if digest != identity["value"]:
                raise ValueError(f"retained artifact hash mismatch: {retained}")
            if not data and identity["value"] != hashlib.sha256(b"").hexdigest():
                raise ValueError(f"retained artifact bytes are absent: {retained}")
        elif "retainedPath" in entry:
            raise ValueError("only retained-and-verified rows may carry retainedPath")

    expected: set[tuple[str, str]] = set()
    for source_path, source in source_records.items():
        for pointer, _locator, _parent in _walk_absolute(source):
            expected.add((source_path, pointer))
    missing = sorted(expected - set(entries))
    extra = sorted(set(entries) - expected)
    if missing:
        raise ValueError(f"historical index is missing pointer: {missing[0][0]}#{missing[0][1]}")
    if extra:
        raise ValueError(f"historical index has extra pointer: {extra[0][0]}#{extra[0][1]}")
    counts = {state: 0 for state in sorted(AVAILABILITY)}
    for entry in entries.values():
        counts[entry["availability"]] += 1
    return {
        "schemaVersion": "mirrors.historical-artifact-verification/v1",
        "status": "verified-historical-index",
        "qualifying": False,
        "entries": len(entries),
        "availabilityCounts": counts,
    }
