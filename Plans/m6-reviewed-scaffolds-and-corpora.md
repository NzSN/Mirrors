# M6 — Reviewed scaffolds and evidence corpora

Date: 2026-10-03

Status: **complete for the declared source and public integration scope**.
These working-tree changes are included in the fresh
[M5 qualification](q3-post-m6-2026-10-03.md) for the named profile.
The user requested this plan
and its execution after the [compiler/client follow-ups and documentation
housekeeping](compiler-client-followups-2026-10-03.md), which are complete.

## Scope and sequence

This implements the five M6 clauses in
[the compiler design](../Docs/model-interface-compiler/design.md#m6-reviewed-scaffolds-and-evidence-corpora).

1. **Merge evidence and bind inputs.** Accept repeated scaffold evidence inputs;
   canonicalize compatible structural facts and observed phase labels; reject
   conflicts and phase overlap. Retain every admitted raw input identity and
   the complete captured source closure. Keep legacy single-input proposal
   bytes available; a versioned reviewable proposal binds the stronger workflow.
2. **Review and seal.** Require an unchanged reviewable proposal plus a strict
   review record with literal approval, complete closed initializer/transition
   universes, a reviewed contract, explicit replacements and a disposition for
   every target-support obligation. Recompute the captured source/evidence and
   optional projection before accepting the review. Publish the companion
   contract and review receipt as one immutable artifact directory.
3. **Resolve with provenance.** Add versioned workflow provenance for proposal,
   review, projection and evidence members. Keep semantic identity independent
   of sampled coverage. Preserve v1 lock parsing and canonical bytes. Resolve
   projected evidence only after validating the original source/raw evidence
   and reviewed projection chain. Add read-only checks and member-aware trace
   preflight; ordinary unreviewed resolution retains its current admission rules.
4. **Publish corpora.** Validate and bound every input before writing output.
   Emit one projected trace/receipt pair per admitted input, the projection plan
   and a canonical manifest. Publish a complete immutable directory with one
   atomic rename; reject collisions and roll back owned staging on caught
   failures. Provide a bounded, strict MirrorECMA loader that verifies linked
   identities and returns the existing corpus replay-plan shape.
5. **Exercise a public vertical slice.** Use a synthetic integer-function model
   whose projected rows contain real sets and string-keyed maps. Generate the
   async public port and run the same suite locally and through Gate's actual
   worker collection bridge. Require success, a well-typed deliberate observer
   mismatch, action/pair coverage, deferred acquisition and confirmed cleanup.

## Ownership and implementation boundaries

- Evidence/review worker: new pure merge/review types and codecs, scaffold/seal
  orchestration and focused tests.
- Provenance worker: lock types/codecs, compiler capture/resolution seams,
  member-aware preflight and generated suite provenance metadata.
- Corpus worker: corpus types/codecs, immutable publication, projection
  orchestration and rollback tests.
- Client/fixture worker: MirrorECMA loader and its tests, the public fixture,
  and actual local/Gate acceptance.
- Parent: shared-interface review, CLI integration, test-gate wiring,
  documentation, integration execution and final acceptance accounting.

Workers share schema/API decisions before dependent edits. Existing generated
files are regenerated through the compiler, never hand edited.

## Design constraints

- Legacy proposal-only scaffolding remains available. New reviewable proposals
  bind raw input bytes and imported sources; a structural type digest alone
  cannot authenticate a review of a particular evidence corpus.
- New workflow-bearing locks use a distinct versioned representation. Existing
  v1 locks and synchronous generated output retain their canonical identities
  when no workflow metadata is present. Runtime semantic descriptors and the
  wire protocol do not gain review or coverage fields.
- Evidence input order does not change canonical results. Incompatible closed
  records/variants and cross-phase labels fail instead of being silently widened.
  Sampled actions never establish a complete action universe.
- Projection receipt hashes are domain-separated canonical identities. Trace
  file hashes include the published LF; MirrorECMA corpus hashes retain its
  existing ordered file-hash algorithm. These identities stay distinct.
- Publication uses a fresh immutable directory as the commit unit. Readers see
  either its complete manifest and files or no publication. This does not claim
  power-loss durability or arbitrary multi-file crash rollback. The parent
  directory is caller-controlled and cooperating publishers share a sibling
  lock; uncoordinated external destination mutation is outside this contract.
- Artifact parsers have explicit size/depth/count/work bounds. The network JSONL
  byte limit remains unchanged. Invalid or stale inputs publish nothing.
- The public fixture contains no private application source or trace data.
  Its observer reads mutable implementation state rather than expected states.

## Acceptance gates

| Area | Required evidence |
| --- | --- |
| Review | Missing/false approval, stale proposal/input/import, incomplete universes, phase overlap, dropped fields and missing/invalid dispositions reject before publication. |
| Merge | Permuting input order produces identical canonical output; every input remains bound; incompatible evidence and duplicate inputs reject. |
| Identity | Review/projection/evidence changes affect workflow provenance; unchanged contract semantics preserve the semantic digest; v1 golden bytes remain unchanged. |
| Corpus | A bad later input writes no publication; simulated publication failures leave no partial destination; existing output remains intact; manifest/pair tampering rejects. |
| Loader | Strict decoding, bounded contained files, exact membership, source/lock/projection links and byte hashes are checked before replay construction. |
| Runtime | Real local and Gate success, real expected/actual mismatch, required coverage, zero acquisition on admission failure and independently confirmed cleanup. |
| Regression | Relevant Core/CLI gates, generated checks, MirrorECMA tests and Gate integration checks pass; broader suites run after integration. |

The coordinator runs no local Apalache or TLC. The public replay fixture uses
checked supplied traces. Any live model check must use the owned Windows oracle
and keep Windows writes within `C:\Users\ayden\Desktop\Workspace\MirrorsRemote`.

M6 acceptance is source and cross-repository integration evidence. It does not
transfer the earlier frozen M5 qualification to these changes. Native Ubuntu,
aggregate cgroups, active-process recovery and Windows service-manager acceptance
remain outside this plan. No commit, push or package publication is included.

## Execution record

- Plan presented after both prerequisite tasks completed.
- Reviewed workflow gate: **45/45 passed**, including explicit review,
  incompatible records/variants, stale raw/import rejection, actual emitter
  support checks, complete replacement injectivity, immutable seal verification
  and real corpus binding.
- Provenance gate: **38/38 passed**, including exact v1 lock bytes, v2 admission,
  semantic independence, imported-source capture and exact member preflight.
- Corpus gate: **38/38 passed**, including permutations, distinct raw inputs with
  identical projected output, invalid later members, all published-file tamper
  cases and injected staging rollback. The injected failures exposed and closed
  an exception-path ownership-tracking bug before acceptance.
  A subsequent platform-aware separator correction preserves native Windows
  path spelling; the CLI rebuild and all 38 corpus checks passed again on this
  coordinator. This is a source fix, not native Windows execution evidence.
- CLI gate: **30/30 passed**. The complete compiler executable builds; malformed
  options reject, legacy scaffolding remains available, repeated evidence is
  canonical, and default publication collisions preserve existing files.
- Six additional read-only checks passed against the actual copied MirrorECMA
  projected-cells artifacts: fresh sealed bundle/corpus, stale generated output,
  missing output and changed corpus members. Fingerprints were unchanged after
  every check, and missing output was not created. Receipt:
  `/tmp/m6-readonly-o7tisd2q/receipt.json`.
- The full local Mirrors runner passed:
  `MIRRORCPP_PREFIX=/tmp/mic-mirrorcpp-install bash tools/run-local-no-model-check.sh`
  (`/tmp/m6-source-mirrors.log`). This includes the new gates, legacy generated
  checks, CMake/native integer maps, distribution/evidence gates, sockets/TLS
  and registry checks. Live model-checking tiers were deliberately excluded;
  the offline TLA differential suite retained its four optional skips. The first
  restricted run stopped on denied socket creation; the successful run used
  approved loopback access.
- Final MirrorECMA type checking and the full regression suite passed:
  **42 suites, 676 tests passed, 13 existing optional skips**. Logs:
  `/tmp/m6-source-ecma-types-final.log` and `/tmp/m6-source-ecma-tests-final.log`.
  This includes the **20/20** loader tests against real compiler-generated
  artifacts and bounded workflow preflight tests covering normalized sources,
  exact trace identity, resource limits and deferred acquisition.
- The public fixture passes **10/10 runtime checks** through the same generated
  suite locally and through Gate's real worker collection bridge. Each correct
  run matches two traces, four updates and two Update/Update pairs. Both faulty
  observers produce an actual typed expected-zero/actual-one model mismatch.
  Successful and mismatch runs confirm cleanup; Gate persists and verifies its
  cleanup receipts with no remaining resources. Deliberate disposer failures
  prevent a passing outcome despite matched conformance and coverage.
- Tampered corpus admission occurs before Gate preparation, model transport or
  implementation acquisition; all three counters remain zero. A separate
  post-load stale-reference Gate case starts no implementation binding or model
  transport and confirms cleanup of the already prepared control session.
- The accepted runtime was packed, relocated and run with all three source
  checkouts hidden and networking isolated. The forbidden model-check sentinel
  records **zero invocations**. `PYTHONOPTIMIZE=1` was enabled for the final run.
  The source-hiding probe uses explicit checks; **3/3** optimized positive and
  rejection tests pass and are wired into `lake test` and the local runner.
- Final invocation:
  `PYTHONOPTIMIZE=1 python3 tools/model-interface-projected-corpus/check.py --out /tmp/m6-projected-cells-integration-v2-20261003`.
  The earlier v1 run remains historical. The final producer, fixtures, compiler,
  package files, corpus files and retained log hashes were independently
  rechecked against the v2 receipt; no differences were found. Manifest and lock
  bytes also agree across both independent fresh generations.

| Accepted artifact | SHA-256 |
| --- | --- |
| `/tmp/m6-projected-cells-integration-v2-20261003/receipt.json` | `4cf4202297c0c0439a009eec1f9c21347e420496ac0c7a33e78551015198eda1` |
| Compiler executable | `85727dfdfd03631bf4185caa8f05323b83157810fefaea85209dcb016faecad2` |
| Corpus manifest file | `440ddd0d446a113dbb5add81915247df7e67de10b8d998f1bca4e6efb66b9782` |
| Workflow lock file | `1e9935df6e1463572098a83db89399c07b1ad36abf5772e985c9e2d1953f0c9a` |

All five M6 clauses are satisfied at this scope. The
[workflow reference](../Docs/model-interface-compiler/reviewed-corpora.md),
[public fixture](../test/fixtures/model-interface/projected-cells/README.md) and
[interop gate](../tools/model-interface-projected-corpus/README.md) describe the
maintained interfaces and reproduction command. Current changes remain
uncommitted and do not inherit the earlier frozen M5 qualification.
