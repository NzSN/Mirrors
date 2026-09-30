# Model-interface compiler improvements from WriteSentry integration

Date: 2026-09-30

Status: proposed implementation plan. The workstreams below have not been implemented or qualified by this document.

## Objective

Generate and replay a C++ binding for WriteSentry's original state representation, with fewer application-specific workarounds and reproducible build checks. Preserve the independent implementation port, strict validation, deterministic generation, and the distinction between compiler acceptance and runtime conformance.

This plan exports five findings from the WriteSentry integration. One finding concerns replay partitioning in the Mirrors runtime; it requires coordinated runtime work alongside the compiler improvements.

## Baseline and evidence

| Component | Identity or observation |
| --- | --- |
| Mirrors source inspected during integration | `81cfa3e7db6905b2c5d0aa9c05ae2659560828ef` |
| Mirrors destination HEAD when this plan was written | `adcf1290e52380367d6632187631b0591cfea4c2` |
| MirrorCPP pinned by WriteSentry | `d8ed4455e8f73a9144215f62f1dc6963d6d792e7` |
| WriteSentry committed baseline | `e26fe92dff6a75e001f3f9b2c2aca573fb938db3` |
| Generated-binding integration | Uncommitted WriteSentry working tree at export time; inputs and output hashes are recorded in its `model-interface/manifest.json` |
| Compiler binary used for generated artifacts | SHA-256 `b0ec430c050ad2516c2198a4275d308c8a4b5e34e4015792f43de15431a05cea`; version `model-interface-gen/1` |
| Current WriteSentry interface semantic digest | `6ebfd3f76796bcc9e25b16849073b4b6d25adac1d5c762e4982eaeb4bf76a187` |
| Recorded MBT qualification | 14 scenarios, 212 compared snapshots, all 18 base actions, eight reached flag classes, three mutations detected by the real server |
| Portable verification build | Seven CTest tests passed, including generated binding dispatch and codec rejection |

The compiler binary hash and source revisions are separate identities; this plan does not infer binary provenance from a Git checkout. Relevant limitations were reconfirmed in the destination source before export. Freeze the generated-binding inputs in a reviewed commit before using them as immutable qualification fixtures.

Planning review (2026-09-30): the destination is still `adcf129`; WriteSentry and MirrorCPP HEADs match the table, and all seven files in the generated-interface manifest match their recorded SHA-256 values. The corpus manifest records the 14 scenarios, 212 compared states, 18 actions, and eight flag classes above. These are recorded integration results: this planning pass did not rerun CTest, compiler generation, or model checking. The existing live replay uses a real local stdio Mirrors process; it is not evidence of qualification against the deployed remote service. WriteSentry's integration remains an uncommitted working tree.

Evidence and existing contract authorities:

- [Compiler design](../../Docs/model-interface-compiler/design.md).
- [Generated interface specification](../../Docs/generated-model-interface-spec.md), especially the C++ target and owned-file rules.
- [TLA+ frontend design](../../Docs/model-interface-compiler/tla-frontend-design.md) and [language profile](../../Docs/model-interface-compiler/tla-language-profile.md).
- [Wire interface](../../Docs/interface-reference.md) and [client contract](../../Docs/client-implementation-guide.md).
- [WriteSentry MBT scope and qualification](../../../WriteSentry/tests/mbt/README.md).
- [WriteSentry generated-interface inputs and manifest](../../../WriteSentry/model-interface/README.md).
- [Application-specific generation wrapper](../../../WriteSentry/tools/mbt/generate_interface.py) and [freshness guard](../../../WriteSentry/model-interface/check.cmake).

## Priorities and ownership

