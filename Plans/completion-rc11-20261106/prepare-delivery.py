"""Private metadata delivery commit, leaving qualified source/tag untouched."""
from common import *
import shutil,re,sys
sys.path.insert(0,str(SOURCE/'tools/evidence'))
from source_policy import is_planning_documentation
from importlib.util import spec_from_file_location,module_from_spec

def main():
 delivery=OUT/'delivery';run('rc11-delivery-clone',['git','clone','--no-hardlinks',SOURCE,delivery])
 run('rc11-delivery-origin',['git','remote','set-url','origin','https://github.com/NzSN/Mirrors.git'],cwd=delivery)
 shutil.copytree(PLAN,delivery/PLAN.relative_to(ROOT),dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__'))
 for name in ['CHECKPOINTS.md','Plans/execution-decisions.md','Plans/completion-rc10-20261106/README.md','Plans/completion-rc10-20261106/companion-ordering-fix.json','Plans/completion-iteration-20261106/README.md']:
  target=delivery/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/name,target)
 paths=[str(PLAN.relative_to(ROOT)),'CHECKPOINTS.md','Plans/execution-decisions.md','Plans/completion-rc10-20261106/README.md','Plans/completion-rc10-20261106/companion-ordering-fix.json','Plans/completion-iteration-20261106/README.md']
 run('rc11-delivery-stage',['git','add','-f','--',*paths],cwd=delivery)
 changed=run('rc11-delivery-staged-paths',['git','diff','--cached','--name-only'],cwd=delivery).splitlines()
 assert changed and all(is_planning_documentation('mirrors',name) for name in changed)
 for name in changed:
  raw=(delivery/name).read_bytes();assert b'\0' not in raw,name
  assert not re.search(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----\r?\n[A-Za-z0-9+/=\r\n]{64,}',raw),name
  assert Path(name).suffix not in ['.key','.crt','.pem','.exe','.dll','.zip','.gz','.whl','.pyc'],name
 run('rc11-delivery-whitespace',['git','diff','--cached','--check'],cwd=delivery)
 author=subprocess.check_output(['git','config','user.name'],cwd=ROOT,text=True).strip();email=subprocess.check_output(['git','config','user.email'],cwd=ROOT,text=True).strip()
 run('rc11-delivery-commit',['git','-c','user.name='+author,'-c','user.email='+email,'-c','commit.gpgSign=false','-c','core.hooksPath=/dev/null','commit','-m','docs: record rc.11 qualification and release handoff'],cwd=delivery)
 revision=run('rc11-delivery-revision',['git','rev-parse','HEAD'],cwd=delivery);assert run('rc11-delivery-parent',['git','rev-parse','HEAD^'],cwd=delivery)==COMMIT
 assert run('rc11-delivery-clean',['git','status','--porcelain'],cwd=delivery)==''
 # All 49 source payload bytes must remain exactly those validated at the tag.
 for record in json.loads((PLAN/'rc11-intake.json').read_text())['sourceEdits']:
  assert hashlib.sha256((delivery/record['path']).read_bytes()).hexdigest()==record['sha256']
 result={'status':'private-reviewed-delivery-ready','metadataCommit':revision,'qualifiedSourceCommit':COMMIT,'tag':TAG,'metadataPaths':changed,'allChangesPlanningOnly':True,'sourcePayloadUnchanged':True,'sharedMainAndIndexUnchanged':True,'pushed':False}
 write(OUT/'delivery-commit.json',result)
 print('RC11 DELIVERY READY '+revision,flush=True)
if __name__=='__main__':main()
