#!/usr/bin/env bash
set -euo pipefail
dpm_handoff=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013
dpm_build="$dpm_handoff/build/followup-20261014"
dpm_root=/home/jlc/Tools/mirrors-dpm-followup-20261014
dpm_sources="$dpm_root/source"
dpm_tools=/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013
dpm_cmake="$dpm_tools/cmake-python/cmake/data/bin/cmake"
trap 'dpm_result=$?; printf "%s\n" "$dpm_result" > "$dpm_build/cpp-phase.exit"' EXIT
export PATH="$dpm_tools/node/bin:$dpm_tools/cmake-python/cmake/data/bin:/home/jlc/.elan/bin:/home/jlc/.cargo/bin:/usr/local/bin:/usr/bin:/bin"
dpm_dependencies="$dpm_root/prerequisites/cpp-dependencies"
dpm_args=(-DCMAKE_CXX_COMPILER=/usr/bin/g++-12 -DCMAKE_C_COMPILER=/usr/bin/gcc-12 -DCMAKE_BUILD_TYPE=Debug
  -DMIRRORCPP_BUILD_TESTS=ON -DMIRRORCPP_BUILD_EXAMPLES=OFF -DMIRRORCPP_BUILD_CLI=OFF -DMIRRORCPP_WERROR=ON
  -DCMAKE_DISABLE_FIND_PACKAGE_Boost=TRUE -DCMAKE_DISABLE_FIND_PACKAGE_nlohmann_json=TRUE
  -DFETCHCONTENT_FULLY_DISCONNECTED=ON -DJSON_Install=ON
  "-DFETCHCONTENT_SOURCE_DIR_NLOHMANN_JSON=$dpm_dependencies/nlohmann_json-src"
  "-DFETCHCONTENT_SOURCE_DIR_CATCH2=$dpm_dependencies/catch2-src")
for dpm_dep in "$dpm_dependencies"/boost_*-src; do
  dpm_name=$(basename "$dpm_dep"); dpm_name=${dpm_name%-src}
  dpm_args+=("-DFETCHCONTENT_SOURCE_DIR_${dpm_name^^}=$dpm_dep")
done
"$dpm_cmake" -S "$dpm_sources/MirrorCPP" -B "$dpm_build/sdk-cpp" "${dpm_args[@]}" > "$dpm_build/logs/cpp-configure.log" 2>&1
"$dpm_cmake" --build "$dpm_build/sdk-cpp" --target mirrorcpp_schedule_test mirrorcpp_schedule_binding_test mirrorcpp_schedule_exploration_test mirrorcpp_schedule_sync_test -j2 > "$dpm_build/logs/cpp-build.log" 2>&1
for dpm_test in mirrorcpp_schedule_test mirrorcpp_schedule_binding_test mirrorcpp_schedule_exploration_test mirrorcpp_schedule_sync_test; do
  "$dpm_build/sdk-cpp/test/unit/$dpm_test" > "$dpm_build/logs/$dpm_test.log" 2>&1
done
"$dpm_cmake" --install "$dpm_build/sdk-cpp" --prefix "$dpm_root/cpp-prefix" > "$dpm_build/logs/cpp-install.log" 2>&1
mkdir -p "$dpm_root/cpp-prefix/include"
for dpm_dep in "$dpm_dependencies"/boost_*-src; do
  cp -a "$dpm_dep/include/." "$dpm_root/cpp-prefix/include/"
done
"$dpm_cmake" -S "$dpm_sources/Mirrors/tools/deterministic-scheduling" -B "$dpm_build/cpp-consumer" \
  -DCMAKE_CXX_COMPILER=/usr/bin/g++-12 -DCMAKE_BUILD_TYPE=Release "-DCMAKE_PREFIX_PATH=$dpm_root/cpp-prefix" > "$dpm_build/logs/cpp-consumer-configure.log" 2>&1
"$dpm_cmake" --build "$dpm_build/cpp-consumer" --target dpm_counter dpm_explore -j2 > "$dpm_build/logs/cpp-consumer-build.log" 2>&1
"$dpm_build/cpp-consumer/dpm_explore" --describe > "$dpm_build/cpp-explorer-description.json"
echo REMOTE_CPP_PHASE_PASSED
