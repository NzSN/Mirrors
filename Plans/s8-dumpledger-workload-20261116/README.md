# S8 DumpLedger workload source — 2026-11-16

The user identified the DumpLedger deployment on `win10` as the workload source
for the remaining Mirrors compatibility lifecycle. Read-only discovery is
complete. The user subsequently approved the exact three-input private processing/
export scope. The bounded real-engine replay and paired comparison now pass.
Private observations, event timestamps, hashes and full receipts remain under the
owner-only ignored artifact directory; this document records aggregate outcome
and scope only. Full workload-soak and shipped-cycle acceptance remain open.

The subsequent commit/push request authorizes publication of the replay recipes
and aggregate documentation. Private deployment/admission/approval JSON inputs
and all raw/derived workload evidence remain excluded by the local ignore policy.
The original processing receipts keep their dated publication flags; the new
`publication-scope.json` records this narrower metadata-publication authorization.

## Approved bounded result

The private approval input, [aggregate result](replay-summary.json) and
[lifecycle progress](lifecycle-progress.json) record the current outcome:

- Three distinct retained inputs, 5,889,824 bytes total, are rehashed before and
  after execution on win10. Their bytes stay in the host's vault/in-memory worker.
- Three fresh/closed in-memory engine sessions execute 18 recorded lifecycle
  transitions plus 12 normalized model-context setup commands, producing 21
  observed frames. Those are seven distinct modeled states repeated across three
  different inputs, not 21 distinct states or complete state-space coverage.
- The published Lean rc.12 binary and pinned Haskell reference each accept all
  three replay streams. Each successful pair has 16 byte-identical response
  frames. Both reject all three altered-observation controls. Only the declared
  C10 trailing terminal message differs in those controls; there is no unexplained
  wire divergence in this profile.
- The actual production inspector and generated observation/dispatch are used;
  expected state is neither read by the producer nor supplied as actual state.
  The existing finite harness's unmodeled grant-byte budget is set from the
  source record at the input adapter seam. Engine/generated files are unchanged.
- An 84-file compiled implementation hash index matches the producer's before/
  after digest. Source/model bytes and existing source overlays remain unchanged,
  backend health remains HTTP 200, all sessions close and native Job cleanup
  reports zero owned processes. The replay worker never opens the production
  ledger and does not mutate the service or its domain data.

Full private receipts are in `.golden-build/s8-dumpledger-workload-20261116/`:
`approved-replay-audit.json`, `observation-producer.json`, `implementation-index.json`,
`observations/`, `production-input-replay/` and `after-replay-observation.json`.
Exact request streams were independently reconstructed and matched to their
recorded SHA-256 values, then retained beside both raw receiver outputs. No raw
dump, key, identifying name, private state transcript or production-event timestamp
is copied into the versioned summary. Private workload evidence remains outside
the approved code/aggregate-metadata publication scope.

This result is an engine-level lifecycle slice under normalized finite IDs/time,
compared against an explicit prefix of reviewed expected evidence. It does not
exercise HTTP/auth, streaming byte admission, batch grants, other input classes,
case workflows/later actions, fresh model checking or historical/long-running soak.
The user-supplied source establishes production retention; independent customer
versus test-origin certification and named ownership/acknowledgements are not
inferred. Accepted complete compatibility cycles remain zero.

## Observed source

- Host: `win10` / `DESKTOP-6DKB5JD`; application `D:\Services\dump-ledger`,
  runtime `D:\Services\dump-ledger-runtime`. Backend/proxy loopback health return
  HTTP 200. This is availability observation only; the proxy health probe did not
  authenticate its HTTPS certificate.
- Deployed checkout base is `7d90dcbd…` with tracked overlays and one pre-existing
  diagnostic file. Actual compiled entry point, adapter and model bytes are
  measured in the private deployment intake; a clean deployed source
  revision or equivalence to the local `75b98a0` checkout is not inferred.
