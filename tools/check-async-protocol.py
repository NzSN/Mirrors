#!/usr/bin/env python3
"""Check async ownership safety/liveness and require leak mutants to fail.

Uses installed TLC and Apalache's unmodified standard module. --quick keeps the
normal Lake gate small; the default additionally exhausts the two-job model.
No tools are downloaded. Missing tools are explicit skips unless --require-tools.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--quick', action='store_true')
    parser.add_argument('--require-tools', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    tlc = shutil.which('tlc')
    java = shutil.which('java')
    tla_jar = Path(os.environ.get('TLA2TOOLS_JAR', str(Path.home() / '.local/lib/tla2tools.jar')))
    apalache = os.environ.get('APALACHE_MC') or shutil.which('apalache-mc')
    apalache_jar = Path(os.environ.get('APALACHE_JAR', str(
        Path(apalache).resolve().parent.parent / 'lib/apalache.jar' if apalache else Path('/missing/apalache.jar'))))
    command = [tlc] if tlc else ([java, '-Xmx2g', '-cp', str(tla_jar), 'tlc2.TLC']
                               if java and tla_jar.is_file() else None)
    if command is None or not apalache_jar.is_file():
        message = 'async protocol model requires TLC and APALACHE_JAR (or installed apalache-mc)'
        if args.require_tools:
            raise SystemExit(message)
        print('SKIP: ' + message)
        return
    results = []
    if args.output:
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / 'source-hashes.json').write_text(json.dumps({
            name: hashlib.sha256((ROOT / 'specs' / name).read_bytes()).hexdigest()
            for name in ['MirrorProtocol.tla', 'MirrorProtocolFaults.tla', 'MirrorProtocolWitness.tla']
        }, indent=2) + '\n')
    with tempfile.TemporaryDirectory(prefix='mirrors-async-protocol-') as temporary:
        work = Path(temporary)
        for name in ['MirrorProtocol.tla', 'MirrorProtocolFaults.tla', 'MirrorProtocolWitness.tla']:
            shutil.copy2(ROOT / 'specs' / name, work / name)
        with zipfile.ZipFile(apalache_jar) as archive:
            (work / 'Apalache.tla').write_bytes(archive.read('tla2sany/StandardModules/Apalache.tla'))
        base = 'INIT Init\nNEXT {next}\nINVARIANT {invariant}\nVIEW AsyncView\nCHECK_DEADLOCK FALSE\n'
        one = 'CONSTANT AsyncJobIds <- AsyncSingleton\n'
        tiny = one + 'CONSTANT AsyncConnections <- AsyncSingleton\n'
        cases = [('sync-compatibility', 'SPECIFICATION SyncSpec\nINVARIANT Inv\nCHECK_DEADLOCK FALSE\n', None), ('safety', base.format(next='AsyncNext', invariant='AsyncInv') + (one if args.quick else ''), None)]
        live = (ROOT / 'specs/MirrorProtocolAsyncLiveness.cfg').read_text()
        cases.append(('liveness', live, None))
        if not args.quick:
            cases.append(('two-job-liveness', live.replace(one, 'CONSTANT AsyncConnections <- AsyncSingleton\n'), None))
        faults = [('exit', 'AsyncExitFaultNext', 'AsyncClosedOwnersHaveNoEntries'),
                  ('slot', 'AsyncSlotFaultNext', 'AsyncNoOrphanedResources'),
                  ('late-hook', 'AsyncHookFaultNext', 'AsyncLateCancellationSafe'),
                  ('partial-acquisition', 'AsyncAcquisitionFaultNext', 'AsyncNoOrphanedResources')]
        for label, action, invariant in faults:
            cases.append((label, base.format(next=action, invariant=invariant) + tiny,
                          f'Invariant {invariant} is violated'))
        cases.append(('no-fairness', live.replace('AsyncFairSpec', 'AsyncSpec'), 'Temporal properties were violated'))
        for label, config, expected in cases:
            (work / 'check.cfg').write_text(config)
            process = subprocess.run(command + ['-workers', '2', '-config', 'check.cfg', 'MirrorProtocol'],
                                     cwd=work, capture_output=True, text=True, timeout=900)
            output = process.stdout + process.stderr
            if args.output:
                args.output.mkdir(parents=True, exist_ok=True)
                (args.output / (label + '.log')).write_text(output)
            if expected:
                assert process.returncode != 0 and expected in output, (label, output[-6000:])
            else:
                assert process.returncode == 0 and 'Model checking completed. No error has been found.' in output, (label, output[-6000:])
            counts = re.findall(r'([\d,]+) states generated, ([\d,]+) distinct states found', output)
            result = {'case': label, 'result': 'expected counterexample' if expected else 'passed',
                      'states': counts[-1] if counts else None}
            results.append(result)
            print(json.dumps(result), flush=True)
    if args.output:
        (args.output / 'summary.json').write_text(json.dumps(results, indent=2) + '\n')
    print('ASYNC PROTOCOL MODEL GREEN', flush=True)


if __name__ == '__main__':
    main()
