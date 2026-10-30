#!/usr/bin/env python3
"""Verify the S5 WSL2 admission record, additive profile variant and blockers."""
from __future__ import annotations
import copy, hashlib, json, os, platform, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools/distribution"))
sys.path.insert(0, str(ROOT / "tools/evidence"))
import install as installer  # noqa: E402
from manifest_check import digest_json, validate_locks  # noqa: E402
import refresh_identity  # noqa: E402

CATALOG_BIN = ROOT / ".lake/build/bin/framework_catalog"

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def load(path: Path):
    return json.loads(path.read_text())

def validate_environment(doc, actual_version: str) -> None:
    if doc.get("schema") != "mirrors.s5.wsl-environment/v1":
        raise ValueError("unexpected environment schema")
    if doc.get("scopeName") != "ubuntu-26.04-wsl2-x86_64":
        raise ValueError("scope must be ubuntu-26.04-wsl2-x86_64")
    if doc["os"].get("versionId") != actual_version:
        raise ValueError("environment OS differs from the observed host")
    if doc.get("virtualization") != "wsl2" or "WSL2" not in doc.get("kernel", ""):
        raise ValueError("environment is not the observed WSL2 host")
    if not any("Ubuntu 24.04" in item and "not" in item.lower() for item in doc.get("limits", [])):
        raise ValueError("limits must be explicit")

def validate_freeze(doc, recomputed_refs) -> None:
    if doc.get("schema") != "mirrors.s5.candidate-freeze/v1":
        raise ValueError("unexpected freeze schema")
    if doc["candidate"]["tag"]["commit"] != "d737aa0886b9d406e391955756922d9d735d7ec1":
        raise ValueError("unexpected candidate commit")
    if doc["candidate"]["mirrors"]["dirty"] is not True:
        raise ValueError("new candidate input must be marked dirty")
    if doc["candidate"]["mirrors"]["dirtyContent"]["digest"] != recomputed_refs["mirrors"]["dirtyContent"]["digest"]:
        raise ValueError("candidate dirty digest changed")
    if doc["c0"]["base"]["sha256"] != "ecd80f70bd0f2dbe2cc752645a8f4e43e269985a6fa65f9b07d753b7446cc421":
        raise ValueError("base catalog digest changed")
    if doc["c0"]["wsl2Variant"]["platform"] != "ubuntu-26.04":
        raise ValueError("variant platform must be ubuntu-26.04")
    if doc["status"] != "blocked-new-candidate-input":
        raise ValueError("freeze must remain blocked on the new candidate input")
    for row in ("linux", "windows"):
        path = ROOT / doc["artifacts"][row]["file"]
        if sha(path) != doc["artifacts"][row]["sha256"]:
            raise ValueError(f"{row} artifact digest mismatch")

def validate_variant(variant_doc, locks_doc, guard) -> None:
    if variant_doc.get("catalogId") != "mirrors.framework.candidate-2026-10-30-wsl2-26.04":
        raise ValueError("unexpected variant catalog id")
    for profile in variant_doc["distributionProfiles"]:
        if profile["platform"]["osRelease"] != "ubuntu-26.04" or "wsl2" not in profile["profileId"]:
            raise ValueError("variant profile platform/id is wrong")
        if {"dependencyId": "virtualization", "version": "WSL2", "class": "operator-host-prerequisite"} not in profile["dependencies"]:
            raise ValueError("variant profile lacks the WSL2 host prerequisite")
    if {entry["combinationId"] for entry in variant_doc["combinations"]} != {
            "candidate.local-node-checked", "candidate.node-gate", "candidate.fresh-trace"}:
        raise ValueError("combination IDs changed")
    if locks_doc["catalogSelectionRef"]["selectionValue"] != digest_json(variant_doc):
        raise ValueError("variant lock selection differs from the catalog")
    if {entry["profileId"] for entry in locks_doc["profiles"]} != {
            "checked-replay-local", "checked-replay-gate", "fresh-trace"}:
        raise ValueError("variant distribution profile IDs changed")
    if not guard("mirrors.reference-node-checked/ubuntu-26.04-wsl2-x86_64/v1", "wsl2"):
        raise ValueError("WSL2 profile was not admitted on WSL2")
    if guard("mirrors.reference-node-checked/ubuntu-26.04-wsl2-x86_64/v1", None):
        raise ValueError("WSL2 profile was admitted on a non-WSL2 host")
    if not guard("mirrors.reference-node-checked/ubuntu-24.04-x86_64/v1", None):
        raise ValueError("Ubuntu 24.04 profile no longer admits a non-WSL2 host")

