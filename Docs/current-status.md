# Current framework status and navigation

## October 30 completion design and execution plan

The [completion, qualification, and release design](completion-qualification-release-design.md)
and [fine-grained execution plan](../Plans/completion-qualification-release-plan-2026-10-30.md)
now cover all remaining stages: final source/evidence freeze, audited branch
delivery, clean tagged Linux/Windows packaging, native M4, exact-candidate
M5/D/Q and Windows acceptance, release admission, publication, deployment,
rollback, reboot, retention, and the two-release compatibility lifecycle.
They define identity invalidation, explicit approval boundaries and exit gates.
This planning addition does not change the candidate or grant any new
qualification, publication or deployment result.

## October 29 completion campaign in progress

The [execution plan](../Plans/completion-execution-plan-2026-10-29.md) is being
performed from published `7e9a27d`. The source prepares `v0.2.0-rc.1`; nothing
has been published or deployed. The [new evidence record](../Plans/completion-evidence-20261029/README.md)
records completed finite F5 remote model comparison/reduction, independent
profile-6 T/U acceptance, source-hidden installed C++/ECMA/Rust DPM acceptance,
the RC non-model/native rebuild gates, eight native Windows runtime suites and
the selected MirrorGate complete required gate. A new TLS long-poll timeout fix
is included. Raw F5 SDK receipt semantics remain unchanged.

The current five-client mTLS matrix passes all 22 verdict/pin/protocol rows.
The installer now derives observed platform/package versions from actual inputs,
and its complete non-model aggregate passes after that correction. The Ubuntu 24.04 reference
distribution's full M5/D/Q renewal needs a matching selected environment; this
coordinator is Ubuntu 26.04. Native M4 needs the requested native runner and
delegated cgroup-v2 parent. The compatibility decision retains stdio
`register_error` and the Haskell oracle with measured retirement prerequisites.
Windows RC packaging is staged; Linux packaging and the final release handoff
are prepared downstream of the validated source snapshot. The separate fetched
Apalache carrier was refused on its archive hash; its contained JAR matches the
observed selected runtime, and the original archive pin remains unchanged. Historical records below keep their original scope.


## October 29 source-review bug fixes

Working-tree fixes at base `0cb5679` resolve six reproduced runtime findings:
shared HTTP receive storage, partial async trace decoding, Explorer's successful
exit after failed assertions, oversized async diagnostics, Unicode HTTP lengths
and rejected-pin socket retention. TLS handles now retain boxed ownership
through native FFI wrappers so their finalizers run. The affected
[wire contract](interface-reference.md) and [native boundary](../Ffi/README.md)
describe the resulting behavior.

The complete local non-model aggregate and isolated native rebuild check pass.
The original probes pass after restoring the exact already-pinned SANY bytes
in the ignored cache while preserving the previous artifact. No pin changed.
[The evidence record](../Plans/runtime-source-review-fix-evidence-20261029/README.md)
retains initial failures, final passes, identities and skipped tiers. These local
checks do not renew live-model, native M4 or framework/release qualification.
The user subsequently authorized commit and push of these fixes and their
retained evidence; the newest checkpoint records that branch publication.

## October 29 publication boundary

The user authorized branch commit/push of the runtime review and SANY re-pin.
The newest [checkpoint](../CHECKPOINTS.md) records audited scope and the separate
MirrorGate upstream rebase and passing destination gates. Publication does not
renew native, live differential, installed/framework or release qualification;
the October 28 identities and outcomes remain attached to their original records.

## October 28 SANY re-pin and local remediation closure

At the user's explicit request, native-runner acceptance is excluded from this
work and SANY is re-pinned to artifact `fc6878c6…`, manifest `2.0 2026-10-28`,
revision `56d37a9`. Exact artifact/help metadata and a content-addressed retained
copy replace the stale cache; the old bytes remain preserved. All standard-library
and catalog facts match, so profile 6/catalog v3 and corpus approvals are unchanged.

The complete local non-model aggregate is green, including the earlier runtime
remediation and previously failing standard-catalog checks. This supersedes the
same-day artifact blocker below. [Current re-pin evidence](../Plans/sany-repin-evidence-20261028/README.md)
records 78 offline differential checks with four live skips, exact identities and
scope. Native M4, live differential and installed/framework/release qualification
are not granted by this local closure or by the user's scope exclusion.

## October 28 architecture/runtime review follow-up

Uncommitted remediation at base Mirrors `ed86c2c` / MirrorGate `5055d91` adds
bounded retained outcomes, exact group-covered journal-v2 recovery with durable
pre-removal quiescence evidence, and persistent private-evaluation attempt budgets
with service-level disclosure. The [boundary contract](mirrors-gate-boundary.md)
and [evidence record](../Plans/mirrors-gate-runtime-review-evidence-20261028/README.md)
identify source changes, passing local destination checks, original failures and
unexercised native tiers. Required native Linux/delegated-cgroup acceptance is
still unavailable; the full Mirrors aggregate also retains its unrelated pinned-
SANY cache failure. These changes grant no installed/framework qualification.

