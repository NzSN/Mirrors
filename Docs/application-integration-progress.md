# Application integration execution record

Implementation and automated acceptance completed across 2026-09-16–17 under the
user's instruction to perform the
[implementation plan](application-integration-implementation-plan.md). This is a
local acceptance record. The remaining P12 gates completed on 2026-09-17 using
three actual restricted authors and a fresh-agent onboarding study. This is not
a publication or human-usability claim.
The [role-oriented guide](application-integration-guide.md) is the starting point
for users. [Machine-readable evidence](application-integration-evidence.json)
records source/artifact hashes and the exercised gates.

## Baseline recovery

The initial MirrorECMA checkout was `76ccec0`. A non-destructive fetch recovered
`008234d` (application validation) and
`ff3a214c7620368d94b3f2f892002b6890168588` (matched evidence), including intervening
owned-transport fixes. Their files were brought into the working tree, retaining
the current branch/HEAD and concurrent implementation changes. The earlier
deleted contract/task documents remain deleted.

The recovered three local matrices pass before migration: WorkQueue's nine,
transfer's four, and lease's four mutants reach their pinned first model
mismatches. All local failure controls and cleanup checks pass. Receipts are
`/tmp/integration-baseline-{queue,transfer,lease}-20260916.json`; these local
receipts are not permanent repository evidence. Transfer/lease needed an
authorized rerun outside the enclosing sandbox to spawn the compiler; the
initial `EPERM` runs were environment failures, not behavioral results.

## Delivered work

| Package | Current evidence / remaining work |
| --- | --- |
| P00 | Recovered baseline; all 17 mutant positions retained and all 23 Gate application cases reproduced |
| P01 | Public suite/model/evidence contracts and shared native vectors implemented and exercised across compiler, local runner and real worker |
| P02 | Bundle generation/check, conservative publication and recursive native bridge; established target bytes preserved; native return values and special record keys covered |
| P03–P05 | Immutable suites, strict matched acceptance, source/corpus preflight, joined lifecycle and normalized results; complete client regression passed |
| P06–P07 | Public kit and admitted Node profile/environment; complete required Gate backend gate passed with no skips |
| P08–P09 | Exclusive mode-0600 receipts and original-owner suite workflow; 163 integration tests plus installed failure/control acceptance passed |
| P10 | Project loader/CLI, package/tool pins and doctor; 14 focused tests and installed command round-trip passed |
| P11 | Both installed consumers passed twice after relocation, offline with framework checkouts hidden; local gate also hides global build tools and audits compiler commands |
| P12 | Three migrated suites pass 29 local, 23 Gate and 29 fresh-witness cases; all three fresh actual restricted authors and the automated fresh-evaluator onboarding/diagnosis study passed |

## Final verification

- Mirrors `lake test` passed with live Apalache. Its separate frontend differential
  unit tier ran 60 tests with four optional live-reference tests skipped because
  `DV_LIVE_REFERENCES` was not selected. Existing fixture bytes and sync/async/C++
  freshness gates pass. The new standalone native bridge runtime gate also passes
  and is wired into normal interop; it needs no MirrorECMA checkout or npm package.
- MirrorECMA: 497 tests passed, four existing TG4 transport-integration cases
  skipped because their separate fake-Apalache inputs were not selected. Core,
  model-interface, examples and application-validation TypeScript checks pass.
- MirrorGate required aggregate: 252 Python, 226 Node and four integration tests,
  C++ and Rust checks, actual worker conformance and six lifecycle cases per
  worker passed, with no skips. The optional integration's 163 tests and final
  focused 55-case rerun passed. Its final installed suite repeated nine real
  evaluations twice, including deliberately unconfirmed disposal cleanup.
- Cross-client command set: TypeScript stdio/TCP/mTLS/registry, negotiated Counter
  and offline/live tutorial passed; exact pinned MirrorCPP passed 215/215 tests;
  pinned MirrorRust passed 24 protocol tests and one real stdio smoke; Haskell TCP,
  mTLS, wrong-pin and rogue-client checks passed. The pinned Rust checkout contains
  no server-mode test suite, so Rust TCP/mTLS/registry was not exercised.
- The interop runner initially stopped when a concurrent documentation write had
  not yet created a file required by a new test. The settled client tests and all
  remaining original tiers subsequently passed. This was a successful combined
  command set, not one uninterrupted `run.sh` invocation. Missing C++ prerequisites
  were prepared in temporary/ignored paths using the exact baseline dependency
  versions; no external client source was modified.
- Final whitespace, shell syntax and current documentation-link checks pass.

Review-driven regressions cover successful and failed construction-scope cleanup,
once-only disposer adoption, owned transport release on preflight failure,
independent cleanup budgets after early readiness/iterator failure, pre-cancelled
connector deferral, observer exception versus codec classification, and matching
local/Gate rejection of non-undefined native action returns.

