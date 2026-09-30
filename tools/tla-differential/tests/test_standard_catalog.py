"""Check catalog identities/import edges against the locked standard sources."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[3]


class StandardCatalogTests(unittest.TestCase):
    def setUp(self) -> None:
        self.jar = ROOT / ".golden-build/tla-differential/toolchain/downloads/tla2tools-1.8.0.jar"
        if not self.jar.is_file():
            self.skipTest("locked standalone standard sources are not acquired")
        lock = json.loads((ROOT / "tools/tla-differential/toolchain.lock.json").read_text())
        self.assertEqual(hashlib.sha256(self.jar.read_bytes()).hexdigest(), lock["tools"]["sany"]["sha256"])
        self.catalog = (ROOT / "Core/Tla/StandardCatalog.lean").read_text()

    def test_module_content_identities(self) -> None:
        identities = re.findall(r'\("([A-Za-z]+)", "([0-9a-f]{64})"\)', self.catalog)
        self.assertEqual(len(identities), 11)
        with zipfile.ZipFile(self.jar) as archive:
            for name, expected in identities:
                content = archive.read(f"tla2sany/StandardModules/{name}.tla")
                self.assertEqual(hashlib.sha256(content).hexdigest(), expected, name)

    def test_public_and_local_import_facts(self) -> None:
        edges = re.findall(r'owner := ⟨"([A-Za-z]+)"⟩, dependency := ⟨"([A-Za-z]+)"⟩(?:, localOnly := (true))?', self.catalog)
        self.assertEqual(len(edges), 18)
        with zipfile.ZipFile(self.jar) as archive:
            for owner, dependency, local in edges:
                content = archive.read(f"tla2sany/StandardModules/{owner}.tla").decode()
                if local:
                    self.assertRegex(content, rf'\bLOCAL\s+INSTANCE\s+{dependency}\b', owner)
                else:
                    self.assertRegex(content, rf'\bEXTENDS[^\n]*\b{dependency}\b', owner)


if __name__ == "__main__":
    unittest.main()
