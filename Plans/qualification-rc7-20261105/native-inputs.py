#!/usr/bin/env python3
"""Admit retained pinned client binaries and prepare a fresh C++ native SDK."""
import json
import shutil
from pathlib import Path

from common import OUT, PLAN, ROOT, environment, identity, run, write


def main():
    registry = json.loads((ROOT / 'tools/evidence/commands.json').read_text())
    command = next(v for v in registry['commands'] if v['commandId'] == 'mirrors.interop')
    old = json.loads((ROOT / '.golden-build/completion-20261029/matrix-context-2.json').read_text())
    rows = []
    for label, repo_key, ref_key, binary_key in [
        ('cpp', 'CPP_REPO', 'CPP_REF', 'CPP_BIN'), ('rust', 'RUST_REPO', 'RUST_REF', 'RUST_BIN'),
        ('lean', 'LEAN_CLIENT_REPO', 'LEAN_CLIENT_REF', 'LEAN_CLIENT_BIN'), ('haskell', 'HS_REPO', 'HS_REF', 'HS_BIN')]:
        repo = Path(old[repo_key]); binary = Path(old[binary_key])
        expected = command['requiredEnvironment'][ref_key]
        assert run(label + '-input-revision', ['git', '-C', repo, 'rev-parse', 'HEAD']) == expected
        status = run(label + '-input-status', ['git', '--no-optional-locks', '-C', repo, 'status', '--porcelain=v1'])
        assert status == '', label + ' repository is dirty'
        observed = identity(binary)
        assert observed['sha256'] == command['requiredEnvironmentFileSha256'][binary_key]
        run(label + '-input-linkage', ['/usr/bin/ldd', binary])
        rows.append({'client': label, 'repository': str(repo), 'revision': expected,
                     'binary': observed, 'requiredHashMatched': True})
    inputs = OUT / 'inputs'
    inputs.mkdir(mode=0o700)
    source = inputs / 'MirrorCPP'
    run('cpp-source-clone', ['git', 'clone', '--no-hardlinks', old['CPP_REPO'], source])
    run('cpp-source-checkout', ['git', '-C', source, 'checkout', '--detach', command['requiredEnvironment']['CPP_REF']])
    build, prefix = OUT / 'cpp-build', OUT / 'cpp-prefix'
    env = environment()
    json_prefix = ROOT / '.golden-build/version-0.1/json-package'
    run('cpp-configure', ['cmake', '-S', source, '-B', build, '-DMIRRORCPP_WITH_TLS=ON',
        '-DMIRRORCPP_BUILD_TESTS=OFF', '-DMIRRORCPP_BUILD_EXAMPLES=OFF',
        '-DMIRRORCPP_BUILD_CLI=OFF', '-DCMAKE_BUILD_TYPE=Release',
        '-DCMAKE_PREFIX_PATH=' + str(json_prefix), '-DCMAKE_INSTALL_PREFIX=' + str(prefix)], env=env)
    run('cpp-build', ['cmake', '--build', build, '--target', 'mirrorcpp', '-j', '2'], env=env)
    run('cpp-install', ['cmake', '--install', build], env=env)
    write(PLAN / 'native-inputs.json', {'clients': rows, 'cppPrefix': str(prefix),
        'cppSourceRevision': command['requiredEnvironment']['CPP_REF'],
        'cppArchive': identity(prefix / 'lib/libmirrorcpp.a'), 'nativeQualificationGranted': False})
    run('cpp-native-integer-maps', ['python3', ROOT / 'tools/check-cpp-integer-maps.py', '--prefix', prefix], env=env)
    run('cpp-controlled-model-preparation', ['/usr/bin/python3', '-I', '-S', '-B',
        ROOT / 'tools/check-controlled-model.py', '--prefix', prefix,
        '--out', OUT / 'controlled-native'], env=env, timeout=1800)
    write(PLAN / 'native-checks.json', {'status': 'passed-current-rc7-native-checks',
        'integerMapsPassed': True, 'controlledPreparationPassed': True,
        'modelComparisonClaimed': False, 'freshRemoteModelQualificationGranted': False})


if __name__ == '__main__':
    main()
