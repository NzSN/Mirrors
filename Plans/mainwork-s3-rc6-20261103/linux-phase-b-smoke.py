#!/usr/bin/env python3
"""Finish Phase B records from the verified dist and extracted package.

Does not rebuild. Retains both earlier failure records. The runtime PATH is
exactly /usr/bin:/bin, applied without a login shell.
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
PACKAGE = TASK / "linux-smoke/extract/mirrors-v0.2.0-rc.6-linux-x86_64"
LOGS = TASK / "linux-logs-smoke"
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
COMMANDS = PLAN / "linux-commands-smoke.jsonl"
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
    started = now()
    completed = subprocess.run(argv, cwd=cwd, env=env, input=stdin, text=True, capture_output=True, timeout=timeout, check=False)
    log_path.write_text(
        f"$ {' '.join(argv)}\n# cwd={cwd}\n# PATH={env.get('PATH')}\n# exit={completed.returncode}\n"
        f"# --- stdout ---\n{completed.stdout}\n# --- stderr ---\n{completed.stderr}",
        encoding="utf-8",
    )
    row = {
        "name": name, "argv": argv, "cwd": str(cwd), "path": env.get("PATH"),
        "startedAt": started, "finishedAt": now(), "exit": completed.returncode,
        "log": str(log_path.relative_to(REPO)), "logSha256": sha256(log_path),
    }
    if stdin is not None:
        row["stdin"] = stdin
    commands.append(row)
    with COMMANDS.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, sort_keys=True) + "\n")
    print(f"{name} exit={completed.returncode}", flush=True)
    return completed


def main() -> int:
    for path in (LOGS, COMMANDS, PLAN / "linux-build.json", PLAN / "linux-archive.json", PLAN / "linux-smoke.json", PLAN / "package-set.json"):
        if path.exists():
            raise SystemExit(f"refuse overwrite: {path}")
    require((PLAN / "linux-failure.json").is_file() and (PLAN / "linux-failure-resume.json").is_file(), "retained failures")
    require(PACKAGE.is_dir(), "extracted package missing")
    LOGS.mkdir()
    os.close(os.open(COMMANDS, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644))
    tool_env = {"PATH": "/usr/bin:/bin:/home/lsz/.elan/bin", "LC_ALL": "C.UTF-8", "TMPDIR": str(TMP), "HOME": str(TMP)}
    smoke_env = {"PATH": "/usr/bin:/bin", "LC_ALL": "C.UTF-8", "TMPDIR": str(TMP), "HOME": str(TASK / "linux-smoke/home")}

    archive = DIST / f"{NAME}.tar.gz"
    external = DIST / f"{NAME}.build.json"
    sums_path = DIST / "SHA256SUMS"
    sums = {}
    for line in sums_path.read_text(encoding="utf-8").splitlines():
        digest, filename = line.split("  ", 1)
        sums[filename] = digest
        require(sha256(DIST / filename) == digest, filename)
    assets = {path.name for path in DIST.iterdir() if path.is_file()}
    require(assets - set(sums) == {"SHA256SUMS", "release-notes.txt"}, "unlisted files")
    manifest = json.loads(external.read_text(encoding="utf-8"))
    require(manifest["tag"] == TAG and manifest["commit"] == FREEZE, "identity")
    require((PACKAGE / "BUILD.json").read_bytes() == external.read_bytes(), "embedded manifest")

    members = []
    with tarfile.open(archive, "r:gz") as handle:
        entries = handle.getmembers()
        require({entry.name for entry in entries} == EXPECTED_MEMBERS and len(entries) == len(EXPECTED_MEMBERS), "members")
        for entry in entries:
            row = {"name": entry.name, "mode": oct(entry.mode & 0o777), "kind": "dir" if entry.isdir() else "file"}
            if entry.isfile():
                payload = (PACKAGE.parent / entry.name).read_bytes() if False else (TASK / "linux-smoke/extract" / entry.name).read_bytes()
                row["bytes"] = len(payload)
                row["sha256"] = hashlib.sha256(payload).hexdigest()
            members.append(row)

    check_lines = (PLAN / "linux-commands-resume.jsonl").read_text(encoding="utf-8").splitlines()
    check_row = json.loads(next(line for line in check_lines if '"check-archive"' in line))
    require(check_row["exit"] == 0, "prior check-archive")

    binary_rows = {}
    for binary in BINARIES:
        path = PACKAGE / "bin" / binary
        digest = sha256(path)
        require(digest == manifest["binaries"][binary]["sha256"], binary)
        require(stat.S_IMODE(path.stat().st_mode) & 0o111, binary)
        ldd = run(f"ldd-{binary}", ["/usr/bin/ldd", str(path)], PACKAGE, smoke_env, 30)
        require(ldd.returncode == 0 and "not found" not in ldd.stdout, binary)
        libraries = []
        for line in ldd.stdout.splitlines():
            matched = re.match(r"\s*(\S+)\s+=>\s+(\S+)", line)
            if not matched:
                continue
            library, target = matched.groups()
            require(library in SYSTEM_LIBRARIES, library)
            require("/.lake/" not in target and "lean" not in target.lower(), target)
            libraries.append({"soname": library, "target": target, "targetSha256": sha256(Path(target))})
        require({item["soname"] for item in libraries} == set(manifest["binaries"][binary]["libraries"]), binary)
        binary_rows[binary] = {"sha256": digest, "bytes": path.stat().st_size, "libraries": libraries, "ldd": ldd.stdout}

    os_release = run("os-release", ["/usr/bin/cat", "/etc/os-release"], PACKAGE, smoke_env, 30)
    uname = run("uname", ["/usr/bin/uname", "-a"], PACKAGE, smoke_env, 30)
    require("Ubuntu 26.04.1" in os_release.stdout and "WSL2" in uname.stdout, "host")
    absent = run(
        "path-absent",
        ["/usr/bin/bash", "--noprofile", "--norc", "-c", "command -v lean || command -v lake || command -v mirror || true; printf '%s' \"$PATH\""],
        PACKAGE, smoke_env, 30,
    )
    require(absent.returncode == 0 and absent.stdout == "/usr/bin:/bin", f"path {absent.stdout!r} {absent.stderr!r}")
    version = run("version", [str(PACKAGE / "bin/mirror"), "--version"], PACKAGE, smoke_env, 30)
    protocol = run("protocol", [str(PACKAGE / "bin/mirror")], PACKAGE, smoke_env, 30, stdin='{"proto_step":"report_state","state":{}}\n')
    help_run = run("help", [str(PACKAGE / "bin/model_interface_gen"), "--help"], PACKAGE, smoke_env, 30)
    require(version.returncode == 0 and version.stdout == "v0.2.0-rc.6\n" and version.stderr == "", "version")
    require(protocol.returncode == 0 and json.loads(protocol.stdout).get("proto_step") == "protocol_error", "protocol")
    require(help_run.returncode == 2 and "usage:" in help_run.stderr, "help")

    first = (PLAN / "linux-commands.jsonl").read_text(encoding="utf-8").splitlines()
    build_row = json.loads(next(line for line in first if '"release-build"' in line))
    test_row = json.loads(next(line for line in first if '"release-tests"' in line))
    exclusive_json(PLAN / "linux-build.json", {
        "schema": "mirrors.s3-rc6.phase-b.linux-build/v1", "published": False, "deployed": False,
        "at": now(), "phase": "B", "acceptance": "not claimed; Codex owns S3 acceptance",
        "scope": "focused non-model release gates only; no live model checker; no DPM CLI",
        "source": str(SOURCE.relative_to(REPO)), "tag": TAG, "tagObject": TAG_OBJECT, "commit": FREEZE,
        "dist": str(DIST.relative_to(REPO)), "tmpdir": str(TMP.relative_to(REPO)), "tmpdirFilesystem": "ext4",
        "tests": test_row, "build": build_row,
        "passedGates": manifest.get("passedGates"), "buildTools": manifest.get("buildTools"),
        "qualification": manifest.get("qualification"),
        "retainedFailures": [
            "Plans/mainwork-s3-rc6-20261103/linux-failure.json",
            "Plans/mainwork-s3-rc6-20261103/linux-failure-resume.json",
        ],
    })
    archive_record = {
        "schema": "mirrors.s3-rc6.phase-b.linux-archive/v1", "published": False, "deployed": False,
        "at": now(), "tag": TAG, "commit": FREEZE,
        "archive": {"path": str(archive.relative_to(REPO)), "bytes": archive.stat().st_size, "sha256": sha256(archive)},
        "externalManifest": {"path": str(external.relative_to(REPO)), "bytes": external.stat().st_size, "sha256": sha256(external)},
        "sha256sums": {"path": str(sums_path.relative_to(REPO)), "sha256": sha256(sums_path), "entries": sums, "verified": True,
                       "unlistedByBuilderOrder": ["SHA256SUMS", "release-notes.txt"]},
        "maintainedCheckArchive": check_row, "embeddedManifestEqualsExternal": True, "members": members,
        "binaries": {name: {"sha256": binary_rows[name]["sha256"], "bytes": binary_rows[name]["bytes"],
                            "libraries": [item["soname"] for item in binary_rows[name]["libraries"]]} for name in BINARIES},
        "allowedLibraries": sorted(SYSTEM_LIBRARIES),
    }
    exclusive_json(PLAN / "linux-archive.json", archive_record)
    exclusive_json(PLAN / "linux-smoke.json", {
        "schema": "mirrors.s3-rc6.phase-b.linux-smoke/v1", "published": False, "deployed": False, "at": now(),
        "host": {"osRelease": os_release.stdout, "uname": uname.stdout.strip()},
        "historicalUbuntu2404ClaimCopied": False,
        "path": "/usr/bin:/bin", "sourceAbsentFromPath": True, "leanAbsentFromPath": True,
        "pathProbe": {"exit": absent.returncode, "stdout": absent.stdout, "stderr": absent.stderr},
        "mirrorVersion": {"exit": version.returncode, "stdout": version.stdout, "stderr": version.stderr},
        "protocol": {"exit": protocol.returncode, "stdout": protocol.stdout, "stderr": protocol.stderr},
        "modelInterfaceGenHelp": {"exit": help_run.returncode, "stderr": help_run.stderr},
        "ldd": {name: binary_rows[name]["ldd"] for name in BINARIES},
        "libraryTargets": {name: binary_rows[name]["libraries"] for name in BINARIES},
        "toolEnvUsedForBuildOnly": tool_env["PATH"],
        "scope": "second isolated runtime smoke on the observed Ubuntu 26.04.1 WSL2 host",
    })
    exclusive_json(PLAN / "package-set.json", {
        "schema": "mirrors.s3-rc6.phase-b.package-set/v1", "published": False, "deployed": False, "at": now(),
        "acceptance": "package records only; not full S3 acceptance and not Codex acceptance",
        "tag": TAG, "tagObject": TAG_OBJECT, "commit": FREEZE,
        "scope": "focused non-model Linux gates and isolated runtime smoke only",
        "modelCheckerRun": False, "dpmCliPackaged": False, "fullLakeTest": False,
        "archiveSha256": archive_record["archive"]["sha256"],
        "externalManifestSha256": archive_record["externalManifest"]["sha256"],
        "checksumsSha256": archive_record["sha256sums"]["sha256"],
        "binaries": {name: binary_rows[name]["sha256"] for name in BINARIES},
        "passedGates": manifest.get("passedGates"),
        "retainedFailures": [
            "Plans/mainwork-s3-rc6-20261103/linux-failure.json",
            "Plans/mainwork-s3-rc6-20261103/linux-failure-resume.json",
        ],
    })
    print(f"PHASE_B_SMOKE_OK archive={archive_record['archive']['sha256']}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        target = PLAN / "linux-failure-smoke.json"
        if not target.exists():
            exclusive_json(target, {"schema": "mirrors.s3-rc6.phase-b.failure/v1", "published": False, "deployed": False,
                                     "at": now(), "error": str(exc), "commands": commands})
        print(f"PHASE_B_SMOKE_FAILED {exc}", flush=True)
        raise
