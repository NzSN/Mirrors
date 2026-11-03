#!/usr/bin/env python3
"""Isolated MW-12 final source/C0 candidate preparation. Does not modify checked-in bytes."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / ".golden-build/mainwork-freeze-20261103"
TMP = OUT / "tmp"
PLAN = Path(__file__).resolve().parent
PARENT = "25b62541ca443d5779fccc8d45fd90f64312747e"
HEAD = "3c4a87309cc3a81924660497207d7c295759bdc1"
HISTORICAL = {
    "wsl2": "22596af73d943b2204a2ae3c7bbc39ae9c41ff03442507e0f26b183ac503a88c",
    "base": "ad9d28ae4b3b4eb2a662117b411fc8acc82e24cc82a04d8dfe6e770289c610bc",
    "dirtySource": "59be0488dc9b32c086ac0b66e05459197fe9209e410ceeb47a87cf26f55ba80a",
}
ECMA = ROOT / ".golden-build/mw12-20261103/inputs/companions/MirrorECMA"
GATE = ROOT / ".golden-build/mw12-20261103/inputs/companions/MirrorGate"
C3 = ROOT / ".lake/build/bin/framework_catalog"
C3_SHA = "5a64a5bd40e999b20dd8268f2846c0f5ad5359067db9f014379c150e27d76126"
FAMILIES = {
    "base": {
        "role": "structural-control",
        "selectedForExecution": False,
        "catalog": "catalog/framework-catalog.json",
        "locks": "distribution/reference-node",
    },
    "wsl2": {
        "role": "selected-execution",
        "selectedForExecution": True,
        "profile": "ubuntu-26.04-wsl2-x86_64",
        "catalog": "catalog/framework-catalog-wsl2-26.04.json",
        "locks": "distribution/reference-node-wsl2-26.04",
    },
}
PRESERVE = [
    "catalog/framework-catalog.json",
    "catalog/framework-catalog-wsl2-26.04.json",
    "catalog/framework-catalog.compact.json",
    "catalog/components/mirrors.json",
    "Docs/framework-map.md",
    "distribution/reference-node/component-lock.json",
    "distribution/reference-node/dependency-lock.json",
    "distribution/reference-node/profiles.json",
    "distribution/reference-node-wsl2-26.04/component-lock.json",
    "distribution/reference-node-wsl2-26.04/dependency-lock.json",
    "distribution/reference-node-wsl2-26.04/profiles.json",
    "distribution/reference-node-wsl2-26.04/README.md",
]


def owner_only(path: Path) -> None:
    """Make one candidate directory tree traversable only by its owner."""
    for directory in [path, *path.rglob("*")]:
        if directory.is_dir():
            directory.chmod(0o700)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_record(path: Path, logical: str) -> dict:
    data = path.read_bytes()
    return {"path": logical, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def git(repository: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(repository), *args], check=True, capture_output=True)
    return result.stdout.decode()


def run_logged(name: str, argv: list[str]) -> dict:
    stdout_path = OUT / "receipts" / f"{name}.stdout"
    stderr_path = OUT / "receipts" / f"{name}.stderr"
    environment = os.environ.copy()
    environment["TMPDIR"] = str(TMP)
    result = subprocess.run(argv, cwd=ROOT, env=environment, capture_output=True)
    stdout_path.write_bytes(result.stdout)
    stderr_path.write_bytes(result.stderr)
    return {
        "name": name,
        "argv": argv,
        "exitCode": result.returncode,
        "stdout": file_record(stdout_path, str(stdout_path.relative_to(ROOT))),
        "stderr": file_record(stderr_path, str(stderr_path.relative_to(ROOT))),
    }


def hash_tree(root: Path) -> list[dict]:
    records = []
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        records.append(file_record(path, str(path.relative_to(ROOT))))
    return records


def main() -> int:
    sys.path.insert(0, str(ROOT / "tools/evidence"))
    sys.path.insert(0, str(ROOT / "tools/distribution"))
    from source_policy import is_planning_documentation  # type: ignore
    from command_registry import parse_registry  # type: ignore
    from manifest_check import validate_locks  # type: ignore

    if OUT.exists():
        raise SystemExit(f"refusing to reuse an existing output root: {OUT}")
    TMP.mkdir(parents=True, mode=0o700)
    owner_only(OUT)
    (OUT / "receipts").mkdir(mode=0o700)
    (OUT / "receipts").chmod(0o700)
    os.environ["TMPDIR"] = str(TMP)

    head = git(ROOT, "rev-parse", "HEAD").strip()
    tree = git(ROOT, "rev-parse", "HEAD^{tree}").strip()
    if head != HEAD:
        raise SystemExit(f"HEAD moved before freeze preparation: {head}")
    delta = [line for line in git(ROOT, "diff", "--name-status", f"{PARENT}..{HEAD}").splitlines() if line]
    delta_paths = []
    for line in delta:
        status, path = line.split("\t", 1)
        delta_paths.append({"status": status, "path": path})
        if not is_planning_documentation("mirrors", path):
            raise SystemExit(f"freeze delta is not planning documentation: {path}")
    identical = subprocess.run(
        ["git", "-C", str(ROOT), "diff", "--quiet", PARENT, HEAD, "--", ".",
         ":!CHECKPOINTS.md", ":!Plans/s1-local-no-model-evidence-20261103/README.md"],
        check=False)
    if identical.returncode != 0:
        raise SystemExit("source or contract bytes differ outside the planning delta")
    untracked = [line for line in git(ROOT, "status", "--porcelain=v1", "-uall").splitlines() if line]
    unrelated = [line for line in untracked if "Plans/mainwork-freeze-20261103/" not in line]

    s1_files = {
        "run.log": "59d1b39bc0bf7176fd3b66140debeb1e98b8bcd66e81f9b95b9171c62fd11dba",
        "sandbox-attempt.log": "1eefddfae98692536508a38faf5e90349e201c26fdf20152e534128339ba951a",
        "tmpfs-attempt.log": "88cfa74bfc5c320f8cc32996eb81ae26e3df90103e376c3bed92ea25fbb842db",
        "receipt.json": "8a3b204f8563309751c29bb6d5fa065cea58b85041479a2bca09a1ac4863fe83",
    }
    s1 = {}
    s1_root = ROOT / ".golden-build/s1-local-no-model-20261103"
    for name, expected in s1_files.items():
        record = file_record(s1_root / name, f".golden-build/s1-local-no-model-20261103/{name}")
        record["expectedSha256"] = expected
        record["matchesRecordedHash"] = record["sha256"] == expected
        s1[name] = record
        if not record["matchesRecordedHash"]:
            raise SystemExit(f"S1 evidence hash drifted: {name}")
    terminal = (s1_root / "run.log").read_bytes().splitlines()[-1]
    if terminal != b"ALL LOCAL NON-MODEL GATES GREEN":
        raise SystemExit("S1 terminal line is not green")

    companions = {}
    expected_companions = {
        "MirrorECMA": (ECMA, "9192171fc5f8d8457f8d13ffaafa117222914ec2", "3a48d828710fafdc9076f0b57bf4e089cdd372ee"),
        "MirrorGate": (GATE, "4b379ac0c017e7621c945ebf8c106cd98a6c70d1", "96e7fa4d0ac90c526d7e499f95664f00b1bc3e9b"),
    }
    for name, (path, revision, tree_id) in expected_companions.items():
        status = git(path, "status", "--porcelain=v1")
        observed = git(path, "rev-parse", "HEAD").strip()
        observed_tree = git(path, "rev-parse", "HEAD^{tree}").strip()
        companions[name] = {
            "path": str(path.relative_to(ROOT)),
            "revision": observed,
            "tree": observed_tree,
            "clean": status == "",
        }
        if observed != revision or observed_tree != tree_id or status != "":
            raise SystemExit(f"companion copy drifted: {name}")

    c3 = file_record(C3, ".lake/build/bin/framework_catalog")
    if c3["sha256"] != C3_SHA or c3["bytes"] != 119687824:
        raise SystemExit("C3 framework_catalog identity drifted")
    registry_bytes = (ROOT / "tools/evidence/commands.json").read_bytes()
    registry = parse_registry(registry_bytes)
    pin = json.loads((ROOT / "tools/interop/ecma-runtime-pin.json").read_text())
    if pin["sourceRevision"] != expected_companions["MirrorECMA"][1]:
        raise SystemExit("ECMA runtime pin revision drifted")
    tracer_records = []
    closure = json.loads((ROOT / "Plans/mainwork-mw12-20261103/integration/strace-closure.json").read_text())
    for entry in [{"path": closure["wrapper"], "sha256": closure["wrapperSha256"], "bytes": None}, *closure["dependencies"]]:
        target = Path(entry["path"])
        if not target.is_file():
            raise SystemExit(f"tracer input missing: {entry['path']}")
        observed = file_record(target, str(target))
        if observed["sha256"] != entry["sha256"]:
            raise SystemExit(f"tracer hash drifted: {entry['path']}")
        tracer_records.append(observed)

    preserved_before = {relative: file_record(ROOT / relative, relative) for relative in PRESERVE}
    companion_record = ECMA / "catalog/framework-capabilities.json"
    preserved_before["companions/MirrorECMA/catalog/framework-capabilities.json"] = file_record(
        companion_record, str(companion_record))
    dependency_before = {
        family: file_record(ROOT / spec["locks"] / "dependency-lock.json", spec["locks"] + "/dependency-lock.json")
        for family, spec in FAMILIES.items()
    }

    copied = {}
    for family, spec in FAMILIES.items():
        family_root = OUT / "candidates" / family
        catalog_source = ROOT / spec["catalog"]
        catalog_dest = family_root / spec["catalog"]
        locks_dest = family_root / spec["locks"]
        catalog_dest.parent.mkdir(parents=True, mode=0o700)
        shutil.copy2(catalog_source, catalog_dest)
        shutil.copytree(ROOT / spec["locks"], locks_dest)
        owner_only(family_root)
        owner_only(OUT / "candidates")
        copied[family] = {
            "catalog": file_record(catalog_dest, str(catalog_dest.relative_to(ROOT))),
            "locks": hash_tree(locks_dest),
        }

    commands = []
    refreshed = {}
    for family, spec in FAMILIES.items():
        family_root = OUT / "candidates" / family
        catalog = family_root / spec["catalog"]
        locks = family_root / spec["locks"]
        argv = [
            sys.executable, "tools/distribution/refresh_identity.py",
            "--mirrorecma", str(ECMA), "--mirrorgate", str(GATE),
            "--framework-catalog-bin", str(C3),
            "--catalog", str(catalog), "--locks-root", str(locks),
            "--skip-component-records", "--skip-render",
        ]
        first = run_logged(f"{family}-refresh-1", argv)
        commands.append(first)
        if first["exitCode"] != 0:
            raise SystemExit(f"{family} refresh failed")
        after_first = hash_tree(family_root)
        second = run_logged(f"{family}-refresh-2", argv)
        commands.append(second)
        if second["exitCode"] != 0:
            raise SystemExit(f"{family} repeat refresh failed")
        after_second = hash_tree(family_root)
        if after_first != after_second:
            raise SystemExit(f"{family} candidate bytes changed on the repeat refresh")
        if (OUT / "receipts" / f"{family}-refresh-1.stdout").read_bytes() != (
                OUT / "receipts" / f"{family}-refresh-2.stdout").read_bytes():
            raise SystemExit(f"{family} refresh stdout is not stable")
        line = (OUT / "receipts" / f"{family}-refresh-1.stdout").read_text().strip()
        prefix = "IDENTITY REFRESH GREEN catalogSha256="
        if not line.startswith(prefix):
            raise SystemExit(f"{family} refresh did not report a selection digest")
        selection = line[len(prefix):]
        if selection in HISTORICAL.values():
            raise SystemExit(f"{family} reused a historical dirty-snapshot digest")
        catalog_doc = json.loads(catalog.read_text())
        mirrors = next(entry for entry in catalog_doc["components"]
            if entry["componentRef"]["componentId"] == "mirrors")
        reference = mirrors["componentRef"]
        if reference["revision"] != HEAD or reference.get("dirty") or "dirtyContent" in reference:
            raise SystemExit(f"{family} Mirrors ref is not the clean freeze revision")
        if mirrors["product"]["version"] != "0.2.0-rc.6":
            raise SystemExit(f"{family} does not declare 0.2.0-rc.6")
        for component_id, expected in (
            ("mirrorecma", expected_companions["MirrorECMA"][1]),
            ("mirrorgate", expected_companions["MirrorGate"][1]),
        ):
            found = next(entry["componentRef"] for entry in catalog_doc["components"]
                if entry["componentRef"]["componentId"] == component_id)
            if found["revision"] != expected or found.get("dirty") or "dirtyContent" in found:
                raise SystemExit(f"{family} {component_id} ref is not the selected clean revision")
        dependency = locks / "dependency-lock.json"
        if sha256_file(dependency) != dependency_before[family]["sha256"]:
            raise SystemExit(f"{family} dependency lock bytes changed")
        for fixture_name in (
            "fixtures/distribution-manifest.checked-replay-local.valid.json",
            "fixtures/distribution-manifest.checked-replay-gate.valid.json",
        ):
            fixture = json.loads((locks / fixture_name).read_text())
            for build_input in fixture["buildInputs"]:
                if not build_input["path"].startswith(spec["locks"] + "/"):
                    raise SystemExit(f"{family} fixture input uses an invalid prefix: {build_input['path']}")
        validate_locks(locks, C3, C3_SHA, catalog)
        profiles = json.loads((locks / "profiles.json").read_text())
        refreshed[family] = {
            **spec,
            "catalogSelectionSha256": selection,
            "catalogFile": file_record(catalog, str(catalog.relative_to(ROOT))),
            "distributionId": profiles["distributionId"],
            "candidateFiles": after_second,
        }
        if selection != refreshed[family]["catalogFile"]["sha256"]:
            # digest_json may differ from raw file bytes. Keep both. The printed
            # value is the canonical selection and must still be fresh.
            pass

    snapshots = {}
    for family, spec in FAMILIES.items():
        locks = OUT / "candidates" / family / spec["locks"]
        destination = OUT / "snapshots" / family
        receipt = run_logged(f"{family}-snapshot", [
            sys.executable, "tools/distribution/snapshot_sources.py",
            "--component-lock", str(locks / "component-lock.json"),
            "--out", str(destination),
            "--mirrors", str(ROOT), "--mirrorecma", str(ECMA), "--mirrorgate", str(GATE),
        ])
        commands.append(receipt)
        if receipt["exitCode"] != 0:
            raise SystemExit(f"{family} source snapshot failed")
        index = json.loads((destination / "snapshot-index.json").read_text())
        snapshots[family] = {
            "index": file_record(destination / "snapshot-index.json",
                str((destination / "snapshot-index.json").relative_to(ROOT))),
            "components": [
                {"componentId": entry["componentRef"]["componentId"],
                 "revision": entry["componentRef"]["revision"],
                 "dirty": entry["componentRef"].get("dirty", False),
                 "treeIndexSha256": entry["treeIndexSha256"]}
                for entry in index["components"]
            ],
        }

    preserved_after = {relative: file_record(ROOT / relative, relative) for relative in PRESERVE}
    preserved_after["companions/MirrorECMA/catalog/framework-capabilities.json"] = file_record(
        companion_record, str(companion_record))
    if preserved_after != preserved_before:
        raise SystemExit("checked-in catalog, lock, projection, or companion record bytes changed")
    mirrors_status = git(ROOT, "status", "--porcelain=v1", "-uall")
    dirty_source = [line for line in mirrors_status.splitlines()
        if line and "Plans/" not in line and not line.endswith("CHECKPOINTS.md")]
    if dirty_source:
        raise SystemExit("Mirrors gained a non-planning worktree change")

    manifest = {
        "schemaVersion": "mirrors.mainwork-freeze-20261103/v1",
        "freezeRevision": head,
        "freezeTree": tree,
        "validatedRevision": PARENT,
        "planningDelta": delta_paths,
        "branch": git(ROOT, "rev-parse", "--abbrev-ref", "HEAD").strip(),
        "originMain": git(ROOT, "rev-parse", "origin/main").strip(),
        "companions": companions,
        "families": {family: {
            "role": refreshed[family]["role"],
            "selectedForExecution": refreshed[family]["selectedForExecution"],
            "profile": refreshed[family].get("profile"),
            "catalogSelectionSha256": refreshed[family]["catalogSelectionSha256"],
            "catalogFile": refreshed[family]["catalogFile"],
            "snapshot": snapshots[family],
            "dependencyLock": dependency_before[family],
        } for family in FAMILIES},
        "c3": c3,
        "ecmaRuntimePin": {
            "path": "tools/interop/ecma-runtime-pin.json",
            "sha256": sha256_file(ROOT / "tools/interop/ecma-runtime-pin.json"),
            "sourceRevision": pin["sourceRevision"],
            "sourceTree": pin["sourceTree"],
            "runtimeDigest": pin["runtime"]["digest"],
        },
        "tracer": {"records": tracer_records, "qualificationClaim": False},
        "registry": {
            "path": "tools/evidence/commands.json",
            "sha256": hashlib.sha256(registry_bytes).hexdigest(),
            "commandCount": len(registry["commands"]),
        },
        "s1": {
            "files": s1,
            "terminalLine": terminal.decode(),
            "nativeExclusion": "MIRRORCPP_PREFIX unset; native integer maps and controlled native preparation skipped",
            "liveModelExclusion": "Counter and Async live Apalache tiers self-skipped; local Apalache/TLC excluded by the runner",
            "qualificationTransferred": False,
        },
        "preserved": preserved_after,
        "historicalDirtySnapshotsRejected": HISTORICAL,
        "openGates": [
            "batteries-carrier", "ptrace-namespace-admission", "installed-D-audit",
            "remote-tls-client-windows", "M5", "Q", "release",
        ],
        "acceptance": "prepared for independent Codex review; not accepted",
    }
    manifest_path = PLAN / "freeze-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    intake = {
        "head": head,
        "tree": tree,
        "branch": manifest["branch"],
        "originMain": manifest["originMain"],
        "trackedDiffEmpty": True,
        "planningDelta": delta_paths,
        "untracked": untracked,
        "unrelatedUntracked": unrelated,
        "companions": companions,
        "c3": c3,
        "s1Matches": True,
        "commands": commands,
    }
    (PLAN / "intake.json").write_text(json.dumps(intake, indent=2) + "\n")
    ignored = []
    for family in FAMILIES:
        ignored.extend(refreshed[family]["candidateFiles"])
        ignored.extend(hash_tree(OUT / "snapshots" / family))
    ignored.extend(hash_tree(OUT / "receipts"))
    (OUT / "ignored-artifacts.json").write_text(json.dumps(ignored, indent=2) + "\n")
    print("PREPARE GREEN")
    for family in FAMILIES:
        print(family, refreshed[family]["catalogSelectionSha256"])


if __name__ == "__main__":
    raise SystemExit(main())
