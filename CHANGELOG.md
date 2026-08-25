# Changelog

All notable changes to the Lean 4 port of ModelMirrors. The port target is
byte-for-byte JSON-lines wire compatibility with ModelMirros@3496251
(Haskell); divergences are listed as ACCEPTED with rationale.

## t31 — async validate/trace-gen enabled in production modes (2026-08-25)

- --serve (TCP) and --server (mTLS) now run concurrent ASYNC sessions:
  one runAsync session per connection over ONE process-shared job store
  (job ids unique across connections); --jobs N sizes the store
  (capacity + worker slots, default 4). Session end cancels + evicts
  exactly that session's jobs.
- Fixed a latent bug this wiring exposed: Shell.Apalache.jobRunner
  genTraces read the generated trace files AFTER the try/finally that
  removes the session dir — the read raced the deletion and crashed the
  job body. Reads now happen inside the try.
- Store job-thread crash reports now include the exception text.
- stdio default mode stays sync-only (Haskell parity; the
  register_error vs Haskell protocol_error tag divergence for stdio
  async rejects remains documented).
- New gate: tools/AsyncSpec.lean (APALACHE_MC-gated) — async
  validate/trace-gen round-trips over live --serve and --server --tls
  children, sync/async congruence, cancel, unknown-id, and
  two-connection concurrency.

## t31 follow-up — Windows async rollback + transport fix (2026-08-25)

- Windows: async server sessions withdrawn. A Lean 4.33 Windows
  runtime bug (session task touching the shared job store segfaults
  on quick teardown; see Docs/async-enablement-design.md §6) makes
  both concurrent and sequential async serving unsafe there. Windows
  builds now serve t30 sync sequential sessions in --serve/--server;
  async_spec self-skips on Windows; the r-windev service was rolled
  back to the sync binary. Linux is unaffected and fully gated.
- Tcp.lean: the shared 64 KiB receive scratch is now per-connection
  (latent cross-connection data race under concurrent sessions).

## 0.1.0 — Lean 4 port, phases 0-6 complete (2026-08-23)

### Added
- Verified pure core (Core/): Value, Trace, Diff, Protocol state machine,
  Jobs lifecycle, Resource — no IO.
- Total JSON codecs (Codec/) with round-trip proofs against the golden
  wire corpus frozen from the Haskell implementation (test/fixtures/,
  63 transcripts; decode_only entries pin JS-client wire shapes).
- Effectful shell (Shell/): stdio + TCP + mTLS transports, session
  drivers (sync + async job store), apalache CLI adapter, explorer
  JSON-RPC client, Consul-style registry, client validate command,
  full CLI parity (mirror default stdio, --serve, --server --tls,
  validate).
- C FFI shims (Ffi/): sockets (select-based accept polling, signals
  without SA_RESTART) and an OpenSSL 3 TLS shim (TLS 1.3 only, mTLS
  with client certs required, fingerprint pinning, SAN-only policy).
- Regression gates: fixtures replay, differential stdio suite vs the
  Haskell test binary, job-store parity, apalache CLI spec, explorer
  spec, transport spec (throwaway PKI, negatives), registry spec (mock
  Consul, SIGTERM deregistration e2e). CI: .github/workflows/interop.yml.
- Client interop validation (tools/interop/): full matrix green —
  unmodified MirrorECMA client over stdio/TCP/mTLS + TLS/registry
  negatives, and the Haskell validate client over TCP/mTLS (pinned
  fingerprint; wrong pin and rogue client fail fast).

### Fixed (found by interop / differential testing)
- Codec: optional fields rejected when the key is absent (JS clients
  omit them; Haskell .:? treats absent == null). optFieldStr now has
  full .:? semantics; pinned by decode_only.jsonl JS-shape entries.
- Codec: missing Haskell defaults (invariant/paramVars "", lengthBound
  10, numTraces 1, view nullable) caused inline-spec register failures.
- Codec: encoder asymmetry pinned and reproduced — register /
  register_trace_gen emit explicit nulls for absent spec/destPath, while
  register_trace_gen_async / register_validate* / await_job OMIT absent
  keys.
- Shell: register_trace_gen ignored destPath and read trace files after
  session-dir cleanup; explorer dispatch passed exports/invariants
  swapped.
- Ffi: sequential TLS connections wedged the server — (a) Ffi.tlsClose
  was declared BaseIO Unit against a uint64_t-returning C function
  (raw 0 register read as a boxed null; task never resumed); (b)
  SSL_shutdown blocked on the peer's already-consumed close_notify.
  Now BaseIO UInt64 + non-blocking shutdown around the close_notify.
- TLS review findings (Docs/tls-ffi-review.md): ssl_finalizer NULL
  guard, server-side key-permission checks, signed expiry arithmetic,
  X509_VERIFY_PARAM pinning with SAN-only policy, negative-test
  coverage (expired/wrong-CA/SAN-mismatch/IP-literal/oversized line).

### ACCEPTED divergences (documented, deliberate)
- TLS certificate wildcard scope: OpenSSL X509_check_host accepts
  leftmost-label wildcards only, which is stricter than the Haskell
  tls package's x509-validation (wildcards anywhere in the label).
  Fail-closed; see Docs/tls-ffi-review.md.
- ITF bare numbers: the verified value codec accepts bare integral
  JSON numbers in report_state state maps (Haskell FromJSON Value
  parity), while encoders always emit #bigint — matching the Haskell
  asymmetry exactly (formerly the normNums normalization in Haskell).
- Out-of-order job message before register: Lean answers
  register_error ("async jobs arrive in Phase 4"); the Haskell server
  answers protocol_error ("Expected Register message"). Flagged, not
  yet harmonized — see Docs/cutover.md (open items).

### Known open items
- MirrorRust interop leg not run (no MirrorRust client in this
  environment); Haskell validate substitutes as the second real
  client. See Docs/cutover.md.
- lake executables do not relink when only the C shims change;
  delete bin/mirror (and the .o) to force a relink.