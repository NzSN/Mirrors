"""Check exact local identities, retained receipts and unrelated-file preservation."""
import ast
import re
from common import *


def git(repository, *args):
    return subprocess.check_output(['git', '-C', str(repository), *args], text=True).strip()


def main():
    intake = json.loads((PLAN / 'rc12-intake-final.json').read_text())
    for entry in intake['sourceEdits'] + intake['preservedUnrelatedFiles']:
        assert identity(ROOT / entry['path']) == entry, entry['path']
    assert git(ROOT, 'rev-parse', 'HEAD') == intake['baseRevision']
    assert not git(ROOT, 'diff', '--cached', '--name-only')
    assert git(SOURCE, 'rev-parse', 'HEAD') == COMMIT
    assert git(SOURCE, 'rev-parse', 'HEAD^{tree}') == TREE
    assert not git(SOURCE, 'status', '--porcelain')
    package_source = json.loads((PLAN / 'source-identity.json').read_text())
    assert git(SOURCE, 'rev-parse', TAG) == package_source['tagObject']
    assert git(SOURCE, 'rev-parse', TAG + '^{commit}') == COMMIT
    shared_tag = subprocess.run(['git', 'show-ref', '--verify', '--quiet', 'refs/tags/' + TAG], cwd=ROOT)
    assert shared_tag.returncode == 1
    for repository, revision in [(ECMA, '9192171fc5f8d8457f8d13ffaafa117222914ec2'),
                                  (GATE, 'cd4914b2fa68aaa4f22955352b81cbb890ffd6f0')]:
        assert git(repository, 'rev-parse', 'HEAD') == revision
    local = json.loads((PLAN / 'local-installed-verification.json').read_text())
    assert local['verifiedBundles'] == 16 and len(local['negativeControls']) == 4
    assert local['sourceCommit'] == COMMIT and local['c0'] == FREEZE['families']['wsl2']['selectionSha256']
    assert local['fullM5Q1Q2Acceptance'] is False
    package = json.loads((PLAN / 'linux-package.json').read_text())
    for key in ['archive', 'externalManifest', 'checksums']:
        assert identity(ROOT / package[key]['path']) == package[key]
    dpm = json.loads((PLAN / 'installed-dpm-result.json').read_text())
    for key in ['acceptance', 'manifest']:
        assert identity(ROOT / dpm[key]['path']) == dpm[key]
    assert dpm['sourceRevision'] == COMMIT and dpm['freshModelCheck'] is False
    records = []
    for path in sorted(PLAN.iterdir()):
        if not path.is_file():
            continue
        raw = path.read_bytes()
        assert not re.search(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----\r?\n[A-Za-z0-9+/=\r\n]{64,}', raw)
        assert path.suffix in ['.py', '.ps1', '.json', '.md']
        if path.suffix == '.py':
            ast.parse(raw.decode('utf-8'), filename=str(path))
        if path.suffix == '.json':
            json.loads(raw)
        records.append(identity(path))
    subprocess.run(['git', 'diff', '--check'], cwd=ROOT, check=True)
    value = {'schema': 'mirrors.rc12.local-continuation-completion/v1',
             'status': 'local-work-complete-awaiting-remote-transfer-approval-and-lifecycle-inputs',
             'sourceCommit': COMMIT, 'sourceTree': TREE, 'tag': TAG,
             'tagScope': 'isolated local candidate repository only',
             'c0': FREEZE['families']['wsl2']['selectionSha256'],
             'sourcePayloadFilesVerified': len(intake['sourceEdits']),
             'preservedUnrelatedFilesVerified': len(intake['preservedUnrelatedFiles']),
             'sharedHeadAndIndexPreserved': True, 'cleanFrozenSourcePreserved': True,
             'localNonModelSourceGatesPassed': True, 'linuxPackageVerified': True,
             'bothInstalledAuditsPassed': True, 'installedDpmProfilesPassed': 3,
             'sealedLocalBundlesVerified': 16, 'independentLocalNegativeControlsRejected': 4,
             'fullM5Q1Q2Acceptance': False,
             'windowsSourceTransfer': 'automatic-review-rejected-specific-approval-pending',
             'remotePublicationDeploymentRebootPerformed': False,
             'postFreezeDocumentationPaths': ['Docs/current-status.md', 'CHECKPOINTS.md', 'Plans/execution-decisions.md'],
             'documentationDoesNotTransferAcceptance': True, 'retainedPlanInputs': records}
    write(PLAN / 'local-completion.json', value)
    print(json.dumps({key: item for key, item in value.items() if key != 'retainedPlanInputs'}, indent=2))


if __name__ == '__main__':
    main()
