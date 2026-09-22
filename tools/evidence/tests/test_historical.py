from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path


EVIDENCE = Path(__file__).resolve().parents[1]
ROOT = EVIDENCE.parents[1]
INDEX = ROOT / "Docs/evidence/historical-artifact-availability.json"

import sys

sys.path.insert(0, str(EVIDENCE))
import historical  # noqa: E402


class HistoricalTests(unittest.TestCase):
    def verify_mutation(self, document):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "historical.json"
            path.write_text(json.dumps(document), encoding="utf-8")
            return historical.verify_historical(path, ROOT)

    def test_checked_sidecar_covers_every_absolute_locator(self):
        result = historical.verify_historical(INDEX, ROOT)
        self.assertEqual(result["status"], "verified-historical-index")
        self.assertFalse(result["qualifying"])
        self.assertEqual(result["entries"], 43)
        self.assertEqual(result["availabilityCounts"]["unavailable-at-audit"], 40)
        self.assertEqual(result["availabilityCounts"]["external-with-policy"], 3)

    def test_duplicate_pointer_is_rejected(self):
        document = json.loads(INDEX.read_text())
        document["entries"].append(copy.deepcopy(document["entries"][0]))
        with self.assertRaisesRegex(ValueError, "duplicate historical pointer"):
            self.verify_mutation(document)

    def test_changed_recorded_hash_is_rejected(self):
        document = json.loads(INDEX.read_text())
        document["entries"][0]["recordedIdentity"]["value"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "recorded identity changed"):
            self.verify_mutation(document)

    def test_fresh_label_is_rejected(self):
        document = json.loads(INDEX.read_text())
        document["entries"][0]["availability"] = "fresh"
        with self.assertRaisesRegex(ValueError, "unsupported historical availability"):
            self.verify_mutation(document)

    def test_claimed_retained_artifact_requires_bytes(self):
        document = json.loads(INDEX.read_text())
        document["entries"][0]["availability"] = "retained-and-verified"
        with self.assertRaisesRegex(ValueError, "retainedPath"):
            self.verify_mutation(document)

    def test_source_record_hash_prevents_rewriting_history(self):
        document = json.loads(INDEX.read_text())
        document["sourceRecords"][0]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "source record hash changed"):
            self.verify_mutation(document)

    def test_progress_document_links_sidecar_and_new_run_remediation(self):
        progress = (ROOT / "Docs/application-integration-progress.md").read_text()
        normalized = " ".join(progress.split())
        self.assertIn("historical-artifact-availability.json", progress)
        self.assertIn("new E1 run ID", progress)
        self.assertIn("do not constitute retained or fresh evidence", normalized)

    def test_empty_scope_cannot_evade_the_four_record_audit(self):
        document = json.loads(INDEX.read_text())
        document["sourceRecords"] = []
        document["entries"] = []
        with self.assertRaisesRegex(ValueError, "source scope is incomplete"):
            self.verify_mutation(document)

    def test_source_and_retained_paths_cannot_escape_repository(self):
        document = json.loads(INDEX.read_text())
        document["sourceRecords"][0]["path"] = "../outside.json"
        with self.assertRaisesRegex(ValueError, "unsafe bundle path"):
            self.verify_mutation(document)
        document = json.loads(INDEX.read_text())
        document["entries"][0]["availability"] = "retained-and-verified"
        document["entries"][0]["retainedPath"] = "../outside.log"
        with self.assertRaisesRegex(ValueError, "unsafe bundle path"):
            self.verify_mutation(document)


if __name__ == "__main__":
    unittest.main()
