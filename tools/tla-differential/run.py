"""DV2 orchestration: isolated captures and one observation per engine/fixture.

Comparison and aggregate report rendering deliberately remain outside this module.
The CLI's final compare/report imports are added by their owners after handoff.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import shutil
import subprocess
from datetime import datetime, timezone
from typing import Any, Callable, Mapping

import capture
import corpus
from process import ProcessLimits


Adapter = Callable[..., dict[str, Any]]


def code_snapshot(root: Path) -> dict[str, str]:
    """Hash implementation inputs before importing adapters and after execution."""
    names = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=root, capture_output=True, check=True).stdout.split(b"\0")
    result = {}
    for raw in names:
        name = raw.decode("utf-8")
        if name and (name.startswith(("Core/Tla/", "Shell/Tla/", "tools/tla-differential/")) or name in (
            "Codec/TlaFrontendJson.lean", "tools/TlaDifferentialDriver.lean", "lakefile.lean", "lean-toolchain")):
            path = root / name
            if path.is_file() and "__pycache__" not in path.parts:
                result[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def _artifact(reference: Path, output_dir: Path) -> dict[str, str]:
    return {
        "path": reference.relative_to(output_dir).as_posix(),
        "sha256": hashlib.sha256(reference.read_bytes()).hexdigest(),
    }


def _unavailable_observation(
    *, fixture: capture.AdapterFixture, engine: str, input_digest: str, message: str, config: Mapping[str, object]
) -> dict[str, Any]:
    tool = config.get("tool", {"id": engine, "version": "unavailable", "fingerprint": "unavailable"})
    return {
        "schema": corpus.OBSERVATION_SCHEMA,
        "fixture": fixture.id,
        "engine": engine,
        "provider": fixture.provider,
        "inputDigest": input_digest,
        "adapter": {"id": "runner.unavailable", "version": "1"},
        "tool": tool,
        "invocation": {"argv": [], "exitCode": None},
        "execution": "unavailable",
        "outcome": "unknown",
        "nativePhase": None,
        "stage": None,
        "diagnostics": [{"kind": "unavailable", "message": message}],
        "facts": {},
        "rawArtifacts": [],
    }


def _failed_observation(
    *, fixture: capture.AdapterFixture, engine: str, input_digest: str, message: str, config: Mapping[str, object], artifact_dir: Path, output_dir: Path
) -> dict[str, Any]:
    error_file = artifact_dir / "runner-error.txt"
    error_file.write_text(message + "\n", encoding="utf-8")
    observation = _unavailable_observation(
        fixture=fixture, engine=engine, input_digest=input_digest, message=message, config=config
    )
    observation["execution"] = "crash"
    observation["adapter"] = {"id": "runner", "version": "1"}
    observation["diagnostics"] = [{"kind": "runner_error", "message": message}]
    observation["rawArtifacts"] = [_artifact(error_file, output_dir)]
    return observation


def _validate_observation(
    observation: Mapping[str, Any], fixture: capture.AdapterFixture, engine: str, input_digest: str
) -> dict[str, Any]:
    value = dict(observation)
    for key, expected in (("fixture", fixture.id), ("engine", engine), ("provider", fixture.provider), ("inputDigest", input_digest)):
        if value.get(key) != expected:
            raise ValueError(f"adapter observation has wrong {key}: {value.get(key)!r}")
    corpus.validate_contract("observation", value)
    return value


def run_corpus(
    *,
    captured: corpus.CorpusCapture,
    adapters: Mapping[str, Adapter],
    configs: Mapping[str, Mapping[str, object]],
    output_dir: Path,
    limits: ProcessLimits = ProcessLimits(),
) -> tuple[dict[str, Any], ...]:
    """Capture every engine input independently and return every observation row."""

    output_dir.mkdir(parents=True, exist_ok=True)
    observations: list[dict[str, Any]] = []
    for fixture in captured.fixtures:
        for engine in corpus.ENGINES:
            config = configs.get(engine, {})
            artifact_dir = output_dir / "fixtures" / fixture.id / engine / "raw"
            artifact_dir.mkdir(parents=True, exist_ok=True)
            with tempfile.TemporaryDirectory(prefix=f"{fixture.id}-{engine}-", dir=output_dir) as temporary:
                materialized = capture.materialize_fixture(fixture=fixture, directory=Path(temporary) / "input")
                adapter = adapters.get(engine)
                if adapter is None:
                    observation = _unavailable_observation(
                        fixture=materialized.fixture,
                        engine=engine,
                        input_digest=materialized.input_digest,
                        message=f"no {engine} adapter configured",
                        config=config,
                    )
                else:
                    try:
                        capture.verify_materialized(materialized)
                        observation = adapter(
                            fixture=materialized.fixture,
                            materialized=materialized,
                            config=config,
                            limits=limits,
                            artifact_dir=artifact_dir,
                        )
                        capture.verify_materialized(materialized)
                        observation = _validate_observation(observation, materialized.fixture, engine, materialized.input_digest)
                    except Exception as error:
                        observation = _failed_observation(
                            fixture=materialized.fixture,
                            engine=engine,
                            input_digest=materialized.input_digest,
                            message=f"{type(error).__name__}: {error}",
                            config=config,
                            artifact_dir=artifact_dir,
                            output_dir=output_dir,
                        )
            observation_path = artifact_dir.parent / "observation.json"
            observation_path.write_text(corpus.canonical_json(observation) + "\n", encoding="utf-8")
            observations.append(observation)
    return tuple(observations)


def main(argv: list[str] | None = None) -> int:
    class Arguments(argparse.ArgumentParser):
        def error(self, message):
            self.print_usage(__import__('sys').stderr)
            self.exit(3, f"{self.prog}: error: {message}\n")
    parser = Arguments(description="Run captured TLA+ differential observations")
    root = Path(__file__).resolve().parents[2]
    parser.add_argument("--output", type=Path, default=root / ".golden-build/tla-differential/results", help="new local evidence directory")
    parser.add_argument("--required", action="store_true", help="require all corpus observations and structural comparisons")
    parser.add_argument("--timeout", type=float, default=60, help="per-invocation timeout seconds")
    args = parser.parse_args(argv)
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("output directory must be empty; evidence is never overwritten")
    code_inputs = code_snapshot(root)
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True, check=True).stdout.strip()
    changed = subprocess.run(["git", "diff", "--binary", "HEAD"], cwd=root, capture_output=True, check=True).stdout
    try:
        captured = corpus.load_corpus(root)
        registry_path = root / "test/fixtures/tla-frontend/differential/differences.json"
        registry = json.loads(registry_path.read_text())
        lock_path = Path(__file__).with_name("toolchain.lock.json")
        lock = json.loads(lock_path.read_text())
        lock_digest = hashlib.sha256(lock_path.read_bytes()).hexdigest()
        corpus.validate_contract("lock", lock)
        limits = ProcessLimits(timeout_seconds=args.timeout)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    from adapters import mirrors, sany, apalache
    from compare import compare_corpus
    from report import write_report
    from process import ProcessRequest, run_process
    import acquire
    cli, driver = root / ".lake/build/bin/tla_frontend", root / ".lake/build/bin/tla_differential_driver"
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    configs = {}
    adapters = {}
    setup_errors = []
    if cli.is_file() and driver.is_file():
        configs["mirrors"] = {"cli": str(cli), "driver": str(driver), "tool": {"id": "mirrors", "version": "worktree", "fingerprint": hashlib.sha256((digest(cli) + digest(driver)).encode()).hexdigest()}}
        adapters["mirrors"] = mirrors.observe
    else:
        setup_errors.append("Mirrors frontend/driver binaries unavailable; run lake build")
    try:
        acquire.verify_tools()
        java = shutil.which("java")
        javac = shutil.which("javac")
        if java is None or javac is None:
            raise ValueError("Java compiler/runtime unavailable")
        toolchain = acquire.TOOLCHAIN
        jar = toolchain / lock["tools"]["sany"]["path"]
        apalache_jar = toolchain / "apalache-0.61.0/lib/apalache.jar"
        classes = toolchain / "bridge-classes"
        classes.mkdir(exist_ok=True)
        source = Path(__file__).with_name("bridges") / "SanyBridge.java"
        compiled = run_process(ProcessRequest([javac, "-J-XX:-UsePerfData", "-cp", str(jar), "-d", str(classes), str(source)], root), limits)
        if compiled.status.value != "completed" or compiled.returncode != 0:
            raise ValueError("bridge compilation failed: " + compiled.stderr.decode("utf-8", errors="replace"))
        configs["sany"] = {"java": java, "sany_jar": str(jar), "bridge_classes": str(classes), "version": lock["tools"]["sany"]["version"],
                           "tool": {"id": "tla2tools", "version": lock["tools"]["sany"]["version"], "fingerprint": digest(jar)}}
        configs["apalache"] = {"java": java, "apalache_jar": str(apalache_jar), "version": lock["tools"]["apalache"]["version"],
                               "tool": {"id": "apalache", "version": lock["tools"]["apalache"]["version"], "fingerprint": digest(apalache_jar)}}
        adapters.update(sany=sany.observe, apalache=apalache.observe)
    except (SystemExit, ValueError, OSError) as error:
        setup_errors.append(str(error))
    executable_paths = [path for path in (cli, driver) if path.is_file()]
    for key in ("sany_jar", "apalache_jar"):
        executable_paths += [Path(config[key]) for config in configs.values() if key in config]
    if "sany" in configs:
        executable_paths += list(Path(configs["sany"]["bridge_classes"]).glob("*.class"))
    executable_snapshot = {str(path): digest(path) for path in executable_paths}
    output.mkdir(parents=True, exist_ok=True)
    archived_code = {name: (root / name).read_bytes().decode("utf-8") for name in code_inputs}
    if any(hashlib.sha256(text.encode()).hexdigest() != code_inputs[name] for name, text in archived_code.items()):
        parser.error("implementation changed while capturing it")
    captured_inputs = {"schema": "mirrors.tla-differential-input-capture/v1", "code": archived_code,
        "trackedDiff": changed.decode("utf-8"), "registry": registry,
        "fixtures": [{"id": fixture.id, "provider": fixture.provider, "root": fixture.root,
            "manifest": fixture.manifest_expectation, "summary": fixture.summary,
            "sources": [{"path": source.logical_path, "sha256": source.sha256,
                "text": source.normalized_bytes.decode("utf-8")} for source in fixture.supplied_sources]}
            for fixture in captured.fixtures]}
    capture_path = output / "captured-inputs.json"
    capture_path.write_text(corpus.canonical_json(captured_inputs) + "\n")
    runtime_observation = None
    if "sany" in configs:
        runtime_result = run_process(ProcessRequest([configs["sany"]["java"], "-XX:-UsePerfData", "-version"], root), limits)
        runtime_observation = {"exitCode": runtime_result.returncode,
            "stdout": runtime_result.stdout.decode("utf-8", errors="replace"),
            "stderr": runtime_result.stderr.decode("utf-8", errors="replace")}
    observations = run_corpus(captured=captured, adapters=adapters, configs=configs, output_dir=output, limits=limits)
    comparisons, coverage, verdict = compare_corpus(captured, observations, registry,
        {"tools": {engine: config["tool"] for engine, config in configs.items()},
         "expectedTools": {"sany": {"fingerprint": lock["tools"]["sany"]["sha256"]},
                           "apalache": {"fingerprint": lock["tools"]["apalache"]["jarSha256"]}},
         "evidenceRoot": str(output), "reviewRoot": str(root)})
    stable = code_inputs == code_snapshot(root) and all(Path(path).is_file() and digest(Path(path)) == sha for path, sha in executable_snapshot.items())
    if not stable:
        comparisons.append({"fixture": "run", "engine": "all", "fact": "implementation", "status": "fail",
            "detail": "implementation or executable changed during execution; exploratory evidence only", "expected": None, "actual": None})
        coverage["comparisons"]["fail"] = coverage["comparisons"].get("fail", 0) + 1
        verdict = "fail"
    identity = {"profile": captured.profile, "manifestSha256": captured.manifest_sha256, "profileSha256": captured.profile_sha256,
                "summarySha256": captured.summary_sha256, "registrySha256": captured.registry_sha256,
                "lockSha256": lock_digest, "codeInputs": code_inputs,
                "executables": {Path(path).name: sha for path, sha in executable_snapshot.items()},
                "runtime": runtime_observation,
                "tools": {engine: config["tool"] for engine, config in configs.items()}, "limits": vars(limits)}
    inputs = {"semanticIdentity": identity, "repositoryCommit": revision, "trackedDiffSha256": hashlib.sha256(changed).hexdigest(),
              "dirty": bool(subprocess.run(["git", "status", "--porcelain"], cwd=root, capture_output=True, check=True).stdout),
              "timestamp": datetime.now(timezone.utc).isoformat(), "setupErrors": setup_errors,
              "toolchain": lock, "implementationStable": stable,
              "capturedInputs": {"path": capture_path.name, "sha256": digest(capture_path)},
              "command": ["python3", "tools/tla-differential/run.py", *(argv if argv is not None else __import__('sys').argv[1:])]}
    write_report(output, inputs, observations, comparisons, coverage, verdict)
    print(f"TLA DIFFERENTIAL {verdict.upper()}: {len(observations)} observations; report {output / 'report.json'}")
    return {"pass": 0, "fail": 1, "incomplete": 2}[verdict]


if __name__ == "__main__":
    raise SystemExit(main())
