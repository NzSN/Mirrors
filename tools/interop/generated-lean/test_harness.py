#!/usr/bin/env python3
"""Acceptance classifier regressions: unrelated failures never count as negatives."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

PATH = Path(__file__).resolve().parents[1] / "run-generated-lean.py"
spec = importlib.util.spec_from_file_location("generated_lean_harness", PATH)
assert spec and spec.loader
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)
DIGEST, PIN = "a" * 64, "b" * 64


def row(case="correct", transport="stdio"):
    value = {"schema": harness.ROW_SCHEMA, "transport": transport, "case": case,
             "semanticDigest": DIGEST, "validatedServerPin": PIN if transport == "tls" else None,
             "factoryCount": 1, "disposedPorts": 1,
             "events": ["Initialize", "Observe", "Tick", "Observe", "Tick", "Observe"],
             "observations": ["0", "2", "5"], "strides": ["2", "3"],
             "reports": [{"count": {"#bigint": n}} for n in ("0", "2", "5")],
             "coverage": {"Initialize": 1, "Tick": 2}, "outcome": {"kind": "completed"}}
    if case == "faulty-observer":
        value.update(events=["Initialize", "Observe"], observations=["1"], strides=[],
                     reports=[{"count": {"#bigint": "1"}}], coverage={"Initialize": 1, "Tick": 0},
                     outcome={"kind": "step_mismatch", "action": "init", "expectedCount": "0", "actualCount": "1"})
    if case in ("wrong-digest", "unauthorized", "wrong-pin"):
        value.update(factoryCount=0, disposedPorts=0, events=[], observations=[], strides=[], reports=[], coverage={})
        code = "interface_digest_mismatch" if case == "wrong-digest" else "interface_unavailable"
        value["outcome"] = {"kind": "registration_error", "code": code}
        if case == "wrong-pin":
            value.update(validatedServerPin=None, outcome={"kind": "tls_pin_mismatch"})
    return value


class AcceptanceTests(unittest.TestCase):
    def accepted(self, value, code):
        return harness.row_passes(value, code, value["transport"], value["case"], DIGEST, pin=PIN)

    def test_exact_positive_and_fault(self):
        self.assertTrue(self.accepted(row(), 0))
        self.assertTrue(self.accepted(row("faulty-observer"), 1))

    def test_exact_zero_factory_negatives(self):
        for case, transport in [("wrong-digest", "stdio"), ("unauthorized", "tcp"),
                                ("wrong-digest", "tls"), ("unauthorized", "tls"), ("wrong-pin", "tls")]:
            with self.subTest(case=case, transport=transport):
                self.assertTrue(self.accepted(row(case, transport), 2))

    def test_fault_is_not_an_arbitrary_error(self):
        value = row("faulty-observer")
        for outcome in ({"kind": "io_error"}, {"kind": "tls_error"}, {"kind": "completed"},
                        {"kind": "step_mismatch", "action": "tick", "expectedCount": "0", "actualCount": "1"}):
            value["outcome"] = outcome
            self.assertFalse(self.accepted(value, 1))

    def test_exact_reports_and_coverage(self):
        for field, replacement in [("reports", [{"count": {"#bigint": "999"}}]),
                                   ("coverage", {"Initialize": True, "Tick": 2}),
                                   ("coverage", {"Initialize": 1}),
                                   ("disposedPorts", 0), ("factoryCount", True)]:
            value = row()
            value[field] = replacement
            self.assertFalse(self.accepted(value, 0), field)

    def test_extra_fields_and_wrong_identity_rejected(self):
        value = row()
        value["extra"] = True
        self.assertFalse(self.accepted(value, 0))
        for field in ("schema", "semanticDigest"):
            value = row()
            value[field] = "wrong"
            self.assertFalse(self.accepted(value, 0))

    def test_unexpected_row_is_not_retained(self):
        value = row()
        value["privateContextValue"] = "SENSITIVE"
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            completed = subprocess.CompletedProcess([], 0, json.dumps(value) + "\n", "")
            with mock.patch.object(harness.subprocess, "run", return_value=completed):
                with self.assertRaises(RuntimeError):
                    harness.execute_row(output / "build", output, {"semanticDigest": DIGEST},
                                        "stdio", "correct", {}, False)
            self.assertFalse((output / "stdio-correct.json").exists())

    def test_hidden_source_tree_cannot_contain_build_or_output(self):
        with mock.patch.object(harness.shutil, "which", return_value="bwrap"):
            with self.assertRaisesRegex(ValueError, "outside hidden source trees"):
                harness.runtime_command(harness.ROOT / "build", Path("/tmp/result"), "stdio", "correct", True)
            with self.assertRaisesRegex(ValueError, "outside hidden source trees"):
                harness.runtime_command(Path("/tmp/build"), harness.ROOT / "result", "stdio", "correct", True)

    def test_nonzero_side_effects_reject_negative(self):
        for field, replacement in [("factoryCount", 1), ("disposedPorts", 1), ("reports", [{}]),
                                   ("coverage", {"Initialize": 1}), ("events", ["Initialize"])]:
            value = row("wrong-digest")
            value[field] = replacement
            self.assertFalse(self.accepted(value, 2), field)

    def test_live_multi_artifact_trace_and_pin(self):
        value = row(transport="tls")
        value.update(events=["Initialize", "Observe"] + ["Tick", "Observe"] * 4,
                     observations=["0", "3", "6", "9", "12"], strides=["3"] * 4,
                     reports=[{"count": {"#bigint": n}} for n in ("0", "3", "6", "9", "12")],
                     coverage={"Initialize": 1, "Tick": 4})
        for field in ("events", "observations", "strides", "reports"):
            value[field] *= 2
        value["coverage"] = {"Initialize": 2, "Tick": 8}
        self.assertTrue(self.accepted(value, 0))
        wrong = copy.deepcopy(value)
        wrong["validatedServerPin"] = "c" * 64
        self.assertFalse(self.accepted(wrong, 0))
        wrong = copy.deepcopy(value)
        wrong["observations"][5] = "12"
        self.assertFalse(self.accepted(wrong, 0))

    def test_only_exact_known_tls_warning_is_permitted(self):
        self.assertTrue(harness.stderr_passes("", "stdio"))
        for days in ("0 days", "1 day", "2 days", "6 days"):
            warning = f"mirrorlean: WARNING: client certificate expires within 7 days ({days})\n"
            self.assertTrue(harness.stderr_passes(warning, "tls"))
            self.assertFalse(harness.stderr_passes(warning, "stdio"))
        known = "mirrorlean: WARNING: client certificate expires within 7 days (0 days)\n"
        for stderr in ("TLS failure\n", known + "TLS failure\n", known + known,
                       " " + known, known.replace("0 days", "999 days"),
                       known.replace("0 days", "1 days"), "mirrorlean: WARNING: client certificate is expired\n"):
            self.assertFalse(harness.stderr_passes(stderr, "tls"), stderr)


if __name__ == "__main__":
    unittest.main()
