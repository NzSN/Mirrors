#!/usr/bin/env bash
set -euo pipefail
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
out="$fix_build/cpp-gate"
exec > >(tee "$out/logs/08-cleanup-test-delta.log") 2>&1
cd "$fix_build"
printf '%s  %s\n' b0c1e16aa91ecdaf85d8bf37ccf35b795c2fb0332ad0cfc299c13283fb938cb9 cpp-gate-cleanup-delta.tar | sha256sum -c -
printf '%s  %s\n' 259cd85a20b68a235e12fcab900aef3c059b51926d5171b536113df94bc32513 cpp-gate-source-after-cleanup.sha256 | sha256sum -c -
cd "$fix_root/source"
sha256sum -c "$out/manifests/source-files.sha256" > "$out/logs/source-hash-before-cleanup-delta.log"
cp "$out/manifests/source-files.sha256" "$out/manifests/source-files-before-cleanup-fix.sha256"
tar -tf "$fix_build/cpp-gate-cleanup-delta.tar"
tar -xf "$fix_build/cpp-gate-cleanup-delta.tar"
sha256sum -c "$fix_build/cpp-gate-source-after-cleanup.sha256" > "$out/logs/source-hash-after-cleanup-delta.log"
cp "$fix_build/cpp-gate-source-after-cleanup.sha256" "$out/manifests/source-files.sha256"
diff -u "$out/manifests/source-files-before-cleanup-fix.sha256" "$out/manifests/source-files.sha256" \
  > "$out/manifests/cleanup-test-source-delta.diff" || test "$?" = 1
echo CPP_GATE_REVIEWED_CLEANUP_TEST_DELTA_VERIFIED
