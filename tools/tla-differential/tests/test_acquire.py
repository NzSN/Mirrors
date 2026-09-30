from __future__ import annotations

import importlib.util
import tempfile
import subprocess
import unittest
from pathlib import Path
from shutil import copyfile
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("acquire", ROOT / "tools/tla-differential/acquire.py")
assert SPEC and SPEC.loader
acquire = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(acquire)


class AcquireTests(unittest.TestCase):
    @staticmethod
    def selected_runtime(argv, **kwargs):
        # Acquisition is an offline artifact test. Pin admission is covered
        # separately below; do not depend on the coordinator's installed JDK.
        if "-version" in argv:
            return subprocess.CompletedProcess(argv, 0, "", 'openjdk version "25.0.4"\nbuild 25.0.4+7\n')
        return subprocess.CompletedProcess(argv, 0,
            "SANY\nhelp\nVersion 2.2 created 08 July 2020\n", "")

    def test_fresh_directory_is_created_and_distribution_is_extracted(self) -> None:
        source = ROOT / ".golden-build/tla-differential/toolchain/downloads"
        with tempfile.TemporaryDirectory() as temporary:
            acquire.TOOLCHAIN = Path(temporary) / "new-toolchain"

            def fake_download(url: str, destination: Path) -> None:
                name = "apalache-0.61.0.tgz" if url.endswith(".tgz") else "tla2tools-1.8.0.jar"
                copyfile(source / name, destination)

            with patch.object(acquire, "download", side_effect=fake_download), \
                    patch.object(acquire.subprocess, "run", side_effect=self.selected_runtime), \
                    patch.object(acquire.shutil, "which", return_value="/selected/java"):
                acquire.acquire()
                acquire.verify_tools()
            self.assertTrue((acquire.TOOLCHAIN / "apalache-0.61.0/lib/apalache.jar").is_file())

    def test_different_jdk_cannot_qualify_selected_tools(self) -> None:
        with patch.object(acquire, "TOOLCHAIN", ROOT / ".golden-build/tla-differential/toolchain"), \
                patch.object(acquire.shutil, "which", return_value="/other/java"), \
                patch.object(acquire.subprocess, "run", return_value=
                    subprocess.CompletedProcess([], 0, "", 'openjdk version "25.0.4.1"\nbuild 25.0.4.1+1\n')):
            with self.assertRaisesRegex(SystemExit, "Java 25.0.4\\+7 is required"):
                acquire.verify_tools()

    def test_missing_extracted_distribution_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            acquire.TOOLCHAIN = Path(temporary)
            downloads = acquire.TOOLCHAIN / "downloads"
            downloads.mkdir(parents=True)
            source = ROOT / ".golden-build/tla-differential/toolchain/downloads"
            copyfile(source / "apalache-0.61.0.tgz", downloads / "apalache-0.61.0.tgz")
            copyfile(source / "tla2tools-1.8.0.jar", downloads / "tla2tools-1.8.0.jar")
            with self.assertRaises(SystemExit):
                acquire.verify_tools()


if __name__ == "__main__":
    unittest.main()
