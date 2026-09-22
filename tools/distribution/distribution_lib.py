from __future__ import annotations

import gzip
import hashlib
import json
import os
import shutil
import stat
import subprocess
import tarfile
import tempfile
from pathlib import Path
from typing import Iterable


def sha256_file(path: Path) -> tuple[int, str]:
    digest = hashlib.sha256()
    size = 0
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0))
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise ValueError(f"regular file required: {path}")
        while chunk := os.read(descriptor, 1024 * 1024):
            digest.update(chunk)
            size += len(chunk)
        after = os.fstat(descriptor)
        if (before.st_size, before.st_mtime_ns, before.st_mode) != (after.st_size, after.st_mtime_ns, after.st_mode):
            raise ValueError(f"file changed while hashing: {path}")
    finally:
        os.close(descriptor)
    return size, digest.hexdigest()


def regular_files(root: Path) -> list[Path]:
    result = []
    total = 0
    for path in root.rglob("*"):
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not (stat.S_ISDIR(metadata.st_mode) or stat.S_ISREG(metadata.st_mode)):
            raise ValueError(f"unsupported tree entry: {path}")
        if stat.S_ISREG(metadata.st_mode):
            result.append(path)
            total += metadata.st_size
            if len(result) > 100_000 or metadata.st_size > 512 * 1024 * 1024 or total > 2 * 1024 * 1024 * 1024:
                raise ValueError(f"tree bound exceeded: {root}")
    return sorted(result, key=lambda item: item.relative_to(root).as_posix().encode())


def runtime_tree(root: Path) -> dict:
    digest = hashlib.sha256(b"mirrors-runtime-tree-v1\0")
    total = 0
    files = regular_files(root)
    for path in files:
        relative = path.relative_to(root).as_posix()
        size, content = sha256_file(path)
        executable = 1 if path.stat().st_mode & stat.S_IXUSR else 0
        encoded = relative.encode("utf-8")
        digest.update(len(encoded).to_bytes(4, "big") + encoded)
        digest.update(b"\0file\0" + bytes([executable]))
        digest.update(size.to_bytes(8, "big") + bytes.fromhex(content))
        total += size
    return {"algorithm": "mirrors-runtime-tree-v1", "digest": digest.hexdigest(),
        "entryCount": len(files), "bytes": total}


