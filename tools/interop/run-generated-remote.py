#!/usr/bin/env python3
"""Bounded generated Rust Counter transport acceptance, separate from M5 interop.

Build once, then run supplied-trace offline acceptance and/or the explicitly
selected owned Windows oracle. This runner never invokes a local model checker.
Private credential context values are neither printed nor copied into receipts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import stat
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "tools/interop/generated-rust"
SDK = ROOT.parent / "MirrorRust"
COUNTER = ROOT / "test/fixtures/model-interface/counter"
HOST, PORT = "172.20.208.1", 8999
ROW_SCHEMA = "mirrors.generated-rust-transport-row/v1"
BUILD_SCHEMA = "mirrors.generated-rust-transport-build/v1"
RECEIPT_SCHEMA = "mirrors.generated-rust-transport-acceptance/v1"


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def unique_object(pairs: list[tuple[str, object]]) -> dict:
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate JSON key")
        value[key] = item
    return value


def load_json(path: Path) -> dict:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 4 * 1024 * 1024:
        raise ValueError("expected a bounded ordinary JSON file")
    value = json.loads(path.read_text(), object_pairs_hook=unique_object)
    if type(value) is not dict:
        raise ValueError("expected a JSON object")
    return value


def private_output(path: Path) -> Path:
    path = path.absolute()
    if path.is_symlink() or not path.parent.is_dir():
        raise ValueError("output needs an existing parent and must not be a symlink")
    path.mkdir(mode=0o700, exist_ok=False)
    return path


def write(path: Path, data: bytes, mode: int = 0o600) -> None:
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, mode)
    with os.fdopen(fd, "wb") as stream:
        stream.write(data)


def write_json(path: Path, value: dict) -> None:
    write(path, (json.dumps(value, indent=2, sort_keys=True) + "\n").encode())


def source_identity(repo: Path, allow_dirty: bool = False) -> dict:
    revision = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    dirty = subprocess.check_output(
        ["git", "-C", str(repo), "status", "--porcelain", "--untracked-files=all"], text=True)
    if dirty and not allow_dirty:
        raise ValueError("MirrorRust source must be clean for this acceptance build")
    if any(line.startswith("?? ") for line in dirty.splitlines()):
        raise ValueError("acceptance builds cannot omit untracked SDK inputs from source identity")
    files = subprocess.check_output(["git", "-C", str(repo), "ls-files", "-z"]).decode().split("\0")
    entries = [{"path": name, "sha256": digest(repo / name)} for name in sorted(files) if name]
    tree = hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return {"revision": revision, "dirty": bool(dirty), "changes": dirty.splitlines(),
            "trackedTreeSha256": tree, "files": entries}


def run_checked(argv: list[str], log: Path, *, env: dict | None = None,
                timeout: int = 300, cwd: Path = ROOT) -> None:
    result = subprocess.run(argv, env=env, cwd=cwd, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=timeout)
    write(log, result.stdout)
    if result.returncode:
        raise RuntimeError(f"preparation failed with exit {result.returncode}; inspect {log.name}")


def build(output: Path, mirror: Path, generator: Path, allow_dirty_sdk: bool = False) -> None:
    output = private_output(output)
    sdk = source_identity(SDK, allow_dirty=allow_dirty_sdk)
    original = {
        "spec": ROOT / "specs/Counter.tla",
        "contract": COUNTER / "Counter.mirror-interface.json",
        "lock": COUNTER / "Counter.mirror-interface.lock.json",
        "trace": COUNTER / "counter.itf.json",
        "runner": RUNNER / "main.rs",
        "manifest": RUNNER / "Cargo.toml",
        "cargoLock": RUNNER / "Cargo.lock",
        "harness": Path(__file__).resolve(),
        "mirror": mirror.resolve(),
        "generator": generator.resolve(),
    }
    original_hashes = {name: digest(path) for name, path in original.items()}
    lock = load_json(original["lock"])
    trace = load_json(original["trace"])
    counts = [state["count"]["#bigint"] for state in trace["states"]]
    if counts != ["0", "2", "5"]:
        raise ValueError("authoritative Counter supplied trace must record 0,2,5")
    # Keep concurrent Lean relinks from replacing the executable between the
    # generate, freshness and preflight operations of this one preparation.
    write(output / "generator", generator.read_bytes(), 0o700)
    if digest(output / "generator") != original_hashes["generator"]:
        raise ValueError("compiler executable changed during capture")
    captured_generator = output / "generator"
    generated = output / "generated"
    run_checked([str(captured_generator), "generate", "--lock", str(original["lock"]),
                 "--target", "mirrorrust-v1", "--out", str(generated)], output / "generate.log")
    common = ["--spec", str(original["spec"]), "--contract", str(original["contract"]),
              "--evidence", str(original["trace"]), "--param-var", "parameters",
              "--lock", str(original["lock"])]
    run_checked([str(captured_generator), "check", *common, "--target", "mirrorrust-v1", "--out", str(generated)],
                output / "freshness.log")
    run_checked([str(captured_generator), "preflight", "--lock", str(original["lock"]), "--trace",
                 str(original["trace"]), "--require-all-actions"], output / "preflight.log")
    inputs = output / "inputs"
    inputs.mkdir(mode=0o700)
    for name, filename in [("spec", "Counter.tla"), ("contract", "Counter.mirror-interface.json"),
                           ("lock", "Counter.mirror-interface.lock.json"), ("trace", "counter.itf.json")]:
        write(inputs / filename, original[name].read_bytes())
    write(output / "mirror", mirror.read_bytes(), 0o700)
    write(output / "main.rs", original["runner"].read_bytes())
    manifest = original["manifest"].read_text().replace('"../../../../MirrorRust"', json.dumps(str(SDK)))
    write(output / "Cargo.toml", manifest.encode())
    write(output / "Cargo.lock", original["cargoLock"].read_bytes())
    env = dict(os.environ)
    env["MIRRORS_GENERATED_COUNTER_RS"] = str(generated / "CounterMirror.generated.rs")
    env["CARGO_TARGET_DIR"] = str(output / "target")
    run_checked(["cargo", "build", "--offline", "--locked", "--manifest-path", str(output / "Cargo.toml")],
                output / "cargo-build.log", env=env, timeout=600)
    binary = output / "target/debug/generated-rust-transport"
    write(output / "runner", binary.read_bytes(), 0o700)
    if (source_identity(SDK, allow_dirty=allow_dirty_sdk) != sdk
            or any(digest(path) != original_hashes[name] for name, path in original.items())):
        raise ValueError("an authoritative build input changed during preparation")
    paths = ["runner", "mirror", "generator", "main.rs", "Cargo.toml", "Cargo.lock",
             "generated/CounterMirror.generated.rs", "generated/.model-interface-generated.json",
             "inputs/Counter.tla", "inputs/Counter.mirror-interface.json",
             "inputs/Counter.mirror-interface.lock.json", "inputs/counter.itf.json"]
    receipt = {
        "schema": BUILD_SCHEMA, "targetProfile": "mirrorrust-v1",
        "semanticDigest": lock["semanticDigest"], "provenanceDigest": lock["provenanceDigest"],
        "sdk": sdk, "authoritativeInputs": original_hashes,
        "cargoVersion": subprocess.check_output(["cargo", "--version"], text=True).strip(),
        "rustcVersion": subprocess.check_output(["rustc", "--version"], text=True).strip(),
        "files": [{"path": path, "sha256": digest(output / path)} for path in paths],
    }
    write_json(output / "build.json", receipt)
    print(f"generated Rust build prepared: {output}")


def verify_build(root: Path) -> dict:
    receipt = load_json(root / "build.json")
    if receipt.get("schema") != BUILD_SCHEMA or receipt.get("targetProfile") != "mirrorrust-v1":
        raise ValueError("unexpected generated Rust build receipt")
    required = {"runner", "mirror", "generator", "main.rs", "Cargo.toml", "Cargo.lock",
                "generated/CounterMirror.generated.rs", "generated/.model-interface-generated.json",
                "inputs/Counter.tla", "inputs/Counter.mirror-interface.json",
                "inputs/Counter.mirror-interface.lock.json", "inputs/counter.itf.json"}
    entries = receipt["files"]
    if len(entries) != len(required) or {entry["path"] for entry in entries} != required:
        raise ValueError("build receipt file membership differs")
    for entry in entries:
        path = root / entry["path"]
        if path.is_symlink() or not path.is_file() or digest(path) != entry["sha256"]:
            raise ValueError("prepared build artifact changed")
    if load_json(root / "inputs/Counter.mirror-interface.lock.json")["semanticDigest"] != receipt["semanticDigest"]:
        raise ValueError("prepared semantic digest differs from the authoritative lock")
    return receipt


def fresh_counter_trace_sequence(events: object, observations: object, strides: object) -> bool:
    """Validate every artifact, not the requested Apalache counterexample count.

    One counterexample can produce multiple ITF artifacts; each starts with its
    own initializer. Every accepted artifact must independently reach the fixed
    TraceComplete violation through legal strides within the requested bound.
    """
    if (not isinstance(events, list) or not isinstance(observations, list)
            or not isinstance(strides, list) or len(events) % 2
            or any(stride not in ("2", "3") for stride in strides)):
        return False
    if len(observations) * 2 != len(events):
        return False
    artifacts = 0
    stride_index = 0
    count = None
    transitions = 0
    for index, observed in enumerate(observations):
        action, observe = events[2 * index:2 * index + 2]
        if observe != "Observe":
            return False
        if action == "Initialize":
            if count is not None and (count < 12 or not 1 <= transitions <= 6):
                return False
            artifacts += 1
            if artifacts > 64:
                return False
            count, transitions = 0, 0
        elif action == "Tick":
            if count is None or stride_index >= len(strides) or transitions >= 6:
                return False
            count += int(strides[stride_index])
            stride_index += 1
            transitions += 1
        else:
            return False
        if observed != str(count):
            return False
    return (artifacts > 0 and count is not None and count >= 12
            and 1 <= transitions <= 6 and stride_index == len(strides))


def row_passes(row: dict, returncode: int, transport: str, case: str,
               semantic_digest: str, *, pin: str | None = None) -> bool:
    expected_fields = {"schema", "transport", "case", "semanticDigest", "peerFingerprint",
                       "factoryCount", "disposedPorts", "events", "observations", "strides", "outcome"}
    if (set(row) != expected_fields or row.get("schema") != ROW_SCHEMA or row.get("transport") != transport
            or row.get("case") != case or row.get("semanticDigest") != semantic_digest):
        return False
    if type(row.get("factoryCount")) is not int or type(row.get("disposedPorts")) is not int:
        return False
    if transport == "tls" and case != "wrong-pin" and row.get("peerFingerprint") != pin:
        return False
    result = row.get("outcome", {})
    events, observations, strides = row.get("events"), row.get("observations"), row.get("strides")
    if case == "correct":
        if returncode != 0 or result != {"kind": "completed"} or row["factoryCount"] != 1 or row["disposedPorts"] != 1:
            return False
        if transport != "tls":
            return (events == ["Initialize", "Observe", "Tick", "Observe", "Tick", "Observe"]
                    and observations == ["0", "2", "5"] and strides == ["2", "3"])
        return fresh_counter_trace_sequence(events, observations, strides)
    if case == "faulty-observer":
        return (returncode == 1 and result == {"kind": "step_mismatch", "action": "init", "expectedCount": "0", "actualCount": "1"}
                and row["factoryCount"] == row["disposedPorts"] == 1
                and events == ["Initialize", "Observe"] and observations == ["1"] and strides == [])
    if returncode != 2 or row["factoryCount"] != 0 or row["disposedPorts"] != 0 or events != [] or observations != [] or strides != []:
        return False
    if case == "wrong-digest":
        return result == {"kind": "registration_error", "code": "interface_digest_mismatch"}
    if case == "unauthorized":
        return result == {"kind": "registration_error", "code": "interface_unavailable"}
    if case == "wrong-pin":
        return row.get("peerFingerprint") is None and result == {"kind": "tls_pin_mismatch"}
    return False


def runtime_command(build_root: Path, output: Path, transport: str, case: str,
                    source_hidden: bool) -> list[str]:
    command = [str(build_root / "runner"), transport, case]
    if not source_hidden:
        return command
    bwrap = shutil.which("bwrap")
    if not bwrap:
        raise ValueError("explicit source hiding requires Bubblewrap")
    for path in (build_root, output):
        if any(path.resolve().is_relative_to(hidden) for hidden in (ROOT, SDK)):
            raise ValueError("source-hidden build and output must be outside Mirrors and MirrorRust")
    # The acceptance runtime reads only captured /tmp inputs and binaries.
    # Check the actual empty mounts before replacing this probe with the client.
    probe = ("import os,sys\nfrom pathlib import Path\n"
             "if any(any(Path(p).iterdir()) for p in sys.argv[1:3]):\n"
             "    raise SystemExit('source hiding failed')\n"
             "os.execv(sys.argv[3],sys.argv[3:])")
    return [bwrap, "--die-with-parent", "--ro-bind", "/", "/", "--bind", str(output), str(output), "--proc", "/proc",
            "--dev-bind", "/dev", "/dev", "--tmpfs", str(ROOT), "--tmpfs", str(SDK),
            "--chdir", str(output), sys.executable, "-c", probe, str(ROOT), str(SDK), *command]


def execute_row(build_root: Path, output: Path, build_receipt: dict, transport: str,
                case: str, env: dict, *, pin: str | None = None,
                source_hidden: bool = False) -> dict:
    result = subprocess.run(runtime_command(build_root, output, transport, case, source_hidden), env=env,
                            cwd=output, capture_output=True, text=True, timeout=180)
    name = f"{transport}-{case}"
    # The Rust adapter reports only structured classifications and public Counter
    # values. Do not retain unfiltered diagnostics from the private child context.
    lines = result.stdout.splitlines()
    try:
        row = json.loads(lines[0], object_pairs_hook=unique_object) if len(lines) == 1 else None
    except (ValueError, UnicodeError):
        row = None
    if not isinstance(row, dict):
        write_json(output / f"{name}.failure.json", {"exitCode": result.returncode, "reason": "missing or malformed unique result frame"})
        raise RuntimeError(f"generated Rust {name} produced no admissible result")
    if result.stderr.strip():
        # Stdio may inherit the local mirror's benign diagnostics. Current happy
        # paths do not need any; refusing them avoids hiding a harness error.
        raise RuntimeError(f"generated Rust {name} produced unexpected stderr")
    if not row_passes(row, result.returncode, transport, case, build_receipt["semanticDigest"], pin=pin):
        raise RuntimeError(f"generated Rust {name} did not satisfy its exact acceptance contract")
    write_json(output / f"{name}.json", {"exitCode": result.returncode, "result": row})
    print(f"generated Rust {name}: PASS", flush=True)
    return {"transport": transport, "case": case, "exitCode": result.returncode,
            "result": row, "artifact": f"{name}.json", "sha256": digest(output / f"{name}.json")}


def runner_environment(build_root: Path) -> dict:
    env = dict(os.environ)
    env.update({"GENERATED_RUST_MIRROR_BIN": str(build_root / "mirror"),
                "GENERATED_RUST_SPEC": str(build_root / "inputs/Counter.tla"),
                "GENERATED_RUST_TRACE": str(build_root / "inputs/counter.itf.json")})
    return env


def free_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def wait_listener(process: subprocess.Popen, port: int) -> None:
    for _ in range(100):
        if process.poll() is not None:
            raise RuntimeError("local supplied-trace server exited before readiness")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                return
        except OSError:
            time.sleep(0.05)
    raise RuntimeError("local supplied-trace server readiness timed out")


def offline(build_root: Path, output: Path, source_hidden: bool = False) -> None:
    build_root = build_root.resolve()
    baseline = verify_build(build_root)
    output = private_output(output)
    write(output / "build.json", (build_root / "build.json").read_bytes())
    write(output / "harness.py", Path(__file__).read_bytes())
    harness_hash = digest(output / "harness.py")
    env = runner_environment(build_root)
    forbidden = output / "forbidden-model-checker"
    marker = output / "model-checker-was-invoked"
    write(forbidden, b'#!/bin/sh\nprintf invoked > "$GENERATED_RUST_FORBIDDEN_MARKER"\nexit 97\n', 0o700)
    env["APALACHE_MC"] = str(forbidden)
    env["GENERATED_RUST_FORBIDDEN_MARKER"] = str(marker)
    for key in ("APALACHE_JAR", "TLA2TOOLS_JAR", "MIRRORS_ASYNC_RESOURCE_E2E"):
        env.pop(key, None)
    rows = [execute_row(build_root, output, baseline, "stdio", case, env, source_hidden=source_hidden)
            for case in ("correct", "faulty-observer", "wrong-digest")]
    port = free_port()
    with (output / "tcp-server.log").open("xb") as log:
        os.chmod(output / "tcp-server.log", 0o600)
        server = subprocess.Popen([str(build_root / "mirror"), "--serve", str(port), "--bind", "127.0.0.1", "--jobs", "1"],
                                  env=env, cwd=output, stdin=subprocess.DEVNULL, stdout=log, stderr=log)
        try:
            wait_listener(server, port)
            rows.append(execute_row(build_root, output, baseline, "tcp", "unauthorized",
                                    {**env, "GENERATED_RUST_HOST": "127.0.0.1", "GENERATED_RUST_PORT": str(port)},
                                    source_hidden=source_hidden))
        finally:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=10)
    if marker.exists():
        raise RuntimeError("offline acceptance attempted a forbidden model-checker invocation")
    if verify_build(build_root) != baseline or digest(Path(__file__)) != harness_hash:
        raise ValueError("prepared build changed during offline acceptance")
    write_json(output / "receipt.json", {"schema": RECEIPT_SCHEMA, "profile": "generated-rust-counter-offline/v1",
               "scope": "supplied Counter trace over stdio and plain-TCP authorization denial; no local model checking",
               "buildSha256": digest(build_root / "build.json"), "semanticDigest": baseline["semanticDigest"],
               "harnessSha256": harness_hash,
               "modelCheckerInvoked": False, "serverStopped": server.poll() is not None,
               "sourceRootsHidden": source_hidden, "rows": rows})


def private_credentials(env: dict, names: tuple[str, ...]) -> None:
    for name in names:
        value = env.get(name)
        if not isinstance(value, str) or not value:
            raise ValueError(f"missing private credential name: {name}")
        path = Path(value)
        if path.is_symlink() or not path.is_file() or not stat.S_ISREG(path.stat().st_mode):
            raise ValueError(f"credential must be an ordinary file: {name}")
        if "KEY" in name and path.stat().st_mode & 0o077:
            raise ValueError(f"credential key must be owner-only: {name}")


def remote(build_root: Path, output: Path, context: Path, observation: Path,
           source_hidden: bool = False) -> None:
    sys.path.insert(0, str(ROOT / "tools/evidence"))
    from run_remote_model_check import validate_observation
    build_root = build_root.resolve()
    baseline = verify_build(build_root)
    private = load_json(context)
    if any(not isinstance(key, str) or not key.startswith("MIRRORS_REMOTE_") or not isinstance(value, str)
           for key, value in private.items()):
        raise ValueError("credential context must contain only private remote environment names")
    env = {**runner_environment(build_root), **private,
           "GENERATED_RUST_HOST": HOST, "GENERATED_RUST_PORT": str(PORT)}
    credential_names = ("MIRRORS_REMOTE_CA", "MIRRORS_REMOTE_CLIENT_CERT", "MIRRORS_REMOTE_CLIENT_KEY",
                        "MIRRORS_REMOTE_DENIED_CLIENT_CERT", "MIRRORS_REMOTE_DENIED_CLIENT_KEY")
    private_credentials(env, credential_names)
    pin = env["MIRRORS_REMOTE_SERVER_PIN"].lower()
    observation_hash = validate_observation(observation, pin, env["MIRRORS_REMOTE_SERVICE_BINARY_SHA256"],
                                            env["MIRRORS_REMOTE_SERVICE_SOURCE_REF"])
    output = private_output(output)
    write(output / "build.json", (build_root / "build.json").read_bytes())
    write(output / "deployment-observation.json", observation.read_bytes())
    write(output / "harness.py", Path(__file__).read_bytes())
    harness_hash = digest(output / "harness.py")
    rows = []
    for case in ("correct", "faulty-observer", "wrong-digest", "unauthorized", "wrong-pin"):
        current = dict(env)
        if case == "unauthorized":
            current["MIRRORS_REMOTE_CLIENT_CERT"] = env["MIRRORS_REMOTE_DENIED_CLIENT_CERT"]
            current["MIRRORS_REMOTE_CLIENT_KEY"] = env["MIRRORS_REMOTE_DENIED_CLIENT_KEY"]
        rows.append(execute_row(build_root, output, baseline, "tls", case, current, pin=pin,
                                source_hidden=source_hidden))
    if (digest(observation) != observation_hash or verify_build(build_root) != baseline
            or digest(Path(__file__)) != harness_hash):
        raise ValueError("admitted observation/build changed during remote acceptance")
    write_json(output / "receipt.json", {"schema": RECEIPT_SCHEMA, "profile": "generated-rust-counter-windows-mtls/v1",
               "scope": "generated Counter fresh inline-source replay and exact negotiation/pin negatives; separate from the historical all-transport and registered 22-row matrices",
               "endpoint": {"host": HOST, "port": PORT}, "transport": "TLS1.3-mTLS",
               "buildSha256": digest(build_root / "build.json"), "semanticDigest": baseline["semanticDigest"],
               "harnessSha256": harness_hash,
               "sourceSha256": digest(build_root / "inputs/Counter.tla"),
               "deploymentObservationSha256": observation_hash, "sourceRootsHidden": source_hidden, "rows": rows})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare = commands.add_parser("build")
    prepare.add_argument("output", type=Path)
    prepare.add_argument("--mirror", type=Path, default=ROOT / ".lake/build/bin/mirror")
    prepare.add_argument("--generator", type=Path, default=ROOT / ".lake/build/bin/model_interface_gen")
    prepare.add_argument("--allow-dirty-sdk", action="store_true",
                         help="bind explicitly selected tracked SDK edits by exact worktree hashes")
    for command in ("offline", "remote"):
        execute = commands.add_parser(command)
        execute.add_argument("build", type=Path)
        execute.add_argument("output", type=Path)
        execute.add_argument("--source-hidden", action="store_true",
                             help="hide Mirrors and MirrorRust checkouts from each client process")
        if command == "remote":
            execute.add_argument("--context", type=Path, required=True)
            execute.add_argument("--observation", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "build":
            build(args.output, args.mirror, args.generator, args.allow_dirty_sdk)
        elif args.command == "offline":
            offline(args.build, args.output, args.source_hidden)
        else:
            remote(args.build, args.output, args.context, args.observation, args.source_hidden)
        return 0
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        # Exception details can contain a private subprocess environment or path.
        # Retained public Counter row classifications identify behavioral failures.
        print(f"generated Rust acceptance failed ({type(error).__name__})", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
