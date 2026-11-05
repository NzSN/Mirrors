#!/usr/bin/env python3
"""Exercise the unchanged installed audit with an explicitly pinned direct tracer."""
import json
from common import C3, C3_SHA, OUT, PLAN, ROOT, environment, run, write


def main():
    tracer = json.loads((PLAN / 'tracer-input.json').read_text())['artifact']
    profile = 'checked-replay-local'
    output = OUT / 'audit/checked-replay-local-direct-tracer'
    output.mkdir(mode=0o700)
    env = environment(); env['TMPDIR'] = '/tmp'
    env.pop('LD_LIBRARY_PATH', None); env.pop('LD_PRELOAD', None)
    run('local-audit-direct-tracer', ['python3', ROOT / 'tools/distribution/qualification.py',
        '--prefix', OUT / 'install' / profile, '--framework-catalog-bin', C3,
        '--framework-catalog-sha256', C3_SHA, '--bwrap', '/usr/bin/bwrap',
        '--strace', tracer['path'], '--strace-sha256', tracer['sha256'],
        '--combination', 'candidate.local-node-checked',
        '--audit-out', output / 'install-diagnostics.json', '--hide-root', ROOT,
        '--hide-root', ROOT.parent / 'MirrorECMA', '--hide-root', ROOT.parent / 'MirrorGate'], env=env)
    write(PLAN / 'local-installed-diagnostic.json', {
        'status': 'strict-installed-runtime-audit-passed-with-explicit-direct-tracer',
        'audit': str(output / 'install-diagnostics.json'), 'registeredFrameworkCommandCredit': False,
        'reason': 'registered path/tracer/hide bindings still require reviewed reconciliation'})


if __name__ == '__main__':
    main()