| ID | Priority | Workstream | Owning code or repository | Main acceptance condition |
| --- | --- | --- | --- | --- |
| MIC-1 | P0 | Integer-keyed maps and `mapKey` paths | Mirrors value model, codecs, resolver, C++ emitter; MirrorCPP compatibility | Original `reg`, `dr`, and `tls` tables compile and replay without slot projections or tagged keys |
| MIC-2 | P0 | Consistent replay parameter partitioning | Mirrors trace core and session/CLI callers | Recorded metadata and actual comparison/input partitions agree |
| MIC-3 | P1 | Transitive standard-module visibility | Mirrors TLA+ catalog, resolver, elaborator | `Nat` resolves through `EXTENDS Integers` without adding `Naturals` to the source |
| MIC-4 | P1 | Generated CMake integration and artifact checks | Compiler publication/tooling; MirrorCPP package consumers | A fresh consumer can build, replay, and reject stale artifacts with generated helpers |
| MIC-5 | P1 | Precise target diagnostics | Compiler emitters and diagnostic adapters | Unsupported nested types and paths identify the responsible contract item and location |

These ownership boundaries identify implementation responsibility; they do not start implementation or assign running agents.

## Recommended first delivery and scope decisions

Deliver MIC-2 first. Its runtime/compiler disagreement can invalidate a generated binding even for types already supported. MIC-5 should accompany the first target change so failures explain the remaining limitations. MIC-3 and MIC-4 are separate improvements; neither needs to wait for full integer-key map support. MIC-1 is the largest change because it crosses the pure value/proof boundary and client compatibility surfaces.

The compiler already implements a bounded, content-addressed `project-trace` preparation step in [the pure projector](../../Core/ModelInterface/TraceProjection.lean) and [its codec](../../Codec/ModelInterfaceTraceProjectionJson.lean). It converts reviewed finite `Map[Int,T]` fields into sequences of records and emits a projection receipt. It does not currently supply a sealed generated binding or a corpus-wide replay integration. WriteSentry's nested `dr` table also needs explicit validation against that projector's supported shapes; successful outer-map projection alone does not establish nested-map support.

Two milestones must remain distinct:

| Milestone | Scope | Acceptance claim |
| --- | --- | --- |
| Optional portable bridge | Evaluate existing `project-trace` support, then add any reviewed nested/corpus projection and implementation-observation mapping required by WriteSentry | Removes hand-maintained projection plumbing while retaining an explicit lossless comparison view; does not complete MIC-1 |
| MIC-1 final target | Typed integer-key maps throughout runtime, codecs, compiler, and generated C++ port | Replays original `reg`, `dr`, and `tls` observations without a projection-only trace |

Keep the final target as this plan's definition of done. If the portable bridge is selected as an earlier release, give it its own qualification result and retain MIC-1 as open. Do not treat scaffold synthesis as reviewed contract sealing or infer a closed action universe from finite traces.

Before implementation, record these decisions in the affected contract documents:

- Effective parameter names augment recorded metadata. Use recorded names followed by configured additions, deduplicated in stable order; descriptor serialization follows its existing canonical ordering.
- Decide whether the corrected comparison policy requires a new policy identity. The current identifier is `mirrors-applyParamVars-filterMeta/v1` in [model-interface types](../../Core/ModelInterface/Types.lean). Regenerate affected semantic locks and invalidate incompatible descriptor/cache identities whenever the recorded semantics change; a product-version bump alone is insufficient.
- Separate a string-key `mapKey` emitter improvement from integer-key wire support. The former can be an independent target slice; the latter requires the complete compatibility decision below.
- Decide the native C++ map API and server/client capability identity before changing the currently documented `mirrorcpp-v1` contract. Preserve existing generated consumers, or publish a distinct target profile with an explicit migration. Apply the same review to ITF decoding and other clients instead of silently widening an existing strict contract.

## MIC-1: Integer-keyed maps and `mapKey` paths

### Observed limitation

The [C++ emitter](../../Shell/ModelInterface/Emit/Cpp.lean) accepts `Map[Str,T]` and rejects other map keys and all `mapKey` paths. The server [value model](../../Core/Value.lean) stores map keys as strings, and the [ITF decoder](../../Codec/Json.lean) requires string keys in `#map` entries. Changing the emitter alone cannot support WriteSentry's original tables.

