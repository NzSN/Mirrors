import subprocess
import tempfile
import unittest
from pathlib import Path

import refresh_identity
from collect import component_ref


def git(repository: Path, *arguments: str) -> None:
    subprocess.run(["git", *arguments], cwd=repository, check=True, capture_output=True)


class PlanningDocumentationExclusionTests(unittest.TestCase):
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
            self.assertEqual(reasons["Plans/plan.md"], "planning-documentation")
            self.assertEqual(reasons["CHECKPOINTS.md"], "planning-documentation")
            self.assertEqual(reasons["tmp/note.md"], "planning-documentation")
            baseline = ref["dirtyContent"]["digest"]

            (repository / "Plans/plan.md").write_text("plan v3 - edited again\n")
            (repository / "CHECKPOINTS.md").write_text("checkpoints v2\n")
            (repository / "Plans/another-plan.md").write_text("new plan\n")
            repeated = component_ref("mirrors", repository,
                                     refresh_identity.exclusions("mirrors", repository))
            self.assertEqual(repeated["dirtyContent"]["digest"], baseline)

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
