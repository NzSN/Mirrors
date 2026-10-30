#!/usr/bin/env python3
"""Verify the S3.6 Ubuntu 26.04 WSL2 package acceptance and reconciled package set."""
from __future__ import annotations
import copy, hashlib, json, os, platform, subprocess, sys, tarfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ARCHIVE = ROOT / ".golden-build/completion-20261030/dist-linux/mirrors-v0.2.0-rc.1-linux-x86_64.tar.gz"
MANIFEST = ROOT / ".golden-build/completion-20261030/dist-linux/mirrors-v0.2.0-rc.1-linux-x86_64.build.json"
WIN = ROOT / ".golden-build/completion-20261030/dist-windows/mirrors-v0.2.0-rc.1-windows-x86_64.zip"
EXPECTED = "39623040464f71bcaff5f1b1002f93b1eec6d19e0bbecabc9a141b523d90b60a"

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def load(path: Path):
    return json.loads(path.read_text())

def validate_acceptance(doc, actual_env, actual_libc, archive_sha, archive_mode) -> None:
    if doc.get("schema") != "mirrors.s3.wsl-archive-acceptance/v1":
        raise ValueError("unexpected acceptance schema")
    if doc.get("result") != "passed":
        raise ValueError("acceptance is not passed")
    scope = doc.get("scope", "")
    if scope != "ubuntu-26.04-wsl2-x86_64":
        raise ValueError("scope must be ubuntu-26.04-wsl2-x86_64")
    if "24.04" in scope or scope.endswith("native-linux-x86_64"):
        raise ValueError("cannot relabel the scope")
    host = doc["environment"]
    if host.get("os", {}).get("versionId") != actual_env.get("versionId"):
        raise ValueError("recorded OS version differs from observed OS")
    if "WSL2" not in host.get("kernel", ""):
        raise ValueError("recorded kernel is not the observed WSL2 kernel")
    if host.get("libc") != actual_libc:
        raise ValueError("recorded libc differs from observed libc")
    if host.get("architecture") != "x86_64":
        raise ValueError("unexpected architecture")
    binding = doc["sourceBinding"]
    if binding.get("commit") != "d737aa0886b9d406e391955756922d9d735d7ec1":
        raise ValueError("unexpected source commit")
    if binding.get("tag") != "v0.2.0-rc.1" or binding.get("tagType") != "tag":
        raise ValueError("unexpected tag identity")
    if binding.get("tagPeelsTo") != binding.get("commit"):
        raise ValueError("tag does not peel to the commit")
    if binding.get("tree") != "8d2de2561d25c219e685bb46980080c03d7d1c98":
        raise ValueError("unexpected source tree")
    arch = doc["archive"]
    if arch.get("sha256") != archive_sha or archive_sha != EXPECTED or not arch.get("sha256Matches"):
        raise ValueError("archive hash mismatch")
    if arch.get("bytes") != 72209232:
        raise ValueError("archive byte count mismatch")
    if archive_mode != 0o444 or arch.get("mode") != "0o444":
        raise ValueError("artifact is not read-only")
    isolation = doc["isolation"]
    for key in ("leanAbsent", "lakeAbsent", "sourceLookupDisabled", "artifactReadOnly", "emptyWorkingDirectory"):
        if isolation.get(key) is not True:
            raise ValueError(f"isolation assertion missing: {key}")
    checks = {entry["id"]: entry for entry in doc["checks"]}
    for required in ("archive-and-manifest-sha256", "embedded-external-manifest-identical",
                     "tag-object-and-peel", "isolated-check-archive", "packaged-cli", "elf-requirements"):
        if checks.get(required, {}).get("exit") != 0:
            raise ValueError(f"check did not pass: {required}")
    if checks["packaged-cli"].get("results", {}).get("mirrorVersion") != "v0.2.0-rc.1":
        raise ValueError("packaged version result is wrong")
    if checks["elf-requirements"].get("maxGlibc", {}).get("mirror") != "2.25":
        raise ValueError("ELF requirement record is wrong")
    for forbidden in ("Ubuntu 24.04 runtime acceptance", "native Linux acceptance"):
        if not any(forbidden in item for item in doc.get("notClaimed", [])):
            raise ValueError(f"missing explicit limitation: {forbidden}")

def validate_package_set(doc, acceptance, archive_sha, windows_sha) -> None:
    if doc.get("schema") != "mirrors.s3.package-set/v3":
        raise ValueError("unexpected package-set schema")
    linux = next((a for a in doc["artifacts"] if a["id"] == "linux-x86_64"), None)
    windows = next((a for a in doc["artifacts"] if a["id"] == "windows-x86_64"), None)
    if linux is None or windows is None:
        raise ValueError("package set lacks an artifact row")
    if linux["sha256"] != archive_sha or archive_sha != EXPECTED:
        raise ValueError("package-set Linux hash mismatch")
    if windows["sha256"] != windows_sha:
        raise ValueError("package-set Windows hash mismatch")
    check = linux["validation"]["archiveCheck"]
    if check.get("acceptedForS3_6") is not True or check.get("exit") != 0:
        raise ValueError("Linux archive check is not accepted")
    if check.get("host") != "ubuntu-26.04-wsl2-x86_64":
        raise ValueError("Linux archive check scope is wrong")
    if check.get("leanAndLakeAbsent") is not True or check.get("isolated") is not True:
        raise ValueError("Linux archive check isolation is not recorded")
    if doc["aggregate"]["S3.6"]["state"] != "passed":
        raise ValueError("S3.6 is not passed")
    if doc["aggregate"]["S3.9"]["state"] != "passed":
        raise ValueError("S3.9 is not passed")
    if windows["sourceBinding"].get("state") != "bound":
        raise ValueError("Windows row is not source-bound")
    if "Ubuntu 24.04 runtime acceptance" not in doc.get("notClaimed", []):
        raise ValueError("package set does not preserve the Ubuntu 24.04 limitation")

