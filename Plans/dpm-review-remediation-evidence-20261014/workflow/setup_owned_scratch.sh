#!/usr/bin/env bash
set -euo pipefail
dpm_build=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build
dpm_scratch=/home/jlc/Tools/mirrors-dpm-remediation-20261013/tmp-tests-ext4
dpm_image="$dpm_build/non-model-scratch.ext4"
test ! -e "$dpm_image"
test ! -e "$dpm_scratch"
mkdir "$dpm_scratch"
truncate -s 4G "$dpm_image"
mkfs.ext4 -q -F "$dpm_image"
mount -o loop "$dpm_image" "$dpm_scratch"
chown jlc:jlc "$dpm_scratch"
findmnt -J --mountpoint "$dpm_scratch" > "$dpm_build/non-model-scratch-mount.json"
df -h "$dpm_scratch"
