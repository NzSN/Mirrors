# MW-00 / MW-10 / MW-20 source audit

Date of observation: 2026-11-03. Observer: Grok source job. Acceptance remains with Codex (MW-11). This directory is the only output this job wrote. No source, catalog, lock, `CHECKPOINTS.md`, central ledger, or other job directory was edited. No commit, push, tag, fetch, or `git ls-remote` was run.

Claim produced here: focused command receipts plus a read-only identity and diff review. This is not `source-validated`, not an S1 freeze, and not S2 publication. S3 packages, S5 admission, M5/D/Q, Windows qualification, release admission, and deployment stay uncredited.

## Tasks

| Task | Disposition | Output |
| --- | --- | --- |
| MW-00 | Executed. Pending Codex review. | Identities, companion snapshot, and status-drift citations in this report and `result.json`. |
| MW-10 | Executed. Pending Codex review. | Three required suites ran. Raw logs are under `logs/`. Distribution discover exited 1. Release and evidence discovers exited 0. |
| MW-20 | Preparation only. No publication action. | Review list, exclusions, final gate commands, and the remote observation recipe below. |

Baseline named by the brief is `75fbf962020cea8a13e009ecfdb3e912e7ce212f`. That is also `HEAD` and the cached `refs/remotes/origin/main`.

## Identities

Observed at 2026-11-03T02:00:38Z, immediately before the three required suites. Machine copy: `logs/identity-before.json`.

| Item | Value |
| --- | --- |
| Mirrors `HEAD` | `75fbf962020cea8a13e009ecfdb3e912e7ce212f` |
| Mirrors tree | `484e8f2991d1e2c56c8d47af668888e1cb48904f` |
| Branch | `main`, upstream `origin/main` |
| Cached `origin/main` | `75fbf962020cea8a13e009ecfdb3e912e7ce212f` |
| Ahead / behind cached upstream | 0 / 0 |
| Index | empty |
| Tracked worktree diff | `CHECKPOINTS.md` only |
| Origin URL | `https://github.com/NzSN/Mirrors.git` |
| Latest cached `origin/main` reflog | `75fbf96 refs/remotes/origin/main@{2026-11-03 09:42:59 +0800}: pull origin refs/heads/main: fast-forward` |

The reflog line is local cache metadata from an earlier pull. It is not a remote observation performed by this job. Cached refs do not establish current remote publication.

Untracked work present before the suites: 246 paths, all under `Plans/`. They were left in place. After the suites the only tracked diff was still `CHECKPOINTS.md`. Untracked count later rose because other jobs were writing; this job did not clean or revert those paths.

`git diff --check` on the worktree, including the uncommitted `CHECKPOINTS.md`, exited 0 with empty stdout and stderr (`logs/git-diff-check.stdout`, `logs/git-diff-check.stderr`).

### Local tags observed, not remote tags

| Tag | Commit |
| --- | --- |
| `v0.2.0-rc.1` | `d737aa0886b9d406e391955756922d9d735d7ec1` |
| `v0.2.0-rc.2` | `1fe379a5361fad8959ac40b47474beb6eb3bbe09` |
| `v0.2.0-rc.3` | `38a94ec85dd9e5e8c5aef45da2a5c909bcd74de5` |
| `v0.2.0-rc.4` | `5ab907d890e2656191e3cf1639244dc1ad15b1b7` |
| `v0.2.0-rc.5` | `3ee3d9226f6258583fe7266c1737acff5abd1edf` |

`Shell/Version.lean:6` is still `0.2.0-rc.5`. `tools/release/release.py:71-72` and `:88-89` require a clean checkout whose `HEAD` equals the tag and whose embedded version equals the tag without the leading `v`. HEAD cannot be packed as `v0.2.0-rc.5` while that tag points at `3ee3d92`. Moving the tag is outside this job and would detach the historical rc.5 packages. A new version string and an unused tag belong to MW-30.

### Companions, read-only, no fetch

Snapshot at 2026-11-03T02:00:38Z. Upstream SHAs below are cached tracking refs.