- A consistent read-only SQLite transaction at `2026-11-16T05:53:42Z` observed
  schema 11, 29 customers, 27 cases, 41 grants, 219 dumps and 1,740 audit events.
  Event timestamps span September 11–November 16 and include lifecycle acceptance/
  rejection, case transitions, downloads, symbols and analysis. The detailed
  inventory stays under the private local raw-artifact directory.
- Dump states: 204 available partial, 10 available full-memory-declared, one
  available unknown, and four rejected. No auth database, environment values,
  original customer/dump names, grant/webhook secret columns or dump bytes were
  exported by discovery. The original source/service/data remain untouched.

Production audit records are security/history records, not historical Mirrors
wire transcripts. DumpLedger's own `docs/formal-model.md` makes that distinction.
Runtime imports of MirrorECMA are in its MBT/adaptor layer; the live intake daemon
does not provide a retained Mirrors conversation merely because that layer exists.

## Prepared bounded workload

Selection examines existing vault inputs on the host, with a 4 KiB–8 MiB byte
bound, a one-shot consumed grant, a model-compatible initial case state and exact
ordered source lifecycle events. Hash/size checks authenticate the actual vault
bytes against the ledger. Names/titles are used only for excluding obvious test
markers and are not retained or returned; customer-real versus test origin is
not independently certified by that heuristic.

| Pseudonymous input | Bytes | Retained classification |
| --- | ---: | --- |
| `c95341bf4cb42031` | 1,886,624 | partial |
| `1a619a5600db6051` | 2,589,072 | partial |
| `c57ec0cde7b7e01a` | 1,414,128 | partial |

These are the three eligible entries among 204 partial rows: 194 fall outside
the declared one-shot profile and seven outside the byte bound. The workload is
a six-command slice: `IssueGrant`, `BeginUpload`, `SealUpload`, `PromoteObject`,
`MarkQuarantined`, `AcceptDump`. Other actions and later case histories are outside
this slice; the complete deployed corpus is not admitted by this selection.

The prepared producer uses the existing compiled real engine, generated port,
fresh in-memory SQLite instances and the production minidump inspector. It uses
the actual payload bytes on win10 and the recorded grant byte budget, normalizes
finite IDs/timestamps explicitly, supplies no expected previous state and never
reads an expected trace. The engine/generated modules remain unchanged. Only
pseudonymous modeled observations, event timestamps, hashes and receipts would
return to the private local `.golden-build/s8-dumpledger-workload-20261116/` folder.
Original dump bytes, keys, names and identifiers stay on the host.

## Comparison setup and authorization boundary

The local paired driver uses the actual published Lean rc.12 Linux binary at
source `6882d5b8…` and pinned Haskell binary at `4aa693f8…`. Its expected trace is
an explicit seven-state prefix of the existing reviewed DumpLedger corpus;
original fixtures are unchanged. Supplied-trace replay invokes no model backend.

A synthetic plumbing preflight passes: 16 success replies are byte-identical.
Both comparators reject the deliberately altered observation, with the already
documented C10 difference that Haskell appends `all_steps_done` after terminal
`step_mismatch`. The driver accounts for that exact tail and rejects unexplained
differences. This preflight supplied expected states as synthetic observations;
it is explicitly not real-input or SUT conformance evidence.

Automatic approval review initially rejected the attempted real-input producer because it
would process private production minidump bytes and export derived observations
without specific payload/destination authorization. The user was asked to approve
exactly the three aliases above and the private local destination. The operation
was not executed or retried through another route before approval. The subsequent
explicit approval is recorded in `processing-approved.json`; the producer and
actual-data comparison both require that file before use.

The first approved worker stopped before accessing selected inputs because the
deployed SDK did not export `encodeReportState`. Its Job cleaned up. A separate
v2 runner uses that SDK's existing `protocol.encodeState` and the ordinary report
envelope, preserving the original failure and keeping the engine/generated code
unchanged. Its real-input outcomes are retained separately from synthetic preflight.
Full workload soak,
two complete shipped compatibility cycles, HTTP/auth/streaming coverage, named
consumer ownership/acknowledgement and retirement receive no credit from source
discovery or this bounded setup.
