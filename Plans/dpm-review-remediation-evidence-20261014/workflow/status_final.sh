#!/usr/bin/env bash
set -u
dpm_build=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build
for dpm_exit in "$dpm_build"/*phase.exit; do
  [[ -f "$dpm_exit" ]] || continue
  printf '%s=' "$(basename "$dpm_exit")"; cat "$dpm_exit"
done
for dpm_name in dpm-python-final rust-fetch-locked rust-consumer-build-final rust-vendor-final acceptance local-no-model-check; do
  if [[ -f "$dpm_build/logs/$dpm_name.log" ]]; then
    printf '%s\n' "$dpm_name"
    tail -n 8 "$dpm_build/logs/$dpm_name.log"
  fi
done
df -h / /mnt/d
