"""Actual Windows job containment controls; no mock grants platform credit."""
import ctypes
from ctypes import wintypes
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from process import ExecutionStatus, ProcessLimits, ProcessRequest, run_process


def alive(pid):
    api = ctypes.WinDLL('kernel32', use_last_error=True)
    api.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    api.OpenProcess.restype = wintypes.HANDLE
    api.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
    api.GetExitCodeProcess.restype = wintypes.BOOL
    api.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = api.OpenProcess(0x1000, False, pid)
    if not handle: return False
    try:
        code = wintypes.DWORD()
        return bool(api.GetExitCodeProcess(handle, ctypes.byref(code))) and code.value == 259
    finally: api.CloseHandle(handle)


@unittest.skipUnless(os.name == 'nt', 'requires actual native Windows job objects')
class WindowsContainmentTests(unittest.TestCase):
    def test_exited_leader_cannot_leave_a_pipe_holding_descendant(self):
        with tempfile.TemporaryDirectory(prefix='mirrors-win-owner-') as temporary:
            root = Path(temporary); marker = root/'child.pid'
            child = 'import time;time.sleep(30)'
            script = ('import subprocess,sys;from pathlib import Path;'
                      'child=subprocess.Popen([sys.executable,"-c",'+repr(child)+']);'
                      'Path('+repr(str(marker))+').write_text(str(child.pid))')
            started = time.monotonic()
            result = run_process(ProcessRequest([sys.executable, '-c', script], root), ProcessLimits(timeout_seconds=10))
            self.assertEqual(result.status, ExecutionStatus.COMPLETED, result.detail)
            self.assertLess(time.monotonic()-started, 8)
            self.assertTrue(marker.is_file())
            self.assertFalse(alive(int(marker.read_text())))

    def test_timeout_reclaims_descendants_and_preserves_unrelated_sentinel(self):
        sentinel = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(30)'],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            with tempfile.TemporaryDirectory(prefix='mirrors-win-timeout-') as temporary:
                root = Path(temporary); marker = root/'child.pid'
                script = ('import subprocess,sys,time;from pathlib import Path;'
                          'child=subprocess.Popen([sys.executable,"-c","import time;time.sleep(30)"]);'
                          'Path('+repr(str(marker))+').write_text(str(child.pid));time.sleep(30)')
                result = run_process(ProcessRequest([sys.executable, '-c', script], root),
                                     ProcessLimits(timeout_seconds=2))
                self.assertEqual(result.status, ExecutionStatus.TIMEOUT, result.detail)
                self.assertTrue(marker.is_file())
                self.assertFalse(alive(int(marker.read_text())))
                self.assertIsNone(sentinel.poll())
        finally:
            sentinel.terminate(); sentinel.wait(timeout=5)


if __name__ == '__main__':
    unittest.main()
