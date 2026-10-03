#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
LEAN_REPO="${LEAN_REPO:-../MirrorLean}"
if [[ ! -f "$LEAN_REPO/MirrorLean/ModelInterface.lean" ]]; then
  echo 'MirrorLean generated-binding SDK is required (set LEAN_REPO).' >&2
  exit 1
fi
.lake/build/bin/model_interface_lean_spec
.lake/build/bin/model_interface_gen check \
  --spec specs/Counter.tla \
  --contract test/fixtures/model-interface/counter/Counter.mirror-interface.json \
  --evidence test/fixtures/model-interface/counter/counter.itf.json \
  --param-var parameters \
  --lock test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json \
  --target mirrorlean-v1 --out test/fixtures/model-interface/counter/generated-lean
python3 - "$LEAN_REPO" <<'PY'
import json
from pathlib import Path
import shutil
import sys
root = Path.cwd()
sdk = Path(sys.argv[1]).resolve()
work = root / '.golden-build/model-interface-lean'
copied = work / 'sdk'
if copied.exists():
    shutil.rmtree(copied)
copied.mkdir(parents=True)
shutil.copytree(sdk / 'MirrorLean', copied / 'MirrorLean')
for name in ('MirrorLean.lean', 'lean-toolchain'):
    shutil.copyfile(sdk / name, copied / name)
(copied / 'lakefile.toml').write_text('name = "mirrorlean"\ndefaultTargets = ["MirrorLean"]\n[[lean_lib]]\nname = "MirrorLean"\n')
shutil.copyfile(root / 'test/fixtures/model-interface/counter/generated-lean/CounterMirror.lean', work / 'CounterMirror.lean')
shutil.copyfile(root / 'tools/model-interface-lean/Tests.lean', work / 'Tests.lean')
(work / 'WrongInput.lean').write_text('import CounterMirror\nexample : CounterMirror.TickInput := { stride := true }\n')
(work / 'WrongObservation.lean').write_text('import CounterMirror\nexample : CounterMirror.Observation := { count := "not an integer" }\n')
PY
stage="$PWD/.golden-build/model-interface-lean"
lake -d "$stage/sdk" build MirrorLean > "$stage/sdk-build.log" 2>&1 || {
  cat "$stage/sdk-build.log" >&2
  exit 1
}
export LEAN_PATH="$stage/sdk/.lake/build/lib/lean:$stage"
cd "$stage"
lean -o CounterMirror.olean CounterMirror.lean
lean -o TypesMirror.olean TypesMirror.lean
lean -o EmptyVariantsMirror.olean EmptyVariantsMirror.lean
lean --run Tests.lean
for negative in WrongInput WrongObservation; do
  if lean "$negative.lean" > "$negative.log" 2>&1; then
    echo "negative native compilation unexpectedly accepted: $negative" >&2
    exit 1
  fi
  if ! rg -q 'Type mismatch|type mismatch' "$negative.log"; then
    cat "$negative.log" >&2
    exit 1
  fi
done
echo 'mirrorlean native negative compilation: 2 rejected'
