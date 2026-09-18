#!/usr/bin/env bash
# Required root and native-server MirrorLean tests; never allow missing live inputs.
set -euo pipefail
MIRRORS="$(cd "$(dirname "$0")/../.." && pwd)"
LEAN_CLIENT="${LEAN_CLIENT_REPO:-$MIRRORS/../MirrorLean}"
export MIRROR_BIN="${MIRROR_BIN:-${LEAN_BIN:-$MIRRORS/.lake/build/bin/mirror}}"
export APALACHE_MC="${APALACHE_MC:-$(command -v apalache-mc || true)}"
export SPEC="$MIRRORS/specs/Counter.tla"
for path in "$MIRROR_BIN" "$APALACHE_MC"; do
  [[ -x "$path" ]] || { echo "Missing required executable: $path" >&2; exit 1; }
done
(cd "$LEAN_CLIENT" && lake build test smoke && .lake/build/bin/test && .lake/build/bin/smoke)
# Older published clients do not yet expose the additive async-test target.
if [[ -f "$LEAN_CLIENT/test/Async.lean" ]]; then
  (cd "$LEAN_CLIENT" && lake build async-test && .lake/build/bin/async-test)
fi
(cd "$LEAN_CLIENT/server-mode" &&
  lake build server-mode-test server-mode-test-discovery server-mode-smoke &&
  .lake/build/bin/server-mode-test &&
  .lake/build/bin/server-mode-test-discovery &&
  .lake/build/bin/server-mode-smoke)
echo 'MIRRORLEAN CONFORMANCE GREEN'