| Repository | Local `HEAD` | Tree | Cached upstream | Dirty scope |
| --- | --- | --- | --- | --- |
| MirrorECMA | `f94358834dce2e527c8bc8feec0423a54cf4176c` | `e9fdf0e513a998fb72faa47c8501cdab9c34f782` | same, ahead 0 behind 0 | 2 untracked: `node_modules-pnpm-isolated/.package-map.json`, `node_modules-pnpm-isolated/.pnpm-workspace-state-v1.json` |
| MirrorGate | `4ef786b30ac6be45e471fb02610484581f5da3b0` | `e2dcc7632cbcead146d3173174817c4aefc7c4c3` | same, ahead 0 behind 0 | clean |
| MirrorCPP | `8c542a6b1339cc0b6176465ff7f17a32e614553d` | `f8700c53f49ff5c0e7200019845596b99c80f6ac` | same, ahead 0 behind 0 | clean |
| MirrorRust | `6b9480ab81717b76ca7f74b41fc554578b70c890` | `8e85af41e8eb1cd1a53d8037d76ffc52a0a02599` | same, ahead 0 behind 0 | clean |
| MirrorLean | `a8634ebe2455f97d15b55bec3c810d945cb6e3d3` | `ff01f8a2a91b1e1485c14c88a7604a37810b99f2` | same, ahead 0 behind 0 | clean |

The checked-in three-component catalog names different companion commits, and those objects are absent from the local companion databases (`git cat-file -e` failed; this job did not fetch):

| Catalog component | Catalog revision | Catalog dirty | Local checkout |
| --- | --- | --- | --- |
| `mirrorecma` | `9192171fc5f8d8457f8d13ffaafa117222914ec2` | false | `f94358834dce…`, object `9192171…` absent locally |
| `mirrorgate` | `4b379ac0c017e7621c945ebf8c106cd98a6c70d1` | false | `4ef786b30ac6…`, object `4b379ac…` absent locally |
| `mirrors` | `bd5d3b51b1dcd75fbdf6c3188f1c90b1e6fe6ea0` | true | HEAD `75fbf962020c…`, clean for the catalog's included paths |

Citations: `catalog/framework-catalog.json:10`, `:39`, `:58`; `Docs/framework-map.md:81-83`; `distribution/reference-node/component-lock.json:13`, `:25`, `:37`; the WSL2 lock has the same three revisions at the same line numbers. MirrorCPP, MirrorRust, and MirrorLean are sibling checkouts outside that three-component catalog. Their clean snapshots are intake facts, not catalog membership.

## Range `3ee3d92..HEAD`

`3ee3d9226f6258583fe7266c1737acff5abd1edf` is the parent of `72d83b0` and the commit named by local tag `v0.2.0-rc.5`. Four commits:

| Commit | Tree | Author date | Subject |
| --- | --- | --- | --- |
| `72d83b047b0f2da92cfd7acbc6780a9a842628a6` | `0b82ef41612da2954a346650e290d6baab2ca310` | 2026-10-31T22:50:43+08:00 | distribution: re-pin Batteries carrier for v0.2.0-rc.5 |
| `bd5d3b51b1dcd75fbdf6c3188f1c90b1e6fe6ea0` | `2e3d01cc375391b9cd6e82819f5a40ecd9b18e84` | 2026-11-01T08:14:24+08:00 | gitignore: exclude Projectile editor cache |
| `f0daef9915a1751d278dcb6645280a5c54dc6f57` | `05c01267c6f6f56d2f6509d7a2abe5c5a080d81e` | 2026-11-02T08:01:10+08:00 | distribution: propagate maintained product identity through lock refresh |
| `75fbf962020cea8a13e009ecfdb3e912e7ce212f` | `484e8f2991d1e2c56c8d47af668888e1cb48904f` | 2026-11-02T23:29:03+08:00 | distribution: accept warning-prefixed CLI diagnostics |

### Behavior and inputs

`72d83b0` changes both dependency locks and the regenerated fixture manifests and cache indexes. Batteries source revision stays `4488d40d070b9700d4d5a6aa342f0d40c31b2a2d`. Carrier bytes change:

| Profile file | At `3ee3d92` | At HEAD |
| --- | --- | --- |
| `distribution/reference-node/dependency-lock.json:65-66` and the WSL2 twin | `f6efbfeb6353195c3318e3ef6e46d3e4e87897659989cd7322156d9e8a5f1cd3`, 3,684,180 bytes | `73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a`, 3,739,542 bytes |

Component-lock catalog selection hashes do not change in this commit. They change in `f0daef9`.

`bd5d3b5` adds `/.projectile-cache.eld` at `.gitignore:24`. No runtime, model, or compiler behavior. Snapshot membership excludes that editor cache. `test_editor_cache` passed in the distribution run.

