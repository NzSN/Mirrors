from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import unittest


TOOLS_DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIRECTORY))

import capture  # noqa: E402
import corpus  # noqa: E402


REPO = Path(__file__).resolve().parents[3]


class CaptureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.corpus = corpus.load_corpus(REPO)

    def test_borrowed_fixture_stages_only_relative_source_root_files(self) -> None:
        fixture = next(item for item in self.corpus.fixtures if item.id == "acc-generic-transfer")
        with tempfile.TemporaryDirectory() as temporary:
            materialized = capture.materialize_fixture(fixture=fixture, directory=Path(temporary) / "input")
            self.assertEqual(sorted(materialized.sources), ["GenericBase.tla", "GenericTransfer.tla"])
            self.assertEqual(materialized.root_path.name, "GenericTransfer.tla")
            capture.verify_materialized(materialized)

    def test_inline_fixture_remains_distinct_and_has_stable_digest(self) -> None:
        fixture = next(item for item in self.corpus.fixtures if item.id == "acc-inline-equivalent")
        self.assertEqual(capture.adapter_fixture(fixture).provider, "inline-source-map")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = capture.materialize_fixture(fixture=fixture, directory=root / "first")
            second = capture.materialize_fixture(fixture=fixture, directory=root / "second")
            self.assertEqual(first.input_digest, second.input_digest)
            self.assertEqual(first.root_path.name, "GenericExtendsRoot.tla")
            self.assertEqual(set(first.sources), {"GenericExtendsBase.tla", "GenericExtendsRoot.tla"})
            self.assertEqual(first.fixture.inline_source_map[0]["stagedPath"], "GenericExtendsBase.tla")

    def test_mutated_or_missing_staged_input_is_refused(self) -> None:
        fixture = next(item for item in self.corpus.fixtures if item.id == "acc-module-minimal")
        with tempfile.TemporaryDirectory() as temporary:
            materialized = capture.materialize_fixture(fixture=fixture, directory=Path(temporary) / "input")
            materialized.root_path.write_text("mutated")
            with self.assertRaisesRegex(capture.CaptureError, "changed"):
                capture.verify_materialized(materialized)

    def test_symlink_or_type_changed_staged_input_is_refused(self) -> None:
        fixture = next(item for item in self.corpus.fixtures if item.id == "acc-module-minimal")
        with tempfile.TemporaryDirectory() as temporary:
            materialized = capture.materialize_fixture(fixture=fixture, directory=Path(temporary) / "input")
            materialized.root_path.unlink()
            materialized.root_path.symlink_to("/dev/null")
            with self.assertRaisesRegex(capture.CaptureError, "missing"):
                capture.verify_materialized(materialized)

    def test_adapter_fixture_cannot_reach_expectations(self) -> None:
        fixture = self.corpus.fixtures[0]
        view = capture.adapter_fixture(fixture)
        self.assertFalse(hasattr(view, "summary"))
        self.assertFalse(hasattr(view, "manifest_expectation"))
        self.assertFalse(hasattr(view, "requirements"))

    def test_added_missing_dependency_is_refused_but_nested_artifacts_are_not_inputs(self):
        fixture = next(item for item in self.corpus.fixtures if item.id == "rej-extends-missing")
        with tempfile.TemporaryDirectory() as temporary:
            materialized = capture.materialize_fixture(fixture=fixture, directory=Path(temporary) / "input")
            artifacts = materialized.input_dir / "artifacts"
            artifacts.mkdir()
            (artifacts / "Output.tla").write_text("native output")
            capture.verify_materialized(materialized)
            (materialized.root_path.parent / "Missing.tla").write_text("---- MODULE Missing ----\n====\n")
            with self.assertRaisesRegex(capture.CaptureError, "source set changed"):
                capture.verify_materialized(materialized)


if __name__ == "__main__":
    unittest.main()
