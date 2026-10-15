#!/bin/bash
set -euo pipefail
r=/home/jlc/Tools/mirrors-client-fixes-20261015
d=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
export TMPDIR=/tmp/fix-tests
export PATH="$r/tools/haskell/bin:$r/tools/haskell/ghc/bin:/usr/bin:/bin"
export CABAL_DIR="$r/tools/haskell/cabal"
export LC_ALL=C.UTF-8
mkdir -p "$d/haskell/logs"
cd "$r/source/ModelMirros"
cabal --config-file="$CABAL_DIR/config" build ModelMirrors-test --builddir="$d/haskell/dist" -j2
cabal --config-file="$CABAL_DIR/config" test ModelMirrors-test --builddir="$d/haskell/dist" --test-show-details=direct --test-options='--list-tests --pattern NonModel'
cabal --config-file="$CABAL_DIR/config" test ModelMirrors-test --builddir="$d/haskell/dist" --test-show-details=direct --test-options='--pattern NonModel --num-threads=1'
cabal --config-file="$CABAL_DIR/config" build ModelMirrors-test --builddir="$d/haskell/dist" -j2
