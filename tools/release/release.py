#!/usr/bin/env python3
"""Build and package an unchanged Mirrors tag; never start a model checker."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile


# Exceptions apply only to these immutable source commits, never to a new tag.
# None means that the original executable has no --version mode.
HISTORICAL = {
    "v0.0.1": ("df2f91aa052fedbbe7d544fb0e3d28565e04114f", None, None),
    "v0.0.2": ("eb5cd001b990e6ac5e9b1e9b1c5a17ffb85e25fc", "0.0.2", "Mirrors 0.0.2\n"),
    "v0.0.3": ("81cfa3e7db6905b2c5d0aa9c05ae2659560828ef", "0.0.2", "Mirrors 0.0.2\n"),
    "v0.0.3.1": ("1a069cd3e34d7bfea272e3ee7e10f51acedcc7cb", "0.0.3", "Mirrors 0.0.3\n"),
    "v0.0.3.2": ("c674ead1164bf9d0d9dcb932e8a95a73cfeaebee", "0.0.3", "Mirrors 0.0.3\n"),
    "v0.0.3.3": ("ea8091c0c723f3f561044a5c1efb91d12e7aaf5f", "0.0.3.2", "v0.0.3.2\n"),
}
TAG_PATTERN = r"v(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){2}(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?"
GATES = ("fixtures_replay", "diff_cross", "model_interface_spec", "stdio_smoke", "transport_spec")
BINARIES = ("mirror", "model_interface_gen")
# The archive relies on distribution-maintained system libraries. A dependency
# on a build-tree/Lean shared library must fail instead of shipping a broken CLI.
SYSTEM_LIBRARIES = {
    "libssl.so.3", "libcrypto.so.3", "libgmp.so.10", "libc.so.6", "libm.so.6",
    "libpthread.so.0", "libdl.so.2", "librt.so.1", "libgcc_s.so.1",
    "libstdc++.so.6", "libatomic.so.1", "libz.so.1", "libuv.so.1",
}


def run(argv: list[str], cwd: Path, *, capture: bool = False,
        timeout: int = 300, check: bool = True, data: str | None = None) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    for key in ("APALACHE_MC", "APALACHE_JAR", "TLA2TOOLS_JAR", "LD_LIBRARY_PATH", "LD_PRELOAD"):
        env.pop(key, None)
    env["LC_ALL"] = "C.UTF-8"
    return subprocess.run(argv, cwd=cwd, env=env, text=True, input=data,
                          capture_output=capture, timeout=timeout, check=check)


def git(source: Path, *args: str) -> str:
    return run(["git", *args], source, capture=True).stdout.strip()


def validate_tag(tag: str) -> str:
    # Existing four-part checkpoint tags are backfill-only. New tags follow
    # the documented MAJOR.MINOR.PATCH[-prerelease] product release policy.
    if tag not in HISTORICAL and not re.fullmatch(TAG_PATTERN, tag):
        raise ValueError("expected vMAJOR.MINOR.PATCH[-prerelease] or a recorded historical tag")
    if len(tag) > 128:
        raise ValueError("tag exceeds 128 characters")
    if "-" in tag:
        for identifier in tag.split("-", 1)[1].split("."):
            if identifier.isdigit() and len(identifier) > 1 and identifier.startswith("0"):
                raise ValueError("numeric prerelease identifiers cannot have leading zeros")
    return tag


def identity(source: Path, tag: str) -> dict:
    validate_tag(tag)
    commit = git(source, "rev-parse", "HEAD")
    if git(source, "rev-parse", f"refs/tags/{tag}^{{commit}}") != commit:
        raise ValueError("source checkout does not match the requested tag")
    if git(source, "status", "--porcelain", "--untracked-files=normal"):
        raise ValueError("release source checkout must be clean")
    version_file = source / "Shell/Version.lean"
    embedded = None
    if version_file.exists():
        match = re.search(r'^def version : String := "([^"]+)"$', version_file.read_text(), re.MULTILINE)
        if not match:
            raise ValueError("cannot read the embedded product version")
        embedded = match[1]
    historical = tag in HISTORICAL
    if historical:
        expected_commit, expected_version, version_output = HISTORICAL[tag]
        if commit != expected_commit or embedded != expected_version:
            raise ValueError("historical tag source identity changed")
    else:
        if embedded != tag[1:]:
            raise ValueError(f"tag {tag} does not match embedded product version {embedded!r}")
        version_output = tag + "\n"
    return {"schema": "mirrors.github-release/v1", "tag": tag, "commit": commit,
            "embeddedVersion": embedded, "expectedVersionOutput": version_output,
            "historical": historical, "prerelease": "-" in tag,
            "leanToolchain": (source / "lean-toolchain").read_text().strip(),
            "lakeManifestSha256": digest(source / "lake-manifest.json")}


def digest(path: Path) -> str:
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def runtime_libraries(binary: Path) -> dict:
    output = run(["ldd", str(binary)], binary.parent, capture=True).stdout
    if "not found" in output:
        raise ValueError(f"unresolved runtime dependency: {output}")
    libraries = re.findall(r"^\s*(\S+) =>", output, re.MULTILINE)
    if not libraries or set(libraries) - SYSTEM_LIBRARIES:
        raise ValueError(f"unsupported runtime dependencies for {binary.name}: {output}")
    return {"libraries": sorted(libraries), "ldd": output}


def smoke(package: Path, metadata: dict) -> None:
    mirror = package / "bin/mirror"
    expected = metadata["expectedVersionOutput"]
    if expected is not None:
        result = run([str(mirror), "--version"], package, capture=True, timeout=30)
        if result.stdout != expected or result.stderr:
            raise ValueError("packaged mirror --version differs from recorded source identity")
    # An out-of-order message exercises the actual JSONL CLI without a model.
    result = run([str(mirror)], package, capture=True, timeout=30,
                 data='{"proto_step":"report_state","state":{}}\n')
    messages = [json.loads(line) for line in result.stdout.splitlines()]
    if len(messages) != 1 or messages[0].get("proto_step") != "protocol_error":
        raise ValueError(f"packaged mirror protocol smoke failed: {result.stdout!r}")
    result = run([str(package / "bin/model_interface_gen"), "--help"],
                 package, capture=True, timeout=30, check=False)
    if result.returncode != 2 or "usage:" not in result.stderr:
        raise ValueError("packaged model_interface_gen cannot display its usage")


def build(source: Path, tag: str, output: Path) -> dict:
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise ValueError("this release profile requires Linux x86_64")
    source_identity = identity(source, tag)
    metadata = dict(source_identity)
    if output.exists() and any(output.iterdir()):
        raise ValueError("release output directory must be empty")
    output.mkdir(parents=True, exist_ok=True)
    run(["lake", "build", *BINARIES, *GATES], source, timeout=3000)
    for gate in GATES:
        print(f"Running non-model release gate: {gate}", flush=True)
        run([str(source / ".lake/build/bin" / gate)], source)
    metadata["passedGates"] = list(GATES)
    framing = source / "tools/check-client-framing.py"
    if framing.is_file():
        run(["python3", str(framing)], source)
        metadata["passedGates"].append("check-client-framing.py")
    if identity(source, tag) != source_identity:
        raise ValueError("source identity changed during the build")
    metadata["platform"] = "linux-x86_64"
    metadata["releaseTooling"] = {
        "repository": os.environ.get("GITHUB_REPOSITORY"),
        "workflowCommit": os.environ.get("GITHUB_WORKFLOW_SHA"),
        "runId": os.environ.get("GITHUB_RUN_ID"),
        "scriptSha256": digest(Path(__file__)),
    }
    metadata["qualification"] = "focused non-model release gates only; no live model qualification"
    metadata["buildTools"] = {
        name: run(args, source, capture=True).stdout.strip()
        for name, args in (("lake", ["lake", "--version"]), ("cc", ["cc", "--version"]),
                           ("openssl", ["openssl", "version"]),
                           ("glibc", ["getconf", "GNU_LIBC_VERSION"]))}
    package_name = f"mirrors-{tag}-linux-x86_64"
    with tempfile.TemporaryDirectory(prefix="mirrors-release-") as temporary:
        root = Path(temporary)
        package = root / package_name
        (package / "bin").mkdir(parents=True)
        metadata["binaries"] = {}
        for name in BINARIES:
            binary = source / ".lake/build/bin" / name
            dependencies = runtime_libraries(binary)
            shutil.copyfile(binary, package / "bin" / name)
            (package / "bin" / name).chmod(0o755)
            metadata["binaries"][name] = {"sha256": digest(binary), **dependencies}
        notice = historical_notice(metadata)
        (package / "README.txt").write_text(
            f"Mirrors {tag} — Linux x86_64\nSource commit: {metadata['commit']}\n\n"
            "Requires Linux x86_64, OpenSSL 3, GMP, and a glibc runtime compatible\n"
            "with buildTools.glibc in BUILD.json. GitHub builds use Ubuntu 24.04.\n"
            "On Ubuntu 24.04: sudo apt-get install libssl3t64 libgmp10\n"
            "Other system dependencies and exact build tools are recorded in BUILD.json.\n"
            "Add this archive's bin directory to PATH. Lean is not required to run it.\n"
            "Run bin/mirror with JSONL on stdin, or bin/model_interface_gen --help.\n"
            "Apalache and a compatible JVM are separate prerequisites for live model work.\n"
            "Companion clients, certificates, models and qualification evidence are not bundled.\n\n"
            f"{notice}\n{metadata['qualification']}.\n")
        # Test a relocated copy with loader environment overrides removed.
        smoke(package, metadata)
        metadata["passedGates"].append("relocated-binary-cli-smoke")
        manifest = json.dumps(metadata, indent=2) + "\n"
        (package / "BUILD.json").write_text(manifest)
        archive = output / f"{package_name}.tar.gz"
        with tarfile.open(archive, "w:gz") as handle:
            handle.add(package, arcname=package_name)
        (output / f"{package_name}.build.json").write_text(manifest)
    assets = sorted(output.iterdir())
    (output / "SHA256SUMS").write_text("".join(f"{digest(path)}  {path.name}\n" for path in assets))
    (output / "release-notes.txt").write_text(
        f"Linux x86-64 binaries built from `{tag}` at `{metadata['commit']}`.\n\n"
        "Includes `mirror` and `model_interface_gen`; requires Ubuntu 24.04 or a compatible "
        "Linux runtime with OpenSSL 3 and GMP. See the archive README and build manifest.\n\n"
        f"{notice}\n\nValidation: {', '.join(metadata['passedGates'])}. "
        "Live model checking, full cross-client qualification, and native Windows/macOS "
        "validation were not run by this workflow.\n")
    return metadata


def historical_notice(metadata: dict) -> str:
    if not metadata["historical"]:
        return "The executable product version matches the release tag."
    if metadata["embeddedVersion"] is None:
        return "Historical source build: the original executable has no --version mode."
    return (f"Historical source build: embedded product version is {metadata['embeddedVersion']!r}; "
            f"--version prints {metadata['expectedVersionOutput'].strip()!r}. "
            "Original tagged source is preserved, including any version-label discrepancy.")


def check_archive(archive: Path, tag: str) -> None:
    validate_tag(tag)
    name = f"mirrors-{tag}-linux-x86_64"
    expected = {name, f"{name}/bin", f"{name}/bin/mirror",
                f"{name}/bin/model_interface_gen", f"{name}/README.txt", f"{name}/BUILD.json"}
    with tempfile.TemporaryDirectory(prefix="mirrors-archive-check-") as temporary:
        root = Path(temporary)
        with tarfile.open(archive, "r:gz") as handle:
            members = handle.getmembers()
            if {entry.name for entry in members} != expected or len(members) != len(expected):
                raise ValueError("unexpected archive contents")
            if any(not (entry.isfile() or entry.isdir()) for entry in members):
                raise ValueError("archive must contain only regular files and directories")
            handle.extractall(root, filter="data")
        package = root / name
        metadata = json.loads((package / "BUILD.json").read_text())
        if metadata["tag"] != tag:
            raise ValueError("archive tag differs from requested release")
        for binary in BINARIES:
            if digest(package / "bin" / binary) != metadata["binaries"][binary]["sha256"]:
                raise ValueError("archived executable checksum mismatch")
        smoke(package, metadata)


def verify_remote(repository: str, tag: str, commit: str) -> None:
    validate_tag(tag)
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("invalid GitHub repository")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("expected a full source commit SHA")
    ref = f"refs/tags/{tag}"
    result = run(["git", "ls-remote", "--exit-code", f"https://github.com/{repository}.git",
                  ref, ref + "^{}"], Path.cwd(), capture=True)
    refs = {name: sha for sha, name in (line.split() for line in result.stdout.splitlines())}
    if refs.get(ref + "^{}", refs.get(ref)) != commit:
        raise ValueError("remote tag no longer identifies the built source commit")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("select", "build", "check-archive", "verify-remote"))
    parser.add_argument("--tag", required=True)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--repository")
    parser.add_argument("--commit")
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    validate_tag(args.tag)
    if args.command == "select":
        print(f"tag={args.tag}")
    elif args.command == "check-archive":
        if args.archive is None:
            parser.error("check-archive requires --archive")
        check_archive(args.archive.resolve(), args.tag)
    elif args.command == "verify-remote":
        if not args.repository or not args.commit:
            parser.error("verify-remote requires --repository and --commit")
        verify_remote(args.repository, args.tag, args.commit)
    else:
        if args.source is None or args.output is None:
            parser.error("build requires --source and --output")
        metadata = build(args.source.resolve(), args.tag, args.output.resolve())
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a") as handle:
                for key in ("tag", "commit", "historical", "prerelease"):
                    value = metadata[key]
                    handle.write(f"{key}={str(value).lower() if isinstance(value, bool) else value}\n")


if __name__ == "__main__":
    main()
