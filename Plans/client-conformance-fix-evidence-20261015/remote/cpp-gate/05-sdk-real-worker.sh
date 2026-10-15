#!/usr/bin/env bash
set -euo pipefail
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
out="$fix_build/cpp-gate"
gate="$fix_root/source/MirrorGate"
export MIRRORGATE_NODE_RUNTIME_ROOT="$fix_root/tools/node"
trap 'result=$?; printf "%s\n" "$result" > "$out/05-sdk-real-worker.exit"' EXIT
exec > >(tee "$out/logs/05-sdk-real-worker.log") 2>&1
date -u +%FT%TZ
id
grep -E '^(CapEff|CapAmb):' /proc/self/status
readlink /proc/self/ns/mnt
/usr/bin/bwrap --version
sha256sum /usr/bin/bwrap "$fix_root/tools/node/bin/node"
node --version
python3 --version
test "$(id -u)" = 1000
test "$(node --version)" = v24.15.0
test "$(/usr/bin/bwrap --version)" = 'bubblewrap 0.9.0'
scratch="$(mktemp -d "$TMPDIR/sdk-real.XXXXXX")"
daemon_pid=""
cleanup() {
  if [[ -n "$daemon_pid" ]]; then
    kill "$daemon_pid" 2>/dev/null || true
    wait "$daemon_pid" 2>/dev/null || true
  fi
  rm -rf "$scratch"
}
trap 'result=$?; cleanup; printf "%s\n" "$result" > "$out/05-sdk-real-worker.exit"' EXIT
mkdir -p "$scratch/submissions/correct" "$scratch/submissions/faulty"
cp "$gate/runtimes/node/examples/counter.mjs" "$scratch/submissions/correct/adapter.mjs"
cp "$gate/runtimes/node/examples/faulty-counter.mjs" "$scratch/submissions/faulty/adapter.mjs"
cp "$gate/runtimes/node/examples/counter.mjs" "$scratch/submissions/faulty/counter.mjs"
policy="$scratch/policy.json"
python3 "$gate/tests/control_policy_fixture.py" "$policy" "$scratch/submissions" --adapter-entry adapter.mjs
e2e="$out/sdk-build/mirrorgate_control_e2e"
manifest="$gate/conformance/manifests/counter.json"
timeout 45s "$e2e" stdio "$gate/bin/mirrorgate" "$policy" "$manifest" correct node-v1 2
timeout 45s "$e2e" stdio "$gate/bin/mirrorgate" "$policy" "$manifest" faulty node-v1 1
mkdir "$scratch/control"
chmod 0700 "$scratch/control"
socket="$scratch/control/control.sock"
"$gate/bin/mirrorgate" control --unix-socket "$socket" --policy-file "$policy" &
daemon_pid=$!
for _ in {1..200}; do [[ -S "$socket" ]] && break; sleep 0.01; done
test -S "$socket"
timeout 45s "$e2e" unix "$socket" "$policy" "$manifest" correct node-v1 2
kill -0 "$daemon_pid"
echo CPP_GATE_SDK_REAL_NODE_WORKERS_PASSED
