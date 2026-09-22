import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import qualification


class QualificationAuditTests(unittest.TestCase):
    def test_trace_audit_accepts_only_one_replacement_mount_probe_per_hidden_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            prefix = root / "trace"
            hidden = ["/source/one", "/source/two"]
            (root / "trace.1").write_text(
                'openat(AT_FDCWD, "/source/one", O_RDONLY|O_DIRECTORY) = 4\n'
                'openat(AT_FDCWD, "/source/two", O_RDONLY|O_DIRECTORY) = 5\n'
                'execve("/runtime/node", ["node"], 0x0) = 0\n')
            result = qualification.trace_audit(prefix, hidden)
            self.assertEqual(result["hiddenRootOpenCalls"], 2)
            self.assertEqual(result["hiddenRootAccess"],
                "empty replacement mount verified by audit launcher")
            (root / "trace.2").write_text(
                'openat(AT_FDCWD, "/source/one/file", O_RDONLY) = 6\n')
            with self.assertRaisesRegex(ValueError, "replacement probe count"):
                qualification.trace_audit(prefix, hidden)

    def test_admission_failure_retains_bounded_audit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            prefix = root / "prefix"
            prefix.mkdir()
            tracer = root / "strace"
            tracer.write_bytes(b"trusted test tracer")
            audit = root / "audit.json"
            argv = ["qualification.py", "--prefix", str(prefix),
                "--framework-catalog-bin", str(root / "catalog"),
                "--framework-catalog-sha256", "0" * 64,
                "--bwrap", str(root / "bwrap"), "--strace", str(tracer),
                "--strace-sha256", hashlib.sha256(tracer.read_bytes()).hexdigest(),
                "--audit-out", str(audit), "--hide-root", str(root / "hidden")]
            with patch.object(sys, "argv", argv):
                self.assertEqual(qualification.main(), 1)
            retained = json.loads(audit.read_text())
            self.assertEqual(retained["status"], "failed")
            self.assertEqual(retained["failure"]["stage"], "admission")
            self.assertIn("no active version", retained["error"])
            self.assertLess(audit.stat().st_size, 8 * 1024 * 1024)


if __name__ == "__main__":
    unittest.main()
