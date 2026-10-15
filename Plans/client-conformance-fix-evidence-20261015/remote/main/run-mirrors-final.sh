#!/usr/bin/env bash
set -euo pipefail
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
trap 'result=$?; printf "%s\n" "$result" > "$fix_build/mirrors-final.exit"' EXIT
export PATH="$fix_root/tools/bin:/home/jlc/.elan/toolchains/leanprover--lean4---v4.33.0/bin:/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/cmake-python/cmake/data/bin:/home/jlc/.cargo/bin:/usr/bin:/bin"
export ELAN_TOOLCHAIN=leanprover/lean4:v4.33.0 LEAN_NUM_THREADS=2 CARGO_BUILD_JOBS=2 CMAKE_BUILD_PARALLEL_LEVEL=2
export CC=/usr/bin/gcc-12 CXX=/usr/bin/g++-12 TMPDIR=/tmp/fix-tests LC_ALL=C.UTF-8
export MIRRORCPP_PREFIX="$fix_root/cpp-gate-install" XDG_CACHE_HOME="$fix_root/tools/xdg-cache"
export PYTHONPATH=/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/python-evidence
export CARGO_TARGET_DIR="$fix_build/mirrors-rust-target"
unset APALACHE_MC MIRROR_BIN DV_LIVE_REFERENCES
test -f "$fix_build/cpp-gate/installed-prefix-ready.json"
cd "$fix_root/source/Mirrors"
bash tools/check-native-rebuild.sh > "$fix_build/logs/native-rebuild.log" 2>&1
bash tools/run-local-no-model-check.sh > "$fix_build/logs/mirrors-full-no-model.log" 2>&1
echo MIRRORS_NATIVE_AND_FULL_NONMODEL_PASSED
