# Independent review of the client conformance fix plan

Reviewed 2026-10-15. Scope: `Plans/completed/client-conformance-fix-plan-2026-10-15.md`, the aggregate audit, the three contributor planning notes and selected current source/manifest paths. Read-only source review; no implementation, compilation, runtime probes, model operations, commits or deployment performed.

Initial verdict: **corrections required before treating the plan as execution-ready**. The seven main fixes are supported by the audit. The C++ trusted-provenance design correctly distinguishes worker-authored diagnostics from SDK/control classifications, preserves primary-over-cleanup precedence and requires real Gate failure injection. The plan appropriately separates source confirmation, scoped future acceptance and full conformance.

## Findings

1. **P2 — Pin the MirrorLean async gate to its non-live mode.** The remote-command table (initial line 171) says to run all three root executables without an environment guard. `MirrorLean/test/Async.lean:8–16` starts a Mirrors server and invokes live job checks whenever inherited `MIRROR_BIN` is present. Remote placement alone does not make that a non-model gate. Use `env -u MIRROR_BIN .lake/build/bin/async-test`, explicitly record its omitted live tier and preserve the already documented separate live-qualification procedure. The contributor note already supplies this exact safe command.

2. **P2 — Correct the ECMA Jest command.** The table (initial line 173) uses `pnpm test -- --runInBand ...`. The package script is Jest; the extra separator can turn the intended option into a positional pattern. Use the repository's existing `pnpm run test --runInBand --no-watchman test/model-interface-runner.test.ts` form, as in `scripts/ci/check.sh:56`, and list the selected tests/results in later evidence. No test execution is needed to fix this planning command.

3. **P2 — Make the chosen synchronous-session policy explicit in D1.** The current prose (initial lines 42–44) calls for explicit continuation where needed and tests protocol-error exits, but does not completely specify what happens when delegated synchronous dispatch returns successfully with an idle phase. Under the selected fresh-synchronous-session policy, make each `dispatchAsync` arm explicit: async accepted/rejected submissions and successful job controls continue; unexpected messages end; a delegated complete synchronous dispatch ends on every return, including success and registration failure. The existing `Bool` result can express this; an enum/refactor is unnecessary unless implementation evidence warrants it. State the compatibility effect: mixing synchronous work onto a connection with earlier accepted async jobs ends that connection and cancels/evicts its owned jobs under C6. Add successful synchronous return and failed synchronous registration cases asserting no next queued request is dispatched, owner jobs are cleaned, and another session remains usable. Preserve rejected **async** submissions as recoverable.

4. **P3 — Give D2 an explicit task identity and finish file ownership.** K1 depends on D2, which currently has no row in the task table. Add a coordinator-owned D2 decision/shared-case-list task dependent on P0, or state clearly that D1/D2 decisions are P0 outputs and make K1 depend on that output. Also explicitly assign Mirrors K1 `Ffi/tls_shim.c`/`tools/TransportSpec.lean` to the Mirrors owner and Haskell K1 transport/TLS tests to the Haskell owner; both overlap their main tasks. Shared contract edits should remain with the coordinator; only the Mirrors owner should edit the session and maintained drivers. This keeps implementation batches free of avoidable file conflicts.

## Acceptance assessment

- L1 covers default/nonempty/empty identity, CA-valid CN-only peers, pin independence, direct native entry and acquisition ordering.
- L2 addresses strings, escapes, nested comments and token separators while preserving original emitted sources and closure order.
- E1 preserves target-neutral descriptor scopes and validates compiled pairs before side effects; compatibility tightening is declared.
- C1 handles trusted origin, worker-code spoofing, failures bypassing the stored-error path, pre-disposal capture and primary/secondary cleanup. Keep the existing real-backend, malformed-worker, deadline/cancellation, application and mismatch controls; do not replace them with the earlier fake-transport result.
- M1/M2 cover stdio/TCP/TLS fragments, clean/abrupt TLS closure, exact writes, terminal failures and local budget-only cancellation.
- H1 covers all real adapters, final encoded bytes, bounded raw accumulation, poisoned input and shared reference-server effects. Selected Tasty patterns must remain explicitly non-model.
- D2 explicitly requires actual POSIX filesystem modes, observed chmod results, unchanged caller keys, exact special-bit handling and separate Windows limits.

The plan remains a proposal. None of these assessments grants implementation acceptance or full client conformance. Recheck the four corrections in the canonical plan, then append the final review verdict here.

## Correction recheck

The revised canonical plan resolves findings 1–3: it removes inherited `MIRROR_BIN` for the Lean async gate, uses the repository's direct Jest argument form, and explicitly ends every delegated synchronous dispatch with mixed-session ownership acceptance coverage. It also strengthens C++ failure-family/second-session controls, keeps Gate's model-generating runner out of this gate, and requires the native rebuild gate for K1.

Finding 4 is also resolved: D2 now has a coordinator-owned task row dependent on P0; K1 explicitly depends on that decision, and Mirrors/Haskell K1 work belongs to their respective main owners alongside overlapping tests.

**Final verdict: no remaining material findings in the reviewed plan.** The proposal is coherent and ready for user review. This verdict covers planning scope, compatibility choices, ownership, task dependencies and proposed acceptance gates. Implementation has not started; no build/runtime/model result or full client conformance is implied. Source/tool/dependency identities, actual Gate failure injection, repaired framing/TLS behavior and platform limits still require the future acceptance work described in the plan.
