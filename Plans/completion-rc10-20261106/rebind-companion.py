"""New C0 for fixed Gate; Mirrors source/tag/packages stay at the same bytes."""
from common import *
import copy,shutil,sys
sys.path.insert(0,str(SOURCE/'tools/distribution'))
from refresh_identity import selected_refs
from manifest_check import digest_json,validate_locks
from build import verify_running_builder,verify_source_snapshots

def main():
 fix=json.loads((PLAN/'companion-ordering-fix.json').read_text());gate=ROOT/fix['source'];refs=selected_refs(ECMA,gate)
 assert refs['mirrors']['revision']==COMMIT and not any(v['dirty'] for v in refs.values())
 frozen=copy.deepcopy(FREEZE);family_root=OUT/'frozen/gate-fixed-candidates';family_root.mkdir(mode=0o700)
 for family,old in FREEZE['families'].items():
  target=family_root/family;target.mkdir(mode=0o700);catalog=target/'catalog.json';locks=target/'locks'
  shutil.copyfile(ROOT/old['catalog']['path'],catalog);shutil.copytree(ROOT/old['locksRoot'],locks)
  for n in range(2):
   run('rc10-fixed-gate-'+family+'-refresh-'+str(n),['python3',SOURCE/'tools/distribution/refresh_identity.py','--mirrorecma',ECMA,'--mirrorgate',gate,'--framework-catalog-bin',C3,'--catalog',catalog,'--locks-root',locks,'--skip-component-records','--skip-render'],cwd=SOURCE)
   now={p.relative_to(target).as_posix():identity(p)['sha256'] for p in target.rglob('*') if p.is_file()}
   if n:assert now==previous
   previous=now
  doc=json.loads(catalog.read_text());assert {v['componentRef']['componentId']:v['componentRef'] for v in doc['components']}==refs
  contract=validate_locks(locks,C3,C3_SHA,catalog);snapshot=target/'snapshots'
  run('rc10-fixed-gate-'+family+'-snapshot',['python3',SOURCE/'tools/distribution/snapshot_sources.py','--component-lock',locks/'component-lock.json','--out',snapshot,'--mirrors',SOURCE,'--mirrorecma',ECMA,'--mirrorgate',gate],cwd=SOURCE)
  verify_source_snapshots(snapshot,contract);verify_running_builder(snapshot)
  idx=json.loads((snapshot/'snapshot-index.json').read_text());m=next(x for x in idx['components'] if x['componentRef']['componentId']=='mirrors');assert m['treeIndexSha256']==FREEZE['validatedSourceTreeIndexSha256']
  frozen['families'][family]={**old,'catalog':identity(catalog),'selectionSha256':digest_json(doc),'locksRoot':locks.relative_to(ROOT).as_posix(),'snapshotIndex':identity(snapshot/'snapshot-index.json'),'candidateFiles':{p.relative_to(target).as_posix():identity(p) for p in sorted(target.rglob('*')) if p.is_file() and 'snapshots' not in p.relative_to(target).parts}}
 frozen['companionOrderingFix']=fix;frozen['supersedesCatalogOnly']='rc10-freeze-manifest.json';frozen['status']='source-and-fixed-companion-bound-new-c0';frozen['qualificationGranted']=False
 write(PLAN/'rc10-fixed-gate-freeze.json',frozen)
 text=(PLAN/'common.py').read_text().replace("PLAN/'rc10-freeze-manifest.json'","PLAN/'rc10-fixed-gate-freeze.json'").replace("GATE=ROOT/'.golden-build/mw12-20261103/inputs/companions/MirrorGate'","GATE=ROOT/ FREEZE['companionOrderingFix']['source']")
 (PLAN/'common_final.py').write_text(text)
 text=(PLAN/'evidence_rc10.py').read_text().replace('from common import *','from common_final import *').replace("PLAN/'rc10-freeze-manifest.json'","PLAN/'rc10-fixed-gate-freeze.json'").replace("BASE=OUT/'qualification'","BASE=OUT/'qualification-final'").replace("prefix=BASE/'install'/profile", "prefix=OUT/'qualification/install'/profile")
 (PLAN/'evidence_final.py').write_text(text)
 print('RC10 FIXED-GATE C0 '+frozen['families']['wsl2']['selectionSha256'],flush=True)
if __name__=='__main__':main()
