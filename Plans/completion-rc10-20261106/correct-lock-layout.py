from common_final import *
import copy,shutil,sys
sys.path.insert(0,str(SOURCE/'tools/distribution'))
from manifest_check import validate_locks,selected_lock_input_path,digest_json

def main():
 frozen=copy.deepcopy(FREEZE)
 for family,record in frozen['families'].items():
  root=OUT/'frozen/final-layout'/family;root.mkdir(mode=0o700,parents=True)
  locks=root/'distribution'/('reference-node-wsl2-26.04' if family=='wsl2' else 'reference-node');shutil.copytree(ROOT/record['locksRoot'],locks)
  catalog=root/'catalog'/('framework-catalog-wsl2-26.04.json' if family=='wsl2' else 'framework-catalog.json');catalog.parent.mkdir(mode=0o700);shutil.copyfile(ROOT/record['catalog']['path'],catalog)
  assert selected_lock_input_path(locks,'profiles.json').startswith('distribution/')
  for n in range(2):
   run('rc10-final-layout-'+family+'-refresh-'+str(n),['python3',SOURCE/'tools/distribution/refresh_identity.py','--mirrorecma',ECMA,'--mirrorgate',GATE,'--framework-catalog-bin',C3,'--catalog',catalog,'--locks-root',locks,'--skip-component-records','--skip-render'],cwd=SOURCE)
   assert digest_json(json.loads(catalog.read_text()))==record['selectionSha256'],'catalog identity must not change with packaging layout'
  validate_locks(locks,C3,C3_SHA,catalog)
  record['locksRoot']=locks.relative_to(ROOT).as_posix();record['catalog']=identity(catalog)
 frozen['packagingLayoutCorrection']='canonical distribution/<root>/ lock paths; C0/source/companion identities unchanged; initial cache refused bootstrap and is not credited'
 write(PLAN/'rc10-final-freeze.json',frozen)
 for name in ['common_final.py','evidence_final.py','collect-final-audits.py']:
  p=PLAN/name;p.write_text(p.read_text().replace('rc10-fixed-gate-freeze.json','rc10-final-freeze.json'))
 p=PLAN/'build-final-distributions.py';s=p.read_text().replace("cache=out/'cache'/profile","cache=out/'cache-admitted'/profile").replace("'rc10-final-'+profile","'rc10-final-layout-'+profile");p.with_name('build-final-layout.py').write_text(s)
 print('CANONICAL LOCK LAYOUT ADMITTED; C0 UNCHANGED',flush=True)
if __name__=='__main__':main()
