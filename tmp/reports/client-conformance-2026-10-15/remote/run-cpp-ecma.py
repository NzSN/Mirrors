import hashlib,json,os,subprocess
from pathlib import Path
root=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-conformance-20261015')
old=Path('/home/jlc/Tools/mirrors-dpm-remediation-20261013/source/MirrorCPP')
fixed=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014')
prefix=Path('/home/jlc/Tools/mirrors-dpm-remediation-20261013/cpp-prefix')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
selection=json.loads((root/'cpp-probes/cpp-source-selection.json').read_text())
frozen=json.loads((fixed/'frozen-inputs.json').read_text())['selectedChanges']
fixed_rows={row['path']:row['sha256'] for row in frozen if row['repository']=='MirrorCPP'}
source_rows={}
for name,digest in selection['files'].items():
    original=old/name
    matches=original.is_file() and sha(original)==digest
    fixed_match=fixed_rows.get(name)==digest
    assert matches or fixed_match,(name,digest)
    source_rows[name]={'sha256':digest,'matchesOriginalQualifiedSource':matches,'matchesFixedSourceInput':fixed_match}
library=fixed/'sdk-cpp/libmirrorcpp.a'
fixture=root/'cpp-probes/CounterMirror.generated.hpp'
assert sha(fixture)=='47ae61359be7875e580817a5d8436acaba00a59b7cae44f7ded1e2e7efaaa5d0'
assert sha(root/'cpp-probes/probe.cpp')=='c0ab7c3d9854d4e08a68945c2925cf13fb61a0d2ee2659b444028e718b72975e'
command=['/usr/bin/g++-12','-std=c++23','-O0','-Wall','-Wextra','-Werror',
    '-I'+str(old/'include'),'-I'+str(prefix/'include'),'-I'+str(root/'cpp-probes'),
    str(root/'cpp-probes/probe.cpp'),str(library),'-lssl','-lcrypto','-pthread','-o',str(root/'cpp-probes/probe')]
compile_result=subprocess.run(command,capture_output=True,timeout=120)
(root/'logs/cpp-build.stdout.log').write_bytes(compile_result.stdout)
(root/'logs/cpp-build.stderr.log').write_bytes(compile_result.stderr)
record={'head':selection['head'],'sourceVerification':source_rows,'command':command,
        'compiler':subprocess.check_output(['/usr/bin/g++-12','--version'],text=True),
        'library':{'path':str(library),'sha256':sha(library)},'fixtureSha256':sha(fixture),
        'probeSourceSha256':sha(root/'cpp-probes/probe.cpp'),'compileExit':compile_result.returncode}
(root/'cpp-provenance.json').write_text(json.dumps(record,indent=2)+'\n')
assert compile_result.returncode==0,compile_result.stderr.decode()
run=subprocess.run([str(root/'cpp-probes/probe')],capture_output=True,timeout=15)
(root/'cpp-result.json').write_bytes(run.stdout);(root/'logs/cpp.stderr.log').write_bytes(run.stderr)
record.update(runExit=run.returncode,probeBinarySha256=sha(root/'cpp-probes/probe'))
(root/'cpp-provenance.json').write_text(json.dumps(record,indent=2)+'\n')
assert run.returncode==0,run.stderr.decode()
node=Path('/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/node/bin/node')
sdk=Path('/home/jlc/Tools/mirrors-dpm-remediation-20261013/ecma/node_modules/mirrorecma')
command=[str(node),str(root/'ecma-probes/invalid-pair.mjs'),str(sdk)]
runs=[subprocess.run(command,capture_output=True,timeout=15) for _ in range(2)]
assert all(result.returncode==0 for result in runs)
assert runs[0].stdout==runs[1].stdout
(root/'ecma-result.json').write_bytes(runs[0].stdout)
(root/'logs/ecma.stderr.log').write_bytes(runs[0].stderr)
dist={str(path.relative_to(sdk)):sha(path) for path in (sdk/'dist').glob('*.js')}
(root/'ecma-provenance.json').write_text(json.dumps({'command':command,'exit':0,'runs':2,
    'identicalOutputBytes':True,'nodeSha256':sha(node),'distJavaScriptSha256':dist,
    'sourceSelection':'ecma-source-selection.json','allCurrentSourceFilesMatchQualifiedSource':True},indent=2)+'\n')
print(json.dumps({'cppExit':run.returncode,'ecmaExit':0,'ecmaRepeatedBytesIdentical':True,'cppSourceHeadersVerified':len(source_rows)}),flush=True)
