from __future__ import annotations

import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


TOOLS_DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIRECTORY))

from process import (  # noqa: E402
    ExecutionStatus,
    ProcessLimits,
    ProcessRequest,
    deterministic_environment,
    run_process,
)


class ProcessTests(unittest.TestCase):
    def request(self, directory: Path, program: str, *, artifact_dir: Path | None = None) -> ProcessRequest:
        return ProcessRequest([sys.executable, "-c", program], directory, artifact_dir=artifact_dir)

    def test_completed_keeps_nonzero_exit_for_adapter_classification(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            result = run_process(self.request(Path(temporary), "import sys; print('rejected'); sys.exit(7)"))
        self.assertEqual(result.status, ExecutionStatus.COMPLETED)
        self.assertEqual(result.returncode, 7)
        self.assertEqual(result.stdout, b"rejected\n")

    def test_missing_executable_is_unavailable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            request = ProcessRequest(["definitely-not-a-tla-tool"], Path(temporary))
            result = run_process(request)
        self.assertEqual(result.status, ExecutionStatus.UNAVAILABLE)
        self.assertIsNone(result.returncode)

    def test_popen_double_receives_direct_hermetic_invocation(self) -> None:
        class FakeStream:
            def __init__(self, contents: bytes) -> None:
                self.contents = contents

            def read1(self, _size: int) -> bytes:
                contents, self.contents = self.contents, b""
                return contents

            def close(self) -> None:
                pass

        class FakeProcess:
            pid = 1234
            stdout = FakeStream(b"stdout")
            stderr = FakeStream(b"stderr")

            def poll(self) -> int:
                return 0

            def wait(self, timeout: float | None = None) -> int:
                return 0

        captured: dict[str, object] = {}

        def fake_popen(*arguments: object, **keywords: object) -> FakeProcess:
            captured["arguments"] = arguments
            captured.update(keywords)
            return FakeProcess()

        with tempfile.TemporaryDirectory() as temporary, patch("process._terminate_process_group") as terminate:
            result = run_process(
                ProcessRequest(["oracle", "--frontend"], Path(temporary), {"JAVA_HOME": "/pinned/java"}),
                popen_factory=fake_popen,
            )
        self.assertEqual(result.status, ExecutionStatus.COMPLETED)
        self.assertEqual(result.stdout, b"stdout")
        self.assertEqual(result.stderr, b"stderr")
        terminate.assert_called_once()
        self.assertFalse(captured["shell"])
        environment = captured["env"]
        self.assertEqual(environment["JAVA_HOME"], "/pinned/java")  # type: ignore[index]
        self.assertNotIn("HOME", environment)  # type: ignore[operator]

    def test_timeout_kills_term_ignoring_child_process_group(self) -> None:
        if os.name != "posix":
            self.skipTest("the stdlib recursive process-group assertion is POSIX-only")
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            child_pid = directory / "child.pid"
            program = (
                "import pathlib, subprocess, sys, time; "
                "child = subprocess.Popen([sys.executable, '-c', \"import signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)\"]); "
                f"pathlib.Path({str(child_pid)!r}).write_text(str(child.pid)); time.sleep(60)"
            )
            result = run_process(self.request(directory, program), ProcessLimits(timeout_seconds=0.2))
            self.assertEqual(result.status, ExecutionStatus.TIMEOUT)
            pid = int(child_pid.read_text())
            deadline = time.monotonic() + 1
            while time.monotonic() < deadline:
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    break
                time.sleep(0.02)
            else:
                self.fail("timeout left a child process running")

    def test_stdout_flood_is_resource_exhausted_and_bounded(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            result = run_process(
                self.request(Path(temporary), "import sys; sys.stdout.buffer.write(b'x' * 4096); sys.stdout.flush(); import time; time.sleep(60)"),
                ProcessLimits(timeout_seconds=2, max_stdout_bytes=128),
            )
        self.assertEqual(result.status, ExecutionStatus.RESOURCE_EXHAUSTED)
        self.assertLessEqual(len(result.stdout), 128)

    def test_completed_leader_does_not_leave_background_child(self) -> None:
        if os.name != "posix":
            self.skipTest("the stdlib recursive process-group assertion is POSIX-only")
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            child_pid = directory / "child.pid"
            program = (
                "import pathlib, subprocess, sys; "
                "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)']); "
                f"pathlib.Path({str(child_pid)!r}).write_text(str(child.pid))"
            )
            result = run_process(self.request(directory, program), ProcessLimits(timeout_seconds=2))
            self.assertEqual(result.status, ExecutionStatus.COMPLETED)
            pid = int(child_pid.read_text())
            deadline = time.monotonic() + 1
            while time.monotonic() < deadline:
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    break
                time.sleep(0.02)
            else:
                self.fail("completed invocation left a child process running")

    def test_artifact_flood_is_resource_exhausted_and_discarded(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            artifacts = directory / "artifacts"
            artifacts.mkdir()
            result = run_process(
                self.request(directory, "from pathlib import Path; Path('artifacts/output').write_bytes(b'x' * 4096)", artifact_dir=artifacts),
                ProcessLimits(max_artifact_bytes=128),
            )
            self.assertEqual(result.status, ExecutionStatus.RESOURCE_EXHAUSTED)
            self.assertEqual(result.artifact_bytes, 0)
            self.assertEqual(list(artifacts.iterdir()), [])
            self.assertIn("discarded 4096 retained artifact bytes", result.detail or "")

    def test_invalid_artifact_directory_is_refused_before_execution(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            missing = directory / "missing"
            with self.assertRaisesRegex(ValueError, "artifact_dir"):
                ProcessRequest([sys.executable, "-c", "pass"], directory, artifact_dir=missing)
            with self.assertRaisesRegex(ValueError, "strictly below cwd"):
                ProcessRequest([sys.executable, "-c", "pass"], directory, artifact_dir=directory)
            with self.assertRaisesRegex(ValueError, "strictly below cwd"):
                ProcessRequest([sys.executable, "-c", "pass"], directory, artifact_dir=directory.parent)
            nonempty = directory / "nonempty"; nonempty.mkdir(); (nonempty / "sentinel").write_text("keep")
            with self.assertRaisesRegex(ValueError, "initially empty"):
                ProcessRequest([sys.executable, "-c", "pass"], directory, artifact_dir=nonempty)
            link = directory / "artifact-link"; link.symlink_to(nonempty, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "non-symlink"):
                ProcessRequest([sys.executable, "-c", "pass"], directory, artifact_dir=link)

    def test_timeout_discards_artifact_overflow_without_losing_timeout_status(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            artifacts = directory / "artifacts"; artifacts.mkdir()
            result = run_process(
                self.request(directory, "from pathlib import Path; Path('artifacts/output').write_bytes(b'x' * 4096); import time; time.sleep(60)", artifact_dir=artifacts),
                ProcessLimits(timeout_seconds=0.05, max_artifact_bytes=128),
                poll_interval_seconds=0.1,
            )
            self.assertEqual(result.status, ExecutionStatus.TIMEOUT)
            self.assertEqual(result.artifact_bytes, 0)
            self.assertEqual(list(artifacts.iterdir()), [])
            self.assertIn("discarded 4096 retained artifact bytes", result.detail or "")

    def test_environment_does_not_inherit_ambient_configuration(self) -> None:
        environment = deterministic_environment({"JAVA_HOME": "/pinned/java"})
        self.assertEqual(environment["JAVA_HOME"], "/pinned/java")
        self.assertEqual(environment["LANG"], "C")
        self.assertNotIn("HOME", environment)
        self.assertNotIn("TLA_LIBRARY", environment)


if __name__ == "__main__":
    unittest.main()
