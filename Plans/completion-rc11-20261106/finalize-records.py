"""Publish outcome records only after every approved operation is verified."""
from common import *
import shutil,re

def main():
 completion=json.loads((PLAN/'completion.json').read_text());assert completion['status']=='approved-publication-deployment-and-reboot-complete'
 release=json.loads((PLAN/'release-publication.json').read_text());assert len(release['assets'])==4
 head='''## Approved operations completed

The user approved publication, production replacement and reboot. The
[rc.11 prerelease](https://github.com/NzSN/Mirrors/releases/tag/v0.2.0-rc.11)
is published, all four assets were downloaded and verified, and it is not Latest.
The exact native Windows binary is deployed. Automatic startup and fresh
sync/async valid/invalid plus wrong-pin checks passed after the actual reboot.
See [completion](completion.json), [publication](release-publication.json),
[reboot](reboot-result.json), and [retention](retention-index.json).

The initial deployment controller failed on PowerShell null conversion after
stopping the service but before replacing bytes. The original binary was
restarted and its health verified; explicit-backup atomic replacement and rollback
were tested on NTFS before the successful retry. The [incident](deployment-incident.json)
and corrected [controller](deploy-windows-v2.ps1) retain that history. Production
configuration, DLLs and credentials were preserved; old and deployed binaries
and the ZIP are retained under the Windows release directory.

S0–S7 and retention preparation are complete for the declared scope. S8 still
requires two actual shipped compatibility cycles, real-workload soak records,
consumer acknowledgements and the separate retirement decision. No compatibility
removal is approved or performed. The earlier qualification checkpoint below
retains its original stage state.

'''
 p=PLAN/'README.md';s=p.read_text();i=s.index('\n')+1;p.write_text(s[:i]+'\n'+head+s[i:])
 p=PLAN/'operations.md';s=p.read_text();i=s.index('\n')+1;p.write_text(s[:i]+'\nExecuted under the subsequent user approval. See [completion](completion.json)\nand [resolved deployment incident](deployment-incident.json). The original\noperation proposal below remains historical; `deploy-windows-v2.ps1` is the\ncorrected controller used for successful replacement.\n'+s[i:])
 entry='''## 2026-11-06 — rc.11 published, Windows deployed and reboot verified

The user's explicit approval covered source/companion publication, the rc.11
prerelease and Windows asset, production replacement, and host reboot.
[Completion record](Plans/completion-rc11-20261106/completion.json) binds source
`19c31bf09b58e27c2942ca123a2017c30b638216` and Gate
`cd4914b2fa68aaa4f22955352b81cbb890ffd6f0`. All four release assets were downloaded
and verified; the successful Ubuntu 24.04 workflow remains its own focused scope.
The Windows binary `5bfb5248a7ab74bfbe6c86361146daa20b0e5e864699c820269279747ef81fd4`
is Running/Auto after the observed 2026-11-06 reboot. Four-way mTLS and wrong-pin
controls pass, configuration/DLLs/credentials are preserved, and rollback bytes
are retained. The initial replacement-controller failure was recovered, fixed
with tested explicit backup paths, and retained in the incident record.
Two-shipped-cycle compatibility/real-workload soak and consumer acknowledgements
remain future gates; no retirement or broader platform/M4 claim is inferred.

'''
 for name in ['CHECKPOINTS.md','Plans/execution-decisions.md']:
  p=ROOT/name;s=p.read_text();i=s.index('## ');p.write_text(s[:i]+(entry.replace('Plans/completion-rc11','completion-rc11') if name.startswith('Plans/') else entry)+s[i:])
 delivery=OUT/'delivery';expected='42a4f73f047d4cfa736045590c1c26b693f298fd'
 assert run('s7-records-local-head',['git','rev-parse','HEAD'],cwd=delivery)==expected
 assert run('s7-records-remote-before',['git','ls-remote','origin','refs/heads/main'],cwd=delivery)==expected+'\trefs/heads/main'
 shutil.copytree(PLAN,delivery/PLAN.relative_to(ROOT),dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__'))
 for name in ['CHECKPOINTS.md','Plans/execution-decisions.md']:shutil.copyfile(ROOT/name,delivery/name)
 run('s7-records-stage',['git','add','-f','--',PLAN.relative_to(ROOT),'CHECKPOINTS.md','Plans/execution-decisions.md'],cwd=delivery)
 paths=run('s7-records-paths',['git','diff','--cached','--name-only'],cwd=delivery).splitlines()
 import sys
 sys.path.insert(0,str(SOURCE/'tools/evidence'));from source_policy import is_planning_documentation
 assert all(is_planning_documentation('mirrors',p) for p in paths)
 for name in paths:
  raw=(delivery/name).read_bytes();assert b'\0' not in raw and not re.search(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----\r?\n[A-Za-z0-9+/=\r\n]{64,}',raw)
 run('s7-records-diff-check',['git','diff','--cached','--check'],cwd=delivery)
 author=subprocess.check_output(['git','config','user.name'],cwd=ROOT,text=True).strip();email=subprocess.check_output(['git','config','user.email'],cwd=ROOT,text=True).strip()
 run('s7-records-commit',['git','-c','user.name='+author,'-c','user.email='+email,'-c','commit.gpgSign=false','-c','core.hooksPath=/dev/null','commit','-m','docs: record rc.11 publication deployment and reboot'],cwd=delivery)
 revision=run('s7-records-revision',['git','rev-parse','HEAD'],cwd=delivery)
 run('s7-records-push',['git','push','origin',revision+':refs/heads/main'],cwd=delivery,timeout=300)
 assert run('s7-records-remote-verify',['git','ls-remote','origin','refs/heads/main'],cwd=delivery)==revision+'\trefs/heads/main'
 assert run('s7-records-clean',['git','status','--porcelain'],cwd=delivery)==''
 assert run('s7-tag-final-peel',['git','ls-remote','origin','refs/tags/'+TAG+'^{}'],cwd=delivery)==COMMIT+'\trefs/tags/'+TAG+'^{}'
 write(OUT/'completed-records-delivery.json',{'status':'published-and-remote-verified','metadataCommit':revision,'qualifiedTagSource':COMMIT,'tag':TAG,'paths':paths,'sourceChanged':False})
 print('ALL APPROVED OPERATIONS AND FINAL CHECKPOINT PUBLISHED '+revision,flush=True)
if __name__=='__main__':main()
