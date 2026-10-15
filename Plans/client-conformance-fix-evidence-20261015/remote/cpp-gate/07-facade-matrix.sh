#!/usr/bin/env bash
set -euo pipefail
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
out="$fix_build/cpp-gate"
attempt="${CPP_GATE_MATRIX_ATTEMPT:-attempt4}"
[[ "$attempt" =~ ^[a-zA-Z0-9-]+$ ]]
export MIRRORCPP_ROOT="$fix_root/source/MirrorCPP"
export MIRRORS_ROOT="$fix_root/source/Mirrors"
export MIRROR_BIN="$out/immutable/mirror"
export MIRRORCPP_DEPENDENCY_CACHE=/home/jlc/Tools/mirrors-dpm-remediation-20261013/prerequisites/cpp-dependencies
export MIRRORGATE_NODE_RUNTIME_ROOT="$fix_root/tools/node"
export MIRRORGATE_CPP_BUILD_JOBS=2
export MIRRORGATE_CPP_FAILURE_BUILD_DIR="$out/matrix-build"
export MIRRORGATE_CPP_FAILURE_EVIDENCE="$out/cpp-failure-matrix-$attempt.jsonl"
export CMAKE_GENERATOR=Ninja
export TMPDIR=/tmp/fix-tests
export PATH="$fix_root/tools/cpp-bin:$fix_root/tools/bin:/usr/bin:/bin"
export CC=/usr/bin/gcc-12 CXX=/usr/bin/g++-12
export CPP_GATE_ARTIFACT_ATTEMPT="$attempt"
mkdir -p "$out/artifacts"
cat > "$fix_root/tools/cpp-bin/cmake" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015/cpp-gate
args=("$@")
if [[ ${1-} == --build && ${!#} == --parallel ]]; then args+=(2); fi
printf '%q ' /home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/cmake-python/cmake/data/bin/cmake "${args[@]}" >> "$out/logs/cmake-commands.log"
printf '\n' >> "$out/logs/cmake-commands.log"
/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/cmake-python/cmake/data/bin/cmake "${args[@]}"
if [[ ${1-} == --build ]]; then
  for name in mirrorgate_mirrorcpp_counter mirrorgate_mirrorcpp_receipt_tests; do
    if [[ -f "$2/$name" ]]; then
      destination="$out/artifacts/${CPP_GATE_ARTIFACT_ATTEMPT:?}-$name"
      cp "$2/$name" "$destination"
      sha256sum "$destination" >> "$out/manifests/matrix-artifacts.sha256"
      cp "$2/CMakeCache.txt" "$out/manifests/integration-${CPP_GATE_ARTIFACT_ATTEMPT}-CMakeCache.txt"
      if [[ -f "$2/compile_commands.json" ]]; then
        cp "$2/compile_commands.json" "$out/manifests/integration-${CPP_GATE_ARTIFACT_ATTEMPT}-compile-commands.json"
      fi
    fi
  done
fi
SH
chmod 0755 "$fix_root/tools/cpp-bin/cmake"
exec > >(tee "$out/logs/07-facade-matrix-$attempt.log") 2>&1
finish() {
  result=$?
  printf '%s\n' "$result" > "$out/07-facade-matrix-$attempt.exit"
  cd "$fix_root/source"
  sha256sum -c "$out/manifests/source-files.sha256" > "$out/logs/source-hash-after-$attempt.log" 2>&1 || true
  python3 - "$out" "$attempt" <<'PY'
import json,sys
from pathlib import Path
rows=[]
for proc in Path('/proc').iterdir():
    if not proc.name.isdigit():continue
    try:
        args=(proc/'cmdline').read_bytes().replace(b'\0',b' ').decode(errors='replace')
        if ('/source/MirrorGate/bin/mirrorgate' in args or '/runtime/mirrorgate-node-shim/runtimes/node/worker.mjs' in args):
            rows.append({'pid':int(proc.name),'arguments':args})
    except (OSError,PermissionError):pass
out=Path(sys.argv[1])
(out/f'gate-processes-after-{sys.argv[2]}.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps({'remainingGateProcesses':rows}),flush=True)
PY
  exit "$result"
}
trap finish EXIT
date -u +%FT%TZ
id
grep -E '^(CapEff|CapAmb):' /proc/self/status
test "$(id -u)" = 1000
test "$(/usr/bin/bwrap --version)" = 'bubblewrap 0.9.0'
test "$(node --version)" = v24.15.0
printf '%s  %s\n' 6e06ecd3d4d2975a42db2a1822b2d28d9e382f6d5b9bf48fa36c6c9ce27fa77d "$MIRROR_BIN" | sha256sum -c -
sha256sum "$MIRROR_BIN" /usr/bin/bwrap "$fix_root/tools/node/bin/node" \
  > "$out/manifests/matrix-runtime-$attempt.sha256"
cd "$fix_root/source"
sha256sum -c "$out/manifests/source-files.sha256" > "$out/logs/source-hash-before-$attempt.log"
cd "$fix_root/source/MirrorGate"
bash "${CPP_GATE_HARNESS_OVERRIDE:-conformance/control-v1/run-cpp-failures}"
sha256sum "$MIRRORGATE_CPP_FAILURE_BUILD_DIR/mirrorgate_mirrorcpp_counter" \
  "$MIRRORGATE_CPP_FAILURE_BUILD_DIR/mirrorgate_mirrorcpp_receipt_tests" \
  > "$out/manifests/matrix-noop-$attempt.sha256"
cmake --build "$MIRRORGATE_CPP_FAILURE_BUILD_DIR" --parallel 2 \
  > "$out/logs/matrix-noop-$attempt.log" 2>&1
sha256sum -c "$out/manifests/matrix-noop-$attempt.sha256"
echo CPP_GATE_REAL_FACADE_MATRIX_PASSED
