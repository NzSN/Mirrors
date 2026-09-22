# Framework catalog inventory

Status: C1 source inventory, 2026-09-22

This inventory identifies the current producers and owners that a future strict
framework catalog must adapt. It is not itself a support catalog. Repository
identities and dirty state are recorded in
[the implementation baseline](../Plans/implementation-baseline.md).

## Fact ownership

| Fact | Authoritative owner | Producing source | Current consumer | Freshness rule | Kind |
| --- | --- | --- | --- | --- | --- |
| Component product version | The component repository | Mirrors `Shell/Version.lean`; MirrorECMA `package.json`; Gate package/Cargo manifests | CLIs, packagers, release records | Read from the exact selected revision and verify against the built/packed artifact | Declared |
| Component source revision and dirty state | The checkout used by the producer | Git full HEAD plus porcelain status; dirty content needs a deterministic content identity | Catalog selection and evidence envelope | Capture immediately before production; never infer cleanliness from a commit alone | Observed |
| Model-interface target names and dispatch | Mirrors compiler | `Shell/ModelInterface/Compiler.lean` and target emitters | `model_interface_gen`, client generators, suite preparation | Re-extract from the exact compiler artifact/revision; source and binary identities remain separate | Declared and source-tested |
| Model-interface schema, interface version and semantic/provenance digests | Mirrors compiler contract and generated lock | `Core/ModelInterface/Resolve.lean`, compiler, generated lock files | Generated clients, preflight, Gate worker admission | Validate the lock and generated ownership manifest; require exact digest/profile match | Declared per generated artifact |
| Mirrors protocol behavior | Mirrors | `Core/Protocol.lean`, codecs and `Docs/interface-reference.md` | Client implementations | Bind claims to protocol corpus/test evidence at an exact revision | Declared and source-tested |
| Client feature support | Each client repository | MirrorECMA public APIs/project CLI/tests and equivalent native-client sources | Framework support table and application users | Component-owned record plus exact acceptance evidence; never infer from base wire support | Declared and observed separately |
| Workflow tool pins | The workflow that executes them | Mirrors `tools/ci/versions.env`; MirrorECMA `scripts/ci/versions.env` | Their CI/install preparation | Parse the selected pin file at its full revision; conflicting purposes remain separate selections | Declared |
| Package name/version/dependency closure | Package owner | MirrorECMA `package.json` and lockfiles; Gate package/Cargo manifests and locks | Installer, package consumer, runtime preparation | Verify packed bytes and installed manifest/lock identity, not only source metadata | Declared plus observed artifact |
| Project toolchain selection | MirrorECMA project contract | `src/project-config.ts`, `src/project.ts`, `src/cli.ts` | `mirrorecma doctor/generate/check/replay` | Closed schema, exact configured hash/version/capabilities; overrides must satisfy the lock | Declared and locally observed |
| Gate control/worker versions | MirrorGate | `sdk/compatibility.json`, protocol schemas, supervisor and SDKs | Gate clients and framework catalog adapter | Validate the Gate manifest at its full revision and confirm protocol tests for observed states | Declared and source-tested |
| Gate backend/runtime profiles | MirrorGate | `sdk/compatibility.json`, `docs/sandbox/linux-bubblewrap.md`, policy/runtime sources | Operator admission and diagnostics | Exact backend/profile plus host and runtime-tree observations; prose is not live admission | Declared and observed separately |
| Frozen source/artifact identity | Gate snapshot owner | `supervisor/mirrorgate/artifacts.py` and receipt producers | Worker admission, evaluator receipts | Recompute with Gate's documented path/content/mode hashing rule for every snapshot | Observed artifact |
| Runtime-tree identity | Operator/Gate admission record | Gate policy/build plan and installed-suite preparation | Gate admission and distribution manifest | Content identity covers the admitted tree; a Node version string is insufficient | Declared selection plus observed artifact |
| Suite/corpus/model identity | Evaluator and compiler-generated suite contract | MirrorECMA suite definition/preflight and generated locks/manifests | Replay, mutation and reproduction | Pin all model sources, corpus occurrences/hashes, interface digest and generated module bytes | Declared and observed |
| Behavioral and cleanup outcome | Run producer; common semantics owned by E1 | MirrorECMA normalized suite result; Gate trusted receipt | Evidence envelope and qualification | Record independently for each exact run; neither result substitutes for the other | Observed |
| Evidence persistence/completeness | E1 envelope/storage producer | `Docs/durable-evidence-design.md` and its schemas | Catalog evidence links, release qualification, offline verifier | Only a finalized retained envelope can be cited as durable; incomplete records stay incomplete | Observed |
| Publication state | Each component's publisher/release process | Publication-specific receipt or registry observation, not a source version | Catalog presentation and release report | Require immutable publication evidence for the exact artifact; absence is `unknown` | Observed |

