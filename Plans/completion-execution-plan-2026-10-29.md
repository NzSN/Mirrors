# Mirrors completion execution plan

Date: 2026-10-29. Starting Mirrors commit:
`7e9a27d0db72ec36b49c6fc5764b2687b565edfd`.

The user requested a design and execution of the remaining qualification,
controlled-synchronization comparison, M4 acceptance, compatibility and release
work. This supersedes the earlier exclusion of M4 from the October 28 task,
but does not select or provision an arbitrary native host. The coordinator is
observed WSL2 with Java 21; neither fact satisfies native M4 or pinned Java 25
reference admission. A native runner/delegation has been requested while other
work continues. Existing dated evidence and unrelated editor caches remain.

Detailed continuation, October 30: the
[completion and release design](../Docs/completion-qualification-release-design.md)
and [fine-grained execution plan](completion-qualification-release-plan-2026-10-30.md)
now define every remaining stage, task, dependency, evidence gate and approval
boundary. They govern the unfinished work ordering; the completed October 29
results and their original limits below remain unchanged.

## Design and ownership

Keep pure domain admission and transition rules in `Core/`, strict typed
representations in `Codec/`, and external-process/remote execution in `Shell/`
and the existing host tooling. Use the existing controlled-sync C++ SDK API;
preserve `mirrors.controlled-sync-replay/v1` and its `modelComparison:false`
meaning. Add a separate composite comparison result for the explicitly finite
producer/consumer mutex/FIFO mapping. A successful native run is input evidence,
never a model oracle or a model-conformance verdict by itself.

The reviewed model owns expected transition semantics. Native observations
come from actual application state after every decision. The receipt's complete
grant/result sequence supplies the fixed decision witness, and remote Mirrors
validation checks that witness against the model. Expected states never enter
the application factory or observer. Match requires complete receipt admission,
the actual remote valid verdict, stable source/executable/mapping identities,
and confirmed cleanup. Invalid, missing, timed-out or malformed evidence cannot
establish a match. New composite results do not change the existing SDK receipt
or wire protocol. The initial scope is this declared finite mapping, not a
generic arbitrary-program or weak-memory comparison guarantee.

The task is owned by the current agent. Companion repositories are inspected
without resetting their trees. Prefer isolated build/install staging within
Mirrors for this campaign; changes to companion public APIs are unnecessary for
the first finite comparison profile.

## Work packages and exit criteria

| ID | Work and concrete outputs | Prerequisites and exit criteria |
| --- | --- | --- |
| W0 | Reconcile completed immutable acquisition and implemented journal-v2 work with the older foundation/task records. Record exact repository, binary, toolchain and host identities in new campaign evidence. Inspect the existing `win10` staged tree and service read-only before reuse. | Preserve historical entries and receipt bytes. Record unavailable inputs explicitly; no service/PID/certificate identity is inherited from a dated record. |
| W1 | Add a finite controlled mutex/FIFO model, native consumer fixture, pure admission/projection, bounded remote comparison workflow and composite receipt. Add matching, FIFO/count mutation, malformed receipt, incomplete cleanup, deadline and output-bound controls. Exercise more than one admitted decision order, and retain fresh reduced failure replay where supported by the explicit catalog. | Actual SDK execution uses real threads/resources. Remote model-valid positives and model-invalid semantic mutations are required before any new `modelComparison:true` claim. Existing v1 schemas keep their meaning. |
| W2 | Stage the exact pinned SANY/Apalache artifacts and an already supplied Java 25.0.4+7 runtime on a separately admitted host. Build the current frontend, run required campaigns T/U into fresh directories, compare semantic reports and review every difference under profile 6. | All 61 fixtures and required observations complete; no unresolved differences; identical semantic payloads; stable before/after hashes. Preserve profile-5 approvals as historical. Do not download an unselected JDK or run reference model tools on this coordinator. |
| W3 | Freeze the current Mirrors and companion identities. Run full local non-model gates with the explicit MirrorCPP prefix, current Windows build/tests, source-hidden installed C++/Node/Rust DPM acceptance, remote model/client matrix and independent evidence verification. | One frozen candidate must pass every required selected tier. Reobserve the selected oracle process, certificate and backend/runtime identities before use. Local source tests do not replace Windows or installed acceptance. |
| W4 | Run M4 eligibility and, on the selected native host/delegation, actual aggregate quota readbacks, descendant enforcement/escape refusal, controller-death recovery, durable journal retries and unrelated-sentinel controls. | Requires an admitted native Linux runner, operator-owned cgroup-v2 parent and declared storage/resource envelope. Existing journal-v2 code is reused; unavailable native acceptance remains pending. Never create ownership from PID/path similarity. |
| W5 | Inventory the stdio async error-tag and Haskell consumers. Record a compatibility decision and measurable deprecation/soak criteria. Keep supported behavior until consumer migration and soak evidence satisfy those criteria. | Golden bytes and supported clients remain compatible. A calendar interval alone cannot authorize removal. Refresh the maintained plan/status navigation without rewriting historical evidence. |
| W6 | Prepare a versioned release candidate, reproducible archives, hashes, release notes, Windows staging, explicit rollback and service lifecycle checks. A new public F5 comparison capability uses the pre-1.0 minor-release policy; a fixes-only release can stay on the patch line. | Qualification records must name the exact scope. Prepare a reviewable payload and deployment first. Public tags/package publication, production service replacement and a machine reboot require final approval of that concrete payload and operation. M4/F5 can be excluded only by an explicit release scope, never silently credited. |

