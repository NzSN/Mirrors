"""Build the validator, then bind registered installed audits to rc.12 paths."""
from common import *


def main():
    run('prepare-framework-catalog', ['lake', 'build', 'framework_catalog'], env=environment())
    validator = identity(ROOT / '.lake/build/bin/framework_catalog')
    path = ROOT / 'tools/evidence/commands.json'
    document = json.loads(path.read_text())
    changed = []
    for entry in document['commands']:
        if entry['commandId'] not in ['framework.install-diagnostics', 'framework.install-diagnostics-gate']:
            continue
        argv = entry['argvPrefix']
        profile = 'checked-replay-gate' if entry['commandId'].endswith('-gate') else 'checked-replay-local'
        argv[argv.index('--prefix') + 1] = str(OUT / 'qualification/install' / profile)
        argv[argv.index('--framework-catalog-sha256') + 1] = validator['sha256']
        changed.append(entry['commandId'])
    path.write_text(json.dumps(document, indent=2) + '\n')
    write(PLAN / 'registry-input-admission.json', {'validator': validator, 'reboundCommands': changed,
          'productionMutationPerformed': False, 'qualificationGranted': False})
    print('RC12 REGISTERED INPUTS PREPARED', flush=True)


if __name__ == '__main__':
    main()
