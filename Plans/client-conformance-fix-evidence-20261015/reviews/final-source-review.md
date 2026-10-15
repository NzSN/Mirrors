# Final bounded source/evidence review — 2026-10-15

**Verdict: no new confirmed material finding in the requested final-delta scope.**
This review read sources, diffs, journals, hashes and retained results only. It
ran no implementation, build, test or remote probe and changed only this file.

The Gate portion is explicitly a **self-check**: this reviewer authored those
tests and performed their remote execution. Independent review here covers the
Python portability and Lean layout deltas plus leaf-report consistency. The
earlier independent [R1](source-review-1.md), [R2](source-review-2.md) and
[H2 review](../remote/haskell-h2/source-review-h2.md) retain their own scope.

## Delta and identity checks

Composing [reviewed-changes.json](../reviewed-changes.json) with all six entries
in [applied-updates.jsonl](../applied-updates.jsonl) gives 61 distinct applied
paths. Every current file matches its latest recorded hash; available old/new
hash chains are consistent. The R2 inventory differs only in the three logged
Gate test/document files and five separately reviewed H2 files. Its Gate SDK,
facade production and MirrorCPP production bytes are unchanged. The six changed
Mirrors production files also match the initial ready-source snapshot. No
unreviewed production delta was found within these task-bound inventories.

The two compiler corrections preserve their assertions: MirrorLean's
`test/Main.lean` only moves the unchanged error predicate into a properly
indented match branch; `tools/TransportSpec.lean` only lays out the same
fd/buf/rbuf record fields on separate lines. Neither adds a skip or weakens a
negative expectation.

## Independent Python portability review

Compared with the retained R1 source snapshot, `tools/check-client-framing.py`
changes only detached-socket closure and linger packing, plus explanatory
comments. `socket.close(connection.detach())` uses the socket-specific close
API that supports Windows socket handles. [Python socket documentation](https://docs.python.org/3.12/library/socket.html#socket.close).
The Windows `hh` layout supplies the two short fields required by Winsock;
the fixed values 1/0 have the same representation as the documented unsigned
fields, while POSIX keeps its previous `ii` layout. [Microsoft LINGER documentation](https://learn.microsoft.com/en-us/windows/win32/api/winsock/ns-winsock-linger).

Registration checks, TLS 1.3/mutual authentication, subprocess/peer bounds,
expected exits, no-VALID/no-capture checks and thread/connection cleanup remain
unchanged. The final retained Linux framing run names this exact script hash
and immutable binary, and ends `CLIENT FRAMING CLI GREEN`. This supports the
recorded WSL result; it grants no native Windows execution credit.

## Gate self-check and report consistency

The cleanup exception applies only to intentional `error-cleanup`: it still
requires a public failure, no body snapshot, the original APPLICATION cleanup
snapshot, confirmed control shutdown and attached sibling survival. Other rows
retain strict successful-cleanup assertions. Evidence records failed cleanup
as failed. The optional persistent build directory retains normal source and
compiler checks, bounded jobs and a trap that removes only its owned scratch.

The two exact wrong-ID scenarios assert the observed SDK origin,
CONTROL_DISCONNECTED code, empty original stage, zero operation ID, correct
invoke/observe context and matching public code. The injected fault is separate
from `primaryFailure`; neither text nor exit status invents a broker cause.
This matches SO7's literal combined worker transport/protocol family and plan
section C1. Direct SDK protocol expectations are unchanged; no new broker,
control schema or SDK production channel was introduced.

Recounting the raw final JSONL yields 37 unique rows: 18 owned and 19 attached,
all 19 sibling checks true, two declared cleanup failures, four separately
labelled wrong-ID injections and confirmed shutdown on every row. The summary,
README, raw records, empty process receipt and no-work build log agree. They
retain the GCC12 override and exclude native Windows/macOS, hosted/GCC13 parity,
other Gate profiles and universal guide conformance. Historical failed/partial
attempts are distinguished from final acceptance. The immutable CLI hash also
matches the final Python framing/original-CLI control record.

## Observed final hashes

```text
fe2b77b8e24bdff58f9b08dc1b594174ce2b0ece765fab76a382e4fbc7df0dca  Mirrors/tools/check-client-framing.py
e13243a42f3ff5d7233fae9da22b5dcc57b4c13ff7dd6806010ee896408b65cc  Mirrors/tools/TransportSpec.lean
d4a02f94142d4007ed09a28827880b44e7e8376dd2bfb8cc21619f2f203c09f5  MirrorLean/test/Main.lean
5904003d28699b1b128254486cfb8c411c34ac829c515cd761366570795736be  MirrorGate/integrations/mirrorcpp/counter_driver.cpp
5b93a2d1cc19af783cafefaada1ef538f34d2d053a9bf84b4d6976057bfd2c1a  MirrorGate/conformance/control-v1/run-cpp-failures
19b56dd6a773b963868a2e1298d78970bc9e948dddce65265f89f48d1e4b1f1f  MirrorGate/integrations/mirrorcpp/README.md
5d2cb565c8d9dc51681171ae768a01d8e7cf2607402bfaaa1342cbd478e47d71  final 493-file CPP/Gate source manifest
031326f2e5626dd47ef3efe64f001a806bc404921e3fe1fc2b0c0b38d3536ed0  final 37-row JSONL evidence
6e06ecd3d4d2975a42db2a1822b2d28d9e382f6d5b9bf48fa36c6c9ce27fa77d  selected immutable Mirrors CLI
```