`f0daef9` changes lock refresh. `tools/distribution/refresh_identity.py:139-149` copies each catalog component's `product` onto the matching component-lock entry. The new test `tools/distribution/test_refresh_identity.py` expects that copy, including replacement of a lock product `mirrorecma` `2.0.0` by the catalog product `0.1.0`. Checked-in results of that refresh:

- Catalog selection at HEAD, both profiles, is the `f0daef9` value. Base `e971cfec068c09532f2ffd01b15425be33aab42fa7dca507c0a0fe844c818b59`. WSL2 `3bef64ce1e1e4fdc7b9d99e2cb4f5a1f165cd54f49cdeac7af42f6c3130253ee`. At `3ee3d92` those values were `03d084ef7464bb40348d3ba81b7f13f48ad86e41b0b7ba6b0b3f07b0176d38d1` and `4a485efb456bb930a0e56832800725c7bdaeff92a533e0241d41cdefcaef5a23`.
- `mirrorecma` lock product moves from `2.0.0` to `0.1.0` (`catalog/framework-catalog.json:14-15`).
- `mirrors` lock product stays `0.1.1` (`catalog/components/mirrors.json:94`, `catalog/framework-catalog.json:142`).
- `mirrors` revision in the catalog becomes `bd5d3b51…` with `dirty: true` and dirty included paths `tools/distribution/refresh_identity.py` and `tools/distribution/test_refresh_identity.py` (`catalog/components/mirrors.json:10-19`). Those paths are committed in `f0daef9`. HEAD does not show them as uncommitted.

`75fbf96` changes `tools/distribution/qualification.py:74-112`. `json_document` accepts one JSON object when non-JSON warning text precedes it and only whitespace follows it. Invalid JSON, trailing non-whitespace, and a second JSON value are rejected. Whole-stream `json.loads` is tried on stdout, then stderr, before the warning-prefix decoder. The five new tests in `tools/distribution/test_qualification.py` passed. This commit does not change catalog revisions, selection hashes, or locks. The checked-in catalog therefore still describes the dirty `bd5d3b5` snapshot from `f0daef9`, and does not name `75fbf96`.

`tools/distribution/install.py` and `tools/distribution/test_install.py` have an empty diff from `3ee3d92` to HEAD.

### Invalidation

Design rule used: `Docs/completion-qualification-release-design.md` section 3.3.

- Dependency-pin change in `72d83b0`: re-admit the affected distribution profiles and rerun dependent producers and Q. Historical rc.5 Linux/Windows packages and local tag `v0.2.0-rc.5` stay bound to `3ee3d92` and the old carrier `f6efbfeb…`. They do not qualify HEAD.
- `bd5d3b5` is a source-tree change with snapshot-exclusion effect. It is part of any HEAD freeze. It does not by itself require a model, compiler, or companion rerun.
- `f0daef9` is a contract-input and tooling change: new catalog selection, new companion revisions, and a product-field change for `mirrorecma`. It is a new candidate. Downstream gates that consume locks or companion identity have to be rerun after the final freeze commit.
- `75fbf96` is a behavioral distribution change. It is a further candidate step. The `f0daef9` selection hashes do not cover it. Distribution qualification behavior has to be rechecked at the freeze commit. The parser unit tests passed in this run.
- Shell version did not change, so this is not a version-string bump. The existing rc.5 tag still cannot be reused for HEAD, because the release tool binds the tag to one commit.
- No D audit, M5 tier, Windows `lake test`, Q1/Q2, package rebuild, publication, or deployment is inherited.

### Maintained-status drift

Committed `CHECKPOINTS.md` at HEAD still says the re-pin is uncommitted:

- Line 19: "all 55 distribution tests pass".
- Line 21: "The re-pin is a new working-tree dependency candidate".
- Lines 27-28: "No source commit/push, tag change, publication, deployment, model checker or reboot was performed."
- Line 60, in the rc.5 entry that the same commit added: "No source commit/push, remote tag, release, deployment, restart, or reboot was performed".

Those sentences are inside the history that contains `72d83b0`. HEAD also contains `bd5d3b5`, `f0daef9`, and `75fbf96`, which the 2026-10-31 text does not name.

