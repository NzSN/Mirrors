# Generic-executor S2 publication handoff

Date: 2026-10-30

## Authority and scope

The user approved the exact S1.7 question: commit and push the frozen 474-file
payload to `origin/main`, including the three reviewed public profile-6
`raw-evidence.tar.gz` archives.

This authorizes only S2.1-S2.4 in
[the completion execution plan](completion-qualification-release-plan-2026-10-30.md).
No local or remote tag, package build, release publication, production
deployment, service replacement, restart, or reboot is authorized.

## Frozen inputs

- Base: `7e9a27d0db72ec36b49c6fc5764b2687b565edfd`.
- Manifest: `Plans/completion-release-evidence-20261030/s2-delivery-payload.json`.
- Manifest SHA-256:
  `e01b565ef20b7b3ccb39c8493f6fd614ec1c2b3a9e883531e620cd56e762017b`.
- Payload: exactly 474 files. Every entry carries SHA-256 and expected Git blob
  SHA-1. The three raw-evidence archives are explicitly included.
- `Plans/completion-release-evidence-20261030/`, this handoff, editor caches,
  `.lake/`, `.golden-build/`, `tmp/`, `__pycache__/`, and all paths outside the
  manifest are excluded from the commit.

## Required execution

1. Verify the manifest's own hash and every current payload file's SHA-256 and
   computed Git blob SHA-1 before staging. Any mismatch stops S2 and requires a
   new S1 freeze; do not improvise a replacement payload.
2. Stage exactly the 474 manifest paths, using explicit force-add only where a
   reviewed evidence path is ignored. Do not stage this handoff or either
   completion execution evidence directory.
3. Verify the staged path set equals the manifest exactly and every staged blob
   ID equals its expected `gitBlobSha1`. Run `git diff --cached --check` and the
   staged credential/binary/archive audit. The three reviewed evidence
   archives are the only archive exceptions.
4. Commit with a concise scoped subject describing the controlled comparison,
   runtime/installer corrections, and qualification evidence. Do not amend an
   existing commit.
5. Push `HEAD` to `origin/main`. Reobserve the remote ref and fetch as needed;
   verify the full remote SHA equals the new local HEAD and there is no
   local/remote divergence for the published branch.
6. Record the commit/tree, remote URL/ref/SHA, staged-payload verification,
   credential scan, push result, and preserved exclusions in a new separate
   `Plans/completion-s2-publication-evidence-20261030/` record. That new record
   is not part of the approved commit.

Preserve all unrelated and post-freeze files. Do not reset, clean, rebase, or
checkout over the shared worktree. Report the exact commit and remote
verification, or stop with the precise mismatch/failure and leave a clear
state. Publication of `main` grants no tag, release, native M4, framework,
production, or reboot acceptance.

