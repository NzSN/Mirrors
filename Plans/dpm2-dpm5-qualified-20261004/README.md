# DPM-2 through DPM-5 acceptance — approved completion, 2026-10-04

**Accepted for the declared profiles.** This record closes the fresh-oracle and
native acceptance gaps in the earlier
[partial local record](../dpm2-dpm5-evidence-20261004/README.md). The user explicitly
approved selected model/trace transfers to the existing Windows oracle and native
source staging under `C:\Users\ayden\Desktop\Workspace\MirrorsRemote`.

[Detailed plan](../deterministic-production-mbt-dpm2-dpm5.md) ·
[Native pilot and exclusions](../deterministic-production-mbt-dpm3-pilot.md) ·
[Acceptance manifest](acceptance.json) ·
[Capability observation](capability-observation.json)

| Stage | Exercised acceptance |
| --- | --- |
| DPM-2 | Four fresh counter captures: serial/overlap at initial inputs 0/5; all 15 replay controls for each capture pass, 60 total. Actual state comparison, mutation mismatch, generated codecs, ownership and cleanup remain enforced. |
| DPM-3 | Four fixed native schedules, each replayed twice in fresh Windows processes; all eight match independent model traces. Two production mutants produce real `step_mismatch`. Actual phase divergence, paused cancellation, native image refusal and guarded owned-child termination are classified. Three incompatible mappings reject before native acquisition. |
| DPM-4 | All 20 interleavings over two declared inputs execute: 40 acquisitions, 80 workers, 40 teardowns. Independent schedule and semantic coverage accounting plus 11 acceptance cases pass. This is finite local execution coverage, not a model comparison of every interleaving. |
| DPM-5 | Fresh installed SDK/consumer build and runtime gates pass with source checkouts hidden and networking isolated. The installed native controller passes 14 native runs and three pre-acquisition refusal controls. The static experimental API declaration is linked to a separate scoped qualification observation. |

The unchanged SDK runtime retains its 220/220 unit result from the local gate;
that log and source hashes are included here. Both counter and fresh native
generated outputs pass `model_interface_gen check`. The installed portable gate
also passes 15 replay cases, 11 exploration cases and four artifact/profile
controls. Historical source records are preserved; no commit or push was made.

## Independent model evidence

All model checking ran through the Mirrors CLI against the existing pinned mTLS
endpoint `172.20.208.1:8999`. Before/after observations identify the same process
2572 and server binary SHA-256
`5949af30735cd1bf515e64fb9d2299023e13b2c36245ce9be696d65944b32dec`, with
Apalache 0.62.2 and Java 25.0.4+7. The server was not restarted or reconfigured.

Counter serial final values are 2 and 7; overlap final values are 1 and 6.
The bound-6 counter `Safety` check from `Init` returned `VALID`. The native
wrapper captures use the unchanged canonical model actions and frozen input
plans. Separate `MBTSafety` checks returned `VALID` for stable-t1/stable-t2 at
bound 28 and overlap-t1/overlap-t2 at bound 17. These model results cover exactly
the selected fixed schedules. Native probe states were diagnostic and never
supplied as expected states or used to initialize the SUT.

Each capture directory retains the request, source closure, replies, original ITF
files and capture hashes. When the backend returned duplicate ITF files, both
were retained; they do not count as extra scenarios. Replay uses the selected
`trace-0.itf.json` artifact. The deliberately modified phase-refusal trace is a
negative control and earns no oracle credit.

## Native execution and installed evidence

Selected production files were frozen from the existing WriteSentry working tree
at base revision `62b62298c5c764dc63cde10968c2555a79df1d3c`; selected-file hashes
identify the actual dirty-source inputs. No WriteSentry source was edited here.
Normal and mutation builds reside under the owned `dpm-20261004` Windows root.
Build receipts, commands, compiler/tool identities, dependency-header hashes and
binary hashes bind the native artifacts. The host/tool observation is post-build;
it is not a hermetic toolchain attestation.

The installed controller uses generated typed callbacks to release proxy actors;
actual Windows threads preserve their stacks at the existing atomic phase gates.
The native worker reports its actual phase and process/thread identities. The
portable mutex/condition-variable hook never enters the trap path. Logical
operation roles and physical native thread identities remain separate.

`duplicate-sink-call` and `skip-hit-release` change staged production `veh.cpp`.
Both produce actual model comparison failures and then confirmed native cleanup.
Cancellation and unexpected-phase controls also clean up normally. The terminated
peer instead retains primary failure plus `teardown_failed`/no Quit acknowledgement;
its exact image and creation time are checked before termination. This expected
failure is not rewritten as successful cleanup. Final host observation finds zero
remaining processes beneath the owned native test root.

`installed-build-acceptance.json` identifies the source-hidden fresh consumer
build. `installed-native-acceptance.json` binds its exact controller binary to the
second source-hidden runtime gate and all 14 native run receipts. The latter
uses WSL's existing local Windows process carrier; no model service or network
connection is used by the replay gate. Namespace isolation applies to the Linux
controller; Bubblewrap does not sandbox the Windows worker processes. Native workers start from their owned
Windows build directory. Source/binary/manifests are checked independently of
exit codes.

## Issues found and resolved during fresh acceptance

- Added missing Apalache type annotations to the counter model.
- Replaced overlapping `CASE` guards with explicit ordered `IF/ELSE`, after the
  captured nominal overlap trace exposed a serial execution.
- Added the native wrapper's missing `<fstream>` include and explicit Windows
  build/runtime working directories.
- Regenerated a campaign-local native lock from raw fresh ITF. The previous lock
  had `itfParamVars=["parameters"]`; raw captures have no such field, so the new
  lock uses `itfParamVars=[]` while configured/effective parameters remain
  `parameters`. Negotiation correctly refused the old digest. The observation
  contract is unchanged, and WriteSentry's existing lock was preserved.

The prior SIGPIPE transport fix and its red/green regression remain recorded in
[the earlier local evidence](../dpm2-dpm5-evidence-20261004/README.md).

## Limits and retention

These are experimental cooperative scheduling and the four-case
`dpm-writesentry-two-operation/v1` pilot claims. They do not establish arbitrary
thread/instruction scheduling, weak-memory completeness, all WriteSentry behavior,
a Windows build of the entire MirrorCPP SDK, a Windows Gate backend, a native
Ubuntu isolation result or a new M5 candidate. Partial-order reduction remains
disabled. Existing unrelated production/performance qualification is unchanged.

Retained files contain observations and source/artifact identities. Scratch SDK
prefixes/Linux executables remain in `/tmp`; frozen native inputs/builds remain
under the owned Windows root. This directory is an acceptance record, not a
self-contained release archive or an external package publication.
