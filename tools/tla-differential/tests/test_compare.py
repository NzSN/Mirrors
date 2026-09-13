from __future__ import annotations

from dataclasses import replace
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest


TOOLS_DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIRECTORY))

import compare  # noqa: E402
import corpus  # noqa: E402
import report  # noqa: E402


REPO = Path(__file__).resolve().parents[3]


class CompareTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        captured = corpus.load_corpus(REPO)
        fixture = next(item for item in captured.fixtures if item.id == "acc-generic-transfer")
        cls.captured = replace(captured, fixtures=(fixture,))
        cls.fixture = fixture

    def observations(self) -> list[dict[str, object]]:
        summary = self.fixture.summary
        assert summary is not None
        variables = copy.deepcopy(summary["effectiveVariables"])
        closure = [
            {"module": source["logicalPath"][:-4], "path": source["logicalPath"], "sha256": source["sha256"]}
            for source in summary["sources"]
        ]
        dependencies = [
            {"owner": edge["owner"], "dependency": edge["module"], "kind": edge["kind"], "local": edge["local"]}
            for edge in summary["dependencies"] if edge["resolution"] == "local"
        ]
        facts = {
            "outcome": {"capability": "supported", "value": "accepted"},
            "stage": {"capability": "supported", "value": {"stage": self.fixture.expected_stage, "reason": None}},
            "source_closure": {"capability": "supported", "value": closure},
            "variables": {"capability": "supported", "value": variables},
            "resolution": {"capability": "supported", "value": {"dependencies": dependencies, "operators": [{"name": "Op", "declaredIn": "M", "arity": 1, "local": False}]}},
            "substitution": {"capability": "supported", "value": []},
            "levels": {"capability": "supported", "value": [{"name": "Op", "declaredIn": "M", "level": "state"}]},
        }
        rows = []
        for engine in corpus.ENGINES:
            row_facts = copy.deepcopy(facts)
            if engine != "mirrors":
                row_facts["stage"]["value"] = {"stage": "parse", "reason": None}
            rows.append({
                "schema": corpus.OBSERVATION_SCHEMA, "fixture": self.fixture.id, "engine": engine,
                "provider": self.fixture.provider, "inputDigest": "a" * 64,
                "adapter": {"id": f"test.{engine}", "version": "1"},
                "tool": {"id": engine, "version": "1", "fingerprint": f"{engine}-pin"},
                "invocation": {"argv": [engine], "exitCode": 0}, "execution": "completed",
                "outcome": "accepted", "nativePhase": "parse", "stage": "sourceEvidence" if engine == "mirrors" else "parse",
                "diagnostics": [], "facts": row_facts, "rawArtifacts": [],
            })
        return rows

    def compare(self, rows: list[dict[str, object]], registry: dict[str, object] | None = None):
        return compare.compare_corpus(self.captured, rows, registry or {"schema": corpus.REGISTRY_SCHEMA, "candidates": [], "reviewed": []})

    def test_matching_subset_passes(self) -> None:
        _, _, verdict = self.compare(self.observations())
        self.assertEqual(verdict, "pass")

    def test_matching_malformed_arity_and_substitution_never_pass(self):
        for invalid in ("arity", "line", "kind", "value"):
            with self.subTest(invalid=invalid):
                rows = self.observations()
                for row in rows:
                    if invalid == "arity":
                        row["facts"]["resolution"]["value"]["operators"][0]["arity"] = -1
                    else:
                        instance = {"owner": "M", "name": "I", "module": "Child", "local": False,
                            "line": 0 if invalid == "line" else 1,
                            "substitutions": [{"formal": "x", "implicit": False,
                                "actual": {"kind": "unknown" if invalid == "kind" else "integer",
                                    "value": "wrong" if invalid == "value" else 1}}]}
                        row["facts"]["substitution"]["value"] = [instance]
                _, _, verdict = self.compare(rows)
                self.assertEqual(verdict, "fail")

    def test_altered_outcome_fails_even_when_other_rows_are_complete(self) -> None:
        rows = self.observations(); rows[0]["outcome"] = "rejected"; rows[0]["facts"] = {"outcome": {"capability": "supported", "value": "rejected"}, "stage": {"capability": "supported", "value": {"stage": self.fixture.expected_stage, "reason": None}}}
        comparisons, _, verdict = self.compare(rows)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any(row["fact"] == "outcome" and row["status"] == "fail" for row in comparisons))

    def test_missing_row_is_incomplete(self) -> None:
        _, _, verdict = self.compare(self.observations()[:-1])
        self.assertEqual(verdict, "incomplete")

    def test_wrong_origin_arity_level_and_dropped_dependency_fail(self) -> None:
        mutations = {
            "variables": lambda value: value["variables"]["value"][0].update({"declaredIn": "Wrong"}),
            "arity": lambda value: value["resolution"]["value"]["operators"][0].update({"arity": 2}),
            "level": lambda value: value["levels"]["value"][0].update({"level": "action"}),
            "dependency": lambda value: value["resolution"]["value"].update({"dependencies": []}),
        }
        for label, mutate in mutations.items():
            with self.subTest(label=label):
                rows = self.observations(); mutate(rows[1]["facts"])
                comparisons, _, verdict = self.compare(rows)
                self.assertEqual(verdict, "fail")
                self.assertTrue(any(row["status"] == "fail" for row in comparisons))

    def test_golden_variable_import_path_is_order_sensitive(self) -> None:
        rows = self.observations(); rows[0]["facts"]["variables"]["value"][0]["importPath"] = ["Wrong"]
        _, _, verdict = self.compare(rows)
        self.assertEqual(verdict, "fail")

    def test_golden_named_operator_levels_fail_on_wrong_level(self) -> None:
        fixture = next(item for item in corpus.load_corpus(REPO).fixtures if item.id == "acc-levels")
        summary = fixture.summary; assert summary is not None
        closure = [{"module": row["logicalPath"][:-4], "path": row["logicalPath"], "sha256": row["sha256"]} for row in summary["sources"]]
        facts = {
            "outcome": {"capability": "supported", "value": "accepted"},
            "stage": {"capability": "supported", "value": {"stage": "sourceEvidence", "reason": None}},
            "source_closure": {"capability": "supported", "value": closure},
            "variables": {"capability": "supported", "value": copy.deepcopy(summary["effectiveVariables"])},
            "resolution": {"capability": "supported", "value": {"dependencies": [], "operators": []}},
            "substitution": {"capability": "supported", "value": []},
            "levels": {"capability": "supported", "value": [{"name": name, "declaredIn": fixture.root, "level": level} for name, level in summary["levels"].items()]},
        }
        rows = [{"schema": corpus.OBSERVATION_SCHEMA, "fixture": fixture.id, "engine": engine, "provider": fixture.provider,
                 "inputDigest": "b" * 64, "adapter": {"id": engine, "version": "1"}, "tool": {"id": engine, "version": "1", "fingerprint": engine},
                 "invocation": {"argv": [], "exitCode": 0}, "execution": "completed", "outcome": "accepted", "nativePhase": "resolve",
                 "stage": "sourceEvidence" if engine == "mirrors" else "parse", "diagnostics": [], "facts": copy.deepcopy(facts), "rawArtifacts": []}
                for engine in corpus.ENGINES]
        rows[0]["facts"]["levels"]["value"][0]["level"] = "wrong"
        _, _, verdict = compare.compare_corpus(replace(self.captured, fixtures=(fixture,)), rows, {"schema": corpus.REGISTRY_SCHEMA, "candidates": [], "reviewed": []})
        self.assertEqual(verdict, "fail")

    def test_missing_required_fact_is_incomplete(self) -> None:
        rows = self.observations(); rows[1]["facts"]["variables"] = {"capability": "unqualified"}
        _, _, verdict = self.compare(rows)
        self.assertEqual(verdict, "incomplete")

    def test_crash_and_malformed_observation_fail_closed(self) -> None:
        rows = self.observations(); rows[1]["execution"] = "crash"; rows[1]["outcome"] = "unknown"; rows[1]["facts"]["outcome"]["value"] = "unknown"
        _, _, verdict = self.compare(rows)
        self.assertEqual(verdict, "incomplete")
        _, _, malformed_verdict = self.compare(["not an observation"])  # type: ignore[list-item]
        self.assertEqual(malformed_verdict, "fail")

    def reviewed_entry(self) -> dict[str, object]:
        return {
            "id": "reviewed-outcome", "fixtureIds": [self.fixture.id], "fields": ["outcome"],
            "expected": {"outcome": {"mirrors": "accepted", "sany": "rejected"}},
            "profile": self.captured.profile,
            "sourceDigests": {self.fixture.id: {source.logical_path: source.sha256 for source in self.fixture.supplied_sources}},
            "enginePins": {"mirrors": "mirrors-pin", "sany": "sany-pin"},
            "rationale": "test", "evidence": [{"path": "evidence.json", "sha256": "0" * 64}],
            "review": {"artifact": "report.json", "commit": "abc", "sha256": "0" * 64},
            "revisit": "when inputs change",
        }

    def test_stale_and_unused_reviewed_entries_fail(self) -> None:
        stale = self.reviewed_entry(); stale["sourceDigests"] = {self.fixture.id: {"bad": "digest"}}
        findings, _, verdict = self.compare(self.observations(), {"schema": corpus.REGISTRY_SCHEMA, "candidates": [], "reviewed": [stale]})
        self.assertEqual(verdict, "fail")
        self.assertTrue(any("stale source digests" in row["detail"] for row in findings))
        unused = self.reviewed_entry()
        _, _, verdict = self.compare(self.observations(), {"schema": corpus.REGISTRY_SCHEMA, "candidates": [], "reviewed": [unused]})
        self.assertEqual(verdict, "fail")

    def test_exact_review_is_consumed_but_unavailable_tool_is_incomplete(self):
        registry = {"schema": corpus.REGISTRY_SCHEMA, "candidates": [], "reviewed": [self.reviewed_entry()]}
        rows = self.observations()
        rows[1]["outcome"] = "rejected"
        rows[1]["facts"] = {"outcome": {"capability": "supported", "value": "rejected"}}
        findings, _, verdict = self.compare(rows, registry)
        self.assertEqual(verdict, "pass")
        self.assertEqual(sum(row["status"] == "reviewed_difference" for row in findings), 1)
        rows[1]["execution"] = "unavailable"
        rows[1]["outcome"] = "unknown"
        rows[1]["facts"] = {}
        findings, _, verdict = self.compare(rows, registry)
        self.assertEqual(verdict, "incomplete")
        self.assertTrue(any("could not execute" in row["detail"] for row in findings))

    def test_unknown_mirrors_phase_is_incomplete_and_fail_precedes_incomplete(self) -> None:
        rows = self.observations(); rows[0]["facts"]["stage"] = {"capability": "unqualified"}
        _, _, verdict = self.compare(rows)
        self.assertEqual(verdict, "incomplete")
        rows[1]["outcome"] = "rejected"; rows[1]["facts"]["outcome"]["value"] = "rejected"
        _, _, verdict = self.compare(rows)
        self.assertEqual(verdict, "fail")

    def test_semantic_payload_ignores_runtime_only_fields(self) -> None:
        rows = self.observations(); comparisons, coverage, verdict = self.compare(rows)
        inputs = {"semanticIdentity": {"corpusDigest": "c", "profileDigest": "p", "registryDigest": "r", "limits": {"timeout": 60}}}
        first = {"schema": corpus.REPORT_SCHEMA, "inputs": inputs, "observations": rows, "comparisons": comparisons, "coverage": coverage, "verdict": verdict}
        second = copy.deepcopy(first)
        second["observations"][0]["invocation"]["argv"] = ["/tmp/random", "--time=now"]
        second["observations"][0]["rawArtifacts"] = [{"path": "/tmp/raw.log", "sha256": "x"}]
        second["observations"][0]["diagnostics"] = [{"time": "later", "message": "raw"}]
        second["observations"].reverse()
        second["comparisons"].reverse()
        self.assertEqual(json.dumps(report.semantic_payload(first), sort_keys=True), json.dumps(report.semantic_payload(second), sort_keys=True))
        with tempfile.TemporaryDirectory() as temporary:
            report.write_report(Path(temporary) / "nested", inputs, rows, comparisons, coverage, verdict)
            self.assertTrue((Path(temporary) / "nested" / "report.json").is_file())


if __name__ == "__main__":
    unittest.main()
