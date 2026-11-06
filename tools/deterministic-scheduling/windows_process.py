"""Creation-time Windows job assignment shared by trusted process owners.

No application code runs before job membership; only selected standard handles
are inherited. Consumers retain their own budget, outcome and cleanup policies.
"""
import os
from pathlib import Path
import subprocess

class WindowsJob:
    """Create the child in a kill-on-close job, with an explicit handle list.

    Assignment at CreateProcess time closes the suspended-child acquisition
    gap. No application code can execute before ownership is established.
    """
    def __init__(self):
        import ctypes as c
        from ctypes import wintypes as w
        self.c, self.w = c, w
        self.api = c.WinDLL('kernel32', use_last_error=True)
        signatures = {
            'CreateJobObjectW': ([c.c_void_p, w.LPCWSTR], w.HANDLE),
            'SetInformationJobObject': ([w.HANDLE, c.c_int, c.c_void_p, w.DWORD], w.BOOL),
            'QueryInformationJobObject': ([w.HANDLE, c.c_int, c.c_void_p, w.DWORD, c.c_void_p], w.BOOL),
            'TerminateJobObject': ([w.HANDLE, w.UINT], w.BOOL),
            'CloseHandle': ([w.HANDLE], w.BOOL),
            'WaitForSingleObject': ([w.HANDLE, w.DWORD], w.DWORD),
            'GetExitCodeProcess': ([w.HANDLE, c.POINTER(w.DWORD)], w.BOOL),
            'InitializeProcThreadAttributeList': ([c.c_void_p, w.DWORD, w.DWORD, c.POINTER(c.c_size_t)], w.BOOL),
            'UpdateProcThreadAttribute': ([c.c_void_p, w.DWORD, c.c_size_t, c.c_void_p, c.c_size_t, c.c_void_p, c.c_void_p], w.BOOL),
            'DeleteProcThreadAttributeList': ([c.c_void_p], None),
            'CreateProcessW': ([w.LPCWSTR, w.LPWSTR, c.c_void_p, c.c_void_p, w.BOOL, w.DWORD,
                                c.c_void_p, w.LPCWSTR, c.c_void_p, c.c_void_p], w.BOOL),
        }
        for name, (args, result) in signatures.items():
            function = getattr(self.api, name); function.argtypes = args; function.restype = result
        class BasicLimits(c.Structure):
            _fields_ = [('perProcess', c.c_int64), ('perJob', c.c_int64), ('flags', w.DWORD),
                        ('minWorkingSet', c.c_size_t), ('maxWorkingSet', c.c_size_t),
                        ('activeLimit', w.DWORD), ('affinity', c.c_size_t),
                        ('priority', w.DWORD), ('scheduling', w.DWORD)]
        class ExtendedLimits(c.Structure):
            _fields_ = [('basic', BasicLimits), ('io', c.c_uint64 * 6),
                        ('processMemory', c.c_size_t), ('jobMemory', c.c_size_t),
                        ('peakProcess', c.c_size_t), ('peakJob', c.c_size_t)]
        self.job = self.api.CreateJobObjectW(None, None)
        self.process = None
        if not self.job: raise c.WinError(c.get_last_error())
        limits = ExtendedLimits(); limits.basic.flags = 0x2000  # KILL_ON_JOB_CLOSE
        if not self.api.SetInformationJobObject(self.job, 9, c.byref(limits), c.sizeof(limits)):
            error = c.WinError(c.get_last_error()); self.close(); raise error

    def active(self):
        c, w = self.c, self.w
        class Accounting(c.Structure):
            _fields_ = [('times', c.c_int64 * 4), ('pageFaults', w.DWORD),
                        ('total', w.DWORD), ('active', w.DWORD), ('terminated', w.DWORD)]
        value = Accounting()
        if not self.api.QueryInformationJobObject(self.job, 1, c.byref(value), c.sizeof(value), None):
            raise c.WinError(c.get_last_error())
        return value.active

    def members(self):
        c, w = self.c, self.w
        class ProcessIds(c.Structure):
            _fields_ = [('assigned', w.DWORD), ('count', w.DWORD), ('ids', c.c_size_t * 4096)]
        value = ProcessIds()
        if not self.api.QueryInformationJobObject(self.job, 3, c.byref(value), c.sizeof(value), None):
            raise c.WinError(c.get_last_error())
        if value.count > 4096: raise OSError('owned process count bound exceeded')
        return set(value.ids[:value.count])

    def start(self, command, directory, input_handle, env=None):
        import msvcrt
        import sys
        c, w = self.c, self.w
        class Startup(c.Structure):
            _fields_ = [('cb', w.DWORD), ('reserved', w.LPWSTR), ('desktop', w.LPWSTR), ('title', w.LPWSTR),
                        ('x', w.DWORD), ('y', w.DWORD), ('xSize', w.DWORD), ('ySize', w.DWORD),
                        ('xChars', w.DWORD), ('yChars', w.DWORD), ('fill', w.DWORD), ('flags', w.DWORD),
                        ('show', w.WORD), ('reservedSize', w.WORD), ('reservedBytes', c.c_void_p),
                        ('stdin', w.HANDLE), ('stdout', w.HANDLE), ('stderr', w.HANDLE)]
        class ExtendedStartup(c.Structure):
            _fields_ = [('startup', Startup), ('attributes', c.c_void_p)]
        class ProcessInfo(c.Structure):
            _fields_ = [('process', w.HANDLE), ('thread', w.HANDLE), ('pid', w.DWORD), ('tid', w.DWORD)]
        reads, writes, attributes = [], [], None
        try:
            for _ in range(2):
                read, write = os.pipe(); reads.append(read); writes.append(write)
            inherited = [msvcrt.get_osfhandle(input_handle.fileno()),
                         *[msvcrt.get_osfhandle(fd) for fd in writes]]
            previous = [os.get_handle_inheritable(handle) for handle in inherited]
            try:
                for handle in inherited: os.set_handle_inheritable(handle, True)
                size = c.c_size_t()
                self.api.InitializeProcThreadAttributeList(None, 2, 0, c.byref(size))
                attributes = c.create_string_buffer(size.value)
                if not self.api.InitializeProcThreadAttributeList(attributes, 2, 0, c.byref(size)):
                    attributes = None
                    raise c.WinError(c.get_last_error())
                handles = (w.HANDLE * len(inherited))(*inherited)
                jobs = (w.HANDLE * 1)(self.job)
                for key, value in [(0x20002, handles), (0x2000D, jobs)]:
                    if not self.api.UpdateProcThreadAttribute(attributes, 0, key, c.byref(value), c.sizeof(value), None, None):
                        raise c.WinError(c.get_last_error())
                startup = ExtendedStartup(); startup.startup.cb = c.sizeof(startup)
                startup.startup.flags = 0x100  # STARTF_USESTDHANDLES
                startup.startup.stdin, startup.startup.stdout, startup.startup.stderr = inherited
                startup.attributes = c.cast(attributes, c.c_void_p)
                info = ProcessInfo()
                # Limit inherited handles and environment to runtime prerequisites.
                # DETACHED_PROCESS avoids a headless console helper in the job;
                # explicit pipe handles provide all I/O. No shell/search is used.
                cmdline = c.create_unicode_buffer(subprocess.list2cmdline([str(arg) for arg in command]))
                system = os.environ['SystemRoot']
                environment = {'SystemRoot':system, 'WINDIR':system,
                    'PATH':str(Path(sys.executable).parent)+';'+str(Path(system)/'System32'),
                    'PYTHONDONTWRITEBYTECODE':'1'}
                if env is not None: environment=dict(env)
                envblock = c.create_unicode_buffer('\0'.join(key+'='+value for key,value in sorted(environment.items(),key=lambda item:item[0].upper()))+'\0\0')
                if not self.api.CreateProcessW(str(command[0]), cmdline, None, None, True,
                        0x80000 | 0x8 | 0x400, envblock, str(directory), c.byref(startup), c.byref(info)):
                    raise c.WinError(c.get_last_error())
                self.process = info.process
                self.pid = info.pid
                self.api.CloseHandle(info.thread)
            finally:
                for handle, value in zip(inherited, previous): os.set_handle_inheritable(handle, value)
            pipes = [os.fdopen(fd, 'rb', buffering=0) for fd in reads]
            reads = []
            return pipes
        finally:
            if attributes is not None: self.api.DeleteProcThreadAttributeList(attributes)
            for fd in reads + writes: os.close(fd)

    def poll(self):
        c, w = self.c, self.w
        waited = self.api.WaitForSingleObject(self.process, 0)
        if waited == 258: return None
        if waited != 0: raise c.WinError(c.get_last_error())
        code = w.DWORD()
        if not self.api.GetExitCodeProcess(self.process, c.byref(code)): raise c.WinError(c.get_last_error())
        return code.value

    def terminate(self, code=2):
        if not self.api.TerminateJobObject(self.job, code): raise self.c.WinError(self.c.get_last_error())

    def close(self):
        if self.process: self.api.CloseHandle(self.process); self.process = None
        if self.job: self.api.CloseHandle(self.job); self.job = None

