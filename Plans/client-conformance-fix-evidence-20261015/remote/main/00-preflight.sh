#!/usr/bin/env bash
set -euo pipefail
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
out="$fix_build/cpp-gate"
mkdir -p "$out/logs" "$out/workflow" "$out/manifests"
exec > >(tee "$out/logs/00-preflight.log") 2>&1
date -u +%FT%TZ
id
findmnt -T "$fix_root/source"
findmnt -T /tmp/fix-tests
df -h "$fix_root" /tmp/fix-tests /mnt/d
for command in g++-12 cc meson ninja pkg-config sha256sum tar xz unshare setpriv; do
  command -v "$command" || true
done
g++-12 --version
/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/cmake-python/cmake/data/bin/cmake --version
/home/jlc/.local/share/uv/python/cpython-3.12.14-linux-x86_64-gnu/bin/python3.12 --version
/usr/bin/bwrap --version
sha256sum /usr/bin/bwrap > "$out/manifests/system-bwrap-before.sha256"
for command in meson ninja pkg-config; do "$command" --version || true; done
pkg-config --modversion libcap || true
ls -la "$fix_build/downloads/bubblewrap-0.9.0.tar.xz" "$fix_build/downloads/bubblewrap-tag.json"
sha256sum "$fix_build/downloads/bubblewrap-0.9.0.tar.xz" "$fix_build/downloads/bubblewrap-tag.json"
cat "$fix_build/downloads/bubblewrap-tag.json"
ls -la /home/jlc/Tools/mirrors-dpm-remediation-20261013/prerequisites/cpp-dependencies
find /home/jlc/Tools/mirrors-dpm-remediation-20261013/prerequisites/cpp-dependencies -maxdepth 2 -type f \( -name CMakeCache.txt -o -name json.hpp -o -name CMakeLists.txt \) -print
ls -la /mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014/sdk-cpp/_deps || true
echo CPP_GATE_PREFLIGHT_COMPLETE
