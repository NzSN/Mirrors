# Retention and compatibility ledger — MW-80 preparation

Status: templates only. MW-81 records observations later. This decision
and this file grant no shipped-cycle credit and no soak credit. Nothing
is retired. `register_error` stays. The pinned Haskell oracle, frozen
fixture generator, and CI oracle stay. No deprecation notice is approved.

`tools/release/compatibility/check.py` and `gate.py` are separate
composition tools (`--work`, and for `check.py` also `--node` and
`--cpp-prefix`). They are not this ledger and were not run.

Product version, wire schema, digest, and qualification records stay
independent. A later tag does not drop `register_error` or golden
bytes. `Docs/interface-reference.md` still documents
`{"proto_step":"register_error","error":"…"}` for registration and
submit failures. Required-verification failure does not fall back to
another tag.

## Public and private retention

Hashes and locations are unresolved. Do not invent them from October
receipts. Private evidence is owner-only. Public projections are
allowlisted metadata, not credential bytes or private graphs.

| Class | Object | Location | SHA-256 | State |
| --- | --- | --- | --- | --- |
| Public | Linux archive, manifest, `SHA256SUMS`, notes | unresolved | unresolved | not published |
| Public | Windows zip, if MW-72 selects it | unresolved | unresolved | not published |
| Public | Public run projections | unresolved | unresolved | not emitted |
| Private | Evidence store, Q envelopes, D manifests | unresolved | unresolved | not collected |
| Private | Rollback bytes and config snapshot | `ROLLBACK_DIR` | unresolved | not copied |
| Private | Credential paths | named in operations.md | absent | not recorded |

Access check, cleanup status, and post-deployment observation are
blank. Independent retention verification has not run.

## Two shipped cycles

Both cycles are `unexecuted`. A required skip or a missing declared row
resets admission. The consumer inventory is unresolved, so the four
labels below are the minimum named by the 2026-10-29 decision. They are
not a complete matrix and not passes.

| Cycle | Row | Result | Evidence SHA-256 |
| --- | --- | --- | --- |
| A | stdio `register_error` retained | unexecuted | unresolved |
| A | Haskell oracle and golden bytes | unexecuted | unresolved |
| A | Rust consumer row | unexecuted | unresolved |
| A | async error-tag controls | unexecuted | unresolved |
| B | stdio `register_error` retained | unexecuted | unresolved |
| B | Haskell oracle and golden bytes | unexecuted | unresolved |
| B | Rust consumer row | unexecuted | unresolved |
| B | async error-tag controls | unexecuted | unresolved |

Add further declared consumer and transport rows when the inventory
exists. Leave them `unexecuted` until MW-81 attaches receipts.
`CONSUMER_INVENTORY`, `CYCLE_A_RELEASE`, and `CYCLE_B_RELEASE` are
blocking and unknown. This candidate is not cycle A or cycle B.

## Real-workload soak

Design requires a dated ledger for both Lean and Haskell. Calendar time
earns nothing. Every measurement below is blank.

| Field | Lean | Haskell |
| --- | --- | --- |
| Workload id | unresolved | unresolved |
| Workload SHA-256 | unresolved | unresolved |
| Run count | unresolved | unresolved |
| Byte comparison | unresolved | unresolved |
| Accepted differences | unresolved | unresolved |
| Failures | unresolved | unresolved |
| Incidents and resolutions | unresolved | unresolved |

Soak credit: none.

## Acknowledgements, fallback, retirement

Acknowledgements are blank: consumer, maintainer, selected release,
transport rows, receipt, date. Status for every future row is
`unacknowledged`. Unknown consumers stay unknown. Source inspection
cannot claim there are no external dependents.

Fallback and rollback exercises are `not-run`. Fields: exercise id,
bytes restored, control exits, hash before and after.

Retirement stays `pending`. All of these are unmet: named consumer
inventory; two consecutive green shipped cycles with no required skip;
completed soak ledger; zero unresolved wire divergence; named
acknowledgements; tested fallback; a separate reviewed notice,
migration guide, compatibility release, and fresh goldens. Historical
oracle artifacts would remain even after a later removal. This
preparation does not propose that removal.
