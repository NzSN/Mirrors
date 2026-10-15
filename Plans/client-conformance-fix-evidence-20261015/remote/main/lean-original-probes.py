import hashlib,json,os,shutil,subprocess
from pathlib import Path
root=Path('/home/jlc/Tools/mirrors-client-fixes-20261015')
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
probe=root/'source/lean-original-probes'
shutil.copytree(build/'postfix-probes/lean-probes',probe)
env={**os.environ,'PATH':'/home/jlc/.elan/toolchains/leanprover--lean4---v4.33.0/bin:/usr/bin:/bin',
     'ELAN_TOOLCHAIN':'leanprover/lean4:v4.33.0','LEAN_NUM_THREADS':'2','TMPDIR':'/tmp/fix-tests',
     'PYTHONDONTWRITEBYTECODE':'1'}
with (build/'logs/lean-original-build.log').open('wb') as output:
    subprocess.run(['lake','-Kjobs=2','build','closure-probe','tls-identity-probe'],cwd=probe,env=env,stdout=output,stderr=subprocess.STDOUT,timeout=300,check=True)
closure=subprocess.check_output([str(probe/'.lake/build/bin/closure-probe'),'fixtures'],cwd=probe,env=env,timeout=20)
(build/'lean-original-closure-fixed.jsonl').write_bytes(closure)
rows=[json.loads(line) for line in closure.splitlines()]
assert all(row['sourceCount']==2 and row['dependencyPresent'] for row in rows[:2])
assert all(row['decoded'] for row in rows[2:])
tls=root/'tmp/lean-original-probe-tls'
command=[str(root/'tools/bin/python3'),'run-tls-probe.py','--client-root',str(root/'source/MirrorLean'),'--output',str(tls)]
result=subprocess.run(command,cwd=probe,env=env,capture_output=True,timeout=120,check=True)
(build/'logs/lean-original-tls-fixed.stdout.jsonl').write_bytes(result.stdout)
(build/'logs/lean-original-tls-fixed.stderr.log').write_bytes(result.stderr)
tlsrows=[json.loads(line) for line in result.stdout.splitlines()]
assert next(row for row in tlsrows if row['peer']=='server' and row['case']=='default')['connected']
assert all(not row['connected'] for row in tlsrows if row['case'] in ['empty-name','wrong-name'] or row['peer']=='server-cn')
record={'status':'passed','originalMarkerClosureNowContainsDependency':True,'originalEmptyTlsIdentityNowRejected':True,
        'nullableDecoderNowAcceptsNull':True,'positiveSanControlPreserved':True,'tlsCommand':command,
        'tlsPosixOutputRoot':str(tls),'probeRoot':str(probe),'privateKeysTransferred':False,
        'binaries':{name:hashlib.sha256((probe/'.lake/build/bin'/name).read_bytes()).hexdigest() for name in ['closure-probe','tls-identity-probe']}}
(build/'lean-original-postfix.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2),flush=True)
