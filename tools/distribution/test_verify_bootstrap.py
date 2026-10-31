import hashlib
import json
import tarfile
import tempfile
import unittest
from pathlib import Path

import manifest_check
import verify


ROOT = Path(__file__).resolve().parents[2]
BASE_ROOT = "distribution/reference-node"
VARIANT_ROOT = "distribution/reference-node-wsl2-26.04"
CATALOG_BIN = ROOT / ".lake/build/bin/framework_catalog"
LOCAL_MANIFEST = "fixtures/distribution-manifest.checked-replay-local.valid.json"
LOCAL_INDEX = "fixtures/cache-index.checked-replay-local.valid.json"


def lock_inputs(root: str) -> list[dict]:
    return [{"inputId": input_id, "path": f"{root}/{name}", "bytes": 1, "sha256": "0" * 64}
        for input_id, name in verify.LOCK_INPUT_FILES.items()]


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


class BootstrapLockRootTests(unittest.TestCase):
    def test_base_and_variant_roots_are_derived(self) -> None:
        for root in (BASE_ROOT, VARIANT_ROOT):
            self.assertEqual(verify.bootstrap_lock_relative_root({"buildInputs": lock_inputs(root)}), root)

    def test_mixed_roots_are_rejected(self) -> None:
        entries = lock_inputs(VARIANT_ROOT)
        entries[0]["path"] = f"{BASE_ROOT}/profiles.json"
        with self.assertRaisesRegex(verify.ContractError, "mixed roots"):
            verify.bootstrap_lock_relative_root({"buildInputs": entries})

    def test_absolute_traversal_and_foreign_paths_are_rejected(self) -> None:
        cases = [
            ("/distribution/reference-node/profiles.json", "relative and traversal-free"),
            ("distribution/../reference-node/profiles.json", "relative and traversal-free"),
            ("distribution/reference-node/../../profiles.json", "relative and traversal-free"),
            ("distribution\\reference-node\\profiles.json", "relative and traversal-free"),
            ("C:/distribution/reference-node/profiles.json", "relative and traversal-free"),
            ("distribution//profiles.json", "relative and traversal-free"),
            ("profiles.json", "must name distribution/<root>/profiles.json"),
            ("distribution/nested/reference-node/profiles.json", "must name distribution/<root>/profiles.json"),
        ]
        for path, message in cases:
            entries = lock_inputs(VARIANT_ROOT)
            entries[0]["path"] = path
            with self.assertRaisesRegex(verify.ContractError, message):
                verify.bootstrap_lock_relative_root({"buildInputs": entries})

    def test_expected_filenames_are_enforced(self) -> None:
        entries = lock_inputs(VARIANT_ROOT)
        entries[0]["path"] = f"{VARIANT_ROOT}/component-lock.json"
        with self.assertRaisesRegex(verify.ContractError,
                "must name distribution/<root>/profiles.json"):
            verify.bootstrap_lock_relative_root({"buildInputs": entries})

    def test_incomplete_duplicate_and_malformed_inputs_are_rejected(self) -> None:
        with self.assertRaisesRegex(verify.ContractError, "incomplete"):
            verify.bootstrap_lock_relative_root({"buildInputs": lock_inputs(VARIANT_ROOT)[:-1]})
        duplicate = lock_inputs(VARIANT_ROOT)
        duplicate[1]["inputId"] = "profiles-lock"
        with self.assertRaisesRegex(verify.ContractError, "identity is invalid"):
            verify.bootstrap_lock_relative_root({"buildInputs": duplicate})
        with self.assertRaisesRegex(verify.ContractError, "bounded array"):
            verify.bootstrap_lock_relative_root({"buildInputs": "distribution/reference-node"})
        with self.assertRaisesRegex(verify.ContractError, "must be an object"):
            verify.bootstrap_lock_relative_root({"buildInputs": [[]]})
        control = lock_inputs(VARIANT_ROOT)
        control[0]["path"] = "distribution/reference-node/profiles.json\x01"
        with self.assertRaisesRegex(verify.ContractError, "control character"):
            verify.bootstrap_lock_relative_root({"buildInputs": control})


