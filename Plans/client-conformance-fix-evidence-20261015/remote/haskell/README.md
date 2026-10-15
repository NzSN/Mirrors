# Haskell remote acceptance — 2026-10-15

Accepted scoped H1/K1 and Haskell reply/TLS observations against base
`5ee414ee16b8aba50ceb480ac8013a56165272bb`. All 120 candidate source files
were hash-verified before compilation and again after the gate. No production
source changes were made by this remote validation task.

## Results

- GHC **9.14.1**, Cabal **3.16.1.0**, Hackage index-state
  **2026-09-01T00:00:00Z**; signed Hackage root/timestamp/snapshot/index
  verification enabled before dependency resolution/build. Compiler and Cabal
  archives passed their official SHA256 manifests before execution.
- Full library (32 modules) and test suite (26 modules) compiled. Native build
  concurrency was bounded to two. The complete source compile is retained in
  `diagnostics/retry.log`; the final `build` receipt is a successful no-change
  build reusing those artifacts.
- Exactly **16 NonModel tests passed in 2.26 seconds**. The retained selected
  list and runtime log cover actual TCP, stdio child, mTLS records, server-owned
  session cleanup with another live fake job preserved, reply kinds/job IDs,
  cancellation response alternatives, byte limits and POSIX key modes.
- The actual old `Protocol.Transport.Core.sendMsg` from the Git baseline wrote
  a **65,536-byte** final encoded JSON value. The fixed implementation refused
  it with **zero writes**; both preserved the ordinary **8-byte** encoded value.
  See `logs/probe-compile-baseline.log` for the baseline source path and
  `logs/probe-run-{baseline,fixed}.log` for executed results. The repeated fixed
  probe output was byte-identical.
- A no-change build preserved the test binary SHA256
  `3381ce1468ad503135ef3fdd412dfecd162cd0c22d4a4c213c1cc29d6c249031`.
- TLS **2.4.3** accepted the CA-valid CN-only observation. DNS SAN precedence,
  wildcard depth, IP match/mismatch, existing no-SAN server startup refusal,
  lowercase pin success and uppercase/wrong pin refusal all passed. This records
  dependency behavior; it introduces no new CN-only policy. The documented
  Haskell case-sensitive fingerprint exception remains.
- Both TLS constructors accepted only exact POSIX **0600** across the tested
  `0000,0400,0600,0640,0644,0700,1600,2600,4600` matrix without changing modes
  or key bytes.
- `cleanup.json` records no active owned Haskell compiler/test processes and no
  remaining `modelmirrors-*` temporary directories.

## Workflow and retained evidence

Private source/toolchain reside under the new owned ext4 image at
`/home/jlc/Tools/mirrors-client-fixes-20261015`; large build output and evidence
reside under `D:/Desktop/Workspaces/Mirrors-client-fixes-20261015/haskell`.
`workflow/run-phases.py` retains exact commands and `phases.json` their exits.
`dependency-plan.json`, `dependency-archives.json`, `tool-downloads.json`,
`toolchain.json`, `artifacts.json` and the source manifests bind the accepted
inputs and outputs. Runtime binaries, package caches and private keys remain
remote.

The retrieved remote evidence archive SHA256 is
`36a74da509eb958101a3f7e5658fae700573302142fe62ae3aa5cfd683ff5ac1`.
`evidence-manifest.json` binds **67 files / 1,766,459 bytes**, all reverified
locally after retrieval. This README is the coordinator's explanatory addition;
it is outside that remote manifest.

The first build failed transiently during prettyprinter 1.7.2 configuration with
`No cabal file found`, although the extracted Cabal file existed. An unchanged
verbose retry configured and built it successfully. Its original log and phase
receipt remain in `diagnostics/first-*`; no root cause or source fix is claimed.
Slow official downloads and rejected mirror paths are retained as setup
observations. The successful GHC mirror supplied the exact official-hash bytes.

No local build/test, Apalache/TLC/model operation, live service call, commit or
push was performed. Native Windows/macOS ACL/TLS behavior, the unselected
historical/model-backed suites and hosted CI remain outside this scoped WSL
acceptance.
