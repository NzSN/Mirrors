# Six runtime source-review fixes — October 29, 2026

The user requested remediation of all six findings reproduced against Mirrors
`0cb5679a9e02d5e4a31c68b43b2b0f8b1abd02bb`. The fixes are in the working tree.
[Validation and source identities](validation.json) bind the reviewed files,
built executables, commands, outcomes and explicit exclusions.

## Changes and regressions

| Finding | Implemented correction | Regression evidence |
| --- | --- | --- |
| Shared HTTP receive storage corrupts concurrent responses | `Ffi.freshBuffer` supplies fresh native output storage. HTTP/TCP retain per-connection receive buffers; TLS allocates receive scratch inside its effectful receive action. Fingerprint, error and address helpers use the same allocation boundary. | Explorer tests exercise 512 synchronized requests across eight workers, alternating one-shot and keep-alive exchanges. The original 960-request probe returns zero wrong bodies and zero errors. |
| Async trace decoding silently removes malformed files | Both trace-generation paths require every file to be readable and decode before owned-directory cleanup. | Async invocation-seam tests cover complete valid results, malformed JSON, invalid encoded values and missing files, including resource cleanup. The original malformed-file probe now returns a terminal infrastructure error. |
| Explorer assertions do not fail the process | The executable returns status 1 for any failed assertion. | The suite invokes its deliberate assertion-failure subprocess and requires exit 1 and the expected diagnostic. |
| Oversized validation/infrastructure results break the owner connection | Every async outcome passes exact compact-envelope sizing. In-limit encodings stay unchanged; oversized diagnostics deliver `JOB_RESULT_TOO_LARGE` for the same ID. Trace results retain `TRACE_RESULT_TOO_LARGE`. | Both outcome families pass at 65,535, 65,536 and 70,000 final UTF-8 bytes, including multibyte and escaped content. Repeated query/await replies match and the runner executes once. |
| HTTP lengths count characters | Both request modes advertise UTF-8 byte counts. | The fixture consumes exactly the advertised bytes. Unicode round trips and a following keep-alive request pass. The original 13-character/15-byte probe declares 15 bytes and produces valid JSON. |
| Rejected TLS pins retain sockets | Successful client handshakes transfer their socket BIO to the SSL external. Opaque boxed handle types preserve native reference counting and finalizers; rejected pins send best-effort close-notify. Failed handshakes and accepted server sockets remain caller-owned. | Twelve rejected pins alternate with twelve successful echoes while descriptors stay 17 to 17. The original rejection-only probe stays 12 to 12. Native output confirms handle decrements, and all four type/instance definitions have no axioms. |

The boxed handle representation is necessary: enum-shaped placeholder types
allowed native compilation to omit reference decrements. BIO ownership alone
did not reclaim the live externals. Intermediate transport failures remain in
[the first candidate log](transport-initial.log) and
[the follow-up log](transport-followup.log); they are not credited as passes.

## Validation

- [Final complete local non-model aggregate](local-no-model-final.log): exit 0,
  `ALL LOCAL NON-MODEL GATES GREEN`.
- [Isolated native rebuild regression](native-rebuild.log): exit 0; C-only,
  header-only, compiler selection, OpenSSL overrides and no-op checks pass.
  The regression leaves the original shims unchanged.
- [Job-store](jobstore.log), [Apalache CLI](apalache-cli.log),
  [Explorer](explorer.log) and [transport](transport-final.log) suites pass.
- [Original reproduction probes after the fixes](original-reproductions-after-fix.log)
  pass their behavioral checks. The probe's final job-phase observation is
  taken after scripted EOF, when normal owner cleanup evicts the job. The new
  job-store regression checks repeated delivery before EOF directly.
- [TLS type axiom audit](tls-type-axioms.log): the opaque types and their
  nonempty instances depend on no axioms.

The first aggregate [failed](local-no-model-initial.log) at two standard-catalog
assertions because the ignored SANY cache contained `d15655ee…` while the
unchanged committed lock requires `fc6878c6…`. The exact locked artifact was
acquired with the bounded acquisition helpers, checked by size, SHA-256 and
standard-library digest, and installed after retaining the old cache separately.
[The cache receipt](sany-cache-restore.json) records both identities and the
backup path. No pin changed. The subsequent aggregate above passes; the
original failed receipt remains unchanged.

## Acceptance limits

No local Apalache or TLC model checking ran. The 78 offline differential checks
retain four live-reference skips. The optional native integer-map gate is
skipped because no `MIRRORCPP_PREFIX` was selected; explicit live-model tiers
self-skip. Windows execution, native M4 admission, remote model acceptance and
installed/framework/release qualification are not granted by these local checks.
No commit, push or deployment was performed.

[Receipt inventory](inventory.json) records retained sizes and SHA-256 hashes.
Temporary keys, generated PKI, probe binaries and build caches are excluded.
