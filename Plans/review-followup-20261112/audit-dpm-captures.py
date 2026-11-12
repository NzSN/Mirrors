"""Read-only strict identity audit of Git-retained DPM remote captures."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/deterministic-scheduling'))
from dpm_host import same_json, strict, strict_bytes


def main():
    tracked = subprocess.check_output(['git', 'ls-files', '-z', '--', 'Plans'], cwd=ROOT)
    captures = [ROOT / name.decode() for name in tracked.split(b'\0') if name
                and name.endswith(b'/capture.json') and name.split(b'/')[1].startswith(b'dpm')]
    rows = []
    for path in sorted(captures):
        row = {'path': str(path.relative_to(ROOT)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
               'inventoryFiles': 0, 'traces': 0, 'comparedTraces': 0, 'failures': [],
               'unavailable': [], 'legacyCoercionMatches': []}
        capture = strict(path)
        if capture.get('schema') != 'mirrors.remote-trace-capture/v1':
            row['failures'].append('unsupported-capture-schema')
            rows.append(row)
            continue
        files = {}
        for entry in capture['files']:
            name = entry['path']
            relative = Path(name)
            if relative.is_absolute() or '..' in relative.parts or '\\' in name:
                raise ValueError('unsafe inventory path')
            source = path.parent / relative
            if name in files:
                row['failures'].append('duplicate-inventory-path:' + name)
                continue
            files[name] = source
            row['inventoryFiles'] += 1
            if not source.is_file():
                row['failures'].append('missing-file:' + name)
            elif hashlib.sha256(source.read_bytes()).hexdigest() != entry['sha256']:
                row['failures'].append('hash-mismatch:' + name)
        if row['failures']:
            rows.append(row)
            continue
        replies = [strict_bytes(line) for line in files['replies.jsonl'].read_bytes().splitlines() if line.strip()]
        returned = [trace for reply in replies if reply.get('proto_step') == 'gen_traces_done'
                    for trace in reply.get('itfTraces', [])]
        path_only = not returned and any(reply.get('proto_step') == 'gen_traces_done'
                                        and reply.get('itfTracePaths') for reply in replies)
        for name, source in files.items():
            if not name.endswith('.itf.json'):
                continue
            row['traces'] += 1
            trace = strict(source)
            if path_only:
                row['unavailable'].append('path-only-reply-no-inline-comparison:' + name)
                continue
            row['comparedTraces'] += 1
            if not any(same_json(trace, actual) for actual in returned):
                row['failures'].append('oracle-differs-from-reply:' + name)
                if trace in returned:
                    row['legacyCoercionMatches'].append(name)
        if row['traces'] != capture['traceCount']:
            row['failures'].append('trace-count-mismatch')
        rows.append(row)
    result = {'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'scope': 'Git-tracked Plans/dpm*/**/capture.json only; no fresh model execution',
              'captures': len(rows), 'traces': sum(row['traces'] for row in rows),
              'comparedTraces': sum(row['comparedTraces'] for row in rows),
              'inventoryFiles': sum(row['inventoryFiles'] for row in rows),
              'failedCaptures': sum(bool(row['failures']) for row in rows),
              'unverifiableCaptures': sum(bool(row['unavailable']) for row in rows),
              'legacyCoercionOnlyMatches': sum(len(row['legacyCoercionMatches']) for row in rows),
              'results': rows}
    (Path(__file__).parent / 'dpm-capture-audit.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key != 'results'}, indent=2))
    raise SystemExit(1 if result['failedCaptures'] else 0)


if __name__ == '__main__':
    main()
