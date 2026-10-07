# Reviewed scaffolds and projected evidence corpora

[Current framework status](../current-status.md) indexes the October 7
frozen qualification, eight compiler emitters and separately scoped generated/
DPM acceptance. This document retains its own normative profile and dated
results; broader M4/platform and package-release claims remain separate.

Status: **implemented; public local/Gate integration accepted 2026-10-03**.
The [M6 execution record](../../Plans/m6-reviewed-scaffolds-and-corpora.md)
records the exact source gates, retained artifacts and qualification limits.

The reviewed workflow binds a human-reviewed companion contract to the exact
source closure and evidence inputs that produced its proposal. A separate
immutable corpus publication binds projected trace files and their receipts.
The compiler can resolve that chain into a lock and generate an ordinary async
suite bundle. Review metadata changes provenance, not the runtime wire protocol
or the semantic meaning of the contract.

## Commands

`scaffold --reviewable` selects the reviewable proposal format. Repeating
`--evidence` selects it implicitly. A single evidence input without that flag
continues to produce the legacy proposal. Legacy proposals cannot be sealed:
their structural evidence digest does not bind exact raw bytes or imported
sources. Regenerate them with the reviewable command.

The following sequence uses the public projected-cells fixture and a fresh
temporary output directory. The review file is supplied by
the reviewer after inspecting the proposal; the compiler never creates approval.

```bash
mi=.lake/build/bin/model_interface_gen
fixture=test/fixtures/model-interface/projected-cells
work=$(mktemp -d)
inputs=(--spec "$fixture/ProjectedCells.tla"
  --evidence "$fixture/trace-a.itf.json"
  --evidence "$fixture/trace-b.itf.json"
  --param-var parameters
  --projection "$fixture/projection.json")

"$mi" scaffold --reviewable "${inputs[@]}" --proposal "$work/proposal.json"

# Supply the reviewed, explicit review.json before continuing.
"$mi" seal-scaffold "${inputs[@]}" --proposal "$work/proposal.json" \
  --review "$work/review.json" --out "$work/sealed"

"$mi" project-corpus --spec "$fixture/ProjectedCells.tla" \
  --evidence "$fixture/trace-a.itf.json" \
  --evidence "$fixture/trace-b.itf.json" \
  --projection "$fixture/projection.json" --out "$work/corpus"

"$mi" resolve-sealed "${inputs[@]}" --sealed "$work/sealed" \
  --corpus-manifest "$work/corpus/manifest.json" --lock "$work/model.lock.json"

"$mi" bundle --lock "$work/model.lock.json" \
  --target mirrorecma-async-v1 --out "$work/bundle"

"$mi" check-sealed-bundle "${inputs[@]}" --sealed "$work/sealed" \
  --corpus-manifest "$work/corpus/manifest.json" --lock "$work/model.lock.json" \
  --target mirrorecma-async-v1 --out "$work/bundle"
```

`check-sealed` checks a normal generated tree; `check-sealed-bundle` checks a
suite bundle. Both recompute admitted inputs and compare the lock and generated
files without repairing them. `check-corpus --out DIR --manifest-sha256 HASH`
verifies a corpus against an expected SHA-256 of its exact manifest file.
The expected hash must come from the reviewed identity being checked. All new
commands accept `--diagnostics json`. Seal and corpus directories are immutable;
an existing destination is an error, and its parent directory must already
exist. Within this reviewed workflow, only proposal publication supports
`--replace`; the legacy `project-trace` command retains its existing replacement
option.

## Explicit review

The strict review schema is `mirrors.model-interface-scaffold-review/v1`.
Unknown fields, duplicate JSON object keys and wrong value types reject.

| Field | Meaning |
| --- | --- |
| `approved` | Must be literal `true`; absence or `false` rejects. |
| `proposalSha256` | Domain-separated canonical identity of the unchanged reviewable proposal. |
| `universes.complete` | Must be literal `true`, declaring that the supplied universes are closed. |
| `universes.initializers` | Complete initializer wire labels, including aliases. |
| `universes.transitions` | Complete transition wire labels, including aliases. |
| `contract` | The complete reviewed version-1 companion contract. |
| `replacements` | Explicit one-to-one decisions for changed initializer, action, input or observation identities. |
| `obligations` | Exactly one supported disposition for every original target-support obligation, with target and reason. |

Finite traces only establish observed labels. The review must retain those
labels in their original phase and may add unobserved actions. The two declared
universes must be disjoint and exactly match the reviewed contract. Review
cannot silently remove an input or observation, change model identity, or
change the wire configuration. Renaming an action also requires explicit
decisions for any resulting input identity changes.

Each replacement has `kind`, `from` and `to` fields. Input identities use
`ActionId/InputId`; other subjects use their stable IDs. An unchanged subject
needs no replacement. Unknown, unnecessary, duplicate or many-to-one decisions
reject. Obligation entries use `stableId`, `disposition`, `target` and `reason`;
the supported dispositions are `replaced` and `target-supported`.

