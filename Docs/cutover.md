# Cutover plan: Haskell ModelMirros → Lean 4 Mirrors

Status: 2026-08-23. The Lean port is feature-complete for phases 0-6
and green on every gate (lake build, lake test — 8 gates, fixtures
replay byte-identical, differential stdio vs the Haskell test binary,
job-store parity, apalache CLI, explorer, transport, registry) and on
the full client interop matrix (tools/interop/run.sh: stdio + TCP +
mTLS, MirrorECMA + Haskell validate, TLS/registry negatives).

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
already listed below). Live-gated by tools/AsyncSpec.lean (self-skipping on Windows, where
async server sessions are withdrawn pending a Lean 4.33 runtime fix —
see Docs/async-enablement-design.md §6; Windows serves the t30 sync
sequential sessions).

## 3. Accepted divergences

- TLS wildcard scope: the OpenSSL shim accepts only leftmost-label
  certificate wildcards; the Haskell tls package (x509-validation)
  accepts wildcards anywhere in the label. The Lean behavior is
  stricter and fail-closed. Documented in Docs/tls-ffi-review.md;
  accepted by the captain.
- Out-of-order job message before register (NOT yet accepted as
  permanent): Lean answers register_error ("async jobs arrive in
  Phase 4"), Haskell answers protocol_error ("Expected Register
  message"). Trivial to harmonize if desired; flagged because it is
  observable on the wire for a malformed session. Track as an open
  item; MirrorECMA does not exercise it.

## 4. MirrorRust leg — OPEN / substituted

The interop matrix substitutes the Haskell ModelMirros validate
client as the second real client (captain ruling: substitution
ACCEPTED; the Haskell client is the reference wire consumer).
MirrorRust was NOT run: no MirrorRust client is available in this
environment. The leg stays open: before final deprecation of the
Haskell implementation, run a MirrorRust client against the Lean
mirror over stdio, TCP, and mTLS (pinned fingerprints + negatives),
following tools/interop/INTEROP.md. Only MirrorECMA + Haskell
coverage may be claimed today.

## 5. Haskell deprecation plan

1. Soak: run both implementations side by side; diff wire transcripts
   on real workloads (the golden corpus + tools/interop/run.sh give
   the automated version of this).
2. Close the open legs: MirrorRust interop (§4) and the pre-register
   job-message error harmonization (§3).
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