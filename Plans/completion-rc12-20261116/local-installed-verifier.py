"""Installed-only consumer for a bounded, explicitly incomplete qualification graph."""
import copy
import hashlib
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

root = Path('/tmp/inputs')
runtime = Path('/tmp/runtime')
config = json.loads((root / 'config.json').read_text())
assert os.readlink('/proc/self/ns/net') != config['parentNetns']
for hidden in config['hiddenRoots']:
    assert not Path(hidden).exists()
try:
    (root / 'forbidden-write').write_bytes(b'no')
except OSError:
    pass
else:
    raise AssertionError('sealed verifier inputs are writable')
assert hashlib.sha256((runtime / 'bin/framework_catalog').read_bytes()).hexdigest() == config['c3Sha256']
sys.path[:0] = [str(root / 'python-site'), str(runtime / 'verification/bundle/tools/evidence')]
import jsonschema
import qualification_scope
import verify
assert str(Path(jsonschema.__file__)).startswith('/tmp/inputs/python-site/')
store = root / 'evidence'
scope = json.loads((root / 'scope.json').read_text())
for run_id, digest in config['expectedDigests'].items():
    assert verify.verify(store / 'runs' / run_id, digest)['status'] == 'verified'
graph = qualification_scope.verify_scope(scope, store)


def node(command):
    for candidate in scope['nodes']:
        envelope = json.loads((store / 'runs' / candidate['privateRunRef']['runId'] / 'envelope.json').read_text())
        if any(entry['commandId'] == command for entry in envelope['commands']):
            return candidate
    raise AssertionError(command)


controls = []


def reject(name, action, message=None):
    try:
        action()
    except (OSError, ValueError, AssertionError) as error:
        if message:
            assert message in str(error)
        controls.append({'name': name, 'status': 'rejected', 'reason': str(error)[:700]})
    else:
        raise AssertionError('negative control accepted: ' + name)


for label, change in [('missing-required-artifact', False), ('changed-required-byte', True)]:
    with tempfile.TemporaryDirectory(prefix='local-verifier-negative-') as directory:
        mutable = Path(directory) / 'evidence'
        shutil.copytree(store, mutable)
        bundle = mutable / 'runs' / node('mirrors.local-no-model')['privateRunRef']['runId']
        envelope = json.loads((bundle / 'envelope.json').read_text())
        artifact = next(entry for entry in envelope['artifacts'] if entry['artifactId'] == 'command-stdout')
        path = bundle / artifact['location']['path']
        if change:
            raw = path.read_bytes()
            assert raw
            path.write_bytes(bytes([raw[0] ^ 1]) + raw[1:])
        else:
            path.unlink()
        reject(label, lambda: qualification_scope.verify_scope(scope, mutable))
changed = copy.deepcopy(scope)
target = next(entry for entry in changed['nodes'] if entry['privateRunRef'] == node('framework.replay-correct')['privateRunRef'])
wrong = node('framework.install-diagnostics-gate')['privateRunRef']['runId']
target.update(distributionRunId=wrong, dependsOnRunIds=[wrong])
reject('wrong-D-binding', lambda: qualification_scope.verify_scope(changed, store), 'components differ from bound distribution')
changed = copy.deepcopy(scope)
target = next(entry for entry in changed['nodes'] if entry['privateRunRef'] == node('framework.reproduction')['privateRunRef'])
original = node('framework.replay-faulty')['privateRunRef']['runId']
replacement = node('framework.replay-correct')['privateRunRef']['runId']
target['dependsOnRunIds'] = [replacement if item == original else item for item in target['dependsOnRunIds']]
reject('wrong-R0-to-R1-link', lambda: qualification_scope.verify_scope(changed, store), 'origin does not match a declared dependency')
print(json.dumps({'schema': 'mirrors.rc12.local-installed-verification/v1',
                  'status': 'local-subgraph-verified', 'verifiedBundles': len(config['expectedDigests']),
                  'sourceAndProducerScratchHidden': True, 'networkNamespaceIsolated': True,
                  'inputsReadOnly': True, 'installedVerifierUsed': True,
                  'negativeControls': controls, 'graph': graph,
                  'fullM5Q1Q2Acceptance': False}, indent=2))
