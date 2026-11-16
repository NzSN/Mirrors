"""Publish only the exact source/tag and metadata commit approved by the user."""
from common import *
import sys

retained_run = run
def run(name, *args, **kwargs):
    suffix = sys.argv[1] if len(sys.argv) > 1 else ''
    return retained_run(name + suffix, *args, **kwargs)


def main():
    delivery = OUT / 'delivery'
    receipt = json.loads((OUT / 'delivery-commit.json').read_text())
    head = receipt['metadataCommit']
    tag_object = json.loads((PLAN / 'source-identity.json').read_text())['tagObject']
    assert head == '9758728458200cef1de666069e1ce8927d1371c2'
    assert tag_object == '7642edc805797ef331ebc5ae86fdf884d53ca9ad'
    for repository, expected in [(delivery, head), (SOURCE, COMMIT)]:
        assert run('s7-local-' + repository.name + '-head', ['git', 'rev-parse', 'HEAD'], cwd=repository) == expected
        assert not run('s7-local-' + repository.name + '-status', ['git', 'status', '--porcelain'], cwd=repository)
    for entry in receipt['payload']:
        path = delivery / entry['path']
        assert path.stat().st_size == entry['bytes'] and hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256']
    assert run('s7-tag-object', ['git', 'rev-parse', TAG], cwd=SOURCE) == tag_object
    assert run('s7-tag-peel', ['git', 'rev-parse', TAG + '^{commit}'], cwd=SOURCE) == COMMIT
    account = run('s7-github-account', ['gh', 'api', 'user', '--jq', '.login'])
    assert account.lower() == 'nzsn', 'select the authorized publication account before pushing'
    before = run('s7-remote-before', ['git', 'ls-remote', 'origin', 'refs/heads/main',
                                    'refs/tags/' + TAG, 'refs/tags/' + TAG + '^{}'], cwd=delivery)
    assert before == FREEZE['sharedBaseRevision'] + '\trefs/heads/main'
    absent = json.loads(run('s7-release-absent', ['gh', 'api', 'repos/NzSN/Mirrors/releases/tags/' + TAG], ok=(1,)))
    assert str(absent.get('status')) == '404'
    releases = json.loads(run('s7-drafts-absent', ['gh', 'api', 'repos/NzSN/Mirrors/releases?per_page=100']))
    assert not any(item['tag_name'] == TAG for item in releases)
    package = json.loads((PLAN / 'windows-package.json').read_text())
    archive = OUT / 'windows-receipts' / package['archive']['name']
    assert identity(archive)['sha256'] == package['archive']['sha256']
    run('s7-push-main', ['git', 'push', 'origin', head + ':refs/heads/main'], cwd=delivery, timeout=300)
    assert run('s7-verify-main', ['git', 'ls-remote', 'origin', 'refs/heads/main'], cwd=delivery) == head + '\trefs/heads/main'
    run('s7-push-tag', ['git', 'push', 'origin', 'refs/tags/' + TAG], cwd=SOURCE, timeout=300)
    after = run('s7-verify-tag', ['git', 'ls-remote', 'origin', 'refs/tags/' + TAG, 'refs/tags/' + TAG + '^{}'], cwd=SOURCE)
    assert after.splitlines() == [tag_object + '\trefs/tags/' + TAG, COMMIT + '\trefs/tags/' + TAG + '^{}']
    write(PLAN / 'source-publication.json', {'schema': 'mirrors.rc12.source-publication/v1',
          'status': 'published-and-remote-refs-verified', 'sourceCommit': COMMIT, 'mainCommit': head,
          'tag': TAG, 'tagObject': tag_object, 'account': account,
          'userApproved': 'public rc.12 publication, production trust renewal/deployment and reboot after deployment checks',
          'companionsChanged': False, 'releaseWorkflowPending': True, 'productionModified': False,
          'sharedHeadAndIndexPreserved': True})
    print('APPROVED RC12 SOURCE AND TAG PUBLISHED; RELEASE WORKFLOW PENDING', flush=True)


if __name__ == '__main__':
    main()
