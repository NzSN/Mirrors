"""Native Windows regressions for ownership, argument bytes and startup failure."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import dpm_host as host


@unittest.skipUnless(os.name == 'nt', 'native Windows job/handle semantics')
class WindowsProcessTests(unittest.TestCase):
    def test_arguments_and_clean_runtime_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = ['', 'with spaces', 'quote"tail\\', '中文', 'x\\\\"y']
            with patch.dict(os.environ, {'PYTHONPATH': str(root/'poison'), 'PYTHONINSPECT': '1'}):
                host.owned_process([sys.executable, '-c',
                    'import json,os,sys;print(json.dumps([sys.argv[1:],os.getenv("PYTHONPATH"),os.getenv("PYTHONINSPECT")]))',
                    *args], root, 5, 65536)
            self.assertEqual(json.loads((root/'stdout.log').read_text()), [args, None, None])

    def test_creation_failure_still_closes_logs_and_confirms_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(host.ProcessFailure) as failure:
                host.owned_process([str(root/'missing.exe')], root, 2, 65536)
            self.assertEqual(failure.exception.accounting['processCleanup'], 'confirmed')
            for name in ['stdout.log', 'stderr.log']:
                path=root/name; moved=path.with_suffix('.closed')
                path.rename(moved); moved.rename(path)

    def test_acquisition_failure_does_not_execute_application(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); marker=root/'executed'
            def fail(owner, *args):
                # Real job exists; fail before the atomic process acquisition.
                raise OSError('injected process acquisition failure')
            with patch.object(host._WindowsJob, 'start', fail):
                with self.assertRaises(host.ProcessFailure) as failure:
                    host.owned_process([sys.executable, '-c',
                        'from pathlib import Path;Path('+repr(str(marker))+').touch()'], root, 2, 65536)
            self.assertEqual(failure.exception.accounting['processCleanup'], 'confirmed')
            self.assertFalse(marker.exists())

    def test_directory_junction_refuses_in_input_and_output_trees(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); target=root/'target';target.mkdir();(target/'input').write_text('{}')
            junction=root/'junction'
            result=subprocess.run(['cmd.exe','/d','/c','mklink','/J',str(junction),str(target)],capture_output=True)
            self.assertEqual(result.returncode,0,result.stderr)
            try:
                with self.assertRaisesRegex(host.Refusal,'symlink'):
                    host.regular(junction/'input')
                with self.assertRaisesRegex(host.Refusal,'reparse'):
                    host.retained_bytes(root)
            finally: junction.rmdir()

    def test_launcher_death_cancels_and_reaps_owned_runner(self):
        # The outer owner contains the parent, host, and runner even if the
        # regression breaks cleanup. No test leaves a detached fixture behind.
        import ctypes as c
        from ctypes import wintypes as w
        api=c.WinDLL('kernel32',use_last_error=True)
        api.OpenProcess.argtypes=[w.DWORD,w.BOOL,w.DWORD];api.OpenProcess.restype=w.HANDLE
        api.TerminateProcess.argtypes=[w.HANDLE,w.UINT];api.TerminateProcess.restype=w.BOOL
        api.CloseHandle.argtypes=[w.HANDLE];api.CloseHandle.restype=w.BOOL
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'request').mkdir()
            script=root/'host.py'
            runner = "import time;from pathlib import Path;Path('../ready').touch();time.sleep(30)"
            script.write_text("""import sys,types
from pathlib import Path
source=Path(sys.argv[1]);root=Path(sys.argv[2])
host=types.ModuleType('dpm_host');host.__file__=str(source)
exec(compile(source.read_bytes(),str(source),'exec'),host.__dict__)
host.watch_windows_parent()
try:
    host.owned_process([sys.executable,'-c',%r],root/'request',20,65536)
except host.ProcessFailure as error:
    (root/'result').write_text(str(error))
""" % runner)
            parent=root/'parent.py'
            parent.write_text("""import subprocess,sys,time
subprocess.Popen(sys.argv[1:]);time.sleep(30)
""")
            owner=host._WindowsJob();pipes=[]
            try:
                with open(os.devnull,'rb') as null:
                    pipes=owner.start([sys.executable,'-I','-S','-B',str(parent),
                        sys.executable,'-I','-S','-B',str(script),host.__file__,str(root)],root,null)
                deadline=time.monotonic()+8
                while not (root/'ready').exists():
                    if owner.poll() is not None or time.monotonic()>deadline: self.fail('runner readiness deadline')
                    time.sleep(.01)
                handle=api.OpenProcess(1,False,owner.pid)
                self.assertTrue(handle)
                try: self.assertTrue(api.TerminateProcess(handle,2))
                finally: api.CloseHandle(handle)
                while owner.active() and time.monotonic()<deadline: time.sleep(.01)
                self.assertEqual(owner.active(),0,'parent death left a host or runner alive')
                self.assertIn('operation cancelled;', (root/'result').read_text())
                self.assertIn('"processCleanup": "confirmed"', (root/'result').read_text())
            finally:
                owner.terminate();owner.close()
                for pipe in pipes: pipe.close()


if __name__ == '__main__': unittest.main()
