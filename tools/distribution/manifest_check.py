#!/usr/bin/env python3
"""Strict offline checker for the reference distribution locks and cache indexes."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import resource
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

MAX_JSON_BYTES = 4 * 1024 * 1024
MAX_DEPTH = 32
SAFE_INTEGER = 9_007_199_254_740_991
SHA256 = re.compile(r"^[0-9a-f]{64}$")
REVISION = re.compile(r"^[0-9a-f]{40}$")
ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/+-]{0,255}$")
FORBIDDEN_PAYLOAD_WORDS = {
    "credential", "credentials", "private-key", "private-model", "private-trace",
    "operator-policy", "secret", "secrets", "trust-store",
}


class ContractError(ValueError):
    pass


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ContractError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _depth(value: Any, depth: int = 0) -> int:
    if depth > MAX_DEPTH:
        raise ContractError(f"JSON nesting exceeds {MAX_DEPTH}")
    if isinstance(value, dict):
        for child in value.values():
            _depth(child, depth + 1)
    elif isinstance(value, list):
        for child in value:
            _depth(child, depth + 1)
    elif isinstance(value, int) and not isinstance(value, bool):
        if not -SAFE_INTEGER <= value <= SAFE_INTEGER:
            raise ContractError("integer exceeds signed safe range")
    elif isinstance(value, float):
        raise ContractError("floating-point JSON numbers are forbidden")
    return depth


def _read_bounded_regular(path: Path) -> bytes:
    try:
        before = path.lstat()
    except OSError as error:
        raise ContractError(f"{path}: cannot stat: {error}") from error
    if not stat.S_ISREG(before.st_mode):
        raise ContractError(f"{path}: regular file required")
    if before.st_size > MAX_JSON_BYTES:
        raise ContractError(f"{path}: exceeds {MAX_JSON_BYTES}-byte limit")
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise ContractError(f"{path}: cannot open safely: {error}") from error
    try:
        opened = os.fstat(descriptor)
        if not stat.S_ISREG(opened.st_mode):
            raise ContractError(f"{path}: regular file required")
        chunks: list[bytes] = []
        total = 0
        while total <= MAX_JSON_BYTES:
            chunk = os.read(descriptor, min(65536, MAX_JSON_BYTES + 1 - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
        raw = b"".join(chunks)
        closed = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    after = path.lstat()
    identity = lambda value: (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns, value.st_mode)
    if identity(before) != identity(opened) or identity(opened) != identity(closed) or identity(closed) != identity(after):
        raise ContractError(f"{path}: changed while reading")
    if len(raw) > MAX_JSON_BYTES:
        raise ContractError(f"{path}: exceeds {MAX_JSON_BYTES}-byte limit")
    return raw


def _decode_json(path: Path, raw: bytes) -> dict[str, Any]:
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError) as error:
        raise ContractError(f"{path}: invalid JSON: {error}") from error
    if not isinstance(value, dict):
        raise ContractError(f"{path}: root object required")
    _depth(value)
    return value


def load_json(path: Path) -> dict[str, Any]:
    return _decode_json(path, _read_bounded_regular(path))


def _quote(value: str) -> str:
    output = ['"']
    for character in value:
        number = ord(character)
        if character == '"':
            output.append('\\"')
        elif character == "\\":
            output.append("\\\\")
        elif number < 0x20:
            output.append(f"\\u{number:04x}")
        else:
            output.append(character)
    output.append('"')
    return "".join(output)


def canonical_json(value: Any) -> bytes:
    if value is None:
        return b"null"
    if value is True:
        return b"true"
    if value is False:
        return b"false"
    if isinstance(value, int):
        if not -SAFE_INTEGER <= value <= SAFE_INTEGER:
            raise ContractError("integer exceeds signed safe range")
        return str(value).encode("ascii")
    if isinstance(value, str):
        return _quote(value).encode("utf-8")
    if isinstance(value, list):
        return b"[" + b",".join(canonical_json(item) for item in value) + b"]"
    if isinstance(value, dict):
        fields = sorted(value.items(), key=lambda field: field[0].encode("utf-8"))
        return b"{" + b",".join(
            _quote(key).encode("utf-8") + b":" + canonical_json(item)
            for key, item in fields
        ) + b"}"
    raise ContractError(f"unsupported JSON value: {type(value).__name__}")


def digest_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value)).hexdigest()


def closed(value: Any, required: set[str], optional: set[str], path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ContractError(f"{path}: object required")
    unknown = sorted(set(value) - required - optional)
    missing = sorted(required - set(value))
    if unknown:
        raise ContractError(f"{path}: unknown field: {unknown[0]}")
    if missing:
        raise ContractError(f"{path}: missing field: {missing[0]}")
    return value


def identifier(value: Any, path: str) -> str:
    if not isinstance(value, str) or not ID.fullmatch(value):
        raise ContractError(f"{path}: invalid identifier")
    return value


def logical_path(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value or len(value.encode()) > 1024:
        raise ContractError(f"{path}: invalid logical path")
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        raise ContractError(f"{path}: logical path contains a control character")
    if value.startswith("/") or "\\" in value or "//" in value or re.match(r"^[A-Za-z]:", value):
        raise ContractError(f"{path}: logical path must be relative")
    if any(part in {"", ".", ".."} for part in value.split("/")):
        raise ContractError(f"{path}: logical path contains traversal")
    return value


def exact_list(values: Any, path: str, limit: int = 2048) -> list[Any]:
    if not isinstance(values, list) or len(values) > limit:
        raise ContractError(f"{path}: bounded array required")
    return values


def string_list(values: Any, path: str, limit: int = 2048) -> list[str]:
    result = exact_list(values, path, limit)
    for index, value in enumerate(result):
        if not isinstance(value, str) or not value:
            raise ContractError(f"{path}[{index}]: nonempty string required")
    if len(result) != len(set(result)):
        raise ContractError(f"{path}: values must be unique")
    return result


def unique_ids(values: list[dict[str, Any]], field: str, path: str) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for index, value in enumerate(values):
        key = identifier(value.get(field), f"{path}[{index}].{field}")
        if key in result:
            raise ContractError(f"{path}[{index}].{field}: duplicate {key}")
        result[key] = value
    return result


def component_identity(value: dict[str, Any]) -> tuple[Any, ...]:
    dirty = value.get("dirtyContent")
    dirty_identity = None if dirty is None else (
        dirty.get("algorithm"), dirty.get("digest"), dirty.get("method"),
        tuple(dirty.get("includedPaths", [])),
        tuple((entry.get("path"), entry.get("reasonCode")) for entry in dirty.get("excludedPaths", [])),
    )
    return value.get("componentId"), value.get("repository"), value.get("revision"), value.get("dirty"), dirty_identity


def copy_trusted_executable(path: Path, destination: Path, expected_sha256: str | None) -> str:
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or stat.S_ISLNK(before.st_mode):
        raise ContractError(f"trusted executable must be a regular file: {path}")
    source = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0))
    target = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0), 0o700)
    digest = hashlib.sha256()
    try:
        opened = os.fstat(source)
        while chunk := os.read(source, 1024 * 1024):
            digest.update(chunk)
            offset = 0
            while offset < len(chunk): offset += os.write(target, chunk[offset:])
        closed = os.fstat(source)
        os.fsync(target)
    finally:
        os.close(source); os.close(target)
    after = path.lstat()
    identity = lambda value: (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns, value.st_mode)
    if identity(before) != identity(opened) or identity(opened) != identity(closed) or identity(closed) != identity(after):
        raise ContractError("trusted framework_catalog changed while copying")
    actual = digest.hexdigest()
    if expected_sha256 is not None and actual != expected_sha256:
        raise ContractError("trusted framework_catalog executable hash mismatch")
    return actual


def _output_limit() -> None:
    resource.setrlimit(resource.RLIMIT_FSIZE, (1024 * 1024, 1024 * 1024))


def run_trusted_catalog_validation(path: Path, expected_sha256: str | None,
    catalog_path: Path) -> tuple[int, str, str]:
    with tempfile.TemporaryDirectory(prefix="mirrors-trusted-catalog-") as temporary:
        root = Path(temporary)
        executable = root / "framework_catalog"
        copy_trusted_executable(path, executable, expected_sha256)
        catalog_snapshot = root / "catalog.json"
        catalog_bytes = _read_bounded_regular(catalog_path)
        descriptor = os.open(catalog_snapshot, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            offset = 0
            while offset < len(catalog_bytes):
                offset += os.write(descriptor, catalog_bytes[offset:])
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        stdout_path = root / "stdout"; stderr_path = root / "stderr"
        with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
            try:
                result = subprocess.run([str(executable), "validate", str(catalog_snapshot)],
                    stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr, check=False,
                    timeout=30, preexec_fn=_output_limit)
            except subprocess.TimeoutExpired as error:
                raise ContractError("trusted framework_catalog validation timed out") from error
        if stdout_path.stat().st_size > 1024 * 1024 or stderr_path.stat().st_size > 1024 * 1024:
            raise ContractError("trusted framework_catalog output exceeded 1 MiB")
        return result.returncode, stdout_path.read_text(errors="replace"), stderr_path.read_text(errors="replace")


def profile_resolution(profile_id: str, profiles: dict[str, dict[str, Any]], stack: tuple[str, ...] = ()) -> tuple[set[str], dict[str, dict[str, Any]], set[str]]:
    if profile_id in stack:
        raise ContractError(f"profile inheritance cycle: {' -> '.join(stack + (profile_id,))}")
    profile = profiles.get(profile_id)
    if profile is None:
        raise ContractError(f"unknown profile: {profile_id}")
    artifacts = set(profile["requiredArtifacts"])
    prerequisites = {entry["id"]: entry for entry in profile["operatorPrerequisites"]}
    ancestors: set[str] = set()
    for parent in profile["extends"]:
        inherited, inherited_prerequisites, parent_ids = profile_resolution(parent, profiles, stack + (profile_id,))
        artifacts |= inherited
        ancestors |= parent_ids | {parent}
        for prerequisite_id, requirement in inherited_prerequisites.items():
            if prerequisite_id in prerequisites and prerequisites[prerequisite_id] != requirement:
                raise ContractError(f"operator prerequisite conflict in {profile_id}: {prerequisite_id}")
            prerequisites[prerequisite_id] = requirement
    return artifacts, prerequisites, ancestors


def profile_closure(profile_id: str, profiles: dict[str, dict[str, Any]], stack: tuple[str, ...] = ()) -> tuple[set[str], set[str]]:
    artifacts, _prerequisites, ancestors = profile_resolution(profile_id, profiles, stack)
    return artifacts, ancestors


def runtime_tree_requirements(profile_id: str, profiles: dict[str, dict[str, Any]],
    stack: tuple[str, ...] = ()) -> dict[str, dict[str, Any]]:
    if profile_id in stack:
        raise ContractError(f"profile inheritance cycle: {' -> '.join(stack + (profile_id,))}")
    profile = profiles.get(profile_id)
    if profile is None:
        raise ContractError(f"unknown profile: {profile_id}")
    result: dict[str, dict[str, Any]] = {}
    for parent in profile["extends"]:
        result.update(runtime_tree_requirements(parent, profiles, stack + (profile_id,)))
    for requirement in profile["requiredRuntimeTrees"]:
        tree_id = requirement["treeId"]
        if tree_id in result and result[tree_id] != requirement:
            raise ContractError(f"runtime tree requirement conflict in {profile_id}: {tree_id}")
        result[tree_id] = requirement
    return result


def validate_locks(root: Path, framework_catalog_bin: Path | None = None,
    framework_catalog_sha256: str | None = None) -> dict[str, Any]:
    lock_files = {
        "profiles-lock": root / "profiles.json",
        "component-lock": root / "component-lock.json",
        "dependency-lock": root / "dependency-lock.json",
    }
    lock_raw = {input_id: _read_bounded_regular(path) for input_id, path in lock_files.items()}
    profiles_doc = _decode_json(lock_files["profiles-lock"], lock_raw["profiles-lock"])
    components_doc = _decode_json(lock_files["component-lock"], lock_raw["component-lock"])
    dependencies_doc = _decode_json(lock_files["dependency-lock"], lock_raw["dependency-lock"])
    catalog_path = root.parents[1] / "catalog/framework-catalog.json"
    catalog_raw = _read_bounded_regular(catalog_path)
    catalog = _decode_json(catalog_path, catalog_raw)
    catalog_bin = framework_catalog_bin or (root.parents[1] / ".lake/build/bin/framework_catalog")
    if not catalog_bin.is_file():
        raise ContractError(f"trusted framework_catalog executable is missing: {catalog_bin}")
    with tempfile.TemporaryDirectory(prefix="mirrors-catalog-snapshot-") as temporary:
        snapshot = Path(temporary) / "framework-catalog.json"
        descriptor = os.open(snapshot, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0), 0o600)
        try:
            offset = 0
            while offset < len(catalog_raw):
                offset += os.write(descriptor, catalog_raw[offset:])
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        returncode, stdout, stderr = run_trusted_catalog_validation(catalog_bin,
            framework_catalog_sha256, snapshot)
    if returncode != 0:
        detail = stderr.strip() or stdout.strip()
        raise ContractError(f"selected catalog fails C3 validation: {detail}")
    closed(profiles_doc, {"schemaVersion", "distributionId", "catalogSelectionRef", "publication", "profiles"}, set(), "profiles")
    if profiles_doc["schemaVersion"] != "mirrors.reference-distribution-profiles/v1" or profiles_doc["publication"] != "unclaimed":
        raise ContractError("profiles: unsupported schema or publication claim")
    selection = profiles_doc["catalogSelectionRef"]
    closed(selection, {"schemaVersion", "selectionKind", "selectionValue"}, set(), "catalogSelectionRef")
    catalog_digest = digest_json(catalog)
    if selection != {"schemaVersion": "mirrors.framework-catalog/v1", "selectionKind": "sha256", "selectionValue": catalog_digest}:
        raise ContractError("catalogSelectionRef does not identify the selected catalog bytes")
    closed(components_doc, {"schemaVersion", "catalogSelectionRef", "components", "buildArtifacts"}, set(), "componentLock")
    if components_doc.get("schemaVersion") != "mirrors.reference-component-lock/v1" or components_doc.get("catalogSelectionRef") != selection:
        raise ContractError("component lock schema/catalog selection mismatch")
    closed(dependencies_doc, {"schemaVersion", "dependencies"}, set(), "dependencyLock")
    if dependencies_doc.get("schemaVersion") != "mirrors.reference-dependency-lock/v1":
        raise ContractError("dependency lock schema mismatch")
    catalog_components = {entry["componentRef"]["componentId"]: entry for entry in catalog["components"]}
    locked_components = {}
    for index, entry in enumerate(exact_list(components_doc.get("components"), "components", 64)):
        ref = closed(entry, {"componentRef", "product"}, set(), f"components[{index}]")["componentRef"]
        component_id = identifier(ref.get("componentId"), f"components[{index}].componentRef.componentId")
        if component_id in locked_components:
            raise ContractError(f"duplicate component lock: {component_id}")
        locked_components[component_id] = ref
    if set(locked_components) != set(catalog_components):
        raise ContractError("component lock does not cover the catalog component set")
    for component_id, ref in locked_components.items():
        locked_entry = next(entry for entry in components_doc["components"] if entry["componentRef"]["componentId"] == component_id)
        if ref != catalog_components[component_id]["componentRef"] or locked_entry["product"] != catalog_components[component_id]["product"]:
            raise ContractError(f"component identity differs from catalog: {component_id}")
    build_artifacts = unique_ids(exact_list(components_doc.get("buildArtifacts"), "buildArtifacts"), "artifactId", "buildArtifacts")
    for artifact_id, artifact in build_artifacts.items():
        closed(artifact, {"artifactId", "componentId", "recipe", "source", "outputPath", "mode"},
            {"dynamicLinkPolicy", "buildDependencies"}, f"buildArtifacts.{artifact_id}")
        if artifact["componentId"] not in locked_components:
            raise ContractError(f"build artifact owner is unknown: {artifact_id}")
        recipe = closed(artifact["recipe"], {"tool", "resolution", "argv"}, set(), f"buildArtifacts.{artifact_id}.recipe")
        identifier(recipe["tool"], f"buildArtifacts.{artifact_id}.recipe.tool")
        if recipe["resolution"] not in {"operator-explicit", "component-artifact", "internal"}:
            raise ContractError(f"build artifact recipe resolution is invalid: {artifact_id}")
        arguments = exact_list(recipe["argv"], f"buildArtifacts.{artifact_id}.recipe.argv", 64)
        if any(not isinstance(argument, str) or not argument for argument in arguments):
            raise ContractError(f"buildArtifacts.{artifact_id}.recipe.argv: nonempty strings required")
        source = closed(artifact["source"], {"kind"}, {"path", "description"}, f"buildArtifacts.{artifact_id}.source")
        if source["kind"] in {"file", "tree"}:
            if set(source) != {"kind", "path"}:
                raise ContractError(f"path source shape is invalid: {artifact_id}")
            logical_path(source["path"], f"buildArtifacts.{artifact_id}.source.path")
        elif source["kind"] in {"generated", "component-root"}:
            if set(source) != {"kind", "description"} or not isinstance(source["description"], str) or not source["description"]:
                raise ContractError(f"generated source shape is invalid: {artifact_id}")
        else:
            raise ContractError(f"unsupported source kind: {artifact_id}")
        logical_path(artifact["outputPath"], f"buildArtifacts.{artifact_id}.outputPath")
        if artifact["mode"] not in {"0644", "0755", "tree"}:
            raise ContractError(f"unsupported artifact mode: {artifact_id}")
        if artifact["mode"] == "0755" and artifact.get("dynamicLinkPolicy") != "record-resolved-path-and-sha256":
            raise ContractError(f"executable lacks dynamic-library audit policy: {artifact_id}")
        if artifact["mode"] != "0755" and "dynamicLinkPolicy" in artifact:
            raise ContractError(f"non-executable has dynamic-library audit policy: {artifact_id}")
        string_list(artifact.get("buildDependencies", []),
            f"buildArtifacts.{artifact_id}.buildDependencies", 64)
    dependencies = unique_ids(exact_list(dependencies_doc.get("dependencies"), "dependencies"), "artifactId", "dependencies")
    for artifact_id, dependency in dependencies.items():
        availability = dependency.get("availability")
        if availability == "prepared-cache":
            closed(dependency, {"artifactId", "version", "availability", "fileName", "bytes", "sha256", "mediaType", "licenseStatus"},
                {"runtimeSelection", "hostLibraries"}, f"dependencies.{artifact_id}")
            logical_path(dependency["fileName"], f"dependencies.{artifact_id}.fileName")
            if type(dependency["bytes"]) is not int or dependency["bytes"] < 0 or not SHA256.fullmatch(dependency["sha256"]):
                raise ContractError(f"invalid prepared dependency identity: {artifact_id}")
            if "runtimeSelection" in dependency:
                runtime_selection = closed(dependency["runtimeSelection"],
                    {"rootPrefix", "symlinkPolicy"}, {"include", "includeTrees", "packageManagerContent"},
                    f"dependencies.{artifact_id}.runtimeSelection")
                logical_path(runtime_selection["rootPrefix"], f"dependencies.{artifact_id}.runtimeSelection.rootPrefix")
                includes = string_list(runtime_selection.get("include", []), f"dependencies.{artifact_id}.runtimeSelection.include", 1024)
                include_trees = string_list(runtime_selection.get("includeTrees", []), f"dependencies.{artifact_id}.runtimeSelection.includeTrees", 1024)
                if not includes and not include_trees:
                    raise ContractError(f"runtime selection is empty: {artifact_id}")
                for field, selected in (("include", includes), ("includeTrees", include_trees)):
                    for index, include in enumerate(selected):
                        logical_path(include, f"dependencies.{artifact_id}.runtimeSelection.{field}[{index}]")
                    if selected != sorted(selected, key=lambda value: value.encode("utf-8")):
                        raise ContractError(f"dependencies.{artifact_id}.runtimeSelection.{field}: UTF-8 sorted order required")
                if runtime_selection["symlinkPolicy"] != "reject":
                    raise ContractError(f"runtime selection must reject links: {artifact_id}")
                if "packageManagerContent" in runtime_selection and runtime_selection["packageManagerContent"] != "excluded":
                    raise ContractError(f"runtime selection must exclude package-manager content: {artifact_id}")
            if "hostLibraries" in dependency:
                libraries = string_list(dependency["hostLibraries"], f"dependencies.{artifact_id}.hostLibraries", 64)
                if libraries != sorted(libraries):
                    raise ContractError(f"dependencies.{artifact_id}.hostLibraries: sorted order required")
        elif availability == "missing":
            closed(dependency, {"artifactId", "version", "availability", "reason", "licenseStatus"}, set(), f"dependencies.{artifact_id}")
        else:
            raise ContractError(f"unsupported dependency availability: {artifact_id}")
    for artifact_id, artifact in build_artifacts.items():
        for dependency_id in artifact.get("buildDependencies", []):
            dependency = dependencies.get(dependency_id)
            if dependency is None or dependency["availability"] != "prepared-cache":
                raise ContractError(f"build dependency is not prepared and locked: {artifact_id}:{dependency_id}")
    profiles = unique_ids(exact_list(profiles_doc["profiles"], "profiles", 64), "profileId", "profiles")
    catalog_profiles = {profile["profileId"] for profile in catalog["distributionProfiles"]}
    known_artifacts = set(build_artifacts) | set(dependencies)
    for profile_id, profile in profiles.items():
        closed(profile, {"profileId", "catalogProfileId", "combinationId", "status", "extends", "requiredArtifacts",
            "requiredRuntimeTrees", "operatorPrerequisites", "forbiddenArtifacts"}, set(), f"profiles.{profile_id}")
        if profile["catalogProfileId"] not in catalog_profiles:
            raise ContractError(f"catalog profile does not resolve: {profile_id}")
        for field in ("extends", "requiredArtifacts", "forbiddenArtifacts"):
            string_list(profile[field], f"profiles.{profile_id}.{field}", 256)
        prerequisites = unique_ids(exact_list(profile["operatorPrerequisites"],
            f"profiles.{profile_id}.operatorPrerequisites", 64), "id",
            f"profiles.{profile_id}.operatorPrerequisites")
        for prerequisite_id, prerequisite in prerequisites.items():
            closed(prerequisite, {"id"}, {"minimumVersion", "observedVersion", "requirement"},
                f"profiles.{profile_id}.operatorPrerequisites.{prerequisite_id}")
            if len(prerequisite) == 1:
                raise ContractError(f"operator prerequisite lacks a requirement: {prerequisite_id}")
        tree_requirements = unique_ids(exact_list(profile["requiredRuntimeTrees"],
            f"profiles.{profile_id}.requiredRuntimeTrees", 64), "treeId",
            f"profiles.{profile_id}.requiredRuntimeTrees")
        for tree_id, requirement in tree_requirements.items():
            closed(requirement, {"treeId", "sourceArtifactId", "selectionId"}, set(),
                f"profiles.{profile_id}.requiredRuntimeTrees.{tree_id}")
            identifier(requirement["sourceArtifactId"], f"profiles.{profile_id}.requiredRuntimeTrees.{tree_id}.sourceArtifactId")
            identifier(requirement["selectionId"], f"profiles.{profile_id}.requiredRuntimeTrees.{tree_id}.selectionId")
        closure, _ = profile_closure(profile_id, profiles)
        unknown = sorted(closure - known_artifacts)
        if unknown:
            raise ContractError(f"profile {profile_id} references unknown artifact: {unknown[0]}")
        forbidden = closure & set(profile["forbiddenArtifacts"])
        if forbidden:
            raise ContractError(f"profile {profile_id} contains forbidden artifact: {sorted(forbidden)[0]}")
        inherited_trees = runtime_tree_requirements(profile_id, profiles)
        for tree_id, requirement in inherited_trees.items():
            if requirement["sourceArtifactId"] not in closure:
                raise ContractError(f"runtime tree source is outside profile closure: {tree_id}")
    for checked in ("checked-replay-local", "checked-replay-gate"):
        closure, _ = profile_closure(checked, profiles)
        if closure & {"java-runtime", "apalache"}:
            raise ContractError(f"{checked} must not contain Java or Apalache")
    gate_closure, gate_ancestors = profile_closure("checked-replay-gate", profiles)
    local_closure, _ = profile_closure("checked-replay-local", profiles)
    if "checked-replay-local" not in gate_ancestors or not local_closure <= gate_closure:
        raise ContractError("Gate profile must explicitly extend complete local closure")
    fresh_closure, _ = profile_closure("fresh-trace", profiles)
    if not {"java-runtime", "apalache"} <= fresh_closure:
        raise ContractError("fresh-trace must contain exact Java/Apalache closure")
    expected_fresh_status = ("build-required" if dependencies["java-runtime"]["availability"] == "prepared-cache"
        else "blocked-missing-java-artifact")
    if profiles["fresh-trace"]["status"] != expected_fresh_status:
        raise ContractError("fresh-trace status does not match exact Java artifact availability")
    catalog_combinations = {combination["combinationId"]: combination for combination in catalog["combinations"]}
    combination_components = {}
    for profile_id, profile in profiles.items():
        combination = catalog_combinations.get(profile["combinationId"])
        if combination is None or profile["catalogProfileId"] not in combination["distributionProfileIds"]:
            raise ContractError(f"profile combination does not resolve: {profile_id}")
        combination_components[profile_id] = set(combination["componentIds"])
    build_inputs = {
        input_id: {
            "inputId": input_id,
            "path": f"distribution/reference-node/{path.name}",
            "bytes": len(lock_raw[input_id]),
            "sha256": hashlib.sha256(lock_raw[input_id]).hexdigest(),
        }
        for input_id, path in lock_files.items()
    }
    return {"profiles": profiles, "dependencies": dependencies, "buildArtifacts": build_artifacts,
        "selection": selection, "componentRefs": locked_components, "combinationComponents": combination_components,
        "buildInputs": build_inputs, "distributionId": profiles_doc["distributionId"],
        "catalog": catalog}


def validate_distribution_manifest(path: Path, profile_id: str, contract: dict[str, Any]) -> tuple[dict[str, Any], str]:
    document = load_json(path)
    closed(document, {"schemaVersion", "distributionId", "catalogSelectionRef", "profileId",
        "componentRefs", "buildInputs", "buildProvenance", "artifacts", "runtimeTrees", "hostRequirements", "publication"}, set(), "distributionManifest")
    if document["schemaVersion"] != "mirrors.reference-distribution-manifest/v1" or document["profileId"] != profile_id:
        raise ContractError("distribution manifest schema/profile mismatch")
    if document["distributionId"] != contract["distributionId"]:
        raise ContractError("distributionId differs from locked profile identity")
    if document["catalogSelectionRef"] != contract["selection"] or document["publication"] != "unclaimed":
        raise ContractError("distribution manifest catalog/publication mismatch")
    refs: dict[str, dict[str, Any]] = {}
    for index, ref in enumerate(exact_list(document["componentRefs"], "componentRefs", 64)):
        if not isinstance(ref, dict):
            raise ContractError(f"componentRefs[{index}]: object required")
        component_id = identifier(ref.get("componentId"), f"componentRefs[{index}].componentId")
        if component_id in refs:
            raise ContractError(f"componentRefs[{index}]: duplicate componentId")
        refs[component_id] = ref
    selected_components = contract["combinationComponents"][profile_id]
    expected_refs = {component_id: contract["componentRefs"][component_id]
        for component_id in selected_components}
    if refs != expected_refs:
        raise ContractError("distribution componentRefs differ from selected combination component set")
    build_inputs = unique_ids(exact_list(document["buildInputs"], "buildInputs", 64), "inputId", "buildInputs")
    for input_id, build_input in build_inputs.items():
        closed(build_input, {"inputId", "path", "bytes", "sha256"}, set(), f"buildInputs.{input_id}")
        logical_path(build_input["path"], f"buildInputs.{input_id}.path")
        if type(build_input["bytes"]) is not int or not 1 <= build_input["bytes"] <= MAX_JSON_BYTES:
            raise ContractError(f"invalid build input byte count: {input_id}")
        if not SHA256.fullmatch(build_input["sha256"]):
            raise ContractError(f"invalid build input digest: {input_id}")
    if build_inputs != contract["buildInputs"]:
        raise ContractError("distribution buildInputs differ from complete lock-file bytes")
    provenance = closed(document["buildProvenance"], {"snapshotIndexSha256", "tools", "trees"}, set(), "buildProvenance")
    if not SHA256.fullmatch(provenance["snapshotIndexSha256"]):
        raise ContractError("build provenance snapshot index digest is invalid")
    provenance_tools = unique_ids(exact_list(provenance["tools"], "buildProvenance.tools", 32),
        "toolId", "buildProvenance.tools")
    if set(provenance_tools) != {"python", "git", "ldd", "lake", "framework-catalog-bootstrap"}:
        raise ContractError("build provenance tool set is incomplete or unexpected")
    for tool_id, tool in provenance_tools.items():
        closed(tool, {"toolId", "version", "bytes", "sha256"}, set(), f"buildProvenance.tools.{tool_id}")
        if not isinstance(tool["version"], str) or not tool["version"] or type(tool["bytes"]) is not int or tool["bytes"] < 1 or not SHA256.fullmatch(tool["sha256"]):
            raise ContractError(f"invalid build tool provenance: {tool_id}")
    provenance_trees = unique_ids(exact_list(provenance["trees"], "buildProvenance.trees", 32),
        "inputId", "buildProvenance.trees")
    required_provenance_trees = {"typescript-node-modules", "evidence-wheels",
        "package:mirrorecma", "application:validation"}
    if profile_id == "checked-replay-gate":
        required_provenance_trees.add("package:mirrorgate-mirrorecma")
    if (not required_provenance_trees <= set(provenance_trees) or
            set(provenance_trees) - required_provenance_trees - {"lean-build-cache"}):
        raise ContractError("build provenance tree set is incomplete or unexpected")
    for input_id, tree in provenance_trees.items():
        closed(tree, {"inputId", "algorithm", "digest", "entryCount", "bytes"}, set(), f"buildProvenance.trees.{input_id}")
        if (tree["algorithm"] != "mirrors-runtime-tree-v1" or not SHA256.fullmatch(tree["digest"]) or
                type(tree["entryCount"]) is not int or tree["entryCount"] < 1 or
                type(tree["bytes"]) is not int or tree["bytes"] < 1):
            raise ContractError(f"invalid build tree provenance: {input_id}")
    artifacts = unique_ids(exact_list(document["artifacts"], "artifacts", 1024), "artifactId", "artifacts")
    closure, prerequisites, _ = profile_resolution(profile_id, contract["profiles"])
    if set(artifacts) != closure:
        raise ContractError(f"distribution artifact closure mismatch: expected={sorted(closure)}, actual={sorted(artifacts)}")
    seen_paths: set[str] = set()
    seen_casefolded: set[str] = set()
    for artifact_id, artifact in artifacts.items():
        closed(artifact, {"artifactId", "path", "kind", "mediaType", "bytes", "sha256", "mode", "source"},
            {"dynamicLibraries"}, f"artifacts.{artifact_id}")
        logical = logical_path(artifact["path"], f"artifacts.{artifact_id}.path")
        if logical in seen_paths or logical.casefold() in seen_casefolded:
            raise ContractError(f"duplicate or case-colliding artifact path: {logical}")
        seen_paths.add(logical)
        seen_casefolded.add(logical.casefold())
        if artifact["kind"] not in {"file", "archive"} or artifact["mode"] not in {"0644", "0755"}:
            raise ContractError(f"unsupported artifact kind/mode: {artifact_id}")
        if type(artifact["bytes"]) is not int or artifact["bytes"] < 0 or not SHA256.fullmatch(artifact["sha256"]):
            raise ContractError(f"invalid artifact identity: {artifact_id}")
        source = closed(artifact["source"], {"kind", "id"}, set(), f"artifacts.{artifact_id}.source")
        if source["kind"] not in {"component-build", "dependency-lock"}:
            raise ContractError(f"unsupported artifact source: {artifact_id}")
        if source["id"] != artifact_id:
            raise ContractError(f"artifact source id does not match artifactId: {artifact_id}")
        if source["kind"] == "component-build" and artifact_id not in contract["buildArtifacts"]:
            raise ContractError(f"artifact source is not a locked component build: {artifact_id}")
        libraries = exact_list(artifact.get("dynamicLibraries", []), f"artifacts.{artifact_id}.dynamicLibraries", 64)
        if artifact["mode"] == "0755" and not libraries:
            raise ContractError(f"executable lacks dynamic-library audit: {artifact_id}")
        if artifact["mode"] != "0755" and libraries:
            raise ContractError(f"non-executable has dynamic-library audit: {artifact_id}")
        seen_sonames: set[str] = set()
        for library_index, library in enumerate(libraries):
            library = closed(library, {"soname", "path", "sha256"}, set(),
                f"artifacts.{artifact_id}.dynamicLibraries[{library_index}]")
            if not isinstance(library["soname"], str) or not library["soname"] or library["soname"] in seen_sonames:
                raise ContractError(f"invalid or duplicate dynamic library SONAME: {artifact_id}")
            seen_sonames.add(library["soname"])
            if not isinstance(library["path"], str) or not Path(library["path"]).is_absolute() or not SHA256.fullmatch(library["sha256"]):
                raise ContractError(f"invalid dynamic library identity: {artifact_id}")
        dependency = contract["dependencies"].get(artifact_id)
        if source["kind"] == "dependency-lock":
            if dependency is None or dependency["availability"] != "prepared-cache":
                raise ContractError(f"artifact lacks prepared dependency lock: {artifact_id}")
            if artifact["bytes"] != dependency["bytes"] or artifact["sha256"] != dependency["sha256"]:
                raise ContractError(f"artifact differs from dependency lock: {artifact_id}")
    trees = unique_ids(exact_list(document["runtimeTrees"], "runtimeTrees", 64), "treeId", "runtimeTrees")
    required_trees = runtime_tree_requirements(profile_id, contract["profiles"])
    if set(trees) != set(required_trees):
        raise ContractError(f"runtime tree set mismatch: expected={sorted(required_trees)}, actual={sorted(trees)}")
    for tree_id, tree in trees.items():
        closed(tree, {"treeId", "sourceArtifactId", "selectionId", "path", "algorithm", "digest", "entryCount", "bytes"}, set(), f"runtimeTrees.{tree_id}")
        requirement = required_trees[tree_id]
        if tree["sourceArtifactId"] != requirement["sourceArtifactId"] or tree["selectionId"] != requirement["selectionId"]:
            raise ContractError(f"runtime tree does not match selected source/extraction: {tree_id}")
        if tree["sourceArtifactId"] not in artifacts:
            raise ContractError(f"runtime tree source artifact is absent: {tree_id}")
        logical_path(tree["path"], f"runtimeTrees.{tree_id}.path")
        if tree["algorithm"] != "mirrors-runtime-tree-v1" or not SHA256.fullmatch(tree["digest"]):
            raise ContractError(f"invalid runtime tree identity: {tree_id}")
        if type(tree["entryCount"]) is not int or not 1 <= tree["entryCount"] <= 100_000:
            raise ContractError(f"invalid runtime tree count: {tree_id}")
        if type(tree["bytes"]) is not int or not 1 <= tree["bytes"] <= 2_147_483_648:
            raise ContractError(f"invalid runtime tree bytes: {tree_id}")
    requirements = unique_ids(exact_list(document["hostRequirements"], "hostRequirements", 64), "id", "hostRequirements")
    if requirements != prerequisites:
        raise ContractError("host requirements differ from inherited profile prerequisite predicates")
    for requirement_id, requirement in requirements.items():
        closed(requirement, {"id"}, {"minimumVersion", "observedVersion", "requirement"},
            f"hostRequirements.{requirement_id}")
        if len(requirement) == 1 or any(not isinstance(value, str) or not value
            for key, value in requirement.items() if key != "id"):
            raise ContractError(f"empty host prerequisite predicate: {requirement_id}")
    return document, digest_json(document)


def validate_cache_index(path: Path, profile_id: str, contract: dict[str, Any],
    distribution_manifest: tuple[dict[str, Any], str] | None = None) -> None:
    document = load_json(path)
    closed(document, {"schemaVersion", "profileId", "catalogSelectionRef", "distributionManifestSha256", "entries"}, set(), "cacheIndex")
    if document["schemaVersion"] != "mirrors.reference-cache-index/v1" or document["profileId"] != profile_id:
        raise ContractError("cache index schema/profile mismatch")
    if document["catalogSelectionRef"] != contract["selection"] or not SHA256.fullmatch(document["distributionManifestSha256"]):
        raise ContractError("cache index catalog/distribution identity mismatch")
    if distribution_manifest is not None and document["distributionManifestSha256"] != distribution_manifest[1]:
        raise ContractError("cache index distributionManifestSha256 does not match manifest bytes")
    entries = unique_ids(exact_list(document["entries"], "cacheIndex.entries"), "artifactId", "cacheIndex.entries")
    closure, _ = profile_closure(profile_id, contract["profiles"])
    if set(entries) != closure:
        missing = sorted(closure - set(entries))
        extra = sorted(set(entries) - closure)
        raise ContractError(f"cache index closure mismatch: missing={missing}, extra={extra}")
    seen_paths: set[str] = set()
    seen_casefolded_paths: set[str] = set()
    for artifact_id, entry in entries.items():
        closed(entry, {"artifactId", "path", "bytes", "sha256", "mode"}, set(), f"entries.{artifact_id}")
        logical = logical_path(entry["path"], f"entries.{artifact_id}.path")
        if logical in seen_paths or logical.casefold() in seen_casefolded_paths:
            raise ContractError(f"duplicate or case-colliding cache path: {logical}")
        seen_paths.add(logical)
        seen_casefolded_paths.add(logical.casefold())
        lowered = {part.lower() for part in re.split(r"[/_.]", artifact_id + "/" + logical)}
        if lowered & FORBIDDEN_PAYLOAD_WORDS:
            raise ContractError(f"private/operator payload is forbidden: {artifact_id}")
        if type(entry["bytes"]) is not int or entry["bytes"] < 0 or not SHA256.fullmatch(entry["sha256"]):
            raise ContractError(f"invalid cache entry identity: {artifact_id}")
        if entry["mode"] not in {"0644", "0755"}:
            raise ContractError(f"invalid cache entry mode: {artifact_id}")
        dependency = contract["dependencies"].get(artifact_id)
        if dependency is not None and dependency["availability"] == "prepared-cache":
            if entry["bytes"] != dependency["bytes"] or entry["sha256"] != dependency["sha256"]:
                raise ContractError(f"cache entry differs from dependency lock: {artifact_id}")
    missing_dependencies = sorted(
        artifact for artifact in closure
        if artifact in contract["dependencies"] and contract["dependencies"][artifact]["availability"] == "missing"
    )
    if missing_dependencies:
        raise ContractError(f"profile is unavailable; missing dependency: {missing_dependencies[0]}")
    if distribution_manifest is not None:
        manifest_entries = {entry["artifactId"]: entry for entry in distribution_manifest[0]["artifacts"]}
        for artifact_id, entry in entries.items():
            manifest = manifest_entries[artifact_id]
            for field in ("path", "bytes", "sha256", "mode"):
                if entry[field] != manifest[field]:
                    raise ContractError(f"cache entry differs from distribution manifest: {artifact_id}.{field}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["validate", "resolve"])
    parser.add_argument("root", type=Path)
    parser.add_argument("--profile")
    parser.add_argument("--cache-index", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--framework-catalog-bin", type=Path)
    parser.add_argument("--framework-catalog-sha256")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        if args.framework_catalog_bin and not args.framework_catalog_sha256:
            raise ContractError("--framework-catalog-bin requires --framework-catalog-sha256")
        contract = validate_locks(args.root.resolve(), args.framework_catalog_bin.resolve()
            if args.framework_catalog_bin else None, args.framework_catalog_sha256)
        if args.command == "resolve":
            if not args.profile or not args.cache_index or not args.manifest:
                raise ContractError("resolve requires --profile, --manifest and --cache-index")
            if args.profile not in contract["profiles"]:
                raise ContractError(f"unknown profile: {args.profile}")
            manifest = validate_distribution_manifest(args.manifest.resolve(), args.profile, contract)
            validate_cache_index(args.cache_index.resolve(), args.profile, contract, manifest)
        print(f"REFERENCE DISTRIBUTION {args.command.upper()} GREEN")
        return 0
    except (ContractError, OSError) as error:
        print(f"manifest-check: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