def run_negative_controls(acceptance, package_set, archive_sha, windows_sha) -> None:
    actual_env = {"versionId": "26.04"}
    controls = []
    def refused(name, fn):
        try:
            fn()
        except Exception:
            controls.append(name)
        else:
            raise SystemExit(f"negative control was accepted: {name}")
    bad = copy.deepcopy(acceptance); bad["scope"] = "ubuntu-24.04-x86_64"
    refused("relabel-as-ubuntu-24.04", lambda: validate_acceptance(bad, actual_env, "glibc 2.43-2ubuntu2.4", archive_sha, 0o444))
    bad = copy.deepcopy(acceptance); bad["scope"] = "native-linux-x86_64"
    refused("relabel-as-native-linux", lambda: validate_acceptance(bad, actual_env, "glibc 2.43-2ubuntu2.4", archive_sha, 0o444))
    bad = copy.deepcopy(acceptance); bad["checks"][3]["exit"] = 1
    refused("failed-check-claimed-pass", lambda: validate_acceptance(bad, actual_env, "glibc 2.43-2ubuntu2.4", archive_sha, 0o444))
    bad = copy.deepcopy(acceptance); bad["archive"]["sha256"] = "0" * 64
    refused("tampered-archive-digest", lambda: validate_acceptance(bad, actual_env, "glibc 2.43-2ubuntu2.4", archive_sha, 0o444))
    bad = copy.deepcopy(acceptance); bad["isolation"]["leanAbsent"] = False
    refused("lean-visible-in-runtime", lambda: validate_acceptance(bad, actual_env, "glibc 2.43-2ubuntu2.4", archive_sha, 0o444))
    bad = copy.deepcopy(package_set); bad["artifacts"] = [a for a in bad["artifacts"] if a["id"] != "windows-x86_64"]
    refused("incomplete-package-set", lambda: validate_package_set(bad, acceptance, archive_sha, windows_sha))
    bad = copy.deepcopy(package_set); bad["artifacts"][0]["validation"]["archiveCheck"]["acceptedForS3_6"] = False
    refused("unaccepted-linux-row", lambda: validate_package_set(bad, acceptance, archive_sha, windows_sha))
    bad = copy.deepcopy(package_set); bad["notClaimed"] = []
    refused("dropped-platform-limitation", lambda: validate_package_set(bad, acceptance, archive_sha, windows_sha))
    return controls

def main() -> int:
    env = load(HERE / "environment.json")
    acceptance = load(HERE / "acceptance.json")
    package_set = load(HERE / "package-set.json")
    if sha(HERE / "environment.json") != acceptance["environment"]["sha256"]:
        raise SystemExit("environment record digest mismatch")
    if sha(HERE / "acceptance.json") != package_set["reconciliation"]["inputs"][3]["sha256"]:
        raise SystemExit("acceptance digest mismatch in package set")
    actual = dict(platform.freedesktop_os_release())
    actual["versionId"] = actual.get("VERSION_ID", "")
    archive_sha = sha(ARCHIVE); windows_sha = sha(WIN)
    manifest = load(MANIFEST)
    validate_acceptance(acceptance, actual, "glibc 2.43-2ubuntu2.4", archive_sha, ARCHIVE.stat().st_mode & 0o777)
    validate_package_set(package_set, acceptance, archive_sha, windows_sha)
    if sha(MANIFEST) != acceptance["archive"]["externalBuildManifest"]["sha256"]:
        raise SystemExit("external manifest digest mismatch")
    if manifest["commit"] != acceptance["sourceBinding"]["commit"] or manifest["tag"] != "v0.2.0-rc.1":
        raise SystemExit("manifest source identity mismatch")
    with tarfile.open(ARCHIVE, "r:gz") as handle:
        embedded = json.loads(handle.extractfile("mirrors-v0.2.0-rc.1-linux-x86_64/BUILD.json").read())
    if embedded != manifest:
        raise SystemExit("embedded and external manifests differ")
    for name in ("archive-source-binding.log", "s3.6-check-archive.log", "packaged-cli.log", "elf-requirements.log"):
        if not (HERE / "logs" / name).is_file():
            raise SystemExit(f"missing log: {name}")
    log = (HERE / "logs/s3.6-check-archive.log").read_text()
    if "checkArchiveExit=0" not in log or "39623040464f71bcaff5f1b1002f93b1eec6d19e0bbecabc9a141b523d90b60a" not in log:
        raise SystemExit("check-archive log lacks the accepted exit or digest")
    cli = (HERE / "logs/packaged-cli.log").read_text()
    if "v0.2.0-rc.1" not in cli or "genExit=2" not in cli:
        raise SystemExit("packaged CLI log lacks expected results")
    tag_commit = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "v0.2.0-rc.1^{commit}"], text=True).strip()
    if tag_commit != acceptance["sourceBinding"]["commit"]:
        raise SystemExit("local tag moved")
    controls = run_negative_controls(acceptance, package_set, archive_sha, windows_sha)
    print(json.dumps({"schema": "mirrors.s3.wsl-verifier-result/v1", "result": "verified",
                      "scope": "ubuntu-26.04-wsl2-x86_64", "archiveSha256": archive_sha,
                      "windowsSha256": windows_sha, "controlsRejected": controls,
                      "claim": "S3.6 passed only in the selected WSL2 scope; S3.9 package set complete for review"}, sort_keys=True))
    return 0

if __name__ == "__main__":
    sys.exit(main())
