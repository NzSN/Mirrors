# Generic-executor S3 Windows rebuild handoff

Date: 2026-10-30

## Authority and scope

The user's S3 approval covers clean package construction with the local-only
`v0.2.0-rc.1` tag. The initial S3 record rejected the October 29 Windows ZIP
for binding to S2 because behavioral tooling and interop sources differ.

Execute the required Windows rebuild and packaging continuation of S3.7-S3.9.
Use the existing `win10` SSH host for an isolated source build only. No remote
tag push, GitHub release, registry publication, production service stop/start,
binary replacement, configuration change, or reboot is authorized.

## Inputs and preservation

- Source: local annotated tag `v0.2.0-rc.1`, peeled commit
  `d737aa0886b9d406e391955756922d9d735d7ec1`.
- Existing S3 record:
  `Plans/completion-s3-package-evidence-20261030/README.md`. Preserve its
  rejected Windows binding as an original result.
- Existing Windows packaging harness and receipts under
  `Plans/completion-evidence-20261029/` are reusable only after inspecting
  their exact inputs and commands.
- Use `ssh -F ~/.ssh/config win10` and a new task-owned staging directory.
  Reobserve Windows source/build tool identities. Never reset or modify an
  existing checkout or the production `ModelMirrors` service.
- Do not use historical PID, service health, certificate, or runtime
  observations as current evidence.

## Required execution

1. Create a source archive from the local tag, record its SHA-256, transfer it
   to a new win10 staging directory, and verify the transferred bytes and
   extracted commit identity. Use only the exact tagged source, with no overlay.
2. Reobserve the native Windows Lean/Lake, C compiler, OpenSSL, packaging tools,
   and any reused offline dependency identity. Preserve production binaries and
   configuration; record their current hashes read-only where practical.
3. Build the required binaries and run the eight existing non-model Windows
   gates: `fixtures_replay`, `diff_cross`, `model_interface_spec`,
   `stdio_smoke`, `transport_spec`, `jobstore_spec`, `async_resource_spec`, and
   `dpm_sync_spec`. Retain exact commands, exits, and any live-tier skips. Do
   not claim full `lake test` or production service qualification.
4. Package `ModelMirrors.exe`, `model_interface_gen.exe`, the required OpenSSL
   DLLs and `zlib1.dll`, and `BUILD.json` using the reviewed harness. Record
   source archive/commit, executable/DLL hashes, actual build tools and gates.
5. Transfer the candidate ZIP and public manifests to a new ignored
   `.golden-build/completion-20261030/dist-windows/` directory. Recheck the
   transferred hash, member set, embedded/external manifest equality, version,
   DLL closure, no-credential rule, and byte-identical repeat packaging of the
   same binaries.
6. Confirm the production service executable and configuration were not
   modified and no build/test descendant remains owned by this task.
7. Create a separate `Plans/completion-s3-windows-evidence-20261030/` record
   with README, machine-readable package receipt, bounded logs, inventory and
   offline verifier with missing/tampered controls. Do not rewrite the earlier
   S3 rejection record. Emit the final accepted Windows artifact identity or
   the precise failure/blocker.

This is a staged native build and eight-suite package result only. S3.6 Ubuntu
24.04 runtime acceptance, S4 native M4, S5 full Windows/framework
qualification, S6 release admission, and all public/production actions remain
outside this handoff.

