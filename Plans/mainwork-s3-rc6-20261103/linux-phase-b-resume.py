#!/usr/bin/env python3
"""Resume Phase B after the retained SHA256SUMS listing failure.

The maintained build, tests, and clean-source checks already passed. This
process does not rebuild. It keeps linux-failure.json and verifies the
existing dist: checksum lines, maintained check-archive, exact members,
binary hashes, library closure, and a second isolated runtime smoke.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import subprocess
import tarfile
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
TASK = REPO / ".golden-build/mainwork-s3-rc6-20261103"
SOURCE = TASK / "source"
DIST = TASK / "linux-dist"
TMP = TASK / "linux-tmp"
SMOKE_ROOT = TASK / "linux-smoke"
LOGS = TASK / "linux-logs-resume"
TAG = "v0.2.0-rc.6"
FREEZE = "3c4a87309cc3a81924660497207d7c295759bdc1"
TAG_OBJECT = "5a2a6fd8728b610db7a6225b4a9d4c5d585344aa"
NAME = "mirrors-v0.2.0-rc.6-linux-x86_64"
EXPECTED_MEMBERS = {
    NAME, f"{NAME}/bin", f"{NAME}/bin/mirror", f"{NAME}/bin/model_interface_gen",
    f"{NAME}/README.txt", f"{NAME}/BUILD.json",
}
SYSTEM_LIBRARIES = {
    "libssl.so.3", "libcrypto.so.3", "libgmp.so.10", "libc.so.6", "libm.so.6",
    "libpthread.so.0", "libdl.so.2", "librt.so.1", "libgcc_s.so.1",
    "libstdc++.so.6", "libatomic.so.1", "libz.so.1", "libuv.so.1",
}
BINARIES = ("mirror", "model_interface_gen")
COMMANDS = PLAN / "linux-commands-resume.jsonl"
NEW_PATHS = (
    LOGS, SMOKE_ROOT, COMMANDS,
    PLAN / "linux-build.json", PLAN / "linux-archive.json", PLAN / "linux-smoke.json",
    PLAN / "package-set.json",
)
commands: list[dict] = []


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def exclusive_json(path: Path, payload: dict) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def run(name: str, argv: list[str], cwd: Path, env: dict, timeout: int, stdin: str | None = None) -> subprocess.CompletedProcess[str]:
    log_path = LOGS / f"{len(commands):04d}-{name}.log"
    if log_path.exists():
        raise SystemExit(f"refuse overwrite: {log_path}")
    started = now()
    completed = subprocess.run(
        argv, cwd=cwd, env=env, input=stdin, text=True, capture_output=True, timeout=timeout, check=False,
    )
    log_path.write_text(
        f"$ {' '.join(argv)}\n# cwd={cwd}\n# exit={completed.returncode}\n"
        f"# --- stdout ---\n{completed.stdout}\n# --- stderr ---\n{completed.stderr}",
        encoding="utf-8",
    )
    row = {
        "name": name, "argv": argv, "cwd": str(cwd), "startedAt": started, "finishedAt": now(),
        "exit": completed.returncode, "log": str(log_path.relative_to(REPO)),
        "logBytes": log_path.stat().st_size, "logSha256": sha256(log_path),
    }
    if stdin is not None:
        row["stdin"] = stdin
    commands.append(row)
    with COMMANDS.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, sort_keys=True) + "\n")
    print(f"{name} exit={completed.returncode}", flush=True)
    return completed


def main() -> int:
    present = [str(path.relative_to(REPO)) for path in NEW_PATHS if path.exists()]
    if present:
        raise SystemExit("refuse overwrite: " + ", ".join(present))
    require((PLAN / "linux-failure.json").is_file(), "retained failure record missing")
    require(DIST.is_dir() and TMP.is_dir() and (TASK / "linux-logs").is_dir(), "verified build stage missing")
    LOGS.mkdir()
    fd = os.open(COMMANDS, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    os.close(fd)
    env = dict(os.environ)
    for key in ("APALACHE_MC", "APALACHE_JAR", "TLA2TOOLS_JAR", "LD_LIBRARY_PATH", "LD_PRELOAD"):
        env.pop(key, None)
    env["TMPDIR"] = str(TMP)
    env["LC_ALL"] = "C.UTF-8"
    env["PATH"] = "/home/lsz/.elan/bin:" + env.get("PATH", "")

    archive = DIST / f"{NAME}.tar.gz"
    external = DIST / f"{NAME}.build.json"
    sums_path = DIST / "SHA256SUMS"
    sums = {}
    for line in sums_path.read_text(encoding="utf-8").splitlines():
        digest, filename = line.split("  ", 1)
        sums[filename] = digest
        require(sha256(DIST / filename) == digest, f"SHA256SUMS mismatch {filename}")
    assets = {path.name for path in DIST.iterdir() if path.is_file()}
    require(assets - set(sums) == {"SHA256SUMS", "release-notes.txt"}, f"unexpected unlisted files {sorted(assets - set(sums))}")

    check = run(
        "check-archive",
        ["python3", "tools/release/release.py", "check-archive", "--tag", TAG, "--archive", str(archive)],
        REPO, env, 180,
    )
    require(check.returncode == 0, "maintained check-archive failed")
    manifest = json.loads(external.read_text(encoding="utf-8"))
    require(manifest["tag"] == TAG and manifest["commit"] == FREEZE, "manifest identity")
    require(manifest["embeddedVersion"] == "0.2.0-rc.6" and manifest["expectedVersionOutput"] == "v0.2.0-rc.6\n", "version")
    require(manifest.get("historical") is False and manifest.get("prerelease") is True, "flags")
    require("focused non-model" in manifest.get("qualification", ""), "qualification")

    members = []
    with tarfile.open(archive, "r:gz") as handle:
        entries = handle.getmembers()
        names = [entry.name for entry in entries]
        require(set(names) == EXPECTED_MEMBERS and len(names) == len(EXPECTED_MEMBERS), f"members {sorted(names)}")
        require(all((entry.isfile() or entry.isdir()) and not entry.issym() and not entry.islnk() for entry in entries), "member type")
        SMOKE_ROOT.mkdir()
        extract = SMOKE_ROOT / "extract"
        extract.mkdir()
        handle.extractall(extract, filter="data")
        for entry in entries:
            row = {"name": entry.name, "mode": oct(entry.mode & 0o777), "kind": "dir" if entry.isdir() else "file"}
            if entry.isfile():
                payload = (extract / entry.name).read_bytes()
                row["bytes"] = len(payload)
                row["sha256"] = hashlib.sha256(payload).hexdigest()
            members.append(row)
    package = extract / NAME
    require((package / "BUILD.json").read_bytes() == external.read_bytes(), "embedded manifest")
    binary_rows = {}
    for binary in BINARIES:
        path = package / "bin" / binary
        digest = sha256(path)
        require(digest == manifest["binaries"][binary]["sha256"], binary)
        require(stat.S_IMODE(path.stat().st_mode) & 0o111, f"{binary} mode")
        ldd = run(f"ldd-{binary}", ["ldd", str(path)], package, env, 30)
        require(ldd.returncode == 0 and "not found" not in ldd.stdout, f"ldd {binary}")
        libraries = []
        for line in ldd.stdout.splitlines():
            matched = re.match(r"\s*(\S+)\s+=>\s+(\S+)", line)
            if not matched:
                continue
            library, target = matched.groups()
            require(library in SYSTEM_LIBRARIES, library)
            require("/.lake/" not in target.lower() and "lean" not in target.lower(), target)
            libraries.append({"soname": library, "target": target, "targetSha256": sha256(Path(target))})
        require({item["soname"] for item in libraries} == set(manifest["binaries"][binary]["libraries"]), f"{binary} library set")
        binary_rows[binary] = {"sha256": digest, "bytes": path.stat().st_size, "libraries": libraries, "ldd": ldd.stdout}

    os_release = run("smoke-os-release", ["cat", "/etc/os-release"], REPO, env, 30)
    uname = run("smoke-uname", ["uname", "-a"], REPO, env, 30)
    require(os_release.returncode == 0 and "Ubuntu 26.04.1" in os_release.stdout, "os")
    require(uname.returncode == 0 and "WSL2" in uname.stdout, "wsl")
    smoke_env = {"PATH": "/usr/bin:/bin", "HOME": str(SMOKE_ROOT / "home"), "TMPDIR": str(TMP), "LC_ALL": "C.UTF-8"}
    (SMOKE_ROOT / "home").mkdir()
    absent = run(
        "smoke-path-absent",
        ["bash", "-lc", "command -v lean >/dev/null || command -v lake >/dev/null || command -v mirror >/dev/null; status=$?; printf '%s' \"$PATH\"; exit \"$status\""],
        package, smoke_env, 30,
    )
    require(absent.returncode != 0 and absent.stdout == "/usr/bin:/bin", f"path probe {absent.returncode} {absent.stdout!r}")
    version = run("smoke-version", [str(package / "bin/mirror"), "--version"], package, smoke_env, 30)
    protocol = run(
        "smoke-protocol", [str(package / "bin/mirror")], package, smoke_env, 30,
        stdin='{"proto_step":"report_state","state":{}}\n',
    )
    help_run = run("smoke-help", [str(package / "bin/model_interface_gen"), "--help"], package, smoke_env, 30)
    require(version.returncode == 0 and version.stdout == "v0.2.0-rc.6\n" and version.stderr == "", "version smoke")
    message = json.loads(protocol.stdout)
    require(protocol.returncode == 0 and message.get("proto_step") == "protocol_error", "protocol smoke")
    require(help_run.returncode == 2 and "usage:" in help_run.stderr, "help smoke")

    first_commands = (PLAN / "linux-commands.jsonl").read_text(encoding="utf-8").splitlines()
    build_row = json.loads(next(line for line in first_commands if '"release-build"' in line))
    test_row = json.loads(next(line for line in first_commands if '"release-tests"' in line))
    linux_build = {
        "schema": "mirrors.s3-rc6.phase-b.linux-build/v1",
        "published": False, "deployed": False, "at": now(), "phase": "B",
        "acceptance": "not claimed; Codex owns S3 acceptance",
        "scope": "focused non-model release gates only; no live model checker; no DPM CLI",
        "source": str(SOURCE.relative_to(REPO)), "tag": TAG, "tagObject": TAG_OBJECT, "commit": FREEZE,
        "retainedFailure": "Plans/mainwork-s3-rc6-20261103/linux-failure.json",
        "retainedFailureMeaning": "first post-build check required SHA256SUMS to list itself and release-notes.txt; the maintained builder writes those two files after hashing. The build itself exited 0 and was not rerun.",
        "tests": test_row, "build": build_row,
        "passedGates": manifest.get("passedGates"), "buildTools": manifest.get("buildTools"),
        "qualification": manifest.get("qualification"),
        "dist": str(DIST.relative_to(REPO)), "tmpdir": str(TMP.relative_to(REPO)),
    }
    linux_archive = {
        "schema": "mirrors.s3-rc6.phase-b.linux-archive/v1",
        "published": False, "deployed": False, "at": now(), "tag": TAG, "commit": FREEZE,
        "archive": {"path": str(archive.relative_to(REPO)), "bytes": archive.stat().st_size, "sha256": sha256(archive)},
        "externalManifest": {"path": str(external.relative_to(REPO)), "bytes": external.stat().st_size, "sha256": sha256(external)},
        "sha256sums": {
            "path": str(sums_path.relative_to(REPO)), "sha256": sha256(sums_path), "entries": sums, "verified": True,
            "unlistedByBuilderOrder": ["SHA256SUMS", "release-notes.txt"],
        },
        "maintainedCheckArchive": commands[0],
        "embeddedManifestEqualsExternal": True, "members": members,
        "binaries": {name: {"sha256": binary_rows[name]["sha256"], "bytes": binary_rows[name]["bytes"],
                            "libraries": [item["soname"] for item in binary_rows[name]["libraries"]]} for name in BINARIES},
        "allowedLibraries": sorted(SYSTEM_LIBRARIES),
    }
    linux_smoke = {
        "schema": "mirrors.s3-rc6.phase-b.linux-smoke/v1",
        "published": False, "deployed": False, "at": now(),
        "host": {"osRelease": os_release.stdout, "uname": uname.stdout.strip()},
        "historicalUbuntu2404ClaimCopied": False,
        "path": "/usr/bin:/bin", "sourceAbsentFromPath": True, "leanAbsentFromPath": True,
        "pathProbe": {"exit": absent.returncode, "stdout": absent.stdout, "stderr": absent.stderr},
        "mirrorVersion": {"exit": version.returncode, "stdout": version.stdout, "stderr": version.stderr},
        "protocol": {"exit": protocol.returncode, "stdout": protocol.stdout, "stderr": protocol.stderr},
        "modelInterfaceGenHelp": {"exit": help_run.returncode, "stderr": help_run.stderr},
        "ldd": {name: binary_rows[name]["ldd"] for name in BINARIES},
        "libraryTargets": {name: binary_rows[name]["libraries"] for name in BINARIES},
        "scope": "second isolated runtime smoke on the observed Ubuntu 26.04.1 WSL2 host",
    }
    package_set = {
        "schema": "mirrors.s3-rc6.phase-b.package-set/v1",
        "published": False, "deployed": False, "at": now(),
        "acceptance": "package records only; not full S3 acceptance and not Codex acceptance",
        "tag": TAG, "tagObject": TAG_OBJECT, "commit": FREEZE,
        "scope": "focused non-model Linux gates and isolated runtime smoke only",
        "modelCheckerRun": False, "dpmCliPackaged": False, "fullLakeTest": False,
        "archiveSha256": linux_archive["archive"]["sha256"],
        "externalManifestSha256": linux_archive["externalManifest"]["sha256"],
        "checksumsSha256": linux_archive["sha256sums"]["sha256"],
        "binaries": {name: binary_rows[name]["sha256"] for name in BINARIES},
        "passedGates": manifest.get("passedGates"),
        "retainedFailure": "Plans/mainwork-s3-rc6-20261103/linux-failure.json",
    }
    exclusive_json(PLAN / "linux-build.json", linux_build)
    exclusive_json(PLAN / "linux-archive.json", linux_archive)
    exclusive_json(PLAN / "linux-smoke.json", linux_smoke)
    exclusive_json(PLAN / "package-set.json", package_set)
    print(f"PHASE_B_RESUME_OK archive={linux_archive['archive']['sha256']}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        target = PLAN / "linux-failure-resume.json"
        if not target.exists():
            exclusive_json(target, {
                "schema": "mirrors.s3-rc6.phase-b.failure/v1", "published": False, "deployed": False,
                "at": now(), "error": str(exc), "commands": commands, "acceptance": "not claimed",
            })
        print(f"PHASE_B_RESUME_FAILED {exc}", flush=True)
        raise