No two repositories are authoritative for the same fact in this map. Gate's
compatibility file may repeat a Mirrors target or external tool version as a Gate
requirement, but that row is a Gate compatibility constraint, not ownership of
the compiler target or tool's product identity. Likewise, Mirrors client baselines
select revisions for an interop workflow; they do not own client capability.

## Current records to adapt

### Mirrors

- `Shell/Version.lean`: product release identity `0.0.2`.
- `Shell/ModelInterface/Compiler.lean`, `Shell/ModelInterface/Emit/`, and
  `tools/ModelInterfaceGen.lean`: four target profiles and deterministic
  generation/check behavior.
- `tools/ci/versions.env`: tool versions and exact interop client revisions.
- `Docs/framework-map.md`, `Docs/application-integration-guide.md`, and
  `Docs/application-integration-progress.md`: handwritten capabilities,
  acceptance scope, installation/publication distinctions and historical gaps.
- `Docs/application-integration-evidence.json` and related evidence JSON:
  component-specific retained summaries, not a common evidence envelope.

### MirrorECMA

- `package.json`, package locks and `scripts/ci/versions.env`: package identity,
  dependency closure, package manager, tools and published compiler baseline.
- `src/project-config.ts`, `src/project.ts`, `src/cli.ts` and
  `docs/project-tools.md`: closed project/toolchain records and read-only doctor.
- `src/suite-definition.ts`, `src/suite-preflight.ts`, `src/suite-result.ts`,
  `src/suite-runner.ts` and `docs/application-suites.md`: suite, provenance,
  matched acceptance, bounded lifecycle and normalized result facts.
- `scripts/check-installed-suite.mjs`: local package-consumer acceptance fixture.
- Application-validation results and WorkQueue acceptance fixtures: mutation
  ledgers and protected input hashes for F1, not general capability records.

### MirrorGate

- `sdk/compatibility.json`: the existing strict input record,
  `mirrorgate.sdk-compatibility/v1`; it is experimental, identifies control v1/v2,
  worker v1, `linux-bubblewrap-v1`, Node/Rust workers and publication false.
- `docs/compatibility.md`: explanatory scope and acceptance ledgers.
- `protocol/`, control schemas and SDK/runtime sources: actual protocol/profile
  definitions and conformance fixtures.
- `supervisor/mirrorgate/artifacts.py`, policy and orchestration sources: snapshot,
  runtime and lifecycle facts.
- `integrations/mirrorecma/src/receipt*.ts` and installed-suite scripts: trusted
  result/cleanup receipts and package-consumer acceptance.

## Capability state dimensions

The catalog must not use one `supported` boolean. Each capability has these
independent dimensions:

| Dimension | Minimum evidence |
| --- | --- |
| `sourceImplemented` | Live implementation entry point at an exact component revision; this source location is not an E1 execution result |
| `sourceTested` | Retained test result bound to the exact source/artifact combination |
| `locallyAccepted` | End-to-end local outcome with platform and cleanup observations |
| `installedConsumerAccepted` | Source-free, relocated installed consumer result for exact artifacts |
| `hostedCiAccepted` | Required hosted job result for the exact combination and platform |
| `published` | Registry/release publication evidence for exact artifact bytes |

`sourceImplemented` is `present`, `absent`, or `unknown` and carries exact source
locations. Every later dimension is `accepted`, `rejected`, `unavailable`,
`notRun`, or `unknown` and requires an immutable E1 `runRef` when it reports a
run outcome. A declared capability is separate from all six dimensions. Wire
negotiation and Gate policy remain authoritative even when catalog observations
are accepted.

## Discrepancies and unresolved inputs

- `mirrorrust-v1` is implemented and tested in Mirrors, but Mirrors framework
  and onboarding prose says no generated Rust target. Gate's false generated-Rust
  flag is correct for its own general application acceptance scope.
- Gate's manifest and prose overlap deliberately. The JSON is the adapter input;
  prose supplies explanation and historical evidence but cannot override JSON.
- Tool pin files name different baselines for different workflows. C2 must model
  the selection purpose and reject two records claiming the same purpose and
  component combination.
- Existing evidence JSON and receipts have several schemas and retention levels.
  C2 references finalized E1 run identities; it does not flatten their outcome or
  cleanup fields.
- Installed-consumer scripts create valid temporary observations but do not
  retain a release bundle or prove registry publication.
- Runtime profile names and runtime-tree hashes are distinct. Gate currently pins
  Node versions and sometimes executable hashes, while a complete distribution
  manifest for the admitted tree remains I2 work.
- Current native Ubuntu 24.04 backend and installed-consumer evidence is missing;
  WSL2 and hosted workflow records remain separately scoped.

## Handoff

C2 may now define one central catalog schema while preserving the owners above.
I1 may select a concrete platform proposal without turning CI configuration into
runtime evidence. E1 supplies `componentRef`, `artifactRef`, `catalogSelectionRef`
and finalized `runRef` shapes. R1, F1 and G1 reference those identities rather
than introducing parallel representations.
