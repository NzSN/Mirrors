#!/usr/bin/env python3
"""Verify a private acyclic scope of already-finalized qualification runs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

from command_registry import parse_registry, select_command
from store import ensure_owner_directory, logical_path, read_regular
from validate import ROOT, load_json, loads_json_bytes
from verify import verify


MAX_SCOPE_BYTES = 1024 * 1024
MAX_NODES = 64
MAX_EDGES = 256
SCOPE_SCHEMA = ROOT / "schema" / "qualification-scope-v1.schema.json"
COMMAND_CONTEXT_SCHEMA = ROOT / "schema" / "command-context-v1.schema.json"
SCOPE_VALIDATOR = Draft202012Validator(load_json(SCOPE_SCHEMA))
COMMAND_CONTEXT_VALIDATOR = Draft202012Validator(load_json(COMMAND_CONTEXT_SCHEMA))
_DISTRIBUTION_VALIDATORS: dict[Path, Draft202012Validator] = {}
SCOPE_PRODUCER = "mirrors.qualifier"
SCOPE_PRODUCER_SCHEMA = "mirrors.qualification-scope/v1"
SOURCE_COMMAND_COMPONENTS = {
    "mirrors.local-no-model": frozenset(("mirrors",)),
    "mirrors.remote-model-check": frozenset(("mirrors",)),
    "mirrors.interop": frozenset(("mirrors", "mirrorecma", "mirrorgate")),
    "mirrorecma.project-check": frozenset(("mirrors", "mirrorecma")),
    "mirrorecma.test": frozenset(("mirrors", "mirrorecma")),
    "mirrorgate.required": frozenset(("mirrors", "mirrorgate")),
}
COMMAND_PHASES = {
    "framework.install-diagnostics": "distribution",
    **{command: "source-gate" for command in SOURCE_COMMAND_COMPONENTS},
    "mirrorgate.application-campaign.work-queue": "origin",
    "mirrorgate.application-campaign.persistent-transfer": "origin",
    "mirrorgate.application-campaign.lease-service": "origin",
    "framework.replay-correct": "replay",
    "framework.replay-faulty": "replay",
    "framework.reproduction": "reproduction",
    "framework.reduction": "reduction",
    "framework.mutation-local": "mutation",
    "framework.mutation-gate": "mutation",
    "mirrorgate.recovery": "recovery",
}
INSTALLED_PHASES = frozenset((
    "installed-diagnostic", "replay", "origin", "reproduction", "reduction",
    "mutation", "recovery",
))


def _canonical_framework_json(value: Any) -> bytes:
    if value is None:
        return b"null"
    if value is True:
        return b"true"
    if value is False:
        return b"false"
    if type(value) is int:
        if not -9_007_199_254_740_991 <= value <= 9_007_199_254_740_991:
            raise ValueError("qualification distribution integer exceeds signed safe range")
        return str(value).encode("ascii")
    if isinstance(value, str):
        output = bytearray(b'"')
        for character in value:
            code = ord(character)
            if character == '"':
                output.extend(b'\\"')
            elif character == "\\":
                output.extend(b"\\\\")
            elif code < 0x20:
                output.extend(f"\\u{code:04x}".encode("ascii"))
            elif 0xD800 <= code <= 0xDFFF:
                raise ValueError("qualification distribution contains a lone Unicode surrogate")
            else:
                output.extend(character.encode("utf-8"))
        output.extend(b'"')
        return bytes(output)
    if isinstance(value, list):
        return b"[" + b",".join(_canonical_framework_json(item) for item in value) + b"]"
    if isinstance(value, dict):
        fields = sorted(value.items(), key=lambda item: item[0].encode("utf-8"))
        return b"{" + b",".join(
            _canonical_framework_json(key) + b":" + _canonical_framework_json(item)
            for key, item in fields
        ) + b"}"
    raise ValueError("qualification distribution contains an unsupported JSON value")


def _scope_document(raw: bytes) -> dict[str, Any]:
    document = loads_json_bytes(raw)
    errors = sorted(SCOPE_VALIDATOR.iter_errors(document),
                    key=lambda error: list(error.absolute_path))
    if errors:
        raise ValueError("invalid qualification scope: " + "; ".join(error.message for error in errors))
    return document


def load_scope(path: Path) -> tuple[dict[str, Any], bytes, str]:
    raw, digest = read_regular(path, max_bytes=MAX_SCOPE_BYTES)
    return _scope_document(raw), raw, digest


def _verified_envelope(bundle: Path, expected: dict[str, Any], public: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    result = verify(bundle, expected["envelopeSha256"])
    if result["privateRunRef"] != expected or result["publicRunRef"] != public:
        raise ValueError(f"qualification runRef differs from finalized bundle: {expected['runId']}")
    raw, digest = read_regular(bundle / "envelope.json", max_bytes=4 * 1024 * 1024)
    if digest != expected["envelopeSha256"]:
        raise ValueError(f"qualification envelope changed after verification: {expected['runId']}")
    return loads_json_bytes(raw), result


def _artifact_bytes(bundle: Path, envelope: dict[str, Any], role: str) -> tuple[dict[str, Any], bytes]:
    matches = [artifact for artifact in envelope["artifacts"]
               if artifact["role"] == role and artifact["requirement"] == "required"]
    if len(matches) != 1:
        raise ValueError(f"distribution run requires exactly one required {role}")
    artifact = matches[0]
    location = artifact["location"]
    if location["kind"] != "bundle":
        raise ValueError(f"distribution {role} must be retained in its bundle")
    path = bundle / logical_path(location["path"])
    raw, digest = read_regular(path, max_bytes=64 * 1024 * 1024)
    if len(raw) != artifact["bytes"] or digest != artifact["sha256"]:
        raise ValueError(f"distribution {role} changed after bundle verification")
    return artifact, raw


def validate_command_context(bundle: Path, envelope: dict[str, Any]) -> dict[str, Any]:
    artifacts = [artifact for artifact in envelope["artifacts"]
                 if artifact["artifactId"] == "command-context"]
    if len(artifacts) != 1:
        raise ValueError("qualification run requires one command-context artifact")
    artifact = artifacts[0]
    if (artifact["role"] != "diagnostic" or artifact["requirement"] != "required"
            or artifact["visibility"] != "private" or artifact["location"]["kind"] != "bundle"):
        raise ValueError("command-context must be a required private diagnostic artifact")
    raw, digest = read_regular(bundle / logical_path(artifact["location"]["path"]),
                               max_bytes=1024 * 1024)
    if len(raw) != artifact["bytes"] or digest != artifact["sha256"]:
        raise ValueError("command-context identity differs from envelope")
    context = loads_json_bytes(raw)
    errors = sorted(COMMAND_CONTEXT_VALIDATOR.iter_errors(context),
                    key=lambda error: list(error.absolute_path))
    if errors:
        raise ValueError("invalid command-context: " + "; ".join(error.message for error in errors))
    if len(envelope["commands"]) != 1:
        raise ValueError("E2 qualification run must record exactly one registered command")
    command = envelope["commands"][0]
    recorded = context["command"]
    selected = context["registry"]["selectedEntry"]
    registry_raw = context["registry"]["rawUtf8"].encode("utf-8")
    if hashlib.sha256(registry_raw).hexdigest() != context["registry"]["sha256"]:
        raise ValueError("command-context raw registry differs from its digest")
    registry = parse_registry(registry_raw)
    if select_command(registry, command["commandId"]) != selected:
        raise ValueError("command-context selected entry differs from raw registry")
    if (recorded["commandId"] != command["commandId"] or recorded["argv"] != command["argv"]
            or recorded["cwd"] != command["cwd"]):
        raise ValueError("command-context differs from E1 command record")
    if (selected.get("commandId") != command["commandId"]
            or selected.get("tierId") != command["tierId"]
            or selected.get("requirement") != command["requirement"]):
        raise ValueError("command-context selected registry entry differs from E1 command")
    prefix = selected.get("argvPrefix")
    if (type(prefix) is not list or command["argv"][:len(prefix)] != prefix
            or (selected.get("argvLength") is not None
                and selected["argvLength"] != len(command["argv"]))
            or (selected.get("requiredCwd") is not None
                and selected["requiredCwd"] != command["cwd"])):
        raise ValueError("command-context argv/cwd differs from selected registry entry")
    cwd_component = selected.get("requiredCwdComponentId")
    if cwd_component is not None and not any(
            component["componentId"] == cwd_component for component in envelope["components"]):
        raise ValueError("command-context cwd component is absent from run components")
    environment = recorded["effectiveEnvironment"]
    names = [item["name"] for item in environment]
    if len(names) != len(set(names)):
        raise ValueError("command-context environment names are duplicate")
    effective = {item["name"]: item["value"] for item in environment}
    expected = selected.get("requiredEnvironment", {})
    if type(expected) is not dict or any(effective.get(key) != value for key, value in expected.items()):
        raise ValueError("command-context environment differs from selected registry entry")
    named = selected.get("requiredEnvironmentNames", [])
    if (type(named) is not list or len(named) != len(set(named))
            or any(type(name) is not str or not name or name in expected for name in named)):
        raise ValueError("command-context registry environment names are invalid")
    expected_names = set(expected) | set(named)
    if selected.get("requiredPathPrefix") is not None:
        expected_names.add("PATH_PREFIX")
        if effective.get("PATH_PREFIX") != selected["requiredPathPrefix"]:
            raise ValueError("command-context PATH prefix differs from registry")
    if set(effective) != expected_names:
        raise ValueError("command-context contains a non-allowlisted environment value")
    cwd_environment = selected.get("requiredCwdEnvironmentName")
    if (cwd_environment is not None
            and (cwd_environment not in named
                 or effective.get(cwd_environment) != recorded["cwd"])):
        raise ValueError("command-context cwd differs from its registered environment owner")
    environment_files = recorded["environmentFiles"]
    file_names = [item["name"] for item in environment_files]
    if len(file_names) != len(set(file_names)):
        raise ValueError("command-context environment file names are duplicate")
    expected_files = selected.get("requiredEnvironmentFileSha256", {})
    if (type(expected_files) is not dict or set(file_names) != set(expected_files)
            or any(item["requested"] != effective.get(item["name"])
                   or item["resolution"] != "available"
                   or item["sha256"] != expected_files[item["name"]]
                   for item in environment_files)):
        raise ValueError("command-context environment file identity differs from registry")
    if context["executable"]["requested"] != command["argv"][0]:
        raise ValueError("command-context executable differs from argv")
    owner = context["registry"]["ownerComponentRef"]
    if owner not in envelope["components"]:
        raise ValueError("command registry provenance is absent from run components")
    if selected.get("registryOwnerComponentId", owner["componentId"]) != owner["componentId"]:
        raise ValueError("command registry owner differs from selected entry")
    return context


def _validate_json_schema(document: Any, bundled_name: str, source_name: str) -> None:
    candidates = [ROOT / "schema" / bundled_name,
                  ROOT.parents[1] / "distribution/reference-node" / source_name]
    schema_path = next((path for path in candidates if path.is_file()), None)
    if schema_path is None:
        raise ValueError(f"installed qualification verifier lacks frozen schema: {bundled_name}")
    validator = _DISTRIBUTION_VALIDATORS.get(schema_path)
    if validator is None:
        validator = Draft202012Validator(load_json(schema_path))
        _DISTRIBUTION_VALIDATORS[schema_path] = validator
    errors = sorted(validator.iter_errors(document),
                    key=lambda error: list(error.absolute_path))
    if errors:
        raise ValueError("invalid qualification distribution: " + "; ".join(
            error.message for error in errors))


def _distribution_binding(bundle: Path, envelope: dict[str, Any], selected: dict[str, Any]) -> dict[str, Any]:
    _manifest_artifact, manifest_raw = _artifact_bytes(bundle, envelope, "distribution-manifest")
    _cache_artifact, cache_raw = _artifact_bytes(bundle, envelope, "cache-index")
    manifest = loads_json_bytes(manifest_raw)
    cache = loads_json_bytes(cache_raw)
    _validate_json_schema(manifest, "reference-distribution-manifest-v1.schema.json",
                          "distribution-manifest.schema.json")
    _validate_json_schema(cache, "reference-cache-index-v1.schema.json",
                          "cache-index.schema.json")
    if manifest["catalogSelectionRef"] != selected or cache["catalogSelectionRef"] != selected:
        raise ValueError("qualification distribution selects a different C0 catalog")
    if manifest["profileId"] != cache["profileId"]:
        raise ValueError("qualification distribution profile differs from cache index")
    components = manifest["componentRefs"]
    if (type(components) is not list or not components or len(components) > 64
            or any(type(component) is not dict for component in components)):
        raise ValueError("qualification distribution componentRefs are malformed")
    component_ids = [component.get("componentId") for component in components]
    if any(type(component_id) is not str for component_id in component_ids) or len(component_ids) != len(set(component_ids)):
        raise ValueError("qualification distribution componentRefs are duplicate or malformed")
    for field, identity in (("buildInputs", "inputId"), ("artifacts", "artifactId"),
                            ("runtimeTrees", "treeId")):
        values = [item[identity] for item in manifest[field]]
        if len(values) != len(set(values)):
            raise ValueError(f"qualification distribution has duplicate {field} identity")
    tools = [item["toolId"] for item in manifest["buildProvenance"]["tools"]]
    trees = [item["inputId"] for item in manifest["buildProvenance"]["trees"]]
    if (set(tools) != {"git", "lake", "framework-catalog-bootstrap"}
            or len(tools) != 3
            or not {"typescript-node-modules", "evidence-wheels"} <= set(trees)
            or set(trees) - {"typescript-node-modules", "evidence-wheels", "lean-build-cache"}
            or len(trees) != len(set(trees))):
        raise ValueError("qualification distribution build provenance closure is invalid")
    artifacts = {item["artifactId"]: item for item in manifest["artifacts"]}
    for artifact_id, artifact in artifacts.items():
        if artifact["source"]["id"] != artifact_id:
            raise ValueError("qualification distribution artifact source identity differs")
        libraries = artifact.get("dynamicLibraries", [])
        if (artifact["mode"] == "0755") != bool(libraries):
            raise ValueError("qualification distribution dynamic-library audit is incomplete")
    for tree in manifest["runtimeTrees"]:
        if tree["sourceArtifactId"] not in artifacts:
            raise ValueError("qualification runtime tree source artifact is absent")
    manifest_sha256 = hashlib.sha256(_canonical_framework_json(manifest)).hexdigest()
    if cache["distributionManifestSha256"] != manifest_sha256:
        raise ValueError("qualification cache does not bind canonical distribution manifest")
    entries = {item["artifactId"]: item for item in cache["entries"]}
    if len(entries) != len(cache["entries"]) or set(entries) != set(artifacts):
        raise ValueError("qualification cache artifact closure differs from manifest")
    for artifact_id, entry in entries.items():
        artifact = artifacts[artifact_id]
        if any(entry[field] != artifact[field]
               for field in ("path", "bytes", "sha256", "mode")):
            raise ValueError(f"qualification cache identity differs: {artifact_id}")
    return {
        "profileId": manifest["profileId"],
        "componentRefs": components,
        "distributionManifestSha256": manifest_sha256,
        "cacheIndexSha256": hashlib.sha256(cache_raw).hexdigest(),
    }


def _validate_graph(nodes: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    by_id: dict[str, dict[str, Any]] = {}
    edges = 0
    for node in nodes:
        run_id = node["privateRunRef"]["runId"]
        if node["publicRunRef"]["runId"] != run_id:
            raise ValueError("qualification private/public runRef IDs differ")
        if run_id in by_id:
            raise ValueError(f"duplicate qualification run: {run_id}")
        by_id[run_id] = node
        edges += len(node["dependsOnRunIds"])
    if edges > MAX_EDGES:
        raise ValueError(f"qualification dependency graph exceeds {MAX_EDGES} edges")
    for run_id, node in by_id.items():
        for dependency in node["dependsOnRunIds"]:
            if dependency == run_id:
                raise ValueError(f"qualification run self-dependency: {run_id}")
            if dependency not in by_id:
                raise ValueError(f"qualification dependency is absent: {dependency}")
    visiting: set[str] = set()
    visited: set[str] = set()
    def visit(run_id: str) -> None:
        if run_id in visiting:
            raise ValueError(f"qualification dependency cycle includes: {run_id}")
        if run_id in visited:
            return
        visiting.add(run_id)
        for dependency in by_id[run_id]["dependsOnRunIds"]:
            visit(dependency)
        visiting.remove(run_id)
        visited.add(run_id)
    for run_id in by_id:
        visit(run_id)
    return by_id


def verify_scope(scope: dict[str, Any], store_root: Path,
                 excluded_run_id: str | None = None) -> dict[str, Any]:
    nodes = scope["nodes"]
    if len(nodes) > MAX_NODES:
        raise ValueError(f"qualification scope exceeds {MAX_NODES} nodes")
    by_id = _validate_graph(nodes)
    if excluded_run_id is not None and excluded_run_id in by_id:
        raise ValueError("Q qualification scope cannot include its enclosing run")
    binding_id = scope["distributionBindingRunId"]
    binding_node = by_id.get(binding_id)
    if (binding_node is None or binding_node["phase"] != "distribution"
            or binding_node["evidenceUse"] != "qualification-credit"):
        raise ValueError("distribution-binding run must be a credited distribution node")
    if any(node["phase"] == "distribution"
           and node["evidenceUse"] == "qualification-credit"
           and run_id != binding_id
           for run_id, node in by_id.items()):
        raise ValueError("only the selected D run may receive distribution credit")
    ensure_owner_directory(store_root)
    runs_root = store_root / "runs"
    ensure_owner_directory(runs_root)
    envelopes: dict[str, dict[str, Any]] = {}
    distributions: dict[str, dict[str, Any]] = {}
    bundles: dict[str, Path] = {}
    for run_id, node in by_id.items():
        bundle = runs_root / run_id
        if not bundle.exists():
            raise ValueError(f"qualification bundle is missing: {run_id}")
        envelope, _verification = _verified_envelope(bundle, node["privateRunRef"], node["publicRunRef"])
        if envelope["catalogSelectionRef"] != scope["selectedCatalogRef"]:
            raise ValueError(f"qualification run selects a different C0 catalog: {run_id}")
        if node["evidenceUse"] == "qualification-credit" and envelope["qualification"]["status"] != "qualified":
            raise ValueError(f"credited qualification run is not qualified: {run_id}")
        validate_command_context(bundle, envelope)
        envelopes[run_id] = envelope
        bundles[run_id] = bundle
        if node["phase"] == "distribution":
            if node["distributionRunId"] is not None or node["dependsOnRunIds"]:
                raise ValueError("distribution nodes cannot bind or depend on another run")
            distributions[run_id] = _distribution_binding(bundle, envelope, scope["selectedCatalogRef"])
    credited_commands: dict[str, str] = {}
    commands: list[dict[str, Any]] = []
    tiers: list[dict[str, Any]] = []
    artifact_roles: set[str] = set()
    cleanup: list[dict[str, Any]] = []
    credited_run_refs: list[dict[str, Any]] = []
    selected_distribution_components = {
        json.dumps(component, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        for component in distributions[binding_id]["componentRefs"]
    }
    for run_id, node in by_id.items():
        envelope = envelopes[run_id]
        phase = node["phase"]
        for command in envelope["commands"]:
            expected_phase = COMMAND_PHASES.get(command["commandId"])
            if expected_phase is not None and phase != expected_phase:
                raise ValueError(
                    f"qualification command is assigned to the wrong phase: {command['commandId']}"
                )
        distribution_id = node["distributionRunId"]
        if phase in INSTALLED_PHASES:
            binding = distributions.get(distribution_id)
            if binding is None:
                raise ValueError(f"installed qualification phase lacks an exact D binding: {run_id}")
            if envelope["components"] != binding["componentRefs"]:
                raise ValueError(f"qualification components differ from bound distribution: {run_id}")
            if distribution_id not in node["dependsOnRunIds"]:
                raise ValueError(f"installed qualification phase must depend directly on its D run: {run_id}")
            if (node["evidenceUse"] == "qualification-credit"
                    and distribution_id != binding_id):
                raise ValueError(f"credited installed run uses a different D binding: {run_id}")
        elif phase == "source-gate":
            if distribution_id is not None:
                raise ValueError("source-gate nodes use declared component-subset binding only")
            encoded = {
                json.dumps(component, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
                for component in envelope["components"]
            }
            commands_for_source = [command["commandId"] for command in envelope["commands"]]
            if (not commands_for_source
                    or any(command not in SOURCE_COMMAND_COMPONENTS for command in commands_for_source)):
                raise ValueError(f"source-gate command lacks declared component ownership: {run_id}")
            required_ids = set().union(*(SOURCE_COMMAND_COMPONENTS[command]
                                         for command in commands_for_source))
            actual_ids = {component["componentId"] for component in envelope["components"]}
            if actual_ids != required_ids or not encoded <= selected_distribution_components:
                raise ValueError(f"source-gate components differ from declared D ownership: {run_id}")
        elif phase != "distribution":
            raise ValueError(f"qualification phase has no identity-binding rule: {phase}")
        if phase == "origin" and not any(by_id[item]["phase"] == "distribution" for item in node["dependsOnRunIds"]):
            raise ValueError("origin run must depend on its distribution run")
        if phase == "reproduction" and not any(by_id[item]["phase"] == "origin" for item in node["dependsOnRunIds"]):
            raise ValueError("reproduction run must depend on its origin run")
        if phase == "reproduction":
            origin_refs = {json.dumps(by_id[item]["privateRunRef"], sort_keys=True,
                                      separators=(",", ":"))
                           for item in node["dependsOnRunIds"]
                           if by_id[item]["phase"] == "origin"}
            reproduction_artifacts = [artifact for artifact in envelope["artifacts"]
                if artifact["role"] == "reproduction-input" and artifact["requirement"] == "required"]
            if not reproduction_artifacts:
                raise ValueError("reproduction run lacks a required reproduction-input artifact")
            for artifact in reproduction_artifacts:
                if artifact["location"]["kind"] != "bundle":
                    raise ValueError("reproduction input must be retained in its bundle")
                raw, digest = read_regular(bundles[run_id] / logical_path(artifact["location"]["path"]),
                                           max_bytes=64 * 1024 * 1024)
                if len(raw) != artifact["bytes"] or digest != artifact["sha256"]:
                    raise ValueError("reproduction input changed after bundle verification")
                value = loads_json_bytes(raw)
                try:
                    origin_ref = value["evidenceLinks"]["runRef"]
                except (KeyError, TypeError) as error:
                    raise ValueError("reproduction input lacks its origin runRef") from error
                if json.dumps(origin_ref, sort_keys=True, separators=(",", ":")) not in origin_refs:
                    raise ValueError("reproduction input origin does not match a declared dependency")
        if phase == "reduction":
            reproduction_ids = [item for item in node["dependsOnRunIds"]
                                if by_id[item]["phase"] == "reproduction"]
            if len(reproduction_ids) != 1:
                raise ValueError("reduction run must depend on exactly one reproduction run")
            reduction_inputs = [artifact for artifact in envelope["artifacts"]
                                if artifact["role"] == "reproduction-input"
                                and artifact["requirement"] == "required"]
            reproduction_inputs = [artifact for artifact in envelopes[reproduction_ids[0]]["artifacts"]
                                   if artifact["role"] == "reproduction-input"
                                   and artifact["requirement"] == "required"]
            if (len(reduction_inputs) != 1 or len(reproduction_inputs) != 1
                    or reduction_inputs[0]["sha256"] != reproduction_inputs[0]["sha256"]
                    or reduction_inputs[0]["bytes"] != reproduction_inputs[0]["bytes"]):
                raise ValueError("reduction input differs from its reproduction dependency")
        if phase == "recovery":
            origin_refs = {json.dumps(by_id[item]["privateRunRef"], sort_keys=True,
                                      separators=(",", ":"))
                           for item in node["dependsOnRunIds"]
                           if by_id[item]["phase"] == "origin"}
            if not origin_refs:
                raise ValueError("recovery run must depend on its interrupted origin run")
            receipts = [artifact for artifact in envelope["artifacts"]
                        if artifact["role"] == "recovery-receipt"
                        and artifact["requirement"] == "required"]
            if len(receipts) != 1 or receipts[0]["location"]["kind"] != "bundle":
                raise ValueError("recovery run requires one retained recovery receipt")
            artifact = receipts[0]
            raw, digest = read_regular(
                bundles[run_id] / logical_path(artifact["location"]["path"]),
                max_bytes=16 * 1024 * 1024)
            if len(raw) != artifact["bytes"] or digest != artifact["sha256"]:
                raise ValueError("recovery receipt changed after bundle verification")
            receipt = loads_json_bytes(raw)
            try:
                original_ref = receipt["original"]["runRef"]
            except (KeyError, TypeError) as error:
                raise ValueError("recovery receipt lacks its original runRef") from error
            if json.dumps(original_ref, sort_keys=True, separators=(",", ":")) not in origin_refs:
                raise ValueError("recovery receipt origin does not match a declared dependency")
        if node["evidenceUse"] != "qualification-credit":
            continue
        credited_run_refs.append(node["privateRunRef"])
        for command in envelope["commands"]:
            command_id = command["commandId"]
            if command_id in credited_commands:
                raise ValueError(f"duplicate qualification command credit: {command_id}")
            credited_commands[command_id] = run_id
            commands.append(command)
        tiers.extend(envelope["tiers"])
        artifact_roles.update(
            artifact["role"] for artifact in envelope["artifacts"]
            if artifact["requirement"] == "required"
        )
        cleanup.extend(envelope["outcomes"]["cleanup"])
    binding = distributions[binding_id]
    return {
        "schemaVersion": "mirrors.qualification-scope-verification/v1",
        "status": "verified",
        "scopeId": scope["scopeId"],
        "qualificationClass": scope["qualificationClass"],
        "selectedCatalogRef": scope["selectedCatalogRef"],
        "distributionBindingRunId": binding_id,
        "distributionManifestSha256": binding["distributionManifestSha256"],
        "cacheIndexSha256": binding["cacheIndexSha256"],
        "componentRefs": binding["componentRefs"],
        "commands": commands,
        "tiers": tiers,
        "requiredArtifactRoles": sorted(artifact_roles),
        "cleanup": cleanup,
        "creditedRunRefs": credited_run_refs,
        "verifiedRunCount": len(nodes),
    }


def verify_scope_path(scope_path: Path, store_root: Path) -> dict[str, Any]:
    scope, _raw, _digest = load_scope(scope_path)
    return verify_scope(scope, Path(os.path.abspath(store_root)))


def attached_scope(bundle: Path, envelope: dict[str, Any], store_root: Path) -> dict[str, Any]:
    producer = [result for result in envelope["producerResults"]
                if result["producer"] == SCOPE_PRODUCER
                and result["schemaVersion"] == SCOPE_PRODUCER_SCHEMA]
    if len(producer) != 1:
        raise ValueError("Q bundle requires exactly one qualification-scope producer result")
    artifacts = [artifact for artifact in envelope["artifacts"]
                 if artifact["artifactId"] == producer[0]["artifactId"]]
    if len(artifacts) != 1:
        raise ValueError("qualification-scope artifact does not resolve")
    artifact = artifacts[0]
    if (artifact["role"] != "producer-result" or artifact["visibility"] != "private"
            or artifact["requirement"] != "required" or artifact["location"]["kind"] != "bundle"):
        raise ValueError("qualification-scope artifact must be a required private producer result")
    raw, digest = read_regular(bundle / logical_path(artifact["location"]["path"]),
                               max_bytes=MAX_SCOPE_BYTES)
    if len(raw) != artifact["bytes"] or digest != artifact["sha256"]:
        raise ValueError("qualification-scope artifact identity differs from Q envelope")
    return verify_scope(_scope_document(raw), store_root, envelope["runId"])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scope", type=Path, required=True)
    parser.add_argument("--store", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        result = verify_scope_path(args.scope, args.store)
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as error:
        print(f"qualification scope verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({
        "schemaVersion": result["schemaVersion"],
        "status": result["status"],
        "scopeId": result["scopeId"],
        "qualificationClass": result["qualificationClass"],
        "distributionManifestSha256": result["distributionManifestSha256"],
        "cacheIndexSha256": result["cacheIndexSha256"],
        "verifiedRunCount": result["verifiedRunCount"],
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
