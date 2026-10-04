#!/usr/bin/env python3
"""Discover a bounded native schedule; all observed states remain diagnostic."""
import argparse
import hashlib
import json
from pathlib import Path
import selectors
import shutil
import subprocess


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def module(steps):
    records = []
    for p in steps:
        records.append('    [' + ', '.join(k + ' |-> ' + (str(v) if type(v) is int else json.dumps(v)) for k, v in p.items()) + ']')
    return '''---- MODULE WriteSentryPhaseRun ----
EXTENDS WriteSentryMBT
RunConstInit ==
  /\\ Threads={"t1","t2"} /\\ Addresses={"A1","A2","A3"}
  /\\ Values={"good","bad"} /\\ WriterKinds={"allowed","other"}
  /\\ SlotCount=4 /\\ Budget=10
  /\\ Plan = <<
''' + ',\n'.join(records) + '\n    >>\n====\n'


class Probe:
    def __init__(self, worker, roles):
        self.process = subprocess.Popen([str(worker)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        self.records, self.steps, self.roles = [], [], roles
        self.identity = None
        self.request({'op': 'Initialize'})

    def request(self, request, role=None):
        self.process.stdin.write(json.dumps(request) + '\n'); self.process.stdin.flush()
        with selectors.DefaultSelector() as selector:
            selector.register(self.process.stdout, selectors.EVENT_READ)
            if not selector.select(30): raise RuntimeError('native response timed out')
        line = self.process.stdout.readline()
        if not line: raise RuntimeError('native worker ended early')
        reply = json.loads(line)
        self.records.append({'request': request, 'reply': reply})
        if 'error' in reply: raise RuntimeError(reply['error'])
        if self.identity is None: self.identity = reply['nativeIdentity']
        if reply['nativeIdentity'] != self.identity: raise RuntimeError('native identity changed')
        if role:
            p = {'action': reply['phase'], 'thread': self.roles[role]['nativeActor'],
                 'command': self.roles[role]['operation'], 'address': 'A1',
                 'value': 'good' if role == 'arm' else 'bad', 'writer': 'allowed', 'span': 1,
                 'entry': reply['entry'], 'slot': reply['slot'], 'target': reply['target']}
            self.steps.append({'role': role, 'request': request, 'parameters': p})
        return reply

    def begin(self, role):
        return self.request({'op': 'Begin', 'thread': self.roles[role]['nativeActor'],
            'command': self.roles[role]['operation'], 'address': 'A1',
            'value': 'good' if role == 'arm' else 'bad', 'writer': 'allowed', 'span': 1}, role)

    def until(self, role, reply, phase):
        for _ in range(150):
            if reply['phase'] == phase: return reply
            if reply['phase'] == 'CallDone': raise RuntimeError('native operation completed before requested phase')
            reply = self.request({'op': 'Advance', 'thread': self.roles[role]['nativeActor']}, role)
        raise RuntimeError('native phase count exceeds pilot bound')

    def close(self):
        reply = self.request({'op': 'Quit'})
        self.process.stdin.close()
        if self.process.wait(timeout=20) != 0 or reply.get('closed') is not True:
            raise RuntimeError('native process cleanup not confirmed')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--worker', type=Path, required=True)
    parser.add_argument('--frozen-source', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args(); args.out.mkdir(parents=True, exist_ok=False)
    worker_hash = sha(args.worker)
    cases = []
    for name in ['stable-t1', 'stable-t2', 'overlap-t1', 'overlap-t2']:
        owner = name[-2:]; writer = owner if name.startswith('stable') else ('t2' if owner == 't1' else 't1')
        roles = {'arm': {'nativeActor': owner, 'operation': 'Arm'}, 'write': {'nativeActor': writer, 'operation': 'Write'}}
        directory = args.out / name; directory.mkdir()
        probe = Probe(args.worker, roles)
        try:
            arm = probe.begin('arm')
            if name.startswith('stable'):
                probe.until('arm', arm, 'CallDone')
                probe.until('write', probe.begin('write'), 'CallDone')
            else:
                arm = probe.until('arm', arm, 'PublishOdd')
                probe.until('write', probe.begin('write'), 'CallDone')
                probe.until('arm', arm, 'CallDone')
            probe.close()
        finally:
            (directory / 'native-probe.json').write_text(json.dumps({'kind': 'diagnostic SUT transcript; not oracle', 'records': probe.records}, indent=2) + '\n')
            if probe.process.poll() is None: probe.close()
        mapping = {'schema': 'mirrors.dpm3-native-mapping/v1', 'profile': 'dpm-writesentry-two-operation/v1', 'roles': roles, 'modelSteps': probe.steps}
        (directory / 'mapping.json').write_text(json.dumps(mapping, indent=2) + '\n')
        (directory / 'WriteSentryPhaseRun.tla').write_text(module([s['parameters'] for s in probe.steps]))
        for model in ['WriteSentry.tla', 'WriteSentryMBT.tla']:
            shutil.copy2(args.frozen_source / 'Specs' / model, directory / model)
        cases.append({'name': name, 'steps': len(probe.steps), 'mappingSha256': sha(directory / 'mapping.json')})
        print(name, len(probe.steps), 'native phases; cleanup confirmed', flush=True)
    if sha(args.worker) != worker_hash: raise RuntimeError('native executable changed')
    (args.out / 'preparation.json').write_text(json.dumps({'schema': 'mirrors.dpm3-preparation/v1', 'workerSha256': worker_hash,
        'cases': cases, 'oracleCaptured': False, 'scope': 'native schedule discovery only'}, indent=2) + '\n')


if __name__ == '__main__': main()
