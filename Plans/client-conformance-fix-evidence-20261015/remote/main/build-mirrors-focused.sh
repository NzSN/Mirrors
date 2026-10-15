#!/usr/bin/env bash
set -euo pipefail
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
trap 'result=$?; printf "%s\n" "$result" > "$fix_build/mirrors-focused.exit"' EXIT
export PATH="$fix_root/tools/bin:/home/jlc/.elan/toolchains/leanprover--lean4---v4.33.0/bin:/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/cmake-python/cmake/data/bin:/home/jlc/.cargo/bin:/usr/bin:/bin"
export ELAN_TOOLCHAIN=leanprover/lean4:v4.33.0 LEAN_NUM_THREADS=2 CARGO_BUILD_JOBS=2 CMAKE_BUILD_PARALLEL_LEVEL=2
export CC=/usr/bin/gcc-12 CXX=/usr/bin/g++-12 TMPDIR=/tmp/fix-tests LC_ALL=C.UTF-8
unset APALACHE_MC MIRROR_BIN
cd "$fix_root/source/Mirrors"
lake -Kjobs=2 build mirror transport_spec trace_capture_spec jobstore_spec > "$fix_build/logs/mirrors-focused-build.log" 2>&1
for target in transport_spec trace_capture_spec jobstore_spec; do
 .lake/build/bin/$target > "$fix_build/logs/mirrors-$target.log" 2>&1
done
python3 tools/check-client-framing.py > "$fix_build/logs/mirrors-client-framing.log" 2>&1
python3 tools/check-trace-capture.py > "$fix_build/logs/mirrors-trace-capture.log" 2>&1
python3 tools/check-validate-async.py > "$fix_build/logs/mirrors-validate-async.log" 2>&1
echo MIRRORS_FOCUSED_GATES_PASSED
