#!/usr/bin/env bash
set -euo pipefail
dpm_build=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014
dpm_root=/home/jlc/Tools/mirrors-dpm-followup-20261014
dpm_tools=/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013
mkdir -p "$dpm_build/logs" "$dpm_build/workflow"
test ! -e "$dpm_build/followup.ext4"
test ! -e "$dpm_root"
mkdir "$dpm_root"
truncate -s 12G "$dpm_build/followup.ext4"
mkfs.ext4 -q -F "$dpm_build/followup.ext4"
mount -o loop "$dpm_build/followup.ext4" "$dpm_root"
chown jlc:jlc "$dpm_root"
findmnt -J --mountpoint "$dpm_root" > "$dpm_build/mount.json"
mkdir -p "$dpm_root/source" "$dpm_root/tmp-tests"
{
  date -u --iso-8601=seconds
  uname -a
  df -h / /mnt/d "$dpm_root"
  free -h
  /usr/bin/python3.10 --version
  /usr/bin/g++-12 --version
  "$dpm_tools/node/bin/node" --version
  "$dpm_tools/cmake-python/cmake/data/bin/cmake" --version
  /home/jlc/.elan/bin/lean --version
  /home/jlc/.cargo/bin/rustc --version
  sha256sum /usr/bin/python3.10 "$dpm_tools/node/bin/node"
} > "$dpm_build/preflight.log" 2>&1
