from __future__ import annotations

import hashlib
import http.client
import importlib.util
import io
import shutil
import subprocess
import tarfile
import tempfile
import unittest
import zipfile
from contextlib import ExitStack
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("acquire", ROOT / "tools/tla-differential/acquire.py")
assert SPEC and SPEC.loader
acquire = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(acquire)


def digest(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def jar_bytes(module_content: bytes = b"---- MODULE Bags ----\n====\n") -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("tla2sany/StandardModules/Bags.tla", module_content)
    return buffer.getvalue()


def archive_bytes(root: str, files: list[tuple[str, bytes, int]]) -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        for name, content, mode in files:
            info = tarfile.TarInfo(f"{root}/{name}")
            info.size = len(content)
            info.mode = mode
            info.mtime = 0
            archive.addfile(info, io.BytesIO(content))
    return buffer.getvalue()


class SyntheticFixture:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.toolchain = root / "toolchain"
        self.store = root / "store"
        self.sources = root / "sources"
        self.sources.mkdir()
        self.sany_content = jar_bytes(b"---- MODULE Bags ----\nSANY ==== \n====\n")
        self.apalache_jar_content = jar_bytes(b"---- MODULE Bags ----\nApalache ==== \n====\n")
        self.launcher_content = b"#!/bin/sh\nexit 0\n"
        self.apalache_content = archive_bytes("apalache-0.61.0", [
            ("lib/apalache.jar", self.apalache_jar_content, 0o644),
            ("bin/apalache-mc", self.launcher_content, 0o755),
        ])
        self.sany_path = self.sources / "tla2tools-1.8.0.jar"
        self.apalache_path = self.sources / "apalache-0.61.0.tgz"
        self.apalache_jar_path = self.sources / "apalache.jar"
        self.sany_path.write_bytes(self.sany_content)
        self.apalache_path.write_bytes(self.apalache_content)
        self.apalache_jar_path.write_bytes(self.apalache_jar_content)
        self.sany_pin = {
            "url": "https://example.invalid/tla2tools-1.8.0.jar",
            "path": "downloads/tla2tools-1.8.0.jar",
            "sha256": digest(self.sany_content),
            "size": len(self.sany_content),
            "version": "SANY2 Version 2.2 created 08 July 2020",
            "standardLibrarySha256": acquire.standard_library_digest(self.sany_path),
        }
        self.apalache_pin = {
            "url": "https://example.invalid/apalache-0.61.0.tgz",
            "path": "downloads/apalache-0.61.0.tgz",
            "sha256": digest(self.apalache_content),
            "size": len(self.apalache_content),
            "archiveRoot": "apalache-0.61.0",
            "installPath": "apalache-0.61.0",
            "jarPath": "lib/apalache.jar",
            "jarSha256": digest(self.apalache_jar_content),
            "jarSize": len(self.apalache_jar_content),
            "launcherPath": "bin/apalache-mc",
            "launcherSha256": digest(self.launcher_content),
            "launcherSize": len(self.launcher_content),
            "standardLibrarySha256": acquire.standard_library_digest(self.apalache_jar_path),
        }

    def patches(self, stack: ExitStack, selected_runtime) -> None:
        stack.enter_context(patch.object(acquire, "TOOLCHAIN", self.toolchain))
        stack.enter_context(patch.object(acquire, "pins", return_value=(self.apalache_pin, self.sany_pin)))
        stack.enter_context(patch.object(acquire.shutil, "which", return_value="/selected/java"))
        stack.enter_context(patch.object(acquire.subprocess, "run", side_effect=selected_runtime))

    def populate_store(self) -> None:
        for pin, source in ((self.apalache_pin, self.apalache_path), (self.sany_pin, self.sany_path)):
            destination = acquire.store_object(self.store, pin["sha256"])
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)

    def target(self, pin: dict) -> Path:
        return self.toolchain / pin["path"]


