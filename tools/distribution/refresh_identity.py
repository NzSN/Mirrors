#!/usr/bin/env python3
"""Refresh the acyclic private C4 catalog and I2 lock identities."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
MIRRORS = HERE.parents[1]
sys.path.insert(0, str(MIRRORS / "tools/evidence"))
sys.path.insert(0, str(HERE))

from collect import _changed_paths, component_ref  # type: ignore  # noqa: E402
from manifest_check import digest_json, validate_locks  # noqa: E402


def read(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, value: dict[str, Any]) -> None:
    data = (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    temporary = path.with_name(path.name + ".tmp")
    descriptor = temporary.open("xb")
    try:
        descriptor.write(data)
        descriptor.flush()
        os.fsync(descriptor.fileno())
    finally:
        descriptor.close()
    temporary.replace(path)


def exclusions(component_id: str, repository: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for path in _changed_paths(repository):
        if component_id == "mirrors":
            if path in {
                "Docs/framework-map.md",
                "catalog/components/mirrors.json",
                "catalog/framework-catalog.json",
                "catalog/framework-catalog.compact.json",
                "distribution/reference-node/component-lock.json",
                "distribution/reference-node/dependency-lock.json",
                "distribution/reference-node/profiles.json",
                "distribution/reference-node/fixtures/cache-index.checked-replay-local.valid.json",
                "distribution/reference-node/fixtures/distribution-manifest.checked-replay-local.valid.json",
                "distribution/reference-node/fixtures/cache-index.checked-replay-gate.valid.json",
                "distribution/reference-node/fixtures/distribution-manifest.checked-replay-gate.valid.json",
            }:
                result[path] = "evidence-output"
            elif "/__pycache__/" in f"/{path}" or path.endswith(".pyc"):
                result[path] = "build-output"
        elif component_id == "mirrorecma":
            if path.startswith(".work/"):
                result[path] = "pre-existing-unrelated"
            elif path == "catalog/framework-capabilities.json":
                result[path] = "evidence-output"
    return result


def selected_refs(mirrorecma: Path, mirrorgate: Path) -> dict[str, dict[str, Any]]:
    repositories = {"mirrors": MIRRORS, "mirrorecma": mirrorecma, "mirrorgate": mirrorgate}
    return {
        component_id: component_ref(component_id, repository, exclusions(component_id, repository))
        for component_id, repository in repositories.items()
    }


def update_catalogs(refs: dict[str, dict[str, Any]], mirrorecma: Path,
    write_mirrorecma_record: bool = True) -> tuple[dict[str, Any], str]:
    catalog_path = MIRRORS / "catalog/framework-catalog.json"
    catalog = read(catalog_path)
    old_refs = {entry["componentRef"]["componentId"]: entry["componentRef"] for entry in catalog["components"]}
    if old_refs != refs:
        captured = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
        catalog["extensions"]["org.nzsn.snapshot"]["capturedAt"] = captured
    else:
        captured = catalog["extensions"]["org.nzsn.snapshot"]["capturedAt"]
    for entry in catalog["components"]:
        entry["componentRef"] = refs[entry["componentRef"]["componentId"]]
    write(catalog_path, catalog)
    mirrors_record = read(MIRRORS / "catalog/components/mirrors.json")
    mirrors_record["components"][0]["componentRef"] = refs["mirrors"]
    mirrors_record["extensions"]["org.nzsn.snapshot"]["capturedAt"] = captured
    write(MIRRORS / "catalog/components/mirrors.json", mirrors_record)
    if write_mirrorecma_record:
        ecma_path = mirrorecma / "catalog/framework-capabilities.json"
        ecma_record = read(ecma_path)
        ecma_record["components"][0]["componentRef"] = refs["mirrorecma"]
        ecma_record["extensions"]["org.nzsn.snapshot"]["capturedAt"] = captured
        write(ecma_path, ecma_record)
    return catalog, digest_json(catalog)


def update_locks(refs: dict[str, dict[str, Any]], selection_digest: str) -> None:
    root = MIRRORS / "distribution/reference-node"
    selection = {"schemaVersion": "mirrors.framework-catalog/v1", "selectionKind": "sha256", "selectionValue": selection_digest}
    profiles = read(root / "profiles.json")
    profiles["catalogSelectionRef"] = selection
    write(root / "profiles.json", profiles)
    components = read(root / "component-lock.json")
    components["catalogSelectionRef"] = selection
    for entry in components["components"]:
        entry["componentRef"] = refs[entry["componentRef"]["componentId"]]
    write(root / "component-lock.json", components)
    lock_files = {
        "profiles-lock": root / "profiles.json",
        "component-lock": root / "component-lock.json",
        "dependency-lock": root / "dependency-lock.json",
    }
    build_inputs = []
    for input_id, path in lock_files.items():
        raw = path.read_bytes()
        build_inputs.append({"inputId": input_id, "path": f"distribution/reference-node/{path.name}",
            "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})
    fixture = root / "fixtures/distribution-manifest.checked-replay-local.valid.json"
    manifest = read(fixture)
    manifest["catalogSelectionRef"] = selection
    catalog = read(MIRRORS / "catalog/framework-catalog.json")
    local_profile = next(profile for profile in profiles["profiles"]
        if profile["profileId"] == "checked-replay-local")
    local_combination = next(combination for combination in catalog["combinations"]
        if combination["combinationId"] == local_profile["combinationId"])
    manifest["componentRefs"] = [refs[component_id] for component_id in sorted(local_combination["componentIds"])]
    manifest["buildInputs"] = build_inputs
    write(fixture, manifest)
    cache_path = root / "fixtures/cache-index.checked-replay-local.valid.json"
    cache = read(cache_path)
    cache["catalogSelectionRef"] = selection
    cache["distributionManifestSha256"] = digest_json(manifest)
    write(cache_path, cache)
    gate_fixture = root / "fixtures/distribution-manifest.checked-replay-gate.valid.json"
    gate_cache_path = root / "fixtures/cache-index.checked-replay-gate.valid.json"
    if gate_fixture.exists() and gate_cache_path.exists():
        gate_manifest = read(gate_fixture)
        gate_manifest["catalogSelectionRef"] = selection
        gate_manifest["componentRefs"] = [refs[component_id] for component_id in sorted(refs)]
        gate_manifest["buildInputs"] = build_inputs
        write(gate_fixture, gate_manifest)
        gate_cache = read(gate_cache_path)
        gate_cache["catalogSelectionRef"] = selection
        gate_cache["distributionManifestSha256"] = digest_json(gate_manifest)
        write(gate_cache_path, gate_cache)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mirrorecma", type=Path, default=MIRRORS.parent / "MirrorECMA")
    parser.add_argument("--mirrorgate", type=Path, default=MIRRORS.parent / "MirrorGate")
    parser.add_argument("--framework-catalog-bin", type=Path,
        default=MIRRORS / ".lake/build/bin/framework_catalog")
    parser.add_argument("--skip-mirrorecma-record-write", action="store_true",
        help="development snapshots only: leave the component-owned derived record unchanged")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    refs = selected_refs(args.mirrorecma.resolve(), args.mirrorgate.resolve())
    _catalog, selection_digest = update_catalogs(refs, args.mirrorecma.resolve(),
        not args.skip_mirrorecma_record_write)
    update_locks(refs, selection_digest)
    subprocess.run([str(args.framework_catalog_bin), "render", "--catalog",
        str(MIRRORS / "catalog/framework-catalog.json"), "--json-out",
        str(MIRRORS / "catalog/framework-catalog.compact.json"), "--markdown-out",
        str(MIRRORS / "Docs/framework-map.md")], check=True)
    validate_locks(MIRRORS / "distribution/reference-node", args.framework_catalog_bin)
    print(f"IDENTITY REFRESH GREEN catalogSha256={selection_digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
