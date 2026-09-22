#!/usr/bin/env python3
"""Stage, verify, atomically activate, and roll back a verified cache."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import shutil
import stat
import sys
import uuid
import re
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from distribution_lib import extract_selected_node, extract_selected_tree, runtime_tree, sha256_file, write_json
from manifest_check import ContractError, _read_bounded_regular, closed, load_json
from verify import safe_extract_regular, verify

DIGEST = re.compile(r"^[0-9a-f]{64}$")
MAX_CACHE_ENTRIES = 100_000
MAX_CACHE_FILE_BYTES = 512 * 1024 * 1024
MAX_CACHE_BYTES = 2 * 1024 * 1024 * 1024


def reject_symlink_chain(path: Path) -> None:
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        if current.exists() and stat.S_ISLNK(current.lstat().st_mode):
            raise ValueError(f"symlink path component is forbidden: {current}")


def filesystem_type(path: Path) -> str:
    resolved = path.resolve()
    best = (0, "")
    for line in Path("/proc/self/mountinfo").read_text().splitlines():
        before, separator, after = line.partition(" - ")
        if not separator: continue
        fields = before.split(); tail = after.split()
        if len(fields) < 5 or not tail: continue
        mount = Path(fields[4].replace("\\040", " "))
        try: resolved.relative_to(mount)
        except ValueError: continue
        if len(mount.parts) >= best[0]: best = (len(mount.parts), tail[0])
    return best[1]


def check_case_sensitive(prefix: Path) -> None:
    upper = prefix / f".CaseProbe.{uuid.uuid4().hex}"
    lower = prefix / upper.name.lower()
    first = os.open(upper, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(first)
    try:
        second = os.open(lower, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.close(second)
    except FileExistsError as error:
        raise ValueError("case-sensitive installation filesystem required") from error
    finally:
        upper.unlink(missing_ok=True); lower.unlink(missing_ok=True)


def fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try: os.fsync(descriptor)
    finally: os.close(descriptor)


def safe_directory(path: Path) -> None:
    if path.exists():
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise ValueError(f"real directory required: {path}")
        if metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) != 0o700:
            raise ValueError(f"directory must be current-user owned mode 0700: {path}")
    else:
        os.mkdir(path, 0o700)


def fsync_tree(root: Path) -> None:
    directories = [root]
    for path in root.rglob("*"):
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not (stat.S_ISDIR(metadata.st_mode) or stat.S_ISREG(metadata.st_mode)):
            raise ValueError(f"unsupported staged entry: {path}")
        if stat.S_ISDIR(metadata.st_mode): directories.append(path)
        else:
            descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
            try: os.fsync(descriptor)
            finally: os.close(descriptor)
    for directory in sorted(directories, key=lambda item: len(item.parts), reverse=True):
        fsync_directory(directory)


def copy_cache_tree(source: Path, destination: Path) -> None:
    """Copy an untrusted cache through pinned descriptors without following links."""
    source_fd = os.open(source, os.O_RDONLY | os.O_DIRECTORY |
        getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0))
    destination.mkdir(mode=0o700, exist_ok=False)
    destination_fd = os.open(destination, os.O_RDONLY | os.O_DIRECTORY |
        getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0))
    state = {"entries": 0, "bytes": 0}

    def copy_directory(source_directory: int, destination_directory: int,
        relative: str) -> None:
        entries = list(os.scandir(source_directory))
        names: set[str] = set()
        folded: set[str] = set()
        for entry in sorted(entries, key=lambda item: item.name.encode("utf-8")):
            name = entry.name
            logical = f"{relative}/{name}" if relative else name
            if (not name or name in {".", ".."} or "/" in name or "\0" in name or
                    len(logical.encode("utf-8")) > 1024 or name in names or
                    name.casefold() in folded):
                raise ValueError(f"invalid, duplicate, or case-colliding cache entry: {logical}")
            names.add(name); folded.add(name.casefold())
            state["entries"] += 1
            if state["entries"] > MAX_CACHE_ENTRIES:
                raise ValueError("cache entry count bound exceeded while copying")
            metadata = entry.stat(follow_symlinks=False)
            if stat.S_ISDIR(metadata.st_mode):
                child_source = os.open(name, os.O_RDONLY | os.O_DIRECTORY |
                    getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0),
                    dir_fd=source_directory)
                try:
                    opened = os.fstat(child_source)
                    if (opened.st_dev, opened.st_ino) != (metadata.st_dev, metadata.st_ino):
                        raise ValueError(f"cache directory changed while opening: {logical}")
                    os.mkdir(name, 0o700, dir_fd=destination_directory)
                    child_destination = os.open(name, os.O_RDONLY | os.O_DIRECTORY |
                        getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0),
                        dir_fd=destination_directory)
                    try:
                        copy_directory(child_source, child_destination, logical)
                        os.fsync(child_destination)
                    finally:
                        os.close(child_destination)
                finally:
                    os.close(child_source)
                continue
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
                raise ValueError(f"cache contains link or unsupported entry: {logical}")
            if metadata.st_size > MAX_CACHE_FILE_BYTES:
                raise ValueError(f"cache file byte bound exceeded: {logical}")
            state["bytes"] += metadata.st_size
            if state["bytes"] > MAX_CACHE_BYTES:
                raise ValueError("cache total byte bound exceeded while copying")
            input_descriptor = os.open(name, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) |
                getattr(os, "O_CLOEXEC", 0), dir_fd=source_directory)
            output_descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                getattr(os, "O_CLOEXEC", 0), 0o600, dir_fd=destination_directory)
            try:
                before = os.fstat(input_descriptor)
                if (not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or
                        (before.st_dev, before.st_ino, before.st_size) !=
                        (metadata.st_dev, metadata.st_ino, metadata.st_size)):
                    raise ValueError(f"cache file changed while opening: {logical}")
                written = 0
                while chunk := os.read(input_descriptor, min(1024 * 1024,
                        before.st_size - written + 1)):
                    written += len(chunk)
                    if written > before.st_size:
                        raise ValueError(f"cache file grew while copying: {logical}")
                    offset = 0
                    while offset < len(chunk):
                        offset += os.write(output_descriptor, chunk[offset:])
                after = os.fstat(input_descriptor)
                if (written != before.st_size or
                        (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns,
                            stat.S_IMODE(before.st_mode)) !=
                        (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns,
                            stat.S_IMODE(after.st_mode))):
                    raise ValueError(f"cache file changed while copying: {logical}")
                os.fchmod(output_descriptor, 0o755 if before.st_mode & stat.S_IXUSR else 0o644)
                os.fsync(output_descriptor)
            finally:
                os.close(output_descriptor)
                os.close(input_descriptor)

    try:
        copy_directory(source_fd, destination_fd, "")
        os.fsync(destination_fd)
    finally:
        os.close(destination_fd)
        os.close(source_fd)


def selector(prefix: Path) -> dict | None:
    path = prefix / "active.json"
    if not path.exists(): return None
    if not stat.S_ISREG(path.lstat().st_mode): raise ValueError("active.json must be a regular file")
    if path.stat().st_size > 65536: raise ValueError("active.json exceeds state bound")
    value = closed(load_json(path), {"manifestDigest", "versionDirectory"}, set(), "active.json")
    digest = value["manifestDigest"]
    if not isinstance(digest, str) or not DIGEST.fullmatch(digest) or value["versionDirectory"] != f"versions/{digest}":
        raise ValueError("active.json versionDirectory is not confined to its digest")
    return value


def load_journal(path: Path) -> dict:
    if path.stat().st_size > 65536: raise ValueError("transaction.json exceeds state bound")
    value = load_json(path)
    state = value.get("state")
    shapes = {
        "staging": {"state", "manifestDigest", "previous", "stage"},
        "staged": {"state", "manifestDigest", "previous", "stage"},
        "verified": {"state", "manifestDigest", "previous", "stage"},
        "abandoned-stage": {"state", "manifestDigest", "previous", "stage"},
        "activating": {"state", "manifestDigest", "previous", "version"},
        "committed": {"state", "manifestDigest", "previous", "version"},
        "rolled-back": {"state", "manifestDigest", "previous", "version"},
    }
    if state not in shapes: raise ValueError(f"unknown transaction state: {state}")
    value = closed(value, shapes[state], set(), "transaction.json")
    if not isinstance(value["manifestDigest"], str) or not DIGEST.fullmatch(value["manifestDigest"]):
        raise ValueError("transaction manifestDigest is invalid")
    previous = value["previous"]
    if previous is not None:
        if not isinstance(previous, dict) or set(previous) != {"manifestDigest", "versionDirectory"}:
            raise ValueError("transaction previous selector is invalid")
        digest = previous["manifestDigest"]
        if not isinstance(digest, str) or not DIGEST.fullmatch(digest) or previous["versionDirectory"] != f"versions/{digest}":
            raise ValueError("transaction previous selector is not confined")
    relative = value.get("stage") or value.get("version")
    if not isinstance(relative, str) or Path(relative).is_absolute() or ".." in Path(relative).parts:
        raise ValueError("transaction resource path is invalid")
    expected_prefix = ".staging/" if "stage" in value else "versions/"
    if not relative.startswith(expected_prefix): raise ValueError("transaction resource path is not confined")
    return value


def extract_prefix(archive: Path, destination: Path, expected_prefix: str) -> None:
    with tempfile.TemporaryDirectory(prefix="mirrors-materialize-") as temporary:
        root = Path(temporary) / "extract"
        safe_extract_regular(archive, root)
        source = root / expected_prefix
        if not source.is_dir() or source.is_symlink():
            raise ValueError(f"archive prefix is missing: {expected_prefix}")
        shutil.copytree(source, destination)


def materialize(cache: Path, runtime: Path, manifest: dict, contract: dict) -> dict:
    runtime.mkdir(mode=0o700)
    artifacts = {entry["artifactId"]: cache / entry["path"] for entry in manifest["artifacts"]}
    binaries = runtime / "bin"; binaries.mkdir()
    for artifact_id, name in [("mirror-server", "ModelMirrors"),
        ("model-interface-gen", "model_interface_gen"),
        ("framework-catalog-verifier", "framework_catalog")]:
        shutil.copyfile(artifacts[artifact_id], binaries / name)
        (binaries / name).chmod(0o755)
    node = runtime / "runtimes/node"
    selection = contract["dependencies"]["node-runtime"]["runtimeSelection"]
    extract_selected_node(artifacts["node-runtime"], node, selection["rootPrefix"], selection["include"])
    packages = runtime / "packages"; packages.mkdir()
    extract_prefix(artifacts["mirrorecma-package"], packages / "mirrorecma", "package")
    node_modules = runtime / "node_modules"; node_modules.mkdir()
    shutil.copytree(packages / "mirrorecma", node_modules / "mirrorecma")
    examples = runtime / "examples"; examples.mkdir()
    extract_prefix(artifacts["counter-suite-bundle"], examples / "counter-suite", "counter-suite")
    shutil.copyfile(artifacts["counter-corpus"], examples / "counter.itf.json")
    shutil.copyfile(artifacts["counter-model"], examples / "Counter.tla")
    extract_prefix(artifacts["application-validation-fixtures"], runtime / "applications",
        "application-validation")
    # The compiled validation fixtures retain their source-package relative import
    # (../../dist/index.js). Materialize that exact package view instead of allowing
    # Node resolution to fall back to a checkout or a global installation.
    shutil.copytree(packages / "mirrorecma" / "dist", runtime / "applications/dist")
    verification = runtime / "verification"; verification.mkdir()
    extract_prefix(artifacts["evidence-verifier"], verification / "bundle", "verification")
    extract_prefix(artifacts["evidence-verifier-dependencies"], verification / "wheels", "wheels")
    inputs = runtime / "inputs"; inputs.mkdir()
    shutil.copyfile(artifacts["selected-catalog"], inputs / "framework-catalog.A.json")
    extract_prefix(artifacts["distribution-locks"], inputs / "distribution-locks", "distribution-locks")
    if manifest["profileId"] == "checked-replay-gate":
        extract_prefix(artifacts["mirrorgate-runtime"], runtime / "gate", "gate")
        gate_package = runtime / "gate/mirrorgate-runtime"
        public_gate_package = node_modules / "mirrorgate"
        public_gate_package.mkdir()
        shutil.copyfile(gate_package / "package.json", public_gate_package / "package.json")
        shutil.copytree(gate_package / "sdk", public_gate_package / "sdk")
        if (gate_package / "integrations").is_dir():
            shutil.copytree(gate_package / "integrations", public_gate_package / "integrations")
        extract_prefix(artifacts["mirrorgate-integration"], packages / "mirrorgate-mirrorecma", "package")
        shutil.copytree(packages / "mirrorgate-mirrorecma",
            node_modules / "mirrorgate-mirrorecma")
    if manifest["profileId"] == "fresh-trace":
        for dependency_id, destination in [("java-runtime", runtime / "runtimes/java"),
            ("apalache", runtime / "tools/apalache")]:
            selected = contract["dependencies"][dependency_id]["runtimeSelection"]
            extract_selected_tree(artifacts[dependency_id], destination,
                selected["rootPrefix"], selected.get("include", []),
                selected.get("includeTrees", []))
    profile = contract["profiles"][manifest["profileId"]]
    catalog_profile = next(item for item in contract["catalog"]["distributionProfiles"]
        if item["profileId"] == profile["catalogProfileId"])
    artifact_identities = {entry["artifactId"]: entry for entry in manifest["artifacts"]}
    admitted_trees = {entry["inputId"]: {key: entry[key]
        for key in ("algorithm", "digest", "entryCount", "bytes")}
        for entry in manifest["buildProvenance"]["trees"]}
    packages_observed = [{"packageId": "mirrorecma", "componentId": "mirrorecma",
        "artifactId": "mirrorecma-package", "version": "2.0.0",
        "sha256": artifact_identities["mirrorecma-package"]["sha256"]}]
    package_policy = [{"packageId": "mirrorecma", "componentId": "mirrorecma",
        "artifactId": "mirrorecma-package"}]
    if "mirrorgate-integration" in artifact_identities:
        packages_observed.append({"packageId": "mirrorgate-mirrorecma",
            "componentId": "mirrorgate", "artifactId": "mirrorgate-integration",
            "version": "0.1.0", "sha256": artifact_identities["mirrorgate-integration"]["sha256"]})
        package_policy.append({"packageId": "mirrorgate-mirrorecma",
            "componentId": "mirrorgate", "artifactId": "mirrorgate-integration"})
    executable_policy = [
        {"role": "mirror-server", "artifactId": "mirror-server", "requiredCapabilityIds": []},
        {"role": "model-interface-gen", "artifactId": "model-interface-gen",
            "requiredCapabilityIds": ["mirrors.compiler.target.mirrorecma-async-v1"]},
        {"role": "framework-catalog", "artifactId": "framework-catalog-verifier",
            "requiredCapabilityIds": []},
    ]
    executable_observed = [{"role": entry["role"], "artifactId": entry["artifactId"],
        "sha256": artifact_identities[entry["artifactId"]]["sha256"],
        "capabilityIds": entry["requiredCapabilityIds"]} for entry in executable_policy]
    tree_capabilities = {"mirrorgate-runtime": ["mirrorgate.runtime.node-v1"]}
    runtime_policy = [{"runtimeId": entry["treeId"], "treeId": entry["treeId"],
        "requiredCapabilityIds": tree_capabilities.get(entry["treeId"], [])}
        for entry in manifest["runtimeTrees"]]
    executable_installation = []
    for entry in executable_policy:
        name = {"mirror-server": "ModelMirrors", "model-interface-gen": "model_interface_gen",
            "framework-catalog-verifier": "framework_catalog"}[entry["artifactId"]]
        relative = f"bin/{name}"
        _size, installed_digest = sha256_file(runtime / relative)
        executable_installation.append({"role": entry["role"],
            "artifactId": entry["artifactId"], "path": relative,
            "sha256": installed_digest})
    package_installation = []
    for observed in packages_observed:
        relative_root = ("packages/mirrorecma" if observed["packageId"] == "mirrorecma"
            else "packages/mirrorgate-mirrorecma")
        manifest_relative = f"{relative_root}/package.json"
        package_manifest = load_json(runtime / manifest_relative)
        version = package_manifest.get("version") if isinstance(package_manifest, dict) else None
        if not isinstance(version, str) or not version:
            raise ValueError(f"installed package version missing: {observed['packageId']}")
        _size, manifest_digest = sha256_file(runtime / manifest_relative)
        package_tree = runtime_tree(runtime / relative_root)
        expected_tree = admitted_trees.get(f"package:{observed['packageId']}")
        if package_tree != expected_tree:
            raise ValueError(f"installed package tree differs from admitted build identity: {observed['packageId']}")
        package_installation.append({"packageId": observed["packageId"],
            "componentId": observed["componentId"], "artifactId": observed["artifactId"],
            "sourceSha256": artifact_identities[observed["artifactId"]]["sha256"],
            "root": relative_root, "tree": package_tree,
            "manifest": {"path": manifest_relative, "sha256": manifest_digest,
                "version": version}})
    runtime_roots = {"node-runtime": "runtimes/node",
        "mirrorgate-runtime": "gate", "java-runtime": "runtimes/java"}
    runtime_installation = []
    runtime_policy_by_tree = {entry["treeId"]: entry for entry in runtime_policy}
    for entry in manifest["runtimeTrees"]:
        tree_id = entry["treeId"]
        relative_root = runtime_roots.get(tree_id)
        if relative_root is None:
            raise ValueError(f"materialized runtime binding is unknown: {tree_id}")
        source_artifact_id = entry["sourceArtifactId"]
        policy_entry = runtime_policy_by_tree.get(tree_id)
        if policy_entry is None:
            raise ValueError(f"materialized runtime lacks an observed policy binding: {tree_id}")
        runtime_installation.append({"runtimeId": policy_entry["runtimeId"], "treeId": tree_id,
            "root": relative_root, "sourceArtifactId": source_artifact_id,
            "sourceSha256": artifact_identities[source_artifact_id]["sha256"],
            "materializedTree": runtime_tree(runtime / relative_root)})
    installation = {"schema": "mirrorecma.installed-framework-binding/v1",
        "executables": executable_installation, "packages": package_installation,
        "runtimeTrees": runtime_installation}
    framework_input = {"catalogRaw": _read_bounded_regular(
            artifacts["selected-catalog"]).decode("utf-8"),
        "selectionRef": manifest["catalogSelectionRef"],
        "observed": {"distributionManifestRaw": _read_bounded_regular(
                cache / "distribution-manifest.json").decode("utf-8"),
            "cacheIndexRaw": _read_bounded_regular(
                cache / "cache-index.json").decode("utf-8"),
            "componentRefs": manifest["componentRefs"], "packages": packages_observed,
            "executables": executable_observed, "runtimeTrees": manifest["runtimeTrees"],
            "platform": catalog_profile["platform"],
            "policy": {"admission": "qualification-candidate",
                "manifestProfileId": manifest["profileId"],
                "catalogProfileId": profile["catalogProfileId"], "packages": package_policy,
                "executables": executable_policy, "runtimeTrees": runtime_policy}},
        "installation": installation}
    write_json(runtime / "framework-input.json", framework_input)
    application_validation_tree = runtime_tree(runtime / "applications")
    if application_validation_tree != admitted_trees.get("application:validation"):
        raise ValueError("installed application-validation tree differs from admitted build identity")
    write_json(runtime / "installed-registry.json", {
        "schemaVersion": "mirrors.installed-registry/v1",
        "profileId": manifest["profileId"], "catalogSelectionRef": manifest["catalogSelectionRef"],
        "combinationId": profile["combinationId"],
        "frameworkInput": "framework-input.json",
        "node": "runtimes/node/bin/node", "mirrorecmaCli": "packages/mirrorecma/dist/cli.js",
        "mirrorServer": "bin/ModelMirrors", "frameworkCatalog": "bin/framework_catalog",
        "modelInterfaceGen": "bin/model_interface_gen",
        "applicationValidationRoot": "applications",
        "applicationValidation": {
            "root": "applications",
            "sourceArtifactId": "application-validation-fixtures",
            "sourceSha256": artifact_identities["application-validation-fixtures"]["sha256"],
            "materializedTree": application_validation_tree,
        },
        "installation": installation,
        "gate": ({"integration": "packages/mirrorgate-mirrorecma/dist/index.js",
            "applicationRunner": "packages/mirrorgate-mirrorecma/scripts/application-program-gate.mjs",
            "aggregateRunner": "packages/mirrorgate-mirrorecma/scripts/application-program-gate-all.mjs",
            "runtime": "gate/mirrorgate-runtime/runtimes/node/worker.mjs",
            "nodeShimRoot": "gate/mirrorgate-runtime",
            "sdk": "gate/mirrorgate-runtime/sdk/node",
            "protocol": "gate/protocol",
            "supervisor": "gate/mirrorgate-supervisor",
            "python": str(Path(sys.executable).resolve())}
            if manifest["profileId"] == "checked-replay-gate" else None),
        "artifactIdentities": {artifact_id: {"sha256": entry["sha256"], "bytes": entry["bytes"]}
            for artifact_id, entry in artifact_identities.items()},
    })
    identity = runtime_tree(runtime)
    write_json(runtime.parent / "materialization.json", {"schemaVersion": "mirrors.materialized-install/v1",
        "manifestDigest": __import__("manifest_check").digest_json(manifest), **identity})
    return identity


def verify_installation(version: Path, framework_catalog_bin: Path,
    framework_catalog_sha256: str) -> tuple[dict, str]:
    manifest, digest, _contract = verify(version / "cache", framework_catalog_bin,
        framework_catalog_sha256, allow_pinned_fd=str(version).startswith("/proc/self/fd/"))
    index = closed(load_json(version / "materialization.json"),
        {"schemaVersion", "manifestDigest", "algorithm", "digest", "entryCount", "bytes"},
        set(), "materialization.json")
    if index["schemaVersion"] != "mirrors.materialized-install/v1" or index["manifestDigest"] != digest:
        raise ValueError("materialization manifest identity mismatch")
    if (index["algorithm"] != "mirrors-runtime-tree-v1" or not DIGEST.fullmatch(index["digest"]) or
            type(index["entryCount"]) is not int or index["entryCount"] < 1 or
            type(index["bytes"]) is not int or index["bytes"] < 1):
        raise ValueError("materialization tree identity is malformed")
    actual = runtime_tree(version / "runtime")
    if any(index[field] != actual[field] for field in ("algorithm", "digest", "entryCount", "bytes")):
        raise ValueError("materialized runtime tree identity mismatch")
    runtime = version / "runtime"
    artifacts = {entry["artifactId"]: entry for entry in manifest["artifacts"]}
    admitted_trees = {entry["inputId"]: {key: entry[key]
        for key in ("algorithm", "digest", "entryCount", "bytes")}
        for entry in manifest["buildProvenance"]["trees"]}
    for package_id, relative in (("mirrorecma", "packages/mirrorecma"),
            ("mirrorgate-mirrorecma", "packages/mirrorgate-mirrorecma")):
        expected = admitted_trees.get(f"package:{package_id}")
        path = runtime / relative
        if expected is None:
            if path.exists():
                raise ValueError(f"unexpected installed package tree: {package_id}")
            continue
        if runtime_tree(path) != expected:
            raise ValueError(f"installed package tree differs from admitted build identity: {package_id}")
    if runtime_tree(runtime / "applications") != admitted_trees.get("application:validation"):
        raise ValueError("installed application-validation tree differs from admitted build identity")
    binary_paths = {"mirror-server": "bin/ModelMirrors",
        "model-interface-gen": "bin/model_interface_gen",
        "framework-catalog-verifier": "bin/framework_catalog"}
    for artifact_id, relative in binary_paths.items():
        size, installed_digest = sha256_file(runtime / relative)
        expected = artifacts[artifact_id]
        if size != expected["bytes"] or installed_digest != expected["sha256"]:
            raise ValueError(f"installed executable differs from admitted artifact: {artifact_id}")
    runtime_roots = {"node-runtime": "runtimes/node",
        "mirrorgate-runtime": "gate", "java-runtime": "runtimes/java",
        "apalache-runtime": "tools/apalache"}
    for expected in manifest["runtimeTrees"]:
        relative = runtime_roots.get(expected["treeId"])
        if relative is None:
            raise ValueError(f"installed runtime tree is unknown: {expected['treeId']}")
        observed = runtime_tree(runtime / relative)
        if any(observed[field] != expected[field]
                for field in ("algorithm", "digest", "entryCount", "bytes")):
            raise ValueError(f"installed runtime tree differs from admitted identity: {expected['treeId']}")
    return manifest, digest


def recover_internal_state(prefix: Path, versions: Path, staging: Path,
    framework_catalog_bin: Path, framework_catalog_sha256: str) -> None:
    for path in prefix.glob(".active.*.tmp"):
        if not stat.S_ISREG(path.lstat().st_mode):
            raise ValueError(f"ambiguous active-selector temporary: {path.name}")
        path.unlink()
    journal_path = prefix / "transaction.json"
    if not journal_path.exists():
        return
    if not stat.S_ISREG(journal_path.lstat().st_mode):
        raise ValueError("transaction.json must be a regular file")
    journal = load_journal(journal_path)
    state = journal.get("state")
    if state in {"staging", "staged", "verified"}:
        relative = journal.get("stage")
        if not isinstance(relative, str) or not relative.startswith(".staging/") or ".." in Path(relative).parts:
            raise ValueError("ambiguous staged transaction path")
        stage = staging / Path(relative).name
        if stage.exists():
            if not stat.S_ISDIR(stage.lstat().st_mode):
                raise ValueError("staged transaction resource is not a directory")
            abandoned = stage.with_name(stage.name + ".abandoned")
            if abandoned.exists():
                raise ValueError("ambiguous abandoned stage already exists")
            os.replace(stage, abandoned)
        write_json(journal_path, {**journal, "state": "abandoned-stage"})
    elif state == "activating":
        active = selector(prefix)
        digest = journal.get("manifestDigest")
        if active and active.get("manifestDigest") == digest:
            try:
                verify_installation(versions / active["manifestDigest"], framework_catalog_bin,
                    framework_catalog_sha256)
                write_json(journal_path, {**journal, "state": "committed"})
            except Exception:
                previous = journal.get("previous")
                if previous is None:
                    (prefix / "active.json").unlink(missing_ok=True)
                else:
                    verify_installation(versions / previous["manifestDigest"], framework_catalog_bin,
                        framework_catalog_sha256)
                    activate_selector(prefix, previous)
                write_json(journal_path, {**journal, "state": "rolled-back"})
                raise
        elif active == journal.get("previous"):
            if active is not None:
                verify_installation(versions / active["manifestDigest"], framework_catalog_bin,
                    framework_catalog_sha256)
            write_json(journal_path, {**journal, "state": "rolled-back"})
        else:
            raise ValueError("ambiguous activating transaction")
    elif state not in {"abandoned-stage", "committed", "rolled-back"}:
        raise ValueError(f"unknown transaction state: {state}")


def activate_selector(prefix: Path, value: dict) -> None:
    temporary = prefix / f".active.{uuid.uuid4().hex}.tmp"
    write_json(temporary, value)
    os.replace(temporary, prefix / "active.json")
    fsync_directory(prefix)


def _populate_and_activate(cache: Path, prefix: Path, versions: Path, stage: Path,
    stage_name: str, stage_fd: int, staging_fd: int, versions_fd: int,
    manifest: dict, contract: dict, digest: str, previous: dict | None,
    framework_catalog_bin: Path, framework_catalog_sha256: str,
    fail_at: str | None) -> tuple[str, str]:
    write_json(prefix / "transaction.json", {"state": "staging", "manifestDigest": digest,
        "previous": previous, "stage": f".staging/{stage_name}"})
    copy_cache_tree(cache, stage / "cache")
    if fail_at == "after-copy": raise RuntimeError("injected after copy")
    copied_manifest, copied_digest, copied_contract = verify(stage / "cache",
        framework_catalog_bin, framework_catalog_sha256, allow_pinned_fd=True)
    if copied_digest != digest or copied_manifest != manifest:
        raise ValueError("cache identity changed between admission and staged copy")
    materialize(stage / "cache", stage / "runtime", copied_manifest, copied_contract)
    if fail_at == "after-materialize": raise RuntimeError("injected after materialization")
    fsync_tree(stage)
    write_json(prefix / "transaction.json", {"state": "staged", "manifestDigest": digest,
        "previous": previous, "stage": f".staging/{stage_name}"})
    verify_installation(stage, framework_catalog_bin, framework_catalog_sha256)
    write_json(prefix / "transaction.json", {"state": "verified", "manifestDigest": digest,
        "previous": previous, "stage": f".staging/{stage_name}"})
    if fail_at == "before-activate": raise RuntimeError("injected before activation")
    if fail_at == "after-verify": raise RuntimeError("injected after verification")
    destination = versions / digest
    if destination.exists():
        verify_installation(destination, framework_catalog_bin, framework_catalog_sha256)
        shutil.rmtree(stage)
    else:
        if os.fstat(stage_fd).st_dev != os.fstat(versions_fd).st_dev:
            raise ValueError("stage and versions are not on the same filesystem")
        os.rename(stage_name, digest, src_dir_fd=staging_fd, dst_dir_fd=versions_fd)
        fsync_directory(versions)
    if fail_at == "after-version-rename": raise RuntimeError("injected after version rename")
    write_json(prefix / "transaction.json", {"state": "activating", "manifestDigest": digest,
        "previous": previous, "version": f"versions/{digest}"})
    try:
        activate_selector(prefix, {"manifestDigest": digest,
            "versionDirectory": f"versions/{digest}"})
        if fail_at in {"after-activate", "after-selector"}: raise RuntimeError("injected after activation")
        verify_installation(destination, framework_catalog_bin, framework_catalog_sha256)
        write_json(prefix / "transaction.json", {"state": "committed", "manifestDigest": digest,
            "previous": previous, "version": f"versions/{digest}"})
        return "committed", digest
    except Exception:
        if previous is None:
            active = prefix / "active.json"
            if active.exists(): active.unlink()
        else:
            verify_installation(versions / previous["manifestDigest"], framework_catalog_bin,
                framework_catalog_sha256)
            activate_selector(prefix, previous)
        write_json(prefix / "transaction.json", {"state": "rolled-back", "manifestDigest": digest,
            "previous": previous, "version": f"versions/{digest}"})
        raise


def _install_locked(cache: Path, prefix: Path, versions: Path, staging: Path,
    versions_fd: int, staging_fd: int, framework_catalog_bin: Path,
    framework_catalog_sha256: str, fail_at: str | None) -> tuple[str, str]:
    manifest, digest, contract = verify(cache, framework_catalog_bin, framework_catalog_sha256)
    recover_internal_state(prefix, versions, staging, framework_catalog_bin,
        framework_catalog_sha256)
    previous = selector(prefix)
    if previous and previous["manifestDigest"] == digest:
        verify_installation(versions / previous["manifestDigest"], framework_catalog_bin,
            framework_catalog_sha256)
        return "idempotent", digest
    stage_name = f"{digest}.{uuid.uuid4().hex}"
    os.mkdir(stage_name, 0o700, dir_fd=staging_fd)
    stage_fd = os.open(stage_name, os.O_RDONLY | os.O_DIRECTORY |
        getattr(os, "O_NOFOLLOW", 0), dir_fd=staging_fd)
    stage = Path(f"/proc/self/fd/{stage_fd}")
    try:
        return _populate_and_activate(cache, prefix, versions, stage, stage_name,
            stage_fd, staging_fd, versions_fd, manifest, contract, digest, previous,
            framework_catalog_bin, framework_catalog_sha256, fail_at)
    finally:
        os.close(stage_fd)


def install(cache: Path, prefix: Path, framework_catalog_bin: Path,
    framework_catalog_sha256: str, fail_at: str | None) -> tuple[str, str]:
    prefix = prefix.absolute()
    reject_symlink_chain(prefix.parent)
    if prefix.exists():
        metadata = prefix.lstat()
        if (not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode) or
                metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) != 0o700):
            raise ValueError("existing prefix must be a current-user-owned real directory mode 0700")
    else:
        prefix.mkdir(mode=0o700, parents=True)
    reject_symlink_chain(prefix)
    if filesystem_type(prefix) != "ext4":
        raise ValueError(f"version 1 requires ext4 installation filesystem, got {filesystem_type(prefix)!r}")
    prefix_fd = os.open(prefix, os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0))
    pinned_prefix = Path(f"/proc/self/fd/{prefix_fd}")
    lock_descriptor = os.open(".install.lock", os.O_RDWR | os.O_CREAT |
        getattr(os, "O_NOFOLLOW", 0), 0o600, dir_fd=prefix_fd)
    lock_metadata = os.fstat(lock_descriptor)
    if not stat.S_ISREG(lock_metadata.st_mode) or lock_metadata.st_uid != os.getuid():
        os.close(lock_descriptor); os.close(prefix_fd)
        raise ValueError("installation lock ownership/type is invalid")
    try:
        fcntl.flock(lock_descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        os.close(lock_descriptor); os.close(prefix_fd)
        raise ValueError("installation prefix is locked") from error
    try:
        allowed = {"versions", ".staging", ".install.lock", "active.json", "transaction.json"}
        unknown = sorted(path.name for path in pinned_prefix.iterdir()
            if path.name not in allowed)
        if unknown: raise ValueError(f"unknown installation entry: {unknown[0]}")
        check_case_sensitive(pinned_prefix)
        versions = pinned_prefix / "versions"; staging = pinned_prefix / ".staging"
        safe_directory(versions); safe_directory(staging)
        versions_fd = os.open("versions", os.O_RDONLY | os.O_DIRECTORY |
            getattr(os, "O_NOFOLLOW", 0), dir_fd=prefix_fd)
        staging_fd = os.open(".staging", os.O_RDONLY | os.O_DIRECTORY |
            getattr(os, "O_NOFOLLOW", 0), dir_fd=prefix_fd)
        current = prefix.lstat()
        pinned = os.fstat(prefix_fd)
        if (current.st_dev, current.st_ino) != (pinned.st_dev, pinned.st_ino):
            raise ValueError("installation prefix changed during admission")
        try:
            return _install_locked(cache, pinned_prefix,
                Path(f"/proc/self/fd/{versions_fd}"), Path(f"/proc/self/fd/{staging_fd}"),
                versions_fd, staging_fd, framework_catalog_bin, framework_catalog_sha256, fail_at)
        finally:
            os.close(versions_fd); os.close(staging_fd)
    finally:
        os.close(prefix_fd)
        fcntl.flock(lock_descriptor, fcntl.LOCK_UN)
        os.close(lock_descriptor)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--prefix", type=Path, required=True)
    parser.add_argument("--framework-catalog-bin", type=Path, required=True)
    parser.add_argument("--framework-catalog-sha256", required=True)
    parser.add_argument("--fail-at", choices=["after-copy", "after-materialize", "after-verify",
        "before-activate", "after-version-rename", "after-selector", "after-activate"])
    args = parser.parse_args()
    try:
        state, digest = install(args.cache.absolute(), args.prefix, args.framework_catalog_bin.absolute(),
            args.framework_catalog_sha256, args.fail_at)
        print(f"REFERENCE DISTRIBUTION INSTALL GREEN state={state} manifestSha256={digest}")
        return 0
    except Exception as error:
        print(f"distribution install failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
