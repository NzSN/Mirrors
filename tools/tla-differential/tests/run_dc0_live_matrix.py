#!/usr/bin/env python3
"""Capture the DC0 reference matrix without involving Mirrors expectations.

The output directory is deliberately new-and-empty.  It contains each exact
input, both engines' untouched stdout/stderr, a SHA-256 index, and a compact
semantic matrix suitable for comparing two independent executions.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys


REPO = Path(__file__).resolve().parents[3]
BUILD = REPO / ".golden-build/tla-differential"
JDK = BUILD / "jdk/jdk-25.0.4+7/bin/java"
JAVAC = BUILD / "jdk/jdk-25.0.4+7/bin/javac"
TOOLS = BUILD / "toolchain"
SANY_JAR = TOOLS / "downloads/tla2tools-1.8.0.jar"
APALACHE_JAR = TOOLS / "apalache-0.61.0/lib/apalache.jar"
BRIDGE = TOOLS / "bridge-classes"

# One context per staged glyph.  Operators with no standard semantic meaning
# are declared at their ASCII spelling and then exercised through its Unicode
# spelling; their native semantic rejection, if any, is a result, not a test
# harness failure.  Every source contains its target glyph exactly once.
UNICODE_SOURCES = {
    "∧": "U == TRUE ∧ TRUE", "∨": "U == TRUE ∨ FALSE", "¬": "U == ¬FALSE",
    "⇒": "U == TRUE ⇒ TRUE", "⇔": "U == TRUE ⇔ TRUE", "≡": "U == TRUE ≡ TRUE",
    "∈": "U == 1 ∈ {1}", "∉": "U == 1 ∉ {2}", "⊆": "U == {1} ⊆ {1, 2}",
    "⊂": "U == {1} ⊂ {1, 2}", "⊇": "U == {1, 2} ⊇ {1}", "⊃": "U == {1, 2} ⊃ {1}",
    "∪": "U == {1} ∪ {2}", "∩": "U == {1} ∩ {2}", "≠": "U == 1 ≠ 2",
    "≤": "EXTENDS Naturals\nU == 1 ≤ 2", "≥": "EXTENDS Naturals\nU == 2 ≥ 1", "⟨": "U == ⟨1 >>",
    "⟩": "U == << 1 ⟩", "↦": "U == [a ↦ 1]", "‥": "EXTENDS Naturals\nU == 1 ‥ 2",
    "□": "U == □TRUE", "◇": "U == ◇TRUE", "≜": "U ≜ TRUE",
    "→": "EXTENDS Functions\nU == {1} → {2}", "←": "U == {2} ← {1}", "∘": "EXTENDS Sequences\nU == <<1>> ∘ <<2>>",
    "×": "U == {1} × {2}", "÷": "EXTENDS Integers\nU == 4 ÷ 2", "≺": "U == 1 ≺ 2",
    "≻": "U == 2 ≻ 1", "∼": "U == ∼FALSE", "≈": "U == 1 ≈ 1",
    "∙": "U == 1 ∙ 2", "⋆": "U == 1 ⋆ 2", "○": "U == 1 ○ 2",
}
ENABLED_SOURCES = {
    "constant": "C == TRUE\nE == ENABLED C",
    "state": "VARIABLE x\nS == x = x\nE == ENABLED S",
    "action": "VARIABLE x\nA == x' = x\nE == ENABLED A",
    "temporal": "T == []TRUE\nE == ENABLED T",
}
INSTANCE_FIXTURES = {
    "direct": "rejected/instance-definition-only",
    "explicit-substitution": "rejected/instance-variable-substituted",
    "implicit-substitution": "rejected/instance-implicit-substitution",
    "state-substitution": "rejected/substitution-constant-by-state",
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()


def module(name: str, body: str) -> str:
    return f"---- MODULE {name} ----\n{body}\n====\n"


def compile_bridge() -> None:
    BRIDGE.mkdir(parents=True, exist_ok=True)
    source = REPO / "tools/tla-differential/bridges/SanyBridge.java"
    target = BRIDGE / "SanyBridge.class"
    if not target.is_file() or target.stat().st_mtime < source.stat().st_mtime:
        subprocess.run([str(JAVAC), "-J-XX:-UsePerfData", "-cp", str(SANY_JAR), "-d", str(BRIDGE), str(source)], check=True)


def invoke(argv: list[str], cwd: Path) -> tuple[int, bytes, bytes]:
    result = subprocess.run(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    return result.returncode, result.stdout, result.stderr


def outcome_sany(code: int, stdout: bytes) -> tuple[str, dict | None]:
    try:
        payload = json.loads(stdout)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return "unknown", None
    if code == 0 and payload.get("ok") is True:
        return "accepted", payload
    if code == 0 and payload.get("ok") is False and payload.get("errorLevel", 0) > 0:
        return "rejected", payload
    return "unknown", payload


def outcome_apalache(code: int, stdout: bytes, parsed: Path) -> str:
    text = stdout.decode("utf-8", errors="replace")
    if code == 0 and "PASS #0: SanyParser" in text and "Parsed successfully" in text and "EXITCODE: OK" in text and parsed.is_file():
        return "accepted"
    if code == 255 and "PASS #0: SanyParser" in text and "Parser has failed" in text and "EXITCODE: ERROR (255)" in text:
        return "rejected"
    return "unknown"


def write(path: Path, data: bytes) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return digest(data)


def run_case(output: Path, case: str, sources: dict[str, str], root: str) -> dict:
    case_dir = output / "cases" / case
    input_dir = case_dir / "input"
    input_dir.mkdir(parents=True)
    source_hashes = {name: write(input_dir / name, text.encode("utf-8")) for name, text in sorted(sources.items())}
    raw = {}
    sany_scratch = case_dir / "sany-tmp"; sany_scratch.mkdir()
    sany_argv = [str(JDK), "-XX:-UsePerfData", "-Xmx1g", "-Djava.io.tmpdir=" + str(sany_scratch), "-cp", f"{BRIDGE}:{SANY_JAR}", "SanyBridge", root]
    code, stdout, stderr = invoke(sany_argv, input_dir)
    raw["sany/stdout"] = write(case_dir / "sany/stdout.txt", stdout)
    raw["sany/stderr"] = write(case_dir / "sany/stderr.txt", stderr)
    sany_outcome, sany = outcome_sany(code, stdout)
    apa_scratch = case_dir / "apalache-tmp"; apa_scratch.mkdir()
    parsed = apa_scratch / "parsed.json"
    apa_argv = [str(JDK), "-XX:-UsePerfData", "-Xmx1g", "-Djava.io.tmpdir=" + str(apa_scratch), "-Duser.home=" + str(input_dir), "-jar", str(APALACHE_JAR), "--out-dir=" + str(apa_scratch), "parse", "--output=" + str(parsed), root]
    code2, stdout2, stderr2 = invoke(apa_argv, input_dir)
    raw["apalache/stdout"] = write(case_dir / "apalache/stdout.txt", stdout2)
    raw["apalache/stderr"] = write(case_dir / "apalache/stderr.txt", stderr2)
    if parsed.is_file(): raw["apalache/parsed"] = write(case_dir / "apalache/parsed.json", parsed.read_bytes())
    facts = None
    if sany and sany_outcome == "accepted":
        root_module = next((m for m in sany["modules"] if m["name"] == sany["root"]), {})
        facts = [{key: row.get(key) for key in ("name", "declaredIn", "arity", "local", "level")} for row in root_module.get("declarations", []) if row.get("kind") == "operator"]
    return {"case": case, "root": root, "sources": source_hashes,
            "sany": {"outcome": sany_outcome, "exitCode": code, "operators": facts},
            "apalache": {"outcome": outcome_apalache(code2, stdout2, parsed), "exitCode": code2}, "raw": raw}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=4, help="independent case pairs to run concurrently")
    parser.add_argument("--group", choices=("unicode", "enabled", "named-instance"), help="capture one independently indexed matrix group")
    parser.add_argument("--assemble", action="store_true", help="assemble the three completed groups into one matrix index")
    args = parser.parse_args(argv)
    output = args.output.resolve()
    if args.assemble:
        group_files = [output / group / "semantic.json" for group in ("unicode", "enabled", "named-instance")]
        if not all(path.is_file() for path in group_files): parser.error("all three group semantic files are required")
        rows = [{key: value for key, value in row.items() if key != "raw"}
                for path in group_files for row in json.loads(path.read_text(encoding="utf-8"))["rows"]]
        semantic = {"schema": "mirrors.dc0-live-matrix/v1", "rows": rows}
        write(output / "semantic.json", canonical(semantic))
        index = {"schema": "mirrors.dc0-live-matrix-index/v1", "semanticSha256": digest((output / "semantic.json").read_bytes()),
                 "groups": {path.parent.name: digest(path.read_bytes()) for path in group_files}}
        write(output / "artifact-index.json", canonical(index))
        print(json.dumps({"output": str(output), "semanticSha256": index["semanticSha256"], "rows": len(rows)}, sort_keys=True))
        return 0
    if not args.group: parser.error("--group is required unless --assemble is used")
    output = output / args.group
    if output.exists() and any(output.iterdir()): parser.error("output group must be new or empty")
    for required in (JDK, JAVAC, SANY_JAR, APALACHE_JAR):
        if not required.is_file(): parser.error(f"missing pinned dependency: {required}")
    output.mkdir(parents=True, exist_ok=True)
    compile_bridge()
    jobs: list[tuple[str, dict[str, str], str]] = []
    if args.group == "unicode":
        for index, (glyph, body) in enumerate(UNICODE_SOURCES.items(), 1):
            name = f"Dc0Unicode{index:02d}"
            jobs.append((f"unicode/{glyph}", {name + ".tla": module(name, body)}, name + ".tla"))
    if args.group == "enabled":
        for kind, body in ENABLED_SOURCES.items():
            name = "Dc0Enabled" + kind.title()
            jobs.append(("enabled/" + kind, {name + ".tla": module(name, body)}, name + ".tla"))
    fixture_root = REPO / "test/fixtures/tla-frontend"
    if args.group == "named-instance":
        for label, relative in INSTANCE_FIXTURES.items():
            files = sorted((fixture_root / relative).glob("*.tla"))
            roots = [path for path in files if "Root" in path.stem]
            if len(roots) != 1: raise RuntimeError(f"cannot determine root for {relative}")
            jobs.append(("named-instance/" + label, {p.name: p.read_text(encoding="utf-8") for p in files}, roots[0].name))
    if args.jobs < 1: parser.error("--jobs must be positive")
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        rows = list(pool.map(lambda job: run_case(output, *job), jobs))
    # Raw streams are indexed below but deliberately excluded from the
    # deterministic semantic payload: Apalache logs its private output path.
    semantic = {"schema": "mirrors.dc0-live-matrix/v1",
                "rows": [{key: value for key, value in row.items() if key != "raw"} for row in rows]}
    identity = {"java": subprocess.run([str(JDK), "-version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stderr.decode("utf-8", errors="replace"),
                "sanyJarSha256": digest(SANY_JAR.read_bytes()), "apalacheJarSha256": digest(APALACHE_JAR.read_bytes()),
                "bridgeSha256": digest((BRIDGE / "SanyBridge.class").read_bytes()), "unicodeGlyphCount": len(UNICODE_SOURCES)}
    write(output / "semantic.json", canonical(semantic))
    write(output / "identity.json", canonical(identity))
    index = {"schema": "mirrors.dc0-live-matrix-index/v1", "semanticSha256": digest((output / "semantic.json").read_bytes()), "identitySha256": digest((output / "identity.json").read_bytes()),
             "rawArtifacts": {row["case"] + "/" + key: value for row in rows for key, value in row["raw"].items()}}
    write(output / "artifact-index.json", canonical(index))
    print(json.dumps({"output": str(output), "semanticSha256": index["semanticSha256"], "rows": len(rows)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
