#!/usr/bin/env python3
"""Exercise DPM identity generation and build freshness in a private Linux copy.

No model checker is started. Sources, evidence, dependency caches, and selected
runtime bytes in the original checkout are never used as writable test inputs.
"""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


SOURCE = Path(__file__).resolve().parents[1]
TIMEOUT_SECONDS = 1800
GENERATED = Path(".lake/build/dpm-generated/Shell/Dpm/HostIdentity.lean")
MODULE = Path(".lake/build/lib/lean/Shell/Dpm/HostIdentity.olean")
LAUNCHER = Path(".lake/build/bin/mirrors_dpm")
OUTPUTS = (GENERATED, MODULE, LAUNCHER)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(work, paths=OUTPUTS):
    return {str(path): (digest(work / path), (work / path).stat().st_mtime_ns)
            for path in paths}


def command(work, env, args, *, expected=0):
    try:
        result = subprocess.run(args, cwd=work, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=TIMEOUT_SECONDS, check=False)
    except subprocess.TimeoutExpired as error:
        raise AssertionError(f"command timed out after {TIMEOUT_SECONDS}s: {args}") from error
    if expected is not None and result.returncode != expected:
        print(result.stdout, end="", flush=True)
        raise AssertionError(f"command exited {result.returncode}, expected {expected}: {args}")
    return result


def build(work, env, *targets, expected=0):
    result = command(work, env, ["lake", "build", *targets], expected=expected)
    if result.returncode == 0:
        for line in result.stdout.splitlines():
            if "Built " in line or line.startswith("Build completed"):
                print(line, flush=True)
    return result


def help_succeeds(work, env):
    result = command(work, env, [str(work / LAUNCHER), "--help"])
    if "mirrors-dpm" not in result.stdout or "doctor" not in result.stdout:
        raise AssertionError("launcher --help did not reach the packaged CLI")


def help_refuses(work, env, reason):
    result = command(work, env, [str(work / LAUNCHER), "--help"], expected=2)
    if reason not in result.stdout:
        raise AssertionError(f"launcher refused for an unexpected reason: {result.stdout}")


def no_op(work, env):
    before = snapshot(work)
    build(work, env, "mirrors_dpm")
    if snapshot(work) != before:
        raise AssertionError("unchanged DPM rebuild modified generated source, module, or launcher")


def changed(work, before, description):
    after = snapshot(work)
    for name in before:
        if before[name][0] == after[name][0]:
            raise AssertionError(f"{description} did not change {name}")


def copy_tree(source, destination):
    # Never hardlink caches: the regression must not mutate build artifacts in
    # the caller's checkout. Dependency .git metadata is retained for Lake.
    shutil.copytree(source, destination,
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))


def copy_checkout(work):
    work.mkdir()
    for name in ("Core", "Codec", "Shell", "Ffi"):
        copy_tree(SOURCE / name, work / name)
    for name in ("Main.lean", "lakefile.lean", "lake-manifest.json", "lean-toolchain"):
        shutil.copy2(SOURCE / name, work / name)
    (work / "tools").mkdir()
    for source in (SOURCE / "tools").glob("*.lean"):
        shutil.copy2(source, work / "tools" / source.name)
    copy_tree(SOURCE / "tools/deterministic-scheduling",
              work / "tools/deterministic-scheduling")
    # Reuse only relevant private caches. Other executable caches alone can
    # occupy several GiB, and historical Plans/test evidence is unnecessary.
    for name in ("config", "packages"):
        source = SOURCE / ".lake" / name
        if source.exists():
            copy_tree(source, work / ".lake" / name)
    source_build = SOURCE / ".lake/build"
    if source_build.exists():
        destination = work / ".lake/build"
        destination.mkdir(parents=True, exist_ok=True)
        for source in source_build.iterdir():
            if source.is_file():
                shutil.copy2(source, destination / source.name)
            elif source.name in ("lib", "ir"):
                copy_tree(source, destination / source.name)
        (destination / "bin").mkdir()
        for target in ("mirror", "mirrors_dpm"):
            for source in (source_build / "bin").glob(target + "*"):
                if source.is_file() and (source.name == target or source.name.startswith(target + ".")):
                    shutil.copy2(source, destination / "bin" / source.name)


def remove_generated_module(work):
    (work / GENERATED).unlink(missing_ok=True)
    for directory in ("lib/lean", "ir"):
        for path in (work / ".lake/build" / directory / "Shell/Dpm").glob("HostIdentity.*"):
            path.unlink()


