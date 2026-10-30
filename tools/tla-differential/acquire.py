#!/usr/bin/env python3
"""Acquire and verify the explicitly pinned DV1 reference toolchain.

Network access is permitted only with --download. Offline restoration requires
an explicitly selected SHA-256 artifact store; normal verification never falls
back to the network, ambient tool installations, or a different artifact.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import http.client
import json
import os
import re
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
STORE_ALGORITHM = "sha256"
HEX_DIGEST = re.compile(r"^[0-9a-f]{64}$")


def pins() -> tuple[dict, dict]:
    try:
        lock = json.loads(LOCK.read_text(encoding="utf-8"))
        return lock["tools"]["apalache"], lock["tools"]["sany"]
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as error:
        raise SystemExit(f"toolchain lock is unreadable: {error}") from error


def relative_pin_path(pin: dict, key: str) -> Path:
    try:
        path = Path(pin[key])
    except KeyError as error:
        raise SystemExit(f"toolchain lock is missing {key}") from error
    if path.is_absolute() or ".." in path.parts or not path.parts:
        raise SystemExit(f"toolchain lock {key} must be a relative path: {path}")
    return path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def download(url: str, destination: Path, *, expected_size: int | None = None) -> None:
    if expected_size is not None and (
        isinstance(expected_size, bool) or not isinstance(expected_size, int) or expected_size < 0
    ):
        raise SystemExit(f"toolchain lock has an invalid size for {destination}: {expected_size}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=60) as response, destination.open("wb") as stream:
        total = 0
        while chunk := response.read(1024 * 1024):
            total += len(chunk)
            if expected_size is not None and total > expected_size:
                raise SystemExit(
                    f"download exceeds pinned size of {expected_size} bytes for {destination}"
                )
            stream.write(chunk)
        stream.flush()
        os.fsync(stream.fileno())


def checked(path: Path, expected: str, *, expected_size: int | None = None, label: str | None = None) -> None:
    description = label or str(path)
    if not HEX_DIGEST.fullmatch(expected):
        raise SystemExit(f"toolchain lock has an invalid sha256 for {description}: {expected}")
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f"required artifact is missing or not a regular file: {description}")
    if expected_size is not None:
        actual_size = path.stat().st_size
        if actual_size != expected_size:
            raise SystemExit(f"size mismatch for {description}: expected {expected_size}, got {actual_size}")
    actual = sha256(path)
    if actual != expected:
        raise SystemExit(f"sha256 mismatch for {description}: expected {expected}, got {actual}")


def standard_library_digest(path: Path) -> str:
    try:
        with zipfile.ZipFile(path) as archive:
            names = sorted(name for name in archive.namelist() if name.startswith("tla2sany/StandardModules/") and name.endswith(".tla"))
            if not names:
                raise SystemExit(f"artifact contains no standard-library modules: {path}")
            digest = hashlib.sha256()
            for name in names:
                content_digest = hashlib.sha256(archive.read(name)).hexdigest()
                digest.update(f"{name} {content_digest}\n".encode())
            return digest.hexdigest()
    except (OSError, zipfile.BadZipFile) as error:
        raise SystemExit(f"invalid tool artifact {path}: {error}") from error


def store_object(store: Path, digest: str) -> Path:
    if not HEX_DIGEST.fullmatch(digest):
        raise SystemExit(f"invalid artifact-store digest: {digest}")
    return Path(store) / STORE_ALGORITHM / digest


def prepare_store(store: Path, *, writable: bool) -> Path:
    store = Path(store).expanduser()
    if store.exists() and not store.is_dir():
        raise SystemExit(f"artifact store is not a directory: {store}")
    if writable:
        store.mkdir(parents=True, exist_ok=True)
    elif not store.is_dir():
        raise SystemExit(f"offline artifact store is missing: {store}")
    return store


def atomic_install(source: Path, destination: Path, expected: str, *, expected_size: int | None = None, label: str | None = None) -> bool:
    """Copy verified bytes to a new path without overwriting existing content."""
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        checked(destination, expected, expected_size=expected_size, label=label)
        return False
    if not source.is_file() or source.is_symlink():
        raise SystemExit(f"source artifact is missing or not a regular file: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{destination.name}.partial-", dir=destination.parent)
    temporary = Path(temporary_name)
    try:
        with source.open("rb") as input_stream, os.fdopen(descriptor, "wb") as output_stream:
            descriptor = -1
            shutil.copyfileobj(input_stream, output_stream, length=1024 * 1024)
            output_stream.flush()
            os.fsync(output_stream.fileno())
        checked(temporary, expected, expected_size=expected_size, label=label)
        try:
            os.link(temporary, destination)
        except FileExistsError:
            checked(destination, expected, expected_size=expected_size, label=label)
            return False
        return True
    finally:
        if descriptor != -1:
            os.close(descriptor)
        temporary.unlink(missing_ok=True)


def publish_to_store(store: Path, source: Path, pin: dict, label: str) -> Path:
    destination = store_object(store, pin["sha256"])
    atomic_install(source, destination, pin["sha256"], expected_size=pin.get("size"), label=f"artifact-store object {destination}")
    return destination


def download_to_toolchain(pin: dict, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{target.name}.download-", dir=target.parent)
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        try:
            download(pin["url"], temporary, expected_size=pin.get("size"))
        except (OSError, http.client.HTTPException) as error:
            raise SystemExit(f"download failed for {target.name}: {error}") from error
        checked(temporary, pin["sha256"], expected_size=pin.get("size"), label=f"downloaded {target.name}")
        atomic_install(temporary, target, pin["sha256"], expected_size=pin.get("size"), label=str(target))
    finally:
        temporary.unlink(missing_ok=True)


def acquire_artifact(pin: dict, store: Path | None, *, allow_network: bool) -> Path:
    target = TOOLCHAIN / relative_pin_path(pin, "path")
    if target.exists() or target.is_symlink():
        checked(target, pin["sha256"], expected_size=pin.get("size"), label=str(target))
        if allow_network and store is not None:
            publish_to_store(store, target, pin, str(target))
        return target

    if store is not None:
        cached = store_object(store, pin["sha256"])
        if cached.exists() or cached.is_symlink():
            checked(cached, pin["sha256"], expected_size=pin.get("size"), label=f"artifact-store object {cached}")
            atomic_install(cached, target, pin["sha256"], expected_size=pin.get("size"), label=str(target))
            return target
        if not allow_network:
            raise SystemExit(f"required artifact is missing from the offline artifact store: {cached}")
    elif not allow_network:
        raise SystemExit(f"required artifact is missing: {target} (offline mode does not download)")

    download_to_toolchain(pin, target)
    if store is not None:
        publish_to_store(store, target, pin, str(target))
    return target


def apalache_distribution(pin: dict) -> Path:
    return TOOLCHAIN / relative_pin_path(pin, "installPath")


def verify_apalache_distribution(pin: dict, distribution: Path | None = None) -> None:
    distribution = distribution or apalache_distribution(pin)
    if not distribution.is_dir():
        raise SystemExit(f"Apalache archive is verified but extracted distribution is missing: {distribution}")
    jar = distribution / relative_pin_path(pin, "jarPath")
    launcher = distribution / relative_pin_path(pin, "launcherPath")
    checked(jar, pin["jarSha256"], expected_size=pin.get("jarSize"), label=str(jar))
    checked(launcher, pin["launcherSha256"], expected_size=pin.get("launcherSize"), label=str(launcher))
    if standard_library_digest(jar) != pin["standardLibrarySha256"]:
        raise SystemExit("Apalache standard-library identity does not match the lock")


def rename_noreplace(source: Path, destination: Path) -> None:
    """Rename a directory without replacing an existing destination."""
    if os.name == "nt":
        os.rename(source, destination)
        return
    try:
        renameat2 = ctypes.CDLL(None, use_errno=True).renameat2
    except AttributeError as error:
        raise SystemExit(
            "atomic no-clobber directory publication is unsupported on this platform"
        ) from error
    renameat2.argtypes = [
        ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint
    ]
    renameat2.restype = ctypes.c_int
    at_fdcwd = -100
    rename_noreplace_flag = 1
    result = renameat2(
        at_fdcwd, os.fsencode(source), at_fdcwd, os.fsencode(destination),
        rename_noreplace_flag,
    )
    if result != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), destination)


def publish_apalache_distribution(pin: dict, source: Path, destination: Path) -> bool:
    try:
        rename_noreplace(source, destination)
        return True
    except OSError:
        if destination.exists() or destination.is_symlink():
            verify_apalache_distribution(pin, destination)
            return False
        raise


def extract_apalache(pin: dict, archive: Path) -> None:
    distribution = apalache_distribution(pin)
    if distribution.exists() or distribution.is_symlink():
        verify_apalache_distribution(pin, distribution)
        return
    try:
        archive_root = pin["archiveRoot"].rstrip("/")
    except (KeyError, AttributeError) as error:
        raise SystemExit("toolchain lock is missing archiveRoot") from error
    if not archive_root or ".." in Path(archive_root).parts:
        raise SystemExit(f"invalid Apalache archive root: {archive_root}")
    prefix = archive_root + "/"
    TOOLCHAIN.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f".{distribution.name}.partial-", dir=TOOLCHAIN))
    try:
        with tarfile.open(archive) as source:
            selected = []
            for member in source.getmembers():
                if member.name == archive_root:
                    continue
                if not member.name.startswith(prefix):
                    raise SystemExit(f"unexpected path in Apalache archive: {member.name}")
                relative_name = member.name[len(prefix):]
                if not relative_name or ".." in Path(relative_name).parts or Path(relative_name).is_absolute():
                    raise SystemExit(f"unsafe path in Apalache archive: {member.name}")
                if not member.isfile() and not member.isdir():
                    raise SystemExit(f"unsupported member in Apalache archive: {member.name}")
                member.name = relative_name
                selected.append(member)
            if not selected:
                raise SystemExit("Apalache archive is empty")
            source.extractall(temporary, members=selected, filter="data")
        verify_apalache_distribution(pin, temporary)
        if publish_apalache_distribution(pin, temporary, distribution):
            temporary = None
    except (OSError, tarfile.TarError) as error:
        raise SystemExit(f"Apalache extraction failed: {error}") from error
    finally:
        if temporary is not None:
            shutil.rmtree(temporary, ignore_errors=True)


def runtime_pin() -> dict:
    try:
        runtime = json.loads(LOCK.read_text(encoding="utf-8"))["tools"]["runtime"]
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as error:
        raise SystemExit(f"toolchain lock runtime is unreadable: {error}") from error
    if not isinstance(runtime, dict) or any(
        not isinstance(runtime.get(key), str) or not runtime[key] for key in ("command", "version", "build")
    ):
        raise SystemExit("toolchain lock runtime is missing command, version, or build")
    return runtime


def java_identity_matches(output: str, version: str, build: str) -> bool:
    version_pattern = re.compile(rf'^(?:openjdk|java) version "{re.escape(version)}"(?:\s|$)', re.MULTILINE)
    build_pattern = re.compile(rf"\bbuild {re.escape(build)}(?=$|[),+\-\s])")
    return version_pattern.search(output) is not None and build_pattern.search(output) is not None


def verify_tools() -> None:
    apalache_pin, sany_pin = pins()
    sany = TOOLCHAIN / relative_pin_path(sany_pin, "path")
    apalache = TOOLCHAIN / relative_pin_path(apalache_pin, "path")
    checked(apalache, apalache_pin["sha256"], expected_size=apalache_pin.get("size"), label=str(apalache))
    checked(sany, sany_pin["sha256"], expected_size=sany_pin.get("size"), label=str(sany))
    verify_apalache_distribution(apalache_pin)
    if standard_library_digest(sany) != sany_pin["standardLibrarySha256"]:
        raise SystemExit("SANY standard-library identity does not match the lock")

    runtime = runtime_pin()
    java = shutil.which(runtime["command"])
    if java is None:
        raise SystemExit("java is required for DV1 qualification")
    java_result = subprocess.run([java, "-XX:-UsePerfData", "-version"], text=True, capture_output=True, check=False)
    if java_result.returncode != 0 or not java_identity_matches(java_result.stderr, runtime["version"], runtime["build"]):
        raise SystemExit(f"Java {runtime['build']} is required for DV1 qualification")
    result = subprocess.run([java, "-XX:-UsePerfData", "-cp", str(sany), "tla2sany.SANY", "-help"], text=True, capture_output=True, check=False)
    if result.returncode != 0 or sany_pin["version"] not in result.stdout:
        raise SystemExit(f"standalone SANY qualification failed (exit {result.returncode})")
    print(f"verified Apalache archive: {apalache}")
    print(f"verified standalone SANY jar: {sany}")
    print(next((line.strip() for line in result.stdout.splitlines() if sany_pin["version"] in line), sany_pin["version"]))


def acquire(store: Path | None = None, *, allow_network: bool = True) -> None:
    apalache_pin, sany_pin = pins()
    if store is not None:
        store = prepare_store(store, writable=allow_network)
    acquire_artifact(apalache_pin, store, allow_network=allow_network)
    acquire_artifact(sany_pin, store, allow_network=allow_network)
    apalache = TOOLCHAIN / relative_pin_path(apalache_pin, "path")
    extract_apalache(apalache_pin, apalache)
    verify_tools()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--download", action="store_true", help="permit downloads from the locked release URLs")
    mode.add_argument("--offline", action="store_true", help="forbid network access; restore from --artifact-store when needed")
    parser.add_argument("--artifact-store", type=Path, metavar="DIRECTORY", help="explicit SHA-256 content-addressed artifact store")
    args = parser.parse_args()
    store = args.artifact_store.expanduser().resolve() if args.artifact_store is not None else None
    try:
        if args.download:
            acquire(store, allow_network=True)
        elif store is not None:
            acquire(store, allow_network=False)
        else:
            verify_tools()
    except (OSError, tarfile.TarError, zipfile.BadZipFile, json.JSONDecodeError) as error:
        raise SystemExit(f"toolchain acquisition failed: {error}") from error
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
