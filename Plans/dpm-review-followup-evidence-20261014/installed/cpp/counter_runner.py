#!/usr/bin/env python3
"""Example application adapter for the common runner protocol, using real SDKs.

The generic CLI has no dependency on this Counter application. Other applications
implement the same request/response exchange with their own factories and ports.
"""
import sys
if __name__ == '__main__' and not (sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode):
    print('DPM Python entrypoint requires python3 -I -S -B', file=sys.stderr)
    raise SystemExit(2)

import json
from pathlib import Path
import subprocess


def main():
    application = Path(sys.argv[1]).resolve()
    options = sys.argv[2:]
    if len(options) != 4 or options[0] != '--request' or options[2] != '--response':
        raise ValueError('fixed runner arguments required')
    request_path, response_path = Path(options[1]), Path(options[3])
    request = json.loads(request_path.read_text())
    project_path = Path(request['project'])
    project = json.loads(project_path.read_text())
    candidate = next(c for c in project['candidates'] if c['id'] == request['candidateId'])
    app = json.loads(application.read_text())
    root = application.parent
    def path(value):
        p = Path(value)
        return str(p if p.is_absolute() else root / p)
    limit = project['limits']['outputBytes']
    def read_receipt(path):
        with path.open('rb') as stream:
            raw = stream.read(limit + 1)
        if len(raw) > limit:
            raise ValueError('SDK receipt exceeds request output budget')
        def pairs(rows):
            result = {}
            for key, value in rows:
                if key in result: raise ValueError('duplicate SDK receipt field')
                result[key] = value
            return result
        def nonfinite(value):
            raise ValueError('nonfinite SDK receipt number')
        return json.loads(raw, object_pairs_hook=pairs, parse_constant=nonfinite)
    operation = request['operation']
    if operation == 'materialize':
        result = {k: candidate[k] for k in ['schedule', 'oracle', 'provenance']}
    elif operation == 'describe':
        result = {'profile': project['profile'], 'identity': project['identity'],
                  'operations': ['describe', 'materialize', 'replay', 'explore']}
    elif operation == 'explore':
        receipt = request_path.parent / 'sdk-exploration.json'
        command = [path(p) for p in app['explorer']]
        if app['language'] != 'cpp': command += ['--kind', 'explore', '--mapping', path(app['mapping'])]
        command += ['--out', str(receipt), '--max-runs', '64', '--max-enumerated', '64', '--time-ms', '10000']
        completed = subprocess.run(command, timeout=30)
        if completed.returncode: raise RuntimeError('SDK exploration runner failed')
        result = read_receipt(receipt)
    elif operation == 'replay':
        schedule = request_path.parent / 'schedule.json'
        schedule.write_text(json.dumps(candidate['schedule']) + '\n')
        receipt = request_path.parent / 'sdk-receipt.json'
        command = [path(p) for p in app['runner']]
        command += ['--mirror', path(app['mirror']), '--spec', path(app['spec']),
                    '--trace', str(project_path.parent / candidate['oracle']['path']),
                    '--schedule', str(schedule), '--mapping', path(app['mapping']), '--out', str(receipt)]
        if app['language'] == 'ecma':
            command += ['--spectator', str(candidate['schedule']['inputs'].get('spectator', False)).lower()]
        completed = subprocess.run(command, timeout=120)
        if completed.returncode:
            raise RuntimeError('SDK runner failed: ' + str(completed.returncode))
        result = read_receipt(receipt)
    else:
        raise ValueError('unknown runner operation')
    response = {k: request[k] for k in ['operation', 'requestId', 'projectSha256', 'candidateId']}
    response['schema'] = 'mirrors.dpm-runner-response/v1'
    response['result'] = result
    with response_path.open('x') as stream:
        json.dump(response, stream, separators=(',', ':'))
        stream.write('\n')


if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(2)