The worktree `CHECKPOINTS.md` has an uncommitted 2026-11-03 prefix that this job did not write. With that prefix present, the same sentences were at lines 57, 59, 65-66, and 98-99. Codex owns `CHECKPOINTS.md`. This job left the prefix in place. Worktree SHA-256 at 02:00:38Z: `ab1d4a1eb012fc83c0474ff06c909a9a34770c3ce3e7184fea18123b69ce018c`. HEAD blob: `988d0fd7ae33a9a8c9c0021d7efb2ec71dcafb03`.

`Docs/current-status.md:1-14` is still the 2026-10-31 re-pin section. Line 9 repeats the 55-test count. The distribution discover at HEAD ran 61 tests (the re-pin count plus one refresh test and five diagnostic tests). The section does not mention `f0daef9` or `75fbf96`. Lines 17-31 correctly describe the rc.5 packages as bound to `3ee3d92`. Line 28's "No dependency pin changed" is about that package record. HEAD's pin is the later `73130433…` value in the section above it.

`Plans/execution-decisions.md:9-21` is still titled as the current continuation for the re-pin and says no commit or push is authorized by that record. It does not record the four commits now on `main`.

`Docs/framework-map.md:81-83` repeats the stale catalog revisions, including `mirrors` dirty at `bd5d3b5`.

`AGENTS.md` points status readers at `Docs/current-status.md` and the newest checkpoint. Its own "current framework checkpoint" paragraph remains the 2026-10-22 pointer. The drift that blocks freeze is the three maintained status files above plus the catalog.

### Product-identity split

`Shell/Version.lean:6` says `0.2.0-rc.5`. Catalog and both component locks say Mirrors `0.1.1`. That split already existed at `3ee3d92`. `f0daef9` now copies the catalog product into locks on every refresh, so a future refresh will keep writing `0.1.1` until the catalog changes. Release packaging reads `Shell/Version.lean`, not the catalog product. A freeze has to choose one meaning and record it. This job did not edit either file.

## Commands

Python 3.14.4. Host used only to explain the distribution failure: Linux `6.18.54.1-microsoft-standard-WSL2` x86_64, Ubuntu 26.04.1 LTS. `/tmp` is tmpfs. The repository filesystem is ext4. This is not an S5 host admission.

Required suites, cwd `/home/lsz/Codebase/Mirrors`, `APALACHE_MC`, `APALACHE_JAR`, `TLA2TOOLS_JAR`, and `MIRRORS_ASYNC_RESOURCE_E2E` unset. Unittest verbose text is on stderr. Empty stdout uses the empty-file SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

| Id | Started (UTC) | Finished (UTC) | Exit | Result |
| --- | --- | --- | --- | --- |
| `distribution-unit` | 2026-11-03T02:00:38Z | 2026-11-03T02:00:41Z | 1 | 61 tests, 3.209 s, 2 failures, 8 errors, 0 skips |
| `release-unit` | 2026-11-03T02:00:41Z | 2026-11-03T02:00:42Z | 0 | 11 tests, 0.949 s, OK, 0 skips |
| `evidence-unit` | 2026-11-03T02:00:42Z | 2026-11-03T02:00:59Z | 0 | 146 tests, 16.846 s, OK, 0 skips |

Argv, in order:

```sh
python3 -m unittest discover -s tools/distribution -p 'test_*.py' -v
python3 -m unittest discover -s tools/release -p 'test_*.py' -v
python3 -m unittest discover -s tools/evidence/tests -p 'test_*.py' -v
```

Elapsed wall time: 3359 ms, 1021 ms, 16984 ms. Byte sizes and SHA-256s are in `result.json` and `logs/command-records.json`.

Release stdout is five lines, `Running non-model release gate:` plus `fixtures_replay`, `diff_cross`, `model_interface_spec`, `stdio_smoke`, and `transport_spec`. Those lines are printed by `tools/release/release.py:142`. The whole release module finished in 1021 ms, so this run is the unit suite, not `bash tools/run-local-no-model-check.sh` and not a Lake build.

The new `75fbf96` and `f0daef9` tests passed inside the failing distribution process: `test_json_document_*` (five) and `test_update_locks_assigns_product_by_component_id`.

### Distribution failure

Classification: environmental filesystem precondition. Not a regression in `3ee3d92..HEAD`.