def deterministic_tar(source: Path, output: Path, prefix: str) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="mirrors-tar-") as temporary:
        tar_path = Path(temporary) / "payload.tar"
        with tarfile.open(tar_path, mode="w", format=tarfile.PAX_FORMAT) as archive:
            for path in regular_files(source):
                relative = path.relative_to(source).as_posix()
                info = tarfile.TarInfo(f"{prefix}/{relative}")
                info.size = path.stat().st_size
                info.mode = 0o755 if path.stat().st_mode & stat.S_IXUSR else 0o644
                info.mtime = 0; info.uid = info.gid = 0; info.uname = info.gname = ""
                with path.open("rb") as data:
                    archive.addfile(info, data)
        with output.open("wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
                with tar_path.open("rb") as uncompressed:
                    shutil.copyfileobj(uncompressed, compressed, length=1024 * 1024)


def extract_selected_node(archive_path: Path, destination: Path, root_prefix: str,
    included: Iterable[str]) -> None:
    destination.mkdir(parents=True, exist_ok=False)
    wanted = {f"{root_prefix}/{item}": item for item in included}
    found: set[str] = set()
    headers: set[str] = set(); folded: set[str] = set(); count = 0; total = 0
    with tarfile.open(archive_path, "r:*") as archive:
        for member in archive:
            archive_name = member.name.rstrip("/")
            path = Path(archive_name)
            if path.is_absolute() or ".." in path.parts or "." in path.parts or len(archive_name.encode()) > 1024:
                raise ValueError(f"unsafe Node archive member: {member.name}")
            if archive_name in headers or archive_name.casefold() in folded:
                raise ValueError(f"duplicate or case-colliding Node archive member: {member.name}")
            headers.add(archive_name); folded.add(archive_name.casefold())
            count += 1; total += member.size
            if count > 100_000 or member.size > 512 * 1024 * 1024 or total > 2 * 1024 * 1024 * 1024:
                raise ValueError("Node archive bound exceeded")
            if archive_name not in wanted: continue
            relative = wanted[archive_name]
            if archive_name in found or not member.isfile() or member.issym() or member.islnk() or member.size > 512 * 1024 * 1024:
                raise ValueError(f"selected Node member is not a unique bounded regular file: {archive_name}")
            found.add(archive_name)
            source = archive.extractfile(member)
            if source is None:
                raise ValueError(f"cannot read selected Node member: {archive_name}")
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("xb") as output:
                shutil.copyfileobj(source, output, length=1024 * 1024)
            if target.stat().st_size != member.size:
                raise ValueError(f"selected Node member is truncated: {archive_name}")
            target.chmod(0o755 if relative == "bin/node" else 0o644)
    if found != set(wanted):
        raise ValueError(f"selected Node members missing: {sorted(set(wanted)-found)}")


def extract_selected_tree(archive_path: Path, destination: Path, root_prefix: str,
    included_files: Iterable[str], included_trees: Iterable[str]) -> None:
    destination.mkdir(parents=True, exist_ok=False)
    files = set(included_files)
    trees = tuple(f"{value.rstrip('/')}/" for value in included_trees)
    prefix = root_prefix.rstrip("/") + "/"
    selected = 0
    total = 0; declared_total = 0; header_count = 0
    headers: set[str] = set(); folded: set[str] = set()
    with tarfile.open(archive_path, "r:*") as archive:
        for member in archive:
            name = member.name.rstrip("/")
            path = Path(name)
            if path.is_absolute() or ".." in path.parts or "." in path.parts or len(name.encode()) > 1024:
                raise ValueError(f"unsafe runtime archive member: {member.name}")
            if name in headers or name.casefold() in folded:
                raise ValueError(f"duplicate or case-colliding runtime archive member: {member.name}")
            headers.add(name); folded.add(name.casefold())
            header_count += 1; declared_total += member.size
            if header_count > 100_000 or member.size > 512 * 1024 * 1024 or declared_total > 2 * 1024 * 1024 * 1024:
                raise ValueError("runtime archive bound exceeded")
            if not name.startswith(prefix):
                continue
            relative = name[len(prefix):]
            if relative not in files and not any(relative.startswith(tree) for tree in trees):
                continue
            if member.isdir():
                continue
            path = Path(relative)
            if path.is_absolute() or ".." in path.parts or not member.isfile() or member.issym() or member.islnk():
                raise ValueError(f"selected runtime member is not a regular file: {member.name}")
            total += member.size
            if total > 2 * 1024 * 1024 * 1024 or selected >= 100_000:
                raise ValueError("selected runtime extraction bound exceeded")
            source = archive.extractfile(member)
            if source is None:
                raise ValueError(f"cannot read selected runtime member: {member.name}")
            target = destination / path
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("xb") as output:
                shutil.copyfileobj(source, output, length=1024 * 1024)
            if target.stat().st_size != member.size:
                raise ValueError(f"selected runtime member is truncated: {member.name}")
            target.chmod(0o755 if member.mode & 0o111 else 0o644)
            selected += 1
    if selected == 0:
        raise ValueError("runtime selection produced no regular files")


def dynamic_libraries(path: Path, ldd_bin: Path) -> list[dict]:
    result = subprocess.run([str(ldd_bin), str(path)], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise ValueError(f"ldd failed for {path}: {result.stderr.strip()}")
    libraries: dict[str, dict] = {}
    for line in result.stdout.splitlines():
        line = line.strip()
        resolved = None
        soname = None
        if "=>" in line:
            soname, tail = [part.strip() for part in line.split("=>", 1)]
            candidate = tail.split(" ", 1)[0]
            if candidate.startswith("/"):
                resolved = candidate
        elif line.startswith("/"):
            candidate = line.split(" ", 1)[0]
            resolved = candidate
            soname = Path(candidate).name
        if resolved and soname:
            resolved_path = Path(resolved).resolve()
            _size, digest = sha256_file(resolved_path)
            libraries[soname] = {"soname": soname, "path": str(resolved_path), "sha256": digest}
    if not libraries:
        raise ValueError(f"no dynamic-library identity found for {path}")
    return [libraries[key] for key in sorted(libraries)]


def write_json(path: Path, value: dict) -> None:
    data = (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()
    temporary = path.with_name(path.name + ".tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        offset = 0
        while offset < len(data):
            offset += os.write(descriptor, data[offset:])
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.replace(temporary, path)
    directory = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
