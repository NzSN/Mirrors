import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

import refresh_identity
from manifest_check import digest_json


class LockProductPropagationTests(unittest.TestCase):
    def test_update_locks_assigns_product_by_component_id(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary) / "repo"
            root = repository / "distribution" / "locks"
            (root / "fixtures").mkdir(parents=True)
            catalog_path = repository / "catalog" / "framework-catalog.json"
            catalog_path.parent.mkdir(parents=True)
            catalog = {
                "components": [
                    {"componentRef": {"componentId": "mirrors"},
                     "product": {"name": "Mirrors", "version": "0.1.1"}},
                    {"componentRef": {"componentId": "mirrorecma"},
                     "product": {"name": "mirrorecma", "version": "0.1.0"}},
                ],
                "combinations": [{
                    "combinationId": "candidate.local-node-checked",
                    "componentIds": ["mirrorecma", "mirrors"],
                }],
            }
            catalog_path.write_text(json.dumps(catalog))
            (root / "profiles.json").write_text(json.dumps({
                "catalogSelectionRef": {},
                "profiles": [{
                    "profileId": "checked-replay-local",
                    "combinationId": "candidate.local-node-checked",
                }],
            }))
            (root / "component-lock.json").write_text(json.dumps({
                "catalogSelectionRef": {},
                "components": [
                    {"componentRef": {"componentId": "mirrorecma", "revision": "old-ecma"},
                     "product": {"name": "mirrorecma", "version": "2.0.0"}},
                    {"componentRef": {"componentId": "mirrors", "revision": "old-mirrors"},
                     "product": {"name": "Mirrors", "version": "9.9.9"}},
                ],
            }))
            (root / "dependency-lock.json").write_text("{}\n")
            for name in (
                "fixtures/distribution-manifest.checked-replay-local.valid.json",
                "fixtures/distribution-manifest.checked-replay-gate.valid.json",
                "fixtures/cache-index.checked-replay-local.valid.json",
                "fixtures/cache-index.checked-replay-gate.valid.json",
            ):
                (root / name).write_text(json.dumps({
                    "catalogSelectionRef": {}, "componentRefs": [], "buildInputs": [],
                    "distributionManifestSha256": "",
                }))
            refs = {
                "mirrorecma": {"componentId": "mirrorecma", "revision": "new-ecma"},
                "mirrors": {"componentId": "mirrors", "revision": "new-mirrors"},
            }
            refresh_identity.update_locks(refs, "ab" * 32, root=root, catalog_path=catalog_path)
            locked = {
                entry["componentRef"]["componentId"]: entry
                for entry in json.loads((root / "component-lock.json").read_text())["components"]
            }
            self.assertEqual(locked["mirrorecma"]["product"],
                {"name": "mirrorecma", "version": "0.1.0"})
            self.assertEqual(locked["mirrorecma"]["componentRef"], refs["mirrorecma"])
            self.assertEqual(locked["mirrors"]["product"],
                {"name": "Mirrors", "version": "0.1.1"})
            self.assertEqual(locked["mirrors"]["componentRef"], refs["mirrors"])


PREPARED = "0.2.0-rc.6"


