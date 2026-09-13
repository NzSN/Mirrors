from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


TOOLS_DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIRECTORY))

import corpus  # noqa: E402
import run  # noqa: E402


REPO = Path(__file__).resolve().parents[3]


def completed_observation(**kwargs: object) -> dict[str, object]:
    fixture = kwargs["fixture"]
    materialized = kwargs["materialized"]
    engine = kwargs["config"]["engine"]
    return {
        "schema": corpus.OBSERVATION_SCHEMA,
        "fixture": fixture.id,
        "engine": engine,
        "provider": fixture.provider,
        "inputDigest": materialized.input_digest,
        "adapter": {"id": f"test.{engine}", "version": "1"},
        "tool": {"id": engine, "version": "test", "fingerprint": "test"},
        "invocation": {"argv": [engine], "exitCode": 0},
        "execution": "completed",
        "outcome": "accepted",
        "nativePhase": "parse",
        "stage": "parse",
        "diagnostics": [],
        "facts": {"outcome": {"capability": "supported", "value": "accepted"}},
        "rawArtifacts": [],
    }


class RunTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.captured = corpus.load_corpus(REPO)

    def test_missing_adapters_produce_all_unknown_unavailable_rows(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            observations = run.run_corpus(captured=self.captured, adapters={}, configs={}, output_dir=Path(temporary))
            self.assertEqual(len(observations), len(self.captured.fixtures) * len(corpus.ENGINES))
            self.assertTrue(all(row["execution"] == "unavailable" and row["outcome"] == "unknown" for row in observations))
            self.assertTrue((Path(temporary) / "fixtures" / "acc-module-minimal" / "mirrors" / "observation.json").is_file())

    def test_adapter_cannot_return_expectation_derived_or_wrong_identity_row(self) -> None:
        def wrong_identity(**kwargs: object) -> dict[str, object]:
            row = completed_observation(**kwargs)
            row["fixture"] = "wrong"
            return row

        configs = {engine: {"engine": engine} for engine in corpus.ENGINES}
        with tempfile.TemporaryDirectory() as temporary:
            observations = run.run_corpus(
                captured=self.captured,
                adapters={engine: wrong_identity for engine in corpus.ENGINES},
                configs=configs,
                output_dir=Path(temporary),
            )
        self.assertTrue(all(row["execution"] == "crash" and row["outcome"] == "unknown" for row in observations))

    def test_all_engines_receive_identical_digest_for_each_fixture(self) -> None:
        configs = {engine: {"engine": engine} for engine in corpus.ENGINES}
        with tempfile.TemporaryDirectory() as temporary:
            observations = run.run_corpus(
                captured=self.captured,
                adapters={engine: completed_observation for engine in corpus.ENGINES},
                configs=configs,
                output_dir=Path(temporary),
            )
        by_fixture: dict[str, set[str]] = {}
        for row in observations:
            by_fixture.setdefault(row["fixture"], set()).add(row["inputDigest"])
        self.assertEqual(set(by_fixture), {fixture.id for fixture in self.captured.fixtures})
        self.assertTrue(all(len(digests) == 1 for digests in by_fixture.values()))

    def test_code_snapshot_changes_after_tracked_implementation_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "tools/tla-differential"; source.mkdir(parents=True)
            probe = source / "probe.py"; probe.write_text("before\n")
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "add", "tools/tla-differential/probe.py"], cwd=root, check=True)
            before = run.code_snapshot(root)
            probe.write_text("after\n")
            after = run.code_snapshot(root)
        self.assertIn("tools/tla-differential/probe.py", before)
        self.assertNotEqual(before, after)


if __name__ == "__main__":
    unittest.main()