`tools/distribution/install.py:697-698` rejects a prefix whose `filesystem_type` is not `ext4`. Blame is `153f387a` (2026-09-22). The same lines exist at `3ee3d92`. `filesystem_type` reads `/proc/self/mountinfo` (`install.py:39-51`). `test_install.py` creates prefixes with `tempfile.TemporaryDirectory`. `TMPDIR` was unset, so the directory was `/tmp` tmpfs.

Failures and errors, all `ValueError: version 1 requires ext4 installation filesystem, got 'tmpfs'`:

- Errors: `test_all_interruption_boundaries_preserve_previous_selector` for `after-copy`, `after-materialize`, `after-verify`, `before-activate`, `after-version-rename`, `after-selector`; `test_commit_idempotence_and_after_activation_rollback`; `test_interrupted_stage_is_quarantined_before_retry`. Call sites: `test_install.py:274`, `:181`, `:202`.
- Failures: `test_lock_symlink_and_selector_confinement` (`test_install.py:217`) and `test_staged_cache_is_verified_before_materialization` (`test_install.py:168`). The intended regexes were `locked` and `staged cache rejected`. The ext4 check raised first.
- One `ResourceWarning` for an unclosed lock file was printed while handling that early exception in `test_lock_symlink_and_selector_confinement`. It did not appear in the ext4 reproduction.

Reproduction, cwd repository root, `TMPDIR` set to a removed directory `Plans/mainwork-execution-20261103/source/tmp-ext4-eBYd` on ext4:

```sh
python3 -m unittest discover -s tools/distribution -p 'test_install.py' -v
```

Started 2026-11-03T02:05:01Z, finished 2026-11-03T02:05:01Z, elapsed 354 ms, exit 0. `Ran 14 tests in 0.288s` OK. Logs: `logs/distribution-install-ext4.stdout` (empty) and `logs/distribution-install-ext4.stderr`. The other distribution tests had already passed on tmpfs, so the 10 failures are the install-prefix cases.

No source fix is proposed for `install.py:697-698`. A later test-harness assignment can give `test_install.py` an ext4 temporary root, or an explicit skip when the default temp filesystem is not ext4, so a tmpfs `/tmp` is reported as a precondition skip. That assignment is optional and was not done.

## S1 review list

Review these paths for the post-rc.5 candidate. Line numbers are HEAD.

| Path | Why |
| --- | --- |
| `tools/distribution/qualification.py:74-112` | Warning-prefixed diagnostic parser. |
| `tools/distribution/test_qualification.py` | New parser tests. Passed. |
| `tools/distribution/refresh_identity.py:139-149` | Catalog product copied into component locks. |
| `tools/distribution/test_refresh_identity.py` | Propagation test. Passed. |
| `distribution/reference-node/dependency-lock.json:62-66` | New Batteries carrier. Same bytes in the WSL2 lock. |
| Both profiles' fixture manifests and cache indexes | Regenerated with the pin and again with `f0daef9` selection hashes. |
| `catalog/framework-catalog.json`, `catalog/framework-catalog.compact.json`, `catalog/framework-catalog-wsl2-26.04.json`, `catalog/components/mirrors.json` | Selection and component revisions do not name HEAD or the local companion checkouts. |
| `distribution/reference-node/component-lock.json` and `distribution/reference-node-wsl2-26.04/component-lock.json` | Same revisions and products. |
| `distribution/reference-node/profiles.json` and the WSL2 `profiles.json` | Catalog selection refs moved in `f0daef9`. |
| `Docs/framework-map.md:81-83` | Generated table of those revisions. |
| `.gitignore:24` | Editor-cache exclusion. |
| `Docs/current-status.md:1-14`, `Plans/execution-decisions.md:9-21`, committed `CHECKPOINTS.md:19-28` and `:60` | Status drift. |
| `Shell/Version.lean:6` versus `catalog/components/mirrors.json:94` | `0.2.0-rc.5` versus `0.1.1`. |

`72d83b0` also adds `Plans/batteries-bundle-repin-evidence-20261031/` and `Plans/completion-rc5-evidence-20261031/`. Those are retained evidence for the historical pin and rc.5 packages. They are part of the commit identity. They are not the runtime diff a reviewer has to re-derive.

### Proposed later edits

Do not apply these in this job.

