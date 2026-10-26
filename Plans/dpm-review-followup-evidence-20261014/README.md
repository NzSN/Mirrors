# DPM review follow-up acceptance

Date: 2026-10-14. Status: accepted for the declared remote WSL scope.

The [fix plan](../completed/dpm-review-followup-2026-10-14.md) and
[task breakdown](../completed/dpm-review-followup-tasks-2026-10-14.md) are complete.
[Independent review](independent-review.json) found no remaining confirmed
finding in the corrected scope. The previous [October 14 remediation record](../dpm-review-remediation-evidence-20261014/README.md)
and [October 13 F3–F5 record](../dpm-f3-f5-evidence-20261013/README.md) retain
their original bytes and identities. Working changes remain uncommitted.

## Corrected behavior and direct controls

| Finding | Correction and result |
| --- | --- |
| Cancellation can interrupt cleanup | An ownership token registers before acquisition. Signals record cancellation while ownership is active; execution checks it, and complete cleanup preserves the first failure and final accounting. No signal masks or handlers are swapped. Seven controls verify normal exit, single/repeated signals, timeout cleanup, normal finalization and the first cleanup instruction. Every runner is absent when its host returns; controller rescue is unnecessary. |
| Final C++ observation exceeds its limit | Admission charges the complete wrapped row and required comma before appending events or observations. Exact-limit and one-byte-over regressions pass. The unchanged original reproducer now retains 420 bytes under its 1,024-byte limit, reports `evidence_exhausted`/`passed:false`, and confirms cleanup. |
| Empty literal cannot be represented | Empty literal argv entries are admitted; executable/script/artifact paths remain nonempty, with NUL/UTF-8/closed-object bounds preserved. Pure tests include ASCII and multibyte boundaries. A public launcher control observes an actual empty argv entry. |
| Missing CTest timeout | All 27 discovered synchronization cases have a 30-second timeout. |

The [seven function/handler controls](cancellation/results.json) preserve logs,
measured bytes, ownership registration and original failure precedence.
[Public launcher controls](public-controls/acceptance.json) separately check
single/repeated cancellation and actual empty-argument delivery. Each doctor
passes; the empty-argv stub deliberately omits its response after recording argv,
so its exit 2 proves invocation and refusal, not model conformance.
The [paired C++ result](fixed-cpp-evidence.json) measures event/observation arrays
only; declaration metadata remains separately bounded.

## Final validation

All builds and tests ran on `windows-dev` Ubuntu WSL. [Setup](setup.json) and
[tool identities](tool-probe.log) record Lean 4.33.0, GCC 12.3.0, CMake 3.28.4,
Node 24.19.0, Rust 1.96.0 and Python 3.10.12.

| Gate | Result |
| --- | --- |
| Lean build | 727 targets passed |
| Pure policy / typed supplied-state evidence | 25 / 11 gates passed |
| DPM Python | Final 65 tests passed, including seven ownership regressions |
| C++ scheduling / binding / exploration | 35 cases / 752 assertions passed |
| C++ controlled synchronization | 27 cases / 362 assertions passed |
| ECMA scheduling / binding / exploration | 23 tests passed |
| Rust | Fresh offline consumer build and vendoring passed |
| Fresh installed C++ / ECMA / Rust | All three passed with sources hidden and network isolated |
| Full non-model suite | Exit 0; [raw log](logs/local-no-model-check-qualified.log) ends `ALL LOCAL NON-MODEL GATES GREEN` |

[Phase results](phase-results.json) select `acceptance-phase.exit = 0`,
`local-gates-qualified-phase.exit = 0` and `python-final-phase.exit = 0`.
The old-launcher control refuses changed helpers before execution.
Pure candidate plans are byte-identical across repeated checks.

The [fresh installation](installation-manifest.json) has selected SHA-256
`aa12b8377ee829558d8b872bb2ae793505e471cb21a22599a094fe54501351f8`;
all 5,265 file hashes and executable modes verify, and the inventory stays
unchanged. [Installed acceptance](installed/acceptance.json) and independent
review verify 24 supplied-trace catalog matches, 120 local SDK schedules,
24 malformed-receipt refusals and 30 distinct cleaned reduction executions.
Each reduction confirms two baselines, seven smaller trials and a fresh best
replay, preserving the write/count delta-1 failure while reducing
`[3,1,4,7]` to `[2,0,0,6]`. Minimality is confined to the admitted catalog.
The separate installed C++ controlled-resource sample and returning-callback
overrun control also pass their declared gates, with `modelComparison:false`.

## Identities, diagnostics and recovery

[Baseline](baseline.json) freezes the starting working trees and historical
manifests. [Frozen changes](frozen-inputs.json), [source manifest](source-manifest.json),
[identity refresh](identity-refresh.json), raw logs/receipts and [workflow](workflow)
bind this corrected implementation. All 36 selected implementation files match
the qualified remote source. Final documentation is recorded separately from
compiled inputs. The [evidence manifest](evidence-manifest.json) inventories the
completed dossier except itself; executable/development-kit bytes remain remote.

The initial Lean workflow's exit 1 came from one Python test finding old helpers
at the executable-resolved D: share directory. Lean and pure gates had passed;
refreshing only the new share directory fixed staging, and the final focused
suite passed. The diagnostic log remains. The first curation archive omitted
ECMA records due to a filter error; the corrected complete archive supersedes it,
with the transport diagnostic preserved. Neither failure receives pass credit.

Sources and the installation live in ordinary ext4 directories under
`/home/jlc/Tools/mirrors-dpm-followup-20261014`, in a new task-owned 12-GiB image
on D:. Large copied build caches and outputs also use the new D: namespace.
Earlier source/install trees and images were preserved. WSL shutdown removes
the mount; [mount-keeper.sh](workflow/mount-keeper.sh) remounts the existing image
without formatting it. The temporary keeper is closed after evidence freeze.
Owned build phases and the full suite bound native jobs to two. The unchanged
installed Rust gate used Cargo default parallelism in its sanitized environment;
it finished with ample remote RAM. [Setup](setup.json) records this exception.

## Scope

No local builds/tests, fresh model checking, production service changes,
commit or push occurred. Live Apalache/Counter/async/explorer and TLA reference
tiers remain explicitly skipped; acquisition fixtures use mocked tool calls.
F5 remains experimental C++ without model comparison. This record does not
extend frozen M5 C0, native-platform acceptance or broader M4 enforcement.
Cancellation is cooperative for the main-thread host and non-detaching runners;
uninterruptible kernel waits still need an external owner. Evidence accounting
is not an OS disk/memory quota, and returning-callback checks do not provide
hard in-process interruption. Trusted Python platform prerequisites remain.
