#!/usr/bin/env python3
"""Pinned native-Windows remote client validation matrix; no local backend."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/evidence"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_remote_model_check import HOST, PORT, validate_observation
from validate import loads_json_bytes
from store import write_exclusive as write_output
from ecma_runtime import PIN, node_environment, verify_runtime


def required(name: str) -> str:
    value = os.environ.get(name)
    if not value: raise ValueError(f"missing environment name: {name}")
    return value


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def classify_result(client: str, case: str, returncode: int,
                    stdout: str, stderr: str) -> bool:
    """Match the selected clients' terminal verdict frames and exit contracts."""
    pin_exits = {"cpp": 2, "haskell": 2, "rust": 2, "lean": 1, "ecma": 1}
    if client not in pin_exits:
        return False
    out = [line.strip() for line in stdout.splitlines() if line.strip()]
    err = [line.strip() for line in stderr.splitlines() if line.strip()]
    markers = [line for line in out + err
               if re.match(r"^(?:VALID|INVALID)(?:\s|$)|^spec invalid:", line)]
    warnings = {"haskell": r"warning: client certificate .+ expires in [0-9]+ day\(s\)",
                "lean": r"mirrorlean: WARNING: client certificate expires within 7 days \([0-9]+ days\)"}
    errors = [line for line in err if not re.fullmatch(warnings.get(client, r"(?!)"), line)]
    if case == "valid":
        return returncode == 0 and out == ["VALID"] and markers == ["VALID"] and not errors
    if case == "wrong-pin":
        return (returncode == pin_exits[client] and not markers
                and "certificate fingerprint mismatch" in stderr.lower())
    if case != "invalid" or returncode != 1 or len(markers) != 1:
        return False
    if client == "lean":
        return not out and bool(errors) and errors[0].startswith("spec invalid: ")
    if not out or errors:
        return False
    if client != "ecma":
        return out[0] == "INVALID" and markers == ["INVALID"]
    if len(out) != 1 or not out[0].startswith("INVALID "):
        return False
    try:
        value = loads_json_bytes(out[0][len("INVALID "):].encode("utf-8"))
    except (ValueError, UnicodeError):
        return False
    return (type(value) is dict and set(value) == {"invalid"}
            and type(value["invalid"]) is str and bool(value["invalid"]))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    output = parser.parse_args().output.absolute()
    if (output.is_symlink() or not output.parent.is_dir()
            or (output.exists() and (not output.is_dir() or any(output.iterdir())
                or output.stat().st_mode & 0o077))):
        raise ValueError("interop output must be new or an empty private directory")
    runtime = Path(required("ECMA_RUNTIME_ROOT"))
    node = Path(required("ECMA_NODE_BIN"))
    binding = verify_runtime(runtime, node, PIN, required("ECMA_REF"))
    revisions = {}
    for name, root_name, ref_name in [
        ("ecma", "ECMA_REPO", "ECMA_REF"), ("cpp", "CPP_REPO", "CPP_REF"),
        ("rust", "RUST_REPO", "RUST_REF"), ("lean", "LEAN_CLIENT_REPO", "LEAN_CLIENT_REF"),
        ("haskell", "HS_REPO", "HS_REF")]:
        revision = subprocess.check_output(["git", "-C", required(root_name), "rev-parse", "HEAD"], text=True).strip()
        if revision != required(ref_name): raise ValueError(f"source revision mismatch: {name}")
        revisions[name] = revision
    admin = Path(required("MIRRORS_REMOTE_ADMIN_OBSERVATION"))
    pin = required("MIRRORS_REMOTE_SERVER_PIN").lower()
    observation_sha = validate_observation(admin, pin,
        required("MIRRORS_REMOTE_SERVICE_BINARY_SHA256"),
        required("MIRRORS_REMOTE_SERVICE_SOURCE_REF"))
    env = node_environment(dict(os.environ))
    for name in ("APALACHE_MC", "APALACHE_JAR", "TLA2TOOLS_JAR"): env.pop(name, None)
    spec = ROOT / "test/specs/HourClock.tla"
    env["M5_INTEROP_SPEC"] = str(spec)
    env["M5_INTEROP_OUTPUT"] = str(output)
    common = ["--host", HOST, "--port", PORT, "--tls", "--cert", required("MIRRORS_REMOTE_CLIENT_CERT"),
        "--key", required("MIRRORS_REMOTE_CLIENT_KEY"), "--ca", required("MIRRORS_REMOTE_CA"),
        "--pin", pin, "--spec", str(spec), "--init", "Init", "--next", "Next"]
    commands = {
        "cpp": [required("CPP_BIN"), *common],
        "haskell": [required("HS_BIN"), "validate", *common],
        "rust": [required("RUST_BIN")], "lean": [required("LEAN_CLIENT_BIN")],
        "ecma": [str(node), str(ROOT / "tools/interop/remote-clients/ecma.mjs")],
    }
    binary_hashes = {name: digest(Path(command[0])) for name, command in commands.items() if name != "ecma"}
    binary_hashes["ecmaAdapter"] = digest(ROOT / "tools/interop/remote-clients/ecma.mjs")
    protocol = ROOT / "tools/interop/remote-clients/ecma-protocol.mjs"
    protocol_hash = digest(protocol)
    output.mkdir(mode=0o700, exist_ok=True)
    write_output(output / "ecma-runtime-pin.json", PIN.read_bytes())
    windows = Path("/mnt/c/Users/ayden/Desktop/Workspace/MirrorsRemote/interop")
    if not windows.is_dir() or windows.is_symlink():
        raise ValueError("prepare the Windows Workspace interop fixture directory")
    fixture_hashes = {}
    for name, relative in (("Counter.tla", "specs/Counter.tla"),
            ("violation.itf.json", "specs/traces/violation.itf.json")):
        source = runtime / relative
        target = windows / name
        if target.is_symlink(): raise ValueError("Windows interop fixture must not be a symlink")
        target.write_bytes(source.read_bytes())
        fixture_hashes[name] = digest(target)
    rows = []
    for client, command in commands.items():
        for case, invariant, bound in [("valid", "Inv", 3), ("invalid", "TraceComplete", 13), ("wrong-pin", "Inv", 3)]:
            current = {**env, "M5_INTEROP_INV": invariant, "M5_INTEROP_BOUND": str(bound)}
            argv = list(command)
            if client in ("cpp", "haskell"): argv += ["--inv", invariant, "--bound", str(bound)]
            if case == "wrong-pin":
                current["MIRRORS_REMOTE_SERVER_PIN"] = "0" * 64
                if client in ("cpp", "haskell"): argv[argv.index("--pin") + 1] = "0" * 64
            result = subprocess.run(argv, env=current, capture_output=True, text=True, timeout=150)
            text = result.stdout + result.stderr
            for credential in ("MIRRORS_REMOTE_CLIENT_CERT", "MIRRORS_REMOTE_CLIENT_KEY", "MIRRORS_REMOTE_CA"):
                text = text.replace(required(credential), "<private-credential-path>")
            log = output / f"{client}-{case}.log"; write_output(log, text.encode("utf-8"))
            passed = classify_result(client, case, result.returncode, result.stdout, result.stderr)
            if not passed: raise RuntimeError(f"interop row failed: {client}/{case}; retained {log}")
            rows.append({"client": client, "case": case, "exitCode": result.returncode,
                "log": log.name, "logSha256": digest(log)})
            print(f"remote interop {client}/{case}: PASS", flush=True)
    result = subprocess.run([str(node), str(protocol)], env=env,
        capture_output=True, text=True, timeout=600)
    log = output / "ecma-protocol.log"
    write_output(log, (result.stdout + result.stderr).encode("utf-8"))
    if result.returncode: raise RuntimeError(f"remote ECMA protocol matrix failed; retained {log}")
    protocol_receipt = json.loads((output / "ecma-protocol-receipt.json").read_text())
    expected = ["register", "mismatch", "register_traces", "register_trace_gen",
        "register_explore", "register_explore_session", "inline_multimodule"]
    if protocol_receipt["rows"] != [{"case": case, "status": "passed"} for case in expected]:
        raise ValueError("remote ECMA protocol case membership differs")
    for case in expected:
        rows.append({"client": "ecma", "case": case, "exitCode": 0,
            "log": log.name, "logSha256": digest(log)})
        print(f"remote interop ecma/{case}: PASS", flush=True)
    for name, sha in fixture_hashes.items():
        if digest(windows / name) != sha: raise ValueError("Windows fixture changed during interop")
    if digest(admin) != observation_sha: raise ValueError("deployment observation changed during interop")
    for name, command in commands.items():
        if name != "ecma" and digest(Path(command[0])) != binary_hashes[name]:
            raise ValueError(f"client binary changed during interop: {name}")
    if (digest(ROOT / "tools/interop/remote-clients/ecma.mjs") != binary_hashes["ecmaAdapter"]
            or digest(protocol) != protocol_hash):
        raise ValueError("ECMA adapter changed during interop")
    if verify_runtime(runtime, node, PIN, required("ECMA_REF")) != binding:
        raise ValueError("ECMA runtime binding changed during interop")
    if digest(output / "ecma-runtime-pin.json") != binding["pinSha256"]:
        raise ValueError("retained runtime pin differs from the admitted pin")
    receipt = {"schema": "mirrors.remote-interop/v2", "profile": "remote-five-client-mtls/v1",
        "scope": "five-client bounded verdicts/pin rejection and ECMA replay/generation/exploration; legacy all-transport matrix remains separate",
        "endpoint": {"host": HOST, "port": int(PORT)}, "transport": "pinned-mtls",
        "revisions": revisions, "binaries": binary_hashes, "modelSha256": digest(spec),
        "deploymentObservationSha256": observation_sha, "windowsFixtureSha256": fixture_hashes,
        "ecmaRuntime": binding, "protocolAdapterSha256": protocol_hash, "rows": rows}
    write_output(output / "receipt.json", (json.dumps(receipt, indent=2) + "\n").encode("utf-8"))
    print(json.dumps(receipt, sort_keys=True))
    print("REMOTE INTEROP PASS: five clients, 22 verdict/pin/protocol rows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
