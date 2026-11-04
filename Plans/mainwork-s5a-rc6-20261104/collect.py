#!/usr/bin/env python3
"""Collect bounded S5-A observations; never grants installation qualification."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FREEZE = ROOT / "Plans/mainwork-freeze-20261103/freeze-manifest.json"
CARRIER_SHA = "73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a"
sys.path.insert(0, str(ROOT / "tools/distribution"))
from build import verify_running_builder, verify_source_snapshots
from install import filesystem_type
from manifest_check import digest_json, validate_locks


def identity(path: Path) -> dict:
    if not path.is_file():
        return {"path": str(path), "present": False}
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return {"path": str(path), "present": True, "bytes": path.stat().st_size,
            "sha256": h.hexdigest()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--search", action="store_true")
    args = parser.parse_args()
    args.out.mkdir(mode=0o700, parents=True, exist_ok=False)
    os.environ["TMPDIR"] = str(args.out.resolve())
    commands = []

    def run(name: str, argv: list[str], *, env=None, timeout=45, stdin=None) -> dict:
        started = datetime.now(timezone.utc).isoformat()
        try:
            p = subprocess.run(argv, input=stdin, capture_output=True, text=True,
                               timeout=timeout, env=env, cwd=ROOT)
            value = {"name": name, "argv": argv, "startedAt": started,
                     "exitCode": p.returncode, "stdout": p.stdout, "stderr": p.stderr}
        except (OSError, subprocess.TimeoutExpired) as error:
            value = {"name": name, "argv": argv, "startedAt": started,
                     "exitCode": None, "error": str(error)}
        log = args.out / f"{name}.json"
        log.write_text(json.dumps(value, indent=2) + "\n")
        commands.append(identity(log))
        return value

    manifest = json.loads(FREEZE.read_text())
    verifier = ROOT / manifest["c3"]["path"]
    verifier_record = identity(verifier)
    if verifier_record.get("sha256") != manifest["c3"]["sha256"]:
        raise ValueError("frozen C3 verifier identity changed")
    locks = []
    for family, spec in manifest["families"].items():
        catalog = ROOT / spec["catalogFile"]["path"]
        lock_root = catalog.parents[1] / "distribution" / (
            "reference-node-wsl2-26.04" if family == "wsl2" else "reference-node")
        snapshot = (ROOT / spec["snapshot"]["index"]["path"]).parent
        assert identity(catalog)["sha256"] == spec["catalogFile"]["sha256"]
        assert digest_json(json.loads(catalog.read_text())) == spec["catalogSelectionSha256"]
        contract = validate_locks(lock_root, verifier, verifier_record["sha256"], catalog)
        verify_source_snapshots(snapshot, contract)
        verify_running_builder(snapshot)
        locks.append({"family": family, "catalog": identity(catalog),
                      "catalogSelectionSha256": spec["catalogSelectionSha256"],
                      "lockRoot": str(lock_root), "locksValidated": True,
                      "snapshotValidated": True, "builderMatchesSnapshot": True,
                      "profiles": {k: v["status"] for k, v in contract["profiles"].items()}})
    packages = json.loads((ROOT / "Plans/mainwork-s3-rc6-20261103/s3-package-set.json").read_text())
    package_records = []
    for expected in [packages["sourceArchive"], packages["linux"]["archive"],
                     packages["windows"]["archive"], packages["windows"]["repeatArchive"]]:
        actual = identity(ROOT / expected["path"])
        assert actual.get("sha256") == expected["sha256"] and actual.get("bytes") == expected["bytes"]
        package_records.append(actual)
    companions = []
    for name, spec in manifest["companions"].items():
        path = ROOT / spec["path"]
        rev = run(name + "-revision", ["git", "-C", str(path), "rev-parse", "HEAD"])
        tree = run(name + "-tree", ["git", "-C", str(path), "rev-parse", "HEAD^{tree}"])
        status = run(name + "-status", ["git", "--no-optional-locks", "-C", str(path), "status", "--porcelain=v1"])
        assert rev["exitCode"] == tree["exitCode"] == status["exitCode"] == 0
        assert rev["stdout"].strip() == spec["revision"] and tree["stdout"].strip() == spec["tree"]
        assert status["stdout"] == ""
        companions.append({"name": name, "revision": spec["revision"], "tree": spec["tree"], "clean": True})
    run("shared-head", ["git", "rev-parse", "HEAD"])
    run("shared-status", ["git", "--no-optional-locks", "status", "--porcelain=v1"])
    run("os-release", ["cat", "/etc/os-release"])
    run("libc", ["ldd", "--version"])
    run("mount", ["findmnt", "-T", str(args.out), "-o", "TARGET,SOURCE,FSTYPE,OPTIONS"])
    run("bwrap-version", ["/usr/bin/bwrap", "--version"])
    run("unshare-probe", ["/usr/bin/unshare", "--user", "--map-root-user", "--net", "/usr/bin/true"])
    run("bwrap-probe", ["/usr/bin/bwrap", "--die-with-parent", "--unshare-net",
        "--ro-bind", "/", "/", "--dev-bind", "/dev", "/dev", "--proc", "/proc", "/usr/bin/true"])
    socket_code = """import json,socket,tempfile\nfrom pathlib import Path\nrows=[]\nwith tempfile.TemporaryDirectory() as d:\n for family,address in [(socket.AF_INET,('127.0.0.1',0)),(socket.AF_UNIX,str(Path(d)/'s'))]:\n  try:\n   with socket.socket(family,socket.SOCK_STREAM) as s: s.bind(address);s.listen(1)\n   rows.append({'family':family.name,'bindListen':True})\n  except OSError as e: rows.append({'family':family.name,'bindListen':False,'errno':e.errno,'error':str(e)})\nprint(json.dumps(rows))\n"""
    sockets = run("socket-probes", [sys.executable, "-c", socket_code])
    tracer_files = []
    for record in manifest["tracer"]["records"]:
        observed = identity(Path(record["path"]))
        observed["matchesFrozen"] = observed.get("sha256") == record["sha256"]
        tracer_files.append(observed)
    tracer = ROOT / ".golden-build/mw12-20261103/integration-runtime/strace-pinned"
    run("strace-version", [str(tracer), "--version"])
    trace = run("strace-probe", [str(tracer), "-f", "-qq", "-o", str(args.out.resolve() / "trace.log"), "/usr/bin/true"])
    search = None
    if args.search:
        roots = [p for p in [ROOT / ".golden-build", Path("/tmp"), Path("/var/tmp"),
                             Path("/home/nzsn/Repos/Mirrors/.golden-build")] if p.exists()]
        candidates = run("carrier-filename-search", ["rg", "--files", "--hidden", "--no-ignore",
            "-g", "*.bundle", "-g", "*73130433*", *map(str, roots)], timeout=60)
        records = [identity(Path(p)) for p in candidates.get("stdout", "").splitlines() if Path(p).is_file()]
        size_hits, errors = [], []
        for base in roots:
            for directory, _, files in os.walk(base, onerror=lambda e: errors.append(str(e)), followlinks=False):
                for name in files:
                    path = Path(directory) / name
                    try:
                        if not path.is_symlink() and path.stat().st_size == 3739542:
                            size_hits.append(identity(path))
                    except OSError as error:
                        errors.append(str(error))
        search = {"roots": list(map(str, roots)), "namedCandidates": records,
                  "exactSizeCandidates": size_hits, "errors": errors,
                  "exactCarrierFound": any(p.get("sha256") == CARRIER_SHA for p in records + size_hits)}
    recorded_carrier = ROOT / f".golden-build/batteries-repin-20261031/artifacts/sha256/{CARRIER_SHA}/batteries-v4.33.0.bundle"
    result = {"schema": "mirrors.s5a-rc6.local-preflight/v1", "observedAt": datetime.now(timezone.utc).isoformat(),
        "claim": "local input and capability observations only", "s5aAccepted": False,
        "freezeRevision": manifest["freezeRevision"], "selectedProfile": "ubuntu-26.04-wsl2-x86_64",
        "host": {"platform": platform.platform(), "uid": os.getuid(),
                 "repositoryFilesystem": filesystem_type(ROOT), "outputFilesystem": filesystem_type(args.out)},
        "verifier": verifier_record, "locks": locks, "packages": package_records, "companions": companions,
        "tracerFiles": tracer_files, "straceProbePassed": trace["exitCode"] == 0,
        "socketProbes": json.loads(sockets["stdout"]) if sockets.get("exitCode") == 0 else sockets,
        "carrier": identity(recorded_carrier), "carrierSearch": search, "commands": commands}
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"output": str(args.out), "s5aAccepted": False,
                      "straceProbePassed": result["straceProbePassed"], "carrierSearch": search}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
