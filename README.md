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

Re-running the stdio integration suite from this repo (needs the
Haskell ModelMirrors test binary and `apalache-mc` on PATH, plus the
spec files under `specs/` and `test/specs/`):

```bash
MODELMIRRORS_BIN=$PWD/.lake/build/bin/mirror MBT_TRANSPORTS=stdio \
  LC_ALL=C.UTF-8 <path-to>/ModelMirrors-test -p '/mbt over stdio/'
```