#!/usr/bin/env bash
# t17 interop validation matrix (design doc section 2 Goal 2, section 8 Phase 6).
# Clients: MirrorECMA, MirrorCPP, MirrorRust, and the Haskell ModelMirrors
# `validate` client (the pinned reference wire consumer).
#
# Transports: stdio + TCP + mTLS (t26 fixes landed; released by the
# captain). The MirrorECMA harness also exercises the TLS negatives
# (wrong pin, untrusted client) and Consul-style registry discovery.
set -euo pipefail

MIRRORS="$(cd "$(dirname "$0")/../.." && pwd)"
LEAN_BIN="${LEAN_BIN:-$MIRRORS/.lake/build/bin/mirror}"
ECMA="${ECMA_REPO:-$MIRRORS/../MirrorECMA}"
CPP="${CPP_REPO:-$MIRRORS/../MirrorCPP}"
RUST="${RUST_REPO:-$MIRRORS/../MirrorRust}"
HS="${HS_REPO:-$MIRRORS/../ModelMirrors}"
APALACHE_MC_BIN="${APALACHE_MC:-$(command -v apalache-mc || true)}"
RF="$MIRRORS/.golden-build/rf"

cd "$MIRRORS"
source tools/ci/versions.env
for checkout in "$ECMA" "$CPP" "$RUST" "$HS"; do
  if [[ ! -d "$checkout" ]]; then
    echo "missing client checkout: $checkout" >&2
    exit 1
  fi
done
if [[ ! -x "$APALACHE_MC_BIN" ]]; then
  echo "full interop requires live Apalache; set APALACHE_MC to its executable" >&2
  exit 1
fi
: "${HS_BIN:?set HS_BIN to the already built ModelMirrors executable}"
[[ -x "$HS_BIN" ]] || { echo "missing Haskell binary: $HS_BIN" >&2; exit 1; }
export HS_BIN LEAN_BIN HS_REPO="$HS" APALACHE_MC="$APALACHE_MC_BIN"

echo "== revisions and tool versions =="
for checkout in "$MIRRORS" "$ECMA" "$CPP" "$RUST" "$HS"; do
  printf '%s: %s\n' "$checkout" "$(git -C "$checkout" rev-parse HEAD)"
  git -C "$checkout" status --short
done
node --version
pnpm --version
lake --version
rustc --version
ghc --version
cabal --version
java -version
"$APALACHE_MC_BIN" version
cmake --version
cc --version
openssl version
if [[ "${INTEROP_VERIFY_PINS:-0}" == 1 ]]; then
  for entry in "$ECMA:${ECMA_REF:-$ECMA_BASELINE}" "$CPP:$CPP_BASELINE" \
    "$RUST:$RUST_BASELINE" "$HS:$HS_BASELINE"; do
    checkout="${entry%:*}"
    expected="${entry##*:}"
    [[ "$(git -C "$checkout" rev-parse HEAD)" == "$expected" ]] || {
      echo "checkout does not match baseline: $checkout ($expected)" >&2; exit 1;
    }
  done
  [[ "$(node --version)" == "v$NODE_VERSION" ]]
  [[ "$(pnpm --version)" == "$PNPM_VERSION" ]]
  [[ "$("$APALACHE_MC_BIN" version)" == "$APALACHE_VERSION" ]]
fi
lake build

mkdir -p .golden-build/ecma-interop "$RF"
ln -sfn "$ECMA" "$RF/_main"   # bazel-style runfiles layout for the harness

echo "== compiling MirrorECMA smoke suite (unmodified sources) =="
(cd "$ECMA" && ./node_modules/.bin/tsc --module nodenext --target es2022 \
  --esModuleInterop --skipLibCheck --moduleResolution nodenext \
  --outDir "$MIRRORS/.golden-build/ecma-interop" --rootDir "$ECMA" test/smoke.test.ts)

echo "== MirrorECMA unit + canonical wire-corpus tests =="
(cd "$ECMA" && MIRRORS_FIXTURES="$MIRRORS/test/fixtures" \
  NODE_OPTIONS="--experimental-vm-modules" \
  ./node_modules/.bin/jest --runInBand --no-watchman)
(cd "$ECMA" && ./node_modules/.bin/tsc \
  -p tsconfig.model-interface.json --noEmit)

