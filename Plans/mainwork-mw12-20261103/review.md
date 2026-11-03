# Codex review — MW-12 source candidate

Status: **source preparation accepted after corrections; final S1 gate pending**.
The current working tree prepares `0.2.0-rc.6`. HEAD remains `75fbf96`; no new
commit, tag, release archive, deployment or reboot occurred. This is a dirty
source candidate, not an immutable clean/tagged release freeze.

## Source and input changes accepted

- Catalog refresh derives Mirrors' product version from its selected source's
  `Shell/Version.lean` before catalog writes/selection. Missing, malformed and
  ambiguous declarations are refused. Other products and skip semantics remain.
- Existing CLI smoke coverage now uses `Shell.Version.version`; the targeted
  `mirror`, `stdio_smoke`, `framework_catalog` build and real stdio smoke pass.
  The rebuilt mirror prints `v0.2.0-rc.6`.
- Exact selected MirrorECMA `9192171` and MirrorGate `4b379ac` refs were fetched
  into clean isolated copies. Older shared checkouts were preserved. Remote
  main was observed at `75fbf96`; no rc.6 tag was returned at that observation.
- The ECMA runtime was rebuilt from the selected Git revision with the pinned
  Node 24.15.0 and TypeScript 5.9.3. Active SDK pin and registry ECMA_REF agree.
  This is runtime preparation, not a fresh remote five-client result.
- The signed Ubuntu index/package chain for strace and libunwind was checked
  independently. An owner-controlled launcher checks its native/library hashes
  and invokes the loader without exporting LD_LIBRARY_PATH to traced children.
  `--version` passes; actual tracing is denied by this Codex context's ptrace
  policy. No tracer/namespace or D-audit admission is credited.
- Only the two D prefixes/tool/hash/hide-root values and interop ECMA_REF were
  changed in the registry. Lengths, output/adapter contracts and other pins stay
  intact. Both catalog variants/locks/fixtures were regenerated, and Mirrors'
  product-version source record was added. Dependency lock bytes are unchanged.

## Review findings and corrections

The first Grok source patch read the running tool's HERE tree even when MIRRORS
selected another source. Codex's independent probe selected `0.0.9` but observed
`0.2.0-rc.6`. Grok corrected the default to MIRRORS, replaced the test asserting
the wrong behavior and completed the planning-doc fixture with its own version
declaration. The independent probe now observes `0.0.9`. Original failing and
passing receipts are both retained; source/ was not rewritten by the correction.

The initial binding job exhausted its turn limit without edits. Its stopped
attempt is retained. The resumed execution ran the concrete integration harness.
That harness initially asserted byte stability before generated-output exclusion
membership had settled. The assertion failure is retained as exit 1; the worker
reported it and separately verified stable follow-up refreshes. Codex corrected
the harness to require two consecutive matching results, bounded to four pairs.
The independent complete run of that corrected harness passed and left the
catalog selections unchanged. See `integration/binding-idempotence-final.json`
and `review/idempotence/reviewer-final-assertions.json`.

## Exact candidate and validation

| Item | Retained identity/result |
| --- | --- |
| HEAD | `75fbf962020cea8a13e009ecfdb3e912e7ce212f` |
| Dirty source digest | `59be0488dc9b32c086ac0b66e05459197fe9209e410ceeb47a87cf26f55ba80a` |
| Selected WSL2 C0 | `22596af73d943b2204a2ae3c7bbc39ae9c41ff03442507e0f26b183ac503a88c` |
| Base C0, structural control only | `ad9d28ae4b3b4eb2a662117b411fc8acc82e24cc82a04d8dfe6e770289c610bc` |
| Distribution Python | 68 passed after corrected source and binding integration |
| Durable evidence Python | 146 passed after binding integration |
| Release Python | 11 passed independently |
| Targeted Lean build / CLI | passed; version and real stdio smoke passed |

Thus 225 focused Python tests pass, plus the targeted Lean/CLI checks. The full
local no-model aggregate did not run: the previous plan left long/full-build
approval open, and the question presented this turn has no answer yet. No native
dependency graph changed, and no full native-rebuild acceptance is claimed.

Grok's source, correction, acquisition and binding inventories contain 53 records
(45 evidence files and eight ignored input-artifact files). Codex verified those
bytes/hashes, exact companion trees/clean state, the active runtime pin, lock
structure/source refs, narrow registry changes and actual command receipts.
The previous preparation's 116 inventoried files remain unchanged.

## Remaining gates

- Complete the approved full local no-model gate before final S1 source freeze.
- Restore exact Batteries carrier `73130433…`, 3,739,542 bytes. Known local-store
  searches did not find it; no replacement/re-pin or invented availability.
- Admit the actual execution context for ptrace/namespaces and both D audits.
  Preparing a tracer does not remove those permission gates.
- Obtain fresh remote/TLS/backend/client/Windows inputs; then execute the
  downstream installed/M5/Q/Windows stages at the immutable delivered candidate.
- Branch/tag/publication/production operations retain their concrete later
  boundaries. Older rc.5 tags/packages and dated qualification are unchanged.

The first two pending questions are already presented asynchronously; no elapsed
time is treated as an answer. Full framework/release qualification is unclaimed.
