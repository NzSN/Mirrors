"""Wait for the selected hosted build, publish the approved Windows ZIP, and verify all assets."""
import tarfile
import time
from common import *


def main():
    rows=json.loads(run('s7-release-workflow-selection',['gh','run','list','--repo','NzSN/Mirrors',
        '--workflow','release.yml','--commit',COMMIT,'--event','push','--json','databaseId,status,conclusion,url,headSha,createdAt']))
    assert len(rows)==1 and rows[0]['headSha']==COMMIT
    workflow_id=str(rows[0]['databaseId'])
    deadline=time.monotonic()+3600
    attempt=0
    previous=None
    while time.monotonic()<deadline:
        workflow=json.loads(run('s7-release-workflow-'+str(attempt),['gh','run','view',workflow_id,
            '--repo','NzSN/Mirrors','--json','status,conclusion,url,headSha,jobs'],timeout=90))
        assert workflow['headSha']==COMMIT
        if workflow['status']!=previous:
            print('Hosted release workflow: '+workflow['status'],flush=True)
            previous=workflow['status']
        if workflow['status']=='completed':
            assert workflow['conclusion']=='success', 'hosted release workflow failed; inspect retained job identities'
            assert all(job['conclusion']=='success' for job in workflow['jobs'])
            break
        attempt+=1
        time.sleep(20)
    else:raise ValueError('hosted release workflow has not completed within its admitted deadline')
    release=json.loads(run('s7-release-initial',['gh','api','repos/NzSN/Mirrors/releases/tags/'+TAG]))
    assert release['prerelease'] and not release['draft'] and len(release['assets'])==3
    expected_linux={'mirrors-'+TAG+'-linux-x86_64.tar.gz','mirrors-'+TAG+'-linux-x86_64.build.json','SHA256SUMS'}
    assert {asset['name'] for asset in release['assets']}==expected_linux
    write(OUT/'release-published-initial.json',release)
    directory=OUT/'published-release'
    directory.mkdir(mode=0o700)
    run('s7-download-linux-assets',['gh','release','download',TAG,'--repo','NzSN/Mirrors','--dir',directory],timeout=600)
    for asset in release['assets']:
        got=identity(directory/asset['name'])
        assert got['bytes']==asset['size'] and 'sha256:'+got['sha256']==asset['digest']
    for line in (directory/'SHA256SUMS').read_text().splitlines():
        digest,name=line.split('  ',1);assert identity(directory/name)['sha256']==digest
    manifest=directory/('mirrors-'+TAG+'-linux-x86_64.build.json')
    metadata=json.loads(manifest.read_text())
    assert metadata['commit']==COMMIT and metadata['tag']==TAG
    assert metadata['passedGates']==['fixtures_replay','diff_cross','model_interface_spec','stdio_smoke',
        'transport_spec','check-client-framing.py','relocated-binary-cli-smoke']
    archive=directory/('mirrors-'+TAG+'-linux-x86_64.tar.gz')
    with tarfile.open(archive) as bundle:
        prefix='mirrors-'+TAG+'-linux-x86_64/'
        assert bundle.extractfile(prefix+'BUILD.json').read()==manifest.read_bytes()
        for name,entry in metadata['binaries'].items():
            assert hashlib.sha256(bundle.extractfile(prefix+'bin/'+name).read()).hexdigest()==entry['sha256']
    run('s7-hosted-archive-check',['python3',SOURCE/'tools/release/release.py','check-archive',
        '--tag',TAG,'--archive',archive],env=environment(),timeout=300)
    run('s7-hosted-tag-check',['python3',SOURCE/'tools/release/release.py','verify-remote',
        '--repository','NzSN/Mirrors','--tag',TAG,'--commit',COMMIT],timeout=180)
    package=json.loads((PLAN/'windows-package.json').read_text())
    windows=OUT/'windows-receipts'/package['archive']['name']
    assert identity(windows)['sha256']==package['archive']['sha256']
    assert run('s7-release-mutation-account',['gh','api','user','--jq','.login']).lower()=='nzsn'
    run('s7-upload-windows',['gh','release','upload',TAG,windows,'--repo','NzSN/Mirrors'],timeout=600)
    run('s7-release-notes',['gh','release','edit',TAG,'--repo','NzSN/Mirrors','--notes-file',PLAN/'release-notes.md',
        '--prerelease','--latest=false'],timeout=120)
    final=json.loads(run('s7-release-final',['gh','api','repos/NzSN/Mirrors/releases/tags/'+TAG]))
    assert final['prerelease'] and not final['draft'] and final['body'].strip()==(PLAN/'release-notes.md').read_text().strip()
    assets={asset['name']:asset for asset in final['assets']}
    assert set(assets)==expected_linux|{windows.name}
    assert assets[windows.name]['digest']=='sha256:'+package['archive']['sha256']
    run('s7-download-windows-asset',['gh','release','download',TAG,'--repo','NzSN/Mirrors',
        '--pattern',windows.name,'--dir',directory],timeout=600)
    for asset in final['assets']:
        got=identity(directory/asset['name'])
        assert got['bytes']==asset['size'] and 'sha256:'+got['sha256']==asset['digest']
    latest=json.loads(run('s7-release-latest',['gh','api','repos/NzSN/Mirrors/releases/latest'],ok=(0,1)))
    assert latest.get('tag_name')!=TAG and (latest.get('tag_name') or str(latest.get('status'))=='404')
    write(PLAN/'release-publication.json',{'schema':'mirrors.rc12.release-publication/v1',
        'status':'published-assets-downloaded-and-verified','url':final['html_url'],'tag':TAG,
        'sourceCommit':COMMIT,'prerelease':True,'isLatest':False,'workflow':workflow['url'],
        'workflowId':workflow_id,'workflowSucceeded':True,
        'assets':[{'name':asset['name'],'bytes':asset['size'],'sha256':asset['digest'].split(':')[1]} for asset in final['assets']],
        'hostedLinuxScope':'Ubuntu 24.04 focused build/runtime workflow gates; no automatic M5 transfer',
        'windowsScope':'exact qualified native source/binary/package at the unchanged source tag',
        'notes':identity(PLAN/'release-notes.md')})
    print('PUBLIC RC12 PRERELEASE AND ALL FOUR DOWNLOADED ASSETS VERIFIED',flush=True)


if __name__=='__main__':main()
