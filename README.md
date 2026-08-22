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

Re-running the stdio integration suite from this repo (needs the
Haskell ModelMirrors test binary and `apalache-mc` on PATH, plus the
spec files under `specs/` and `test/specs/`):

```bash
MODELMIRRORS_BIN=$PWD/.lake/build/bin/mirror MBT_TRANSPORTS=stdio \
  LC_ALL=C.UTF-8 <path-to>/ModelMirrors-test -p '/mbt over stdio/'
```