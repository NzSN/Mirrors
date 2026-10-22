#!/usr/bin/env python3
"""Actual SDK supplied-trace compatibility; no local model checker is used."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path: Path) -> str:
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def source_snapshot(repo: Path) -> dict:
    names = subprocess.check_output(['git', '-C', str(repo), 'ls-files', '--cached', '--others', '--exclude-standard', '-z']).decode().split('\0')
    # The compatibility manifest references this receipt and is added after
    # validation. Documentation-only release policy changes are not runtime
    # build inputs. All tracked implementation, fixtures and package/build
    # metadata are bound to their actual working-tree bytes.
    excluded = {'README.md', 'docs/versioning.md', 'mirrors-compatibility.json'}
    files = [{'path': name, 'sha256': sha(repo / name)} for name in sorted(names) if name and name not in excluded]
    return {'parentRevision': subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
            'sourceTreeSha256': hashlib.sha256(json.dumps(files, sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
            'files': files, 'excludedDocumentation': sorted(excluded)}


def run(argv, cwd: Path, env: dict, log: Path, timeout=600):
    with log.open('w') as output:
        result = subprocess.run(list(map(str, argv)), cwd=cwd, env=env, stdout=output,
                                stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'command exited {result.returncode}; inspect {log}')


def build(work: Path, node: Path, env: dict, cpp_prefix: Path):
    consumers = work / 'consumers'
    consumers.mkdir(exist_ok=True)
    rust = consumers / 'rust'
    rust.mkdir(exist_ok=True)
    (rust / 'Cargo.toml').write_text(
        '[package]\nname="mirrors-v01-client-compatibility"\nversion="0.0.0"\nedition="2021"\n'
        f'[dependencies]\nmirrorrust={{path={json.dumps(str(work / "MirrorRust"))}}}\n'
        f'[[bin]]\nname="runner"\npath={json.dumps(str(HERE / "rust.rs"))}\n')
    shutil.copyfile(work / 'MirrorRust/Cargo.lock', rust / 'Cargo.lock')
    run(['cargo', 'build', '--offline', '--manifest-path', rust / 'Cargo.toml'], ROOT, env,
        work / 'logs/rust-consumer-build.log')
    cpp = consumers / 'cpp'
    cpp.mkdir(exist_ok=True)
    (cpp / 'CMakeLists.txt').write_text(
        'cmake_minimum_required(VERSION 3.24)\nproject(mirrors_v01_consumer LANGUAGES CXX)\n'
        'find_package(mirrorcpp CONFIG REQUIRED)\n'
        f'add_executable(runner "{HERE / "cpp.cpp"}")\n'
        'target_compile_features(runner PRIVATE cxx_std_23)\n'
        'target_link_libraries(runner PRIVATE mirrorcpp::mirrorcpp)\n')
    run(['cmake', '-S', cpp, '-B', cpp / 'build', f'-DCMAKE_PREFIX_PATH={cpp_prefix}',
         f'-DBOOST_ROOT={cpp_prefix}'], ROOT, env,
        work / 'logs/cpp-consumer-configure.log')
    run(['cmake', '--build', cpp / 'build', '-j2'], ROOT, env, work / 'logs/cpp-consumer-build.log')
    lean = consumers / 'lean'
    lean.mkdir(exist_ok=True)
    shutil.copyfile(HERE / 'Lean.lean', lean / 'Main.lean')
    shutil.copyfile(work / 'MirrorLean/lean-toolchain', lean / 'lean-toolchain')
    native = lean / 'native'
    native.mkdir(exist_ok=True)
    for filename in ('mirrorlean_tls.c', 'mirrorlean_tls.h'):
        shutil.copyfile(work / 'MirrorLean/server-mode/native' / filename, native / filename)
    lakefile = (ROOT / 'tools/interop/generated-lean/lakefile.lean').read_text()
    lakefile = lakefile.replace('require mirrorlean from "./sdk"',
                               f'require mirrorlean from {json.dumps(str(work / "MirrorLean"))}')
    lakefile = lakefile.replace('lean_lib CounterMirror\n', '')
    # Match the SDK's explicit GNU17 native profile. GCC 15 defaults to C23,
    # whose glibc strtol symbol is absent from Lean's bundled link sysroot.
    lakefile = lakefile.replace('"-fPIC"', '"-fPIC", "-std=gnu17"')
    (lean / 'lakefile.lean').write_text(lakefile)
    # This disposable validation project must compile its captured native input
    # afresh, including when a previous failed attempt used different C flags.
    (lean / '.lake/build/native/mirrorlean_tls.o').unlink(missing_ok=True)
    run(['lake', 'build', 'runner'], lean, {**env, 'LEAN_NUM_THREADS': '2'},
        work / 'logs/lean-consumer-build.log')
    return {
        'MirrorECMA': [str(node), str(HERE / 'ecma.mjs')],
        'MirrorRust': [str(rust / 'target/debug/runner')],
        'MirrorCPP': [str(cpp / 'build/runner')],
        'MirrorLean': [str(lean / '.lake/build/bin/runner')],
    }


def free_port() -> int:
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        return listener.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--node', type=Path, required=True)
    parser.add_argument('--cpp-prefix', type=Path, required=True)
    args = parser.parse_args()
    work, node = args.work.resolve(), args.node.resolve()
    env = dict(os.environ)
    for name in ('APALACHE_JAR', 'TLA2TOOLS_JAR', 'NODE_OPTIONS', 'NODE_PATH'):
        env.pop(name, None)
    sentinel = work / 'forbidden-apalache'
    marker = work / 'unexpected-model-invocation'
    sentinel.write_text('#!/usr/bin/env python3\nfrom pathlib import Path\n'
                        f'Path({str(marker)!r}).write_text("unexpected model work")\nraise SystemExit(97)\n')
    sentinel.chmod(0o755)
    if marker.exists():
        raise RuntimeError('a previous unexpected model invocation must be investigated')
    mirror = work / 'Mirrors-baseline/.lake/build/bin/mirror'
    env.update(APALACHE_MC=str(sentinel), RUSTUP_TOOLCHAIN='1.96.0',
               COMPAT_MIRROR=str(mirror), COMPAT_ECMA_INDEX=str(work / 'MirrorECMA/dist/index.js'),
               COMPAT_TRACE=str(work / 'Mirrors-baseline/test/fixtures/model-interface/counter/counter.itf.json'))
    commands = build(work, node, env, args.cpp_prefix.resolve())
    source_identities = {name: source_snapshot(work / name) for name in commands}
    server_identity = sha(mirror)
    # Reuse the actual-CLI gate's reviewed ephemeral PKI generation, not any
    # operator credentials or retained deployment certificate.
    spec = importlib.util.spec_from_file_location('framing_pki', ROOT / 'tools/check-client-framing.py')
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    pki = work / 'compatibility-pki'
    pki.mkdir(exist_ok=True)
    _, pin = module.make_pki(pki)
    env.update(COMPAT_CA=str(pki / 'ca.crt'), COMPAT_CERT=str(pki / 'client.crt'),
               COMPAT_KEY=str(pki / 'client.key'), COMPAT_PIN=pin)
    receipts = []
    for mode in ('stdio', 'tcp', 'tls'):
        process = None
        output = None
        if mode != 'stdio':
            port = free_port()
            env['COMPAT_PORT'] = str(port)
            argv = [str(mirror), '--serve' if mode == 'tcp' else '--server', str(port), '--bind', '127.0.0.1']
            if mode == 'tls':
                argv += ['--tls', '--cert', str(pki / 'server.crt'), '--key', str(pki / 'server.key'),
                         '--ca', str(pki / 'ca.crt')]
            output = (work / f'logs/baseline-{mode}-server.log').open('w')
            process = subprocess.Popen(argv, env=env, cwd=work, stdout=output, stderr=subprocess.STDOUT)
            for _ in range(200):
                if process.poll() is not None:
                    raise RuntimeError(f'baseline {mode} server exited during startup')
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=.1):
                        break
                except OSError:
                    time.sleep(.025)
            else:
                process.terminate()
                raise RuntimeError('server startup timed out')
        try:
            cases = ('match', 'mismatch', 'wrong-pin') if mode == 'tls' else ('match', 'mismatch')
            for name, command in commands.items():
                for case in cases:
                    log = work / f'logs/{name}-{mode}-{case}.log'
                    result = subprocess.run(command, env={**env, 'COMPAT_TRANSPORT': mode, 'COMPAT_CASE': case},
                                            cwd=work, capture_output=True, text=True, timeout=45)
                    log.write_text(result.stdout + result.stderr)
                    if result.returncode:
                        raise RuntimeError(f'{name} {mode} {case} exited {result.returncode}; inspect {log}')
                    row = json.loads(result.stdout)
                    expected = {'match': ('match', 3), 'mismatch': ('step_mismatch', 2), 'wrong-pin': ('pin_mismatch', 0)}[case]
                    if (row['outcome'], row['calls']) != expected:
                        raise RuntimeError(f'unexpected actual SDK result: {row}')
                    receipts.append({'client': name, 'transport': mode, 'case': case, **row, 'logSha256': sha(log)})
                    print(name, mode, case, 'passed', flush=True)
        finally:
            if process is not None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
                output.close()
    if marker.exists():
        raise RuntimeError('supplied-trace compatibility unexpectedly invoked a model checker')
    if sha(mirror) != server_identity or any(source_snapshot(work / name) != identity for name, identity in source_identities.items()):
        raise RuntimeError('a validated server or SDK input changed during the matrix')
    receipt = {'schema': 'mirrors.v01-transport-compatibility/v1',
               'serverCommit': 'ea8091c0c723f3f561044a5c1efb91d12e7aaf5f', 'serverSha256': sha(mirror),
               'scope': 'actual SDK supplied-trace match/mismatch over stdio/TCP/mTLS and wrong-pin zero-callback rejection',
               'liveModelChecking': False, 'rows': receipts,
               'clientSources': source_identities,
               'consumerSources': [{'path': path.name, 'sha256': sha(path)} for path in sorted(HERE.iterdir()) if path.is_file()],
               'nodeVersion': subprocess.check_output([str(node), '--version'], text=True).strip(),
               'rustcVersion': subprocess.check_output(['rustc', '--version'], env=env, text=True).strip(),
               'pythonVersion': subprocess.check_output(['python3', '--version'], text=True).strip()}
    (work / 'transport-compatibility.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('All 28 supplied-trace SDK transport compatibility rows passed')


if __name__ == '__main__':
    main()
