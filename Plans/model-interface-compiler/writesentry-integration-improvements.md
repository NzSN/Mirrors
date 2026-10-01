# Model-interface compiler improvements from WriteSentry integration

Date: 2026-09-30

Status: resumed implementation, 2026-10-01. Local source and native recorded-replay acceptance have advanced; the full definition of done remains incomplete. See [the extension contract](../../Docs/model-interface-compiler/writesentry-extensions.md) and [retained local acceptance](writesentry-v2-evidence/acceptance.json). The original plan/baseline below remains historical.

## 2026-10-01 remaining-work execution

Latest, Windows campaign: **fresh remote oracle qualification passes** against
the explicitly selected current Windows host at `172.20.208.1:8999`, Apalache
0.62.2 / Microsoft Java 25.0.4+7-LTS. Fourteen scenarios cover all eighteen
actions, eight flags and both overlap directions; all three genuine-server
mutation controls pass. The 424 replayed snapshots represent 212 snapshots in
fourteen distinct state sequences; timestamp-distinct backend artifacts are
preserved. The binding is regenerated/checked against fresh evidence, and the
normal rebuilt application passes 8/8 CTests plus fresh native/stdio/mutation
replays. [Acceptance and complete corpus](writesentry-windows-evidence-20261001/acceptance.json).
The explicit confined Workspace transfer preserves the wire bound. Publication
of the clean MirrorCPP v2 carrier and advancing WriteSentry's gitlink remain
pending. Frontend reference evidence retains its selected 0.61.0 identity.
The earlier entries below describe their respective execution checkpoints.

- Applied the adoption to the user-identified `~/Repos/WriteSentry`, now at the intended `9dd4b57` history; initialized its pinned MirrorCPP submodule and applied the reviewed v2 client patch. Actual application build/CTest passes 8/8, and the actual SDK's 27 unit cases pass. Recorded native coverage is recounted as 14 scenarios, 212 states, 18 actions, and eight flags; the three actual stdio-server controls produce `step_mismatch`.
- Obtained the selected Microsoft JDK 25.0.4+7-LTS archive/runtime with exact local hashes. Renewed only the fourteen existing outcome-policy differences against fresh observed source/tool identities. Profile-5 required differential qualification passes all 183 observations; 292 unsupported reference projections remain explicit. Raw evidence and policy review are retained in the frontend corpus and `Drafts/tla-profile5-policy-renewals.md`.
- Implemented the remote Mirrors CLI trace-capture path and WriteSentry's remote-only campaign wrapper. The owning Lean spec, fourteen actual CLI loopback cases, and four campaign admission/integrity tests pass. Original ITF metadata and bounded protocol semantics are preserved; server paths are never treated as local files.
- Added ordinary v2 recorded replay over stdio/TCP/mTLS, negotiated stdio/allowlisted mTLS, plain-TCP authorization-denial zero-callback checks, and TypeScript/Rust incompatible-profile rejection. The current local non-model aggregate passes 44/44 steps.
- Fresh deployed-service campaign admission is still blocked by absent private credentials and same-time service observation. Publication of a clean MirrorCPP v2 dependency revision and advancing WriteSentry's gitlink require the separately requested publication approval; current client source remains the reviewed dirty baseline plus patch. Neither absence is silently credited as completed qualification.
- Evidence: [remaining-work acceptance](writesentry-remaining-evidence/acceptance.json). The acceptance position below is the earlier committed checkpoint and remains historical.

## 2026-10-01 acceptance position

- Mirrors builds successfully. All 42 local non-model runner steps passed with `MIRRORCPP_PREFIX=/tmp/mic-mirrorcpp-install`. Live model-checking portions remain excluded/self-skipped. The offline differential suite reports 63 tests, four live-reference skips; its acquisition test now isolates runtime admission and separately proves that the different installed JDK is rejected.
- MIC-2 partition semantics and `/v1` policy rationale are recorded in the extension contract. The existing frozen wire/golden targets still pass.
- MIC-1/5 native v2 acceptance covers arbitrary-precision signed keys, integer/string distinction, nested and empty maps, copy/codec behavior, literal map lookup, duplicate/missing/mistyped rejection before callbacks, five accumulated lowering findings, and JSON/human agreement. The checked runtime specialization refuses missing/ambiguous template sections. A later negotiated fixture exposed the pinned client's v1-only allowlist; [the retained MirrorCPP patch](writesentry-v2-evidence/mirrorcpp-v2.patch) adds exactly v2 without changing its v1 default or registry key. Ordinary/negotiated v2 stdio replay and wrong-profile zero-callback rejection pass on that patched carrier. Its unit suites pass 21 negotiation cases (393 assertions) and six v1 binding cases (50 assertions). An executable invalid-ID case caught and now verifies quotes/backslashes/newline escaping in human diagnostics. Native string-map lookup with embedded NUL/quotes/backslashes/newline caught C-string truncation; length-delimited UTF-8 emission repairs it. V2 keyword errors identify the selected profile.
- MIC-4 consumer tests pass offline/configure/build verification, captured dependency changes, owned-header/helper/input mutations, unsafe/duplicate paths, omitted-owned-artifact rejection, regeneration and failure preservation. New meaningful gates are wired into Lake and the local runner.
- MIC-3 uses frontend profile 5, regenerated standard-module summary and metadata-migrated live summaries. Eleven content identities and eighteen import edges match the locked standalone jar. Profile-4 approvals are archived; the active registry credits none to profile 5. The required differential run is **incomplete**, because the installed JDK is `25.0.4.1+1`, rather than `25.0.4+7`; selected-JDK retrieval timed out. Do not relax the pin.
- The recorded WriteSentry integration was retrieved at exact upstream commit `9dd4b57` into `/tmp/mic-writesentry`; the sibling `/home/nzsn/Repos/WriteSentry` instead has unrelated Bazel history (`ed35481`) and was preserved. The tested adoption is delivered as [a patch](writesentry-v2-evidence/writesentry-v2.patch), verified to apply cleanly to `9dd4b57`.
- That adoption removes slot projections from the wrapper, contract, port, runner and recorded traces; restores `EXTENDS Integers, FiniteSets`; generates `mirrorcpp-v2` helpers; and replaces application freshness plumbing. The normal CMake build/CTest consumer passes **7/7**. Independent native replay recounts **14 scenarios, 212 states, 18 actions, eight reached flag classes**, including both overlap directions. Real stdio Mirrors replay passes, and all three mutations return actual server `step_mismatch`. These are results over a derived recorded corpus, explicitly `freshOracle: false`; they are not fresh remote-oracle qualification.
- Fresh remote qualification remains open: no client credentials or same-time service identity are present, and the Mirrors CLI currently exposes remote validation but no reviewed remote trace-generation/retrieval path for this corpus. Local trace paths are not a remote transfer mechanism. The original local Apalache generator was not run.
- Full new-profile cross-client/transport qualification, application delivery to the intended checkout, commit/push, publication, installation, and service deployment are not claimed.


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
