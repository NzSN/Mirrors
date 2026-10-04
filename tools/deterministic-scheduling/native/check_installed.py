#!/usr/bin/env python3
"""Exercise an installed native controller with checkout paths hidden."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--installed', type=Path, required=True)
    parser.add_argument('--prepared', type=Path, required=True)
    parser.add_argument('--oracles', type=Path, required=True)
    parser.add_argument('--worker-root', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args(); out = args.out.resolve(); out.mkdir(parents=True, exist_ok=False)
    installed = args.installed.resolve()
    build_acceptance = json.loads((installed/'work/acceptance.json').read_text())
    if not build_acceptance['nativeControllerCompiled'] or not build_acceptance['sourceHidden']:
        raise RuntimeError('requires successful installed source-hidden controller build')
    admitted = out/'admitted'; admitted.mkdir(); work = out/'work'; work.mkdir()
    for source, target in [(installed/'work/build/dpm_native','dpm_native'), (installed/'admitted/runtime/mirror','mirror'),
                           (installed/'admitted/native-generated/WriteSentryMBTMirror.generated.hpp','generated.hpp'),
                           (Path(__file__).with_name('check.py'),'check.py'),
                           (Path(__file__).with_name('terminate_peer.py'),'terminate_peer.py')]:
        shutil.copy2(source, admitted/target)
    shutil.copytree(args.prepared, admitted/'prepared'); shutil.copytree(args.oracles, admitted/'oracles')
    files = {str(p.relative_to(admitted)): sha(p) for p in sorted(admitted.rglob('*')) if p.is_file()}
    (out/'admitted-manifest.json').write_text(json.dumps(files, indent=2)+'\n')
    command = ['bwrap','--die-with-parent','--unshare-net','--ro-bind','/','/', '--tmpfs','/home','--tmpfs','/tmp',
        '--ro-bind',str(admitted),'/tmp/admitted','--bind',str(work),'/tmp/work','--proc','/proc','--dev','/dev',
        '--clearenv','--setenv','PATH','/usr/bin:/bin','--setenv','HOME','/tmp/work','--setenv','LC_ALL','C.UTF-8']
    # WSL's native process carrier uses this local Unix socket; no network endpoint is opened.
    for key in ['WSL_INTEROP','WSL_DISTRO_NAME']:
        if key in os.environ: command += ['--setenv',key,os.environ[key]]
    command += ['--chdir','/tmp/work','/usr/bin/python3','/tmp/admitted/check.py',
        '--runner','/tmp/admitted/dpm_native','--mirror','/tmp/admitted/mirror',
        '--prepared','/tmp/admitted/prepared','--oracles','/tmp/admitted/oracles',
        '--worker-root',str(args.worker_root.resolve()),'--generated','/tmp/admitted/generated.hpp','--out','/tmp/work/native']
    with (out/'run.log').open('w') as log: subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT, timeout=600)
    for rel, digest in files.items():
        if sha(admitted/rel) != digest: raise RuntimeError('admitted native input changed')
    acceptance = json.loads((work/'native/acceptance.json').read_text())
    if acceptance['status'] != 'passed' or len(acceptance['rows']) != 14 or len(acceptance['compatibilityControls']) != 3:
        raise RuntimeError('native installed gate incomplete')
    result = {'schema':'mirrors.dpm5-native-installed-acceptance/v1','status':'passed',
        'profile':'dpm-writesentry-two-operation/v1','sourceHidden':True,'networkNamespaceIsolated':True,
        'nativeRuns':14,'compatibilityControls':3,'installedBuildAcceptanceSha256':sha(installed/'work/acceptance.json'),
        'controllerSha256':sha(admitted/'dpm_native'),'nativeAcceptanceSha256':sha(work/'native/acceptance.json'),
        'admittedManifestSha256':sha(out/'admitted-manifest.json'),'fullProductionQualified':False,
        'hostScope':'WSL Linux controller and actual Windows workers via existing local interoperability carrier'}
    (out/'acceptance.json').write_text(json.dumps(result,indent=2)+'\n'); print(json.dumps(result,indent=2))


if __name__ == '__main__': main()
