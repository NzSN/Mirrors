#!/usr/bin/env bash
set -euo pipefail
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
out="$fix_build/cpp-gate"
export PATH="$fix_root/tools/cpp-bin:$fix_root/tools/bin:/usr/bin:/bin"
export TMPDIR=/tmp/fix-tests
exec > >(tee "$out/logs/13-final-evidence.log") 2>&1
test "$(cat "$out/07-facade-matrix-attempt4.exit")" = 0
cd "$fix_root/source"
sha256sum -c "$out/manifests/source-files.sha256" > "$out/logs/final-source-hash-verification.log"
sha256sum "$out/manifests/source-files.sha256"
sha256sum -c "$out/manifests/system-bwrap-before.sha256"
sha256sum -c "$out/manifests/matrix-noop-attempt4.sha256"
printf '%s  %s\n' 6e06ecd3d4d2975a42db2a1822b2d28d9e382f6d5b9bf48fa36c6c9ce27fa77d \
  "$out/immutable/mirror" | sha256sum -c -
sha256sum /usr/bin/g++-12 /usr/bin/gcc-12 /usr/bin/openssl /usr/bin/ninja /usr/bin/meson \
  /home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/cmake-python/cmake/data/bin/cmake \
  /home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/cmake-python/cmake/data/bin/ctest \
  "$fix_root/tools/node/bin/node" "$fix_root/tools/bin/python3" \
  "$fix_root/tools/bwrap09/bin/bwrap" > "$out/manifests/final-tools.sha256"
cp "$fix_build/frozen-mirror-producer.json" "$out/manifests/frozen-mirror-producer.json"
python3 - "$out" <<'PY'
import collections,hashlib,json,sys
from pathlib import Path
out=Path(sys.argv[1])
rows=[json.loads(line) for line in (out/'cpp-failure-matrix-attempt4.jsonl').read_text().splitlines() if line]
scenarios=['correct','faulty','wrong-digest','error-adapter','error-cleanup','error-build','error-admission',
    'error-invoke-protocol','error-observe-protocol','error-invoke-transport','error-observe-transport',
    'error-invoke-application','error-observe-application','error-invoke-timeout','error-observe-timeout',
    'error-invoke-cancel','error-observe-cancel','error-spoof-admission','error-spoof-deadline']
expected={(mode,scenario) for mode in ['owned','attached'] for scenario in scenarios
          if not(mode=='owned' and scenario=='error-admission')}
actual=[(row['controlMode'],row['sut']) for row in rows]
assert len(rows)==37 and len(set(actual))==37 and set(actual)==expected
for row in rows:
    mode,scenario=row['controlMode'],row['sut']
    assert row['controlShutdown']=='confirmed'
    assert row['cleanupConfirmed']==(scenario!='error-cleanup')
    assert row['cleanup']==('failed' if scenario=='error-cleanup' else 'succeeded')
    if mode=='attached':assert row['secondSessionSurvived']
    if scenario=='error-cleanup':
        assert row['primaryFailure'] is None
        assert row['cleanupFailure']['origin']=='worker_application'
        assert row['cleanupFailure']['code']=='APPLICATION'
        assert row['publicErrorCode']=='mirrorgate.worker_application'
    if scenario in ['error-invoke-protocol','error-observe-protocol']:
        failure=row['primaryFailure'];operation='invoke' if 'invoke' in scenario else 'observe'
        assert failure['origin']=='sdk' and failure['code']=='CONTROL_DISCONNECTED'
        assert failure['family']=='worker_transport' and failure['stage']==''
        assert failure['operationId']==0 and failure['operation']==operation
        assert row['publicErrorCode']=='mirrorgate.CONTROL_DISCONNECTED'
        assert row['faultInjection']=={'kind':'uncorrelated_worker_response_id','operation':operation}
assert json.loads((out/'gate-processes-after-attempt4.json').read_text())==[]
summary={'status':'passed','requiredRows':37,'actualRows':len(rows),
    'controlModes':dict(collections.Counter(row['controlMode'] for row in rows)),
    'attachedSecondSessionSurvivalRows':sum(row['controlMode']=='attached' and row['secondSessionSurvived'] for row in rows),
    'intentionalCleanupFailureRows':sum(not row['cleanupConfirmed'] for row in rows),
    'brokerWrongIdRows':sum('faultInjection' in row for row in rows),
    'requiredFailureFamily':'SO7 worker transport/protocol combined family; exact observed SDK class retained',
    'sourceManifestSha256':hashlib.sha256((out/'manifests/source-files.sha256').read_bytes()).hexdigest(),
    'mirrorBinarySha256':hashlib.sha256((out/'immutable/mirror').read_bytes()).hexdigest(),
    'evidenceSha256':hashlib.sha256((out/'cpp-failure-matrix-attempt4.jsonl').read_bytes()).hexdigest(),
    'remainingOwnedGateProcesses':[],
    'modelCheckerLaunched':False,'newProtocolChannelAdded':False,
    'supersededAttempts':['attempt1 cleanup expectation','attempt2 subfamily overprecision',
                          'attempt3 mutable producer identity rejection'],
    'partialDiagnosticSelection':'attempt2-unaffected; 33 rows; not full acceptance',
    'caseInventory':[{'mode':mode,'scenario':scenario} for mode,scenario in sorted(actual)]}
(out/'matrix-final-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary),flush=True)
PY
echo CPP_GATE_FINAL_EVIDENCE_CURATED
