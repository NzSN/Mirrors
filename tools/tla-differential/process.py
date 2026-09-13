"""Bounded, hermetic subprocess execution for differential-tool adapters.

This module deliberately knows nothing about fixture capture or adapter output.
In particular, a non-zero exit is a completed execution: adapters decide whether
the tool's own result denotes language rejection.  Only a signal termination or
one of the enforced execution bounds changes the execution status here.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
import os
from pathlib import Path
import signal
import shutil
import subprocess
import threading
import time
from typing import Callable, Mapping, Sequence


DEFAULT_TIMEOUT_SECONDS = 60.0
DEFAULT_MAX_OUTPUT_BYTES = 8 * 1024 * 1024
DEFAULT_MAX_ARTIFACT_BYTES = 64 * 1024 * 1024


class ExecutionStatus(str, Enum):
    """Statuses used by the differential observation contract.

    ``INVALID_OUTPUT`` is intentionally not produced by this transport layer;
    adapters assign it after parsing a completed tool response.
    """

    COMPLETED = "completed"
    UNAVAILABLE = "unavailable"
    TIMEOUT = "timeout"
    CRASH = "crash"
    INVALID_OUTPUT = "invalid_output"
    RESOURCE_EXHAUSTED = "resource_exhausted"


@dataclass(frozen=True)
class ProcessLimits:
    """Execution ceilings.

    Artifact directories are sampled at the runner poll interval, so a writer
    can briefly overshoot ``max_artifact_bytes`` by up to one polling window.
    The oversized tree is discarded before this function returns.
    """

    timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS
    max_stdout_bytes: int = DEFAULT_MAX_OUTPUT_BYTES
    max_stderr_bytes: int = DEFAULT_MAX_OUTPUT_BYTES
    max_artifact_bytes: int = DEFAULT_MAX_ARTIFACT_BYTES

    def __post_init__(self) -> None:
        if self.timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        for name in ("max_stdout_bytes", "max_stderr_bytes", "max_artifact_bytes"):
            if getattr(self, name) < 0:
                raise ValueError(f"{name} must not be negative")


@dataclass(frozen=True)
class ProcessRequest:
    """A direct executable invocation; shell syntax is not accepted."""

    argv: Sequence[str]
    cwd: Path
    environment: Mapping[str, str] = field(default_factory=dict)
    artifact_dir: Path | None = None

    def __post_init__(self) -> None:
        if not self.argv:
            raise ValueError("argv must contain an executable")
        if any(not isinstance(argument, str) or "\x00" in argument for argument in self.argv):
            raise ValueError("argv entries must be strings without NUL bytes")
        if not self.cwd.is_dir():
            raise ValueError(f"cwd is not a directory: {self.cwd}")
        if self.artifact_dir is not None:
            if not self.artifact_dir.is_dir() or self.artifact_dir.is_symlink():
                raise ValueError(f"artifact_dir must be a non-symlink directory: {self.artifact_dir}")
            cwd = self.cwd.resolve()
            artifact_dir = self.artifact_dir.resolve()
            if artifact_dir == cwd or cwd not in artifact_dir.parents:
                raise ValueError("artifact_dir must be strictly below cwd")
            if any(self.artifact_dir.iterdir()):
                raise ValueError("artifact_dir must be initially empty")
        for key, value in self.environment.items():
            if (
                not isinstance(key, str)
                or not isinstance(value, str)
                or not key
                or "=" in key
                or "\x00" in key
                or "\x00" in value
            ):
                raise ValueError("environment contains an invalid key or value")


@dataclass(frozen=True)
class ProcessResult:
    status: ExecutionStatus
    returncode: int | None
    stdout: bytes
    stderr: bytes
    elapsed_seconds: float
    artifact_bytes: int | None
    detail: str | None = None


def deterministic_environment(overrides: Mapping[str, str] = {}) -> dict[str, str]:
    """Return the complete environment inherited by a tool invocation.

    The caller must explicitly supply any tool-specific path such as a Java
    runtime or module search path.  This avoids accidental dependence on a
    developer's locale, home directory, or ambient TLA+/JVM configuration.
    """

    environment = {
        "LANG": "C",
        "LC_ALL": "C",
        "NO_COLOR": "1",
        "PATH": os.defpath,
        "PYTHONIOENCODING": "utf-8",
        "SOURCE_DATE_EPOCH": "0",
        "TERM": "dumb",
        "TZ": "UTC",
    }
    environment.update(overrides)
    return environment


def _directory_size(directory: Path) -> int:
    """Count regular artifact bytes without following links outside the bundle."""

    total = 0
    for path in directory.rglob("*"):
        try:
            if path.is_file() and not path.is_symlink():
                total += path.stat().st_size
        except FileNotFoundError:
            # A tool can remove a transient artifact while this monitor walks it.
            continue
    return total


def _discard_artifacts(directory: Path) -> None:
    """Remove an over-limit invocation tree before it can enter retained evidence."""

    shutil.rmtree(directory)
    directory.mkdir()


def _process_group_exists(process_group_id: int) -> bool:
    try:
        os.killpg(process_group_id, 0)
    except ProcessLookupError:
        return False
    return True


def _terminate_process_group(process: subprocess.Popen[bytes]) -> None:
    """End every POSIX group member, including children of an exited leader."""

    if os.name == "posix":
        process_group_id = process.pid
        try:
            os.killpg(process_group_id, signal.SIGTERM)
        except ProcessLookupError:
            return
        deadline = time.monotonic() + 0.2
        while time.monotonic() < deadline:
            if not _process_group_exists(process_group_id):
                return
            time.sleep(0.01)
        if _process_group_exists(process_group_id):
            try:
                os.killpg(process_group_id, signal.SIGKILL)
            except ProcessLookupError:
                pass
        return

    # Windows has no stdlib equivalent of POSIX killpg. CREATE_NEW_PROCESS_GROUP
    # lets Console tools receive CTRL_BREAK_EVENT; terminating the direct process
    # remains the portable fallback. CI support for recursive Windows cleanup must
    # be supplied by the runner's platform-specific containment layer.
    process.terminate()


def _stream_reader(
    stream: object,
    maximum: int,
    captured: bytearray,
    exceeded: threading.Event,
) -> None:
    # BufferedReader.read(n) may wait for n bytes, hiding a small flood until
    # process exit. read1 observes each currently available pipe chunk instead.
    read = getattr(stream, "read1", None)
    if read is None:
        read = getattr(stream, "read")
    while True:
        chunk = read(64 * 1024)
        if not chunk:
            return
        remaining = maximum - len(captured)
        if remaining > 0:
            captured.extend(chunk[:remaining])
        if len(chunk) > remaining:
            exceeded.set()


def run_process(
    request: ProcessRequest,
    limits: ProcessLimits = ProcessLimits(),
    *,
    popen_factory: Callable[..., subprocess.Popen[bytes]] = subprocess.Popen,
    monotonic: Callable[[], float] = time.monotonic,
    poll_interval_seconds: float = 0.02,
) -> ProcessResult:
    """Run one direct command with bounded streams, artifacts, and lifetime."""

    if poll_interval_seconds <= 0:
        raise ValueError("poll_interval_seconds must be positive")

    started = monotonic()
    try:
        process = popen_factory(
            list(request.argv),
            cwd=request.cwd,
            env=deterministic_environment(request.environment),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            shell=False,
            start_new_session=os.name == "posix",
            creationflags=(subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0),
        )
    except OSError as error:
        return ProcessResult(
            ExecutionStatus.UNAVAILABLE, None, b"", b"", monotonic() - started, None, str(error)
        )

    assert process.stdout is not None
    assert process.stderr is not None
    stdout, stderr = bytearray(), bytearray()
    stdout_exceeded, stderr_exceeded = threading.Event(), threading.Event()
    readers = [
        threading.Thread(target=_stream_reader, args=(process.stdout, limits.max_stdout_bytes, stdout, stdout_exceeded)),
        threading.Thread(target=_stream_reader, args=(process.stderr, limits.max_stderr_bytes, stderr, stderr_exceeded)),
    ]
    for reader in readers:
        reader.start()

    status = ExecutionStatus.COMPLETED
    detail: str | None = None
    artifact_bytes: int | None = None
    try:
        while True:
            if process.poll() is not None:
                # The leader can exit while a background child still owns the
                # pipes and artifacts. Every invocation owns its whole group.
                process.wait()
                _terminate_process_group(process)
                break
            elapsed = monotonic() - started
            if elapsed >= limits.timeout_seconds:
                status, detail = ExecutionStatus.TIMEOUT, "process exceeded timeout"
            elif stdout_exceeded.is_set() or stderr_exceeded.is_set():
                status, detail = ExecutionStatus.RESOURCE_EXHAUSTED, "process exceeded output limit"
            elif request.artifact_dir is not None:
                artifact_bytes = _directory_size(request.artifact_dir)
                if artifact_bytes > limits.max_artifact_bytes:
                    status, detail = ExecutionStatus.RESOURCE_EXHAUSTED, "process exceeded artifact limit"
            if status is not ExecutionStatus.COMPLETED:
                _terminate_process_group(process)
                break
            time.sleep(poll_interval_seconds)

        try:
            returncode = process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            _terminate_process_group(process)
            returncode = process.wait()
    except BaseException:
        # The subprocess has a separate session, so an interrupted Python
        # runner must explicitly end the complete tool group before propagating.
        _terminate_process_group(process)
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass
        for reader in readers:
            reader.join()
        process.stdout.close()
        process.stderr.close()
        raise
    else:
        for reader in readers:
            reader.join()
        process.stdout.close()
        process.stderr.close()

    if status is ExecutionStatus.COMPLETED and (stdout_exceeded.is_set() or stderr_exceeded.is_set()):
        status, detail = ExecutionStatus.RESOURCE_EXHAUSTED, "process exceeded output limit"
    if request.artifact_dir is not None:
        artifact_bytes = _directory_size(request.artifact_dir)
        if artifact_bytes > limits.max_artifact_bytes:
            observed_bytes = artifact_bytes
            _discard_artifacts(request.artifact_dir)
            artifact_bytes = 0
            if status is ExecutionStatus.COMPLETED:
                status, detail = ExecutionStatus.RESOURCE_EXHAUSTED, "process exceeded artifact limit"
            detail = f"{detail}; discarded {observed_bytes} retained artifact bytes"
    if status is ExecutionStatus.COMPLETED and returncode < 0:
        status, detail = ExecutionStatus.CRASH, f"process terminated by signal {-returncode}"

    return ProcessResult(status, returncode, bytes(stdout), bytes(stderr), monotonic() - started, artifact_bytes, detail)
