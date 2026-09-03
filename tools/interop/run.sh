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
ECMA="${ECMA_REPO:-/home/nzsn/Repos/MirrorECMA}"
CPP="${CPP_REPO:-/home/nzsn/Repos/MirrorCPP}"
RUST="${RUST_REPO:-/home/nzsn/Repos/MirrorRust}"
HS_BIN="${HS_BIN:-/home/nzsn/Repos/ModelMirros/dist-newstyle/build/x86_64-linux/ghc-9.14.1/ModelMirrors-0.1.1.0/x/ModelMirrors/build/ModelMirrors/ModelMirrors}"
APALACHE_MC_BIN="${APALACHE_MC:-/home/nzsn/.local/bin/apalache/bin/apalache-mc}"
RF="$MIRRORS/.golden-build/rf"

cd "$MIRRORS"
lake build

for checkout in "$ECMA" "$CPP" "$RUST"; do
  if [[ ! -d "$checkout" ]]; then
    echo "missing client checkout: $checkout" >&2
    exit 1
  fi
done

mkdir -p .golden-build/ecma-interop "$RF"
ln -sfn "$ECMA" "$RF/_main"   # bazel-style runfiles layout for the harness

echo "== compiling MirrorECMA smoke suite (unmodified sources) =="
(cd "$ECMA" && ./node_modules/.bin/tsc --module nodenext --target es2022 \
  --esModuleInterop --skipLibCheck --moduleResolution nodenext \
  --outDir "$MIRRORS/.golden-build/ecma-interop" --rootDir "$ECMA" test/smoke.test.ts)

echo "== MirrorECMA unit + canonical wire-corpus tests =="
(cd "$ECMA" && MIRRORS_FIXTURES="$MIRRORS/test/fixtures" \
  NODE_OPTIONS="--experimental-vm-modules" \
  ./node_modules/.bin/jest --runInBand)
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

echo "== MirrorECMA negotiated model-interface: stdio + authorized mTLS =="
(cd "$RUNDIR" && LC_ALL=C.UTF-8 \
  MIRRORS_ROOT="$MIRRORS" MIRRORECMA_ROOT="$ECMA" \
  MIRROR_BIN="$LEAN_BIN" APALACHE_MC="$APALACHE_MC_BIN" \
  TS_NODE_PROJECT="$ECMA/tsconfig.model-interface.json" \
  node --loader "$ECMA/node_modules/ts-node/esm.mjs" \
    "$ECMA/test/model-interface-counter.smoke.ts")

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
  cargo test -- --nocapture)

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
