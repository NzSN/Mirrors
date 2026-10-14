# F3–F5 implementation and acceptance

Date: 2026-10-13. All six authorized execution stages are implemented and
accepted within the scopes below. Changes remain uncommitted. The implementation
starts from Mirrors `66f9418`, MirrorCPP `75a63db`, MirrorECMA `fe9a648` and
MirrorRust `7606173`; [source-manifest.json](source-manifest.json) binds the exact
working files and full base revisions. MirrorExamples and ModelMirrors are
excluded. No commit, push, publication, service change or fresh model check ran.

## What each stage delivered

| Stage | Implementation | Acceptance |
| --- | --- | --- |
| 1: contract | [Runner contract](../../Docs/dpm-runner-contract.md): trusted project selection, oracle authority, process lifetime, signatures, finite scope and experimental resource semantics | Explicit implemented boundaries and exit gates |
| 2: policy and ownership | `Core/Dpm.lean` validates whole actor chains and deterministic costs; `Codec/Dpm.lean` admits closed bounded JSON; `Shell/Dpm` dispatches the CLI and verifies packaged Python/runtime identities; the host owns request process groups, deadlines and evidence | Lean build, eight pure gates, strict admission and actual timeout/output/receipt controls |
| 3: actual SDK adapters | Application-owned C++/Node-worker/Rust-thread Counter runners use existing SDK binding sessions and actual SUT observations. A real initialization spectator can be removed together with its complete chain/factory declaration | Three reductions preserve the same actual `write/count` mismatch and confirm physical cleanup |
| 4: installed CLI | `mirrors-dpm doctor/replay/explore/reduce/report`; verified inventory/modes, staged installation and atomic no-overwrite activation; packaged explicit consumer prerequisites | Three fresh consumers rebuilt and exercised with checkouts hidden and Linux networking isolated |
| 5: controlled resources | Separate C++ `mirrorcpp.controlled-sync-experimental/v1` module: nonrecursive mutex, bounded signed-integer FIFO, real worker threads, explicit enabled sets, fixed decisions and fresh prefix exploration | Eleven tests/179 assertions plus an installed public-header/library consumer with actual count/FIFO checks |
| 6: integration | Lake/local gates, SDK regressions, updated guides/checkpoint and this separate dated evidence | All recorded gates pass; earlier frozen qualification remains unchanged |

The [CLI guide](../../Docs/dpm-cli-guide.md) gives commands and prerequisites.
The [C++ prototype guide](../../../MirrorCPP/docs/controlled-synchronization.md)
describes resource boundaries, misuse, deadlock and lifetime constraints.

## Reducer result and scope

For each language, the actual baseline contains three workers, input rank 1,
four preemptions and seven intervals. The best candidate contains two workers,
input rank 0, zero preemptions and six intervals:

```text
[actors, input rank, preemptions, intervals]
[3, 1, 4, 7] -> [2, 0, 0, 6]
signature: counter-count-delta/v1, action write, path count, integer delta 1
```

The host reproduces the baseline twice, compares all seven smaller admitted
candidates through the real generated binding/Mirrors comparison path, and
freshly replays the best candidate. Each reduction retains ten distinct SDK
execution IDs and confirmed cleanup. [Acceptance](acceptance.json) records the
IDs; raw SDK receipts, requests, replies, schedules and logs live under
`installed/{cpp,ecma,rust}/reduction/`.

The claim is `minimal_in_admitted_catalog`. The eight-candidate catalog has two
declared initial values, serial/overlapping chains and an optional real,
model-inert spectator. Retained actors keep their entire local chain. This does
not establish a global schedule/input minimum or arbitrary actor-removal
correctness. A one-attempt control reports `best_observed` with a freshly
confirmed best replay. Unresolved trials or lost cleanup stop the search.

The Counter signature permits only the reviewed integer `write/count` delta;
unrelated field changes or ambiguous attribution refuse. Other applications
must supply their own reviewed factories, candidate catalog and correspondence,
and select `exact-terminal/v1` or the reviewed Counter normalization. Adding a
new normalization requires a new packaged host identity.

## Installed evidence

The selected [installation manifest](installation-manifest.json) has SHA-256
`81a0bb368f108ea12880ed3f7cec6a253c329390817e2f6e81d0c91c42078ef2`.
The prepared tree was installed at `/tmp/mirrors-dpm-installed-v3-20261013`.
Compiled/build artifacts remain scratch artifacts; this record retains their
inventory hashes, inputs, commands, actual receipts and logs.

The [installed acceptance](installed/acceptance.json) and
[namespace command](installed/command.json) record Bubblewrap hiding `/home`
and the original `/tmp`, mounting only the admitted installation, writable
consumer output, three copied gate helpers and the explicit Rust toolchain.
Linux networking was isolated. C++ compiled against installed headers/library;
ECMA compiled generated TypeScript against the installed SDK declarations;
Rust built offline from the packaged SDK and vendored dependencies.

