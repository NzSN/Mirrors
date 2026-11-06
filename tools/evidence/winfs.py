"""Native NTFS primitives for private, handle-relative retained evidence.

All path components are opened individually without following reparse points.
Names beneath a pinned directory are resolved through its handle, not a second
absolute-path traversal. NTFS and a local drive are required; no network or DOS
namespace fallback is provided.
"""
from __future__ import annotations

import contextlib
import ctypes as c
from ctypes import wintypes as w
import hashlib
import errno
import msvcrt
import os
from pathlib import Path
import re
import stat
import threading
from types import SimpleNamespace

k = c.WinDLL('kernel32', use_last_error=True)
a = c.WinDLL('advapi32', use_last_error=True)
n = c.WinDLL('ntdll', use_last_error=True)


def _signature(lib, name, args, result):
    fn = getattr(lib, name); fn.argtypes = args; fn.restype = result
    return fn


_signature(k, 'CloseHandle', [w.HANDLE], w.BOOL)
_signature(k, 'GetCurrentProcess', [], w.HANDLE)
_signature(k, 'LocalFree', [c.c_void_p], c.c_void_p)
_signature(k, 'FlushFileBuffers', [w.HANDLE], w.BOOL)
_signature(k, 'GetFileInformationByHandle', [w.HANDLE, c.c_void_p], w.BOOL)
_signature(k, 'SetFileInformationByHandle', [w.HANDLE, c.c_int, c.c_void_p, w.DWORD], w.BOOL)
_signature(k, 'GetFinalPathNameByHandleW', [w.HANDLE, w.LPWSTR, w.DWORD, w.DWORD], w.DWORD)
_signature(a, 'OpenProcessToken', [w.HANDLE, w.DWORD, c.POINTER(w.HANDLE)], w.BOOL)
_signature(a, 'GetTokenInformation', [w.HANDLE, c.c_int, c.c_void_p, w.DWORD, c.POINTER(w.DWORD)], w.BOOL)
_signature(a, 'ConvertSidToStringSidW', [c.c_void_p, c.POINTER(w.LPWSTR)], w.BOOL)
_signature(a, 'ConvertStringSecurityDescriptorToSecurityDescriptorW', [w.LPCWSTR, w.DWORD, c.POINTER(c.c_void_p), c.c_void_p], w.BOOL)
_signature(a, 'GetSecurityInfo', [w.HANDLE, c.c_int, w.DWORD, c.POINTER(c.c_void_p), c.c_void_p, c.POINTER(c.c_void_p), c.c_void_p, c.POINTER(c.c_void_p)], w.DWORD)
_signature(a, 'GetSecurityDescriptorControl', [c.c_void_p, c.POINTER(w.WORD), c.POINTER(w.DWORD)], w.BOOL)
_signature(a, 'GetAce', [c.c_void_p, w.DWORD, c.POINTER(c.c_void_p)], w.BOOL)
_signature(a, 'SetKernelObjectSecurity', [w.HANDLE, w.DWORD, c.c_void_p], w.BOOL)
_signature(n, 'RtlNtStatusToDosError', [c.c_long], w.DWORD)
_signature(n, 'NtQueryVolumeInformationFile', [w.HANDLE,c.c_void_p,c.c_void_p,w.DWORD,c.c_int], c.c_long)
_signature(n, 'NtSetInformationFile', [w.HANDLE, c.c_void_p, c.c_void_p, w.DWORD, c.c_int], c.c_long)
_signature(n, 'NtCreateFile', [c.POINTER(w.HANDLE), w.DWORD, c.c_void_p, c.c_void_p, c.c_void_p, w.DWORD, w.DWORD, w.DWORD, w.DWORD, c.c_void_p, w.DWORD], c.c_long)
_signature(n, 'NtQueryDirectoryFile', [w.HANDLE, w.HANDLE, c.c_void_p, c.c_void_p, c.c_void_p, c.c_void_p, w.DWORD, c.c_int, w.BOOLEAN, c.c_void_p, w.BOOLEAN], c.c_long)


class Unicode(c.Structure):
    _fields_ = [('length', w.USHORT), ('maximum', w.USHORT), ('buffer', w.LPWSTR)]


class Attributes(c.Structure):
    _fields_ = [('length', w.ULONG), ('root', w.HANDLE), ('name', c.POINTER(Unicode)),
                ('flags', w.ULONG), ('security', c.c_void_p), ('qos', c.c_void_p)]


