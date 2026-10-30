"""Windows tool-process containment. No child runs before job assignment.

This is a trusted platform adapter for the differential harness, not a Gate
backend or native-M4 acceptance claim. The job handle is non-inheritable and
KILL_ON_JOB_CLOSE also covers abrupt loss of the Python controller.
"""
from __future__ import annotations

import ctypes
from ctypes import wintypes
import time


class BasicLimits(ctypes.Structure):
    _fields_ = [('process_time', ctypes.c_longlong), ('job_time', ctypes.c_longlong),
                ('flags', wintypes.DWORD), ('minimum_working_set', ctypes.c_size_t),
                ('maximum_working_set', ctypes.c_size_t), ('active_process_limit', wintypes.DWORD),
                ('affinity', ctypes.c_size_t), ('priority_class', wintypes.DWORD),
                ('scheduling_class', wintypes.DWORD)]


class IoCounters(ctypes.Structure):
    _fields_ = [(name, ctypes.c_ulonglong) for name in
                ['read_operations', 'write_operations', 'other_operations', 'read_bytes', 'write_bytes', 'other_bytes']]


class ExtendedLimits(ctypes.Structure):
    _fields_ = [('basic', BasicLimits), ('io', IoCounters), ('process_memory', ctypes.c_size_t),
                ('job_memory', ctypes.c_size_t), ('peak_process_memory', ctypes.c_size_t),
                ('peak_job_memory', ctypes.c_size_t)]


class Accounting(ctypes.Structure):
    _fields_ = [('user', ctypes.c_longlong), ('kernel', ctypes.c_longlong),
                ('period_user', ctypes.c_longlong), ('period_kernel', ctypes.c_longlong),
                ('page_faults', wintypes.DWORD), ('processes', wintypes.DWORD),
                ('active', wintypes.DWORD), ('terminated', wintypes.DWORD)]


class ThreadEntry(ctypes.Structure):
    _fields_ = [('size', wintypes.DWORD), ('usage', wintypes.DWORD), ('thread', wintypes.DWORD),
                ('owner', wintypes.DWORD), ('priority', wintypes.LONG), ('delta', wintypes.LONG),
                ('flags', wintypes.DWORD)]


class WindowsJob:
    def __init__(self):
        self.handle = None
        self.process = None
        self.api = ctypes.WinDLL('kernel32', use_last_error=True)
        signatures = {
            'CreateJobObjectW': ([ctypes.c_void_p, wintypes.LPCWSTR], wintypes.HANDLE),
            'SetInformationJobObject': ([wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD], wintypes.BOOL),
            'QueryInformationJobObject': ([wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD, ctypes.c_void_p], wintypes.BOOL),
            'AssignProcessToJobObject': ([wintypes.HANDLE, wintypes.HANDLE], wintypes.BOOL),
            'TerminateJobObject': ([wintypes.HANDLE, wintypes.UINT], wintypes.BOOL),
            'CloseHandle': ([wintypes.HANDLE], wintypes.BOOL),
            'CreateToolhelp32Snapshot': ([wintypes.DWORD, wintypes.DWORD], wintypes.HANDLE),
            'Thread32First': ([wintypes.HANDLE, ctypes.POINTER(ThreadEntry)], wintypes.BOOL),
            'Thread32Next': ([wintypes.HANDLE, ctypes.POINTER(ThreadEntry)], wintypes.BOOL),
            'OpenThread': ([wintypes.DWORD, wintypes.BOOL, wintypes.DWORD], wintypes.HANDLE),
            'ResumeThread': ([wintypes.HANDLE], wintypes.DWORD),
        }
        for name, (arguments, result) in signatures.items():
            function = getattr(self.api, name); function.argtypes = arguments; function.restype = result
        self.handle = self.api.CreateJobObjectW(None, None)
        if not self.handle: raise ctypes.WinError(ctypes.get_last_error())
        limits = ExtendedLimits(); limits.basic.flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if not self.api.SetInformationJobObject(self.handle, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
            error = ctypes.WinError(ctypes.get_last_error()); self.close(); raise error

    def assign_and_resume(self, process):
        if not self.api.AssignProcessToJobObject(self.handle, wintypes.HANDLE(int(process._handle))):
            raise ctypes.WinError(ctypes.get_last_error())
        self.process = process
        snapshot = self.api.CreateToolhelp32Snapshot(4, 0)  # TH32CS_SNAPTHREAD
        if not snapshot or snapshot == ctypes.c_void_p(-1).value:
            raise ctypes.WinError(ctypes.get_last_error())
        try:
            entry = ThreadEntry(); entry.size = ctypes.sizeof(entry)
            available = self.api.Thread32First(snapshot, ctypes.byref(entry))
            while available:
                if entry.owner == process.pid:
                    thread = self.api.OpenThread(2, False, entry.thread)  # THREAD_SUSPEND_RESUME
                    if not thread: raise ctypes.WinError(ctypes.get_last_error())
                    try:
                        previous = self.api.ResumeThread(thread)
                        if previous == 0xFFFFFFFF: raise ctypes.WinError(ctypes.get_last_error())
                        if previous > 0: return
                    finally: self.api.CloseHandle(thread)
                available = self.api.Thread32Next(snapshot, ctypes.byref(entry))
            raise OSError('suspended tool primary thread was not found')
        finally: self.api.CloseHandle(snapshot)

    def terminate(self):
        if not self.handle: return
        if not self.api.TerminateJobObject(self.handle, 137):
            raise ctypes.WinError(ctypes.get_last_error())
        if self.process is not None:
            # Job active counts can retain a terminated process while an
            # external handle remains open. Cache its exit code, then release
            # our process handle before asserting the job is empty.
            self.process.wait(timeout=2)
            self.process._handle.Close()
        deadline = time.monotonic()+3
        while True:
            accounting = Accounting()
            if not self.api.QueryInformationJobObject(self.handle, 1, ctypes.byref(accounting), ctypes.sizeof(accounting), None):
                raise ctypes.WinError(ctypes.get_last_error())
            if accounting.active == 0: return
            if time.monotonic() >= deadline: raise OSError('owned Windows job did not become empty')
            time.sleep(0.01)

    def close(self):
        if self.handle:
            self.api.CloseHandle(self.handle); self.handle = None
        self.process = None

    def __del__(self):
        self.close()
