"""Send a real console break only to a task-owned collector process group."""
import ctypes as c
from ctypes import wintypes as w
import sys
k=c.WinDLL('kernel32',use_last_error=True)
k.AttachConsole.argtypes=[w.DWORD];k.AttachConsole.restype=w.BOOL
k.GenerateConsoleCtrlEvent.argtypes=[w.DWORD,w.DWORD];k.GenerateConsoleCtrlEvent.restype=w.BOOL
k.FreeConsole.argtypes=[];k.FreeConsole.restype=w.BOOL
pid=int(sys.argv[1])
if not k.AttachConsole(pid):raise c.WinError(c.get_last_error())
try:
    if not k.GenerateConsoleCtrlEvent(1,pid):raise c.WinError(c.get_last_error())
finally:k.FreeConsole()
