#!/usr/bin/env python3
"""Acquire and verify the explicitly pinned DV1 reference toolchain.

Downloads happen only with --download. Normal verification never falls back to
the network, ambient PATH tools, or a previously installed distribution.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLCHAIN = ROOT / ".golden-build/tla-differential/toolchain"
LOCK = ROOT / "tools/tla-differential/toolchain.lock.json"


def pins() -> tuple[dict, dict]:
    lock = json.loads(LOCK.read_text())
    return lock["tools"]["apalache"], lock["tools"]["sany"]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def download(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url) as response, destination.open("wb") as stream:
        shutil.copyfileobj(response, stream)


def checked(path: Path, expected: str) -> None:
    if not path.is_file():
        raise SystemExit(f"required artifact is missing: {path}")
    actual = sha256(path)
    if actual != expected:
        raise SystemExit(f"sha256 mismatch for {path}: expected {expected}, got {actual}")


def standard_library_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with zipfile.ZipFile(path) as archive:
        names = sorted(name for name in archive.namelist() if name.startswith("tla2sany/StandardModules/") and name.endswith(".tla"))
        for name in names:
            content_digest = hashlib.sha256(archive.read(name)).hexdigest()
            digest.update(f"{name} {content_digest}\n".encode())
    return digest.hexdigest()


def verify_tools() -> None:
    apalache_pin, sany_pin = pins()
    apalache = TOOLCHAIN / "downloads/apalache-0.61.0.tgz"
    sany = TOOLCHAIN / "downloads/tla2tools-1.8.0.jar"
    checked(apalache, apalache_pin["sha256"])
    checked(sany, sany_pin["sha256"])
    distribution = TOOLCHAIN / "apalache-0.61.0"
    apalache_jar = distribution / "lib/apalache.jar"
    launcher = distribution / "bin/apalache-mc"
    if not apalache_jar.is_file() or not launcher.is_file():
        raise SystemExit("Apalache archive is verified but extracted distribution is missing")
    if sha256(apalache_jar) != apalache_pin["jarSha256"]:
        raise SystemExit("Apalache extracted jar hash does not match the lock")
    if standard_library_digest(sany) != sany_pin["standardLibrarySha256"]:
        raise SystemExit("SANY standard-library identity does not match the lock")
    if standard_library_digest(apalache_jar) != apalache_pin["standardLibrarySha256"]:
        raise SystemExit("Apalache standard-library identity does not match the lock")
    java = shutil.which("java")
    if java is None:
        raise SystemExit("java is required for DV1 qualification")
    java_result = subprocess.run([java, "-XX:-UsePerfData", "-version"], text=True, capture_output=True, check=False)
    if java_result.returncode != 0 or "25.0.4+7" not in java_result.stderr:
        raise SystemExit("Java 25.0.4+7 is required for DV1 qualification")
    result = subprocess.run([java, "-XX:-UsePerfData", "-cp", str(sany), "tla2sany.SANY", "-help"], text=True, capture_output=True, check=False)
    if result.returncode != 0 or "Version 2.2 created 08 July 2020" not in result.stdout:
        raise SystemExit(f"standalone SANY qualification failed (exit {result.returncode})")
    print(f"verified Apalache archive: {apalache}")
    print(f"verified standalone SANY jar: {sany}")
    print(result.stdout.splitlines()[2].strip())


def acquire() -> None:
    apalache_pin, sany_pin = pins()
    downloads = TOOLCHAIN / "downloads"
    downloads.parent.mkdir(parents=True, exist_ok=True)
    apalache = downloads / "apalache-0.61.0.tgz"
    sany = downloads / "tla2tools-1.8.0.jar"
    if apalache.exists() or sany.exists():
        raise SystemExit("refusing to overwrite an existing DV1 download; remove it explicitly")
    with tempfile.TemporaryDirectory(dir=downloads.parent) as temporary:
        temporary_path = Path(temporary)
        a_tmp, s_tmp = temporary_path / apalache.name, temporary_path / sany.name
        download(apalache_pin["url"], a_tmp)
        checked(a_tmp, apalache_pin["sha256"])
        download(sany_pin["url"], s_tmp)
        checked(s_tmp, sany_pin["sha256"])
        downloads.mkdir(parents=True, exist_ok=True)
        a_tmp.replace(apalache)
        s_tmp.replace(sany)
    distribution = TOOLCHAIN / "apalache-0.61.0"
    distribution.mkdir(parents=True, exist_ok=False)
    with tarfile.open(apalache) as archive:
        members = archive.getmembers()
        prefix = "apalache-0.61.0/"
        selected = []
        for member in members:
            if member.name == prefix[:-1]:
                continue
            if not member.name.startswith(prefix):
                raise SystemExit(f"unexpected path in Apalache archive: {member.name}")
            member.name = member.name[len(prefix):]
            selected.append(member)
        archive.extractall(distribution, members=selected, filter="data")
    verify_tools()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true", help="download the pinned artifacts")
    args = parser.parse_args()
    if args.download:
        acquire()
    else:
        verify_tools()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
