#!/usr/bin/env bash
set -euo pipefail
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
out="$fix_build/cpp-gate"
deps=/home/jlc/Tools/mirrors-dpm-remediation-20261013/prerequisites/cpp-dependencies
prefix="$fix_root/cpp-gate-install"
export TMPDIR=/tmp/fix-tests
export PATH="$fix_root/tools/cpp-bin:$fix_root/tools/bin:/usr/bin:/bin"
export CC=/usr/bin/gcc-12 CXX=/usr/bin/g++-12
trap 'result=$?; printf "%s\n" "$result" > "$out/06-install-and-consumers.exit"' EXIT
exec > >(tee "$out/logs/06-install-and-consumers.log") 2>&1
test "$(cat "$out/03-tls-build-and-tests.exit")" = 0
if [[ -e "$prefix" ]]; then
  cmp "$out/tls-build/libmirrorcpp.a" "$prefix/lib/libmirrorcpp.a"
fi
cmake --install "$out/tls-build" --prefix "$prefix"
cmake -S "$deps/nlohmann_json-src" -B "$out/nlohmann-install-build" -G Ninja \
  -DJSON_BuildTests=OFF -DJSON_Install=ON -DCMAKE_INSTALL_PREFIX="$prefix"
cmake --install "$out/nlohmann-install-build"
for includes in "$deps"/boost_*-src/include; do cp -a "$includes"/. "$prefix/include/"; done
test -f "$prefix/include/mirrorcpp/client.hpp"
test -f "$prefix/include/nlohmann/json.hpp"
test -f "$prefix/include/boost/multiprecision/cpp_int.hpp"
sha256sum "$prefix/lib/libmirrorcpp.a" "$prefix/include/mirrorcpp/client.hpp" \
  "$prefix/include/nlohmann/json.hpp" "$prefix/include/boost/multiprecision/cpp_int.hpp" \
  > "$out/manifests/installed-prefix.sha256"
python3 - "$out" "$prefix" <<'PY'
import hashlib,json,sys
from pathlib import Path
out,prefix=map(Path,sys.argv[1:])
manifest={'status':'ready','prefix':str(prefix),'tls':True,'buildType':'Debug',
          'warningsAsErrors':True,'compiler':'GCC 12.3.0; explicitly recorded override from documented GCC13 baseline',
          'sourceArchiveSha256':'577f5fd3dd9fd4b52741d85a242b9d14b7250d2d52dcb73f6ce38eeb7628fc83',
          'librarySha256':hashlib.sha256((prefix/'lib/libmirrorcpp.a').read_bytes()).hexdigest(),
          'oldMirrorCppObjectsUsed':False,'dependencies':'copied immutable cached nlohmann3.11.3/Boost1.85 headers'}
(out/'installed-prefix-ready.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest),flush=True)
PY
cmake -S "$fix_root/source/MirrorCPP/test/packaging" -B "$out/installed-consumer-build" -G Ninja \
  -DCMAKE_PREFIX_PATH="$prefix" -DCMAKE_BUILD_TYPE=Debug -DCMAKE_DISABLE_FIND_PACKAGE_Boost=ON
cmake --build "$out/installed-consumer-build" --parallel 2
"$out/installed-consumer-build/mirrorcpp_packaging_consumer"
mkdir "$out/gate-installed-consumer"
cat > "$out/gate-installed-consumer/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.24)
project(gate_installed_consumer CXX)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(mirrorcpp CONFIG REQUIRED)
if(TARGET Boost::headers)
  set_target_properties(Boost::headers PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_PREFIX_PATH}/include")
endif()
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
add_subdirectory("${GATE_ROOT}/sdk/cpp" gate-sdk)
add_library(facade "${GATE_ROOT}/integrations/mirrorcpp/orchestration.cpp")
target_include_directories(facade PUBLIC "${GATE_ROOT}/integrations/mirrorcpp")
target_link_libraries(facade PUBLIC mirrorgate::cpp mirrorcpp::mirrorcpp)
target_compile_options(facade PRIVATE -Wall -Wextra -Wpedantic -Werror)
add_executable(gate_installed_consumer main.cpp)
target_link_libraries(gate_installed_consumer PRIVATE facade)
target_compile_options(gate_installed_consumer PRIVATE -Wall -Wextra -Wpedantic -Werror)
CMAKE
cat > "$out/gate-installed-consumer/main.cpp" <<'CPP'
#include "orchestration.hpp"
#include <iostream>
#include <type_traits>
int main() {
  static_assert(std::is_copy_constructible_v<mirrorgate::FailureSnapshot>);
  static_assert(!std::is_copy_assignable_v<mirrorgate::FailureSnapshot>);
  namespace integration = mirrorgate::mirrorcpp_integration;
  integration::SandboxEvidence evidence;
  evidence.primary_failure = std::make_shared<const mirrorgate::FailureSnapshot>(
      mirrorgate::snapshot_failure(mirrorgate::SdkError("BACKEND_ADMISSION_FAILED",
          "authorize", "same human text", 42, mirrorgate::FailureOrigin::control_reply), "authorize"));
  const auto result = integration::detail::restore_gate_failure(
      std::unexpected(mirrorcpp::Error(mirrorcpp::ErrorKind::model_interface,
          "same human text", "adapter_factory_failed")), evidence);
  if (result || result.error().code != "mirrorgate.BACKEND_ADMISSION_FAILED" ||
      evidence.primary_failure->operation_id != 42) return 1;
  std::cout << "Installed MirrorCPP + rebuilt SDK/facade consumer passed\n";
}
CPP
cmake -S "$out/gate-installed-consumer" -B "$out/gate-installed-consumer-build" -G Ninja \
  -DCMAKE_PREFIX_PATH="$prefix" -DCMAKE_BUILD_TYPE=Debug -DCMAKE_DISABLE_FIND_PACKAGE_Boost=ON \
  -DGATE_ROOT="$fix_root/source/MirrorGate"
cmake --build "$out/gate-installed-consumer-build" --parallel 2
"$out/gate-installed-consumer-build/gate_installed_consumer"
cmake --build "$out/gate-installed-consumer-build" --parallel 2 > "$out/logs/consumer-noop-build.log" 2>&1
sha256sum "$out/installed-consumer-build/mirrorcpp_packaging_consumer" \
  "$out/gate-installed-consumer-build/gate_installed_consumer" \
  > "$out/manifests/downstream-consumers.sha256"
echo CPP_GATE_FRESH_INSTALL_AND_CONSUMERS_PASSED
