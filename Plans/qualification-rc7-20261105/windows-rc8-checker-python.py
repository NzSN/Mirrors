import hashlib,json,os,subprocess,time
from pathlib import Path
stage=Path(r'D:\ModelMirrors\staging\qualification-rc7-20261105');source=stage/'Mirrors-rc8-f328e32'
job=stage/'runtime-inputs/native-test-job.exe';python=Path(r'D:\Programs\Python310\python.exe')
aliases=[]
for name in ['mirror','model_interface_gen','tla_frontend','mirrors_dpm','dpm_spec']:
 original=source/'.lake/build/bin'/(name+'.exe');alias=original.with_suffix('')
 if alias.exists():raise RuntimeError('retain previous alias')
 alias.write_bytes(original.read_bytes())
 aliases.append({'alias':str(alias),'executable':str(original),'sha256':hashlib.sha256(alias.read_bytes()).hexdigest()})
(stage/'logs/rc8-test-binary-aliases.json').write_text(json.dumps(aliases,indent=2),encoding='utf-8')
cases=[
 ('async-emitter',['tools/check-async-emitter.py']),
 ('cmake-consumer',['tools/check-cmake-consumer.py']),
 ('native-integer-maps',['tools/check-cpp-integer-maps.py','--prefix',str(stage/'cpp-prefix-rc8')]),
 ('suite-bundle',['tools/check-suite-bundle.py']),
 ('validate-closure',['tools/check-validate-closure.py']),
 ('trace-capture',['tools/check-trace-capture.py']),
 ('client-framing',['tools/check-client-framing.py']),
 ('validate-async',['tools/check-validate-async.py']),
 ('tlc-diagnostics',['-m','unittest','discover','-s','tools','-p','test_check_async_protocol.py']),
 ('required-tlc',['tools/check-async-protocol.py','--quick','--require-tools','--output',str(stage/'rc8-required-async-model')]),
 ('projected-corpus',['tools/model-interface-projected-corpus/test_check.py']),
 ('offline-tla',['-m','unittest','discover','-s','tools/tla-differential/tests']),
]
rows=[]
for name,args in cases:
 log=stage/'logs'/('rc8-python-'+name+'.log');began=time.time()
 try:
  with log.open('xb') as out:p=subprocess.run([str(job),str(python),*args],cwd=source,stdout=out,stderr=subprocess.STDOUT,timeout=1200)
  code=p.returncode
 except subprocess.TimeoutExpired:code='timeout'
 rows.append({'name':name,'exitCode':code,'seconds':round(time.time()-began,3),'logSha256':hashlib.sha256(log.read_bytes()).hexdigest()})
 (stage/'logs/rc8-python-checker-results.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
 print(name,code,flush=True)
print('Completed',len(rows),'passed',sum(r['exitCode']==0 for r in rows),flush=True)
raise SystemExit(0 if all(r['exitCode']==0 for r in rows) else 1)
