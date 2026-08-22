# Golden wire fixtures (Phase 0 — fixture freeze)

Frozen JSON wire corpus generated from the **Haskell** ModelMirrors
implementation (external artifact, pinned by commit — see `metadata.json`).
This corpus is the byte-for-byte contract the Lean 4 port must satisfy
(design doc §5.2, §8 Phase 0). **Do not hand-edit**; regenerate with
`tools/fixtures/run.sh`.

## Files

| File | Contents |
| ---- | -------- |
| `client_messages.jsonl` | 24 raw wire lines covering all 19 `ClientMessage` constructors (plus `Maybe`-field variants: spec present/absent, timeout present/absent, hints present/absent). |
| `mirror_messages.jsonl` | 30 raw wire lines covering all 20 `MirrorMessage` constructors (plus variants: both `ValidateResult`s, all 6 `JobPhase`s, all 3 `JobOutcome`s, both `JobKind`s). |
| `explorer_transcripts.jsonl` | 9 recorded apalache explorer JSON-RPC exchanges: raw request bytes emitted by the Haskell `Apalache.Rpc.Client` for a full session (health, loadSpec, assumeTransition, nextStep, checkInvariant, query, assumeState, rollback, disposeSpec), each paired with the raw response served. |
| `manifest.json` | Per-line constructor/variant names for both message files. |
| `metadata.json` | Source repo, pinned commit, corpus shape. |

Payloads deliberately exercise every `Value` constructor (VInt/VBool/VStr/VSet/VSeq/VTuple/VRecord/VMap/VVariant/VUnserializable/VNull) and all 7 `DiffHint` constructors, so aeson quirks (#bigint strings, #set/#tup/#map wrappers, tag/value variants, Maybe omission, null vs absent) are frozen as data.

## Provenance

- Haskell source: ModelMirrors @ `349625134441a9263c10dee92a99d1be3d29483b` (read-only checkout at /home/nzsn/Repos/ModelMirrors); codecs = `Protocol.Format.Json` orphans, RPC layer = `Apalache.Rpc.Client`.
- Encoded with aeson 2.3.1.0 / GHC 9.14.1, compact encoding (no spaces), one JSON object per line — exactly the newline-delimited protocol bytes.
- Explorer transcripts were recorded by driving the real Haskell RPC client against a loopback mock server (in `tools/fixtures/GenGolden.hs`); the *request* bytes are genuine client output.

## Replay (Phase 0 exit criterion)

`tools/fixtures/ReplayGolden.hs` decodes every line with the Haskell FromJSON instances, re-encodes with ToJSON, and asserts:

1. re-encoded bytes == fixture line (no wire drift),
2. decode (encode m) == m (semantic round-trip),
3. every transcript request has well-formed JSON-RPC shape and every response parses as `JsonRpcResponse`.

Current status: **63/63 green** (24 client + 30 mirror + 9 transcripts).

Regenerate + replay-gate:

    tools/fixtures/run.sh

(The Lean codec work in Phase 2 consumes these files as its 100% round-trip acceptance target.)
