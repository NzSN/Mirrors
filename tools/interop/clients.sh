#!/usr/bin/env bash
# Focused C++/Lean/Rust acceptance; all live dependencies are required.
set -euo pipefail
MIRRORS="$(cd "$(dirname "$0")/../.." && pwd)"
CPP="${CPP_REPO:-$MIRRORS/../MirrorCPP}"
RUST="${RUST_REPO:-$MIRRORS/../MirrorRust}"
LEAN_CLIENT="${LEAN_CLIENT_REPO:-$MIRRORS/../MirrorLean}"
export MIRROR_BIN="${MIRROR_BIN:-$MIRRORS/.lake/build/bin/mirror}"
export APALACHE_MC="${APALACHE_MC:-$(command -v apalache-mc || true)}"
export MIRRORS_FIXTURES="$MIRRORS/test/fixtures"
export MIRRORS_CLIENT_CONFORMANCE="$MIRRORS/test/client-conformance/async-replies.json"
export SPEC="$MIRRORS/specs/Counter.tla"
for path in "$MIRROR_BIN" "$APALACHE_MC"; do
  [[ -x "$path" ]] || { echo "Missing required executable: $path" >&2; exit 1; }
done
for path in "$CPP" "$RUST" "$LEAN_CLIENT"; do
  [[ -d "$path" ]] || { echo "Missing client checkout: $path" >&2; exit 1; }
done
for entry in "$CPP/test" "$RUST/tests" "$LEAN_CLIENT/test"; do
  cmp "$MIRRORS_CLIENT_CONFORMANCE" "$entry/fixtures/client-conformance/async-replies.json"
done
cmake -S "$CPP" -B "$MIRRORS/.golden-build/mirrorcpp" -DMIRRORCPP_BUILD_TESTS=ON
cmake --build "$MIRRORS/.golden-build/mirrorcpp" -j2
ctest --test-dir "$MIRRORS/.golden-build/mirrorcpp" --output-on-failure
(cd "$RUST" && CARGO_TARGET_DIR="$MIRRORS/.golden-build/mirrorrust-target" cargo test --locked -- --nocapture)
bash "$MIRRORS/tools/interop/lean-client.sh"
echo 'CPP LEAN RUST CONFORMANCE GREEN'