class SourceProductRefreshTests(unittest.TestCase):
    def test_checkout_declares_prepared_version(self) -> None:
        source = refresh_identity.HERE.parents[1]
        self.assertEqual(refresh_identity.declared_product_version(source), PREPARED)
        declaration = (source / "Shell" / "Version.lean").read_text(encoding="utf-8")
        self.assertEqual(declaration.count(f'def version : String := "{PREPARED}"'), 1)

    def test_stale_catalog_product_is_corrected_before_selection(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            repository = root / "repo"
            self.write_declaration(source, PREPARED)
            catalog_path, owned_path, refs = self.write_catalog(repository)
            stale = json.loads(catalog_path.read_text(encoding="utf-8"))
            stale_digest = digest_json(stale)
            with patch.object(refresh_identity, "MIRRORS", repository):
                catalog, digest = refresh_identity.update_catalogs(
                    refs, repository, False, catalog_path=catalog_path,
                    mirrors_source=source)
            written = json.loads(catalog_path.read_text(encoding="utf-8"))
            self.assertEqual(written, catalog)
            self.assertEqual(digest, digest_json(written))
            self.assertNotEqual(digest, stale_digest)
            products = self.products(written)
            self.assertEqual(products["mirrors"], {"name": "Mirrors", "version": PREPARED})
            self.assertEqual(products["mirrorecma"], {"name": "mirrorecma", "version": "0.1.0"})
            self.assertEqual(products["mirrorgate"], {"name": "MirrorGate", "version": "0.1.0"})
            self.assertEqual(written["extensions"]["org.nzsn.snapshot"]["capturedAt"],
                "2000-01-01T00:00:00Z")
            self.assertEqual(json.loads(owned_path.read_text(encoding="utf-8"))["components"][1]["product"],
                {"name": "Mirrors", "version": PREPARED})
            locks = root / "locks"
            self.write_locks(locks)
            refresh_identity.update_locks(refs, digest, root=locks, catalog_path=catalog_path)
            locked = self.products(json.loads((locks / "component-lock.json").read_text(encoding="utf-8")))
            self.assertEqual(locked["mirrors"], {"name": "Mirrors", "version": PREPARED})
            self.assertEqual(locked["mirrorecma"], {"name": "mirrorecma", "version": "0.1.0"})
            self.assertEqual(locked["mirrorgate"], {"name": "MirrorGate", "version": "0.1.0"})

    def test_selected_source_version_wins_over_running_tool(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            selected = root / "selected"
            self.write_declaration(selected, "0.0.9")
            catalog_path, _owned, refs = self.write_catalog(selected)
            tool_version = refresh_identity.declared_product_version(
                refresh_identity.HERE.parents[1])
            self.assertEqual(tool_version, PREPARED)
            self.assertNotEqual(tool_version, "0.0.9")
            with patch.object(refresh_identity, "MIRRORS", selected):
                catalog, digest = refresh_identity.update_catalogs(
                    refs, selected, False, catalog_path=catalog_path,
                    write_component_records=False)
            self.assertEqual(self.products(catalog)["mirrors"]["version"], "0.0.9")
            self.assertEqual(digest, digest_json(catalog))
            self.assertEqual(self.products(catalog)["mirrorecma"]["version"], "0.1.0")
            self.assertEqual(self.products(catalog)["mirrorgate"]["version"], "0.1.0")

    def test_owned_record_follows_mirrors_component_only(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            self.write_declaration(source, PREPARED)
            catalog_path, owned_path, refs = self.write_catalog(root / "repo")
            original_owned = json.loads(owned_path.read_text(encoding="utf-8"))
            with patch.object(refresh_identity, "MIRRORS", root / "repo"):
                refresh_identity.update_catalogs(
                    refs, root / "repo", False, catalog_path=catalog_path,
                    mirrors_source=source)
            owned = json.loads(owned_path.read_text(encoding="utf-8"))
            decoy, mirrors = owned["components"]
            self.assertEqual(decoy, original_owned["components"][0])
            self.assertEqual(mirrors["product"], {"name": "Mirrors", "version": PREPARED})
            self.assertEqual(mirrors["componentRef"], refs["mirrors"])
            self.assertEqual(mirrors["records"], original_owned["components"][1]["records"])
            self.assertEqual(owned["extensions"]["org.nzsn.snapshot"]["capturedAt"],
                "2000-01-01T00:00:00Z")

    def test_skip_component_records_leaves_the_owned_record_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            self.write_declaration(source, PREPARED)
            catalog_path, owned_path, refs = self.write_catalog(root / "repo")
            owned_bytes = owned_path.read_bytes()
            with patch.object(refresh_identity, "MIRRORS", root / "repo"):
                _catalog, digest = refresh_identity.update_catalogs(
                    refs, root / "repo", False, catalog_path=catalog_path,
                    write_component_records=False, mirrors_source=source)
            self.assertEqual(owned_path.read_bytes(), owned_bytes)
            self.assertFalse(owned_path.with_name(owned_path.name + ".tmp").exists())
            written = json.loads(catalog_path.read_text(encoding="utf-8"))
            self.assertEqual(self.products(written)["mirrors"]["version"], PREPARED)
            self.assertEqual(digest, digest_json(written))
            absent = root / "absent"
            absent_catalog, _absent_owned, absent_refs = self.write_catalog(absent)
            (absent / "catalog" / "components" / "mirrors.json").unlink()
            with patch.object(refresh_identity, "MIRRORS", absent):
                refresh_identity.update_catalogs(
                    absent_refs, absent, False, catalog_path=absent_catalog,
                    write_component_records=False, mirrors_source=source)
            self.assertFalse((absent / "catalog" / "components" / "mirrors.json").exists())

    def test_invalid_declaration_is_refused_before_catalog_write(self) -> None:
        cases = {
            "absent-file": ("missing", None),
            "no-declaration": ("missing", "namespace Shell.Version\nend Shell.Version\n"),
            "empty": ("malformed", 'def version : String := ""\n'),
            "leading-zero": ("malformed", 'def version : String := "01.2.3"\n'),
            "patch-leading-zero": ("malformed", 'def version : String := "0.2.01"\n'),
            "historical-four-part": ("malformed", 'def version : String := "0.0.3.2"\n'),
            "prerelease-leading-zero": ("malformed", 'def version : String := "0.2.0-rc.01"\n'),
            "tag-prefix": ("malformed", 'def version : String := "v0.2.0-rc.6"\n'),
            "binary": ("malformed", b"\xff"),
            "ambiguous": ("ambiguous",
                'def version : String := "0.2.0-rc.6"\ndef version : String := "0.1.1"\n'),
        }
        for name, (kind, payload) in cases.items():
            with self.subTest(name=name):
                with tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    source = root / "source"
                    if isinstance(payload, bytes):
                        self.write_declaration(source, raw=payload)
                    elif isinstance(payload, str):
                        self.write_declaration(source, text=payload)
                    catalog_path, owned_path, refs = self.write_catalog(root / "repo")
                    catalog_bytes = catalog_path.read_bytes()
                    owned_bytes = owned_path.read_bytes()
                    with patch.object(refresh_identity, "MIRRORS", root / "repo"):
                        with self.assertRaisesRegex(refresh_identity.SourceVersionError,
                                f"Mirrors source version declaration is {kind}"):
                            refresh_identity.update_catalogs(
                                refs, root / "repo", True, catalog_path=catalog_path,
                                mirrors_source=source)
                    self.assertEqual(catalog_path.read_bytes(), catalog_bytes)
                    self.assertEqual(owned_path.read_bytes(), owned_bytes)
                    self.assertFalse(catalog_path.with_name(catalog_path.name + ".tmp").exists())

    def test_skip_flags_stay_independent(self) -> None:
        cases = {
            "skip-render": (["--skip-render"], True, False),
            "skip-component-records": (["--skip-component-records"], False, True),
            "both": (["--skip-component-records", "--skip-render"], False, False),
        }
        for name, (extra, write_records, renders) in cases.items():
            with self.subTest(name=name):
                code, catalogs, locks, validate, run = self.run_main(extra)
                self.assertEqual(code, 0)
                self.assertIs(catalogs.call_args.kwargs["write_component_records"], write_records)
                self.assertIs(catalogs.call_args.args[2], True)
                locks.assert_called_once()
                validate.assert_called_once()
                if renders:
                    run.assert_called_once()
                    self.assertEqual(run.call_args.args[0][1], "render")
                    self.assertIs(run.call_args.kwargs["check"], True)
                else:
                    run.assert_not_called()

    def run_main(self, extra: list[str]):
        argv = ["refresh_identity.py", "--mirrorecma", "/tmp/ecma", "--mirrorgate", "/tmp/gate",
            "--catalog", "/tmp/catalog.json", "--locks-root", "/tmp/locks", *extra]
        with patch.object(sys, "argv", argv), \
                patch.object(refresh_identity, "selected_refs",
                    return_value={"mirrors": {"componentId": "mirrors"}}) as _selected, \
                patch.object(refresh_identity, "update_catalogs",
                    return_value=({}, "ab" * 32)) as catalogs, \
                patch.object(refresh_identity, "update_locks") as locks, \
                patch.object(refresh_identity, "validate_locks") as validate, \
                patch.object(refresh_identity.subprocess, "run") as run, \
                redirect_stdout(StringIO()):
            code = refresh_identity.main()
        return code, catalogs, locks, validate, run

    def write_declaration(self, root: Path, version: str | None = None,
            text: str | None = None, raw: bytes | None = None) -> None:
        path = root / "Shell" / "Version.lean"
        path.parent.mkdir(parents=True, exist_ok=True)
        if raw is not None:
            path.write_bytes(raw)
            return
        if text is None:
            text = f'def version : String := "{version}"\n'
        path.write_text(text, encoding="utf-8")

    def write_catalog(self, repository: Path):
        catalog_path = repository / "catalog" / "framework-catalog.json"
        owned_path = repository / "catalog" / "components" / "mirrors.json"
        owned_path.parent.mkdir(parents=True)
        refs = {
            "mirrorecma": {"componentId": "mirrorecma", "revision": "ecma"},
            "mirrorgate": {"componentId": "mirrorgate", "revision": "gate"},
            "mirrors": {"componentId": "mirrors", "revision": "mirrors"},
        }
        catalog = {
            "extensions": {"org.nzsn.snapshot": {"capturedAt": "2000-01-01T00:00:00Z"}},
            "components": [
                {"componentRef": dict(refs["mirrorecma"]),
                 "product": {"name": "mirrorecma", "version": "0.1.0"}},
                {"componentRef": dict(refs["mirrorgate"]),
                 "product": {"name": "MirrorGate", "version": "0.1.0"}},
                {"componentRef": dict(refs["mirrors"]),
                 "product": {"name": "Mirrors", "version": "0.1.1"}},
            ],
            "combinations": [{
                "combinationId": "candidate.local-node-checked",
                "componentIds": ["mirrorecma", "mirrorgate", "mirrors"],
            }],
        }
        owned = {
            "extensions": {"org.nzsn.snapshot": {"capturedAt": "1999-01-01T00:00:00Z"}},
            "components": [
                {"componentRef": {"componentId": "mirrorecma", "revision": "leave-me"},
                 "product": {"name": "mirrorecma", "version": "0.1.0"}},
                {"componentRef": {"componentId": "mirrors", "revision": "old-mirrors"},
                 "product": {"name": "Mirrors", "version": "0.0.2"},
                 "records": [{"recordId": "compiler", "path": "Shell/ModelInterface/Compiler.lean"}]},
            ],
        }
        catalog_path.write_text(json.dumps(catalog), encoding="utf-8")
        owned_path.write_text(json.dumps(owned), encoding="utf-8")
        return catalog_path, owned_path, refs

    def write_locks(self, root: Path) -> None:
        (root / "fixtures").mkdir(parents=True)
        (root / "profiles.json").write_text(json.dumps({
            "catalogSelectionRef": {},
            "profiles": [{
                "profileId": "checked-replay-local",
                "combinationId": "candidate.local-node-checked",
            }],
        }), encoding="utf-8")
        (root / "component-lock.json").write_text(json.dumps({
            "catalogSelectionRef": {},
            "components": [
                {"componentRef": {"componentId": "mirrorecma", "revision": "old-ecma"},
                 "product": {"name": "mirrorecma", "version": "2.0.0"}},
                {"componentRef": {"componentId": "mirrorgate", "revision": "old-gate"},
                 "product": {"name": "MirrorGate", "version": "8.8.8"}},
                {"componentRef": {"componentId": "mirrors", "revision": "old-mirrors"},
                 "product": {"name": "Mirrors", "version": "9.9.9"}},
            ],
        }), encoding="utf-8")
        (root / "dependency-lock.json").write_text("{}\n", encoding="utf-8")
        for name in (
            "fixtures/distribution-manifest.checked-replay-local.valid.json",
            "fixtures/distribution-manifest.checked-replay-gate.valid.json",
            "fixtures/cache-index.checked-replay-local.valid.json",
            "fixtures/cache-index.checked-replay-gate.valid.json",
        ):
            (root / name).write_text(json.dumps({
                "catalogSelectionRef": {}, "componentRefs": [], "buildInputs": [],
                "distributionManifestSha256": "",
            }), encoding="utf-8")

    def products(self, document: dict) -> dict[str, dict[str, str]]:
        return {
            entry["componentRef"]["componentId"]: entry["product"]
            for entry in document["components"]
        }


if __name__ == "__main__":
    unittest.main()
