#!/usr/bin/env python3
"""Resume with non-overlapping hidden roots; retain the first rejected audit."""
import json
from common import C3, C3_SHA, CATALOG, LOCKS, OUT, PLAN, ROOT, SNAPSHOT, STRACE, STRACE_SHA, environment, run, write


def audit(profile, combination, attempt):
    directory = OUT / 'audit' / (profile + '-' + attempt)
    directory.mkdir(mode=0o700)
    run(profile + '-audit-' + attempt, ['python3', ROOT / 'tools/distribution/qualification.py',
        '--prefix', OUT / 'install' / profile, '--framework-catalog-bin', C3,
        '--framework-catalog-sha256', C3_SHA, '--bwrap', '/usr/bin/bwrap',
        '--strace', STRACE, '--strace-sha256', STRACE_SHA, '--combination', combination,
        '--audit-out', directory / 'install-diagnostics.json', '--hide-root', ROOT,
        '--hide-root', ROOT.parent / 'MirrorECMA', '--hide-root', ROOT.parent / 'MirrorGate'], env=environment())
    assert json.loads((directory / 'install-diagnostics.json').read_text())['status'] == 'passed'


def main():
    first = OUT / 'audit/checked-replay-local/install-diagnostics.json'
    assert json.loads(first.read_text())['status'] == 'failed'
    audit('checked-replay-local', 'candidate.local-node-checked', 'nonoverlap')
    profile = 'checked-replay-gate'
    run(profile + '-build', ['python3', ROOT / 'tools/distribution/build.py', '--profile', profile,
        '--locks-root', LOCKS, '--catalog', CATALOG, '--out', OUT / 'cache' / profile,
        '--snapshot-root', SNAPSHOT, '--lake-bin', '/home/lsz/.elan/bin/lake',
        '--node-archive', ROOT / '.golden-build/version-0.1/toolchains/node-v24.15.0-linux-x64.tar.xz',
        '--batteries-bundle', ROOT / 'third_party/batteries/batteries-v4.33.0.bundle',
        '--git-bin', '/usr/bin/git', '--ldd-bin', '/usr/bin/ldd',
        '--typescript-node-modules', ROOT / '.golden-build/rc3-s5-20261031/ts-deps',
        '--evidence-wheels', ROOT / '.golden-build/rc3-s5-20261031/prepared/evidence-wheels',
        '--framework-catalog-bin', C3, '--framework-catalog-sha256', C3_SHA], env=environment())
    run(profile + '-install', ['python3', ROOT / 'tools/distribution/install.py',
        '--cache', OUT / 'cache' / profile, '--prefix', OUT / 'install' / profile,
        '--framework-catalog-bin', C3, '--framework-catalog-sha256', C3_SHA], env=environment())
    audit(profile, 'candidate.node-gate', 'nonoverlap')
    write(PLAN / 'installed-audits.json', {'status': 'both-installed-audits-passed',
          'sourceRevision': 'f525c6349dc5a5e457757fa040c89312c6703e3a',
          'firstIsolationRecipeFailureRetained': True, 'qualificationGranted': 'installed D only'})


if __name__ == '__main__':
    main()