class IoStatus(c.Structure):
    _fields_ = [('status', c.c_void_p), ('information', c.c_size_t)]


class FileInfo(c.Structure):
    _fields_ = [('attributes', w.DWORD), ('created', w.FILETIME), ('accessed', w.FILETIME),
                ('written', w.FILETIME), ('volume', w.DWORD), ('sizeHigh', w.DWORD),
                ('sizeLow', w.DWORD), ('links', w.DWORD), ('indexHigh', w.DWORD), ('indexLow', w.DWORD)]


def _check(result):
    if not result: raise c.WinError(c.get_last_error())
    return result


def _ntcheck(status):
    if status < 0:
        raise c.WinError(n.RtlNtStatusToDosError(status))


def _handle(fd): return msvcrt.get_osfhandle(fd)


def _sid_text(sid):
    text = w.LPWSTR()
    _check(a.ConvertSidToStringSidW(sid, c.byref(text)))
    try: return text.value
    finally: k.LocalFree(c.cast(text, c.c_void_p))


def user_sid():
    token = w.HANDLE()
    _check(a.OpenProcessToken(k.GetCurrentProcess(), 8, c.byref(token)))
    try:
        size = w.DWORD()
        a.GetTokenInformation(token, 1, None, 0, c.byref(size))
        data = c.create_string_buffer(size.value)
        _check(a.GetTokenInformation(token, 1, data, len(data), c.byref(size)))
        return _sid_text(c.cast(data, c.POINTER(c.c_void_p))[0])
    finally: k.CloseHandle(token)


@contextlib.contextmanager
def private_security():
    sid = user_sid(); descriptor = c.c_void_p()
    _check(a.ConvertStringSecurityDescriptorToSecurityDescriptorW(
        f'O:{sid}G:{sid}D:P(A;OICI;FA;;;{sid})', 1, c.byref(descriptor), None))
    try: yield descriptor
    finally: k.LocalFree(descriptor)


def _name(name):
    if (not isinstance(name, str) or not name or name in {'.', '..'}
            or any(ord(ch) < 32 or ch in '/\\:*?"<>|' for ch in name)
            or name.endswith((' ', '.')) or len(name.encode('utf-16-le')) > 510
            or re.fullmatch(r'(?i)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?', name)):
        raise ValueError('unsafe native file name')
    return name


def info(fd):
    value = FileInfo()
    _check(k.GetFileInformationByHandle(_handle(fd), c.byref(value)))
    return value


def fstat(fd):
    value=info(fd)
    directory=bool(value.attributes&0x10)
    permissions=(0o444 if value.attributes&1 else 0o666)|(0o111 if directory else 0)
    written=(value.written.dwHighDateTime<<32)|value.written.dwLowDateTime
    return SimpleNamespace(st_dev=value.volume,st_ino=(value.indexHigh<<32)|value.indexLow,
        st_size=(value.sizeHigh<<32)|value.sizeLow,
        st_mtime_ns=(written-116444736000000000)*100,
        st_mode=(stat.S_IFDIR if directory else stat.S_IFREG)|permissions,
        st_file_attributes=value.attributes,st_nlink=value.links)


def no_reparse(fd):
    if info(fd).attributes & 0x400:
        raise OSError(errno.ELOOP,'reparse point or symlink is forbidden')


