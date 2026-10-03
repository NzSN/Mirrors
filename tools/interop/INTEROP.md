# Client interop validation (Phase 6)

## Selected remote Windows profile

The qualification registry uses `python3 tools/interop/run-remote.py OUTPUT_ROOT`
for five-client verdict/pin checks and ECMA protocol checks (22 mTLS rows).
`OUTPUT_ROOT` must be new or an empty private directory. This profile uses the
deployed Windows service; the local-backend matrix described below is separate.

The registered `ECMA_REF` is built from Git objects into a new runtime root:

```sh
python3 tools/interop/prepare-ecma-runtime.py \
  --repo "$ECMA_REPO" --ref "$ECMA_REF" --node "$ECMA_NODE_BIN" \
  --node-modules "$ECMA_REPO/node_modules" \
  --out "$ECMA_RUNTIME_ROOT" --pin-out /tmp/ecma-runtime-pin.json
```

Use absolute paths and prepared TypeScript dependencies. The builder ignores
working-tree `dist`, compiles a clean source export, and packages `dist`,
`package.json`, and protocol fixtures. Compare the resulting pin with the
reviewed `ecma-runtime-pin.json` beside the runner; updating that checked-in pin
is a source change requiring a fresh qualification selection. The current pin
uses Node 24.15.0 and TypeScript 5.9.3. Runtime dependencies require an explicit
closure extension before the builder accepts them.

The runner verifies the complete runtime tree and Node executable before any
client executes, clears ambient Node options/module paths, and checks identities
again after the matrix. Both ECMA adapters import the admitted runtime. Its v2
receipt records the actual bindings; the E2 attachment plan retains that receipt
and the runtime pin as required diagnostic artifacts. Historical v1 receipts
remain historical evidence and do not establish this new runtime binding.

## Generated-client acceptance

The generated-language entry point is a separate profile and branches before
the legacy runner probes any local model checker:

```sh
bash tools/interop/run.sh --generated-clients \
  --out /tmp/generated-client-acceptance \
  --cpp-prefix "$MIRRORCPP_PREFIX" --node "$ECMA_NODE_BIN" \
  --context /private/generated-client-context.json \
  --observation /private/windows-deployment-observation.json \
  --allow-dirty-sdk
```

The private context supplies the normal CA/client credential paths and server
identity, plus `MIRRORS_REMOTE_DENIED_CLIENT_CERT` and
`MIRRORS_REMOTE_DENIED_CLIENT_KEY` for a valid same-CA leaf absent from the
server's interface allowlist. A TLS handshake failure cannot satisfy interface
authorization denial. `--allow-dirty-sdk` explicitly permits the Rust SDK's
tracked working-tree edits and binds their hashes; omit it for clean SDK builds.
Existing prepared native builds may be supplied with `--rust-build` and
`--lean-build`; each native runner verifies its admitted bytes.

This entry runs fresh shared type/value/equivalence/path and recording vectors
through synchronous/asynchronous TypeScript, C++, Rust and Lean generated code,
then runs four offline and five remote rows for each new Rust/Lean target.
Offline stdio covers exact `0,2,5` reports, wrong observations and failed
negotiation; plain TCP must deny interface authority before factory construction.
Local servers use a forbidden-model-checker sentinel. Live model generation uses
the observed Windows endpoint over pinned, allowlisted TLS 1.3 mTLS, including
wrong digest, nonallowlisted principal and wrong pin cases. Each compiled client
runs with source roots hidden. Exact known certificate-expiry warnings are
retained without admitting other stderr as success.

The aggregate receipt binds its shared-vector and transport receipts. It is
source/generated-client acceptance, not the registered 22-case M5 interop run,
the entire historical client matrix below, or an installed-distribution audit.
See [Lean target](../../Docs/model-interface-compiler/lean-target.md),
[Rust target](../../Docs/model-interface-compiler/rust-target.md), and
[shared corpus](../../test/fixtures/model-interface/language/README.md).

## Full local matrix

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
`.github/workflows/interop.yml`). It runs the MirrorECMA, MirrorCPP, MirrorLean, and
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
   In-limit trace-generation replies retain their inline bytes. The focused
   `tools/TraceGenerationTransportReproSpec.lean` and MirrorECMA
   `owned-registration-lifecycle.test.ts` suites separately pin the 65,535/
   65,536-byte delivery boundary, durable stdio path-only fallback, bounded
   remote/ephemeral failures, idempotent async terminal projection, and
   pre-spawn registration rejection. MirrorECMA's env-gated
   `trace-generation-transport.integration.test.ts` additionally drives a
   generic oversized ITF result through the real stdio, TCP, and mTLS server
   paths and verifies post-error server reuse.
3. Typechecks and runs MirrorECMA's standalone D3+D4 model-interface Counter
   slice. It checks the generated lock/source bytes, exact digest negotiation,
   fail-closed ordering, dynamic `resolved -> not_modified` cache reuse,
   source-free local handlers, wrong-observer `step_mismatch`, allowlisted mTLS
   verification and descriptor read, descriptor-read denial, and no-allowlist
   denial.
