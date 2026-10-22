# Mirrors ecosystem version and compatibility policy

This policy covers Mirrors, MirrorGate, MirrorECMA, MirrorCPP, MirrorRust,
and MirrorLean. MirrorRegistry, MirrorExamples, and ModelMirrors are outside
this release migration.

## Product contracts

Each repository owns its product version and compatibility promises. The
initial compatible client releases use `v0.1.0`; subsequent compatible fix
releases use their own `v0.1.x` patch sequences. Equal patch numbers across
repositories are not required. Compatibility with the selected server is
declared by an explicit manifest and scoped tests, not inferred from a number.

| Component | Public contract |
| --- | --- |
| Mirrors | CLI, JSONL behavior, model-interface compiler commands, and advertised generated interfaces |
| MirrorECMA | Exported TypeScript/JavaScript APIs, project CLI/configuration, reports, and generated-binding integration |
| MirrorCPP | C++ APIs, CMake package, and generated-binding integration; no general stable binary ABI promise |
| MirrorRust | Rust APIs, Cargo features, serialized public records, and generated-binding integration |
| MirrorLean | Lean declarations/modules, client behavior, and generated-binding integration |
| MirrorGate | Controller/worker protocols, SDK APIs, policy/configuration, lifecycle/isolation semantics, and recovery formats |

Versions use `MAJOR.MINOR.PATCH[-prerelease]`. After 1.0, a compatible fix
increments PATCH; compatible functionality or deprecation increments MINOR;
incompatible supported usage increments MAJOR. Higher components reset lower
components. Supported runtime/compiler/platform requirements are part of the
contract. A security fix is classified by its actual contract effect.

Before 1.0, PATCH contains compatible fixes; MINOR introduces features or
breaking changes, with migration notes for the latter. Version 1.0 declares a
maintained public contract for an explicit supported scope; it does not assert
that every roadmap feature or platform is complete.

Correcting an implementation to satisfy an unchanged conformance contract is
a fix. Changing the meaning of conformance, required fields, supported lifecycle
ordering, or accepted public interfaces is a compatibility change. Adding an
optional capability while preserving old contracts is compatible; removing a
supported capability is breaking.

## Baseline migration

At the user's explicit request, Mirrors `v0.1.0` identifies the unchanged commit
`ea8091c0c723f3f561044a5c1efb91d12e7aaf5f`, originally named `v0.0.3.3`.
Its executable still prints `v0.0.3.2`. This is a documented source-version
exception, not a rewritten executable or a claim that current main is 0.1.0.
The new release manifest and checksums identify the exact source and binaries.

Existing tag identities are retained in the dated migration inventory before
any authorized removal. Historical evidence keeps its original labels and
commit identities. This requested reset is a one-time migration; subsequent
released tags are immutable and corrections require a new release.

For subsequent ordinary releases, the product manifest, executable version
(when available), and Git tag must agree. Package-registry publication is a
separate action; this migration creates Git source release identities.

## Compatibility and exact identity

Product versions, wire/schema versions, generated target profiles, model-author
interface versions, semantic digests, artifact hashes, and qualification records
are independent. A product bump does not silently change a frozen protocol.
Adding a new protocol alongside the old one can be compatible; dropping the old
one is breaking. Exact semantic-digest selection is still required.

A compatibility record binds the server commit, each component commit, tool
versions, tested profiles, commands/results, and evidence hashes. It must say
which operations and transports were exercised and which were unavailable.
Codec tests, actual supplied-trace replay, generated-source compilation,
Gate isolation, and live model operations are distinct claims.

The 0.1 baseline compiler advertises `mirrorecma-v1`, `mirrorecma-async-v1`,
`mirrorcpp-v1`, `mirrorcpp-v2`, and `mirrorrust-v1`. It does not emit
`mirrorlean-v1` or the later async-ECMA/Rust v2 targets. A Lean JSONL client may
interoperate with the server without receiving a compiler-target claim. Gate
has Node/C++/Rust evaluator SDKs and Node/Rust workers; this does not establish
a Lean Gate SDK or C++/Lean worker support.

Release tags identify only the scopes actually validated in the corresponding
compatibility record. Local/hosted non-model success does not inherit the
separate frozen framework, live model, recovery, or platform qualification.
