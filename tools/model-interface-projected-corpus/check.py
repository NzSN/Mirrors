#!/usr/bin/env python3
"""Public reviewed projection corpus: fresh CLI artifacts and local/Gate replay.

Requires sibling SDK checkouts, installed TypeScript dependencies, Node 24,
OpenSSL/Python/Gate prerequisites and Bubblewrap permissions. No model checker
is started. Packages are packed locally, relocated, and executed with the three
source checkouts hidden. This is integration evidence, not release qualification.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "test/fixtures/model-interface/projected-cells"
TOOLS = Path(__file__).resolve().parent
SOURCE_HIDING_PROBE = """import os,sys
from pathlib import Path
if len(sys.argv) < 5:
    raise SystemExit('source hiding probe arguments are incomplete')
for source in sys.argv[1:4]:
    try:
        occupied = next(iter(Path(source).iterdir()), None) is not None
    except OSError:
        raise SystemExit('source hiding directory is missing or unreadable')
    if occupied:
        raise SystemExit('source hiding directory is not empty')
os.execv(sys.argv[4],sys.argv[4:])
"""


def sha(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def tree(root: Path) -> list[dict]:
    entries = []
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError("prepared artifacts cannot contain symlinks")
        if path.is_file():
            entries.append({"path": path.relative_to(root).as_posix(), "sha256": sha(path)})
    return entries


def run(command: list[str], cwd: Path, log: Path, env: dict) -> str:
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=600)
    log.write_text(result.stdout + result.stderr)
    log.chmod(0o600)
    if result.returncode:
        raise RuntimeError(f"command exited {result.returncode}; see {log}")
    return result.stdout.strip()


def execute(args: argparse.Namespace) -> None:
    output = args.out.absolute()
    output.mkdir(mode=0o700, exist_ok=False)
    logs = output / "logs"
    logs.mkdir(mode=0o700)
    ecma, gate = args.ecma_repo.resolve(), args.gate_repo.resolve()
    integration = gate / "integrations/mirrorecma"
    node = Path(shutil.which("node") or "").resolve()
    bwrap = shutil.which("bwrap")
    if not node.is_file() or not bwrap:
        raise ValueError("Node and Bubblewrap are required")
    env = dict(os.environ, npm_config_offline="true", npm_config_cache=str(output / "npm-cache"))
    for name in ("NODE_OPTIONS", "NODE_PATH", "APALACHE_MC", "APALACHE_JAR", "TLA2TOOLS_JAR"):
        env.pop(name, None)
    compiler = output / "model_interface_gen"
    shutil.copy2(args.compiler.resolve(), compiler)
    compiler.chmod(0o700)
    inputs = {path.relative_to(ROOT).as_posix(): sha(path) for path in FIXTURE.iterdir() if path.is_file()}
    harness_inputs = {path.relative_to(ROOT).as_posix(): sha(path) for path in TOOLS.iterdir() if path.is_file()}
    original = output / "prepared-install"
    app = original / "application"
    app.mkdir(parents=True, mode=0o700)
    (app / "package.json").write_text('{"type":"module","private":true}\n')
    base = ["--spec", str(FIXTURE.relative_to(ROOT) / "ProjectedCells.tla"),
            "--evidence", str(FIXTURE.relative_to(ROOT) / "trace-a.itf.json"),
            "--evidence", str(FIXTURE.relative_to(ROOT) / "trace-b.itf.json"),
            "--projection", str(FIXTURE.relative_to(ROOT) / "projection.json")]
    workflow = base + ["--param-var", "parameters"]
    proposal, sealed, corpus, lock, generated = (app / name for name in
        ("proposal.json", "sealed", "corpus", "ProjectedCells.lock.json", "generated"))
    calls = [
        ("scaffold", ["scaffold", "--reviewable", *workflow, "--proposal", str(proposal)]),
        ("project-corpus", ["project-corpus", *base, "--out", str(corpus)]),
        ("seal", ["seal-scaffold", *workflow, "--proposal", str(proposal), "--review", str(FIXTURE / "review.json"), "--out", str(sealed)]),
        ("resolve", ["resolve-sealed", *workflow, "--sealed", str(sealed), "--corpus-manifest", str(corpus / "manifest.json"), "--lock", str(lock)]),
        ("bundle", ["bundle", "--lock", str(lock), "--target", "mirrorecma-async-v1", "--out", str(generated)]),
        ("check-sealed-bundle", ["check-sealed-bundle", *workflow, "--sealed", str(sealed), "--corpus-manifest", str(corpus / "manifest.json"),
                                  "--lock", str(lock), "--target", "mirrorecma-async-v1", "--out", str(generated)]),
        ("check-corpus", ["check-corpus", "--out", str(corpus), "--manifest-sha256", "PUBLISHED_MANIFEST_HASH"]),
    ]
    for name, flags in calls:
        flags = [sha(corpus / "manifest.json") if flag == "PUBLISHED_MANIFEST_HASH" else flag for flag in flags]
        run([str(compiler), *flags], ROOT, logs / f"{name}.log", env)
    manifest = json.loads((corpus / "manifest.json").read_text())
    for index, member in enumerate(manifest["members"]):
        run([str(compiler), "preflight", "--lock", str(lock), "--trace", str(corpus / member["trace"]["path"]), "--require-all-actions"],
            ROOT, logs / f"member-{index}-preflight.log", env)
    source = app / "source" / FIXTURE.relative_to(ROOT)
    source.mkdir(parents=True)
    shutil.copy2(FIXTURE / "ProjectedCells.tla", source / "ProjectedCells.tla")
    # Real compiled package consumers: source preparation may build dist, but
    # execution below uses only packed package payloads and copied native tools.
    for name, directory in (("ecma", ecma), ("integration", integration)):
        run([str(node), str(directory / "node_modules/typescript/bin/tsc"), "-p", str(directory / "tsconfig.json")], directory,
            logs / f"{name}-build.log", env)
    for name, directory in (("mirrorecma", ecma), ("mirrorgate", gate), ("mirrorgate-mirrorecma", integration)):
        archive = run(["npm", "pack", "--ignore-scripts", "--offline", "--silent", "--pack-destination", str(output)], directory,
                      logs / f"{name}-pack.log", env).splitlines()[-1]
        target = app / "node_modules" / name
        target.mkdir(parents=True)
        run(["tar", "-xzf", str(output / archive), "--strip-components=1", "-C", str(target)], app, logs / f"{name}-unpack.log", env)
    run([str(node), str(ecma / "node_modules/typescript/bin/tsc"), str(generated / "ProjectedCells.suite.ts"),
         "--target", "ES2022", "--module", "NodeNext", "--moduleResolution", "NodeNext", "--strict", "--skipLibCheck",
         "--types", "node", "--typeRoots", str(ecma / "node_modules/@types")], app, logs / "generated-build.log", env)
    run([str(node), "--input-type=module", "-e", "import {generateAdapterKit} from 'mirrorgate/adapter-kit'; import {ProjectedCellsModel} from './generated/ProjectedCells.suite.js'; await generateAdapterKit(ProjectedCellsModel.publicManifest,{directory:'./public-kit'});"],
        app, logs / "public-kit.log", env)
    shutil.copy2(TOOLS / "adapter.mjs", app / "adapter.mjs")
    shutil.copy2(TOOLS / "run-suite.mjs", app / "run.mjs")
    for variant in ("correct", "faulty", "dispose-failure"):
        submission = app / "submissions" / variant
        submission.mkdir(parents=True)
        shutil.copy2(TOOLS / "adapter.mjs", submission / "implementation.mjs")
        options = {"faulty": variant == "faulty", "disposeFailure": variant == "dispose-failure"}
        (submission / "adapter.mjs").write_text("import {createAdapter as create} from './implementation.mjs';\nexport function createAdapter(){return create(" + json.dumps(options) + ");}\n")
    operator = original / "operator"
    operator.mkdir()
    for name in ("bin", "supervisor", "runtimes/node", "sdk/node", "protocol"):
        shutil.copytree(gate / name, operator / name, ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copy2(args.mirror.resolve(), operator / "bin/mirror")
    installed = output / "relocated-install"
    original.rename(installed)
    app, operator = installed / "application", installed / "operator"
    node_root = Path(env.get("MIRRORGATE_NODE_RUNTIME_ROOT", str(node.parent.parent))).resolve()
    policy_script = """import json,sys
