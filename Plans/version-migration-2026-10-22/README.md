# 0.1 release-line migration and compatibility evidence

This record implements version semantics for Mirrors, MirrorGate, MirrorECMA,
MirrorCPP, MirrorRust, and MirrorLean. MirrorRegistry, MirrorExamples, and
ModelMirrors are excluded. The [policy](../../Docs/ecosystem-versioning.md)
defines component contracts, independent patch sequences and exact compatibility
identity. The initial compatible component tags are `v0.1.0`.

## Exact server baseline

Mirrors `v0.1.0` points to unchanged commit
`ea8091c0c723f3f561044a5c1efb91d12e7aaf5f`, originally `v0.0.3.3`.
The executable still prints `v0.0.3.2`. The release builder accepts this single
normal-SemVer alias only at its exact commit and expected embedded version.
No server source, generated fixture or executable version bytes were rewritten.

## Validated component source targets

The exact component commits and review links are in
[compatibility.json](compatibility.json). They contain aligned product metadata,
version policy, compatibility manifests and required build/CI setup corrections.
Tag publication and retired-ref observations are recorded separately in
`publication.json` after completion; a source target is not itself a claim that
a tag was published.

## Executed compatibility gates

- All four actual SDKs passed supplied-trace match/mismatch over stdio, TCP and
  TLS 1.3 mutual authentication, plus wrong-pin zero-callback controls: **28 rows**.
- Actual C++ and Rust evaluators composed with owned/attached Gate controllers
  and Node/Rust workers passed match, real mismatch, and wrong-digest
  zero-acquisition cases with confirmed cleanup: **24 rows**.
- The Gate-owned ECMA suite packed the three packages, relocated them, hid all
  source checkouts, disabled networking and ran twice. Correct/faulty/crash/hang/
  disposal-failure, coverage, negotiation, cancellation and persistence controls
  retained their expected distinct outcomes.
- Gate `scripts/test.sh` passed with required real Bubblewrap isolation, Node
  and Rust conformance/lifecycle tests, C++ control/hosting tests and Rust
  formatting/Clippy/package checks. Its Python gate ran 297 tests with three
  explicit delegated-cgroup skips; Node gates passed 231 tests.
- ECMA passed 717 unit tests with four skips against the baseline fixture setup.
  Its complete focused non-model gate passed with the separately pinned current
  development compiler; that gate reported 708 tests with 13 explicit skips.
- C++ passed all 291 non-model unit/golden/protocol-fixture CTest rows.
- Rust unit/golden/model-interface/protocol/transport tests passed. Existing
  live-model smoke executables self-skip when their prerequisite is absent;
  their zero exit alone is not live evidence. The 28-row actual SDK matrix
  supplies the real baseline replay/transport evidence.
- Lean passed 125 root tests, async and model-interface suites, and native TLS
  loopback regressions. Its actual supplied-trace rows include mTLS.
- Release tooling tests, actionlint, shell syntax and `git diff --check` passed.

## Evidence and identity

[compatibility.json](compatibility.json) binds exact targets and evidence hashes.
[Transport rows and source snapshots](evidence/transport-compatibility.json)
bind actual SDK bytes and server identity. [Gate composition rows](evidence/gate-composition.json)
bind actual evaluator binaries and source inputs. [Successful validation logs](evidence/validation-logs.tar.gz)
retain 20 complete command logs; the summary records each uncompressed log hash.

The server/compiler binaries were downloaded from the already-published original
baseline release and verified against release-asset and binary checksums.
Node 24.15.0, pnpm 11.22.0, Lean 4.33.0 and Rust 1.96.0 were selected explicitly.
The local host used GCC 15.2, CMake 4.2.3, OpenSSL 3.5.5 and Python 3.14.4.
Native Lean TLS now selects GNU17 so GCC15 does not select the C23 strtol symbol
absent from Lean bundled linker libraries. Native tests pass with that fix.

Cold hosted checks exposed setup defects: ECMA tested before building its paired
tools; Lean invoked elan before its PATH update took effect; the Ubuntu Gate
runner denied Bubblewrap namespace setup. The candidate changes fix tool/build
ordering and provide application-specific CI namespace admission, retaining all
required real isolation checks. Hosted outcomes are reported separately from
the completed local evidence.

## Separate compiler and qualification scopes

The baseline compiler has no Lean emitter or later async-ECMA/Rust v2 emitters.
Current ECMA generated fixture bytes require the separately pinned published
development compiler `545ed2166c5817eb7cbec3bc1ec5b1b2f7051b6f`; no frozen
generated fixture was weakened to make the older compiler appear byte-fresh.
Server runtime compatibility and compiler freshness are recorded independently.

No local Apalache or TLC was launched. Live model operations, full framework
qualification, native Windows/macOS, real delegated aggregate cgroups and new
production isolation profiles are not credited. Lean has no Gate evaluator SDK;
C++/Lean workers are not implied by these tags.

## Retired tag preservation

[inventory.json](inventory.json) preserves original tag targets, exact annotated
tag object bytes and SHA-256 identities of local recovery bundles. The bundles
remain under `.golden-build/version-0.1/tag-backups/`.

Tag removal is limited to the six original Mirrors refs unless the user selects
broader removal for the other five repositories. New `v0.1.0` refs are never
part of the retired-ref set. Existing evidence/checkpoint files retain their
recorded labels and source identities. Package registries are not published,
reset, or overwritten by this migration.
