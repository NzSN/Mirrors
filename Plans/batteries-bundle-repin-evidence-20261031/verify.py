#!/usr/bin/env python3
"""Verify the retained carrier/pin change without network or model execution."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
import tempfile

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
REVISION = "4488d40d070b9700d4d5a6aa342f0d40c31b2a2d"
TREE = "5a1de86f7997958aaffec998882c29006b688d1e"


def read(path):
    return json.loads(path.read_text())


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def check_file(path, row):
    require(path.is_file() and not path.is_symlink(), "missing or linked input: " + str(path))
    raw = path.read_bytes()
    require(len(raw) == row["bytes"] and sha(raw) == row["sha256"], "input differs: " + str(path))


def canonical(value):
    return sha(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode())


def check_source(source):
    require(source["revision"] == REVISION and source["tree"] == TREE and source["status"] == "",
            "Batteries source identity changed")


def verify():
    inventory = read(ROOT / "inventory.json")
    names = set()
    for row in inventory["files"]:
        path = Path(row["path"])
        require(not path.is_absolute() and ".." not in path.parts and row["path"] not in names,
                "invalid inventory path")
        names.add(row["path"])
        check_file(ROOT / path, row)
    actual = {p.relative_to(ROOT).as_posix() for p in ROOT.rglob("*") if p.is_file()
              and p.name != "inventory.json" and "__pycache__" not in p.parts}
    require(actual == names, "evidence membership changed")
    carrier = read(ROOT / "carrier.json")
    artifact = carrier["artifact"]
    bundle = REPO / artifact["path"]
    check_file(bundle, artifact)
    require(artifact["bytes"] == 3739542 and artifact["sha256"] ==
            "73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a", "carrier pin differs")
    check_source(carrier["source"])
    require(not carrier["sourceRevisionChanged"] and not carrier["generation"]["reproducibleCarrierClaim"],
            "overstated source/carrier claim")
    for row in carrier["checks"]:
        require(row["exitCode"] == 0, "Git carrier check failed")
        require(sha((ROOT / row["log"]).read_bytes()) == row["logSha256"], "Git log changed")
    require("complete history" in (ROOT / "logs/bundle-verify.log").read_text(), "bundle history incomplete")
    for command in ("distribution-unit", "prior-rc5-preservation"):
        row = read(ROOT / (command + ".json"))
        require(row["exitCode"] == 0, "required command failed")
        check_file(ROOT / row["log"], {"bytes": row["logBytes"], "sha256": row["logSha256"]})
    require("Ran 55 tests" in (ROOT / "logs/distribution-unit.log").read_text(), "test denominator differs")
    for name in ("reference-node", "reference-node-wsl2-26.04"):
        rel = Path("distribution") / name
        after = read(ROOT / "after" / rel / "dependency-lock.json")
        before = read(ROOT / "before" / rel / "dependency-lock.json")
        entry = next(x for x in after["dependencies"] if x["artifactId"] == "lean-batteries-source")
        require(entry["version"] == REVISION, "dependency revision changed")
        require(entry["bytes"] == artifact["bytes"] and entry["sha256"] == artifact["sha256"], "profile pin differs")
        expected = copy.deepcopy(before)
        old = next(x for x in expected["dependencies"] if x["artifactId"] == "lean-batteries-source")
        old.update(bytes=artifact["bytes"], sha256=artifact["sha256"])
        require(expected == after, "unrelated dependency changed")
        require((REPO / rel / "dependency-lock.json").read_bytes() ==
                (ROOT / "after" / rel / "dependency-lock.json").read_bytes(), "current profile differs")
        for profile in ("checked-replay-local", "checked-replay-gate"):
            base = ROOT / "after" / rel / "fixtures"
            manifest = read(base / f"distribution-manifest.{profile}.valid.json")
            index = read(base / f"cache-index.{profile}.valid.json")
            require(index["distributionManifestSha256"] == canonical(manifest), "cache/manifest binding differs")
            for identity in manifest["buildInputs"]:
                # Profiles/component locks are unchanged; retained payload binds
                # those exact existing inputs as well as the new dependency lock.
                check_file(ROOT / "after" / identity["path"], identity)
    preview = read(ROOT / "candidate-preview.json")
    require(preview["byteStableRefreshes"] == 2 and not preview["qualificationCredit"], "unearned preview credit")
    require(preview["selection"] == canonical(read(ROOT / "candidate/catalog/framework-catalog.json")),
            "candidate selection differs")
    for path, digest in read(ROOT / "intake.json")["preservedRc5RecordFiles"].items():
        require(sha((REPO / path).read_bytes()) == digest, "historical rc.5 evidence changed")
    return carrier


def controls(carrier):
    results = []
    def reject(name, action):
        try:
            action()
        except (ValueError, OSError):
            results.append(name)
            return
        raise ValueError("control unexpectedly accepted: " + name)
    source = REPO / carrier["artifact"]["path"]
    with tempfile.TemporaryDirectory(prefix="batteries-repin-negative-") as temporary:
        base = Path(temporary)
        reject("missing-carrier", lambda: check_file(base / "absent", carrier["artifact"]))
        damaged = base / "damaged.bundle"
        shutil.copyfile(source, damaged)
        with damaged.open("r+b") as stream:
            byte = stream.read(1)
            stream.seek(0)
            stream.write(bytes([byte[0] ^ 1]))
        reject("same-size-damaged-carrier", lambda: check_file(damaged, carrier["artifact"]))
    reject("old-pin-on-new-bytes", lambda: check_file(source, carrier["previousPin"]))
    changed = dict(carrier["source"], revision="0" * 40)
    reject("changed-source-revision", lambda: check_source(changed))
    return results


if __name__ == "__main__":
    carrier = verify()
    print(json.dumps({"status": "passed", "negativeControlsRejected": controls(carrier),
                      "sourceRevisionChanged": False, "frameworkQualification": False}, indent=2))
