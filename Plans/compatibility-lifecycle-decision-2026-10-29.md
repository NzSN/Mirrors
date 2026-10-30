# Compatibility lifecycle decision

The current supported stdio contract retains `register_error` for async
registration and job-control requests. A client must choose `--serve`/`--server`
for async operations. Do not infer protocol capability from a version number or
human-readable error text. A future harmonized tag requires an explicit new
compatibility decision and migrated consumer evidence.

Read-only source inventory finds the owning branch in
`Shell/Mirror/Session.lean`, current client rules C4/C5 in
`Docs/client-implementation-guide.md`, the wire table in
`Docs/interface-reference.md`, codec goldens and five-client runner/CI inclusion
of the Haskell oracle. Current ECMA/CPP/Rust/Lean SDK identities are recorded in
the completion evidence. No public consumer telemetry is available, so source
inspection cannot claim there are no external dependents. A fresh five-request
native-CLI probe checks exact current stdio responses without a backend.

Keep the pinned Haskell implementation, frozen fixture generator and CI oracle.
No retirement/removal occurs in this candidate. Deprecation admission requires:

1. A named inventory of supported consumers, maintainers, selected releases and
   required operation/transport rows, plus an explicit unknown-consumer policy.
2. Two consecutive shipped release cycles with retained independent green
   compatibility matrices for each declared row, including the Rust leg and
   async error-tag controls. Required skips or an unobserved row reset admission.
3. A dated real-workload soak ledger for both implementations: workload hashes,
   run counts, byte comparisons, known accepted differences, failures, incident
   reports and resolutions. Calendar time without executions earns no credit.
4. Zero unresolved wire-divergence reports in those cycles; named consumer
   migration acknowledgements and verified fallback/rollback exercises.
5. A reviewed deprecation notice and migration instructions before removal,
   followed by a separately approved compatibility release and fresh goldens/
   matrix. Retain the historical oracle/artifacts for audit even after runtime
   support retires.

No cycle or soak credit is granted by this decision. It closes the design
choice while leaving the measured retirement prerequisites open.
