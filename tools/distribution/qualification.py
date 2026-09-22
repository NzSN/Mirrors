#!/usr/bin/env python3
"""Relocate and exercise an installed checked-replay runtime without source/global tools."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from install import selector, verify_installation


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def descendants(pid: int) -> set[int]:
    found = {pid}; pending = [pid]
    while pending and len(found) < 4096:
        current = pending.pop()
        try: children = Path(f"/proc/{current}/task/{current}/children").read_text().split()
        except OSError: continue
        for child in children:
            value = int(child)
            if value not in found: found.add(value); pending.append(value)
    return found


def run_audited(command: list[str], timeout: float) -> tuple[int, bytes, bytes, list[dict]]:
    with tempfile.TemporaryDirectory(prefix="mirrors-exec-audit-") as temporary:
        stdout_path = Path(temporary) / "stdout"; stderr_path = Path(temporary) / "stderr"
        with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=stdout,
                stderr=stderr, start_new_session=True)
            observed = {}
            deadline = time.monotonic() + timeout
            while process.poll() is None:
                if time.monotonic() >= deadline:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=10)
                    raise TimeoutError("relocated replay timed out")
                for pid in descendants(process.pid):
                    if pid in observed: continue
                    try:
                        observed[pid] = {"pid": pid,
                            "exe": os.readlink(f"/proc/{pid}/exe"),
                            "argv": Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode("utf-8", "replace").strip()}
                    except OSError: pass
                time.sleep(0.01)
        if stdout_path.stat().st_size > 16 * 1024 * 1024 or stderr_path.stat().st_size > 4 * 1024 * 1024:
            raise ValueError("relocated replay output bound exceeded")
        return process.returncode, stdout_path.read_bytes(), stderr_path.read_bytes(), list(observed.values())


def trace_audit(prefix: Path, hidden_roots: list[str]) -> dict:
    files = sorted(prefix.parent.glob(prefix.name + ".*"))
    total = sum(path.stat().st_size for path in files)
    if not files or len(files) > 4096 or total > 16 * 1024 * 1024:
        raise ValueError("syscall trace file/count bound failed")
    content = b"".join(path.read_bytes() for path in files)
    text = content.decode("utf-8", "replace")
    forbidden_exec = ("model_interface_gen", "apalache", "java", "npm", "npx", "pnpm", "tsc", "git", "make")
    exec_lines = [line for line in text.splitlines() if "execve(" in line or "execveat(" in line]
    open_lines = [line for line in text.splitlines() if "openat(" in line or "openat2(" in line]
    if any(any(token in line for token in forbidden_exec) for line in exec_lines):
        raise ValueError("forbidden build/install/compiler executable observed")
    hidden_open_lines = [line for line in open_lines
        if any(root in line for root in hidden_roots)]
    for root in hidden_roots:
        matches = [line for line in hidden_open_lines if root in line]
        if len(matches) != 1:
            raise ValueError("hidden-root replacement probe count differs")
    return {"files": len(files), "bytes": total, "sha256": digest(content),
        "execCalls": len(exec_lines), "openCalls": len(open_lines),
        "forbiddenExecCalls": 0, "hiddenRootOpenCalls": len(hidden_open_lines),
        "hiddenRootAccess": "empty replacement mount verified by audit launcher"}


def bounded_process_record(exit_code: int, stdout: bytes, stderr: bytes,
    processes: list[dict]) -> dict:
    limit = 64 * 1024
    return {"exitCode": exit_code, "stdoutBytes": len(stdout),
        "stdoutSha256": digest(stdout), "stdoutTail": stdout[-limit:].decode("utf-8", "replace"),
        "stderrBytes": len(stderr), "stderrSha256": digest(stderr),
        "stderrTail": stderr[-limit:].decode("utf-8", "replace"),
        "processes": processes, "tailLimitBytes": limit}


def bounded_syscall_records(prefix: Path) -> list[dict]:
    files = sorted(prefix.parent.glob(prefix.name + ".*"))[:128]
    remaining = 4 * 1024 * 1024
    records = []
    for path in files:
        raw = path.read_bytes()
        retained = raw[:min(len(raw), remaining)]
        remaining -= len(retained)
        records.append({"name": path.name, "bytes": len(raw), "sha256": digest(raw),
            "retainedBytes": len(retained), "content": retained.decode("utf-8", "replace")})
        if remaining == 0:
            break
    return records


def write_audit(path: Path, value: dict) -> None:
    audit = (json.dumps(value, indent=2) + "\n").encode()
    if len(audit) > 8 * 1024 * 1024:
        raise ValueError("qualification audit output bound exceeded")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        offset = 0
        while offset < len(audit):
            offset += os.write(descriptor, audit[offset:])
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", type=Path, required=True)
    parser.add_argument("--framework-catalog-bin", type=Path, required=True)
    parser.add_argument("--framework-catalog-sha256", required=True)
    parser.add_argument("--bwrap", type=Path, required=True)
    parser.add_argument("--strace", type=Path, required=True)
    parser.add_argument("--strace-sha256", required=True)
    parser.add_argument("--audit-out", type=Path, required=True)
    parser.add_argument("--hide-root", action="append", type=Path, required=True)
    args = parser.parse_args()
    active = None
    failure_context: dict = {"stage": "admission"}
    try:
        if digest(args.strace.read_bytes()) != args.strace_sha256:
            raise ValueError("trusted strace SHA-256 mismatch")
        active = selector(args.prefix)
        if active is None:
            raise ValueError("installation has no active version")
        version = args.prefix / active["versionDirectory"]
        verify_installation(version, args.framework_catalog_bin,
            args.framework_catalog_sha256)
        observations = []
        with tempfile.TemporaryDirectory(prefix="mirrors-relocation-") as temporary:
            for iteration in range(2):
                relocated = Path(temporary) / f"relocated-{iteration}"
                shutil.copytree(version, relocated)
                verify_installation(relocated, args.framework_catalog_bin,
                    args.framework_catalog_sha256)
                runtime = relocated / "runtime"
                hidden = [str(path.resolve()) for path in args.hide_root]
                launcher = HERE / "audit-launcher.mjs"
                counter_driver = HERE / "counter-driver.mjs"
                command = [str(args.bwrap), "--die-with-parent", "--unshare-net",
                    "--ro-bind", "/", "/", "--dev-bind", "/dev", "/dev",
                    "--proc", "/proc", "--tmpfs", "/tmp", "--dir", "/tmp/home",
                    "--ro-bind", str(runtime), "/tmp/runtime",
                    "--ro-bind", str(launcher), "/tmp/audit-launcher.mjs",
                    "--ro-bind", str(counter_driver), "/tmp/counter-driver.mjs",
                    "--chdir", "/tmp/runtime/applications", "--setenv", "PATH",
                    "/tmp/runtime/runtimes/node/bin:/tmp/runtime/bin", "--setenv", "HOME", "/tmp/home",
                    "--setenv", "MIRROR_BIN", "/tmp/runtime/bin/ModelMirrors"]
                for source in args.hide_root:
                    if source.exists() and not str(source.resolve()).startswith("/tmp/"):
                        command += ["--tmpfs", str(source.resolve())]
                for hidden_global in ("/usr/local/lib/node_modules", "/usr/lib/node_modules", "/usr/share/nodejs"):
                    if Path(hidden_global).exists(): command += ["--tmpfs", hidden_global]
                for executable_root in ("/usr/local/bin", "/usr/bin"):
                    if Path(executable_root).is_dir(): command += ["--tmpfs", executable_root]
                command += ["--", "/tmp/runtime/runtimes/node/bin/node", "/tmp/audit-launcher.mjs",
                    json.dumps(hidden), "/tmp/runtime/runtimes/node/bin/node",
                    "/tmp/runtime/applications/examples/application-validation/run.mjs", "all",
                    "--prevalidated-registry", "/tmp/runtime/installed-registry.json",
                    "--receipt", "/tmp/home/application-campaign.json"]
                trace_prefix = Path(temporary) / f"syscalls-{iteration}"
                traced = [str(args.strace), "-ff", "-qq", "-o", str(trace_prefix),
                    "-e", "trace=execve,execveat,openat,openat2", *command]
                exit_code, stdout, stderr, processes = run_audited(traced, 180)
                failure_context = {"stage": "application-validation", "iteration": iteration,
                    "argv": command, "process": bounded_process_record(exit_code, stdout, stderr, processes),
                    "syscallFiles": bounded_syscall_records(trace_prefix)}
                if exit_code:
                    raise ValueError(f"relocated replay failed: {stderr.decode('utf-8','replace')[-4000:]}")
                receipt = json.loads(stdout)
                if (receipt.get("schema") != "mirrorecma.application-campaign-aggregate/v1" or
                        receipt.get("tier") != "installed-prevalidated" or
                        receipt.get("applications") != ["work-queue", "persistent-transfer", "lease-service"] or
                        receipt.get("denominator") != 17 or receipt.get("acceptance") != {"status": "met"} or
                        receipt.get("cleanup") != {"scope": "local-cooperative", "status": "confirmed", "cases": 29}):
                    raise ValueError("acceptance receipt identity is wrong")
                framework = receipt.get("framework", {})
                if (framework.get("installationSchema") != "mirrorecma.installed-framework-binding/v1" or
                        framework.get("catalogSelectionRef") is None or not framework.get("componentRefs") or
                        not isinstance(framework.get("installedRegistrySha256"), str) or
                        not isinstance(framework.get("frameworkInputSha256"), str)):
                    raise ValueError("installed framework identity is absent from application aggregate")
                campaigns = receipt.get("campaigns", [])
                expected_campaigns = [("work-queue", 9), ("persistent-transfer", 4), ("lease-service", 4)]
                if len(campaigns) != len(expected_campaigns):
                    raise ValueError("application campaign count differs")
                for campaign, (application, denominator) in zip(campaigns, expected_campaigns):
                    mutation = campaign.get("mutationCampaign", {})
                    if (campaign.get("schema") != "mirrorecma.application-validation/v2" or
                            campaign.get("application") != application or mutation.get("status") != "complete" or
                            mutation.get("denominator") != denominator or
                            mutation.get("requiredOnPath") != denominator or
                            mutation.get("acceptance", {}).get("status") != "met" or
                            any(result.get("cleanup", {}).get("status") != "confirmed"
                                for result in campaign.get("results", []))):
                        raise ValueError(f"application campaign differs: {application}")
                allowed_executables = {"strace", "bwrap", "node", "ModelMirrors"}
                if any(Path(item["exe"]).name not in allowed_executables for item in processes):
                    raise ValueError("unexpected executable observed in process audit")
                syscalls = trace_audit(trace_prefix, hidden)
                separator = command.index("--")

                def run_cli_case(label: str, cli_args: list[str], expected_exit: int,
                    sandbox_prefix: list[str] | None = None) -> tuple[dict, dict]:
                    nonlocal failure_context
                    cli_trace = Path(temporary) / f"cli-{label}-{iteration}"
                    prefix = command[:separator] if sandbox_prefix is None else sandbox_prefix
                    cli_command = prefix + ["--", "/tmp/runtime/runtimes/node/bin/node",
                        "/tmp/audit-launcher.mjs", json.dumps(hidden),
                        "/tmp/runtime/runtimes/node/bin/node",
                        "/tmp/runtime/packages/mirrorecma/dist/cli.js", *cli_args]
                    cli_traced = [str(args.strace), "-ff", "-qq", "-o", str(cli_trace),
                        "-e", "trace=execve,execveat,openat,openat2", *cli_command]
                    code, output, error_output, cli_processes = run_audited(cli_traced, 180)
                    failure_context = {"stage": f"cli-{label}", "iteration": iteration,
                        "argv": cli_command, "process": bounded_process_record(code, output,
                            error_output, cli_processes),
                        "syscallFiles": bounded_syscall_records(cli_trace)}
                    if code != expected_exit:
                        raise ValueError(f"installed CLI {label} exit differs: {code} != {expected_exit}: "
                            f"{error_output.decode('utf-8', 'replace')[-2000:]}")
                    raw = output.strip() or error_output.strip()
                    value = json.loads(raw)
                    return value, trace_audit(cli_trace, hidden)

                project = "/tmp/runtime/applications/reference-project/mirror.project.json"
                framework_input = "/tmp/runtime/framework-input.json"
                combination = "candidate.local-node-checked"
                doctor, doctor_syscalls = run_cli_case("doctor", ["doctor", "--project", project,
                    "--framework-input", framework_input, "--combination", combination], 0)
                required_checks = {"catalog.selection", "catalog.combination", "catalog.components",
                    "catalog.package.mirrorecma", "catalog.executable.mirror-server",
                    "catalog.runtime-tree.node-runtime", "catalog.platform", "configuration",
                    "executable.server", "package.mirrorecma", "catalog.filesystem-binding"}
                required_checks.remove("catalog.components")
                required_checks.update({"catalog.component.mirrorecma", "catalog.component.mirrors"})
                checks = {entry.get("check"): entry.get("status") for entry in doctor}
                if any(checks.get(name) != "passed" for name in required_checks):
                    raise ValueError("installed doctor lacks required passing identity checks")
                replay, replay_syscalls = run_cli_case("replay", ["replay", "--project", project,
                    "--framework-input", framework_input, "--combination", combination], 0)
                if (replay.get("outcome") != "passed" or replay.get("acceptance", {}).get("status") != "met" or
                        replay.get("cleanup", {}).get("status") != "succeeded" or
                        replay.get("cleanup", {}).get("quiescence") != "confirmed"):
                    raise ValueError("installed catalog-admitted project replay differs")
                missing_framework, missing_framework_syscalls = run_cli_case("missing-framework",
                    ["replay", "--project", project], 2)
                if missing_framework.get("failure", {}).get("code") != "catalog_selection_required":
                    raise ValueError("marker project did not reject missing framework selection")
                wrong_project_host = Path(temporary) / f"wrong-{iteration}.project.json"
                wrong_lock_host = Path(temporary) / f"wrong-{iteration}.toolchain.json"
                wrong_project_value = json.loads((runtime /
                    "applications/reference-project/mirror.project.json").read_text())
                wrong_project_value["toolchainLock"] = "/tmp/home/wrong.toolchain.json"
                wrong_project_host.write_text(json.dumps(wrong_project_value) + "\n")
                package_manifest = runtime / "packages/mirrorecma/package.json"
                package_value = json.loads(package_manifest.read_text())
                wrong_lock_host.write_text(json.dumps({
                    "schema": "mirrorecma.toolchain/v1",
                    "tools": {"server": {"path": "/tmp/runtime/runtimes/node/bin/node",
                        "sha256": digest((runtime / "runtimes/node/bin/node").read_bytes()),
                        "version": "v24.15.0",
                        "capabilities": ["model-interface-v1", "checked-replay-v1"]}},
                    "packages": {"mirrorecma": {
                        "packageJson": "/tmp/runtime/packages/mirrorecma/package.json",
                        "packageJsonSha256": digest(package_manifest.read_bytes()),
                        "version": package_value["version"]}},
                }) + "\n")
                wrong_sandbox = command[:separator] + ["--ro-bind", str(wrong_project_host),
                    "/tmp/home/wrong.project.json", "--ro-bind", str(wrong_lock_host),
                    "/tmp/home/wrong.toolchain.json"]
                wrong_identity, wrong_identity_syscalls = run_cli_case("wrong-server", ["replay",
                    "--project", "/tmp/home/wrong.project.json", "--framework-input", framework_input,
                    "--combination", combination], 2, wrong_sandbox)
                if (wrong_identity.get("failure", {}).get("code") != "executable_identity_mismatch" or
                        "actual installed executable differs" not in
                        wrong_identity.get("failure", {}).get("message", "")):
                    raise ValueError("individually valid wrong server did not fail catalog filesystem binding")
                counter_results = []
                for variant in ("correct", "faulty"):
                    counter_trace = Path(temporary) / f"counter-{variant}-{iteration}"
                    counter_command = command[:separator] + ["--",
                        "/tmp/runtime/runtimes/node/bin/node", "/tmp/audit-launcher.mjs", json.dumps(hidden),
                        "/tmp/runtime/runtimes/node/bin/node", "/tmp/counter-driver.mjs", variant]
                    counter_traced = [str(args.strace), "-ff", "-qq", "-o", str(counter_trace),
                        "-e", "trace=execve,execveat,openat,openat2", *counter_command]
                    counter_exit, counter_stdout, counter_stderr, _counter_processes = run_audited(counter_traced, 60)
                    failure_context = {"stage": f"counter-{variant}", "iteration": iteration,
                        "argv": counter_command,
                        "process": bounded_process_record(counter_exit, counter_stdout,
                            counter_stderr, _counter_processes),
                        "syscallFiles": bounded_syscall_records(counter_trace)}
                    if counter_exit:
                        raise ValueError(f"Counter {variant} failed: {counter_stderr.decode('utf-8','replace')[-2000:]}")
                    counter = json.loads(counter_stdout)
                    outcome = counter["result"].get("outcome")
                    cleanup = counter["result"].get("cleanup", {}).get("status")
                    if variant == "correct" and (outcome != "passed" or cleanup != "confirmed"):
                        raise ValueError("Counter correct outcome/cleanup differs")
                    if variant == "faulty":
                        failure = counter["result"].get("failure", {})
                        if (outcome != "mismatch" or cleanup != "confirmed" or
                                failure.get("traceIndex") != 0 or failure.get("stateIndex") != 1 or
                                failure.get("action") not in {"Tick", "tick"}):
                            raise ValueError("Counter faulty observed mismatch signature differs")
                    counter_results.append({"variant": variant, "outcome": outcome,
                        "cleanup": cleanup, "syscalls": trace_audit(counter_trace, hidden)})
                observations.append({"iteration": iteration, "argv": command,
                    "exitCode": exit_code, "stdoutBytes": len(stdout),
                    "stdoutSha256": digest(stdout), "stderrBytes": len(stderr),
                    "stderrSha256": digest(stderr), "processes": processes, "syscalls": syscalls,
                    "relocated": True,
                    "networkNamespace": "isolated", "hiddenRoots": hidden,
                    "filesystemOpenProbes": "denied-by-audit-launcher", "runtimeMount": "read-only",
                    "path": "/tmp/runtime/runtimes/node/bin:/tmp/runtime/bin", "counter": counter_results,
                    "catalogAdmission": {"doctor": doctor, "doctorSyscalls": doctor_syscalls,
                        "replayOutcome": replay.get("outcome"), "replaySyscalls": replay_syscalls,
                        "missingFrameworkCode": missing_framework.get("failure", {}).get("code"),
                        "missingFrameworkSyscalls": missing_framework_syscalls,
                        "wrongIdentityCode": wrong_identity.get("failure", {}).get("code"),
                        "wrongIdentitySyscalls": wrong_identity_syscalls}})
        write_audit(args.audit_out, {"schemaVersion": "mirrors.installed-consumer-audit/v1",
            "status": "passed",
            "manifestDigest": active["manifestDigest"],
            "trustedStraceSha256": args.strace_sha256, "runs": observations})
        print("REFERENCE DISTRIBUTION QUALIFICATION GREEN: relocated twice, offline namespace, correct plus mismatch")
        return 0
    except Exception as error:
        if not args.audit_out.exists():
            try:
                write_audit(args.audit_out, {"schemaVersion": "mirrors.installed-consumer-audit/v1",
                    "status": "failed", "manifestDigest": active.get("manifestDigest")
                        if isinstance(active, dict) else None,
                    "trustedStraceSha256": args.strace_sha256,
                    "error": str(error)[:4096], "failure": failure_context})
            except Exception as audit_error:
                print(f"qualification failure audit could not be retained: {audit_error}", file=sys.stderr)
        print(f"distribution qualification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
