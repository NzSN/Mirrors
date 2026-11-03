#!/usr/bin/env python3
"""Refresh the acyclic private C4 catalog and I2 lock identities."""

from __future__ import annotations

import argparse
import json
import os
import re
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
from source_policy import is_planning_documentation as _is_planning_documentation  # noqa: E402
from manifest_check import digest_json, lock_build_inputs, validate_locks  # noqa: E402


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


EDITOR_CACHE = ".projectile-cache.eld"

# The collector records planning changes in a separate private audit artifact.
# New component refs omit those paths entirely; v1 historical records still read.


def is_planning_documentation(path: str) -> bool:
    return _is_planning_documentation("mirrors", path)


def exclusions(component_id: str, repository: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for path in _changed_paths(repository):
        if path == EDITOR_CACHE:
            result[path] = "pre-existing-unrelated"
            continue
        if component_id == "mirrors":
            if path in {
                "Docs/framework-map.md",
                "catalog/components/mirrors.json",
                "catalog/framework-catalog.json",
                "catalog/framework-catalog.compact.json",
                "catalog/framework-catalog-wsl2-26.04.json",
                "distribution/reference-node/component-lock.json",
                "distribution/reference-node/dependency-lock.json",
                "distribution/reference-node/profiles.json",
                "distribution/reference-node/fixtures/cache-index.checked-replay-local.valid.json",
                "distribution/reference-node/fixtures/distribution-manifest.checked-replay-local.valid.json",
                "distribution/reference-node/fixtures/cache-index.checked-replay-gate.valid.json",
                "distribution/reference-node/fixtures/distribution-manifest.checked-replay-gate.valid.json",
                "distribution/reference-node-wsl2-26.04/README.md",
                "distribution/reference-node-wsl2-26.04/component-lock.json",
                "distribution/reference-node-wsl2-26.04/profiles.json",
                "distribution/reference-node-wsl2-26.04/dependency-lock.json",
                "distribution/reference-node-wsl2-26.04/fixtures/cache-index.checked-replay-local.valid.json",
                "distribution/reference-node-wsl2-26.04/fixtures/distribution-manifest.checked-replay-local.valid.json",
                "distribution/reference-node-wsl2-26.04/fixtures/cache-index.checked-replay-gate.valid.json",
                "distribution/reference-node-wsl2-26.04/fixtures/distribution-manifest.checked-replay-gate.valid.json",
                "Plans/q3-readiness-2026-09-25.md",
            }:
                result[path] = "evidence-output"
            elif is_planning_documentation(path):
                result[path] = "planning-documentation"
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


# MAJOR.MINOR.PATCH[-prerelease], the same rule as release.TAG_PATTERN without
# the leading "v". Historical four-part tags are not product declarations.
_PRODUCT_VERSION = re.compile(
    r"(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){2}"
    r"(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?"
)
_VERSION_DECL = re.compile(r'^def version : String := "([^"]*)"$', re.MULTILINE)


class SourceVersionError(ValueError):
    """The selected Mirrors source has no single usable product declaration."""


def declared_product_version(source: Path) -> str:
    version_file = source / "Shell" / "Version.lean"
    if not version_file.is_file():
        raise SourceVersionError("Mirrors source version declaration is missing")
    try:
        text = version_file.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise SourceVersionError("Mirrors source version declaration is malformed") from error
    matches = _VERSION_DECL.findall(text)
    if not matches:
        raise SourceVersionError("Mirrors source version declaration is missing")
    if len(matches) != 1:
        raise SourceVersionError("Mirrors source version declaration is ambiguous")
    version = matches[0]
    if len(version) > 127 or not _PRODUCT_VERSION.fullmatch(version):
        raise SourceVersionError("Mirrors source version declaration is malformed")
    if "-" in version:
        for identifier in version.split("-", 1)[1].split("."):
            if identifier.isdigit() and len(identifier) > 1 and identifier.startswith("0"):
                raise SourceVersionError("Mirrors source version declaration is malformed")
    return version


def require_mirrors_component(document: dict[str, Any]) -> dict[str, Any]:
    components = document.get("components")
    matches: list[dict[str, Any]] = []
    if isinstance(components, list):
        matches = [
            entry for entry in components
            if isinstance(entry, dict)
            and isinstance(entry.get("componentRef"), dict)
            and entry["componentRef"].get("componentId") == "mirrors"
        ]
    if len(matches) != 1:
        raise ValueError("Mirrors catalog component is missing or ambiguous")
    return matches[0]


def assign_mirrors_source_version(entry: dict[str, Any], version: str) -> dict[str, str]:
    product = entry.get("product")
    name = product.get("name") if isinstance(product, dict) else None
    if not isinstance(product, dict) or not isinstance(name, str) or not name:
        raise ValueError("Mirrors product record is missing")
    product["version"] = version
    return {"name": name, "version": version}


def update_catalogs(refs: dict[str, dict[str, Any]], mirrorecma: Path,
    write_mirrorecma_record: bool = True, catalog_path: Path | None = None,
    write_component_records: bool = True, *,
    mirrors_source: Path | None = None) -> tuple[dict[str, Any], str]:
    source = MIRRORS if mirrors_source is None else mirrors_source
    version = declared_product_version(source)
    catalog_path = catalog_path or (MIRRORS / "catalog/framework-catalog.json")
    catalog = read(catalog_path)
    corrected = assign_mirrors_source_version(require_mirrors_component(catalog), version)
    old_refs = {entry["componentRef"]["componentId"]: entry["componentRef"] for entry in catalog["components"]}
    if old_refs != refs:
        captured = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
        catalog["extensions"]["org.nzsn.snapshot"]["capturedAt"] = captured
    else:
        captured = catalog["extensions"]["org.nzsn.snapshot"]["capturedAt"]
    for entry in catalog["components"]:
        entry["componentRef"] = refs[entry["componentRef"]["componentId"]]
    owned_record = None
    owned_path = MIRRORS / "catalog/components/mirrors.json"
    if write_component_records:
        owned_record = read(owned_path)
        owned = require_mirrors_component(owned_record)
        owned["product"] = dict(corrected)
        owned["componentRef"] = refs["mirrors"]
        owned_record["extensions"]["org.nzsn.snapshot"]["capturedAt"] = captured
    write(catalog_path, catalog)
    if owned_record is not None:
        write(owned_path, owned_record)
    if write_component_records and write_mirrorecma_record:
        ecma_path = mirrorecma / "catalog/framework-capabilities.json"
        ecma_record = read(ecma_path)
        ecma_record["components"][0]["componentRef"] = refs["mirrorecma"]
        ecma_record["extensions"]["org.nzsn.snapshot"]["capturedAt"] = captured
        write(ecma_path, ecma_record)
    return catalog, digest_json(catalog)


def update_locks(refs: dict[str, dict[str, Any]], selection_digest: str,
    root: Path | None = None, catalog_path: Path | None = None) -> None:
    root = root or (MIRRORS / "distribution/reference-node")
    catalog_path = catalog_path or (MIRRORS / "catalog/framework-catalog.json")
    selection = {"schemaVersion": "mirrors.framework-catalog/v1", "selectionKind": "sha256", "selectionValue": selection_digest}
    profiles = read(root / "profiles.json")
    profiles["catalogSelectionRef"] = selection
    write(root / "profiles.json", profiles)
    catalog = read(catalog_path)
    products = {
        entry["componentRef"]["componentId"]: entry["product"]
        for entry in catalog["components"]
    }
    components = read(root / "component-lock.json")
    components["catalogSelectionRef"] = selection
    for entry in components["components"]:
        component_id = entry["componentRef"]["componentId"]
        entry["componentRef"] = refs[component_id]
        entry["product"] = products[component_id]
    write(root / "component-lock.json", components)
    lock_files = {
        "profiles-lock": root / "profiles.json",
        "component-lock": root / "component-lock.json",
        "dependency-lock": root / "dependency-lock.json",
    }
    build_inputs = list(lock_build_inputs(root,
        {input_id: path.read_bytes() for input_id, path in lock_files.items()}).values())
    fixture = root / "fixtures/distribution-manifest.checked-replay-local.valid.json"
    manifest = read(fixture)
    manifest["catalogSelectionRef"] = selection
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
    parser.add_argument("--catalog", type=Path, default=MIRRORS / "catalog/framework-catalog.json",
        help="catalog to refresh; defaults to the checked Ubuntu 24.04 catalog")
    parser.add_argument("--locks-root", type=Path, default=MIRRORS / "distribution/reference-node",
        help="lock root to refresh; defaults to the checked Ubuntu 24.04 root")
    parser.add_argument("--skip-component-records", action="store_true",
        help="variant snapshots only: do not rewrite component-owned catalog records")
    parser.add_argument("--skip-render", action="store_true",
        help="variant snapshots only: skip compact/markdown projection generation")
    parser.add_argument("--skip-mirrorecma-record-write", action="store_true",
        help="development snapshots only: leave the component-owned derived record unchanged")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    refs = selected_refs(args.mirrorecma.resolve(), args.mirrorgate.resolve())
    _catalog, selection_digest = update_catalogs(refs, args.mirrorecma.resolve(),
        not args.skip_mirrorecma_record_write, catalog_path=args.catalog,
        write_component_records=not args.skip_component_records)
    update_locks(refs, selection_digest, root=args.locks_root, catalog_path=args.catalog)
    if not args.skip_render:
        compact = args.catalog.with_name(args.catalog.stem + ".compact.json")
        subprocess.run([str(args.framework_catalog_bin), "render", "--catalog",
            str(args.catalog), "--json-out", str(compact), "--markdown-out",
            str(MIRRORS / "Docs/framework-map.md")], check=True)
    validate_locks(args.locks_root, args.framework_catalog_bin, catalog_path=args.catalog)
    print(f"IDENTITY REFRESH GREEN catalogSha256={selection_digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
