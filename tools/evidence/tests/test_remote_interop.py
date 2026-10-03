"""The remote qualification gate must distinguish verdicts from failures."""
import importlib.util
import os
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("remote_interop", ROOT / "tools/interop/run-remote.py")
remote = importlib.util.module_from_spec(spec)
spec.loader.exec_module(remote)


class RemoteVerdictTests(unittest.TestCase):
    def test_runtime_receipts_meet_the_real_attachment_capture_contract(self):
        import collect
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            output = base / "output"; output.mkdir(mode=0o700)
            private = base / "private"; private.mkdir(mode=0o700)
            entry = next(item for item in json.loads((ROOT / "tools/evidence/commands.json").read_text())["commands"]
                         if item["commandId"] == "mirrors.interop")
            plan_path = base / "plan.json"
            plan_path.write_text(json.dumps({"schemaVersion": "mirrors.evidence-attachment-plan/v1",
                "sourceRoot": str(output), "application": None,
                "adapter": {"kind": "none", "artifactId": None},
                "attachments": entry["attachmentOutputs"]}))
            plan = collect.prepare_attachment_plan(plan_path)
            try:
                previous = os.umask(0o022)
                try:
                    for item in entry["attachmentOutputs"]:
                        remote.write_output(output / item["relativePath"], b'{}\n')
                finally:
                    os.umask(previous)
                artifacts, _, captured, missing, failures = collect.capture_attachments(plan, private, "interop-fixture")
                self.assertEqual(missing, [])
                self.assertEqual(failures, [])
                self.assertEqual(len(artifacts), 2)
                self.assertEqual(set(captured), {"remote-interop-receipt", "ecma-runtime-pin"})
            finally:
                plan.close()

    def check(self, client, case, code, stdout="", stderr=""):
        return remote.classify_result(client, case, code, stdout, stderr)

    def test_declared_client_verdicts(self):
        for client in ["cpp", "haskell", "rust", "lean", "ecma"]:
            with self.subTest(client=client):
                self.assertTrue(self.check(client, "valid", 0, "VALID\n"))
        for client in ["cpp", "haskell", "rust"]:
            with self.subTest(client=client):
                self.assertTrue(self.check(client, "invalid", 1, "INVALID\nmodel counterexample\n"))
        self.assertTrue(self.check("ecma", "invalid", 1, 'INVALID {"invalid":"counterexample"}\n'))
        self.assertTrue(self.check("lean", "invalid", 1, stderr="spec invalid: counterexample\n"))

    def test_errors_substrings_and_wrong_statuses_do_not_count_as_verdicts(self):
        for client in ["cpp", "haskell", "rust", "lean", "ecma"]:
            for case, code, out, err in [
                ("valid", 0, "INVALID\n", ""),
                ("valid", 0, "validation says VALID\n", ""),
                ("valid", 1, "VALID\n", ""),
                ("valid", 0, "VALID\nINVALID\n", ""),
                ("valid", 0, "VALID\n", "spec invalid: failure\n"),
                ("valid", 0, "VALID\n", "connection refused\n"),
                ("invalid", 2, "", "invalid command-line option\n"),
                ("invalid", 1, "", "invalid command-line option\n"),
                ("invalid", 1, "VALID\n", ""),
                ("invalid", 0, "INVALID\n", ""),
                ("invalid", -15, "INVALID\n", ""),
                ("invalid", 1, "INVALID\nVALID\n", ""),
            ]:
                with self.subTest(client=client, case=case, code=code, out=out, err=err):
                    self.assertFalse(self.check(client, case, code, out, err))

    def test_ecma_payload_and_pin_failures_are_distinct(self):
        for value in ['INVALID {}\n', 'INVALID null\n', 'INVALID {"invalid":false}\n',
                      'INVALID {"invalid":"x","other":1}\n']:
            self.assertFalse(self.check("ecma", "invalid", 1, value))
        # The pinned Haskell CLI distinguishes infrastructure exit 2 from
        # counterexample exit 1 (app/Main.hs reportValidate).
        for client, code in [("cpp",2),("haskell",2),("rust",2),("lean",1),("ecma",1)]:
            with self.subTest(client=client):
                self.assertTrue(self.check(client,"wrong-pin",code,stderr="certificate fingerprint mismatch\n"))
                self.assertFalse(self.check(client,"wrong-pin",0,stderr="certificate fingerprint mismatch\n"))
                self.assertFalse(self.check(client,"wrong-pin",1 if code == 2 else 2,
                    stderr="certificate fingerprint mismatch\n"))
                self.assertFalse(self.check(client,"wrong-pin",code,stderr="connection refused\n"))

    def test_valid_warning_does_not_change_verdict(self):
        self.assertTrue(self.check("haskell","valid",0,"VALID\n","warning: client certificate /private/cert.pem expires in 6 day(s)\n"))
        self.assertTrue(self.check("lean","valid",0,"VALID\n","mirrorlean: WARNING: client certificate expires within 7 days (6 days)\n"))

    def test_runtime_admission_precedes_all_client_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "output"
            with patch.dict(os.environ, {"ECMA_RUNTIME_ROOT": temporary, "ECMA_NODE_BIN": "/prepared/node", "ECMA_REF": "a" * 40}), \
                 patch.object(sys, "argv", ["run-remote.py", str(output)]), \
                 patch.object(remote, "verify_runtime", side_effect=ValueError("stale runtime")), \
                 patch.object(remote.subprocess, "run") as run, \
                 patch.object(remote.subprocess, "check_output") as check:
                with self.assertRaisesRegex(ValueError, "stale runtime"):
                    remote.main()
                run.assert_not_called()
                check.assert_not_called()
                self.assertFalse(output.exists())
