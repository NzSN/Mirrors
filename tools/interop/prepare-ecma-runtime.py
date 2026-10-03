#!/usr/bin/env python3
"""Build a new SDK from Git objects; emit a pin for review before qualification."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

from ecma_runtime import node_environment, node_identity, runtime_tree, verify_runtime


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--ref", required=True)
    parser.add_argument("--node", type=Path, required=True)
    parser.add_argument("--node-modules", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--pin-out", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.ref):
        raise ValueError("a full source revision is required")
    if args.out.exists() or args.out.is_symlink() or args.pin_out.exists() or args.pin_out.is_symlink():
        raise ValueError("runtime and pin outputs must be new")
    node = args.node.absolute()
    environment = node_environment(dict(os.environ))
    node_before = node_identity(node)
    compiler = (args.node_modules / "typescript").resolve(strict=True)
    compiler_before = runtime_tree(compiler)
    git = ["git", "-C", str(args.repo)]
    source = subprocess.check_output([*git, "archive", "--format=tar", args.ref])
    tree = subprocess.check_output([*git, "rev-parse", args.ref + "^{tree}"], text=True).strip()
    with tempfile.TemporaryDirectory(prefix="mirrors-interop-ecma-build-") as temporary:
        clean = Path(temporary)
        with tarfile.open(fileobj=io.BytesIO(source), mode="r:") as archive:
            archive.extractall(clean, filter="data")
        if (clean / "dist").exists():
            raise ValueError("selected source unexpectedly contains built dist")
        package = json.loads((clean / "package.json").read_text())
        if package.get("dependencies") or package.get("optionalDependencies"):
            raise ValueError("prepare a closed runtime for SDK runtime dependencies first")
        (clean / "node_modules").symlink_to(args.node_modules.resolve(strict=True), target_is_directory=True)
        subprocess.run([str(node), str(compiler / "bin/tsc"), "-p", str(clean / "tsconfig.json")],
            cwd=clean, env=environment, check=True)
        if runtime_tree(compiler) != compiler_before or node_identity(node) != node_before:
            raise ValueError("build tool changed during compilation")
        args.out.mkdir(mode=0o700)
        shutil.copytree(clean / "dist", args.out / "dist")
        shutil.copytree(clean / "specs", args.out / "specs")
        shutil.copyfile(clean / "package.json", args.out / "package.json")
    value = {"schema": "mirrors.interop-ecma-runtime/v1", "sourceRevision": args.ref,
        "sourceTree": tree, "sourceArchiveSha256": hashlib.sha256(source).hexdigest(),
        "compiler": {"version": json.loads((compiler / "package.json").read_text())["version"],
                     "tree": compiler_before},
        "nodeVersion": subprocess.check_output([str(node), "--version"], env=environment, text=True).strip(),
        "node": node_before, "runtime": runtime_tree(args.out)}
    with args.pin_out.open("x") as output:
        output.write(json.dumps(value, indent=2) + "\n")
    verify_runtime(args.out.absolute(), node, args.pin_out, args.ref)
    print(json.dumps(value, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
