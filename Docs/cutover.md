# Cutover plan: Haskell ModelMirros → Lean 4 Mirrors

Status: source inventory refreshed 2026-09-08. The Lean port implements the
original phases 0–6, pooled async server sessions on both platforms,
model-interface compilation/negotiation, and the product-version CLI. The
[documentation index](README.md) lists the current 12 test executables,
compiler checks, and external tiers. The interop runner includes MirrorECMA,
MirrorCPP, MirrorRust, and the Haskell reference client. Dated results below
remain evidence of their recorded runs, not a current hosted-CI or service check.

## 1. Final state

- Wire protocol: byte-for-byte JSON-lines parity with
  ModelMirros@3496251, pinned by the frozen golden corpus
  (test/fixtures/, 63 transcripts + decode_only JS-shape entries) and
  by live interop with two unmodified real clients.
- Transports: stdio (default), TCP (--serve), mTLS
  (--server --tls --cert --key --ca [--registry]), client validate
  over direct TCP/mTLS or registry discovery with fingerprint pinning.
- Trusted TCB: Ffi/ C shims (sockets, OpenSSL TLS) + Shell effectful
  layer; everything under Core/ and Codec/ is verified/pure.

## 2. Pinned codec semantics (interoperability contract)

These semantics are pinned by fixtures + the Haskell oracle
(tools/fixtures/GenDecodeOnly.hs); changing them is a wire break:

- absent-vs-null: optional client fields decode with Haskell .:?
  semantics — an absent key and an explicit null are the same None.
  JS clients (MirrorECMA) omit optional keys; Haskell clients send
  explicit nulls. Lean accepts both.
- encoder asymmetry (reproduced from Haskell): register and
  register_trace_gen emit explicit nulls for absent spec/destPath,
  while register_trace_gen_async, register_validate*, and await_job
  OMIT absent keys. Pinned by decode_only.jsonl.
- defaults on decode (Haskell Apalache/Types.hs): invariant and
  paramVars default to "", lengthBound to 10, numTraces to 1, and
  view is nullable (Maybe Text; --view passed only when present).
- ITF values (normNums/bare-number): bare integral JSON numbers are
  accepted as VInt in report_state state maps (matching the Haskell
  FromJSON Value instance, which is what normNums fed); encoders
  always emit #bigint. Non-integral bare numbers are rejected with a
  decode error.

## 2b. Async modes (t31) — WIRED

The async job machinery (Core.Jobs machine + Shell.Jobs store + the
runAsync session loop) is now wired into the shipped binary: --serve
(TCP) and --server (mTLS) run one async session per connection over a
single process-shared job store; --jobs N sizes it (capacity and
worker slots, default 4). A connection ending cancels and evicts
exactly its own jobs. The stdio default mode stays sync-only (Haskell
parity): async registers answer register_error there (divergence tag
already listed below). Live-gated by tools/AsyncSpec.lean.

t33 update (2026-08-31): the Windows withdrawal described in
Docs/async-enablement-design.md §6 is SUPERSEDED — both server modes
now run worker-pool sessions on both platforms (the pool's
never-completing workers eliminate the Windows task-teardown race),
async_spec was unskipped and validated on Windows, and the ledger records a
pooled r-windev service redeploy on 2026-08-31. See
Docs/worker-pool-design.md / Docs/worker-pool-impl-status.md.

## 3. Accepted divergences

- TLS wildcard scope: the OpenSSL shim accepts only leftmost-label
  certificate wildcards; the Haskell tls package (x509-validation)
  accepts wildcards anywhere in the label. The Lean behavior is
  stricter and fail-closed. Documented in Docs/tls-ffi-review.md;
  accepted by the captain.
- Async job messages in synchronous stdio mode (NOT yet accepted as
  permanent): Lean answers register_error ("async jobs arrive in
  Phase 4"), Haskell answers protocol_error ("Expected Register
  message"). Trivial to harmonize if desired; flagged because it is
  observable on that wire path. Server-mode job controls are supported,
  including a query from another connection without a new registration.
  Track the stdio error-tag choice as an open item.

## 4. Non-Lean client legs — implementation and runner green

`tools/interop/run.sh` runs the MirrorECMA, MirrorCPP, and MirrorRust
unit/golden suites and their live gates against this Lean mirror. MirrorRust
now covers stdio, plain TCP, TLS 1.3 mTLS, registry discovery/pinning/failover,
async jobs, and positive plus deliberately incorrect Counter replay. The mTLS
gate uses an ephemeral PKI and covers SAN-only verification, TLS-version
rejection, client authentication, case-insensitive correct pinning, wrong-pin
rejection, and POSIX key-permission rejection.

The implementation and runner legs are green as of 2026-09-01. The Haskell
reference client remains in the matrix as an independent compatibility oracle,
not as a substitute for a missing non-Lean client gate.

## 5. Haskell deprecation plan

1. Soak: run both implementations side by side; diff wire transcripts
   on real workloads (the golden corpus + tools/interop/run.sh give
   the automated version of this).
2. Keep the implemented MirrorRust runner/CI wiring (§4) in the regression
   matrix and decide the stdio async-message error harmonization (§3).
3. Freeze ModelMirros@3496251 as the read-only reference artifact
   (fixtures oracle + differential test binary). It stays pinned in
   CI (.github/workflows/interop.yml) as the oracle.
4. Announce deprecation of the Haskell mirror; keep the repo
   available for audit; move issue tracking to the Lean repo.
5. Removal criteria: two consecutive release cycles of green interop
   matrix + zero wire-divergence reports, MirrorRust leg green.

## 6. Verification commands

- lake build && lake test (all gates; APALACHE_MC set enables the
  real-apalache integration specs)
- tools/fixtures/run.sh (golden corpus vs the Haskell oracle)
- tools/interop/run.sh (full client matrix incl. mTLS + negatives)
- CI: .github/workflows/interop.yml (checkout MirrorECMA +
  ModelMirros, lean-action, cabal-built Haskell client, run.sh)
