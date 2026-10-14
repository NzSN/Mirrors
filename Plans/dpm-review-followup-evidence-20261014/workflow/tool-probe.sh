#!/usr/bin/env bash
set -euo pipefail
dpm_build=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014
cd /home/jlc/Tools/mirrors-dpm-remediation-20261013/source/Mirrors
{
  id
  /home/jlc/.elan/bin/lean --version
  /home/jlc/.cargo/bin/rustc --version
  sha256sum /usr/bin/python3.10 /home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/node/bin/node
  findmnt -J --mountpoint /home/jlc/Tools/mirrors-dpm-followup-20261014
  test -w /home/jlc/Tools/mirrors-dpm-followup-20261014
  echo FOLLOWUP_PREFLIGHT_PASSED
} > "$dpm_build/tool-probe.log" 2>&1