Before sealing, the compiler captures the current source closure, reads every
raw evidence input, reapplies the optional projection and recomputes the
proposal. Changes to captured normalized source content or exact raw trace bytes
invalidate the review, including changes that preserve the sampled structural
type. Contract
resolution is part of admission. Successful sealing publishes `contract.json`,
`proposal.json`, `review.json` and `review-receipt.json` together.

## Identity and compatibility

Workflow-bearing locks use `mirrors.model-interface-lock/v2` with a
`mirrors.model-interface-workflow/v1` provenance object. Ordinary locks retain
their v1 format and canonical bytes. Semantic descriptors retain their existing
schema. The workflow carries proposal and review identities, every raw evidence
member, and optional projection-plan and corpus-manifest identities.

| Identity | Bytes covered |
| --- | --- |
| Captured source SHA-256 | UTF-8 source after CRLF and lone CR are normalized to LF, for the root and every imported source. |
| Raw file SHA-256 | Exact admitted raw file bytes. |
| Structural evidence digest | Parsed structural facts; distinct from a trace file identity. |
| Projected output digest | Domain-separated canonical projected ITF JSON, without the published LF. |
| Projected trace file SHA-256 | Exact published trace bytes, including LF. |
| Projection receipt digest | Domain-separated canonical receipt. |
| Corpus manifest SHA-256 | Exact canonical manifest file bytes, including LF. |
| Replay corpus digest | MirrorECMA's existing ordered trace-file-hash corpus identity. |

Members are ordered by raw file SHA-256. Input argument order therefore does
not change the result. Distinct raw inputs remain distinct members even when
their projected output is identical. Duplicate raw inputs and incompatible
closed records, variants, variable sets or phase labels reject.

Preflight for a workflow lock checks that each trace is an admitted member,
using both its exact file hash and structural evidence identity. The aggregate
evidence digest is never treated as the identity of an individual trace.
Coverage remains a replay result and does not become contract semantics.

## Corpus publication and loading

The corpus manifest schema is `mirrors.model-interface-corpus/v1`. Its source
list covers the captured source closure. Each member has a projected trace and
receipt named from its raw file hash; `projection.json` holds the plan.
`manifest.json` binds every member's hashes and lengths, the plan and ordered
replay corpus identity.

The producer validates every input before creating publication output. It
stages the complete flat artifact directory beside the destination and commits
it with one directory rename. Caught failures remove owned staging; existing
destinations remain intact. Publishers coordinate through a sibling lock and
require a caller-controlled parent directory. Concurrent external changes that
ignore that lock are outside this contract; ordinary directory rename is not
an atomic no-replace primitive. Publication does not claim fsync or power-loss
durability.

The workflow is bounded to 32 evidence inputs, 16 MiB per artifact and 64 MiB
aggregate corpus input/output bytes, at most 256 source members and JSON depth
128. Aggregate JSON traversal and projection work each have a 1,000,000-node
bound; individual trace projection retains its stricter existing work bound.
The network JSONL limit is unchanged.

MirrorECMA's corpus loader validates strict artifact schemas, contained files,
exact membership, lengths and hashes, and the source/projection/workflow links
to the generated suite's expected provenance digest. It then supplies the
existing `ReplayPlan.corpus` shape. Artifact identity is reported separately
from replay success; loading a corpus does not establish conformance.

```typescript
import { defineSuite, loadProjectedCorpus } from "mirrorecma";

const corpus = await loadProjectedCorpus({
  directory: corpusDirectory,
  lockPath,
  sourceRoot,
  model: ProjectedCellsModel,
  config,
});
const suite = defineSuite({
  id: "projected-cells",
  model: ProjectedCellsModel,
  replay: corpus.replay,
});
```

Here `config` is the ordinary `ApalacheConfig` for the model. `sourceRoot`
contains the root's compiler-recorded logical path; imported source paths are
resolved relative to that root source file's directory. The returned
`corpus.identity` records the verified artifact hashes. Every replay trace
retains its expected SHA-256 so suite preflight can reject changes after loading
before constructing an implementation. An optional `serverPath` callback
supplies a caller-owned remote filesystem mapping.

## Acceptance boundary

The public fixture projects a finite integer-keyed function into rows containing
real sets and string-keyed maps. Its adapter maintains independent mutable
state. Acceptance exercises the generated async port locally and through Gate's
worker collection bridge, including a deliberate well-typed wrong observation,
coverage, admission failure before acquisition, and confirmed cleanup.
Corpus artifact admission precedes provider construction. A later Gate replay
preflight failure prevents model transport and implementation binding; Gate can
already have a control session at that point, and its cleanup is checked
separately.

The [execution record](../../Plans/m6-reviewed-scaffolds-and-corpora.md#execution-record)
owns the measured results and remaining gaps. This source and integration
workflow does not requalify an earlier frozen framework candidate, establish
native Ubuntu/cgroup acceptance, or certify Windows service management.
