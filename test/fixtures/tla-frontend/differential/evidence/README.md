# Differential validation evidence — 2026-09-13

**Profile-3 differential acceptance: passed.** Historical profile-2 captures
below remain failed evidence; they are not rewritten or reinterpreted.

## Profile-3 differential closure (2026-09-14)

Checkpoints Q and R are independent required profile-3 runs after the approved
renewal of the seven narrow policy differences on both pinned references. Each
completed all 183 observations and reports 564 exact matches, 14 reviewed
differences, 292 explicitly unsupported surfaces, and zero unresolved findings.
Their normalized semantic payloads are byte-identical:
`b239480873912e7cabc79bde8266613b6aece19fb1acdede15afe9aca2459c11`.

- [Checkpoint Q summary](checkpoint-q-profile3-final-1-poststatus/summary.md),
  [report](checkpoint-q-profile3-final-1-poststatus/report.json), and
  [raw-artifact index](checkpoint-q-profile3-final-1-poststatus/artifact-index.json).
- [Checkpoint R summary](checkpoint-r-profile3-final-2-poststatus/summary.md),
  [report](checkpoint-r-profile3-final-2-poststatus/report.json), and
  [raw-artifact index](checkpoint-r-profile3-final-2-poststatus/artifact-index.json).
- The independently reviewed source/profile/tool/fact bindings are recorded in
  [the profile-3 renewal record](../../../../../Drafts/tla-junction-profile3-policy-renewals-phase1.md).

`lake build`, the 60-test offline suite, the five-test live reference suite,
and the full `lake test` aggregate passed using the pinned JDK 25.0.4+7 and an
absolute `APALACHE_MC` path. The aggregate's exact output is retained as
[`aggregate-lake-test.log`](checkpoint-q-profile3-final-1-poststatus/aggregate-lake-test.log);
it required loopback socket access
for the Apalache explorer server. Checkpoint N remains the reviewed baseline.
Checkpoint L is retained only as [quarantined historical evidence](checkpoint-l-profile3-baseline/QUARANTINED.md).

## Profile-2 junction closure (2026-09-13)

Checkpoints J and K are independent final profile-2 runs. Each completed all
180 observations (60 fixtures × 3 engines), recorded 540 exact matches, 14
approved profile-2 policy differences, 11 unresolved findings, and no
precedence exception. Their semantic payloads are byte-identical:
`5dd32f9003de7c09771dac69282be01a853fcf5dfd11c4302011b6bf3da3f354`.
The original mixed-junction disagreements are closed. Unicode, ENABLED
classification (Mirrors temporal; SANY state), and named-instance projections
remain unreviewed findings. Portable raw archives are indexed in each
checkpoint.

- [Checkpoint J summary](checkpoint-j/summary.md) and [report](checkpoint-j/report.json).
- [Checkpoint K summary](checkpoint-k/summary.md) and [report](checkpoint-k/report.json).
- [Renewal baseline](checkpoint-jp4-baseline/summary.md) and
  [independent approval](../../../../../Drafts/tla-junction-profile2-policy-renewals.md).

Both final reports record stable implementation hashes and no setup errors.
The coordinator verified all 639 raw-artifact hashes in each checkpoint and
the archive hashes. The JP0 matrix and supplement also retain indexed raw
archives. Build and aggregate Lake tests passed; the final offline suite passed
54 tests (four opt-in live tests skipped).

Commands for the final runs, from the repository root:

```sh
python3 tools/tla-differential/run.py --required --output .golden-build/tla-differential/jp4-profile2-final-1
python3 tools/tla-differential/run.py --required --output .golden-build/tla-differential/jp4-profile2-final-2
```

Each returned exit 1 because of the eleven unrelated findings.

## Historical profile-1 delivery

Final revision-1 runs:

- [Checkpoint H summary](checkpoint-h/summary.md) and [report](checkpoint-h/report.json).
- [Checkpoint I summary](checkpoint-i/summary.md) and [report](checkpoint-i/report.json).

