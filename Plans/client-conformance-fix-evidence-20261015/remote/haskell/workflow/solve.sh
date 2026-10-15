#!/bin/bash
set -euo pipefail
r=/home/jlc/Tools/mirrors-client-fixes-20261015
d=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
export TMPDIR=/tmp/fix-tests
export PATH="$r/tools/haskell/bin:$r/tools/haskell/ghc/bin:/usr/bin:/bin"
export CABAL_DIR="$r/tools/haskell/cabal"
export LC_ALL=C.UTF-8
cd "$r/source/ModelMirros"
cabal --config-file="$CABAL_DIR/config" build ModelMirrors-test --builddir="$d/haskell/dist" --dry-run -j2
