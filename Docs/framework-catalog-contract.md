# Framework catalog contract

Status: C2/E1 identity seam reviewed for local C3 implementation, 2026-09-22.
E1 validator acceptance and later catalog migration remain separate gates.

This contract defines the strict, versioned catalog that describes framework
components, declared capabilities, observed acceptance dimensions and exact
component combinations. It does not replace wire negotiation, Gate admission,
or run evidence. The fact-owner inventory is
[framework-catalog-inventory.md](framework-catalog-inventory.md); E1 owns the
referenced evidence envelope in
[durable-evidence-design.md](durable-evidence-design.md).

## Ownership boundary

| Data | Owner |
| --- | --- |
| Capability declarations, source locations, component revisions, platform constraints, distribution profiles and selected combinations | This catalog contract (C2), populated from component-owned records |
| Run identity, observed component/dirty-tree identity, artifact identity, outcomes, completeness, cleanup and retention | Durable evidence contract (E1) |
| Model/interface semantic and provenance digests | Mirrors model-interface contract and generated lock |
| Runtime wire compatibility | The negotiated protocol and exact interface match at runtime |
| Gate policy and live backend admission | MirrorGate and its operator |

A catalog can say that a combination was observed only by referencing finalized
E1 evidence. It never copies an outcome or cleanup result out of that envelope.
An evidence envelope records the catalog selection made before execution; it
does not claim a later catalog revision and does not contain its own digest.

## Version and document shape

The root is a closed JSON object with these fields:

| Field | Required | Meaning |
| --- | --- | --- |
| `schemaVersion` | yes | Exact string `mirrors.framework-catalog/v1` |
| `catalogId` | yes | Stable logical identifier |
| `visibility` | yes | `public` or `private`; controls admissible dirty-tree identity |
| `components` | yes | Component records keyed by unique `componentRef.componentId` |
| `evidenceRefs` | yes | Named, finalized E1 `runRef` values |
| `capabilities` | yes | Unique capability declarations and independent observations |
| `distributionProfiles` | yes | Install/runtime profiles and their platform/dependency classes |
| `combinations` | yes | Exact component selections and supported/candidate platform profiles |
| `extensions` | no | Namespaced inert data as described below |

Unknown fields are rejected at every contract-owned level. Unknown schema
versions, including another major, fail closed. Version 1 has no implicit minor
upgrade rule: a shape change requires a new explicit schema string and adapter.
The optional `extensions` object is the only additive seam. Each key must be a
reverse-DNS name and its value is inert JSON; required behavior may not depend on
an extension that a consumer does not understand.

The decoder rejects duplicate JSON object keys before materializing a value,
duplicate logical identities in arrays, invalid UTF-8, non-integer JSON numbers,
integers outside `[-9007199254740991, 9007199254740991]`, and nesting deeper than 32. A catalog
is at most 4 MiB; strings are at most 64 KiB; identifiers and paths are at most
256 and 4096 UTF-8 bytes respectively. Shared `componentRef.dirtyContent` paths
use E1's tighter 1024-byte limit. Limits are: 64 components, 4096 evidence
refs, 4096 capabilities, 256 profiles, 1024 combinations, 256 source locations
per capability, and 256 component/capability selections per combination.

## Shared identity vocabulary

These types are byte-for-byte compatible with E1.

### `componentRef`

```json
{
  "componentId": "mirrors",
  "repository": "https://github.com/NzSN/Mirrors.git",
  "revision": "e7c8681d7db62000555675188d0125931136e002",
  "dirty": false
}
```

`revision` is exactly 40 lowercase hexadecimal characters. If and only if
`dirty` is true, `dirtyContent` is required:

```json
{
  "algorithm": "sha256",
  "digest": "64-lowercase-hex-characters",
  "method": "git-diff-and-untracked-manifest-v1",
  "includedPaths": ["logical/path"],
  "excludedPaths": [
    {"path": ".work", "reasonCode": "pre-existing-unrelated"}
  ]
}
```

The other permitted method is `filesystem-tree-v1`; exclusion reasons are
`pre-existing-unrelated`, `evidence-output`, or `build-output`. Paths are logical
repository paths, never host absolute paths. Lists are sorted and duplicate-free.
`includedPaths` may be empty when every observed dirty path is explicitly listed
as excluded; the digest/method still bind the selected content.
Because dirty manifests can reveal non-public logical filenames, a `public`
catalog rejects every component with `dirty: true`. Dirty components may appear
only in a `private` catalog whose storage and access follow E1 private-evidence
rules. A future public dirty-tree projection requires a separate reviewed schema;
version 1 never silently removes paths from the shared `componentRef` shape.

### `catalogSelectionRef`

```json
{
  "schemaVersion": "mirrors.framework-catalog/v1",
  "selectionKind": "sha256",
  "selectionValue": "64-lowercase-hex-characters"
}
```

