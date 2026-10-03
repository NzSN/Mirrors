# Compiler and client follow-ups — 2026-10-03

Status: **complete for the declared compiler/client scope**. Source checks, the
five-base-profile/18-row aggregate and the additional C++ v2 shared-profile run
passed. The Mirrors/MirrorECMA changes are now included in the fresh framework
M5 candidate in [the qualification report](q3-post-m6-2026-10-03.md). The generated
client matrix retains its separate scope from M5's pinned compatibility matrix.

## Delivered behavior

- `mirrorlean-v1` emits typed, fallible Lean ports, codecs and mechanical
  bindings. MirrorLean supplies strict negotiated admission, an exact binding
  registry, deferred construction and classified replay/cleanup errors while
  preserving its legacy client API. See [the target contract](../Docs/model-interface-compiler/lean-target.md).
- The pure Core conformance implementation and six shared fixture families
  exercise generated synchronous/async TypeScript, C++, Rust and Lean bindings.
  The consumers compare actual SDK `report_state` payloads as well as recording
  events. Codec repairs preserve ordinary records with marker-looking keys;
  typed sets reject duplicate equivalent elements before application effects.
- Generated Rust and Lean acceptance covers supplied-trace stdio success,
  actual mismatch, digest denial and plain-TCP authority denial, plus
  fresh owned-Windows mTLS success, mismatch, digest denial, principal denial
  and pin denial. Factories remain deferred until admission; acquired bindings
  are disposed once. Source trees are hidden during runtime acceptance.
- Architecture references and historical roadmap headers now distinguish
  implemented compiler targets, current bounded acceptance and older checkpoint
  states. Historical qualification reports and their identities are preserved.

## Validation

- Mirrors local non-model suite passed, including the new language and Lean
  executable gates and the existing C++ v2 checks.
- MirrorECMA full type checking and Jest passed: 643 tests, with 13 optional
  skips. The later shared frame-encoder change passed 138 focused protocol and
  synchronous/async replay tests plus type checking.
- MirrorLean: 136 focused model-interface checks, 118 legacy checks and async
  checks passed; generated native examples compile and execute, and malformed
  typed observations fail compilation.
- MirrorRust protocol tests passed (36). MirrorCPP value tests passed (198
  assertions in 38 cases).
- Core shared fixtures cover 23 types, 54 values, 15 equivalence cases, 12 paths
  and four resource bounds. Native consumers pass 99 TypeScript, 99 async
  TypeScript and 96 each C++ v1, C++ v2, Rust and Lean cases. All six profiles agree on 15 common
  recordings and 16 SDK report frames. Canonical frame JSONL SHA-256 is
  `503df8c3f7f15417f788d1cde8e669bf8e5b40319b899b770b7a55aad9fa4272`.
- All Counter target outputs were regenerated through the compiler and passed
  read-only checks. The Lean consumer also builds outside the repository using
  its explicit `leanprover/lean4:v4.33.0` pin.

The combined entry point is `tools/interop/run.sh --generated-clients`;
[INTEROP.md](../tools/interop/INTEROP.md) records its arguments and boundaries.
Its default shared gate now requires all six profiles. The retained acceptance
was collected as the five-base-profile aggregate followed by the C++ v2
supplement; the supplemental run preserves the fixture and canonical frame
hashes above and is explicitly marked as a subset.

| Retained receipt | SHA-256 |
| --- | --- |
| `/tmp/generated-clients-final-20261003/receipt.json` (five base profiles and 18 transport rows) | `fcc03960006c509e79bdbc0a40cb30f64a1342a597f19cda9237401096f87499` |
| `/tmp/shared-cpp-v2-20261003/receipt.json` (C++ v2 supplement) | `d212c1f7986db6a8d5d53e89ff2e18219e57dcf9b054e6f990b34eda9947b264` |

All transport rows use verified prepared build closures and source hiding.
The Lean build was refreshed after the acceptance harness changed; the earlier
prepared build correctly failed its harness-hash check before executing a row.
Receipt classifiers reject unknown fields and validate rows before retention.
Shared verifier controls also pass under optimized Python.

## Acceptance boundaries

These changes do not inherit the earlier M5 qualification. The generated
transport profile has 18 declared Rust/Lean rows and is distinct from the
legacy all-client/all-transport matrix. Runtime acceptance uses copied build
closures and source hiding; it is not a package release qualification. Local
Apalache and TLC are prohibited on this coordinator. Live model generation
uses the owned native Windows oracle, Apalache 0.62.2 with Java 25.0.4+7-LTS.

Publication commits are recorded in [CHECKPOINTS.md](../CHECKPOINTS.md).
Native Ubuntu, aggregate cgroups, active-process
recovery and Windows service-manager acceptance remain outside this work.
