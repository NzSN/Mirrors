"""Observe the real borrowed CLI and provider-correct differential driver."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from corpus import OBSERVATION_SCHEMA
from normalize import mirrors_facts, supported
from process import ProcessRequest, run_process


def reason(diagnostic):
    code = diagnostic["code"]
    if code in {"TLA-LEX-UNICODE-STAGED", "TLA-PARSE-PLUSCAL-STAGED", "TLA-PARSE-UNSUPPORTED-SPELLING"}:
        return "profile_limit"
    if code == "TLA-LEX-INVALID-NUMBER" and diagnostic.get("message") == "decimal fractions and exponents are outside the revision-1 profile":
        return "profile_limit"
    limits = {"TLA-LEX-" + suffix for suffix in ("INTEGER-TOO-LARGE", "IDENTIFIER-TOO-LARGE", "COMMENT-NESTING", "TOKEN-TOO-LARGE", "TOO-MANY-TOKENS", "SOURCE-TOO-LARGE", "DIAGNOSTICS-TRUNCATED")}
    limits |= {"TLA-PARSE-" + suffix for suffix in ("DECLARATION-LIMIT", "NESTING-DEPTH", "RECURSION-LIMIT", "DIAGNOSTICS-TRUNCATED")}
    limits |= {"TLA-ELAB-" + suffix for suffix in ("DECLARATION-LIMIT", "SYMBOL-LIMIT", "FUEL-EXHAUSTED", "DIAGNOSTICS-TRUNCATED")}
    limits |= {"TLA-GRAPH-" + suffix for suffix in ("TOO-MANY-MODULES", "DEPENDENCY-TOO-DEEP", "TOO-MANY-EDGES", "FUEL-EXHAUSTED")}
    if code in limits:
        return "limit"
    malformed = {
        "LEX": "INVALID-UTF8 CONTROL-CHARACTER UNKNOWN-CHARACTER UNTERMINATED-STRING NEWLINE-IN-STRING INVALID-ESCAPE INVALID-NUMBER UNTERMINATED-COMMENT",
        "PARSE": "MODULE-HEADER MODULE-END TRAILING-CONTENT EXPECTED-IDENTIFIER EXPECTED-EXPRESSION MIXED-BOUNDS EXPECTED-TOKEN PRECEDENCE-CONFLICT PROOF-TERMINATION PROOF-UNSUPPORTED",
        "ELAB": "DUPLICATE-DECLARATION AMBIGUOUS-IMPORT UNKNOWN-NAME ARITY-MISMATCH ASSUMPTION-LEVEL SUBSTITUTION-MISSING SUBSTITUTION-INVALID SUBSTITUTION-DUPLICATE SUBSTITUTION-ARITY SUBSTITUTION-LEVEL",
        "GRAPH": "ROOT-HEADER-MISMATCH DEPENDENCY-HEADER-MISMATCH DUPLICATE-MODULE MISSING-MODULE CYCLE",
    }
    if code in {f"TLA-{family}-{suffix}" for family, suffixes in malformed.items() for suffix in suffixes.split()}:
        return "malformed"
    return None


def classify(document, exit_code):
    expected_keys = {"command", "dependencies", "diagnostics", "levels", "module", "ok", "operators", "schema", "source", "sources", "variables"}
    if not isinstance(document, dict) or set(document) != expected_keys or document["schema"] != "mirrors.tla-frontend-inspection/v1":
        raise ValueError("invalid inspection document schema")
    errors = [d for d in document["diagnostics"] if d["severity"] == "error"]
    if exit_code == 0 and document["ok"] is True and not errors and isinstance(document["module"], str):
        return "accepted"
    if exit_code == 1 and document["ok"] is False and errors and document["module"] is None:
        if any(document[k] for k in ("variables", "sources", "operators", "levels", "dependencies")):
            raise ValueError("rejected inspection contains partial facts")
        return "rejected"
    raise ValueError("contradictory inspection exit/outcome/diagnostics")


def observe(*, fixture, materialized, config, limits, artifact_dir):
    driver = Path(str(config["driver"])).resolve()
    cli = Path(str(config["cli"])).resolve()
    output_root = artifact_dir.parents[3]
    observation = {"schema": OBSERVATION_SCHEMA, "fixture": fixture.id, "engine": "mirrors", "provider": fixture.provider,
                   "inputDigest": materialized.input_digest, "adapter": {"id": "mirrors", "version": "1"},
                   "tool": config["tool"], "invocation": {"argv": [], "exitCode": None}, "execution": "unavailable",
                   "outcome": "unknown", "nativePhase": None, "stage": None, "diagnostics": [], "facts": {}, "rawArtifacts": []}
    if not driver.is_file() or not cli.is_file():
        return observation
    if fixture.provider == "inline-source-map":
        request = materialized.input_dir / "request.json"
        request.write_text(json.dumps({"root": fixture.root, "sources": [
            {"name": item["logicalName"], "text": materialized.source_bytes[item["stagedPath"]].decode("utf-8")}
            for item in fixture.inline_source_map]}))
        commands = [("driver", [str(driver), "inline", str(request)])]
    else:
        commands = [("cli", [str(cli), "resolve", "--spec", str(materialized.root_path), "--format", "json"]),
                    ("driver", [str(driver), "borrowed", str(materialized.root_path), fixture.root])]
    documents = {}
    for label, argv in commands:
        result = run_process(ProcessRequest(argv, materialized.root_path.parent), limits)
        observation["execution"] = result.status.value
        observation["invocation"] = {"argv": argv, "exitCode": result.returncode}
        for stream, content in (("stdout", result.stdout), ("stderr", result.stderr)):
            path = artifact_dir / f"{label}-{stream}.txt"
            path.write_bytes(content)
            observation["rawArtifacts"].append({"path": path.relative_to(output_root).as_posix(), "sha256": hashlib.sha256(content).hexdigest()})
        if result.status.value != "completed":
            return observation
        try:
            data = json.loads(result.stdout)
            inspection = data if label == "cli" else data["inspection"]
            if label == "driver" and (set(data) != {"schema", "inspection", "modules"} or data["schema"] != "mirrors.tla-differential-driver/v1"):
                raise ValueError("invalid driver schema")
            outcome = classify(inspection, result.returncode)
            documents[label] = data
        except (ValueError, KeyError, TypeError) as error:
            observation["execution"] = "invalid_output"
            observation["diagnostics"] = [{"message": str(error)}]
            return observation
    driver_data = documents["driver"]
    inspection = driver_data["inspection"]
    # The CLI discovers a root header; the corpus provider requires the supplied
    # root identity. Compare CLI equivalence only where those requests coincide.
    cli_same_identity = "cli" in documents and documents["cli"]["module"] in (fixture.root, None)
    if cli_same_identity and documents["cli"] != inspection:
        observation["execution"] = "invalid_output"
        observation["diagnostics"] = [{"message": "CLI and driver facts disagree on identical captured sources"}]
        return observation
    observation["outcome"] = outcome
    observation["nativePhase"] = "resolve"
    observation["diagnostics"] = inspection["diagnostics"]
    observation["facts"]["outcome"] = supported(outcome)
    if outcome == "accepted":
        observation["facts"].update(mirrors_facts(driver_data))
        observation["stage"] = "sourceEvidence"
        observation["facts"]["stage"] = supported({"stage": "sourceEvidence", "reason": None})
    else:
        error = next(d for d in inspection["diagnostics"] if d["severity"] == "error")
        observation["stage"] = error["stage"]
        why = reason(error)
        observation["facts"]["stage"] = supported({"stage": error["stage"], "reason": why}) if why else {"capability": "unqualified"}
    return observation
