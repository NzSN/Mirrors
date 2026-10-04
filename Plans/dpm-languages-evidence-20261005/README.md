# MirrorECMA and MirrorRust DPM acceptance

Accepted 2026-10-05 (Asia/Shanghai; capture timestamps use UTC). DPM-0 through
DPM-5 pass for the two experimental profiles in the
[execution plan](../dpm-mirrorecma-mirrorrust.md):
`mirrorecma.worker-checkpoints/v1` and
`mirrorrust.cooperative-checkpoints/v1`. Node workers retain async stacks;
Rust owns real OS threads. Both expose incremental generated replay, separate
comparison/cleanup receipts and finite checkpoint exploration.

## Installed evidence

[Installed acceptance](installed/acceptance.json) binds six reports and the
[input manifest](installed/input-manifest.json). Each language passed:

| Gate | Result |
| --- | --- |
| Generated counter replay | 60 cases over four fresh oracle captures |
| Finite exploration | 11 checks; full finite case is 20 interleavings × two inputs |
| Native WriteSentry pilot | 14 runs: four schedules twice, two production mutants, cancellation, wrong image, child exit and phase mismatch |
| Native mapping admission | Three incompatible mappings refused before acquisition |
| Artifact admission | Missing and tampered inputs refused |

Read [ECMA](ecma-acceptance/counter/acceptance.json) or
[Rust](rust-acceptance/counter/acceptance.json) counter reports, their sibling
`exploration/acceptance.json` and `native/acceptance.json`, and the referenced
raw receipts. Mutation success means a real expected Mirrors `step_mismatch`.
Full finite exploration is local coverage, not universal model conformance.

The consumers compiled from the actual npm archive and Cargo crate while `/home`
and the ordinary `/tmp` were hidden, with an isolated network namespace. Rust
metadata confirms the admitted crate path. The Linux namespace does not sandbox
the external Windows workers reached through WSL. Inputs were hash-verified both
before and after execution. Current Rust source and current compiled ECMA modules
match the admitted package contents. The [build identity](build-identity.json)
records archive and executable hashes. Packages and receipts are retained here;
full vendor/toolchain trees and large executable artifacts remain in the named
`/tmp/dpm-languages-installed-20261004` tree. This is not a self-contained release
archive or a published package release.

## Models, generated bindings and native ownership

[Fresh oracle acceptance](oracles/acceptance.json) records eight captures and six
bounded VALID checks: counter Safety at bound 6 for Init/InitFive, and native
MBTSafety at bounds 28/17 for the four fixed schedules. Model requests, raw ITF,
source closures and replies are retained. No local model checker ran. The
[before](oracle-before.json) and [after](oracle-after.json) observations preserve
PID 2572 and binary hash `5949af30735cd1bf515e64fb9d2299023e13b2c36245ce9be696d65944b32dec`;
Apalache 0.62.2 and Java 25.0.4+7-LTS were observed. The service was not restarted
or reconfigured.

Native source/build manifests bind the previously frozen application worker,
not every current WriteSentry working-tree file. Each replay retains fresh
process/thread identities and actual native observations. The final
[host observation](native-host-observation.json) records zero remaining owned
processes. Historical C++ evidence was left unchanged.

[Generated acceptance](generated-acceptance.json) verifies all six consumer
copies byte-for-byte against the current compiler and retained locks. Existing
v1 profiles remain stable; additive `mirrorecma-async-v2` and `mirrorrust-v2`
support the native integer-key maps. Installed codec tests reject duplicate or
wrong map keys and check integer precision. V2 ECMA bundle/project commands and
integer map-key projections are outside this implementation.

## Source regressions and fixes

The retained `logs/` contain the full local Mirrors gate pass, compiler build,
MirrorRust test/clippy results and MirrorECMA stages. Mirrors' local model tiers
self-skip by design; the remote checks above supply this campaign's model evidence.
MirrorRust reports 91 successful test functions, including three existing live
smoke functions which returned early without MIRROR_BIN: 88 executed source tests,
including 19 new scheduling/lifecycle tests. Strict all-target clippy passed.
MirrorECMA passed 676 Jest tests (13 optional tests and one suite skipped), plus
22 scheduling tests. Compiler, generated replay, packed-package boundary,
async replay and WorkQueue stages passed across the retained logs. There is no
claim that an entire final CI invocation exited zero: earlier combined commands
stopped on stale generated fixtures and a package-boundary false positive;
subsequent targeted stages passed after repairs.

The existing stale ECMA Counter/WorkQueue fixtures were regenerated through the
compiler. The package-boundary check now parses dependency syntax, so the ordinary
`mirrorgate` data-role string is accepted while actual forbidden imports remain
rejected. Scheduling fixes cover observer cancellation, late worker hooks,
cleanup retry receipts, comparison-plus-cleanup failures and binding reentry.

## Scope and next use

Use the SDK guides at `MirrorECMA/docs/deterministic-scheduling.md` and
`MirrorRust/docs/deterministic-scheduling.md`, and the executable consumers in
`tools/deterministic-scheduling/languages/`. The checker supports counter,
exploration and native scopes; `capture.py` obtains the selected remote oracles,
and `check_installed.py` rebuilds the package acceptance with an explicit vendor
tree and native dependency.

No browser or async-Rust scheduler, arbitrary in-process preemption, POR,
weak-memory completeness, generic native scheduler, full WriteSentry validation,
Windows Gate backend or new M5 candidate is claimed. Cooperative non-returning
callbacks can still prevent bounded cleanup. Work remains uncommitted and
unpublished; unrelated Rust protocol-test edits and editor caches are preserved.