4. Compiles MirrorECMA's generated Counter tutorial and standalone acceptance
   harness once into `.golden-build/ecma-generated-counter`. The harness runs
   the same emitted executable as the tutorial's package commands, with the
   client root as its working directory. It compares the tutorial model with
   `specs/Counter.tla`, runs compiler `check` and required-action preflight, and
   proves that stale generated output is detected without repair in a temporary
   fixture copy. Supplied-trace replay must cover Initialize and Tick with
   `APALACHE_MC` set to a nonexistent path; the faulty implementation must exit
   1 with the actual `tick`/`count` state mismatch. Missing tools or arbitrary
   failures do not satisfy that negative case. An executable `APALACHE_MC`
   enables the additional `--live` case, which must generate fresh traces and
   cover both actions through the same adapter. The full matrix requires live
   Apalache up front and always enables this tier; the focused client command
   below makes it optional.
5. Generates a fresh Counter suite bundle in a temporary directory, transforms
   its two TypeScript modules using the pinned Node runtime, and executes the
   native bridge vectors plus invalid-input/observation/return and poisoning
   checks. This execution gate installs no packages and requires no MirrorECMA
   module at runtime. Installed consumer gates separately typecheck the public
   compiler/runtime contract. Run it alone with
   `python3 tools/check-suite-runtime.py` after building `model_interface_gen`.
6. Starts \`mirror --serve\` and runs the Haskell ModelMirrors \`validate\`
   client against it over TCP.

The mTLS legs run the same unmodified clients with pinned leaf
fingerprints (SHA-256 hex of the DER) and negative cases.

## Reproducible CI and local setup

MirrorECMA now has its own focused push/PR workflow. It installs the checked
`pnpm-lock.yaml` with `pnpm install --frozen-lockfile`, runs all three typechecks
and Jest, and checks compiler freshness and the passing/faulty generated Counter
executables. It needs only Mirrors, Lean, Node/pnpm, and native build headers.
Java, Apalache, Haskell, Rust and C++ clients are unnecessary for that offline
client gate. From MirrorECMA:

```bash
pnpm install --frozen-lockfile
MIRRORS_ROOT=../Mirrors bash scripts/ci/check.sh
```

The client gate checks the published compiler revision recorded in
`MirrorECMA/scripts/ci/versions.env`. To test a coordinated newer server commit,
set `MIRRORS_REF` to its full 40-character SHA. Its manual workflow offers the
same `mirrors_ref` input and a `live` checkbox. Publish and verify a matching
server commit before updating the checked baseline; never pin an unpublished
future change. Current synchronous generated artifacts remain compatible with
the baseline even when separate asynchronous targets evolve.

The broader Mirrors workflow keeps the full matrix. `tools/ci/versions.env`
records exact tool versions and explicit published client commit baselines;
`workflow_dispatch.ecma_ref` accepts a full matching MirrorECMA SHA. All checkout
revisions, dirty files, and tool versions are printed. Hosted runs enforce the
client pins with `INTEROP_VERIFY_PINS=1`. The runner is `ubuntu-24.04`; OS package
patch levels and existing C++ FetchContent policy remain outside the exact pins.
Haskell resolution uses a fixed index-state and Rust uses its checked lockfile.
GitHub action implementations are pinned by commit SHA.

Full local interop consumes sibling `MirrorECMA`, `MirrorCPP`, `MirrorRust`, and
`ModelMirrors` checkouts by default. Override their paths using `ECMA_REPO`,
`CPP_REPO`, `LEAN_CLIENT_REPO`, `RUST_REPO`, and `HS_REPO`. First build the Haskell reference with
`cabal build ModelMirrors:exe:ModelMirrors` in its checkout, then supply the
absolute path returned by `cabal list-bin ModelMirrors:exe:ModelMirrors` as
`HS_BIN`. The matrix requires that already built executable and a live
`APALACHE_MC`; missing prerequisites fail before the Lean build. For example:

```bash
HS_BIN=/absolute/path/to/ModelMirrors \
APALACHE_MC=/absolute/path/to/apalache/bin/apalache-mc \
  bash tools/interop/run.sh
