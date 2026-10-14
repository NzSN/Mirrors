"""Retain raw validation authorities; keep compiled/development artifacts remote."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile

root=Path('/home/jlc/Tools/mirrors-dpm-followup-20261014')
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014')
gate=build/'installed-gate-final'
output=build/'curated-followup-final'
assert (build/'acceptance-phase.exit').read_text().strip()=='0'
assert (build/'local-gates-qualified-phase.exit').read_text().strip()=='0'
assert (build/'python-final-phase.exit').read_text().strip()=='0'
assert json.loads((gate/'acceptance.json').read_text())['status']=='passed'
output.mkdir()
def digest(path):
    value=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):value.update(chunk)
    return value.hexdigest()
def retain(path,name):
    assert path.is_file() and not path.is_symlink(),str(path)
    destination=output/name;destination.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(path,destination)
    assert digest(destination)==digest(path)
def write(name,value):
    path=output/name;path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
for path in sorted((build/'logs').iterdir()):
    if path.is_file():retain(path,'logs/'+path.name)
for path in sorted(build.iterdir()):
    if path.is_file() and path.suffix in ['.json','.exit']:
        retain(path,'remote-records/'+path.name)
for path in sorted((build/'workflow').iterdir()):
    if path.is_file() and path.suffix in ['.py','.sh','.cpp']:retain(path,'workflow/'+path.name)
retain(build/'source-manifest.json','source-manifest.json')
retain(build/'installation-manifest-final.json','installation-manifest.json')
for path in sorted((root/'cancellation-controls').rglob('*')):
    if path.is_file() and not path.is_symlink():retain(path,'cancellation/'+str(path.relative_to(root/'cancellation-controls')))
formats={'.json','.jsonl','.log','.tla','.txt','.sha256'}
for directory,prefix in [(gate,'installed'),(root/'public-controls','public-controls')]:
    for path in sorted(directory.rglob('*')):
        if not path.is_file() or path.is_symlink():continue
        relative=path.relative_to(directory);parts=relative.parts
        if any(part in ['devkit','build','bin','runtime','ecma','node_modules'] for part in parts[1:]):continue
        if path.suffix in formats or path.name=='counter_runner.py' or (parts[0]=='gate-helpers' and path.suffix=='.py') or (len(parts)==1 and path.suffix=='.cpp'):
            retain(path,prefix+'/'+str(relative))
for language in ['cpp','ecma','rust']:
    for directory,prefix in [(root/'installed-final','installed'),(build/'prepared-final','prepared'),(gate,'fresh-consumers')]:
        retain(directory/language/'project.json','input-projects/'+prefix+'/'+language+'.json')
manifest=json.loads((build/'installation-manifest-final.json').read_text())
actual={}
for path in sorted((root/'installed-final').rglob('*')):
    assert not path.is_symlink()
    if path.is_file():actual[str(path.relative_to(root/'installed-final'))]={'sha256':digest(path),'executable':bool(path.stat().st_mode&0o111)}
assert actual==manifest['files']
write('installation-verification.json',{'status':'verified','files':len(actual),
    'manifestSha256':digest(build/'installation-manifest-final.json'),'installedInventoryUnchanged':True})
binaries={}
def binary(path):
    if path.is_file():binaries[str(path)]={'sha256':digest(path),'bytes':path.stat().st_size,'resolvedPath':str(path.resolve())}
for path in sorted((build/'lean-build/bin').iterdir()):
    if path.is_file():binary(path)
for directory in [build/'sdk-cpp',build/'cpp-consumer']:
    for path in sorted(directory.rglob('*')):
        if path.is_file() and not path.is_symlink() and (path.name in ['libmirrorcpp.a','dpm_counter','dpm_explore'] or path.name.startswith('mirrorcpp_schedule') and not path.suffix):binary(path)
for language in ['cpp','ecma','rust']:
    for directory in [root/'installed-final'/language,gate/language]:
        for name in ['bin/mirrors-dpm','runtime/mirror','runner','explorer']:binary(directory/name)
for name in ['controlled-sync','controlled-sync-overrun']:binary(gate/name)
binary(build/'fixed-cpp-evidence')
binary(build/'rust-consumer-target/debug/mirrors-dpm-rust-consumer')
write('binary-identities.json',{'schema':'mirrors.dpm-followup-binary-identities/v1','storage':'remote-only','artifacts':binaries})
commands={'python':['python3','--version'],'lean':['/home/jlc/.elan/bin/lean','--version'],
 'rustc':['/home/jlc/.cargo/bin/rustc','--version'],'cxx':['/usr/bin/g++-12','--version'],
 'node':['/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/node/bin/node','--version'],
 'cmake':['/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/cmake-python/cmake/data/bin/cmake','--version']}
versions={}
for name,command in commands.items():
    completed=subprocess.run(command,cwd=root/'source/Mirrors',capture_output=True,text=True,check=True)
    versions[name]={'command':command,'stdout':completed.stdout,'stderr':completed.stderr}
write('environment.json',{'host':'windows-dev / Ubuntu WSL','versions':versions,'osRelease':Path('/etc/os-release').read_text(),
    'sourceRoot':str(root/'source'),'buildRoot':str(build),'installationRoot':str(root/'installed-final'),
    'modelCheckerExecuted':False,'localBuildsOrTests':False,'ownedPhaseMaximumNativeJobs':2,
    'installedGateRustBuildParallelism':'Cargo default in the unchanged gate sanitized environment; no overlap with other native builds'})
write('phase-results.json',{'exits':{path.name:int(path.read_text().strip()) for path in build.glob('*phase.exit')},
 'finalInstalled':'acceptance-phase.exit','finalNonModel':'local-gates-qualified-phase.exit','finalPython':'python-final-phase.exit',
 'superseded':{'lean-phase.exit':'Lean build/pure gates passed; one Python check found old copied helpers at executable-resolved D share. New D share was refreshed; final focused suite passed.'}})
archive=build/'curated-followup-final.tar.gz'
with tarfile.open(archive,'w:gz') as bundle:
    for path in sorted(output.rglob('*')):
        if path.is_file():bundle.add(path,arcname=str(path.relative_to(output)),recursive=False)
record={'archive':str(archive),'archiveSha256':digest(archive),'archiveBytes':archive.stat().st_size,
        'retainedFiles':sum(path.is_file() for path in output.rglob('*')),'binariesHashed':len(binaries),
        'installedFilesVerified':len(actual),'installationManifestSha256':digest(build/'installation-manifest-final.json')}
(build/'curated-transfer-final.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2),flush=True)
