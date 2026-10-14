#!/usr/bin/env bash
set -euo pipefail
dpm_handoff=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013
if [[ ! -f "$dpm_handoff/build/input-verification.json" ]]; then
  python3 -I -S -B "$dpm_handoff/setup_remote.py"
fi
dpm_build="$dpm_handoff/build"
dpm_tools=/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013
mkdir -p "$dpm_build/tmp" "$dpm_build/pip-cache"
TMPDIR="$dpm_build/tmp" PIP_CACHE_DIR="$dpm_build/pip-cache" python3 -m pip install --no-deps --target "$dpm_tools/cmake-python" 'cmake>=3.24,<3.29' > "$dpm_build/logs/cmake-setup-v2.log" 2>&1
"$dpm_tools/node/bin/node" --version
"$dpm_tools/cmake-python/cmake/data/bin/cmake" --version
printf '#include <expected>\nint main(){std::expected<int,int> n(1); return n.value()-1;}\n' > "$dpm_build/cxx23-probe.cpp"
/usr/bin/g++-12 -std=c++23 "$dpm_build/cxx23-probe.cpp" -o "$dpm_build/cxx23-probe"
"$dpm_build/cxx23-probe"
echo REMOTE_SETUP_PASSED
