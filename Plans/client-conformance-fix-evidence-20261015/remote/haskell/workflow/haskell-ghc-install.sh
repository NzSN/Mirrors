#!/bin/bash
set -euo pipefail
r=/home/jlc/Tools/mirrors-client-fixes-20261015
d=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
export TMPDIR=/tmp/fix-tests
cd "$d/downloads"
expected=$(awk '$2 ~ /ghc-9.14.1-x86_64-deb11-linux.tar.xz$/ {print $1}' ghc-SHA256SUMS)
printf '%s  %s\n' "$expected" ghc-9.14.1-x86_64-deb11-linux.tar.xz | sha256sum -c -
mkdir -p "$r/tools/haskell/unpack"
tar -xJf ghc-9.14.1-x86_64-deb11-linux.tar.xz -C "$r/tools/haskell/unpack"
cd "$r/tools/haskell/unpack/ghc-9.14.1-x86_64-unknown-linux"
./configure --prefix="$r/tools/haskell/ghc"
make install -j2
"$r/tools/haskell/ghc/bin/ghc" --version