def validate_ledger(doc) -> None:
    rows = {row["id"]: row["state"] for row in doc["rows"]}
    if rows.get("S5.1") != "passed":
        raise ValueError("S5.1 is not passed")
    if rows.get("S5.2") != "blocked" or rows.get("S5.3") != "blocked":
        raise ValueError("S5.2/S5.3 must remain blocked")
    for index in range(4, 21):
        if rows.get(f"S5.{index}") not in {"blocked", "not_started"}:
            raise ValueError(f"S5.{index} cannot claim qualification")
    if doc["summary"]["productionTouched"] or doc["summary"]["tagMoved"] or doc["summary"]["publication"]:
        raise ValueError("out-of-scope mutation claimed")

def validate_source_change(doc) -> None:
    if doc.get("kind") != "additive Ubuntu 26.04 WSL2 distribution/catalog profile variant":
        raise ValueError("unexpected source change")
    if not doc["candidateEffect"]["newCandidateInput"]:
        raise ValueError("source change must be a new candidate input")
    if doc["candidateEffect"]["existingTagDisposition"].find("must not be moved") < 0:
        raise ValueError("tag disposition is not explicit")
    if doc["compatibility"]["existingCatalogBytesChanged"] or doc["compatibility"]["existingProfilesJsonBytesChanged"]:
        raise ValueError("base 24.04 inputs changed")
    for row in doc["newFiles"] + doc["modifiedFiles"]:
        if sha(ROOT / row["path"]) != row["sha256"]:
            raise ValueError(f"source change digest mismatch: {row['path']}")

def negative_controls(env, ledger, change, variant, guard) -> list[str]:
    rejected = []
    def refuse(name, fn):
        try:
            fn()
        except Exception:
            rejected.append(name)
        else:
            raise SystemExit(f"negative control accepted: {name}")
    bad = copy.deepcopy(env); bad["scopeName"] = "ubuntu-24.04-x86_64"
    refuse("relabel-env-as-24.04", lambda: validate_environment(bad, "26.04"))
    bad = copy.deepcopy(ledger); bad["rows"][2]["state"] = "passed"
    refuse("claim-S5.3-passed", lambda: validate_ledger(bad))
    bad = copy.deepcopy(change); bad["candidateEffect"]["existingTagDisposition"] = "tag may move"
    refuse("allow-tag-move", lambda: validate_source_change(bad))
    bad = copy.deepcopy(variant)
    bad["distributionProfiles"][0]["platform"]["osRelease"] = "ubuntu-24.04"
    refuse("variant-relabelled-24.04", lambda: validate_variant(bad, load(ROOT / "distribution/reference-node-wsl2-26.04/profiles.json"), guard))
    refuse("wsl2-guard-removed", lambda: validate_variant(variant, load(ROOT / "distribution/reference-node-wsl2-26.04/profiles.json"), lambda _p, _v: True))
    bad = copy.deepcopy(change); bad["newFiles"][0]["sha256"] = "0" * 64
    refuse("tampered-variant-catalog", lambda: validate_source_change(bad))
    return rejected

