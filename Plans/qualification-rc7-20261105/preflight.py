#!/usr/bin/env python3
"""Reobserve exact S5-A inputs and live host isolation capabilities."""
import json
import os
import platform
import socket
import sys
import tempfile
from pathlib import Path

from common import C3, C3_SHA, CATALOG, ECMA, FREEZE, GATE, LOCKS, OUT, PLAN, ROOT, SELECTED, SNAPSHOT, STRACE, STRACE_SHA, environment, identity, run, write


def main():
    sys.path.insert(0, str(ROOT / 'tools/distribution'))
    from build import verify_running_builder, verify_source_snapshots
    from distribution_lib import runtime_tree
    from install import check_case_sensitive, filesystem_type
    from manifest_check import digest_json, validate_locks
    assert identity(C3)['sha256'] == C3_SHA
    assert identity(STRACE)['sha256'] == STRACE_SHA
    assert digest_json(json.loads(CATALOG.read_text())) == SELECTED['selectionSha256']
    contract = validate_locks(LOCKS, C3, C3_SHA, CATALOG)
    verify_source_snapshots(SNAPSHOT, contract)
    verify_running_builder(SNAPSHOT)
    check_case_sensitive(OUT / 'tmp')
    assert filesystem_type(OUT) == 'ext4' and os.getuid() == 1000
    env = environment()
    run('strace-version', [STRACE, '--version'], env=env)
    run('strace-child', [STRACE, '-f', '-qq', '-o', OUT / 'strace-probe.log', '/usr/bin/true'], env=env)
    run('bwrap-probe', ['/usr/bin/bwrap', '--die-with-parent', '--unshare-net', '--ro-bind', '/', '/',
        '--dev-bind', '/dev', '/dev', '--proc', '/proc', '/usr/bin/true'], env=env)
    sockets = []
    with tempfile.TemporaryDirectory(dir=OUT / 'tmp') as temp:
        for family, address in [(socket.AF_INET, ('127.0.0.1', 0)), (socket.AF_UNIX, str(Path(temp) / 's'))]:
            with socket.socket(family, socket.SOCK_STREAM) as s:
                s.bind(address); s.listen(1)
                sockets.append({'family': family.name, 'bindListen': True})
    node = ROOT / '.golden-build/version-0.1/toolchains/node-v24.15.0-linux-x64.tar.xz'
    batteries = ROOT / 'third_party/batteries/batteries-v4.33.0.bundle'
    inputs = []
    for key, path in [('node-runtime', node), ('lean-batteries-source', batteries)]:
        row = identity(path); expected = contract['dependencies'][key]
        assert (row['bytes'], row['sha256']) == (expected['bytes'], expected['sha256'])
        inputs.append({'artifactId': key, **row})
    trees = []
    for name, path in [('typescript', ROOT / '.golden-build/rc3-s5-20261031/ts-deps'),
                       ('evidence-wheels', ROOT / '.golden-build/rc3-s5-20261031/prepared/evidence-wheels')]:
        trees.append({'inputId': name, 'path': str(path), **runtime_tree(path)})
    for label, path, revision in [('ecma', ECMA, '9192171fc5f8d8457f8d13ffaafa117222914ec2'),
                                  ('gate', GATE, '4b379ac0c017e7621c945ebf8c106cd98a6c70d1')]:
        assert run(label + '-revision', ['git', '-C', path, 'rev-parse', 'HEAD']) == revision
        assert run(label + '-status', ['git', '--no-optional-locks', '-C', path, 'status', '--porcelain=v1']) == ''
    write(PLAN / 'preflight.json', {'schema': 'mirrors.rc7-qualification-preflight/v1',
        'status': 'passed-local-S5A-prerequisites', 'sourceRevision': FREEZE['freezeRevision'],
        'selectedC0': SELECTED['selectionSha256'], 'profile': 'ubuntu-26.04-wsl2-x86_64',
        'host': {'platform': platform.platform(), 'osRelease': Path('/etc/os-release').read_text(),
                 'filesystem': filesystem_type(OUT), 'uid': os.getuid()},
        'inputs': inputs, 'trees': trees, 'sockets': sockets, 'strace': identity(STRACE),
        'frameworkCatalog': identity(C3), 'installedAuditsPassed': False})
    print('S5-A LOCAL PREREQUISITES GREEN', flush=True)


if __name__ == '__main__':
    main()
