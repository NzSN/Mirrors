#!/usr/bin/env python3
"""rc.6 Windows source extract, manifest, and offline Batteries placement.

Runs on the Windows host. Does not build, package, or touch the production service.
"""
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

STAGE = Path(r"D:\ModelMirrors\staging\s3-rc6-20261103-3c4a873")
ARCHIVE = STAGE / "mirrors-v0.2.0-rc.6-source.tar.gz"
SOURCE = STAGE / "mirrors-v0.2.0-rc.6"
PREFIX = "mirrors-v0.2.0-rc.6/"
EXPECTED_ARCHIVE = "87ab9dee6c1a247da0ef4f1a7028c941323997202721ccada2e6ef6c62371a62"
EXPECTED_FILES = 9833
BATTERIES_REV = "4488d40d070b9700d4d5a6aa342f0d40c31b2a2d"
BATTERIES_TREE = "5a1de86f7997958aaffec998882c29006b688d1e"
GIT = Path(r"C:\Program Files\Git\cmd\git.exe")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def extract() -> None:
    if not ARCHIVE.is_file():
        fail(f"archive missing: {ARCHIVE}")
    digest = sha256(ARCHIVE)
    if digest != EXPECTED_ARCHIVE:
        fail(f"archive transfer hash differs: {digest}")
    if SOURCE.exists():
        fail(f"source directory already exists: {SOURCE}")
    with tarfile.open(ARCHIVE, "r:gz") as handle:
        for member in handle.getmembers():
            name = member.name
            if name.startswith("/") or ".." in Path(name).parts:
                fail(f"unsafe archive member: {name}")
            if name != PREFIX.rstrip("/") and not name.startswith(PREFIX):
                fail(f"unexpected archive prefix: {name}")
            if not (member.isdir() or member.isfile()):
                fail(f"unexpected member type {member.type!r}: {name}")
        handle.extractall(STAGE)
    if not SOURCE.is_dir():
        fail("extracted source directory missing")
    if (SOURCE / ".git").exists():
        fail("extracted source contains .git")
    print(f"EXTRACTED {digest}")


def manifest(out_path: str) -> None:
    if not SOURCE.is_dir():
        fail("source directory missing")
    rows = []
    for path in SOURCE.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(SOURCE).as_posix()
        rows.append({"path": rel, "bytes": path.stat().st_size, "sha256": sha256(path)})
    rows.sort(key=lambda row: row["path"])
    destination = Path(out_path)
    destination.write_text("".join(json.dumps(row, separators=(",", ":")) + "\n" for row in rows), encoding="utf-8")
    print(f"MANIFEST {len(rows)} {destination}")
    if len(rows) < EXPECTED_FILES:
        fail(f"file count below archive membership: {len(rows)}")


