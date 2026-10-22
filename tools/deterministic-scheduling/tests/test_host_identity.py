import ast
from contextlib import redirect_stderr
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    'refresh_host_identity', Path(__file__).resolve().parents[1] / 'refresh_host_identity.py')
identity = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(identity)


class HostIdentityTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.tools = self.root / 'tools'
        self.tools.mkdir()
        for name in identity.FILES:
            (self.tools / name).write_text('# ' + name + '\n', encoding='utf-8')
        for name in ['install_cli.py', 'check_cli_installed.py']:
            (self.tools / name).write_text(
                '_HELPER_SHA256 = {}  # refreshed helper identities\n', encoding='utf-8')
        self.interpreter = self.root / 'selected-python'
        self.interpreter.write_bytes(b'selected interpreter bytes')
        self.destination = self.root / 'build/Shell/Dpm/HostIdentity.lean'
        for target, value in [('TOOL_DIR', self.tools), ('DEFAULT_OUTPUT', self.destination)]:
            replacement = patch.object(identity, target, value)
            replacement.start()
            self.addCleanup(replacement.stop)
        executable = patch.object(identity.sys, 'executable', str(self.interpreter))
        executable.start()
        self.addCleanup(executable.stop)
        identity.refresh_helpers()

    def run_main(self, *arguments):
        error = io.StringIO()
        with redirect_stderr(error):
            result = identity.main(list(arguments))
        return result, error.getvalue()

    def snapshot(self):
        return {path.relative_to(self.root): (path.read_bytes(), path.stat().st_mtime_ns)
                for path in self.root.rglob('*') if path.is_file()}

    def helper_pins(self, name):
        line = (self.tools / name).read_text(encoding='utf-8').splitlines()[0]
        return ast.literal_eval(line.partition(' = ')[2].partition('  #')[0])

    def test_selected_interpreter_resolves_symlink_and_pins_runtime_bytes(self):
        alias = self.root / 'python-alias'
        try:
            alias.symlink_to(self.interpreter)
        except OSError as error:
            # Windows can require developer mode or elevated symlink privileges.
            if os.name == 'nt' and getattr(error, 'winerror', None) in (1, 50, 1314):
                self.skipTest('Windows symbolic links unavailable: ' + str(error))
            raise
        with patch.object(identity.sys, 'executable', str(alias)):
            self.assertEqual(self.run_main('--check-helpers'), (0, ''))
        generated = self.destination.read_text(encoding='utf-8')
        self.assertIn('def interpreter : String := ' + identity.lean_string(str(self.interpreter)), generated)
        self.assertNotIn(str(alias), generated)
        self.assertIn(hashlib.sha256(self.interpreter.read_bytes()).hexdigest(), generated)
        for name in identity.FILES:
            self.assertIn(hashlib.sha256((self.tools / name).read_bytes()).hexdigest(), generated)

    def test_path_quotes_backslashes_controls_and_unicode_are_lean_safe(self):
        value = 'C:\\runtime\\"python"\t\r\n\b\f\x00\x1f\x7f雪🐍'
        quoted = identity.lean_string(value)
        self.assertEqual(json.loads(quoted), value)
        self.assertIn('\\u0008', quoted)
        self.assertIn('\\u000c', quoted)
        self.assertNotIn('\n', quoted)
        self.assertNotIn('\r', quoted)
        filename = 'python 雪' if os.name == 'nt' else 'python "quoted" \\ 雪\n'
        interpreter = self.root / filename
        interpreter.write_bytes(b'quoted interpreter')
        with patch.object(identity.sys, 'executable', str(interpreter)):
            self.assertEqual(self.run_main('--check-helpers'), (0, ''))
        line = self.destination.read_text(encoding='utf-8').splitlines()[2]
        self.assertEqual(json.loads(line.partition(' := ')[2]), str(interpreter))

    def test_noop_preserves_generated_timestamp_and_tracked_helpers(self):
        self.assertEqual(self.run_main('--check-helpers'), (0, ''))
        os.utime(self.destination, ns=(1000000000, 1000000000))
        before = self.snapshot()
        self.assertEqual(self.run_main('--check-helpers'), (0, ''))
        self.assertEqual(self.run_main('--check'), (0, ''))
        self.assertEqual(self.snapshot(), before)

    def test_check_distinguishes_missing_generated_file_without_writing(self):
        before = self.snapshot()
        result, error = self.run_main('--check')
        self.assertEqual(result, 2)
        self.assertIn('identity missing:', error)
        self.assertIn('lake build mirrors_dpm', error)
        self.assertEqual(self.snapshot(), before)

    def test_check_rejects_changed_runtime_and_launcher_helper_without_writing(self):
        self.assertEqual(self.run_main('--check-helpers'), (0, ''))
        for path in [self.interpreter, self.tools / 'cli.py']:
            with self.subTest(path=path.name):
                original = path.read_bytes()
                path.write_bytes(original + b'changed')
                before = self.snapshot()
                result, error = self.run_main('--check')
                self.assertEqual(result, 2)
                self.assertIn('identity stale:', error)
                self.assertEqual(self.snapshot(), before)
                path.write_bytes(original)

    def test_build_helper_check_refuses_stale_pins_without_any_writes(self):
        self.assertEqual(self.run_main('--check-helpers'), (0, ''))
        (self.tools / 'dpm_host.py').write_bytes(b'changed helper bytes')
        before = self.snapshot()
        for arguments in [('--check-helpers',), ('--check',), ('--helpers-only', '--check')]:
            with self.subTest(arguments=arguments):
                result, error = self.run_main(*arguments)
                self.assertEqual(result, 2)
                self.assertIn('helper identities stale: install_cli.py', error)
                self.assertIn('--helpers-only', error)
                self.assertEqual(self.snapshot(), before)

    def test_helper_refresh_updates_dependent_pin_after_installer_and_skips_runtime(self):
        (self.tools / 'dpm_host.py').write_bytes(b'updated host')
        with patch.object(identity.sys, 'executable', str(self.root / 'missing-python')):
            self.assertEqual(self.run_main('--helpers-only'), (0, ''))
        host_hash = hashlib.sha256((self.tools / 'dpm_host.py').read_bytes()).hexdigest()
        installer_hash = hashlib.sha256((self.tools / 'install_cli.py').read_bytes()).hexdigest()
        self.assertEqual(self.helper_pins('install_cli.py'), {'dpm_host': host_hash})
        self.assertEqual(self.helper_pins('check_cli_installed.py'),
                         {'dpm_host': host_hash, 'install_cli': installer_hash})
        self.assertFalse(self.destination.exists())
        self.assertEqual(self.run_main('--helpers-only', '--check'), (0, ''))

    def test_default_manual_refreshes_helpers_and_custom_output(self):
        (self.tools / 'dpm_host.py').write_bytes(b'updated host')
        destination = self.root / 'custom/output.lean'
        self.assertEqual(self.run_main('--output', str(destination)), (0, ''))
        self.assertTrue(destination.is_file())
        self.assertFalse(self.destination.exists())
        self.assertEqual(self.run_main('--check', '--output', str(destination)), (0, ''))

    def test_missing_runtime_reports_error_without_writing(self):
        before = self.snapshot()
        for executable in ['', str(self.root / 'absent-python')]:
            with self.subTest(executable=executable), patch.object(identity.sys, 'executable', executable):
                result, error = self.run_main('--check-helpers')
                self.assertEqual(result, 2)
                self.assertIn('DPM host identity preparation failed:', error)
                self.assertEqual(self.snapshot(), before)

    def test_missing_helper_declaration_is_rejected(self):
        (self.tools / 'install_cli.py').write_text('# missing declaration\n', encoding='utf-8')
        before = self.snapshot()
        result, error = self.run_main('--check-helpers')
        self.assertEqual(result, 2)
        self.assertIn('declaration missing or duplicated: install_cli.py', error)
        self.assertEqual(self.snapshot(), before)

    def test_atomic_write_failure_preserves_previous_generation_and_cleans_temporary(self):
        self.assertEqual(self.run_main('--check-helpers'), (0, ''))
        self.interpreter.write_bytes(b'new runtime')
        before = self.snapshot()
        with patch.object(identity.os, 'replace', side_effect=OSError('replacement refused')):
            result, error = self.run_main('--check-helpers')
        self.assertEqual(result, 2)
        self.assertIn('replacement refused', error)
        self.assertEqual(self.snapshot(), before)


if __name__ == '__main__':
    unittest.main()
