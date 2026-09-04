# Client interop validation (Phase 6)

Unmodified real clients must interoperate with the Lean mirror over the
JSON-lines wire protocol, byte-for-byte, on every transport.

Status (2026-09-04): FULL MATRIX GREEN. MirrorECMA smoke suite
GREEN over stdio, TCP, AND mTLS (register, register_traces,
register_trace_gen incl. destPath copy + trace inlining, register_explore,
register_explore_session, inline multi-module specs; 18 scenario runs over
stdio + TCP daemon + mTLS daemon) PLUS the harness TLS negatives (wrong
pin, wrong-CA/rogue client, key-mode) and registry discovery/failover/
fail-closed. Haskell `validate`: VALID over TCP and over mTLS with pinned
fingerprint; wrong pin fails fast (fingerprint mismatch); rogue client
cert rejected at handshake. The model-interface D3+D4 slice additionally
verifies the generated Counter digest before adapter construction; exercises
dynamic descriptor `resolved -> not_modified` cache reuse over stdio; completes
compiled verification and authorized descriptor read over allowlisted mTLS;
rejects wrong digests, missing descriptor-read scope, and non-allowlisted
clients before application callbacks; and keeps wrong observers on ordinary
`step_mismatch`. MirrorCPP additionally generates the same Counter interface
through `mirrorcpp-v1`, selects its compiled adapter by the exact four-part key,
and exercises negotiated replay over stdio and allowlisted mTLS with
wrong-digest and unauthorized zero-SUT negatives.

## Matrix

