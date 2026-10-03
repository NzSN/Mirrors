#!/usr/bin/env python3
"""The source-hiding boundary must execute even under Python optimization."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

path = Path(__file__).with_name("check.py")
spec = importlib.util.spec_from_file_location("projected_corpus_check", path)
if spec is None or spec.loader is None:
    raise RuntimeError("cannot load fixture harness")
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


class ProbeTests(unittest.TestCase):
    def probe(self, directories):
        return subprocess.run([sys.executable, "-O", "-c", harness.SOURCE_HIDING_PROBE,
                               *map(str, directories), sys.executable, "-c", "print('RUNNER_EXECUTED')"],
                              env={**os.environ, "PYTHONOPTIMIZE": "1"}, capture_output=True, text=True)

    def test_empty_mounts_execute_runner_under_optimization(self):
        with tempfile.TemporaryDirectory() as temporary:
            directories = [Path(temporary) / str(index) for index in range(3)]
            for directory in directories:
                directory.mkdir()
            result = self.probe(directories)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "RUNNER_EXECUTED\n")

    def test_nonempty_directory_stops_before_runner_under_optimization(self):
        with tempfile.TemporaryDirectory() as temporary:
            directories = [Path(temporary) / str(index) for index in range(3)]
            for directory in directories:
                directory.mkdir()
            (directories[1] / "source-visible").write_text("must fail")
            result = self.probe(directories)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertIn("not empty", result.stderr)

    def test_missing_and_non_directory_paths_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "file").write_text("not a directory")
            (root / "empty-a").mkdir()
            (root / "empty-b").mkdir()
            for bad in (root / "missing", root / "file"):
                result = self.probe([bad, root / "empty-a", root / "empty-b"])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn("missing or unreadable", result.stderr)


if __name__ == "__main__":
    unittest.main()
