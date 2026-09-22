#!/usr/bin/env python3
"""Verify a finalized evidence bundle without producer scratch state or network."""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

from finalize import canonical_json, public_summary, sha256
from store import ensure_owner_directory, logical_path, read_regular
from validate import ROOT, load_json, loads_json_bytes, validate_document


MAX_INDEX_BYTES = 4 * 1024 * 1024
MAX_BUNDLE_BYTES = 512 * 1024 * 1024


def _mode_600(path: Path) -> None:
    info = path.lstat()
    if stat.S_IMODE(info.st_mode) != 0o600:
        raise ValueError(f"bundle record must use mode 0600: {path}")


def _load_record(path: Path, maximum: int) -> tuple[dict[str, Any], bytes, str]:
    data, digest = read_regular(path, max_bytes=maximum)
    _mode_600(path)
    document = loads_json_bytes(data)
    if canonical_json(document) != data:
        raise ValueError(f"record is not mirrors-evidence-json/v1 canonical bytes: {path.name}")
    return document, data, digest


def verify(bundle: Path, expected_envelope_sha256: str | None = None) -> dict[str, Any]:
    bundle = Path(os.path.abspath(bundle))
    ensure_owner_directory(bundle)
    index_path = bundle / "bundle-index.json"
    if not index_path.exists():
        raise ValueError("bundle is incomplete: committed index is absent")
    index, index_bytes, _ = _load_record(index_path, MAX_INDEX_BYTES)
    schema = load_json(ROOT / "schema" / "bundle-index-v1.schema.json")
    errors = list(Draft202012Validator(schema).iter_errors(index))
    if errors:
        raise ValueError("invalid bundle index: " + "; ".join(error.message for error in errors))

    paths = [record["path"] for record in index["records"]]
    if len(paths) != len(set(paths)):
        raise ValueError("bundle index contains duplicate paths")
    artifact_ids = [record["artifactId"] for record in index["records"] if record["role"] == "payload"]
    if len(artifact_ids) != len(set(artifact_ids)):
        raise ValueError("bundle index contains duplicate artifact IDs")
    structural = {record["role"]: record for record in index["records"] if record["role"] != "payload"}
    if set(structural) != {"private-envelope", "public-summary"}:
        raise ValueError("bundle index must contain exactly one envelope and public summary")
    if structural["private-envelope"]["path"] != "envelope.json" or structural["public-summary"]["path"] != "public-summary.json":
        raise ValueError("bundle structural paths are not canonical")

    declared_total = len(index_bytes) + sum(record["bytes"] for record in index["records"])
    if declared_total > MAX_BUNDLE_BYTES:
        raise ValueError("bundle exceeds 512 MiB")
    verified_structural: dict[str, tuple[bytes, str]] = {}
    total = len(index_bytes)
    for record in index["records"]:
        relative = logical_path(record["path"])
        path = bundle / relative
        # Every directory was created by finalization; none may later become a symlink.
        current = bundle
        for part in relative.parts[:-1]:
            current = current / part
            ensure_owner_directory(current)
        data, digest = read_regular(path)
        _mode_600(path)
        if len(data) != record["bytes"] or digest != record["sha256"]:
            raise ValueError(f"bundle record identity mismatch: {record['path']}")
        total += len(data)
        if total > MAX_BUNDLE_BYTES:
            raise ValueError("bundle exceeds 512 MiB")
        if record["role"] != "payload":
            verified_structural[record["path"]] = (data, digest)

    envelope_bytes, envelope_digest = verified_structural["envelope.json"]
    summary_bytes, summary_digest = verified_structural["public-summary.json"]
    envelope = loads_json_bytes(envelope_bytes)
    summary = loads_json_bytes(summary_bytes)
    if canonical_json(envelope) != envelope_bytes or canonical_json(summary) != summary_bytes:
        raise ValueError("structural record is not mirrors-evidence-json/v1 canonical bytes")
    envelope_errors = validate_document(envelope)
    summary_errors = validate_document(summary)
    if envelope_errors:
        raise ValueError("invalid finalized envelope: " + "; ".join(envelope_errors))
    if summary_errors:
        raise ValueError("invalid public summary: " + "; ".join(summary_errors))
    if envelope["outcomes"]["persistence"]["status"] != "complete":
        raise ValueError("committed envelope does not claim complete persistence")
    if envelope["runId"] != index["runId"] or summary["runId"] != index["runId"]:
        raise ValueError("runId differs across bundle records")
    if canonical_json(public_summary(envelope)) != summary_bytes:
        raise ValueError("public summary is not the exact allowlisted projection")
    if expected_envelope_sha256 is not None and envelope_digest != expected_envelope_sha256:
        raise ValueError("private envelope does not match expected runRef digest")

    expected_payload = {
        artifact["artifactId"]: (
            artifact["location"]["path"], artifact["bytes"], artifact["sha256"],
            artifact["visibility"], artifact["requirement"] == "required",
        )
        for artifact in envelope["artifacts"]
    }
    indexed_payload = {
        record["artifactId"]: (
            record["path"], record["bytes"], record["sha256"], record["visibility"], record["required"]
        )
        for record in index["records"] if record["role"] == "payload"
    }
    if indexed_payload != expected_payload:
        raise ValueError("bundle index payload membership differs from envelope")
    return {
        "schemaVersion": "mirrors.evidence-verification/v1",
        "status": "verified",
        "runId": index["runId"],
        "integrity": "sha256-membership-verified",
        "executionProvenance": "not-established-by-hashes",
        "privateRunRef": {
            "schemaVersion": envelope["schemaVersion"],
            "runId": envelope["runId"],
            "envelopeSha256": envelope_digest,
            "projectionKind": "private",
        },
        "publicRunRef": {
            "schemaVersion": summary["schemaVersion"],
            "runId": summary["runId"],
            "envelopeSha256": summary_digest,
            "projectionKind": "public",
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="assert the verifier performs no network access")
    parser.add_argument("--expected-envelope-sha256")
    parser.add_argument("--historical-index", type=Path)
    parser.add_argument("--catalog", type=Path)
    parser.add_argument("--profile")
    parser.add_argument("--profiles", type=Path)
    parser.add_argument("bundle", type=Path, nargs="?")
    args = parser.parse_args(argv)
    try:
        if args.historical_index is not None:
            if args.bundle is not None or args.expected_envelope_sha256 is not None:
                parser.error("historical-index mode does not accept a bundle or expected run digest")
            from historical import verify_historical

            result = verify_historical(args.historical_index)
        else:
            if args.bundle is None:
                parser.error("a finalized bundle is required")
            result = verify(args.bundle, args.expected_envelope_sha256)
            if args.catalog is not None or args.profile is not None or args.profiles is not None:
                if args.catalog is None or args.profile is None:
                    parser.error("catalog qualification requires --catalog and --profile")
                from catalog_links import DEFAULT_PROFILES, evaluate_catalog_link

                link = evaluate_catalog_link(
                    args.catalog,
                    args.bundle,
                    result,
                    args.profile,
                    args.profiles or DEFAULT_PROFILES,
                )
                result = {**result, "catalogLink": link}
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as error:
        print(f"evidence verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
