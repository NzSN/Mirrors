# Confined Windows Workspace trace transfer

2026-10-01 implementation decision for the approved Windows remote campaign.
The native 0.62.2 / Java 25.0.4+7 server passed pinned mTLS HourClock validation.
The first WriteSentry lifecycle trace requires 229,159 compact reply bytes;
the existing 65,535-byte framing limit correctly rejects inline delivery.
The failed attempt remains diagnostic and qualifies no fresh corpus.

## Contract

Use the existing synchronous `destPath` and durable path-only reply, with an
explicit shared-filesystem deployment grant. No wire schema or framing bound
changes. Ordinary TCP/TLS servers and clients retain their existing behavior.

- The mTLS server accepts `--shared-trace-root DIR` only together with an exact
  client-fingerprint allowlist. Only an allowlisted peer gets shared delivery.
  The root must exist and have ordinary, non-symlink ancestors. Each requested
  destination must be one new `capture-...` directory directly under that root;
  reserve it atomically before generation. Existing or escaping paths fail.
- `mirror trace-gen` accepts paired `--shared-server-root` and
  `--shared-local-root` options. Require direct pinned mTLS and synchronous mode.
  Resolve an ordinary local root before contact and create a fresh destination
  name. Send that exact server destination with the inline source closure.
- A path-only success can be read only under the exact requested destination.
  Normalize server path separators, reject traversal, duplicate paths and
  non-ITF filenames, and map one filename into the declared local root. Refuse
  symlink prefixes and nonregular files. Read each file with the existing
  16 MiB artifact bound, a 64 MiB aggregate bound, strict JSON and ITF validation.
  Retain the original-file hashes and declared transfer mapping in the receipt.
- Counterexamples and artifact files have separate counts. Apalache 0.62.2
  observed here emits equal state sequences with distinct description timestamps
  in its numbered and unnumbered files. Preserve both under the existing
  64-artifact cap and report distinct per-scenario state sequences separately
  from all actually replayed snapshots.
- Failed capture publishes no local output. Server-owned durable artifacts are
  retained for diagnosis; client cleanup never deletes them. Async trace jobs
  retain their existing inline-only contract.

The Windows root is confined to
`C:\Users\ayden\Desktop\Workspace\MirrorsRemote\trace-artifacts`; its local
mapping is `/mnt/c/Users/ayden/Desktop/Workspace/MirrorsRemote/trace-artifacts`.
Generation must still be acknowledged by the pinned mTLS endpoint. Merely
opening a file or replaying a historical shared corpus is not fresh evidence.

## Verification

Exercise paired-option admission; pinned-TLS/synchronous prerequisites;
unconfigured/default path-only refusal; direct-child reservation; existing and
escaping destinations; response traversal/duplicates; symlink/nonregular and
oversized artifacts; strict JSON failures; original metadata and hash retention;
and an actual large result from the native Windows server. Rebuild and observe
the changed server before the full fresh campaign. Record both deployment
identities and retain the first failed campaign separately.
