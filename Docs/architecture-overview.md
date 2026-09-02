# Mirrors — Architecture Overview

> Companion to the interactive diagram `architecture-overview.html`
> (open it in a browser; source spec: `architecture-overview.json`).
> Audience: anyone who needs the system's shape in five minutes.
> Deep-dive: `architecture-details.md`. Design rationale:
> `lean4-refactor-design.md`. Acceptance audit: `final-review.md`.

Mirrors is the Lean 4 port of the ModelMirrors mirror: a conformance
checker that sits between a client state machine and the apalache model
checker, speaking a frozen JSON-lines wire protocol. The port's premise
is that **the shipping binary is also the verified artifact** — the
proved functions are the executed functions, with no extraction gap.

## The one-sentence architecture

A **thin, trusted effectful shell** drives a **pure, machine-checked
core**: every line from a client flows
`transport → decode → Core.step → encode → transport`, and everything
behind `Core.step` is theorem-covered.

## Component map

```
  +---------------------- verified pure core (no IO) ----------------------+
  |                                                                      |
  clients --JSONL--> transports --lines--> session --Core.step--> Core.*   |
  (MirrorECMA,      (stdio/Tcp/Tls)      (thin fold)            Protocol,  |
   Haskell, Rust)        |                   |                  Jobs,Trace,|
                         |extern             |                  Diff,Value,|
                         v                   |                  Resource   |
                    Ffi shims (C)            |                     ^       |
              TLS 1.3, sockets,              |           tag bridge (proof)|
              signals, timeouts              |                     |       |
                                  Shell.Apalache --spawn--> apalache-mc    |
                                  Shell.Jobs -----per-job--> apalache-mc   |
  |                                 (validate, trace-gen, explore)         |
  +----------------------------------------------------------------------+

   CLI modes: stdio | --serve (TCP) | --server --tls (mTLS) | validate
   --registry --> Shell.Registry --HTTP--> Consul (discovery)

   Core.Protocol --refines (6.3 theorem)--> MirrorProtocol.tla
```

## Components

| # | Component | Where | Zone | Role |
| - | --------- | ----- | ---- | ---- |
| 1 | Clients | external | oracle | MirrorECMA, Haskell reference client, others on the frozen JSONL wire |
| 2 | Transports | `Shell.Transport.{Stdio,Tcp,Tls}` | trusted | line framing over stdio / plain TCP / mTLS (TLS 1.3, mutual auth, fingerprint pinning) |
| 3 | Ffi shims | `Ffi/` (`tls_shim.c`, `socket_shim.c`) | trusted, reviewed | OpenSSL TLS, sockets, signals, process exit, recv timeouts; unproven TCB, adversarially reviewed (`tls-ffi-review.md`) |
| 4 | Session driver | `Shell.Mirror` | trusted | the thin fold: recv → decode → `Core.step` → encode → send; sync and async (`runAsync`) variants |
| 5 | Pure core | `Core.{Value,Trace,Diff,Protocol,Jobs,Resource,ModelInterface}` | **verified** | phase-indexed session machine, model-interface resolver/preflight/negotiation, async jobs, and ITF value/trace/diff domain |
| 6 | Codecs | `Codec.{Json,ExplorerRpc,Bridge,Consul,StrictJson,ModelInterfaceJson,ModelInterfaceDistributionJson}` | **verified** | total wire/compiler codecs, duplicate-aware JSON preflight, and the proven Core↔wire tag mapping |
| 7 | Job store | `Shell.Jobs.Store` | trusted | process-shared async jobs: Mutex-protected table, semaphore-bounded `Task` workers, capacity = `--jobs` |
| 8 | apalache adapter | `Shell.Apalache` | trusted | spawns `apalache-mc` (validate/trace-gen), explorer HTTP/JSON-RPC client, per-session run dirs |
| 9 | apalache-mc | external (JVM) | oracle | the actual model checker |
| 10 | Server accept paths | `Shell.Transport.Tcp/Tls` + `Shell.Cli` | trusted | **t33 worker pool** (below) |
| 11 | Registry client | `Shell.Registry` | trusted | register/heartbeat/deregister/discover + fingerprint pin lookup |
| 12 | Consul | external | oracle | service discovery over plain HTTP |
| 13 | CLI | `Main.lean`, `Shell.Cli` | trusted | modes: stdio (default), `--serve`, `--server --tls`, `validate` |
| 14 | TLA+ reference | `specs/MirrorProtocol.tla` | spec | the model-level contract the session machine refines by proof |

## Relations

| From → To | What flows | Kind |
| --------- | ---------- | ---- |
| clients → transports | JSON-lines wire (frozen, byte-compatible with Haskell) | external |
| transports → session driver | framed lines (`recv`/`send`) | in-process |
| transports → Ffi shims | fd/TLS extern calls (accept, recv, handshake, close, timeouts) | FFI |
| session driver → `Codec.Json` | decode client messages / encode replies | pure, proven round-trips |
| session driver → `Core.Protocol.step` | one pure session transition per message | pure, §6.3 refinement |
| `Codec.Bridge` → `Core` | tag mapping core constructors ↔ wire tags | pure, 40 tag theorems |
| session driver → `Shell.Apalache` | sync validate / trace-gen / explore | trusted → oracle |
| session driver → `Shell.Jobs` | async submit / await / cancel (t31) | trusted |
| `Shell.Jobs` → apalache-mc | one `Task` worker per job, spawn/kill via `CancelToken` | trusted → oracle |
| accept loop → pool workers | accepted fds via bounded `ConnQueue` (t33, below) | trusted |
| pool workers → session driver | one async session per connection, over ONE shared job store | trusted |
| CLI → `Shell.Registry` | `--registry` register/heartbeat/deregister | trusted |
| `Shell.Registry` → Consul | plain HTTP register/discover | external |
| `Core.Protocol` → `MirrorProtocol.tla` | refinement theorem (proof, not test) | proof |
| everything → Haskell mirror | parity oracle: 70 golden fixtures, 500/500 diff cases, MirrorECMA interop | differential test |

