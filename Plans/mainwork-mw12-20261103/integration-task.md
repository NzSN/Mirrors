# MW-12 candidate binding integration

Execute now using the completed source/acquisition work; do not repeat the
wide investigation. You are not alone. Preserve other agents' files, raw
receipts, historical checkpoints and sibling repositories.

Own `tools/evidence/commands.json`, `tools/interop/ecma-runtime-pin.json`, the
three framework catalog JSON projections, `catalog/components/mirrors.json`,
the generated component-lock/profiles/fixtures under both distribution roots,
`Docs/framework-map.md`, and NEW evidence only under
`Plans/mainwork-mw12-20261103/binding/`. No dependency pin change.

Inputs and exact paths:

- Source prepares `0.2.0-rc.6`; corrected `update_catalogs` must use selected
  `MIRRORS` by default. No branch/tag operation is authorized.
- Mirrors root `/home/lsz/Codebase/Mirrors`.
- Clean selected ECMA root
  `.golden-build/mw12-20261103/inputs/companions/MirrorECMA` at
  `9192171fc5f8d8457f8d13ffaafa117222914ec2`.
- Clean selected Gate root
  `.golden-build/mw12-20261103/inputs/companions/MirrorGate` at
  `4b379ac0c017e7621c945ebf8c106cd98a6c70d1`.
- Fresh runtime pin: `Plans/mainwork-mw12-20261103/integration/ecma-runtime-pin.json`.
- Trusted rebuilt C3: `.lake/build/bin/framework_catalog`, actual SHA-256 in
  `integration/targeted-binaries.json`; verify bytes before using it.
- Hash-guarded tracer launcher and its exact SHA-256:
  `integration/strace-closure.json`. It runs `--version` without exporting
  LD_LIBRARY_PATH; its tracing/namespace admission is NOT established.
- Candidate root, not yet installed:
  `.golden-build/mw12-20261103/candidate/`.

Implement in this order:

1. Copy the freshly prepared runtime pin to `tools/interop/ecma-runtime-pin.json`
   and set ONLY `mirrors.interop.requiredEnvironment.ECMA_REF` to the selected
   ECMA SHA in `commands.json`. Keep every other client/backend pin unchanged.
2. Rebind ONLY the local and Gate D command prefixes to absolute current paths:
   `--prefix` = candidate `/install/checked-replay-local` or
   `/install/checked-replay-gate`; C3 path/hash from the verified input;
   `--strace` = pinned wrapper path/hash from the closure; `--hide-root` =
   actual Mirrors and the two selected companion roots. Preserve argument
   order, argv lengths, attachment indexes, adapter/output contracts and
   all other registry entries. Parse the result using `command_registry`.
   These are future exact bindings, not evidence either D audit ran.
3. Add one `source` record for `Shell/Version.lean` to the Mirrors component's
   `records` in the owned record and both catalog variants (unique record ID
   `product-version`). Preserve all unrelated records/declarations.
4. Regenerate base catalog/owned record/locks/projections with
   `refresh_identity.py --mirrorecma ABS_ECMA --mirrorgate ABS_GATE
   --skip-mirrorecma-record-write`; then regenerate the additive WSL2 catalog
   with explicit `--catalog`/`--locks-root`, `--skip-component-records` and
   `--skip-render`. Never modify the clean companion checkouts. Do not hand-edit
   generated fixture hashes. Both dependency locks must retain their original
   bytes. The base root is a structural control; only the WSL2 profile is selected
   for execution.
5. Validate both lock roots with their explicit matching catalogs and C3 hash.
   Verify selected companion refs/products and Mirrors `0.2.0-rc.6` everywhere.
   Assert every fixture lock input uses its actual `distribution/<root>/...`
   prefix, and current source refs are stable after a second refresh.
6. Run full distribution and durable-evidence Python suites using an ext4
   TMPDIR under the task root. No Lake/full aggregate, installed build, D audit,
   remote model operation, local Apalache/TLC or Git ref mutation.

Write concise report/result/inventory and raw command logs under `binding/`.
Record active config/fixture hashes and exact C0 selection digests, including
the dirty source content digest. This is an uncommitted candidate, not a final
clean/tagged release freeze. Any missing input or failed validation remains
explicit; do not substitute old refs, weaken pins or claim namespace admission.
