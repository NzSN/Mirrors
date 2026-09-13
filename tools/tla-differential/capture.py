"""Stage frozen corpus bytes into one isolated tool input directory."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from types import MappingProxyType
from typing import Mapping

from corpus import FixtureCapture, SourceFile


@dataclass(frozen=True)
class AdapterFixture:
    """The fixture view given to an external oracle adapter.

    It intentionally omits corpus expectations, reasons, summaries, and fact
    requirements so reference observations cannot be derived from Mirrors data.
    """

    id: str
    provider: str
    root: str
    source_root: str | None
    inline_source_map: tuple[Mapping[str, str], ...]


@dataclass(frozen=True)
class MaterializedFixture:
    fixture: AdapterFixture
    input_dir: Path
    root_path: Path
    sources: Mapping[str, Path]
    source_bytes: Mapping[str, bytes]
    source_digests: Mapping[str, str]
    input_digest: str


class CaptureError(ValueError):
    pass


def adapter_fixture(fixture: FixtureCapture) -> AdapterFixture:
    inline_map = tuple(
        MappingProxyType({"logicalName": item["logicalName"], "stagedPath": f"{item['logicalName']}.tla"})
        for item in fixture.inline_source_map
    )
    return AdapterFixture(fixture.id, fixture.provider, fixture.root, fixture.source_root, inline_map)


def _relative_name(fixture: FixtureCapture, source: SourceFile) -> Path:
    logical = Path(source.logical_path)
    if fixture.source_root is None:
        for item in fixture.inline_source_map:
            if item["file"] == source.logical_path:
                return Path(f"{item['logicalName']}.tla")
        raise CaptureError(f"{fixture.id}: inline source has no logical name: {source.logical_path}")
    try:
        relative = logical.relative_to(fixture.source_root)
    except ValueError as error:
        raise CaptureError(f"{fixture.id}: source is outside sourceRoot: {source.logical_path}") from error
    if not relative.parts:
        raise CaptureError(f"{fixture.id}: sourceRoot cannot name a source file")
    return relative


def _input_digest(fixture: AdapterFixture, source_bytes: Mapping[str, bytes]) -> str:
    digest = hashlib.sha256()
    for value in (fixture.id, fixture.provider, fixture.root, fixture.source_root or ""):
        encoded = value.encode("utf-8")
        digest.update(len(encoded).to_bytes(8, "big"))
        digest.update(encoded)
    inline_map = json.dumps([dict(item) for item in fixture.inline_source_map], sort_keys=True, separators=(",", ":")).encode("utf-8")
    digest.update(len(inline_map).to_bytes(8, "big"))
    digest.update(inline_map)
    for name in sorted(source_bytes):
        encoded = name.encode("utf-8")
        digest.update(len(encoded).to_bytes(8, "big"))
        digest.update(encoded)
        digest.update(len(source_bytes[name]).to_bytes(8, "big"))
        digest.update(source_bytes[name])
    return digest.hexdigest()


def materialize_fixture(*, fixture: FixtureCapture, directory: Path) -> MaterializedFixture:
    """Write exactly the captured normalized sources into an empty directory."""

    directory.mkdir(parents=True, exist_ok=False)
    sanitized = adapter_fixture(fixture)
    paths: dict[str, Path] = {}
    bytes_by_name: dict[str, bytes] = {}
    digests: dict[str, str] = {}
    for source in fixture.supplied_sources:
        name = _relative_name(fixture, source).as_posix()
        if name in paths:
            raise CaptureError(f"{fixture.id}: duplicate staged source name: {name}")
        path = directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(source.normalized_bytes)
        paths[name] = path
        bytes_by_name[name] = source.normalized_bytes
        digests[name] = source.sha256

    root_name = f"{fixture.root}.tla"
    root_candidates = [path for name, path in paths.items() if Path(name).name == root_name]
    if len(root_candidates) != 1:
        raise CaptureError(f"{fixture.id}: cannot identify a unique staged root file {root_name}")
    return MaterializedFixture(
        sanitized,
        directory,
        root_candidates[0],
        MappingProxyType(paths),
        MappingProxyType(bytes_by_name),
        MappingProxyType(digests),
        _input_digest(sanitized, bytes_by_name),
    )


def fixture_input_digest(fixture: FixtureCapture) -> str:
    """Expected invocation identity derived solely from the frozen capture."""
    return _input_digest(adapter_fixture(fixture), {
        _relative_name(fixture, source).as_posix(): source.normalized_bytes
        for source in fixture.supplied_sources})


def verify_materialized(materialized: MaterializedFixture) -> None:
    """Refuse an invocation whose tool changed or removed its frozen inputs."""

    if materialized.input_dir.is_symlink():
        raise CaptureError("staged input directory became a symlink")
    # Resolve only sibling modules, exactly as the providers do. Native tool
    # outputs live below separate child directories and are not source inputs.
    parents = {path.parent for path in materialized.sources.values()}
    for parent in parents:
        cursor = parent
        while cursor != materialized.input_dir:
            if cursor.is_symlink() or not cursor.is_relative_to(materialized.input_dir):
                raise CaptureError("staged source directory changed")
            cursor = cursor.parent
        expected_paths = {path for path in materialized.sources.values() if path.parent == parent}
        if set(parent.glob("*.tla")) != expected_paths:
            raise CaptureError("staged sibling source set changed")
    actual: dict[str, bytes] = {}
    for name, expected in materialized.source_bytes.items():
        path = materialized.sources[name]
        try:
            if path.is_symlink() or not path.is_file():
                raise OSError("staged source is no longer a regular file")
            observed = path.read_bytes()
        except OSError as error:
            raise CaptureError(f"{materialized.fixture.id}: staged source missing: {name}") from error
        if observed != expected:
            raise CaptureError(f"{materialized.fixture.id}: staged source changed: {name}")
        actual[name] = observed
    if _input_digest(materialized.fixture, actual) != materialized.input_digest:
        raise CaptureError(f"{materialized.fixture.id}: staged input digest changed")
