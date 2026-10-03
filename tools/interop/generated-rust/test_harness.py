"""Exact result-classification controls and real-client negotiation mocks."""
from copy import deepcopy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "run-generated-remote.py"
SPEC = importlib.util.spec_from_file_location("generated_remote", SCRIPT)
harness = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(harness)
DIGEST = "a" * 64
PIN = "b" * 64


def zero_row(case="unauthorized", transport="tls"):
    return {
        "schema": harness.ROW_SCHEMA, "transport": transport, "case": case,
        "semanticDigest": DIGEST, "peerFingerprint": PIN,
        "factoryCount": 0, "disposedPorts": 0, "events": [],
        "observations": [], "strides": [],
        "outcome": {"kind": "registration_error", "code": "interface_unavailable"},
    }


class Classification(unittest.TestCase):
    def test_authorization_requires_completed_pinned_tls_and_exact_denial(self):
        good = zero_row()
        self.assertTrue(harness.row_passes(good, 2, "tls", "unauthorized", DIGEST, pin=PIN))
        for field, value in [
            ("peerFingerprint", None), ("factoryCount", 1), ("factoryCount", False),
            ("disposedPorts", 1), ("events", ["Initialize"]),
            ("outcome", {"kind": "tls_error"}),
            ("outcome", {"kind": "registration_error", "code": "interface_trace_preflight_failed"}),
        ]:
            with self.subTest(field=field, value=value):
                row = deepcopy(good)
                row[field] = value
                self.assertFalse(harness.row_passes(row, 2, "tls", "unauthorized", DIGEST, pin=PIN))
        self.assertFalse(harness.row_passes(good, 0, "tls", "unauthorized", DIGEST, pin=PIN))
        self.assertFalse(harness.row_passes(good, -9, "tls", "unauthorized", DIGEST, pin=PIN))

    def test_wrong_pin_does_not_accept_generic_connection_failure(self):
        row = zero_row("wrong-pin")
        row["peerFingerprint"] = None
        row["outcome"] = {"kind": "tls_pin_mismatch"}
        self.assertTrue(harness.row_passes(row, 2, "tls", "wrong-pin", DIGEST, pin=PIN))
        for kind in ("tls_error", "io_error", "transport_closed", "unexpected_error"):
            row["outcome"] = {"kind": kind}
            self.assertFalse(harness.row_passes(row, 2, "tls", "wrong-pin", DIGEST, pin=PIN))

    def test_wrong_observer_requires_the_actual_counter_mismatch(self):
        row = zero_row("faulty-observer", "stdio")
        row.update(factoryCount=1, disposedPorts=1, events=["Initialize", "Observe"], observations=["1"],
                   outcome={"kind": "step_mismatch", "action": "init", "expectedCount": "0", "actualCount": "1"})
        self.assertTrue(harness.row_passes(row, 1, "stdio", "faulty-observer", DIGEST))
        row["outcome"]["actualCount"] = "0"
        self.assertFalse(harness.row_passes(row, 1, "stdio", "faulty-observer", DIGEST))

    def test_fresh_replay_requires_legal_strides_and_counterexample_termination(self):
        row = zero_row("correct")
        row.update(factoryCount=1, disposedPorts=1,
                   events=["Initialize", "Observe"] + ["Tick", "Observe"] * 4,
                   observations=["0", "3", "6", "9", "12"], strides=["3"] * 4,
                   outcome={"kind": "completed"})
        self.assertTrue(harness.row_passes(row, 0, "tls", "correct", DIGEST, pin=PIN))
        for observations in (["0", "3", "6", "9"], ["0", "3", "7", "9", "12"], ["0", "3", "6", "9", "11"]):
            altered = deepcopy(row)
            altered["observations"] = observations
            self.assertFalse(harness.row_passes(altered, 0, "tls", "correct", DIGEST, pin=PIN))

    def test_duplicate_json_members_are_rejected(self):
        with self.assertRaises(ValueError):
            json.loads('{"factoryCount":1,"factoryCount":0}', object_pairs_hook=harness.unique_object)

    def test_unexpected_row_field_is_rejected_before_retention(self):
        row = zero_row()
        row["privateContextValue"] = "SENSITIVE"
        self.assertFalse(harness.row_passes(row, 2, "tls", "unauthorized", DIGEST, pin=PIN))
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            completed = subprocess.CompletedProcess([], 2, json.dumps(row) + "\n", "")
            with mock.patch.object(harness.subprocess, "run", return_value=completed):
                with self.assertRaises(RuntimeError):
                    harness.execute_row(output / "build", output, {"semanticDigest": DIGEST},
                                        "tls", "unauthorized", {}, pin=PIN)
            self.assertFalse((output / "tls-unauthorized.json").exists())

    def test_hidden_source_tree_cannot_contain_build_or_output(self):
        with mock.patch.object(harness.shutil, "which", return_value="bwrap"):
            with self.assertRaisesRegex(ValueError, "outside Mirrors"):
                harness.runtime_command(harness.ROOT / "build", Path("/tmp/result"), "stdio", "correct", True)
            with self.assertRaisesRegex(ValueError, "outside Mirrors"):
                harness.runtime_command(Path("/tmp/build"), harness.ROOT / "result", "stdio", "correct", True)

    def test_multiple_artifacts_each_require_a_complete_bounded_trace(self):
        events = ["Initialize", "Observe"] + ["Tick", "Observe"] * 4
        observations = ["0", "3", "6", "9", "12"]
        self.assertTrue(harness.fresh_counter_trace_sequence(events * 2, observations * 2, ["3"] * 8))
        incomplete = ["Initialize", "Observe", "Tick", "Observe"]
        self.assertFalse(harness.fresh_counter_trace_sequence(incomplete + events, ["0", "3"] + observations, ["3"] * 5))
        self.assertFalse(harness.fresh_counter_trace_sequence(events * 2, observations * 2, ["3"] * 7))
        self.assertFalse(harness.fresh_counter_trace_sequence(events * 65, observations * 65, ["3"] * 260))
        self.assertFalse(harness.fresh_counter_trace_sequence(
            ["Initialize", "Observe"] + ["Tick", "Observe"] * 7,
            list(map(str, range(0, 15, 2))), ["2"] * 7))


