#!/usr/bin/env python3
"""Retain a historical producer package pending an honest E1 catalog/run identity."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from finalize import canonical_json
from store import (
    create_owner_directory,
    create_owner_directory_exclusive,
    fsync_directory,
    logical_path,
    publish_exclusive,
    read_regular,
    write_exclusive,
)


LINE = re.compile(r"^([0-9a-f]{64})  (.+)$")
MAX_FILES = 2048
MAX_BYTES = 512 * 1024 * 1024


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def _default_store() -> Path:
    configured = os.environ.get("MIRRORS_EVIDENCE_ROOT")
    if configured:
        return Path(configured)
    state = os.environ.get("XDG_STATE_HOME")
    base = Path(state) if state else Path.home() / ".local" / "state"
    return base / "mirrors" / "evidence" / "v1"


def _manifest_entries(manifest: Path, reference_root: Path) -> list[tuple[str, Path, str]]:
    data, _ = read_regular(manifest, max_bytes=4 * 1024 * 1024)
    entries: list[tuple[str, Path, str]] = []
    seen: set[str] = set()
    root = Path(os.path.abspath(reference_root))
    for number, line in enumerate(data.decode("utf-8").splitlines(), 1):
        if len(entries) >= MAX_FILES:
            raise ValueError("source package exceeds 2048 files")
        match = LINE.fullmatch(line)
        if match is None:
            raise ValueError(f"malformed sha256 manifest line {number}")
        expected, source_text = match.groups()
        source = Path(os.path.abspath(source_text))
        try:
            relative = source.relative_to(root).as_posix()
        except ValueError as error:
            raise ValueError(f"manifest path escapes reference root: {source_text}") from error
        logical_path(relative)
        if relative in seen:
            raise ValueError(f"duplicate manifest path: {relative}")
        seen.add(relative)
        entries.append((relative, source, expected))
    return entries


def retain(package: Path, manifest: Path, reference_root: Path, store: Path, label: str) -> tuple[Path, dict[str, Any]]:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", label):
        raise ValueError("label must be a bounded opaque identifier")
    package = Path(os.path.abspath(package))
    manifest = Path(os.path.abspath(manifest))
    store = Path(os.path.abspath(store))
    create_owner_directory(store)
    pending = store / "pending"
    create_owner_directory(pending)
    destination = pending / f"{label}-{uuid.uuid4()}"
    create_owner_directory_exclusive(destination)
    package_dest = destination / "files" / "package"
    referenced_dest = destination / "files" / "referenced"
    for directory in [destination / "files", package_dest, referenced_dest]:
        create_owner_directory(directory)

    sources: list[tuple[str, str, Path, str | None]] = []
    package_members: list[Path] = []
    for source in package.rglob("*"):
        if len(package_members) >= MAX_FILES:
            raise ValueError("source package exceeds 2048 files")
        package_members.append(source)
    for source in sorted(package_members):
        relative = source.relative_to(package).as_posix()
        logical_path(relative)
        if source.is_symlink() or not source.is_file():
            if source.is_dir():
                continue
            raise ValueError(f"package member is not a regular file: {relative}")
        sources.append(("package", relative, source, None))
    for relative, source, expected in _manifest_entries(manifest, reference_root):
        if len(sources) >= MAX_FILES:
            raise ValueError("source package exceeds 2048 files")
        sources.append(("referenced-manifest-input", relative, source, expected))

    records: list[dict[str, Any]] = []
    total = 0
    directories: set[Path] = set()
    for source_kind, source_name, source, expected in sources:
        data, digest = read_regular(source)
        if expected is not None and digest != expected:
            raise ValueError(f"manifest digest mismatch: {source_name}")
        total += len(data)
        if total > MAX_BYTES:
            raise ValueError("source package exceeds 512 MiB")
        base = package_dest if source_kind == "package" else referenced_dest
        relative = logical_path(source_name)
        target = base / relative
        current = base
        for component in relative.parts[:-1]:
            current = current / component
            create_owner_directory(current)
            directories.add(current)
        write_exclusive(target, data)
        records.append({
            "sourceKind": source_kind,
            "sourceName": source_name,
            "retainedPath": target.relative_to(destination).as_posix(),
            "bytes": len(data),
            "sha256": digest,
        })

    index = {
        "schemaVersion": "mirrors.evidence-source-package/v1",
        "status": "historical-unqualified",
        "label": label,
        "acquiredAtUtc": _utc_now(),
        "files": records,
        "limitations": [
            "no-selected-framework-catalog",
            "no-preserved-pre-run-component-observation",
            "not-an-e1-finalized-run",
            "hashes-prove-retained-bytes-not-execution-truth",
        ],
    }
    for directory in sorted(directories | {package_dest, referenced_dest, destination / "files"}, key=lambda path: len(path.parts), reverse=True):
        fsync_directory(directory)
    fsync_directory(destination)
    temporary = destination / f".source-package-index-{uuid.uuid4()}.tmp"
    index_bytes = canonical_json(index)
    write_exclusive(temporary, index_bytes)
    fsync_directory(destination)
    publish_exclusive(destination, temporary.name, "source-package-index.json")
    fsync_directory(pending)

    for record in records:
        retained, digest = read_regular(destination / record["retainedPath"])
        if len(retained) != record["bytes"] or digest != record["sha256"]:
            raise ValueError(f"retained copy verification failed: {record['sourceName']}")
    return destination, index


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--reference-root", type=Path, required=True)
    parser.add_argument("--store", type=Path, default=None)
    parser.add_argument("--label", required=True)
    args = parser.parse_args(argv)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", args.label):
        parser.error("label must be a bounded opaque identifier")
    try:
        destination, index = retain(
            args.package,
            args.manifest,
            args.reference_root,
            args.store or _default_store(),
            args.label,
        )
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as error:
        print(f"source-package retention failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({
        "destination": str(destination),
        "status": index["status"],
        "files": len(index["files"]),
        "indexSha256": hashlib.sha256(canonical_json(index)).hexdigest(),
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