The original installed inventory stayed unchanged. Fresh consumers are copied
to a separate output tree and explicitly rebound to their newly built binary
identity; the Rust consumer therefore has a different project digest from the
prebuilt installation. Both selections are retained, with no identity inheritance.

| Installed profile | Fresh-consumer project SHA-256 | Results |
| --- | --- | --- |
| C++ cooperative checkpoints | `f1a15b88f9941b09c8a9501de9adb56c7113f75280df5c260e3194ccb913e58e` | Passed |
| Node-worker checkpoints | `67f0f0022cd834dfe09e2969cadca0d1dbf34fb276397268beb7f86b2f38854b` | Passed |
| Rust-thread checkpoints | `c573376c5ebab1f5a0c100da1308b8f099b35b7da5d32d9b736790f4f0dc76c1` | Passed |

Every profile ran actual match and mismatch, reduction, report/timeline, all
eight supplied-model catalog cases and all 40 SDK finite actor-chain cases.
The SDK explorer explicitly has no model comparison; the catalog compares
actual observations against supplied retained model traces. Mapping tamper,
unsupported profile and oracle tamper refuse before acquisition; bounded-search
and deliberately failing teardown controls preserve incomplete/failure scope.
Installer tests also preserve occupied destinations and reject inventory/mode
changes. Host tamper and actual process timeout/output controls pass in the
focused Python suite. Supplemental installed runtime tamper controls modify each
application runner artifact, confirm admission refusal and restore the exact
original bytes; these three additional checks ran in the ordinary tool sandbox.
[Their commands/results](installed/runtime-tamper-controls.json) are retained.

The installed C++ controlled-resource example independently checks actual
`count = 2` and FIFO `received = [10,20]`, with confirmed joins. Its receipt has
`modelComparison: false`. Supplemental installed CLI rendering preserves that
receipt's meaning; this extra resource-report rendering ran in the ordinary
tool sandbox. The standard report commands for all three checkpoint profiles
ran inside the isolated installed gate.

## Regression results and discovered lifecycle bug

| Validation | Result |
| --- | --- |
| `LEAN_NUM_THREADS=2 lake build` | Passed, 722 jobs |
| Lean DPM pure policy | 8 gates passed |
| DPM Python/compiler/timeline/installation suite | 34 tests passed |
| Full `tools/run-local-no-model-check.sh` | All local non-model gates green; live Counter/async tiers explicitly skipped |
| Existing C++ scheduling/binding/exploration | 35 cases, 752 assertions passed |
| New C++ controlled synchronization | 11 cases, 179 assertions passed |
| ECMA scheduling/binding/exploration | 23 tests passed |
| Source-hidden offline fresh consumers | C++, ECMA and Rust passed |

Logs are under [logs](logs/) and [installed/logs](installed/logs/);
[toolchains.json](toolchains.json) records the actual compiler/runtime versions.
C++ SDK unit suites used Debug with warnings as errors. The initial Release unit
build hit GCC's `maybe-uninitialized` warning in the unchanged
`examples/scheduled_counter.hpp` fixture; this is not reported as a passing
Release unit build. Fresh installed C++ consumers did compile in Release with
warnings as errors.

The first installed ECMA run exposed a completion race: a worker could exit
before the controller delivered its terminal message from the separate private
MessagePort. Closing that port at exit could discard the notification. A focused
delivery-delay reproduction failed 10/10 before the fix and passed 10/10 after
it. MirrorECMA now acknowledges completion before the worker releases the
bootstrap channel reference. The controller still waits for real exit, and
late-hook, timeout and cleanup semantics remain covered by the 23-test suite.
Before/after diagnostics are retained under [diagnostic](diagnostic/).

## Qualification limits

Exact October 5 remote oracle captures are reused byte-for-byte and validated
through model/source/request/reply/corpus hashes and explicit correspondence.
This campaign did not contact the expired historical service credentials,
generate new model traces, or start local Apalache/TLC.

F5 is a C++ participating-thread prototype outside the proof boundary. Its
controlled ownership/FIFO operations coordinate real threads through the
coordinator's synchronization; it does not wrap arbitrary native locks or
unmodified binaries. Local completion, independent semantic mutation tests and
finite enabled-prefix exploration do not supply model conformance. Recursive/
timed/shared locks, condition variables, dynamic actors, Node/Rust resource
wrappers, general preemption, POR and weak-memory completeness remain outside
the profile. Uncooperative callbacks can delay destruction indefinitely; hard
termination belongs to an external process owner.

This is current WSL2/Linux installed acceptance with explicit runtimes, not
native Ubuntu/Windows/macOS platform acceptance or a new full M5 qualification.
Broader M4, package publication and production deployment remain separate.
Historical checkpoint/evidence bytes and unrelated editor caches/ECMA `.work/`
remain preserved.
