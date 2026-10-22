from __future__ import annotations

import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import release


class ReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="mirrors-release-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        (self.source / "Shell").mkdir(parents=True)
        (self.source / "Shell/Version.lean").write_text('def version : String := "1.2.3"\n')
        (self.source / "lean-toolchain").write_text("leanprover/lean4:v4.33.0\n")
        (self.source / "lake-manifest.json").write_text('{}\n')
        (self.source / ".gitignore").write_text('/.lake\n')
        self.git("init", "-q")
        self.git("add", ".")
        self.commit()
        self.git("tag", "-a", "v1.2.3", "-m", "release test")

    def git(self, *args: str) -> str:
        return subprocess.check_output([
            "git", "-c", "user.name=Release Test", "-c", "user.email=release@example.invalid",
            *args], cwd=self.source, text=True, stderr=subprocess.STDOUT).strip()

    def commit(self) -> None:
        self.git("commit", "-qm", "release fixture")

    def test_future_tag_requires_matching_clean_tagged_source(self) -> None:
        metadata = release.identity(self.source, "v1.2.3")
        self.assertEqual(metadata["commit"], self.git("rev-parse", "HEAD"))
        self.assertFalse(metadata["historical"])
        self.assertEqual(metadata["expectedVersionOutput"], "v1.2.3\n")
        (self.source / "unexpected.txt").write_text("untracked source")
        with self.assertRaisesRegex(ValueError, "clean"):
            release.identity(self.source, "v1.2.3")

    def test_version_mismatch_and_unmatched_commit_are_refused(self) -> None:
        self.git("tag", "v1.2.4")
        with self.assertRaisesRegex(ValueError, "embedded product version"):
            release.identity(self.source, "v1.2.4")
        (self.source / "extra.txt").write_text("another source commit")
        self.git("add", ".")
        self.commit()
        with self.assertRaisesRegex(ValueError, "does not match the requested tag"):
            release.identity(self.source, "v1.2.3")

    def test_historical_exceptions_are_full_sha_bound(self) -> None:
        for tag, (commit, embedded, output) in release.HISTORICAL.items():
            with self.subTest(tag=tag):
                self.assertRegex(commit, r"^[0-9a-f]{40}$")
                version = self.source / "Shell/Version.lean"
                if embedded is None:
                    version.unlink(missing_ok=True)
                else:
                    version.write_text(f'def version : String := "{embedded}"\n')
                with patch.object(release, "git", side_effect=[commit, commit, ""]):
                    metadata = release.identity(self.source, tag)
                self.assertEqual(metadata["expectedVersionOutput"], output)
                self.assertTrue(metadata["historical"])
                changed = "0" * 40
                with patch.object(release, "git", side_effect=[changed, changed, ""]):
                    with self.assertRaisesRegex(ValueError, "source identity changed"):
                        release.identity(self.source, tag)

    def test_tag_validation_blocks_injection_and_nonrelease_names(self) -> None:
        for tag in ("main", "refs/tags/v1.2.3", "v1.2.3\ntag=main", "v1.2.3;id",
                    "v01.2.3", "v1.2.3.4", "v1.2.3-rc.01", "v1.2.3/../../main"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.validate_tag(tag)
        for tag in ("v1.2.3", "v1.2.3-rc.1", "v1.2.3-BETA.2", *release.HISTORICAL):
            self.assertEqual(release.validate_tag(tag), tag)

    def test_model_and_loader_environment_is_removed(self) -> None:
        overrides = {key: "untrusted" for key in
                     ("APALACHE_MC", "APALACHE_JAR", "TLA2TOOLS_JAR", "LD_LIBRARY_PATH", "LD_PRELOAD")}
        with patch.dict(os.environ, overrides), patch.object(subprocess, "run") as call:
            release.run(["true"], self.source)
        self.assertFalse(overrides.keys() & call.call_args.kwargs["env"].keys())

    def test_runtime_closure_refuses_missing_or_toolchain_libraries(self) -> None:
        for output in ("libssl.so.3 => not found\n",
                       "libleanshared.so => /opt/lean/lib/libleanshared.so (0x123)\n"):
            with self.subTest(output=output), patch.object(release, "run", return_value=
                    subprocess.CompletedProcess([], 0, output, "")):
                with self.assertRaises(ValueError):
                    release.runtime_libraries(self.source / "mirror")

    def test_remote_tag_recheck_handles_annotated_and_lightweight_tags(self) -> None:
        commit = "a" * 40
        ref = "refs/tags/v1.2.3"
        for output in (f"{commit}\t{ref}\n",
                       f"{'b' * 40}\t{ref}\n{commit}\t{ref}^{{}}\n"):
            with patch.object(release, "run", return_value=subprocess.CompletedProcess([], 0, output, "")):
                release.verify_remote("NzSN/Mirrors", "v1.2.3", commit)
                with self.assertRaisesRegex(ValueError, "no longer identifies"):
                    release.verify_remote("NzSN/Mirrors", "v1.2.3", "c" * 40)

    def test_archive_rejects_traversal_and_links(self) -> None:
        archive = self.root / "unsafe.tar.gz"
        with tarfile.open(archive, "w:gz") as handle:
            entry = tarfile.TarInfo("../escape")
            entry.size = 1
            handle.addfile(entry, io.BytesIO(b"x"))
        with self.assertRaisesRegex(ValueError, "unexpected archive contents"):
            release.check_archive(archive, "v1.2.3")
        self.assertFalse((self.root / "escape").exists())
        name = "mirrors-v1.2.3-linux-x86_64"
        with tarfile.open(archive, "w:gz") as handle:
            for path in (name, f"{name}/bin", f"{name}/README.txt", f"{name}/BUILD.json",
                         f"{name}/bin/mirror", f"{name}/bin/model_interface_gen"):
                entry = tarfile.TarInfo(path)
                if path.endswith("/mirror"):
                    entry.type = tarfile.SYMTYPE
                    entry.linkname = "/bin/sh"
                handle.addfile(entry)
        with self.assertRaisesRegex(ValueError, "regular files and directories"):
            release.check_archive(archive, "v1.2.3")

    def test_publication_is_drafted_and_failed_upload_never_publishes(self) -> None:
        tools = self.root / "publication-tools"
        tools.mkdir()
        log = self.root / "gh-calls.jsonl"
        gh = tools / "gh"
        gh.write_text(
            '#!/usr/bin/env python3\nimport json,os,sys\n'
            'with open(os.environ["GH_CALL_LOG"],"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n'
            'command=sys.argv[2]\n'
            'if command=="view": sys.exit(0 if os.environ.get("EXISTING_RELEASE")=="1" else 1)\n'
            'if command=="create" and os.environ.get("UPLOAD_FAILURE")=="1": sys.exit(1)\n')
        gh.chmod(0o755)
        git = tools / "git"
        git.write_text('#!/bin/sh\nprintf "%s\\trefs/tags/%s\\n" "$SOURCE_COMMIT" "$RELEASE_TAG"\n')
        git.chmod(0o755)
        assets = self.root / "artifacts"
        assets.mkdir()
        payload = assets / "payload"
        payload.write_bytes(b"checksum fixture")
        (assets / "SHA256SUMS").write_text(f"{release.digest(payload)}  payload\n")
        script = Path(release.__file__).with_name("publish.sh")
        env = {**os.environ, "PATH": f"{tools}:{os.environ['PATH']}",
               "RELEASE_TAG": "v1.2.3", "SOURCE_COMMIT": "a" * 40,
               "GH_REPO": "NzSN/Mirrors", "GH_TOKEN": "fixture-token", "GH_CALL_LOG": str(log)}
        for historical, prerelease, failure, existing in (
                ("false", "false", "0", "0"), ("true", "false", "0", "0"),
                ("false", "true", "0", "0"), ("false", "false", "1", "0"),
                ("false", "false", "0", "1")):
            with self.subTest(historical=historical, prerelease=prerelease, failure=failure, existing=existing):
                log.unlink(missing_ok=True)
                result = subprocess.run(["bash", str(script), str(assets)], cwd=self.root,
                                        env={**env, "HISTORICAL": historical, "PRERELEASE": prerelease,
                                             "UPLOAD_FAILURE": failure, "EXISTING_RELEASE": existing},
                                        capture_output=True, text=True)
                calls = [json.loads(line) for line in log.read_text().splitlines()]
                if existing == "1":
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual([call[1] for call in calls], ["view"])
                    continue
                create = calls[1]
                self.assertEqual(create[1], "create")
                self.assertIn("--draft", create)
                self.assertIn("--latest=false", create)
                self.assertNotIn("--latest", create)
                if failure == "1":
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("edit", [call[1] for call in calls])
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    edit = calls[2]
                    self.assertIn("--draft=false", edit)
                    latest = "--latest=false" if historical == "true" or prerelease == "true" else "--latest"
                    self.assertIn(latest, edit)
                    self.assertEqual("--prerelease" in edit, prerelease == "true")

    @unittest.skipUnless(shutil.which("cc") and shutil.which("ldd"), "native fixture compiler required")
    def test_packaged_native_clis_relocate_with_verified_checksums(self) -> None:
        # Real native executables exercise archive permissions, loader closure,
        # relocation, checksums and CLI failures. They are tooling fixtures,
        # not substitutes for Mirrors' Lean regression gates in hosted CI.
        binary_dir = self.source / ".lake/build/bin"
        binary_dir.mkdir(parents=True)
        for name, body in {
            "mirror": 'if (argc > 1) { puts("v1.2.3"); } else { puts("{\\"proto_step\\":\\"protocol_error\\"}"); } return 0;',
            "model_interface_gen": 'fputs("usage: model_interface_gen\\n", stderr); return 2;',
        }.items():
            source_file = self.root / f"{name}.c"
            source_file.write_text(f"#include <stdio.h>\nint main(int argc, char **argv) {{ {body} }}\n")
            subprocess.run(["cc", str(source_file), "-o", str(binary_dir / name)], check=True)
        for gate in release.GATES:
            path = binary_dir / gate
            path.write_text("#!/bin/sh\nexit 0\n")
            path.chmod(0o755)
        tool_bin = self.root / "tool-bin"
        tool_bin.mkdir()
        lake = tool_bin / "lake"
        lake.write_text("#!/bin/sh\nif [ \"$1\" = --version ]; then echo 'fixture lake'; fi\n")
        lake.chmod(0o755)
        output = self.root / "dist"
        with patch.dict(os.environ, {"PATH": f"{tool_bin}:{os.environ['PATH']}"}):
            metadata = release.build(self.source, "v1.2.3", output)
        archive = output / "mirrors-v1.2.3-linux-x86_64.tar.gz"
        release.check_archive(archive, "v1.2.3")
        self.assertEqual(metadata["passedGates"][-1], "relocated-binary-cli-smoke")
        for line in (output / "SHA256SUMS").read_text().splitlines():
            checksum, filename = line.split("  ")
            self.assertEqual(release.digest(output / filename), checksum)
        manifest = json.loads((output / "mirrors-v1.2.3-linux-x86_64.build.json").read_text())
        self.assertEqual(manifest["commit"], self.git("rev-parse", "HEAD"))
        self.assertIn("no live model qualification", manifest["qualification"])
        # A tampered binary inside an otherwise valid archive is rejected.
        expanded = self.root / "expanded"
        with tarfile.open(archive, "r:gz") as handle:
            handle.extractall(expanded, filter="data")
        package = expanded / "mirrors-v1.2.3-linux-x86_64"
        (package / "bin/mirror").write_bytes(b"changed")
        with tarfile.open(archive, "w:gz") as handle:
            handle.add(package, arcname=package.name)
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            release.check_archive(archive, "v1.2.3")


if __name__ == "__main__":
    unittest.main()
