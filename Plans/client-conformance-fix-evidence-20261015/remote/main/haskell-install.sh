#!/bin/bash
set -euo pipefail
r=/home/jlc/Tools/mirrors-client-fixes-20261015
d=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
mkdir -p "$r/tools/haskell/bin" "$d/haskell"
cd "$d/downloads"
expected=$(awk '$2 ~ /cabal-install-3.16.1.0-x86_64-linux-deb11.tar.xz$/ {print $1}' cabal-SHA256SUMS)
test -n "$expected"
printf '%s  %s\n' "$expected" cabal-install-3.16.1.0-x86_64-linux-deb11.tar.xz | sha256sum -c -
tar -xJf cabal-install-3.16.1.0-x86_64-linux-deb11.tar.xz -C "$r/tools/haskell/bin" cabal
"$r/tools/haskell/bin/cabal" --version
mkdir -p "$r/tools/haskell/cabal/packages/hackage.haskell.org"
cat > "$r/tools/haskell/cabal/config" <<CONFIG
repository hackage.haskell.org
  url: https://hackage.haskell.org/
  secure: False
remote-repo-cache: $r/tools/haskell/cabal/packages
store-dir: $r/tools/haskell/cabal/store
logs-dir: $d/haskell/cabal-logs
jobs: 2
CONFIG
