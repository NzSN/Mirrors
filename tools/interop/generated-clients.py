#!/usr/bin/env python3
"""Shared generated-language vectors plus bounded Rust/Lean transport acceptance.

All model generation uses the explicitly selected Windows oracle. Local stdio
and TCP cases consume supplied traces with a forbidden-model-checker sentinel.
This profile does not substitute for the historical full client matrix or M5.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/evidence"))
from store import write_exclusive


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--cpp-prefix", type=Path, required=True)
    parser.add_argument("--node", type=Path, required=True)
    parser.add_argument("--context", type=Path, required=True)
    parser.add_argument("--observation", type=Path, required=True)
    parser.add_argument("--rust-build", type=Path)
    parser.add_argument("--lean-build", type=Path)
    parser.add_argument("--allow-dirty-sdk", action="store_true")
    args = parser.parse_args()
    output = args.out.absolute()
    hidden_roots = (ROOT, ROOT.parent / "MirrorRust", ROOT.parent / "MirrorLean")
    for candidate in (output, args.rust_build, args.lean_build):
        if candidate is not None and any(candidate.resolve().is_relative_to(root.resolve()) for root in hidden_roots):
            raise ValueError("matrix output and prepared builds must be outside the source roots hidden at runtime")
    if output.exists() or output.is_symlink() or not output.parent.is_dir():
        raise ValueError("matrix output must be new with an existing parent")
    output.mkdir(mode=0o700)
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    for key in ("APALACHE_MC", "APALACHE_JAR", "TLA2TOOLS_JAR", "NODE_OPTIONS", "NODE_PATH", "PYTHONOPTIMIZE"):
        environment.pop(key, None)

    def run(name: str, command: list[str]) -> None:
        descriptor = os.open(output / (name + ".log"), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(descriptor, "wb") as log:
            subprocess.run(command, cwd=ROOT, env=environment, stdout=log,
                           stderr=subprocess.STDOUT, check=True, timeout=1200)
        print(name + ": passed", flush=True)

    run("shared-vectors", [sys.executable, "tools/model-interface-conformance/check.py",
        "--work", str(output / "vectors"), "--cpp-prefix", str(args.cpp_prefix.resolve()),
        "--node", str(args.node.resolve(strict=True))])
    vector_path = output / "vectors/receipt.json"
    vectors = json.loads(vector_path.read_text())
    if not vectors["freshGeneration"] or not vectors["completeTargetSet"]:
        raise ValueError("all supported targets and fresh generation are required")

    receipts = []
    for language, helper in (("rust", "run-generated-remote.py"), ("lean", "run-generated-lean.py")):
        script = ROOT / "tools/interop" / helper
        selected = getattr(args, language + "_build")
        build = selected.resolve(strict=True) if selected else output / (language + "-build")
        if selected is None:
            command = [sys.executable, str(script), "build", str(build)]
            if language == "rust" and args.allow_dirty_sdk:
                command.append("--allow-dirty-sdk")
            run(language + "-build", command)
        for mode in ("offline", "remote"):
            destination = output / (language + "-" + mode)
            command = [sys.executable, str(script), mode, str(build), str(destination), "--source-hidden"]
            if mode == "remote":
                command += ["--context", str(args.context.resolve(strict=True)),
                            "--observation", str(args.observation.resolve(strict=True))]
            run(language + "-" + mode, command)
            path = destination / "receipt.json"
            value = json.loads(path.read_text())
            hidden_key = "sourceRootsHidden" if language == "rust" else "sourceHidden"
            if value.get(hidden_key) is not True or len(value["rows"]) != (4 if mode == "offline" else 5):
                raise ValueError("transport receipt has incomplete membership or source hiding")
            receipts.append({"language": language, "mode": mode,
                "path": path.relative_to(output).as_posix(),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "rows": len(value["rows"])})

    result = {"schema": "mirrors.generated-clients-acceptance/v1", "status": "passed",
        "scope": "shared generated conformance and Rust/Lean stdio, TCP-denial and owned-Windows mTLS acceptance",
        "releaseQualification": False,
        "sharedVectors": {"path": "vectors/receipt.json",
            "sha256": hashlib.sha256(vector_path.read_bytes()).hexdigest(), "cases": vectors["cases"]},
        "transportReceipts": receipts}
    write_exclusive(output / "receipt.json", (json.dumps(result, indent=2) + "\n").encode())
    print(f"GENERATED CLIENT ACCEPTANCE PASSED: {len(vectors['targets'])} generated profiles and 18 transport rows", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
