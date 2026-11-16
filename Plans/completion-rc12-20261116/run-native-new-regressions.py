"""Use transferred files and the native Job wrapper for explicit regression receipts."""
from common import *


def main():
    scp = ['scp', '-F', str(Path.home() / '.ssh/config'), '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes']
    run('native-new-regression-file-transfer', scp + [PLAN / 'native-new-regressions.py',
        PLAN / 'native-new-regressions.ps1', 'win10:D:/ModelMirrors/staging/completion-rc12-20261116/'], timeout=120)
    raw = run('native-new-review-regressions-attempt2', SSH + ['powershell', '-NoProfile', '-NonInteractive',
        '-ExecutionPolicy', 'Bypass', '-File', STAGE.replace('\\', '/') + '/native-new-regressions.ps1'], timeout=180)
    value, end = json.JSONDecoder().raw_decode(raw)
    assert raw[end:].strip() == 'TASK JOB CLEANUP active=0'
    assert value['status'] == 'passed' and value['testsRun'] == 3 and value['skipped'] == 0
    assert value['nativeDpmDiscoveryCount'] >= 90
    value.update(ownedJobCleanupActive=0, priorAttempt='stdin transport timed out before creating a runner or starting any test; no owned process remained')
    write(PLAN / 'native-new-regressions.json', value)
    print(json.dumps({key: item for key, item in value.items() if key not in ['log', 'python']}, indent=2))


if __name__ == '__main__':
    main()
