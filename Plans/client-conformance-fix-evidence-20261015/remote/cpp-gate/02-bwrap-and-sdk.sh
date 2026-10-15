#!/usr/bin/env bash
set -euo pipefail
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
out="$fix_build/cpp-gate"
export TMPDIR=/tmp/fix-tests
export PATH="$fix_root/tools/bin:/usr/bin:/bin"
export CC=/usr/bin/gcc-12 CXX=/usr/bin/g++-12
trap 'result=$?; printf "%s\n" "$result" > "$out/02-bwrap-and-sdk.exit"' EXIT
exec > >(tee "$out/logs/02-bwrap-and-sdk.log") 2>&1
date -u +%FT%TZ
meson setup "$out/bwrap-build" "$out/bwrap-source/bubblewrap-0.9.0" \
  --prefix "$fix_root/tools/bwrap09" --buildtype release \
  -Dtests=false -Dman=disabled -Dbash_completion=disabled -Dzsh_completion=disabled
ninja -C "$out/bwrap-build" -j2 install
"$fix_root/tools/bwrap09/bin/bwrap" --version
test "$("$fix_root/tools/bwrap09/bin/bwrap" --version)" = 'bubblewrap 0.9.0'
test "$(stat -c %a "$fix_root/tools/bwrap09/bin/bwrap")" = 755
sha256sum "$fix_root/tools/bwrap09/bin/bwrap" > "$out/manifests/private-bwrap.sha256"
sha256sum -c "$out/manifests/system-bwrap-before.sha256"
"$fix_root/tools/bwrap09/bin/bwrap" --unshare-user --unshare-pid --unshare-ipc \
  --unshare-net --unshare-uts --disable-userns --assert-userns-disabled \
  --cap-drop ALL --clearenv --new-session --die-with-parent --as-pid-1 \
  --ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /lib64 /lib64 \
  --proc /proc --dev /dev -- /usr/bin/true
echo BWRAP_090_REAL_NAMESPACE_PROBE_PASSED
mkdir -p "$fix_root/tools/cpp-bin"
cat > "$fix_root/tools/cpp-bin/cmake" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# Only bound an otherwise unbounded build. Version and configuration are the
# actual CMake 3.28.4 binary, with every target/source option preserved.
if [[ ${1-} == --build && ${!#} == --parallel ]]; then
  exec /home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/cmake-python/cmake/data/bin/cmake "$@" 2
fi
exec /home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/cmake-python/cmake/data/bin/cmake "$@"
SH
chmod 0755 "$fix_root/tools/cpp-bin/cmake"
ln -s /home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/cmake-python/cmake/data/bin/ctest "$fix_root/tools/cpp-bin/ctest"
export PATH="$fix_root/tools/cpp-bin:$PATH"
export CMAKE_GENERATOR=Ninja
export MIRRORGATE_CPP_BUILD_DIR="$out/sdk-build"
export MIRRORGATE_NLOHMANN_JSON_INCLUDE_DIR=/home/jlc/Tools/mirrors-dpm-remediation-20261013/prerequisites/cpp-dependencies/nlohmann_json-src/single_include
cmake --version
printf 'Compiler override: GCC 12.3.0 used instead of documented GCC 13 baseline; existing accepted override reused.\n'
cd "$fix_root/source/MirrorGate"
bash scripts/test-control-cpp.sh
cmake --build "$out/sdk-build" --parallel 2 > "$out/logs/sdk-noop-build.log" 2>&1
sha256sum "$out/sdk-build/mirrorgate_cpp_tests" "$out/sdk-build/mirrorgate_transport_tests" \
  "$out/sdk-build/mirrorgate_hosting_tests" "$out/sdk-build/libmirrorgate_cpp.a" \
  > "$out/manifests/sdk-binaries.sha256"
echo CPP_GATE_PRIVATE_BWRAP_AND_SDK_PASSED
