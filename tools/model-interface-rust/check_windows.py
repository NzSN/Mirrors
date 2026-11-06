"""Native Rust generated binding tests: compiler helpers and SUT lifetimes differ.

Compile only inside an owned job, stopping compiler background helpers at its
exit. Execute each real unit-test binary in a separate strict job: any surviving
application descendant refuses acceptance. No process-name-wide cleanup occurs.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/evidence'))
from process_control import capture


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if os.name!='nt':raise ValueError('native Rust test job requires Windows')
    cargo=shutil.which('cargo');assert cargo
    work=ROOT/'.golden-build/model-interface-rust';manifest=work/'Cargo.toml'
    target=Path(os.environ['CARGO_TARGET_DIR']).resolve();target.mkdir(parents=True,exist_ok=True)
    details=[]
    code,timeout,unavailable,stdout,stderr,out_full,err_full,_=capture(
        [cargo,'test','--no-run','--message-format=json','--manifest-path',str(manifest)],
        ROOT,1800,16*1024*1024,stop_descendants_on_exit=True,cleanup_details=details)
    (work/'windows-compile.stdout.jsonl').write_bytes(stdout)
    (work/'windows-compile.stderr.log').write_bytes(stderr)
    sys.stderr.buffer.write(stderr);sys.stderr.buffer.flush()
    if code or timeout or unavailable or out_full or err_full:raise ValueError('native Rust compilation failed or was incomplete')
    binaries=[]
    for line in stdout.splitlines():
        item=json.loads(line)
        if item.get('reason')=='compiler-artifact' and item.get('profile',{}).get('test') and item.get('executable'):
            path=Path(item['executable']).resolve()
            if not path.is_relative_to(target) or not path.is_file():raise ValueError('test executable escapes the owned target tree')
            binaries.append(path)
    if not binaries or len(set(binaries))!=len(binaries):raise ValueError('missing or duplicate Rust test executable')
    result=[]
    for index,binary in enumerate(binaries):
        before=digest(binary);owned=[]
        code,timeout,unavailable,out,err,out_full,err_full,_=capture(
            [str(binary)],ROOT,300,4*1024*1024,forward=True,require_clean_exit=True,cleanup_details=owned)
        (work/f'windows-unit-{index}.stdout.log').write_bytes(out)
        (work/f'windows-unit-{index}.stderr.log').write_bytes(err)
        if code or timeout or unavailable or out_full or err_full or digest(binary)!=before:
            raise ValueError('native Rust unit execution failed or was incomplete')
        result.append({'binary':str(binary),'sha256':before,'exitCode':code,'cleanup':owned})
    # Rustdoc's generated examples are still run through Cargo. Any future
    # executable doctest runs retain the same strict descendant check.
    doc=[]
    code,timeout,unavailable,out,err,out_full,err_full,_=capture(
        [cargo,'test','--doc','--manifest-path',str(manifest)],ROOT,300,4*1024*1024,
        forward=True,require_clean_exit=True,cleanup_details=doc)
    (work/'windows-doc.stdout.log').write_bytes(out);(work/'windows-doc.stderr.log').write_bytes(err)
    if code or timeout or unavailable or out_full or err_full:raise ValueError('native Rust documentation execution failed or was incomplete')
    (work/'windows-result.json').write_text(json.dumps({'compiler':details,'unitExecutions':result,'doc':doc},indent=2)+'\n')
    print('NATIVE RUST GENERATED BINDING EXECUTION GREEN (compiler helpers and strict test jobs cleaned)')


if __name__=='__main__':main()
