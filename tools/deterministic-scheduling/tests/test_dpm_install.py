import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from install_cli import Refusal, inventory, no_replace, verify


class InstallationTests(unittest.TestCase):
    def test_content_mode_missing_and_extra_files_refuse(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);file=root/'runner';file.write_bytes(b'original')
            rows=inventory(root);verify(root,rows)
            file.write_bytes(b'changed')
            with self.assertRaises(Refusal):verify(root,rows)
            file.write_bytes(b'original');file.chmod(0o755)
            with self.assertRaises(Refusal):verify(root,rows)
            file.chmod(0o644);(root/'extra').write_text('extra')
            with self.assertRaises(Refusal):verify(root,rows)
            (root/'extra').unlink();file.unlink()
            with self.assertRaises(Refusal):verify(root,rows)

    def test_symlink_tree_refuses(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'source').write_text('source');(root/'link').symlink_to(root/'source')
            with self.assertRaises(Refusal):inventory(root)

    def test_atomic_activation_preserves_existing_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);staged=root/'staged';staged.mkdir();(staged/'new').write_text('new')
            existing=root/'existing';existing.mkdir();(existing/'old').write_text('old')
            with self.assertRaises(OSError):no_replace(staged,existing)
            self.assertEqual((existing/'old').read_text(),'old');self.assertTrue(staged.exists())
            activated=root/'activated';no_replace(staged,activated)
            self.assertFalse(staged.exists());self.assertEqual((activated/'new').read_text(),'new')


    def test_wrong_invocation_refuses_before_adjacent_imports(self):
        import shutil, subprocess
        source=Path(__file__).resolve().parents[1]
        for name in ['cli.py','install_cli.py','check_cli_installed.py','prepare_cli.py',
                     'refresh_host_identity.py','apps/counter_runner.py']:
            with self.subTest(entrypoint=name), tempfile.TemporaryDirectory() as directory:
                root=Path(directory);script=root/Path(name).name;shutil.copy2(source/name,script)
                marker=root/'marker'
                for module in ['argparse.py','json.py','hashlib.py']:
                    (root/module).write_text('from pathlib import Path;Path('+repr(str(marker))+').write_text("injected")')
                result=subprocess.run([sys.executable,str(script)],capture_output=True,text=True)
                self.assertEqual(result.returncode,2,result.stderr)
                self.assertIn('requires python3 -I -S -B',result.stderr)
                self.assertFalse(marker.exists())

    def test_isolated_installer_rejects_tampered_helper_and_ignores_shadow_modules(self):
        import shutil, subprocess
        source=Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for name in ['install_cli.py','dpm_host.py']:
                shutil.copy2(source/name,root/name)
            marker=root/'marker'
            for name in ['hashlib.py','json.py']:
                (root/name).write_text('from pathlib import Path;Path('+repr(str(marker))+').write_text("injected")')
            command=[sys.executable,'-I','-S','-B',str(root/'install_cli.py'),'--help']
            result=subprocess.run(command,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr);self.assertFalse(marker.exists())
            (root/'dpm_host.py').write_text('from pathlib import Path;Path('+repr(str(marker))+').write_text("helper")')
            result=subprocess.run(command,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0);self.assertIn('helper differs',result.stderr)
            self.assertFalse(marker.exists())


if __name__=='__main__':unittest.main()
