#!/usr/bin/env python3
"""Offline Codex verification for the bounded S3 rc.6 package set."""

from __future__ import annotations

import hashlib
import json
import struct
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
TASK = ROOT / ".golden-build/mainwork-s3-rc6-20261103"
REVIEW = ROOT / ".golden-build/mainwork-s3-rc6-review-20261103"
SOURCE = TASK / "source"
BATTERIES = TASK / "inputs/batteries"
ARCHIVE = TASK / "archive/mirrors-v0.2.0-rc.6-source.tar.gz"
LINUX = TASK / "linux-dist"
WINDOWS = TASK / "dist-windows"
TAG = "v0.2.0-rc.6"
TAG_OBJECT = "5a2a6fd8728b610db7a6225b4a9d4c5d585344aa"
COMMIT = "3c4a87309cc3a81924660497207d7c295759bdc1"
TREE = "5c15228e006f4d1b6efaa7e088488bc4b1fe619e"
BATTERIES_REV = "4488d40d070b9700d4d5a6aa342f0d40c31b2a2d"
BATTERIES_TREE = "5a1de86f7997958aaffec998882c29006b688d1e"
SOURCE_SHA = "87ab9dee6c1a247da0ef4f1a7028c941323997202721ccada2e6ef6c62371a62"
LINUX_ARCHIVE_SHA = "9dc8e0ce2203c155bf8150479fd25e19bb5cd9774a6b688fd38fc57e74022038"
WINDOWS_ARCHIVE_SHA = "9919ac2cb96a3dd693df89b02059a559f25aff7e052efc00a60a2e569c87564e"
LINUX_NAME = f"mirrors-{TAG}-linux-x86_64"
WINDOWS_NAME = f"mirrors-{TAG}-windows-x86_64"
LINUX_GATES = ["fixtures_replay", "diff_cross", "model_interface_spec", "stdio_smoke",
               "transport_spec", "check-client-framing.py", "relocated-binary-cli-smoke"]
WINDOWS_GATES = ["fixtures_replay", "diff_cross", "model_interface_spec", "stdio_smoke",
                 "transport_spec", "jobstore_spec", "async_resource_spec", "dpm_sync_spec"]
SYSTEM_DLLS = {item.lower() for item in (
    "ADVAPI32.dll", "IPHLPAPI.DLL", "KERNEL32.dll", "SHELL32.dll", "USER32.dll",
    "USERENV.dll", "WS2_32.dll", "bcrypt.dll", "dbghelp.dll", "icu.dll", "ole32.dll",
    "ucrtbase.dll", "msvcrt.dll", "CRYPT32.dll", "ntdll.dll")}


class S3Error(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise S3Error(message)


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def git(repository: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(repository), *args], capture_output=True, check=False)
    require(result.returncode == 0, f"git failed at {repository}: {args}: {result.stderr!r}")
    return result.stdout.decode().strip()


def check_linux_manifest(manifest: dict) -> None:
    require(manifest["tag"] == TAG and manifest["commit"] == COMMIT, "Linux tag/source mismatch")
    require(manifest["embeddedVersion"] == "0.2.0-rc.6", "Linux product version mismatch")
    require(manifest["passedGates"] == LINUX_GATES, "Linux gate set mismatch")
    require("focused non-model" in manifest["qualification"], "Linux qualification scope missing")
    require(set(manifest["binaries"]) == {"mirror", "model_interface_gen"}, "Linux binary set mismatch")


def check_windows_manifest(manifest: dict) -> None:
    require(manifest["tag"] == TAG and manifest["sourceCommit"] == COMMIT, "Windows tag/source mismatch")
    require(manifest["sourceTree"] == TREE and manifest["sourceFileCount"] == 9833,
            "Windows source tree/count mismatch")
    require(manifest["sourceOverlay"] is False, "Windows source overlay claimed")
    require(manifest["embeddedVersion"] == "0.2.0-rc.6", "Windows product version mismatch")
    require([entry["gate"] for entry in manifest["gates"]] == WINDOWS_GATES,
            "Windows gate set mismatch")
    require(all(entry["exit"] == 0 for entry in manifest["gates"]), "Windows gate failure")
    require(manifest["published"] is False and manifest["deployed"] is False,
            "Windows publication state changed")
    require(manifest["fullLakeTest"] is False and manifest["releaseAdmission"] is False,
            "Windows overclaims qualification")