Full logs were written under `/tmp/mirrors-application-integration-*` and
`/tmp/mirrorgate-*`. The six aggregate logs referenced by hash in the evidence
JSON were absent during the 2026-09-17 documentation audit; those temporary
paths are historical provenance, not retained downloadable evidence. Their
hashes, selected installed-consumer records, and archived P12 onboarding
artifacts remain in the repository. No runtime gates were rerun for that audit.
The additive
[historical artifact availability sidecar](evidence/historical-artifact-availability.json)
now inventories every absolute scratch/external locator in this record and the
three related evidence records without changing their bytes or claims. An
unavailable row and its recorded hash do not constitute retained or fresh
evidence. Remediation is a new run with a new E1 run ID and finalized bundle;
it never recreates an old log, substitutes unrelated bytes under its hash, or
changes an old date or source identity to `fresh`.
The application-specific durable summary is
[suite migration evidence](../../MirrorECMA/examples/application-validation/results/2026-09-16-suite-migration.json).

## Completed P12 acceptance, 2026-09-17

Both previously pending activities were completed without changing the framework,
models, corpora or evaluator requirements. [P12 evidence](application-integration-p12-evidence.json)
records the audit, submitted/prepared identities, matched coverage, physical
cleanup and archived onboarding measurements. All previously recorded framework
source/artifact hashes were verified unchanged before accepting these results.

The exact supported `codex-cli 0.153.4` executable was recovered from the existing
npm cache and its package integrity verified. Its SHA-256 is
`56ef98ab4032d317ab26e9b5e5a175650717351edb16ed9cde0cb6d1734d62da`.
A fresh `mirrorgate.codex-dispatch/v1` audit passed against the current support
bytes. The three subsequent authors used model `gpt-5.6-sol`, new private contexts,
the negotiated public environment, and only approved Gate tools. They received
the public contract, sanitized manifest and generated adapter declarations.

| Fresh author | Attempt | Matched initializations | Matched transitions | Physical cleanup |
| --- | --- | --- | --- | --- |
| WorkQueue | 1, passed | 2 | 30 | Confirmed, no remaining resources |
| Persistent transfer | 1, passed | 2 | 30 | Confirmed, no remaining resources |
| Lease service | 1, passed | 2 | 20 | Confirmed, no remaining resources |

Each submitted source hash equals its prepared source hash. No evaluator repair
or private mismatch feedback was supplied. This actual managed-author evidence is
separate from the earlier synthetic/deterministic hosting tests.

The operator profile, verified executable, current audit and private raw receipts
are retained under the ignored, owner-only directory
`../MirrorGate/.build/operator/p12-2026-09-17-pcfrvf26/`. The profile references the
existing private credential file; no credentials were copied into repository
evidence. Future runs must renew an expired or invalidated audit normally.

The onboarding evaluator was a separate agent started with `fork_turns=none`,
without inherited implementation turns. It used only the copied public guides,
prepared public tools, reviewed Counter inputs, an independent correct SUT and
an adapter skeleton. Reading restrictions were instruction-scoped, not OS
isolation. This is an automated unfamiliar-evaluator proxy, not a human study.

| Measurement | Observed result |
| --- | --- |
| Prerequisite installation and packet assembly, measured separately | 293.613 seconds |
| Dispatch with prerequisites ready to first valid replay | 177.436 seconds wall; 161.065 seconds monotonic |
| Packet-read milestone to first valid replay | 134.395 seconds wall; 124.377 seconds monotonic |
| Manual configuration/preparation steps | 4 |
| Added/replacement integration and configuration lines | 54: 3 adapter, 23 project, 28 toolchain; copied pin data included |
| Unexpected product failures | 0 |
| Environment capture failures | 1 `spawnSync EPERM`; recovery and approval overhead recorded, not treated as a product defect |
| Seed activation dispatch to diagnosis, recorded before repair | 67.468 seconds wall; 61.633 seconds monotonic |
| Diagnosis dispatch to verified repair | 83.212 seconds wall; 74.922 seconds monotonic |

First replay matched two traces, two initializations, four transitions and two
required adjacent pairs. The coordinator then changed the real SUT arithmetic,
preserving the observer and evaluator. The same replay produced a genuine mismatch
at trace 0/state 1. The evaluator diagnosed the off-by-one operation, recorded the
diagnosis before editing, repaired one application line and restored the original
SUT hash and passing replay. Independent coordinator probes accepted all three
raw results and verified protected files remained unchanged.

The study found one documentation ambiguity: generated TypeScript compilation
lacked a concrete command. The role guide was clarified after the measurement;
the archived copy hashes identify the guide actually used. No historical time
saving, general human usability, or broader application onboarding rate is inferred.

Package publication remains separate from source-control delivery.