Illegal protocol orderings are **unrepresentable** (phase-indexed
`Session p`), so whole classes of bugs are type errors, not test cases.

## Server concurrency (t33 worker pool)

Both server modes use one model on both platforms
(`Docs/worker-pool-design.md`):

```
main thread                     N long-lived workers (spawned once,
  signal flag check              dedicated Tasks that NEVER return —
  park in select(200ms)          the Lean 4.33 Windows task-teardown
  acceptFd ──▶ ConnQueue ──▶     race fires on task completion, so the
  (Mutex+2 sems, capacity 128;   pool removes completion structurally)
  push blocks when full; the     worker: pop → run session → closeFd
  kernel backlog holds clients)  → loop
```

- One `runAsync` session per connection over **one process-shared job
  store** (job ids unique across connections; a connection's end
  cancels and evicts exactly its own jobs).
- Pool size = `--jobs N` (default 4) on `--server`; `--serve` uses the
  default of 4 (the flag is not parsed there — known deviation).
- Shutdown: signal flag → accept loop returns → direct `dsh_exit` with
  workers parked — no exit-time teardown either.
- Parking caveat: the queue's semaphore wait must use `IO.wait`,
  never `Task.get`, on the Lean promise machinery (`Task.get` on an
  unresolved semaphore promise returns immediately — the phantom-pop
  storm) — see `Docs/worker-pool-impl-status.md` for the investigation
  and the Windows validation state.

## The three zones

### 1. Verified pure core (no IO) — `Core/`, `Codec/`

| Module | Contents | Theorems |
| ------ | -------- | -------- |
| `Core.Value` | ITF values, assoc-list `ValueMap`, `setEq` | set-extensionality law, `valEq` refl/symm/trans |
| `Core.Trace` | ITF traces, `applyParamVars`, `traceSteps` | §6.2 lossless repartition, length/order |
| `Core.Diff` | `diffState`, hints, 50-hint cap | §6.1 soundness, completeness, cap + path validity |
| `Core.Protocol` | phase-indexed session machine | §6.3 refinement vs `MirrorProtocol.tla`, no unsolicited output |
| `Core.Jobs` | async job machine | §6.4 terminal-once, outcome congruence, bounds |
| `Core.Resource` | lifecycle model | §6.5 cleanup-at-most-once; dead finalizer |
| `Core.ModelInterface` | compiler IR, deterministic resolution, trace preflight, negotiation, SHA-256 | resolver/policy/protocol-gating laws plus executable canonical vectors |
| `Codec.Json` | total wire codecs (39 ctors) | §6.6 round-trips, value + message level |
| `Codec.StrictJson` + model-interface codecs | duplicate-aware bounded JSON and strict contract/descriptor negotiation envelopes | canonical round trips, digest correspondence, absent-field compatibility |
| `Codec.ExplorerRpc` | explorer JSON-RPC codec | per-method round-trips |
| `Codec.Bridge` | Core↔Codec tag mapping | 40 tag-fidelity theorems |
| `Codec.Consul` | Consul payload codec | round-trips, fail-closed decode |

### 2. Trusted effect boundary (TCB) — `Shell/`, `Ffi/`

Thin, audited, explicitly *unproven*: transports (stdio/TCP/mTLS), the
session driver fold, the t33 worker pool, async job store (`Task`
workers), apalache CLI runner + explorer HTTP/JSON-RPC client, Consul
registry, CLI — plus two C shims (OpenSSL TLS 1.3, sockets/signals/
timeouts). The TLS shim is the largest TCB addition and passed an
adversarial review (1 blocker + 3 majors fixed; see `tls-ffi-review.md`).

### 3. External oracles — apalache, Consul, TLA+ spec, Haskell reference

apalache-mc (JVM) does the actual model checking behind
validate/trace-gen/explore; the mirror isolates its filesystem litter in
per-session run dirs. Consul handles discovery over plain HTTP. The
TLA+ spec is the model-level contract the core *refines by proof*. The
pinned Haskell implementation (`ModelMirros@3496251`) is the parity
oracle for fixtures and differential tests.

## The wire contract

Byte-for-byte compatible with the Haskell mirror: 70 golden fixtures
byte-identical, diff engine 500/500 *ordered* parity (+5000-case
sweeps), unmodified MirrorECMA green over stdio/TCP/mTLS, and the
Haskell validate client green. Two documented divergences where Lean
follows the TLA+ spec rather than Haskell's quirks (mismatch tail;
wildcard scope), plus open items tracked in `cutover.md`.

## Test pyramid (12 lake gates)

fixtures_replay → diff_cross → model_interface_spec →
model_interface_distribution_spec → stdio_smoke → jobstore_spec →
apalache_cli_spec → explorer_spec → transport_spec → registry_spec →
counter_spec (end-to-end MBT conformance vs real apalache) → async_spec
(live async flows over real server children, `APALACHE_MC`-gated). Plus
the interop matrix (MirrorECMA + Haskell client) and the TLS review.
