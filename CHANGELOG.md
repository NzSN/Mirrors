# Changelog

All notable changes to the Lean 4 port of ModelMirrors. The port target is
byte-for-byte JSON-lines wire compatibility with ModelMirros@3496251
(Haskell); divergences are listed as ACCEPTED with rationale.

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
