#!/usr/bin/env bash
set -euo pipefail
dpm_handoff=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013
dpm_build="$dpm_handoff/build"
dpm_root=/home/jlc/Tools/mirrors-dpm-remediation-20261013
dpm_source="$dpm_root/source/Mirrors"
dpm_tools=/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013
trap 'dpm_result=$?; printf "%s\n" "$dpm_result" > "$dpm_build/acceptance-phase.exit"' EXIT
export PATH="$dpm_tools/node/bin:$dpm_tools/cmake-python/cmake/data/bin:/home/jlc/.elan/bin:/home/jlc/.cargo/bin:/usr/local/bin:/usr/bin:/bin"
cd "$dpm_source"
python3 -I -S -B tools/deterministic-scheduling/prepare_cli.py \
  --cpp-runner "$dpm_build/cpp-consumer/dpm_counter" --cpp-explorer "$dpm_build/cpp-consumer/dpm_explore" \
  --ecma "$dpm_root/ecma" --rust-runner "$dpm_build/rust-consumer-target/debug/mirrors-dpm-rust-consumer" \
  --cpp-prefix "$dpm_root/cpp-prefix" --rust-devkit "$dpm_root/rust" --rust-vendor "$dpm_root/rust-vendor" \
  --typescript "$dpm_root/prerequisites/node_modules/typescript" --out "$dpm_build/prepared-final" > "$dpm_build/logs/prepare-final.log" 2>&1
python3 -I -S -B tools/deterministic-scheduling/install_cli.py manifest --source "$dpm_build/prepared-final" \
  --out "$dpm_build/installation-manifest-final.json" > "$dpm_build/logs/installation-manifest.log"
dpm_digest=$(sha256sum "$dpm_build/installation-manifest-final.json" | cut -d' ' -f1)
python3 -I -S -B tools/deterministic-scheduling/install_cli.py install --source "$dpm_build/prepared-final" \
  --manifest "$dpm_build/installation-manifest-final.json" --manifest-sha256 "$dpm_digest" \
  --dest "$dpm_root/installed-final" > "$dpm_build/logs/install-final.log" 2>&1
python3 -I -S -B tools/deterministic-scheduling/check_cli_installed.py --installed "$dpm_root/installed-final" \
  --rust-toolchain "$(rustc --print sysroot)" --out "$dpm_build/installed-gate-final" \
  --cmake "$dpm_tools/cmake-python/cmake/data/bin/cmake" --cxx /usr/bin/g++-12 --tool-root "$dpm_tools" \
  > "$dpm_build/logs/acceptance.log" 2>&1
echo REMOTE_INSTALLED_ACCEPTANCE_PASSED
