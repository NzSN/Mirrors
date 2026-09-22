#!/usr/bin/env python3
"""Create immutable regular-file source snapshots matching component-lock refs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MIRRORS = HERE.parents[1]
sys.path.insert(0, str(MIRRORS / "tools/evidence"))
from collect import component_ref  # type: ignore  # noqa: E402
from store import logical_path, read_regular  # type: ignore  # noqa: E402

MAX_FILES = 20_000
MAX_BYTES = 1024 * 1024 * 1024


def git(repository: Path, *arguments: str) -> bytes:
    result = subprocess.run(["git", "-C", str(repository), *arguments], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise ValueError(result.stderr.decode("utf-8", "replace").strip())
    return result.stdout


def write_regular(path: Path, data: bytes, executable: bool) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0),
        0o755 if executable else 0o644)
    try:
        offset = 0
        while offset < len(data):
            offset += os.write(descriptor, data[offset:])
    finally:
        os.close(descriptor)


def snapshot(repository: Path, ref: dict, destination: Path) -> dict:
    exclusions = {entry["path"]: entry["reasonCode"]
        for entry in ref.get("dirtyContent", {}).get("excludedPaths", [])}
    before = component_ref(ref["componentId"], repository, exclusions)
    if before != ref:
        raise ValueError(f"live component differs from lock before snapshot: {ref['componentId']}")
    destination.mkdir(mode=0o700, parents=True, exist_ok=False)
    records = git(repository, "ls-tree", "-rz", "--full-tree", ref["revision"]).split(b"\0")
    count = 0
    total = 0
    for raw in records:
        if not raw:
            continue
        metadata, raw_path = raw.split(b"\t", 1)
        mode, kind, object_id = metadata.decode("ascii").split(" ")
        path = logical_path(raw_path.decode("utf-8"))
        if kind != "blob" or mode not in {"100644", "100755"}:
            raise ValueError(f"unsupported tracked source entry: {path} {mode} {kind}")
        data = git(repository, "cat-file", "blob", object_id)
        count += 1
        total += len(data)
        if count > MAX_FILES or total > MAX_BYTES:
            raise ValueError("source snapshot bound exceeded")
        write_regular(destination / path, data, mode == "100755")
    for path in ref.get("dirtyContent", {}).get("includedPaths", []):
        source = repository / logical_path(path)
        target = destination / path
        if not source.exists():
            if target.exists():
                target.unlink()
            continue
        data, _digest = read_regular(source, max_bytes=512 * 1024 * 1024)
        if target.exists():
            target.unlink()
        write_regular(target, data, bool(source.stat().st_mode & stat.S_IXUSR))
    for path in exclusions:
        target = destination / logical_path(path)
        if target.is_file():
            target.unlink()
    after = component_ref(ref["componentId"], repository, exclusions)
    if after != before:
        raise ValueError(f"live component changed during snapshot: {ref['componentId']}")
    files = []
    for path in sorted(item for item in destination.rglob("*") if item.is_file()):
        data, digest = read_regular(path)
        files.append({"path": path.relative_to(destination).as_posix(), "bytes": len(data),
            "sha256": digest, "executable": bool(path.stat().st_mode & stat.S_IXUSR)})
    return {"componentRef": ref, "files": files,
        "treeIndexSha256": hashlib.sha256(json.dumps(files, sort_keys=True,
            separators=(",", ":")).encode()).hexdigest()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--component-lock", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--mirrors", type=Path, default=MIRRORS)
    parser.add_argument("--mirrorecma", type=Path, default=MIRRORS.parent / "MirrorECMA")
    parser.add_argument("--mirrorgate", type=Path, default=MIRRORS.parent / "MirrorGate")
    args = parser.parse_args()
    if args.out.exists():
        print("snapshot output must not exist", file=sys.stderr)
        return 1
    lock = json.loads(args.component_lock.read_text())
    repositories = {"mirrors": args.mirrors.resolve(), "mirrorecma": args.mirrorecma.resolve(),
        "mirrorgate": args.mirrorgate.resolve()}
    args.out.mkdir(mode=0o700, parents=True)
    try:
        indexes = []
        for entry in lock["components"]:
            ref = entry["componentRef"]
            indexes.append(snapshot(repositories[ref["componentId"]], ref,
                args.out / "sources" / ref["componentId"]))
        (args.out / "snapshot-index.json").write_text(json.dumps({
            "schemaVersion": "mirrors.source-snapshot/v1", "components": indexes,
        }, sort_keys=True, indent=2) + "\n")
        print("SOURCE SNAPSHOT GREEN")
        return 0
    except Exception as error:
        shutil.rmtree(args.out, ignore_errors=True)
        print(f"source snapshot failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