WriteSentry currently adds six lossless observations: `reg_one/reg_two`, `tls_one/tls_two`, and `dr_one/dr_two`. Native replay checks the original tables; live replay publishes a reversible projected view. The target improvement should remove this adaptation.

### Deliverables

1. Agree a supported key-type matrix. The initial acceptance scope must include integer and string keys, nested maps, and arbitrary-precision integers. Other key types remain explicitly rejected until their semantics and target support are defined.
2. Keep state-variable names and record-field names string-based. Introduce typed function-map keys without conflating records, state maps, and TLA+ function values.
3. Define key equality, duplicate rejection, deterministic encoding, lookup failure, and order-independent map comparison. Preserve key identity: integer `1` and string `"1"` are distinct.
4. Extend pure values, ITF codecs, structural evidence/type checks, comparison, and relevant proofs. Retain existing string-key wire fixtures and record behavior.
5. Extend C++ native map lowering and input projection for supported `mapKey` literals. Missing keys and mistyped keys must fail before application mutation.
6. Review capability and profile versioning before publication. Document which server/client/compiler combinations support the extension; keep unsupported targets rejecting it explicitly.

### Implementation slices

| Slice | Owning surface | Exit gate |
| --- | --- | --- |
| MIC-1a | `Core/Value.lean`, `Core/Diff.lean`, `Core/Trace.lean` | Distinct typed function-map keys, terminating equality/diff procedures, and preserved equivalence/lookup/repartition proofs; record and state-variable keys remain strings |
| MIC-1b | `Codec/Json.lean`, structural evidence, resolver, and runtime preflight | Original nested ITF tables decode, infer, compare, and fail strictly on malformed or duplicate keys; path and ordered diff-hint rules are documented |
| MIC-1c | C++ emitter and MirrorCPP | Native typed maps and supported literal lookup compile; decode/dispatch failures invoke zero application callbacks |
| MIC-1d | Other clients and publication contracts | Supported clients pass the selected extension profile; incompatible combinations fail before replay; existing frozen fixtures retain exact bytes |

Do not extend the association-list `ValueMap` used for root state and record fields as a shortcut for typed function maps. Budget the proof and diff-path changes explicitly. Complete the agreed slices before removing application-side workarounds.

### Acceptance

- Decode/encode/replay nested integer-key maps without key tagging or source projection variables.
- Cover positive and negative integer keys, large integer keys, empty maps, reordered entries, duplicate keys, and integer/string key distinction.
- Reject malformed keys, unsupported key types, and missing projected keys with stable diagnostics.
- Generate, compile, and replay a minimal two-thread/two-slot fixture with WriteSentry-shaped tables.
- Preserve existing string-key comparison semantics, wire fixtures, and public C++ source compatibility, subject to the recorded profile decision.
- Do not introduce `sorry` or axioms when updating proofs.

## MIC-2: Consistent replay parameter partitioning

### Observed limitation

[`applyParamVars`](../../Core/Trace.lean) records `pvs ++ t.paramVars` as metadata but calls `resplit` using only `pvs`. During WriteSentry replay, recorded parameters `reg`, `dr`, and `tls` were consequently reclassified as compared state when configuration supplied only `parameters`. The compiler's evidence partition and the runtime's comparison partition differed.

### Deliverables

1. Define whether configured parameter names augment or replace recorded names. Adopt augmenting semantics for the existing combined-metadata behavior, or introduce an explicit documented override mode with consistent metadata.
2. Construct one effective, duplicate-free parameter set and use it for metadata, state splitting, evidence resolution, and compiler/runtime agreement checks.
3. Audit session registration, CLI replay, and other `applyParamVars` callers. Preserve `action_taken` exclusion and the existing meaning of constants.
4. Update affected fixtures, proofs, compatibility documentation, and the Haskell-reference divergence record if behavior intentionally differs.

