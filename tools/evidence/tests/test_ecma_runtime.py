"""Admission uses the complete prepared SDK and an explicitly pinned Node."""
import importlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/interop"))


class EcmaRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.binding = importlib.import_module("ecma_runtime")
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.runtime = self.base / "sdk"
        (self.runtime / "dist").mkdir(parents=True)
        (self.runtime / "dist/index.js").write_text("export const version = 1;\n")
        (self.runtime / "package.json").write_text('{"type":"module"}\n')
        self.node = self.base / "node"
        self.node.write_bytes(b"prepared executable\n")
        self.node.chmod(0o700)
        self.pin = self.base / "pin.json"
        self.ref = "a" * 40
        self.value = {"schema": "mirrors.interop-ecma-runtime/v1", "sourceRevision": self.ref,
            "sourceArchiveSha256": "b" * 64, "sourceTree": "c" * 40,
            "compiler": {"version": "5.9.3", "tree": self.binding.runtime_tree(self.runtime)},
            "node": self.binding.node_identity(self.node),
            "runtime": self.binding.runtime_tree(self.runtime)}
        self.pin.write_text(json.dumps(self.value))

    def verify(self):
        return self.binding.verify_runtime(self.runtime, self.node, self.pin, self.ref)

    def test_stable_binding_and_sanitized_node_environment(self):
        self.assertEqual(self.verify(), self.verify())
        env = self.binding.node_environment({"NODE_OPTIONS": "ambient-options", "NODE_PATH": "/ambient", "KEEP": "yes"})
        self.assertEqual(env, {"KEEP": "yes"})

    def test_stale_or_incomplete_runtime_is_rejected(self):
        for relative in ["dist/index.js", "package.json", "dist/unrecorded.js"]:
            with self.subTest(path=relative):
                path = self.runtime / relative
                old = path.read_bytes() if path.exists() else None
                path.write_bytes(b"changed runtime\n")
                with self.assertRaisesRegex(ValueError, "runtime"):
                    self.verify()
                if old is None:
                    path.unlink()
                else:
                    path.write_bytes(old)

    def test_node_and_source_revision_must_match_before_execution(self):
        self.node.write_bytes(b"another executable\n")
        with self.assertRaisesRegex(ValueError, "Node"):
            self.verify()
        self.node.write_bytes(b"prepared executable\n")
        self.value["sourceRevision"] = "d" * 40
        self.pin.write_text(json.dumps(self.value))
        with self.assertRaisesRegex(ValueError, "revision"):
            self.verify()

    def test_post_execution_check_detects_changes(self):
        before = self.verify()
        (self.runtime / "dist/index.js").write_text("export const version = 2;\n")
        with self.assertRaises(ValueError):
            self.verify()
        self.assertEqual(before["runtime"], self.value["runtime"])

    def test_manifest_schema_is_required(self):
        self.value["schema"] = "unknown/v0"
        self.pin.write_text(json.dumps(self.value))
        with self.assertRaisesRegex(ValueError, "schema"):
            self.verify()
