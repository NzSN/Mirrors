#!/usr/bin/env bash
set -euo pipefail
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
out=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015/cpp-gate
gate="$fix_root/source/MirrorGate"
export PATH="$fix_root/tools/cpp-bin:$fix_root/tools/bin:/usr/bin:/bin"
export TMPDIR=/tmp/fix-tests MIRRORGATE_NODE_RUNTIME_ROOT="$fix_root/tools/node"
exec > >(tee "$out/logs/10-broker-snapshot-diagnostic.log") 2>&1
python3 - "$gate" "$out" <<'PY'
import hashlib,json,shlex,subprocess,sys
from pathlib import Path
gate,out=map(Path,sys.argv[1:])
source=gate/'integrations/mirrorcpp/counter_driver.cpp'
original=source.read_text()
needle='        require(mirrorgate::failure_family_name(failure->family) == expected_family,'
assert original.count(needle)==1
insertion='''        std::cerr << "RAW_BROKER_FAULT_SNAPSHOT=" << mirrorgate::Json{
            {"scenario", expected_outcome}, {"origin", mirrorgate::failure_origin_name(failure->origin)},
            {"family", mirrorgate::failure_family_name(failure->family)}, {"code", failure->code},
            {"stage", failure->stage}, {"operationId", failure->operation_id},
            {"operation", failure->operation}, {"message", failure->message},
            {"publicCode", result.error().code.value_or("")}}.dump() << '\\n';
'''
diagnostic=original.replace(needle,insertion+needle)
src=out/'workflow/counter-driver-snapshot-diagnostic.cpp'
src.write_text(diagnostic)
build=out/'matrix-build'
command=subprocess.check_output(['ninja','-C',str(build),'-t','commands',
    'CMakeFiles/mirrorgate_mirrorcpp_counter.dir/counter_driver.cpp.o'],text=True).strip().splitlines()[-1]
args=shlex.split(command)
obj=out/'artifacts/counter-driver-snapshot-diagnostic.o'
args[args.index('-o')+1]=str(obj)
args[args.index('-c')+1]=str(src)
print('DIAGNOSTIC_COMPILE='+shlex.join(args),flush=True)
subprocess.run(args,cwd=build,check=True)
binary=out/'artifacts/counter-driver-snapshot-diagnostic'
link=[args[0],'-std=c++23',str(obj),str(build/'libmirrorgate_mirrorcpp_orchestration.a'),
      str(build/'mirrorgate-sdk-build/libmirrorgate_cpp.a'),str(build/'mirrorcpp-build/libmirrorcpp.a'),
      '-pthread','-o',str(binary)]
print('DIAGNOSTIC_LINK='+shlex.join(link),flush=True)
subprocess.run(link,check=True)
manifest={'purpose':'Output-only diagnostic; original assertions intentionally still fail',
    'sourceSha256':hashlib.sha256(original.encode()).hexdigest(),
    'diagnosticSourceSha256':hashlib.sha256(diagnostic.encode()).hexdigest(),
    'binarySha256':hashlib.sha256(binary.read_bytes()).hexdigest(),
    'predicateChanges':False}
(out/'manifests/broker-snapshot-diagnostic.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest),flush=True)
PY
scratch="$(mktemp -d "$TMPDIR/broker-snapshot.XXXXXX")"
daemon_pid=""
cleanup() {
  if [[ -n "$daemon_pid" ]]; then kill "$daemon_pid" 2>/dev/null || true; wait "$daemon_pid" 2>/dev/null || true; fi
  rm -rf "$scratch"
}
trap cleanup EXIT
mkdir -p "$scratch/submissions/observer"
cp "$gate/runtimes/node/examples/counter.mjs" "$scratch/submissions/observer/adapter.mjs"
: > "$out/broker-snapshot-diagnostic.jsonl"
for mode in owned attached; do
  for operation in invoke observe; do
    scenario="error-$operation-protocol"
    relative="$mode-$operation"
    mkdir "$scratch/submissions/$relative"
    cp "$gate/conformance/control-v1/failure-counter.mjs" "$scratch/submissions/$relative/adapter.mjs"
    printf 'export default "%s";\n' "$scenario" > "$scratch/submissions/$relative/scenario.mjs"
    policy="$scratch/$relative.policy.json"
    python3 "$gate/tests/control_policy_fixture.py" "$policy" "$scratch/submissions" \
      --policy-id accept.cpp.failure --adapter-id mirrorgate/node-v1 --target-profile mirrorcpp-v1 \
      --runtime node --artifact-entry adapter.mjs >/dev/null
    endpoint="$gate/bin/mirrorgate"
    unset MIRRORGATE_CPP_SECOND_SESSION
    if [[ "$mode" == attached ]]; then
      mkdir "$scratch/socket-$operation"
      chmod 0700 "$scratch/socket-$operation"
      endpoint="$scratch/socket-$operation/control.sock"
      "$gate/bin/mirrorgate" control --unix-socket "$endpoint" --policy-file "$policy" &
      daemon_pid=$!
      for _ in {1..200}; do [[ -S "$endpoint" ]] && break; sleep 0.01; done
      test -S "$endpoint"
      export MIRRORGATE_CPP_SECOND_SESSION=1
    fi
    set +e
    timeout 45s "$out/artifacts/counter-driver-snapshot-diagnostic" "$mode" "$endpoint" "$policy" \
      accept.cpp.failure "$gate/conformance/manifests/counter.json" "$relative" node-v1 \
      "$fix_root/source/Mirrors/.lake/build/bin/mirror" "$fix_root/source/Mirrors/specs/Counter.tla" \
      "$gate/conformance/control-v1/counter.itf.json" "$scenario" \
      > "$out/logs/diagnostic-$relative.stdout" 2> "$out/logs/diagnostic-$relative.stderr"
    result=$?
    set -e
    cat "$out/logs/diagnostic-$relative.stderr"
    test "$result" = 1
    python3 - "$out" "$relative" "$mode" "$result" <<'PY'
import json,sys
from pathlib import Path
out=Path(sys.argv[1]); relative,mode,code=sys.argv[2:]
prefix='RAW_BROKER_FAULT_SNAPSHOT='
lines=(out/f'logs/diagnostic-{relative}.stderr').read_text().splitlines()
record=json.loads(next(line[len(prefix):] for line in lines if line.startswith(prefix)))
record.update({'controlMode':mode,'exitCode':int(code),'acceptance':False,'predicateChanged':False})
with (out/'broker-snapshot-diagnostic.jsonl').open('a') as stream:stream.write(json.dumps(record)+'\n')
PY
    if [[ "$mode" == attached ]]; then
      kill "$daemon_pid"; wait "$daemon_pid" 2>/dev/null || true; daemon_pid=""
    fi
  done
done
echo BROKER_RAW_SNAPSHOTS_RETAINED_NO_ACCEPTANCE_CLAIM