## Previous source refresh

Source status refreshed 2026-10-26 against committed temporary-root
canonicalization in `658b9ef` and the scoped October 26 changes below. The DPM
build-preparation fix is committed in `03510b4`. Mirrors reducer/CLI tooling
landed in `c17bae9`; the October 15 client-conformance repairs landed in `d1c5e74`.
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
and newest [checkpoint](../CHECKPOINTS.md) for the separate patch-release
validation/publication boundary and the temporary-path repair.
The [October 22 build evidence](../Plans/dpm-build-preparation-evidence-20261022/README.md)
retains exact source/artifact hashes for the changes committed in `03510b4`:
the complete non-model pass with `TMPDIR=/tmp`, 79 DPM Python tests and bounded
installed-launcher checks. The `v0.1.1` version/documentation changes passed
focused local release gates; their separate validation is recorded in the newest
checkpoint, with hosted publication tracked independently. They do not rewrite
the earlier build evidence. The inherited `TMPDIR=/tmp/` aggregate failure was
also reproduced at the baseline. The current repair resolves temporary roots
to physical paths before creating owned spec/session directories, keeping the
recorded run path aligned with child diagnostics for redaction. New validation
is recorded in the newest checkpoint; the original failed receipts are unchanged.
This source/build change does not renew full DPM installed-package or framework
acceptance.
The [October 9 documentation audit](../Plans/completed/documentation-sync-2026-10-09.md)
remains a historical full source-navigation audit across linked repositories; this
refresh reconciles maintained status and the affected DPM ownership paths.

## October 26 scoped continuation

The [Windows model-interface repair](../Plans/windows-compiler-temp-path-fix-evidence-20261026/README.md)
resolves the eight stale-path/race assertions; the initial Windows pass was
followed by three consecutive repeats. Production publication/rollback code is
unchanged. The upstream `658b9ef` temporary-root implementation and its broader
regressions are retained instead of the independently developed local duplicate.

The explicitly requested [SANY re-pin and profile-6 migration](../Plans/sany-repin-profile6-evidence-20261026/README.md)
binds the new jar and its changed standard-library identity. Because `Bags`
no longer publicly extends `TLC`, the migration advances to
`mirrors-tla-frontend-profile-6` and `mirrors-standard-modules/v3`, preserves
profile-5 approvals in a byte-identical archive, and starts a new unreviewed
difference registry. The complete no-model aggregate passes with ext4 `TMPDIR`:
728 build jobs and all configured gates are green. Profile 6 remains provisional
pending fresh Java 25 live differential qualification; the coordinator's Java
21 does not satisfy that unchanged runtime pin.

A separate [October 26 Windows service record](../Plans/windows-service-upgrade-evidence-20261026/README.md)
observes a scoped upgrade to `v0.1.0` (`b243b37`) on the native Windows
`ModelMirrors` service. Six focused runtime suites and the live positive/
negative controls passed; full `lake test`, complete cross-client qualification
and reboot/service-lifecycle acceptance did not run. This retained observation
does not establish current service health or v0.1.1 deployment.

## Qualified scope and evidence

The [published roadmap candidate](../Plans/completed/q3-published-roadmap-2026-10-07.md)
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
observations of their original commits and binary hashes. The compatible
`v0.1.1` patch uses a new immutable tag and leaves `v0.1.0` unchanged. Its release
validation is separate from full cross-client, live-model and framework
qualification. The hosted release archive includes `mirror` and
`model_interface_gen`; DPM uses its separate build/install procedure.

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
window has ended. The October 25 renewal campaign separately observed that the
old process and address were absent, then prepared an isolated owned Windows
fixture at `172.28.144.1:8999` with fresh seven-day mTLS credentials. It retains
the pinned oracle binary/runtime and preserves the original deployment records
and credentials. The new endpoint and rebuilt interop harness identities are
selected explicitly by the current qualification tooling. The newest checkpoint
records campaign progress and acceptance; fixture startup alone grants no new
framework or current native-Windows release qualification. Reobserve the fixture
before use; a recorded PID or certificate does not establish current health.
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
| Inspect exact accepted identities | [October 7 readiness](../Plans/completed/q3-published-roadmap-2026-10-07.md), [DPM acceptance](../Plans/dpm-review-followup-evidence-20261014/README.md), [conformance acceptance](../Plans/client-conformance-fix-evidence-20261015/README.md), [release retag scope](../Plans/version-migration-2026-10-22/retag.json), [checkpoint history](../CHECKPOINTS.md) |

Dated baselines, proof statements, frozen fixtures and machine-readable acceptance
files retain their original bytes/counts. A historical “pending” stage is not a
current blocker when a later record explicitly supersedes it. Generated catalog A
shows its own declarations and unknown observations; later approval B carries the
actual scoped observations. Documentation sync never fabricates either record.
