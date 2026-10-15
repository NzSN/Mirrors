#!/usr/bin/env bash
set -euo pipefail
cd /d/Desktop/Workspaces/Mirrors-client-fixes-20261015
mkdir -p downloads
curl --fail --location --retry 2 --connect-timeout 20 --max-time 1800 --silent --show-error https://downloads.haskell.org/~ghc/9.14.1/ghc-9.14.1-x86_64-deb11-linux.tar.xz -o downloads/ghc-9.14.1-x86_64-deb11-linux.tar.xz
curl --fail --location --retry 2 --connect-timeout 20 --max-time 120 --silent --show-error https://downloads.haskell.org/~ghc/9.14.1/SHA256SUMS -o downloads/ghc-SHA256SUMS
curl --fail --location --retry 2 --connect-timeout 20 --max-time 300 --silent --show-error https://downloads.haskell.org/~cabal/cabal-install-3.16.1.0/cabal-install-3.16.1.0-x86_64-linux-deb11.tar.xz -o downloads/cabal-install-3.16.1.0-x86_64-linux-deb11.tar.xz
curl --fail --location --retry 2 --connect-timeout 20 --max-time 120 --silent --show-error https://downloads.haskell.org/~cabal/cabal-install-3.16.1.0/SHA256SUMS -o downloads/cabal-SHA256SUMS
curl --fail --location --retry 2 --connect-timeout 20 --max-time 300 --silent --show-error https://nodejs.org/dist/v24.15.0/node-v24.15.0-linux-x64.tar.xz -o downloads/node-v24.15.0-linux-x64.tar.xz
curl --fail --location --retry 2 --connect-timeout 20 --max-time 120 --silent --show-error https://nodejs.org/dist/v24.15.0/SHASUMS256.txt -o downloads/node-SHASUMS256.txt
sha256sum downloads/* > downloads/observed-sha256.txt
