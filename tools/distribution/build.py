#!/usr/bin/env python3
"""Build one reference-distribution cache from immutable source snapshots."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tarfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MIRRORS = HERE.parents[1]
sys.path.insert(0, str(HERE))

from distribution_lib import (deterministic_tar, dynamic_libraries, extract_selected_node, extract_selected_tree,
    runtime_tree, sha256_file, write_json)
from manifest_check import (_read_bounded_regular, digest_json, profile_resolution,
    load_json, runtime_tree_requirements, validate_locks)


def run(argv: list[str], cwd: Path) -> None:
    result = subprocess.run(argv, cwd=cwd, stdin=subprocess.DEVNULL, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise ValueError(f"command failed ({result.returncode}): {argv}\n{result.stdout}\n{result.stderr}")


def tool_record(tool_id: str, path: Path, version_args: list[str]) -> dict:
    size, digest = sha256_file(path)
    result = subprocess.run([str(path), *version_args], stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30, check=False)
    output = result.stdout.strip()
    if result.returncode or not output or len(output.encode()) > 4096:
        raise ValueError(f"cannot identify build tool: {tool_id}")
    return {"toolId": tool_id, "version": output, "bytes": size, "sha256": digest}


def write_reference_project(application_root: Path, server: Path,
    compiler: Path, package_root: Path) -> None:
    project_root = application_root / "reference-project"
    project_root.mkdir()
    trace = application_root / "examples/work-queue/artifacts/witness.itf.json"
    module = application_root / "dist-validation/examples/work-queue/artifacts/bundle/WorkQueue.suite.js"
    package_manifest = package_root / "package.json"
    server_sha = sha256_file(server)[1]
    compiler_sha = sha256_file(compiler)[1]
    trace_sha = sha256_file(trace)[1]
    module_sha = sha256_file(module)[1]
    package_sha = sha256_file(package_manifest)[1]
    package = load_json(package_manifest)
    project = {
        "schema": "mirrorecma.project/v1",
        "frameworkAdmission": "required",
        "suiteId": "work-queue.reference-installed/v1",
        "model": {
            "source": "../examples/work-queue/specs/WorkQueue.tla",
            "contract": "../examples/work-queue/artifacts/WorkQueue.mirror-interface.json",
            "evidence": "../examples/work-queue/artifacts/witness.itf.json",
            "lock": "../examples/work-queue/artifacts/WorkQueue.mirror-interface.lock.json",
            "target": "mirrorecma-async-v1",
            "generatedDirectory": "../examples/work-queue/artifacts/bundle",
            "module": "../dist-validation/examples/work-queue/artifacts/bundle/WorkQueue.suite.js",
            "moduleSha256": module_sha,
            "export": "WorkQueueModel",
        },
        "implementation": {"module": "reference-correct-adapter.mjs", "export": "createAdapter"},
        "replay": {
            "kind": "corpus",
            "config": {"specPath": "../examples/work-queue/specs/WorkQueue.tla",
                "initPredicate": "Init", "nextPredicate": "WitnessNext",
                "invariant": "TraceComplete", "lengthBound": 15,
                "paramVars": "parameters"},
            "traces": [{"path": "../examples/work-queue/artifacts/witness.itf.json",
                "sha256": trace_sha}],
        },
        "acceptance": {
            "requiredActions": ["Complete", "Enqueue", "Fail", "Reset", "Retry", "Start"],
            "requiredPairs": [["Enqueue", "Enqueue"], ["Fail", "Retry"],
                ["Retry", "Complete"], ["Reset", "Enqueue"]],
        },
        "execution": {"mirror": {"kind": "local"}, "timeouts": {
            "registrationMs": 30000, "actionMs": 5000, "receiveMs": 30000,
            "cleanupMs": 5000}},
        "toolchainLock": "mirror.toolchain.json",
    }
    write_json(project_root / "mirror.project.json", project)
    write_json(project_root / "mirror.correct.project.json", project)
    faulty_project = {**project,
        "implementation": {"module": "reference-faulty-adapter.mjs", "export": "createAdapter"}}
    write_json(project_root / "mirror.faulty.project.json", faulty_project)
    write_json(project_root / "mirror.toolchain.json", {
        "schema": "mirrorecma.toolchain/v1",
        "tools": {
            "compiler": {"path": "../../bin/model_interface_gen", "sha256": compiler_sha,
                "version": "model-interface-gen/1",
                "capabilities": ["bundle-v1", "check-bundle-v1", "preflight-v1"]},
            "server": {"path": "../../bin/ModelMirrors", "sha256": server_sha,
                "version": "Mirrors 0.0.2",
                "capabilities": ["model-interface-v1", "checked-replay-v1"]}},
        "packages": {"mirrorecma": {
            "packageJson": "../../packages/mirrorecma/package.json",
            "packageJsonSha256": package_sha, "version": package["version"]}},
    })
    for name, variant in (("reference-correct-adapter.mjs", "correct"),
            ("reference-faulty-adapter.mjs", "enqueue-drops")):
        (project_root / name).write_text(
            "import { mkdtemp, rm } from 'node:fs/promises';\n"
            "import { tmpdir } from 'node:os';\n"
            "import { join } from 'node:path';\n"
            "import { createAdapter as createWorkQueueAdapter } from '../examples/work-queue/native-service.mjs';\n"
            "export async function createAdapter() {\n"
            "  const scratch = await mkdtemp(join(tmpdir(), 'work-queue-reference-'));\n"
            f"  const adapter = await createWorkQueueAdapter('{variant}', scratch);\n"
            "  return { actions: adapter.actions, observe: adapter.observe.bind(adapter), async dispose() {\n"
            "    try { await adapter.dispose?.(); } finally { await rm(scratch, { recursive: true, force: true }); }\n"
            "  } };\n"
            "}\n", encoding="utf-8")


def copy_typescript_dependencies(source: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=False)
    for name in ("typescript", "@types"):
        source_path = (source / name).resolve()
        if not source_path.exists():
            raise ValueError(f"missing TypeScript build dependency: {source_path}")
        shutil.copytree(source_path, destination / name, symlinks=False)
    undici = source / "undici-types"
    if undici.exists():
        shutil.copytree(undici.resolve(), destination / "undici-types", symlinks=False)


def copy_gate_operator_closure(source: Path, destination: Path) -> None:
    """Materialize the complete relocated Gate root needed by installed runs."""
    destination.mkdir(parents=True, exist_ok=False)
    runtime = destination / "mirrorgate-runtime"
    runtime.mkdir()
    shutil.copyfile(source / "package.json", runtime / "package.json")
    for relative in ("runtimes/node", "sdk/node"):
        shutil.copytree(source / relative, runtime / relative, symlinks=False)
    shutil.copyfile(source / "sdk/compatibility.json", runtime / "sdk/compatibility.json")
    agent_host = source / "integrations/agent-host"
    if agent_host.is_dir():
        shutil.copytree(agent_host, runtime / "integrations/agent-host", symlinks=False)
    supervisor = destination / "mirrorgate-supervisor"
    shutil.copytree(source / "supervisor/mirrorgate", supervisor / "mirrorgate",
        symlinks=False)
    shutil.copytree(source / "protocol", destination / "protocol", symlinks=False)


def verify_source_snapshots(snapshot_root: Path, contract: dict) -> None:
    index_path = snapshot_root / "snapshot-index.json"
    index = load_json(index_path)
    if set(index) != {"schemaVersion", "components"} or index["schemaVersion"] != "mirrors.source-snapshot/v1":
        raise ValueError("source snapshot index schema mismatch")
    records = {entry["componentRef"]["componentId"]: entry for entry in index["components"]}
    if set(records) != set(contract["componentRefs"]):
        raise ValueError("source snapshot component set mismatch")
    for component_id, locked_ref in contract["componentRefs"].items():
        record = records[component_id]
        if record["componentRef"] != locked_ref:
            raise ValueError(f"source snapshot componentRef mismatch: {component_id}")
        root = snapshot_root / "sources" / component_id
        if root.is_symlink() or not root.is_dir():
            raise ValueError(f"source snapshot root is not a real directory: {component_id}")
        actual = []
        paths = []
        for path in root.rglob("*"):
            paths.append(path)
            if len(paths) > 100_000:
                raise ValueError(f"source snapshot entry bound exceeded: {component_id}")
        for path in sorted(paths, key=lambda item: item.relative_to(root).as_posix().encode()):
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode) or not (stat.S_ISDIR(metadata.st_mode) or stat.S_ISREG(metadata.st_mode)):
                raise ValueError(f"unsupported snapshot entry: {path}")
            if stat.S_ISREG(metadata.st_mode):
                size, digest = sha256_file(path)
                actual.append({"path": path.relative_to(root).as_posix(), "bytes": size,
                    "sha256": digest, "executable": bool(metadata.st_mode & stat.S_IXUSR)})
        if {entry["path"]: entry for entry in actual} != {
                entry["path"]: entry for entry in record["files"]}:
            raise ValueError(f"source snapshot file identity mismatch: {component_id}")
        tree_digest = hashlib.sha256(json.dumps(record["files"], sort_keys=True,
            separators=(",", ":")).encode()).hexdigest()
        if tree_digest != record["treeIndexSha256"]:
            raise ValueError(f"source snapshot tree index mismatch: {component_id}")


def verify_running_builder(snapshot_root: Path) -> None:
    snapshot_tools = snapshot_root / "sources/mirrors/tools/distribution"
    live_tools = MIRRORS / "tools/distribution"
    for live in sorted(live_tools.glob("*.py")):
        snap = snapshot_tools / live.name
        if not snap.is_file() or live.read_bytes() != snap.read_bytes():
            raise ValueError(f"running distribution builder differs from immutable snapshot: {live.name}")


def artifact_record(artifact_id: str, path: Path, cache_root: Path, mode: str,
    source_kind: str, media_type: str, ldd_bin: Path) -> dict:
    size, digest = sha256_file(path)
    record = {"artifactId": artifact_id, "path": path.relative_to(cache_root).as_posix(),
        "kind": "archive" if path.name.endswith((".tgz", ".tar", ".tar.gz", ".tar.xz")) else "file",
        "mediaType": media_type, "bytes": size, "sha256": digest, "mode": mode,
        "source": {"kind": source_kind, "id": artifact_id}}
    if mode == "0755":
        record["dynamicLibraries"] = dynamic_libraries(path, ldd_bin)
    return record


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True, choices=["checked-replay-local", "checked-replay-gate", "fresh-trace"])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--snapshot-root", type=Path, required=True)
    parser.add_argument("--lake-bin", type=Path, required=True)
    parser.add_argument("--node-archive", type=Path, required=True)
    parser.add_argument("--batteries-bundle", type=Path, required=True)
    parser.add_argument("--git-bin", type=Path, required=True)
    parser.add_argument("--ldd-bin", type=Path, required=True)
    parser.add_argument("--typescript-node-modules", type=Path, required=True)
    parser.add_argument("--evidence-wheels", type=Path, required=True)
    parser.add_argument("--framework-catalog-bin", type=Path, required=True)
    parser.add_argument("--framework-catalog-sha256", required=True)
    parser.add_argument("--lean-build-cache", type=Path)
    parser.add_argument("--export-lean-build-cache", type=Path)
    parser.add_argument("--apalache-archive", type=Path)
    parser.add_argument("--java-archive", type=Path)
    args = parser.parse_args()
    if args.out.exists():
        print("build output must not exist", file=sys.stderr)
        return 1
    try:
        contract = validate_locks(MIRRORS / "distribution/reference-node", args.framework_catalog_bin,
            args.framework_catalog_sha256)
        verify_source_snapshots(args.snapshot_root, contract)
        verify_running_builder(args.snapshot_root)
        profile = contract["profiles"][args.profile]
        if profile["status"].startswith("blocked"):
            raise ValueError(f"profile is unavailable: {profile['status']}")
        closure, prerequisites, _ = profile_resolution(args.profile, contract["profiles"])
        args.out.mkdir(mode=0o700, parents=True)
        artifacts_root = args.out / "artifacts"
        work = args.out / ".build"
        artifacts_root.mkdir(); work.mkdir()
        sources = args.snapshot_root / "sources"
        for component_id in ("mirrors", "mirrorecma", "mirrorgate"):
            if not (sources / component_id).is_dir():
                raise ValueError(f"missing immutable source snapshot: {component_id}")

        # Exact selected Node archive and minimal admitted runtime tree.
        dependency = contract["dependencies"]["node-runtime"]
        size, digest = sha256_file(args.node_archive)
        if size != dependency["bytes"] or digest != dependency["sha256"]:
            raise ValueError("Node archive differs from dependency lock")
        node_archive_out = artifacts_root / "runtimes/node-v24.15.0-linux-x64.tar.xz"
        node_archive_out.parent.mkdir(parents=True)
        shutil.copyfile(args.node_archive, node_archive_out)
        selection = dependency["runtimeSelection"]
        node_tree = work / "node-runtime"
        extract_selected_node(node_archive_out, node_tree, selection["rootPrefix"], selection["include"])
        node_bin = node_tree / "bin/node"

        # Mirrors build from immutable snapshot with exact prepared Batteries source.
        mirrors_work = work / "mirrors"
        shutil.copytree(sources / "mirrors", mirrors_work)
        batteries_size, batteries_digest = sha256_file(args.batteries_bundle)
        batteries = contract["dependencies"]["lean-batteries-source"]
        if batteries_size != batteries["bytes"] or batteries_digest != batteries["sha256"]:
            raise ValueError("Batteries archive differs from dependency lock")
        packages = mirrors_work / ".lake/packages"
        packages.mkdir(parents=True)
        run([str(args.git_bin), "clone", str(args.batteries_bundle), str(packages / "batteries")], mirrors_work)
        run([str(args.git_bin), "remote", "set-url", "origin",
            "https://github.com/leanprover-community/batteries"], packages / "batteries")
        if subprocess.check_output([str(args.git_bin), "-C", str(packages / "batteries"),
                "rev-parse", "HEAD"], text=True).strip() != batteries["version"]:
            raise ValueError("Batteries bundle revision differs from dependency lock")
        if args.lean_build_cache:
            shutil.copytree(args.lean_build_cache, mirrors_work / ".lake/build", symlinks=False)
        run([str(args.lake_bin), "build", "mirror", "model_interface_gen", "framework_catalog"], mirrors_work)
        if args.export_lean_build_cache:
            if args.export_lean_build_cache.exists():
                raise ValueError("export Lean build cache path already exists")
            shutil.copytree(mirrors_work / ".lake/build", args.export_lean_build_cache,
                symlinks=False)

        artifact_paths: dict[str, tuple[Path, str, str, str]] = {}
        artifact_paths["node-runtime"] = (node_archive_out, "0644", "dependency-lock", "application/x-xz")
        bin_dir = artifacts_root / "bin"; bin_dir.mkdir(parents=True)
        for artifact_id, source_name, output_name in [
            ("mirror-server", "mirror", "ModelMirrors"),
            ("model-interface-gen", "model_interface_gen", "model_interface_gen"),
            ("framework-catalog-verifier", "framework_catalog", "framework_catalog")]:
            target = bin_dir / output_name
            shutil.copyfile(mirrors_work / ".lake/build/bin" / source_name, target)
            target.chmod(0o755)
            artifact_paths[artifact_id] = (target, "0755", "component-build", "application/x-executable")

        # TypeScript build dependencies are copied before use; no source checkout fallback.
        ts_modules = work / "typescript-node-modules"
        copy_typescript_dependencies(args.typescript_node_modules, ts_modules)
        typescript_identity = runtime_tree(ts_modules)
        tsc = ts_modules / "typescript/bin/tsc"
        ecma_work = work / "mirrorecma"
        shutil.copytree(sources / "mirrorecma", ecma_work)
        (ecma_work / "node_modules").symlink_to(ts_modules, target_is_directory=True)
        run([str(node_bin), str(tsc), "-p", "tsconfig.json"], ecma_work)
        package_dir = work / "mirrorecma-package"; package_dir.mkdir()
        shutil.copytree(ecma_work / "dist", package_dir / "dist")
        shutil.copyfile(ecma_work / "package.json", package_dir / "package.json")
        package_out = artifacts_root / "packages/mirrorecma.tgz"
        deterministic_tar(package_dir, package_out, "package")
        artifact_paths["mirrorecma-package"] = (package_out, "0644", "component-build", "application/gzip")
        run([str(node_bin), str(tsc), "-p", "tsconfig.examples.json"], ecma_work)
        run([str(node_bin), str(tsc), "-p", "tsconfig.application-validation.json"], ecma_work)
        application_fixture_dir = work / "application-validation-fixtures"
        application_fixture_dir.mkdir()
        shutil.copytree(ecma_work / "examples", application_fixture_dir / "examples")
        shutil.copytree(ecma_work / "dist-test", application_fixture_dir / "dist-test")
        shutil.copytree(ecma_work / "dist-validation", application_fixture_dir / "dist-validation")
        write_reference_project(application_fixture_dir, bin_dir / "ModelMirrors",
            bin_dir / "model_interface_gen", package_dir)
        application_fixture_out = artifacts_root / "examples/application-validation-fixtures.tar.gz"
        deterministic_tar(application_fixture_dir, application_fixture_out,
            "application-validation")
        artifact_paths["application-validation-fixtures"] = (application_fixture_out,
            "0644", "component-build", "application/gzip")
        application_materialized = work / "application-validation-materialized"
        shutil.copytree(application_fixture_dir, application_materialized)
        shutil.copytree(ecma_work / "dist", application_materialized / "dist")
        application_materialized_identity = runtime_tree(application_materialized)

        # Compiler-owned Counter suite and checked corpus.
        suite_modules = work / "node_modules"; suite_modules.mkdir()
        (suite_modules / "mirrorecma").symlink_to(ecma_work, target_is_directory=True)
        (suite_modules / "@types").symlink_to(ts_modules / "@types", target_is_directory=True)
        if (ts_modules / "undici-types").exists():
            (suite_modules / "undici-types").symlink_to(ts_modules / "undici-types", target_is_directory=True)
        suite_dir = work / "counter-suite"
        run([str(bin_dir / "model_interface_gen"), "bundle", "--lock",
            "test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json",
            "--target", "mirrorecma-async-v1", "--out", str(suite_dir)], mirrors_work)
        run([str(node_bin), str(tsc), str(suite_dir / "Counter.suite.ts"), "--target", "ES2022",
            "--module", "NodeNext", "--moduleResolution", "NodeNext", "--strict", "--skipLibCheck",
            "--types", "node", "--typeRoots", str(ts_modules / "@types")], mirrors_work)
        suite_out = artifacts_root / "examples/counter-suite.tar.gz"
        deterministic_tar(suite_dir, suite_out, "counter-suite")
        artifact_paths["counter-suite-bundle"] = (suite_out, "0644", "component-build", "application/gzip")
        corpus_out = artifacts_root / "examples/counter.itf.json"
        corpus_out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(mirrors_work / "test/fixtures/model-interface/counter/counter.itf.json", corpus_out)
        artifact_paths["counter-corpus"] = (corpus_out, "0644", "component-build", "application/json")
        model_out = artifacts_root / "examples/Counter.tla"
        shutil.copyfile(mirrors_work / "specs/Counter.tla", model_out)
        artifact_paths["counter-model"] = (model_out, "0644", "component-build", "text/plain")

        # Offline verification tools and pinned wheel closure.
        evidence_out = artifacts_root / "evidence/tools.tar.gz"
        verification_bundle = work / "verification-bundle"
        shutil.copytree(mirrors_work / "tools/evidence", verification_bundle / "tools/evidence")
        distribution_verifier = verification_bundle / "tools/distribution"
        distribution_verifier.mkdir(parents=True)
        for name in ("audit-launcher.mjs", "counter-driver.mjs", "distribution_lib.py",
                "install.py", "manifest_check.py", "qualification.py", "upgrade_matrix.py",
                "verify.py", "install.sh", "verify.sh", "test-installed.sh", "test-upgrade.sh"):
            shutil.copyfile(mirrors_work / "tools/distribution" / name,
                distribution_verifier / name)
            if name.endswith(".sh") or name.endswith(".py"):
                (distribution_verifier / name).chmod(0o755)
        schema_dir = verification_bundle / "distribution/reference-node"
        schema_dir.mkdir(parents=True)
        for name in ("distribution-manifest.schema.json", "cache-index.schema.json"):
            shutil.copyfile(MIRRORS / "distribution/reference-node" / name, schema_dir / name)
        deterministic_tar(verification_bundle, evidence_out, "verification")
        artifact_paths["evidence-verifier"] = (evidence_out, "0644", "component-build", "application/gzip")
        wheels_out = artifacts_root / "evidence/wheels.tar.gz"
        wheels_identity = runtime_tree(args.evidence_wheels)
        deterministic_tar(args.evidence_wheels, wheels_out, "wheels")
        artifact_paths["evidence-verifier-dependencies"] = (wheels_out, "0644", "component-build", "application/gzip")
        locks_dir = work / "distribution-locks"; locks_dir.mkdir()
        for input_id, identity in contract["buildInputs"].items():
            source = MIRRORS / identity["path"]
            raw = _read_bounded_regular(source)
            if len(raw) != identity["bytes"] or hashlib.sha256(raw).hexdigest() != identity["sha256"]:
                raise ValueError(f"lock input changed after validation: {input_id}")
            (locks_dir / source.name).write_bytes(raw)
        locks_out = artifacts_root / "inputs/distribution-locks.tar.gz"
        deterministic_tar(locks_dir, locks_out, "distribution-locks")
        artifact_paths["distribution-locks"] = (locks_out, "0644", "component-build", "application/gzip")
        catalog_raw = _read_bounded_regular(MIRRORS / "catalog/framework-catalog.json")
        catalog_value = json.loads(catalog_raw.decode("utf-8"))
        if digest_json(catalog_value) != contract["selection"]["selectionValue"]:
            raise ValueError("selected catalog changed after lock validation")
        selected_catalog = artifacts_root / "inputs/framework-catalog.A.json"
        selected_catalog.parent.mkdir(parents=True, exist_ok=True)
        selected_catalog.write_bytes(catalog_raw)
        selected_catalog.chmod(0o644)
        artifact_paths["selected-catalog"] = (selected_catalog, "0644", "component-build", "application/json")

        java_tree = None
        apalache_tree = None
        if args.profile == "fresh-trace":
            if args.apalache_archive is None or args.java_archive is None:
                raise ValueError("fresh-trace requires explicit --apalache-archive and --java-archive")
            for artifact_id, source, media_type in [
                ("apalache", args.apalache_archive, "application/gzip"),
                ("java-runtime", args.java_archive, "application/gzip")]:
                dependency = contract["dependencies"][artifact_id]
                size, digest = sha256_file(source)
                if size != dependency["bytes"] or digest != dependency["sha256"]:
                    raise ValueError(f"{artifact_id} archive differs from dependency lock")
                output = artifacts_root / f"tools/{dependency['fileName']}"
                output.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, output)
                artifact_paths[artifact_id] = (output, "0644", "dependency-lock", media_type)
            java_selection = contract["dependencies"]["java-runtime"]["runtimeSelection"]
            java_tree = work / "java-runtime"
            extract_selected_tree(args.java_archive, java_tree, java_selection["rootPrefix"],
                java_selection.get("include", []), java_selection.get("includeTrees", []))
            apalache_selection = contract["dependencies"]["apalache"]["runtimeSelection"]
            apalache_tree = work / "apalache-runtime"
            extract_selected_tree(args.apalache_archive, apalache_tree,
                apalache_selection["rootPrefix"], apalache_selection.get("include", []),
                apalache_selection.get("includeTrees", []))

        if args.profile == "checked-replay-gate":
            gate_source = sources / "mirrorgate"
            gate_operator = work / "mirrorgate-operator"
            copy_gate_operator_closure(gate_source, gate_operator)
            for artifact_id, relative, prefix in [("mirrorgate-protocol", "protocol", "protocol"),
                ("mirrorgate-supervisor", "supervisor", "supervisor")]:
                output = artifacts_root / f"gate/{artifact_id}.tar.gz"
                deterministic_tar(gate_source / relative, output, prefix)
                artifact_paths[artifact_id] = (output, "0644", "component-build", "application/gzip")
            runtime_output = artifacts_root / "gate/mirrorgate-runtime.tar.gz"
            deterministic_tar(gate_operator, runtime_output, "gate")
            artifact_paths["mirrorgate-runtime"] = (runtime_output, "0644",
                "component-build", "application/gzip")
            integration_work = work / "mirrorgate-integration"
            shutil.copytree(gate_source / "integrations/mirrorecma", integration_work)
            modules = integration_work / "node_modules"; modules.mkdir()
            (modules / "typescript").symlink_to(ts_modules / "typescript", target_is_directory=True)
            (modules / "@types").symlink_to(ts_modules / "@types", target_is_directory=True)
            if (ts_modules / "undici-types").exists():
                (modules / "undici-types").symlink_to(ts_modules / "undici-types", target_is_directory=True)
            (modules / "mirrorecma").symlink_to(ecma_work, target_is_directory=True)
            (modules / "mirrorgate").symlink_to(gate_source, target_is_directory=True)
            run([str(node_bin), str(tsc), "-p", "tsconfig.json"], integration_work)
            integration_package = work / "gate-integration-package"; integration_package.mkdir()
            for name in ("dist", "service", "examples", "scripts"):
                source = integration_work / name
                if source.exists(): shutil.copytree(source, integration_package / name)
            for name in ("package.json", "README.md", "VALIDATION.md", "WORKFLOW.md"):
                shutil.copyfile(integration_work / name, integration_package / name)
            for source in sorted(integration_work.glob("*.mjs")):
                shutil.copyfile(source, integration_package / source.name)
            output = artifacts_root / "packages/mirrorgate-mirrorecma.tgz"
            deterministic_tar(integration_package, output, "package")
            artifact_paths["mirrorgate-integration"] = (output, "0644", "component-build", "application/gzip")

        if set(artifact_paths) != closure:
            raise ValueError(f"built artifact closure mismatch: expected={sorted(closure)}, actual={sorted(artifact_paths)}")
        artifacts = []
        for artifact_id in sorted(artifact_paths):
            path, mode, source_kind, media_type = artifact_paths[artifact_id]
            artifacts.append(artifact_record(artifact_id, path, args.out, mode, source_kind,
                media_type, args.ldd_bin))
        tree_requirements = runtime_tree_requirements(args.profile, contract["profiles"])
        trees = []
        for tree_id, requirement in sorted(tree_requirements.items()):
            if tree_id == "node-runtime":
                tree_root = node_tree
            elif tree_id == "java-runtime" and java_tree is not None:
                tree_root = java_tree
            elif tree_id == "apalache-runtime" and apalache_tree is not None:
                tree_root = apalache_tree
            elif tree_id == "mirrorgate-runtime":
                tree_root = gate_operator
            else:
                raise ValueError(f"unknown runtime-tree selection: {tree_id}")
            identity = runtime_tree(tree_root)
            trees.append({"treeId": tree_id, "sourceArtifactId": requirement["sourceArtifactId"],
                "selectionId": requirement["selectionId"], "path": f"artifacts/selected-trees/{tree_id}", **identity})
        manifest = {"schemaVersion": "mirrors.reference-distribution-manifest/v1",
            "distributionId": json.loads((MIRRORS / "distribution/reference-node/profiles.json").read_text())["distributionId"],
            "catalogSelectionRef": contract["selection"], "profileId": args.profile,
            "componentRefs": [contract["componentRefs"][component_id]
                for component_id in sorted(contract["combinationComponents"][args.profile])],
            "buildInputs": list(contract["buildInputs"].values()), "artifacts": artifacts,
            "buildProvenance": {
                "snapshotIndexSha256": sha256_file(args.snapshot_root / "snapshot-index.json")[1],
                "tools": [tool_record("python", Path(sys.executable).resolve(), ["--version"]),
                    tool_record("git", args.git_bin, ["--version"]),
                    tool_record("ldd", args.ldd_bin, ["--version"]),
                    tool_record("lake", args.lake_bin, ["--version"]),
                    tool_record("framework-catalog-bootstrap", args.framework_catalog_bin, ["validate",
                        str(MIRRORS / "catalog/framework-catalog.json")])],
                "trees": [{"inputId": "typescript-node-modules", **typescript_identity},
                    {"inputId": "evidence-wheels", **wheels_identity},
                    {"inputId": "package:mirrorecma", **runtime_tree(package_dir)},
                    {"inputId": "application:validation", **application_materialized_identity}] +
                    ([{"inputId": "package:mirrorgate-mirrorecma",
                        **runtime_tree(integration_package)}]
                        if args.profile == "checked-replay-gate" else []) +
                    ([{"inputId": "lean-build-cache", **runtime_tree(args.lean_build_cache)}]
                        if args.lean_build_cache else []),
            },
            "runtimeTrees": trees, "hostRequirements": list(prerequisites.values()),
            "publication": "unclaimed"}
        write_json(args.out / "distribution-manifest.json", manifest)
        manifest_digest = digest_json(manifest)
        index = {"schemaVersion": "mirrors.reference-cache-index/v1", "profileId": args.profile,
            "catalogSelectionRef": contract["selection"], "distributionManifestSha256": manifest_digest,
            "entries": [{key: artifact[key] for key in ("artifactId", "path", "bytes", "sha256", "mode")}
                for artifact in artifacts]}
        write_json(args.out / "cache-index.json", index)
        shutil.rmtree(work)
        print(f"REFERENCE DISTRIBUTION BUILD GREEN profile={args.profile} manifestSha256={manifest_digest}")
        return 0
    except Exception as error:
        if args.out.exists():
            try:
                write_json(args.out / "build-state.json", {"state": "incomplete", "error": str(error)[:4096]})
            except Exception:
                pass
        print(f"distribution build failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
