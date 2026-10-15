#!/bin/bash
set -euo pipefail
r=/home/jlc/Tools/mirrors-client-fixes-20261015
export PATH="$r/tools/haskell/bin:$r/tools/haskell/ghc/bin:/usr/bin:/bin"
export TMPDIR=/tmp/fix-tests
export CABAL_DIR="$r/tools/haskell/cabal"
cabal --config-file="$CABAL_DIR/config" update -v2