Reuse the effective-name policy already expressed by [`effectiveParamVars`](../../Core/ModelInterface/Resolve.lean). Audit both the session call in [`Session.lean`](../../Shell/Mirror/Session.lean) and compiler-side preflight in [`Compiler.lean`](../../Shell/ModelInterface/Compiler.lean), plus CLI callers found by repository search. Keep configured `paramVars` compatibility checks distinct from the full effective-name set: a client configuration contains one configured name, while a lock can include several recorded names.

### Acceptance

- Recorded `param_vars=[parameters, reg, dr, tls]` plus configured `parameters` keeps all four names in the effective parameter partition.
- Cover empty configuration, missing metadata, overlap, duplicate names, configured additions, and repeated application.
- Effective partitions are disjoint and lossless, and repeated application is idempotent under the selected policy.
- State losslessness is proved under the parse-time key invariant; constants and `action_taken` retain their existing separate treatment.
- Ordinary and negotiated replay either use matching partitions or reject a disagreement before SUT execution.
- Add a focused regression demonstrating the original WriteSentry failure without changing the oracle values.

## MIC-3: Transitive standard-module visibility

### Observed limitation

The [elaborator](../../Core/Tla/Elaboration.lean) seeds selected standard-module declarations and explicitly defers transitive standard-module visibility. WriteSentry added `Naturals` to `EXTENDS Integers, FiniteSets` so the frontend could resolve `Nat`, although the standard `Integers` module already imports `Naturals`.

### Deliverables

1. Define a pinned standard-module catalog containing dependency edges and reviewed declaration facts, with a documented catalog identity and compatibility baseline.
2. Resolve transitive visibility through that catalog using the frontend's existing scope and shadowing rules. Keep local source overrides and captured-source provenance well defined.
3. Extend qualified and unqualified reference handling consistently; retain explicit failures for uncatalogued declarations rather than inventing facts.
4. Add differential fixtures against pinned SANY and supported Apalache versions through the existing conformance harness.

Keep dependency acquisition in [`Shell/Tla/ModuleResolver.lean`](../../Shell/Tla/ModuleResolver.lean) and source-provider effects in the shell; declaration visibility and its invariants belong in the pure frontend. Update the [language-profile identity](../../Docs/model-interface-compiler/tla-language-profile.md) and its frozen corpus when catalog facts or accepted source semantics change. Captured local modules retain the existing precedence over catalog fallback.

### Acceptance

- A fixture using `Nat` with only `EXTENDS Integers` resolves successfully.
- Cover relevant chains such as `Reals -> Integers -> Naturals`, qualified imports, local shadowing, and unsupported catalog entries.
- Match reference declaration identity, arity, and level facts for supported fixtures.
- Record catalog changes separately from source hashes and follow the existing provenance/semantic-digest contract.

## MIC-4: Generated CMake integration and artifact checks

### Observed limitation

The compiler already provides deterministic generation, ownership metadata, and `check`. WriteSentry still had to author a Python `resolve/generate/check` wrapper, a separate input/output hash manifest, and CMake replay guards. The current C++ ownership manifest identifies owned files but does not provide the consumer's complete freshness-verification workflow.

### Deliverables

1. Offer optional, compiler-owned CMake integration and a versioned verification manifest. Exact artifact and target names should be agreed in the compiler contract before implementation.
2. Record the root and captured source closure, contract, structural evidence, lock, generated outputs, target profile, and relevant digest identities.
3. Provide an offline freshness check that uses recorded hashes and digest agreement without requiring the compiler or a model checker on consumer machines.
4. Provide an explicit regeneration target that invokes the existing compiler commands and reports the compiler identity separately from the semantic digest.
5. Integrate with owned-file publication: update outputs together, preserve unrelated files, and refuse unsafe output replacement.

