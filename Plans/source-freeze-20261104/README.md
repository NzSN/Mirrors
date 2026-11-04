# Next source-freeze preparation — 2026-11-04

Status: **source review/preflight complete; full-gate approval pending**.
The user asked whether the next step could be performed. The Batteries
recovery removes the missing-carrier prerequisite for the new dependency
selection. The next boundary is source validation and a new candidate freeze,
before distribution cache/install/D execution.

## Reviewed scope

`intake.json` inventories 56 reviewed files from this session: the builder and
regressions, both dependency locks and derived fixtures, the actual vendored
carrier and metadata, maintained documentation/checkpoints and new evidence
records. It explicitly preserves 240 older unrelated untracked files. The
shared Git index is unchanged. The allowed binary is only the user-selected,
verified `third_party/batteries/batteries-v4.33.0.bundle`, SHA-256 `f6efbfeb…`.

Review confirms the builder preserves explicit overrides, enforces selected
byte length/hash before staging, and rechecks before clone consumption. Both
dependency roots change only carrier identity and API-regenerated fixture
bindings. The source revision/tree and license remain unchanged.

The recovery verifier was rerun and passes its independent offline clone and
negative controls. The focused durable-evidence suite passes 146 tests.
The earlier 73 distribution tests remain bound to the unchanged reviewed
builder/lock/vendor bytes. Pinned clean MirrorECMA/MirrorGate copies and the
hash-pinned C3 verifier match their prior admitted identities.

Local navigation checking covers 193 relative links in reviewed Markdown.
Three missing links in older CHECKPOINTS entries already exist at HEAD; no
new missing link is introduced. The dated checkpoint entries are preserved.
Git binary attributes disable text/diff/merge for the bundle.

## Approval boundary and execution proposal

The proposed next product version is **0.2.0-rc.7**, keeping the existing rc.6
package/tag identity bound to its old source. No version edit or tag creation
has occurred. A fresh remote tag-absence observation remains necessary before
any later tag operation; this preparation does not claim global tag availability.

The execution plan's MW-12/full-build boundary and the user's standing explicit
long/full-build approval preference apply. A concise approval question has been
presented for rc.7 preparation and this exact local gate:

```sh
TMPDIR="$PWD/.golden-build/source-freeze-20261104/tmp" \
  bash tools/run-local-no-model-check.sh
```

Run from the repository root in the admitted host context with loopback and
ext4 temporary storage, retaining stdout/stderr, exit status and source hashes.
The runner rebuilds and explicitly excludes local Apalache/TLC. Native integer
map/controlled preparation remains conditional on an actually admitted
`MIRRORCPP_PREFIX`; an absent input must retain its skip. No C/native dependency
graph change is in this payload, so a separate native-rebuild graph gate is not
selected for these edits.

After approval: prepare the selected version, rerun affected focused checks and
the full local non-model gate, bind a clean reviewed source identity, refresh
isolated base-control and selected WSL2 catalogs to a stable fixed point, produce
immutable source snapshots and independently verify the new freeze. Do not reuse
the historical dirty C0s or earlier rc.6 package acceptance for the new source.
Branch commit/push, local tags, packages, release and deployment retain their
separate concrete approval boundaries.

The full gate is **not run** and no final freeze is accepted while approval is
pending. New drafts/snapshots are not installation, D, M5/Q or release evidence.
Raw focused checks are retained under ignored owner-only
`.golden-build/source-freeze-20261104/`; intake, identity and navigation
observations are in this directory. No source behavior, version, shared refs,
remote service or deployment is changed by this preparation.
