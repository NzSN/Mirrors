"""Bind a verified E1 bundle to one exact C2/C3 catalog combination."""

from __future__ import annotations

import json
import hashlib
import os
import re
import selectors
import signal
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any

from store import read_regular
from validate import load_json, loads_json_bytes


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PROFILES = Path(__file__).resolve().parent / "qualification-profiles.json"
DIGEST = re.compile(r"sha256=([0-9a-f]{64})$")


def _quote(value: str) -> bytes:
    result = bytearray(b'"')
    for character in value:
        code = ord(character)
        if code == 0x22:
            result.extend(b'\\"')
        elif code == 0x5C:
            result.extend(b"\\\\")
        elif code < 0x20:
            result.extend(f"\\u{code:04x}".encode("ascii"))
        elif 0xD800 <= code <= 0xDFFF:
            raise ValueError("lone Unicode surrogate in distribution manifest")
        else:
            result.extend(character.encode("utf-8"))
    result.extend(b'"')
    return bytes(result)


def _framework_canonical(value: Any) -> bytes:
    if value is None:
        return b"null"
    if value is True:
        return b"true"
    if value is False:
        return b"false"
    if type(value) is int:
        if not -9_007_199_254_740_991 <= value <= 9_007_199_254_740_991:
            raise ValueError("integer exceeds signed safe range")
        return str(value).encode("ascii")
    if isinstance(value, str):
        return _quote(value)
    if isinstance(value, list):
        return b"[" + b",".join(_framework_canonical(item) for item in value) + b"]"
    if isinstance(value, dict):
        fields = sorted(value.items(), key=lambda field: field[0].encode("utf-8"))
        return b"{" + b",".join(
            _quote(key) + b":" + _framework_canonical(item) for key, item in fields
        ) + b"}"
    raise ValueError("unsupported distribution manifest JSON value")


def _profile(path: Path, profile_id: str) -> dict[str, Any]:
    document = load_json(path)
    if not isinstance(document, dict) or set(document) != {"schemaVersion", "profiles"}:
        raise ValueError("qualification profiles use a closed root shape")
    if document["schemaVersion"] != "mirrors.evidence-qualification-profiles/v1":
        raise ValueError("unsupported qualification profile schema")
    if not isinstance(document["profiles"], list):
        raise ValueError("qualification profiles must be an array")
    if not all(isinstance(profile, dict) for profile in document["profiles"]):
        raise ValueError("qualification profile entries must be objects")
    matches = [profile for profile in document["profiles"] if profile.get("profileId") == profile_id]
    if len(matches) != 1:
        raise ValueError(f"qualification profile must resolve exactly once: {profile_id}")
    profile = matches[0]
    required = {
        "profileId", "qualificationClass", "catalogVisibility", "requiredCommandIds", "requiredTierIds",
        "requiredArtifactRoles", "requiredCleanupScopes", "requiredObservationDimensions", "requireQualified",
        "allowedObservationDimensions",
        "requirePublicProjection", "requireCatalogLineage",
    }
    if set(profile) != required:
        raise ValueError("qualification profile uses an unknown or missing field")
    if (
        not isinstance(profile["profileId"], str)
        or profile["qualificationClass"] not in {"source-validation", "local-candidate", "release-candidate"}
        or profile["catalogVisibility"] not in {"public", "private"}
    ):
        raise ValueError("qualification profile identity/visibility is malformed")
    for field in ["requiredCommandIds", "requiredTierIds", "requiredArtifactRoles", "requiredCleanupScopes", "requiredObservationDimensions", "allowedObservationDimensions"]:
        if (
            not isinstance(profile[field], list)
            or not all(isinstance(item, str) and item for item in profile[field])
            or len(profile[field]) != len(set(profile[field]))
        ):
            raise ValueError(f"qualification profile {field} must be a unique array")
    if not set(profile["requiredObservationDimensions"]).issubset(profile["allowedObservationDimensions"]):
        raise ValueError("required observation dimensions must be allowed by the profile")
    for field in ["requireQualified", "requirePublicProjection", "requireCatalogLineage"]:
        if not isinstance(profile[field], bool):
            raise ValueError(f"qualification profile {field} must be Boolean")
    return profile