Use the current `resolve`, `generate`, and `check` pipeline; avoid a second C++ generation implementation. Generated consumer helpers should expose three separate operations: offline verification, build dependency registration, and explicit regeneration. Verify at configure/build time and immediately before replay so edits after configuration cannot bypass freshness checks. Keep corpus/oracle provenance in its own manifest, linked by digest rather than replaced by the generated-tree ownership manifest.

### Acceptance

- A fresh C++23 consumer uses generated helpers with the pinned MirrorCPP package and completes a positive replay.
- Editing a source dependency, contract, evidence, lock, header, or relevant metadata rejects stale artifacts before replay.
- A replay-only installation works without the compiler executable or model-checker installation.
- Exercise paths containing spaces, supported compilers/platforms, regeneration failure, and preservation of unrelated output files.
- Reject escaping relative paths, ambiguous duplicate manifest entries, and unexpected owned-output changes; never expand verification into recursive cleanup of consumer files.
- Keep consumer freshness checks distinct from full semantic compiler `check` and from artifact authenticity or publication claims.

## MIC-5: Precise target diagnostics

### Observed limitation

The C++ target reports stable codes such as `MIC-E-TYPE-001`, but generic rejection messages do not identify which action input or observation contains the unsupported nested type. Frontend source diagnostics already carry locations; target lowering should retain comparable contract context.

### Deliverables

1. Thread model/action/input/observation IDs, contract JSON paths, and nested type/projection paths through lowering.
2. Include a source or contract location where available, the unsupported feature, the selected target, and a supported remedy or capability requirement.
3. Report independent target findings in deterministic order rather than stopping at an unlabelled first failure.
4. Reuse existing diagnostic schemas and codes where possible. Document any schema extension and retain command exit behavior.

### Acceptance

- A rejected `dr: Map[Str,Map[Int,Rec[...]]]` names the observation and the nested integer-key location.
- A rejected `mapKey` names its action/input and projection segment.
- Multiple unsupported fields produce reproducible diagnostics without partial generated output.
- JSON diagnostics and human-readable output agree; paths and identifiers are escaped correctly.
- Unsupported-target guidance remains accurate after MIC-1 expands the C++ capability matrix.

## Delivery sequence and qualification

1. Freeze baseline fixtures, compatibility decisions, source identities, and the reviewed generated-binding integration. Add focused failing regressions for each finding.
2. Implement and qualify MIC-2 first; include the comparison-policy/lock migration in that slice. Deliver MIC-5 alongside target work and MIC-3/MIC-4 independently once their contract changes are agreed. Implement MIC-1 in the slices above; evaluate the optional portable bridge only as a separately scoped milestone.
3. Remove the WriteSentry slot projection and temporary replay-view workaround only after original integer-key tables compile and replay successfully. Restore the base import form as a MIC-3 regression.
4. Regenerate contracts, locks, evidence, and outputs through the compiler. Rebuild the typed application port against the supported original observations; preserve its independent state and behavior.
5. Requalify all 14 scenarios and 18 actions, eight reached flag classes, and the three mutations: `drop-reservation`, `skip-clear`, and `allow-foreign-writer`.
6. Confirm mutations yield the real server's `step_mismatch`, separately from binding/codec/configuration failures. Record snapshot totals from the fresh corpus rather than assuming the historical 212 count remains invariant.
7. Record exact Mirrors/MirrorCPP/WriteSentry commits, compiler/server hashes, backend versions, generated digests, command results, and skipped gates. Refresh the MirrorCPP dependency only to a reviewed revision that supports the tested combination.

Use the existing focused compiler, evidence, frontend, fixture, and client suites; add gates to their owning repositories. Follow the current Mirrors `AGENTS.md`: run required model checking through the Mirrors CLI against the designated remote service, with its actual deployed backend identity recorded. Recorded traces support local replay; they do not replace a required fresh remote qualification. An unavailable remote gate remains incomplete. Do not start a local model checker or reconfigure the service as part of this plan.

