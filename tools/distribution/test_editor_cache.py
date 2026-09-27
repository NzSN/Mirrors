import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

import distribution_lib
import refresh_identity
import snapshot_sources
from collect import component_ref


class EditorCacheExclusionTests(unittest.TestCase):
    def test_projectile_cache_is_excluded_from_snapshot_and_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary) / "component"
            repository.mkdir()
            subprocess.run(["git", "init"], cwd=repository, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "cache@example.invalid"], cwd=repository, check=True)
            subprocess.run(["git", "config", "user.name", "Cache Test"], cwd=repository, check=True)
            (repository / "README").write_text("tracked\n")
            subprocess.run(["git", "add", "README"], cwd=repository, check=True)
            subprocess.run(["git", "commit", "-m", "initial"], cwd=repository, check=True, capture_output=True)
            cache = repository / ".projectile-cache.eld"
            cache.write_text("unrelated-editor-cache\n")
            self.assertTrue(cache.is_file())

            excluded = refresh_identity.exclusions("mirrorgate", repository)
            self.assertEqual(excluded, {".projectile-cache.eld": "pre-existing-unrelated"})
            ref = component_ref("mirrorgate", repository, excluded)
            self.assertNotIn(".projectile-cache.eld", ref["dirtyContent"]["includedPaths"])
            self.assertIn({"path": ".projectile-cache.eld", "reasonCode": "pre-existing-unrelated"},
                ref["dirtyContent"]["excludedPaths"])

            destination = Path(temporary) / "snapshot"
            record = snapshot_sources.snapshot(repository, ref, destination)
            self.assertTrue(cache.is_file())
            self.assertFalse((destination / ".projectile-cache.eld").exists())
            self.assertNotIn(".projectile-cache.eld", {entry["path"] for entry in record["files"]})

            artifact = Path(temporary) / "artifact.tar.gz"
            distribution_lib.deterministic_tar(destination, artifact, "component")
            with tarfile.open(artifact, "r:gz") as archive:
                self.assertFalse(any(name.endswith(".projectile-cache.eld") for name in archive.getnames()))
            planted = destination / ".projectile-cache.eld"
            planted.write_text("must-not-be-packed\n")
            with self.assertRaisesRegex(ValueError, "cannot enter a distribution artifact"):
                distribution_lib.deterministic_tar(destination, Path(temporary) / "rejected.tar.gz", "component")


if __name__ == "__main__":
    unittest.main()