Both runs have stable implementation/binary hashes, no setup errors, and all
171 observations completed (57 fixtures × Mirrors/SANY/Apalache). Mirrors agrees
with every manifest outcome: 32 accepted, 25 rejected. SANY and Apalache each
accept 39 and reject 18. Their parser evidence is correlated, not independent
implementations.

| Comparison disposition | Count |
| --- | ---: |
| Exact match | 510 |
| Narrowly reviewed difference | 14 |
| Unresolved failure | 13 |
| Unsupported comparison surface | 269 |
| Not applicable without mutually accepted graphs | 10 |

The normalized semantic payloads are byte-identical, SHA-256:

```text
e00451640aba6ca3c93fb836c2574cc7567dedee413151853536ddf41d156815
```

The 13 failures cover four causes: mixed-junction precedence (2 comparisons),
Unicode baseline rationale (2), ENABLED level classification (1), and missing
qualified named-instance operator/level projections (8). The seven documented
policy differences on both references were reviewed against
[checkpoint A](checkpoint-a/report.json) and approved only for their exact
fixture, source hashes, tools, and outcome field. See [triage](triage.md) and
[the registry](../differences.json). No unexpected difference was promoted.

## Commands and validation

From the repository root:

```sh
lake build
APALACHE_MC=.golden-build/tla-differential/toolchain/apalache-0.61.0/bin/apalache-mc lake test
python3 -m unittest discover -s tools/tla-differential/tests -q
DV_LIVE_REFERENCES=1 python3 tools/tla-differential/tests/test_references.py -v
python3 tools/tla-differential/run.py --required --output .golden-build/tla-differential/checkpoint-h
python3 tools/tla-differential/run.py --required --output .golden-build/tla-differential/checkpoint-i
```

The native build and aggregate Lake suite passed, including live Apalache and
permitted loopback/TCP/TLS tests. The final offline suite ran 51 tests: 47 passed
and four opt-in live tests were skipped. The separate live calibration suite
ran five tests with no skips. Additional real integer/boolean/string INSTANCE
actual calibration passed; [its inputs and observations](atomic-calibration.json)
are preserved. All 75 manifest branches have fixture coverage.

The required runner was also executed with Java absent from PATH, including
after the reviewed registry was installed. It retained all 171 rows and returned
`incomplete`, exit 2. Exact-match, malformed-fact, missing-row, wrong-origin/
arity/level, dropped-edge, stale/unused-review, process cleanup, changed-source,
and report-order negative controls pass. The final full runs return exit 1
because of the 13 findings, not because of unavailable tools.

The aggregate Lake run preceded the last required-mode registry fallback test;
the final 51-test Python suite and real missing-runtime invocation validate that
later change. Hosted GitHub Actions was configured but not executed here.
Validation logs and exit results are indexed by [validation.json](validation.json).

## Restoring and verifying artifacts

Each checkpoint contains a report, deterministic semantic payload, captured
source/harness snapshot, and `artifact-index.json`. Its `raw-evidence.tar.gz`
contains `fixtures/**`, including every raw artifact referenced by the report.
All archive entries were checked against the report's SHA-256 references before
packaging. Restore them within that checkpoint directory with:

```sh
tar -xzf raw-evidence.tar.gz
```

Host paths were sanitized for publication; original raw/report hashes and the
archiver hash are retained in report metadata. Sanitization was checked not to
change the semantic payload. `captured-inputs.json` preserves source bytes and
harness code, while tool/binary identities are in the report. Binaries are
identified by hashes rather than bundled; a different rebuild is a different
input identity. Each report describes its captured snapshot, even when a later
ledger update advances evidence links.

Earlier B/C runs preceded the final source-closure/validator fixes; D/E exposed
JVM performance-data collisions across process namespaces; F/G preceded the last
unavailable-tool registry correction. Those exploratory runs remain in ignored
local build output and are not the final acceptance evidence.

Atomic substitution values/spellings and instance sites are compared. Richer
resolved expression identity, external stage mappings, Apalache structural
normalization, lexical/CST equivalence, MirrorGate certification, and the real
application correct/faulty harness remain outside the established evidence.
