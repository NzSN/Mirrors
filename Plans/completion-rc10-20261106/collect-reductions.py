"""Fresh prefix/domain reductions from exact installed R1 and project bytes."""
from evidence_rc10 import *
import importlib.util,shutil
spec=importlib.util.spec_from_file_location('linked',PLAN/'collect-linked.py');linked=importlib.util.module_from_spec(spec);spec.loader.exec_module(linked)
result=linked.result;artifact=linked.artifact

def private(path,value):write(path,value);path.chmod(0o600);return path

def main():
 runtime,_=installed('checked-replay-local');env=base_environment();env['MIRRORS_INSTALLED_RUNTIME']=str(runtime);env['TMPDIR']='/tmp/mrc10-reductions';Path(env['TMPDIR']).mkdir(mode=0o700)
 support=BASE/'reduction-inputs';support.mkdir(mode=0o700)
 cid='framework.reduction-prefix';r1=BASE/'outputs/framework.reproduction/reproduction-bundle.json';r0=Path(result('framework.replay-faulty')['bundle'])/'envelope.json';stable=support/'prefix-stability.json'
 run('rc10-prefix-stability',[runtime/'runtimes/node/bin/node',ROOT/'Plans/qualification-rc7-20261105/prepare-prefix-stability.mjs',runtime,r1,r0,stable],env=env)
 root=BASE/'outputs'/cid
 existing={'prefix-reduction-original-bundle.json':r1,'prefix-reduction-stability.json':stable,'prefix-reduction-original-trace.json':runtime/'applications/examples/work-queue/artifacts/witness.itf.json','prefix-reduction-framework-input.json':runtime/'framework-input.json','prefix-reduction-r0-envelope.json':r0}
 plan=attachment_for(cid,root,existing)
 tail=['--project','applications/reference-project/mirror.faulty.project.json','--bundle',root/'prefix-reduction-original-bundle.json','--stability',root/'prefix-reduction-stability.json','--original-trace',root/'prefix-reduction-original-trace.json','--framework-input',root/'prefix-reduction-framework-input.json','--combination','candidate.local-node-checked','--evidence-envelope',root/'prefix-reduction-r0-envelope.json','--output-root',root,'--candidate-limit','64','--total-budget-ms','600000','--per-candidate-budget-ms','60000','--cleanup-budget-ms','10000']
 collect('rc10-prefix-reduction',cid,cwd=runtime,tail=tail,env=env,attachment_plan=plan,timeout=1200)
 cid='framework.reduction';root=BASE/'outputs'/cid;r1=BASE/'outputs/framework.reproduction-lease/reproduction-bundle.json';bundle=json.loads(r1.read_text());model=runtime/'applications/examples/lease-service/specs/LeaseService.tla';trace=runtime/'applications/examples/lease-service/artifacts/witness.itf.json'
 candidate={'schema':'mirrors.reduction-candidate/lease-service-input-shrink/v1','modelSha256':identity(model)['sha256'],'interfaceDigest':bundle['identities']['generatedInterface']['semanticDigest'],'orderedCorpusSha256':bundle['identities']['corpus']['orderedOccurrencesSha256'],'originalBundleSha256':identity(r1)['sha256'],'selectedTraceSha256':identity(trace)['sha256'],'traceIndex':0,'traceOccurrences':[0,1],'edits':[{'stateIndex':2,'actionId':'Acquire','inputId':'Client','before':2,'after':1}]}
 tool={'schema':'mirrorecma.lease-reduction-tools/v2','mode':'remote','totalBudgetMs':180000,'cleanupBudgetMs':10000,'validator':{'id':'mirrors.model-interface-reduction/v1','path':str(SOURCE/'.lake/build/bin/model_interface_reduction'),'sha256':identity(SOURCE/'.lake/build/bin/model_interface_reduction')['sha256']}}
 obs=json.loads((BASE/'remote/admin-observation.json').read_text());q=result('mirrors.remote-model-check')['privateRunRef'];service={'endpoint':obs['endpoint'],'peerLeafSha256':obs['mtls']['serverLeafSha256'],'apalacheVersion':obs['runtime']['apalacheVersion'],'javaVersion':obs['runtime']['javaVersion'],'observedAt':obs['observedAt'],'qualificationRef':'E1:'+q['runId']+':'+q['envelopeSha256']}
 existing={'lease-reduction-candidate.json':private(support/'lease-candidate.json',candidate),'lease-reduction-tool-manifest.json':private(support/'lease-tools.json',tool),'lease-reduction-service-identity.json':private(support/'lease-service.json',service),'lease-reduction-original-bundle.json':r1,'lease-reduction-model.tla':model,'lease-reduction-lock.json':runtime/'applications/examples/lease-service/artifacts/LeaseService.mirror-interface.lock.json','lease-reduction-original-trace.json':trace}
 plan=attachment_for(cid,root,existing)
 tail=[]
 for flag,name in [('--candidate','candidate.json'),('--bundle','original-bundle.json'),('--model','model.tla'),('--lock','lock.json'),('--original-trace','original-trace.json'),('--tool-manifest','tool-manifest.json'),('--out','candidate-trace.json'),('--receipt','receipt.json')]:tail +=[flag,root/('lease-reduction-'+name)]
 tail+=['--oracle-mode','remote','--service-identity',root/'lease-reduction-service-identity.json']
 for flag,name in [('--tls-ca','ca.crt'),('--tls-cert','linux-client.crt'),('--tls-key','linux-client.key')]:tail +=[flag,ROOT/'.golden-build/qualification-rc7-20261105/private-pki'/name]
 collect('rc10-domain-reduction',cid,cwd=runtime,tail=tail,env=env,attachment_plan=plan,timeout=900)
 print('RC10 BOTH REAL REDUCTION BRANCHES GREEN',flush=True)
if __name__=='__main__':main()
