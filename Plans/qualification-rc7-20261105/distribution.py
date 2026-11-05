#!/usr/bin/env python3
"""Build, install and run both exact selected installed-distribution audits."""
from common import C3, C3_SHA, CATALOG, ECMA, GATE, LOCKS, OUT, PLAN, ROOT, SNAPSHOT, STRACE, STRACE_SHA, environment, run, write
import json


def main():
    assert json.loads((PLAN / 'preflight.json').read_text())['status'] == 'passed-local-S5A-prerequisites'
    env = environment()
    for profile, combination in [('checked-replay-local', 'candidate.local-node-checked'),
                                  ('checked-replay-gate', 'candidate.node-gate')]:
        cache = OUT / 'cache' / profile
        prefix = OUT / 'install' / profile
        audit = OUT / 'audit' / profile
        audit.mkdir(mode=0o700)
        run(profile + '-build', ['python3', ROOT / 'tools/distribution/build.py', '--profile', profile,
            '--locks-root', LOCKS, '--catalog', CATALOG, '--out', cache, '--snapshot-root', SNAPSHOT,
            '--lake-bin', '/home/lsz/.elan/bin/lake',
            '--node-archive', ROOT / '.golden-build/version-0.1/toolchains/node-v24.15.0-linux-x64.tar.xz',
            '--batteries-bundle', ROOT / 'third_party/batteries/batteries-v4.33.0.bundle',
            '--git-bin', '/usr/bin/git', '--ldd-bin', '/usr/bin/ldd',
            '--typescript-node-modules', ROOT / '.golden-build/rc3-s5-20261031/ts-deps',
            '--evidence-wheels', ROOT / '.golden-build/rc3-s5-20261031/prepared/evidence-wheels',
            '--framework-catalog-bin', C3, '--framework-catalog-sha256', C3_SHA], env=env)
        run(profile + '-install', ['python3', ROOT / 'tools/distribution/install.py', '--cache', cache,
            '--prefix', prefix, '--framework-catalog-bin', C3, '--framework-catalog-sha256', C3_SHA], env=env)
        run(profile + '-audit', ['python3', ROOT / 'tools/distribution/qualification.py', '--prefix', prefix,
            '--framework-catalog-bin', C3, '--framework-catalog-sha256', C3_SHA,
            '--bwrap', '/usr/bin/bwrap', '--strace', STRACE, '--strace-sha256', STRACE_SHA,
            '--combination', combination, '--audit-out', audit / 'install-diagnostics.json',
            '--hide-root', ROOT, '--hide-root', ECMA, '--hide-root', GATE,
            '--hide-root', ROOT.parent / 'MirrorECMA', '--hide-root', ROOT.parent / 'MirrorGate'], env=env)
        result = json.loads((audit / 'install-diagnostics.json').read_text())
        assert result['status'] == 'passed'
    write(PLAN / 'installed-audits.json', {'status': 'both-installed-audits-passed',
          'profiles': ['checked-replay-local', 'checked-replay-gate'],
          'installedDAdmissionOnly': True, 'frameworkQualificationGranted': False})


if __name__ == '__main__':
    main()
