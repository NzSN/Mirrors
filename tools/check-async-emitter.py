#!/usr/bin/env python3
"""Check target identity, deterministic generation, and cross-target ownership."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def snapshot(root: Path) -> dict[str, str]:
    return {
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=root / ".lake/build/bin/model_interface_gen")
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    fixture = root / "test/fixtures/model-interface/counter"
    lock = fixture / "Counter.mirror-interface.lock.json"
    inputs = [
        "--spec", str(root / "specs/Counter.tla"),
        "--contract", str(fixture / "Counter.mirror-interface.json"),
        "--evidence", str(fixture / "counter.itf.json"),
        "--param-var", "parameters", "--lock", str(lock),
    ]

    def run(arguments: list[str], expected: int = 0) -> subprocess.CompletedProcess[str]:
        result = subprocess.run([str(compiler), *arguments], text=True, capture_output=True, cwd=root)
        if result.returncode != expected:
            raise AssertionError(f"{arguments}: exit {result.returncode}, expected {expected}\n{result.stdout}{result.stderr}")
        return result

    original = snapshot(fixture)
    run(["check", *inputs, "--target", "mirrorecma-v1", "--out", str(fixture / "generated")])
    with tempfile.TemporaryDirectory(prefix="mirrors-async-emitter-") as directory:
        scratch = Path(directory)
        async_out = scratch / "async"
        sync_out = scratch / "sync"
        for target, output in [("mirrorecma-v1", sync_out), ("mirrorecma-async-v1", async_out)]:
            command = ["generate", "--lock", str(lock), "--target", target, "--out", str(output)]
            run(command)
            run(["check", *inputs, "--target", target, "--out", str(output)])
            manifest = json.loads((output / ".model-interface-generated.json").read_text())
            assert manifest["targetProfile"] == target
            assert manifest["semanticDigest"] == json.loads(lock.read_text())["semanticDigest"]
            before = snapshot(output)
            run(command)
            assert snapshot(output) == before, "repeated emission changed bytes"

        assert snapshot(sync_out) == snapshot(fixture / "generated"), "sync golden drift"
        source = (async_out / "CounterMirror.generated.ts").read_text()
        assert "readonly computer: AsyncStateComputer" in source
        assert "await awaitPortOperation(port.initialize(context), context)" in source
        assert "await awaitPortOperation(port.tick(input, context), context)" in source
        assert "await awaitPortOperation(port.observe(context), context)" in source
        assert "context.signal.aborted" in source
        assert "performance.now() >= context.deadline" in source
        assert snapshot(async_out) == snapshot(fixture / "generated-async"), "async golden drift"

        for target, output in [("mirrorecma-v1", async_out), ("mirrorecma-async-v1", sync_out)]:
            before = snapshot(output)
            rejected = run(["generate", "--lock", str(lock), "--target", target, "--out", str(output)], 1)
            assert "different target profile" in rejected.stderr
            assert snapshot(output) == before, "cross-target rejection modified output"
            run(["check", *inputs, "--target", target, "--out", str(output)], 1)
            assert snapshot(output) == before, "cross-target check modified output"

        run(["generate", "--lock", str(lock), "--target", "unsupported", "--out", str(scratch / "bad")], 2)
        assert not (scratch / "bad").exists()

    assert snapshot(fixture) == original, "compiler regression changed shared fixtures"
    print("Async emitter: deterministic targets, shared semantic identity, stable sync golden, and ownership rejection passed.")


if __name__ == "__main__":
    main()
