# Mirrors / MirrorGate architecture runtime remediation

Date: 2026-10-28. Base checkouts: Mirrors `ed86c2c` and MirrorGate `5055d91`.
These are uncommitted source changes with scoped regression evidence, not a new
installed distribution, native-host acceptance or framework qualification.
Earlier dated evidence and editor caches are preserved.

## Changes and disposition

| Finding | Concrete correction | Evidence boundary |
| --- | --- | --- |
| Observation fidelity | The architecture requires the existing protected real-SUT observer/probe campaign. Added Gate regression rejecting matching reports when the independent probe disagrees | Six actual application observer-fidelity tests and the Gate campaign regressions; finite protected closures, not universal observer honesty |
| Controller-crash cleanup | V2 journal records bind a process to an exact owned group/delegation before releasing execution. Recovery requires durable observed-empty group cleanup, retains terminal counters, and preserves retries for failed enclosing cleanup | Journal, recovery and production-hook regressions. Actual native descendant/controller-death gates are added but cannot run without an admitted native host/delegation |
| Retained results | Pure retention admission reserves at most 256 entries by default; each stored encoded outcome is bounded at 262,144 bytes. Oversized outcomes fail before terminal publication and promise resolution; eviction restores admission | Kernel-checked arithmetic bound and concurrent/cancellation/eviction/multibyte regressions. The 64 MiB encoded-data envelope is independent of wire-frame size and OS RSS |
| Adaptive feedback | Optional private service mode requires durable author/corpus attempt budgets. Exclusive synchronized markers survive restart and arbitrate concurrent consumers; failures never refund attempts. Minimal disclosure is applied at the service boundary | Real HTTP restart/duplicate/failure/concurrency tests, concurrent marker consumers, and private-mode disclosure rejection. Operator budget-directory custody remains trusted |
| Trusted computing base and result paths | Updated Markdown, text and interactive architecture, with trusted compiler/binding ownership and separate private/public result paths | Payload equality, script checks, renderer smoke and local source links; no whole-executable proof claim |

## Preserved failures and exclusions

The first Mirrors aggregate stopped at two `StandardCatalogTests` setup failures:
the existing cached SANY jar hashes to
`db131ddb48e7004d823bef4493df7b35694babe37505b9d9fa5685e7a331f1f1`, while
the unchanged pin requires
`d15655eeaff4b3f7b3d65c46b838bc0f35d131b2ef4b1e473689b62c98d4726f`.
A minimal unchanged-HEAD replay reproduces both failures. The existing release
URL now returned
`fc6878c603f0fdc18b9fe3e5bf51860cb90ab5b1154e3c371660c036d6bdd63e`;
that download was rejected. Neither the pin, profile, catalog nor cached jar was
changed. The failed aggregate is retained; subsequent gates are recorded
separately and cannot turn it green.

The first transport follow-up detected that a wire-sized retention cap bypassed
the existing oversized-trace delivery error. The final default is a separate
256 KiB storage cap. The final replay must preserve the transport boundary/error
checks; the initial failed receipt remains separate.

The current host is WSL2 `6.18.54.1-microsoft-standard-WSL2`, UID 1000, with no
operator-supplied cgroup-v2 delegation. Read-only M4 preflight reports
`nativeLinuxHost: false`, `kernelEnforcementTested: false`, and
`postRestartProcessRecoveryTested: false`. No host configuration was changed and
no local Apalache/TLC was started. Tests skipped for missing cgroup requirements
are not passes. Native process-tree recovery, whole-host aggregate/storage
acceptance and a new exact framework freeze remain outstanding.

## Required external completion

Use the admitted native Linux runner with the operator-owned delegated parent:

```sh
MIRRORGATE_REQUIRE_CGROUP=1 \
MIRRORGATE_CGROUP_PARENT=/operator/delegated/parent \
MIRRORGATE_REQUIRE_SANDBOX=1 \
PYTHONPATH=supervisor \
python3 -m unittest discover -s tests -p 'test_cgroup_acceptance.py' -v
```

The required cases include actual quota/descendant observations, production
backend membership hooks, abrupt controller death, exact group/process/filesystem
reclamation, idempotent recovery and unrelated sentinel survival. Keep the
interrupted behavioral result abandoned. Record the actual host, source/runtime
identities and receipts; mocked controller files do not satisfy this gate.

## Final local receipts

The [summary](summary.json) records 16 commands and retained log hashes. The
destination Gate gate passes 311 Python tests with five required-native-profile
cases skipped, 227 Node tests, 11 integration tests, three C++ CTest cases and
the Rust/native worker gates. The optional integration suite passes 171 tests;
seven durable-budget and 12 new group-process contract cases pass. The latter
include the cut after group removal but before terminal publication, rejection
of unexplained disappearance, stale boot/delegation/digest refusal, production
hooks, retry and original-PID safety. These are contract tests, not native kernel
acceptance. Six observer-fidelity and 142 Mirrors evidence tests also pass.

The final Mirrors build completes 728 jobs. The retained-outcome theorem passes
the explicit standard-axiom audit, and the job-store suite covers concurrent
admission, cancelled reservations, repeated delivery, eviction and multibyte
storage overflow. The final post-differential local gates pass, including the
previously failed trace-overflow fixture, with live tiers explicitly skipped.
The earlier failed aggregate and failed first retention cap remain in `logs/`.

The [Gate manifest](gate-source-manifest.json) binds all 20 destination source,
documentation and test files against their original Git blobs. The
[Mirrors manifest](mirrors-source-manifest.json) records the corresponding current
source/doc/checkpoint identities. [Native preflight](native-preflight.json)
retains the exact current host/source observation and unavailable prerequisites.
Packed JS/TS consumers, the private-service declaration consumer and package
inclusion of the new durable-budget module pass. Diagram payloads, 26 rendered
nodes/31 edges, script syntax and local links pass structural/renderer checks;
the optional Chromium screenshot attempt crashed and supplies no visual credit.

No source-regression receipt replaces native-host/storage admission, the exact
pinned SANY artifact, a new source freeze, or corresponding framework gates.
