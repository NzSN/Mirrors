# Durable evidence contract

Status: **E1 accepted for the selected local implementation**, 2026-09-22. The
shared C2/E1 reference seam, envelope, public projection, fixtures, and validator
were reviewed under B2. No fixture in this directory is execution evidence.

This contract carries evidence produced by existing Mirrors, MirrorECMA, and
MirrorGate commands without redefining their result semantics. It keeps the
behavioral result, cleanup observations, and persistence result independent.
Qualification is derived from all required observations; it never rewrites one
axis to hide a failure on another.

The implementation baseline is [the B1 snapshot](../Plans/implementation-baseline.md).
At that snapshot Mirrors was
`e7c8681d7db62000555675188d0125931136e002`, MirrorGate was
`173075d318e4be926570a1378fc0aa36a1294f89`, and MirrorECMA was
`87ff8ca1555e2e35dd9a4664fc94aaa46d8f3dc2` with a pre-existing untracked
`.work/`. These are source inputs, not transferred test results.

## Ownership and reference vocabulary

[The framework catalog contract](framework-catalog-contract.md) owns component
and capability declarations, supported combinations, source/install/hosted/
published states, and catalog canonicalization. E1 owns observations from one
run: selected catalog identity, actual component state, commands, environment,
artifacts, outcomes, completeness, and retention.

The shared records are:

- `catalogSelectionRef`: `{schemaVersion, selectionKind, selectionValue}`. Version
  1 accepts the exact catalog schema `mirrors.framework-catalog/v1`. A SHA-256
  value identifies the catalog's `mirrors-framework-canonical-json/v1` bytes; a
  40-hex Git revision selects the catalog path at a clean commit. E1 validates
  syntax and treats the selected identity as an immutable pre-run input.
- `componentRef`: `{componentId, repository, revision, dirty, dirtyContent?}`.
  `revision` is a full 40-hex commit. Dirty content requires an independent
  SHA-256 digest, capture method, included logical paths, and explicitly excluded
  logical paths with reasons. A HEAD-only dirty identity is invalid.
- `artifactRef`: `{artifactId, mediaType, role, bytes, sha256, visibility,
  requirement, location}`. The byte hash is the identity; a bundle path or
  immutable external locator only locates it. Public v1 permits reviewed
  `artifacts/public/` bundle paths, not arbitrary external locators.
- `producerResultRef`: `{producer, schemaVersion, artifactId}`. It names a
  producer-owned result without flattening or interpreting that result.
- `runRef`: `{schemaVersion, runId, envelopeSha256, projectionKind}`. The schema
  and projection pair is strict: private envelope/private or public summary/public.
  A catalog or evidence store creates this reference after finalization.

An envelope contains `runId` but never its own digest or `runRef`. A run selects
the catalog before execution. A later catalog may cite the finalized run; the
old run does not claim that later catalog revision. These asymmetric links avoid
self-reference and catalog/evidence digest cycles.

Version 1.0 objects are closed. Unknown major or minor versions fail closed.
There is no guessed additive-minor policy; a changed shape needs an explicit
schema and adapter. IDs are local opaque values and must be unique in their
scope.

## Dirty source identity

The dirty digest covers the capture method's selected source content, including
selected untracked files. `includedPaths` may be empty when every observed dirty
path is deliberately excluded, as with MirrorECMA's pre-existing unrelated
`.work/`. Each exclusion records a logical path and one of
`pre-existing-unrelated`, `evidence-output`, or `build-output`. Evidence output
uses a store outside the checkout by default, but a collector still records any
checkout-local output exclusion. It must not silently exclude a changed source
file merely because collection created or noticed it. E2 will capture before and
after identities; a changing checkout makes evidence incomplete.

Logical paths use `/`, contain no absolute/drive prefix, backslash, control
character, empty component, `.` component, or `..` component. Private envelopes
retain the reviewed path manifest. Public summaries expose only dirty digest and
capture method, and only after an explicit public projector approves the
repository locator. C2 version 1 is stricter and permits only clean component
references in a public catalog.

## Time, commands, and environment

`startedAtUtc` and `finishedAtUtc` are display/correlation timestamps in UTC with
an uppercase `Z`. They do not measure timeouts. `monotonicDurationNs` measures
elapsed execution and is never reconstructed from wall-clock subtraction.

