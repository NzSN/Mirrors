#!/usr/bin/env bash
set -euo pipefail
dpm_build=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014
dpm_source=/home/jlc/Tools/mirrors-dpm-followup-20261014/source/Mirrors
dpm_tools=/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013
trap 'dpm_result=$?; printf "%s\n" "$dpm_result" > "$dpm_build/lean-phase.exit"' EXIT
export PATH="$dpm_tools/node/bin:$dpm_tools/cmake-python/cmake/data/bin:/home/jlc/.elan/bin:/home/jlc/.cargo/bin:/usr/local/bin:/usr/bin:/bin"
export LEAN_NUM_THREADS=2
cd "$dpm_source"
python3 -I -S -B tools/deterministic-scheduling/refresh_host_identity.py --check
mkdir -p .lake/build/share/mirrors-dpm
mkdir -p "$dpm_build/lean-build/share/mirrors-dpm"
for dpm_helper in cli.py dpm_host.py timeline.py; do
  cp "tools/deterministic-scheduling/$dpm_helper" .lake/build/share/mirrors-dpm/
  cp "tools/deterministic-scheduling/$dpm_helper" "$dpm_build/lean-build/share/mirrors-dpm/"
done
lake build > "$dpm_build/logs/lean-build.log" 2>&1
.lake/build/bin/dpm_spec > "$dpm_build/logs/dpm-spec.log"
.lake/build/bin/dpm_evidence_spec > "$dpm_build/logs/dpm-evidence-spec.log"
python3 -m unittest discover -s tools/deterministic-scheduling/tests -v > "$dpm_build/logs/dpm-python.log" 2>&1
echo REMOTE_LEAN_PHASE_PASSED
