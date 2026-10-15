#!/usr/bin/env bash
set -euo pipefail
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
trap 'result=$?; printf "%s\n" "$result" > "$fix_build/ecma-focused.exit"' EXIT
export PATH="$fix_root/tools/bin:/home/jlc/.elan/toolchains/leanprover--lean4---v4.33.0/bin:/usr/bin:/bin"
export TMPDIR=/tmp/fix-tests CI=1 COREPACK_ENABLE_AUTO_PIN=0
cd "$fix_root/source/MirrorECMA"
python3 - "$fix_root" "$fix_build" <<'PY'
import hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1]);build=Path(sys.argv[2]);file=Path('node_modules/.modules.yaml')
original=file.read_bytes();metadata=json.loads(original)
assert metadata['packageManager']=='pnpm@11.22.0'
old=metadata['storeDir'];metadata['storeDir']=str(root/'tools/pnpm-store/v11')
file.write_text(json.dumps(metadata,indent=2)+'\n')
record={'originalModulesMetadataSha256':hashlib.sha256(original).hexdigest(),'oldStoreDir':old,
        'privateStoreDir':metadata['storeDir'],'sourceOrLockModified':False}
(build/'ecma-dependency-metadata.json').write_text(json.dumps(record,indent=2)+'\n')
PY
pnpm install --offline --frozen-lockfile --ignore-scripts --store-dir "$fix_root/tools/pnpm-store" > "$fix_build/logs/ecma-frozen-install.log" 2>&1
pnpm run check > "$fix_build/logs/ecma-check.log" 2>&1
pnpm run check:model-interface > "$fix_build/logs/ecma-check-model-interface.log" 2>&1
pnpm run check:examples > "$fix_build/logs/ecma-check-examples.log" 2>&1
pnpm run test --runInBand --no-watchman test/model-interface-runner.test.ts test/async-replay-report.test.ts test/model-interface-dynamic.test.ts test/async-dynamic-binding.test.ts test/client-spawn-allocation.test.ts test/transport.test.ts test/tls-key-mode.test.ts > "$fix_build/logs/ecma-focused-tests.log" 2>&1
pnpm run build > "$fix_build/logs/ecma-build.log" 2>&1
pnpm run build > "$fix_build/logs/ecma-build-repeat.log" 2>&1
echo ECMA_ALL_FOCUSED_GATES_PASSED