Private commands retain exact argv, working directory, stable `commandId`, tier,
requirement, and a discriminated exit: `{kind: code, code}`, `{kind: signal,
signal}`, or `{kind: not-started}`. E2 preserves the child's exit or signal; an
evidence write failure is recorded on persistence instead. The public projector
copies only the command ID and command-registry-approved stable argument IDs.
It never redacts and republishes arbitrary argv.

Private environment data may contain working directory and kernel details.
Public environment data is limited to reviewed platform profile, OS,
architecture, and tool identities. Platform observations describe the actual
run and do not promote a catalog capability or establish native-host acceptance.

## Independent outcome axes

The private envelope and public summary both contain all three axes:

| Axis | States | Rule |
| --- | --- | --- |
| Behavior | `passed`, `failed`, `inconclusive`, `not_run` plus namespaced producer classification | Preserve the producer's native result and primary failure. Cleanup or storage cannot rewrite it. |
| Cleanup | Per-scope `confirmed`, `failed`, `unconfirmed`, `not_applicable` | Scopes are `local-cooperative`, `gate-physical`, and `gate-recovery`. Required confirmed cleanup cites a retained receipt. Local disposal never proves physical cleanup. |
| Persistence | `complete`, `incomplete`, `failed`, `not_requested` with required/optional policy | Complete means every required payload exists and the no-overwrite final index was atomically published and verified. No artifact is truncated and called complete. |

Gate recovery support is a C2 capability. A recovery attempt is an E1
observation. Gate session, boot, ownership, cgroup, control-handle, and private
path details stay inside private producer artifacts; the public view contains
only approved scope/outcome and public receipt identity.

Each tier is independently required or optional and records `passed`, `failed`,
`skipped`, `unavailable`, `blocked`, or `not_run`. A required non-pass prevents
`qualified`; an optional skip remains visible. Qualification values are
`qualified`, `not_qualified`, or `incomplete` with stable reason codes.

## Finalization topology and release profile

Version 1 deliberately separates payload artifacts from structural records:

1. E2 captures producer payloads and builds a private envelope. The envelope
   hashes payload logs/receipts/results, but never itself, the public summary, or
   the final index.
2. The public projector constructs a new closed allowlisted summary from typed
   fields and approved registries. It is not a redacted private serialization.
   The summary never hashes itself or embeds a private-envelope `runRef`.
3. E3 builds the private index last. The index hashes the envelope, public
   summary, and every payload, then publishes with exclusive no-overwrite
   semantics. The external index/store may construct their `runRef` values.
4. Only a present, schema-valid, hash-valid committed index makes persistence
   `complete`. Staging envelopes found without that index are incomplete,
   regardless of their intended outcome.

This ordering has no self-hash or mutual-hash fixed point. The envelope declares
`requiredStructuralRoles: [public-summary, private-index]` without pretending
those structural bytes are payload `artifactRef` values.

The initial `mirrors.local-release-evidence/v1` profile requires exact catalog
and component identities, every command record, behavioral result, all applicable
cleanup scopes, all required producer logs/receipts/results, the public summary,
and private index. Every required payload has size and SHA-256. Optional raw
diagnostics remain labeled optional. The public persistence counts mean all
required payloads plus the two structural records; they are counts rather than
private artifact IDs.

Hashes establish byte integrity and content identity. They do not prove that a
command ran, a producer was honest, a timestamp is trustworthy, or a signer is
authorized. Those provenance and trust claims require independent execution
controls or a future signing policy.

## Public and private boundary

Private bundles use owner-only directories and mode `0600` files. The selected
developer default is
`${XDG_STATE_HOME:-$HOME/.local/state}/mirrors/evidence/v1/`, overridable with
`MIRRORS_EVIDENCE_ROOT`. It is outside `/tmp` and the checkout. It performs no
automatic upload or pruning and keeps finalized bundles until explicit operator
action. Tests always supply a disposable root.

The public projector's source allowlist consists of reviewed component identity,
catalog selection, stable command/approved-argument IDs, normalized outcomes,
tier states, counts, UTC timestamps, public artifact hashes, and reviewed
platform/tool identity. It excludes credentials, tokens, raw model/trace data,
expected states, private paths, raw argv, arbitrary exception or stdout/stderr,
control handles, and reproduction/recovery ownership secrets. Every public string
is checked for the private canary prefix in addition to structural validation.
Producer/tier/cleanup references must resolve only to public artifacts.