def _run_bounded_validator(executable: Path, snapshot: Path) -> tuple[int, bytes, bytes]:
    try:
        child = subprocess.Popen(
            [str(executable), "validate", str(snapshot)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
    except FileNotFoundError as error:
        raise ValueError(f"framework catalog validator is unavailable: {executable}") from error
    assert child.stdout is not None and child.stderr is not None
    selector = selectors.DefaultSelector()
    stdout = bytearray(); stderr = bytearray()
    selector.register(child.stdout, selectors.EVENT_READ, stdout)
    selector.register(child.stderr, selectors.EVENT_READ, stderr)
    deadline = time.monotonic() + 30
    try:
        while child.poll() is None or selector.get_map():
            if time.monotonic() >= deadline:
                try: os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError: pass
                child.wait(timeout=1)
                raise ValueError("framework catalog validation exceeded 30 seconds")
            for key, _ in selector.select(timeout=0.05):
                chunk = os.read(key.fileobj.fileno(), 8192)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                key.data.extend(chunk)
                if len(key.data) > 65536:
                    try: os.killpg(child.pid, signal.SIGKILL)
                    except ProcessLookupError: pass
                    child.wait(timeout=1)
                    raise ValueError("framework catalog validator output exceeded 65536 bytes")
        return child.wait(timeout=1), bytes(stdout), bytes(stderr)
    finally:
        selector.close()
        child.stdout.close(); child.stderr.close()


def _catalog_digest(catalog_path: Path, validator: Path | None) -> tuple[str, bytes]:
    configured = os.environ.get("MIRRORS_FRAMEWORK_CATALOG_VALIDATOR")
    executable = validator or (Path(configured) if configured else ROOT / ".lake/build/bin/framework_catalog")
    before, _ = read_regular(catalog_path, max_bytes=4 * 1024 * 1024)
    with tempfile.TemporaryDirectory(prefix="mirrors-catalog-verify-") as temporary:
        snapshot = Path(temporary) / "catalog.json"
        snapshot.write_bytes(before)
        os.chmod(snapshot, 0o600)
        returncode, stdout_bytes, stderr_bytes = _run_bounded_validator(executable, snapshot)
    stdout_text = stdout_bytes.decode("utf-8", "replace")
    stderr_text = stderr_bytes.decode("utf-8", "replace")
    if returncode != 0:
        raise ValueError("framework catalog validation failed: " + stderr_text.strip())
    match = DIGEST.search(stdout_text.strip())
    if match is None:
        raise ValueError("framework catalog validator did not report its canonical digest")
    return match.group(1), before


def _component_map(catalog: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {component["componentRef"]["componentId"]: component["componentRef"] for component in catalog["components"]}


def evaluate_catalog_link(
    catalog_path: Path,
    bundle: Path,
    verification: dict[str, Any],
    profile_id: str,
    profiles_path: Path = DEFAULT_PROFILES,
    catalog_validator: Path | None = None,
) -> dict[str, Any]:
    catalog_digest, catalog_bytes = _catalog_digest(catalog_path, catalog_validator)
    catalog = loads_json_bytes(catalog_bytes)
    profile = _profile(profiles_path, profile_id)
    if catalog["visibility"] != profile["catalogVisibility"]:
        raise ValueError(f"catalog visibility is {catalog['visibility']}; profile requires {profile['catalogVisibility']}")
    bundle = Path(bundle)
    envelope_bytes, envelope_digest = read_regular(bundle / "envelope.json", max_bytes=4 * 1024 * 1024)
    public_bytes, public_digest = read_regular(bundle / "public-summary.json", max_bytes=4 * 1024 * 1024)
    if envelope_digest != verification["privateRunRef"]["envelopeSha256"]:
        raise ValueError("private envelope changed after offline verification")
    if public_digest != verification["publicRunRef"]["envelopeSha256"]:
        raise ValueError("public summary changed after offline verification")
    envelope = loads_json_bytes(envelope_bytes)
    public = loads_json_bytes(public_bytes)
    from qualification_scope import validate_command_context
    validate_command_context(bundle, envelope)

    if profile["requireCatalogLineage"]:
        lineage = catalog.get("extensions", {}).get("org.nzsn.catalog-lineage")
        selected = lineage.get("previousSelectionRef") if isinstance(lineage, dict) else None
        if selected != envelope["catalogSelectionRef"]:
            raise ValueError("catalog lineage does not name the bundle's exact pre-run catalog selection")

    public_ref = verification["publicRunRef"]
    matches = [
        item for item in catalog["evidenceRefs"]
        if item.get("runRef") == public_ref
    ]
    if len(matches) != 1:
        raise ValueError("catalog must contain exactly one matching finalized public runRef")
    evidence_id = matches[0]["evidenceId"]
    combinations = [combination for combination in catalog["combinations"] if evidence_id in combination["evidenceIds"]]
    if len(combinations) != 1:
        raise ValueError("public evidence must resolve to exactly one catalog combination")
    combination = combinations[0]
    if combination["declaredState"] == "unsupported":
        raise ValueError("unsupported combination cannot be release evidence")

    catalog_components = _component_map(catalog)
    expected_ids = set(combination["componentIds"])
    actual_components = {component["componentId"]: component for component in envelope["components"]}
    if set(actual_components) != expected_ids:
        raise ValueError("bundle component set differs from the cited catalog combination")
    for component_id in sorted(expected_ids):
        if actual_components[component_id] != catalog_components.get(component_id):
            raise ValueError(f"bundle component identity differs from catalog: {component_id}")

    scope_verification: dict[str, Any] | None = None
    candidate = profile["qualificationClass"] in {"local-candidate", "release-candidate"}
    if candidate:
        if [command["commandId"] for command in envelope["commands"]] != ["evidence.offline-verify"]:
            raise ValueError("Q bundle must contain only the registered offline scope-verification command")
        from qualification_scope import attached_scope

        scope_verification = attached_scope(bundle, envelope, bundle.parent.parent)
        if scope_verification["qualificationClass"] != profile["qualificationClass"]:
            raise ValueError("qualification scope class differs from the selected profile")
        if scope_verification["selectedCatalogRef"] != envelope["catalogSelectionRef"]:
            raise ValueError("qualification scope selects a different C0 catalog")
        scope_components = {
            component["componentId"]: component
            for component in scope_verification["componentRefs"]
        }
        if scope_components != actual_components:
            raise ValueError("distribution-binding run components differ from the Q/catalog combination")
        scope_command_ids = [command["commandId"] for command in scope_verification["commands"]]
        if "evidence.offline-verify" in scope_command_ids:
            raise ValueError("qualification input scope cannot pre-credit the Q verification command")
        command_ids = {"evidence.offline-verify", *scope_command_ids}
        tier_records = [*envelope["tiers"], *scope_verification["tiers"]]
        required_roles = {
            artifact["role"] for artifact in envelope["artifacts"]
            if artifact["requirement"] == "required"
        } | set(scope_verification["requiredArtifactRoles"])
        cleanup_records = [*envelope["outcomes"]["cleanup"], *scope_verification["cleanup"]]
        distribution_manifest_sha256 = scope_verification["distributionManifestSha256"]
        cache_index_sha256 = scope_verification["cacheIndexSha256"]
    else:
        command_ids = {command["commandId"] for command in envelope["commands"]}
        tier_records = envelope["tiers"]
        required_roles = {
            artifact["role"] for artifact in envelope["artifacts"]
            if artifact["requirement"] == "required"
        }
        cleanup_records = envelope["outcomes"]["cleanup"]
        distribution_manifest_sha256 = None
        cache_index_sha256 = None
    missing_commands = sorted(set(profile["requiredCommandIds"]) - command_ids)
    if missing_commands:
        raise ValueError(f"required command is absent: {missing_commands[0]}")
    for tier_id in profile["requiredTierIds"]:
        matches = [tier for tier in tier_records if tier["tierId"] == tier_id]
        if not matches or any(tier["requirement"] != "required" or tier["status"] != "passed"
                              for tier in matches):
            raise ValueError(f"required tier did not pass: {tier_id}")
    missing_roles = sorted(set(profile["requiredArtifactRoles"]) - required_roles)
    if missing_roles:
        raise ValueError(f"required artifact role is absent: {missing_roles[0]}")
    cleanup: dict[str, list[dict[str, Any]]] = {}
    for entry in cleanup_records:
        cleanup.setdefault(entry["scope"], []).append(entry)
    cleanup_scopes = set(profile["requiredCleanupScopes"]) | set(envelope["releaseRequirements"]["requiredCleanupScopes"])
    for scope in sorted(cleanup_scopes):
        entries = [entry for entry in cleanup.get(scope, [])
                   if entry["requirement"] == "required"]
        if not entries or any(entry["status"] != "confirmed" for entry in entries):
            raise ValueError(f"required cleanup is not confirmed: {scope}")
    if envelope["outcomes"]["persistence"]["status"] != "complete":
        raise ValueError("release evidence persistence is not complete")
    if profile["requireQualified"] and envelope["qualification"]["status"] != "qualified":
        raise ValueError("bundle is not qualified under its recorded outcomes")
    if profile["requirePublicProjection"] and public["projectionKind"] != "public":
        raise ValueError("release evidence lacks its public projection")

    capabilities = {capability["capabilityId"]: capability for capability in catalog["capabilities"]}
    distribution_profiles = {item["profileId"]: item for item in catalog["distributionProfiles"]}
    for distribution_id in combination["distributionProfileIds"]:
        distribution = distribution_profiles[distribution_id]
        for capability_id in distribution["requiredCapabilityIds"]:
            capability = capabilities[capability_id]
            for dimension in profile["requiredObservationDimensions"]:
                observation = capability["observations"].get(dimension)
                if observation != {"state": "accepted", "evidenceId": evidence_id}:
                    raise ValueError(
                        f"required catalog observation is not bound to this evidence: {capability_id}/{dimension}"
                    )
    for capability_id in combination["capabilityIds"]:
        capability = capabilities[capability_id]
        for dimension, observation in capability["observations"].items():
            if observation.get("evidenceId") == evidence_id and dimension not in profile["allowedObservationDimensions"]:
                raise ValueError(
                    f"qualification profile cannot promote evidence into observation dimension: {dimension}"
                )

    result = {
        "schemaVersion": "mirrors.evidence-catalog-link/v1",
        "profileId": profile_id,
        "qualificationClass": profile["qualificationClass"],
        "catalogId": catalog["catalogId"],
        "catalogSha256": catalog_digest,
        "approvalCatalogRef": {
            "schemaVersion": "mirrors.framework-catalog/v1",
            "selectionKind": "sha256",
            "selectionValue": catalog_digest,
        },
        "combinationId": combination["combinationId"],
        "evidenceId": evidence_id,
        "selectedCatalogRef": envelope["catalogSelectionRef"],
        "publicRunRef": public_ref,
        "qualification": "accepted",
        "integrity": "verified",
        "executionProvenance": "evidence-observed",
    }
    if distribution_manifest_sha256 is not None:
        result["distributionManifestSha256"] = distribution_manifest_sha256
        result["cacheIndexSha256"] = cache_index_sha256
    return result
