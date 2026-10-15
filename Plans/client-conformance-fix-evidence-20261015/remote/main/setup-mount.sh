#!/usr/bin/env bash
set -euo pipefail
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
fix_image="$fix_build/fix-workspace.ext4"
test ! -e "$fix_image"
test ! -e "$fix_root"
mkdir "$fix_root"
truncate -s 24G "$fix_image"
mkfs.ext4 -q -F "$fix_image"
mount -o loop "$fix_image" "$fix_root"
mkdir -p "$fix_root/source" "$fix_root/tools" "$fix_root/tmp" /tmp/fix-tests
chown -R jlc:jlc "$fix_root" /tmp/fix-tests
mkdir -p "$fix_build/logs" "$fix_build/workflow"
chown jlc:jlc "$fix_build/logs" "$fix_build/workflow"
findmnt -J --mountpoint "$fix_root" > "$fix_build/fix-mount.json"
printf '{"pid":%s,"seconds":14400}\n' "$$" > "$fix_build/mount-keeper.json"
df -h / /mnt/d "$fix_root"
echo FIX_NEW_MOUNT_READY
sleep 14400
