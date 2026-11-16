"""Transfer a hash-bound clean candidate to the owned stage and run full Windows gates."""
from common import *


def main():
    source = json.loads((PLAN / 'source-identity.json').read_text())
    candidate = OUT / 'candidate-input.json'
    write(candidate, source)
    scp = ['scp', '-F', str(Path.home() / '.ssh/config'), '-o', 'BatchMode=yes',
           '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=20']
    run('native-source-transfer', scp + [ROOT / source['sourceBundle']['path'],
        candidate, PLAN / 'native-driver.ps1', 'win10:D:/ModelMirrors/staging/completion-rc12-20261116/'], timeout=300)
    run('native-clean-build-full-test', SSH + ['powershell', '-NoProfile', '-NonInteractive',
        '-ExecutionPolicy', 'Bypass', '-File', STAGE.replace('\\', '/') + '/native-driver.ps1'], timeout=10800)
    print('EXACT-CANDIDATE FULL WINDOWS GATES GREEN', flush=True)


if __name__ == '__main__':
    main()