## Execution order

1. Execute W0 and host/runtime admission immediately.
2. Implement and locally validate W1 while remote prerequisites are inspected.
3. Freeze the changed implementation; run W2 and W3 against that identity.
   Repairs invalidate affected campaigns and require a new freeze.
4. Execute W4 when its selected runner/delegation is supplied. Its absence does
   not prevent independent implementation or qualification preparation.
5. Complete W5 documentation/consumer controls, then stage W6 with exact
   qualification limits and request only the final publication/deployment action.

Every work package receives a new result record: `completed`, `failed`,
`incomplete` or `awaiting-external-input`, together with its acceptance boundary.
Do not collapse successful local preparation into a passed external tier.

## Validation and retained evidence

Use new directories under `Plans/completion-evidence-20261029/` for curated
receipts and ignored task-owned build/output roots for binaries and credentials.
Retain original failures independently of later passes. Inventory bounded raw
outputs, source/tool/runtime hashes and selected command results. Never commit
private keys, temporary PKI, large tool archives or compiled binaries.

The existing local gate is `bash tools/run-local-no-model-check.sh`; keep its
model-check exclusions. Cross-client checks follow `tools/interop/INTEROP.md`.
Native changes use `bash tools/check-native-rebuild.sh`. Differential work uses
`tools/tla-differential/run.py --required` only on the admitted host. Live model
operations use the existing Mirrors CLI and a freshly observed owned remote
service. Run meaningful focused negative controls before aggregate gates.


## Execution checkpoint — October 29

W0 reconciles completed immutable acquisition and the already-implemented
journal-v2 source extension. W1 has scoped finite remote comparison/reduction
acceptance. W2 has independent required T/U passes with identical semantic
payloads. W3 has the full local non-model/native rebuild gates, current native
Windows build/eight suites, three installed DPM profiles and the selected Gate
required gate; its current five-client matrix is in progress. The existing
Ubuntu 24.04 reference distribution's D/Q/M5 renewal cannot be transferred to
this observed Ubuntu 26.04.1 coordinator. W4 still needs the requested native
runner/delegation. W5 records the compatibility decision, preserving both legacy
behaviors while measured retirement prerequisites remain open. W6 has a validated
Windows RC archive and a prepared independent Linux build checkout; packaging
and final handoff continue. See the [evidence record](completion-evidence-20261029/README.md).

The matrix uses fresh identities generated independently on each host and a
loopback SSH tunnel. Only public CSRs/certificates cross hosts. This is the safe
replacement for the rejected proposal to export an existing remote private key.
The actual executable JAR, Java executable, launcher, server binary and certificate
are reobserved. The selected Apalache archive pin is distinguished from a newly
verified archive carrier while its bounded restoration remains in progress.
The original dated qualification records and private credentials are preserved.
