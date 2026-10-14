#!/usr/bin/env bash
set -u
dpm_build=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build
for dpm_phase in lean cpp languages acceptance; do
  if [[ -f "$dpm_build/$dpm_phase-phase.exit" ]]; then
    printf '%s exit=' "$dpm_phase"; cat "$dpm_build/$dpm_phase-phase.exit"
  fi
done
for dpm_log in lean-build cpp-build languages-build acceptance; do
  if [[ -f "$dpm_build/logs/$dpm_log.log" ]]; then
    printf '%s\n' "$dpm_log"
    tail -n 4 "$dpm_build/logs/$dpm_log.log"
  fi
done
df -h / /mnt/d
