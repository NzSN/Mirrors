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
| `Codec.Json` | total wire codecs (39 ctors) | §6.6 round-trips, value + message level |
| `Codec.ExplorerRpc` | explorer JSON-RPC codec | per-method round-trips |
| `Codec.Bridge` | Core↔Codec tag mapping | 40 tag-fidelity theorems |
| `Codec.Consul` | Consul payload codec | round-trips, fail-closed decode |

Illegal protocol orderings are **unrepresentable** (phase-indexed
`Session p`), so whole classes of bugs are type errors, not test cases.

### 2. Trusted effect boundary (TCB) — `Shell/`, `Ffi/`

Thin, audited, explicitly *unproven*: transports (stdio/TCP/mTLS), the
session driver fold, async job store (`Task` workers), apalache CLI
runner + explorer HTTP/JSON-RPC client, Consul registry, CLI — plus two
C shims (OpenSSL TLS 1.3, sockets/signals). The TLS shim is the largest
TCB addition and passed an adversarial review (1 blocker + 3 majors
fixed; see `tls-ffi-review.md`).

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

## Test pyramid (9 lake gates)

fixtures_replay → diff_cross → stdio_smoke → jobstore_spec →
apalache_cli_spec → explorer_spec → transport_spec → registry_spec →
counter_spec (end-to-end MBT conformance vs real apalache). Plus the
interop matrix (MirrorECMA + Haskell client) and the TLS review.
