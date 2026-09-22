import hashlib
import io
import json
import tarfile
import tempfile
import unittest
from pathlib import Path

from distribution_lib import extract_selected_node, extract_selected_tree
from build import copy_gate_operator_closure, write_reference_project
from manifest_check import ContractError
from verify import safe_extract_regular


def duplicate_archive(path: Path, name: str) -> None:
    with tarfile.open(path, "w:gz") as archive:
        for payload in (b"one", b"two"):
            info = tarfile.TarInfo(name)
            info.size = len(payload)
            archive.addfile(info, io.BytesIO(payload))


class ArchiveBoundsTests(unittest.TestCase):
    def test_reference_projects_pin_compiler_and_fixed_faulty_adapter(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            application = root / "application"
            for relative in ("examples/work-queue/artifacts/witness.itf.json",
                    "dist-validation/examples/work-queue/artifacts/bundle/WorkQueue.suite.js"):
                path = application / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(relative)
            server = root / "ModelMirrors"; server.write_bytes(b"server")
            compiler = root / "model_interface_gen"; compiler.write_bytes(b"compiler")
            package = root / "package"; package.mkdir()
            (package / "package.json").write_text('{"name":"mirrorecma","version":"2.0.0"}')
            write_reference_project(application, server, compiler, package)
            project = application / "reference-project"
            lock = json.loads((project / "mirror.toolchain.json").read_text())
            self.assertEqual(lock["tools"]["compiler"]["sha256"],
                hashlib.sha256(b"compiler").hexdigest())
            self.assertEqual(lock["tools"]["compiler"]["capabilities"],
                ["bundle-v1", "check-bundle-v1", "preflight-v1"])
            correct = json.loads((project / "mirror.correct.project.json").read_text())
            faulty = json.loads((project / "mirror.faulty.project.json").read_text())
            self.assertEqual(correct["implementation"]["module"], "reference-correct-adapter.mjs")
            self.assertEqual(faulty["implementation"]["module"], "reference-faulty-adapter.mjs")
            self.assertIn("enqueue-drops", (project / "reference-faulty-adapter.mjs").read_text())

    def test_gate_operator_closure_preserves_relocated_root_layout(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            for relative in ("supervisor/mirrorgate", "runtimes/node", "sdk/node", "protocol"):
                path = source / relative
                path.mkdir(parents=True)
                (path / "payload").write_text(relative)
            (source / "sdk/compatibility.json").write_text("{}")
            (source / "package.json").write_text("{}")
            agent_host = source / "integrations/agent-host"
            agent_host.mkdir(parents=True)
            (agent_host / "index.mjs").write_text("export {}")
            destination = root / "operator"
            copy_gate_operator_closure(source, destination)
            self.assertEqual({path.relative_to(destination).as_posix()
                for path in destination.rglob("*") if path.is_file()}, {
                    "mirrorgate-runtime/package.json",
                    "mirrorgate-runtime/runtimes/node/payload",
                    "mirrorgate-runtime/sdk/node/payload",
                    "mirrorgate-runtime/sdk/compatibility.json",
                    "mirrorgate-runtime/integrations/agent-host/index.mjs",
                    "mirrorgate-supervisor/mirrorgate/payload", "protocol/payload",
                })

    def test_duplicate_members_rejected_by_generic_extractor(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "duplicate.tar.gz"
            duplicate_archive(archive, "package/file.js")
            with self.assertRaisesRegex(ContractError, "duplicate"):
                safe_extract_regular(archive, root / "out")

    def test_duplicate_selected_node_member_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "node.tar.gz"
            duplicate_archive(archive, "node/bin/node")
            with self.assertRaisesRegex(ValueError, "duplicate"):
                extract_selected_node(archive, root / "out", "node", ["bin/node"])

    def test_selected_fresh_runtime_tree_is_materialized(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "java.tar.gz"
            with tarfile.open(archive, "w:gz") as output:
                for name, payload in [("jdk/release", b"JAVA_VERSION=25"),
                    ("jdk/bin/java", b"java"), ("jdk/lib/modules", b"modules")]:
                    info = tarfile.TarInfo(name); info.size = len(payload); info.mode = 0o755 if name.endswith("java") else 0o644
                    output.addfile(info, io.BytesIO(payload))
            extract_selected_tree(archive, root / "selected", "jdk", ["release"], ["bin", "lib"])
            self.assertEqual((root / "selected/bin/java").read_bytes(), b"java")
            self.assertEqual((root / "selected/lib/modules").read_bytes(), b"modules")


if __name__ == "__main__":
    unittest.main()
