# Batteries bundle carrier re-pin — 2026-10-31

The user requested a new Batteries bundle pin after the rc.5 distribution
builder refused the unavailable old carrier. The dependency remains the exact
same source revision, `4488d40d070b9700d4d5a6aa342f0d40c31b2a2d`, with tree
`5a1de86f7997958aaffec998882c29006b688d1e`.

| Input | Previous pin | New pin |
| --- | --- | --- |
| Bundle | `batteries-v4.33.0.bundle` | Same name |
| Bytes | 3,684,180 | **3,739,542** |
| SHA-256 | `f6efbfeb6353195c3318e3ef6e46d3e4e87897659989cd7322156d9e8a5f1cd3` | **`73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a`** |
| Source revision | `4488d40d…` | Unchanged |

The raw new bundle is retained at:

```text
.golden-build/batteries-repin-20261031/artifacts/sha256/73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a/batteries-v4.33.0.bundle
```

Its parent is owner-only; the retained artifact is read-only. `carrier.json`
records the exact generation command, Git version, source identity and log
hashes. The command uses `pack.threads=1` and `pack.compression=9`. The one
produced byte sequence is pinned; reproducible regeneration is not claimed.

## Change and validation scope

- Both `distribution/reference-node/dependency-lock.json` and the additive
  `reference-node-wsl2-26.04/dependency-lock.json` select the new bytes/hash.
  No other dependency record changed.
- The existing lock-generation API refreshed the four dependent fixture
  manifests and four cache-index digests. Catalog/profile and component-lock
  files in the shared checkout remain unchanged.
- A standalone clone from the new bundle resolves the exact required commit
  and tree with clean status. `git fsck --full`, `git bundle verify` and bundle
  HEAD checks pass; the bundle contains complete history.
- The trusted C3 verifier validates both lock roots. All **55 distribution
  tests pass**, covering base/variant lock resolution and bootstrap validation.
- A separate candidate catalog/lock preview is refreshed after the final
  status edits. It records the actual working-tree identity and the new
  dependency-lock bytes. It is not published source or final S5 acceptance.
- The prior rc.5 record and all its inventoried files are preserved
  byte-for-byte. Its offline verifier is rerun as a preservation check.

`lock-update.json`, command receipts, `candidate-preview.json` and `inventory.json`
provide the machine-readable bindings. `before/` preserves the two original
dependency locks. The offline verifier checks the new retained artifact,
both pins and regenerated fixtures, the candidate preview, and the earlier
record. It also rejects missing/tampered carriers, the old pin applied to the
new bytes, and a changed source revision.

## Continuation boundary

The missing-carrier problem is resolved for this **new working-tree dependency
candidate**. The existing clean rc.5 packages and tag still bind their original
source/contract inputs; they do not inherit the re-pin or new S5 credit.
Proceed through the new S1/S2 identity freeze/delivery boundary before final
exact-candidate S5 installation and producer admission. Both D audits, all
18 qualified M5 commands, 16 required tiers, full Windows acceptance and Q1/Q2
remain outstanding. No model checker, commit/push, tag mutation, publication,
deployment or reboot is part of this re-pin.

```sh
python3 Plans/batteries-bundle-repin-evidence-20261031/verify.py
```