echo "== MirrorECMA interop: stdio + TCP + mTLS + registry =="
# Run from a writable copy of the client assets: the spawned mirror shells
# out to apalache, which writes _apalache-out/ under its cwd (the ECMA
# checkout itself may be read-only; the client sources are unmodified).
# RUNFILES unset => the upstream harness runs its TLS/registry scenarios
# too (mTLS with pinned fingerprints, wrong-pin/rogue-client negatives,
# registry discovery/failover/fail-closed).
RUNDIR="$MIRRORS/.golden-build/ecma-rundir"
rm -rf "$RUNDIR" && mkdir -p "$RUNDIR"
cp -r "$ECMA/specs" "$RUNDIR/"
(cd "$RUNDIR" && LC_ALL=C.UTF-8 MIRROR_BIN="$LEAN_BIN" \
  SPEC="$MIRRORS/specs/Counter.tla" \
  node "$MIRRORS/.golden-build/ecma-interop/test/smoke.test.js")

echo "== MirrorECMA negotiated model-interface D3+D4: stdio + authorized mTLS =="
# Covers compiled matched verification, dynamic resolved -> not_modified cache
# reuse, wrong-observer step_mismatch, allowlisted mTLS verification, authorized
# descriptor read, denial without descriptor-read scope, and no-allowlist denial.
(cd "$RUNDIR" && LC_ALL=C.UTF-8 \
  MIRRORS_ROOT="$MIRRORS" MIRRORECMA_ROOT="$ECMA" \
  MIRROR_BIN="$LEAN_BIN" APALACHE_MC="$APALACHE_MC_BIN" \
  TS_NODE_PROJECT="$ECMA/tsconfig.model-interface.json" \
  node --loader "$ECMA/node_modules/ts-node/esm.mjs" \
    "$ECMA/test/model-interface-counter.smoke.ts")

echo "== MirrorECMA generated Counter tutorial: artifacts + replay + real bug =="
# Build the documented executable and acceptance harness once, without writing
# into the client checkout. The harness launches that executable from ECMA's
# root and keeps its stale-output negative fixture in a temporary directory.
COUNTER_BUILD="$MIRRORS/.golden-build/ecma-generated-counter"
mkdir -p "$COUNTER_BUILD"
printf '%s\n' '{"type":"module"}' > "$COUNTER_BUILD/package.json"
(cd "$ECMA" && ./node_modules/.bin/tsc \
  -p tsconfig.examples.json --outDir "$COUNTER_BUILD")
COUNTER_SMOKE_ARGS=(--live)
(cd "$RUNDIR" && LC_ALL=C.UTF-8 \
  MIRRORS_ROOT="$MIRRORS" MIRRORECMA_ROOT="$ECMA" \
  MIRROR_BIN="$LEAN_BIN" APALACHE_MC="$APALACHE_MC_BIN" \
  MODEL_INTERFACE_GEN="${MODEL_INTERFACE_GEN:-$MIRRORS/.lake/build/bin/model_interface_gen}" \
  node "$COUNTER_BUILD/test/generated-counter.smoke.js" "${COUNTER_SMOKE_ARGS[@]}")

echo "== MirrorCPP conformance: unit/golden + real stdio/TCP/mTLS =="
CPP_BUILD="$MIRRORS/.golden-build/mirrorcpp"
cmake -S "$CPP" -B "$CPP_BUILD" -DMIRRORCPP_BUILD_TESTS=ON
cmake --build "$CPP_BUILD" -j2
MIRROR_BIN="$LEAN_BIN" SPEC="$MIRRORS/specs/Counter.tla" \
  ctest --test-dir "$CPP_BUILD" --output-on-failure

echo "== MirrorRust conformance: unit/golden + real stdio/TCP/mTLS/registry =="
(cd "$RUST" && \
  CARGO_TARGET_DIR="$MIRRORS/.golden-build/mirrorrust-target" \
  MIRRORS_FIXTURES="$MIRRORS/test/fixtures" \
  MIRROR_BIN="$LEAN_BIN" SPEC="$MIRRORS/specs/Counter.tla" \
  cargo test --locked -- --nocapture)

echo "== Haskell validate client over TCP =="
# The mirror shells out to apalache, which writes _apalache-out/ under its
# cwd; run from the (writable) Mirrors tree with a workspace-local spec copy.
mkdir -p .golden-build/specs
cp "$ECMA/specs/HourClock.tla" .golden-build/specs/
PORT=$((10000 + RANDOM % 20000))
"$LEAN_BIN" --serve "$PORT" &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
for i in $(seq 1 50); do
  if (echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null; then break; fi
  sleep 0.2
done
LC_ALL=C.UTF-8 "$HS_BIN" validate --host 127.0.0.1 --port "$PORT" \
  --spec "$MIRRORS/.golden-build/specs/HourClock.tla" --inv Inv --bound 10
kill $SRV 2>/dev/null || true

echo "== Haskell validate client over mTLS (pinned + negatives) =="
bash "$(dirname "$0")/hs-mtls.sh"

echo "INTEROP MATRIX GREEN (stdio, TCP, mTLS; ECMA + CPP + Rust + Haskell clients)"
