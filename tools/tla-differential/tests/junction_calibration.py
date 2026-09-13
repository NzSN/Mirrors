#!/usr/bin/env python3
"""JP0 junction calibration through the DV2 adapters and bounded process layer."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
from types import MappingProxyType

ROOT = Path(__file__).resolve().parents[3]
DV = ROOT / "tools/tla-differential"
sys.path.insert(0, str(DV))
import acquire
from adapters import apalache, mirrors, sany
from capture import AdapterFixture, MaterializedFixture, _input_digest
from process import ProcessLimits

CASES = {
    "mixed-and-or": "Value == A /\\ B \\/ C", "mixed-or-and": "Value == A \\/ B /\\ C",
    "mixed-long-chain": "Value == A /\\ B /\\ C \\/ A", "and-chain": "Value == A /\\ B /\\ C",
    "or-chain": "Value == A \\/ B \\/ C", "paren-left-and-or": "Value == (A /\\ B) \\/ C",
    "paren-right-and-or": "Value == A /\\ (B \\/ C)", "paren-left-or-and": "Value == (A \\/ B) /\\ C",
    "paren-right-or-and": "Value == A \\/ (B /\\ C)", "symbolic-word-alias": "Value == A /\\ B \\land C",
    "word-mixed-alias": "Value == A \\land B \\lor C", "prefix-single": "Value == /\\ A",
    "prefix-and": "Value == /\\ A\n         /\\ B\n         /\\ C", "prefix-nested": "Value == /\\ A\n         /\\ \\/ B\n            \\/ C",
    "prefix-mixed-column": "Value == /\\ A\n         \\/ B", "prefix-inline-opposite": "Value == /\\ A \\/ B",
}
PREFIX_SUPPLEMENT_CASES = {
    "prefix-two-item-mixed-column": "Value == /\\ A\n         /\\ B\n         \\/ C",
    "prefix-two-item-inline-opposite": "Value == /\\ A\n         /\\ B \\/ C",
    "prefix-parenthesized-outdented": "Value == /\\ (A\n         /\\ B)",
    "prefix-switch-back": "Value == /\\ A\n         \\/ B\n         /\\ C",
}

def module_name(case: str) -> str: return "Jp0" + "".join(part.title() for part in case.split("-"))
def sha256(path: Path) -> str: return hashlib.sha256(path.read_bytes()).hexdigest()
def materialize(case: str, body: str, input_dir: Path) -> MaterializedFixture:
    name = module_name(case); encoded = f"---- MODULE {name} ----\n\nCONSTANTS A, B, C\n\n{body}\n\n====\n".encode(); input_dir.mkdir(parents=True)
    path = input_dir / f"{name}.tla"; path.write_bytes(encoded); fixture = AdapterFixture(case, "borrowed-directory", name, ".", ()); digest = hashlib.sha256(encoded).hexdigest()
    return MaterializedFixture(fixture, input_dir, path, MappingProxyType({path.name: path}), MappingProxyType({path.name: encoded}), MappingProxyType({path.name: digest}), _input_digest(fixture, {path.name: encoded}))
def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("--output", type=Path, required=True); parser.add_argument("--timeout", type=float, default=60.0); parser.add_argument("--prefix-supplement", action="store_true"); args = parser.parse_args(argv); output = args.output.resolve()
    if output.exists(): parser.error("output must be a new directory; calibration evidence is never overwritten")
    acquire.verify_tools(); cli, driver = ROOT / ".lake/build/bin/tla_frontend", ROOT / ".lake/build/bin/tla_differential_driver"
    if not cli.is_file() or not driver.is_file(): parser.error("build tla_frontend and tla_differential_driver before calibration")
    java = shutil.which("java")
    if java is None: parser.error("java is required")
    lock = json.loads((DV / "toolchain.lock.json").read_text()); chain = acquire.TOOLCHAIN
    configs = {"mirrors": {"cli": str(cli), "driver": str(driver), "tool": {"id": "mirrors", "version": "baseline-binaries", "fingerprint": hashlib.sha256((sha256(cli) + sha256(driver)).encode()).hexdigest()}}, "sany": {"java": java, "sany_jar": str(chain / lock["tools"]["sany"]["path"]), "bridge_classes": str(chain / "bridge-classes"), "version": lock["tools"]["sany"]["version"]}, "apalache": {"java": java, "apalache_jar": str(chain / "apalache-0.61.0/lib/apalache.jar"), "version": lock["tools"]["apalache"]["version"]}}
    adapters = {"mirrors": mirrors.observe, "sany": sany.observe, "apalache": apalache.observe}; output.mkdir(parents=True); rows = []; selected = PREFIX_SUPPLEMENT_CASES if args.prefix_supplement else CASES
    for case, body in selected.items():
        source_digest = hashlib.sha256((f"---- MODULE {module_name(case)} ----\n\nCONSTANTS A, B, C\n\n{body}\n\n====\n").encode()).hexdigest(); row = {"id": case, "sourceSha256": source_digest, "outcomes": {}}
        for engine, observe in adapters.items():
            fixture = materialize(case, body, output / "inputs" / case / engine)
            artifact_dir = output / "fixtures" / case / engine / "raw"; artifact_dir.mkdir(parents=True); observation = observe(fixture=fixture.fixture, materialized=fixture, config=configs[engine], limits=ProcessLimits(timeout_seconds=args.timeout), artifact_dir=artifact_dir)
            (artifact_dir.parent / "observation.json").write_text(json.dumps(observation, indent=2) + "\n"); row["outcomes"][engine] = {key: observation[key] for key in ("outcome", "execution", "invocation")}
        rows.append(row)
    (output / "matrix.json").write_text(json.dumps({"schema": "mirrors.jp0-junction-calibration/v2", "baseline": {"cliSha256": sha256(cli), "driverSha256": sha256(driver), "parserSourceSha256": sha256(ROOT / "Core/Tla/Parser.lean"), "note": "binaries were not rebuilt after the observed parser-source edit"}, "cases": rows}, indent=2) + "\n")
    unknown = [f"{row['id']}/{engine}" for row in rows for engine, value in row["outcomes"].items() if value["outcome"] == "unknown" or value["execution"] != "completed"]
    if unknown: print("JP0 INCOMPLETE: " + ", ".join(unknown), file=sys.stderr); return 1
    return 0
if __name__ == "__main__": raise SystemExit(main())
