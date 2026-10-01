# WriteSentry remote oracle capture

Implementation design, 2026-10-01. This continues the approved WriteSentry
compiler plan. Fresh qualification requires operator-supplied credentials and
a same-time observation of the deployed backend; implementing the client does
not establish those facts.

Windows deployment addendum, 2026-10-01: the user selected the current Windows
host and Apalache 0.62.2. Its fixed campaign endpoint is `172.20.208.1:8999`,
with Microsoft Java 25.0.4+7-LTS. A real lifecycle result exceeded the frozen
wire limit. The explicitly configured, allowlisted shared-artifact mode in
[the confined transfer contract](windows-shared-trace-transfer.md) is therefore
available for that campaign. The inline-only path below remains the default;
the original 0.61.0 frontend reference evidence and older endpoint observations
retain their historical identities.

## Decision and boundary

Add `mirror trace-gen` as a remote client of the existing `register_trace_gen`
and optional async job protocol. Reuse source-closure capture, TCP/mTLS/registry
transports, request codecs, and the 65,535-byte framing limit. The command sends
the captured source closure inline and never launches a local model checker.
No wire-schema or deployed-service change is required.

The command accepts validation's connection/model options and `--out DIR`,
`--num-traces N`, `--view NAME`, and `--param-var NAME`. `--async` keeps the
submitting connection alive and awaits the exact accepted `gen_traces` job.
Retry only pending/running statuses, with a finite poll budget. Wrong job IDs,
wrong result kinds, unknown/cancelled jobs, malformed replies, backend failures,
and exhausted polling fail explicitly. Cancellation is attempted after an
owned async job fails locally.

The output directory must be absent and its parent must exist. Before connecting,
reject existing outputs, missing source dependencies, and oversized requests.
After receiving a valid result, reserve the directory atomically and publish
only controlled filenames: `trace-N.itf.json`, `request.json`, `replies.json`,
`sources.json`, and `capture.json`. Preserve the raw JSON trace values returned
by the server instead of decoding/re-encoding their ITF metadata. Validate each
trace through the existing decoder. Partial publication cleans only files this
invocation created; it never replaces or recursively removes consumer data.

Require nonempty inline ITF traces. Server-side `itfTracePaths` are retained as
receipt data and never opened as local paths. A path-only reply or
`TRACE_RESULT_TOO_LARGE` fails. Each WriteSentry scenario requests one bounded
trace, so the existing remote protocol suffices when that complete reply fits.
If a fresh trace exceeds the wire limit, that scenario remains incomplete; do
not introduce a silent shared-filesystem assumption or weaken the limit.

The receipt records captured request/reply/source and trace hashes, endpoint,
transport, pin when supplied, compiler/client binary identity at campaign
level, and any async correlation. Credential contents and private key paths
do not enter receipts. Service/toolchain declarations belong to the separate
operator-observation document, which the qualification wrapper validates
against selected pins before remote contact.

## Application campaign

WriteSentry emits its fourteen existing scenario modules and plans from the
independent runner. A separate remote generator invokes the Mirrors CLI for
each source closure, retrieves and retains its result, normalizes only constant
fields/parameter metadata, and runs original-table native plus local stdio
comparison. It recounts states/actions/flags and requires both overlap
directions and all three actual server `step_mismatch` controls. Corpus
publication retains origin capture references and explicit fresh-oracle status.

New corpus qualification must not inherit the historical 212-state total.
Backend identity, component refs/dirty manifests, local binaries, and all
command results are separate recorded identities.

## Acceptance

- Actual CLI against loopback protocol fixtures: source closure, synchronous
  and async success, exact returned ITF metadata, correlation/failure matrix,
  no path-only success, no local publication on invalid replies, and existing
  output preservation.
- Existing remote validation and frozen wire gates remain green.
- Actual WriteSentry checkout uses original observations and generated helpers;
  source-only/recorded acceptance remains distinct from fresh remote evidence.
- Fresh campaign against `192.168.150.219:8999` only after private credentials
  and selected same-time backend observation are available. The CLI implementation
  and loopback fixtures do not satisfy that final clause.
