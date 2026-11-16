"""Fresh prefix/domain reductions from exact installed R1 and project bytes."""
from evidence_rc12 import *
import importlib.util,shutil
spec=importlib.util.spec_from_file_location('linked',PLAN/'collect-linked.py');linked=importlib.util.module_from_spec(spec);spec.loader.exec_module(linked)
result=linked.result;artifact=linked.artifact

def private(path,value):write(path,value);path.chmod(0o600);return path

def main():
 runtime,_=installed('checked-replay-local');env=base_environment();env['MIRRORS_INSTALLED_RUNTIME']=str(runtime);env['TMPDIR']=str(OUT/'tmp/domain-reduction');Path(env['TMPDIR']).mkdir(mode=0o700,parents=True)
 support=BASE/'reduction-inputs-absolute'
 assert support.is_dir()
 cid='framework.reduction';root=BASE/'outputs'/cid;r1=BASE/'outputs/framework.reproduction-lease/reproduction-bundle.json';bundle=json.loads(r1.read_text());model=runtime/'applications/examples/lease-service/specs/LeaseService.tla';trace=runtime/'applications/examples/lease-service/artifacts/witness.itf.json'
 candidate={'schema':'mirrors.reduction-candidate/lease-service-input-shrink/v1','modelSha256':identity(model)['sha256'],'interfaceDigest':bundle['identities']['generatedInterface']['semanticDigest'],'orderedCorpusSha256':bundle['identities']['corpus']['orderedOccurrencesSha256'],'originalBundleSha256':identity(r1)['sha256'],'selectedTraceSha256':identity(trace)['sha256'],'traceIndex':0,'traceOccurrences':[0,1],'edits':[{'stateIndex':2,'actionId':'Acquire','inputId':'Client','before':2,'after':1}]}
 tool={'schema':'mirrorecma.lease-reduction-tools/v2','mode':'remote','totalBudgetMs':180000,'cleanupBudgetMs':10000,'validator':{'id':'mirrors.model-interface-reduction/v1','path':str(SOURCE/'.lake/build/bin/model_interface_reduction'),'sha256':identity(SOURCE/'.lake/build/bin/model_interface_reduction')['sha256']}}
 obs=json.loads((BASE/'remote/admin-observation.json').read_text());q=result('mirrors.remote-model-check')['privateRunRef'];service={'endpoint':obs['endpoint'],'peerLeafSha256':obs['mtls']['serverLeafSha256'],'apalacheVersion':obs['runtime']['apalacheVersion'],'javaVersion':obs['runtime']['javaVersion'],'observedAt':__import__('datetime').datetime.fromisoformat(obs['observedAt'].replace('Z','+00:00')).isoformat(timespec='milliseconds').replace('+00:00','Z'),'qualificationRef':'E1:'+q['runId']+':'+q['envelopeSha256']}
 existing={'lease-reduction-candidate.json':private(support/'lease-candidate.json',candidate),'lease-reduction-tool-manifest.json':private(support/'lease-tools.json',tool),'lease-reduction-service-identity.json':private(support/'lease-service.json',service),'lease-reduction-original-bundle.json':r1,'lease-reduction-model.tla':model,'lease-reduction-lock.json':runtime/'applications/examples/lease-service/artifacts/LeaseService.mirror-interface.lock.json','lease-reduction-original-trace.json':trace}
 plan=attachment_for(cid,root,existing)
 tail=[]
 for flag,name in [('--candidate','candidate.json'),('--bundle','original-bundle.json'),('--model','model.tla'),('--lock','lock.json'),('--original-trace','original-trace.json'),('--tool-manifest','tool-manifest.json'),('--out','candidate-trace.json'),('--receipt','receipt.json')]:tail +=[flag,root/('lease-reduction-'+name)]
 tail+=['--oracle-mode','remote','--service-identity',root/'lease-reduction-service-identity.json']
 for flag,name in [('--tls-ca','ca.crt'),('--tls-cert','linux-client.crt'),('--tls-key','linux-client.key')]:tail +=[flag,Path(json.loads((PLAN/'fixture-pki.json').read_text())['localRoot'])/name]
 collect('rc12-c0-final-domain-reduction',cid,cwd=runtime,tail=tail,env=env,attachment_plan=plan,timeout=900)
 print('RC12 REMOTE DOMAIN REDUCTION GREEN',flush=True)
if __name__=='__main__':main()
