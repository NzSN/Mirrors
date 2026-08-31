# Mirrors — the Lean 4 port of ModelMirrors

This repository holds the Lean 4 port of the ModelMirrors mirror:
a formally verified pure core, total JSON codecs with byte-identical
wire compatibility, and a thin trusted effectful shell.
Design: `Docs/lean4-refactor-design.md`.

## Layout

- `Core/`   — verified pure core (no IO): Value, Trace, Diff, Protocol, Jobs, Resource
- `Codec/`  — total JSON codecs + round-trip proofs
- `Shell/`  — effectful shell (transports, apalache adapters, registry, session driver)
- `Ffi/`    — C shims (TLS, sockets, signals) — trusted TCB
- `Main.lean` — CLI (parity with the Haskell `app/Main.hs`)
- `test/`   — golden wire fixtures and differential tests vs Haskell

## Building

Requirements: [elan](https://github.com/leanprover/elan) (the Lean version
manager). The toolchain is pinned by `lean-toolchain`; the `batteries`
dependency is pinned by tag in `lakefile.lean`. First build fetches
`batteries` from GitHub automatically.

```bash
lake build     # builds Core, Codec, Shell, the mirror CLI and test exes
lake test      # fixtures + differential + stdio smoke + job parity + apalache CLI
```

The default mode of the built CLI is the stdio mirror session
(`.lake/build/bin/mirror`, parity with the Haskell binary's default
mode; `--serve`/`--server`/`validate` land in Phase 6).

Note: `lake build` needs network access on the first run to fetch the
pinned `batteries` rev. Keep `LC_ALL=C.UTF-8` when running the mirror
(apalache quirk, unchanged from the Haskell build).

## Status

FINAL STATE — all phases (0-6) complete. Cutover plan and Haskell
deprecation: `Docs/cutover.md`. Change log: `CHANGELOG.md`.
The full client interop matrix (stdio + TCP + mTLS, two real unmodified
clients, TLS + registry negatives) is green via `tools/interop/run.sh`
— see `tools/interop/INTEROP.md`. Known open item: the MirrorRust
interop leg was not run (no MirrorRust client available in this
environment); the Haskell `validate` client substitutes as the
second client, and the Rust leg remains open until a MirrorRust build is
run against this mirror over stdio/TCP/mTLS (`Docs/cutover.md`).

Server concurrency (t33): `--serve`/`--server` accept loops are
bounded worker pools on both platforms — never-completing dedicated
workers draining a connection queue, which also retired the Windows
sync-sequential fallback (`Docs/async-enablement-design.md` §6).
`--jobs N` sizes the pool and the process-shared async job store in
both server modes (default 4). Design + validation record:
`Docs/worker-pool-design.md`, `Docs/worker-pool-impl-status.md`.

Phases 0-4 done (fixtures, core, codecs, session machine + stdio
driver, and the async job store with Task workers). Phase 4 parity:
`tools/JobStoreSpec.lean` ports the Haskell `AsyncJobsSpec` fake-runner
workloads — validate/gen-traces round-trips, bound and capacity
rejections, unknown-id answers, cancellation, session close, await
timeouts, eviction — and both suites are green (Lean `jobstore_spec`,
Haskell `ModelMirrors-test -p AsyncJobs`). See the phase table in
`Docs/lean4-refactor-design.md` §8.

Phase 4 pieces: `Shell/Jobs/Store.lean` (Std.Mutex-protected store,
Std.Semaphore worker slots, dedicated Task per job, every phase change
through the pure `Core.Jobs.transition`), cooperative cancellation
(Lean tasks cannot be killed; bodies observe a `CancelToken` — the
Phase 5 apalache runner will terminate its child there),
`Shell/Mirror/Session.lean` `runAsync` (async session loop),
`Shell/Transport/Mock.lean` (test transport pair).