The final acceptance fixture should use WriteSentry's original `reg`, `dr`, and `tls` tables, no key tagging, and no projection-only trace files. The implementation port must never adopt oracle state. Compiler generation does not generate application behavior, and portable protocol qualification does not establish Windows debug-register/VEH conformance.

### Validation gates and evidence to retain

| Gate | Existing suite or consumer | Required evidence |
| --- | --- | --- |
| Parameter policy | `tools/ReplayFixtures.lean`, `tools/ModelInterfaceSpec.lean`, `tools/ModelInterfaceEvidenceSpec.lean` | Original failing partition case, repaired replay, losslessness/idempotence proofs, and regenerated locks where required |
| Map values and C++ lowering | `tools/DiffCross.lean`, `tools/ModelInterfaceSpec.lean`, `tools/ModelInterfaceEvidenceSpec.lean`, MirrorCPP native tests | Key matrix, nested maps, exact existing string-key wire corpus, supported `mapKey`, and zero-callback input rejection |
| Standard visibility | `tools/TlaModuleResolverSpec.lean`, `tools/TlaElaborationSpec.lean`, `tools/TlaFrontendSpec.lean`, differential corpus | Transitive identity/arity/level checks, source-override behavior, profile identity, and pinned reference results |
| Portable bridge, if selected | `tools/ModelInterfaceTraceProjectionSpec.lean`, `tools/ModelInterfaceTraceProjectionCliSpec.lean` | Nested-shape feasibility, reversible observation correspondence, domain completeness, resource limits, and per-corpus source/raw/plan/output hashes |
| Consumer integration | New compiler/CMake publication cases plus WriteSentry's existing seven CTest gates | Fresh checkout build, offline replay, stale-input failures, regeneration transaction failure, and unrelated-file preservation |
| Regression closure | `bash tools/run-local-no-model-check.sh` from Mirrors | Full affected local gates, exact generated golden checks, and explicit excluded live tiers |
| Application requalification | WriteSentry corpus runner and actual Mirrors replay | 14 scenarios, all 18 actions, both arm/write overlap directions, eight reached flag classes, and three terminal `step_mismatch` mutation controls |

These are commands and gates for implementation, not checks performed by writing this plan. Extend the owning suites for behavior changes; regenerate frozen Haskell fixtures with their documented generator and generated bindings with `model_interface_gen`, never by hand.

WriteSentry's current `generate_corpus.py` invokes a local Apalache executable, and its replay sends local trace paths to a stdio server. Before fresh qualification here, add a separate remote-oracle path through the Mirrors CLI to `192.168.150.219:8999`; do not run that existing local-backend path unchanged. Preserve remote job/result artifacts and record the deployed backend identity. Local stdio replay of retrieved traces can establish the binding/server comparison result separately. A remote TCP/TLS replay additionally needs an explicit supported trace-transfer mechanism or shared filesystem; local path strings alone are insufficient.

Retain, for each delivery, the contract/profile decision, exact source revisions and dirty-tree status, compiler and installed server hashes when obtainable, manifest and semantic digests, commands/exit codes, logs, compared-state totals, and negative-control outcomes. Distinguish backend unavailability, compile/codec/configuration failure, adapter failure, and genuine state mismatch. The portable model's simulated DR/VEH lifecycle remains its acceptance boundary; Windows runtime qualification is a separate project.

## Definition of done

- All five workstreams meet their focused acceptance checks and recorded compatibility decisions.
- Original-state WriteSentry generation and replay pass, with all three real-server mutation controls detected.
- Generated CMake helpers replace the duplicated application-specific freshness plumbing.
- Existing supported targets, transports, owned-file publication, and strict validation pass their affected regression gates.
- Documentation states the qualified server/client/compiler combination and any remaining unsupported key types or skipped gates.

Creating this plan completes the requested export. Implementation, dependency upgrades, commit/push, and publication are subsequent tasks.
