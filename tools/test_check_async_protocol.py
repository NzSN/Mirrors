"""TLC terminal-diagnostic compatibility; no model checker is executed."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('async_protocol_gate', Path(__file__).with_name('check-async-protocol.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class TemporalDiagnosticTests(unittest.TestCase):
    def test_declared_temporal_counterexamples(self):
        for line in [
            'Error: Temporal properties were violated.',
            'Error: Temporal properties AsyncResourcesReleased and AsyncClosingEventuallyClean were violated.',
            'Error: Temporal properties AsyncClosingEventuallyClean and AsyncResourcesReleased were violated.',
            'Error: Temporal property AsyncResourcesReleased was violated.',
            'Error: Temporal property AsyncClosingEventuallyClean was violated.',
        ]:
            with self.subTest(line=line):
                self.assertTrue(gate.temporal_counterexample('TLC version\r\n' + line + '\r\nState 1:\r\n'))

    def test_unrelated_or_quoted_diagnostics_do_not_pass(self):
        for text in [
            'Error: Temporal property OtherProperty was violated.',
            'Error: Temporal properties OtherProperty and AsyncResourcesReleased were violated.',
            'Error: Parsing or semantic analysis failed.',
            'Model checking completed. No error has been found.',
            'state_text = "Error: Temporal properties were violated."',
            'Error: Temporal properties were violated. trailing junk',
        ]:
            with self.subTest(text=text):
                self.assertFalse(gate.temporal_counterexample(text))


if __name__ == '__main__':
    unittest.main()
