# Batteries Git-managed location preparation — 2026-11-04

The user selected `third_party/batteries/batteries-v4.33.0.bundle` as the
Git-managed location for the exact locked offline carrier. The builder now
defaults to that checkout-relative location and retains the explicit
`--batteries-bundle` override. Every selection still requires the selected
dependency lock's byte length and SHA-256. Admission now occurs before staging;
the existing immediate-before-clone hash check remains in place.

The directory contains the pinned checksum, upstream license and source/carrier
provenance, plus `*.bundle binary` Git attributes to prevent newline conversion.
The license is copied byte-for-byte from Batteries commit
`4488d40d070b9700d4d5a6aa342f0d40c31b2a2d`. The canonical bundle path is not
ignored by Git. **The bundle itself is still missing and has not been added to
Git.** No placeholder, superseded carrier or regenerated bundle is substituted.
Both dependency locks and their exact checksum remain unchanged.

A bounded filename/hash-name search across `/home/lsz/Codebase`,
`/home/lsz/Workspaces`, `/mnt/c/Users/lsz/Downloads`, and `/mnt/d/Knowledges`
finds no exact carrier filename/hash-name candidate beyond the already known
older bundle and unrelated Git backups. The prior S5-A exact-size search is
retained separately. The canonical-path input admission exits 2 with
`cacheBuildReady:false`; no real cache build or installation is run.

## Validation

`python3 -m unittest discover -s tools/distribution -p 'test_*.py' -v`
passes **72 tests** on an ext4-backed task `TMPDIR`. Four new regression cases
exercise missing canonical bytes without ambient/cache fallback, same-size
wrong-hash refusal before staging, checkout-relative resolution from another
working directory, and explicit override acceptance/refusal. They reach actual
builder input gates without compilation or model operations. The existing
Lake/local distribution gate discovers them automatically.

The first run had two new-test expectation failures: the valid-carrier tests
reached the independent missing-source gate before the missing-Node gate.
Their assertions were corrected to that actual stage; product code was not
changed for those failures. Both logs are retained. Final checks confirm clean
diff whitespace, unchanged dependency locks, upstream license byte identity,
non-ignored canonical path, and unset Git text/diff/merge attributes for the
binary bundle.

Raw search, admission and test receipts are retained under ignored
`.golden-build/batteries-vendoring-20261104/`; `result.json` binds their hashes
and the changed source/metadata. Earlier freeze and S5-A records are unchanged.

## Continuation

Restore the exact 3,739,542-byte carrier
`73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a`
to the canonical path and verify its Git revision/tree and checksum before
adding the actual file to Git. The builder/default change and future vendor
addition require a new source/candidate freeze; do not run the changed builder
against the earlier immutable snapshot or transfer prior S3/D/M5/Q credit.
The old [S5-A recipe](../mainwork-s5a-rc6-20261104/resume.md) is historical
until its source/snapshot bindings are renewed. No long/full build, dependency
re-pin, commit/push, tag, release, remote operation or deployment is performed.