def pe_imports(data: bytes) -> set[str]:
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    require(data[pe:pe + 4] == b"PE\0\0", "invalid PE signature")
    coff = pe + 4
    sections = struct.unpack_from("<H", data, coff + 2)[0]
    opt_size = struct.unpack_from("<H", data, coff + 16)[0]
    opt = coff + 20
    require(struct.unpack_from("<H", data, opt)[0] == 0x20B, "not PE32+")
    directories = opt + 112
    table = []
    for index in range(sections):
        offset = opt + opt_size + 40 * index
        virtual_size, virtual_address, raw_size, raw_pointer = struct.unpack_from("<IIII", data, offset + 8)
        table.append((virtual_address, virtual_size, raw_pointer, raw_size))

    def file_offset(rva: int) -> int:
        for virtual_address, virtual_size, raw_pointer, raw_size in table:
            if virtual_address <= rva < virtual_address + max(virtual_size, raw_size):
                return raw_pointer + rva - virtual_address
        raise S3Error(f"unmapped PE RVA 0x{rva:x}")

    names = set()
    rva = struct.unpack_from("<I", data, directories + 8)[0]
    while rva:
        offset = file_offset(rva)
        name_rva = struct.unpack_from("<I", data, offset + 12)[0]
        if name_rva == 0:
            break
        target = file_offset(name_rva)
        names.add(data[target:data.index(b"\0", target)].decode("ascii"))
        rva += 20
    return names


def check_source_after() -> None:
    expected = {row["path"]: row for row in load(TASK / "archive/source-manifest.json")["files"]}
    rows = [json.loads(line) for line in (REVIEW / "review-source-after.jsonl").read_text().splitlines()
            if line.strip()]
    seen = {row["path"]: row for row in rows}
    require(len(rows) == len(seen), "duplicate post-build source path")
    missing = sorted(set(expected) - set(seen))
    changed = sorted(path for path, row in expected.items() if path in seen and
                     (seen[path]["bytes"] != row["bytes"] or seen[path]["sha256"] != row["sha256"]))
    extra = sorted(path for path in seen if path not in expected and not path.startswith(".lake/"))
    require(not missing and not changed and len(expected) == 9833,
            f"post-build original source changed: missing={missing[:3]} changed={changed[:3]}")
    require(extra == [".golden-build/model-interface-rust/CorpusMirror.generated.rs",
                      ".golden-build/model-interface-rust/MultiMirror.generated.rs"],
            f"unexpected post-build source additions: {extra}")


def check_inventory() -> None:
    inventory = load(PLAN / "inventory.json")
    entries = inventory["files"]
    paths = [entry["path"] for entry in entries]
    require(len(paths) == len(set(paths)), "duplicate inventory path")
    require(str(PLAN.relative_to(ROOT) / "inventory.json") not in paths, "inventory self-hash")
    for entry in entries:
        path = ROOT / entry["path"]
        require(path.is_file(), f"missing inventory file: {entry['path']}")
        require(path.stat().st_size == entry["bytes"] and sha(path) == entry["sha256"],
                f"stale inventory file: {entry['path']}")
    expected = {entry["path"] for entry in entries if entry["class"] == "git-payload"}
    actual = {str(path.relative_to(ROOT)) for path in PLAN.rglob("*")
              if path.is_file() and path.name != "inventory.json" and "__pycache__" not in path.parts}
    require(actual == expected, f"plan inventory closure mismatch: {sorted(actual ^ expected)[:8]}")


