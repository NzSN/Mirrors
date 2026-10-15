#!/usr/bin/env bash
# Run ONLY on windows-dev Ubuntu WSL as root. Never formats or replaces an image.
set -euo pipefail
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
fix_image="$fix_build/fix-workspace.ext4"
test -f "$fix_image"
test "$(stat -c %s "$fix_image")" = 25769803776
mkdir -p "$fix_root" /tmp/fix-tests
if ! mountpoint -q "$fix_root"; then mount -o loop "$fix_image" "$fix_root"; fi
# Refuse to bind a different filesystem accidentally occupying our path.
fix_device=$(findmnt -rn -o SOURCE --mountpoint "$fix_root")
test "$(losetup -n -O BACK-FILE "$fix_device")" = "$fix_image"
if ! mountpoint -q /tmp/fix-tests; then mount --bind "$fix_root/tmp" /tmp/fix-tests; fi
findmnt --mountpoint "$fix_root"
findmnt --mountpoint /tmp/fix-tests
# Keep the WSL instance alive for a bounded operator session. Ctrl-C is safe;
# flush and unmount /tmp/fix-tests, then fix_root when work is complete.
sleep 14400
