import hashlib,json,os,shutil,stat,subprocess,tarfile
from pathlib import Path
B=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
R=Path('/home/jlc/Tools/mirrors-client-fixes-20261015')
O=B/'main-evidence';O.mkdir(exist_ok=False)
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
def write(p,v):p.write_text(json.dumps(v,indent=2)+'\n')
def copy(p):
 rel=p.relative_to(B);d=O/rel;d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,d)
# Exact original selected source set plus current deltas. Derived artifacts excluded.
initial=json.loads((B/'ready-source-manifest.json').read_text()); sources={}
for repo,paths in initial.items():
 rows={}
 for path,old in paths.items():
  p=R/'source'/repo/path
  rows[path]={'sha256':sha(p),'bytes':p.stat().st_size,'executable':bool(p.stat().st_mode&0o111)}
 sources[repo]={'sourceRoot':str(R/'source'/repo),'files':rows,'changesSinceInitialTransfer':[p for p in rows if rows[p]['sha256']!=paths[p]['sha256']]}
cpp={}
for line in (B/'cpp-gate-source-final.sha256').read_text().splitlines():
 digest,path=line.split(None,1);repo,rel=path.strip().split('/',1);p=R/'source'/repo/rel
 assert sha(p)==digest,(repo,rel)
 cpp.setdefault(repo,{})[rel]={'sha256':digest,'bytes':p.stat().st_size,'executable':bool(p.stat().st_mode&0o111)}
for repo,rows in cpp.items():sources[repo]={'sourceRoot':str(R/'source'/repo),'files':rows}
# Haskell has its own independently reviewed complete final H2 manifest.
write(O/'final-main-source-manifest.json',sources)
# Raw top-level records and command scripts; archives, binaries, private material excluded.
for p in B.iterdir():
 if p.is_file() and p.suffix in {'.json','.jsonl','.exit','.log','.py','.sh','.ps1'}:copy(p)
for directory in ['logs','frozen-cli-original-probe','frozen-cli-original-work','postfix-probes','postfix-cli-work']:
 for p in sorted((B/directory).rglob('*')):
  if p.is_file() and p.suffix.lower() not in {'.pem','.key','.crt','.p12','.pfx','.der','.pyc'}:copy(p)
# Hash artifacts in place; no binary retrieval.
artifacts={}
selected=[B/'cpp-gate/immutable/mirror']
for repo in ['Mirrors','MirrorLean']:
 for p in (R/'source'/repo/'.lake/build/bin').glob('*'):
  if p.is_file():selected.append(p)
selected += [R/'source/Mirrors/.lake/build/socket_shim.o',R/'source/Mirrors/.lake/build/tls_shim.o']
for p in (R/'source/MirrorECMA/dist').rglob('*'):
 if p.is_file():selected.append(p)
for p in (B/'rust-control-target/debug/deps').glob('transport-*'):
 if p.is_file() and p.suffix!='.d':selected.append(p)
for p in sorted(set(selected)):
 artifacts[str(p)]={'sha256':sha(p),'bytes':p.stat().st_size,'mode':oct(stat.S_IMODE(p.stat().st_mode)),'resolvedPath':str(p.resolve())}
write(O/'compiled-artifact-identities.json',artifacts)
phases={name:(B/name).read_text().strip() for name in ['lean-final-2.exit','mirrors-focused-2.exit','mirrors-full-2.exit','ecma-focused-2.exit','ecma-ci-3.exit']}
assert all(x=='0' for x in phases.values())
write(O/'final-phase-results.json',{'status':'passed','phaseExits':phases,'nativeRebuildLog':'logs/native-rebuild.log','rustResult':'rust-control-result.json','finalProducer':'frozen-mirror-producer.json','finalFramingAndOriginalCli':'frozen-cli-checks.json','finalLeanOriginalRepros':'lean-original-postfix.json','finalEcmaOriginalRepro':'postfix-ecma-cli.json','sourceOnlyPostCiDelta':{'path':'tools/check-client-framing.py','sha256':'fe2b77b8e24bdff58f9b08dc1b594174ce2b0ece765fab76a382e4fbc7df0dca','compiledInputsChanged':False,'focusedGateRerun':True},'skippedTiers':['Apalache/TLC/live model checking and all production service operations','native Windows/macOS runtime, TLS and ACL profiles','hosted CI runner qualification and GCC13 baseline parity','other Gate backends and current-source Rust worker replay','broader M5/native platform qualification'],'diagnostics':'Earlier nonzero attempts are retained; only final named phases receive success credit. See parent report and per-stream READMEs for individual causes.'})
# Self-excluding inventory, then uncompressed remote-only transport archive.
rows=[]
for p in sorted(O.rglob('*')):
 if p.is_file():rows.append({'path':p.relative_to(O).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size})
write(O/'artifact-manifest.json',{'schema':'client-fixes-main-evidence/v1','files':rows,'fileCount':len(rows),'totalBytes':sum(r['bytes'] for r in rows)})
archive=B/'main-evidence.tar'
with tarfile.open(archive,'w') as tf:tf.add(O,arcname='main')
receipt={'archive':str(archive),'sha256':sha(archive),'bytes':archive.stat().st_size,'manifestSha256':sha(O/'artifact-manifest.json'),'files':len(rows),'totalBytes':sum(r['bytes'] for r in rows),'sourceCounts':{k:len(v['files']) for k,v in sources.items()},'artifactCount':len(artifacts)}
write(B/'main-evidence-transport.json',receipt);print(json.dumps(receipt),flush=True)