`sha256` identifies the `mirrors-framework-canonical-json/v1` bytes of the entire
parsed catalog. The catalog contains no self-digest. `git-revision` is also permitted
with a 40-hex value and selects the fixed
`catalog/framework-catalog.json` path in the Mirrors repository at that clean
commit. Portable distributions use `sha256`; dirty catalog content cannot use
`git-revision`.

### `runRef`

```json
{
  "schemaVersion": "mirrors.evidence-envelope/v1.0",
  "runId": "01J00000000000000000000000",
  "envelopeSha256": "64-lowercase-hex-characters",
  "projectionKind": "private"
}
```

The other schema/projection pair is
`mirrors.evidence-public-summary/v1.0` with `public`. A `runRef` identifies an
already finalized envelope or projection. The catalog stores it in a unique
`evidenceRefs` record `{evidenceId, runRef}`. Capabilities and combinations cite
the local `evidenceId`, allowing missing references and duplicate aliases to fail
deterministically. The offline catalog validator checks shape and reference
integrity; E3/E4 verifies retained bytes and the envelope hash.

A `public` catalog accepts only the public-summary/public pair; it rejects a
private envelope reference. Its `componentRef.repository` must be a normalized
HTTPS repository URI and cannot be a `file:` URI, host absolute path, or private
locator. A `private` catalog may reference either evidence projection, but host
absolute repository locators remain invalid because they are not stable identity.

E1's `artifactRef` and `producerResultRef` remain inside evidence. They are not
redefined or flattened into catalog records.

## Component records

Each component record is closed:

```json
{
  "componentRef": {"componentId": "mirrors", "repository": "...", "revision": "...", "dirty": false},
  "product": {"name": "Mirrors", "version": "0.0.2"},
  "records": [
    {"recordId": "compiler-source", "path": "Shell/ModelInterface/Compiler.lean", "recordKind": "source"}
  ]
}
```

`product.version` is a declaration from the selected source and does not imply a
tag or publication. `records` identify the component-owned inputs an adapter
used. `recordKind` is `source`, `manifest`, `pins`, `protocol`, or `ledger`.

## Capabilities and evidence states

Each capability has a globally unique `capabilityId`, one `ownerComponentId`, a
human-readable description, a declaration, source implementation, and five
later observation dimensions:

```json
{
  "capabilityId": "mirrors.compiler.target.mirrorrust-v1",
  "ownerComponentId": "mirrors",
  "description": "Generate a Rust model-interface port",
  "declaration": {
    "state": "experimental",
    "constraints": [
      {"constraintId": "linux-x64", "fact": {"kind": "platformField", "id": "architecture"}, "operator": "equals", "values": ["x86_64"]}
    ]
  },
  "sourceImplementation": {
    "state": "present",
    "locations": [{"path": "Shell/ModelInterface/Emit/Rust.lean", "symbol": "emit"}]
  },
  "observations": {
    "sourceTested": {"state": "accepted", "evidenceId": "run-rust-golden"},
    "locallyAccepted": {"state": "unknown"},
    "installedConsumerAccepted": {"state": "unknown"},
    "hostedCiAccepted": {"state": "unknown"},
    "published": {"state": "unknown"}
  }
}
```

Declaration state is `available`, `experimental`, or `unavailable` and may list
sorted structured constraints. A constraint has unique `constraintId`, a `fact`,
an operator, and sorted values. Version 1 fact kinds are `platformField`
(`os`, `osRelease`, `architecture`, or `backend`), `componentVersion`
(component ID), `dependencyVersion` (dependency ID), and `capabilitySelected`
(capability ID). Operators are `equals`, `oneOf`, and `atLeastSemver`; `equals`
has exactly one value and `atLeastSemver` has one version-1 core SemVer value:
exactly `MAJOR.MINOR.PATCH`, decimal with no leading zero except zero itself.
Prerelease/build forms require a later contract version. Every fact must
resolve in a combination/profile context. Constraints over the same fact whose
allowed values cannot intersect are contradictory; the validator never compares
unstructured prose to decide compatibility. Source implementation state is `present`, `absent`, or
`unknown`; `present` requires at least one live source location at the owner's
selected revision and is not E1 execution evidence.

Each observation state is independently `accepted`, `rejected`, `unavailable`,
`notRun`, or `unknown`. `accepted` and `rejected` require `evidenceId`.
`unavailable` may carry one when a run observed environmental unavailability.
`notRun` and `unknown` must not carry one. No state implies another: publication
does not prove testing, source tests do not prove installation, and hosted CI
does not prove a local backend. A source-only feature therefore has
`sourceImplementation.state: present` and later dimensions `unknown`/`notRun`;
it cannot be labeled published without finalized publication evidence.

## Distribution profiles and combinations

A distribution profile has a unique `profileId`, exact platform object,
required/optional capability IDs and dependencies. Platform fields are closed:
`os`, `osRelease`, `architecture`, and optional `backend`. Version 1 recognizes
`linux`, `ubuntu-24.04`, `x86_64`, and the selected backends `local-process` and
`linux-bubblewrap-v1`. Other well-formed concrete values may be declared for
future profiles, but require their own reviewed record and evidence; matching is
always exact and never uses a wildcard.