Phase 5 (CLI adapter): `Shell/Apalache/SpecSource.lean` (MODULE-header
parsing, inline-spec materialization into owned temp dirs, Borrowed
spec paths, per-session temp dirs), `Shell/Apalache/Cli.lean`
(apalache-mc spawn with `LC_ALL=C.UTF-8`, cwd pinned to the run dir so
`_apalache-out`/`tmp` never land in the mirror's cwd, exit-code tiers
255/other/0 = infra/invalid/valid, output-dir parsing, ITF trace file
discovery feeding the Core trace types, cancellable spawns wired to the
job CancelToken), `Shell/Apalache/Runner.lean` (job-store Runner + sync
Oracles glue). Regression suite: `tools/ApalacheCliSpec.lean` (unit:
header parsing/materialization/acquisition/args/output-dir; integration
vs real apalache 0.57 — runs when `APALACHE_MC` is set, else self-skips).

Phase 5 (explorer JSON-RPC): `Ffi/socket_shim.c` + `Ffi/Socket.lean`
(loopback TCP only: socket/connect/bind/listen/accept/send/recv with a
bounded receive timeout; decision: pure-Lean HTTP over this ~150-line
shim instead of libcurl FFI — no TLS/redirects/auth in the explorer's
surface), `Shell/Net/Http.lean` (HTTP/1.1 POST framing in Lean:
one-shot Connection-close mode and a buffered keep-alive mode with
Content-Length/chunked response parsing; the apalache server's Jetty +
async jsonrpc4s handlers sporadically answer 200 with an empty body
when every request arrives on a fresh close-mode socket, so the RPC
client pins one persistent connection per session like the Haskell
http-client manager), `Shell/Apalache/Explorer.lean` (JSON-RPC client,
apalache server lifecycle, explorer session/explore command
implementations), `Shell/Apalache/Runner.lean` (`runExplore` /
`runExploreSession` oracle flows). Regression suite:
`tools/ExplorerSpec.lean` (unit: HTTP spike vs a python loopback peer,
byte-identical transcript parity; integration vs real apalache 0.57 —
HourClock explorer session + explore flows; runs when `APALACHE_MC` is
set or apalache-mc is found at the conventional path, else self-skips).

Phase 6 (TCP + mTLS transports): `Shell/Transport/Tcp.lean`
(connectTcp/listenTcp/serveTcpOn over `Ffi/socket_shim.c`: one
session per connection, per-session line framing, peer drops logged
and survived, SO_REUSEADDR, ephemeral-port support) and
`Shell/Transport/Tls.lean` + `Ffi/tls_shim.c` (OpenSSL 3 FFI:
serveTlsOn/connectTlsPinned/certFingerprintSHA256/warnIfNearExpiry
parity with the Haskell TLS transport). The shim is deliberately
thin — connect/accept/read/write plus fingerprints and expiry
arithmetic — and the OpenSSL policy surface is explicit in it:
TLS 1.3 only, client certificates required
(SSL_VERIFY_PEER|SSL_VERIFY_FAIL_IF_NO_PEER_CERT), CA chain
validation, server certs must carry a SAN, private keys must be
0600, and clients pin the peer fingerprint. SSL_CTX/SSL objects are
Lean external objects freed by GC finalizers — the only finalizer
backstop in the codebase (§9.7). Regression suite:
`tools/TransportSpec.lean` (generates a throwaway PKI with the
openssl CLI at test time, runs TCP echo + drop-survival, mTLS echo
with fingerprint pinning, and negatives: wrong pin, untrusted
client cert, TLS 1.2-only peer, certificate-less client, no-SAN
server cert, group-readable key, near-expiry arithmetic; skips
itself when the openssl CLI is missing).

