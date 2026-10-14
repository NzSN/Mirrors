#!/usr/bin/env bash
set -eu
uname -a
id
free -m
df -h / /mnt/d
for tool in python3 node npm c++ cmake ninja pkg-config cargo rustc elan lake lean bwrap rg; do
  command -v "$tool" || true
done
ls -d /home/*/Repos/Mirrors /home/*/Repos/MirrorCPP /home/*/Repos/MirrorECMA /home/*/Repos/MirrorRust /home/*/.elan/toolchains /home/*/.rustup/toolchains /opt/* 2>/dev/null || true
ps -eo comm | sort | uniq -c | sort -nr | head -12
