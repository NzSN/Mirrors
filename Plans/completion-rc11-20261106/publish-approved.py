"""Execute the user's explicit publication approval after exact-state checks."""
from common import *

def main():
 delivery=OUT/'delivery';head='42a4f73f047d4cfa736045590c1c26b693f298fd';gate_head='cd4914b2fa68aaa4f22955352b81cbb890ffd6f0'
 for repo,expected in [(SOURCE,COMMIT),(delivery,head),(GATE,gate_head)]:
  assert run('s7-local-'+repo.name+'-head',['git','rev-parse','HEAD'],cwd=repo)==expected
  assert run('s7-local-'+repo.name+'-status',['git','status','--porcelain'],cwd=repo)==''
 assert run('s7-local-tag-object',['git','rev-parse',TAG],cwd=SOURCE)=='1defd75cf9e1df347103f4414ef43a10d1fe26e6'
 assert run('s7-local-tag-peel',['git','rev-parse',TAG+'^{commit}'],cwd=SOURCE)==COMMIT
 mirrors=run('s7-mirrors-remote-before',['git','ls-remote','https://github.com/NzSN/Mirrors.git','refs/heads/main','refs/tags/'+TAG,'refs/tags/'+TAG+'^{}'])
 assert mirrors==FREEZE['sharedBaseRevision']+'\trefs/heads/main'
 gate=run('s7-gate-remote-before',['git','ls-remote','https://github.com/NzSN/MirrorGate.git','refs/heads/main']);assert gate=='4b379ac0c017e7621c945ebf8c106cd98a6c70d1\trefs/heads/main'
 absent=json.loads(run('s7-release-absent',['gh','api','repos/NzSN/Mirrors/releases/tags/'+TAG],ok=(1,)));assert str(absent.get('status'))=='404'
 archive=OUT/'windows-receipts'/('mirrors-'+TAG+'-windows-x86_64.zip');assert identity(archive)['sha256']=='f5ec1c9ba3204be04f797acb9086c3a6edd00dce81d7f478c5292b377b7c7df0'
 run('s7-push-gate',['git','push','origin',gate_head+':refs/heads/main'],cwd=GATE,timeout=300)
 assert run('s7-verify-gate',['git','ls-remote','origin','refs/heads/main'],cwd=GATE)==gate_head+'\trefs/heads/main'
 run('s7-push-mirrors',['git','push','origin',head+':refs/heads/main'],cwd=delivery,timeout=300)
 assert run('s7-verify-mirrors',['git','ls-remote','origin','refs/heads/main'],cwd=delivery)==head+'\trefs/heads/main'
 run('s7-push-release-tag',['git','push','origin','refs/tags/'+TAG],cwd=SOURCE,timeout=300)
 refs=run('s7-verify-release-tag',['git','ls-remote','origin','refs/tags/'+TAG,'refs/tags/'+TAG+'^{}'],cwd=SOURCE)
 assert refs.splitlines()==['1defd75cf9e1df347103f4414ef43a10d1fe26e6\trefs/tags/'+TAG,COMMIT+'\trefs/tags/'+TAG+'^{}']
 write(PLAN/'source-publication.json',{'status':'published-and-remote-refs-verified','sourceCommit':COMMIT,'mainCommit':head,'gateCommit':gate_head,'tag':TAG,'tagObject':'1defd75cf9e1df347103f4414ef43a10d1fe26e6','userApproved':'publish source commits, automated rc.11 prerelease and Windows ZIP','releaseWorkflowPending':True,'sharedMainAndIndexUnchanged':True})
 print('APPROVED SOURCE/TAG PUBLICATION VERIFIED',flush=True)
if __name__=='__main__':main()
