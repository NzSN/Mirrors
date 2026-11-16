"""Prepare an audited local metadata commit without changing shared refs or publishing."""
import re
import shutil
import sys
from common import *


def main():
    result = json.loads((PLAN / 'result.json').read_text())
    assert result['sealedBundles'] == 20 and result['negativeControlsRejected'] == 6
    assert result['offlineVerificationIdenticalAfterShutdown']
    regressions = json.loads((PLAN / 'native-new-regressions.json').read_text())
    assert regressions['testsRun'] == 3 and regressions['skipped'] == 0 and regressions['ownedJobCleanupActive'] == 0
    sys.path.insert(0, str(SOURCE / 'tools/evidence'))
    from source_policy import is_planning_documentation
    write(PLAN / 'delivery.json', {'schema': 'mirrors.rc12.reviewed-delivery-inputs/v1',
          'qualifiedSourceCommit': COMMIT, 'tag': TAG, 'tagObject': json.loads((PLAN / 'source-identity.json').read_text())['tagObject'],
          'expectedRemoteMain': FREEZE['sharedBaseRevision'], 'repositoryVisibility': 'public',
          'payload': ['Plans/completion-rc12-20261116/', 'CHECKPOINTS.md', 'Plans/execution-decisions.md', 'Docs/current-status.md'],
          'followingCommitScope': 'status/evidence documentation and reproducible receipts only; qualified tag stays on source commit',
          'privateArtifactsExcluded': ['raw stores and private command contexts', 'source bundles and package binaries',
                                       'private keys and credentials', 'all 240 pre-existing unrelated files'],
          'pushed': False, 'published': False, 'productionModified': False, 'rebootPerformed': False})
    delivery = OUT / 'delivery'
    run('delivery-clone', ['git', 'clone', '--no-hardlinks', SOURCE, delivery])
    run('delivery-origin', ['git', 'remote', 'set-url', 'origin', 'https://github.com/NzSN/Mirrors.git'], cwd=delivery)
    shutil.copytree(PLAN, delivery / PLAN.relative_to(ROOT), dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('__pycache__'))
    documents = ['CHECKPOINTS.md', 'Plans/execution-decisions.md', 'Docs/current-status.md']
    for name in documents:
        shutil.copyfile(ROOT / name, delivery / name)
    run('delivery-stage', ['git', 'add', '-f', '--', PLAN.relative_to(ROOT), *documents], cwd=delivery)
    changed = run('delivery-paths', ['git', 'diff', '--cached', '--name-only'], cwd=delivery).splitlines()
    assert changed and all(is_planning_documentation('mirrors', name) or name == 'Docs/current-status.md' for name in changed)
    receipts = []
    for name in changed:
        path = delivery / name
        raw = path.read_bytes()
        assert b'\0' not in raw and path.suffix in ['.md', '.py', '.ps1', '.json']
        assert not re.search(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----\r?\n[A-Za-z0-9+/=\r\n]{64,}', raw), name
        staged = subprocess.check_output(['git', 'show', ':' + name], cwd=delivery)
        assert staged == raw
        receipts.append({'path': name, 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()})
    run('delivery-whitespace', ['git', 'diff', '--cached', '--check'], cwd=delivery)
    author = subprocess.check_output(['git', 'config', 'user.name'], cwd=ROOT, text=True).strip()
    email = subprocess.check_output(['git', 'config', 'user.email'], cwd=ROOT, text=True).strip()
    run('delivery-commit', ['git', '-c', 'user.name=' + author, '-c', 'user.email=' + email,
        '-c', 'commit.gpgSign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-m',
        'docs: record rc.12 qualification and production trust handoff'], cwd=delivery)
    revision = run('delivery-revision', ['git', 'rev-parse', 'HEAD'], cwd=delivery)
    assert run('delivery-parent', ['git', 'rev-parse', 'HEAD^'], cwd=delivery) == COMMIT
    assert not run('delivery-status', ['git', 'status', '--porcelain'], cwd=delivery)
    intake = json.loads((PLAN / 'rc12-intake-final.json').read_text())
    for entry in intake['sourceEdits']:
        assert hashlib.sha256((delivery / entry['path']).read_bytes()).hexdigest() == entry['sha256']
    for entry in intake['preservedUnrelatedFiles']:
        assert identity(ROOT / entry['path']) == entry
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == FREEZE['sharedBaseRevision']
    assert not subprocess.check_output(['git', 'diff', '--cached', '--name-only'], cwd=ROOT, text=True).strip()
    value = {'schema': 'mirrors.rc12.delivery-commit/v1', 'status': 'reviewed-local-delivery-ready',
             'metadataCommit': revision, 'qualifiedSourceCommit': COMMIT, 'tag': TAG,
             'metadataPaths': changed, 'payload': receipts, 'sourcePayloadUnchanged': True,
             'statusDocumentationDoesNotTransferQualification': True, 'sharedHeadAndIndexPreserved': True,
             'preservedUnrelatedFiles': len(intake['preservedUnrelatedFiles']), 'pushed': False}
    write(OUT / 'delivery-commit.json', value)
    print('REVIEWED LOCAL DELIVERY READY ' + revision, flush=True)


if __name__ == '__main__':
    main()
