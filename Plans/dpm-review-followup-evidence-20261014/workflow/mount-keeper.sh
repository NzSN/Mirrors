#!/usr/bin/env bash
set -euo pipefail
dpm_build=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014
dpm_root=/home/jlc/Tools/mirrors-dpm-followup-20261014
mountpoint -q "$dpm_root" || mount -o loop "$dpm_build/followup.ext4" "$dpm_root"
findmnt -J --mountpoint "$dpm_root" > "$dpm_build/mount.json"
echo FOLLOWUP_MOUNT_READY
sleep 7200
