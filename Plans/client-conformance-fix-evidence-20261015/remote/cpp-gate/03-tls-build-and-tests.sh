#!/usr/bin/env bash
set -euo pipefail
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
out="$fix_build/cpp-gate"
deps=/home/jlc/Tools/mirrors-dpm-remediation-20261013/prerequisites/cpp-dependencies
export TMPDIR=/tmp/fix-tests
export PATH="$fix_root/tools/cpp-bin:$fix_root/tools/bin:/usr/bin:/bin"
export CC=/usr/bin/gcc-12 CXX=/usr/bin/g++-12
trap 'result=$?; printf "%s\n" "$result" > "$out/03-tls-build-and-tests.exit"' EXIT
exec > >(tee "$out/logs/03-tls-build-and-tests.log") 2>&1
date -u +%FT%TZ
args=(-S "$fix_root/source/MirrorCPP" -B "$out/tls-build" -G Ninja
  -DCMAKE_BUILD_TYPE=Debug -DMIRRORCPP_WERROR=ON -DMIRRORCPP_WITH_TLS=ON
  -DMIRRORCPP_BUILD_TESTS=ON -DMIRRORCPP_BUILD_EXAMPLES=OFF -DMIRRORCPP_BUILD_CLI=OFF
  -DFETCHCONTENT_FULLY_DISCONNECTED=ON -DCMAKE_DISABLE_FIND_PACKAGE_Boost=ON
  -DCMAKE_DISABLE_FIND_PACKAGE_nlohmann_json=ON
  -DFETCHCONTENT_SOURCE_DIR_NLOHMANN_JSON="$deps/nlohmann_json-src"
  -DFETCHCONTENT_SOURCE_DIR_CATCH2="$deps/catch2-src"
  -DCMAKE_INSTALL_PREFIX="$fix_root/cpp-gate-install")
for module in multiprecision config core assert static_assert throw_exception exception \
    type_traits utility integer mpl preprocessor predef rational smart_ptr tuple io winapi; do
  upper="${module^^}"
  args+=("-DFETCHCONTENT_SOURCE_DIR_BOOST_${upper}=$deps/boost_${module}-src")
done
cmake "${args[@]}"
cmake --build "$out/tls-build" --target mirrorcpp_tls_test --parallel 2
"$out/tls-build/test/unit/mirrorcpp_tls_test" '[tls][key-mode]' --reporter console \
  > "$out/logs/tls-key-mode.log" 2>&1
cat "$out/logs/tls-key-mode.log"
"$out/tls-build/test/unit/mirrorcpp_tls_test" '[tls]' --reporter console \
  > "$out/logs/tls-normal-and-framing.log" 2>&1
cat "$out/logs/tls-normal-and-framing.log"
cmake --build "$out/tls-build" --target mirrorcpp_tls_test --parallel 2 \
  > "$out/logs/tls-noop-build.log" 2>&1
sha256sum "$out/tls-build/test/unit/mirrorcpp_tls_test" "$out/tls-build/libmirrorcpp.a" \
  > "$out/manifests/tls-binaries.sha256"
grep -E 'CMAKE_(BUILD_TYPE|CXX_COMPILER):|MIRRORCPP_(WITH_TLS|WERROR):' "$out/tls-build/CMakeCache.txt"
echo CPP_GATE_FRESH_TLS_GATES_PASSED
