from __future__ import annotations

import copy
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import corpus  # noqa: E402

REPO = HERE.parents[1]


class CorpusTests(unittest.TestCase):
    def test_current_corpus_is_captured_with_frozen_input_bytes(self) -> None:
        captured = corpus.validate_corpus(REPO)
        self.assertEqual((len(captured.fixtures), sum(x.kind == "accepted" for x in captured.fixtures), sum(x.kind == "rejected" for x in captured.fixtures), len(captured.branch_ids)), (60, 33, 27, 75))
        inline = next(x for x in captured.fixtures if x.id == "acc-inline-equivalent")
        self.assertEqual(inline.provider, "inline-source-map")
        self.assertEqual(len(inline.supplied_sources), 2)
        self.assertEqual(len(inline.expected_reachable_sources or ()), 2)
        self.assertIsNotNone(inline.summary)
        rejected = next(x for x in captured.fixtures if x.id == "rej-no-terminator")
        self.assertIsNone(rejected.expected_reachable_sources)
        self.assertTrue(rejected.supplied_sources[0].normalized_bytes)

    def test_refuses_manifest_path_duplicate_source_and_unknown_branch(self) -> None:
        manifest = json.loads((REPO / "test/fixtures/tla-frontend/manifest.json").read_text())
        bad_path = copy.deepcopy(manifest); bad_path["fixtures"][0]["files"] = ["../escape.tla"]
        with self.assertRaisesRegex(corpus.CorpusError, "relative"):
            corpus.validate_manifest(bad_path, REPO / "test/fixtures/tla-frontend")
        duplicate = copy.deepcopy(manifest); duplicate["fixtures"][1]["id"] = duplicate["fixtures"][0]["id"]
        with self.assertRaisesRegex(corpus.CorpusError, "duplicate"):
            corpus.validate_manifest(duplicate, REPO / "test/fixtures/tla-frontend")
        unknown = copy.deepcopy(manifest); unknown["fixtures"][0]["branches"].append("unknown.fact")
        with self.assertRaisesRegex(corpus.CorpusError, "unknown branch"):
            corpus.validate_manifest(unknown, REPO / "test/fixtures/tla-frontend")
        missing = copy.deepcopy(manifest); missing["fixtures"][0]["files"] = ["accepted/nope.tla"]
        with self.assertRaisesRegex(corpus.CorpusError, "missing source"):
            corpus.validate_manifest(missing, REPO / "test/fixtures/tla-frontend")
        outside_root = copy.deepcopy(manifest); outside_root["fixtures"][0]["files"] = ["rejected/RejectCommentDepth.tla"]
        with self.assertRaisesRegex(corpus.CorpusError, "outside sourceRoot"):
            corpus.validate_manifest(outside_root, REPO / "test/fixtures/tla-frontend")

    def test_refuses_inline_provider_shape_and_symlinked_or_non_utf8_source(self) -> None:
        manifest = json.loads((REPO / "test/fixtures/tla-frontend/manifest.json").read_text())
        inline = next(row for row in manifest["fixtures"] if row["provider"] == "inline-source-map")
        bad_root = copy.deepcopy(manifest); next(row for row in bad_root["fixtures"] if row["id"] == inline["id"])["sourceRoot"] = "accepted"
        with self.assertRaisesRegex(corpus.CorpusError, "inline provider cannot carry sourceRoot"):
            corpus.validate_manifest(bad_root, REPO / "test/fixtures/tla-frontend")
        bad_map = copy.deepcopy(manifest); next(row for row in bad_map["fixtures"] if row["id"] == inline["id"])["inlineSourceMap"] = [inline["inlineSourceMap"][0]]
        with self.assertRaisesRegex(corpus.CorpusError, "cover every source"):
            corpus.validate_manifest(bad_map, REPO / "test/fixtures/tla-frontend")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / "linked.tla").symlink_to(REPO / "test/fixtures/tla-frontend/accepted/AcceptModuleMinimal.tla")
            with self.assertRaisesRegex(corpus.CorpusError, "symlink"):
                corpus._source(root, "linked.tla", "test")
            (root / "invalid.tla").write_bytes(b"\xff")
            with self.assertRaisesRegex(corpus.CorpusError, "UTF-8"):
                corpus._source(root, "invalid.tla", "test")

    def test_unlisted_tla_file_invalidates_corpus_capture(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            clone = Path(temporary)
            shutil.copytree(REPO / "test/fixtures/tla-frontend", clone / "test/fixtures/tla-frontend")
            profile = clone / "Docs/model-interface-compiler"; profile.mkdir(parents=True)
            shutil.copy2(REPO / "Docs/model-interface-compiler/tla-language-profile.md", profile)
            (clone / "test/fixtures/tla-frontend/rejected/Missing.tla").write_text("---- MODULE Missing ----\n====\n")
            with self.assertRaisesRegex(corpus.CorpusError, "manifest files do not account"):
                corpus.load_corpus(clone)

    def test_closed_contract_round_trip_and_empty_fact(self) -> None:
        observation = {"schema": corpus.OBSERVATION_SCHEMA, "fixture": "acc-module-minimal", "engine": "sany", "provider": "borrowed-directory", "inputDigest": "0" * 64, "adapter": {"id": "test", "version": "1"}, "tool": {"id": "sany", "version": "pending", "fingerprint": "pending"}, "invocation": {"argv": [], "exitCode": 0}, "execution": "completed", "outcome": "accepted", "nativePhase": "semantic", "stage": None, "diagnostics": [], "facts": {"outcome": {"capability": "supported", "value": "accepted"}, "variables": {"capability": "supported", "value": []}}, "rawArtifacts": []}
        corpus.validate_contract("observation", json.loads(corpus.canonical_json(observation)))
        unsupported = copy.deepcopy(observation); unsupported["facts"]["variables"] = {"capability": "unsupported"}
        corpus.validate_contract("observation", unsupported)
        invalid = copy.deepcopy(unsupported); invalid["facts"]["variables"]["value"] = []
        with self.assertRaises(corpus.CorpusError): corpus.validate_contract("observation", invalid)
        invalid = copy.deepcopy(observation); invalid["facts"]["made-up"] = {"capability": "supported", "value": []}
        with self.assertRaises(corpus.CorpusError): corpus.validate_contract("observation", invalid)

    def test_refuses_malformed_structural_fact_and_observation_identity(self) -> None:
        observation = {"schema": corpus.OBSERVATION_SCHEMA, "fixture": "acc-module-minimal", "engine": "sany", "provider": "borrowed-directory", "inputDigest": "0" * 64, "adapter": {"id": "test", "version": "1"}, "tool": {"id": "sany", "version": "pending", "fingerprint": "pending"}, "invocation": {"argv": [], "exitCode": 0}, "execution": "completed", "outcome": "accepted", "nativePhase": "semantic", "stage": None, "diagnostics": [], "facts": {"resolution": {"capability": "supported", "value": {"dependencies": [1], "operators": [2]}}}, "rawArtifacts": []}
        with self.assertRaisesRegex(corpus.CorpusError, "dependency"):
            corpus.validate_contract("observation", observation)
        bad_digest = copy.deepcopy(observation); bad_digest["inputDigest"] = "not-a-digest"
        with self.assertRaisesRegex(corpus.CorpusError, "inputDigest"):
            corpus.validate_contract("observation", bad_digest)
        bad_artifact = copy.deepcopy(observation); bad_artifact["rawArtifacts"] = [{"path": "../escape", "sha256": "0" * 64}]
        with self.assertRaisesRegex(corpus.CorpusError, "raw artifact"):
            corpus.validate_contract("observation", bad_artifact)
        rejected = copy.deepcopy(observation); rejected["outcome"] = "rejected"; rejected["facts"]["resolution"] = {"capability": "supported", "value": {"dependencies": [], "operators": []}}
        with self.assertRaisesRegex(corpus.CorpusError, "rejected"):
            corpus.validate_contract("observation", rejected)

    def test_observation_requires_outcome_and_deep_fact_rows(self) -> None:
        base = {"schema": corpus.OBSERVATION_SCHEMA, "fixture": "acc-module-minimal", "engine": "sany", "provider": "borrowed-directory", "inputDigest": "0" * 64, "adapter": {"id": "test", "version": "1"}, "tool": {"id": "sany", "version": "pending", "fingerprint": "pending"}, "invocation": {"argv": [], "exitCode": 0}, "execution": "completed", "outcome": "accepted", "nativePhase": "semantic", "stage": None, "diagnostics": [], "facts": {"outcome": {"capability": "supported", "value": "accepted"}}, "rawArtifacts": []}
        missing = copy.deepcopy(base); missing["facts"] = {}
        with self.assertRaisesRegex(corpus.CorpusError, "outcome"):
            corpus.validate_contract("observation", missing)
        for key, value in {"variables": [1], "source_closure": [1], "resolution": {"dependencies": [1], "operators": [2]}, "levels": [1], "substitution": [1]}.items():
            with self.subTest(key=key):
                malformed = copy.deepcopy(base); malformed["facts"][key] = {"capability": "supported", "value": value}
                with self.assertRaises(corpus.CorpusError):
                    corpus.validate_contract("observation", malformed)
        wrong_provider = copy.deepcopy(base); wrong_provider["provider"] = "other"
        with self.assertRaisesRegex(corpus.CorpusError, "provider"):
            corpus.validate_contract("observation", wrong_provider)
        empty_tool = copy.deepcopy(base); empty_tool["tool"]["id"] = ""
        with self.assertRaisesRegex(corpus.CorpusError, "tool"):
            corpus.validate_contract("observation", empty_tool)

    def test_source_read_is_bounded(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "large.tla"
            path.write_bytes(b"x" * (corpus.MAX_SOURCE_BYTES + 1))
            with self.assertRaisesRegex(corpus.CorpusError, "byte bound"):
                corpus._source(Path(temporary), "large.tla", "test")

    def test_unreviewed_difference_cannot_be_promoted_or_wildcarded(self) -> None:
        registry = json.loads((REPO / "test/fixtures/tla-frontend/differential/differences.json").read_text())
        corpus.validate_contract("registry", registry)
        registry["candidates"] = [{"id": "test-candidate", "fixtureIds": ["rej-comment-depth"],
            "fields": ["outcome"], "expected": {}, "profile": "test", "sourceDigests": {},
            "rationale": "test only", "revisit": "on qualification", "reviewStatus": "unreviewed"}]
        bad = copy.deepcopy(registry); bad["candidates"][0]["reviewStatus"] = "accepted"
        with self.assertRaises(corpus.CorpusError): corpus.validate_contract("registry", bad)
        bad = copy.deepcopy(registry); bad["extra"] = True
        with self.assertRaises(corpus.CorpusError): corpus.validate_contract("registry", bad)


if __name__ == "__main__":
    unittest.main()
