"""Admission failures must precede contact with the remote oracle."""
import copy
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

s = importlib.util.spec_from_file_location("remote_probe", Path(__file__).parents[1] / "run_remote_model_check.py")
remote = importlib.util.module_from_spec(s)
s.loader.exec_module(remote)

class RemoteObservationTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.TemporaryDirectory()
        self.addCleanup(self.root.cleanup)
        self.path = Path(self.root.name) / "observation.json"
        self.pin, self.binary, self.source = "a" * 64, "b" * 64, "c" * 40
        self.value = {
            "schema": "mirrors.windows-deployment-observation/v1",
            "endpoint": {"host": remote.HOST, "port": int(remote.PORT)},
            "deploymentMode": "owned-native-console", "processId": 42,
            "binarySha256": self.binary, "sourceBaseRevision": self.source,
            "mtls": {"serverLeafSha256": self.pin},
            "sourceTreeSha256": "d" * 64, "sourceManifestSha256": "e" * 64,
            "runtimeManifestSha256": "f" * 64,
            "observedAt": datetime.now(timezone.utc).isoformat(),
            "processCreatedAt": "2026-01-01T00:00:00Z",
            "runtime": {
                "apalacheVersion": remote.APALACHE_VERSION,
                "apalacheArchiveSha256": remote.APALACHE_ARCHIVE_SHA256,
                "apalacheJarSha256": remote.APALACHE_JAR_SHA256,
                "javaVersion": remote.JAVA_OBSERVED_VERSION,
                "javaArchiveSha256": remote.JAVA_ARCHIVE_SHA256,
                "javaExecutableSha256": remote.JAVA_EXECUTABLE_SHA256,
            },
        }
    def admit(self, value):
        self.path.write_text(json.dumps(value))
        return remote.validate_observation(self.path, self.pin, self.binary, self.source)
    def test_selected_console_identity_passes(self):
        self.assertEqual(len(self.admit(self.value)), 64)
    def test_old_or_altered_runtime_is_rejected(self):
        for key in self.value["runtime"]:
            value = copy.deepcopy(self.value)
            value["runtime"][key] = "wrong"
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "runtime"):
                self.admit(value)
    def test_endpoint_process_binary_source_and_pin_are_bound(self):
        for key, replacement in [("endpoint", {"host": "192.168.150.219", "port": 8999}),
                ("processId", 0), ("processId", True), ("deploymentMode", "unowned"),
                ("binarySha256", "0" * 64), ("sourceBaseRevision", "0" * 40),
                ("mtls", {"serverLeafSha256": "0" * 64})]:
            value = {**self.value, key: replacement}
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "identity"):
                self.admit(value)
    def test_stale_future_and_invalid_lifetime_are_rejected(self):
        for key, stamp in [("observedAt", "2020-01-01T00:00:00Z"),
                ("observedAt", "2100-01-01T00:00:00Z"),
                ("processCreatedAt", "2100-01-01T00:00:00Z"),
                ("observedAt", "2026-01-01T00:00:00")]:
            value = {**self.value, key: stamp}
            with self.subTest(key=key), self.assertRaises(ValueError): self.admit(value)
    def test_non_regular_oversized_and_invalid_digest_are_rejected(self):
        self.path.write_bytes(b" " * (1024 * 1024 + 1))
        with self.assertRaisesRegex(ValueError, "bounded regular"):
            remote.validate_observation(self.path, self.pin, self.binary, self.source)
        link = Path(self.root.name) / "link.json"
        link.symlink_to(self.path)
        with self.assertRaisesRegex(ValueError, "bounded regular"):
            remote.validate_observation(link, self.pin, self.binary, self.source)
        with self.assertRaisesRegex(ValueError, "digest"):
            self.admit({**self.value, "sourceTreeSha256": "bad"})
