import json
import tempfile
import unittest
from pathlib import Path

import refresh_identity


class LockProductPropagationTests(unittest.TestCase):
    def test_update_locks_assigns_product_by_component_id(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary) / "repo"
            root = repository / "distribution" / "locks"
            (root / "fixtures").mkdir(parents=True)
            catalog_path = repository / "catalog" / "framework-catalog.json"
            catalog_path.parent.mkdir(parents=True)
            catalog = {
                "components": [
                    {"componentRef": {"componentId": "mirrors"},
                     "product": {"name": "Mirrors", "version": "0.1.1"}},
                    {"componentRef": {"componentId": "mirrorecma"},
                     "product": {"name": "mirrorecma", "version": "0.1.0"}},
                ],
                "combinations": [{
                    "combinationId": "candidate.local-node-checked",
                    "componentIds": ["mirrorecma", "mirrors"],
                }],
            }
            catalog_path.write_text(json.dumps(catalog))
            (root / "profiles.json").write_text(json.dumps({
                "catalogSelectionRef": {},
                "profiles": [{
                    "profileId": "checked-replay-local",
                    "combinationId": "candidate.local-node-checked",
                }],
            }))
            (root / "component-lock.json").write_text(json.dumps({
                "catalogSelectionRef": {},
                "components": [
                    {"componentRef": {"componentId": "mirrorecma", "revision": "old-ecma"},
                     "product": {"name": "mirrorecma", "version": "2.0.0"}},
                    {"componentRef": {"componentId": "mirrors", "revision": "old-mirrors"},
                     "product": {"name": "Mirrors", "version": "9.9.9"}},
                ],
            }))
            (root / "dependency-lock.json").write_text("{}\n")
            for name in (
                "fixtures/distribution-manifest.checked-replay-local.valid.json",
                "fixtures/distribution-manifest.checked-replay-gate.valid.json",
                "fixtures/cache-index.checked-replay-local.valid.json",
                "fixtures/cache-index.checked-replay-gate.valid.json",
            ):
                (root / name).write_text(json.dumps({
                    "catalogSelectionRef": {}, "componentRefs": [], "buildInputs": [],
                    "distributionManifestSha256": "",
                }))
            refs = {
                "mirrorecma": {"componentId": "mirrorecma", "revision": "new-ecma"},
                "mirrors": {"componentId": "mirrors", "revision": "new-mirrors"},
            }
            refresh_identity.update_locks(refs, "ab" * 32, root=root, catalog_path=catalog_path)
            locked = {
                entry["componentRef"]["componentId"]: entry
                for entry in json.loads((root / "component-lock.json").read_text())["components"]
            }
            self.assertEqual(locked["mirrorecma"]["product"],
                {"name": "mirrorecma", "version": "0.1.0"})
            self.assertEqual(locked["mirrorecma"]["componentRef"], refs["mirrorecma"])
            self.assertEqual(locked["mirrors"]["product"],
                {"name": "Mirrors", "version": "0.1.1"})
            self.assertEqual(locked["mirrors"]["componentRef"], refs["mirrors"])


if __name__ == "__main__":
    unittest.main()
