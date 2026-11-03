#!/usr/bin/env python3
"""Bounded read-only check of Phase A artifacts. Does not build or push."""
from __future__ import annotations

import gzip
import hashlib
import json
import subprocess
import sys
import tarfile
from pathlib import Path

FREEZE = "3c4a87309cc3a81924660497207d7c295759bdc1"
FREEZE_TREE = "5c15228e006f4d1b6efaa7e088488bc4b1fe619e"
TAG = "v0.2.0-rc.6"
BATTERIES_REV = "4488d40d070b9700d4d5a6aa342f0d40c31b2a2d"
BATTERIES_TREE = "5a1de86f7997958aaffec998882c29006b688d1e"
REPO = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
TASK = REPO / ".golden-build/mainwork-s3-rc6-20261103"
PREFIX = "mirrors-v0.2.0-rc.6/"

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)


def git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True, check=False)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    blocker = PLAN / "blocker.json"
    intake_preview = json.loads((PLAN / "intake.json").read_text(encoding="utf-8"))
    if blocker.exists():
        check(intake_preview.get("retainedFailure") == "Plans/mainwork-s3-rc6-20261103/blocker.json", "unretained blocker")
        check("20-systemd-ssh-proxy.conf" in blocker.read_text(encoding="utf-8"), "unexpected blocker")
    intake = load(PLAN / "intake.json")
    identity = load(PLAN / "source-identity.json")
    inventory = load(PLAN / "input-inventory.json")
    for record in (intake, identity, inventory):
        check(record.get("published") is False and record.get("deployed") is False, "manifest flags")
    source = REPO / identity["tagRepository"]
    head = git(source, "rev-parse", "HEAD")
    tree = git(source, "rev-parse", "HEAD^{tree}")
    status = git(source, "status", "--porcelain=v1")
    tag_object = git(source, "rev-parse", f"refs/tags/{TAG}")
    tag_type = git(source, "cat-file", "-t", tag_object.stdout.strip())
    peel = git(source, "rev-parse", f"refs/tags/{TAG}^{{commit}}")
    check(head.stdout.strip() == FREEZE, "clone HEAD")
    check(tree.stdout.strip() == FREEZE_TREE, "clone tree")
    check(status.stdout.strip() == "", "clone status")
    check(tag_type.stdout.strip() == "tag", "tag type")
    check(tag_object.stdout.strip() == identity["tagObject"], "tag object")
    check(peel.stdout.strip() == FREEZE, "tag peel")
    shared = git(REPO, "rev-parse", "-q", "--verify", f"refs/tags/{TAG}")
    check(shared.returncode != 0, "shared checkout gained the rc.6 tag")
    before = load(TASK / "shared-before.json")
    tags_now = git(REPO, "show-ref", "--tags").stdout.strip()
    check(tags_now == before["tags"], "shared tag refs differ from the pre-tag snapshot")
    batteries = REPO / identity["batteries"]["offlineClone"]
    check(git(batteries, "rev-parse", "HEAD").stdout.strip() == BATTERIES_REV, "batteries HEAD")
    check(git(batteries, "rev-parse", "HEAD^{tree}").stdout.strip() == BATTERIES_TREE, "batteries tree")
    check(git(batteries, "status", "--porcelain=v1").stdout.strip() == "", "batteries status")
    archive = REPO / identity["archive"]["path"]
    manifest = load(REPO / identity["archive"]["manifest"])
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    check(digest == identity["archive"]["sha256"] == manifest["archiveSha256"], "archive sha256")
    files = []
    with tarfile.open(archive, "r:gz") as handle:
        for member in handle.getmembers():
            if not member.isfile():
                continue
            payload = handle.extractfile(member).read()
            rel = member.name[len(PREFIX):]
            files.append({"path": rel, "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()})
    recorded = {(item["path"], item["bytes"], item["sha256"]) for item in manifest["files"]}
    actual = {(item["path"], item["bytes"], item["sha256"]) for item in files}
    check(recorded == actual, "per-file manifest")
    check(len(files) == manifest["fileCount"] == identity["archive"]["fileCount"], "file count")
    check(identity["remoteTag"]["present"] is False and identity["remoteTag"]["stdout"] == "", "remote tag record")
    windows = load(PLAN / "receipts/windows-observe.json")["parsed"]
    check(windows.get("HOST") and windows.get("STAGE_EXISTS") == "False", "windows stage")
    for name in ("lake", "lean", "gcc", "git", "openssl"):
        check(windows["tools"].get(name, {}).get("present") == "True", f"windows {name}")
    linux = load(PLAN / "receipts/linux-observe.json")["parsed"]
    check("4.33.0" in linux.get("lean", {}).get("stdout", ""), "linux lean")
    check("4.33.0" in linux.get("lake", {}).get("stdout", ""), "linux lake")
    check(identity["releaseIdentity"]["embeddedVersion"] == "0.2.0-rc.6", "embedded version")
    check(identity["batteries"]["substitutesLockedCarrier"] is False, "carrier substitution flag")
    roles = {item["role"] for item in inventory["inputs"]}
    check(roles == {"source-clone", "source-archive", "source-manifest", "batteries-offline", "linux-toolchain", "windows-host"}, "inventory roles")
    # Confirm the gzip member is readable and the tag, not HEAD, was the archive source.
    check(manifest["sourceCommand"][-1] == TAG, "archive source ref")
    check(gzip.decompress(archive.read_bytes())[:8] != b"", "gzip payload")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"PHASE_A_VERIFIED tag={tag_object.stdout.strip()} archive={digest} files={len(files)} batteries={BATTERIES_REV}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
