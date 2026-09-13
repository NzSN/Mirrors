#!/usr/bin/env python3
"""Produce the two junction summaries from the real Lean frontend.

Write mode never reads destination summaries. Check mode compares decoded JSON;
key order/whitespace are presentation, not semantic facts.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from process import ProcessLimits, ProcessRequest, run_process

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ("acc-precedence", "acc-precedence-junctions")


def generate(fixture: str) -> dict:
    binary = ROOT / ".lake/build/bin/tla_parser_spec"
    result = run_process(ProcessRequest(
        [str(binary), "--emit-junction-summary", fixture], ROOT), ProcessLimits())
    if result.status.value != "completed" or result.returncode != 0:
        raise ValueError(f"{fixture}: {result.status.value}: {result.stderr.decode(errors='replace')}")
    value = json.loads(result.stdout)
    if value.get("schema") != "mirrors.tla-frontend-summary/1" or value.get("fixture") != fixture:
        raise ValueError(f"{fixture}: unexpected producer document")
    return value


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true", help="generate complete summaries, including into an empty directory")
    mode.add_argument("--check", action="store_true", help="compare with the destination summaries (default)")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "test/fixtures/tla-frontend/expected")
    args = parser.parse_args(argv)
    generated = {fixture: generate(fixture) for fixture in FIXTURES}
    if args.write:
        args.output_dir.mkdir(parents=True, exist_ok=True)
        for fixture, value in generated.items():
            (args.output_dir / f"{fixture}.json").write_text(
                json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n")
    else:
        for fixture, value in generated.items():
            destination = args.output_dir / f"{fixture}.json"
            if not destination.is_file() or json.loads(destination.read_text()) != value:
                print(f"{fixture}: summary differs from the real frontend projection")
                return 1
    print("JUNCTION SUMMARY GENERATION GREEN" if args.write else "JUNCTION SUMMARY CHECK GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