Each profile also has `requiredObservationDimensions`, a duplicate-free subset
of `sourceTested`, `locallyAccepted`, `installedConsumerAccepted`,
`hostedCiAccepted`, and `published`. This is the evidence policy for rendering a
combination as `supported`; Gate profiles normally require an actual local or
installed backend dimension, while a source-only catalog can remain `candidate`.
For a `supported` version-1 combination, a `local-process` profile must include
`installedConsumerAccepted`; a `linux-bubblewrap-v1` profile must include both
`installedConsumerAccepted` and `locallyAccepted`. A profile may use an empty
policy only while every referencing combination remains `candidate` or
`unsupported`.

Dependency entries contain `dependencyId`, optional exact `version`, and one class:
`bundled-artifact`, `content-addressed-runtime-tree`, or
`operator-host-prerequisite`. They are declarations only. I2 binds bundled and
runtime dependencies to E1 artifact identities in an installation manifest;
private policy, credentials and kernel state remain operator prerequisites.

A combination contains:

- unique `combinationId`;
- duplicate-free `componentIds`; each resolves to the unique root
  `componentRef`, including revision and any dirty-content digest;
- a platform exactly equal to its distribution profile platform;
- duplicate-free capability and distribution-profile IDs;
- `declaredState` of `candidate`, `supported`, or `unsupported`;
- optional evidence IDs for observations of that exact combination.

`supported` is invalid if a required capability is absent, declared unavailable,
owned by an unselected component, platform-incompatible, violates a structured
constraint, or lacks `accepted` evidence in every profile-required observation
dimension. Candidate declarations may retain unknown/not-run observations.
Contradictory component revisions cannot be expressed through a combination: a
component ID resolves to exactly one root `componentRef`, and duplicate root IDs
are rejected. Runtime negotiation
may still reject a catalog-supported combination. The catalog cannot authorize
an incompatible interface or bypass Gate policy.

## Contradictions and error contract

Validation reports all independent errors in stable path/code order. Each error
has `{code, path, message}`. Required version-1 codes include:

| Code | Condition |
| --- | --- |
| `E-FCAT-SCHEMA-001` | Unsupported schema version or unknown field |
| `E-FCAT-IDENTITY-001` | Missing/malformed revision, digest or identity |
| `E-FCAT-DUPLICATE-001` | Duplicate JSON key or logical identity |
| `E-FCAT-REFERENCE-001` | Missing or malformed component/capability/profile/evidence reference |
| `E-FCAT-CONTRADICTION-001` | Records disagree for the same owner/scope/selection |
| `E-FCAT-STATE-001` | Invalid declaration or observation transition/shape |
| `E-FCAT-STATE-003` | Later support/publication state asserted without required evidence |
| `E-FCAT-PLATFORM-001` | Combination and profile platforms are incompatible |
| `E-FCAT-BOUND-001` | Size/count/depth/numeric bound exceeded |

The fixtures under `test/fixtures/framework-catalog/` freeze exact examples and
expected errors. Validation never executes a component, follows an external URI,
downloads evidence, imports an adapter, installs a package, or performs Gate
admission.

## Adapter and governance rules

Mirrors owns the selected central catalog and deterministic renderer. Each
component owns its capability facts:

- Mirrors adapter reads compiler source/targets and `tools/ci/versions.env` for
  the specific interop workflow.
- MirrorECMA adapter reads package/project/suite records and its workflow pins.
- MirrorGate adapter reads `sdk/compatibility.json`; explanatory prose cannot
  override that JSON record.

Adapters preserve producing repository, path and exact component revision. Two
records for the same fact scope that disagree produce
`E-FCAT-CONTRADICTION-001`; ordering never selects a winner. A pin in another
repository is a consumer constraint, not ownership of the component capability.

Generated JSON and Markdown use stable key/row ordering, LF newlines and one
terminal newline. Catalog canonical identity uses
`mirrors-framework-canonical-json/v1`: null/booleans use JSON literals; integers
use shortest base-10 with no leading zero; arrays preserve order; object keys
sort by unsigned UTF-8 bytes; strings emit UTF-8 directly except JSON-required
escapes for quote, reverse solidus and U+0000-U+001F (lowercase `\u00xx`). No
floats, surrogate scalar values or Unicode normalization are accepted in the
data model. These escape restrictions govern canonical output; the strict input
decoder may accept an equivalent valid JSON escape before canonicalization. The
vectors in `canonicalization-vectors.json` freeze ordering and
escaping. This is deliberately not RFC 8785/JCS and can be implemented directly
with the repository's strict JSON decoder. C3 must render twice byte-identically
and reject manual drift.

## Handoff

C3 implements this closed validator and deterministic renderer. I2 consumes
profile/dependency declarations plus E1 artifact identities. E4 may attach
finalized `runRef` values without changing outcomes. G5 exports recovery/backend
capabilities through component-owned Gate input and evidence through E1. Any
change to the shared ref shapes requires joint C2/E1 review before freeze.
