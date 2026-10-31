"""Assemble exact artifact rows and the bounded stage ledger from actual receipts."""
import hashlib
import json
from pathlib import Path
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
WORK = REPO / ".golden-build/completion-rc5-20261031"
TAG = "v0.2.0-rc.5"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def file_record(path):
    return {"path": str(path.relative_to(REPO)), "bytes": path.stat().st_size,
            "sha256": sha(path.read_bytes())}


def member_record(raw):
    return {"bytes": len(raw), "sha256": sha(raw)}


identity = read(ROOT / "source-identity.json")
native = read(ROOT / "windows-native.json")
assert native["state"] == "passed"
artifacts = []
for platform in ("linux-x86_64", "windows-x86_64"):
    directory = WORK / ("dist-linux" if platform.startswith("linux") else "dist-windows")
    prefix = f"mirrors-{TAG}-{platform}"
    archive = directory / (prefix + (".tar.gz" if platform.startswith("linux") else ".zip"))
    external = directory / (prefix + ".build.json")
    members = {}
    if platform.startswith("linux"):
        with tarfile.open(archive) as handle:
            for entry in handle:
                if entry.isfile():
                    members[entry.name.removeprefix(prefix + "/")] = member_record(handle.extractfile(entry).read())
        gates = read(external)["passedGates"]
        host = "Ubuntu 24.04.3 WSL2 x86_64; glibc 2.39"
        scope = "seven focused release checks and isolated packaged-runtime smoke"
    else:
        with zipfile.ZipFile(archive) as handle:
            for entry in handle.infolist():
                members[entry.filename.removeprefix(prefix + "/")] = member_record(handle.read(entry))
        gates = [g["name"] for g in native["gates"]]
        host = native["os"] + " / " + native["host"]
        scope = "native build, eight selected non-model suites, repeatable packaging, PE import closure"
    row = file_record(archive)
    row["retentionLocation"] = row.pop("path")
    row.update({"platform": platform, "fileName": archive.name, "members": members,
                "externalBuildManifest": file_record(external), "host": host,
                "passedGates": gates, "validationScope": scope,
                "sourceBinding": {"tag": TAG, "commit": identity["commit"], "state": "bound"}})
    artifacts.append(row)
package_set = {"schema": "mirrors.s3.package-set/v2",
               "source": {"tag": TAG, "commit": identity["commit"], "tree": identity["tree"],
                          "tagObject": identity["tagObject"], "tagScope": identity["tagScope"]},
               "artifacts": artifacts,
               "limits": ["Linux runtime acceptance is Ubuntu 24.04.3 WSL2 only",
                          "Windows is the observed Windows 11 host, not the earlier win10 fixture",
                          "No full Windows lake test, M5/D/Q, native M4, release admission, publication, deployment or reboot",
                          "Repeated Windows packaging does not establish reproducible compilation"]}
(ROOT / "package-set.json").write_text(json.dumps(package_set, indent=2) + "\n")
stages = {f"S3.{i}": {"state": "passed", "record": "package-set.json"} for i in range(1, 10)}
stages["S3.6"].update(scope="ubuntu-24.04-wsl2-x86_64", record="isolated-archive.json")
stages["S3.7"].update(record="windows-native.json")
stages["S3.8"].update(record="windows-package.json")
stages["S5.1"] = {"state": "passed", "scope": "actual Ubuntu 24.04.3 WSL2 environment observation",
                   "record": "intake.json", "limit": "no Ubuntu 26.04 admission claim"}
for i in range(2, 5):
    stages[f"S5.{i}"] = {"state": "awaiting-external-input",
                          "reason": "locked Batteries Git bundle is unavailable; available carriers rejected",
                          "record": "s5-batteries-carrier-admission.json"}
stages["S5.2"]["completedSubscope"] = "C0 selection and immutable clean component snapshots frozen"
stages["S5.5"] = {"state": "awaiting-external-input",
                  "reason": "fresh selected remote oracle/backend/certificate and full five-client runtime admission required"}
for i in range(6, 21):
    stages[f"S5.{i}"] = {"state": "not-started", "reason": "exact-candidate D/remote admission is incomplete"}
stages["S5.12"]["supplementalEvidence"] = "eight Windows non-model suites only; full Windows lake test not run"
ledger = {"schema": "mirrors.completion-stage-ledger/v1", "candidate": identity["commit"], "tag": TAG,
          "stages": stages, "c0Selection": "50b12873ffd6799174efea4c1ee69afdbd2e592370e39b39cc84c9d5fab305a8",
          "completedDAudits": 0, "requiredDAudits": 2,
          "qualifiedM5Commands": 0, "requiredM5Commands": 18,
          "qualifiedM5Tiers": 0, "requiredM5Tiers": 16,
          "sourceOnlyAcceptance": "local-no-model.json; not collected/finalized as a qualified M5 producer",
          "frameworkQualified": False, "releaseAdmitted": False, "published": False, "deployed": False,
          "nextRequiredInput": read(ROOT / "s5-batteries-carrier-admission.json")["expected"]}
(ROOT / "stage-ledger.json").write_text(json.dumps(ledger, indent=2) + "\n")
print(json.dumps({"packages": [a["fileName"] for a in artifacts], "S3": "passed",
                  "S5": "awaiting-external-input", "qualifiedM5Commands": "0/18"}, indent=2))
