#!/usr/bin/env python3
"""Phase A only: local rc.6 tag, source archive, offline Batteries, input observation.

Does not build, push, or change the shared checkout's refs.
Refuses to overwrite an existing task output path.
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import gzip
import tempfile
from datetime import datetime, timezone
from pathlib import Path

FREEZE = "3c4a87309cc3a81924660497207d7c295759bdc1"
FREEZE_TREE = "5c15228e006f4d1b6efaa7e088488bc4b1fe619e"
PUBLISHED = "0d95b6ff586c9014b456ed42ebdfbbccdb600701"
TAG = "v0.2.0-rc.6"
VERSION = "0.2.0-rc.6"
BATTERIES_REV = "4488d40d070b9700d4d5a6aa342f0d40c31b2a2d"
BATTERIES_TREE = "5a1de86f7997958aaffec998882c29006b688d1e"
MISSING_CARRIER = "73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a"
DOC_PATHS = {
    "CHECKPOINTS.md",
    "Docs/current-status.md",
    "Plans/mainwork-freeze-20261103/README.md",
    "Plans/mainwork-freeze-20261103/freeze-manifest.json",
    "Plans/mainwork-freeze-20261103/intake.json",
    "Plans/mainwork-freeze-20261103/inventory.json",
    "Plans/mainwork-freeze-20261103/prepare.py",
    "Plans/mainwork-freeze-20261103/report.md",
    "Plans/mainwork-freeze-20261103/result.json",
    "Plans/mainwork-freeze-20261103/review.md",
    "Plans/mainwork-freeze-20261103/review/review.json",
    "Plans/mainwork-freeze-20261103/task.md",
    "Plans/mainwork-freeze-20261103/verify.py",
}

REPO = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
TASK_ROOT = REPO / ".golden-build/mainwork-s3-rc6-20261103"
SOURCE = TASK_ROOT / "source"
BATTERIES = TASK_ROOT / "inputs/batteries"
ARCHIVE_DIR = TASK_ROOT / "archive"
LOG_DIR = TASK_ROOT / "logs"
ARCHIVE = ARCHIVE_DIR / "mirrors-v0.2.0-rc.6-source.tar.gz"
MANIFEST_PATH = ARCHIVE_DIR / "source-manifest.json"
COMMANDS = PLAN / "receipts/commands.jsonl"
OBS_PS1 = PLAN / "windows-observe.ps1"
OWNED_PREFIX = "Plans/mainwork-s3-rc6-20261103/"


class PhaseAError(RuntimeError):
    pass


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def dump(path: Path, payload: dict) -> None:
    if path.exists():
        raise PhaseAError(f"refuse to overwrite {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def run(argv: list[str], *, cwd: Path | None = None, stdin: str | None = None,
        timeout: int = 600, check: bool = True) -> subprocess.CompletedProcess[str]:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    COMMANDS.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        argv, cwd=cwd, input=None if stdin is None else stdin.encode(),
        capture_output=True, timeout=timeout, check=False,
    )
    def decode(payload: bytes) -> str:
        return payload.decode("utf-8", errors="replace")
    record = {
        "at": now(),
        "argv": argv,
        "cwd": str(cwd) if cwd else None,
        "exit": proc.returncode,
        "stdout": decode(proc.stdout),
        "stderr": decode(proc.stderr),
    }
    with COMMANDS.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record) + "\n")
    log_name = f"{len(list(LOG_DIR.glob('*.json'))):04d}.json"
    (LOG_DIR / log_name).write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    if check and proc.returncode != 0:
        raise PhaseAError(f"command failed ({proc.returncode}): {argv}\n{record['stderr']}")
    proc.stdout = record["stdout"]
    proc.stderr = record["stderr"]
    return proc


def git(repo: Path, *args: str, check: bool = True, timeout: int = 600) -> subprocess.CompletedProcess[str]:
    return run(["git", "-C", str(repo), *args], check=check, timeout=timeout)


def git_out(repo: Path, *args: str) -> str:
    return git(repo, *args).stdout.strip()


def require_absent(path: Path) -> None:
    if path.exists():
        raise PhaseAError(f"refuse to overwrite existing path {path}")


def porcelain(repo: Path) -> list[str]:
    return [line for line in git_out(repo, "status", "--porcelain=v1", "--untracked-files=normal").splitlines() if line]


def resume_observed_stage() -> int:
    """Continue after the retained SSH config failure. Do not rebuild existing inputs."""
    blocker_path = PLAN / "blocker.json"
    if not blocker_path.is_file():
        raise PhaseAError("task root exists without the retained blocker; refusing to resume")
    blocker = json.loads(blocker_path.read_text(encoding="utf-8"))
    if "20-systemd-ssh-proxy.conf" not in blocker.get("error", ""):
        raise PhaseAError("retained blocker is not the observed SSH config failure")
    for path in (PLAN / "intake.json", PLAN / "source-identity.json", PLAN / "input-inventory.json"):
        require_absent(path)
    snapshot = json.loads((TASK_ROOT / "shared-before.json").read_text(encoding="utf-8"))
    if git_out(SOURCE, "rev-parse", "HEAD") != FREEZE or git_out(SOURCE, "rev-parse", "HEAD^{tree}") != FREEZE_TREE:
        raise PhaseAError("existing source clone is not the freeze")
    if porcelain(SOURCE):
        raise PhaseAError("existing source clone is dirty")
    tag_object = git_out(SOURCE, "rev-parse", f"refs/tags/{TAG}")
    if git_out(SOURCE, "cat-file", "-t", tag_object) != "tag":
        raise PhaseAError("existing tag is not annotated")
    if git_out(SOURCE, "rev-parse", f"refs/tags/{TAG}^{{commit}}") != FREEZE:
        raise PhaseAError("existing tag does not peel to the freeze")
    if git_out(REPO, "show-ref", "--tags") != snapshot["tags"]:
        raise PhaseAError("shared tags differ from the pre-tag snapshot")
    if git_out(BATTERIES, "rev-parse", "HEAD") != BATTERIES_REV or git_out(BATTERIES, "rev-parse", "HEAD^{tree}") != BATTERIES_TREE:
        raise PhaseAError("existing Batteries clone identity mismatch")
    if porcelain(BATTERIES):
        raise PhaseAError("existing Batteries clone is dirty")
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if sha256_file(ARCHIVE) != manifest["archiveSha256"] or manifest["tagObject"] != tag_object:
        raise PhaseAError("existing source archive does not match its manifest")
    if manifest["commit"] != FREEZE or manifest["sourceCommand"][-1] != TAG:
        raise PhaseAError("existing archive was not taken from the tag")
    identity_proc = run(
        [sys.executable, "-c",
         "import json, sys\nfrom pathlib import Path\n"
         "sys.path.insert(0, 'tools/release')\nimport release\n"
         f"print(json.dumps(release.identity(Path({str(SOURCE)!r}), 'v0.2.0-rc.6')))\n"],
        cwd=REPO, timeout=60,
    )
    identity = json.loads(identity_proc.stdout)
    if identity["commit"] != FREEZE or identity["embeddedVersion"] != VERSION:
        raise PhaseAError("maintained identity() rejected the resumed tag")
    linux = observe_linux()
    windows_proc = run(
        ["ssh", "-F", str(Path.home() / ".ssh/config"), "-o", "BatchMode=yes",
         "-o", "ConnectTimeout=20", "win10",
         "powershell -NoProfile -NonInteractive -Command '$code = [Console]::In.ReadToEnd(); Invoke-Expression $code'"],
        stdin=OBS_PS1.read_text(encoding="utf-8"), timeout=180,
    )
    windows = parse_windows(windows_proc.stdout)
    if windows.get("STAGE_EXISTS") != "False":
        raise PhaseAError(f"Windows stage is not a fresh absent path: {windows.get('STAGE')}")
    for name in ("lake", "lean", "gcc", "git", "openssl"):
        tool = windows["tools"].get(name)
        if not tool or tool.get("present") != "True":
            raise PhaseAError(f"Windows tool absent: {name}")
    if "4.33.0" not in windows["tools"]["lean"]["version"] or "4.33.0" not in windows["tools"]["lake"]["version"]:
        raise PhaseAError("Windows Lean/Lake is not 4.33.0")
    remote_tag = run(["git", "-C", str(REPO), "ls-remote", "origin", f"refs/tags/{TAG}"], timeout=120)
    remote_main = run(["git", "-C", str(REPO), "ls-remote", "origin", "refs/heads/main"], timeout=120)
    if remote_tag.stdout.strip():
        raise PhaseAError(f"remote already has {TAG}")
    history = git_out(BATTERIES, "rev-list", "--count", "HEAD")
    source_identity = {
        "schema": "mirrors.s3-rc6.phase-a.source-identity/v1",
        "published": False,
        "deployed": False,
        "at": now(),
        "resumedAfterRetainedFailure": str((PLAN / "blocker.json").relative_to(REPO)),
        "sharedHead": snapshot["head"],
        "sharedTree": snapshot["tree"],
        "freeze": FREEZE,
        "freezeTree": FREEZE_TREE,
        "publishedCommit": PUBLISHED,
        "publishedDiffPaths": sorted(DOC_PATHS),
        "publishedDiffIsPlanningStatusOnly": True,
        "tag": TAG,
        "tagType": "tag",
        "tagObject": tag_object,
        "tagPeel": FREEZE,
        "tagRepository": str(SOURCE.relative_to(REPO)),
        "sharedTagRefsUnchanged": True,
        "remoteTag": {"ref": f"refs/tags/{TAG}", "present": False, "stdout": remote_tag.stdout},
        "remoteMain": {"stdout": remote_main.stdout.strip()},
        "releaseIdentity": identity,
        "archive": {
            "path": manifest["archive"],
            "sha256": manifest["archiveSha256"],
            "bytes": manifest["archiveBytes"],
            "fileCount": manifest["fileCount"],
            "manifest": str(MANIFEST_PATH.relative_to(REPO)),
        },
        "batteries": {
            "revision": BATTERIES_REV,
            "tree": BATTERIES_TREE,
            "retainedSource": ".lake/packages/batteries",
            "offlineClone": str(BATTERIES.relative_to(REPO)),
            "historyCount": int(history),
            "substitutesLockedCarrier": False,
            "missingCarrierSha256": MISSING_CARRIER,
        },
    }
    inventory = {
        "schema": "mirrors.s3-rc6.phase-a.input-inventory/v1",
        "published": False,
        "deployed": False,
        "at": now(),
        "phase": "A",
        "buildsRun": False,
        "inputs": [
            {"role": "source-clone", "path": str(SOURCE.relative_to(REPO)), "commit": FREEZE, "tree": FREEZE_TREE, "tag": TAG, "tagObject": tag_object},
            {"role": "source-archive", "path": manifest["archive"], "sha256": manifest["archiveSha256"], "fileCount": manifest["fileCount"]},
            {"role": "source-manifest", "path": str(MANIFEST_PATH.relative_to(REPO)), "fileCount": manifest["fileCount"]},
            {"role": "batteries-offline", "path": str(BATTERIES.relative_to(REPO)), "revision": BATTERIES_REV, "tree": BATTERIES_TREE},
            {"role": "linux-toolchain", "observation": linux},
            {"role": "windows-host", "observation": windows},
        ],
    }
    intake = {
        "schema": "mirrors.s3-rc6.phase-a.intake/v1",
        "published": False,
        "deployed": False,
        "at": now(),
        "task": "Plans/mainwork-s3-rc6-20261103/task.md",
        "phase": "A",
        "acceptance": "not claimed; Codex owns S3 acceptance",
        "retainedFailure": "Plans/mainwork-s3-rc6-20261103/blocker.json",
        "sourceIdentity": "Plans/mainwork-s3-rc6-20261103/source-identity.json",
        "inputInventory": "Plans/mainwork-s3-rc6-20261103/input-inventory.json",
        "verifier": "Plans/mainwork-s3-rc6-20261103/verify.py",
        "commands": str(COMMANDS.relative_to(REPO)),
        "tagObject": tag_object,
        "archiveSha256": manifest["archiveSha256"],
        "archiveFileCount": manifest["fileCount"],
        "batteriesRevision": BATTERIES_REV,
        "windowsHost": windows.get("HOST"),
        "windowsStage": windows.get("STAGE"),
        "windowsStageExists": windows.get("STAGE_EXISTS"),
    }
    dump(PLAN / "source-identity.json", source_identity)
    dump(PLAN / "input-inventory.json", inventory)
    dump(PLAN / "intake.json", intake)
    dump(PLAN / "receipts/windows-observe.json", {"published": False, "deployed": False, "stdout": windows_proc.stdout, "parsed": windows})
    dump(PLAN / "receipts/linux-observe.json", {"published": False, "deployed": False, "parsed": linux})
    print("PHASE_A_ADMITTED")
    return 0


def main() -> int:
    if TASK_ROOT.exists():
        return resume_observed_stage()
    for path in (TASK_ROOT, SOURCE, BATTERIES, ARCHIVE_DIR, COMMANDS):
        require_absent(path)
    if not OBS_PS1.is_file():
        raise PhaseAError(f"missing observation script {OBS_PS1}")
    blocker: dict | None = None
    snapshot = {
        "at": now(),
        "head": git_out(REPO, "rev-parse", "HEAD"),
        "tree": git_out(REPO, "rev-parse", "HEAD^{tree}"),
        "status": porcelain(REPO),
        "tags": git_out(REPO, "show-ref", "--tags"),
    }
    dump(TASK_ROOT / "shared-before.json", snapshot)
    try:
        admit(snapshot)
    except Exception as exc:
        blocker = {"at": now(), "error": str(exc), "type": type(exc).__name__}
        dump(PLAN / "blocker.json", blocker)
        print(f"PHASE_A_BLOCKER {exc}", file=sys.stderr)
        return 1
    if blocker:
        return 1
    print("PHASE_A_ADMITTED")
    return 0


def admit(snapshot: dict) -> None:
    if snapshot["head"] != PUBLISHED:
        raise PhaseAError(f"shared HEAD {snapshot['head']} is not {PUBLISHED}")
    names = set(git_out(REPO, "diff", "--name-only", FREEZE, PUBLISHED).splitlines())
    if names != DOC_PATHS:
        raise PhaseAError(f"freeze..published is not the recorded planning/status set: {sorted(names - DOC_PATHS)} extra, {sorted(DOC_PATHS - names)} missing")
    if git_out(REPO, "merge-base", "--is-ancestor", FREEZE, PUBLISHED) != "" and git(REPO, "merge-base", "--is-ancestor", FREEZE, PUBLISHED).returncode != 0:
        raise PhaseAError("freeze is not an ancestor of published HEAD")
    # merge-base --is-ancestor prints nothing and exits 0. git_out used check=True so exit 0 is enough.
    version_text = git_out(REPO, "show", f"{FREEZE}:Shell/Version.lean")
    if f'def version : String := "{VERSION}"' not in version_text:
        raise PhaseAError("freeze Shell/Version.lean does not declare 0.2.0-rc.6")
    if git_out(REPO, "rev-parse", f"{FREEZE}^{{tree}}") != FREEZE_TREE:
        raise PhaseAError("freeze tree differs from the brief")
    remote_main = run(["git", "-C", str(REPO), "ls-remote", "origin", "refs/heads/main"], timeout=120)
    remote_tag = run(["git", "-C", str(REPO), "ls-remote", "origin", f"refs/tags/{TAG}"], timeout=120)
    if remote_tag.stdout.strip():
        raise PhaseAError(f"remote already has {TAG}: {remote_tag.stdout.strip()}")
    shared_tag = git(REPO, "rev-parse", "-q", "--verify", f"refs/tags/{TAG}", check=False)
    if shared_tag.returncode == 0:
        raise PhaseAError("shared checkout already has the rc.6 tag")

    validation = run(
        [sys.executable, "-c",
         "import sys; from pathlib import Path\n"
         "sys.path.insert(0, 'tools/release')\n"
         "import release\n"
         "print(release.validate_tag('v0.2.0-rc.6'))\n"],
        cwd=REPO, timeout=60,
    )

    user_name = git(REPO, "config", "--get", "user.name", check=False).stdout.strip()
    user_email = git(REPO, "config", "--get", "user.email", check=False).stdout.strip()
    if not user_name or not user_email:
        raise PhaseAError("git user.name and user.email are required to create the annotated tag")

    require_absent(SOURCE)
    run(["git", "clone", "--no-hardlinks", "--no-local", str(REPO), str(SOURCE)], timeout=1800)
    git(SOURCE, "checkout", "--detach", FREEZE, timeout=600)
    if git_out(SOURCE, "rev-parse", "HEAD") != FREEZE:
        raise PhaseAError("clone HEAD is not the freeze commit")
    if git_out(SOURCE, "rev-parse", "HEAD^{tree}") != FREEZE_TREE:
        raise PhaseAError("clone tree is not the freeze tree")
    if porcelain(SOURCE):
        raise PhaseAError("clone is not clean before tagging")
    git(SOURCE, "-c", f"user.name={user_name}", "-c", f"user.email={user_email}",
        "tag", "-a", TAG, FREEZE, "-m",
        "Local-only packaging tag v0.2.0-rc.6 at the accepted source freeze. Not pushed.")
    tag_object = git_out(SOURCE, "rev-parse", f"refs/tags/{TAG}")
    tag_type = git_out(SOURCE, "cat-file", "-t", tag_object)
    peel = git_out(SOURCE, "rev-parse", f"refs/tags/{TAG}^{{commit}}")
    if tag_type != "tag" or peel != FREEZE or tag_object == FREEZE:
        raise PhaseAError(f"tag identity failed type={tag_type} object={tag_object} peel={peel}")
    identity_proc = run(
        [sys.executable, "-c",
         "import json, sys\n"
         "from pathlib import Path\n"
         "sys.path.insert(0, 'tools/release')\n"
         "import release\n"
         f"print(json.dumps(release.identity(Path({str(SOURCE)!r}), 'v0.2.0-rc.6')))\n"],
        cwd=REPO, timeout=60,
    )
    identity = json.loads(identity_proc.stdout)
    if identity["commit"] != FREEZE or identity["embeddedVersion"] != VERSION or identity["tag"] != TAG:
        raise PhaseAError(f"maintained identity() rejected the tag: {identity}")
    tags_after = git_out(REPO, "show-ref", "--tags")
    if tags_after != snapshot["tags"]:
        raise PhaseAError("shared checkout tag refs changed")
    if git(REPO, "rev-parse", "-q", "--verify", f"refs/tags/{TAG}", check=False).returncode == 0:
        raise PhaseAError("rc.6 tag appeared in the shared checkout")

    batteries_src = REPO / ".lake/packages/batteries"
    if git_out(batteries_src, "rev-parse", "HEAD") != BATTERIES_REV:
        raise PhaseAError("retained Batteries checkout revision mismatch")
    if git_out(batteries_src, "rev-parse", "HEAD^{tree}") != BATTERIES_TREE:
        raise PhaseAError("retained Batteries checkout tree mismatch")
    if git_out(batteries_src, "cat-file", "-t", BATTERIES_REV) != "commit":
        raise PhaseAError("Batteries revision is not a commit object")
    if git_out(batteries_src, "rev-parse", f"{BATTERIES_REV}^{{tree}}") != BATTERIES_TREE:
        raise PhaseAError("Batteries commit tree differs")
    history = git_out(batteries_src, "rev-list", "--count", BATTERIES_REV)
    if not history.isdigit() or int(history) < 1:
        raise PhaseAError("Batteries history is empty")
    require_absent(BATTERIES)
    BATTERIES.parent.mkdir(parents=True, exist_ok=True)
    run(["git", "clone", "--no-hardlinks", "--no-local", str(batteries_src), str(BATTERIES)], timeout=1800)
    git(BATTERIES, "checkout", "--detach", BATTERIES_REV, timeout=600)
    if git_out(BATTERIES, "rev-parse", "HEAD") != BATTERIES_REV:
        raise PhaseAError("offline Batteries HEAD mismatch")
    if git_out(BATTERIES, "rev-parse", "HEAD^{tree}") != BATTERIES_TREE:
        raise PhaseAError("offline Batteries tree mismatch")
    if porcelain(BATTERIES):
        raise PhaseAError("offline Batteries checkout is dirty")
    if git_out(BATTERIES, "rev-list", "--count", "HEAD") != history:
        raise PhaseAError("offline Batteries history count differs from the retained source")
    fsck = git(BATTERIES, "fsck", "--no-dangling", timeout=1800)

    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
    prefix = "mirrors-v0.2.0-rc.6/"
    with tempfile.TemporaryDirectory(prefix="rc6-source-archive-") as temporary:
        raw = Path(temporary) / "source.tar"
        git(SOURCE, "archive", "--format=tar", f"--prefix={prefix}", TAG, "-o", str(raw), timeout=600)
        with raw.open("rb") as src, ARCHIVE.open("wb") as out, gzip.GzipFile(filename="", mode="wb", fileobj=out, mtime=0) as dst:
            shutil.copyfileobj(src, dst)
        files = []
        with tarfile.open(ARCHIVE, "r:gz") as handle:
            members = handle.getmembers()
            for member in sorted(members, key=lambda item: item.name):
                if not member.isfile():
                    continue
                extracted = handle.extractfile(member)
                if extracted is None:
                    raise PhaseAError(f"missing archive member {member.name}")
                payload = extracted.read()
                rel = member.name[len(prefix):] if member.name.startswith(prefix) else member.name
                files.append({
                    "path": rel,
                    "mode": oct(member.mode & 0o777),
                    "bytes": len(payload),
                    "sha256": hashlib.sha256(payload).hexdigest(),
                })
        member_count = len(members)
    manifest = {
        "schema": "mirrors.s3-rc6.phase-a.source-manifest/v1",
        "published": False,
        "deployed": False,
        "tag": TAG,
        "tagObject": tag_object,
        "commit": FREEZE,
        "tree": FREEZE_TREE,
        "archive": str(ARCHIVE.relative_to(REPO)),
        "archiveBytes": ARCHIVE.stat().st_size,
        "archiveSha256": sha256_file(ARCHIVE),
        "fileCount": len(files),
        "memberCount": member_count,
        "gzipMtime": 0,
        "prefix": prefix,
        "sourceCommand": ["git", "archive", "--format=tar", f"--prefix={prefix}", TAG],
        "files": files,
    }
    dump(MANIFEST_PATH, manifest)

    linux = observe_linux()
    windows_proc = run(
        ["ssh", "-F", str(Path.home() / ".ssh/config"), "-o", "BatchMode=yes", "-o", "ConnectTimeout=20", "win10",
         "powershell -NoProfile -NonInteractive -Command '$code = [Console]::In.ReadToEnd(); Invoke-Expression $code'"],
        stdin=OBS_PS1.read_text(encoding="utf-8"), timeout=180,
    )
    windows = parse_windows(windows_proc.stdout)
    if windows.get("STAGE_EXISTS") != "False":
        raise PhaseAError(f"Windows stage is not a fresh absent path: {windows.get('STAGE')}")
    required_tools = ("lake", "lean", "gcc", "git", "openssl")
    for name in required_tools:
        tool = windows["tools"].get(name)
        if not tool or tool.get("present") != "True":
            raise PhaseAError(f"Windows tool absent: {name}")
    if "4.33.0" not in windows["tools"]["lean"]["version"] or "4.33.0" not in windows["tools"]["lake"]["version"]:
        raise PhaseAError("Windows Lean/Lake is not 4.33.0")

    status_after = porcelain(REPO)
    added = [line for line in status_after if line not in snapshot["status"]]
    removed = [line for line in snapshot["status"] if line not in status_after]
    for line in added:
        path = line[3:]
        if not path.startswith(OWNED_PREFIX):
            raise PhaseAError(f"unexpected shared status addition: {line}")
    if removed:
        raise PhaseAError(f"shared status lost entries: {removed}")
    if git(REPO, "diff", "--quiet", check=False).returncode != 0 or git(REPO, "diff", "--cached", "--quiet", check=False).returncode != 0:
        raise PhaseAError("shared tracked content changed")
    if git_out(REPO, "rev-parse", "HEAD") != snapshot["head"]:
        raise PhaseAError("shared HEAD changed")
    if git_out(REPO, "show-ref", "--tags") != snapshot["tags"]:
        raise PhaseAError("shared tags changed at exit")

    source_identity = {
        "schema": "mirrors.s3-rc6.phase-a.source-identity/v1",
        "published": False,
        "deployed": False,
        "at": now(),
        "sharedHead": snapshot["head"],
        "sharedTree": snapshot["tree"],
        "freeze": FREEZE,
        "freezeTree": FREEZE_TREE,
        "publishedCommit": PUBLISHED,
        "publishedDiffPaths": sorted(DOC_PATHS),
        "publishedDiffIsPlanningStatusOnly": True,
        "tag": TAG,
        "tagType": tag_type,
        "tagObject": tag_object,
        "tagPeel": peel,
        "tagRepository": str(SOURCE.relative_to(REPO)),
        "sharedTagRefsUnchanged": True,
        "remoteTag": {"ref": f"refs/tags/{TAG}", "present": False, "stdout": remote_tag.stdout},
        "remoteMain": {"stdout": remote_main.stdout.strip()},
        "validateTagStdout": validation.stdout.strip(),
        "releaseIdentity": identity,
        "archive": {
            "path": manifest["archive"],
            "sha256": manifest["archiveSha256"],
            "bytes": manifest["archiveBytes"],
            "fileCount": manifest["fileCount"],
            "manifest": str(MANIFEST_PATH.relative_to(REPO)),
        },
        "batteries": {
            "revision": BATTERIES_REV,
            "tree": BATTERIES_TREE,
            "retainedSource": str(batteries_src.relative_to(REPO)),
            "offlineClone": str(BATTERIES.relative_to(REPO)),
            "historyCount": int(history),
            "fsckExit": fsck.returncode,
            "substitutesLockedCarrier": False,
            "missingCarrierSha256": MISSING_CARRIER,
        },
    }
    inventory = {
        "schema": "mirrors.s3-rc6.phase-a.input-inventory/v1",
        "published": False,
        "deployed": False,
        "at": now(),
        "phase": "A",
        "buildsRun": False,
        "inputs": [
            {"role": "source-clone", "path": str(SOURCE.relative_to(REPO)), "commit": FREEZE, "tree": FREEZE_TREE, "tag": TAG, "tagObject": tag_object},
            {"role": "source-archive", "path": manifest["archive"], "sha256": manifest["archiveSha256"], "fileCount": manifest["fileCount"]},
            {"role": "source-manifest", "path": str(MANIFEST_PATH.relative_to(REPO)), "fileCount": manifest["fileCount"]},
            {"role": "batteries-offline", "path": str(BATTERIES.relative_to(REPO)), "revision": BATTERIES_REV, "tree": BATTERIES_TREE},
            {"role": "linux-toolchain", "observation": linux},
            {"role": "windows-host", "observation": windows},
        ],
    }
    intake = {
        "schema": "mirrors.s3-rc6.phase-a.intake/v1",
        "published": False,
        "deployed": False,
        "at": now(),
        "task": "Plans/mainwork-s3-rc6-20261103/task.md",
        "phase": "A",
        "acceptance": "not claimed; Codex owns S3 acceptance",
        "sourceIdentity": "Plans/mainwork-s3-rc6-20261103/source-identity.json",
        "inputInventory": "Plans/mainwork-s3-rc6-20261103/input-inventory.json",
        "verifier": "Plans/mainwork-s3-rc6-20261103/verify.py",
        "commands": str(COMMANDS.relative_to(REPO)),
        "tagObject": tag_object,
        "archiveSha256": manifest["archiveSha256"],
        "archiveFileCount": manifest["fileCount"],
        "batteriesRevision": BATTERIES_REV,
        "windowsHost": windows.get("HOST"),
        "windowsStage": windows.get("STAGE"),
        "windowsStageExists": windows.get("STAGE_EXISTS"),
    }
    dump(PLAN / "source-identity.json", source_identity)
    dump(PLAN / "input-inventory.json", inventory)
    dump(PLAN / "intake.json", intake)
    dump(PLAN / "receipts/windows-observe.json", {"published": False, "deployed": False, "stdout": windows_proc.stdout, "parsed": windows})
    dump(PLAN / "receipts/linux-observe.json", {"published": False, "deployed": False, "parsed": linux})


def observe_linux() -> dict:
    commands = {
        "os-release": ["bash", "-lc", "cat /etc/os-release"],
        "uname": ["uname", "-a"],
        "git": ["git", "--version"],
        "gcc": ["gcc", "--version"],
        "openssl": ["openssl", "version"],
        "python": [sys.executable, "--version"],
    }
    observed = {}
    for name, argv in commands.items():
        proc = run(argv, check=False, timeout=60)
        observed[name] = {"argv": argv, "exit": proc.returncode, "stdout": proc.stdout, "stderr": proc.stderr}
    lean_root = Path.home() / ".elan/toolchains"
    lean_bins = sorted(lean_root.glob("leanprover--lean4---v4.33.0/bin/lean")) if lean_root.is_dir() else []
    lake_bins = sorted(lean_root.glob("leanprover--lean4---v4.33.0/bin/lake")) if lean_root.is_dir() else []
    for label, bins in (("lean", lean_bins), ("lake", lake_bins)):
        if not bins:
            observed[label] = {"present": False}
            continue
        proc = run([str(bins[0]), "--version"], check=False, timeout=60)
        observed[label] = {
            "present": True, "path": str(bins[0]), "sha256": sha256_file(bins[0]),
            "exit": proc.returncode, "stdout": proc.stdout, "stderr": proc.stderr,
        }
    if not observed.get("lean", {}).get("present") or "4.33.0" not in observed["lean"].get("stdout", ""):
        raise PhaseAError("Linux Lean 4.33.0 is absent")
    if not observed.get("lake", {}).get("present") or "4.33.0" not in observed["lake"].get("stdout", ""):
        raise PhaseAError("Linux Lake 4.33.0 is absent")
    return observed


def parse_windows(stdout: str) -> dict:
    parsed: dict = {"tools": {}}
    for line in stdout.splitlines():
        if line.startswith("TOOL\t"):
            parts = line.split("\t")
            fields = {}
            for part in parts[2:]:
                key, value = part.split("=", 1)
                fields[key] = value
            parsed["tools"][parts[1]] = fields
        elif " " in line:
            key, value = line.split(" ", 1)
            parsed[key] = value
        else:
            parsed[line] = True
    return parsed


if __name__ == "__main__":
    try:
        sys.exit(main())
    except PhaseAError as exc:
        print(f"PHASE_A_BLOCKER {exc}", file=sys.stderr)
        sys.exit(1)
