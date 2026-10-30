import json
import fcntl
import os
import shutil
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import install as installer


def fake_cache(root: Path, digest: str) -> Path:
    cache = root / f"cache-{digest}"
    cache.mkdir()
    (cache / "identity.json").write_text(json.dumps({"digest": digest}))
    return cache


def fake_verify(path: Path, _catalog: Path, _sha256: str, allow_pinned_fd: bool = False):
    identity = json.loads((path / "identity.json").read_text())
    return {"profileId": "checked-replay-local"}, identity["digest"], {}


def fake_verify_installation(path: Path, *_args):
    identity = json.loads((path / "cache/identity.json").read_text())
    return {"profileId": "checked-replay-local"}, identity["digest"]


class InstallTransactionTests(unittest.TestCase):
    def test_materialization_retains_actual_package_and_host_facts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cache = root / "cache"; cache.mkdir()
            inputs = root / "inputs"; inputs.mkdir()
            artifacts = []

            def record(artifact_id: str, path: Path) -> None:
                size, digest = installer.sha256_file(path)
                artifacts.append({"artifactId": artifact_id, "path": path.name,
                                  "bytes": size, "sha256": digest})

            def archive(artifact_id: str, prefix: str, files: dict[str, str]) -> Path:
                source = inputs / artifact_id; source.mkdir()
                for name, content in files.items():
                    target = source / name; target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text(content)
                target = cache / (artifact_id + ".tar.gz")
                with tarfile.open(target, "w:gz") as stream:
                    stream.add(source, arcname=prefix)
                record(artifact_id, target)
                return source

            for artifact_id in ["mirror-server", "model-interface-gen", "framework-catalog-verifier",
                                "counter-corpus", "counter-model", "selected-catalog"]:
                target = cache / artifact_id; target.write_text("{}")
                record(artifact_id, target)
            archive("node-runtime", "node", {"bin/node": "fixture"})
            package = archive("mirrorecma-package", "package", {
                "package.json": json.dumps({"name": "mirrorecma", "version": "0.1.0"}),
                "dist/index.js": "export {};"})
            application = archive("application-validation-fixtures", "application-validation", {"fixture.txt": "public"})
            shutil.copytree(package / "dist", application / "dist")
            for artifact_id, prefix in [("counter-suite-bundle", "counter-suite"),
                    ("evidence-verifier", "verification"), ("evidence-verifier-dependencies", "wheels"),
                    ("distribution-locks", "distribution-locks")]:
                archive(artifact_id, prefix, {"fixture.txt": "public"})
            manifest = {"profileId": "checked-replay-local", "artifacts": artifacts,
                "componentRefs": [], "runtimeTrees": [], "catalogSelectionRef": {"kind": "sha256", "value": "a"*64},
                "buildProvenance": {"trees": [
                    {"inputId": "package:mirrorecma", **installer.runtime_tree(package)},
                    {"inputId": "application:validation", **installer.runtime_tree(application)}]}}
            (cache / "distribution-manifest.json").write_text(json.dumps(manifest))
            (cache / "cache-index.json").write_text("{}")
            target_platform = {"os": "linux", "osRelease": "ubuntu-24.04",
                               "architecture": "x86_64", "backend": "local-process"}
            contract = {"dependencies": {"node-runtime": {"runtimeSelection": {
                "rootPrefix": "node", "include": ["bin/node"]}}},
                "profiles": {"checked-replay-local": {"catalogProfileId": "declared-target", "combinationId": "fixture"}},
                "catalog": {"distributionProfiles": [{"profileId": "declared-target", "platform": target_platform}]}}
            with patch.object(installer.platform, "freedesktop_os_release",
                              return_value={"ID": "ubuntu", "VERSION_ID": "26.04"}), \
                 patch.object(installer.platform, "machine", return_value="x86_64"):
                installer.materialize(cache, root / "runtime", manifest, contract)
            data = json.loads((root / "runtime/framework-input.json").read_text())
            self.assertEqual(data["observed"]["packages"][0]["version"], "0.1.0")
            self.assertEqual(data["installation"]["packages"][0]["manifest"]["version"], "0.1.0")
            self.assertEqual(data["observed"]["platform"]["osRelease"], "ubuntu-26.04")
            self.assertNotEqual(data["observed"]["platform"], target_platform)

    def test_package_observation_reads_actual_version_instead_of_a_profile_constant(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, version in [("mirrorecma", "0.1.0"), ("mirrorecma", "2.1.0"),
                                  ("mirrorgate-mirrorecma", "0.2.0-rc.1")]:
                (root / "package.json").write_text(json.dumps({"name": name, "version": version}))
                self.assertEqual(installer.observed_package_version(root, name), version)
            for package in [{"name": "other", "version": "2.0.0"},
                            {"name": "mirrorecma"}, {"name": "mirrorecma", "version": 2}]:
                (root / "package.json").write_text(json.dumps(package))
                with self.assertRaisesRegex(ValueError, "identity/version"):
                    installer.observed_package_version(root, "mirrorecma")

    def test_platform_observation_does_not_claim_the_catalogs_ubuntu_24_target(self) -> None:
        with patch.object(installer.platform, "freedesktop_os_release",
                          return_value={"ID": "ubuntu", "VERSION_ID": "26.04"}), \
             patch.object(installer.platform, "machine", return_value="x86_64"):
            actual = installer.observed_platform("checked-replay-local")
            self.assertEqual(actual, {"os": "linux", "osRelease": "ubuntu-26.04",
                "architecture": "x86_64", "backend": "local-process"})
            self.assertNotEqual(actual["osRelease"], "ubuntu-24.04")
            self.assertEqual(installer.observed_platform("checked-replay-gate")["backend"],
                             "linux-bubblewrap-v1")
        with patch.object(installer.platform, "freedesktop_os_release", return_value={"ID": "ubuntu"}):
            with self.assertRaisesRegex(ValueError, "incomplete"):
                installer.observed_platform("checked-replay-local")
        with patch.object(installer.sys, "platform", "darwin"):
            with self.assertRaisesRegex(ValueError, "Linux"):
                installer.observed_platform("checked-replay-local")

    def test_cache_copy_rejects_links_and_normalizes_modes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            payload = source / "payload"
            payload.write_bytes(b"payload")
            payload.chmod(0o777)
            destination = root / "destination"
            installer.copy_cache_tree(source, destination)
            self.assertEqual((destination / "payload").read_bytes(), b"payload")
            self.assertEqual(os.stat(destination / "payload").st_mode & 0o777, 0o755)
            linked = root / "linked"
            linked.mkdir()
            (linked / "payload").symlink_to(payload)
            with self.assertRaisesRegex(ValueError, "link or unsupported"):
                installer.copy_cache_tree(linked, root / "linked-copy")

    def test_proc_fd_stage_is_removed_without_rmtree_on_the_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            stage = Path(temporary) / "stage"
            stage.mkdir()
            (stage / "marker").write_text("present\n")
            descriptor = os.open(stage, os.O_RDONLY | os.O_DIRECTORY)
            try:
                installer.remove_real_directory(Path(f"/proc/self/fd/{descriptor}"))
            finally:
                os.close(descriptor)
            self.assertFalse(stage.exists())

    def test_staged_cache_is_verified_before_materialization(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cache = fake_cache(root, "9" * 64)
            prefix = root / "prefix"
            calls = 0

            def admission_then_reject(path: Path, *_args, **_kwargs):
                nonlocal calls
                calls += 1
                if calls == 1:
                    return fake_verify(path, Path("/unused"), "0" * 64)
                raise ValueError("staged cache rejected")

            with patch.object(installer, "verify", side_effect=admission_then_reject), \
                    patch.object(installer, "materialize") as materialize:
                with self.assertRaisesRegex(ValueError, "staged cache rejected"):
                    installer.install(cache, prefix, Path("/unused"), "0" * 64, None)
                materialize.assert_not_called()

    def test_commit_idempotence_and_after_activation_rollback(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = fake_cache(root, "a" * 64)
            second = fake_cache(root, "b" * 64)
            prefix = root / "prefix"
            with patch.object(installer, "verify", side_effect=fake_verify), \
                    patch.object(installer, "materialize", return_value={}), \
                    patch.object(installer, "verify_installation", side_effect=fake_verify_installation):
                state, digest = installer.install(first, prefix, Path("/unused"), "0" * 64, None)
                self.assertEqual((state, digest), ("committed", "a" * 64))
                self.assertEqual(installer.selector(prefix)["manifestDigest"], "a" * 64)
                state, _ = installer.install(first, prefix, Path("/unused"), "0" * 64, None)
                self.assertEqual(state, "idempotent")
                with self.assertRaisesRegex(RuntimeError, "injected"):
                    installer.install(second, prefix, Path("/unused"), "0" * 64, "after-activate")
                self.assertEqual(installer.selector(prefix)["manifestDigest"], "a" * 64)
                self.assertEqual(json.loads((prefix / "transaction.json").read_text())["state"], "rolled-back")
                self.assertTrue((prefix / "versions" / ("a" * 64)).is_dir())
                self.assertTrue((prefix / "versions" / ("b" * 64)).is_dir())

    def test_interrupted_stage_is_quarantined_before_retry(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cache = fake_cache(root, "c" * 64)
            prefix = root / "prefix"
            with patch.object(installer, "verify", side_effect=fake_verify), \
                    patch.object(installer, "materialize", return_value={}), \
                    patch.object(installer, "verify_installation", side_effect=fake_verify_installation):
                with self.assertRaisesRegex(RuntimeError, "injected"):
                    installer.install(cache, prefix, Path("/unused"), "0" * 64, "before-activate")
                old_stage = next((prefix / ".staging").iterdir())
                self.assertFalse(old_stage.name.endswith(".abandoned"))
                state, _ = installer.install(cache, prefix, Path("/unused"), "0" * 64, None)
                self.assertEqual(state, "committed")
                self.assertTrue(any(path.name.endswith(".abandoned") for path in (prefix / ".staging").iterdir()))

    def test_lock_symlink_and_selector_confinement(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cache = fake_cache(root, "d" * 64)
            prefix = root / "prefix"
            prefix.mkdir(mode=0o700)
            lock = (prefix / ".install.lock").open("w")
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(ValueError, "locked"):
                installer.install(cache, prefix, Path("/unused"), "0" * 64, None)
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
            lock.close()
            target = root / "elsewhere"
            target.mkdir(mode=0o700)
            (prefix / "versions").symlink_to(target, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "real directory required"):
                installer.install(cache, prefix, Path("/unused"), "0" * 64, None)
            (prefix / "versions").unlink()
            (prefix / "active.json").write_text(json.dumps({
                "manifestDigest": "d" * 64,
                "versionDirectory": "../../outside",
            }))
            with patch.object(installer, "verify", side_effect=fake_verify):
                with self.assertRaisesRegex(ValueError, "not confined"):
                    installer.install(cache, prefix, Path("/unused"), "0" * 64, None)

    def test_restart_recovery_verification_failure_restores_previous(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            prefix = Path(temporary) / "prefix"
            prefix.mkdir(mode=0o700)
            versions = prefix / "versions"
            versions.mkdir(mode=0o700)
            for digest in ("a" * 64, "b" * 64):
                version = versions / digest
                (version / "cache").mkdir(parents=True)
                (version / "cache/identity.json").write_text(json.dumps({"digest": digest}))
            previous = {"manifestDigest": "a" * 64, "versionDirectory": "versions/" + "a" * 64}
            installer.activate_selector(prefix, {"manifestDigest": "b" * 64,
                "versionDirectory": "versions/" + "b" * 64})
            (prefix / "transaction.json").write_text(json.dumps({"state": "activating",
                "manifestDigest": "b" * 64, "previous": previous,
                "version": "versions/" + "b" * 64}))
            def fail_new(path: Path, *_args):
                if path.name == "b" * 64:
                    raise ValueError("new version corrupt")
                return fake_verify_installation(path)
            with patch.object(installer, "verify_installation", side_effect=fail_new):
                with self.assertRaisesRegex(ValueError, "corrupt"):
                    installer.recover_internal_state(prefix, versions, prefix / ".staging",
                        Path("/unused"), "0" * 64)
            self.assertEqual(installer.selector(prefix), previous)
            self.assertEqual(json.loads((prefix / "transaction.json").read_text())["state"], "rolled-back")

    def test_all_interruption_boundaries_preserve_previous_selector(self) -> None:
        stages = ["after-copy", "after-materialize", "after-verify", "before-activate",
            "after-version-rename", "after-selector"]
        for stage in stages:
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                first = fake_cache(root, "e" * 64)
                second = fake_cache(root, "f" * 64)
                prefix = root / "prefix"
                with patch.object(installer, "verify", side_effect=fake_verify), \
                        patch.object(installer, "materialize", return_value={}), \
                        patch.object(installer, "verify_installation", side_effect=fake_verify_installation):
                    installer.install(first, prefix, Path("/unused"), "0" * 64, None)
                    previous = installer.selector(prefix)
                    with self.assertRaisesRegex(RuntimeError, "injected"):
                        installer.install(second, prefix, Path("/unused"), "0" * 64, stage)
                    self.assertEqual(installer.selector(prefix), previous)


class WslProfileAdmissionTests(unittest.TestCase):
    def test_observed_virtualization_reads_the_kernel_release(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary) / "osrelease"
            release.write_text("6.18.54.1-microsoft-standard-WSL2\n")
            self.assertEqual(installer.observed_virtualization(release), "wsl2")
            release.write_text("6.8.0-40-generic\n")
            self.assertIsNone(installer.observed_virtualization(release))
            self.assertIsNone(installer.observed_virtualization(Path(temporary) / "missing"))

    def test_wsl2_catalog_profile_requires_a_wsl2_host(self) -> None:
        profile = "mirrors.reference-node-checked/ubuntu-26.04-wsl2-x86_64/v1"
        installer.require_profile_host(profile, "wsl2")
        with self.assertRaisesRegex(ValueError, "observed WSL2 host"):
            installer.require_profile_host(profile, None)
        # The existing Ubuntu 24.04 profiles stay admissible on either host.
        installer.require_profile_host(
            "mirrors.reference-node-checked/ubuntu-24.04-x86_64/v1", None)
        installer.require_profile_host(
            "mirrors.reference-node-checked/ubuntu-24.04-x86_64/v1", "wsl2")

    def test_reference_wsl2_catalog_and_locks_are_additive(self) -> None:
        repo = Path(__file__).resolve().parents[2]
        base_catalog = json.loads((repo / "catalog/framework-catalog.json").read_text())
        variant = json.loads((repo / "catalog/framework-catalog-wsl2-26.04.json").read_text())
        base_ids = {entry["profileId"] for entry in base_catalog["distributionProfiles"]}
        self.assertIn("mirrors.reference-node-checked/ubuntu-24.04-x86_64/v1", base_ids)
        self.assertIn("mirrors.reference-node-gate/ubuntu-24.04-x86_64/v1", base_ids)
        for entry in variant["distributionProfiles"]:
            self.assertEqual(entry["platform"]["osRelease"], "ubuntu-26.04")
            self.assertIn("wsl2", entry["profileId"])
            self.assertIn({"dependencyId": "virtualization", "version": "WSL2",
                           "class": "operator-host-prerequisite"}, entry["dependencies"])
        self.assertEqual(
            {entry["combinationId"] for entry in base_catalog["combinations"]},
            {entry["combinationId"] for entry in variant["combinations"]})
        profiles = json.loads((repo / "distribution/reference-node-wsl2-26.04/profiles.json").read_text())
        self.assertEqual(
            {entry["profileId"] for entry in profiles["profiles"]},
            {"checked-replay-local", "checked-replay-gate", "fresh-trace"})
        for entry in profiles["profiles"]:
            self.assertIn("wsl2", entry["catalogProfileId"])


if __name__ == "__main__":
    unittest.main()
