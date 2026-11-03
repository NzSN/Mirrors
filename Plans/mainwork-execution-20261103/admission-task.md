# Grok admission and distribution task

Goal: execute MW-50/MW-51/MW-52 in
`Plans/mainwork-stages-2026-11-03.md` and produce an actionable exact-candidate
admission dossier. This task performs bounded local preflight and command
development, not final S5 qualification.

Read root AGENTS.md, the stage plan, Docs/qualification-harness-design.md,
Docs/reference-distribution-profile.md, Docs/model-interface-runtime-distribution-design.md,
distribution/reference-node/activation-transaction.md, Docs/remote-server-guide.md
and tools/interop/INTEROP.md. Read tool parser/source contracts before preparing
invocations. Current source is `75fbf962020cea8a13e009ecfdb3e912e7ce212f`.

Ownership: new files only in
`Plans/mainwork-execution-20261103/admission/` and task-owned temporary roots.
You are not alone in the checkout; preserve others' work. No edits to source,
catalogs, locks, shared dependencies, central ledger, CHECKPOINTS.md or other
job outputs. Read companion repositories only.

Execute:

1. Reobserve actual local OS/kernel/WSL/libc/filesystem, tool paths and versions,
   and relevant non-destructive loopback/UNIX-socket/ptrace/bwrap prerequisites.
   A denied probe is environmental evidence, never a pass or host relabeling.
   Do not start any model checker. Do not dump the environment or credentials.
2. Validate both distribution lock roots using current library APIs without
   changing their bytes. Check the retained Batteries carrier size/hash and,
   if available, verify its Git bundle/source identity in an isolated temporary
   clone. Missing or changed bytes remain a concrete blocker. Never replace
   pins or regenerate historical fixtures.
3. Derive runnable C0/lock-refresh, cache-build, install and two D-audit command
   recipes from actual parsers and the selected profile. Show argument binding,
   required input origin and output paths; explicitly mark unresolved inputs.
   Use a separate proposed candidate root, never checked-in catalog mutation.
   Do not execute final builds/install/D audits before S1–S3 dependencies.
4. Identify exact fresh remote/TLS/backend, five-client and full Windows
   admission prerequisites, read-only observation commands and responsible
   operator inputs. No SSH, remote contact, credential read/export or backend
   lifecycle changes in this readiness task. Historical endpoints are not live
   observations. Base/24.04 and additive 26.04 profiles must stay distinct.
5. Write `report.md`, `commands.md`, `result.json` with actual observations,
   raw-log command records and task dispositions, and `inventory.json` with
   bytes/SHA-256 for generated files (excluding itself). Avoid self-references.

Constraints: no source changes, full build, `lake test`, local Apalache/TLC,
network downloads, package/host installation, git mutations, publication,
production operations or reboot. Probe bounded local capabilities only; report
permission denials. Respect writable roots and preserve old evidence.

Done when Codex can inspect every observation and resolve each recipe argument
to a known value or named missing input. Readiness does not pass either D audit
or grant M5/Q/Windows/platform qualification. Return paths and precise blockers.