from pathlib import Path
sys.path.insert(0,sys.argv[1]+'/supervisor')
from mirrorgate.control_policy import example_policy_document
p=example_policy_document(submission_root=sys.argv[2]+'/submissions',node_shim_root=sys.argv[1],node_runtime_root=sys.argv[3],policy_id='suite.projected-cells',adapter_id='suite.projected-cells',target_profile='mirrorecma-async-v1',state_computer_contract_version='mirrors.async-state-computer/v1')
p['schema']='mirrorgate.control-policy/v2'
p['agentProfiles']=[]
p['policies'][0]['agentProfileIds']=[]
p['policies'][0]['buildPlans']=[dict(id='node',profile='node-esm/v1',entryPoint='adapter.mjs',sourceFiles=['adapter.mjs','implementation.mjs'],runtimeSha256=sys.argv[4],dependencies=[])]
Path(sys.argv[2]+'/operator.json').write_text(json.dumps(p))
"""
    run(["python3", "-c", policy_script, str(operator), str(app), str(node_root), sha(node_root / "bin/node")], app,
        logs / "operator-policy.log", env)
    baseline = tree(app / "corpus")
    package_baseline = tree(app / "node_modules")
    executable_hashes = {"node": sha(node), "mirror": sha(operator / "bin/mirror"), "gate": sha(operator / "bin/mirrorgate")}
    # Probe actual empty mounts before executing the relocated runner. The
    # nested Gate worker uses the real operator sandbox and collection bridge.
    hidden = [str(ROOT), str(ecma), str(gate)]
    command = [bwrap, "--die-with-parent", "--unshare-net", "--ro-bind", "/", "/", "--bind", "/tmp", "/tmp",
               "--dev-bind", "/dev", "/dev", "--proc", "/proc"]
    for path in hidden:
        command += ["--tmpfs", path]
    command += ["--chdir", str(app), sys.executable, "-c", SOURCE_HIDING_PROBE, *hidden,
                str(node), str(app / "run.mjs"), "--application", str(app), "--mirror", str(operator / "bin/mirror"),
                "--mirrorgate", str(operator / "bin/mirrorgate")]
    stdout = run(command, app, logs / "runtime.log", env)
    lines = stdout.splitlines()
    result = json.loads(lines[-1])
    if result.get("schema") != "mirrors.projected-corpus-runtime/v1" or result.get("passed") is not True:
        raise ValueError("runtime produced no complete acceptance result")
    if tree(app / "corpus") != baseline or tree(app / "node_modules") != package_baseline:
        raise ValueError("admitted corpus/packages changed during execution")
    if executable_hashes != {"node": sha(node), "mirror": sha(operator / "bin/mirror"), "gate": sha(operator / "bin/mirrorgate")}:
        raise ValueError("runtime executable changed during execution")
    if any(sha(ROOT / path) != value for path, value in inputs.items()) or any(sha(ROOT / path) != value for path, value in harness_inputs.items()):
        raise ValueError("fixture/harness input changed during acceptance")
    receipt = {"schema": "mirrors.projected-corpus-acceptance/v1", "scope": "public synthetic reviewed-corpus source and relocated packed-package integration; not release qualification",
               "sourceHidden": True, "networkIsolated": True, "originalInstallationAbsent": not original.exists(),
               "fixtureInputs": inputs, "harnessInputs": harness_inputs, "compilerSha256": sha(compiler), "executables": executable_hashes,
               "manifestSha256": sha(app / "corpus/manifest.json"), "lockSha256": sha(app / "ProjectedCells.lock.json"),
               "runtime": result, "corpusFiles": baseline, "packageFiles": package_baseline,
               "logs": [{"path": str(path.relative_to(output)), "sha256": sha(path)} for path in sorted(logs.iterdir())]}
    (output / "receipt.json").write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n")
    (output / "receipt.json").chmod(0o600)
    print(f"PROJECTED CORPUS PASS: {output / 'receipt.json'}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, default=ROOT / ".lake/build/bin/model_interface_gen")
    parser.add_argument("--mirror", type=Path, default=ROOT / ".lake/build/bin/mirror")
    parser.add_argument("--ecma-repo", type=Path, default=ROOT.parent / "MirrorECMA")
    parser.add_argument("--gate-repo", type=Path, default=ROOT.parent / "MirrorGate")
    try:
        execute(parser.parse_args())
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"PROJECTED CORPUS FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
