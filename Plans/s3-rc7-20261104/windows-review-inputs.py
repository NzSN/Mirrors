"""Read Windows build inputs and exercise the packaged CLI with a restricted PATH."""
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

STAGE = Path(r'D:\ModelMirrors\staging\s3-rc7-20261104-f525c63')
PACKAGE = STAGE / 'mirrors-v0.2.0-rc.7-windows-x86_64'


def record(path):
    data = path.read_bytes()
    return {'path': str(path), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
            'lastWriteUtc': datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()}


def main():
    build = json.loads((STAGE / 'windows-build-record.json').read_text())
    started = datetime.fromisoformat(build['startedUtc'].replace('Z', '+00:00'))
    inputs = [Path(r'D:\Programs\msys2\ucrt64\lib') / name
              for name in ['libssl.dll.a', 'libcrypto.dll.a']]
    inputs += [Path(r'D:\Programs\msys2\ucrt64\include\openssl') / name
               for name in ['ssl.h', 'crypto.h', 'opensslv.h']]
    rows = [record(p) for p in inputs]
    assert all(datetime.fromisoformat(r['lastWriteUtc']) <= started for r in rows)
    before = {p.name: record(p)['sha256'] for p in (PACKAGE / 'bin').iterdir()}
    env = dict(os.environ)
    windows = os.environ.get('SystemRoot', r'C:\Windows')
    env['PATH'] = str(PACKAGE / 'bin') + ';' + windows + r'\System32;' + windows
    for key in ['APALACHE_MC', 'APALACHE_JAR', 'TLA2TOOLS_JAR']:
        env.pop(key, None)
    observations = []
    commands = [([str(PACKAGE / 'bin/ModelMirrors.exe'), '--version'], None, 0),
                ([str(PACKAGE / 'bin/ModelMirrors.exe')], '{"proto_step":"report_state","state":{}}\n', 0),
                ([str(PACKAGE / 'bin/model_interface_gen.exe'), '--help'], None, 2)]
    for argv, data, expected in commands:
        p = subprocess.run(argv, input=data, capture_output=True, text=True,
                           cwd=PACKAGE, env=env, timeout=30)
        assert p.returncode == expected, p.stderr
        observations.append({'argv': argv, 'exitCode': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr})
    assert observations[0]['stdout'] == 'v0.2.0-rc.7\n' and not observations[0]['stderr']
    assert json.loads(observations[1]['stdout'])['proto_step'] == 'protocol_error'
    assert 'usage:' in observations[2]['stderr']
    after = {p.name: record(p)['sha256'] for p in (PACKAGE / 'bin').iterdir()}
    assert before == after
    result = {'schema': 'mirrors.s3-rc7.windows-independent-smoke/v1',
              'observedAt': datetime.now(timezone.utc).isoformat(), 'inputsObservedAfterBuild': rows,
              'observedInputWriteTimesPredateBuild': True, 'path': env['PATH'],
              'sourceAndLeanAbsentFromPath': True, 'observations': observations,
              'packageBytesUnchanged': True, 'published': False, 'deployed': False}
    with (STAGE / 'windows-review-inputs.json').open('x', encoding='utf-8') as stream:
        stream.write(json.dumps(result, indent=2) + '\n')
    print('WINDOWS PACKAGED CLI AND INPUT OBSERVATIONS VERIFIED')


if __name__ == '__main__':
    main()
