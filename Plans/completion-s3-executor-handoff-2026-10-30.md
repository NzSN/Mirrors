# Generic-executor S3 package handoff

Date: 2026-10-30

## Authority and scope

The user approved the exact S3.1 question: create a local-only
`v0.2.0-rc.1` tag at `d737aa0886b9d406e391955756922d9d735d7ec1`
for S3 clean package construction.

Execute S3.1-S3.9 in
[the completion execution plan](completion-qualification-release-plan-2026-10-30.md)
under [the completion design](../Docs/completion-qualification-release-design.md).
No remote tag push, GitHub release, package-registry publication, production
deployment, service replacement, restart, or reboot is authorized.

## Frozen source and preservation rules

- Required commit: `d737aa0886b9d406e391955756922d9d735d7ec1`.
- Embedded version must remain `0.2.0-rc.1`.
- The main checkout is shared and contains untracked execution records and an
  unrelated editor cache. Do not reset, clean, rebase, checkout over, stage, or
  commit in that checkout.
- Use a new detached clean worktree under the ignored
  `.golden-build/completion-20261030/` root for release construction.
- If the local tag already exists, accept it only if it peels to the required
  commit; otherwise stop. Never move a tag. Do not push it.

## Required execution

1. Verify source/version/tag identity and create the annotated local tag if
   absent. Create the separate clean release checkout and require clean status.
2. Run `python3 -m unittest discover -s tools/release -p 'test_*.py' -v`.
3. Build through `tools/release/release.py build` into a new empty artifact
   directory. Retain actual host/toolchain/library identities and all focused
   non-model gate results. Do not run local Apalache or TLC.
4. Verify `SHA256SUMS`, embedded/external build manifests, tag/commit identity,
   executable versions, dynamic dependencies, archive paths/types, and absence
   of source or credentials. Run the archive smoke in an actual Ubuntu 24.04
   runtime without Lean or a source checkout, using the existing
   `release.py check-archive` path. If no admitted Ubuntu 24.04 runtime is
   available, record S3.6 as awaiting external input and do not claim runtime
   acceptance from Ubuntu 26.04.
5. For Windows, compare the October 29 base-plus-overlay build inputs with the
   frozen commit. Reuse the staged ZIP only if every executable/build input is
   identical and remaining differences are reviewed non-behavioral planning or
   evidence files. Otherwise record rebuild required; do not silently transfer
   the old archive.
6. Locate the retained Windows ZIP and repeat packaging only from the exact
   selected binaries. Recheck its SHA-256, executable/DLL hashes, expected
   version, archive membership, repeatability, and no-credential rule. This is
   not a reproducible-compilation or full Windows `lake test` claim.
7. Emit a versioned `package-set.json` and human-readable README in a new
   `Plans/completion-s3-package-evidence-20261030/` record. Bind each artifact
   to source/build inputs, runtime prerequisites, actual validation scope, and
   retention location. Include an independent inventory/verifier with missing
   and tampered negative controls.
8. Reobserve that no remote tag was created or pushed and that the shared
   checkout's pre-existing untracked files remain. Report completed, failed,
   and awaiting-external-input S3 rows precisely.

Do not broaden package construction into S4 native M4, S5 framework
qualification, S6 release admission, or any public/production operation.

