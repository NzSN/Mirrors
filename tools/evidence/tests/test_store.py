from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


EVIDENCE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVIDENCE))

import finalize  # noqa: E402
import retain_source_package  # noqa: E402
import store  # noqa: E402
import verify  # noqa: E402


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.repository = self.root / "repository"
        self.repository.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repository)], check=True)
        subprocess.run(["git", "-C", str(self.repository), "config", "user.email", "fixture@example.invalid"], check=True)
        subprocess.run(["git", "-C", str(self.repository), "config", "user.name", "Fixture"], check=True)
        subprocess.run(["git", "-C", str(self.repository), "remote", "add", "origin", "https://example.invalid/Mirrors.git"], check=True)
        (self.repository / "source.txt").write_text("source\n", encoding="utf-8")
        catalog = self.repository / "catalog"
        catalog.mkdir()
        (catalog / "framework-catalog.json").write_text("{}\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(self.repository), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.repository), "commit", "-qm", "fixture"], check=True)
        self.store = self.root / "store"
        self.registry = self.root / "commands.json"
        self.registry.write_text(json.dumps({
            "schemaVersion": "mirrors.evidence-command-registry/v1",
            "commands": [{
                "commandId": "fixture.command",
                "tierId": "fixture.required",
                "requirement": "required",
                "argvPrefix": [sys.executable],
                "defaultTimeoutSeconds": 10,
                "catalogComponentId": "fixture",
                "catalogPath": "catalog/framework-catalog.json",
            }],
        }), encoding="utf-8")

    def tearDown(self):
        self.temporary.cleanup()

    def collect(self, program: str = "print('ok')") -> Path:
        result = subprocess.run([
            sys.executable, str(EVIDENCE / "collect.py"),
            "--store", str(self.store), "--registry", str(self.registry),
            "--command-id", "fixture.command", "--cwd", str(self.repository),
            "--component", f"fixture={self.repository}", "--",
            sys.executable, "-c", program,
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        staging = list((self.store / "staging").iterdir())
        self.assertEqual(len(staging), 1)
        return staging[0]

    def finalized(self) -> tuple[Path, Path, dict]:
        staging = self.collect()
        bundle, result = finalize.finalize(staging, self.store)
        return staging, bundle, result

    def test_finalize_and_verify_after_scratch_removal(self):
        staging, bundle, finalized = self.finalized()
        shutil.rmtree(staging)
        result = verify.verify(bundle, finalized["privateRunRef"]["envelopeSha256"])
        self.assertEqual(result["status"], "verified")
        self.assertEqual(result["integrity"], "sha256-membership-verified")
        self.assertEqual(result["executionProvenance"], "not-established-by-hashes")

    def test_finalized_payload_does_not_share_staging_inode(self):
        staging, bundle, _ = self.finalized()
        staged = staging / "artifacts/private/stdout.log"
        retained = bundle / "artifacts/private/stdout.log"
        self.assertNotEqual(staged.stat().st_ino, retained.stat().st_ino)
        staged.write_bytes(b"mutated staging")
        os.chmod(staged, 0o600)
        self.assertEqual(retained.read_bytes(), b"ok\n")
        self.assertEqual(verify.verify(bundle)["status"], "verified")

    def test_index_is_commit_marker(self):
        _, bundle, _ = self.finalized()
        (bundle / "bundle-index.json").unlink()
        with self.assertRaisesRegex(ValueError, "committed index is absent"):
            verify.verify(bundle)

    def test_missing_and_changed_payload_are_detected(self):
        _, bundle, _ = self.finalized()
        stdout = bundle / "artifacts/private/stdout.log"
        stdout.unlink()
        with self.assertRaises((OSError, ValueError)):
            verify.verify(bundle)

        self.tearDown()
        self.setUp()
        _, bundle, _ = self.finalized()
        stdout = bundle / "artifacts/private/stdout.log"
        stdout.write_bytes(b"tampered")
        os.chmod(stdout, 0o600)
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            verify.verify(bundle)

    def test_index_tampering_is_detected_against_envelope(self):
        _, bundle, _ = self.finalized()
        index_path = bundle / "bundle-index.json"
        index = json.loads(index_path.read_text())
        index["runId"] = "tampered-run"
        index_path.write_bytes(finalize.canonical_json(index))
        os.chmod(index_path, 0o600)
        with self.assertRaisesRegex(ValueError, "runId differs"):
            verify.verify(bundle)

    def test_expected_run_ref_detects_rewritten_structural_records(self):
        _, bundle, finalized = self.finalized()
        with self.assertRaisesRegex(ValueError, "expected runRef digest"):
            verify.verify(bundle, "0" * 64)
        self.assertEqual(verify.verify(bundle)["privateRunRef"], finalized["privateRunRef"])

    def test_staging_symlink_is_rejected(self):
        staging = self.collect()
        stdout = staging / "artifacts/private/stdout.log"
        stdout.unlink()
        stdout.symlink_to(self.repository / "source.txt")
        with self.assertRaisesRegex(ValueError, "not a regular file"):
            finalize.finalize(staging, self.store)

    def test_traversal_and_destination_collision_are_rejected(self):
        staging = self.collect()
        envelope_path = staging / "envelope.staging.json"
        envelope = json.loads(envelope_path.read_text())
        envelope["artifacts"][0]["location"]["path"] = "artifacts/private/../escape"
        envelope_path.write_bytes(finalize.canonical_json(envelope))
        os.chmod(envelope_path, 0o600)
        with self.assertRaisesRegex(ValueError, "invalid staging envelope"):
            finalize.finalize(staging, self.store)

        self.tearDown()
        self.setUp()
        staging, _, _ = self.finalized()
        with self.assertRaises(FileExistsError):
            finalize.finalize(staging, self.store)

    def test_owner_permissions_are_verified(self):
        _, bundle, _ = self.finalized()
        os.chmod(bundle, 0o755)
        with self.assertRaisesRegex(ValueError, "owner-only permissions"):
            verify.verify(bundle)

    def test_symlinked_runs_directory_is_rejected_without_following(self):
        staging = self.collect()
        outside = self.root / "outside"
        outside.mkdir(mode=0o700)
        (self.store / "runs").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(OSError):
            finalize.finalize(staging, self.store)
        self.assertEqual(list(outside.iterdir()), [])

    def test_regular_reader_rejects_fifo_and_max_plus_one(self):
        fifo = self.root / "record.fifo"
        os.mkfifo(fifo, 0o600)
        with self.assertRaisesRegex(ValueError, "not a regular file"):
            store.read_regular(fifo, max_bytes=4)
        record = self.root / "record.bin"
        record.write_bytes(b"12345")
        with self.assertRaisesRegex(ValueError, "exceeds 4 bytes"):
            store.read_regular(record, max_bytes=4)

    def test_duplicate_key_in_staging_is_rejected(self):
        staging = self.collect()
        envelope = staging / "envelope.staging.json"
        text = envelope.read_text()
        text = text.replace('"runId":', '"runId":"duplicate","runId":', 1)
        envelope.write_text(text)
        os.chmod(envelope, 0o600)
        with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
            finalize.finalize(staging, self.store)

    def test_verifier_parses_each_structural_buffer_without_rereading(self):
        _, bundle, _ = self.finalized()
        calls: list[str] = []
        real = verify.read_regular

        def observed(path, *args, **kwargs):
            calls.append(Path(path).name)
            return real(path, *args, **kwargs)

        with mock.patch.object(verify, "read_regular", side_effect=observed):
            self.assertEqual(verify.verify(bundle)["status"], "verified")
        self.assertEqual(calls.count("envelope.json"), 1)
        self.assertEqual(calls.count("public-summary.json"), 1)

    def test_payload_directories_are_synced_before_index_publication(self):
        staging = self.collect()
        events: list[str] = []
        real_sync = finalize.fsync_directory
        real_publish = finalize.publish_exclusive

        def synced(path):
            events.append(f"fsync:{Path(path).name}")
            return real_sync(path)

        def published(*args, **kwargs):
            events.append("publish:index")
            return real_publish(*args, **kwargs)

        with mock.patch.object(finalize, "fsync_directory", side_effect=synced), mock.patch.object(
            finalize, "publish_exclusive", side_effect=published
        ):
            finalize.finalize(staging, self.store)
        publish_index = events.index("publish:index")
        self.assertLess(events.index("fsync:private"), publish_index)
        self.assertLess(events.index("fsync:artifacts"), publish_index)
        self.assertTrue(any(event.startswith("fsync:run-") for event in events[:publish_index]), events)

    def test_verifier_rejects_declared_aggregate_before_opening_missing_payloads(self):
        _, bundle, _ = self.finalized()
        index_path = bundle / "bundle-index.json"
        index = json.loads(index_path.read_text())
        for number in range(9):
            index["records"].append({
                "role": "payload",
                "artifactId": f"oversize-{number}",
                "path": f"artifacts/private/missing-{number}.bin",
                "bytes": 64 * 1024 * 1024,
                "sha256": "0" * 64,
                "visibility": "private",
                "required": False,
            })
        index_path.write_bytes(finalize.canonical_json(index))
        os.chmod(index_path, 0o600)
        with self.assertRaisesRegex(ValueError, "bundle exceeds 512 MiB"):
            verify.verify(bundle)

    def test_historical_source_package_is_retained_without_e1_claim(self):
        package = self.root / "historical-package"
        package.mkdir()
        (package / "producer.log").write_text("historical output\n")
        referenced = self.root / "historical-source"
        referenced.mkdir()
        source = referenced / "Model.tla"
        source.write_text("---- MODULE Model ----\n====\n")
        digest = __import__("hashlib").sha256(source.read_bytes()).hexdigest()
        manifest = package / "sha256sums.txt"
        manifest.write_text(f"{digest}  {source}\n")
        destination, index = retain_source_package.retain(
            package, manifest, referenced, self.root / "retained", "historical-fixture"
        )
        self.assertEqual(index["status"], "historical-unqualified")
        self.assertIn("no-selected-framework-catalog", index["limitations"])
        self.assertEqual((destination / "files/referenced/Model.tla").read_bytes(), source.read_bytes())
        self.assertEqual((destination / "source-package-index.json").stat().st_mode & 0o777, 0o600)
        with self.assertRaisesRegex(ValueError, "bounded opaque identifier"):
            retain_source_package.retain(package, manifest, referenced, self.root / "bad-retained", "../escape")

    def test_public_projection_rejects_canary_in_any_free_text(self):
        subprocess.run([
            "git", "-C", str(self.repository), "remote", "set-url", "origin",
            "https://example.invalid/MIRRORS_PRIVATE_CANARY_REPOSITORY",
        ], check=True)
        staging = self.collect()
        with self.assertRaisesRegex(ValueError, "private canary"):
            finalize.finalize(staging, self.store)

    def test_changing_source_collection_cannot_finalize(self):
        staging = self.collect("from pathlib import Path; Path('source.txt').write_text('changed\\n')")
        with self.assertRaisesRegex(ValueError, "changing component checkout"):
            finalize.finalize(staging, self.store)

    def test_files_are_owner_only_and_public_projection_has_no_private_fields(self):
        _, bundle, _ = self.finalized()
        for path in bundle.rglob("*"):
            mode = path.stat().st_mode & 0o777
            self.assertEqual(mode, 0o700 if path.is_dir() else 0o600, path)
        summary = json.loads((bundle / "public-summary.json").read_text())
        rendered = json.dumps(summary)
        self.assertNotIn("workingDirectory", rendered)
        self.assertNotIn("privateMetadata", rendered)
        self.assertNotIn("argv", rendered)


if __name__ == "__main__":
    unittest.main()
