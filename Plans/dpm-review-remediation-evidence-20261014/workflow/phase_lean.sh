#!/usr/bin/env bash
set -euo pipefail
dpm_handoff=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013
dpm_build="$dpm_handoff/build"
dpm_source=/home/jlc/Tools/mirrors-dpm-remediation-20261013/source/Mirrors
dpm_tools=/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013
trap 'dpm_result=$?; printf "%s\n" "$dpm_result" > "$dpm_build/lean-phase.exit"' EXIT
export PATH="$dpm_tools/node/bin:$dpm_tools/cmake-python/cmake/data/bin:/home/jlc/.elan/bin:/home/jlc/.cargo/bin:/usr/local/bin:/usr/bin:/bin"
export LEAN_NUM_THREADS=4
cp -a /home/jlc/Repos/Mirrors/.lake/build/. "$dpm_build/lean-build/"
cd "$dpm_source"
python3 -I -S -B tools/deterministic-scheduling/refresh_host_identity.py
lake build > "$dpm_build/logs/lean-build.log" 2>&1
python3 -I -S -B tools/deterministic-scheduling/refresh_host_identity.py --check
.lake/build/bin/dpm_spec > "$dpm_build/logs/dpm-spec.log"
.lake/build/bin/dpm_evidence_spec > "$dpm_build/logs/dpm-evidence-spec.log"
python3 -m unittest discover -s tools/deterministic-scheduling/tests -v > "$dpm_build/logs/dpm-python.log" 2>&1
echo REMOTE_LEAN_PHASE_PASSED
