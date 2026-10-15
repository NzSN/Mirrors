#!/usr/bin/env bash
set -euo pipefail
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
trap 'result=$?; printf "%s\n" "$result" > "$fix_build/ecma-focused-2.exit"' EXIT
export PATH="$fix_root/tools/bin:/home/jlc/.elan/toolchains/leanprover--lean4---v4.33.0/bin:/usr/bin:/bin"
export TMPDIR=/tmp/fix-tests CI=1 COREPACK_ENABLE_AUTO_PIN=0
cd "$fix_root/source/MirrorECMA"
pnpm install --frozen-lockfile --network-concurrency=4 --ignore-scripts --store-dir "$fix_root/tools/pnpm-store" > "$fix_build/logs/ecma-frozen-install-online.log" 2>&1
pnpm run check > "$fix_build/logs/ecma-check.log" 2>&1
pnpm run check:model-interface > "$fix_build/logs/ecma-check-model-interface.log" 2>&1
pnpm run check:examples > "$fix_build/logs/ecma-check-examples.log" 2>&1
pnpm run test --runInBand --no-watchman test/model-interface-runner.test.ts test/async-replay-report.test.ts test/model-interface-dynamic.test.ts test/async-dynamic-binding.test.ts test/client-spawn-allocation.test.ts test/transport.test.ts test/tls-key-mode.test.ts > "$fix_build/logs/ecma-focused-tests.log" 2>&1
pnpm run build > "$fix_build/logs/ecma-build.log" 2>&1
pnpm run build > "$fix_build/logs/ecma-build-repeat.log" 2>&1
echo ECMA_ALL_FOCUSED_GATES_PASSED
