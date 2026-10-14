#!/usr/bin/env bash
set -euo pipefail
dpm_build=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014
dpm_source=/home/jlc/Tools/mirrors-dpm-followup-20261014/source/Mirrors
trap 'dpm_result=$?; printf "%s\n" "$dpm_result" > "$dpm_build/python-final-phase.exit"' EXIT
cd "$dpm_source"
for dpm_helper in cli.py dpm_host.py timeline.py; do
  cp "tools/deterministic-scheduling/$dpm_helper" "$dpm_build/lean-build/share/mirrors-dpm/"
done
python3 -m unittest discover -s tools/deterministic-scheduling/tests -v > "$dpm_build/logs/dpm-python-final.log" 2>&1
echo REMOTE_PYTHON_FINAL_PASSED
