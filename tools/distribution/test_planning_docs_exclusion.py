import subprocess
import tempfile
import unittest
import copy
import json
from unittest.mock import patch
from pathlib import Path

import refresh_identity
from collect import component_ref, planning_documentation_audit
from manifest_check import digest_json
from snapshot_sources import snapshot


def git(repository: Path, *arguments: str) -> None:
    subprocess.run(["git", *arguments], cwd=repository, check=True, capture_output=True)


class PlanningDocumentationExclusionTests(unittest.TestCase):
    def test_real_catalog_refresh_preserves_selection_and_capture_time(self) -> None:
        original = json.loads((refresh_identity.MIRRORS / "catalog/framework-catalog.json").read_text())
        record = (refresh_identity.MIRRORS / "catalog/components/mirrors.json").read_bytes()
        with tempfile.TemporaryDirectory() as temporary:
            repository = self.repository(temporary)
            (repository / "catalog/components").mkdir(parents=True)
            (repository / "catalog/framework-catalog.json").write_text(json.dumps(original))
            (repository / "catalog/components/mirrors.json").write_bytes(record)
            git(repository, "add", ".")
            git(repository, "commit", "-m", "catalog fixture")
            refs = {entry["componentRef"]["componentId"]: entry["componentRef"]
                    for entry in original["components"]}
            with patch.object(refresh_identity, "MIRRORS", repository):
                def refresh():
                    refs["mirrors"] = component_ref("mirrors", repository,
                        refresh_identity.exclusions("mirrors", repository))
                    return refresh_identity.update_catalogs(refs, repository, False)
                for _ in range(3):
                    refresh()
                value = json.loads((repository / "catalog/framework-catalog.json").read_text())
                value["extensions"]["org.nzsn.snapshot"]["capturedAt"] = "2000-01-01T00:00:00Z"
                (repository / "catalog/framework-catalog.json").write_text(json.dumps(value))
                baseline = refresh()
                (repository / "Plans/plan.md").write_text("first planning edit\n")
                (repository / "Plans/new.md").write_text("new plan\n")
                (repository / "CHECKPOINTS.md").write_text("checkpoint\n")
                self.assertEqual(refresh(), baseline)
                (repository / "Plans/plan.md").unlink()
                self.assertEqual(refresh(), baseline)
                (repository / "tools/registry.py").write_text("VALUE = 2\n")
                self.assertNotEqual(refresh()[1], baseline[1])

    def test_snapshot_membership_ignores_tracked_and_new_planning(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = self.repository(temporary)
            reference = component_ref("mirrors", repository, {})
            first = snapshot(repository, reference, Path(temporary) / "first")
            (repository / "Plans/plan.md").unlink()
            (repository / "Plans/new.md").write_text("new planning record\n")
            second = snapshot(repository, reference, Path(temporary) / "second")
            self.assertEqual(first, second)
            self.assertFalse(any(entry["path"].startswith("Plans/") for entry in first["files"]))

    def test_complete_catalog_identity_ignores_planning_only_changes(self) -> None:
        original = json.loads((refresh_identity.MIRRORS / "catalog/framework-catalog.json").read_text())
        for state in ["clean", "editor-cache", "implementation-dirty"]:
            with self.subTest(state=state), tempfile.TemporaryDirectory() as temporary:
                repository = self.repository(temporary)
                if state == "editor-cache":
                    (repository / ".projectile-cache.eld").write_text("cache\n")
                if state == "implementation-dirty":
                    (repository / "tools/registry.py").write_text("VALUE = 2\n")
                def selected():
                    value = copy.deepcopy(original)
                    reference = component_ref("mirrors",repository,
                        refresh_identity.exclusions("mirrors",repository))
                    next(item for item in value["components"]
                         if item["componentRef"]["componentId"] == "mirrors")["componentRef"] = reference
                    return reference,digest_json(value)
                baseline = selected()
                (repository / "Plans/plan.md").write_text("updated status\n")
                self.assertEqual(selected(),baseline)
                (repository / "Plans/new.md").write_text("new planning record\n")
                self.assertEqual(selected(),baseline)
                (repository / "Plans/plan.md").unlink()
                self.assertEqual(selected(),baseline)
                (repository / "Plans/new.md").unlink()
                git(repository,"checkout","--","Plans/plan.md")
                self.assertEqual(selected(),baseline)
                (repository / "tools/registry.py").write_text("VALUE = 3\n")
                self.assertNotEqual(selected(),baseline)

    def repository(self, temporary: str) -> Path:
        repository = Path(temporary) / "mirrors"
        repository.mkdir()
        git(repository, "init")
        git(repository, "config", "user.email", "planning@example.invalid")
        git(repository, "config", "user.name", "Planning Test")
        (repository / "tools").mkdir()
        (repository / "tools/registry.py").write_text("VALUE = 1\n")
        (repository / "Plans").mkdir()
        (repository / "Plans/plan.md").write_text("plan v1\n")
        (repository / "AGENTS.md").write_text("agents v1\n")
        git(repository, "add", ".")
        git(repository, "commit", "-m", "initial")
        return repository

    def test_planning_documents_are_excluded_and_do_not_move_the_digest(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = self.repository(temporary)
            (repository / "Plans/plan.md").write_text("plan v2\n")
            (repository / "CHECKPOINTS.md").write_text("checkpoints v1\n")
            (repository / "tmp").mkdir()
            (repository / "tmp/note.md").write_text("note v1\n")
            (repository / "AGENTS.md").write_text("agents v2\n")

            excluded = refresh_identity.exclusions("mirrors", repository)
            self.assertEqual(excluded, {
                "Plans/plan.md": "planning-documentation",
                "CHECKPOINTS.md": "planning-documentation",
                "tmp/note.md": "planning-documentation",
            })
            ref = component_ref("mirrors", repository, excluded)
            self.assertEqual(ref["dirtyContent"]["includedPaths"], ["AGENTS.md"])
            reasons = {entry["path"]: entry["reasonCode"]
                       for entry in ref["dirtyContent"]["excludedPaths"]}
            self.assertEqual(reasons, {})
            audit = planning_documentation_audit("mirrors", repository)
            self.assertEqual(audit["paths"], ["CHECKPOINTS.md", "Plans/plan.md", "tmp/note.md"])
            baseline = ref["dirtyContent"]["digest"]

            (repository / "Plans/plan.md").write_text("plan v3 - edited again\n")
            (repository / "CHECKPOINTS.md").write_text("checkpoints v2\n")
            (repository / "Plans/another-plan.md").write_text("new plan\n")
            repeated = component_ref("mirrors", repository,
                                     refresh_identity.exclusions("mirrors", repository))
            self.assertEqual(repeated["dirtyContent"]["digest"], baseline)
            self.assertNotEqual(planning_documentation_audit("mirrors", repository)["digest"], audit["digest"])

            (repository / "tools/registry.py").write_text("VALUE = 2\n")
            changed = component_ref("mirrors", repository,
                                    refresh_identity.exclusions("mirrors", repository))
            self.assertNotEqual(changed["dirtyContent"]["digest"], baseline)
            self.assertIn("tools/registry.py", changed["dirtyContent"]["includedPaths"])

    def test_q3_report_stays_evidence_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = self.repository(temporary)
            (repository / "Plans/q3-readiness-2026-09-25.md").write_text("readiness\n")
            excluded = refresh_identity.exclusions("mirrors", repository)
            self.assertEqual(excluded["Plans/q3-readiness-2026-09-25.md"], "evidence-output")


if __name__ == "__main__":
    unittest.main()
