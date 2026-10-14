"""Curate completed remote evidence; retain executable artifacts by hash only."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import tarfile

handoff=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013')
build=handoff/'build'
root=Path('/home/jlc/Tools/mirrors-dpm-remediation-20261013')
source=root/'source'
gate=build/'installed-gate-final'
output=build/'curated-evidence-20261014'
assert (build/'acceptance-phase.exit').read_text().strip()=='0'
assert (build/'local-gates-qualified-phase.exit').read_text().strip()=='0'
assert json.loads((gate/'acceptance.json').read_text())['status']=='passed'
output.mkdir(exist_ok=False)
def digest(path):
    result=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):result.update(chunk)
    return result.hexdigest()
def row(path):
    return {'sha256':digest(path),'bytes':path.stat().st_size,'executable':bool(path.stat().st_mode&0o111)}
def write(name,value):
    path=output/name;path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
def retain(path,name):
    assert path.is_file() and not path.is_symlink(),str(path)
    destination=output/name;destination.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(path,destination)
    assert digest(path)==digest(destination),str(path)
selection=json.loads((handoff/'dpm-local-source-selection.json').read_text())
transfer=json.loads((source/'source-transfer.json').read_text())
current={};deltas=[];count=0
for repository in transfer['repositories']:
    name=repository['name'];current[name]={}
    for relative,expected in repository['files'].items():
        path=source/name/relative
        assert path.is_file() and not path.is_symlink(),str(path)
        actual=row(path);current[name][relative]=actual;count+=1
        if actual!=expected:deltas.append({'repository':name,'path':relative,'transferred':expected,'qualified':actual})
allowed={('Mirrors','Shell/Dpm/HostIdentity.lean'),('Mirrors','tools/deterministic-scheduling/tests/test_dpm_host.py')}
assert all((item['repository'],item['path']) in allowed for item in deltas),deltas
repositories=[]
for repository in selection['repositories']:
    name=repository['name'];files={}
    for relative,local in repository['workingFiles'].items():
        remote_path=source/name/relative
        remote=row(remote_path) if remote_path.is_file() else None
        matches=remote is not None and all(local[key]==remote[key] for key in ['sha256','bytes','executable'])
        if local['scope']=='implementation':assert matches,(name,relative,local,remote)
        files[relative]={**local,'remoteSource':remote,'matchesQualifiedSnapshot':matches}
    repositories.append({'name':name,'baseHead':repository['baseHead'],'localPath':repository['localPath'],
                         'qualifiedRemoteRoot':str(source/name),'workingFiles':files})
retain(source/'source-transfer.json','source-transfer.json')
write('qualified-source-verification.json',{'schema':'mirrors.dpm-qualified-source-verification/v1',
      'status':'verified','transferredFiles':count,'sourceTransferSha256':digest(source/'source-transfer.json'),
      'changesAfterTransfer':deltas,'qualifiedSources':current})
write('source-manifest.json',{'schema':'mirrors.dpm-remediation-source-manifest/v1','repositories':repositories,
      'implementationParity':'all selected working implementation files match qualified remote sources',
      'documentationScope':'snapshot metadata; final acceptance documentation recorded separately',
      'excluded':['unrelated .projectile-cache.eld','MirrorECMA .work/','dated evidence contents','build/cache outputs']})
retain(build/'installation-manifest-final.json','installation-manifest.json')
retain(build/'input-verification.json','remote-input-verification.json')
for path in sorted((build/'logs').iterdir()):
    if path.is_file():retain(path,'logs/'+path.name)
for path in sorted(build.iterdir()):
    if path.is_file() and path.suffix in ['.json','.sha256','.exit'] and path.name not in ['installation-manifest-final.json','input-verification.json']:
        retain(path,'remote-records/'+path.name)
for path in sorted(handoff.iterdir()):
    if path.is_file() and path.suffix in ['.py','.sh'] and path.name!='independent-review.py':
        retain(path,'workflow/'+path.name)
# A runtime tree has thousands of development-kit files. Retain operation records
# and selected input authorities, not those source/devkit/binary copies.
formats={'.json','.jsonl','.log','.tla','.txt','.sha256'}
for path in sorted(gate.rglob('*')):
    if not path.is_file() or path.is_symlink():continue
    relative=path.relative_to(gate);parts=relative.parts
    if parts[0] in ['cpp','ecma','rust'] and len(parts)>1 and parts[1] in ['devkit','build','bin','runtime','ecma']:
        continue
    if path.suffix in formats or (parts[0]=='gate-helpers' and path.suffix=='.py') or (len(parts)==1 and path.suffix=='.cpp'):
        retain(path,'installed/'+str(relative))
for language in ['cpp','ecma','rust']:
    retain(root/'installed-final'/language/'project.json','input-projects/installed/'+language+'.json')
    retain(build/'prepared-final'/language/'project.json','input-projects/prepared/'+language+'.json')
    retain(gate/language/'project.json','input-projects/fresh-consumers/'+language+'.json')
# Hash the executed Lean programs, the native SDK/test programs, and actual
# original/fresh application runtimes. Large artifacts stay on the remote host.
binaries={}
def binary(path):
    if path.is_file():binaries[str(path)]={**row(path),'resolvedPath':str(path.resolve())}
for path in sorted((build/'lean-build/bin').iterdir()):
    if path.is_file():binary(path)
for directory in [build/'sdk-cpp',build/'cpp-consumer']:
    for path in sorted(directory.rglob('*')):
        if path.is_file() and not path.is_symlink() and (path.name in ['libmirrorcpp.a','dpm_counter','dpm_explore'] or path.name.startswith('mirrorcpp_schedule') and path.suffix==''):
            binary(path)
for language in ['cpp','ecma','rust']:
    for base in [root/'installed-final'/language,gate/language]:
        for relative in ['bin/mirrors-dpm','runtime/mirror','runner','explorer']:
            binary(base/relative)
for name in ['controlled-sync','controlled-sync-overrun']:
    binary(gate/name)
binary(build/'rust-consumer-target/debug/mirrors-dpm-rust-consumer')
write('binary-identities.json',{'schema':'mirrors.dpm-remote-binary-identities/v1','storage':'remote-only','artifacts':binaries})
versions={}
commands={'uname':['uname','-a'],'python':['python3','--version'],
          'node':['/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/node/bin/node','--version'],
          'cmake':['/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/cmake-python/cmake/data/bin/cmake','--version'],
          'cxx':['/usr/bin/g++-12','--version'],'rustc':['/home/jlc/.cargo/bin/rustc','--version'],
          'lean':['/home/jlc/.elan/bin/lean','--version']}
for name,command in commands.items():
    result=subprocess.run(command,cwd=source/'Mirrors',capture_output=True,text=True,check=True)
    versions[name]={'command':command,'stdout':result.stdout,'stderr':result.stderr}
write('environment.json',{'schema':'mirrors.dpm-qualified-environment/v1','host':'windows-dev Ubuntu WSL',
      'osRelease':Path('/etc/os-release').read_text(),'versions':versions,'modelCheckerExecuted':False,
      'sourceRoot':str(source),'buildRoot':str(build),'installedRoot':str(root/'installed-final'),
      'runtimeTrust':'OS standard library, extension modules and loader remain trusted prerequisites'})
phases={path.name:int(path.read_text().strip()) for path in build.glob('*phase.exit')}
write('phase-results.json',{'schema':'mirrors.dpm-remediation-phases/v1','exits':phases,
      'finalInstalled':'acceptance-phase.exit','finalNonModel':'local-gates-qualified-phase.exit',
      'supersededNonModelAttempts':{
          'local-gates-phase.exit':'symlink build-root layout incompatible with strict filesystem checks',
          'local-gates-final-phase.exit':'insufficient Linux root space while copying a launcher fixture',
          'local-gates-retry-phase.exit':'missing pinned jsonschema dependency',
          'local-gates-complete-phase.exit':'missing pinned offline acquisition archive fixture cache'},
      'additionalSetupDiagnostics':'original logs retained; only explicitly passing final phases receive acceptance credit'})
archive=build/'curated-evidence-20261014.tar.gz'
with tarfile.open(archive,'w:gz') as tar:
    for path in sorted(output.rglob('*')):
        if path.is_file():tar.add(path,arcname=str(path.relative_to(output)),recursive=False)
print(json.dumps({'directory':str(output),'archive':str(archive),'archiveSha256':digest(archive),
                  'archiveBytes':archive.stat().st_size,'retainedFiles':sum(path.is_file() for path in output.rglob('*')),
                  'sourceFilesVerified':count,'selectedWorkingFiles':sum(len(r['workingFiles']) for r in repositories),
                  'binariesHashed':len(binaries),'installationManifestSha256':digest(build/'installation-manifest-final.json')},indent=2),flush=True)