def main():
    if sys.platform != "linux":
        print("SKIP: isolated DPM build regression requires Linux (copied ELF runtime probe).")
        return 0
    selected = shutil.which("python3")
    if selected is None:
        raise AssertionError("python3 is unavailable for the default DPM build selection")
    interpreter = Path(selected).resolve(strict=True)
    original_interpreter = digest(interpreter)
    original_cli = digest(SOURCE / "tools/deterministic-scheduling/cli.py")
    with tempfile.TemporaryDirectory(prefix="mirrors-dpm-build-") as temporary:
        work = Path(temporary) / "repo"
        print(f"DPM build regression uses {work}", flush=True)
        copy_checkout(work)
        env = os.environ.copy()
        env.pop("MIRRORS_DPM_PYTHON", None)

        # Prove generation from absence even when another host left compiled
        # DPM artifacts behind, then prove that stable identities are no-ops.
        remove_generated_module(work)
        for path in (work / ".lake/build/bin").glob("mirrors_dpm*"):
            path.unlink()
        build(work, env, "mirrors_dpm")
        help_succeeds(work, env)
        no_op(work, env)
        print("PASS: absent generated identity is prepared; unchanged rebuild preserves outputs", flush=True)

        remove_generated_module(work)
        build(work, env, "Shell")
        if not (work / GENERATED).is_file() or not (work / MODULE).is_file():
            raise AssertionError("lake build Shell did not prepare the imported identity module")
        build(work, env, "mirrors_dpm", "mirror")
        help_succeeds(work, env)
        print("PASS: Shell library builds with the generated identity initially absent", flush=True)

        configs = tuple(path.relative_to(work)
                        for path in (work / ".lake/config").rglob("lakefile.olean"))
        if not configs:
            raise AssertionError("Lake configuration cache was not populated")
        cached_config = snapshot(work, configs)
        copied = Path(temporary) / "selected runtime with spaces" / interpreter.name
        copied.parent.mkdir()
        shutil.copy2(interpreter, copied)
        env["MIRRORS_DPM_PYTHON"] = str(copied)
        before = snapshot(work)
        build(work, env, "mirrors_dpm")
        changed(work, before, "interpreter path selection")
        help_succeeds(work, env)
        no_op(work, env)
        if snapshot(work, configs) != cached_config:
            raise AssertionError("interpreter selection required regenerating the cached Lake configuration")
        print("PASS: interpreter path with spaces changes identity through cached Lake configuration", flush=True)

        # An inert ELF trailer changes the executable identity without changing
        # Python behavior. The old launcher must refuse before any rebuild.
        before = snapshot(work)
        with copied.open("ab") as stream:
            stream.write(b"\nMirrors DPM runtime identity regression\n")
        help_refuses(work, env, "DPM Python runtime differs")
        build(work, env, "mirrors_dpm")
        changed(work, before, "interpreter content change")
        help_succeeds(work, env)
        no_op(work, env)
        print("PASS: changed interpreter bytes are refused until rebuilt and repinned", flush=True)

        before = snapshot(work)
        with (work / "tools/deterministic-scheduling/cli.py").open("a") as stream:
            stream.write("\n# Isolated DPM helper freshness regression.\n")
        help_refuses(work, env, "DPM host artifact differs: cli.py")
        build(work, env, "mirrors_dpm")
        changed(work, before, "packaged CLI helper edit")
        help_succeeds(work, env)
        no_op(work, env)
        print("PASS: helper-only edits are refused until rebuilt and repinned", flush=True)

        before = snapshot(work)
        env["MIRRORS_DPM_PYTHON"] = str(Path(temporary) / "missing-python")
        result = build(work, env, "mirrors_dpm", expected=None)
        if result.returncode == 0 or "DPM host identity" not in result.stdout or "missing-python" not in result.stdout:
            raise AssertionError(f"missing selected interpreter did not fail clearly: {result.stdout}")
        if snapshot(work) != before:
            raise AssertionError("failed identity preparation overwrote working DPM build outputs")
        build(work, env, "mirror")
        help_succeeds(work, env)
        print("PASS: missing selected runtime fails DPM build without replacing outputs; mirror still builds", flush=True)

    if digest(interpreter) != original_interpreter:
        raise AssertionError("original selected interpreter changed during isolated regression")
    if digest(SOURCE / "tools/deterministic-scheduling/cli.py") != original_cli:
        raise AssertionError("original CLI helper changed during isolated regression")
    print("All DPM build checks passed; original runtime and helper bytes unchanged.", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError) as error:
        print(f"DPM build regression failed: {error}", file=sys.stderr)
        raise SystemExit(1)