def negative_controls(linux_manifest: dict, windows_manifest: dict) -> None:
    stale = json.loads(json.dumps(linux_manifest))
    stale["tag"] = "v0.2.0-rc.5"
    try:
        check_linux_manifest(stale)
    except S3Error:
        pass
    else:
        raise S3Error("negative control accepted a stale Linux tag")
    missing_gate = json.loads(json.dumps(windows_manifest))
    missing_gate["gates"].pop()
    try:
        check_windows_manifest(missing_gate)
    except S3Error:
        pass
    else:
        raise S3Error("negative control accepted a missing Windows gate")
    require("NEW-UNREVIEWED.dll".lower() not in SYSTEM_DLLS, "DLL negative control setup failed")


def main() -> int:
    subprocess.run([sys.executable, str(PLAN / "verify.py")], cwd=ROOT, check=True)
    require(git(SOURCE, "rev-parse", "HEAD") == COMMIT, "source HEAD mismatch")
    require(git(SOURCE, "rev-parse", f"refs/tags/{TAG}") == TAG_OBJECT, "tag object mismatch")
    require(git(SOURCE, "rev-parse", f"refs/tags/{TAG}^{{commit}}") == COMMIT, "tag peel mismatch")
    require(git(SOURCE, "status", "--porcelain=v1") == "", "source clone is dirty")
    require(git(BATTERIES, "rev-parse", "HEAD") == BATTERIES_REV, "Batteries revision mismatch")
    require(git(BATTERIES, "rev-parse", "HEAD^{tree}") == BATTERIES_TREE, "Batteries tree mismatch")
    require(git(BATTERIES, "status", "--porcelain=v1") == "", "Batteries checkout is dirty")
    require(subprocess.run(["git", "-C", str(ROOT), "rev-parse", "-q", "--verify",
                            f"refs/tags/{TAG}"], capture_output=True).returncode != 0,
            "shared checkout gained the local packaging tag")
    require(sha(ARCHIVE) == SOURCE_SHA, "source archive hash mismatch")
    source_manifest = load(TASK / "archive/source-manifest.json")
    require(source_manifest["fileCount"] == 9833 and source_manifest["commit"] == COMMIT,
            "source manifest mismatch")
    with tarfile.open(ARCHIVE, "r:gz") as handle:
        require(sum(member.isfile() for member in handle.getmembers()) == 9833,
                "source archive file count mismatch")

    linux_archive = LINUX / f"{LINUX_NAME}.tar.gz"
    linux_external = LINUX / f"{LINUX_NAME}.build.json"
    require(sha(linux_archive) == LINUX_ARCHIVE_SHA, "Linux archive hash mismatch")
    linux_manifest = load(linux_external)
    check_linux_manifest(linux_manifest)
    for line in (LINUX / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        require(sha(LINUX / name) == digest, f"Linux checksum mismatch: {name}")
    subprocess.run([sys.executable, "tools/release/release.py", "check-archive", "--tag", TAG,
                    "--archive", str(linux_archive)], cwd=ROOT, check=True)
    with tarfile.open(linux_archive, "r:gz") as handle:
        names = {member.name for member in handle.getmembers()}
        expected = {LINUX_NAME, f"{LINUX_NAME}/bin", f"{LINUX_NAME}/bin/mirror",
                    f"{LINUX_NAME}/bin/model_interface_gen", f"{LINUX_NAME}/README.txt",
                    f"{LINUX_NAME}/BUILD.json"}
        require(names == expected, "Linux archive member mismatch")
        require(handle.extractfile(f"{LINUX_NAME}/BUILD.json").read() == linux_external.read_bytes(),
                "Linux embedded/external manifest mismatch")
        for binary, record in linux_manifest["binaries"].items():
            data = handle.extractfile(f"{LINUX_NAME}/bin/{binary}").read()
            require(hashlib.sha256(data).hexdigest() == record["sha256"], f"Linux binary mismatch: {binary}")
    smoke = load(PLAN / "linux-smoke.json")
    require("Ubuntu 26.04.1" in smoke["host"]["osRelease"] and "WSL2" in smoke["host"]["uname"],
            "Linux smoke host mismatch")
    require(smoke["path"] == "/usr/bin:/bin" and smoke["sourceAbsentFromPath"] and
            smoke["leanAbsentFromPath"], "Linux smoke isolation failed")
    require(smoke["mirrorVersion"]["exit"] == 0 and
            smoke["mirrorVersion"]["stdout"] == "v0.2.0-rc.6\n", "Linux smoke version failed")
    require(smoke["protocol"]["exit"] == 0 and "protocol_error" in smoke["protocol"]["stdout"],
            "Linux protocol smoke failed")

    windows_archive = WINDOWS / f"{WINDOWS_NAME}.zip"
    windows_repeat = WINDOWS / f"{WINDOWS_NAME}-repeat.zip"
    windows_external = WINDOWS / f"{WINDOWS_NAME}.build.json"
    require(sha(windows_archive) == WINDOWS_ARCHIVE_SHA, "Windows archive hash mismatch")
    require(windows_archive.read_bytes() == windows_repeat.read_bytes(), "Windows repeat ZIP differs")
    windows_manifest = load(windows_external)
    check_windows_manifest(windows_manifest)
    for line in (WINDOWS / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        require(sha(WINDOWS / name) == digest, f"Windows checksum mismatch: {name}")
    binary_names = ("ModelMirrors.exe", "model_interface_gen.exe", "libcrypto-3-x64.dll",
                    "libssl-3-x64.dll", "zlib1.dll")
    packaged_dlls = {path.lower() for path in binary_names}
    with zipfile.ZipFile(windows_archive) as handle:
        expected = {f"{WINDOWS_NAME}/BUILD.json", f"{WINDOWS_NAME}/README.txt",
                    *(f"{WINDOWS_NAME}/bin/{name}" for name in binary_names)}
        require(set(handle.namelist()) == expected, "Windows archive member mismatch")
        require(handle.read(f"{WINDOWS_NAME}/BUILD.json") == windows_external.read_bytes(),
                "Windows embedded/external manifest mismatch")
        for relative, record in windows_manifest["files"].items():
            data = handle.read(f"{WINDOWS_NAME}/{relative}")
            require(len(data) == record["bytes"] and hashlib.sha256(data).hexdigest() == record["sha256"],
                    f"Windows payload mismatch: {relative}")
            if relative.endswith((".exe", ".dll")):
                imports = pe_imports(data)
                unknown = [name for name in imports if name.lower() not in SYSTEM_DLLS | packaged_dlls
                           and not name.lower().startswith("api-ms-win-")]
                require(not unknown, f"Windows PE imports outside closure: {relative}: {unknown}")
    for gate in windows_manifest["gates"]:
        log = WINDOWS / "logs" / f"{gate['gate']}.log"
        require(log.is_file() and sha(log) == gate["logSha256"], f"Windows gate log mismatch: {gate['gate']}")
    check_source_after()
    package_set = load(PLAN / "s3-package-set.json")
    require(package_set["tag"] == TAG and package_set["tagObject"] == TAG_OBJECT and
            package_set["commit"] == COMMIT, "unified package-set identity mismatch")
    require(package_set["linux"]["archive"]["sha256"] == LINUX_ARCHIVE_SHA and
            package_set["windows"]["archive"]["sha256"] == WINDOWS_ARCHIVE_SHA,
            "unified package-set artifact mismatch")
    require(package_set["published"] is False and package_set["deployed"] is False and
            package_set["releaseAdmission"] is False, "unified package-set overclaims release")
    negative_controls(linux_manifest, windows_manifest)
    check_inventory()
    print("S3 RC6 VERIFY GREEN")
    print("SOURCE/TAG + LINUX + WINDOWS + PE + SOURCE-AFTER + INVENTORY + NEGATIVE CONTROLS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (S3Error, KeyError, ValueError, subprocess.CalledProcessError) as error:
        print(f"S3 RC6 VERIFY FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
