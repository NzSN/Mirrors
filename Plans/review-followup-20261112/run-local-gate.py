"""Run the maintained non-model gate with bounded, separately located scratch."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
OUT = ROOT / '.golden-build/review-followup-20261112'
SOURCE = '37f2d70651a21e7905e80cecc4ce6016a1c315c2'


def main():
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == SOURCE
    assert not subprocess.check_output(['git', 'diff', '--name-only'], cwd=ROOT)
    log = OUT / 'local-no-model.log'
    if log.exists():
        raise RuntimeError('retain previous gate attempt')
    # Only these two steps copy large executables. All other commands retain
    # ordinary ext4 scratch, including the installer filesystem admission tests.
    wrapper = '''
python3() {
  if [[ "$1" == tools/check-dpm-build.py ]] ||
     [[ "$1" == -m && "${2:-}" == unittest && "${5:-}" == tools/deterministic-scheduling/tests ]]; then
    TMPDIR="$MIRRORS_REVIEW_RAM_SCRATCH" command python3 "$@"
  else
    command python3 "$@"
  fi
}
export -f python3
bash tools/run-local-no-model-check.sh
'''
    with tempfile.TemporaryDirectory(prefix='mirrors-review-gate-', dir='/dev/shm') as ram, \
            tempfile.TemporaryDirectory(prefix='mirrors-review-gate-', dir='/tmp') as disk:
        env = os.environ.copy()
        env.update(TMPDIR=disk, MIRRORS_REVIEW_RAM_SCRATCH=ram,
                   PYTHONDONTWRITEBYTECODE='1', CARGO_NET_OFFLINE='true')
        for name in ['APALACHE_MC', 'APALACHE_JAR', 'TLA2TOOLS_JAR', 'MIRRORS_ASYNC_RESOURCE_E2E', 'MIRRORCPP_PREFIX']:
            env.pop(name, None)
        started = time.time()
        with log.open('xb') as output:
            result = subprocess.run(['bash', '-c', wrapper], cwd=ROOT, env=env,
                                    stdout=output, stderr=subprocess.STDOUT, timeout=5400)
        raw = log.read_bytes()
        receipt = {
            'sourceCommit': SOURCE, 'command': 'bash tools/run-local-no-model-check.sh',
            'exitCode': result.returncode, 'startedAtEpoch': started, 'finishedAtEpoch': time.time(),
            'log': {'path': str(log.relative_to(ROOT)), 'bytes': len(raw),
                    'sha256': hashlib.sha256(raw).hexdigest()},
            'largeCopyStepsRamScratch': ['tools/check-dpm-build.py', 'tools/deterministic-scheduling/tests'],
            'scratchWrapper': wrapper, 'otherScratchFilesystem': 'ext4',
            'optionalNativeCppProfile': 'not-selected', 'modelChecking': 'excluded-by-maintained-runner',
            'allLocalNonModelGatesGreen': result.returncode == 0 and raw.rstrip().endswith(b'ALL LOCAL NON-MODEL GATES GREEN'),
        }
        (PLAN / 'local-gate.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps(receipt, indent=2), flush=True)
        raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
