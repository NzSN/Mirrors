#!/usr/bin/env bash
set -euo pipefail
dpm_build=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014
dpm_root=/home/jlc/Tools/mirrors-dpm-followup-20261014
/usr/bin/g++-12 -std=c++23 -Wall -Wextra -Werror -I"$dpm_root/cpp-prefix/include" \
  "$dpm_build/workflow/cpp-evidence.cpp" "$dpm_root/cpp-prefix/lib/libmirrorcpp.a" \
  -pthread -lssl -lcrypto -o "$dpm_build/fixed-cpp-evidence" > "$dpm_build/logs/fixed-cpp-evidence-build.log" 2>&1
"$dpm_build/fixed-cpp-evidence" > "$dpm_build/fixed-cpp-evidence.json"
