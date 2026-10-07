import copy,hashlib,json,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
GEN=ROOT/'.lake/build/bin/model_interface_gen'
LOCK=ROOT/'test/fixtures/deterministic-scheduling/ScheduledCounter.lock.json'
PLAN=ROOT/'test/fixtures/deterministic-scheduling/dpm-kit-plan.json'
TARGETS=['mirrorcpp-v1','mirrorcpp-v2','mirrorecma-async-v1','mirrorecma-async-v2','mirrorrust-v1','mirrorrust-v2']

def invoke(command,plan,target,out):
 return subprocess.run([str(GEN),command,'--lock',str(LOCK),'--mapping',str(plan),'--target',target,'--out',str(out)],capture_output=True,text=True)

class KitTests(unittest.TestCase):
 def test_all_profiles_publish_and_check_without_changing_ordinary_bindings(self):
  with tempfile.TemporaryDirectory() as work:
   for target in TARGETS:
    out=Path(work)/target;plain=Path(work)/(target+'-plain')
    r=invoke('generate-dpm',PLAN,target,out);self.assertEqual(r.returncode,0,r.stderr)
    normal=subprocess.run([str(GEN),'generate','--lock',str(LOCK),'--target',target,'--out',str(plain)],capture_output=True,text=True);self.assertEqual(normal.returncode,0,normal.stderr)
    for p in plain.iterdir():
     if p.name!='.model-interface-generated.json':self.assertEqual(p.read_bytes(),(out/p.name).read_bytes())
    owner=json.loads((out/'.model-interface-generated.json').read_text());self.assertEqual(set(owner['files']),{p.name for p in out.iterdir()})
    self.assertEqual(len(owner['files']),7)
    metadata=json.loads((out/'DpmKit.metadata.json').read_text());self.assertEqual(metadata['mappingSha256'],hashlib.sha256((out/'DpmKit.plan.json').read_bytes()).hexdigest());self.assertTrue(metadata['applicationInstrumentationRequired'])
    before={p.name:p.read_bytes() for p in out.iterdir()};self.assertEqual(invoke('check-dpm',PLAN,target,out).returncode,0);self.assertEqual(before,{p.name:p.read_bytes() for p in out.iterdir()})
 def test_mapping_order_normalizes_to_identical_payloads(self):
  with tempfile.TemporaryDirectory() as work:
   root=Path(work);plan=json.loads(PLAN.read_text());plan['actors'].reverse();plan['actions'].reverse();p=root/'reordered.json';p.write_text(json.dumps(plan))
   a=root/'a';b=root/'b';self.assertEqual(invoke('generate-dpm',PLAN,TARGETS[0],a).returncode,0);self.assertEqual(invoke('generate-dpm',p,TARGETS[0],b).returncode,0)
   self.assertEqual({p.name:p.read_bytes() for p in a.iterdir()},{p.name:p.read_bytes() for p in b.iterdir()})
 def test_invalid_static_mappings_reject_before_output_creation(self):
  changes=[lambda p:p.update(semanticDigest='0'*64),lambda p:p['actors'].append(copy.deepcopy(p['actors'][0])),lambda p:p['actions'].pop(),lambda p:p['actions'][0]['actorSource'].update(inputId='Unknown'),lambda p:p['actions'][0].update(checkpoint='bad checkpoint'),lambda p:p.update(extra=True),lambda p:p['actions'][0].update(actorSource={'kind':'fixed','actor':'unknown'})]
  with tempfile.TemporaryDirectory() as work:
   root=Path(work)
   for i,change in enumerate(changes):
    p=json.loads(PLAN.read_text());change(p);path=root/f'bad{i}.json';path.write_text(json.dumps(p));out=root/f'out{i}'
    r=invoke('generate-dpm',path,TARGETS[0],out);self.assertNotEqual(r.returncode,0,r.stdout);self.assertFalse(out.exists())
 def test_wrong_profile_duplicate_json_and_foreign_flags(self):
  with tempfile.TemporaryDirectory() as work:
   root=Path(work)
   for target in ['mirrorlean-v1','mirrorecma-v1']:
    out=root/target;self.assertNotEqual(invoke('generate-dpm',PLAN,target,out).returncode,0);self.assertFalse(out.exists())
   duplicate=root/'duplicate.json';text=PLAN.read_text();duplicate.write_text('{"schema":"mirrors.dpm-kit-plan/v1",'+text[1:]);self.assertNotEqual(invoke('generate-dpm',duplicate,TARGETS[0],root/'dup').returncode,0)
   r=subprocess.run([str(GEN),'generate','--mapping',str(PLAN)],capture_output=True);self.assertEqual(r.returncode,2)
 def test_non_string_actor_input_and_fixed_actor_semantics(self):
  native=ROOT/'test/fixtures/deterministic-scheduling/timeline/native.lock.json'
  lock=json.loads(native.read_text());action=next(a for a in lock['actions'] if any(x['id']=='Entry' and x['type']['kind']=='int' for x in a['inputs']))
  plan={'schema':'mirrors.dpm-kit-plan/v1','semanticDigest':lock['semanticDigest'],'actors':[{'actor':'a','operation':'owned-operation'}],'actions':[{'actionId':a['id'],'actorSource':{'kind':'fixed','actor':'a'},'checkpoint':a['id']} for a in lock['actions']]}
  next(a for a in plan['actions'] if a['actionId']==action['id'])['actorSource']={'kind':'input','inputId':'Entry'}
  with tempfile.TemporaryDirectory() as work:
   root=Path(work);mapping=root/'mapping.json';mapping.write_text(json.dumps(plan));out=root/'out'
   run=subprocess.run([str(GEN),'generate-dpm','--lock',str(native),'--mapping',str(mapping),'--target','mirrorcpp-v2','--out',str(out)],capture_output=True,text=True)
   self.assertNotEqual(run.returncode,0);self.assertIn('string type',run.stderr);self.assertFalse(out.exists())
 def test_owned_collision_readonly_stale_and_unrelated_file_preservation(self):
  with tempfile.TemporaryDirectory() as work:
   root=Path(work);out=root/'kit';out.mkdir();collision=out/'DpmKit.generated.hpp';collision.write_text('UNOWNED')
   self.assertNotEqual(invoke('generate-dpm',PLAN,TARGETS[0],out).returncode,0);self.assertEqual(collision.read_text(),'UNOWNED');self.assertEqual([p.name for p in out.iterdir()],['DpmKit.generated.hpp'])
   collision.unlink();self.assertEqual(invoke('generate-dpm',PLAN,TARGETS[0],out).returncode,0)
   user=out/'application.cpp';user.write_text('USER OWNED');helper=out/'DpmKit.generated.hpp';original=helper.read_bytes();helper.write_bytes(original+b'// stale\n')
   before=helper.read_bytes();self.assertEqual(invoke('check-dpm',PLAN,TARGETS[0],out).returncode,1);self.assertEqual(helper.read_bytes(),before)
   self.assertEqual(invoke('generate-dpm',PLAN,TARGETS[0],out).returncode,0);self.assertEqual(user.read_text(),'USER OWNED');self.assertEqual(helper.read_bytes(),original)

if __name__=='__main__':unittest.main()
