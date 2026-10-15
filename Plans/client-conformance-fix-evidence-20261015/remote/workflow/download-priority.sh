#!/usr/bin/env bash
set -euo pipefail
cd /d/Desktop/Workspaces/Mirrors-client-fixes-20261015
mkdir -p downloads logs
fetch() { curl --fail --location --retry 2 --connect-timeout 20 --max-time 600 --silent --show-error "$1" -o "downloads/$2"; }
node_fetch() {
 fetch https://nodejs.org/dist/v24.15.0/node-v24.15.0-linux-x64.tar.xz node-v24.15.0-linux-x64.tar.xz
 fetch https://nodejs.org/dist/v24.15.0/SHASUMS256.txt node-SHASUMS256.txt
}
cabal_fetch() {
 fetch https://downloads.haskell.org/~cabal/cabal-install-3.16.1.0/cabal-install-3.16.1.0-x86_64-linux-deb11.tar.xz cabal-install-3.16.1.0-x86_64-linux-deb11.tar.xz
 fetch https://downloads.haskell.org/~cabal/cabal-install-3.16.1.0/SHA256SUMS cabal-SHA256SUMS
}
pnpm_fetch() {
 fetch https://registry.npmjs.org/pnpm/11.22.0 pnpm-metadata.json
 fetch https://registry.npmjs.org/pnpm/-/pnpm-11.22.0.tgz pnpm-11.22.0.tgz
}
node_fetch > logs/download-node.log 2>&1 & node_job=$!
cabal_fetch > logs/download-cabal.log 2>&1 & cabal_job=$!
pnpm_fetch > logs/download-pnpm.log 2>&1 & pnpm_job=$!
wait "$node_job"
wait "$cabal_job"
wait "$pnpm_job"
fetch https://github.com/containers/bubblewrap/releases/download/v0.9.0/bubblewrap-0.9.0.tar.xz bubblewrap-0.9.0.tar.xz
fetch https://api.github.com/repos/containers/bubblewrap/git/ref/tags/v0.9.0 bubblewrap-tag.json
echo PRIORITY_DOWNLOADS_COMPLETED
