import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).parents[1]))
SPEC = importlib.util.spec_from_file_location(
    "junction_summaries", Path(__file__).parents[1] / "junction_summaries.py")
summaries = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(summaries)


class JunctionSummaryWrapper(unittest.TestCase):
    def test_write_check_and_repeatable_bytes(self):
        self.assertEqual(summaries.main([]), 0, "frozen semantic summaries must match real frontend output")
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "missing" / "summaries"
            self.assertEqual(summaries.main(["--write", "--output-dir", str(output)]), 0)
            first = {fixture: (output / f"{fixture}.json").read_bytes()
                     for fixture in summaries.FIXTURES}
            self.assertEqual(summaries.main(["--check", "--output-dir", str(output)]), 0)
            self.assertEqual(summaries.main(["--write", "--output-dir", str(output)]), 0)
            self.assertEqual({fixture: (output / f"{fixture}.json").read_bytes()
                              for fixture in summaries.FIXTURES}, first)

            corrupted = output / "acc-precedence.json"
            value = json.loads(corrupted.read_text())
            value["profile"] = "corrupted"
            corrupted.write_text(json.dumps(value) + "\n")
            self.assertEqual(summaries.main(["--check", "--output-dir", str(output)]), 1)


if __name__ == "__main__":
    unittest.main()
