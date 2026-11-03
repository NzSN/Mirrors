# MW-12 final source/C0 freeze task — 2026-11-03

## Goal and acceptance boundary

Prepare a reproducible final source/C0 freeze for the already delivered rc.6
source after the successful full local non-model gate. Grok executes F0–F4 and
reports evidence; Codex independently reviews, reproduces material claims and
owns acceptance. Grok completion alone is not a stage pass.

Current published HEAD is `3c4a87309cc3a81924660497207d7c295759bdc1`.
The full local non-model gate passed at its parent
`25b62541ca443d5779fccc8d45fd90f64312747e`; the intervening commit contains only
`CHECKPOINTS.md` and `Plans/s1-local-no-model-evidence-20261103/README.md`.
Prove that delta is entirely planning documentation under the maintained
`refresh_identity.is_planning_documentation` contract before using HEAD as the
freeze revision. Do not assume that a documentation-only delta transfers any
other qualification.

The earlier dirty-snapshot C0 values are historical and must not be reused:

- WSL2 `22596af73d943b2204a2ae3c7bbc39ae9c41ff03442507e0f26b183ac503a88c`
- base `ad9d28ae4b3b4eb2a662117b411fc8acc82e24cc82a04d8dfe6e770289c610bc`
- dirty source digest `59be0488dc9b32c086ac0b66e05459197fe9209e410ceeb47a87cf26f55ba80a`

## Ownership and prohibitions

Grok owns NEW files under `Plans/mainwork-freeze-20261103/`, except this task
file, and ignored outputs under `.golden-build/mainwork-freeze-20261103/`.
Do not edit existing source, catalogs, locks, registry, maintained status,
checkpoints, earlier evidence or sibling repositories. Preserve all unrelated
untracked records and ignored inputs.

No commit/push, tag, package, cache build, installation, D audit, M5/Q producer,
remote contact/model operation, local Apalache/TLC, deployment, service change
or reboot. Do not weaken a pin, skip a failed assertion or invent availability
of the missing Batteries carrier or ptrace/namespace admission. The base
catalog remains a structural control; selected execution is only
`ubuntu-26.04-wsl2-x86_64`.

## F0 — Intake and freeze eligibility

1. Record HEAD, tree, branch/cached origin state, tracked diff and the complete
   unrelated untracked scope without modifying it.
2. Verify the `25b6254..3c4a873` delta and prove every changed path is planning
   documentation. Verify source/contract bytes are otherwise identical.
3. Verify the S1 receipt/log hashes and terminal green line recorded in
   `Plans/s1-local-no-model-evidence-20261103/README.md`, including its native
   and live-model exclusions. Do not rerun the long aggregate.
4. Reobserve the exact clean companion copies and pins:
   MirrorECMA `9192171fc5f8d8457f8d13ffaafa117222914ec2`, MirrorGate
   `4b379ac0c017e7621c945ebf8c106cd98a6c70d1`. Use the task-owned copies from
   `Plans/mainwork-mw12-20261103/acquisition/inputs.json`.
5. Verify the current C3 binary against
   `Plans/mainwork-mw12-20261103/integration/targeted-binaries.json`, the ECMA
   runtime pin, tracer wrapper/dependency hashes and command-registry parse.
   Report if any identity drift blocks the freeze.

Exit: an intake receipt establishes the freeze revision, eligible source delta,
exact inputs and remaining external blockers.

## F1 — Isolated candidate copies

1. Create owner-only base and WSL2 candidate directories under the ignored task
   root. Copy each checked-in catalog and matching complete lock root into its
   own candidate family. Do not write refreshed outputs into checked-in paths.
2. Record before-hashes for every copied file and for checked-in non-output
   files that must remain unchanged.
3. Confirm that Mirrors has no in-scope source diff and selected companions are
   clean. Unrelated planning documents remain preserved and explicitly excluded;
   they are not evidence of a dirty source candidate.

Exit: isolated inputs are complete and checked-in files remain byte-identical.

## F2 — Fresh C0 refresh and stable fixed point

For each family, run `tools/distribution/refresh_identity.py` against the
candidate catalog/lock copies with explicit `--catalog` and `--locks-root`, the
selected clean companions and verified C3 binary. Use
`--skip-component-records --skip-render`; do not write companion records or
rendered documentation. Follow the corrected command contract in
`Plans/mainwork-execution-20261103/review/corrected-commands.md`.

1. Retain raw stdout/stderr/exit receipts for the first and independent repeat
   refreshes. The repeat must be byte-stable.
2. Record fresh canonical C0 selection digests and catalog file SHA-256 values.
   Assert they differ from the historical dirty-snapshot values above.
3. Assert Mirrors is the selected freeze revision with no dirty source payload,
   both companions have their exact selected clean revisions, and Mirrors
   declares `0.2.0-rc.6`.
4. Validate both candidate lock roots against their explicit catalogs and C3
   hash using maintained validators. Both dependency-lock files must retain
   their original bytes, and fixture lock inputs must use their actual
   `distribution/<root>/...` prefixes.
5. Prove checked-in catalogs, locks, compact projection, component records,
   `Docs/framework-map.md` and companion records are unchanged.

Exit: two fresh, stable and internally validated C0 candidates; only WSL2 is
selected for subsequent execution, while base is explicitly a control.

## F3 — Immutable source snapshots and freeze manifest

1. Run `tools/distribution/snapshot_sources.py` once per family against that
   family's refreshed component lock, using new output paths and the exact
   Mirrors/companion roots. Retain command receipts and snapshot inventories.
2. Produce a freeze manifest binding the freeze revision/tree, planning-only
   delta from the validated revision, companion revisions/trees, C0 selections,
   candidate catalog/lock/snapshot hashes, C3/runtime/tracer/registry identities,
   and the S1 local-gate evidence hashes/scope.
3. Include an inventory with byte lengths and SHA-256 for every new tracked
   report/script/receipt and every ignored candidate input/output needed to
   reproduce the freeze. Distinguish Git payload candidates from ignored raw
   artifacts.
4. Record the exact Batteries carrier, ptrace/namespace, D,
   remote/TLS/client/Windows, M5/Q and release gates as still open. No snapshot
   or C0 digest is installation or framework acceptance.

Exit: an immutable, reviewable C0/source snapshot manifest with no unresolved
identity substitution.

## F4 — Independent verifier and focused validation

1. Add a bounded `verify.py` under the new plan directory. It must independently
   parse the maintained registry/locks, check all manifest/inventory hashes,
   source and companion identities, planning-only delta, stable C0 selections,
   dependency-lock preservation, snapshot bindings and checked-in-file
   preservation. It must fail closed on missing/stale/extra inventoried files.
2. Include at least one non-mutating negative control demonstrating that the
   historical dirty C0 or a stale source revision is rejected.
3. Run the verifier and the distribution plus durable-evidence Python suites
   with an ext4 task-owned `TMPDIR`; retain raw logs and exit codes. Do not run
   the full local aggregate again.
4. Write `README.md`, `report.md`, `result.json` and `inventory.json` summarizing
   exact commands, identities, validation, failed attempts, exclusions and open
   gates. Separate executed facts from future commands and Codex acceptance.

Done when all F0–F4 assertions pass, or a precise blocker with retained failed
evidence prevents further progress. Edit first, then run the focused tests.
