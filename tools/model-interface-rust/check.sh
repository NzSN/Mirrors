#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
RUST_REPO="${RUST_REPO:-../MirrorRust}"
if ! command -v cargo >/dev/null || [[ ! -f "$RUST_REPO/Cargo.toml" ]]; then
  echo 'SKIP Rust generated binding execution: cargo and a MirrorRust checkout are required (RUST_REPO).'
  exit 0
fi
# The Lean suite emits the synthetic structural-type corpus.
.lake/build/bin/model_interface_spec
python3 - "$RUST_REPO" <<'PY'
from pathlib import Path
import json
import sys
root = Path.cwd()
work = root / '.golden-build/model-interface-rust'
work.mkdir(parents=True, exist_ok=True)
(work / 'Cargo.toml').write_text('''[package]
name = "mirrors-generated-rust-tests"
version = "0.0.0"
edition = "2021"
[dependencies]
num-bigint = "0.4"
serde_json = "1"
mirrorrust = { path = %s }
[lib]
path = %s
''' % (json.dumps(str(Path(sys.argv[1]).resolve())), json.dumps(str(root / 'tools/model-interface-rust/tests.rs'))))
PY
CARGO_TARGET_DIR="$PWD/.golden-build/mirrorrust-target" cargo test --manifest-path .golden-build/model-interface-rust/Cargo.toml
