#!/usr/bin/env bash
set -euo pipefail
dpm_handoff=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013
dpm_build="$dpm_handoff/build"
dpm_source=/home/jlc/Tools/mirrors-dpm-remediation-20261013/source/Mirrors
trap 'dpm_result=$?; printf "%s\n" "$dpm_result" > "$dpm_build/lean-focus-phase.exit"' EXIT
cp "$dpm_handoff/test_dpm_host.py" "$dpm_source/tools/deterministic-scheduling/tests/test_dpm_host.py"
mkdir -p "$dpm_build/lean-build/share/mirrors-dpm"
for dpm_host in cli.py dpm_host.py timeline.py; do
  cp "$dpm_source/tools/deterministic-scheduling/$dpm_host" "$dpm_build/lean-build/share/mirrors-dpm/"
done
cd "$dpm_source"
python3 -I -S -B tools/deterministic-scheduling/refresh_host_identity.py --check
.lake/build/bin/dpm_spec > "$dpm_build/logs/dpm-spec-final.log"
.lake/build/bin/dpm_evidence_spec > "$dpm_build/logs/dpm-evidence-spec-final.log"
python3 -m unittest discover -s tools/deterministic-scheduling/tests -v > "$dpm_build/logs/dpm-python-final.log" 2>&1
echo REMOTE_LEAN_FOCUSED_PASSED
