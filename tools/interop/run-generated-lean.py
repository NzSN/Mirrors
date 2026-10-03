#!/usr/bin/env python3
"""Freshly compiled generated Lean Counter transport acceptance.

Preparation copies only SDK source inputs into a new build tree. Runtime uses
captured executables and can hide both checkouts and the entire compiler tree.
No subcommand starts a local Apalache/TLC process.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SDK = ROOT.parent / "MirrorLean"
RUNNER = ROOT / "tools/interop/generated-lean"
COUNTER = ROOT / "test/fixtures/model-interface/counter"
SHARED = ROOT / "tools/interop/run-generated-remote.py"
spec = importlib.util.spec_from_file_location("generated_transport_common", SHARED)
assert spec and spec.loader
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
digest, load_json, write, write_json = common.digest, common.load_json, common.write, common.write_json
BUILD_SCHEMA = "mirrors.generated-lean-transport-build/v1"
ROW_SCHEMA = "mirrors.generated-lean-transport-row/v1"
RECEIPT_SCHEMA = "mirrors.generated-lean-transport-acceptance/v1"


def stderr_passes(stderr: str, transport: str) -> bool:
    if not stderr:
        return True
    lines = stderr.splitlines()
    # Exactly the successful SDK connection's source-defined expiry warning;
    # the native shim's <7-day branch renders 0..6, with singular only for 1.
    return (transport == "tls" and len(lines) == 1 and
            re.fullmatch(r"mirrorlean: WARNING: client certificate expires within 7 days \((?:1 day|[02-6] days)\)",
                         lines[0]) is not None)


def source_identity() -> dict:
    names = ["MirrorLean.lean", "lean-toolchain", "lakefile.toml",
             "server-mode/native/mirrorlean_tls.c", "server-mode/native/mirrorlean_tls.h"]
    names += [path.relative_to(SDK).as_posix() for path in (SDK / "MirrorLean").rglob("*.lean")]
    entries = []
    for name in sorted(names):
        path = SDK / name
        if path.is_symlink() or not path.is_file():
            raise ValueError("SDK source is not an ordinary file")
        entries.append({"path": name, "sha256": digest(path)})
    revision = subprocess.check_output(["git", "-C", str(SDK), "rev-parse", "HEAD"], text=True).strip()
    tree = hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return {"revision": revision, "sourceTreeSha256": tree, "files": entries,
            "scope": "exact current SDK Lean sources, root manifest/toolchain and native TLS shim; includes authorized uncommitted additions"}


def environment() -> dict:
    env = dict(os.environ)
    for name in ("LEAN_PATH", "LEAN_SRC_PATH", "LEAN_SYSROOT", "ELAN_TOOLCHAIN", "LD_PRELOAD", "LD_LIBRARY_PATH",
                 "MIRRORLEAN_DEBUG_TLS", "MIRRORLEAN_DEBUG_TLS_PLAIN"):
        env.pop(name, None)
    return env


def runtime_libraries(binary: Path) -> list[dict]:
    result = subprocess.check_output(["ldd", str(binary)], text=True, env=environment())
    paths = set()
    for line in result.splitlines():
        words = line.split()
        path = words[2] if len(words) > 2 and words[1] == "=>" else (words[0] if words else "")
        if path.startswith("/"):
            paths.add(Path(path).resolve())
        elif "not found" in line:
            raise ValueError("unresolved native runtime library")
    return [{"path": str(path), "sha256": digest(path)} for path in sorted(paths)]


def build(output: Path, mirror: Path, generator: Path) -> None:
    output = common.private_output(output)
    sdk = source_identity()
    originals = {
        "spec": ROOT / "specs/Counter.tla", "contract": COUNTER / "Counter.mirror-interface.json",
        "lock": COUNTER / "Counter.mirror-interface.lock.json", "trace": COUNTER / "counter.itf.json",
        "runnerSource": RUNNER / "Main.lean", "lakefile": RUNNER / "lakefile.lean",
        "harness": Path(__file__).resolve(), "sharedHarness": SHARED,
        "mirror": mirror.resolve(), "generator": generator.resolve()}
    hashes = {name: digest(path) for name, path in originals.items()}
    lock, trace = load_json(originals["lock"]), load_json(originals["trace"])
    if [state["count"]["#bigint"] for state in trace["states"]] != ["0", "2", "5"]:
        raise ValueError("supplied trace must be the authoritative 0,2,5 Counter trace")
    write(output / "generator", originals["generator"].read_bytes(), 0o700)
    write(output / "mirror", originals["mirror"].read_bytes(), 0o700)
    if digest(output / "generator") != hashes["generator"] or digest(output / "mirror") != hashes["mirror"]:
        raise ValueError("an executable changed during capture")
    inputs = output / "inputs"
    inputs.mkdir(mode=0o700)
    for name, filename in (("spec", "Counter.tla"), ("contract", "Counter.mirror-interface.json"),
                           ("lock", "Counter.mirror-interface.lock.json"), ("trace", "counter.itf.json")):
        write(inputs / filename, originals[name].read_bytes())
    generated = output / "generated"
    base = ["--spec", str(inputs / "Counter.tla"), "--contract", str(inputs / "Counter.mirror-interface.json"),
            "--evidence", str(inputs / "counter.itf.json"), "--param-var", "parameters",
            "--lock", str(inputs / "Counter.mirror-interface.lock.json")]
    # Use authoritative source paths for freshness: the logical source identity
    # is specs/Counter.tla, while all runtime reads use captured inputs.
    base[1] = str(originals["spec"])
    common.run_checked([str(output / "generator"), "generate", "--lock", str(inputs / "Counter.mirror-interface.lock.json"),
                        "--target", "mirrorlean-v1", "--out", str(generated)], output / "generate.log")
    common.run_checked([str(output / "generator"), "check", *base, "--target", "mirrorlean-v1", "--out", str(generated)],
                       output / "freshness.log")
    common.run_checked([str(output / "generator"), "preflight", "--lock", str(inputs / "Counter.mirror-interface.lock.json"),
                        "--trace", str(inputs / "counter.itf.json"), "--require-all-actions"], output / "preflight.log")
    work = output / "work"
    work.mkdir(mode=0o700)
    sdk_copy = work / "sdk"
    sdk_copy.mkdir(mode=0o700)
    for entry in sdk["files"]:
        target = sdk_copy / entry["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        write(target, (SDK / entry["path"]).read_bytes())
        if digest(target) != entry["sha256"]:
            raise ValueError("SDK source changed during capture")
    # Source-only package: test executables and all prior .lake artifacts are
    # excluded; every imported module is compiled in this new tree.
    (sdk_copy / "lakefile.toml").unlink()
    write(sdk_copy / "lakefile.toml", b'name = "mirrorlean"\ndefaultTargets = ["MirrorLean"]\n[[lean_lib]]\nname = "MirrorLean"\n')
    for filename in ("Main.lean", "lakefile.lean"):
        write(work / filename, (RUNNER / filename).read_bytes())
    write(work / "CounterMirror.lean", (generated / "CounterMirror.lean").read_bytes())
    write(work / "lean-toolchain", (SDK / "lean-toolchain").read_bytes())
    (work / "native").mkdir(mode=0o700)
    for filename in ("mirrorlean_tls.c", "mirrorlean_tls.h"):
        write(work / "native" / filename, (sdk_copy / "server-mode/native" / filename).read_bytes())
    common.run_checked(["lake", "build", "runner"], output / "lean-build.log", env=environment(), cwd=work, timeout=600)
    write(output / "runner", (work / ".lake/build/bin/runner").read_bytes(), 0o700)
    write(output / "harness.py", originals["harness"].read_bytes())
    write(output / "shared-harness.py", originals["sharedHarness"].read_bytes())
    if source_identity() != sdk or any(digest(path) != hashes[name] for name, path in originals.items()):
        raise ValueError("authoritative build inputs changed during preparation")
    paths = ["runner", "mirror", "generator", "harness.py", "shared-harness.py",
             "generated/CounterMirror.lean", "generated/.model-interface-generated.json",
             "inputs/Counter.tla", "inputs/Counter.mirror-interface.json",
             "inputs/Counter.mirror-interface.lock.json", "inputs/counter.itf.json",
             "work/Main.lean", "work/CounterMirror.lean", "work/lakefile.lean", "work/lean-toolchain",
             "work/native/mirrorlean_tls.c", "work/native/mirrorlean_tls.h", "work/sdk/lakefile.toml"]
    paths += ["work/sdk/" + entry["path"] for entry in sdk["files"] if entry["path"] != "lakefile.toml"]
    receipt = {
        "schema": BUILD_SCHEMA, "targetProfile": "mirrorlean-v1", "semanticDigest": lock["semanticDigest"],
        "provenanceDigest": lock["provenanceDigest"], "sdk": sdk, "authoritativeInputs": hashes,
        "leanVersion": subprocess.check_output(["lean", "--version"], text=True, cwd=work, env=environment()).strip(),
        "ccVersion": subprocess.check_output(["cc", "--version"], text=True).splitlines()[0],
        "opensslVersion": subprocess.check_output(["openssl", "version"], text=True).strip(),
        "files": [{"path": name, "sha256": digest(output / name)} for name in sorted(paths)],
        "runtimeLibraries": runtime_libraries(output / "runner"), "freshSourceBuild": True}
    write_json(output / "build.json", receipt)
    print(f"generated Lean build prepared: {output}")


def verify_build(root: Path) -> dict:
    receipt = load_json(root / "build.json")
    if (receipt.get("schema") != BUILD_SCHEMA or receipt.get("targetProfile") != "mirrorlean-v1"
            or receipt.get("freshSourceBuild") is not True):
        raise ValueError("unexpected Lean build receipt")
    entries = receipt["files"]
    required = {"runner", "mirror", "generator", "harness.py", "shared-harness.py",
                "generated/CounterMirror.lean", "generated/.model-interface-generated.json",
                "inputs/Counter.tla", "inputs/Counter.mirror-interface.json",
                "inputs/Counter.mirror-interface.lock.json", "inputs/counter.itf.json",
                "work/Main.lean", "work/CounterMirror.lean", "work/lakefile.lean", "work/lean-toolchain",
                "work/native/mirrorlean_tls.c", "work/native/mirrorlean_tls.h", "work/sdk/lakefile.toml"}
    required |= {"work/sdk/" + entry["path"] for entry in receipt["sdk"]["files"] if entry["path"] != "lakefile.toml"}
    if len(entries) != len(required) or {entry["path"] for entry in entries} != required:
        raise ValueError("build payload membership differs")
    for entry in entries:
        name = Path(entry["path"])
        if name.is_absolute() or ".." in name.parts:
            raise ValueError("invalid receipt path")
        path = root / name
        if path.is_symlink() or not path.is_file() or digest(path) != entry["sha256"]:
            raise ValueError("prepared payload changed")
    if digest(Path(__file__)) != digest(root / "harness.py") or digest(SHARED) != digest(root / "shared-harness.py"):
        raise ValueError("acceptance harness differs from prepared build")
    if runtime_libraries(root / "runner") != receipt.get("runtimeLibraries"):
        raise ValueError("native runtime library closure changed")
    if load_json(root / "inputs/Counter.mirror-interface.lock.json")["semanticDigest"] != receipt["semanticDigest"]:
        raise ValueError("prepared lock identity differs")
    return receipt


def row_passes(row: dict, returncode: int, transport: str, case: str, semantic_digest: str,
               *, pin: str | None = None) -> bool:
    expected_fields = {"schema", "transport", "case", "semanticDigest", "validatedServerPin", "factoryCount",
                       "disposedPorts", "events", "observations", "strides", "reports", "coverage", "outcome"}
    if set(row) != expected_fields or row.get("schema") != ROW_SCHEMA:
        return False
    # Reuse the identical Counter/protocol contract. The alias is internal to
    # this validator; retained Lean evidence calls this validatedServerPin.
    shared = {key: value for key, value in row.items() if key != "validatedServerPin"}
    shared["schema"] = common.ROW_SCHEMA
    shared["peerFingerprint"] = row["validatedServerPin"]
    for key in ("reports", "coverage"):
        shared.pop(key)
    if not common.row_passes(shared, returncode, transport, case, semantic_digest, pin=pin):
        return False
    if transport != "tls" and row["validatedServerPin"] is not None:
        return False
    if row["reports"] != [{"count": {"#bigint": value}} for value in row["observations"]]:
        return False
    if row["factoryCount"]:
        expected_coverage = {"Initialize": row["events"].count("Initialize"), "Tick": row["events"].count("Tick")}
    else:
        expected_coverage = {}
    return row["coverage"] == expected_coverage and all(type(value) is int for value in row["coverage"].values())


def runtime_command(root: Path, output: Path, transport: str, case: str, source_hidden: bool) -> list[str]:
    command = [str(root / "runner"), transport, case]
    if not source_hidden:
        return command
    bwrap = shutil.which("bwrap")
    if not bwrap:
        raise ValueError("source hiding requires Bubblewrap")
    hidden = [str(ROOT), str(SDK), str(root / "work")]
    for path in (root, output):
        if any(path.resolve().is_relative_to(Path(hidden_root).resolve()) for hidden_root in hidden):
            raise ValueError("source-hidden build and output must be outside hidden source trees")
    probe = ("import os,sys\nfrom pathlib import Path\n"
             "if any(any(Path(p).iterdir()) for p in sys.argv[1:4]):\n"
             "    raise SystemExit('source hiding failed')\n"
             "os.execv(sys.argv[4],sys.argv[4:])")
    return [bwrap, "--die-with-parent", "--ro-bind", "/", "/", "--bind", str(output), str(output),
            "--proc", "/proc", "--dev-bind", "/dev", "/dev", "--tmpfs", hidden[0],
            "--tmpfs", hidden[1], "--tmpfs", hidden[2], "--chdir", str(output),
            sys.executable, "-c", probe, *hidden, *command]


def execute_row(root: Path, output: Path, baseline: dict, transport: str, case: str,
                env: dict, source_hidden: bool, pin: str | None = None) -> dict:
    result = subprocess.run(runtime_command(root, output, transport, case, source_hidden), env=env,
                            cwd=output, capture_output=True, text=True, timeout=180)
    name = f"{transport}-{case}"
    lines = result.stdout.splitlines()
    try:
        row = json.loads(lines[0], object_pairs_hook=common.unique_object) if len(lines) == 1 else None
    except (ValueError, UnicodeError):
        row = None
    if not isinstance(row, dict):
        write_json(output / f"{name}.failure.json", {"exitCode": result.returncode, "reason": "missing unique result frame"})
        raise RuntimeError("missing admissible Lean result")
    if not stderr_passes(result.stderr, transport) or not row_passes(row, result.returncode, transport, case, baseline["semanticDigest"], pin=pin):
        raise RuntimeError("Lean row failed its exact acceptance contract")
    write_json(output / f"{name}.json", {"exitCode": result.returncode, "result": row})
    write(output / f"{name}.stderr.log", result.stderr.encode())
    print(f"generated Lean {name}: PASS", flush=True)
    return {"transport": transport, "case": case, "exitCode": result.returncode, "result": row,
            "artifact": f"{name}.json", "sha256": digest(output / f"{name}.json"),
            "stderrArtifact": f"{name}.stderr.log", "stderrSha256": digest(output / f"{name}.stderr.log")}


def runner_environment(root: Path) -> dict:
    return {**environment(), "GENERATED_LEAN_MIRROR_BIN": str(root / "mirror"),
            "GENERATED_LEAN_SPEC": str(root / "inputs/Counter.tla"),
            "GENERATED_LEAN_TRACE": str(root / "inputs/counter.itf.json")}


def offline(root: Path, output: Path, source_hidden: bool) -> None:
    root = root.resolve()
    baseline = verify_build(root)
    output = common.private_output(output)
    write(output / "build.json", (root / "build.json").read_bytes())
    env = runner_environment(root)
    forbidden, marker = output / "forbidden-model-checker", output / "model-checker-was-invoked"
    write(forbidden, b'#!/bin/sh\nprintf invoked > "$GENERATED_LEAN_FORBIDDEN_MARKER"\nexit 97\n', 0o700)
    env.update({"APALACHE_MC": str(forbidden), "GENERATED_LEAN_FORBIDDEN_MARKER": str(marker)})
    for name in ("APALACHE_JAR", "TLA2TOOLS_JAR", "MIRRORS_ASYNC_RESOURCE_E2E"):
        env.pop(name, None)
    rows = [execute_row(root, output, baseline, "stdio", case, env, source_hidden)
            for case in ("correct", "faulty-observer", "wrong-digest")]
    port = common.free_port()
    with (output / "tcp-server.log").open("xb") as log:
        os.chmod(output / "tcp-server.log", 0o600)
        server = subprocess.Popen([str(root / "mirror"), "--serve", str(port), "--bind", "127.0.0.1", "--jobs", "1"],
                                  env=env, cwd=output, stdin=subprocess.DEVNULL, stdout=log, stderr=log)
        try:
            common.wait_listener(server, port)
            rows.append(execute_row(root, output, baseline, "tcp", "unauthorized",
                                    {**env, "GENERATED_LEAN_HOST": "127.0.0.1", "GENERATED_LEAN_PORT": str(port)}, source_hidden))
        finally:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=10)
    if marker.exists() or verify_build(root) != baseline:
        raise ValueError("offline runtime identity/model-checker contract failed")
    write_json(output / "receipt.json", {
        "schema": RECEIPT_SCHEMA, "profile": "generated-lean-counter-offline/v1",
        "scope": "generated supplied-trace replay over stdio plus plain TCP authorization denial; no local model checking",
        "buildSha256": digest(root / "build.json"), "semanticDigest": baseline["semanticDigest"],
        "sourceHidden": source_hidden, "hiddenPaths": [str(ROOT), str(SDK), str(root / "work")] if source_hidden else [],
        "modelCheckerInvoked": False, "serverStopped": server.poll() is not None, "rows": rows})


def remote(root: Path, output: Path, context: Path, observation: Path, source_hidden: bool) -> None:
    sys.path.insert(0, str(ROOT / "tools/evidence"))
    from run_remote_model_check import validate_observation
    root = root.resolve()
    baseline = verify_build(root)
    private = load_json(context)
    if any(not isinstance(key, str) or not key.startswith("MIRRORS_REMOTE_") or not isinstance(value, str)
           for key, value in private.items()):
        raise ValueError("invalid private remote context")
    env = {**runner_environment(root), **private, "GENERATED_LEAN_HOST": common.HOST, "GENERATED_LEAN_PORT": str(common.PORT)}
    common.private_credentials(env, ("MIRRORS_REMOTE_CA", "MIRRORS_REMOTE_CLIENT_CERT", "MIRRORS_REMOTE_CLIENT_KEY",
                                     "MIRRORS_REMOTE_DENIED_CLIENT_CERT", "MIRRORS_REMOTE_DENIED_CLIENT_KEY"))
    pin = env["MIRRORS_REMOTE_SERVER_PIN"].lower()
    env["MIRRORS_REMOTE_SERVER_PIN"] = pin
    observation_hash = validate_observation(observation, pin, env["MIRRORS_REMOTE_SERVICE_BINARY_SHA256"],
                                            env["MIRRORS_REMOTE_SERVICE_SOURCE_REF"])
    output = common.private_output(output)
    write(output / "build.json", (root / "build.json").read_bytes())
    write(output / "deployment-observation.json", observation.read_bytes())
    rows = []
    for case in ("correct", "faulty-observer", "wrong-digest", "unauthorized", "wrong-pin"):
        current = dict(env)
        if case == "unauthorized":
            current["MIRRORS_REMOTE_CLIENT_CERT"] = env["MIRRORS_REMOTE_DENIED_CLIENT_CERT"]
            current["MIRRORS_REMOTE_CLIENT_KEY"] = env["MIRRORS_REMOTE_DENIED_CLIENT_KEY"]
        rows.append(execute_row(root, output, baseline, "tls", case, current, source_hidden, pin))
    if digest(observation) != observation_hash or verify_build(root) != baseline:
        raise ValueError("admitted observation/build changed during remote acceptance")
    write_json(output / "receipt.json", {
        "schema": RECEIPT_SCHEMA, "profile": "generated-lean-counter-windows-mtls/v1",
        "scope": "generated Counter fresh inline-source replay and exact negotiation/pin negatives; separate from historical interop matrices",
        "endpoint": {"host": common.HOST, "port": common.PORT}, "transport": "TLS1.3-mTLS",
        "buildSha256": digest(root / "build.json"), "semanticDigest": baseline["semanticDigest"],
        "sourceSha256": digest(root / "inputs/Counter.tla"), "deploymentObservationSha256": observation_hash,
        "sourceHidden": source_hidden, "hiddenPaths": [str(ROOT), str(SDK), str(root / "work")] if source_hidden else [],
        "pinEvidence": "validatedServerPin is the exact pin verified by the SDK on the successful TLS connection",
        "rows": rows})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare = commands.add_parser("build")
    prepare.add_argument("output", type=Path)
    prepare.add_argument("--mirror", type=Path, default=ROOT / ".lake/build/bin/mirror")
    prepare.add_argument("--generator", type=Path, default=ROOT / ".lake/build/bin/model_interface_gen")
    for name in ("offline", "remote"):
        execute = commands.add_parser(name)
        execute.add_argument("build", type=Path)
        execute.add_argument("output", type=Path)
        execute.add_argument("--source-hidden", action="store_true")
        if name == "remote":
            execute.add_argument("--context", type=Path, required=True)
            execute.add_argument("--observation", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "build":
            build(args.output, args.mirror, args.generator)
        elif args.command == "offline":
            offline(args.build, args.output, args.source_hidden)
        else:
            remote(args.build, args.output, args.context, args.observation, args.source_hidden)
        return 0
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"generated Lean acceptance failed ({type(error).__name__})", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
