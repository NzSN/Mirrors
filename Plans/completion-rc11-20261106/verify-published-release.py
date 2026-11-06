"""Verify real hosted assets and upload/publication outcomes after completion."""
from common import *
import tarfile

def main():
 directory=OUT/'published-release'
 initial=json.loads((OUT/'release-published-initial.json').read_text())
 assert initial['prerelease'] and not initial['draft'] and len(initial['assets'])==3
 for asset in initial['assets']:
  got=identity(directory/asset['name']);assert got['bytes']==asset['size'] and 'sha256:'+got['sha256']==asset['digest']
 for line in (directory/'SHA256SUMS').read_text().splitlines():
  digest,name=line.split('  ',1);assert identity(directory/name)['sha256']==digest
 manifest=directory/('mirrors-'+TAG+'-linux-x86_64.build.json');metadata=json.loads(manifest.read_text())
 assert metadata['commit']==COMMIT and metadata['tag']==TAG
 assert metadata['passedGates']==['fixtures_replay','diff_cross','model_interface_spec','stdio_smoke','transport_spec','check-client-framing.py','relocated-binary-cli-smoke']
 archive=directory/('mirrors-'+TAG+'-linux-x86_64.tar.gz')
 with tarfile.open(archive) as bundle:
  prefix='mirrors-'+TAG+'-linux-x86_64/'
  assert bundle.extractfile(prefix+'BUILD.json').read()==manifest.read_bytes()
  for name,record in metadata['binaries'].items():assert hashlib.sha256(bundle.extractfile(prefix+'bin/'+name).read()).hexdigest()==record['sha256']
 run('s7-hosted-linux-archive-check',['python3',SOURCE/'tools/release/release.py','check-archive','--tag',TAG,'--archive',archive],env=environment(),timeout=300)
 run('s7-published-tag-check',['python3',SOURCE/'tools/release/release.py','verify-remote','--repository','NzSN/Mirrors','--tag',TAG,'--commit',COMMIT],timeout=180)
 run('s7-approved-release-notes',['gh','release','edit',TAG,'--repo','NzSN/Mirrors','--notes-file',PLAN/'release-notes.md','--prerelease','--latest=false'],timeout=120)
 release=json.loads(run('s7-release-final',['gh','api','repos/NzSN/Mirrors/releases/tags/'+TAG],timeout=120))
 assert release['prerelease'] and not release['draft'] and release['body'].strip()==(PLAN/'release-notes.md').read_text().strip()
 names={a['name']:a for a in release['assets']};windows_name='mirrors-'+TAG+'-windows-x86_64.zip'
 assert set(names)=={a['name'] for a in initial['assets']}|{windows_name}
 assert names[windows_name]['digest']=='sha256:f5ec1c9ba3204be04f797acb9086c3a6edd00dce81d7f478c5292b377b7c7df0'
 download=json.loads(run('s7-download-published-windows-on-target',SSH+['D:/ModelMirrors/staging/windows-fixes-20261106/python312-completion/python3.exe','-I','-S','-B',STAGE.replace('\\','/')+'/download-published-windows.py'],timeout=1800));assert download['sha256']==names[windows_name]['digest'].split(':')[1]
 run('s7-retain-published-windows',['scp','-F',str(Path.home()/'.ssh/config'),'win10:'+STAGE.replace('\\','/')+'/published-asset-verification/'+windows_name,directory/windows_name],timeout=1800)
 assert identity(directory/windows_name)['sha256']==names[windows_name]['digest'].split(':')[1]
 latest=json.loads(run('s7-latest-release-check',['gh','api','repos/NzSN/Mirrors/releases/latest'],ok=(0,1),timeout=120));assert latest.get('tag_name')!=TAG and (latest.get('tag_name') or str(latest.get('status'))=='404')
 workflow=json.loads(run('s7-final-workflow',['gh','run','view','42186557688','--repo','NzSN/Mirrors','--json','status,conclusion,url,headSha,jobs'],timeout=120));assert workflow['conclusion']=='success' and workflow['headSha']==COMMIT
 assert all(j['conclusion']=='success' for j in workflow['jobs'])
 write(PLAN/'release-publication.json',{'status':'published-assets-downloaded-and-verified','url':release['html_url'],'tag':TAG,'sourceCommit':COMMIT,'prerelease':True,'isLatest':False,'workflow':workflow['url'],'workflowSucceeded':True,'assets':[{'name':a['name'],'bytes':a['size'],'sha256':a['digest'].split(':')[1]} for a in release['assets']],'hostedLinuxScope':'Ubuntu 24.04 workflow focused build/runtime gates plus local archive verification; no automatic M5 transfer','windowsScope':'exact fully tested native Windows binary/package at source commit','notes':identity(PLAN/'release-notes.md')})
 print('PUBLISHED RC11 RELEASE AND ALL FOUR ASSETS VERIFIED',flush=True)
if __name__=='__main__':main()
