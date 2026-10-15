#!/usr/bin/env bash
set -euo pipefail
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
out="$fix_build/cpp-gate"
exec > >(tee "$out/logs/11-broker-observation-test-delta.log") 2>&1
cd "$fix_build"
printf '%s  %s\n' f267d6a568968685829c153d54b10c88cda6baa7ac75267b07f531b17e2869a7 cpp-gate-broker-observation-delta.tar | sha256sum -c -
printf '%s  %s\n' 5d2cb565c8d9dc51681171ae768a01d8e7cf2607402bfaaa1342cbd478e47d71 cpp-gate-source-final.sha256 | sha256sum -c -
cd "$fix_root/source"
sha256sum -c "$out/manifests/source-files.sha256" > "$out/logs/source-hash-before-broker-test-delta.log"
cp "$out/manifests/source-files.sha256" "$out/manifests/source-files-before-broker-test-fix.sha256"
tar -tf "$fix_build/cpp-gate-broker-observation-delta.tar"
tar -xf "$fix_build/cpp-gate-broker-observation-delta.tar"
sha256sum -c "$fix_build/cpp-gate-source-final.sha256" > "$out/logs/source-hash-after-broker-test-delta.log"
cp "$fix_build/cpp-gate-source-final.sha256" "$out/manifests/source-files.sha256"
diff -u "$out/manifests/source-files-before-broker-test-fix.sha256" "$out/manifests/source-files.sha256" \
  > "$out/manifests/broker-observation-test-source-delta.diff" || test "$?" = 1
echo CPP_GATE_REVIEWED_BROKER_OBSERVATION_TEST_DELTA_VERIFIED
