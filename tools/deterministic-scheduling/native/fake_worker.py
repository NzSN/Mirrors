#!/usr/bin/env python3
"""Linux-only native bridge protocol fixture; supplies no production evidence."""
import json
import os
import sys
mode = os.environ['DPM_FAKE_CASE']
identity = {'imagePath': 'synthetic-worker', 'imageSha256': 'a' * 64,
            'processId': os.getpid(), 'createdFileTime': 'synthetic-creation',
            'actors': {'t1': 1001, 't2': 1001 if mode == 'duplicate-actors' else 1002}}
count = 0
for line in sys.stdin:
    request = json.loads(line)
    if request['op'] == 'Quit':
        print(json.dumps({'closed': mode != 'missing-quit', 'nativeIdentity': identity}), flush=True)
        break
    if request['op'] == 'Initialize':
        print(json.dumps({'state': {'actual': 0}, 'nativeIdentity': identity}), flush=True)
        continue
    count += 1
    if mode == 'crash': sys.exit(7)
    if mode == 'identity-change': identity['actors']['t1'] += 1
    phase = ('Reserve' if request['command'] == 'Arm' else 'WriteBegin') if request['op'] == 'Begin' else 'CallDone'
    if mode == 'unexpected-phase': phase = 'Undeclared'
    print(json.dumps({'state': {'actual': count}, 'phase': phase, 'nativeIdentity': identity}), flush=True)
