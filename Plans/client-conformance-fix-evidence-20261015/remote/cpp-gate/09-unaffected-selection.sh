#!/usr/bin/env bash
set -euo pipefail
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
out=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015/cpp-gate
export CPP_GATE_MATRIX_ATTEMPT=attempt2-unaffected
export CPP_GATE_HARNESS_OVERRIDE="$out/workflow/run-cpp-unaffected"
python3 - "$fix_root/source/MirrorGate" "$out" <<'PY'
import hashlib,json,sys
from pathlib import Path
gate,out=map(Path,sys.argv[1:])
original=(gate/'conformance/control-v1/run-cpp-failures').read_text()
lines=original.splitlines(keepends=True)
assert sum(line.startswith('gate_root=') for line in lines)==1
assert sum('error-invoke-protocol error-observe-protocol' in line for line in lines)==1
selected=[]
for line in lines:
    if line.startswith('gate_root='):selected.append(f'gate_root="{gate}"\n')
    elif 'error-invoke-protocol error-observe-protocol' not in line:selected.append(line)
selection=''.join(selected)
path=out/'workflow/run-cpp-unaffected'
path.write_text(selection)
record={'purpose':'Explicit partial diagnostic selection; not full37 C1 acceptance',
        'originalHarnessSha256':hashlib.sha256(original.encode()).hexdigest(),
        'selectorSha256':hashlib.sha256(selection.encode()).hexdigest(),
        'changes':['source-root literal because external selector lives outside checkout',
                   'omit only error-invoke-protocol and error-observe-protocol in both modes'],
        'expectedRows':33,'protocolClassificationStillFailed':True,
        'predicateOrDriverChanges':False}
(out/'manifests/unaffected-selection.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record),flush=True)
PY
exec bash "$out/workflow/07-facade-matrix.sh"