The local bounds are 4 MiB for an envelope/index, 16 MiB for an inline
Gate-compatible receipt, 64 MiB per artifact, and 512 MiB plus 2,048 files per
bundle. The file count includes the envelope, public summary, and final index,
leaving at most 2,045 payload artifacts. Overflow makes required persistence
incomplete or failed. It never
authorizes truncating evidence or leaking credentials.

Hosted retention, production access policy, signatures, key management, remote
storage, and publication remain unqualified. They do not block the selected
local-only implementation and no hosted/deployed/released claim follows from it.

## Schemas, fixtures, and validation

The normative draft schemas are
`tools/evidence/schema/evidence-envelope-v1.schema.json` and
`tools/evidence/schema/public-summary-v1.schema.json`. Fixtures cover clean and
dirty identities, required skip, cleanup failure, persistence failure, private
canary, and rejected mutations. Synthetic hashes and outcomes are deliberately
not historical results.

The validator rejects duplicate keys, malformed/non-integer JSON numbers,
documents over 4 MiB, depth over 32, excess nodes/strings, unsupported versions,
invalid references, a complete bundle missing required payloads, public private
canaries, path aliases, mixed exit variants, outcome-axis merging, and a false
qualified result. It does not read payloads or establish their hashes; E3 owns
offline byte verification.

Run the E1 contract gates from the repository root:

```bash
python3 -m unittest discover -s tools/evidence/tests -p 'test_contract.py'
python3 tools/evidence/validate.py tools/evidence/fixtures/envelope-private.valid.json
python3 tools/evidence/validate.py tools/evidence/fixtures/public-summary.valid.json
```

The local validator currently uses the Python 3.12 dependency closure pinned in
`tools/evidence/requirements.txt`. I2 must bundle those exact dependencies or
declare them as explicit host prerequisites; Q2 cannot rely on an unrecorded
global package. E2/E3 consume this accepted local contract. E4 binds
catalog/release claims to finalized `runRef` values. E5 audits
older records honestly and never recreates missing historical logs.

The local E2/E3 implementation and operator commands are documented in
[`tools/evidence/README.md`](../tools/evidence/README.md). E2 emits incomplete
staging envelopes while preserving the child's exit or signal. E3 independently
copies payload bytes, synchronizes payload directories, and publishes the index
last; its offline verifier parses the exact bytes whose hashes it checked. A
separate pending-package tool retains historical logs whose catalog or pre-run
source identity is absent, explicitly without creating an E1 `runRef`.

Candidate qualification spans runs that must be finalized in sequence, so E4
does not fabricate one envelope containing commands executed elsewhere. A
private `mirrors.qualification-scope/v1` producer result forms a bounded DAG of
exact private and public run references. It selects one distribution-binding D
run and records dependencies from D through origin capture, reproduction and
reduction. The later Q run executes only offline verification of this graph and
retains the scope as a required private producer result. C1 then cites Q's
allowlisted public run reference.

The linked verifier independently verifies each committed bundle, matches both
run references, enforces the same selected catalog A, validates the complete I2
manifest/cache shapes and hashes, and requires qualification-credit installed
runs to bind the selected exact D component and byte identities. Source commands
have a fixed component-owner mapping. Supporting diagnostics and failed retries
remain in the graph but contribute no command, tier, artifact-role, or cleanup
credit. Cycles, Q self-inclusion, duplicate command credit, mixed D identities,
arbitrary source subsets, and reproduction inputs whose embedded origin differs
from the dependency edge are refused. A recovery receipt must likewise name the
exact interrupted origin dependency. Q's public projection omits the graph,
private run IDs, paths, and artifact references.

Each qualification-credit run also carries a required private
`mirrors.evidence-command-context/v1` diagnostic. This keeps E1 v1.0 unchanged
while retaining and binding the exact bounded registry bytes, their hash and the
selected entry, component-owned
cwd rule, allowlisted effective environment, explicitly pinned environment-file
identities and executable identity. Registry
changes during execution prevent persistence. The linked verifier checks this
context against the raw registry, E1 command record and component identities; public projection
does not expose its paths, values or hashes.

The concrete command-to-demonstration mapping and remaining installed adapter
seams are tracked in
[`qualification-harness-design.md`](qualification-harness-design.md). A command
is registered only after its executable, cwd, argv length, output names and
native result schema are frozen.