def place_batteries(tar_path: str) -> None:
    bundle = Path(tar_path)
    if not bundle.is_file():
        fail(f"batteries archive missing: {bundle}")
    dest_parent = SOURCE / ".lake" / "packages"
    dest = dest_parent / "batteries"
    if dest.exists():
        fail("batteries destination already exists")
    hold = STAGE / "batteries-input"
    if hold.exists():
        fail("batteries hold directory already exists")
    hold.mkdir(parents=True)
    with tarfile.open(bundle, "r") as handle:
        for member in handle.getmembers():
            if member.name.startswith("/") or ".." in Path(member.name).parts:
                fail(f"unsafe batteries member: {member.name}")
        handle.extractall(hold)
    copied = hold / "batteries"
    if not copied.is_dir():
        fail("batteries directory missing from transfer archive")
    dest_parent.mkdir(parents=True)
    shutil.move(str(copied), str(dest))
    head = subprocess.run([str(GIT), "-C", str(dest), "rev-parse", "HEAD"], text=True, capture_output=True)
    tree = subprocess.run([str(GIT), "-C", str(dest), "rev-parse", "HEAD^{tree}"], text=True, capture_output=True)
    status = subprocess.run(
        [str(GIT), "-C", str(dest), "-c", "core.autocrlf=false", "-c", "core.filemode=false", "status", "--porcelain=v1"],
        text=True, capture_output=True,
    )
    if head.returncode != 0 or tree.returncode != 0 or status.returncode != 0:
        fail(f"batteries git probe failed: {head.stderr} {tree.stderr} {status.stderr}")
    if head.stdout.strip() != BATTERIES_REV or tree.stdout.strip() != BATTERIES_TREE:
        fail(f"batteries identity differs: {head.stdout.strip()} {tree.stdout.strip()}")
    if status.stdout.strip():
        fail("batteries checkout is dirty")
    manifest_doc = json.loads((SOURCE / "lake-manifest.json").read_text(encoding="utf-8"))
    batteries = next(pkg for pkg in manifest_doc["packages"] if pkg["name"] == "batteries")
    if batteries["rev"] != BATTERIES_REV:
        fail(f"lake-manifest batteries rev differs: {batteries['rev']}")
    record = {
        "schema": "mirrors.s3-rc6.windows-offline-dependency/v1",
        "published": False,
        "deployed": False,
        "name": "batteries",
        "revision": head.stdout.strip(),
        "tree": tree.stdout.strip(),
        "manifestRev": batteries["rev"],
        "gitDirty": False,
        "gitStatusCommand": [str(GIT), "-C", str(dest), "-c", "core.autocrlf=false", "-c", "core.filemode=false", "status", "--porcelain=v1"],
        "note": "Windows Git reports executable-bit differences on four shell scripts unless core.filemode=false. The recorded status uses that override and core.autocrlf=false without writing Git config.",
        "substitutesLockedCarrier": False,
        "missingCarrierSha256": "73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a",
    }
    (STAGE / "windows-offline-dependency.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(f"BATTERIES {head.stdout.strip()} {tree.stdout.strip()}")


def main() -> None:
    command = sys.argv[1]
    if command == "extract":
        extract()
    elif command == "manifest":
        manifest(sys.argv[2])
    elif command == "batteries":
        place_batteries(sys.argv[2])
    elif command == "batteries-record":
        dest = SOURCE / ".lake" / "packages" / "batteries"
        head = subprocess.run([str(GIT), "-C", str(dest), "rev-parse", "HEAD"], text=True, capture_output=True)
        tree = subprocess.run([str(GIT), "-C", str(dest), "rev-parse", "HEAD^{tree}"], text=True, capture_output=True)
        status = subprocess.run(
            [str(GIT), "-C", str(dest), "-c", "core.autocrlf=false", "-c", "core.filemode=false", "status", "--porcelain=v1"],
            text=True, capture_output=True,
        )
        if head.stdout.strip() != BATTERIES_REV or tree.stdout.strip() != BATTERIES_TREE or status.stdout.strip():
            fail(f"batteries record check failed: {head.stdout!r} {tree.stdout!r} {status.stdout!r}")
        manifest_doc = json.loads((SOURCE / "lake-manifest.json").read_text(encoding="utf-8"))
        batteries = next(pkg for pkg in manifest_doc["packages"] if pkg["name"] == "batteries")
        record = {
            "schema": "mirrors.s3-rc6.windows-offline-dependency/v1",
            "published": False,
            "deployed": False,
            "name": "batteries",
            "revision": head.stdout.strip(),
            "tree": tree.stdout.strip(),
            "manifestRev": batteries["rev"],
            "gitDirty": False,
            "gitStatusCommand": ["git", "-c", "core.autocrlf=false", "-c", "core.filemode=false", "status", "--porcelain=v1"],
            "defaultStatusNote": "Host Git without core.filemode=false reports mode changes on four shell scripts. Overrides are command-local and do not edit config.",
            "substitutesLockedCarrier": False,
            "missingCarrierSha256": "73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a",
        }
        (STAGE / "windows-offline-dependency.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        print(f"BATTERIES {head.stdout.strip()} {tree.stdout.strip()}")
    else:
        fail(f"unknown command: {command}")


if __name__ == "__main__":
    main()
