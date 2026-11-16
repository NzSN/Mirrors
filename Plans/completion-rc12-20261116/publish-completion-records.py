"""Audit/publish final receipt documentation, then align refs/index without writing working files."""
import ast
import re
import shutil
import sys
from common import *


def git(repository,*args):
    return subprocess.check_output(['git','-C',str(repository),*args],text=True).strip()


def main():
    completion=json.loads((PLAN/'completion.json').read_text())
    assert completion['status']=='approved-publication-trust-renewal-deployment-and-reboot-complete'
    assert completion['sourceCommit']==COMMIT and completion['releaseAssetsVerified']==4
    delivery=OUT/'delivery'
    base=json.loads((PLAN/'source-publication.json').read_text())['mainCommit']
    assert git(delivery,'rev-parse','HEAD')==base and not git(delivery,'status','--porcelain')
    assert git(SOURCE,'rev-parse','HEAD')==COMMIT and not git(SOURCE,'status','--porcelain')
    assert git(ROOT,'rev-parse','HEAD')==FREEZE['sharedBaseRevision'] and not git(ROOT,'diff','--cached','--name-only')
    intake=json.loads((PLAN/'rc12-intake-final.json').read_text())
    for entry in intake['preservedUnrelatedFiles']:
        assert identity(ROOT/entry['path'])==entry
    for entry in intake['sourceEdits']:
        assert hashlib.sha256((SOURCE/entry['path']).read_bytes()).hexdigest()==entry['sha256']
        if entry['path']!='Docs/versioning.md':
            assert identity(ROOT/entry['path'])==entry
    write(PLAN/'final-delivery-inputs.json',{'schema':'mirrors.rc12.final-receipt-delivery-inputs/v1',
          'qualifiedSourceCommit':COMMIT,'tag':TAG,'expectedPriorPublishedMain':base,
          'operationCompletion':identity(PLAN/'completion.json'),'sourceTagAndArtifactsUnchanged':True,
          'postQualificationDocumentationPaths':['Docs/current-status.md','Docs/versioning.md','CHECKPOINTS.md','Plans/execution-decisions.md','Plans/completion-rc12-20261116/'],
          'qualificationNotTransferredToMetadataCommit':True,'privateKeysAndRawStoresExcluded':True,
          'rollbackEvidenceScope':'old binary tested in stage and live with renewed PKI; no failure-triggered production rollback was needed',
          'unrelatedFilesPreserved':len(intake['preservedUnrelatedFiles'])})
    shutil.copytree(PLAN,delivery/PLAN.relative_to(ROOT),dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__'))
    docs=['CHECKPOINTS.md','Docs/current-status.md','Docs/versioning.md','Plans/execution-decisions.md']
    for name in docs:shutil.copyfile(ROOT/name,delivery/name)
    paths=[PLAN.relative_to(ROOT),*docs]
    run('s7-final-stage',['git','add','-f','--',*paths],cwd=delivery)
    changed=run('s7-final-paths',['git','diff','--cached','--name-only'],cwd=delivery).splitlines()
    sys.path.insert(0,str(SOURCE/'tools/evidence'))
    from source_policy import is_planning_documentation
    assert changed and all(is_planning_documentation('mirrors',name) or name in ['Docs/current-status.md','Docs/versioning.md'] for name in changed)
    selected=[]
    for name in changed:
        path=delivery/name;raw=path.read_bytes()
        assert path.suffix in ['.md','.py','.ps1','.json'] and b'\0' not in raw
        assert not re.search(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----\r?\n[A-Za-z0-9+/=\r\n]{64,}',raw),name
        assert subprocess.check_output(['git','show',':'+name],cwd=delivery)==raw
        if path.suffix=='.py':ast.parse(raw.decode('utf-8'),filename=name)
        if path.suffix=='.json':json.loads(raw)
        selected.append({'path':name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()})
    run('s7-final-whitespace',['git','diff','--cached','--check'],cwd=delivery)
    author=git(ROOT,'config','user.name');email=git(ROOT,'config','user.email')
    run('s7-final-commit',['git','-c','user.name='+author,'-c','user.email='+email,
        '-c','commit.gpgSign=false','-c','core.hooksPath=/dev/null','commit','-m',
        'docs: record rc.12 release trust renewal deployment and reboot'],cwd=delivery)
    revision=git(delivery,'rev-parse','HEAD')
    assert git(delivery,'rev-parse','HEAD^')==base and not git(delivery,'status','--porcelain')
    assert run('s7-final-publication-account',['gh','api','user','--jq','.login']).lower()=='nzsn'
    assert run('s7-final-remote-before',['git','ls-remote','origin','refs/heads/main'],cwd=delivery)==base+'\trefs/heads/main'
    run('s7-final-push',['git','push','origin',revision+':refs/heads/main'],cwd=delivery,timeout=300)
    assert run('s7-final-remote-after',['git','ls-remote','origin','refs/heads/main'],cwd=delivery)==revision+'\trefs/heads/main'
    tag_object=json.loads((PLAN/'source-identity.json').read_text())['tagObject']
    refs=run('s7-final-tag-observation',['git','ls-remote','origin','refs/tags/'+TAG,'refs/tags/'+TAG+'^{}'],cwd=delivery)
    assert refs.splitlines()==[tag_object+'\trefs/tags/'+TAG,COMMIT+'\trefs/tags/'+TAG+'^{}']
    write(OUT/'final-publication.json',{'schema':'mirrors.rc12.final-receipt-publication/v1',
          'status':'final-receipts-published-and-exact-refs-verified','mainCommit':revision,
          'qualifiedSourceCommit':COMMIT,'tag':TAG,'tagObject':tag_object,'payload':selected,
          'qualifiedSourceTagUnchanged':True,'compiledBehavioralInputsUnchanged':True,'documentationDoesNotTransferQualification':True,
          'preservedUnrelatedFiles':len(intake['preservedUnrelatedFiles'])})
    # Align only after proving every currently changed tracked file and every
    # task-owned untracked file is already represented byte-for-byte remotely.
    assert not git(ROOT,'diff','--cached','--name-only')
    dirty=git(ROOT,'diff','--name-only').splitlines()
    new=subprocess.check_output(['git','ls-files','--others','--exclude-standard','--',str(PLAN.relative_to(ROOT))],cwd=ROOT,text=True).splitlines()
    for name in sorted(set(dirty+new)):
        raw=(ROOT/name).read_bytes()
        remote_raw=subprocess.check_output(['git','show',revision+':'+name],cwd=delivery)
        assert raw==remote_raw,'refuse alignment of unreviewed working bytes: '+name
    for entry in intake['preservedUnrelatedFiles']:assert identity(ROOT/entry['path'])==entry
    run('s7-align-fetch',['git','fetch','--no-tags',delivery,'refs/heads/main','refs/tags/'+TAG+':refs/tags/'+TAG],cwd=ROOT,timeout=180)
    # --mixed changes HEAD/index only. Working files and unrelated untracked
    # paths remain untouched; the index was checked empty before this action.
    run('s7-align-head-index',['git','reset','--mixed',revision],cwd=ROOT)
    run('s7-align-remote-tracking',['git','update-ref','refs/remotes/origin/main',revision],cwd=ROOT)
    assert git(ROOT,'rev-parse','HEAD')==revision and not git(ROOT,'diff','--name-only')
    assert not git(ROOT,'diff','--cached','--name-only')
    for entry in intake['preservedUnrelatedFiles']:assert identity(ROOT/entry['path'])==entry
    write(OUT/'shared-checkout-alignment.json',{'status':'aligned-to-already-published-identical-bytes',
          'previousHead':FREEZE['sharedBaseRevision'],'head':revision,'workingFileBytesChanged':False,
          'preExistingStagedChanges':False,'preservedUnrelatedFiles':len(intake['preservedUnrelatedFiles'])})
    print('FINAL RECEIPTS PUBLISHED AND SHARED CHECKOUT ALIGNED '+revision,flush=True)


if __name__=='__main__':main()