@unittest.skipUnless(os.environ.get("GENERATED_RUST_TEST_BUILD"), "explicit prepared Rust build required")
class NegotiationMocks(unittest.TestCase):
    def test_untrusted_admission_replies_never_construct_the_adapter(self):
        root = Path(os.environ["GENERATED_RUST_TEST_BUILD"]).resolve()
        harness.verify_build(root)
        replies = [
            json.dumps({"proto_step": "spec_validated", "result": "valid", "modelInterface": {
                "schema": "mirrors.model-interface-negotiation/v1", "status": "matched",
                "descriptorSchema": "mirrors.model-interface-descriptor/v1", "semanticDigest": "sha256:" + "0" * 64}}),
            '{"proto_step":"spec_validated","result":"valid","result":"valid"}',
            '{"proto_step":"spec_validated","result":"valid"}',
        ]
        for reply in replies:
            with self.subTest(reply=reply), tempfile.TemporaryDirectory() as temporary:
                server = Path(temporary) / "mock-mirror"
                server.write_text("#!/usr/bin/env python3\nimport sys\nsys.stdin.readline()\nprint(" + repr(reply) + ", flush=True)\n")
                server.chmod(0o700)
                env = harness.runner_environment(root)
                env["GENERATED_RUST_MIRROR_BIN"] = str(server)
                result = subprocess.run([str(root / "runner"), "stdio", "correct"],
                                        env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stderr, "")
                row = json.loads(result.stdout)
                self.assertEqual(row["factoryCount"], 0)
                self.assertEqual(row["disposedPorts"], 0)
                self.assertEqual(row["events"], [])
                self.assertEqual(row["observations"], [])
                self.assertNotEqual(row["outcome"]["kind"], "completed")


if __name__ == "__main__":
    unittest.main()
