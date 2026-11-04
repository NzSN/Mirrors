import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import ExitStack, redirect_stderr
from io import StringIO
from pathlib import Path
from unittest.mock import patch

import build
from distribution_lib import sha256_file


class BatteriesInputTests(unittest.TestCase):
    """Exercise carrier admission before any build staging or external command."""

    def test_vendored_carrier_matches_both_dependency_locks_and_source_revision(self):
        repository = Path(__file__).resolve().parents[2]
        carrier = repository / "third_party/batteries/batteries-v4.33.0.bundle"
        size, digest = sha256_file(carrier)
        dependencies = []
        for name in ("reference-node", "reference-node-wsl2-26.04"):
            lock = json.loads((repository / "distribution" / name / "dependency-lock.json").read_text())
            dependency = next(v for v in lock["dependencies"] if v["artifactId"] == "lean-batteries-source")
            self.assertEqual((size, digest), (dependency["bytes"], dependency["sha256"]))
            dependencies.append(dependency)
        self.assertEqual(dependencies[0], dependencies[1])
        heads = subprocess.run(["git", "bundle", "list-heads", str(carrier)],
                               capture_output=True, text=True, check=True).stdout.splitlines()
        self.assertEqual(heads, [dependencies[0]["version"] + " HEAD"])

    def invoke(self, repository: Path, output: Path, *, explicit: Path | None = None):
        selected = b"selected-carrier"
        contract = {
            "profiles": {"checked-replay-local": {"status": "build-required"}},
            "dependencies": {"lean-batteries-source": {
                "bytes": len(selected), "sha256": hashlib.sha256(selected).hexdigest()}},
        }
        argv = ["build.py", "--profile", "checked-replay-local", "--out", str(output)]
        for flag in ("snapshot-root", "lake-bin", "node-archive", "git-bin", "ldd-bin",
                     "typescript-node-modules", "evidence-wheels", "framework-catalog-bin"):
            argv.extend(["--" + flag, str(repository / ("absent-" + flag))])
        argv.extend(["--framework-catalog-sha256", "0" * 64])
        if explicit is not None:
            argv.extend(["--batteries-bundle", str(explicit)])
        error = StringIO()
        with ExitStack() as stack:
            stack.enter_context(patch.object(build, "MIRRORS", repository))
            stack.enter_context(patch.object(sys, "argv", argv))
            stack.enter_context(patch.object(build, "validate_locks", return_value=contract))
            stack.enter_context(patch.object(build, "verify_source_snapshots"))
            stack.enter_context(patch.object(build, "verify_running_builder"))
            stack.enter_context(patch.object(build, "profile_resolution", return_value=(set(), {}, None)))
            command = stack.enter_context(patch.object(build, "run"))
            stack.enter_context(redirect_stderr(error))
            result = build.main()
            command.assert_not_called()
        return result, error.getvalue()

    def test_missing_canonical_carrier_refuses_ambient_source_and_legacy_cache(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / ".lake/packages/batteries").mkdir(parents=True)
            old = root / ".golden-build/batteries-v4.33.0.bundle"
            old.parent.mkdir()
            old.write_bytes(b"selected-carrier")
            output = root / "cache"
            code, error = self.invoke(root, output)
            self.assertEqual(code, 1)
            self.assertIn("third_party/batteries/batteries-v4.33.0.bundle", error)
            self.assertFalse(output.exists())

    def test_wrong_same_size_canonical_carrier_is_rejected_before_staging(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            carrier = root / "third_party/batteries/batteries-v4.33.0.bundle"
            carrier.parent.mkdir(parents=True)
            carrier.write_bytes(b"selected-carriex")
            output = root / "cache"
            code, error = self.invoke(root, output)
            self.assertEqual(code, 1)
            self.assertIn("Batteries archive differs from dependency lock", error)
            self.assertFalse(output.exists())

    def test_default_resolves_from_builder_checkout_in_another_working_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = root / "checkout"
            carrier = repository / "third_party/batteries/batteries-v4.33.0.bundle"
            carrier.parent.mkdir(parents=True)
            carrier.write_bytes(b"selected-carrier")
            output = root / "cache"
            original = Path.cwd()
            try:
                os.chdir(root)
                code, error = self.invoke(repository, output)
            finally:
                os.chdir(original)
            self.assertEqual(code, 1)
            # Correct carrier reaches the next independent source gate; no compilation.
            self.assertIn("missing immutable source snapshot: mirrors", error)
            self.assertTrue((output / "build-state.json").is_file())

    def test_explicit_carrier_overrides_default_and_still_requires_locked_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            canonical = root / "third_party/batteries/batteries-v4.33.0.bundle"
            canonical.parent.mkdir(parents=True)
            canonical.write_bytes(b"wrong")
            override = root / "explicit.bundle"
            override.write_bytes(b"selected-carrier")
            code, error = self.invoke(root, root / "cache", explicit=override)
            self.assertEqual(code, 1)
            self.assertIn("missing immutable source snapshot: mirrors", error)
            override.write_bytes(b"wrong")
            output = root / "rejected"
            code, error = self.invoke(root, output, explicit=override)
            self.assertEqual(code, 1)
            self.assertIn("Batteries archive differs from dependency lock", error)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