class AcquireTests(unittest.TestCase):
    @staticmethod
    def selected_runtime(argv, **kwargs):
        if "-version" in argv:
            return subprocess.CompletedProcess(argv, 0, "", 'openjdk version "25.0.4"\nbuild 25.0.4+7\n')
        return subprocess.CompletedProcess(
            argv,
            0,
            "SANY\nhelp\nSANY2 Version 2.2 created 08 July 2020\n",
            "",
        )

    def test_jdk_identity_requires_exact_version_and_build(self) -> None:
        self.assertTrue(acquire.java_identity_matches(
            'openjdk version "25.0.4" 2026-01-01 LTS\nOpenJDK Runtime Environment (build 25.0.4+7-LTS)\n',
            "25.0.4",
            "25.0.4+7",
        ))
        for output in (
            'openjdk version "125.0.4"\nbuild 125.0.4+7\n',
            'openjdk version "25.0.4.1"\nbuild 25.0.4.1+1\n',
            'openjdk version "25.0.4"\nbuild 25.0.4+70\n',
            'openjdk version "25.0.4"\nbuild 25.0.40\n',
        ):
            with self.subTest(output=output):
                self.assertFalse(acquire.java_identity_matches(output, "25.0.4", "25.0.4+7"))

    def test_fresh_toolchain_restores_from_store_without_network(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = SyntheticFixture(Path(temporary))
            fixture.populate_store()
            with ExitStack() as stack:
                fixture.patches(stack, self.selected_runtime)
                stack.enter_context(patch.object(acquire, "download", side_effect=AssertionError("network used")))
                acquire.acquire(fixture.store, allow_network=False)
                acquire.verify_tools()
            self.assertEqual(fixture.target(fixture.sany_pin).read_bytes(), fixture.sany_content)
            self.assertEqual(fixture.target(fixture.apalache_pin).read_bytes(), fixture.apalache_content)
            distribution = fixture.toolchain / "apalache-0.61.0"
            self.assertEqual((distribution / "lib/apalache.jar").read_bytes(), fixture.apalache_jar_content)
            self.assertEqual((distribution / "bin/apalache-mc").read_bytes(), fixture.launcher_content)

    def test_missing_offline_store_entry_fails_without_creating_toolchain(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = SyntheticFixture(Path(temporary))
            fixture.store.mkdir()
            with ExitStack() as stack:
                fixture.patches(stack, self.selected_runtime)
                with self.assertRaisesRegex(SystemExit, "missing from the offline artifact store"):
                    acquire.acquire(fixture.store, allow_network=False)
            self.assertFalse(fixture.target(fixture.apalache_pin).exists())

    def test_truncated_store_object_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = SyntheticFixture(Path(temporary))
            cached = acquire.store_object(fixture.store, fixture.sany_pin["sha256"])
            cached.parent.mkdir(parents=True)
            cached.write_bytes(fixture.sany_content[:-1])
            with ExitStack() as stack:
                fixture.patches(stack, self.selected_runtime)
                with self.assertRaisesRegex(SystemExit, "size mismatch"):
                    acquire.acquire_artifact(fixture.sany_pin, fixture.store, allow_network=False)
            self.assertFalse(fixture.target(fixture.sany_pin).exists())

    def test_hash_mismatched_store_object_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = SyntheticFixture(Path(temporary))
            cached = acquire.store_object(fixture.store, fixture.sany_pin["sha256"])
            cached.parent.mkdir(parents=True)
            cached.write_bytes(b"x" * len(fixture.sany_content))
            with ExitStack() as stack:
                fixture.patches(stack, self.selected_runtime)
                with self.assertRaisesRegex(SystemExit, "sha256 mismatch"):
                    acquire.acquire_artifact(fixture.sany_pin, fixture.store, allow_network=False)
            self.assertFalse(fixture.target(fixture.sany_pin).exists())

    def test_corrupt_store_object_never_falls_back_to_network(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = SyntheticFixture(Path(temporary))
            cached = acquire.store_object(fixture.store, fixture.sany_pin["sha256"])
            cached.parent.mkdir(parents=True)
            cached.write_bytes(b"x" * len(fixture.sany_content))
            with ExitStack() as stack:
                fixture.patches(stack, self.selected_runtime)
                download = stack.enter_context(patch.object(acquire, "download"))
                with self.assertRaisesRegex(SystemExit, "sha256 mismatch"):
                    acquire.acquire_artifact(fixture.sany_pin, fixture.store, allow_network=True)
                download.assert_not_called()
            self.assertFalse(fixture.target(fixture.sany_pin).exists())

    def test_partial_download_leaves_no_target_or_store_object(self) -> None:
        for failure in (OSError("connection reset"), http.client.IncompleteRead(b"partial")):
            with self.subTest(failure=type(failure).__name__), tempfile.TemporaryDirectory() as temporary:
                fixture = SyntheticFixture(Path(temporary))

                def interrupted(url: str, destination: Path, *, expected_size=None, failure=failure) -> None:
                    destination.write_bytes(b"partial")
                    raise failure

                with ExitStack() as stack:
                    fixture.patches(stack, self.selected_runtime)
                    stack.enter_context(patch.object(acquire, "download", side_effect=interrupted))
                    with self.assertRaisesRegex(SystemExit, "download failed"):
                        acquire.acquire_artifact(fixture.sany_pin, fixture.store, allow_network=True)
                self.assertFalse(fixture.target(fixture.sany_pin).exists())
                self.assertFalse(acquire.store_object(fixture.store, fixture.sany_pin["sha256"]).exists())
                self.assertEqual(list(fixture.target(fixture.sany_pin).parent.glob("*partial*")), [])

    def test_download_enforces_pinned_size_before_excess_write(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = SyntheticFixture(Path(temporary))
            target = fixture.target(fixture.sany_pin)
            with patch.object(
                acquire.urllib.request, "urlopen",
                return_value=io.BytesIO(fixture.sany_content),
            ):
                acquire.download_to_toolchain(fixture.sany_pin, target)
            self.assertEqual(target.read_bytes(), fixture.sany_content)

            target.unlink()
            undersized_pin = {**fixture.sany_pin, "size": len(fixture.sany_content) - 1}
            with patch.object(
                acquire.urllib.request, "urlopen",
                return_value=io.BytesIO(fixture.sany_content),
            ), self.assertRaisesRegex(SystemExit, "exceeds pinned size"):
                acquire.download_to_toolchain(undersized_pin, target)
            self.assertFalse(target.exists())
            self.assertEqual(list(target.parent.glob("*download*")), [])

    def test_publication_preserves_concurrent_empty_destination(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = SyntheticFixture(Path(temporary))
            destination = fixture.toolchain / "apalache-0.61.0"
            rename = acquire.rename_noreplace

            def concurrent_create(source: Path, target: Path) -> None:
                target.mkdir()
                rename(source, target)

            with patch.object(acquire, "TOOLCHAIN", fixture.toolchain), \
                    patch.object(acquire, "rename_noreplace", side_effect=concurrent_create), \
                    self.assertRaises(SystemExit):
                acquire.extract_apalache(fixture.apalache_pin, fixture.apalache_path)
            self.assertTrue(destination.is_dir())
            self.assertEqual(list(destination.iterdir()), [])
            self.assertEqual(list(fixture.toolchain.glob(".apalache-0.61.0.partial-*")), [])

    def test_publication_accepts_concurrent_valid_distribution(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = SyntheticFixture(Path(temporary))
            destination = fixture.toolchain / "apalache-0.61.0"
            rename = acquire.rename_noreplace

            def concurrent_publish(source: Path, target: Path) -> None:
                (target / "lib").mkdir(parents=True)
                (target / "bin").mkdir()
                (target / "lib/apalache.jar").write_bytes(fixture.apalache_jar_content)
                (target / "bin/apalache-mc").write_bytes(fixture.launcher_content)
                rename(source, target)

            with patch.object(acquire, "TOOLCHAIN", fixture.toolchain), \
                    patch.object(acquire, "rename_noreplace", side_effect=concurrent_publish):
                acquire.extract_apalache(fixture.apalache_pin, fixture.apalache_path)
            self.assertEqual(
                (destination / "lib/apalache.jar").read_bytes(),
                fixture.apalache_jar_content,
            )
            self.assertEqual(
                (destination / "bin/apalache-mc").read_bytes(),
                fixture.launcher_content,
            )
            self.assertEqual(list(fixture.toolchain.glob(".apalache-0.61.0.partial-*")), [])

    def test_existing_local_artifact_is_never_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = SyntheticFixture(Path(temporary))
            fixture.populate_store()
            target = fixture.target(fixture.sany_pin)
            target.parent.mkdir(parents=True)
            target.write_bytes(b"local corrupt bytes")
            with ExitStack() as stack:
                fixture.patches(stack, self.selected_runtime)
                with self.assertRaises(SystemExit):
                    acquire.acquire_artifact(fixture.sany_pin, fixture.store, allow_network=False)
            self.assertEqual(target.read_bytes(), b"local corrupt bytes")

    def test_store_refuses_conflicting_existing_object(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = SyntheticFixture(Path(temporary))
            target = fixture.target(fixture.sany_pin)
            target.parent.mkdir(parents=True)
            target.write_bytes(fixture.sany_content)
            cached = acquire.store_object(fixture.store, fixture.sany_pin["sha256"])
            cached.parent.mkdir(parents=True)
            cached.write_bytes(b"different cached bytes")
            with ExitStack() as stack:
                fixture.patches(stack, self.selected_runtime)
                with self.assertRaisesRegex(SystemExit, "artifact-store object"):
                    acquire.acquire_artifact(fixture.sany_pin, fixture.store, allow_network=True)
            self.assertEqual(cached.read_bytes(), b"different cached bytes")
            self.assertEqual(target.read_bytes(), fixture.sany_content)

    def test_identical_existing_store_object_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = SyntheticFixture(Path(temporary))
            fixture.populate_store()
            cached = acquire.store_object(fixture.store, fixture.sany_pin["sha256"])
            before = cached.stat().st_mtime_ns
            with ExitStack() as stack:
                fixture.patches(stack, self.selected_runtime)
                self.assertFalse(acquire.atomic_install(fixture.sany_path, cached, fixture.sany_pin["sha256"], expected_size=fixture.sany_pin["size"]))
            self.assertEqual(cached.read_bytes(), fixture.sany_content)
            self.assertEqual(cached.stat().st_mtime_ns, before)

    def test_missing_extracted_distribution_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = SyntheticFixture(Path(temporary))
            for pin, source in ((fixture.apalache_pin, fixture.apalache_path), (fixture.sany_pin, fixture.sany_path)):
                target = fixture.target(pin)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
            with ExitStack() as stack:
                fixture.patches(stack, self.selected_runtime)
                with self.assertRaisesRegex(SystemExit, "extracted distribution is missing"):
                    acquire.verify_tools()

    def test_corrupt_extracted_jar_is_rejected_without_replacing_it(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = SyntheticFixture(Path(temporary))
            distribution = fixture.toolchain / "apalache-0.61.0"
            (distribution / "lib").mkdir(parents=True)
            (distribution / "bin").mkdir()
            (distribution / "lib/apalache.jar").write_bytes(b"corrupt")
            (distribution / "bin/apalache-mc").write_bytes(fixture.launcher_content)
            with ExitStack() as stack:
                fixture.patches(stack, self.selected_runtime)
                with self.assertRaises(SystemExit):
                    acquire.extract_apalache(fixture.apalache_pin, fixture.apalache_path)
            self.assertEqual((distribution / "lib/apalache.jar").read_bytes(), b"corrupt")

    def test_corrupt_extracted_launcher_is_rejected_without_replacing_it(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = SyntheticFixture(Path(temporary))
            distribution = fixture.toolchain / "apalache-0.61.0"
            (distribution / "lib").mkdir(parents=True)
            (distribution / "bin").mkdir()
            (distribution / "lib/apalache.jar").write_bytes(fixture.apalache_jar_content)
            (distribution / "bin/apalache-mc").write_bytes(b"x" * len(fixture.launcher_content))
            with ExitStack() as stack:
                fixture.patches(stack, self.selected_runtime)
                with self.assertRaisesRegex(SystemExit, "bin/apalache-mc"):
                    acquire.extract_apalache(fixture.apalache_pin, fixture.apalache_path)
            self.assertEqual((distribution / "bin/apalache-mc").read_bytes(), b"x" * len(fixture.launcher_content))

    def test_different_jdk_cannot_qualify_selected_tools(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = SyntheticFixture(Path(temporary))
            for pin, source in ((fixture.apalache_pin, fixture.apalache_path), (fixture.sany_pin, fixture.sany_path)):
                target = fixture.target(pin)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
            with patch.object(acquire, "TOOLCHAIN", fixture.toolchain):
                acquire.extract_apalache(fixture.apalache_pin, fixture.target(fixture.apalache_pin))
            with patch.object(acquire, "TOOLCHAIN", fixture.toolchain), \
                    patch.object(acquire, "pins", return_value=(fixture.apalache_pin, fixture.sany_pin)), \
                    patch.object(acquire.shutil, "which", return_value="/other/java"), \
                    patch.object(acquire.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "", 'openjdk version "25.0.4.1"\nbuild 25.0.4.1+1\n')):
                with self.assertRaisesRegex(SystemExit, "25.0.4\\+7 is required"):
                    acquire.verify_tools()

    def test_store_paths_are_digest_only(self) -> None:
        store = Path("/approved/store")
        self.assertEqual(acquire.store_object(store, "a" * 64), store / "sha256" / ("a" * 64))
        with self.assertRaisesRegex(SystemExit, "invalid artifact-store digest"):
            acquire.store_object(store, "../escape")


if __name__ == "__main__":
    unittest.main()