```

Both workflows install the exact Apalache 0.61.0 versioned archive through a
SHA-256-checking helper. The full matrix always requires live generation; the
focused client workflow installs Java and Apalache only when live coverage was
explicitly requested. A failed live prerequisite is a failure, not a skipped
test. The separate native CI job runs `bash tools/check-native-rebuild.sh`.

The [design](../../../MirrorECMA/docs/superpowers/specs/2026-09-06-reproducible-ci-design.md)
and [task plan](../../../MirrorECMA/docs/superpowers/plans/2026-09-06-reproducible-ci.md)
record version provenance, acceptance evidence, and hosted/full-matrix limits.

## Environment notes

- The checked release is apalache-mc 0.61.0; set `APALACHE_MC` explicitly or
  put `apalache-mc` on PATH. The JSON-RPC explorer endpoint is `/rpc`.
- The ECMA checkout and the Haskell tree are consumed read-only; all
  compiled interop output lives under \`.golden-build/\` in this repo. The
  generated Counter harness creates and removes its stale-output fixture in
  the system temporary directory; Mirrors isolates live Apalache work in
  session temporary directories.
- The generated Counter gate receives `MIRRORECMA_ROOT`, `MIRRORS_ROOT`, and
  `MIRROR_BIN` from the matrix's existing root and binary settings. Override
  `MODEL_INTERFACE_GEN` for a compiler outside
  `$MIRRORS_ROOT/.lake/build/bin/model_interface_gen`. To run this gate alone
  from the MirrorECMA root:

  ```bash
  MIRRORS_ROOT=../Mirrors pnpm run smoke:generated-counter
  MIRRORS_ROOT=../Mirrors APALACHE_MC=/path/to/apalache-mc \
    pnpm run smoke:generated-counter --live
  ```

## Non-Lean client gates

- MirrorECMA runs its canonical-corpus Jest tests and full standalone smoke
  suite, including async, TLS, registry negatives, strict inbound framing, and
  D3 compiled model-interface verification and D4 dynamic descriptor/cache
  replay, including descriptor-read authorization negatives. The generated
  Counter tutorial adds artifact provenance, offline passing/faulty executable
  acceptance, and explicitly enabled live-generation coverage; see the
  [client tutorial](../../../MirrorECMA/examples/generated-counter/README.md).
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
   connection per server instance. The historical workaround required a manual
   relink. The current [native build graph](../../Docs/native-build-design.md)
   tracks shim sources, included headers, compiler identity and OpenSSL settings;
   rebuild normally and use `bash tools/check-native-rebuild.sh` after dependency
   graph changes.
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

## Reviewed projected-corpus integration

```bash
python3 tools/model-interface-projected-corpus/check.py \
  --out /tmp/m6-public-corpus-new
```

The output directory must not exist. This explicit cross-repository gate needs
the MirrorECMA and MirrorGate checkouts, their installed TypeScript dependencies,
Node 24, npm, Python, tar, Bubblewrap permissions and prepared Gate prerequisites.
`--compiler`, `--mirror`, `--ecma-repo` and `--gate-repo` select explicit paths.
It remains separate from generic `lake test`, which does not require those
external checkouts.

The [public projected-cells fixture](../../test/fixtures/model-interface/projected-cells/)
uses a fixed synthetic review record. The gate regenerates its proposal, seal,
corpus, workflow lock and async bundle through the CLI, performs read-only checks
and trace-member preflight, and type-checks the generated consumer against the
packed SDK. It then relocates the installation and runs with the three source
checkouts hidden and networking isolated.

The same suite exercises local replay and Gate's actual worker collection bridge:
complete action/pair coverage, a deliberate typed observation mismatch, deferred
acquisition and confirmed cleanup. Disposer failures must prevent a passing
outcome. Gate's persisted cleanup receipts are checked independently. Artifact
loader rejection happens before any Gate preparation; later replay preflight
can follow control-session preparation and must leave implementation binding
unstarted while confirming control cleanup.

All replay uses supplied traces. A forbidden model-check sentinel must remain
untouched. `receipt.json` retains input, package, executable and artifact hashes
plus runtime results and log identities. This is bounded source and relocated
package integration evidence; it does not establish fresh M5 release
qualification. The [M6 execution record](../../Plans/m6-reviewed-scaffolds-and-corpora.md)
records the accepted run and limits.

## Focused C++ / Lean / Rust conformance

`APALACHE_MC=/path/to/apalache-mc bash tools/interop/clients.sh` runs the three
native client gates against the current built Mirrors executable without
requiring Node or the Haskell reference client. `MIRROR_BIN` can select another
explicit server binary. All server/Apalache prerequisites are mandatory; missing
inputs fail before a live suite can report a skip. Optional registry-daemon
checks remain separate from the stub-registry coverage.

The full runner now includes MirrorLean's root tests and its separate native
server-mode package. `LEAN_CLIENT_REPO` selects its checkout, while `LEAN_BIN`
continues to name the Mirrors server executable. Workflow dispatch accepts full
`cpp_ref`, `rust_ref`, and `lean_client_ref` SHAs alongside `ecma_ref`; local
pin verification uses `CPP_REF`, `RUST_REF`, `LEAN_CLIENT_REF`, and `HS_REF`.
Each override is an explicit full 40-character SHA; omitting `HS_REF` preserves
the published `HS_BASELINE`. The C++/Lean/Rust
baselines pin the coordinated conformance commits published on 2026-09-18.
The additive [async reply vectors](../../test/client-conformance/README.md) do
not modify the frozen Haskell golden corpus.