def main() -> int:
    env = load(HERE / "environment.json")
    freeze = load(HERE / "freeze.json")
    ledger = load(HERE / "s5-ledger.json")
    change = load(HERE / "source-change.json")
    gap = load(HERE / "profile-gap.json")
    actual = platform.freedesktop_os_release()
    validate_environment(env, actual.get("VERSION_ID", ""))
    refs = refresh_identity.selected_refs(Path("/home/lsz/Codebase/MirrorECMA"), Path("/home/lsz/Codebase/MirrorGate"))
    validate_freeze(freeze, refs)
    variant_path = ROOT / "catalog/framework-catalog-wsl2-26.04.json"
    variant = load(variant_path)
    locks = load(ROOT / "distribution/reference-node-wsl2-26.04/profiles.json")
    def guard(profile_id, virtualization):
        try:
            installer.require_profile_host(profile_id, virtualization)
            return True
        except ValueError:
            return False
    validate_variant(variant, locks, guard)
    validate_ledger(ledger)
    validate_source_change(change)
    base = load(ROOT / "catalog/framework-catalog.json")
    if {entry["platform"]["osRelease"] for entry in base["distributionProfiles"]} != {"ubuntu-24.04"}:
        raise SystemExit("base catalog no longer preserves the Ubuntu 24.04 platform")
    base_profiles = {entry["profileId"] for entry in base["distributionProfiles"]}
    if not {"mirrors.reference-node-checked/ubuntu-24.04-x86_64/v1",
            "mirrors.reference-node-gate/ubuntu-24.04-x86_64/v1"} <= base_profiles:
        raise SystemExit("base Ubuntu 24.04 profiles were removed")
    if digest_json(base) != freeze["c0"]["base"]["sha256"]:
        raise SystemExit("base catalog digest differs from the freeze")
    if digest_json(variant) != freeze["c0"]["wsl2Variant"]["sha256"]:
        raise SystemExit("variant catalog digest differs from the freeze")
    validate_locks(ROOT / "distribution/reference-node-wsl2-26.04", CATALOG_BIN, catalog_path=variant_path)
    validate_locks(ROOT / "distribution/reference-node", CATALOG_BIN)
    result = subprocess.run([str(CATALOG_BIN), "validate", str(variant_path)], text=True, capture_output=True)
    if result.returncode != 0:
        raise SystemExit("variant catalog fails framework_catalog validation")
    tag_commit = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "v0.2.0-rc.1^{commit}"], text=True).strip()
    if tag_commit != "d737aa0886b9d406e391955756922d9d735d7ec1":
        raise SystemExit("the local tag moved")
    for log in ("distribution-tests.log", "catalog-validation.log", "refresh-variant-smoke.log", "local-no-model.log"):
        if not (HERE / "logs" / log).is_file():
            raise SystemExit(f"missing log: {log}")
    if "OK" not in (HERE / "logs/distribution-tests.log").read_text():
        raise SystemExit("distribution test log does not report OK")
    if "ALL LOCAL NON-MODEL GATES GREEN" not in (HERE / "logs/local-no-model.log").read_text():
        raise SystemExit("local no-model gate did not pass")
    if gap["baseCatalog"]["platform"] != "ubuntu-24.04":
        raise SystemExit("gap record no longer identifies the 24.04 base")
    win10 = load(HERE / "win10-observation.json")
    if win10["production"]["sha256"] != "8173ddea65f78a88b1a303f8a233dd7113b28e7dc8aefd8916a5add25a3687cc":
        raise SystemExit("production observation hash changed")
    if win10["isolatedOracleListener19131"] != "absent":
        raise SystemExit("a leftover isolated oracle is claimed present")
    if not win10.get("limits"):
        raise SystemExit("win10 observation lacks limits")
    rejected = negative_controls(env, ledger, change, variant, guard)
    print(json.dumps({"schema": "mirrors.s5.wsl-verifier-result/v1", "result": "verified",
        "scope": "ubuntu-26.04-wsl2-x86_64", "s5Complete": False,
        "variantCatalogSha256": digest_json(variant), "baseCatalogSha256": digest_json(base),
        "negativeControlsRejected": rejected,
        "claim": "S5.1 only; S5.2-S5.20 blocked/not started; additive profile variant validated"}, sort_keys=True))
    return 0

if __name__ == "__main__":
    sys.exit(main())
