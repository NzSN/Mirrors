#!/usr/bin/env bash
# Regenerate and replay-gate the golden wire corpus (design doc section 8, Phase 0).
#
# The Haskell ModelMirrors checkout at /home/nzsn/Repos/ModelMirros is consumed
# read-only as an external artifact pinned by commit: its prebuilt inplace
# package (ModelMirrors-0.1.1.0-inplace) and cabal store instances are passed
# to ghc via -package-db / -package-id; nothing inside the Haskell tree is
# written or rebuilt. Update the paths/ids below if the checkout or store
# hashes move.
set -euo pipefail

cd /home/nzsn/Repos/Mirrors
mkdir -p .golden-build/gen .golden-build/replay test/fixtures
ghc -O0 -hide-all-packages -package-db /home/nzsn/.cabal/store/ghc-9.14.1-c6c3/package.db -package-db /home/nzsn/Repos/ModelMirros/dist-newstyle/packagedb/ghc-9.14.1 -package-id ModelMirrors-0.1.1.0-inplace -package-id aeson-2.3.1.0-f07ba8ad3fcf09cb68d7f1e75fcffdc4e82a1dd8abd67f21022e4529e21a643f -package-id base-4.22.0.0-fde1 -package-id text-2.1.3-2a27 -package-id network-3.2.8.0-3832058753340e5395be89506ae54384258ce58dcdbf2101be000049f5674519 -package-id containers-0.8-89c1 -package-id bytestring-0.12.2.0-3f3f -outputdir .golden-build/gen -o .golden-build/gen-golden tools/fixtures/GenGolden.hs
ghc -O0 -hide-all-packages -package-db /home/nzsn/.cabal/store/ghc-9.14.1-c6c3/package.db -package-db /home/nzsn/Repos/ModelMirros/dist-newstyle/packagedb/ghc-9.14.1 -package-id ModelMirrors-0.1.1.0-inplace -package-id aeson-2.3.1.0-f07ba8ad3fcf09cb68d7f1e75fcffdc4e82a1dd8abd67f21022e4529e21a643f -package-id base-4.22.0.0-fde1 -package-id text-2.1.3-2a27 -package-id network-3.2.8.0-3832058753340e5395be89506ae54384258ce58dcdbf2101be000049f5674519 -package-id containers-0.8-89c1 -package-id bytestring-0.12.2.0-3f3f -outputdir .golden-build/replay -o .golden-build/replay-golden tools/fixtures/ReplayGolden.hs

COMMIT="$(git -C /home/nzsn/Repos/ModelMirros rev-parse HEAD)"
./.golden-build/gen-golden test/fixtures "$COMMIT"
./.golden-build/replay-golden test/fixtures
