"""Owner-only, descriptor-relative filesystem primitives for evidence bundles."""

from __future__ import annotations

import hashlib
import errno
import os
import stat
from pathlib import Path


MAX_RECORD_BYTES = 64 * 1024 * 1024
_DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0)


def logical_path(value: str) -> Path:
    if not value or value.startswith("/") or "\\" in value or "\x00" in value:
        raise ValueError(f"unsafe bundle path: {value!r}")
    parts = value.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise ValueError(f"unsafe bundle path: {value!r}")
    return Path(*parts)


def _absolute_parts(path: Path) -> tuple[str, ...]:
    absolute = Path(os.path.abspath(path))
    return absolute.parts[1:]


def _open_directory_chain(path: Path, *, create_missing: bool = False) -> int:
    descriptor = os.open("/", _DIRECTORY_FLAGS)
    try:
        for component in _absolute_parts(path):
            try:
                next_descriptor = os.open(component, _DIRECTORY_FLAGS, dir_fd=descriptor)
            except FileNotFoundError:
                if not create_missing:
                    raise
                os.mkdir(component, 0o700, dir_fd=descriptor)
                next_descriptor = os.open(component, _DIRECTORY_FLAGS, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = next_descriptor
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def _check_owner_directory(descriptor: int, path: Path) -> None:
    info = os.fstat(descriptor)
    if not stat.S_ISDIR(info.st_mode):
        raise ValueError(f"evidence path is not a real directory: {path}")
    if hasattr(os, "getuid") and info.st_uid != os.getuid():
        raise ValueError(f"evidence directory is not owned by the current user: {path}")
    if stat.S_IMODE(info.st_mode) & 0o077:
        raise ValueError(f"evidence directory must use owner-only permissions: {path}")


def ensure_owner_directory(path: Path, *, create: bool = False) -> None:
    descriptor = _open_directory_chain(path, create_missing=create)
    try:
        _check_owner_directory(descriptor, path)
    finally:
        os.close(descriptor)


def open_owner_directory(path: Path) -> int:
    """Return a pinned owner-only directory descriptor; caller closes it."""
    descriptor = _open_directory_chain(path)
    try:
        _check_owner_directory(descriptor, path)
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def create_owner_directory(path: Path) -> None:
    descriptor = _open_directory_chain(path, create_missing=True)
    try:
        _check_owner_directory(descriptor, path)
    finally:
        os.close(descriptor)


def create_owner_directory_exclusive(path: Path) -> None:
    parent = _open_directory_chain(path.parent)
    child = -1
    try:
        os.mkdir(path.name, 0o700, dir_fd=parent)
        child = os.open(path.name, _DIRECTORY_FLAGS, dir_fd=parent)
        _check_owner_directory(child, path)
    finally:
        if child >= 0:
            os.close(child)
        os.close(parent)


def read_regular(path: Path, *, max_bytes: int = MAX_RECORD_BYTES) -> tuple[bytes, str]:
    parent = _open_directory_chain(path.parent)
    descriptor = -1
    try:
        try:
            descriptor = os.open(
                path.name,
                os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0),
                dir_fd=parent,
            )
        except OSError as error:
            if error.errno in {errno.ELOOP, errno.ENXIO}:
                raise ValueError(f"evidence record is not a regular file: {path}") from error
            raise
        opened = os.fstat(descriptor)
        if not stat.S_ISREG(opened.st_mode):
            raise ValueError(f"evidence record is not a regular file: {path}")
        if opened.st_size > max_bytes:
            raise ValueError(f"evidence record exceeds {max_bytes} bytes: {path}")
        digest = hashlib.sha256()
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                raise ValueError(f"evidence record exceeds {max_bytes} bytes: {path}")
            chunks.append(chunk)
            digest.update(chunk)
        closed = os.fstat(descriptor)
        stable = (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns, opened.st_mode)
        if stable != (closed.st_dev, closed.st_ino, closed.st_size, closed.st_mtime_ns, closed.st_mode):
            raise ValueError(f"evidence record changed while reading: {path}")
        named = os.stat(path.name, dir_fd=parent, follow_symlinks=False)
        if stable != (named.st_dev, named.st_ino, named.st_size, named.st_mtime_ns, named.st_mode):
            raise ValueError(f"evidence record changed while reading: {path}")
        if total != opened.st_size:
            raise ValueError(f"evidence record size changed while reading: {path}")
        return b"".join(chunks), digest.hexdigest()
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        os.close(parent)


def write_exclusive(path: Path, data: bytes) -> None:
    parent = _open_directory_chain(path.parent)
    descriptor = -1
    try:
        descriptor = os.open(
            path.name,
            os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0),
            0o600,
            dir_fd=parent,
        )
        os.fchmod(descriptor, 0o600)
        view = memoryview(data)
        while view:
            written = os.write(descriptor, view)
            view = view[written:]
        os.fsync(descriptor)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        os.close(parent)


def publish_exclusive(directory: Path, temporary_name: str, final_name: str) -> None:
    descriptor = _open_directory_chain(directory)
    try:
        os.link(
            temporary_name,
            final_name,
            src_dir_fd=descriptor,
            dst_dir_fd=descriptor,
            follow_symlinks=False,
        )
        os.unlink(temporary_name, dir_fd=descriptor)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def fsync_directory(path: Path) -> None:
    descriptor = _open_directory_chain(path)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