class BootstrapMaterializeTests(unittest.TestCase):
    def archive_locks(self, cache: Path, root: str) -> Path:
        archive = cache / "distribution-locks.tar.gz"
        with tarfile.open(archive, "w:gz") as stream:
            for name in verify.LOCK_INPUT_FILES.values():
                stream.add(ROOT / root / name, arcname=f"distribution-locks/{name}")
        return archive

    def test_base_and_variant_archives_materialize_the_declared_root(self) -> None:
        for root in (BASE_ROOT, VARIANT_ROOT):
            with tempfile.TemporaryDirectory() as temporary:
                cache = Path(temporary) / "cache"
                cache.mkdir()
                archive = self.archive_locks(cache, root)
                manifest = {"buildInputs": lock_inputs(root)}
                artifacts = {"distribution-locks": {"path": archive.name}}
                bootstrap = Path(temporary) / "bootstrap"
                lock_root = verify.materialize_bootstrap_locks(cache, artifacts, manifest, bootstrap)
                self.assertEqual(lock_root, bootstrap / root)
                for name in verify.LOCK_INPUT_FILES.values():
                    self.assertEqual((lock_root / name).read_bytes(), (ROOT / root / name).read_bytes())
                other = VARIANT_ROOT if root == BASE_ROOT else BASE_ROOT
                self.assertFalse((bootstrap / other).exists())

    def test_mixed_root_archive_is_rejected_before_extraction(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            cache = Path(temporary) / "cache"
            cache.mkdir()
            archive = self.archive_locks(cache, VARIANT_ROOT)
            entries = lock_inputs(VARIANT_ROOT)
            entries[2]["path"] = f"{BASE_ROOT}/dependency-lock.json"
            with self.assertRaisesRegex(verify.ContractError, "mixed roots"):
                verify.materialize_bootstrap_locks(cache,
                    {"distribution-locks": {"path": archive.name}},
                    {"buildInputs": entries}, Path(temporary) / "bootstrap")
            self.assertFalse((Path(temporary) / "bootstrap/extracted").exists())


class BootstrapCacheVerifyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not CATALOG_BIN.is_file():
            raise unittest.SkipTest(f"framework catalog binary is missing: {CATALOG_BIN}")
        cls.catalog_sha256 = sha256(CATALOG_BIN.read_bytes())

    def seed_cache(self, temporary: str, root: str, catalog: str) -> Path:
        cache = Path(temporary) / "cache"
        cache.mkdir()
        lock_root = ROOT / root
        manifest = json.loads((lock_root / LOCAL_MANIFEST).read_text())
        index = json.loads((lock_root / LOCAL_INDEX).read_text())
        contract = manifest_check.validate_locks(lock_root, CATALOG_BIN,
            catalog_path=ROOT / catalog, framework_catalog_sha256=self.catalog_sha256)
        _, prerequisites, _ = manifest_check.profile_resolution("checked-replay-local",
            contract["profiles"])
        manifest["distributionId"] = contract["distributionId"]
        manifest["hostRequirements"] = list(prerequisites.values())
        archive = cache / "artifacts/inputs/distribution-locks.tar.gz"
        archive.parent.mkdir(parents=True)
        with tarfile.open(archive, "w:gz") as stream:
            for name in verify.LOCK_INPUT_FILES.values():
                stream.add(lock_root / name, arcname=f"distribution-locks/{name}")
        catalog_path = cache / "artifacts/inputs/framework-catalog.A.json"
        catalog_path.write_bytes((ROOT / catalog).read_bytes())
        identities = {
            "distribution-locks": (archive.stat().st_size, sha256(archive.read_bytes())),
            "selected-catalog": (catalog_path.stat().st_size, sha256(catalog_path.read_bytes())),
        }
        for entries in (manifest["artifacts"], index["entries"]):
            for entry in entries:
                if entry["artifactId"] in identities:
                    entry["bytes"], entry["sha256"] = identities[entry["artifactId"]]
        index["distributionManifestSha256"] = verify.digest_json(manifest)
        for artifact in manifest["artifacts"]:
            target = cache / artifact["path"]
            if not target.exists():
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"")
        (cache / "distribution-manifest.json").write_text(json.dumps(manifest))
        (cache / "cache-index.json").write_text(json.dumps(index))
        return cache

    def test_real_base_and_variant_caches_reach_artifact_identity_checks(self) -> None:
        selections = (
            (BASE_ROOT, "catalog/framework-catalog.json"),
            (VARIANT_ROOT, "catalog/framework-catalog-wsl2-26.04.json"),
        )
        for root, catalog in selections:
            with tempfile.TemporaryDirectory() as temporary:
                cache = self.seed_cache(temporary, root, catalog)
                with self.assertRaises(verify.ContractError) as raised:
                    verify.verify(cache, CATALOG_BIN, self.catalog_sha256)
                message = str(raised.exception)
                self.assertIn("artifact identity mismatch", message)
                self.assertNotIn("buildInputs differ", message)
                self.assertNotIn("lock build input", message)


if __name__ == "__main__":
    unittest.main()
