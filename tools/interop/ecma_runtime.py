"""Verify the interop SDK against a reviewed, source-built runtime pin."""
from __future__ import annotations

import os
from pathlib import Path
import re
import stat
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/distribution"))
sys.path.insert(0, str(ROOT / "tools/evidence"))
from distribution_lib import runtime_tree, sha256_file
from store import read_regular
from validate import loads_json_bytes

PIN = Path(__file__).with_name("ecma-runtime-pin.json")


def node_environment(environment: dict[str, str]) -> dict[str, str]:
    return {key: value for key, value in environment.items()
            if key not in {"NODE_OPTIONS", "NODE_PATH"}}


def node_identity(node: Path) -> dict:
    if not node.is_absolute() or node.is_symlink() or not os.access(node, os.X_OK):
        raise ValueError("Node must be an absolute regular executable")
    size, digest = sha256_file(node)
    return {"bytes": size, "sha256": digest}


def verify_runtime(runtime: Path, node: Path, pin: Path, revision: str) -> dict:
    raw, pin_sha = read_regular(pin, max_bytes=2 * 1024 * 1024)
    selected = loads_json_bytes(raw)
    if type(selected) is not dict or selected.get("schema") != "mirrors.interop-ecma-runtime/v1":
        raise ValueError("unsupported ECMA runtime pin schema")
    if not re.fullmatch(r"[0-9a-f]{40}", revision) or selected.get("sourceRevision") != revision:
        raise ValueError("ECMA runtime source revision differs from the selected client")
    if (not runtime.is_absolute() or runtime.is_symlink()
            or not stat.S_ISDIR(runtime.stat().st_mode)):
        raise ValueError("ECMA runtime must be an absolute regular directory")
    actual_node = node_identity(node)
    if actual_node != selected.get("node"):
        raise ValueError("Node executable differs from the reviewed runtime pin")
    actual_runtime = runtime_tree(runtime)
    if actual_runtime != selected.get("runtime"):
        raise ValueError("ECMA runtime tree differs from the reviewed runtime pin")
    return {"pinSha256": pin_sha, "sourceRevision": revision,
            "node": actual_node, "runtime": actual_runtime}