Phase 6 registry/signals/CLI (completing the transports phase):
`Ffi/socket_shim.c` grew t16 primitives — getaddrinfo IPv4 host
resolution (registry URLs are configurable addresses, not
loopback-only, matching the Haskell CLI), SIGINT/SIGTERM handlers
installed WITHOUT SA_RESTART plus a signal flag, a select-based
wait-readable so the accept loops poll instead of blocking (which
also keeps heartbeat tasks schedulable), and a POSIX exit shim.
`Shell/Net/Http.lean` generalizes to arbitrary hosts
(`requestTo`/`postTo`/`putTo` — Consul's agent API is PUT-based;
plain HTTP per design 9.2). `Shell/Registry.lean` ports
Protocol.Registry: registerService (30s TTL, failures → false),
heartbeat (10s loop as a task), best-effort deregister, and
discoverServices failing closed per entry. `Shell/Client.lean` ports
the client message exchange (`runClientValidate`).
`Shell/Cli.lean` + `Main.lean` complete the CLI surface:
`--serve <port> [--bind]`, `--server <port> --tls --cert --key --ca
[--registry] [--jobs] [--bind]` (register/heartbeat/deregister;
SIGTERM → deregister + exit 0 — verified against a mock Consul), and
`validate` with direct TCP/mTLS or registry discovery
(candidateFingerprint/--pin override, tryCandidates ordering).
Concurrent accept (one session per connection, each on its own task);
--jobs N sizes the process-shared async job store (live-job capacity
and concurrently running apalache bodies; default 4). Both server
modes run ASYNC sessions (t31): register_validate_async /
register_gen_traces_async fork dedicated job tasks over the ONE shared
store (job ids unique across connections), await_job / query_job /
cancel_job answer from it, and a connection ending cancels + evicts
exactly its own jobs (Haskell endSession semantics) — other
sessions' jobs are unaffected. The stdio default mode stays sync-only
(Haskell parity): async registers there answer register_error.
WINDOWS CAVEAT (t31 follow-up): async server sessions are Linux-only.
A Lean 4.33 Windows runtime bug makes any session task that touches
the shared job store segfault the process on quick session teardown
(reproducible on rapid connect/disconnect; 300-connection Linux
stress clean, all Linux gates green). Windows builds therefore serve
the t30 sync sequential sessions in both modes and the async_spec
gate self-skips there; see Docs/async-enablement-design.md §8.
Live-gated by tools/AsyncSpec.lean (APALACHE_MC): validate/trace-gen
round-trips over real TCP and mTLS connections, sync/async outcome
congruence, cancel, unknown-id, and multi-connection concurrency.

Phase 6 interop (client validation): `tools/interop/run.sh` runs the
full matrix — the unmodified MirrorECMA TypeScript smoke suite over
stdio, TCP (`--serve`), and mTLS (`--server --tls`, pinned
fingerprints) including its TLS negatives (wrong pin, wrong-CA/rogue
client, key mode) and registry discovery/failover/fail-closed
scenarios, plus the Haskell `validate` client over TCP and mTLS
(pinned fingerprint, wrong-pin and rogue-client negatives fail fast).
This leg surfaced and fixed a sequential-TLS-connection wedge invisible
to the unit suite (FFI ABI mismatch on tlsClose + a blocking SSL_shutdown);
details in `tools/interop/INTEROP.md`. Gate:
`tools/RegistrySpec.lean` (mock Consul via tools/mock_consul.py:
parser parity units, register/heartbeat/deregister recorded,
discovery fail-closed parsing, dead-registry [], and the SIGTERM
deregistration e2e with a throwaway PKI). t27 hardened --bind:
listenTcp resolves the bind address (IPv4 literals directly, names
via getaddrinfo — Haskell serveTcpOn parity with AI_PASSIVE) and
FAILS LOUDLY on unresolvable/unbindable values; the old silent
wildcard fallback (any --bind value other than the literal
"localhost" bound 0.0.0.0 — security-relevant for the unauthenticated
--serve mode) is gone. Bind regressions live in transport_spec
(loopback reachability + non-loopback block + bad-address startup
errors), and an unknown CLI mode now prints the full usage block
instead of an empty "usage: " line.

Re-running the stdio integration suite from this repo (needs the
Haskell ModelMirrors test binary and `apalache-mc` on PATH, plus the
spec files under `specs/` and `test/specs/`):

```bash
MODELMIRRORS_BIN=$PWD/.lake/build/bin/mirror MBT_TRANSPORTS=stdio \
  LC_ALL=C.UTF-8 <path-to>/ModelMirrors-test -p '/mbt over stdio/'
```