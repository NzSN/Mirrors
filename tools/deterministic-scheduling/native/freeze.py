#!/usr/bin/env python3
"""Freeze the selected native sources locally; this performs no Windows/network action."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
NATIVE = ROOT.parent / 'WriteSentry'
FILES = ['src/self_watch.cpp', 'src/veh.cpp', 'src/self_watch_internal.h', 'src/mbt_phase_hooks.h',
         'src/test_fault_hooks.h', 'src/arm_timing_diagnostic.h', 'include/writesentry/evidence.h', 'include/writesentry/core_policy.h',
         'include/writesentry/writesentry.h', 'tests/mbt/phase_worker.cpp', 'tests/mbt/runtime_writers.asm',
         'Specs/WriteSentry.tla', 'Specs/WriteSentryMBT.tla',
         'model-interface/phase/WriteSentryPhase.mirror-interface.json',
         'model-interface/phase/WriteSentryPhase.mirror-interface.lock.json',
         'model-interface/phase/WriteSentryPhase.evidence.itf.json',
         'docs/production-readiness/multi-slot-correspondence.md']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(mode=0o700, parents=True, exist_ok=False)
    source = args.out / 'source'; source.mkdir(mode=0o700)
    before = {name: digest(NATIVE / name) for name in FILES}
    for name in FILES:
        target = source / name; target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(NATIVE / name, target)
        if digest(target) != before[name]: raise RuntimeError('source copy changed: ' + name)
    wrapper = Path(__file__).with_name('worker.cpp')
    shutil.copyfile(wrapper, source / 'tests/mbt/dpm_worker.cpp')
    if before != {name: digest(NATIVE / name) for name in FILES}: raise RuntimeError('native source changed during capture')
    manifest = {'schema': 'mirrors.dpm3-native-inputs/v1',
                'sourceBaseRevision': subprocess.check_output(['git', '-C', str(NATIVE), 'rev-parse', 'HEAD'], text=True).strip(),
                'sourceState': 'selected existing working-tree files; unrelated work preserved',
                'sourceHashes': before, 'wrapperSha256': digest(wrapper),
                'scope': 'stable-t1, stable-t2, overlap-t1, overlap-t2; one native operation per actor',
                'nativeExecuted': False, 'modelChecked': False}
    (args.out / 'source-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Locally froze', len(before), 'native source/model/correspondence inputs; no native execution')


if __name__ == '__main__': main()
