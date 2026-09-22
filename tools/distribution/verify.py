#!/usr/bin/env python3
"""Verify a finalized reference-distribution cache without executing its tools."""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
import tarfile
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MIRRORS = HERE.parents[1]
sys.path.insert(0, str(HERE))
from distribution_lib import extract_selected_node, extract_selected_tree, runtime_tree, sha256_file
from manifest_check import (ContractError, digest_json, load_json, validate_cache_index,
    run_trusted_catalog_validation, validate_distribution_manifest, validate_locks)


def safe_extract_regular(archive_path: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=False)
    seen: set[str] = set()
    casefolded: set[str] = set()
    total = 0
    count = 0
    with tarfile.open(archive_path, "r:*") as archive:
        for member in archive:
            path = Path(member.name)
            logical = path.as_posix()
            if (path.is_absolute() or ".." in path.parts or "." in path.parts or
                    len(logical.encode()) > 1024):
                raise ContractError(f"unsafe archive member: {member.name}")
            if logical in seen or logical.casefold() in casefolded:
                raise ContractError(f"duplicate or case-colliding archive member: {member.name}")
            seen.add(logical); casefolded.add(logical.casefold())
            count += 1; total += member.size
            if count > 100_000 or member.size > 512 * 1024 * 1024 or total > 2 * 1024 * 1024 * 1024:
                raise ContractError("archive extraction bound exceeded")
            if member.isdir():
                continue
            if not member.isfile() or member.issym() or member.islnk():
                raise ContractError(f"unsafe archive member: {member.name}")
            source = archive.extractfile(member)
            if source is None:
                raise ContractError(f"cannot read archive member: {member.name}")
            target = destination / path
            target.parent.mkdir(parents=True, exist_ok=True)
            descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            written = 0
            try:
                while chunk := source.read(min(1024 * 1024, member.size - written + 1)):
                    written += len(chunk)
                    if written > member.size:
                        raise ContractError(f"archive member exceeds declared size: {member.name}")
                    offset = 0
                    while offset < len(chunk):
                        offset += os.write(descriptor, chunk[offset:])
            finally:
                os.close(descriptor)
            if written != member.size:
                raise ContractError(f"archive member is truncated: {member.name}")
            target.chmod(0o755 if member.mode & 0o111 else 0o644)


def reject_symlink_chain(path: Path) -> None:
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        if current.exists() and stat.S_ISLNK(current.lstat().st_mode):
            raise ContractError(f"symlink path component is forbidden: {current}")


