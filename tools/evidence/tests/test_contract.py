from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator


EVIDENCE = Path(__file__).resolve().parents[1]
FIXTURES = EVIDENCE / "fixtures"
SCHEMAS = EVIDENCE / "schema"
sys.path.insert(0, str(EVIDENCE))

import validate  # noqa: E402


def fixture(name: str):
    return validate.load_json(FIXTURES / name)


def mutate(document, operation: str, path: list, value=None):
    current = document
    for part in path[:-1]:
        current = current[part]
    final = path[-1]
    if operation == "set":
        current[final] = value
    elif operation == "delete":
        del current[final]
    else:  # pragma: no cover - fixture author error
        raise AssertionError(f"unknown mutation operation: {operation}")


class ContractTests(unittest.TestCase):
    maxDiff = None

    def assertValid(self, document):
        self.assertEqual(validate.validate_document(document), [])

    def assertRejected(self, document, message: str | None = None):
        errors = validate.validate_document(document)
        self.assertTrue(errors, "document unexpectedly validated")
        if message is not None:
            self.assertTrue(any(message in error for error in errors), errors)

    def test_schemas_are_valid_draft_2020_12(self):
        for name in ["attachment-plan-v1.schema.json", "bundle-index-v1.schema.json",
                     "evidence-envelope-v1.schema.json", "public-summary-v1.schema.json"]:
            Draft202012Validator.check_schema(validate.load_json(SCHEMAS / name))

    def test_all_valid_fixtures(self):
        names = sorted(path.name for path in FIXTURES.glob("*.valid.json"))
        self.assertEqual(len(names), 6)
        for name in names:
            with self.subTest(name=name):
                self.assertValid(fixture(name))

    def test_all_rejected_mutation_fixtures(self):
        corpus = fixture("rejected-cases.json")
        self.assertEqual(corpus["schemaVersion"], "mirrors.evidence-contract-rejected-fixtures/v1")
        for case in corpus["cases"]:
            with self.subTest(name=case["name"]):
                document = fixture(case["base"])
                mutate(document, case["operation"], case["path"], case.get("value"))
                self.assertRejected(document)

    def test_dirty_identity_requires_content_digest(self):
        document = fixture("envelope-private.dirty.valid.json")
        del document["components"][0]["dirtyContent"]
        self.assertRejected(document, "dirtyContent")

    def test_unknown_major_and_minor_fail_closed(self):
        for version in ["mirrors.evidence-envelope/v2.0", "mirrors.evidence-envelope/v1.1"]:
            document = fixture("envelope-private.valid.json")
            document["schemaVersion"] = version
            self.assertRejected(document, "unsupported evidence schema")

    def test_schema_version_must_be_string(self):
        document = fixture("envelope-private.valid.json")
        document["schemaVersion"] = []
        self.assertRejected(document, "must be a string")

    def test_complete_bundle_rejects_missing_required_artifact(self):
        document = fixture("envelope-private.valid.json")
        document["artifacts"].pop()
        self.assertRejected(document, "complete bundle is missing required artifact")

    def test_outcome_axes_cannot_be_merged(self):
        for field, value in [("cleanupStatus", "confirmed"), ("persistenceStatus", "complete")]:
            document = fixture("envelope-private.valid.json")
            document["outcomes"]["behavior"][field] = value
            self.assertRejected(document, "Additional properties")

    def test_required_skip_cannot_be_qualified(self):
        document = fixture("envelope-private.required-skip.valid.json")
        document["qualification"] = {"status": "qualified", "reasonCodes": []}
        self.assertRejected(document, "qualified requires every required tier to pass")

    def test_cleanup_failure_does_not_rewrite_behavior(self):
        document = fixture("envelope-private.cleanup-failure.valid.json")
        self.assertEqual(document["outcomes"]["behavior"]["status"], "passed")
        self.assertEqual(document["outcomes"]["cleanup"][0]["status"], "failed")
        self.assertValid(document)

    def test_persistence_failure_does_not_rewrite_behavior_or_cleanup(self):
        document = fixture("envelope-private.persistence-failure.valid.json")
        self.assertEqual(document["outcomes"]["behavior"]["status"], "passed")
        self.assertEqual(document["outcomes"]["cleanup"][0]["status"], "confirmed")
        self.assertEqual(document["outcomes"]["persistence"]["status"], "failed")
        self.assertValid(document)

    def test_public_canary_rejected_in_each_free_text_class(self):
        mutations = [
            (["components", 0, "repository"], "https://example.invalid/MIRRORS_PRIVATE_CANARY_REPOSITORY"),
            (["environment", "os"], "MIRRORS_PRIVATE_CANARY_OS"),
            (["environment", "tools", 0, "version"], "MIRRORS_PRIVATE_CANARY_TOOL"),
            (["commands", 0, "approvedArgs"], ["MIRRORS_PRIVATE_CANARY_ARGUMENT"]),
            (["artifacts", 0, "mediaType"], "application/MIRRORS_PRIVATE_CANARY_MEDIA"),
        ]
        for path, value in mutations:
            with self.subTest(path=path):
                document = fixture("public-summary.valid.json")
                mutate(document, "set", path, value)
                self.assertRejected(document, "private canary")

    def test_public_references_cannot_name_private_or_absent_artifacts(self):
        document = fixture("public-summary.valid.json")
        document["tiers"][0]["artifactIds"] = ["command-log-private"]
        self.assertRejected(document, "does not resolve to a public artifact")

    def test_public_repository_and_artifacts_are_reviewed_locators(self):
        document = fixture("public-summary.valid.json")
        document["components"][0]["repository"] = "/private/checkout"
        self.assertRejected(document)
        document = fixture("public-summary.valid.json")
        document["artifacts"][0]["location"] = {"kind": "external", "immutableUri": "https://example.invalid/result"}
        self.assertRejected(document)

    def test_logical_path_rejects_aliases_and_host_paths(self):
        invalid = [
            "/absolute/log",
            "C:/private/log",
            "artifacts/private/../secret",
            "artifacts/private/./log",
            "artifacts//private/log",
            "artifacts\\private\\log",
            "artifacts/private/control\u0001log",
        ]
        for path in invalid:
            with self.subTest(path=repr(path)):
                document = fixture("envelope-private.valid.json")
                document["artifacts"][0]["location"]["path"] = path
                self.assertRejected(document)

    def test_exit_is_a_discriminated_union(self):
        invalid = [
            {"kind": "code"},
            {"kind": "code", "code": 0, "signal": "SIGTERM"},
            {"kind": "signal"},
            {"kind": "signal", "signal": "SIGTERM", "code": 143},
            {"kind": "not-started", "code": 0},
        ]
        for exit_value in invalid:
            with self.subTest(exit=exit_value):
                document = fixture("envelope-private.valid.json")
                document["commands"][0]["exit"] = exit_value
                self.assertRejected(document)

    def test_wall_clock_requires_utc_z_and_monotonic_duration_is_independent(self):
        document = fixture("envelope-private.valid.json")
        document["timestamps"]["startedAtUtc"] = "2026-09-22T09:00:00+08:00"
        self.assertRejected(document)
        document = fixture("envelope-private.valid.json")
        document["timestamps"]["finishedAtUtc"] = "2026-09-21T23:59:59Z"
        self.assertRejected(document, "must not precede")

    def test_run_ref_pairs_schema_and_projection(self):
        schema = validate.load_json(SCHEMAS / "evidence-envelope-v1.schema.json")
        run_schema = {"$ref": "#/$defs/runRef", "$defs": schema["$defs"]}
        validator = Draft202012Validator(run_schema)
        valid = {
            "schemaVersion": "mirrors.evidence-envelope/v1.0",
            "runId": "fixture-run",
            "envelopeSha256": "a" * 64,
            "projectionKind": "private",
        }
        self.assertFalse(list(validator.iter_errors(valid)))
        invalid = copy.deepcopy(valid)
        invalid["projectionKind"] = "public"
        self.assertTrue(list(validator.iter_errors(invalid)))

    def test_structural_records_cannot_create_hash_cycles(self):
        for role in ["public-summary", "private-index"]:
            document = fixture("envelope-private.valid.json")
            document["artifacts"][0]["role"] = role
            self.assertRejected(document)
        document = fixture("envelope-private.valid.json")
        document["envelopeSha256"] = "e" * 64
        self.assertRejected(document, "Additional properties")

    def test_input_bounds_and_non_json_values_fail_before_schema(self):
        document = fixture("envelope-private.valid.json")
        document["timestamps"]["monotonicDurationNs"] = validate.MAX_SAFE_INTEGER + 1
        self.assertRejected(document, "safe JSON range")
        document = fixture("envelope-private.valid.json")
        document["timestamps"]["monotonicDurationNs"] = 1.5
        self.assertRejected(document, "non-integer JSON number")
        cyclic = {"schemaVersion": "mirrors.evidence-envelope/v1.0"}
        cyclic["cycle"] = cyclic
        self.assertRejected(cyclic, "depth")


if __name__ == "__main__":
    unittest.main()
