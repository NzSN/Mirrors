#!/usr/bin/env python3
"""Offline record/artifact verification. No binaries, backend, or network run."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
TAG = "v0.2.0-rc.5"
COMMIT = "3ee3d9226f6258583fe7266c1737acff5abd1edf"
WINDOWS_GATES = ("fixtures_replay", "diff_cross", "model_interface_spec", "stdio_smoke",
                 "transport_spec", "jobstore_spec", "async_resource_spec", "dpm_sync_spec")


def require(value, message):
    if not value:
        raise ValueError(message)


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def check_file(path, row):
    require(path.is_file() and not path.is_symlink(), f"missing or linked artifact: {path}")
    require(path.stat().st_size == row["bytes"] and sha(path) == row["sha256"],
            f"changed artifact: {path}")


def safe_path(base, name):
    relative = Path(name)
    require(not relative.is_absolute() and ".." not in relative.parts, "unsafe retained path")
    return base / relative


def claims(ledger):
    for stage in ("S3.1", "S3.2", "S3.3", "S3.4", "S3.5", "S3.6", "S3.7", "S3.8", "S3.9",
                  "S5.1"):
        require(ledger["stages"][stage]["state"] == "passed", "missing package/admission gate")
    for stage in ("S5.2", "S5.3", "S5.4"):
        require(ledger["stages"][stage]["state"] == "awaiting-external-input",
                "unearned installation/D credit")
    require(ledger["qualifiedM5Commands"] == 0 and ledger["requiredM5Commands"] == 18,
            "unearned M5 command credit")
    require(ledger["qualifiedM5Tiers"] == 0 and ledger["requiredM5Tiers"] == 16,
            "unearned M5 tier credit")
    require(ledger["completedDAudits"] == 0 and ledger["requiredDAudits"] == 2,
            "unearned D credit")
    require(not ledger["frameworkQualified"] and not ledger["releaseAdmitted"], "unearned qualification")
    require(not ledger["published"] and not ledger["deployed"], "unearned publication/deployment")


def verify_record():
    inventory = read(ROOT / "inventory.json")
    paths = set()
    for row in inventory["files"]:
        require(row["path"] not in paths, "duplicate evidence path")
        paths.add(row["path"])
        check_file(safe_path(ROOT, row["path"]), row)
    actual = {p.relative_to(ROOT).as_posix() for p in ROOT.rglob("*")
              if p.is_file() and "__pycache__" not in p.parts
              and p.name != "inventory.json"}
    require(actual == paths, "evidence inventory membership changed")
    for p in ROOT.glob("*.json"):
        value = read(p)
        if isinstance(value, dict) and value.get("schema") == "mirrors.completion-command/v1":
            check_file(safe_path(ROOT, value["log"]),
                       {"sha256": value["logSha256"], "bytes": value["logBytes"]})
    source = read(ROOT / "source-identity.json")
    require(source["commit"] == source["peeledTagCommit"] == COMMIT
            and source["tagType"] == "tag" and source["status"] == "", "source/tag mismatch")
    final_state = read(ROOT / "final-state.json")
    for entry in final_state["retainedPrivateInputs"]:
        check_file(safe_path(REPO, entry["path"]), entry)
    require((ROOT / "logs/remote-ref-final.log").read_text().strip() == COMMIT + "\trefs/heads/main",
            "remote source/tag observation differs")
    require(read(ROOT / "logs/windows-cleanup-observation.log")["taskOwnedExecutableCount"] == 0,
            "staged Windows executables remain")
    for name in ("release-unit", "linux-build", "linux-archive-smoke", "local-no-model",
                 "s5-c0-refresh-canonical-remotes", "s5-source-snapshot", "windows-build-attempt6",
                 "windows-package-build"):
        require(read(ROOT / (name + ".json"))["exitCode"] == 0, "required command failed: " + name)
    require("ALL LOCAL NON-MODEL GATES GREEN" in (ROOT / "logs/local-no-model.log").read_text(),
            "non-model aggregate lacks pass marker")
    isolated = read(ROOT / "isolated-archive.json")
    require(not isolated["leanVisible"] and not isolated["lakeVisible"]
            and isolated["workingDirectoryEmpty"] and isolated["exitCode"] == 0, "archive smoke not isolated")
    require('VERSION_ID="24.04"' in isolated["osRelease"]
            and "WSL2" in isolated["scope"], "host was relabeled")
    native = read(ROOT / "windows-native.json")
    require(native["state"] == "passed" and native["commit"] == COMMIT
            and native["tag"] == TAG and native["postBuildSourceStable"], "Windows source/build failed")
    require(tuple(g["name"] for g in native["gates"]) == WINDOWS_GATES, "Windows tier set differs")
    for gate in [native["build"], *native["gates"]]:
        require(gate["exitCode"] == 0, "Windows gate failed")
        check_file(ROOT / "windows-logs-attempt6" / Path(gate["log"]).name,
                   {"sha256": gate["logSha256"], "bytes": gate["logBytes"]})
    source_manifest = read(ROOT / "windows-source-manifest.json")
    require(source_manifest["commit"] == COMMIT and len(source_manifest["files"]) == 9367,
            "Windows source manifest differs")
    require(native["sourceFilesVerified"] == len(source_manifest["files"]), "source denominator differs")
    inputs = REPO / ".golden-build/completion-rc5-20261031/windows-input"
    for name, row in source_manifest["archives"].items():
        check_file(inputs / name, row)
    expected = {"source/" + row["path"]: row for row in source_manifest["files"]}
    with tarfile.open(inputs / "mirrors-v0.2.0-rc.5-source.tar.gz") as handle:
        found = set()
        for entry in handle:
            if entry.isdir():
                continue
            require(entry.isfile() and entry.name in expected and entry.name not in found,
                    "unexpected source archive member")
            found.add(entry.name)
            raw = handle.extractfile(entry).read()
            require(len(raw) == expected[entry.name]["bytes"] and
                    hashlib.sha256(raw).hexdigest() == expected[entry.name]["sha256"], "source archive drift")
        require(found == set(expected), "source archive incomplete")
    package_set = read(ROOT / "package-set.json")
    require(package_set["source"]["commit"] == COMMIT and package_set["source"]["tag"] == TAG,
            "package source mismatch")
    require({a["platform"] for a in package_set["artifacts"]} == {"linux-x86_64", "windows-x86_64"},
            "package set incomplete")
    for artifact in package_set["artifacts"]:
        path = safe_path(REPO, artifact["retentionLocation"])
        check_file(path, artifact)
        ext = artifact["externalBuildManifest"]
        extpath = safe_path(REPO, ext["path"])
        check_file(extpath, ext)
        members = {}
        if artifact["platform"] == "linux-x86_64":
            with tarfile.open(path) as handle:
                rows = handle.getmembers()
                require(len(rows) == 6 and all(m.isfile() or m.isdir() for m in rows), "Linux archive shape")
                members = {m.name: handle.extractfile(m).read() for m in rows if m.isfile()}
        else:
            with zipfile.ZipFile(path) as handle:
                require(len(handle.infolist()) == 7 and len(set(handle.namelist())) == 7, "Windows ZIP shape")
                members = {m.filename: handle.read(m) for m in handle.infolist()}
        prefix = "mirrors-" + TAG + "-" + artifact["platform"] + "/"
        names = {prefix + n for n in artifact["members"]}
        require(set(members) == names, "unexpected package members")
        require(members[prefix + "BUILD.json"] == extpath.read_bytes(), "embedded/external manifest differs")
        metadata = json.loads(extpath.read_bytes())
        require(metadata["tag"] == TAG and metadata.get("commit", metadata.get("sourceCommit")) == COMMIT,
                "embedded source identity differs")
        for name, raw in members.items():
            row = artifact["members"][name.removeprefix(prefix)]
            require(len(raw) == row["bytes"] and hashlib.sha256(raw).hexdigest() == row["sha256"],
                    "package member differs")
    catalog = read(ROOT / "s5-c0/framework-catalog.json")
    selection = hashlib.sha256(json.dumps(catalog, sort_keys=True, separators=(",", ":"),
                                         ensure_ascii=False).encode()).hexdigest()
    require(selection == "50b12873ffd6799174efea4c1ee69afdbd2e592370e39b39cc84c9d5fab305a8",
            "C0 selection differs")
    require(all(not c["componentRef"]["dirty"] for c in catalog["components"]), "dirty C0 component")
    snapshot = REPO / ".golden-build/completion-rc5-20261031/qualification/source-snapshot"
    index = read(snapshot / "snapshot-index.json")
    require({c["componentRef"]["componentId"]: c["componentRef"] for c in index["components"]} ==
            {c["componentRef"]["componentId"]: c["componentRef"] for c in catalog["components"]},
            "snapshot/C0 refs differ")
    for component in index["components"]:
        base = snapshot / "sources" / component["componentRef"]["componentId"]
        names = set()
        for row in component["files"]:
            check_file(safe_path(base, row["path"]), row)
            names.add(row["path"])
        require({p.relative_to(base).as_posix() for p in base.rglob("*") if p.is_file()} == names,
                "source snapshot file membership differs")
    carrier = read(ROOT / "s5-batteries-carrier-admission.json")
    require(not carrier["admitted"] and not carrier["pinChanged"], "unearned carrier admission")
    refusal = read(ROOT / "s5-distribution-build-admitted-verifier.json")
    require(refusal["exitCode"] == 1 and "Batteries archive differs from dependency lock" in
            (ROOT / refusal["log"]).read_text(), "carrier refusal not retained")
    ledger = read(ROOT / "stage-ledger.json")
    claims(ledger)
    return package_set, ledger


def negative_controls(package_set, ledger):
    rejected = []
    def refuse(name, action):
        try:
            action()
        except (ValueError, OSError):
            rejected.append(name)
            return
        raise ValueError("negative control accepted: " + name)
    row = package_set["artifacts"][0]
    path = safe_path(REPO, row["retentionLocation"])
    with tempfile.TemporaryDirectory(prefix="rc5-evidence-negative-") as tmp:
        tmp = Path(tmp)
        refuse("missing-archive", lambda: check_file(tmp / "missing", row))
        changed = tmp / "changed-archive"
        shutil.copyfile(path, changed)
        with changed.open("r+b") as stream:
            raw = stream.read(1)
            stream.seek(0)
            stream.write(bytes([raw[0] ^ 1]))
        refuse("same-size-changed-archive", lambda: check_file(changed, row))
    for name, update in (
        ("unearned-D", lambda v: v.update(completedDAudits=2)),
        ("unearned-M5", lambda v: v.update(qualifiedM5Commands=18)),
        ("unearned-framework", lambda v: v.update(frameworkQualified=True)),
        ("unearned-installation", lambda v: v["stages"]["S5.3"].update(state="passed")),
        ("unearned-release", lambda v: v.update(releaseAdmitted=True)),
    ):
        modified = copy.deepcopy(ledger)
        update(modified)
        refuse(name, lambda: claims(modified))
    return rejected


if __name__ == "__main__":
    packages, ledger = verify_record()
    print(json.dumps({"status": "passed", "negativeControlsRejected": negative_controls(packages, ledger),
                      "fullFrameworkQualified": False, "releaseAdmitted": False}, indent=2))
