#!/usr/bin/env bash
set -euo pipefail
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
trap 'result=$?; printf "%s\n" "$result" > "$fix_build/lean-final.exit"' EXIT
export PATH=/home/jlc/.elan/toolchains/leanprover--lean4---v4.33.0/bin:/usr/bin:/bin
export ELAN_TOOLCHAIN=leanprover/lean4:v4.33.0 LEAN_NUM_THREADS=2 TMPDIR=/tmp/fix-tests
unset MIRROR_BIN
cd "$fix_root/source/MirrorLean"
lake -Kjobs=2 build test async-test model-interface-test > "$fix_build/logs/lean-root-build.log" 2>&1
for target in test async-test model-interface-test; do
 .lake/build/bin/$target > "$fix_build/logs/lean-$target.log" 2>&1
done
cd server-mode
lake -Kjobs=2 build server-mode-test server-mode-test-discovery > "$fix_build/logs/lean-native-build.log" 2>&1
.lake/build/bin/server-mode-test > "$fix_build/logs/lean-native-test.log" 2>&1
.lake/build/bin/server-mode-test-discovery > "$fix_build/logs/lean-native-discovery.log" 2>&1
lake -Kjobs=2 build server-mode-test server-mode-test-discovery > "$fix_build/logs/lean-native-noop.log" 2>&1
echo LEAN_ALL_FOCUSED_GATES_PASSED
