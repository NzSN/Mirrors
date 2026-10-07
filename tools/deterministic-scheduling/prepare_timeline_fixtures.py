#!/usr/bin/env python3
"""Copy byte-identical selected real receipts into the diagnostic regression corpus."""
from pathlib import Path
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'test/fixtures/deterministic-scheduling/timeline'

def main():
    OUT.mkdir(parents=True,exist_ok=False);rows=[]
    def copy(source,dest):
        raw=source.read_bytes();target=OUT/dest;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(raw)
        rows.append({'fixture':dest,'source':str(source.relative_to(ROOT)),'sha256':hashlib.sha256(raw).hexdigest()})
    for lang in ['ecma','rust']:
        root=ROOT/f'Plans/dpm-languages-evidence-20261005/{lang}-acceptance'
        for case in ['serial-ok','serial-mutate','serial-mutate-and-teardown-fail','serial-repeat']:
            copy(root/'counter'/case/'receipt.json',f'{lang}/counter/{case}/receipt.json')
    native=ROOT/'Plans/dpm-languages-evidence-20261005/ecma-acceptance/native'
    for case in ['00-stable-t1-normal-v3-ok','08-stable-t1-duplicate-sink-call-ok']:
        copy(native/case/'receipt.json',f'ecma/native/{case}/receipt.json')
    cpp=ROOT/'Plans/dpm2-dpm5-qualified-20261004/counter-replay/serial'
    for source in sorted(cpp.glob('*.receipt.json')):
        if json.loads(source.read_text()).get('schema')=='mirrors.scheduled-comparison/v1':copy(source,f'cpp/counter/{source.name}')
    copy(ROOT/'Plans/dpm2-dpm5-qualified-20261004/native-fresh.lock.json','native.lock.json')
    (OUT/'manifest.json').write_text(json.dumps({'schema':'mirrors.dpm-timeline-fixtures/v1','rows':rows},indent=2)+'\n')
    (OUT/'README.md').write_text('''# DPM timeline regression inputs\n\nSelected actual C++/Node/Rust receipts copied byte-for-byte from the accepted\nDPM records. These are diagnostic inputs, not new replay/qualification results.\nRegenerate with `python3 tools/deterministic-scheduling/prepare_timeline_fixtures.py`\ninto an absent output directory; do not edit frozen receipt bytes. The manifest\nbinds every original source path and copied digest. Malformed controls are\nconstructed in tests without changing these inputs.\n''')
    print('Copied',len(rows),'actual receipt inputs')

if __name__=='__main__':main()