| Client            | stdio | TCP | mTLS |
|-------------------|-------|-----|------|
| MirrorECMA (TS)   | run.sh (smoke suite) | run.sh (smoke suite over \`--serve\`) | run.sh (smoke suite over \`--server --tls\`, pinned + negatives + registry) |
| Haskell \`validate\` (ModelMirrors) | n/a (TCP client) | run.sh | run.sh (hs-mtls.sh: pinned fp + wrong-pin/rogue negatives) |
| MirrorCPP         | `real_mirror_hourclock` | same suite over `--serve` | same suite over `--server --tls` with ephemeral PKI |
| MirrorLean        | `test/Smoke.lean` | transport/integration gates | `ServerModeSmoke.lean` with ephemeral PKI |
| MirrorRust        | `tests/smoke.rs` | `tests/server_mode_smoke.rs` over `--serve` | same suite over `--server --tls`, pinned + negatives |

Runner: `tools/interop/run.sh` (also wired as the CI job
`.github/workflows/interop.yml`). It runs the MirrorECMA, MirrorCPP, and
MirrorRust unit/golden suites plus their live Counter replay and transport
negatives before the Haskell reference-client legs.

What run.sh does:

1. \`lake build\` the Lean mirror.
2. Compiles MirrorECMA's unmodified \`test/smoke.test.ts\` with the repo's own
   \`tsc\` into \`.golden-build/ecma-interop\` and runs it from a writable
   rundir (\`.golden-build/ecma-rundir\`; apalache writes \`_apalache-out/\`
   under the mirror's cwd). \`MIRROR_BIN\` points at the Lean
   \`.lake/build/bin/mirror\`. The suite exercises register,
   register_traces, register_trace_gen (destPath copy + inline traces),
   register_explore, register_explore_session, inline specs, and repeats
   every scenario over TCP against \`mirror --serve\`, followed by its mTLS,
   TLS-negative, and registry scenarios.
3. Typechecks and runs MirrorECMA's standalone D3+D4 model-interface Counter
   slice. It checks the generated lock/source bytes, exact digest negotiation,
   fail-closed ordering, dynamic `resolved -> not_modified` cache reuse,
   source-free local handlers, wrong-observer `step_mismatch`, allowlisted mTLS
   verification and descriptor read, descriptor-read denial, and no-allowlist
   denial.
4. Starts \`mirror --serve\` and runs the Haskell ModelMirrors \`validate\`
   client against it over TCP.

The mTLS legs run the same unmodified clients with pinned leaf
fingerprints (SHA-256 hex of the DER) and negative cases.

## Environment notes

- apalache-mc 0.57.0 at \`~/.local/bin/apalache/bin/apalache-mc\`; the JSON-RPC
  explorer endpoint is \`/rpc\`.
- The ECMA checkout and the Haskell tree are consumed read-only; all
  writable scratch state lives under \`.golden-build/\` in this repo.

## Non-Lean client gates

- MirrorECMA runs its canonical-corpus Jest tests and full standalone smoke
  suite, including async, TLS, registry negatives, strict inbound framing, and
  D3 compiled model-interface verification and D4 dynamic descriptor/cache
  replay, including descriptor-read authorization negatives.
- MirrorCPP runs its complete CTest suite; `real_mirror_hourclock` replays the
  authoritative Counter model over stdio, TCP, and mTLS. Its D5 static
  model-interface leg checks strict negotiation codecs, the generated portable
  C++23 binding, exact registry selection, cleanup, stdio success, allowlisted
  mTLS success, and pre-construction digest/authorization failures.
- MirrorRust runs `cargo test` with the canonical corpus and real mirror
  enabled; its server-mode suite covers TCP, mTLS, registry pinning/failover,
  mismatch rejection, and asynchronous job semantics.

## decode_only.jsonl: JS-client wire shape

Captain ruling: the absent-vs-null optional-key semantics are pinned by
fixtures, not just by the Haskell-null shape. `tools/fixtures/GenDecodeOnly.hs`
(read-only Haskell oracle, same pinned packages as run.sh) decodes JS-shaped
client messages (optional keys omitted) and re-encodes them; the entries in
`test/fixtures/decode_only.jsonl` (lines 7-16) pin Lean's decode to the
Haskell `.:?` semantics + defaults. Note the encoder asymmetry this pinned:
`register_trace_gen_async` / `register_validate*` / `await_job` OMIT absent
optional keys, while `register` / `register_trace_gen` emit explicit nulls —
per-constructor parity with Protocol/Format/Json.hs.

## Bugs found by this matrix (fixed)

1. \`Ffi\`/\`Shell\`: TLS sequential-connection wedge (mTLS leg): after the
   first TLS session ended, the server never accepted another connection
   (the whole MirrorECMA mTLS matrix stalled on its second connection).
   Two causes, both fixed: (a) ABI mismatch — \`Ffi.tlsClose\` was declared
   \`BaseIO Unit\` while \`dsh_tls_close\` returns \`uint64_t\`, so the raw 0
   register was read as a boxed (null) result and the Lean task never
   resumed (now \`BaseIO UInt64\`); (b) \`SSL_shutdown\` blocked waiting for
   the peer's close_notify that \`SSL_read\` had already consumed —
   \`dsh_tls_close\` now flips the BIOs to non-blocking around the
   shutdown. Found ONLY by interop: \`transport_spec\` exercises one TLS
   connection per server instance. Gotcha for future shim edits: the
   executables do not relink when only the C shim changes — delete
   \`bin/mirror\` (and the \`.o\`) to force a relink.
2. \`Codec\`: optional fields rejected when the key is absent (JS clients omit
   optional fields; Haskell clients send explicit nulls). \`optFieldStr\`
   now implements full Haskell \`.:?\` semantics (absent or null -> none).
3. \`Shell\`: \`register_trace_gen\` ignored \`destPath\` (no copy/re-path) and
   read trace files after the session dir cleanup deleted them (ENOENT
   crash). \`Runner.syncOracles.generateTraceFiles\` now ports
   \`MkRunMirrorGenTraces\` faithfully.
4. \`Shell\`: the explorer dispatch passed \`exports\` and \`invariants\`
   swapped to the explorer oracles, so apalache was told about zero state
   invariants.
