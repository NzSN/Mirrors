# Mirrors — Architecture Details

> Module-by-module companion to `architecture-overview.md`.
> Read that first; this is the reference.

## 1. Repository layout

```
Core/          pure, proof-carrying core (no IO)        [verified]
Codec/         total JSON/RPC codecs + bridge            [verified]
Shell/         effectful drivers, oracles, CLI           [trusted]
Ffi/           C shims: tls_shim.c, socket_shim.c        [trusted, reviewed]
Main.lean      CLI entry (default stdio mirror)
test/          golden fixtures, specs, README
tools/         9 lake test gates + fixture generators + interop
specs/         TLA+ reference copies for the test suite
Docs/          design, reviews, cutover, this file
```

Lake `lean_lib` roots are `Core`, `Codec`, `Shell`, `Ffi`;
toolchain pinned at `leanprover/lean4:v4.33.0`, batteries at `v4.33.0`.

## 2. The pure core, module by module

### Core.Value — the value domain
ITF `Value` (11 constructors: ints as arbitrary-precision `Int`,
sets as element *lists*, records/maps as assoc-list `ValueMap`).
Two deliberate choices drive everything downstream:
- **No `BEq` instance.** `valEq` is a *proved* decision procedure
  (with `valEq_refl/symm/trans`); set extensionality (`{1,1}={1}`)
  would break `LawfulBEq`. Callers use `valEq a b = true`.
- **Assoc-list maps, not HashMap** (doc §9.3): extensional equality is
  what makes diff soundness statable. `mapCont_iff` gives the
  extensionality lemma; real state maps are small, so the simple
  structure suffices.
`filterMeta`/`isMetaKey` drops `#*`, `action_taken`,
`parameters` — the conformance comparison's meta-key rule.

### Core.Trace — the trace pipeline
`parseItfTrace` splits ITF states into action / parameters / state
vars; `applyParamVars` repartitions by the config's `paramVars`
(e.g. Counter's `"parameters"` record moves to the params side so the
client's report isn't diffed against it); `traceSteps` injects
`action_taken`. §6.2 proves the repartition **lossless under the
parse-time key invariant** (`ResplitKeyInv`) — faithfully matching the
Haskell behavior of dropping keys in neither `pvs` nor `vars`.

### Core.Diff — the conformance judge
`diffState` with fuel-budgeted mutual recursion, 7 hint constructors,
`capHints` at 50 + one `HTruncated`. §6.1 proves soundness,
completeness (uncapped core), cap correctness, and **path validity**
(every hint path navigates to a real subterm). Hint *order* is
byte-parity with Haskell (`Data.Map` sorted-key interleave via
`sortHintsByKey` + permutation bridges) — capped diffs select the same
surviving hints on both implementations. Differentially tested:
500/500 ordered, 5000-case sweeps, zero divergence.

### Core.Protocol — the session machine (the centerpiece)
Phase-indexed: `Session p` with `p : Phase` (7 TLA+ phases + 2 async
extensions). `step` takes a message and returns
`Except ProtocolError (Σ p', Session p' × List MirrorMessage)` —
illegal orderings are unrepresentable (no `report_state` case in
`idle`). §6.3 encodes `specs/MirrorProtocol.tla`'s mirror-side
relation as `TlaStep` and proves:
- `step_refines_tla`: every machine step decomposes into 1–3 spec
  actions (queue semantics absorbed);
- `no_unsolicited_output` + `allowed_outputs_attainable`: per-phase
  emittable sets are *exactly* the spec'd sets;
- `PhaseOk` and the mirror obligations of `ClientNeverStuck`.
Fidelity details honored: `mirror_flow` as state, the
`RegisterTraces` fast path (idle→ready, no validating), the
`SpecValidatedValid` flow branch, `STEP_OK` queued with `NEXT_STEP`
as a separate send. Async-job steps are explicit, marked *extensions*.

### Core.Jobs — async work
Job vocabulary + state machine; `StoredPhase` (JobPhase minus
`jobUnknown`) makes "JobUnknown exactly for never-submitted/evicted"
hold **by construction**. §6.4: terminal phases absorbing, outcome
congruence with the sync `RegisterValidate` flow, bound enforcement
[1,100] on both paths.

### Core.Resource — lifecycle model
Abstract token in `{Live,Delivered,Released,ReleaseFailed} ×
{Owned,Borrowed}`. §6.5: cleanup at most once over arbitrary op
sequences; `use` requires a proof the handle is `Live` — so the
GC-finalizer backstop is *provably dead code* in-language and exists
only at the FFI boundary (doc §9.7).

