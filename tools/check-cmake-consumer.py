#!/usr/bin/env python3
"""Exercise generated CMake consumers, offline freshness, and owned publication."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COMPILER = ROOT / ".lake/build/bin/model_interface_gen"


def run(argv: list[str], cwd: Path, *, ok: bool = True, signal: str = "") -> str:
    result = subprocess.run(argv, cwd=cwd, text=True, capture_output=True, timeout=120)
    output = result.stdout + result.stderr
    if (result.returncode == 0) != ok or signal and signal not in output:
        raise AssertionError(f"{argv}: exit {result.returncode}\n{output}")
    return output


def snapshot(root: Path) -> dict[str, str]:
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob("*") if p.is_file()}


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="mirrors cmake consumer ") as directory:
        root = Path(directory)
        (root / "specs").mkdir()
        shutil.copy(ROOT / "specs/Counter.tla", root / "specs/Counter.tla")
        source = root / "specs/Counter.tla"
        source.write_text(source.read_text().replace("EXTENDS Integers", "EXTENDS Integers, Support"))
        (root / "specs/Support.tla").write_text("---- MODULE Support ----\nMarker == TRUE\n====\n")
        fixture = ROOT / "test/fixtures/model-interface/counter"
        for src, dst in [("Counter.mirror-interface.json", "contract.json"),
                         ("counter.itf.json", "trace.json")]:
            shutil.copy(fixture / src, root / dst)
        inputs = ["--spec", "specs/Counter.tla", "--contract", "contract.json",
                  "--evidence", "trace.json", "--param-var", "parameters", "--lock", "lock.json"]
        run([str(COMPILER), "resolve", *inputs], root)
        generated = root / "generated bindings"
        generation = [str(COMPILER), "generate-cmake", *inputs,
                      "--target", "mirrorcpp-v2", "--out", generated.name]
        run(generation, root)
        run([str(COMPILER), "check-cmake", *inputs, "--target", "mirrorcpp-v2",
             "--out", generated.name], root)
        verify = ["cmake", f"-DMIRRORS_INPUT_ROOT={root}",
                  f"-DMIRRORS_GENERATED_ROOT={generated}", "-P", str(generated / "MirrorVerify.cmake")]
        run(verify, root)
        before = snapshot(generated)
        run(generation, root)
        assert snapshot(generated) == before, "nondeterministic CMake generation"
        (generated / "unrelated.txt").write_text("keep me\n")
        run(generation, root)
        assert (generated / "unrelated.txt").read_text() == "keep me\n"

        # No compiler is supplied for this replay-only consumer.
        project = root / "consumer"
        project.mkdir()
        (project / "CMakeLists.txt").write_text(
            'cmake_minimum_required(VERSION 3.24)\nproject(offline LANGUAGES CXX)\n'
            f'include("{generated}/MirrorInterface.cmake")\n'
            f'mirrors_add_model_interface(binding "{root}")\n'
            'add_custom_target(replay ALL COMMAND "${CMAKE_COMMAND}" -E echo replay)\n'
            'add_dependencies(replay binding_verify)\n')
        build = root / "build"
        run(["cmake", "-S", str(project), "-B", str(build)], root)
        run(["cmake", "--build", str(build)], root)
        manifest_path = generated / "MirrorInterface.inputs.json"
        original_manifest = manifest_path.read_bytes()
        manifest = json.loads(original_manifest)
        assert "specs/Support.tla" in {entry["path"] for entry in manifest["inputs"]}, "missing captured dependency"
        for section in ("inputs", "outputs"):
            for entry in manifest[section]:
                base = root if section == "inputs" else generated
                path = base / entry["path"]
                original = path.read_bytes()
                path.write_bytes(original + b"\n")
                run(verify, root, ok=False)
                run(["cmake", "--build", str(build)], root, ok=False)
                path.write_bytes(original)

        for path in ("../lock.json", "specs/../lock.json", "specs//Counter.tla",
                     "./lock.json", "lock.json/", "lock.json.", "lock.json ",
                     "C:/lock.json", "specs\\Counter.tla", "lock;json"):
            changed = json.loads(original_manifest)
            changed["inputs"][0]["path"] = path
            manifest_path.write_text(json.dumps(changed))
            run(verify, root, ok=False, signal="Unsafe Mirrors artifact path")
        for section in ("inputs", "outputs"):
            changed = json.loads(original_manifest)
            changed[section].append(changed[section][0])
            manifest_path.write_text(json.dumps(changed))
            run(verify, root, ok=False, signal="Duplicate Mirrors artifact path")
        changed = json.loads(original_manifest)
        changed["outputs"] = [entry for entry in changed["outputs"]
                              if entry["path"] != "CounterMirror.generated.hpp"]
        manifest_path.write_text(json.dumps(changed))
        run(verify, root, ok=False, signal="Mirrors manifest omits owned artifacts")
        changed = json.loads(original_manifest)
        changed["lockPath"] = "../lock.json"
        manifest_path.write_text(json.dumps(changed))
        run(verify, root, ok=False, signal="Unsafe Mirrors artifact path")
        manifest_path.write_bytes(original_manifest)

        # Check rejects changed owned bytes; explicit generation repairs them.
        header = generated / "CounterMirror.generated.hpp"
        original_header = header.read_bytes()
        header.write_text(header.read_text() + "// consumer modification\n")
        run([str(COMPILER), "check-cmake", *inputs, "--target", "mirrorcpp-v2",
             "--out", generated.name], root, ok=False)
        run(generation, root)
        assert header.read_bytes() == original_header

        # Unsafe replacement must preserve every old byte, including unrelated files.
        outside = root / "outside.hpp"
        outside.write_text("do not replace\n")
        header.unlink()
        header.symlink_to(outside)
        before = snapshot(generated)
        run(generation, root, ok=False)
        assert snapshot(generated) == before, "failed generation modified existing outputs"
        assert outside.read_text() == "do not replace\n" and header.is_symlink()
        header.unlink()
        header.write_bytes(original_header)

        (project / "CMakeLists.txt").write_text(
            'cmake_minimum_required(VERSION 3.24)\nproject(regeneration LANGUAGES CXX)\n'
            f'include("{generated}/MirrorInterface.cmake")\n'
            f'mirrors_add_model_interface(binding "{root}" COMPILER "{COMPILER}")\n')
        run(["cmake", "-S", str(project), "-B", str(build)], root)
        run(["cmake", "--build", str(build), "--target", "binding_regenerate"], root)
        contract = root / "contract.json"
        original = contract.read_bytes()
        contract.write_text("{}")
        before = snapshot(generated)
        run(["cmake", "--build", str(build), "--target", "binding_regenerate"], root, ok=False)
        assert snapshot(generated) == before
        contract.write_bytes(original)
        run(verify, root)
    print("CMAKE CONSUMER GREEN: offline/configure/build freshness, paths, regeneration, preservation")


if __name__ == "__main__":
    main()
