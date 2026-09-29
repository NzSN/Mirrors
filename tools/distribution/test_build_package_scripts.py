import json
import tempfile
import unittest
from pathlib import Path

from build import PACKAGE_SCRIPTS, copy_package_scripts


ROOT = Path(__file__).resolve().parents[2]
PREFIX = "packages/mirrorecma/scripts/"


class BuildPackageScriptTests(unittest.TestCase):
    def test_package_scripts_are_copied_and_missing_sources_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ecma_work = root / "mirrorecma"
            (ecma_work / "scripts").mkdir(parents=True)
            payloads = {}
            for name in PACKAGE_SCRIPTS:
                payloads[name] = f"// {name}\n"
                (ecma_work / "scripts" / name).write_text(payloads[name])
            package = root / "package"
            package.mkdir()
            copy_package_scripts(ecma_work, package)
            for name in PACKAGE_SCRIPTS:
                self.assertEqual((package / "scripts" / name).read_text(), payloads[name])
            (ecma_work / "scripts" / PACKAGE_SCRIPTS[-1]).unlink()
            package_missing = root / "package-missing"
            package_missing.mkdir()
            with self.assertRaises(ValueError) as caught:
                copy_package_scripts(ecma_work, package_missing)
            self.assertIn(PACKAGE_SCRIPTS[-1], str(caught.exception))

    def test_registry_referenced_package_scripts_are_packaged(self) -> None:
        registry = json.loads((ROOT / "tools/evidence/commands.json").read_text())
        referenced = {
            arg[len(PREFIX):]
            for command in registry["commands"]
            for arg in command["argvPrefix"]
            if isinstance(arg, str) and arg.startswith(PREFIX)
        }
        self.assertTrue(referenced, "the reduction tiers must reference installed drivers")
        self.assertLessEqual(referenced, set(PACKAGE_SCRIPTS))
        self.assertIn("materialize-lease-reduction.mjs", PACKAGE_SCRIPTS)
        self.assertIn("reduce-reproduction-prefix.mjs", PACKAGE_SCRIPTS)


if __name__ == "__main__":
    unittest.main()
