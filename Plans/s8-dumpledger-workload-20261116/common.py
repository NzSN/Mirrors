"""S8 workload discovery with private raw receipts and explicit domain-only reads."""
import hashlib
import json
import os
import subprocess
from datetime import datetime,timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
PLAN=Path(__file__).resolve().parent
OUT=ROOT/'.golden-build/s8-dumpledger-workload-20261116'
SSH=['ssh','-F',str(Path.home()/'.ssh/config'),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=15','win10']


def identity(path):
    path=Path(path);digest=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):digest.update(chunk)
    return {'path':path.relative_to(ROOT).as_posix(),'bytes':path.stat().st_size,'sha256':digest.hexdigest()}


def write(path,value):
    with Path(path).open('x',encoding='utf-8') as stream:stream.write(json.dumps(value,indent=2)+'\n')


def run(name,argv,*,stdin=None,timeout=120,ok=(0,)):
    folder=OUT/'logs';folder.mkdir(mode=0o700,parents=True,exist_ok=True)
    OUT.chmod(0o700)
    stdout,stderr,receipt=[folder/(name+suffix) for suffix in ['.stdout','.stderr','.json']]
    if any(path.exists() for path in [stdout,stderr,receipt]):raise ValueError('retain prior attempt: '+name)
    started=datetime.now(timezone.utc).isoformat()
    with stdout.open('xb') as out,stderr.open('xb') as err:
        try:
            result=subprocess.run(list(map(str,argv)),input=stdin.encode() if stdin is not None else None,
                                  stdout=out,stderr=err,timeout=timeout)
            code=result.returncode
        except subprocess.TimeoutExpired:code=124
    write(receipt,{'argv':list(map(str,argv)),'startedAt':started,'finishedAt':datetime.now(timezone.utc).isoformat(),
                   'exitCode':code,'stdout':identity(stdout),'stderr':identity(stderr)})
    print(name+' exit='+str(code),flush=True)
    if code not in ok:raise ValueError(name+' failed; retained private logs')
    return stdout.read_text(encoding='utf-8-sig').strip()


def remote(name,script,timeout=120):
    return run(name,SSH+["powershell -NoProfile -NonInteractive -Command '$code = [Console]::In.ReadToEnd(); Invoke-Expression $code'"],stdin=script,timeout=timeout)
