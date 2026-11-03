#!/usr/bin/env python3
"""Phase B: maintained Linux release build, archive checks, and a second isolated smoke.

Does not push, deploy, start a model checker, or edit the clean source, tag, archive,
Batteries input, shared checkout, or Windows records. Refuses to overwrite an existing
output path. Every material command is retained with argv, exit, and raw logs.
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
LOGS = TASK / "linux-logs"
TAG = "v0.2.0-rc.6"
FREEZE = "3c4a87309cc3a81924660497207d7c295759bdc1"
TAG_OBJECT = "5a2a6fd8728b610db7a6225b4a9d4c5d585344aa"
BATTERIES = TASK / "inputs/batteries"
BATTERIES_REV = "4488d40d070b9700d4d5a6aa342f0d40c31b2a2d"
NAME = "mirrors-v0.2.0-rc.6-linux-x86_64"
EXPECTED_MEMBERS = {
    NAME,
    f"{NAME}/bin",
    f"{NAME}/bin/mirror",
    f"{NAME}/bin/model_interface_gen",
    f"{NAME}/README.txt",
    f"{NAME}/BUILD.json",
}
SYSTEM_LIBRARIES = {
    "libssl.so.3", "libcrypto.so.3", "libgmp.so.10", "libc.so.6", "libm.so.6",
    "libpthread.so.0", "libdl.so.2", "librt.so.1", "libgcc_s.so.1",
    "libstdc++.so.6", "libatomic.so.1", "libz.so.1", "libuv.so.1",
}
BINARIES = ("mirror", "model_interface_gen")
OWNED = (
    PLAN / "linux-build.json",
    PLAN / "linux-archive.json",
    PLAN / "linux-smoke.json",
    PLAN / "linux-package-set.json",
    PLAN / "package-set.json",
    PLAN / "linux-commands.jsonl",
    PLAN / "linux-failure.json",
    DIST, TMP, SMOKE_ROOT, LOGS,
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


def refuse_existing() -> None:
    present = [str(path.relative_to(REPO)) for path in OWNED if path.exists()]
    if present:
        raise SystemExit("refuse overwrite: " + ", ".join(present))


def exclusive_json(path: Path, payload: dict) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    fd = os.open(path, flags, 0o644)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def run(name: str, argv: list[str], cwd: Path, env: dict, timeout: int) -> subprocess.CompletedProcess[str]:
    LOGS.mkdir(parents=True, exist_ok=True)
    log_path = LOGS / f"{len(commands):04d}-{name}.log"
    if log_path.exists():
        raise SystemExit(f"refuse overwrite: {log_path}")
    started = now()
    try:
        completed = subprocess.run(
            argv, cwd=cwd, env=env, text=True, capture_output=True, timeout=timeout, check=False,
        )
        timed_out = False
    except subprocess.TimeoutExpired as exc:
        completed = subprocess.CompletedProcess(argv, 124, exc.stdout or "", exc.stderr or "")
        timed_out = True
    raw = (
        f"$ {' '.join(argv)}\n# cwd={cwd}\n# exit={completed.returncode} timeout={timed_out}\n"
        f"# --- stdout ---\n{completed.stdout}\n# --- stderr ---\n{completed.stderr}"
    )
    log_path.write_text(raw, encoding="utf-8")
    row = {
        "name": name,
        "argv": argv,
        "cwd": str(cwd),
        "startedAt": started,
        "finishedAt": now(),
        "exit": completed.returncode,
        "timedOut": timed_out,
        "log": str(log_path.relative_to(REPO)),
        "logBytes": log_path.stat().st_size,
        "logSha256": sha256(log_path),
        "stdoutBytes": len(completed.stdout.encode()),
        "stderrBytes": len(completed.stderr.encode()),
    }
    commands.append(row)
    with (PLAN / "linux-commands.jsonl").open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, sort_keys=True) + "\n")
    print(f"{name} exit={completed.returncode} log={row['log']}", flush=True)
    return completed


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def base_env() -> dict:
    env = dict(os.environ)
    for key in ("APALACHE_MC", "APALACHE_JAR", "TLA2TOOLS_JAR", "LD_LIBRARY_PATH", "LD_PRELOAD"):
        env.pop(key, None)
    env["TMPDIR"] = str(TMP)
    env["TMP"] = str(TMP)
    env["TEMP"] = str(TMP)
    env["LC_ALL"] = "C.UTF-8"
    env["PATH"] = "/home/lsz/.elan/bin:" + env.get("PATH", "")
    env["GIT_CONFIG_COUNT"] = "1"
    env["GIT_CONFIG_KEY_0"] = f"url.{BATTERIES}/.insteadOf"
    env["GIT_CONFIG_VALUE_0"] = "https://github.com/leanprover-community/batteries"
    env["GIT_CONFIG_GLOBAL"] = "/dev/null"
    env["GIT_CONFIG_SYSTEM"] = "/dev/null"
    return env


def main() -> int:
    refuse_existing()
    for path in (TMP, LOGS):
        path.mkdir()
    fd = os.open(PLAN / "linux-commands.jsonl", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    os.close(fd)
    env = base_env()
    fs_probe = run("tmpdir-fstype", ["findmnt", "-no", "FSTYPE,TARGET", "--target", str(TMP)], REPO, env, 30)
    require(fs_probe.returncode == 0 and fs_probe.stdout.split()[0] == "ext4", "TMPDIR is not ext4")

    phase_a = run("phase-a-verifier", ["python3", str(PLAN / "verify.py")], REPO, env, 180)
    require(phase_a.returncode == 0, "phase A verifier failed")

    identity_head = run("source-head", ["git", "-C", str(SOURCE), "rev-parse", "HEAD"], REPO, env, 30)
    identity_peel = run(
        "source-tag-peel", ["git", "-C", str(SOURCE), "rev-parse", f"refs/tags/{TAG}^{{commit}}"], REPO, env, 30,
    )
    identity_tag = run("source-tag-object", ["git", "-C", str(SOURCE), "rev-parse", f"refs/tags/{TAG}"], REPO, env, 30)
    batteries_head = run("batteries-head", ["git", "-C", str(BATTERIES), "rev-parse", "HEAD"], REPO, env, 30)
    require(identity_head.stdout.strip() == FREEZE, "clean source HEAD")
    require(identity_peel.stdout.strip() == FREEZE, "tag peel")
    require(identity_tag.stdout.strip() == TAG_OBJECT, "tag object")
    require(batteries_head.stdout.strip() == BATTERIES_REV, "batteries revision")

    tests = run(
        "release-tests",
        ["python3", "-m", "unittest", "discover", "-s", "tools/release", "-p", "test_*.py", "-v"],
        REPO, env, 600,
    )
    require(tests.returncode == 0, "release tests failed")

    build = run(
        "release-build",
        ["python3", "tools/release/release.py", "build", "--source", str(SOURCE), "--tag", TAG, "--output", str(DIST)],
        REPO, env, 3600,
    )
    require(build.returncode == 0, "release build failed")
    after = run("source-status-after", ["git", "-C", str(SOURCE), "status", "--porcelain=v1"], REPO, env, 30)
    require(after.stdout.strip() == "", "clean source status changed")
    shared_tag = run(
        "shared-tag-absent", ["git", "-C", str(REPO), "rev-parse", "-q", "--verify", f"refs/tags/{TAG}"], REPO, env, 30,
    )
    require(shared_tag.returncode != 0, "shared checkout gained the rc.6 tag")

    archive = DIST / f"{NAME}.tar.gz"
    external = DIST / f"{NAME}.build.json"
    sums_path = DIST / "SHA256SUMS"
    require(archive.is_file() and external.is_file() and sums_path.is_file(), "expected dist outputs missing")
    sums = {}
    for line in sums_path.read_text(encoding="utf-8").splitlines():
        digest, filename = line.split("  ", 1)
        sums[filename] = digest
        require(sha256(DIST / filename) == digest, f"SHA256SUMS mismatch {filename}")
    assets = {path.name for path in DIST.iterdir() if path.is_file()}
    # release.py hashes the directory, then writes SHA256SUMS and release-notes.txt.
    # Those two names are absent from the checksum file by construction.
    require(assets - set(sums) == {"SHA256SUMS", "release-notes.txt"}, f"unexpected unlisted dist files: {sorted(assets - set(sums))}")
    require(set(sums) <= assets, f"SHA256SUMS names a missing file: {sorted(set(sums) - assets)}")

    check = run(
        "check-archive",
        ["python3", "tools/release/release.py", "check-archive", "--tag", TAG, "--archive", str(archive)],
        REPO, env, 180,
    )
    require(check.returncode == 0, "maintained check-archive failed")

    manifest = json.loads(external.read_text(encoding="utf-8"))
    require(manifest["tag"] == TAG and manifest["commit"] == FREEZE, "external manifest identity")
    require(manifest["embeddedVersion"] == "0.2.0-rc.6", "embedded version")
    require(manifest["expectedVersionOutput"] == "v0.2.0-rc.6\n", "expected version output")
    require(manifest.get("historical") is False and manifest.get("prerelease") is True, "release flags")
    require("focused non-model" in manifest.get("qualification", ""), "qualification scope")
    require("model checker" not in " ".join(manifest.get("passedGates", [])).lower(), "model gate recorded")

    members = []
    with tarfile.open(archive, "r:gz") as handle:
        entries = handle.getmembers()
        names = [entry.name for entry in entries]
        require(set(names) == EXPECTED_MEMBERS and len(names) == len(EXPECTED_MEMBERS), f"members {sorted(names)}")
        require(all(entry.isfile() or entry.isdir() for entry in entries), "non-regular archive member")
        require(all(not entry.issym() and not entry.islnk() for entry in entries), "link member")
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
    embedded = (package / "BUILD.json").read_bytes()
    require(embedded == external.read_bytes(), "embedded BUILD.json differs from external manifest")
    binary_rows = {}
    for binary in BINARIES:
        path = package / "bin" / binary
        digest = sha256(path)
        require(digest == manifest["binaries"][binary]["sha256"], f"{binary} hash")
        mode = stat.S_IMODE(path.stat().st_mode)
        require(mode & 0o111, f"{binary} is not executable")
        ldd = run(f"ldd-{binary}", ["ldd", str(path)], package, env, 30)
        require(ldd.returncode == 0 and "not found" not in ldd.stdout, f"ldd {binary}")
        libraries = []
        for line in ldd.stdout.splitlines():
            matched = re.match(r"\s*(\S+)\s+=>\s+(\S+)", line)
            if not matched:
                continue
            library, target = matched.groups()
            libraries.append({"soname": library, "target": target, "targetSha256": sha256(Path(target))})
            require(library in SYSTEM_LIBRARIES, f"library outside closure: {library}")
            lowered = target.lower()
            require("/.lake/" not in lowered and "lean" not in lowered, f"non-system library {target}")
        recorded = set(manifest["binaries"][binary]["libraries"])
        require(recorded <= SYSTEM_LIBRARIES and {item["soname"] for item in libraries} == recorded, f"{binary} library set")
        binary_rows[binary] = {"sha256": digest, "bytes": path.stat().st_size, "libraries": libraries, "ldd": ldd.stdout}

    os_release = run("smoke-os-release", ["cat", "/etc/os-release"], REPO, env, 30)
    uname = run("smoke-uname", ["uname", "-a"], REPO, env, 30)
    require("Ubuntu 26.04.1" in os_release.stdout, "host is not Ubuntu 26.04.1")
    require("WSL2" in uname.stdout, "host is not WSL2")
    smoke_env = {
        "PATH": "/usr/bin:/bin",
        "HOME": str(SMOKE_ROOT / "home"),
        "TMPDIR": str(TMP),
        "LC_ALL": "C.UTF-8",
        "LANG": "C.UTF-8",
    }
    (SMOKE_ROOT / "home").mkdir()
    absent = run(
        "smoke-path-absent",
        ["bash", "-lc", "command -v lean >/dev/null || command -v lake >/dev/null || command -v mirror >/dev/null; status=$?; printf '%s' \"$PATH\"; exit \"$status\""],
        package, smoke_env, 30,
    )
    require(absent.returncode != 0, "lean, lake, or mirror resolved on the packaged PATH")
    require(absent.stdout == "/usr/bin:/bin", f"packaged PATH {absent.stdout!r}")
    require(str(SOURCE) not in smoke_env["PATH"] and ".elan" not in smoke_env["PATH"], "source or Lean on PATH")
    version = run("smoke-version", [str(package / "bin/mirror"), "--version"], package, smoke_env, 30)
    protocol_log = LOGS / f"{len(commands):04d}-smoke-protocol-stdin.log"
    started = now()
    completed = subprocess.run(
        [str(package / "bin/mirror")], cwd=package, env=smoke_env, input='{"proto_step":"report_state","state":{}}\n',
        text=True, capture_output=True, timeout=30, check=False,
    )
    protocol_log.write_text(
        f"$ {package / 'bin/mirror'}\n# stdin protocol line\n# exit={completed.returncode}\n"
        f"# --- stdout ---\n{completed.stdout}\n# --- stderr ---\n{completed.stderr}",
        encoding="utf-8",
    )
    row = {
        "name": "smoke-protocol-stdin",
        "argv": [str(package / "bin/mirror")],
        "cwd": str(package),
        "startedAt": started,
        "finishedAt": now(),
        "exit": completed.returncode,
        "timedOut": False,
        "log": str(protocol_log.relative_to(REPO)),
        "logBytes": protocol_log.stat().st_size,
        "logSha256": sha256(protocol_log),
        "stdin": '{"proto_step":"report_state","state":{}}\\n',
    }
    commands.append(row)
    with (PLAN / "linux-commands.jsonl").open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, sort_keys=True) + "\n")
    help_run = run("smoke-help", [str(package / "bin/model_interface_gen"), "--help"], package, smoke_env, 30)
    require(version.returncode == 0 and version.stdout == "v0.2.0-rc.6\n" and version.stderr == "", "version smoke")
    message = json.loads(completed.stdout)
    require(completed.returncode == 0 and message.get("proto_step") == "protocol_error", "protocol smoke")
    require(help_run.returncode == 2 and "usage:" in help_run.stderr, "help smoke")

    build_row = next(item for item in commands if item["name"] == "release-build")
    test_row = next(item for item in commands if item["name"] == "release-tests")
    check_row = next(item for item in commands if item["name"] == "check-archive")
    linux_build = {
        "schema": "mirrors.s3-rc6.phase-b.linux-build/v1",
        "published": False,
        "deployed": False,
        "at": now(),
        "phase": "B",
        "acceptance": "not claimed; Codex owns S3 acceptance",
        "scope": "focused non-model release gates only; no live model checker; no DPM CLI",
        "source": str(SOURCE.relative_to(REPO)),
        "tag": TAG,
        "tagObject": TAG_OBJECT,
        "commit": FREEZE,
        "batteriesRevision": BATTERIES_REV,
        "batteriesBinding": "process-local git insteadOf to the verified offline clone; source lakefile unchanged",
        "tmpdir": str(TMP.relative_to(REPO)),
        "tmpdirFilesystem": fs_probe.stdout.strip(),
        "dist": str(DIST.relative_to(REPO)),
        "tests": test_row,
        "build": build_row,
        "sourceStatusAfter": after.stdout,
        "sharedTagAbsent": shared_tag.returncode != 0,
        "passedGates": manifest.get("passedGates"),
        "buildTools": manifest.get("buildTools"),
        "qualification": manifest.get("qualification"),
    }
    linux_archive = {
        "schema": "mirrors.s3-rc6.phase-b.linux-archive/v1",
        "published": False,
        "deployed": False,
        "at": now(),
        "tag": TAG,
        "commit": FREEZE,
        "archive": {"path": str(archive.relative_to(REPO)), "bytes": archive.stat().st_size, "sha256": sha256(archive)},
        "externalManifest": {"path": str(external.relative_to(REPO)), "bytes": external.stat().st_size, "sha256": sha256(external)},
        "sha256sums": {"path": str(sums_path.relative_to(REPO)), "sha256": sha256(sums_path), "entries": sums, "verified": True},
        "maintainedCheckArchive": check_row,
        "embeddedManifestEqualsExternal": True,
        "members": members,
        "binaries": {name: {"sha256": binary_rows[name]["sha256"], "bytes": binary_rows[name]["bytes"],
                            "libraries": [item["soname"] for item in binary_rows[name]["libraries"]]} for name in BINARIES},
        "libraryClosure": "SYSTEM_LIBRARIES from the maintained release contract; targets resolved outside .lake and lean",
        "allowedLibraries": sorted(SYSTEM_LIBRARIES),
    }
    linux_smoke = {
        "schema": "mirrors.s3-rc6.phase-b.linux-smoke/v1",
        "published": False,
        "deployed": False,
        "at": now(),
        "host": {"osRelease": os_release.stdout, "uname": uname.stdout.strip()},
        "historicalUbuntu2404ClaimCopied": False,
        "path": smoke_env["PATH"],
        "sourceAbsentFromPath": True,
        "leanAbsentFromPath": True,
        "pathProbe": {"exit": absent.returncode, "stdout": absent.stdout, "stderr": absent.stderr},
        "mirrorVersion": {"exit": version.returncode, "stdout": version.stdout, "stderr": version.stderr},
        "protocol": {"exit": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr},
        "modelInterfaceGenHelp": {"exit": help_run.returncode, "stderr": help_run.stderr},
        "ldd": {name: binary_rows[name]["ldd"] for name in BINARIES},
        "libraryTargets": {name: binary_rows[name]["libraries"] for name in BINARIES},
        "scope": "second isolated runtime smoke of the packaged archive on the observed Ubuntu 26.04.1 WSL2 host",
    }
    package_set = {
        "schema": "mirrors.s3-rc6.phase-b.package-set/v1",
        "published": False,
        "deployed": False,
        "at": now(),
        "acceptance": "package records only; not full S3 acceptance and not Codex acceptance",
        "tag": TAG,
        "tagObject": TAG_OBJECT,
        "commit": FREEZE,
        "scope": "focused non-model Linux gates and isolated runtime smoke only",
        "modelCheckerRun": False,
        "dpmCliPackaged": False,
        "fullLakeTest": False,
        "archiveSha256": linux_archive["archive"]["sha256"],
        "externalManifestSha256": linux_archive["externalManifest"]["sha256"],
        "checksumsSha256": linux_archive["sha256sums"]["sha256"],
        "binaries": {name: binary_rows[name]["sha256"] for name in BINARIES},
        "passedGates": manifest.get("passedGates"),
        "records": {
            "linux-build": "Plans/mainwork-s3-rc6-20261103/linux-build.json",
            "linux-archive": "Plans/mainwork-s3-rc6-20261103/linux-archive.json",
            "linux-smoke": "Plans/mainwork-s3-rc6-20261103/linux-smoke.json",
        },
    }
    exclusive_json(PLAN / "linux-build.json", linux_build)
    exclusive_json(PLAN / "linux-archive.json", linux_archive)
    exclusive_json(PLAN / "linux-smoke.json", linux_smoke)
    exclusive_json(PLAN / "package-set.json", package_set)
    print(
        f"PHASE_B_OK archive={linux_archive['archive']['sha256']} "
        f"mirror={binary_rows['mirror']['sha256']} gen={binary_rows['model_interface_gen']['sha256']}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        failure = {
            "schema": "mirrors.s3-rc6.phase-b.failure/v1",
            "published": False,
            "deployed": False,
            "at": now(),
            "error": str(exc),
            "commands": commands,
            "acceptance": "not claimed",
        }
        target = PLAN / "linux-failure.json"
        if not target.exists():
            exclusive_json(target, failure)
        print(f"PHASE_B_FAILED {exc}", flush=True)
        raise
