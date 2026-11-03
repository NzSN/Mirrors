"""Verify retained MW-12 evidence; optionally check the current candidate tree."""

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--current-source", action="store_true")
args = parser.parse_args()
phase = Path(__file__).resolve().parent
repo = phase.parents[1]


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_record(path, record):
    assert path.is_file(), str(path)
    assert path.stat().st_size == record["bytes"], str(path)
    assert sha(path) == record["sha256"], str(path)


counts = {}
for name in ("source", "source-correction", "acquisition", "binding"):
    root = phase / name
    inventory = read(root / "inventory.json")
    for item in inventory["files"]:
        candidate = repo / item["path"]
        path = candidate if candidate.is_file() else root / item["path"]
        assert path.resolve().is_relative_to(repo)
        check_record(path, item)
    counts[name] = len(inventory["files"])

command_count = 0
for path in (phase / "integration").glob("*.json"):
    command = read(path)
    if command.get("schemaVersion") != "mirrors.mw12.command/v1":
        continue
    for log in command["logs"]:
        check_record(phase / "integration" / log["path"], log)
    command_count += 1

for name, expected in (("selected-source-initial", 1),
                       ("selected-source-reviewed", 0),
                       ("binding-idempotence-final", 0),
                       ("targeted-lean-build", 0), ("mirror-version", 0),
                       ("stdio-smoke", 0), ("release-unit-final", 0),
                       ("strace-version", 0), ("strace-smoke", 1)):
    assert read(phase / "integration" / (name + ".json"))["exitCode"] == expected, name

old_counts = {}
old = repo / "Plans/mainwork-execution-20261103"
for name in ("source", "admission", "handoff"):
    root = old / name
    items = read(root / "inventory.json")["files"]
    for item in items:
        candidate = repo / item["path"]
        check_record(candidate if candidate.is_file() else root / item["path"], item)
    old_counts[name] = len(items)

inventory_path = phase / "inventory.json"
if inventory_path.exists():
    for item in read(inventory_path)["files"]:
        check_record(phase / item["path"], item)

current = None
if args.current_source:
    sys.path.insert(0, str(repo / "tools/evidence"))
    sys.path.insert(0, str(repo / "tools/distribution"))
    import refresh_identity
    from command_registry import parse_registry
    from manifest_check import digest_json, validate_locks
    sys.path.insert(0, str(repo / "tools/interop"))
    from ecma_runtime import verify_runtime
    for item in read(phase / "integration/targeted-binaries.json")["binaries"]:
        check_record(repo / item["path"], item)
    tracer = read(phase / "integration/strace-closure.json")
    assert sha(Path(tracer["wrapper"])) == tracer["wrapperSha256"]
    for item in tracer["dependencies"]:
        check_record(Path(item["path"]), item)
    verify_runtime((repo / ".golden-build/mw12-20261103/integration-runtime/ecma-runtime").resolve(),
                   (repo / ".golden-build/mw12-20261103/integration-runtime/node").resolve(),
                   repo / "tools/interop/ecma-runtime-pin.json",
                   "9192171fc5f8d8457f8d13ffaafa117222914ec2")
    companions = {item["id"]: item for item in read(phase / "acquisition/inputs.json")["acquired"]
                  if item["id"] in ("MirrorECMA", "MirrorGate")}
    roots = {key: repo / value["path"] for key, value in companions.items()}
    for key, path in roots.items():
        assert subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip() == companions[key]["commit"]
        assert not subprocess.check_output(["git", "-C", str(path), "status", "--porcelain"], text=True).strip()
    refs = refresh_identity.selected_refs(roots["MirrorECMA"], roots["MirrorGate"])
    c3 = repo / ".lake/build/bin/framework_catalog"
    c3_sha = next(item["sha256"] for item in read(phase / "integration/targeted-binaries.json")["binaries"]
                  if item["path"] == ".lake/build/bin/framework_catalog")
    selections = {}
    for name, catalog_name in (("reference-node", "framework-catalog.json"),
                               ("reference-node-wsl2-26.04", "framework-catalog-wsl2-26.04.json")):
        root = repo / "distribution" / name
        catalog_path = repo / "catalog" / catalog_name
        catalog = read(catalog_path)
        assert {entry["componentRef"]["componentId"]: entry["componentRef"]
                for entry in catalog["components"]} == refs
        assert next(entry["product"]["version"] for entry in catalog["components"]
                    if entry["componentRef"]["componentId"] == "mirrors") == "0.2.0-rc.6"
        validate_locks(root, c3, c3_sha, catalog_path)
        original = subprocess.check_output(["git", "show", "HEAD:" + str((root / "dependency-lock.json").relative_to(repo))], cwd=repo)
        assert (root / "dependency-lock.json").read_bytes() == original
        assert catalog["evidenceRefs"] == []
        selections[name] = digest_json(catalog)
    original_registry = parse_registry(subprocess.check_output(["git", "show", "HEAD:tools/evidence/commands.json"], cwd=repo))
    registry = parse_registry((repo / "tools/evidence/commands.json").read_bytes())
    old_entries = {entry["commandId"]: entry for entry in original_registry["commands"]}
    for entry in registry["commands"]:
        previous = old_entries[entry["commandId"]]
        if entry["commandId"] == "mirrors.interop":
            expected = json.loads(json.dumps(previous))
            expected["requiredEnvironment"]["ECMA_REF"] = companions["MirrorECMA"]["commit"]
            assert entry == expected
        elif entry["commandId"] in ("framework.install-diagnostics", "framework.install-diagnostics-gate"):
            assert {key: value for key, value in entry.items() if key != "argvPrefix"} == {
                key: value for key, value in previous.items() if key != "argvPrefix"}
            allowed = set()
            for index, flag in enumerate(previous["argvPrefix"]):
                if flag in ("--prefix", "--framework-catalog-bin", "--framework-catalog-sha256",
                            "--strace", "--strace-sha256", "--hide-root"):
                    allowed.add(index + 1)
            assert len(entry["argvPrefix"]) == len(previous["argvPrefix"])
            assert all(a == b for index, (a, b) in enumerate(zip(entry["argvPrefix"], previous["argvPrefix"]))
                       if index not in allowed)
        else:
            assert entry == previous
    payload = read(phase / "review/reviewed-payload.json")
    for item in payload["trackedFiles"]:
        if not refresh_identity.is_planning_documentation(item["path"]):
            check_record(repo / item["path"], item)
    before = (phase / "checkpoint-before.md").read_bytes()
    marker = before[before.index(b"## 2026-11-03"):].split(b"\n", 1)[0]
    now = (repo / "CHECKPOINTS.md").read_bytes()
    header = before[:before.index(b"## 2026-11-03")]
    assert header + now[now.index(marker):] == before
    assert not subprocess.check_output(["git", "diff", "--cached", "--name-only"], cwd=repo, text=True).strip()
    subprocess.run(["git", "diff", "--check"], cwd=repo, check=True, capture_output=True)
    current = {"selections": selections, "sourceDigest": refs["mirrors"]["dirtyContent"]["digest"],
               "sourceVersion": "0.2.0-rc.6", "fullS1GatePassed": False}

print(json.dumps({"schemaVersion": "mirrors.mw12-verification/v1", "status": "verified-focused-preparation",
                  "workstreamInventoryRecords": counts, "totalWorkstreamRecords": sum(counts.values()),
                  "retainedCommandRecords": command_count, "historicalWorkstreamRecordsPreserved": old_counts,
                  "currentSource": current, "newFrameworkQualification": False}, indent=2))