def open_at(parent, name, *, directory=False, create=False, exclusive=False,
            write=False, delete=False, private=False, pin=False, acl_write=False, share_mode=None):
    if parent is not None: _name(name)
    text = c.create_unicode_buffer(name, len(name.encode('utf-16-le'))//2+1)
    u = Unicode(len(name.encode('utf-16-le')), c.sizeof(text), c.cast(text, w.LPWSTR))
    attributes = Attributes(c.sizeof(Attributes), _handle(parent) if parent is not None else None,
                            c.pointer(u), 0x40, None, None)
    # Metadata and synchronous access; directory enumeration needs LIST_DIRECTORY.
    access = 0x20000 | 0x100000 | 0x80 | (0x21 if directory else 0x80000000)
    if write: access |= 0x40000000
    if delete: access |= 0x10000
    if acl_write: access |= 0x40000
    disposition = 2 if exclusive else 3 if create else 1  # CREATE / OPEN_IF / OPEN
    options = 0x200000 | 0x20 | (1 if directory else 0x40)
    result = w.HANDLE(); io = IoStatus()
    security = private_security() if private else contextlib.nullcontext(None)
    with security as descriptor:
        attributes.security = descriptor
        status = n.NtCreateFile(c.byref(result), access, c.byref(attributes), c.byref(io), None,
            0x80, (1 if pin else 7) if share_mode is None else share_mode, disposition, options, None, 0)
    _ntcheck(status)
    try:
        fd = msvcrt.open_osfhandle(result.value, os.O_BINARY | (os.O_RDWR if write else os.O_RDONLY))
    except BaseException:
        k.CloseHandle(result); raise
    try:
        no_reparse(fd)
        if bool(info(fd).attributes & 0x10) != directory:
            raise ValueError('native object is not a regular file or directory as required')
        return fd
    except BaseException:
        os.close(fd); raise


def open_directory(path, *, create=False, exclusive=False, write=False, pin=False):
    path = Path(os.path.abspath(path))
    if not re.fullmatch(r'[A-Za-z]:\\', path.anchor):
        raise ValueError('native private storage requires a local drive')
    current = open_at(None, '\\??\\'+path.anchor, directory=True)
    try:
        device=(w.DWORD*2)();io=IoStatus()
        _ntcheck(n.NtQueryVolumeInformationFile(_handle(current),c.byref(io),c.byref(device),c.sizeof(device),4))
        if device[1]&0x10 or filesystem_type(current)!='ntfs':
            raise ValueError('native private storage requires local NTFS')
        for index, part in enumerate(path.parts[1:]):
            last = index == len(path.parts)-2
            child = open_at(current, part, directory=True, create=create,
                exclusive=exclusive and last, write=write and last, delete=pin and last,
                private=create, pin=pin and last)
            os.close(current); current=child
        return current
    except BaseException:
        os.close(current); raise


def check_private_fd(fd):
    owner = c.c_void_p(); acl = c.c_void_p(); descriptor = c.c_void_p()
    code = a.GetSecurityInfo(_handle(fd), 1, 1|4, c.byref(owner), None, c.byref(acl), None, c.byref(descriptor))
    if code: raise c.WinError(code)
    try:
        control = w.WORD(); revision = w.DWORD()
        _check(a.GetSecurityDescriptorControl(descriptor, c.byref(control), c.byref(revision)))
        sid = user_sid()
        if _sid_text(owner) != sid or not acl.value:
            raise ValueError('evidence object must have owner-only permissions (native ACL)')
        # ACL header: revision, padding, size, ACE count, padding.
        count = w.WORD.from_address(acl.value+4).value
        for index in range(count):
            ace = c.c_void_p(); _check(a.GetAce(acl, index, c.byref(ace)))
            kind = c.c_ubyte.from_address(ace.value).value
            if kind == 1: continue  # deny ACE cannot grant access
            if kind != 0 or _sid_text(ace.value+8) != sid:
                raise ValueError('evidence object must have owner-only permissions (native ACL grants another principal)')
    finally: k.LocalFree(descriptor)


def check_private(path):
    path = Path(path)
    parent = open_directory(path.parent)
    try: fd = open_at(parent, path.name, directory=path.is_dir())
    finally: os.close(parent)
    try: check_private_fd(fd)
    finally: os.close(fd)


def set_private(path):
    path = Path(path); parent = open_directory(path.parent)
    try:
        # WRITE_DAC and WRITE_OWNER are not in open_at's ordinary access mask.
        # Use the current owner descriptor through a dedicated metadata open.
        fd = open_at(parent, path.name, directory=path.is_dir(), acl_write=True)
    finally: os.close(parent)
    try:
        with private_security() as descriptor:
            _check(a.SetKernelObjectSecurity(_handle(fd), 4|0x80000000, descriptor))
    finally: os.close(fd)


def create_directory(path, *, exclusive=False):
    fd = open_directory(path, create=True, exclusive=exclusive)
    try: check_private_fd(fd)
    finally: os.close(fd)


def stat_at(parent, name):
    try: fd = open_at(parent, name)
    except ValueError:
        fd = open_at(parent, name, directory=True)
    try: return fstat(fd)
    finally: os.close(fd)


def read_regular(path, *, max_bytes=64*1024*1024):
    path=Path(path); parent=open_directory(path.parent)
    try: return read_at(parent, path.name, max_bytes=max_bytes)
    finally: os.close(parent)


def read_at(parent, name, *, max_bytes=64*1024*1024, private=False):
    try: fd=open_at(parent,name)
    except (OSError,ValueError) as error:
        if isinstance(error,FileNotFoundError): raise
        raise ValueError('evidence record is not a regular file') from error
    try:
        if private: check_private_fd(fd)
        before=fstat(fd)
        if before.st_size>max_bytes: raise ValueError(f'evidence record exceeds {max_bytes} bytes')
        chunks=[];total=0;digest=hashlib.sha256()
        while True:
            block=os.read(fd,min(1024*1024,max_bytes-total+1))
            if not block:break
            total+=len(block)
            if total>max_bytes:raise ValueError(f'evidence record exceeds {max_bytes} bytes')
            chunks.append(block);digest.update(block)
        identity=lambda value:(value.st_dev,value.st_ino,value.st_size,value.st_mtime_ns,value.st_mode)
        if identity(before)!=identity(fstat(fd)) or identity(before)!=identity(stat_at(parent,name)) or total!=before.st_size:
            raise ValueError('evidence record changed while reading')
        return b''.join(chunks),digest.hexdigest()
    finally:os.close(fd)


def write_exclusive(path,data):
    path=Path(path); parent=open_directory(path.parent)
    try:fd=open_at(parent,path.name,create=True,exclusive=True,write=True,private=True)
    finally:os.close(parent)
    try:
        view=memoryview(data)
        while view:
            written=os.write(fd,view)
            if written<=0:raise OSError('native write made no progress')
            view=view[written:]
        os.fsync(fd)
    finally:os.close(fd)


def _rename_or_link(fd, parent, name, *, link=False, replace=False):
    _name(name)
    class Rename(c.Structure):
        _fields_=[('replace',w.BOOLEAN),('root',w.HANDLE),('length',w.DWORD),('name',w.WCHAR*(len(name.encode('utf-16-le'))//2))]
    value=Rename();value.replace=replace;value.root=_handle(parent) if parent is not None else None
    value.length=len(name.encode('utf-16-le'));value.name=name
    io=IoStatus()
    _ntcheck(n.NtSetInformationFile(_handle(fd),c.byref(io),c.byref(value),c.sizeof(value),11 if link else 10))


def unlink_fd(fd):
    value=w.BOOLEAN(True)
    _check(k.SetFileInformationByHandle(_handle(fd),4,c.byref(value),c.sizeof(value)))


def publish_exclusive(directory, temporary_name, final_name):
    parent=open_directory(directory,write=True)
    try:
        fd=open_at(parent,temporary_name,delete=True)
        try:
            _rename_or_link(fd,parent,final_name,link=True)
            unlink_fd(fd)
        finally:os.close(fd)
        os.fsync(parent)
    finally:os.close(parent)




def listdir(fd):
    buffer=c.create_string_buffer(65536);io=IoStatus();restart=True
    while True:
        status=n.NtQueryDirectoryFile(_handle(fd),None,None,None,c.byref(io),buffer,len(buffer),12,False,None,restart)
        restart=False
        if status & 0xffffffff == 0x80000006:return
        _ntcheck(status)
        offset=0
        while offset<io.information:
            next_offset,_,length=(w.DWORD*3).from_buffer(buffer,offset)
            name=c.wstring_at(c.addressof(buffer)+offset+12,length//2)
            if name not in {'.','..'}:yield _name(name)
            if not next_offset:break
            if next_offset<12 or offset+next_offset>=io.information:raise ValueError('invalid native directory record')
            offset+=next_offset


# Transaction roots additionally deny metadata mutation and rename while legacy
# path-consuming materializers work beneath them. Reuse handles for nested pins.
_pins=threading.local()


@contextlib.contextmanager
def pin_directory(path, *, create=False, writable=True, share_write=False):
    path=Path(os.path.abspath(path));key=lambda p:str(p).casefold()
    registry=getattr(_pins,'directories',None)
    if registry is None:registry={};_pins.directories=registry
    if not re.fullmatch(r'[A-Za-z]:\\',path.anchor):raise ValueError('native transaction requires a local drive')
    owned=[];registered=[];current=None;part_path=Path(path.anchor)
    try:
        all_paths=[part_path]
        for part in path.parts[1:]:part_path/=part;all_paths.append(part_path)
        for index,component in enumerate(all_paths):
            name=key(component);last=index==len(all_paths)-1
            if name in registry:
                fd=os.dup(registry[name]["fd"])
            else:
                fd=open_at(current,component.name if current is not None else '\\??\\'+component.anchor,
                    directory=True,create=create and index>0,private=create,
                    write=last and writable,pin=True,share_mode=3 if last and share_write else 1)
                registry[name]={"fd":fd,"owned":owned,"index":len(owned),"writable":last and writable};registered.append(name)
            owned.append(fd);current=fd
        yield current
    finally:
        for name in reversed(registered):registry.pop(name,None)
        for fd in reversed(owned):
            if fd is not None:os.close(fd)


def _pinned(path):
    record=getattr(_pins,'directories',{}).get(str(Path(os.path.abspath(path))).casefold())
    return record['fd'] if record is not None else None


def fsync_directory(path):
    record=getattr(_pins,'directories',{}).get(str(Path(os.path.abspath(path))).casefold())
    if record is not None and record['writable']:
        os.fsync(record['fd']);return
    fd=open_directory(path,write=True)
    try:os.fsync(fd)
    finally:os.close(fd)


def filesystem_type(fd):
    fn=_signature(k,'GetVolumeInformationByHandleW',[w.HANDLE,w.LPWSTR,w.DWORD,c.c_void_p,c.c_void_p,c.c_void_p,w.LPWSTR,w.DWORD],w.BOOL)
    filesystem=c.create_unicode_buffer(64)
    _check(fn(_handle(fd),None,0,None,None,None,filesystem,len(filesystem)))
    return filesystem.value.lower()


def lock(fd, *, unlock=False):
    class Overlapped(c.Structure):
        _fields_=[('internal',c.c_size_t),('internalHigh',c.c_size_t),('offset',w.DWORD),('offsetHigh',w.DWORD),('event',w.HANDLE)]
    fn=_signature(k,'UnlockFileEx' if unlock else 'LockFileEx',
        [w.HANDLE,w.DWORD,w.DWORD,w.DWORD,c.POINTER(Overlapped)] if unlock else
        [w.HANDLE,w.DWORD,w.DWORD,w.DWORD,w.DWORD,c.POINTER(Overlapped)],w.BOOL)
    overlap=Overlapped()
    result=fn(_handle(fd),0,1,0,c.byref(overlap)) if unlock else fn(_handle(fd),3,0,1,0,c.byref(overlap))
    if not result:
        code=c.get_last_error()
        if code==33:raise BlockingIOError(errno.EAGAIN,'installation prefix is locked')
        raise c.WinError(code)


def copy_tree(source,destination,*,max_entries,max_file_bytes,max_bytes):
    source_fd=open_directory(source)
    try:destination_fd=open_directory(destination,create=True,exclusive=True,write=True)
    except BaseException:os.close(source_fd);raise
    count=0;total=0
    def copy(parent,target,relative):
        nonlocal count,total
        names=set();folded=set()
        for name in sorted(listdir(parent),key=lambda text:text.encode('utf-8')):
            logical=relative+name
            if len(logical.encode('utf-8'))>1024 or name in names or name.casefold() in folded:
                raise ValueError('invalid, duplicate, or case-colliding cache entry')
            names.add(name);folded.add(name.casefold());count+=1
            if count>max_entries:raise ValueError('cache entry count bound exceeded')
            # Type-neutral metadata open rejects reparses before descent/copy.
            try:child=open_at(parent,name)
            except OSError as error:
                if error.errno==errno.ELOOP:raise ValueError('link or unsupported cache entry') from error
                child=open_at(parent,name,directory=True)
            try:
                before=fstat(child)
                if stat.S_ISDIR(before.st_mode):
                    out=open_at(target,name,directory=True,create=True,exclusive=True,write=True,private=True)
                    try:copy(child,out,logical+'/');os.fsync(out)
                    finally:os.close(out)
                else:
                    if before.st_size>max_file_bytes:raise ValueError('cache file byte bound exceeded')
                    out=open_at(target,name,create=True,exclusive=True,write=True,private=True)
                    size=0
                    try:
                        while True:
                            block=os.read(child,1024*1024)
                            if not block:break
                            size+=len(block);total+=len(block)
                            if size>max_file_bytes or total>max_bytes:raise ValueError('cache byte bound exceeded')
                            view=memoryview(block)
                            while view:
                                written=os.write(out,view)
                                if written<=0:raise OSError('cache write made no progress')
                                view=view[written:]
                        after=fstat(child);named=stat_at(parent,name)
                        identity=lambda value:(value.st_dev,value.st_ino,value.st_size,value.st_mtime_ns,value.st_mode)
                        if size!=before.st_size or identity(before)!=identity(after) or identity(after)!=identity(named):
                            raise ValueError('cache file changed while copying')
                        os.fsync(out)
                    finally:os.close(out)
            finally:os.close(child)
    try:copy(source_fd,destination_fd,'');os.fsync(destination_fd)
    finally:os.close(destination_fd);os.close(source_fd)


def remove_directory(path):
    fd=_pinned(path);own=fd is None
    if own:fd=open_directory(path,write=True,pin=True)
    def clear(directory):
        for name in list(listdir(directory)):
            try:child=open_at(directory,name,delete=True)
            except OSError as error:
                if error.errno==errno.ELOOP:raise ValueError('refusing linked removal') from error
                child=open_at(directory,name,directory=True,write=True,delete=True)
            try:
                if info(child).attributes&0x10:clear(child)
                unlink_fd(child)
            finally:os.close(child)
    try:
        clear(fd)
        if not own:
            parent=open_directory(Path(path).parent)
            try:fd=_delete_handle_for_pinned_directory(path,parent)
            finally:os.close(parent)
        unlink_fd(fd)
    finally:
        if own:os.close(fd)


def rename_handle(fd,parent,name,*,replace=False):
    _rename_or_link(fd,parent,name,replace=replace)


def fsync_file(path):
    path=Path(path);parent=open_directory(path.parent)
    try:fd=open_at(parent,path.name,write=True)
    finally:os.close(parent)
    try:os.fsync(fd)
    finally:os.close(fd)


@contextlib.contextmanager
def writable_directory(path):
    existing=_pinned(path)
    if existing is not None:
        yield existing
    else:
        fd=open_directory(path,write=True)
        try:yield fd
        finally:os.close(fd)


def atomic_write(path,data):
    path=Path(path)
    with writable_directory(path.parent) as parent:
        fd=open_at(parent,path.name+'.tmp',create=True,exclusive=True,write=True,delete=True,private=True)
        try:
            view=memoryview(data)
            while view:
                written=os.write(fd,view)
                if written<=0:raise OSError('native write made no progress')
                view=view[written:]
            os.fsync(fd)
            rename_handle(fd,None,path.name,replace=True)
        finally:os.close(fd)
        os.fsync(parent)


def replace_file(source,destination):
    source=Path(source);destination=Path(destination)
    if source.parent!=destination.parent:raise ValueError('native selector replacement requires the same directory')
    with writable_directory(source.parent) as parent:
        fd=open_at(parent,source.name,delete=True)
        try:rename_handle(fd,None,destination.name,replace=True)
        finally:os.close(fd)
        os.fsync(parent)


def _delete_handle_for_pinned_directory(path,parent):
    registry=_pins.directories;key=str(Path(os.path.abspath(path))).casefold()
    record=registry[key];old=record['fd'];identity=fstat(old)
    record['fd']=None;record['owned'][record['index']]=None;os.close(old)
    fd=open_at(parent,Path(path).name,directory=True,delete=True,pin=True)
    record['fd']=fd;record['owned'][record['index']]=fd;record['writable']=False
    current=fstat(fd)
    if (current.st_dev,current.st_ino)!=(identity.st_dev,identity.st_ino):
        raise ValueError('transaction directory changed before metadata operation')
    return fd


def rename_pinned_directory(path,source_parent,destination_parent,name):
    # Exchange only this guard at the commit boundary. Acquisition remains
    # relative to its still-pinned parent and must retain the exact file ID.
    fd=_delete_handle_for_pinned_directory(path,source_parent)
    rename_handle(fd,destination_parent,name)


def rename_directory_in_place(source,destination):
    source=Path(source);destination=Path(destination)
    if source.parent!=destination.parent:raise ValueError('directory quarantine requires one parent')
    parent=open_directory(source.parent)
    try:fd=open_at(parent,source.name,directory=True,delete=True,pin=True)
    finally:os.close(parent)
    try:rename_handle(fd,None,destination.name)
    finally:os.close(fd)
