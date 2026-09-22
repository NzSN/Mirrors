#!/usr/bin/env python3
"""Run a registered command and create bounded, incomplete staging evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

from command_registry import parse_registry, select_command
from store import (create_owner_directory, create_owner_directory_exclusive,
                   open_owner_directory, read_regular, write_exclusive)
from validate import ROOT as EVIDENCE_ROOT, load_json, loads_json_bytes


ROOT = Path(__file__).resolve().parent
DEFAULT_REGISTRY = ROOT / "commands.json"
DEFAULT_OUTPUT_LIMIT = 4 * 1024 * 1024
MAX_DIRTY_FILE_BYTES = 512 * 1024 * 1024
MAX_DIRTY_TOTAL_BYTES = 512 * 1024 * 1024
MAX_ATTACHMENT_PLAN_BYTES = 64 * 1024
MAX_ATTACHMENTS = 256
MAX_ATTACHMENT_BYTES = 64 * 1024 * 1024
ATTACHMENT_ROLES = frozenset(("cleanup-receipt", "producer-result",
    "distribution-manifest", "cache-index", "diagnostic",
    "reproduction-input", "recovery-receipt"))
GATE_RECOVERY_RESULTS = frozenset(("reclaimed", "failed", "ambiguous", "retained", "unconfirmed"))
GATE_RECOVERY_BEHAVIORS = frozenset(("passed", "failed", "inconclusive", "not_run"))
GATE_RECOVERY_CLEANUPS = frozenset(("confirmed", "failed", "unconfirmed", "not_applicable"))
GATE_RECOVERY_CGROUP_FIELDS = frozenset(("pids.current", "pids.events", "memory.current",
    "memory.peak", "memory.events", "cpu.stat", "cgroup.events"))
GATE_RECOVERY_CGROUP_SETTINGS = frozenset(("pids.max", "memory.max", "memory.swap.max", "cpu.max"))
LOCAL_CAMPAIGNS = {
    "work-queue": [
        ("duplicate-accepts", 0, 2, "enqueue"),
        ("enqueue-drops", 0, 1, "enqueue"),
        ("enqueue-in-flight", 0, 5, "enqueue"),
        ("start-stale", 0, 4, "start"),
        ("fail-does-not-mark", 0, 6, "fail"),
        ("retry-does-not-clear", 0, 7, "retry"),
        ("complete-keeps-in-flight", 0, 8, "complete"),
        ("complete-stale", 0, 8, "complete"),
        ("reset-leaves-state", 1, 0, "init"),
    ],
    "persistent-transfer": [
        ("premature-success", 0, 3, "commit"),
        ("duplicate-retry", 0, 7, "chunk"),
        ("stale-session", 0, 13, "chunk"),
        ("corrupt-content", 0, 2, "chunk"),
    ],
    "lease-service": [
        ("overlapping-ownership", 0, 2, "acquire"),
        ("expired-token", 0, 5, "write"),
        ("stale-release", 0, 7, "release"),
        ("invalid-renewal", 0, 8, "renew"),
    ],
}


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _canonical_json(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def _write_private(path: Path, data: bytes) -> None:
    write_exclusive(path, data)


def _git(path: Path, *args: str) -> bytes:
    result = subprocess.run(
        ["git", "-C", str(path), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        message = result.stderr.decode("utf-8", "replace").strip()
        raise ValueError(f"git {' '.join(args)} failed for {path}: {message}")
    return result.stdout


def _logical_path(value: str) -> str:
    if not value or value.startswith("/") or "\\" in value or "\x00" in value:
        raise ValueError(f"invalid logical path: {value!r}")
    parts = value.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise ValueError(f"invalid logical path: {value!r}")
    return value


def _changed_paths(repository: Path) -> list[str]:
    tracked = _git(repository, "diff", "--no-renames", "--name-only", "-z", "HEAD").split(b"\0")
    untracked = _git(repository, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0")
    result: set[str] = set()
    for raw in tracked + untracked:
        if not raw:
            continue
        result.add(_logical_path(raw.decode("utf-8")))
    return sorted(result)


def _selected_content_digest(
    repository: Path, revision: str, included: list[str], excluded: list[dict[str, str]]
) -> str:
    digest = hashlib.sha256()
    digest.update(b"mirrors-dirty-content-v1\0")
    digest.update(revision.encode("ascii"))
    total_bytes = 0
    for path in included:
        full = repository / path
        try:
            before = full.lstat()
        except FileNotFoundError:
            before = None
        content_digest = hashlib.sha256()
        if before is None:
            kind, mode, size = b"deleted", 0, 0
        elif stat.S_ISLNK(before.st_mode):
            kind, mode = b"symlink", stat.S_IMODE(before.st_mode)
            target = os.readlink(full).encode("utf-8")
            size = len(target)
            if total_bytes + size > MAX_DIRTY_TOTAL_BYTES:
                raise ValueError(f"dirty source hashing limit exceeded at: {path}")
            content_digest.update(target)
            after = full.lstat()
            if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_mode) != (
                after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_mode
            ) or os.readlink(full).encode("utf-8") != target:
                raise ValueError(f"dirty source changed while hashing: {path}")
        elif stat.S_ISREG(before.st_mode):
            kind, mode, size = b"file", stat.S_IMODE(before.st_mode), before.st_size
            if size > MAX_DIRTY_FILE_BYTES or total_bytes + size > MAX_DIRTY_TOTAL_BYTES:
                raise ValueError(f"dirty source hashing limit exceeded at: {path}")
            with full.open("rb") as handle:
                opened = os.fstat(handle.fileno())
                while chunk := handle.read(1024 * 1024):
                    content_digest.update(chunk)
                closed = os.fstat(handle.fileno())
            stable = (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns, opened.st_mode)
            if stable != (closed.st_dev, closed.st_ino, closed.st_size, closed.st_mtime_ns, closed.st_mode):
                raise ValueError(f"dirty source changed while hashing: {path}")
            after = full.lstat()
            if stable != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_mode):
                raise ValueError(f"dirty source changed while hashing: {path}")
        else:
            raise ValueError(f"dirty path is not a regular file or symlink: {path}")
        total_bytes += size
        encoded = path.encode("utf-8")
        digest.update(len(encoded).to_bytes(4, "big"))
        digest.update(encoded)
        digest.update(b"\0" + kind + b"\0")
        digest.update(mode.to_bytes(4, "big"))
        digest.update(size.to_bytes(8, "big"))
        digest.update(content_digest.digest())
    for entry in excluded:
        digest.update(b"excluded\0")
        digest.update(entry["path"].encode("utf-8"))
        digest.update(b"\0")
        digest.update(entry["reasonCode"].encode("ascii"))
    return digest.hexdigest()


def component_ref(component_id: str, repository: Path, exclusions: dict[str, str]) -> dict[str, Any]:
    root = Path(_git(repository, "rev-parse", "--show-toplevel").decode().strip()).resolve()
    revision = _git(root, "rev-parse", "HEAD").decode("ascii").strip()
    remote_result = subprocess.run(
        ["git", "-C", str(root), "config", "--get", "remote.origin.url"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    remote = remote_result.stdout.decode("utf-8").strip() if remote_result.returncode == 0 else ""
    changed = _changed_paths(root)
    excluded_paths = [
        {"path": path, "reasonCode": exclusions[path]}
        for path in changed
        if path in exclusions
    ]
    included = [path for path in changed if path not in exclusions]
    result: dict[str, Any] = {
        "componentId": component_id,
        "repository": remote or str(root),
        "revision": revision,
        "dirty": bool(changed),
    }
    if changed:
        result["dirtyContent"] = {
            "algorithm": "sha256",
            "digest": _selected_content_digest(root, revision, included, excluded_paths),
            "method": "git-diff-and-untracked-manifest-v1",
            "includedPaths": included,
            "excludedPaths": excluded_paths,
        }
    return result


@dataclass
class ChildObservation:
    returncode: int | None
    timed_out: bool
    unavailable: bool
    stdout: bytes
    stderr: bytes
    stdout_exceeded: bool
    stderr_exceeded: bool


@dataclass(frozen=True)
class AttachmentSpec:
    artifact_id: str
    relative_path: str
    role: str
    media_type: str
    requirement: str
    capture_mode: str
    max_bytes: int
    expected_sha256: str | None
    producer_result: dict[str, str] | None
    before_identity: tuple[int, int, int, int, int] | None


@dataclass
class AttachmentPlan:
    path: Path
    source_root: Path
    root_fd: int
    root_identity: tuple[int, int]
    application: str | None
    adapter_kind: str
    adapter_artifact_id: str | None
    attachments: list[AttachmentSpec]

    def close(self) -> None:
        if self.root_fd >= 0:
            os.close(self.root_fd)
            self.root_fd = -1


def _attachment_id(value: Any, label: str) -> str:
    if (type(value) is not str or not value or len(value) > 128
            or value[0] not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            or any(char not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-" for char in value)):
        raise ValueError(f"invalid attachment {label}")
    return value


def _attachment_schema(value: Any) -> str:
    if (type(value) is not str or not value or len(value) > 256
            or any(char not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/-" for char in value)):
        raise ValueError("invalid attachment producer schemaVersion")
    return value


def _attachment_identity(info: os.stat_result) -> tuple[int, int, int, int, int]:
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_mode)


def _attachment_stat(root_fd: int, name: str) -> os.stat_result | None:
    try:
        return os.stat(name, dir_fd=root_fd, follow_symlinks=False)
    except FileNotFoundError:
        return None


def prepare_attachment_plan(path: Path) -> AttachmentPlan:
    raw, _digest = read_regular(path, max_bytes=MAX_ATTACHMENT_PLAN_BYTES)
    document = loads_json_bytes(raw)
    if (type(document) is not dict or set(document) != {
            "schemaVersion", "sourceRoot", "application", "adapter", "attachments"}):
        raise ValueError("attachment plan uses an unknown or missing field")
    if document["schemaVersion"] != "mirrors.evidence-attachment-plan/v1":
        raise ValueError("unsupported attachment plan schema")
    source_root_value = document["sourceRoot"]
    if type(source_root_value) is not str or not Path(source_root_value).is_absolute():
        raise ValueError("attachment sourceRoot must be absolute")
    source_root = Path(source_root_value)
    root_fd = open_owner_directory(source_root)
    try:
        root_info = os.fstat(root_fd)
        application = document["application"]
        if application is not None:
            application = _attachment_id(application, "application")
        adapter = document["adapter"]
        if type(adapter) is not dict or set(adapter) != {"kind", "artifactId"}:
            raise ValueError("attachment adapter uses an unknown or missing field")
        adapter_kind = adapter["kind"]
        if adapter_kind not in ("none", "mirrorecma.application-campaign-aggregate/v1",
                                "mirrorecma.lease-reduction-oracle/v1",
                                "mirrorgate.application-validation/v2",
                                "mirrorgate.application-validation-aggregate/v1",
                                "mirrorgate.recovery-receipt/v1"):
            raise ValueError("unsupported attachment adapter")
        adapter_artifact_id = adapter["artifactId"]
        if adapter_artifact_id is not None:
            adapter_artifact_id = _attachment_id(adapter_artifact_id, "adapter artifactId")
        values = document["attachments"]
        if type(values) is not list or not values or len(values) > MAX_ATTACHMENTS:
            raise ValueError("attachment plan requires a bounded nonempty attachment array")
        specs: list[AttachmentSpec] = []
        ids: set[str] = set()
        names: set[str] = set()
        for index, value in enumerate(values):
            required = {"artifactId", "relativePath", "role", "mediaType", "requirement",
                        "captureMode", "maxBytes", "expectedSha256", "producerResult"}
            if type(value) is not dict or set(value) != required:
                raise ValueError(f"attachment[{index}] uses an unknown or missing field")
            artifact_id = _attachment_id(value["artifactId"], "artifactId")
            if artifact_id in ids or artifact_id in {
                    "command-stdout", "command-stderr", "component-snapshots"}:
                raise ValueError("duplicate attachment artifactId")
            ids.add(artifact_id)
            relative = _logical_path(value["relativePath"])
            if "/" in relative:
                raise ValueError("attachment relativePath must be one predeclared root file")
            if relative in names:
                raise ValueError("duplicate attachment relativePath")
            names.add(relative)
            role = value["role"]
            if role not in ATTACHMENT_ROLES:
                raise ValueError("unsupported attachment role")
            media_type = value["mediaType"]
            if type(media_type) is not str or not media_type or len(media_type) > 256:
                raise ValueError("invalid attachment mediaType")
            requirement = value["requirement"]
            if requirement not in ("required", "optional"):
                raise ValueError("invalid attachment requirement")
            capture_mode = value["captureMode"]
            if capture_mode not in ("new-output", "existing-input"):
                raise ValueError("invalid attachment captureMode")
            max_bytes = value["maxBytes"]
            if type(max_bytes) is not int or not 0 <= max_bytes <= MAX_ATTACHMENT_BYTES:
                raise ValueError("invalid attachment maxBytes")
            expected_sha256 = value["expectedSha256"]
            if expected_sha256 is not None and (type(expected_sha256) is not str
                    or len(expected_sha256) != 64
                    or any(char not in "0123456789abcdef" for char in expected_sha256)):
                raise ValueError("invalid attachment expectedSha256")
            producer = value["producerResult"]
            if producer is not None:
                if type(producer) is not dict or set(producer) != {"producer", "schemaVersion"}:
                    raise ValueError("invalid attachment producerResult")
                if role != "producer-result":
                    raise ValueError("attachment producerResult requires the producer-result role")
                producer = {"producer": _attachment_id(producer["producer"], "producer"),
                            "schemaVersion": _attachment_schema(producer["schemaVersion"])}
            before = _attachment_stat(root_fd, relative)
            if capture_mode == "new-output":
                if expected_sha256 is not None or before is not None:
                    raise ValueError(f"new attachment output must be absent before execution: {relative}")
                before_identity = None
            else:
                if expected_sha256 is None or before is None or not stat.S_ISREG(before.st_mode):
                    raise ValueError(f"existing attachment input is unavailable: {relative}")
                before_identity = _attachment_identity(before)
            specs.append(AttachmentSpec(artifact_id, relative, role, media_type,
                requirement, capture_mode, max_bytes, expected_sha256, producer,
                before_identity))
        if adapter_kind not in ("none", "mirrorgate.application-validation-aggregate/v1") and (adapter_artifact_id is None
                or adapter_artifact_id not in ids):
            raise ValueError("attachment adapter artifactId does not resolve")
        if adapter_kind == "mirrorgate.application-validation/v2" and application is None:
            raise ValueError("Gate campaign attachment adapter requires application")
        if adapter_kind == "mirrorgate.recovery-receipt/v1" and application is not None:
            raise ValueError("Gate recovery attachment adapter does not accept an application")
        if adapter_kind == "mirrorgate.application-validation-aggregate/v1" and (
                application is not None or adapter_artifact_id is not None):
            raise ValueError("Gate aggregate adapter uses its fixed three receipt identities")
        plan = AttachmentPlan(path, source_root, root_fd,
            (root_info.st_dev, root_info.st_ino), application, adapter_kind,
            adapter_artifact_id, specs)
        for spec in specs:
            if spec.capture_mode == "existing-input":
                _read_attachment(plan, spec)
        return plan
    except BaseException:
        os.close(root_fd)
        raise


def _read_attachment(plan: AttachmentPlan, spec: AttachmentSpec) -> bytes:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    descriptor = os.open(spec.relative_path, flags, dir_fd=plan.root_fd)
    try:
        opened = os.fstat(descriptor)
        if (not stat.S_ISREG(opened.st_mode) or opened.st_uid != os.geteuid()
                or stat.S_IMODE(opened.st_mode) != 0o600):
            raise ValueError(f"attachment must be an owner mode-0600 regular file: {spec.relative_path}")
        if opened.st_size > spec.max_bytes:
            raise ValueError(f"attachment exceeds declared bound: {spec.relative_path}")
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, min(1024 * 1024, spec.max_bytes + 1 - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if total > spec.max_bytes:
                raise ValueError(f"attachment exceeds declared bound: {spec.relative_path}")
        closed = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    named = os.stat(spec.relative_path, dir_fd=plan.root_fd, follow_symlinks=False)
    identity = _attachment_identity(opened)
    if identity != _attachment_identity(closed) or identity != _attachment_identity(named):
        raise ValueError(f"attachment changed while reading: {spec.relative_path}")
    if spec.before_identity is not None and identity != spec.before_identity:
        raise ValueError(f"existing attachment changed during execution: {spec.relative_path}")
    data = b"".join(chunks)
    if len(data) != opened.st_size:
        raise ValueError(f"attachment size changed while reading: {spec.relative_path}")
    digest = _sha256(data)
    if spec.expected_sha256 is not None and digest != spec.expected_sha256:
        raise ValueError(f"attachment SHA-256 differs: {spec.relative_path}")
    return data


def capture_attachments(plan: AttachmentPlan | None, private: Path, run_id: str) -> tuple[
        list[dict[str, Any]], list[dict[str, str]], dict[str, bytes], list[str], list[str]]:
    if plan is None:
        return [], [], {}, [], []
    root = os.fstat(plan.root_fd)
    if (root.st_dev, root.st_ino) != plan.root_identity:
        raise ValueError("attachment source root identity changed")
    artifacts: list[dict[str, Any]] = []
    producer_results: list[dict[str, str]] = []
    captured: dict[str, bytes] = {}
    missing: list[str] = []
    failures: list[str] = []
    total = 0
    for index, spec in enumerate(plan.attachments):
        try:
            data = _read_attachment(plan, spec)
            if spec.role == "reproduction-input":
                value = loads_json_bytes(data)
                try:
                    origin_run = value["evidenceLinks"]["runRef"]["runId"]
                except (KeyError, TypeError):
                    raise ValueError("reproduction attachment lacks originating runRef")
                if origin_run == run_id:
                    raise ValueError("reproduction attachment self-references enclosing run")
            total += len(data)
            if total > 512 * 1024 * 1024:
                raise ValueError("attachment aggregate exceeds 512 MiB")
            filename = f"attachment-{index:03d}.bin"
            relative = f"artifacts/private/{filename}"
            _write_private(private / filename, data)
            artifact = _artifact(spec.artifact_id, spec.role, relative, data,
                                 spec.requirement)
            artifact["mediaType"] = spec.media_type
            artifacts.append(artifact)
            captured[spec.artifact_id] = data
            if spec.producer_result is not None:
                producer_results.append({**spec.producer_result,
                    "artifactId": spec.artifact_id})
        except (OSError, ValueError) as error:
            failures.append(f"{spec.artifact_id}:{type(error).__name__}")
            if spec.requirement == "required":
                missing.append(spec.artifact_id)
    after = os.fstat(plan.root_fd)
    if (after.st_dev, after.st_ino) != plan.root_identity:
        raise ValueError("attachment source root identity changed")
    return artifacts, producer_results, captured, missing, failures


def run_child(argv: list[str], cwd: Path, timeout: float, output_limit: int) -> ChildObservation:
    try:
        child = subprocess.Popen(
            argv,
            cwd=cwd,
            stdin=None,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
    except OSError as error:
        message = f"{type(error).__name__}: {error}\n".encode("utf-8", "replace")
        sys.stderr.buffer.write(message)
        sys.stderr.buffer.flush()
        return ChildObservation(None, False, True, b"", message[:output_limit], False, len(message) > output_limit)

    assert child.stdout is not None and child.stderr is not None
    original_handlers: dict[int, Any] = {}
    forwarded: list[int] = []
    for signum in (signal.SIGINT, signal.SIGTERM):
        original_handlers[signum] = signal.getsignal(signum)

        def forward(received: int, _frame: Any) -> None:
            forwarded.append(received)
            if child.poll() is None:
                try:
                    os.killpg(child.pid, received)
                except ProcessLookupError:
                    pass

        signal.signal(signum, forward)
    selector = selectors.DefaultSelector()
    stdout_buffer = bytearray()
    stderr_buffer = bytearray()
    selector.register(child.stdout, selectors.EVENT_READ, (sys.stdout.buffer, stdout_buffer, "stdout"))
    selector.register(child.stderr, selectors.EVENT_READ, (sys.stderr.buffer, stderr_buffer, "stderr"))
    started = time.monotonic()
    deadline = started + timeout
    timed_out = False
    termination_started: float | None = None
    killed = False
    exceeded = {"stdout": False, "stderr": False}
    try:
        while child.poll() is None or selector.get_map():
            now = time.monotonic()
            if forwarded and termination_started is None:
                termination_started = now
            if now >= deadline and termination_started is None:
                timed_out = True
                termination_started = now
                try:
                    os.killpg(child.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            if termination_started is not None and now - termination_started >= 1.0 and not killed:
                killed = True
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            if termination_started is not None and now - termination_started >= 2.0:
                break
            events = selector.select(timeout=0.05)
            for key, _ in events:
                sink, captured, name = key.data
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                try:
                    sink.write(chunk)
                    sink.flush()
                except (BrokenPipeError, OSError):
                    pass
                capacity = output_limit - len(captured)
                if capacity > 0:
                    captured.extend(chunk[:capacity])
                if len(chunk) > max(capacity, 0):
                    exceeded[name] = True
        if child.poll() is None:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        returncode = child.wait(timeout=1.0)
    finally:
        for signum, handler in original_handlers.items():
            signal.signal(signum, handler)
        selector.close()
        child.stdout.close()
        child.stderr.close()
    return ChildObservation(
        returncode,
        timed_out,
        False,
        bytes(stdout_buffer),
        bytes(stderr_buffer),
        exceeded["stdout"],
        exceeded["stderr"],
    )


def _registry_command(path: Path, command_id: str) -> tuple[dict[str, Any], str, str]:
    raw, registry_digest = read_regular(path, max_bytes=256 * 1024)
    registry = parse_registry(raw)
    return select_command(registry, command_id), registry_digest, raw.decode("utf-8")


def _executable_identity(requested: str, cwd: Path) -> dict[str, Any]:
    selected = (requested if os.path.isabs(requested)
                else str(cwd / requested) if "/" in requested
                else shutil.which(requested))
    if selected is None:
        return {"requested": requested, "resolution": "unavailable"}
    path = Path(selected).resolve()
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except FileNotFoundError:
        return {"requested": requested, "resolution": "unavailable"}
    digest = hashlib.sha256()
    total = 0
    try:
        opened = os.fstat(descriptor)
        if not stat.S_ISREG(opened.st_mode):
            raise ValueError(f"registered executable is not a regular file: {path}")
        while chunk := os.read(descriptor, 1024 * 1024):
            total += len(chunk)
            if total > 512 * 1024 * 1024:
                raise ValueError(f"registered executable exceeds 512 MiB: {path}")
            digest.update(chunk)
        closed = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    named = path.lstat()
    identity = lambda value: (value.st_dev, value.st_ino, value.st_size,
                              value.st_mtime_ns, value.st_mode)
    if identity(opened) != identity(closed) or identity(closed) != identity(named):
        raise ValueError(f"registered executable changed while hashing: {path}")
    if total != opened.st_size or total == 0:
        raise ValueError(f"registered executable size changed or is empty: {path}")
    return {"requested": requested, "resolution": "available", "resolvedPath": str(path),
            "bytes": total, "sha256": digest.hexdigest()}


def _command_context(args: argparse.Namespace, entry: dict[str, Any], registry_digest: str,
        registry_raw: str,
        components: list[dict[str, Any]]) -> bytes:
    environment = [{"name": key, "value": value}
                   for key, value in sorted(entry.get("requiredEnvironment", {}).items())]
    for name in sorted(entry.get("requiredEnvironmentNames", [])):
        environment.append({"name": name, "value": os.environ[name]})
    path_prefix = entry.get("requiredPathPrefix")
    if path_prefix is not None:
        environment.append({"name": "PATH_PREFIX", "value": path_prefix})
    environment_files = []
    for name, expected in sorted(entry.get("requiredEnvironmentFileSha256", {}).items()):
        identity = _executable_identity(os.environ[name], args.cwd)
        if identity.get("resolution") != "available" or identity.get("sha256") != expected:
            raise ValueError(f"registered environment file identity differs: {name}")
        environment_files.append({"name":name, **identity})
    owner_id = entry.get("registryOwnerComponentId", components[0]["componentId"])
    owners = [component for component in components if component["componentId"] == owner_id]
    if len(owners) != 1:
        raise ValueError("registry owner component does not resolve in collected components")
    context = {
        "schemaVersion": "mirrors.evidence-command-context/v1",
        "registry": {"schemaVersion": "mirrors.evidence-command-registry/v1",
                     "sha256": registry_digest, "rawUtf8": registry_raw,
                     "ownerComponentRef": owners[0],
                     "selectedEntry": entry},
        "command": {"commandId": args.command_id, "argv": args.command,
                    "cwd": str(args.cwd), "effectiveEnvironment": environment,
                    "environmentFiles": environment_files},
        "executable": _executable_identity(args.command[0], args.cwd),
    }
    errors = list(Draft202012Validator(
        load_json(EVIDENCE_ROOT / "schema/command-context-v1.schema.json")
    ).iter_errors(context))
    if errors:
        raise ValueError("collector command-context is invalid: " + "; ".join(
            error.message for error in errors))
    return _canonical_json(context)


def _component_argument(value: str) -> tuple[str, Path]:
    component_id, separator, path = value.partition("=")
    if not separator or not component_id or not path:
        raise argparse.ArgumentTypeError("component must be COMPONENT_ID=PATH")
    return component_id, Path(path).resolve()


def _exclusion_argument(value: str) -> tuple[str, str, str]:
    owner_path, separator, reason = value.partition("=")
    owner, colon, path = owner_path.partition(":")
    if not separator or not colon or reason not in {"pre-existing-unrelated", "evidence-output", "build-output"}:
        raise argparse.ArgumentTypeError("exclusion must be COMPONENT_ID:PATH=REASON")
    return owner, _logical_path(path), reason


def _default_store() -> Path:
    configured = os.environ.get("MIRRORS_EVIDENCE_ROOT")
    if configured:
        return Path(configured).resolve()
    state = os.environ.get("XDG_STATE_HOME")
    base = Path(state).resolve() if state else Path.home() / ".local" / "state"
    return base / "mirrors" / "evidence" / "v1"


def _catalog_selection(
    args: argparse.Namespace,
    entry: dict[str, Any],
    components: dict[str, Path],
    before: list[dict[str, Any]],
) -> dict[str, str]:
    if args.catalog_selection_kind is not None or args.catalog_selection_value is not None:
        if args.catalog_selection_kind is None or args.catalog_selection_value is None:
            raise ValueError("catalog selection kind and value must be supplied together")
        return {
            "schemaVersion": "mirrors.framework-catalog/v1",
            "selectionKind": args.catalog_selection_kind,
            "selectionValue": args.catalog_selection_value,
        }
    configured = entry.get("catalogSelectionRef")
    if configured is not None:
        return configured
    component_id = entry.get("catalogComponentId")
    catalog_path = entry.get("catalogPath")
    if not isinstance(component_id, str) or not isinstance(catalog_path, str) or component_id not in components:
        raise ValueError("registry does not provide a catalog selection")
    selected = next(component for component in before if component["componentId"] == component_id)
    if selected["dirty"]:
        raise ValueError("dirty catalog checkout requires an explicit sha256 catalog selection")
    _git(components[component_id], "ls-files", "--error-unmatch", catalog_path)
    return {
        "schemaVersion": "mirrors.framework-catalog/v1",
        "selectionKind": "git-revision",
        "selectionValue": selected["revision"],
    }


def _exit_record(observation: ChildObservation) -> dict[str, Any]:
    if observation.returncode is None:
        return {"kind": "not-started"}
    if observation.returncode < 0:
        return {"kind": "signal", "signal": signal.Signals(-observation.returncode).name}
    return {"kind": "code", "code": observation.returncode}


def _outcomes(observation: ChildObservation) -> tuple[dict[str, str], str, str]:
    if observation.unavailable:
        return {"status": "inconclusive", "classification": {"namespace": "collector", "code": "unavailable-executable"}}, "unavailable", "unavailable-executable"
    if observation.timed_out:
        return {"status": "inconclusive", "classification": {"namespace": "collector", "code": "timeout"}}, "failed", "timeout"
    assert observation.returncode is not None
    if observation.returncode == 0:
        return {"status": "passed", "classification": {"namespace": "process", "code": "exit-0"}}, "passed", "passed"
    if observation.returncode < 0:
        name = signal.Signals(-observation.returncode).name.lower()
        return {"status": "failed", "classification": {"namespace": "process", "code": f"signal-{name}"}}, "failed", f"signal-{name}"
    return {"status": "failed", "classification": {"namespace": "process", "code": f"exit-{observation.returncode}"}}, "failed", f"exit-{observation.returncode}"


def _closed_record(value: Any, required: set[str], optional: set[str], label: str) -> dict[str, Any]:
    if type(value) is not dict or set(value) - required - optional or required - set(value):
        raise ValueError(f"{label} is not a closed record")
    return value


def _sha_identity(value: Any, label: str) -> dict[str, str]:
    item = _closed_record(value, {"id", "sha256"}, set(), label)
    identity_id = item["id"]
    if (type(identity_id) is not str or not identity_id or len(identity_id) > 256
            or identity_id[0] not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            or any(character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:/+-"
                   for character in identity_id)):
        raise ValueError(f"{label} ID is invalid")
    if (type(item["sha256"]) is not str or len(item["sha256"]) != 64
            or any(character not in "0123456789abcdef" for character in item["sha256"])):
        raise ValueError(f"{label} SHA-256 is invalid")
    return item


def _campaign_cleanup(value: Any, required_scopes: set[str]) -> None:
    if type(value) is not list or not value or len(value) > 8:
        raise ValueError("mutation cleanup is invalid")
    scopes: set[str] = set()
    for item in value:
        item = _closed_record(item, {"scope", "requirement", "status"}, {"code"},
                              "mutation cleanup item")
        if item["scope"] in scopes:
            raise ValueError("mutation cleanup scope is duplicate")
        scopes.add(item["scope"])
        if item["scope"] in required_scopes and (item["requirement"] != "required"
                or item["status"] != "confirmed"):
            raise ValueError("required mutation cleanup is not confirmed")
    if not required_scopes <= scopes:
        raise ValueError("required mutation cleanup scope is absent")


def _physical_cleanup(value: Any) -> None:
    if (type(value) is not dict or value.get("status") != "confirmed"
            or value.get("remainingResources") != [] or value.get("failures") != []):
        raise ValueError("Gate physical cleanup is not confirmed")


def _receipt_reports_failed_physical_cleanup(receipt: Any) -> bool:
    if type(receipt) is not dict:
        return False
    observed: list[Any] = []
    outcomes = receipt.get("outcomes")
    if type(outcomes) is list:
        for outcome in outcomes:
            if type(outcome) is dict and type(outcome.get("receipt")) is dict:
                observed.append(outcome["receipt"].get("cleanup"))
    controls = receipt.get("controls")
    if type(controls) is list:
        for control in controls:
            if type(control) is dict:
                observed.append(control.get("cleanup"))
    return any(type(item) is dict and (item.get("status") == "failed"
               or bool(item.get("failures"))) for item in observed)


def _validate_gate_campaign_receipt(receipt: Any, application: str,
        catalog_selection: dict[str, str], components: list[dict[str, Any]]) -> None:
    root_fields = {"schema", "application", "authoring", "node", "runnerSha256",
        "publicContractSha256", "model", "referenceImplementation", "trace", "interface",
        "catalog", "protected", "campaignDefinition", "mutationCampaign", "fidelity",
        "controls", "outcomes"}
    receipt = _closed_record(receipt, root_fields, set(), "Gate campaign receipt")
    if (receipt["schema"] != "mirrorgate.application-validation/v2"
            or receipt["application"] != application
            or application not in {"work-queue", "persistent-transfer", "lease-service"}
            or receipt["authoring"] != "not exercised; source submissions"
            or receipt["node"] != "v24.15.0"):
        raise ValueError("Gate campaign receipt identity is invalid")
    for field in ("runnerSha256", "publicContractSha256", "model",
                  "referenceImplementation", "trace"):
        value = receipt[field]
        if type(value) is not str or len(value) != 64 or any(
                character not in "0123456789abcdef" for character in value):
            raise ValueError(f"Gate receipt {field} is invalid")
    if type(receipt["interface"]) is not str or not receipt["interface"]:
        raise ValueError("Gate receipt interface identity is invalid")
    catalog = _closed_record(receipt["catalog"], {"selectionRef", "combinationId", "componentRefs"},
                             set(), "Gate campaign catalog")
    if (catalog["selectionRef"] != catalog_selection or catalog["componentRefs"] != components
            or type(catalog["combinationId"]) is not str or not catalog["combinationId"]):
        raise ValueError("Gate campaign catalog/component identity differs")
    protected = _closed_record(receipt["protected"], {"suite", "model", "generatedInterface",
        "corpus", "acceptance", "observer", "correctImplementation", "probes",
        "executionProfiles"}, set(), "Gate protected inputs")
    for field in ("suite", "model", "generatedInterface", "corpus", "acceptance",
                  "observer", "correctImplementation"):
        _sha_identity(protected[field], f"protected {field}")
    for field in ("probes", "executionProfiles"):
        values = protected[field]
        if type(values) is not list or not values or len(values) > 64:
            raise ValueError(f"protected {field} is invalid")
        ids = [_sha_identity(value, f"protected {field}")["id"] for value in values]
        if len(ids) != len(set(ids)):
            raise ValueError(f"protected {field} identity is duplicate")
    definition = _closed_record(receipt["campaignDefinition"],
        {"id", "revision", "denominator", "orderedCaseIds", "cases"}, set(),
        "Gate campaign definition")
    expected_denominator = {"work-queue": 9, "persistent-transfer": 4,
                            "lease-service": 4}[application]
    if (type(definition["revision"]) is not int or definition["revision"] < 1
            or definition["denominator"] != expected_denominator
            or type(definition["id"]) is not str or not definition["id"]):
        raise ValueError("Gate campaign definition identity/denominator is invalid")
    cases = definition["cases"]
    ordered = definition["orderedCaseIds"]
    if (type(cases) is not list or len(cases) != expected_denominator
            or type(ordered) is not list or len(ordered) != expected_denominator):
        raise ValueError("Gate campaign case denominator is incomplete")
    case_by_id: dict[str, dict[str, Any]] = {}
    for item in cases:
        item = _closed_record(item, {"id", "implementation", "expected", "probeIds"}, set(),
                              "Gate campaign case")
        case_id = _attachment_id(item["id"], "campaign case id")
        if case_id in case_by_id:
            raise ValueError("Gate campaign case ID is duplicate")
        _sha_identity(item["implementation"], "campaign case implementation")
        expected = _closed_record(item["expected"],
            {"kind", "code", "traceIndex", "stateIndex", "action"}, set(),
            "campaign expected mismatch")
        if (expected["kind"] != "behavioral_mismatch" or expected["code"] != "replay_mismatch"
                or type(expected["traceIndex"]) is not int or expected["traceIndex"] < 0
                or type(expected["stateIndex"]) is not int or expected["stateIndex"] < 0
                or type(expected["action"]) is not str or not expected["action"]
                or type(item["probeIds"]) is not list or not item["probeIds"]):
            raise ValueError("campaign expected mismatch/probe is invalid")
        case_by_id[case_id] = item
    if ordered != list(case_by_id):
        raise ValueError("Gate campaign ordered case IDs differ from exact cases")
    campaign = _closed_record(receipt["mutationCampaign"], {"schema", "campaignId", "revision",
        "testedPath", "denominator", "requiredOnPath", "status", "acceptance", "baseline",
        "mutants"}, set(), "Gate mutation campaign")
    acceptance = _closed_record(campaign["acceptance"], {"status", "reasonCodes"}, set(),
                                "Gate mutation acceptance")
    if (campaign["schema"] != "mirrorecma.mutation-campaign-result/v1"
            or campaign["campaignId"] != definition["id"]
            or campaign["revision"] != definition["revision"]
            or campaign["testedPath"] != "gate"
            or campaign["denominator"] != expected_denominator
            or campaign["requiredOnPath"] != expected_denominator
            or campaign["status"] != "complete"
            or acceptance != {"status": "met", "reasonCodes": []}):
        raise ValueError("Gate mutation campaign was not completely accepted")
    baseline = _closed_record(campaign["baseline"],
        {"id", "testedPath", "disposition", "classification", "cleanup", "probe", "durationMs"},
        {"reasonCode"}, "Gate mutation baseline")
    if (baseline["id"] != "correct" or baseline["testedPath"] != "gate"
            or baseline["disposition"] != "attempted" or baseline["classification"] != "survived"
            or baseline["probe"] != {"status": "passed"}):
        raise ValueError("Gate mutation baseline is invalid")
    _campaign_cleanup(baseline["cleanup"], {"local-cooperative", "gate-physical"})
    mutants = campaign["mutants"]
    if type(mutants) is not list or len(mutants) != expected_denominator:
        raise ValueError("Gate mutation result denominator is incomplete")
    observed_ids: list[str] = []
    for item in mutants:
        item = _closed_record(item, {"id", "testedPath", "disposition", "classification",
            "expected", "observed", "cleanup", "probe", "durationMs"}, {"reasonCode"},
            "Gate mutation result")
        case = case_by_id.get(item["id"])
        if (case is None or item["testedPath"] != "gate" or item["disposition"] != "attempted"
                or item["classification"] != "killed_by_behavioral_mismatch"
                or item["expected"] != case["expected"] or item["observed"] != case["expected"]
                or item["probe"] != {"status": "passed"}):
            raise ValueError("Gate mutation result differs from its expected exact mismatch")
        _campaign_cleanup(item["cleanup"], {"local-cooperative", "gate-physical"})
        observed_ids.append(item["id"])
    if observed_ids != ordered or len(observed_ids) != len(set(observed_ids)):
        raise ValueError("Gate mutation results are missing, duplicate, or reordered")
    fidelity = receipt["fidelity"]
    common = {"schema", "method", "probeIdentity", "normalCases", "shadowControl"}
    if application == "lease-service":
        fidelity = _closed_record(fidelity, common | {"observerError", "invalidObservation"}, set(),
                                  "Gate fidelity result")
        shadow = _closed_record(fidelity["shadowControl"], {"reportedReplay", "actualFactsComparison"},
                                set(), "Gate shadow control")
        comparison = _closed_record(shadow["actualFactsComparison"],
            {"status", "code", "enforcedOutcome"}, set(), "Gate facts comparison")
        if (shadow["reportedReplay"] != "passed" or comparison != {
                "status":"failed", "code":"probe_observer_divergence", "enforcedOutcome":"failed"}
                or fidelity["observerError"] != "implementation_failure"
                or fidelity["invalidObservation"] != "codec_failure"):
            raise ValueError("Gate fidelity negative controls are invalid")
    else:
        fidelity = _closed_record(fidelity, common, set(), "Gate fidelity result")
        if fidelity["shadowControl"] != {"status":"not_applicable",
                "reason":"real Gate shadow negative is retained by lease-service"}:
            raise ValueError("Gate fidelity delegation is invalid")
    if (fidelity["schema"] != "mirrorgate.observer-fidelity/v1"
            or fidelity["method"] != "actual-facts-vs-observation"
            or fidelity["normalCases"] != "passed"
            or fidelity["probeIdentity"] not in protected["probes"]):
        raise ValueError("Gate fidelity identity/result is invalid")
    controls = receipt["controls"]
    expected_controls = {"crash":"failed", "hang":"timedOut", "cancel":"cancelled"}
    if type(controls) is not list or len(controls) != 3:
        raise ValueError("Gate control outcomes are incomplete")
    for item in controls:
        item = _closed_record(item, {"id", "outcome", "cleanup"}, set(), "Gate control result")
        if item["id"] not in expected_controls or item["outcome"] != expected_controls[item["id"]]:
            raise ValueError("Gate control result is invalid")
        _physical_cleanup(item["cleanup"])
    if [item["id"] for item in controls] != ["crash", "hang", "cancel"]:
        raise ValueError("Gate control results are duplicate or reordered")
    outcomes = receipt["outcomes"]
    extra = (["observer-shadow-unchecked", "observer-shadow-enforced",
              "observer-throws", "observer-invalid"] if application == "lease-service" else [])
    expected_variants = ["correct", *ordered, "crash", "hang", "cancel", *extra]
    if type(outcomes) is not list or len(outcomes) != len(expected_variants):
        raise ValueError("Gate detailed outcome denominator is incomplete")
    by_variant: dict[str, dict[str, Any]] = {}
    for outcome in outcomes:
        if type(outcome) is not dict or type(outcome.get("variant")) is not str:
            raise ValueError("Gate detailed outcome is malformed")
        variant = outcome["variant"]
        if variant in by_variant or outcome.get("fixedFixtureProbe") != "enforced":
            raise ValueError("Gate detailed outcome is duplicate or lacks its fixed probe")
        native = outcome.get("receipt")
        if type(native) is not dict:
            raise ValueError("Gate detailed outcome lacks a trusted receipt")
        _physical_cleanup(native.get("cleanup"))
        by_variant[variant] = outcome
    if list(by_variant) != expected_variants:
        raise ValueError("Gate detailed outcomes are missing or reordered")


def _gate_campaign_outcomes(plan: AttachmentPlan, captured: dict[str, bytes],
        producer_results: list[dict[str, str]], catalog_selection: dict[str, str],
        components: list[dict[str, Any]]) -> tuple[dict[str, Any], list[dict[str, Any]], str]:
    artifact_id = plan.adapter_artifact_id
    cleanup_status = "unconfirmed"
    try:
        if artifact_id is None or artifact_id not in captured:
            raise ValueError("campaign receipt was not captured")
        receipt = loads_json_bytes(captured[artifact_id])
        if _receipt_reports_failed_physical_cleanup(receipt):
            cleanup_status = "failed"
        _validate_gate_campaign_receipt(receipt, plan.application, catalog_selection, components)
        behavior_passed = True
        cleanup_status = "confirmed"
        producer = next((item for item in producer_results
                         if item["artifactId"] == artifact_id), None)
        behavior: dict[str, Any] = {
            "status": "passed" if behavior_passed else "failed",
            "classification": {"namespace": "mirrorgate.application-validation",
                               "code": "passed" if behavior_passed else "campaign-case-failed"},
        }
        if producer is not None:
            behavior["producerResult"] = producer
        cleanup = [{"scope": "local-cooperative", "requirement": "not-applicable",
                    "status": "not_applicable", "artifactIds": []},
                   {"scope": "gate-physical", "requirement": "required",
                    "status": cleanup_status, "artifactIds": [artifact_id]}]
        return behavior, cleanup, ("passed" if behavior_passed else "failed")
    except (ValueError, UnicodeError, json.JSONDecodeError):
        return ({"status": "inconclusive", "classification": {
                    "namespace": "mirrorgate.application-validation",
                    "code": "producer-result-invalid"}},
                [{"scope": "local-cooperative", "requirement": "not-applicable",
                  "status": "not_applicable", "artifactIds": []},
                 {"scope": "gate-physical", "requirement": "required",
                  "status": cleanup_status, "reasonCode": "producer-result-invalid",
                  "artifactIds": ([] if artifact_id is None else [artifact_id])}],
                "failed")


def _validate_local_aggregate_receipt(receipt: Any, catalog_selection: dict[str, str],
        components: list[dict[str, Any]]) -> None:
    receipt = _closed_record(receipt, {"schema", "tier", "applications", "denominator",
        "acceptance", "cleanup", "framework", "campaigns"}, set(),
        "local aggregate receipt")
    applications = list(LOCAL_CAMPAIGNS)
    if (receipt["schema"] != "mirrorecma.application-campaign-aggregate/v1"
            or receipt["tier"] != "installed-prevalidated"
            or receipt["applications"] != applications
            or receipt["denominator"] != 17
            or receipt["acceptance"] != {"status":"met"}
            or receipt["cleanup"] != {"scope":"local-cooperative",
                                      "status":"confirmed", "cases":29}):
        raise ValueError("local aggregate identity, denominator, or cleanup is invalid")
    framework = _closed_record(receipt["framework"], {"catalogSelectionRef", "componentRefs",
        "installedRegistrySha256", "frameworkInputSha256", "installationSchema"}, set(),
        "local aggregate framework identity")
    if (framework["catalogSelectionRef"] != catalog_selection
            or framework["componentRefs"] != components
            or framework["installationSchema"] != "mirrorecma.installed-framework-binding/v1"):
        raise ValueError("local aggregate catalog/component identity differs")
    for field in ("installedRegistrySha256", "frameworkInputSha256"):
        _sha_identity({"id":field, "sha256":framework[field]}, field)
    campaigns = receipt["campaigns"]
    if type(campaigns) is not list or len(campaigns) != 3:
        raise ValueError("local aggregate campaign denominator is incomplete")
    for campaign, application in zip(campaigns, applications, strict=True):
        campaign = _closed_record(campaign, {"schema", "application", "suiteId", "tier",
            "generatedAt", "node", "identities", "mutationCampaign", "measurements",
            "results"}, set(), f"local {application} receipt")
        expected = LOCAL_CAMPAIGNS[application]
        if (campaign["schema"] != "mirrorecma.application-validation/v2"
                or campaign["application"] != application
                or campaign["tier"] != "checked-deterministic-witness"
                or campaign["node"] != "v24.15.0"
                or type(campaign["suiteId"]) is not str or not campaign["suiteId"]
                or type(campaign["generatedAt"]) is not str
                or type(campaign["measurements"]) is not dict):
            raise ValueError(f"local {application} receipt identity is invalid")
        identities = _closed_record(campaign["identities"], {"model", "implementation",
            "harness", "interface", "applicationConfig", "mirror", "trace"}, set(),
            f"local {application} identities")
        for field, value in identities.items():
            if (type(value) is not str or len(value) != 64
                    or any(character not in "0123456789abcdef" for character in value)):
                raise ValueError(f"local {application} {field} identity is invalid")
        mutation = _closed_record(campaign["mutationCampaign"], {"id", "revision", "status",
            "acceptance", "denominator", "requiredOnPath", "results"}, set(),
            f"local {application} mutation campaign")
        acceptance = _closed_record(mutation["acceptance"], {"status", "reasonCodes"}, set(),
                                    f"local {application} mutation acceptance")
        if (type(mutation["id"]) is not str or not mutation["id"]
                or type(mutation["revision"]) is not int or mutation["revision"] < 1
                or mutation["status"] != "complete"
                or acceptance != {"status":"met", "reasonCodes":[]}
                or mutation["denominator"] != len(expected)
                or mutation["requiredOnPath"] != len(expected)):
            raise ValueError(f"local {application} mutation campaign is incomplete")
        mutation_results = mutation["results"]
        if type(mutation_results) is not list or len(mutation_results) != len(expected):
            raise ValueError(f"local {application} mutation denominator differs")
        for result, (case_id, _trace, _state, _action) in zip(
                mutation_results, expected, strict=True):
            result = _closed_record(result, {"id", "classification", "disposition",
                "cleanup", "probe"}, set(), f"local {application} mutation result")
            if (result["id"] != case_id
                    or result["classification"] != "killed_by_behavioral_mismatch"
                    or result["disposition"] != "attempted"
                    or type(result["probe"]) is not dict
                    or result["probe"].get("status") != "passed"):
                raise ValueError(f"local {application} mutation result is invalid")
            _campaign_cleanup(result["cleanup"], {"local-cooperative"})
        detailed = campaign["results"]
        expected_variants = ["correct", *[item[0] for item in expected],
                             "crash", "hang", "cancel"]
        if type(detailed) is not list or len(detailed) != len(expected_variants):
            raise ValueError(f"local {application} detailed denominator differs")
        detailed_by_id: dict[str, dict[str, Any]] = {}
        for result in detailed:
            if type(result) is not dict or type(result.get("variant")) is not str:
                raise ValueError(f"local {application} detailed result is malformed")
            variant = result["variant"]
            if variant in detailed_by_id:
                raise ValueError(f"local {application} detailed result is duplicate")
            detailed_by_id[variant] = result
            cleanup = result.get("cleanup")
            probe = result.get("probe")
            suite_result = result.get("suiteResult")
            if (type(cleanup) is not dict or cleanup.get("status") != "confirmed"
                    or cleanup.get("remainingEntries") != []
                    or type(probe) is not dict or probe.get("status") != "passed"
                    or "facts" not in probe or type(suite_result) is not dict
                    or suite_result.get("outcome") != result.get("classification")
                    or type(suite_result.get("cleanup")) is not dict
                    or suite_result["cleanup"].get("status") != "succeeded"
                    or suite_result["cleanup"].get("quiescence") != "confirmed"):
                raise ValueError(f"local {application} cleanup/probe is invalid")
        if list(detailed_by_id) != expected_variants:
            raise ValueError(f"local {application} detailed results are missing or reordered")
        if detailed_by_id["correct"].get("classification") != "passed":
            raise ValueError(f"local {application} correct baseline did not pass")
        for case_id, trace_index, state_index, action in expected:
            result = detailed_by_id[case_id]
            wanted = {"code":"replay_mismatch", "traceIndex":trace_index,
                      "stateIndex":state_index, "action":action}
            if (result.get("classification") != "mismatch"
                    or result.get("expectedFirstMismatch") != wanted):
                raise ValueError(f"local {application} mismatch coordinates differ: {case_id}")
        for variant, classification in (("crash", "failed"), ("hang", "timedOut"),
                                        ("cancel", "cancelled")):
            if detailed_by_id[variant].get("classification") != classification:
                raise ValueError(f"local {application} control outcome differs: {variant}")


def _local_reports_failed_cleanup(receipt: Any) -> bool:
    if type(receipt) is not dict:
        return False
    cleanup = receipt.get("cleanup")
    if type(cleanup) is dict and cleanup.get("status") == "failed":
        return True
    campaigns = receipt.get("campaigns")
    if type(campaigns) is not list:
        return False
    for campaign in campaigns:
        if type(campaign) is not dict:
            continue
        for result in campaign.get("results", []) if type(campaign.get("results")) is list else []:
            if type(result) is dict and type(result.get("cleanup")) is dict \
                    and result["cleanup"].get("status") == "failed":
                return True
        mutation = campaign.get("mutationCampaign")
        if type(mutation) is dict and type(mutation.get("results")) is list:
            for result in mutation["results"]:
                if type(result) is not dict or type(result.get("cleanup")) is not list:
                    continue
                if any(type(item) is dict and item.get("status") == "failed"
                       for item in result["cleanup"]):
                    return True
    return False


def _local_aggregate_outcomes(plan: AttachmentPlan, captured: dict[str, bytes],
        producer_results: list[dict[str, str]], catalog_selection: dict[str, str],
        components: list[dict[str, Any]]) -> tuple[dict[str, Any], list[dict[str, Any]], str]:
    artifact_id = plan.adapter_artifact_id
    cleanup_status = "unconfirmed"
    try:
        if artifact_id is None or artifact_id not in captured:
            raise ValueError("local aggregate receipt was not captured")
        receipt = loads_json_bytes(captured[artifact_id])
        if _local_reports_failed_cleanup(receipt):
            cleanup_status = "failed"
        _validate_local_aggregate_receipt(receipt, catalog_selection, components)
        behavior: dict[str, Any] = {"status":"passed", "classification":{
            "namespace":"mirrorecma.application-campaign-aggregate",
            "code":"all-local-application-campaigns-accepted"}}
        producer = next((item for item in producer_results
                         if item["artifactId"] == artifact_id), None)
        if producer is not None:
            behavior["producerResult"] = producer
        return (behavior, [{"scope":"local-cooperative", "requirement":"required",
                            "status":"confirmed", "artifactIds":[artifact_id]}], "passed")
    except (ValueError, UnicodeError, json.JSONDecodeError):
        return ({"status":"inconclusive", "classification":{
                    "namespace":"mirrorecma.application-campaign-aggregate",
                    "code":"producer-result-invalid"}},
                [{"scope":"local-cooperative", "requirement":"required",
                  "status":cleanup_status, "reasonCode":"producer-result-invalid",
                  "artifactIds":[] if artifact_id is None else [artifact_id]}], "failed")


def _captured_sha256(captured: dict[str, bytes], artifact_id: str) -> str:
    data = captured.get(artifact_id)
    if data is None:
        raise ValueError(f"required reduction artifact is absent: {artifact_id}")
    return _sha256(data)


def _validate_reduction_receipt(receipt: Any, captured: dict[str, bytes]) -> None:
    receipt = _closed_record(receipt, {"schema", "status", "profile", "domainVersion",
        "modelSha256", "interfaceDigest", "originalCorpusSha256", "candidateCorpusSha256",
        "selectedTraceSha256", "traceOccurrences", "validator", "apalache", "java",
        "cleanup", "materialization"}, set(), "LeaseService reduction receipt")
    if (receipt["schema"] != "mirrorecma.lease-reduction-oracle/v1"
            or receipt["status"] != "model_valid"
            or receipt["profile"] != "lease-service-input-shrink/v1"
            or receipt["domainVersion"] != "LeaseService.Next/v1"
            or receipt["traceOccurrences"] != [0, 1]
            or receipt["cleanup"] != {"status":"confirmed", "method":"explore_done"}):
        raise ValueError("LeaseService reduction result is not model-valid and cleaned")
    for field in ("modelSha256", "interfaceDigest", "originalCorpusSha256",
                  "candidateCorpusSha256", "selectedTraceSha256"):
        _sha_identity({"id":field, "sha256":receipt[field]}, field)
    validator = _closed_record(receipt["validator"], {"id", "sha256"}, set(),
                               "reduction validator")
    apalache = _closed_record(receipt["apalache"], {"version", "sha256"}, set(),
                              "reduction Apalache")
    java = _closed_record(receipt["java"], {"observedVersion", "selectedVersion",
        "executableSha256", "archiveSha256", "distributionQualified", "qualificationRef"},
        set(), "reduction Java")
    if (validator["id"] != "mirrors.model-interface-reduction/v1"
            or apalache["version"] != "0.61.0"
            or java["selectedVersion"] != "25.0.4+7"
            or java["observedVersion"] != "25.0.4+7-LTS"
            or java["distributionQualified"] is not True):
        raise ValueError("reduction tool identities are unsupported")
    for label, value in (("validator", validator["sha256"]),
                         ("apalache", apalache["sha256"]),
                         ("java executable", java["executableSha256"]),
                         ("java archive", java["archiveSha256"])):
        _sha_identity({"id":label.replace(" ", "-"), "sha256":value}, label)
    if java["qualificationRef"] != (
            "microsoft-jdk-25.0.4+7-linux-x64/sha256:" + java["archiveSha256"]):
        raise ValueError("reduction Java qualification reference differs")
    materialization = _closed_record(receipt["materialization"], {
        "originalTraceSha256", "candidateTraceSha256", "originalBundleSha256",
        "actionSequence", "inputMeasure", "changes", "toolManifestSha256", "sources"},
        set(), "reduction materialization")
    if (materialization["originalTraceSha256"] != receipt["selectedTraceSha256"]
            or materialization["actionSequence"] != ["init", "acquire", "acquire", "renew",
                "advance", "write", "acquire", "release", "renew", "write", "release"]
            or materialization["inputMeasure"] != {"before":2, "after":1}
            or materialization["changes"] != ["/states/2/parameters/client/#bigint"]):
        raise ValueError("reduction materialization changed unsupported coordinates")
    expected_hashes = {
        "candidateTraceSha256": _captured_sha256(captured, "lease-reduction-candidate-trace"),
        "originalBundleSha256": _captured_sha256(captured, "lease-reduction-original-bundle"),
        "toolManifestSha256": _captured_sha256(captured, "lease-reduction-tool-manifest"),
    }
    if any(materialization[field] != value for field, value in expected_hashes.items()):
        raise ValueError("reduction materialization artifact identity differs")
    sources = _closed_record(materialization["sources"], {"model", "lock", "originalTrace",
        "candidateRequest"}, set(), "reduction materialization sources")
    source_artifacts = {"model":"lease-reduction-model", "lock":"lease-reduction-lock",
        "originalTrace":"lease-reduction-original-trace",
        "candidateRequest":"lease-reduction-candidate"}
    for name, artifact_id in source_artifacts.items():
        source = _closed_record(sources[name], {"path", "sha256"}, set(),
                                f"reduction source {name}")
        if type(source["path"]) is not str or not source["path"] \
                or source["sha256"] != _captured_sha256(captured, artifact_id):
            raise ValueError(f"reduction source identity differs: {name}")
    if (receipt["modelSha256"] != sources["model"]["sha256"]
            or receipt["selectedTraceSha256"] != sources["originalTrace"]["sha256"]):
        raise ValueError("reduction receipt source identity differs")
    tool_manifest = loads_json_bytes(captured["lease-reduction-tool-manifest"])
    if type(tool_manifest) is not dict or tool_manifest.get("schema") != \
            "mirrorecma.lease-reduction-tools/v1":
        raise ValueError("reduction tool manifest schema is invalid")
    try:
        tool_values = (tool_manifest["validator"]["sha256"],
                       tool_manifest["apalache"]["jarSha256"],
                       tool_manifest["java"]["executableSha256"],
                       tool_manifest["java"]["archiveSha256"],
                       tool_manifest["java"]["qualificationRef"])
    except (KeyError, TypeError) as error:
        raise ValueError("reduction tool manifest is incomplete") from error
    if tool_values != (validator["sha256"], apalache["sha256"],
                       java["executableSha256"], java["archiveSha256"],
                       java["qualificationRef"]):
        raise ValueError("reduction receipt differs from tool manifest")


def _reduction_outcomes(plan: AttachmentPlan, captured: dict[str, bytes],
        producer_results: list[dict[str, str]]) -> tuple[dict[str, Any], list[dict[str, Any]], str]:
    artifact_id = plan.adapter_artifact_id
    cleanup_status = "unconfirmed"
    try:
        if artifact_id is None or artifact_id not in captured:
            raise ValueError("reduction receipt was not captured")
        receipt = loads_json_bytes(captured[artifact_id])
        if type(receipt) is dict and type(receipt.get("cleanup")) is dict \
                and receipt["cleanup"].get("status") not in {None, "confirmed"}:
            cleanup_status = "failed"
        _validate_reduction_receipt(receipt, captured)
        behavior: dict[str, Any] = {"status":"passed", "classification":{
            "namespace":"mirrorecma.lease-reduction-oracle", "code":"model-valid"}}
        producer = next((item for item in producer_results
                         if item["artifactId"] == artifact_id), None)
        if producer is not None:
            behavior["producerResult"] = producer
        return (behavior, [{"scope":"local-cooperative", "requirement":"required",
                            "status":"confirmed", "artifactIds":[artifact_id]}], "passed")
    except (KeyError, ValueError, UnicodeError, json.JSONDecodeError):
        return ({"status":"inconclusive", "classification":{
                    "namespace":"mirrorecma.lease-reduction-oracle",
                    "code":"producer-result-invalid"}},
                [{"scope":"local-cooperative", "requirement":"required",
                  "status":cleanup_status, "reasonCode":"producer-result-invalid",
                  "artifactIds":[] if artifact_id is None else [artifact_id]}], "failed")


def _gate_recovery_outcomes(plan: AttachmentPlan, captured: dict[str, bytes],
        producer_results: list[dict[str, str]], run_id: str) -> tuple[
            dict[str, Any], list[dict[str, Any]], str]:
    artifact_id = plan.adapter_artifact_id
    try:
        if artifact_id is None or artifact_id not in captured:
            raise ValueError("recovery receipt was not captured")
        receipt = loads_json_bytes(captured[artifact_id])
        required = {"schema", "attemptId", "trigger", "original", "journalSchema",
            "controllerInstance", "bootId", "principalUid", "ownershipObservations",
            "cgroupObservations", "remainingResources", "results", "cleanup", "sha256"}
        if type(receipt) is not dict or set(receipt) != required:
            raise ValueError("recovery receipt root is not closed")
        if (receipt["schema"] != "mirrorgate.recovery-receipt/v1"
                or receipt["journalSchema"] != "mirrorgate.recovery-journal/v1"):
            raise ValueError("recovery receipt schema is unsupported")
        for field in ("attemptId", "trigger", "controllerInstance", "bootId"):
            _attachment_id(receipt[field], f"recovery {field}")
        if type(receipt["principalUid"]) is not int or receipt["principalUid"] < 0:
            raise ValueError("recovery principalUid is invalid")
        ownership = receipt["ownershipObservations"]
        if (type(ownership) is not list or len(ownership) > 4096
                or any(value not in GATE_RECOVERY_RESULTS for value in ownership)):
            raise ValueError("recovery ownership observations are invalid")
        cgroup = receipt["cgroupObservations"]
        if type(cgroup) is not list or len(cgroup) > 4096:
            raise ValueError("recovery cgroup observations are invalid")
        remaining = receipt["remainingResources"]
        if (type(remaining) is not list or len(remaining) > 4096
                or any(_attachment_id(value, "remaining resource") != value for value in remaining)):
            raise ValueError("recovery remaining resources are invalid")
        original = receipt["original"]
        if original is not None:
            if type(original) is not dict or set(original) != {"runRef", "behavior", "cleanup"}:
                raise ValueError("recovery original result is not closed")
            reference = original["runRef"]
            if (type(reference) is not dict or set(reference) != {
                    "schemaVersion", "runId", "envelopeSha256", "projectionKind"}
                    or reference["schemaVersion"] != "mirrors.evidence-envelope/v1.0"
                    or reference["projectionKind"] != "private"
                    or reference["runId"] == run_id):
                raise ValueError("recovery original runRef is invalid or self-referential")
            _attachment_id(reference["runId"], "original runId")
            if (type(reference["envelopeSha256"]) is not str
                    or len(reference["envelopeSha256"]) != 64
                    or any(character not in "0123456789abcdef"
                           for character in reference["envelopeSha256"])
                    or original["behavior"] not in GATE_RECOVERY_BEHAVIORS
                    or original["cleanup"] not in GATE_RECOVERY_CLEANUPS):
                raise ValueError("recovery original outcome is invalid")
        results = receipt["results"]
        if type(results) is not list or len(results) > 4096:
            raise ValueError("recovery results are invalid")
        seen_resources: set[str] = set()
        statuses: set[str] = set()
        result_by_resource: dict[str, dict[str, Any]] = {}
        for item in results:
            if type(item) is not dict or set(item) != {
                    "resourceId", "sessionId", "kind", "result", "reasonCode"}:
                raise ValueError("recovery result is not closed")
            for field in ("resourceId", "sessionId", "kind"):
                _attachment_id(item[field], f"recovery result {field}")
            if item["resourceId"] in seen_resources or item["result"] not in GATE_RECOVERY_RESULTS:
                raise ValueError("recovery result is duplicate or invalid")
            seen_resources.add(item["resourceId"])
            result_by_resource[item["resourceId"]] = item
            statuses.add(item["result"])
            if item["reasonCode"] is not None:
                _attachment_id(item["reasonCode"], "recovery reasonCode")
        observed_cgroups: set[str] = set()
        for item in cgroup:
            if type(item) is not dict or set(item) != {"resourceId", "settings", "counters"}:
                raise ValueError("recovery cgroup observation is not closed")
            resource_id = _attachment_id(item["resourceId"], "cgroup observation resourceId")
            result = result_by_resource.get(resource_id)
            if (resource_id in observed_cgroups or result is None
                    or result["kind"] not in {"cgroup", "cgroup-v2"}):
                raise ValueError("recovery cgroup observation does not resolve uniquely")
            observed_cgroups.add(resource_id)
            settings = item["settings"]
            counters = item["counters"]
            if (type(settings) is not dict or set(settings) != GATE_RECOVERY_CGROUP_SETTINGS
                    or any(value is not None and type(value) is not str
                           for value in settings.values())):
                raise ValueError("recovery cgroup settings are invalid")
            if (type(counters) is not dict or set(counters) - GATE_RECOVERY_CGROUP_FIELDS
                    or any(value is not None and type(value) is not str
                           for value in counters.values())
                    or (not counters and result["result"] == "reclaimed")
                    or (not counters and result["reasonCode"] is None)):
                raise ValueError("recovery cgroup counters are invalid")
        expected_cgroups = {resource_id for resource_id, item in result_by_resource.items()
                            if item["kind"] in {"cgroup", "cgroup-v2"}}
        if observed_cgroups != expected_cgroups:
            raise ValueError("recovery cgroup observations do not cover each cgroup result")
        expected_status = ("failed" if "failed" in statuses else
            "unconfirmed" if not results or remaining or statuses & {
                "ambiguous", "unconfirmed", "retained"} else "confirmed")
        cleanup = receipt["cleanup"]
        if (type(cleanup) is not dict or set(cleanup) != {
                "scope", "requirement", "status", "artifactIds"}
                or cleanup["scope"] != "gate-recovery"
                or cleanup["requirement"] != "required"
                or cleanup["status"] != expected_status
                or type(cleanup["artifactIds"]) is not list
                or any(type(value) is not str or len(value) != 71
                       or not value.startswith("sha256:")
                       or any(character not in "0123456789abcdef" for character in value[7:])
                       for value in cleanup["artifactIds"])):
            raise ValueError("recovery cleanup projection is invalid")
        digest = receipt["sha256"]
        payload = {key: value for key, value in receipt.items() if key != "sha256"}
        native = json.dumps(payload, sort_keys=True, separators=(",", ":"),
                            ensure_ascii=True).encode()
        if (type(digest) is not str or digest != _sha256(native)):
            raise ValueError("recovery receipt native digest is invalid")
        behavior: dict[str, Any] = {"status": "passed", "classification": {
            "namespace": "mirrorgate.recovery", "code": "recovery-receipt-valid"}}
        return (behavior, [{"scope": "local-cooperative", "requirement": "not-applicable",
                    "status": "not_applicable", "artifactIds": []},
                {"scope": "gate-recovery", "requirement": "required",
                    "status": expected_status, "artifactIds": [artifact_id]}],
                "passed" if expected_status == "confirmed" else "failed")
    except (ValueError, UnicodeError, json.JSONDecodeError):
        return ({"status": "inconclusive", "classification": {
                    "namespace": "mirrorgate.recovery", "code": "producer-result-invalid"}},
                [{"scope": "local-cooperative", "requirement": "not-applicable",
                    "status": "not_applicable", "artifactIds": []},
                 {"scope": "gate-recovery", "requirement": "required",
                    "status": "unconfirmed", "reasonCode": "producer-result-invalid",
                    "artifactIds": ([] if artifact_id is None else [artifact_id])}],
                "failed")


def _gate_aggregate_outcomes(captured: dict[str, bytes], catalog_selection: dict[str, str],
        components: list[dict[str, Any]]) -> tuple[dict[str, Any], list[dict[str, Any]], str]:
    artifact_ids: list[str] = []
    cleanup_status = "unconfirmed"
    try:
        for application in ("work-queue", "persistent-transfer", "lease-service"):
            artifact_id = f"{application}-gate-receipt"
            data = captured.get(artifact_id)
            if data is None:
                raise ValueError(f"aggregate Gate receipt is absent: {application}")
            artifact_ids.append(artifact_id)
            receipt = loads_json_bytes(data)
            if _receipt_reports_failed_physical_cleanup(receipt):
                cleanup_status = "failed"
            _validate_gate_campaign_receipt(receipt, application, catalog_selection, components)
        cleanup_status = "confirmed"
        return ({"status":"passed","classification":{
                    "namespace":"mirrorgate.application-validation",
                    "code":"all-application-campaigns-accepted"}},
                [{"scope":"local-cooperative","requirement":"not-applicable",
                    "status":"not_applicable","artifactIds":[]},
                 {"scope":"gate-physical","requirement":"required",
                    "status":"confirmed","artifactIds":artifact_ids}], "passed")
    except (ValueError, UnicodeError, json.JSONDecodeError):
        return ({"status":"inconclusive","classification":{
                    "namespace":"mirrorgate.application-validation",
                    "code":"aggregate-producer-result-invalid"}},
                [{"scope":"local-cooperative","requirement":"not-applicable",
                    "status":"not_applicable","artifactIds":[]},
                 {"scope":"gate-physical","requirement":"required",
                    "status":cleanup_status,"reasonCode":"aggregate-producer-result-invalid",
                    "artifactIds":artifact_ids}], "failed")


def _artifact(artifact_id: str, role: str, relative: str, data: bytes, requirement: str) -> dict[str, Any]:
    return {
        "artifactId": artifact_id,
        "mediaType": "application/octet-stream" if role == "command-log" else "application/json",
        "role": role,
        "bytes": len(data),
        "sha256": _sha256(data),
        "visibility": "private",
        "requirement": requirement,
        "location": {"kind": "bundle", "path": relative},
    }


def _stage(
    store: Path,
    run_id: str,
    args: argparse.Namespace,
    entry: dict[str, Any],
    before: list[dict[str, Any]],
    after: list[dict[str, Any]],
    catalog_selection: dict[str, str],
    observation: ChildObservation,
    started_utc: str,
    finished_utc: str,
    duration_ns: int,
    attachment_plan: AttachmentPlan | None,
    command_context: bytes,
) -> Path:
    create_owner_directory(store)
    staging_root = store / "staging"
    create_owner_directory(staging_root)
    run_root = staging_root / run_id
    create_owner_directory_exclusive(run_root)
    artifacts_root = run_root / "artifacts"
    create_owner_directory(artifacts_root)
    private = artifacts_root / "private"
    create_owner_directory(private)

    artifacts: list[dict[str, Any]] = []
    required_ids = ["command-stdout", "command-stderr", "command-context"]
    missing: list[str] = []
    for artifact_id, filename, data, exceeded in [
        ("command-stdout", "stdout.log", observation.stdout, observation.stdout_exceeded),
        ("command-stderr", "stderr.log", observation.stderr, observation.stderr_exceeded),
    ]:
        relative = f"artifacts/private/{filename}"
        if exceeded:
            missing.append(artifact_id)
            continue
        _write_private(private / filename, data)
        artifacts.append(_artifact(artifact_id, "command-log", relative, data, "required"))

    _write_private(private / "command-context.json", command_context)
    context_artifact = _artifact("command-context", "diagnostic",
        "artifacts/private/command-context.json", command_context, "required")
    context_artifact["mediaType"] = "application/json"
    artifacts.append(context_artifact)

    snapshots = _canonical_json({
        "schemaVersion": "mirrors.component-snapshots/v1",
        "before": before,
        "after": after,
        "changed": before != after,
    })
    _write_private(private / "component-snapshots.json", snapshots)
    artifacts.append(_artifact(
        "component-snapshots", "diagnostic", "artifacts/private/component-snapshots.json", snapshots, "optional"
    ))

    attachment_artifacts, producer_results, captured, attachment_missing, attachment_failures = \
        capture_attachments(attachment_plan, private, run_id)
    artifacts.extend(attachment_artifacts)
    if attachment_plan is not None:
        required_ids.extend(spec.artifact_id for spec in attachment_plan.attachments
                            if spec.requirement == "required")
    missing.extend(attachment_missing)

    behavior, tier_status, behavior_reason = _outcomes(observation)
    cleanup_outcomes = [{
        "scope": "local-cooperative",
        "requirement": "not-applicable",
        "status": "not_applicable",
        "artifactIds": [],
    }]
    required_cleanup_scopes: list[str] = []
    if (attachment_plan is not None
            and attachment_plan.adapter_kind == "mirrorgate.application-validation/v2"):
        native_behavior, cleanup_outcomes, native_tier_status = _gate_campaign_outcomes(
            attachment_plan, captured, producer_results, catalog_selection, before)
        required_cleanup_scopes = ["gate-physical"]
        if behavior["status"] == "passed" and not observation.timed_out:
            behavior = native_behavior
            tier_status = native_tier_status
            behavior_reason = behavior["classification"]["code"]
    elif (attachment_plan is not None
            and attachment_plan.adapter_kind == "mirrorecma.application-campaign-aggregate/v1"):
        native_behavior, cleanup_outcomes, native_tier_status = _local_aggregate_outcomes(
            attachment_plan, captured, producer_results, catalog_selection, before)
        required_cleanup_scopes = ["local-cooperative"]
        if behavior["status"] == "passed" and not observation.timed_out:
            behavior = native_behavior
            tier_status = native_tier_status
            behavior_reason = behavior["classification"]["code"]
    elif (attachment_plan is not None
            and attachment_plan.adapter_kind == "mirrorecma.lease-reduction-oracle/v1"):
        native_behavior, cleanup_outcomes, native_tier_status = _reduction_outcomes(
            attachment_plan, captured, producer_results)
        required_cleanup_scopes = ["local-cooperative"]
        if behavior["status"] == "passed" and not observation.timed_out:
            behavior = native_behavior
            tier_status = native_tier_status
            behavior_reason = behavior["classification"]["code"]
    elif (attachment_plan is not None
            and attachment_plan.adapter_kind == "mirrorgate.recovery-receipt/v1"):
        native_behavior, cleanup_outcomes, native_tier_status = _gate_recovery_outcomes(
            attachment_plan, captured, producer_results, run_id)
        required_cleanup_scopes = ["gate-recovery"]
        if behavior["status"] == "passed" and not observation.timed_out:
            behavior = native_behavior
            tier_status = native_tier_status
            behavior_reason = behavior["classification"]["code"]
    elif (attachment_plan is not None
            and attachment_plan.adapter_kind == "mirrorgate.application-validation-aggregate/v1"):
        native_behavior, cleanup_outcomes, native_tier_status = _gate_aggregate_outcomes(
            captured, catalog_selection, before)
        required_cleanup_scopes = ["gate-physical"]
        if behavior["status"] == "passed" and not observation.timed_out:
            behavior = native_behavior
            tier_status = native_tier_status
            behavior_reason = behavior["classification"]["code"]
    reasons = ["awaiting-final-index"]
    persistence_reason = "awaiting-final-index"
    if missing:
        persistence_reason = ("attachment-capture-failed" if attachment_missing
                              else "output-limit-exceeded")
        reasons.append("required-artifact-not-retained")
    if attachment_failures:
        reasons.append("attachment-capture-failed")
    if before != after:
        persistence_reason = "component-changed-during-collection"
        reasons.append("component-changed-during-collection")
    if behavior["status"] != "passed":
        reasons.append(behavior_reason)
    persistence_status = "failed" if missing else "incomplete"
    envelope = {
        "schemaVersion": "mirrors.evidence-envelope/v1.0",
        "projectionKind": "private",
        "runId": run_id,
        "releaseProfile": "mirrors.local-release-evidence/v1",
        "catalogSelectionRef": catalog_selection,
        "components": before,
        "timestamps": {
            "startedAtUtc": started_utc,
            "finishedAtUtc": finished_utc,
            "monotonicDurationNs": duration_ns,
        },
        "environment": {
            "platformProfile": "local-collector",
            "os": sys.platform,
            "architecture": os.uname().machine,
            "kernel": os.uname().release,
            "workingDirectory": str(args.cwd),
            "tools": [{"name": "python", "version": sys.version.split()[0]}],
        },
        "commands": [{
            "commandId": args.command_id,
            "tierId": entry["tierId"],
            "requirement": entry["requirement"],
            "argv": args.command,
            "cwd": str(args.cwd),
            "exit": _exit_record(observation),
            "logArtifactId": "command-stdout",
        }],
        "tiers": [{
            "tierId": entry["tierId"],
            "requirement": entry["requirement"],
            "status": tier_status,
            "reasonCode": behavior_reason,
            "artifactIds": [artifact["artifactId"] for artifact in artifacts
                            if artifact["role"] == "command-log"
                            or artifact["artifactId"] in required_ids],
        }],
        "artifacts": artifacts,
        "producerResults": producer_results,
        "releaseRequirements": {
            "requiredArtifactIds": required_ids,
            "requiredStructuralRoles": ["public-summary", "private-index"],
            "requiredCleanupScopes": required_cleanup_scopes,
        },
        "outcomes": {
            "behavior": behavior,
            "cleanup": cleanup_outcomes,
            "persistence": {
                "requirement": "required",
                "status": persistence_status,
                "reasonCode": persistence_reason,
                "requiredArtifactIds": required_ids,
                "missingArtifactIds": missing,
            },
        },
        "qualification": {"status": "incomplete", "reasonCodes": sorted(set(reasons))},
        "retention": {"profile": "local-owner-only-v1", "automaticUpload": False, "automaticPruning": False},
        "privateMetadata": {"operatorNotes": ["Unfinalized E2 staging envelope."]},
    }
    from validate import validate_document

    errors = validate_document(envelope)
    if errors:
        raise ValueError("collector produced invalid staging envelope: " + "; ".join(errors))
    _write_private(run_root / "envelope.staging.json", _canonical_json(envelope))
    return run_root


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--store", type=Path, default=None)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    parser.add_argument("--command-id", required=True)
    parser.add_argument("--cwd", type=Path, default=Path.cwd())
    parser.add_argument("--component", action="append", type=_component_argument, default=[])
    parser.add_argument("--exclude-dirty", action="append", type=_exclusion_argument, default=[])
    parser.add_argument("--timeout-seconds", type=float)
    parser.add_argument("--max-output-bytes", type=int, default=DEFAULT_OUTPUT_LIMIT)
    parser.add_argument("--attachment-plan", type=Path)
    parser.add_argument("--catalog-selection-kind", choices=["sha256", "git-revision"])
    parser.add_argument("--catalog-selection-value")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    result = parser.parse_args(argv)
    if result.command and result.command[0] == "--":
        result.command = result.command[1:]
    if not result.command:
        parser.error("a child command is required after --")
    result.cwd = result.cwd.resolve()
    result.store = result.store.resolve() if result.store is not None else _default_store()
    if result.attachment_plan is not None:
        result.attachment_plan = result.attachment_plan.resolve()
    if result.max_output_bytes < 0 or result.max_output_bytes > 64 * 1024 * 1024:
        parser.error("max output bytes must be between 0 and 67108864")
    return result


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    attachment_plan: AttachmentPlan | None = None
    try:
        entry, registry_digest, registry_raw = _registry_command(args.registry, args.command_id)
        prefix = entry.get("argvPrefix")
        if not isinstance(prefix, list) or args.command[: len(prefix)] != prefix:
            raise ValueError(f"argv does not match registered prefix for {args.command_id}")
        argv_length = entry.get("argvLength")
        if argv_length is not None and (type(argv_length) is not int
                or len(args.command) != argv_length):
            raise ValueError(f"argv length does not match registration for {args.command_id}")
        timeout = args.timeout_seconds if args.timeout_seconds is not None else float(entry["defaultTimeoutSeconds"])
        if timeout <= 0:
            raise ValueError("timeout must be positive")
        required_environment = entry.get("requiredEnvironment", {})
        if type(required_environment) is not dict or any(
                type(key) is not str or type(value) is not str
                or os.environ.get(key) != value
                for key, value in required_environment.items()):
            raise ValueError("required registered command environment does not match")
        required_environment_names = entry.get("requiredEnvironmentNames", [])
        if (type(required_environment_names) is not list
                or len(required_environment_names) != len(set(required_environment_names))
                or any(type(name) is not str or not name or name in required_environment
                       or not os.environ.get(name) for name in required_environment_names)):
            raise ValueError("required registered command environment names do not resolve")
        environment_file_hashes = entry.get("requiredEnvironmentFileSha256", {})
        if (type(environment_file_hashes) is not dict
                or any(type(name) is not str or name not in required_environment_names
                       or type(value) is not str or len(value) != 64
                       or any(character not in "0123456789abcdef" for character in value)
                       for name, value in environment_file_hashes.items())):
            raise ValueError("registered environment file identities are invalid")
        path_prefix = entry.get("requiredPathPrefix")
        if path_prefix is not None and (type(path_prefix) is not str
                or os.environ.get("PATH", "").split(os.pathsep)[0] != path_prefix):
            raise ValueError("registered command PATH prefix does not match")
        attachments_allowed = entry.get("attachmentsAllowed", False)
        if args.attachment_plan is not None and attachments_allowed is not True:
            raise ValueError("registered command does not admit attachments")
        if attachments_allowed is True:
            if args.attachment_plan is None:
                raise ValueError("registered command requires an attachment plan")
            attachment_plan = prepare_attachment_plan(args.attachment_plan)
            adapter_contract = entry.get("attachmentAdapter")
            if adapter_contract is not None:
                if (type(adapter_contract) is not dict or set(adapter_contract) != {
                        "kind", "application", "artifactId"}
                        or attachment_plan.adapter_kind != adapter_contract["kind"]
                        or attachment_plan.application != adapter_contract["application"]
                        or attachment_plan.adapter_artifact_id != adapter_contract["artifactId"]):
                    raise ValueError("attachment plan adapter differs from registered contract")
            output_contracts = entry.get("attachmentOutputs")
            if output_contracts is not None:
                actual_outputs = [{"artifactId": spec.artifact_id,
                    "relativePath": spec.relative_path, "role": spec.role,
                    "mediaType": spec.media_type, "requirement": spec.requirement,
                    "captureMode": spec.capture_mode, "maxBytes": spec.max_bytes,
                    "expectedSha256": spec.expected_sha256,
                    "producerResult": spec.producer_result} for spec in attachment_plan.attachments]
                if actual_outputs != output_contracts:
                    raise ValueError("attachment plan outputs differ from registered contract")
            root_index = entry.get("attachmentRootArgIndex")
            path_index = entry.get("attachmentPathArgIndex")
            if (root_index is None) == (path_index is None):
                raise ValueError("registered attachment command requires exactly one root/path argv binding")
            if root_index is not None:
                if (type(root_index) is not int or not 0 <= root_index < len(args.command)
                        or Path(args.command[root_index]) != attachment_plan.source_root):
                    raise ValueError("registered command output root differs from attachment plan")
            else:
                if type(path_index) is not int or not 0 <= path_index < len(args.command):
                    raise ValueError("registered command output path index is invalid")
                output_path = Path(args.command[path_index])
                declared_names = {spec.relative_path for spec in attachment_plan.attachments
                                  if spec.capture_mode == "new-output"}
                if (not output_path.is_absolute()
                        or output_path.parent != attachment_plan.source_root
                        or output_path.name not in declared_names):
                    raise ValueError("registered command output path differs from attachment plan")
        components = dict(args.component or [("mirrors", args.cwd)])
        if len(components) != len(args.component or [("mirrors", args.cwd)]):
            raise ValueError("duplicate component id")
        required_cwd = entry.get("requiredCwd")
        cwd_component = entry.get("requiredCwdComponentId")
        cwd_environment = entry.get("requiredCwdEnvironmentName")
        cwd_subdirectory = entry.get("requiredCwdSubdirectory")
        if sum(item is not None for item in (required_cwd, cwd_component, cwd_environment)) > 1:
            raise ValueError("registered command has conflicting cwd bindings")
        if required_cwd is not None:
            if type(required_cwd) is not str or args.cwd != Path(required_cwd).resolve():
                raise ValueError(f"working directory does not match registration for {args.command_id}")
        elif cwd_component is not None:
            if type(cwd_component) is not str or cwd_component not in components:
                raise ValueError("registered cwd component does not resolve")
            expected_cwd = components[cwd_component]
            if cwd_subdirectory is not None:
                if type(cwd_subdirectory) is not str:
                    raise ValueError("registered cwd subdirectory is invalid")
                expected_cwd = expected_cwd / _logical_path(cwd_subdirectory)
            if args.cwd != expected_cwd.resolve():
                raise ValueError(f"working directory does not match registration for {args.command_id}")
        elif cwd_environment is not None:
            if (type(cwd_environment) is not str
                    or cwd_environment not in required_environment_names):
                raise ValueError("registered cwd environment does not resolve")
            expected_cwd = Path(os.environ[cwd_environment])
            if not expected_cwd.is_absolute() or str(expected_cwd.resolve()) != os.environ[cwd_environment]:
                raise ValueError("registered cwd environment must be an absolute canonical path")
            if cwd_subdirectory is not None:
                if type(cwd_subdirectory) is not str:
                    raise ValueError("registered cwd subdirectory is invalid")
                expected_cwd = expected_cwd / _logical_path(cwd_subdirectory)
            if args.cwd != expected_cwd.resolve():
                raise ValueError(f"working directory does not match registration for {args.command_id}")
        elif cwd_subdirectory is not None:
            raise ValueError("registered cwd subdirectory lacks a component owner")
        exclusions: dict[str, dict[str, str]] = {component_id: {} for component_id in components}
        for component_id, path, reason in args.exclude_dirty:
            if component_id not in components:
                raise ValueError(f"exclusion names unknown component: {component_id}")
            exclusions[component_id][path] = reason
        before = [component_ref(component_id, path, exclusions[component_id]) for component_id, path in sorted(components.items())]
        catalog = _catalog_selection(args, entry, components, before)
        command_context = _command_context(args, entry, registry_digest, registry_raw, before)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        if attachment_plan is not None:
            attachment_plan.close()
        print(f"evidence collector preflight failed: {error}", file=sys.stderr)
        return 2

    run_id = f"run-{uuid.uuid4()}"
    started_utc = _utc_now()
    started_ns = time.monotonic_ns()
    observation = run_child(args.command, args.cwd, timeout, args.max_output_bytes)
    finished_ns = time.monotonic_ns()
    finished_utc = _utc_now()
    staging: Path | None = None
    try:
        current_entry, current_registry_digest, current_registry_raw = _registry_command(
            args.registry, args.command_id)
        if current_entry != entry or current_registry_digest != registry_digest:
            raise ValueError("command registry changed during collection")
        if current_registry_raw != registry_raw:
            raise ValueError("command registry changed during collection")
        after = [component_ref(component_id, path, exclusions[component_id]) for component_id, path in sorted(components.items())]
        staging = _stage(
            args.store,
            run_id,
            args,
            entry,
            before,
            after,
            catalog,
            observation,
            started_utc,
            finished_utc,
            finished_ns - started_ns,
            attachment_plan,
            command_context,
        )
    except (OSError, ValueError, KeyError) as error:
        print(f"evidence collection persistence failed: {error}", file=sys.stderr)
    if staging is not None:
        print(f"evidence staging: {staging}", file=sys.stderr)
    if attachment_plan is not None:
        attachment_plan.close()

    if observation.returncode is None:
        return 127
    if observation.returncode < 0:
        signum = -observation.returncode
        signal.signal(signum, signal.SIG_DFL)
        os.kill(os.getpid(), signum)
        return 128 + signum
    return observation.returncode


if __name__ == "__main__":
    raise SystemExit(main())
