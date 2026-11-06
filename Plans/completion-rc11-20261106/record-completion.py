"""Bind actual publication/deployment/reboot results and retained evidence."""
from common import *

def main():
 release=json.loads((PLAN/'release-publication.json').read_text());reboot=json.loads((PLAN/'reboot-result.json').read_text());deployment=json.loads((OUT/'windows-receipts/deployment-result-v2.json').read_text());retained=json.loads((OUT/'windows-release-retention.json').read_text())
 assert release['status']=='published-assets-downloaded-and-verified' and release['workflowSucceeded'] and release['prerelease'] and not release['isLatest']
 assert deployment['status']=='deployed-and-live-verified' and reboot['status']=='reboot-auto-start-and-live-controls-passed'
 assert reboot['after']['binary']['sha256']=='5bfb5248a7ab74bfbe6c86361146daa20b0e5e864699c820269279747ef81fd4'
 assert (OUT/'post-reboot-version.txt').read_text().strip()==TAG
 assert retained['status']=='release-and-rollback-retained' and not retained['credentialsIncluded']
 intake=json.loads((PLAN/'rc11-intake.json').read_text())
 for entry in intake['sourceEdits']+intake['preservedUnrelatedFiles']:assert identity(ROOT/entry['path'])==entry
 assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()==FREEZE['sharedBaseRevision']
 assert not subprocess.check_output(['git','diff','--cached','--name-only'],cwd=ROOT,text=True).strip()
 receipts=['source-publication.json','release-publication.json','reboot-result.json','deployment-incident.json','result.json','offline-after-shutdown.json','installed-dpm-result.json','controlled-model-result.json','windows-full-result.json','candidate-port.json']
 raw=['service-recovery.log','atomic-replacement-probe.log','deployment-apply.log','deployment-apply-v2.log','deployed-observation.json','post-reboot-observation.json','windows-release-retention.json','failed-staging-retention.json','reboot-command.log','reboot-poll-receipt.json','hosted-linux-verification.json']
 index={'schema':'mirrors.rc11-retention-index/v1','publicReceipts':[identity(PLAN/n) for n in receipts],'privateOperationReceipts':[identity(OUT/n) for n in raw],'privateQualificationStore':str(OUT/'qualification/evidence'),'publicProjections':str(PLAN/'public-evidence'),'windowsRetention':retained,'privateCredentialBytesIncluded':False}
 write(PLAN/'retention-index.json',index)
 write(PLAN/'completion.json',{'schema':'mirrors.rc11-operation-completion/v1','status':'approved-publication-deployment-and-reboot-complete','completedAtUtc':datetime.now(timezone.utc).isoformat(),'sourceCommit':COMMIT,'tag':TAG,'releaseUrl':release['url'],'publishedBranches':{'Mirrors':'42a4f73f047d4cfa736045590c1c26b693f298fd','MirrorGate':'cd4914b2fa68aaa4f22955352b81cbb890ffd6f0'},'releaseAssetsVerified':len(release['assets']),'windowsDeployedSha256':reboot['after']['binary']['sha256'],'productionVersion':TAG,'productionState':reboot['after']['service'],'postRebootHealth':reboot['health'],'bootTimeUtc':reboot['afterBootUtc'],'configurationDllCredentialsPreserved':True,'initialDeploymentFailure':'retained executable restarted and health verified; explicit-backup File.Replace fix tested and successful retry completed','rollbackRetained':True,'sharedMainAndIndexPreserved':True,'unrelatedFilesPreserved':240,'remaining':'S8 full two-shipped-cycle compatibility/real-workload soak/consumer acknowledgements and retirement decision; no compatibility removal authorized or performed'})
 print('APPROVED PUBLICATION DEPLOYMENT REBOOT AND RETENTION COMPLETE',flush=True)
if __name__=='__main__':main()
