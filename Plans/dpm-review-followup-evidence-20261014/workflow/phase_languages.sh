#!/usr/bin/env bash
set -euo pipefail
dpm_build=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014
dpm_handoff=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013
dpm_tools=/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013
trap 'dpm_result=$?; printf "%s\n" "$dpm_result" > "$dpm_build/languages-phase.exit"' EXIT
export PATH="$dpm_tools/node/bin:$dpm_tools/cmake-python/cmake/data/bin:/home/jlc/.elan/bin:/home/jlc/.cargo/bin:/usr/local/bin:/usr/bin:/bin"
export CARGO_TARGET_DIR="$dpm_build/rust-consumer-target" CARGO_BUILD_JOBS=2
python3 -I -S -B "$dpm_build/workflow/compile_languages.py"
