"""Fresh prefix/domain reductions from exact installed R1 and project bytes."""
from evidence_rc12 import *
import importlib.util,shutil
spec=importlib.util.spec_from_file_location('linked',PLAN/'collect-linked.py');linked=importlib.util.module_from_spec(spec);spec.loader.exec_module(linked)
result=linked.result;artifact=linked.artifact

def private(path,value):write(path,value);path.chmod(0o600);return path

def main():
 runtime,_=installed('checked-replay-local');env=base_environment();env['MIRRORS_INSTALLED_RUNTIME']=str(runtime);env['TMPDIR']='/tmp/mrc12-final-reductions';Path(env['TMPDIR']).mkdir(mode=0o700)
 support=BASE/'reduction-inputs-absolute';support.mkdir(mode=0o700)
 cid='framework.reduction-prefix';r1=BASE/'outputs/framework.reproduction/reproduction-bundle.json';r0=Path(result('framework.replay-faulty')['bundle'])/'envelope.json';stable=support/'prefix-stability.json'
 run('rc12-c0-final-absolute-prefix-stability',[runtime/'runtimes/node/bin/node',ROOT/'Plans/qualification-rc7-20261105/prepare-prefix-stability.mjs',runtime,r1,r0,stable],env=env)
 framework=json.loads((runtime/'framework-input.json').read_text());installation=framework['installation']
 for item in installation['executables']:item['path']=str((runtime/item['path']).resolve())
 for item in installation['packages']:
  item['root']=str((runtime/item['root']).resolve());item['manifest']['path']=str((runtime/item['manifest']['path']).resolve())
 for item in installation['runtimeTrees']:item['root']=str((runtime/item['root']).resolve())
 admitted_framework=private(support/'prefix-framework.json',framework)
 root=BASE/'outputs'/(cid+'-absolute-inputs')
 existing={'prefix-reduction-original-bundle.json':r1,'prefix-reduction-stability.json':stable,'prefix-reduction-original-trace.json':runtime/'applications/examples/work-queue/artifacts/witness.itf.json','prefix-reduction-framework-input.json':admitted_framework,'prefix-reduction-r0-envelope.json':r0}
 plan=attachment_for(cid,root,existing)
 tail=['--project','applications/reference-project/mirror.faulty.project.json','--bundle',root/'prefix-reduction-original-bundle.json','--stability',root/'prefix-reduction-stability.json','--original-trace',root/'prefix-reduction-original-trace.json','--framework-input',root/'prefix-reduction-framework-input.json','--combination','candidate.local-node-checked','--evidence-envelope',root/'prefix-reduction-r0-envelope.json','--output-root',root,'--candidate-limit','64','--total-budget-ms','600000','--per-candidate-budget-ms','60000','--cleanup-budget-ms','10000']
 collect('rc12-c0-final-absolute-prefix-reduction',cid,cwd=runtime,tail=tail,env=env,attachment_plan=plan,timeout=1200)
 print('RC12 INSTALLED PREFIX REDUCTION GREEN; REMOTE DOMAIN REDUCTION PENDING',flush=True)
if __name__=='__main__':main()
