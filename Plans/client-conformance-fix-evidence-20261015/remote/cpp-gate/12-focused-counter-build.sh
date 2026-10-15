#!/usr/bin/env bash
set -euo pipefail
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
out=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015/cpp-gate
cmake=/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/cmake-python/cmake/data/bin/cmake
export TMPDIR=/tmp/fix-tests CC=/usr/bin/gcc-12 CXX=/usr/bin/g++-12
exec > >(tee "$out/logs/12-focused-counter-build.log") 2>&1
printf '%s  %s\n' 5904003d28699b1b128254486cfb8c411c34ac829c515cd761366570795736be \
  "$fix_root/source/MirrorGate/integrations/mirrorcpp/counter_driver.cpp" | sha256sum -c -
"$cmake" --build "$out/matrix-build" --target mirrorgate_mirrorcpp_counter --parallel 2
sha256sum "$out/matrix-build/mirrorgate_mirrorcpp_counter" \
  > "$out/manifests/reviewed-counter-binary.sha256"
echo CPP_GATE_REVIEWED_COUNTER_TARGET_BUILT
