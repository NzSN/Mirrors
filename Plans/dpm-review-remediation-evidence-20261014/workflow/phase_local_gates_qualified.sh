#!/usr/bin/env bash
set -euo pipefail
dpm_handoff=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013
dpm_build="$dpm_handoff/build"
dpm_root=/home/jlc/Tools/mirrors-dpm-remediation-20261013
dpm_tools=/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013
trap 'dpm_result=$?; printf "%s\n" "$dpm_result" > "$dpm_build/local-gates-qualified-phase.exit"' EXIT
export PATH="$dpm_tools/node/bin:$dpm_tools/cmake-python/cmake/data/bin:/home/jlc/.elan/bin:/home/jlc/.cargo/bin:/usr/local/bin:/usr/bin:/bin"
export LEAN_NUM_THREADS=4 CXX=/usr/bin/g++-12 CC=/usr/bin/gcc-12
export MIRRORCPP_PREFIX="$dpm_root/cpp-prefix"
export CARGO_TARGET_DIR="$dpm_build/local-gates-rust"
export PYTHONPATH="$dpm_tools/python-evidence"
export TMPDIR="$dpm_root/tmp-tests-ext4"
unset DV_LIVE_REFERENCES
[[ "$(findmnt -rn -o FSTYPE --mountpoint "$TMPDIR")" == ext4 ]]
test -f "$dpm_build/offline-fixture-artifacts.json"
cd "$dpm_root/source/Mirrors"
bash tools/run-local-no-model-check.sh > "$dpm_build/logs/local-no-model-check-qualified.log" 2>&1
echo REMOTE_NON_MODEL_GATES_QUALIFIED_PASSED
