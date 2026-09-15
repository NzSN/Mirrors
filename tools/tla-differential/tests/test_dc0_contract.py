"""Regression guards for the DC0 frozen compatibility contract."""
from __future__ import annotations

import hashlib
import importlib.util
import unittest
from pathlib import Path


SPEC = importlib.util.spec_from_file_location("dc0_contract", Path(__file__).with_name("dc0_contract.py"))
dc0 = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(dc0)
LIVE_SPEC = importlib.util.spec_from_file_location("run_dc0_live_matrix", Path(__file__).with_name("run_dc0_live_matrix.py"))
live = importlib.util.module_from_spec(LIVE_SPEC)
assert LIVE_SPEC.loader is not None
LIVE_SPEC.loader.exec_module(live)


class Dc0Contract(unittest.TestCase):
    def test_all_currently_staged_spellings_are_listed_once(self):
        lexer = (dc0.REPO / "Core/Tla/Lexer.lean").read_text(encoding="utf-8")
        self.assertEqual(
            set(dc0.STAGED_UNICODE_SPELLINGS) | set(dc0.ADMITTED_UNICODE_ALIASES),
            set(dc0.DC0_UNICODE_SPELLINGS),
        )
        self.assertEqual(
            len(dc0.STAGED_UNICODE_SPELLINGS) + len(dc0.ADMITTED_UNICODE_ALIASES),
            len(dc0.DC0_UNICODE_SPELLINGS),
        )
        for spelling in dc0.STAGED_UNICODE_SPELLINGS:
            self.assertEqual(lexer.count(f'"{spelling}"'), 1, spelling)
        for spelling in dc0.ADMITTED_UNICODE_ALIASES:
            self.assertEqual(lexer.count(f'"{spelling}"'), 1, spelling)
        self.assertNotIn('"∧", "∨"', lexer)
        self.assertEqual(len(dc0.STAGED_UNICODE_SPELLINGS), len(set(dc0.STAGED_UNICODE_SPELLINGS)))

    def test_minimal_exercised_unicode_sources_are_stable_and_isolated(self):
        self.assertEqual(set(dc0.EXERCISED_UNICODE_SOURCES), {"∧", "∈", "≤"})
        for spelling, source in dc0.EXERCISED_UNICODE_SOURCES.items():
            self.assertEqual(source.count(spelling), 1)
            self.assertEqual(source.count("---- MODULE"), 1)
            self.assertTrue(source.endswith("====\n"))
            self.assertEqual(dc0.source_sha256(source), hashlib.sha256(source.encode()).hexdigest())

    def test_enabled_contract_has_three_positive_boundaries_and_one_negative_control(self):
        self.assertEqual(dc0.ENABLED_ACTION_LEVEL, "state")
        self.assertEqual(set(dc0.ENABLED_SOURCES), {"constant", "state", "action", "temporal"})
        self.assertEqual(len(dc0.calibration_input_hashes()), 7)

    def test_live_matrix_covers_the_closed_unicode_and_boundary_sets(self):
        self.assertEqual(tuple(live.UNICODE_SOURCES), dc0.DC0_UNICODE_SPELLINGS)
        self.assertEqual(set(live.ENABLED_SOURCES), set(dc0.ENABLED_SOURCES))
        self.assertEqual(set(live.INSTANCE_FIXTURES), {"direct", "explicit-substitution", "implicit-substitution", "state-substitution"})
        for glyph, body in live.UNICODE_SOURCES.items():
            self.assertEqual(body.count(glyph), 1, glyph)
            self.assertTrue(live.module("Dc0", body).endswith("====\n"))

    def test_checkpoint_j_and_k_reproduce_exactly_eleven_findings(self):
        for checkpoint in dc0.CHECKPOINTS:
            report = dc0.load_report(checkpoint)
            semantic = (dc0.EVIDENCE / checkpoint / "semantic.json").read_bytes()
            self.assertEqual(hashlib.sha256(semantic).hexdigest(), dc0.CHECKPOINT_SEMANTIC_SHA256)
            self.assertEqual(dc0.finding_keys(report), dc0.expected_findings())

    def test_preserved_sany_facts_define_dc1_and_dc2_handoffs(self):
        for checkpoint in dc0.CHECKPOINTS:
            report = dc0.load_report(checkpoint)
            action = dc0.sany_observation(report, "acc-actions")["facts"]["levels"]["value"]
            self.assertIn({"name": "Enabled", "declaredIn": "AcceptActions", "level": "state"}, action)
            for fixture, (declared_in, level) in dc0.NAMED_INSTANCE_EXPECTED.items():
                facts = dc0.sany_observation(report, fixture)["facts"]
                self.assertIn({"name": "I!ChildOp", "declaredIn": declared_in, "arity": 0, "local": False}, facts["resolution"]["value"]["operators"])
                self.assertIn({"name": "I!ChildOp", "declaredIn": declared_in, "level": level}, facts["levels"]["value"])


if __name__ == "__main__":
    unittest.main()
