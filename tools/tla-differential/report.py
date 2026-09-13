"""Portable evidence report plus a deterministic semantic comparison payload."""
import hashlib
import json
from pathlib import Path
from corpus import REPORT_SCHEMA, canonical_json, validate_contract
from normalize import ordered
from compare import projection


def semantic_payload(report):
    observations = []
    for observation in report["observations"]:
        row = {key: observation[key] for key in ("fixture", "engine", "provider", "inputDigest", "execution", "outcome", "stage")}
        facts = {}
        for key, fact in observation["facts"].items():
            value = dict(fact)
            if fact["capability"] == "supported":
                if key == "substitution":
                    value["value"] = ordered([{**item, "substitutions": ordered(item["substitutions"])} for item in fact["value"]])
                elif key != "variables" or row["engine"] != "mirrors":
                    value["value"] = projection(key, fact["value"])
            facts[key] = value
        row["facts"] = facts
        observations.append(row)
    return {"inputs": report["inputs"]["semanticIdentity"],
            "observations": sorted(observations, key=lambda row: (row["fixture"], row["engine"])),
            "comparisons": ordered(report["comparisons"]), "coverage": report["coverage"], "verdict": report["verdict"]}


def write_report(output_dir, inputs, observations, comparisons, coverage, verdict):
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    value = {"schema": REPORT_SCHEMA, "inputs": inputs, "observations": list(observations),
             "comparisons": comparisons, "coverage": coverage, "verdict": verdict}
    validate_contract("report", value)
    (output_dir / "report.json").write_text(canonical_json(value) + "\n")
    semantic = canonical_json(semantic_payload(value)) + "\n"
    (output_dir / "semantic.json").write_text(semantic)
    lines = ["# TLA+ differential validation", "", f"Verdict: **{verdict}**.", "",
             f"{coverage['fixtures']} fixtures; {coverage['branches']} branches; {coverage['observations']}/{coverage['expectedObservations']} observations.",
             f"Semantic SHA-256: `{hashlib.sha256(semantic.encode()).hexdigest()}`.", "",
             "| Comparison status | Count |", "| --- | ---: |"]
    lines += [f"| {key} | {count} |" for key, count in coverage["comparisons"].items()]
    lines += ["", "## Findings", ""]
    lines += [f"- `{row['fixture']}` / {row['engine']} / {row['fact']}: {row['status']} — {row['detail']}"
              for row in comparisons if row["status"] in ("fail", "incomplete", "oracle_disagreement")]
    lines += ["", "Raw evidence and exact comparisons: [report.json](report.json).",
              "Unsupported surfaces are coverage gaps, not passed comparisons. This report does not certify complete TLA+ conformance.", ""]
    (output_dir / "summary.md").write_text("\n".join(lines))
    return value
