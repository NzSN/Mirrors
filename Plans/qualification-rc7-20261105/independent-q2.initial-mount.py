"""Run inside the installed-only namespace; inputs are mounted read-only."""
import copy,hashlib,json,os,shutil,sys,tempfile,zipfile
from pathlib import Path
root=Path('/q2');config=json.loads((root/'config.json').read_text());runtime=Path('/runtime')
for path in config['hiddenRoots']:assert not Path(path).exists(),path
assert os.readlink('/proc/self/ns/net')!=config['parentNetworkNamespace']
try:(root/'forbidden-write').write_bytes(b'no')
except OSError:pass
else:raise AssertionError('Q2 input mount is writable')
assert hashlib.sha256((runtime/'bin/framework_catalog').read_bytes()).hexdigest()==config['c3Sha256']
sys.path.insert(0,str(root/'python-site'));sys.path.insert(0,str(runtime/'verification/bundle/tools/evidence'))
import jsonschema
assert str(Path(jsonschema.__file__)).startswith('/q2/python-site/')
import verify,qualification_scope,catalog_links
from finalize import canonical_json,public_summary
store=root/'evidence';catalog=root/'qualified-catalog.json';scope=json.loads((root/'qualification-scope.json').read_text());q_id=config['qRunId'];q=store/'runs'/q_id
checks=[]
for run_id in config['runIds']:
 result=verify.verify(store/'runs'/run_id,config['expectedPrivateDigests'][run_id]);assert result['status']=='verified';checks.append(run_id)
verification=verify.verify(q,config['expectedPrivateDigests'][q_id])
linked=catalog_links.evaluate_catalog_link(catalog,q,verification,'m5-wsl-windows-remote')
assert linked['qualification']=='accepted'
controls=[]
def rejects(name,action,contains=None):
 try:action()
 except (OSError,ValueError,AssertionError) as error:
  if contains:assert contains in str(error),(name,str(error))
  controls.append({'name':name,'status':'rejected','reason':str(error)[:700]})
 else:raise AssertionError('negative control accepted: '+name)
def node(command):
 for n in scope['nodes']:
  e=json.loads((store/'runs'/n['privateRunRef']['runId']/'envelope.json').read_text())
  if any(c['commandId']==command for c in e['commands']):return n
 raise AssertionError(command)
# Integrity controls use real mutable copies; the admitted originals stay read-only.
for label,change in [('missing-required-artifact',False),('changed-required-byte',True)]:
 with tempfile.TemporaryDirectory(prefix='q2-negative-') as d:
  mutable=Path(d)/'evidence';shutil.copytree(store,mutable)
  bundle=mutable/'runs'/node('mirrors.local-no-model')['privateRunRef']['runId'];e=json.loads((bundle/'envelope.json').read_text());a=next(a for a in e['artifacts'] if a['artifactId']=='command-stdout');path=bundle/a['location']['path']
  if change:
   raw=path.read_bytes();assert raw;path.write_bytes(bytes([raw[0]^1])+raw[1:])
  else:path.unlink()
  rejects(label,lambda:qualification_scope.verify_scope(scope,mutable))
# Logical controls retain valid sealed bundles and alter the proposed graph.
changed=copy.deepcopy(scope);target=next(n for n in changed['nodes'] if n['privateRunRef']==node('framework.replay-correct')['privateRunRef']);wrong=node('framework.install-diagnostics-gate')['privateRunRef']['runId'];target['distributionRunId']=wrong;target['dependsOnRunIds']=[wrong]
rejects('wrong-D-binding',lambda:qualification_scope.verify_scope(changed,store),'components differ from bound distribution')
changed=copy.deepcopy(scope);target=next(n for n in changed['nodes'] if n['privateRunRef']==node('framework.reproduction')['privateRunRef']);original=node('framework.replay-faulty')['privateRunRef']['runId'];replacement=node('framework.replay-correct')['privateRunRef']['runId'];target['dependsOnRunIds']=[replacement if x==original else x for x in target['dependsOnRunIds']]
rejects('wrong-R0-to-R1-link',lambda:qualification_scope.verify_scope(changed,store),'origin does not match a declared dependency')
changed=copy.deepcopy(scope);target=next(n for n in changed['nodes'] if n['privateRunRef']==node('framework.reduction')['privateRunRef']);original=node('framework.reproduction-lease')['privateRunRef']['runId'];replacement=node('framework.reproduction')['privateRunRef']['runId'];target['dependsOnRunIds']=[replacement if x==original else x for x in target['dependsOnRunIds']]
rejects('wrong-R1-to-R5-link',lambda:qualification_scope.verify_scope(changed,store),'reduction input differs')
# Re-seal an intentionally incomplete Q proposal, so its failure must come
# from complete-profile requirements rather than a stale payload checksum.
with tempfile.TemporaryDirectory(prefix='q2-incomplete-') as d:
 mutable=Path(d)/'evidence';shutil.copytree(store,mutable);bundle=mutable/'runs'/q_id
 envelope=json.loads((bundle/'envelope.json').read_text());artifact=next(a for a in envelope['artifacts'] if a['artifactId']=='qualification-scope');incomplete=copy.deepcopy(scope);omitted=node('mirrorecma.project-check')['privateRunRef']['runId'];incomplete['nodes']=[n for n in incomplete['nodes'] if n['privateRunRef']['runId']!=omitted]
 raw=canonical_json(incomplete);path=bundle/artifact['location']['path'];path.write_bytes(raw);artifact['bytes']=len(raw);artifact['sha256']=hashlib.sha256(raw).hexdigest()
 (bundle/'envelope.json').write_bytes(canonical_json(envelope));(bundle/'public-summary.json').write_bytes(canonical_json(public_summary(envelope)))
 index=json.loads((bundle/'bundle-index.json').read_text())
 for record in index['records']:
  data=(bundle/record['path']).read_bytes();record['bytes']=len(data);record['sha256']=hashlib.sha256(data).hexdigest()
 (bundle/'bundle-index.json').write_bytes(canonical_json(index));checked=verify.verify(bundle);assert checked['status']=='verified'
 proposed=json.loads(catalog.read_text());entry=next(e for e in proposed['evidenceRefs'] if e.get('runRef',{}).get('runId')==q_id);entry['runRef']=checked['publicRunRef'];candidate=Path(d)/'incomplete-catalog.json';candidate.write_text(json.dumps(proposed))
 rejects('incomplete-required-command-profile',lambda:catalog_links.evaluate_catalog_link(candidate,bundle,checked,'m5-wsl-windows-remote'),'required command is absent: mirrorecma.project-check')
assert len(controls)==6
print(json.dumps({'status':'independent-installed-Q2-accepted','scopeId':scope['scopeId'],'sourceHidden':True,'producerScratchHidden':True,'networkNamespaceIsolated':True,'inputsReadOnly':True,'installedVerifierAndSchemas':str(runtime/'verification/bundle/tools/evidence'),'dependencyProvider':str(Path(jsonschema.__file__)),'selectedBundlesVerified':len(checks),'catalogLink':linked,'negativeControls':controls},indent=2))