def verify(cache: Path, framework_catalog_bin: Path, framework_catalog_sha256: str,
    allow_pinned_fd: bool = False) -> tuple[dict, str, dict]:
    cache = cache.absolute()
    if not (allow_pinned_fd and str(cache).startswith("/proc/self/fd/")):
        reject_symlink_chain(cache)
    if not cache.is_dir() or stat.S_ISLNK(cache.lstat().st_mode):
        raise ContractError("cache must be a real directory")
    bootstrap_manifest = load_json(cache / "distribution-manifest.json")
    bootstrap_artifacts = {entry.get("artifactId"): entry for entry in bootstrap_manifest.get("artifacts", [])
        if isinstance(entry, dict)}
    if "distribution-locks" not in bootstrap_artifacts or "selected-catalog" not in bootstrap_artifacts:
        raise ContractError("bootstrap locks/catalog artifacts are missing")
    for artifact_id in ("distribution-locks", "selected-catalog"):
        entry = bootstrap_artifacts[artifact_id]
        path = cache / entry.get("path", "")
        size, digest = sha256_file(path)
        if size != entry.get("bytes") or digest != entry.get("sha256"):
            raise ContractError(f"bootstrap artifact identity mismatch: {artifact_id}")
    with tempfile.TemporaryDirectory(prefix="mirrors-distribution-bootstrap-") as temporary:
        bootstrap = Path(temporary)
        safe_extract_regular(cache / bootstrap_artifacts["distribution-locks"]["path"],
            bootstrap / "extracted")
        extracted = bootstrap / "extracted/distribution-locks"
        lock_root = bootstrap / "distribution/reference-node"
        lock_root.mkdir(parents=True)
        for name in ("profiles.json", "component-lock.json", "dependency-lock.json"):
            (lock_root / name).write_bytes((extracted / name).read_bytes())
        catalog_root = bootstrap / "catalog"; catalog_root.mkdir()
        (catalog_root / "framework-catalog.json").write_bytes(
            (cache / bootstrap_artifacts["selected-catalog"]["path"]).read_bytes())
        contract = validate_locks(lock_root, framework_catalog_bin, framework_catalog_sha256)
        manifest_pair = validate_distribution_manifest(cache / "distribution-manifest.json",
            bootstrap_manifest["profileId"], contract)
        manifest, manifest_digest = manifest_pair
        validate_cache_index(cache / "cache-index.json", manifest["profileId"], contract, manifest_pair)
    expected = {"distribution-manifest.json", "cache-index.json"}
    for artifact in manifest["artifacts"]:
        expected.add(artifact["path"])
        path = cache / artifact["path"]
        size, digest = sha256_file(path)
        if size != artifact["bytes"] or digest != artifact["sha256"]:
            raise ContractError(f"artifact identity mismatch: {artifact['artifactId']}")
        actual_mode = "0755" if path.stat().st_mode & stat.S_IXUSR else "0644"
        if actual_mode != artifact["mode"]:
            raise ContractError(f"artifact mode mismatch: {artifact['artifactId']}")
        for library in artifact.get("dynamicLibraries", []):
            size_unused, library_digest = sha256_file(Path(library["path"]))
            if library_digest != library["sha256"]:
                raise ContractError(f"dynamic library identity mismatch: {library['soname']}")
    actual = set(); actual_directories = {""}; entry_count = 0
    for path in cache.rglob("*"):
        entry_count += 1
        if entry_count > 100_000:
            raise ContractError("cache entry count exceeds 100000")
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not (stat.S_ISDIR(metadata.st_mode) or stat.S_ISREG(metadata.st_mode)):
            raise ContractError(f"unsupported cache entry: {path}")
        if stat.S_ISREG(metadata.st_mode):
            actual.add(path.relative_to(cache).as_posix())
        else:
            actual_directories.add(path.relative_to(cache).as_posix())
    if actual != expected:
        raise ContractError(f"cache file set mismatch: missing={sorted(expected-actual)}, extra={sorted(actual-expected)}")
    expected_directories = {""}
    for logical in expected:
        parent = Path(logical).parent
        while parent != Path("."):
            expected_directories.add(parent.as_posix())
            parent = parent.parent
    if actual_directories != expected_directories:
        raise ContractError(f"cache directory set mismatch: missing={sorted(expected_directories-actual_directories)}, extra={sorted(actual_directories-expected_directories)}")
    artifacts = {entry["artifactId"]: cache / entry["path"] for entry in manifest["artifacts"]}
    selected_catalog = artifacts.get("selected-catalog")
    if selected_catalog is None:
        raise ContractError("immutable selected catalog A artifact is missing")
    if digest_json(load_json(selected_catalog)) != manifest["catalogSelectionRef"]["selectionValue"]:
        raise ContractError("selected catalog A bytes differ from catalogSelectionRef")
    returncode, stdout, stderr = run_trusted_catalog_validation(framework_catalog_bin,
        framework_catalog_sha256, selected_catalog)
    if returncode:
        raise ContractError(f"selected catalog A fails C3 validation: {(stderr.strip() or stdout.strip())}")
    requirements = {entry["treeId"]: entry for entry in manifest["runtimeTrees"]}
    for tree_id, requirement in requirements.items():
        with tempfile.TemporaryDirectory(prefix="mirrors-tree-verify-") as temporary:
            root = Path(temporary)
            if tree_id == "node-runtime":
                dependency = contract["dependencies"]["node-runtime"]
                selected = dependency["runtimeSelection"]
                extract_selected_node(artifacts[requirement["sourceArtifactId"]], root / "selected",
                    selected["rootPrefix"], selected["include"])
                actual_tree = runtime_tree(root / "selected")
            elif tree_id in {"java-runtime", "apalache-runtime"}:
                dependency_id = requirement["sourceArtifactId"]
                selected = contract["dependencies"][dependency_id]["runtimeSelection"]
                extract_selected_tree(artifacts[dependency_id], root / "selected",
                    selected["rootPrefix"], selected.get("include", []),
                    selected.get("includeTrees", []))
                actual_tree = runtime_tree(root / "selected")
            elif tree_id == "mirrorgate-runtime":
                safe_extract_regular(artifacts[requirement["sourceArtifactId"]], root / "extracted")
                actual_tree = runtime_tree(root / "extracted/gate")
            else:
                raise ContractError(f"unknown runtime tree: {tree_id}")
            for field in ("algorithm", "digest", "entryCount", "bytes"):
                if requirement[field] != actual_tree[field]:
                    raise ContractError(f"runtime tree identity mismatch: {tree_id}.{field}")
    return manifest, manifest_digest, contract


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cache", type=Path)
    parser.add_argument("--framework-catalog-bin", type=Path, required=True)
    parser.add_argument("--framework-catalog-sha256", required=True)
    args = parser.parse_args()
    try:
        manifest, digest, _contract = verify(args.cache.absolute(), args.framework_catalog_bin.absolute(),
            args.framework_catalog_sha256)
        print(f"REFERENCE DISTRIBUTION VERIFY GREEN profile={manifest['profileId']} manifestSha256={digest}")
        return 0
    except (ContractError, OSError, ValueError) as error:
        print(f"distribution verify failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
