# Current framework status and navigation

Source status refreshed 2026-10-22 against Mirrors `b243b37` (`v0.1.0`) and
the current DPM build-preparation changes. The DPM implementation landed in
`c17bae9`; the October 15 client-conformance repairs landed in `d1c5e74`.
These source identities do not replace the exact runtime and source hashes in
[October 14 DPM acceptance](../Plans/dpm-review-followup-evidence-20261014/README.md)
or [October 15 conformance acceptance](../Plans/client-conformance-fix-evidence-20261015/README.md).
The [preceding remediation record](../Plans/dpm-review-remediation-evidence-20261014/README.md)
and [original October 13 evidence](../Plans/dpm-f3-f5-evidence-20261013/README.md)
remain unchanged history.

DPM launcher builds now prepare the local interpreter/helper identity before
compilation; an explicit build-time interpreter can be selected with
`MIRRORS_DPM_PYTHON`. Runtime hash checks remain enforced. See the
[build and runtime prerequisites](dpm-cli-guide.md#build-and-runtime-prerequisites)
and newest [checkpoint](../CHECKPOINTS.md) for current working-tree validation
and its temporary-directory-path limitation. The
[October 22 build evidence](../Plans/dpm-build-preparation-evidence-20261022/README.md)
records the complete non-model pass with `TMPDIR=/tmp`, 79 DPM Python tests and
bounded installed-launcher checks. The inherited `TMPDIR=/tmp/` aggregate
failure is also reproduced at the baseline and remains an open sanitizer issue.
This source/build change does not renew full DPM installed-package or framework
acceptance.
The [October 9 documentation audit](../Plans/documentation-sync-2026-10-09.md)
remains a historical full source-navigation audit across linked repositories; this
refresh reconciles maintained status and the affected DPM ownership paths.

## Qualified scope and evidence

The [published roadmap candidate](../Plans/q3-published-roadmap-2026-10-07.md)
qualifies for `m5-wsl-windows-remote/v1`, qualification class `local-candidate`,
at Mirrors `f0894d2`, MirrorECMA `eef6f71` and MirrorGate `455e196` under C0
`94271a543085118e47c7fd540ee8d34d3f427fa5f45fedaeba0c852534f4f34a`.
All 18 required commands/16 tiers, both installed D bindings, 19 scope nodes,
20 independently verified bundles and six rejected controls pass. Source-hidden
installed replay, real mismatch/mutation, both R1 branches, prefix/domain
reduction, prepared-filesystem recovery and the remote model/client matrix are
bound to that record. Subsequent documentation/catalog publication does not
extend it to a new implementation or release automatically.

The October 22 [release-line compatibility record](../Plans/version-migration-2026-10-22/compatibility.json)
contains 28 actual SDK transport rows and 24 Gate composition rows against the
earlier server `ea8091c` and its recorded binaries. The replacement `v0.1.0`
tag at `b243b37` has [focused release validation](../Plans/version-migration-2026-10-22/retag.json)
only. The retag grants no new cross-client, live-model or full-framework
qualification; the original compatibility and publication records remain
observations of their original commits and binary hashes.

M6 reviewed scaffolds/corpora, compiler/client follow-ups and the read-only
[lock migration helper](model-interface-compiler/lock-migration.md) are implemented.
[DPM](deterministic-scheduling.md) is accepted through DPM-5 for declared C++,
Node-worker and Rust-thread profiles. Its finite/native/package evidence remains
separate from the framework's independently pinned compatibility matrix.

The latest qualified topology uses WSL2 clients, local supplied-trace replay and
Linux/Bubblewrap Gate; live model operations use an owned native Windows mTLS
Mirrors service with Apalache 0.62.2 / Java 25.0.4+7-LTS. The service was started and
observed as PID 35888 during that campaign; reobserve before use. Its original
certificates were recorded as valid through 2026-10-08T02:47:53Z; that validity
window has ended as of this documentation review. No live service or replacement
certificate was inspected. Reconcile any renewed credential and pin identities
before remote work. Neither static documentation nor an old PID/certificate
record establishes current health or permission to re-pin.
No local Apalache/TLC runs on this coordinator.

## Approved usability features after the frozen candidate

The [generated DPM kit and counterexample timeline](dpm-usability-design.md)
remain source accepted. F3 now supplies a deterministic reducer over an explicit
finite oracle-backed catalog, with baseline reproduction and fresh best replay.
F4 supplies the [installed CLI](dpm-cli-guide.md) for C++/Node-worker/Rust-thread
application runners. F5 supplies a separate experimental C++ controlled mutex/
bounded FIFO profile; its local execution receipts do not establish model comparison.
See the [runner contract](dpm-runner-contract.md),
[feature plan](../Plans/dpm-usability-features-2026-10-07.md) and
[October 14 follow-up evidence](../Plans/dpm-review-followup-evidence-20261014/README.md)
for the accepted source/runtime identities, actual gate results and limits. Both
remote installed acceptance and the full non-model suite passed in that campaign.
Independent review confirmed all three fresh profiles and found no remaining confirmed findings in
its reviewed scope. Current projects use v2 typed commands; receipt/oracle checks,
retained-output accounting and C++ callback/join deadlines include the review
corrections. Cancellation preserves ownership through the first cleanup
instruction and final accounting; C++ admission measures complete retained
rows and commas; empty literal arguments remain intact. These changes do not extend the frozen M5 candidate or
qualify a new framework release. Broader M4 stays independent.

## Separate work and open choices

- Broader M4: aggregate cgroup enforcement and active-process post-restart
  recovery stay on a separate track, as explicitly requested by the user. See
  [native-host/process ownership plan](../Plans/m4-native-host-and-platform-plan-2026-10-07.md).
- Native Ubuntu acceptance, Windows/macOS Gate backends, service-manager
  AUTO_START acceptance and the legacy full all-transport matrix remain separate.
- DPM does not supply arbitrary instruction preemption, browser or async-Rust
  scheduling, weak-memory completeness, POR or generic native trap instrumentation.
  Non-intrusive scheduling is optional research, not an approved implemented profile.
- Package-registry publication, hosted CI and production deployment are not
  inferred from source commits or the named local-candidate qualification.
- [Haskell cutover](cutover.md) retains the stdio async error-tag decision and
  its documented deprecation/soak criteria. The multi-client runner is implemented.

## Find the maintained documentation

| Need | Entry point |
| --- | --- |
| Read architecture in a terminal | [Plain-text blocks](architecture-overview.txt) |
| Explore component/source relationships | [Architecture overview](architecture-overview.md), [interactive view](architecture-overview.html), [module details](architecture-details.md) |
| Locate client, evaluator and worker owners | [Framework map](framework-map.md) |
| Integrate an application | [Role guide](application-integration-guide.md), [usage guide](usage-of-mirror-framework.md) |
| Control participating threads under MBT | [DPM guide](deterministic-scheduling.md), [build/install/replay CLI](dpm-cli-guide.md) |
| Review compiler/profile/migration contracts | [Compiler index](model-interface-compiler/README.md), [generated specification](generated-model-interface-spec.md) |
| Operate model checking remotely | [Remote guide](remote-server-guide.md), [qualification harness](qualification-harness-design.md) |
| Inspect completion and planned extensions | [Framework roadmap](../Plans/mirror-framework-improvements.md), [execution decisions](../Plans/execution-decisions.md) |
| Inspect exact accepted identities | [October 7 readiness](../Plans/q3-published-roadmap-2026-10-07.md), [DPM acceptance](../Plans/dpm-review-followup-evidence-20261014/README.md), [conformance acceptance](../Plans/client-conformance-fix-evidence-20261015/README.md), [release retag scope](../Plans/version-migration-2026-10-22/retag.json), [checkpoint history](../CHECKPOINTS.md) |

Dated baselines, proof statements, frozen fixtures and machine-readable acceptance
files retain their original bytes/counts. A historical “pending” stage is not a
current blocker when a later record explicitly supersedes it. Generated catalog A
shows its own declarations and unknown observations; later approval B carries the
actual scoped observations. Documentation sync never fabricates either record.
