#!/usr/bin/env bash
set -euo pipefail
cd /d/Desktop/Workspaces/Mirrors-client-fixes-20261015/downloads
f=ghc-9.14.1-x86_64-deb11-linux.tar.xz
n=$(stat -c %s "$f")
total=307306404
curl -fL --retry 3 https://downloads.haskell.org/~ghc/9.14.1/SHA256SUMS -o ghc-SHA256SUMS
step=$(((total-n+3)/4))
pids=()
for i in 0 1 2 3; do
 start=$((n+i*step)); end=$((start+step-1)); ((end>=total)) && end=$((total-1))
 curl -fL --retry 4 --range "$start-$end" https://downloads.haskell.org/~ghc/9.14.1/ghc-9.14.1-x86_64-deb11-linux.tar.xz -o "$f.part$i" >"ghc-range-$i.log" 2>&1 &
 pids+=("$!")
done
for p in "${pids[@]}"; do wait "$p"; done
for i in 0 1 2 3; do start=$((n+i*step)); end=$((start+step-1)); ((end>=total)) && end=$((total-1)); test "$(stat -c %s "$f.part$i")" = "$((end-start+1))"; done
cp "$f" "$f.assembled"
cat "$f.part0" "$f.part1" "$f.part2" "$f.part3" >> "$f.assembled"
expected=$(awk '$2 ~ /ghc-9.14.1-x86_64-deb11-linux.tar.xz$/ {print $1}' ghc-SHA256SUMS)
test -n "$expected"
printf '%s  %s\n' "$expected" "$f.assembled" | sha256sum -c -
mv "$f.assembled" "$f"
sha256sum "$f" cabal-install-3.16.1.0-x86_64-linux-deb11.tar.xz
