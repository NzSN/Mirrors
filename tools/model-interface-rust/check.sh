#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
  # A shell caller may supply /c/...; native Python needs the Windows spelling.
  export RUST_REPO="$(cygpath -m "${RUST_REPO:-../MirrorRust}")"
fi
exec python3 tools/model-interface-rust/check.py
