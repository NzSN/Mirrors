#!/usr/bin/env bash
set -euo pipefail
dpm_handoff=/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013
dpm_build="$dpm_handoff/build"
dpm_root=/home/jlc/Tools/mirrors-dpm-remediation-20261013
dpm_tools=/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013
trap 'dpm_result=$?; printf "%s\n" "$dpm_result" > "$dpm_build/rust-retry-phase.exit"' EXIT
export PATH="$dpm_tools/node/bin:$dpm_tools/cmake-python/cmake/data/bin:/home/jlc/.elan/bin:/home/jlc/.cargo/bin:/usr/local/bin:/usr/bin:/bin"
export CARGO_TARGET_DIR="$dpm_build/rust-consumer-target"
export CARGO_BUILD_JOBS=2
cd "$dpm_root/rust"
cargo fetch --locked --manifest-path sdk/Cargo.toml > "$dpm_build/logs/rust-fetch-locked.log" 2>&1
cargo build --offline > "$dpm_build/logs/rust-consumer-build-final.log" 2>&1
cargo vendor --offline --locked "$dpm_root/rust-vendor" > "$dpm_build/logs/rust-vendor-final.log" 2>&1
echo REMOTE_RUST_PHASE_PASSED
