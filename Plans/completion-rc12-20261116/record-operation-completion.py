"""Bind publication, deployment, renewed trust and actual reboot receipts separately."""
import zipfile
from common import *


def main():
    source=json.loads((PLAN/'source-publication.json').read_text())
    release=json.loads((PLAN/'release-publication.json').read_text())
    deployed=json.loads((PLAN/'deployment-result.json').read_text())
    reboot=json.loads((PLAN/'reboot-result.json').read_text())
    renewal=json.loads((PLAN/'production-pki-renewal.json').read_text())
    bundle=json.loads((PLAN/'public-trust-bundle.json').read_text())
    package=json.loads((PLAN/'windows-package.json').read_text())
    assert source['sourceCommit']==COMMIT and source['tag']==TAG
    assert release['workflowSucceeded'] and release['sourceCommit']==COMMIT and release['prerelease'] and not release['isLatest']
    assert len(release['assets'])==4
    for asset in release['assets']:
        selected=OUT/'published-release'/asset['name']
        assert identity(selected)['sha256']==asset['sha256'] and selected.stat().st_size==asset['bytes']
    expected=package['package']['files']['bin/ModelMirrors.exe']['sha256']
    assert deployed['newSha256']==expected==reboot['after']['binary']['sha256']
    assert deployed['health']['wrongPinRejected'] and reboot['health']['wrongPinRejected']
    assert len(deployed['health']['cases'])==len(reboot['health']['cases'])==4
    assert reboot['status']=='reboot-auto-start-and-mtls-verified'
    assert renewal['existingKeysAndAclsPreserved'] and reboot['configurationDllRuntimeAndPrivateKeysPreserved']
    assert deployed['observation']['certificates']==reboot['after']['certificates']==renewal['renewedCertificates']
    assert reboot['after']['service']['state']=='Running' and reboot['after']['service']['startMode']=='Auto'
    assert identity(ROOT/bundle['localArchive']['path'])==bundle['localArchive']
    with zipfile.ZipFile(ROOT/bundle['localArchive']['path']) as archive:
        assert set(archive.namelist())=={'ca.crt','client.crt','server.crt','TRUST.json','README.txt'}
        assert not bundle['privateKeysIncluded']
    intake=json.loads((PLAN/'rc12-intake-final.json').read_text())
    for entry in intake['preservedUnrelatedFiles']:
        assert identity(ROOT/entry['path'])==entry
    assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=SOURCE,text=True).strip()==COMMIT
    assert not subprocess.check_output(['git','status','--porcelain'],cwd=SOURCE,text=True).strip()
    value={'schema':'mirrors.rc12.operation-completion/v1','status':'approved-publication-trust-renewal-deployment-and-reboot-complete',
           'completedAtUtc':datetime.now(timezone.utc).isoformat(),'sourceCommit':COMMIT,'tag':TAG,
           'initialPublishedMain':source['mainCommit'],'releaseUrl':release['url'],'releaseAssetsVerified':4,
           'prerelease':True,'isLatest':False,'windowsDeployedSha256':expected,
           'productionState':reboot['after']['service'],'newBootUtc':reboot['afterBootUtc'],
           'postBootHealth':reboot['health'],'newCertificates':renewal['renewedCertificates'],
           'existingPrivateKeysAndAclsPreserved':True,'serviceConfigurationDllsAndRuntimePreserved':True,
           'oldBinaryRollbackUnderRenewedTrustTested':True,'rollbackMaterialRetained':True,
           'publicTrustBundle':bundle['localArchive'],'privateKeysExported':False,
           'externalConsumerTrustUpdatesOrAcknowledgementsClaimed':False,
           'unrelatedFilesPreserved':len(intake['preservedUnrelatedFiles']),
           'qualificationScope':'exact source/C0 selected WSL2/native-Windows-oracle profile; production lifecycle controls remain separate',
           'remaining':['two actual shipped compatibility cycles with complete declared matrices and real-workload records',
                        'named consumer/operator trust updates, migration acknowledgements and tested fallback',
                        'separate future retirement decision'],
           'nativeRunnerM4Planning':'withdrawn-from-this-campaign'}
    write(PLAN/'completion.json',value)
    write(PLAN/'lifecycle-update.json',{'schema':'mirrors.rc12.lifecycle-observation/v1',
          'status':'shipping-complete-measured-lifecycle-inputs-still-required',
          'knownShippedReleases':[{'tag':'v0.2.0-rc.11','record':'Plans/completion-rc11-20261106/completion.json'},
                                  {'tag':TAG,'record':'Plans/completion-rc12-20261116/completion.json'}],
          'acceptedCompleteCompatibilityCycles':0,'workloadEntryPointProvided':False,
          'namedConsumerOwnersProvided':False,'consumerAcknowledgementsReceived':False,
          'calendarOrRepeatedSyntheticRunCreditGranted':False,'retirementAdmitted':False})
    print(json.dumps({key:item for key,item in value.items() if key not in ['postBootHealth','newCertificates']},indent=2))


if __name__=='__main__':main()
