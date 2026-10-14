#!/usr/bin/env python3
"""Verified, atomic, no-overwrite installation of prepared DPM projects."""
import sys
if __name__ == '__main__' and not (sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode):
    print('DPM Python entrypoint requires python3 -I -S -B', file=sys.stderr)
    raise SystemExit(2)

import argparse
import types
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid
# Generated helper pins; refresh_host_identity.py updates these before packaging.
_HELPER_SHA256 = {'dpm_host': '250f79d558d2277fe7849fb0b77f91c41b8b2d5d5cdb6618618b97c134e63ff6'}  # refreshed helper identities

def _load_helper(name):
    source = Path(__file__).with_name(name + '.py')
    raw = source.read_bytes()
    if len(raw) > 1048576 or hashlib.sha256(raw).hexdigest() != _HELPER_SHA256.get(name):
        raise RuntimeError('DPM helper differs from trusted tool: ' + name)
    module = types.ModuleType(name)
    module.__file__ = str(source)
    sys.modules[name] = module
    exec(compile(raw, str(source), 'exec'), module.__dict__)
    return module

_host = _load_helper('dpm_host')
Refusal, regular, sha, strict, write = (_host.Refusal, _host.regular, _host.sha, _host.strict, _host.write)


def inventory(root):
    rows = {}
    for file in sorted(root.rglob('*')):
        if file.is_symlink(): raise Refusal('symlink in installation tree')
        if file.is_file():
            regular(file)
            rows[str(file.relative_to(root))] = {'sha256':sha(file),'executable':bool(file.stat().st_mode & 0o111)}
    return rows


def verify(root, rows):
    if inventory(root) != rows: raise Refusal('installation inventory differs')


def no_replace(source, destination):
    libc = ctypes.CDLL(None, use_errno=True)
    if not hasattr(libc,'renameat2'): raise Refusal('atomic no-overwrite rename unavailable')
    libc.renameat2.argtypes=[ctypes.c_int,ctypes.c_char_p,ctypes.c_int,ctypes.c_char_p,ctypes.c_uint]
    if libc.renameat2(-100,os.fsencode(source),-100,os.fsencode(destination),1)!=0:
        code=ctypes.get_errno();raise OSError(code,os.strerror(code))


def main():
    parser=argparse.ArgumentParser()
    sub=parser.add_subparsers(dest='operation',required=True)
    manifest=sub.add_parser('manifest');manifest.add_argument('--source',type=Path,required=True);manifest.add_argument('--out',type=Path,required=True)
    install=sub.add_parser('install');install.add_argument('--source',type=Path,required=True)
    install.add_argument('--manifest',type=Path,required=True);install.add_argument('--manifest-sha256',required=True)
    install.add_argument('--dest',type=Path,required=True)
    args=parser.parse_args();source=args.source.absolute()
    if args.operation=='manifest':
        rows=inventory(source)
        projects=[]
        for path in sorted(source.glob('*/project.json')):
            project=str(path.relative_to(source));projects.append({'path':project,'sha256':sha(path)})
        if not projects: raise Refusal('no prepared DPM projects')
        write(args.out,{'schema':'mirrors.dpm-installation/v1','files':rows,'projects':projects})
        print(sha(args.out));return
    if sha(args.manifest)!=args.manifest_sha256: raise Refusal('installation manifest differs from selected digest')
    manifest=strict(args.manifest,16*1024*1024)
    if set(manifest)!= {'schema','files','projects'} or manifest['schema']!='mirrors.dpm-installation/v1':
        raise Refusal('unsupported installation manifest')
    verify(source,manifest['files'])
    for project in manifest['projects']:
        if set(project)!= {'path','sha256'} or project['path'] not in manifest['files'] or manifest['files'][project['path']]['sha256']!=project['sha256']:
            raise Refusal('project not bound to installation')
    destination=args.dest.absolute()
    if destination.exists() or destination.is_symlink(): raise Refusal('existing destination preserved')
    destination.parent.mkdir(parents=True,exist_ok=True)
    if any(p.is_symlink() for p in [destination.parent,*destination.parent.parents]): raise Refusal('symlink destination parent')
    staging=destination.parent/('.'+destination.name+'.staging-'+uuid.uuid4().hex)
    try:
        shutil.copytree(source,staging)
        verify(staging,manifest['files'])
        for selected in manifest['projects']:
            project=staging/selected['path'];binary=project.parent/'bin/mirrors-dpm'
            subprocess.run([str(binary),'doctor','--project',str(project),'--project-sha256',selected['sha256']],
                           check=True,timeout=60,stdout=subprocess.DEVNULL)
        verify(staging,manifest['files']);verify(source,manifest['files'])
        no_replace(staging,destination)
    finally:
        if staging.exists(): shutil.rmtree(staging)
    verify(destination,manifest['files'])
    print(json.dumps({'schema':'mirrors.dpm-installation-result/v1','status':'installed',
                      'manifestSha256':args.manifest_sha256,'destination':str(destination),'projects':manifest['projects']}))


if __name__=='__main__':
    try:main()
    except (OSError,Refusal,ValueError,subprocess.SubprocessError) as error:
        print('DPM installation refused: '+str(error),file=sys.stderr);raise SystemExit(2)