1. Refresh catalog, both component locks, both profile selection refs, dependent fixtures, and `Docs/framework-map.md` from the freeze commit after the companion revisions actually exist in the checkouts that will be bound. The current catalog names objects this workspace does not have.
2. Update `Docs/current-status.md` and `Plans/execution-decisions.md` so the current continuation names `72d83b0`, `bd5d3b5`, `f0daef9`, and `75fbf96`. Codex can add a checkpoint entry that the 2026-10-31 "no commit was performed" wording is historical.
3. Resolve Mirrors `0.1.1` in the catalog against `0.2.0-rc.5` in `Shell/Version.lean` before any package tag is chosen. Leave tag `v0.2.0-rc.5` on `3ee3d92`.
4. Optional: ext4 temporary root or explicit skip in `tools/distribution/test_install.py`.

## S2 preparation

No commit and no push. Cached `origin/main` already names `75fbf96`. Republishing that unchanged commit would not advance S2. Any MW-12 edit creates a new commit and a new publication candidate.

### Exclusions until a reviewed scope says otherwise

- Uncommitted `CHECKPOINTS.md` delta.
- Untracked `Plans/completion-*` trees and execution-order notes.
- `Plans/mainwork-stages-2026-11-03.md` and `Plans/mainwork-execution-20261103/` except a later explicit decision to add reviewed files. This `source/` directory is review input, not an authorized commit.
- Other jobs' `admission/` and `handoff/` outputs.
- `.projectile-cache.eld`, `.lake/`, `__pycache__/`, PKI, credentials, private keys, tool archives, and compiled binaries.
- Companion working trees. They are separate repositories. MirrorECMA's two untracked pnpm state files stay untracked.

A future delivery list has to be regenerated after MW-12. The file list above is the review scope, not a staged index. The index was empty at observation.

### Final gates still required before S1 can pass

Run from the repository root after the freeze commit exists. This job did not run the build gates.

1. `git diff --check` on the delivery diff. Already run once on the current worktree; rerun on the freeze diff.
2. The three Python discovers in this report. For the distribution discover, set `TMPDIR` to an ext4 directory on this host, or the install tests fail before their assertions.
3. `bash tools/run-local-no-model-check.sh`. This builds with Lake and runs the non-model aggregate, including distribution and evidence discovers. It does not run the release unit suite. It excludes `lake test`, `tools/check-async-protocol.py` (TLC), and live Apalache. Needs the existing full-build approval.
4. `bash tools/check-native-rebuild.sh`. Native rebuild gate. Needs build approval. Not run.
5. `Plans/completion-evidence-20261029/verify.py` checks the October 29 campaign record. It is not a gate for HEAD.

S3, after a new tag and MW-20, still needs `python3 -m unittest discover -s tools/release -p 'test_*.py' -v` (already green at this HEAD, to be rerun on the freeze commit) and `tools/release/release.py` `build` / `check-archive` in a clean checkout. Those package commands were not run.

### Remote observation recipe

Do not update refs. `git fetch` is a remote-tracking ref update and is not the recipe. Run:

```sh
git ls-remote https://github.com/NzSN/Mirrors.git refs/heads/main
```

Compare that full SHA with the reviewed candidate commit. Record, without mutating, `git rev-parse HEAD`, `git rev-parse 'HEAD^{tree}'`, and `git status --porcelain=v1`. If the remote SHA is already the reviewed commit and the reviewed tree is clean, stop. A second push of the same commit does not complete S2. If MW-12 adds a commit, publish only the reviewed list and run `git ls-remote` again against the new SHA.

This job did not run `git ls-remote`. No current remote SHA is claimed.

## Evidence limits

- Focused Python results are not the local non-model aggregate, native rebuild, package smoke, installed D audits, or Q.
- Distribution discover on the default temp filesystem exited 1. The install module passed when `TMPDIR` was ext4. The full 61-test discover was not repeated on ext4; the other tests had already passed in the required run.
- Companion catalog SHAs were not fetched. Local absence is not a proof that GitHub lacks those objects.
- No model checker, no network model run, and no remote service contact.
- `CHECKPOINTS.md` and untracked plans can still change under other jobs. Hashes in `logs/identity-before.json` are the 02:00:38Z snapshot.
- No credential or private-key bytes were written.

## Next executable action

Codex MW-11: recompute the SHA-256s in `inventory.json`, read `logs/distribution-unit.stderr` and `logs/distribution-install-ext4.stderr`, and confirm the exit 1 is the tmpfs precondition. Then either accept the catalog and status findings for a file-scoped MW-12 assignment, or record corrections in `review.md`. Do not freeze, tag, package, or push from this report.
