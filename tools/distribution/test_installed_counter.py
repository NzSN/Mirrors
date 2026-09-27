import subprocess
import unittest
from pathlib import Path


class InstalledCounterBindingTests(unittest.TestCase):
    def test_confirmed_cleanup_uses_succeeded_status_and_keeps_the_faulty_coordinate(self) -> None:
        from qualification import counter_variant_accepted
        correct = {"outcome": "passed", "cleanup": {
            "status": "succeeded", "quiescence": "confirmed", "bindingStatus": "succeeded"}}
        self.assertTrue(counter_variant_accepted(correct, "correct"))
        unconfirmed = {"outcome": "passed", "cleanup": {
            "status": "confirmed", "quiescence": "confirmed", "bindingStatus": "succeeded"}}
        self.assertFalse(counter_variant_accepted(unconfirmed, "correct"))
        faulty = {"outcome": "mismatch", "cleanup": correct["cleanup"], "failure": {
            "code": "model_mismatch", "traceIndex": 0, "stateIndex": 1, "action": "Tick"}}
        self.assertTrue(counter_variant_accepted(faulty, "faulty"))
        missing_action = {**faulty, "failure": {**faulty["failure"], "action": None}}
        self.assertFalse(counter_variant_accepted(missing_action, "faulty"))

    def test_generated_digest_binding_fails_closed_without_the_fix(self) -> None:
        script = Path(__file__).with_name("installed-counter.test.mjs")
        result = subprocess.run(["node", "--test", str(script)], check=False, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
