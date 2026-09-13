from __future__ import annotations

import importlib.util
import tempfile
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
    def test_fresh_directory_is_created_and_distribution_is_extracted(self) -> None:
        source = ROOT / ".golden-build/tla-differential/toolchain/downloads"
        with tempfile.TemporaryDirectory() as temporary:
            acquire.TOOLCHAIN = Path(temporary) / "new-toolchain"

            def fake_download(url: str, destination: Path) -> None:
                name = "apalache-0.61.0.tgz" if url.endswith(".tgz") else "tla2tools-1.8.0.jar"
                copyfile(source / name, destination)

            with patch.object(acquire, "download", side_effect=fake_download):
                acquire.acquire()
            self.assertTrue((acquire.TOOLCHAIN / "apalache-0.61.0/lib/apalache.jar").is_file())
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
