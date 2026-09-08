# Mirrors — Architecture Details

> Explanatory types and judgments use the [shared semantic notation](https://github.com/NzSN/Mirrors/blob/main/Docs/semantic-notation.md).

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
tools/         test executables, interface compiler, fixtures, interop
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
`Shell.Mirror.parseItfTrace` parses ITF states into action / parameters / state
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
The state is phase-indexed, with 7 TLA+ phases and 2 async extensions.
Its successful-step judgment packages the next phase with the corresponding
session and ordered outputs:

```text
StepOutcome ≜ Sum[
  accepted:(∃p:Phase. Session(p) × Seq[MirrorMessage]),
  rejected:ProtocolError]

s : Session(p); input : ClientMessage ⊢ step ⇓ result : StepOutcome
idle; reportState ⊢ step ⇓ rejected(outOfOrder)
```

The second line abbreviates the result for any idle session and report
payload. No successful derivation accepts that pair; the input message itself
can still be represented and rejected. §6.3 encodes
`specs/MirrorProtocol.tla`'s mirror-side relation as `TlaStep` and proves:
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
The abstract resource carries a value, a label, a lifecycle state in
`{Live, Delivered, Released, ReleaseFailed}`, and `Owned` or `Borrowed`
provenance. Its pure use operation has a proof premise:

```text
Γ ⊢ r : Resource(α)    Γ ⊢ h : r.state = Live    Γ ⊢ f : α → β
──────────────────────────────────────────────────────────────
Γ ⊢ use(r, h, f) : β
```

This restates the dependent argument of `Core.Resource.use`. §6.5 proves
at-most-once cleanup for threaded operation sequences and the lexical bracket's
cleanup properties. Those pure token proofs do not supply a linear discipline
for copied host handles; the effectful owner must maintain actual liveness.
Native GC finalizers remain the FFI backstop described in §9.7.

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

### Core.ModelInterface and model-interface codecs

`Core/ModelInterface/` defines structural types, deterministic resolution,
canonical SHA-256 identity, trace preflight/coverage, and distribution policy.
`Codec.StrictJson`, `Codec.ModelInterfaceJson`, and
`Codec.ModelInterfaceDistributionJson` implement duplicate-aware bounded JSON
and the contract/lock/descriptor/negotiation envelopes. Their proofs and
fixtures cover the stated pure laws; they do not prove that arbitrary evidence
describes a TLA+ model or that an application adapter reports honest state.

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
- **Shell.ModelInterface** — filesystem/compiler operations, typed evidence
  loading, sync/async TypeScript and C++ emitters, runtime resolution,
  authorization, and bounded scoped caching. The CLI is
  `tools/ModelInterfaceGen.lean`; see the [compiler contract](model-interface-compiler-design.md).
- **Shell.Registry / Cli / Client** — Consul register/heartbeat/
  deregister/discover (fail-closed), full CLI surface
  (`--version`/`--serve`/`--server --tls`/`validate` incl. registry discovery +
  `--pin`), SIGINT/SIGTERM deregistration. `Shell.Version` supplies the declared
  product version; both server modes use the same connection-pool strategy.

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
- **Lake:** 12 test executables plus three generated-target freshness checks
  and exact Counter preflight coverage. The [documentation index](README.md)
  lists the executables and external-tier behavior from `lakefile.lean`.
- **Interop:** MirrorECMA, MirrorCPP, MirrorRust, and the Haskell reference
  client over their supported stdio/TCP/mTLS paths; see
  [the executable matrix](../tools/interop/INTEROP.md). Async replay and sandbox
  tests have additional companion gates, described in [client coverage](client-test-coverage.md).
- **Review:** `tls-ffi-review.md` (1 blocker, 3 majors, 8 minors — all
  fixed and re-reviewed PASS).

## 6. Documented divergences & open items

1. Mismatch tail: Haskell appends `all_steps_done`; Lean follows the
   TLA+ spec (`STEP_MISMATCH` only). *Spec-faithful.*
2. Wildcard scope stricter than `x509-validation` (fail-closed).
   *Accepted.*
3. Async job messages in synchronous stdio mode: `register_error` vs Haskell
   `protocol_error`. *Open harmonization candidate.* Server job controls do
   not require a new registration on the querying connection.
4. `--pin` is case-insensitive (Lean robustness improvement over Haskell).
   MirrorRust's base-wire leg is implemented and wired into the matrix; its
   generated model-interface target remains planned. See `cutover.md`.
