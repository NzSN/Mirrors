import copy
import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path

import manifest_check as checker


ROOT = Path(__file__).resolve().parents[2]
LOCK_ROOT = ROOT / "distribution/reference-node"
VALID_CACHE = LOCK_ROOT / "fixtures/cache-index.checked-replay-local.valid.json"
VALID_MANIFEST = LOCK_ROOT / "fixtures/distribution-manifest.checked-replay-local.valid.json"
CATALOG_BIN = ROOT / ".lake/build/bin/framework_catalog"


def load_contract(root: Path = LOCK_ROOT) -> dict:
    return checker.validate_locks(root, CATALOG_BIN)


class ManifestCheckTests(unittest.TestCase):
    def test_locked_profiles_and_local_cache(self) -> None:
        locked = load_contract()
        local, _ = checker.profile_closure("checked-replay-local", locked["profiles"])
        gate, ancestors = checker.profile_closure("checked-replay-gate", locked["profiles"])
        fresh, _ = checker.profile_closure("fresh-trace", locked["profiles"])
        self.assertFalse(local & {"java-runtime", "apalache"})
        self.assertFalse(gate & {"java-runtime", "apalache"})
        self.assertIn("checked-replay-local", ancestors)
        self.assertLessEqual(local, gate)
        self.assertTrue({"java-runtime", "apalache"} <= fresh)
        self.assertEqual(set(checker.runtime_tree_requirements("fresh-trace", locked["profiles"])),
            {"node-runtime", "java-runtime", "apalache-runtime"})
        manifest = checker.validate_distribution_manifest(VALID_MANIFEST, "checked-replay-local", locked)
        checker.validate_cache_index(VALID_CACHE, "checked-replay-local", locked, manifest)

    def test_wrong_catalog_and_product_only_component_match_fail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            locks = root / "distribution/reference-node"
            catalog = root / "catalog"
            shutil.copytree(LOCK_ROOT, locks)
            catalog.mkdir()
            shutil.copy(ROOT / "catalog/framework-catalog.json", catalog / "framework-catalog.json")
            profiles = json.loads((locks / "profiles.json").read_text())
            profiles["catalogSelectionRef"]["selectionValue"] = "0" * 64
            (locks / "profiles.json").write_text(json.dumps(profiles))
            with self.assertRaisesRegex(checker.ContractError, "catalogSelectionRef"):
                checker.validate_locks(locks, CATALOG_BIN)
            shutil.copy(LOCK_ROOT / "profiles.json", locks / "profiles.json")
            components = json.loads((locks / "component-lock.json").read_text())
            components["components"][0]["componentRef"]["revision"] = "0" * 40
            (locks / "component-lock.json").write_text(json.dumps(components))
            with self.assertRaisesRegex(checker.ContractError, "component identity differs"):
                checker.validate_locks(locks, CATALOG_BIN)
            shutil.copy(LOCK_ROOT / "component-lock.json", locks / "component-lock.json")
            profiles = json.loads((locks / "profiles.json").read_text())
            profiles["profiles"][0]["requiredArtifacts"] = [[]]
            (locks / "profiles.json").write_text(json.dumps(profiles))
            with self.assertRaisesRegex(checker.ContractError, "nonempty string required"):
                checker.validate_locks(locks, CATALOG_BIN)

    def test_cache_traversal_private_path_and_closure_fail(self) -> None:
        contract = load_contract()
        document = json.loads(VALID_CACHE.read_text())
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "index.json"
            traversal = copy.deepcopy(document)
            traversal["entries"][0]["path"] = "artifacts/../private"
            path.write_text(json.dumps(traversal))
            with self.assertRaisesRegex(checker.ContractError, "traversal"):
                checker.validate_cache_index(path, "checked-replay-local", contract)
            private = copy.deepcopy(document)
            private["entries"][0]["path"] = "artifacts/secrets/counter.json"
            path.write_text(json.dumps(private))
            with self.assertRaisesRegex(checker.ContractError, "private/operator payload"):
                checker.validate_cache_index(path, "checked-replay-local", contract)
            extra = copy.deepcopy(document)
            extra["entries"].append({"artifactId": "java-runtime", "path": "artifacts/java.tar", "bytes": 1, "sha256": "a" * 64, "mode": "0644"})
            path.write_text(json.dumps(extra))
            with self.assertRaisesRegex(checker.ContractError, "closure mismatch"):
                checker.validate_cache_index(path, "checked-replay-local", contract)
            wrong_dependency = copy.deepcopy(document)
            node = next(entry for entry in wrong_dependency["entries"] if entry["artifactId"] == "node-runtime")
            node["sha256"] = "f" * 64
            path.write_text(json.dumps(wrong_dependency))
            with self.assertRaisesRegex(checker.ContractError, "differs from dependency lock"):
                checker.validate_cache_index(path, "checked-replay-local", contract)
            duplicate_path = copy.deepcopy(document)
            duplicate_path["entries"][1]["path"] = duplicate_path["entries"][0]["path"]
            path.write_text(json.dumps(duplicate_path))
            with self.assertRaisesRegex(checker.ContractError, "duplicate or case-colliding"):
                checker.validate_cache_index(path, "checked-replay-local", contract)

    def test_fresh_trace_is_unavailable_without_exact_java(self) -> None:
        contract = load_contract()
        local = json.loads(VALID_CACHE.read_text())
        closure, _ = checker.profile_closure("fresh-trace", contract["profiles"])
        template = local["entries"][0]
        local["profileId"] = "fresh-trace"
        existing = {entry["artifactId"]: entry for entry in local["entries"]}
        for artifact_id in closure:
            if artifact_id not in existing:
                existing[artifact_id] = {**template, "artifactId": artifact_id, "path": f"artifacts/{artifact_id}.bin"}
        existing["apalache"]["bytes"] = contract["dependencies"]["apalache"]["bytes"]
        existing["apalache"]["sha256"] = contract["dependencies"]["apalache"]["sha256"]
        local["entries"] = list(existing.values())
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "index.json"
            path.write_text(json.dumps(local))
            with self.assertRaisesRegex(checker.ContractError,
                    "profile is unavailable; missing dependency: java-runtime"):
                checker.validate_cache_index(path, "fresh-trace", contract)

    def test_final_manifest_digest_and_entry_identity(self) -> None:
        locked = load_contract()
        manifest = checker.validate_distribution_manifest(VALID_MANIFEST, "checked-replay-local", locked)
        checker.validate_cache_index(VALID_CACHE, "checked-replay-local", locked, manifest)
        cache = json.loads(VALID_CACHE.read_text())
        cache["distributionManifestSha256"] = "0" * 64
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "index.json"
            path.write_text(json.dumps(cache))
            with self.assertRaisesRegex(checker.ContractError, "does not match manifest bytes"):
                checker.validate_cache_index(path, "checked-replay-local", locked, manifest)

    def test_identity_dag_excludes_carriers_and_binds_lock_bytes(self) -> None:
        locked = load_contract()
        catalog = json.loads((ROOT / "catalog/framework-catalog.json").read_text())
        mirrors = next(entry["componentRef"] for entry in catalog["components"]
            if entry["componentRef"]["componentId"] == "mirrors")
        excluded = {entry["path"]: entry["reasonCode"]
            for entry in mirrors["dirtyContent"]["excludedPaths"]}
        carriers = {
            "catalog/framework-catalog.json",
            "catalog/framework-catalog.compact.json",
            "catalog/components/mirrors.json",
            "Docs/framework-map.md",
            "distribution/reference-node/profiles.json",
            "distribution/reference-node/component-lock.json",
            "distribution/reference-node/dependency-lock.json",
            "distribution/reference-node/fixtures/cache-index.checked-replay-local.valid.json",
            "distribution/reference-node/fixtures/distribution-manifest.checked-replay-local.valid.json",
            "distribution/reference-node/fixtures/cache-index.checked-replay-gate.valid.json",
            "distribution/reference-node/fixtures/distribution-manifest.checked-replay-gate.valid.json",
        }
        self.assertLessEqual(carriers, set(excluded))
        self.assertTrue(all(excluded[path] == "evidence-output" for path in carriers))
        manifest = json.loads(VALID_MANIFEST.read_text())
        self.assertEqual({entry["inputId"]: entry for entry in manifest["buildInputs"]},
            locked["buildInputs"])

    def test_final_manifest_rejects_tree_source_and_host_downgrades(self) -> None:
        locked = load_contract()
        document = json.loads(VALID_MANIFEST.read_text())
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "manifest.json"
            missing_tree = copy.deepcopy(document)
            missing_tree["runtimeTrees"] = []
            path.write_text(json.dumps(missing_tree))
            with self.assertRaisesRegex(checker.ContractError, "runtime tree set mismatch"):
                checker.validate_distribution_manifest(path, "checked-replay-local", locked)
            wrong_source = copy.deepcopy(document)
            wrong_source["artifacts"][0]["source"]["id"] = "mirror-server"
            path.write_text(json.dumps(wrong_source))
            with self.assertRaisesRegex(checker.ContractError, "source id does not match"):
                checker.validate_distribution_manifest(path, "checked-replay-local", locked)
            downgraded_host = copy.deepcopy(document)
            downgraded_host["hostRequirements"][0]["requirement"] = "any libc"
            path.write_text(json.dumps(downgraded_host))
            with self.assertRaisesRegex(checker.ContractError, "prerequisite predicates"):
                checker.validate_distribution_manifest(path, "checked-replay-local", locked)
            boolean_count = copy.deepcopy(document)
            boolean_count["artifacts"][0]["bytes"] = True
            path.write_text(json.dumps(boolean_count))
            with self.assertRaisesRegex(checker.ContractError, "invalid artifact identity"):
                checker.validate_distribution_manifest(path, "checked-replay-local", locked)
            missing_tool = copy.deepcopy(document)
            missing_tool["buildProvenance"]["tools"] = [entry for entry in
                missing_tool["buildProvenance"]["tools"] if entry["toolId"] != "ldd"]
            path.write_text(json.dumps(missing_tool))
            with self.assertRaisesRegex(checker.ContractError, "tool set is incomplete"):
                checker.validate_distribution_manifest(path, "checked-replay-local", locked)

    def test_malformed_catalog_and_bounded_loader(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            locks = root / "distribution/reference-node"
            catalog = root / "catalog"
            shutil.copytree(LOCK_ROOT, locks)
            catalog.mkdir()
            malformed = json.loads((ROOT / "catalog/framework-catalog.json").read_text())
            malformed["unexpected"] = True
            (catalog / "framework-catalog.json").write_text(json.dumps(malformed))
            profiles = json.loads((locks / "profiles.json").read_text())
            profiles["catalogSelectionRef"]["selectionValue"] = checker.digest_json(malformed)
            (locks / "profiles.json").write_text(json.dumps(profiles))
            components = json.loads((locks / "component-lock.json").read_text())
            components["catalogSelectionRef"] = profiles["catalogSelectionRef"]
            (locks / "component-lock.json").write_text(json.dumps(components))
            with self.assertRaisesRegex(checker.ContractError, "fails C3 validation"):
                checker.validate_locks(locks, CATALOG_BIN)
            oversized = root / "oversized.json"
            oversized.write_bytes(b" " * (checker.MAX_JSON_BYTES + 1))
            with self.assertRaisesRegex(checker.ContractError, "exceeds"):
                checker.load_json(oversized)
            deep = root / "deep.json"
            deep.write_text('{"x":' * 40 + "null" + "}" * 40)
            with self.assertRaisesRegex(checker.ContractError, "nesting"):
                checker.load_json(deep)
            linked = root / "linked.json"
            linked.symlink_to(deep.name)
            with self.assertRaisesRegex(checker.ContractError, "regular file|required|safely"):
                checker.load_json(linked)
            fifo = root / "manifest.fifo"
            os.mkfifo(fifo)
            with self.assertRaisesRegex(checker.ContractError, "regular file required"):
                checker.load_json(fifo)


if __name__ == "__main__":
    unittest.main()
