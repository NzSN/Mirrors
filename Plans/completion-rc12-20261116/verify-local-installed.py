"""Verify the completed local subgraph using only installed tools and sealed inputs."""
import shutil
import zipfile
from evidence_rc12 import *


def main():
    audits = json.loads((PLAN / 'rc12-registered-installed-audits.json').read_text())['results']
    local, gate = [item['finalized'] for item in audits]
    nodes = []

    def result(command):
        return json.loads((BASE / 'producer-runs' / (command + '.json')).read_text())

    def add(value, phase, binding=None, dependencies=(), credit=True):
        nodes.append({'phase': phase, 'evidenceUse': 'qualification-credit' if credit else 'retained-attempt',
                      'privateRunRef': value['privateRunRef'], 'publicRunRef': value['publicRunRef'],
                      'distributionRunId': binding['privateRunRef']['runId'] if binding else None,
                      'dependsOnRunIds': [item['privateRunRef']['runId'] for item in dependencies]})

    add(local, 'distribution')
    add(gate, 'distribution')
    for command in ['mirrors.local-no-model', 'mirrorecma.project-check', 'mirrorecma.test', 'mirrorgate.required']:
        add(result(command), 'source-gate', dependencies=[gate] if command == 'mirrorgate.required' else [local])
    for command in ['framework.replay-correct', 'framework.replay-faulty']:
        add(result(command), 'replay', local, [local])
    add(result('framework.lease-origin-installed'), 'origin', local, [local])
    add(result('framework.reproduction'), 'reproduction', local, [local, result('framework.replay-faulty')])
    add(result('framework.reproduction-lease'), 'reproduction', local, [local, result('framework.lease-origin-installed')])
    add(result('framework.reduction-prefix'), 'reduction', local, [local, result('framework.reproduction')])
    add(result('framework.mutation-local'), 'mutation', local, [local])
    add(result('framework.mutation-gate'), 'mutation', gate, [gate])
    add(result('framework.recovery-origin-installed'), 'origin', gate, [gate], credit=False)
    add(result('mirrorgate.recovery'), 'recovery', gate, [gate, result('framework.recovery-origin-installed')])
    assert len(nodes) == 16
    scope = {'schemaVersion': 'mirrors.qualification-scope/v2',
             'scopeId': 'rc12-local-partial-wsl2-20261116', 'qualificationClass': 'local-candidate',
             'selectedCatalogRef': {'schemaVersion': 'mirrors.framework-catalog/v1',
                                   'selectionKind': 'sha256', 'selectionValue': SELECTION},
             'distributionBindingRunIds': [local['privateRunRef']['runId'], gate['privateRunRef']['runId']],
             'nodes': nodes}
    inputs = OUT / 'local-installed-verifier-inputs'
    inputs.mkdir(mode=0o700)
    write(inputs / 'scope.json', scope)
    runtime, _ = installed('checked-replay-local')
    expected = {}
    (inputs / 'evidence').mkdir(mode=0o700)
    (inputs / 'evidence/runs').mkdir(mode=0o700)
    for node in nodes:
        run_id = node['privateRunRef']['runId']
        destination = inputs / 'evidence/runs' / run_id
        destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        shutil.copytree(STORE / 'runs' / run_id, destination)
        expected[run_id] = node['privateRunRef']['envelopeSha256']
    site = inputs / 'python-site'
    site.mkdir(mode=0o700)
    wheels = list((runtime / 'verification/wheels').glob('*.whl'))
    assert wheels
    for wheel in wheels:
        with zipfile.ZipFile(wheel) as archive:
            assert all(not name.startswith('/') and '..' not in Path(name).parts and '\\' not in name
                       for name in archive.namelist())
            archive.extractall(site)
    shutil.copyfile(PLAN / 'local-installed-verifier.py', inputs / 'driver.py')
    write(inputs / 'config.json', {'expectedDigests': expected, 'c3Sha256': C3_SHA,
                                  'hiddenRoots': list(map(str, [ROOT, SOURCE, ECMA, GATE, OUT])),
                                  'parentNetns': os.readlink('/proc/self/ns/net')})
    for path in [inputs / 'scope.json', inputs / 'config.json']:
        path.chmod(0o600)
    command = ['/usr/bin/bwrap', '--die-with-parent', '--unshare-net', '--ro-bind', '/', '/',
               '--tmpfs', '/home', '--tmpfs', '/mnt', '--tmpfs', '/tmp',
               '--ro-bind', inputs, '/tmp/inputs', '--ro-bind', runtime, '/tmp/runtime',
               '--proc', '/proc', '--dev', '/dev', '--clearenv', '--setenv', 'PATH', '/usr/bin:/bin',
               '--setenv', 'HOME', '/tmp', '--setenv', 'TMPDIR', '/tmp',
               '--setenv', 'PYTHONDONTWRITEBYTECODE', '1', '--setenv', 'MIRRORS_FRAMEWORK_CATALOG_VALIDATOR',
               '/tmp/runtime/bin/framework_catalog', '--chdir', '/tmp/inputs',
               '/usr/bin/python3', '-I', '-S', '-B', '/tmp/inputs/driver.py']
    value = json.loads(run('local-installed-subgraph-verification', command, timeout=1200))
    assert value['verifiedBundles'] == 16 and len(value['negativeControls']) == 4
    value.update(sourceCommit=COMMIT, c0=SELECTION, fullM5Q1Q2Acceptance=False,
                 missingRequiredCommands=['mirrors.remote-model-check', 'mirrors.interop', 'framework.reduction'])
    write(PLAN / 'local-installed-verification.json', value)
    print('LOCAL INSTALLED SUBGRAPH VERIFIED; COMPLETE M5/Q REMAINS PENDING', flush=True)


if __name__ == '__main__':
    main()
