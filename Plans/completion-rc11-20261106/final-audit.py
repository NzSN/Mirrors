"""Verify final immutable identities, retained qualification and delivery scope."""
from evidence_rc11 import *
import shutil,re

def main():
 intake=json.loads((PLAN/'rc11-intake.json').read_text())
 for record in intake['sourceEdits']+intake['preservedUnrelatedFiles']:assert identity(ROOT/record['path'])==record
 assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()==FREEZE['sharedBaseRevision']
 assert subprocess.check_output(['git','diff','--cached','--name-only'],cwd=ROOT,text=True).strip()==''
 for repo,expected in [(SOURCE,COMMIT),(ECMA,'9192171fc5f8d8457f8d13ffaafa117222914ec2'),(GATE,'cd4914b2fa68aaa4f22955352b81cbb890ffd6f0')]:
  assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()==expected
  assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo,text=True).strip()
 assert subprocess.check_output(['git','rev-parse',TAG+'^{commit}'],cwd=SOURCE,text=True).strip()==COMMIT
 q=json.loads((PLAN/'independent-q2-result.json').read_text());assert q['selectedBundlesVerified']==20 and len(q['negativeControls'])==6 and q['catalogLink']['qualification']=='accepted'
 offline=json.loads((PLAN/'offline-after-shutdown.json').read_text());assert offline['status']=='byte-identical-independent-Q2-after-oracle-shutdown'
 for name in ['linux-package.json','windows-package.json','windows-full-result.json','installed-dpm-result.json','controlled-model-result.json','candidate-port.json']:assert (PLAN/name).is_file()
 linux=json.loads((PLAN/'linux-package.json').read_text());assert identity(ROOT/linux['archive']['path'])==linux['archive']
 windows=json.loads((PLAN/'windows-package.json').read_text());wp=OUT/'windows-receipts'/windows['archive']['name'];assert identity(wp)['sha256']==windows['archive']['sha256']
 public=PLAN/'public-evidence';public.mkdir()
 bundles=list((STORE/'runs').iterdir());assert len(bundles)==20
 for bundle in bundles:shutil.copyfile(bundle/'public-summary.json',public/(bundle.name+'.json'))
 for path in [SOURCE/row['path'] for row in intake['sourceEdits']]:
  raw=path.read_bytes();assert b'\x00' not in raw,path
  assert not re.search(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----\r?\n[A-Za-z0-9+/=\r\n]{64,}',raw),path
 controlled=json.loads((ROOT/json.loads((PLAN/'controlled-model-result.json').read_text())['acceptance']['path']).read_text());assert controlled['freshExecutions']==13
 result={'schema':'mirrors.completion-rc11-handoff/v1','status':'qualified-scoped-prerelease-ready-for-separate-publication-and-deployment-approval','sourceRevision':COMMIT,'sourceTree':TREE,'tag':TAG,'gateRevision':'cd4914b2fa68aaa4f22955352b81cbb890ffd6f0','c0':SELECTION,'profile':'m5-wsl-windows-remote','qualificationClass':'local-candidate','qualifiedCatalogSha256':q['catalogLink']['catalogSha256'],'sealedBundles':20,'distributionBindings':q['catalogLink']['distributionBindings'],'negativeControlsRejected':6,'staleAuditControlsRejected':4,'offlineVerificationIdenticalAfterShutdown':True,'windowsFullDriverIncludingNativeRust':True,'installedDpmProfiles':3,'controlledFreshExecutions':13,'clientMatrixRows':22,'linuxArchive':linux['archive'],'windowsArchive':windows['archive'],'sourceFiles':len(intake['sourceEdits']),'unrelatedFilesPreserved':len(intake['preservedUnrelatedFiles']),'productionModified':False,'published':False,'rebootPerformed':False,'remaining':['reviewed source/companion branch publication','tag push including automated GitHub prerelease publication','separate exact Windows asset upload','hash-guarded production replacement and post-deployment controls','separate Windows host reboot and post-boot controls','two shipped compatibility cycles with real workload ledger and consumer acknowledgements'],'scopeLimits':['Ubuntu 26.04.1 WSL2 qualification; local Linux package is not an Ubuntu 24.04 ABI claim','hosted Linux release asset is built and gated by the approved publication workflow; its bytes are not the local WSL package','Linux-only DPM build regression and optional TLA differential unit tiers remain explicitly skipped on native Windows','finite controlled model comparison is not generic/exhaustive native scheduling','native M4 aggregate enforcement, active-process recovery and Windows/macOS Gate backends remain separate tracks']}
 write(PLAN/'result.json',result)
 print('RC11 FINAL IDENTITY / RETENTION / QUALIFICATION AUDIT GREEN',flush=True)
if __name__=='__main__':main()