### Codec.* — the wire layer
Total `encode`/`decode` per message family with §6.6 round-trips at
value *and* message level (fuel-bounded, `defaultFuel = 2^32`, a
documented deviation for opaque `Json.sizeOf`). Frozen aeson quirks:
sum encoding, per-constructor omit-vs-null asymmetry, Haskell defaults,
bare integral numbers → `VInt` (general divisible-mantissa rule with
`decValueF_num_integral`). `Codec.Bridge` connects the tag-abstract
Core messages to the payload-concrete Codec messages with 40
tag-fidelity theorems — the seam can't drift. Explorer JSON-RPC and
Consul codecs mirror the pinned Haskell field behavior (fail-closed
decode, empty-address drops).

## 3. The trusted shell

- **Shell.Mirror.Session** — the §5.3 thin fold; all oracle calls
  injected (`Oracles` record) so the refinement proof never mentions
  IO. Replay: `replayOne`/`replayAll` drive
  `initial_state/next_step` and render `step_ok/step_mismatch/
  all_steps_done` via the proven machine's transitions.
- **Shell.Transport** — line-framed stdio; TCP (one session per
  connection, drops survived, general `--bind` with loud failure);
  mTLS via the shim (`serveTlsOn`/`connectTlsPinned`, case-insensitive
  pins).
- **Shell.Apalache** — CLI runner (`LC_ALL=C.UTF-8`, exit tiers
  255/12,120/0, cancellable spawns on the job `CancelToken`, cwd =
  per-session run dir — *no `_apalache-out` litter*, regression-tested);
  SpecSource (inline spec materialization, Owned/Borrowed); Explorer
  (pure-Lean HTTP/1.1 with keep-alive over the socket shim — works
  around apalache/Jetty's empty-200-on-fresh-connection quirk).
- **Shell.Jobs** — Mutex+Semaphore store, dedicated `Task` per job,
  parity suite ports all 10 Haskell `AsyncJobsSpec` scenarios.
- **Shell.Registry / Cli / Client** — Consul register/heartbeat/
  deregister/discover (fail-closed), full CLI surface
  (`--serve`/`--server --tls`/`validate` incl. registry discovery +
  `--pin`), SIGINT/SIGTERM deregistration.

## 4. The C shims (TCB core)

| Shim | Surface | Policy |
| ---- | ------- | ------ |
| `tls_shim.c` | connect/accept/read/write + fingerprints/expiry only | TLS 1.3-only, client certs mandatory, CA chain + SAN (`NEVER_CHECK_SUBJECT`, `set1_ip_asc` for IP literals), key perms 0600, startup time-check off (warn-only), handshake strict |
| `socket_shim.c` | resolve/bind/connect/accept/read/write, signals, select-poll | general IPv4 + getaddrinfo; SIGINT/SIGTERM flags checked every 200 ms |

`SSL_CTX`/`SSL` are Lean external objects freed by GC finalizers —
the single permitted §9.7 backstop (NULL-guarded post-review).
ABI lessons pinned in code: no C-built `Option` ctors (NULL-payload
sentinels + `is_null`), `ByteArray` out-params as `lean_object*`
+ `lean_sarray_cptr`, non-blocking `SSL_shutdown`.

## 5. Verification & test inventory

- **Proofs:** §6.1–§6.6 all machine-checked; `#print axioms` audit:
  nothing beyond `propext`/`Classical.choice`/`Quot.sound`.
- **Gates (lake test, 9):** fixtures_replay (70 byte-identical),
  diff_cross (ordered parity), stdio_smoke, jobstore_spec,
  apalache_cli_spec, explorer_spec, transport_spec (throwaway PKI, 16
  negative cases), registry_spec (mock Consul, SIGTERM e2e),
  counter_spec (Counter + DeterministicCounter MBT e2e).
- **Interop:** MirrorECMA unmodified (jest 120/120 + tsx smoke) and
  Haskell validate client, over stdio/TCP/mTLS.
- **Review:** `tls-ffi-review.md` (1 blocker, 3 majors, 8 minors — all
  fixed and re-reviewed PASS).

## 6. Documented divergences & open items

1. Mismatch tail: Haskell appends `all_steps_done`; Lean follows the
   TLA+ spec (`STEP_MISMATCH` only). *Spec-faithful.*
2. Wildcard scope stricter than `x509-validation` (fail-closed).
   *Accepted.*
3. Pre-register job message: `register_error` vs Haskell
   `protocol_error`. *Open harmonization candidate.*
4. MirrorRust leg unrun (client unavailable); `--pin` case-insensitive
   (Lean robustness improvement over Haskell). See `cutover.md`.
