"""Execute the reviewed MW-12 registry/catalog integration, retaining receipts."""

import argparse
import copy
import hashlib
import json
import subprocess
import sys
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--attempt", required=True)
parser.add_argument("--evidence-root", type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
phase = Path(__file__).resolve().parent
out = args.evidence_root.resolve() if args.evidence_root is not None else phase / "binding"
assert out.resolve().is_relative_to(phase)
out.mkdir(parents=True, exist_ok=True)
before_root = out / (args.attempt + "-before")
before_root.mkdir()
sys.path.insert(0, str(repo / "tools/evidence"))
sys.path.insert(0, str(repo / "tools/distribution"))
import refresh_identity
from command_registry import parse_registry
from manifest_check import digest_json, validate_locks


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    refresh_identity.write(path, value)


acquisition = read(phase / "acquisition/inputs.json")
companions = {item["id"]: item for item in acquisition["acquired"]
              if item["id"] in ("MirrorECMA", "MirrorGate")}
for item in companions.values():
    root = repo / item["path"]
    assert subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip() == item["commit"]
    assert not subprocess.check_output(["git", "-C", str(root), "status", "--porcelain"], text=True).strip()

c3 = repo / ".lake/build/bin/framework_catalog"
c3_identity = next(item for item in read(phase / "integration/targeted-binaries.json")["binaries"]
                   if item["path"] == ".lake/build/bin/framework_catalog")
assert sha(c3) == c3_identity["sha256"]
tracer = read(phase / "integration/strace-closure.json")
assert sha(Path(tracer["wrapper"])) == tracer["wrapperSha256"]
for item in tracer["dependencies"]:
    assert sha(Path(item["path"])) == item["sha256"]
pin = read(phase / "integration/ecma-runtime-pin.json")
assert pin["sourceRevision"] == companions["MirrorECMA"]["commit"]

registry_path = repo / "tools/evidence/commands.json"
original_registry = parse_registry(registry_path.read_bytes())
registry = copy.deepcopy(original_registry)
roots = [repo, repo / companions["MirrorECMA"]["path"], repo / companions["MirrorGate"]["path"]]
candidate = repo / ".golden-build/mw12-20261103/candidate"
for entry in registry["commands"]:
    if entry["commandId"] == "mirrors.interop":
        entry["requiredEnvironment"]["ECMA_REF"] = pin["sourceRevision"]
    if entry["commandId"] in ("framework.install-diagnostics", "framework.install-diagnostics-gate"):
        prefix = entry["argvPrefix"]
        profile = "checked-replay-gate" if entry["commandId"].endswith("-gate") else "checked-replay-local"
        replacements = {
            "--prefix": str(candidate / "install" / profile),
            "--framework-catalog-bin": str(c3),
            "--framework-catalog-sha256": c3_identity["sha256"],
            "--strace": tracer["wrapper"],
            "--strace-sha256": tracer["wrapperSha256"],
        }
        for flag, value in replacements.items():
            prefix[prefix.index(flag) + 1] = value
        indexes = [index + 1 for index, value in enumerate(prefix) if value == "--hide-root"]
        assert len(indexes) == len(roots)
        for index, root in zip(indexes, roots, strict=True):
            prefix[index] = str(root.resolve())
parse_registry((json.dumps(registry) + "\n").encode())

catalog_paths = [repo / "catalog/framework-catalog.json",
                 repo / "catalog/framework-catalog-wsl2-26.04.json"]
owned = repo / "catalog/components/mirrors.json"
pin_path = repo / "tools/interop/ecma-runtime-pin.json"
dependency_paths = [repo / "distribution" / name / "dependency-lock.json"
                    for name in ("reference-node", "reference-node-wsl2-26.04")]
dependency_hashes = {str(p.relative_to(repo)): sha(p) for p in dependency_paths}
for path in [registry_path, pin_path, owned, *catalog_paths]:
    destination = before_root / path.relative_to(repo)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(path.read_bytes())
save(registry_path, registry)
save(pin_path, pin)
source_record = {"recordId": "product-version", "path": "Shell/Version.lean", "recordKind": "source"}
for path in [owned, *catalog_paths]:
    document = read(path)
    component = refresh_identity.require_mirrors_component(document)
    records = component.setdefault("records", [])
    existing = [item for item in records if item["recordId"] == "product-version"]
    if existing:
        assert existing == [source_record]
    else:
        records.append(dict(source_record))
    save(path, document)


def refresh(label, variant):
    command = [sys.executable, str(phase / "run_step.py"), "--tmp-root",
               str(repo / ".golden-build/mw12-20261103/binding-tmp"),
               args.attempt + "-" + label, "--", sys.executable,
               "tools/distribution/refresh_identity.py", "--mirrorecma", str(roots[1]),
               "--mirrorgate", str(roots[2]), "--framework-catalog-bin", str(c3)]
    if variant:
        command += ["--catalog", str(catalog_paths[1]), "--locks-root",
                    str(repo / "distribution/reference-node-wsl2-26.04"),
                    "--skip-component-records", "--skip-render"]
    else:
        command += ["--skip-mirrorecma-record-write"]
    subprocess.run(command, cwd=repo, check=True)


previous = None
convergence = []
stable = False
for iteration in range(1, 5):
    refresh(f"base-refresh-{iteration}", False)
    refresh(f"wsl-refresh-{iteration}", True)
    current = {str(path.relative_to(repo)): sha(path) for path in catalog_paths}
    convergence.append(current)
    if current == previous:
        stable = True
        break
    previous = current
assert stable, "catalog identities did not converge within four refresh pairs"
assert dependency_hashes == {str(p.relative_to(repo)): sha(p) for p in dependency_paths}
selections = []
for root_name, catalog_path in zip(("reference-node", "reference-node-wsl2-26.04"), catalog_paths, strict=True):
    lock_root = repo / "distribution" / root_name
    contract = validate_locks(lock_root, c3, c3_identity["sha256"], catalog_path)
    catalog = read(catalog_path)
    components = {entry["componentRef"]["componentId"]: entry for entry in catalog["components"]}
    assert components["mirrors"]["product"]["version"] == "0.2.0-rc.6"
    assert components["mirrorecma"]["componentRef"]["revision"] == companions["MirrorECMA"]["commit"]
    assert components["mirrorgate"]["componentRef"]["revision"] == companions["MirrorGate"]["commit"]
    assert catalog["evidenceRefs"] == []
    for profile in ("local", "gate"):
        manifest = read(lock_root / f"fixtures/distribution-manifest.checked-replay-{profile}.valid.json")
        for identity in manifest["buildInputs"]:
            assert identity["path"].startswith("distribution/" + root_name + "/")
    selections.append({"lockRoot": str(lock_root.relative_to(repo)), "catalogSha256": digest_json(catalog),
                       "componentRefs": contract["componentRefs"], "structurallyValidated": True})
save(out / (args.attempt + "-assertions.json"), {
    "schemaVersion": "mirrors.mw12.binding-integration/v1", "sourceVersion": "0.2.0-rc.6",
    "selectedExecutionProfile": "ubuntu-26.04-wsl2-x86_64", "selections": selections,
    "catalogsStableAcrossRepeat": True, "refreshConvergence": convergence,
    "dependencyLocksUnchanged": dependency_hashes,
    "registrySha256": sha(registry_path), "runtimePinSha256": sha(pin_path),
    "newQualificationClaim": False,
})
print("MW12 BINDINGS STRUCTURALLY CONSISTENT; no D/model/release qualification")
