"""Admit the exact frozen rc.10 commit and prepare an immutable local tag."""
import gzip,json,os,shutil,subprocess,tarfile
from pathlib import Path
from common import *

def main():
 review=json.loads((PLAN/'rc10-freeze-review.json').read_text());assert review['status']=='RC10 SOURCE FREEZE VERIFY GREEN'
 assert run('rc10-package-source-status',['git','-C',SOURCE,'status','--porcelain'])==''
 assert run('rc10-package-source-commit',['git','-C',SOURCE,'rev-parse','HEAD'])==COMMIT
 remote=(OUT/'remote-before-rc10.txt').read_text().splitlines()
 assert remote==[FREEZE['sharedBaseRevision']+'\trefs/heads/main'],remote
 result=subprocess.run(['git','-C',SOURCE,'show-ref','--verify','--quiet','refs/tags/'+TAG],capture_output=True)
 assert result.returncode==1,'tag must be unused'
 author=run('rc10-tag-author',['git','config','user.name']);email=run('rc10-tag-email',['git','config','user.email'])
 run('rc10-local-tag',['git','-C',SOURCE,'-c','tag.gpgSign=false','-c','user.name='+author,'-c','user.email='+email,'tag','-a',TAG,COMMIT,'-m','rc.10 exact-candidate construction and qualification'])
 tag_object=run('rc10-tag-object',['git','-C',SOURCE,'rev-parse',TAG])
 assert run('rc10-tag-peel',['git','-C',SOURCE,'rev-parse',TAG+'^{commit}'])==COMMIT
 import sys
 sys.path.insert(0,str(SOURCE/'tools/release'));import release
 selected=release.identity(SOURCE,TAG);assert selected['embeddedVersion']=='0.2.0-rc.10'
 archive_root=OUT/'archive';archive_root.mkdir(mode=0o700)
 tar_path=archive_root/'source.tar';archive=archive_root/('mirrors-'+TAG+'-source.tar.gz')
 with tar_path.open('xb') as stream:subprocess.run(['git','-C',SOURCE,'archive','--format=tar','--prefix=mirrors-'+TAG+'/',TAG],stdout=stream,check=True)
 with tar_path.open('rb') as src,archive.open('xb') as dst:
  with gzip.GzipFile(filename='',fileobj=dst,mode='wb',mtime=0) as compressed:shutil.copyfileobj(src,compressed)
 rows=[]
 with tarfile.open(archive) as handle:
  for member in handle:
   assert member.isdir() or member.isfile()
   if member.isfile():
    data=handle.extractfile(member).read();rows.append({'path':member.name[len('mirrors-'+TAG+'/'):],'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
 rows.sort(key=lambda row:row['path'])
 write(archive_root/'source-manifest.json',{'commit':COMMIT,'tree':TREE,'tag':TAG,'tagObject':tag_object,'fileCount':len(rows),'files':rows})
 package=SOURCE/'.lake/packages/batteries';package.parent.mkdir(parents=True)
 run('rc10-offline-batteries',['git','clone',SOURCE/'third_party/batteries/batteries-v4.33.0.bundle',package])
 run('rc10-batteries-origin',['git','-C',package,'remote','set-url','origin','https://github.com/leanprover-community/batteries'])
 assert run('rc10-batteries-revision',['git','-C',package,'rev-parse','HEAD'])=='4488d40d070b9700d4d5a6aa342f0d40c31b2a2d'
 bundle=OUT/'rc10-source.bundle'
 run('rc10-source-bundle',['git','-C',SOURCE,'bundle','create',bundle,'HEAD','refs/tags/'+TAG])
 write(PLAN/'source-identity.json',{'schema':'mirrors.rc10-package-source/v1','commit':COMMIT,'tree':TREE,'tag':TAG,'tagObject':tag_object,'tagScope':'task-owned repository only; no remote tag pushed','sourceArchive':identity(archive),'sourceManifest':identity(archive_root/'source-manifest.json'),'fileCount':len(rows),'sourceBundle':identity(bundle),'releaseIdentity':selected})
 print('RC10 SOURCE/TAG PACKAGE ADMISSION GREEN',flush=True)
if __name__=='__main__':main()
