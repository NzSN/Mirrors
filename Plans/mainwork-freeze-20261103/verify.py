#!/usr/bin/env python3
"""Independent closed check for the MW-12 final source/C0 freeze candidate."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
OUT = ROOT / ".golden-build/mainwork-freeze-20261103"
PARENT = "25b62541ca443d5779fccc8d45fd90f64312747e"
HEAD = "3c4a87309cc3a81924660497207d7c295759bdc1"
HISTORICAL_C0 = {
    "22596af73d943b2204a2ae3c7bbc39ae9c41ff03442507e0f26b183ac503a88c",
    "ad9d28ae4b3b4eb2a662117b411fc8acc82e24cc82a04d8dfe6e770289c610bc",
}
HISTORICAL_DIRTY = "59be0488dc9b32c086ac0b66e05459197fe9209e410ceeb47a87cf26f55ba80a"
sys.path.insert(0, str(ROOT / "tools/evidence"))
sys.path.insert(0, str(ROOT / "tools/distribution"))
from command_registry import parse_registry  # noqa: E402
from manifest_check import digest_json, validate_locks  # noqa: E402
from source_policy import is_planning_documentation  # noqa: E402


class FreezeError(Exception):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git(repository: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(repository), *args], check=True, capture_output=True)
    return result.stdout.decode()


def require_record(record: dict, root: Path = ROOT) -> None:
    path = root / record["path"] if not Path(record["path"]).is_absolute() else Path(record["path"])
    if not path.is_file():
        raise FreezeError(f"missing inventoried file: {record['path']}")
    data = path.read_bytes()
    if len(data) != record["bytes"] or hashlib.sha256(data).hexdigest() != record["sha256"]:
        raise FreezeError(f"stale inventoried file: {record['path']}")


def check_snapshot(index_path: Path, expected_components: list[dict]) -> None:
    index = json.loads(index_path.read_text())
    if [entry["componentRef"]["componentId"] for entry in index["components"]] != [
            entry["componentId"] for entry in expected_components]:
        raise FreezeError("snapshot component order drifted")
    for entry, expected in zip(index["components"], expected_components):
        ref = entry["componentRef"]
        if (ref["componentId"] != expected["componentId"] or ref["revision"] != expected["revision"]
                or ref.get("dirty") or "dirtyContent" in ref):
            raise FreezeError(f"snapshot binding drifted: {expected['componentId']}")
        files = []
        base = index_path.parent / "sources" / ref["componentId"]
        for path in sorted(item for item in base.rglob("*") if item.is_file()):
            raw = path.read_bytes()
            files.append({"path": path.relative_to(base).as_posix(), "bytes": len(raw),
                "sha256": hashlib.sha256(raw).hexdigest(),
                "executable": bool(path.stat().st_mode & 0o100)})
        tree = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        if tree != entry["treeIndexSha256"] or tree != expected["treeIndexSha256"]:
            raise FreezeError(f"snapshot tree index drifted: {ref['componentId']}")


def check_manifest(manifest: dict, *, head: str | None = None) -> None:
    observed_head = head if head is not None else git(ROOT, "rev-parse", "HEAD").strip()
    if manifest["freezeRevision"] != HEAD or observed_head != manifest["freezeRevision"]:
        raise FreezeError("freeze revision is stale or was substituted")
    if manifest["freezeTree"] != git(ROOT, "rev-parse", "HEAD^{tree}").strip():
        raise FreezeError("freeze tree drifted")
    if manifest["validatedRevision"] != PARENT or manifest["originMain"] != HEAD:
        raise FreezeError("validated revision or origin binding drifted")
    delta = [line.split("\t", 1) for line in git(
        ROOT, "diff", "--name-status", f"{PARENT}..{HEAD}").splitlines() if line]
    recorded = [[entry["status"], entry["path"]] for entry in manifest["planningDelta"]]
    if delta != recorded or not delta:
        raise FreezeError("planning delta does not match the validated range")
    for status, path in delta:
        if not is_planning_documentation("mirrors", path):
            raise FreezeError(f"delta path is outside planning documentation: {path}")
    identical = subprocess.run(["git", "-C", str(ROOT), "diff", "--quiet", PARENT, HEAD, "--", ".",
        ":!CHECKPOINTS.md", ":!Plans/s1-local-no-model-evidence-20261103/README.md"], check=False)
    if identical.returncode != 0:
        raise FreezeError("source bytes differ outside the planning delta")
    for name, companion in manifest["companions"].items():
        path = ROOT / companion["path"]
        if git(path, "rev-parse", "HEAD").strip() != companion["revision"]:
            raise FreezeError(f"companion revision drifted: {name}")
        if git(path, "rev-parse", "HEAD^{tree}").strip() != companion["tree"]:
            raise FreezeError(f"companion tree drifted: {name}")
        if git(path, "status", "--porcelain=v1") != "" or not companion["clean"]:
            raise FreezeError(f"companion copy is dirty: {name}")
    require_record(manifest["c3"])
    registry_path = ROOT / manifest["registry"]["path"]
    registry_bytes = registry_path.read_bytes()
    registry = parse_registry(registry_bytes)
    if hashlib.sha256(registry_bytes).hexdigest() != manifest["registry"]["sha256"]:
        raise FreezeError("command registry bytes drifted")
    if len(registry["commands"]) != manifest["registry"]["commandCount"]:
        raise FreezeError("command registry count drifted")
    pin_path = ROOT / manifest["ecmaRuntimePin"]["path"]
    pin = json.loads(pin_path.read_text())
    if (hashlib.sha256(pin_path.read_bytes()).hexdigest() != manifest["ecmaRuntimePin"]["sha256"]
            or pin["sourceRevision"] != manifest["ecmaRuntimePin"]["sourceRevision"]
            or pin["sourceTree"] != manifest["ecmaRuntimePin"]["sourceTree"]
            or pin["runtime"]["digest"] != manifest["ecmaRuntimePin"]["runtimeDigest"]):
        raise FreezeError("ECMA runtime pin drifted")
    for record in manifest["tracer"]["records"]:
        require_record(record)
    for record in manifest["s1"]["files"].values():
        check_s1_record(record)
    if manifest["s1"]["terminalLine"] != "ALL LOCAL NON-MODEL GATES GREEN":
        raise FreezeError("S1 terminal line is not green")
    if manifest["s1"]["qualificationTransferred"] is not False:
        raise FreezeError("planning delta was treated as transferred qualification")
    for relative, record in manifest["preserved"].items():
        path = Path(record["path"]) if Path(record["path"]).is_absolute() else ROOT / record["path"]
        if relative.startswith("companions/"):
            path = Path(record["path"])
        require_record({"path": str(path), "bytes": record["bytes"], "sha256": record["sha256"]})
    if set(manifest["families"]) != {"base", "wsl2"}:
        raise FreezeError("candidate family set drifted")
    if manifest["families"]["wsl2"]["selectedForExecution"] is not True or manifest["families"]["wsl2"]["profile"] != "ubuntu-26.04-wsl2-x86_64":
        raise FreezeError("WSL2 is not the selected execution profile")
    if manifest["families"]["base"]["selectedForExecution"] is not False or manifest["families"]["base"]["role"] != "structural-control":
        raise FreezeError("base is not held as the structural control")
    os.environ["TMPDIR"] = str(OUT / "tmp")
    for family, spec in manifest["families"].items():
        selection = spec["catalogSelectionSha256"]
        if selection in HISTORICAL_C0 or selection == HISTORICAL_DIRTY:
            raise FreezeError(f"{family} reuses a historical dirty-snapshot digest")
        require_record(spec["catalogFile"])
        catalog = json.loads((ROOT / spec["catalogFile"]["path"]).read_text())
        if digest_json(catalog) != selection:
            raise FreezeError(f"{family} canonical C0 selection does not match the catalog")
        mirrors = next(entry for entry in catalog["components"] if entry["componentRef"]["componentId"] == "mirrors")
        if (mirrors["componentRef"]["revision"] != HEAD or mirrors["componentRef"].get("dirty")
                or "dirtyContent" in mirrors["componentRef"] or mirrors["product"]["version"] != "0.2.0-rc.6"):
            raise FreezeError(f"{family} Mirrors source identity is not the clean rc.6 freeze")
        for component_id, companion in (("mirrorecma", "MirrorECMA"), ("mirrorgate", "MirrorGate")):
            ref = next(entry["componentRef"] for entry in catalog["components"]
                if entry["componentRef"]["componentId"] == component_id)
            if ref["revision"] != manifest["companions"][companion]["revision"] or ref.get("dirty"):
                raise FreezeError(f"{family} {component_id} identity drifted")
        locks = ROOT / spec["catalogFile"]["path"].split("/catalog/")[0] / (
            "distribution/reference-node" if family == "base" else "distribution/reference-node-wsl2-26.04")
        dependency = locks / "dependency-lock.json"
        if sha256_file(dependency) != spec["dependencyLock"]["sha256"]:
            raise FreezeError(f"{family} dependency lock was not preserved")
        if sha256_file(ROOT / spec["dependencyLock"]["path"]) != spec["dependencyLock"]["sha256"]:
            raise FreezeError(f"{family} checked-in dependency lock drifted")
        prefix = "distribution/reference-node/" if family == "base" else "distribution/reference-node-wsl2-26.04/"
        for fixture_name in (
            "fixtures/distribution-manifest.checked-replay-local.valid.json",
            "fixtures/distribution-manifest.checked-replay-gate.valid.json",
        ):
            fixture = json.loads((locks / fixture_name).read_text())
            if any(not item["path"].startswith(prefix) for item in fixture["buildInputs"]):
                raise FreezeError(f"{family} fixture lock prefix drifted")
        validate_locks(locks, ROOT / manifest["c3"]["path"], manifest["c3"]["sha256"], ROOT / spec["catalogFile"]["path"])
        require_record(spec["snapshot"]["index"])
        check_snapshot(ROOT / spec["snapshot"]["index"]["path"], spec["snapshot"]["components"])
        check_prior_refreshes(family, spec["catalogSelectionSha256"])
        check_fixed_point(family, locks, ROOT / spec["catalogFile"]["path"])
    check_owner_only()
    if manifest["acceptance"] != "prepared for independent Codex review; not accepted":
        raise FreezeError("manifest claims an acceptance this preparation does not own")


def check_s1_record(record: dict) -> None:
    require_record(record)
    if record["sha256"] != record["expectedSha256"]:
        raise FreezeError("S1 actual sha256 does not equal expectedSha256")
    if record["matchesRecordedHash"] is not True:
        raise FreezeError("S1 evidence hash does not match the published record")


def file_map(root: Path) -> dict[str, str]:
    mapping = {}
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        mapping[path.relative_to(root).as_posix()] = sha256_file(path)
    return mapping


def check_owner_only() -> None:
    required = [
        OUT,
        OUT / "candidates",
        OUT / "candidates" / "base",
        OUT / "candidates" / "wsl2",
        OUT / "candidates" / "base" / "distribution" / "reference-node",
        OUT / "candidates" / "wsl2" / "distribution" / "reference-node-wsl2-26.04",
    ]
    for directory in required:
        mode = directory.stat().st_mode & 0o777
        if mode != 0o700:
            raise FreezeError(f"candidate directory is not owner-only: {directory} mode {mode:04o}")
    for directory in (OUT / "candidates").rglob("*"):
        if directory.is_dir() and (directory.stat().st_mode & 0o777) != 0o700:
            raise FreezeError(f"candidate directory is not owner-only: {directory}")


def check_prior_refreshes(family: str, selection: str) -> None:
    intake = json.loads((PLAN / "intake.json").read_text())
    commands = {entry["name"]: entry for entry in intake["commands"]}
    first = commands[f"{family}-refresh-1"]
    second = commands[f"{family}-refresh-2"]
    for entry in (first, second):
        if entry["exitCode"] != 0:
            raise FreezeError(f"retained refresh exit is not zero: {entry['name']}")
        require_record(entry["stdout"])
        require_record(entry["stderr"])
    stdout_1 = (ROOT / first["stdout"]["path"]).read_bytes()
    stdout_2 = (ROOT / second["stdout"]["path"]).read_bytes()
    if stdout_1 != stdout_2:
        raise FreezeError(f"{family} retained refresh receipts are not byte-stable")
    if stdout_1 != f"IDENTITY REFRESH GREEN catalogSha256={selection}\n".encode():
        raise FreezeError(f"{family} retained refresh receipt does not bind the C0 selection")


def check_fixed_point(family: str, locks: Path, catalog: Path) -> None:
    source = locks.parents[1]
    original = file_map(source)
    destination = OUT / "tmp" / "fixed-point" / family
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)
    for directory in [destination, *destination.rglob("*")]:
        if directory.is_dir():
            directory.chmod(0o700)
    receipt_dir = OUT / "tmp" / "fixed-point"
    receipt_dir.mkdir(parents=True, mode=0o700, exist_ok=True)
    argv = [
        sys.executable, "tools/distribution/refresh_identity.py",
        "--mirrorecma", str(ROOT / ".golden-build/mw12-20261103/inputs/companions/MirrorECMA"),
        "--mirrorgate", str(ROOT / ".golden-build/mw12-20261103/inputs/companions/MirrorGate"),
        "--framework-catalog-bin", str(ROOT / ".lake/build/bin/framework_catalog"),
        "--catalog", str(destination / catalog.relative_to(source)),
        "--locks-root", str(destination / locks.relative_to(source)),
        "--skip-component-records", "--skip-render",
    ]
    environment = os.environ.copy()
    environment["TMPDIR"] = str(OUT / "tmp")
    result = subprocess.run(argv, cwd=ROOT, env=environment, capture_output=True)
    (receipt_dir / f"{family}-refresh-3.stdout").write_bytes(result.stdout)
    (receipt_dir / f"{family}-refresh-3.stderr").write_bytes(result.stderr)
    (receipt_dir / f"{family}-refresh-3.exit").write_text(f"{result.returncode}\n")
    if result.returncode != 0:
        raise FreezeError(f"{family} third refresh failed")
    if file_map(destination) != original or file_map(source) != original:
        raise FreezeError(f"{family} candidate bytes changed on the independent refresh")


def negative_control(manifest: dict) -> None:
    stale = json.loads(json.dumps(manifest))
    stale["freezeRevision"] = PARENT
    try:
        check_manifest(stale)
    except FreezeError as error:
        if "freeze revision" not in str(error):
            raise FreezeError(f"stale revision control failed closed for the wrong reason: {error}") from error
    else:
        raise FreezeError("stale source revision was accepted")
    dirty = json.loads(json.dumps(manifest))
    dirty["families"]["wsl2"]["catalogSelectionSha256"] = next(iter(HISTORICAL_C0))
    try:
        check_manifest(dirty)
    except FreezeError as error:
        if "historical dirty-snapshot" not in str(error):
            raise FreezeError(f"historical C0 control failed closed for the wrong reason: {error}") from error
    else:
        raise FreezeError("historical dirty C0 was accepted")
    mismatched = json.loads(json.dumps(next(iter(manifest["s1"]["files"].values()))))
    mismatched["expectedSha256"] = "0" * 64
    mismatched["matchesRecordedHash"] = True
    try:
        check_s1_record(mismatched)
    except FreezeError as error:
        if "does not equal expectedSha256" not in str(error):
            raise FreezeError(f"S1 expected-hash control failed closed for the wrong reason: {error}") from error
    else:
        raise FreezeError("S1 evidence with a substituted expected hash was accepted")


def check_inventory(inventory: dict) -> None:
    entries = inventory["files"]
    paths = [entry["path"] for entry in entries]
    if len(paths) != len(set(paths)):
        raise FreezeError("inventory repeats a path")
    if "Plans/mainwork-freeze-20261103/inventory.json" in paths:
        raise FreezeError("inventory claims a self-hash")
    for entry in entries:
        require_record(entry)
        if entry["class"] not in {"git-payload", "ignored-raw"}:
            raise FreezeError(f"inventory class is unknown: {entry['path']}")
    expected = set(paths)
    actual = set()
    for path in PLAN.rglob("*"):
        if path.is_file() and path.name != "inventory.json":
            actual.add(str(path.relative_to(ROOT)))
    for path in OUT.rglob("*"):
        if path.is_file() and path.relative_to(OUT).parts[0] != "tmp":
            actual.add(str(path.relative_to(ROOT)))
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        raise FreezeError(f"inventory closure mismatch missing={missing[:8]} extra={extra[:8]}")


def main() -> int:
    manifest = json.loads((PLAN / "freeze-manifest.json").read_text())
    inventory_path = PLAN / "inventory.json"
    if not inventory_path.is_file():
        raise FreezeError("inventory is missing")
    inventory = json.loads(inventory_path.read_text())
    check_manifest(manifest)
    negative_control(manifest)
    check_inventory(inventory)
    print("FREEZE VERIFY GREEN")
    print("NEGATIVE CONTROL GREEN")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except FreezeError as error:
        print(f"FREEZE VERIFY FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
