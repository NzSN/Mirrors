"""A correct generated state alone cannot satisfy the SDK wire-frame gate."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

from check import canonical_report_frame, verify_recording

FIXTURES = Path(__file__).resolve().parents[2] / "test/fixtures/model-interface/language"


class ReportStateFrameTests(unittest.TestCase):
    def setUp(self):
        cases = [json.loads(line) for line in (FIXTURES / "counter-binding-events.jsonl").read_text().splitlines()]
        self.expected = next(case["expected"] for case in cases if case["id"] == "Counter")

    def test_reviewed_count_frames_are_exact_canonical_payloads(self):
        verify_recording(copy.deepcopy(self.expected), self.expected, "control")
        self.assertEqual(self.expected["wireFrames"][0], '{"proto_step":"report_state","state":{"count":{"#bigint":"0"}}}')

    def test_correct_events_without_actual_encoder_frames_fail(self):
        actual = copy.deepcopy(self.expected)
        del actual["wireFrames"]
        with self.assertRaisesRegex(AssertionError, "missing SDK"):
            verify_recording(actual, self.expected, "missing-frame")

    def test_correct_events_with_wrong_sdk_frame_fail(self):
        actual = copy.deepcopy(self.expected)
        actual["wireFrames"][0] = '{"proto_step":"report_state","state":{"count":{"#bigint":"1"}}}'
        with self.assertRaisesRegex(AssertionError, "wrong SDK"):
            verify_recording(actual, self.expected, "wrong-frame")

    def test_internal_value_representation_is_not_wire_encoding(self):
        actual = copy.deepcopy(self.expected)
        actual["wireFrames"][0] = '{"proto_step":"report_state","state":{"count":{"tag":"int","val":{"#bigint":"0"}}}}'
        with self.assertRaises(AssertionError):
            verify_recording(actual, self.expected, "internal-state")

    def test_wrong_or_extra_envelope_fields_rejected(self):
        for frame in ('{"proto_step":"report_state","state":{},"extra":true}',
                      '{"proto_step":"report_state","state":[]}',
                      '{"proto_step":"next_step","state":{}}', '{}'):
            with self.subTest(frame=frame), self.assertRaises(AssertionError):
                canonical_report_frame(frame)

    def test_duplicate_fields_rejected_even_when_the_last_value_matches(self):
        for frame in ('{"proto_step":"next_step","proto_step":"report_state","state":{}}',
                      '{"proto_step":"report_state","state":{"count":false,"count":{"#bigint":"0"}}}',
                      '{"proto_step":"report_state","state":{"count":{"#bigint":"1","#bigint":"0"}}}'):
            with self.subTest(frame=frame), self.assertRaisesRegex(ValueError, "duplicate"):
                canonical_report_frame(frame)

    def test_payload_must_not_include_line_terminators_or_non_json_numbers(self):
        with self.assertRaises(AssertionError):
            canonical_report_frame(self.expected["wireFrames"][0]+"\n")
        with self.assertRaises(ValueError):
            canonical_report_frame('{"proto_step":"report_state","state":{"count":NaN}}')

    def test_noncanonical_encoder_bytes_are_not_silently_rewritten(self):
        actual = copy.deepcopy(self.expected)
        actual["wireFrames"][0] = '{ "proto_step": "report_state", "state": {"count":{"#bigint":"0"}} }'
        with self.assertRaisesRegex(AssertionError, "noncanonical SDK"):
            verify_recording(actual, self.expected, "spaces")

    def test_imported_verifiers_reject_invalid_values_under_python_optimization(self):
        program = '''
from check import canonical_report_frame, verify_recording, verify_roundtrip
cases = [
    lambda: verify_roundtrip({"accepted":False,"effects":0,"error":"input_shape_mismatch","poisoned":True}, {"#bigint":"0"}, True, "optimized-roundtrip"),
    lambda: canonical_report_frame('{"proto_step":"next_step","state":{}}'),
    lambda: verify_recording({"wireFrames":[]}, {"wireFrames":["expected"]}, "optimized-frame"),
]
for case in cases:
    try: case()
    except (AssertionError, ValueError): pass
    else: raise SystemExit("optimized verifier accepted invalid input")
print("three imported verifier negatives rejected")
'''
        for flags, optimize in ((["-O"], None), ([], "1")):
            env = dict(os.environ)
            env.pop("PYTHONOPTIMIZE", None)
            if optimize is not None: env["PYTHONOPTIMIZE"] = optimize
            result = subprocess.run([sys.executable, *flags, "-c", program],
                                    cwd=Path(__file__).resolve().parent, env=env,
                                    capture_output=True, text=True, timeout=30)
            with self.subTest(flags=flags, optimize=optimize):
                self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
                self.assertEqual(result.stdout.strip(), "three imported verifier negatives rejected")


if __name__ == "__main__": unittest.main()
