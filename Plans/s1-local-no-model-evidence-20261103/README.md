# MW-12 full local non-model validation — 2026-11-03

## Identity and result

The user explicitly approved the long/full build and requested the pending S1
local aggregate. The validated committed source was:

```text
25b62541ca443d5779fccc8d45fd90f64312747e
distribution: prepare rc.6 source and candidate bindings
```

The successful command, run from the repository root, was:

```bash
TMPDIR="$PWD/.golden-build/s1-local-no-model-20261103/tmp" \
  bash tools/run-local-no-model-check.sh
```

It exited zero and ended with `ALL LOCAL NON-MODEL GATES GREEN`. The build
completed 737 jobs. Distribution ran 68 tests, DPM 87, durable evidence 146 and
the offline TLA differential 81 with six documented skips; all executed tests
passed. No tracked source difference existed at completion.

This is the full local non-model gate, not a final candidate/C0 freeze or any
remote-model, installed D, M5/Q, Windows, framework or release qualification.
Native integer maps and controlled native preparation were skipped because
`MIRRORCPP_PREFIX` was unset. Counter and Async live Apalache tiers self-skipped,
and the runner's explicitly excluded local Apalache/TLC checks did not run.

## Retained attempts and environment correction

The initial sandboxed attempt failed when socket creation was denied. A second
run outside the sandbox passed the loopback gates but failed ten distribution
installation cases because their required ext4 filesystem was tmpfs `/tmp`.
The successful run retained that approved loopback execution and selected an
ext4-backed workspace `TMPDIR`. No source or test expectation was changed to
resolve either environmental failure.

Raw evidence remains ignored under
`.golden-build/s1-local-no-model-20261103/`:

| File | SHA-256 | Meaning |
| --- | --- | --- |
| `run.log` | `59d1b39bc0bf7176fd3b66140debeb1e98b8bcd66e81f9b95b9171c62fd11dba` | Successful complete aggregate |
| `sandbox-attempt.log` | `1eefddfae98692536508a38faf5e90349e201c26fdf20152e534128339ba951a` | Initial sandbox socket denial |
| `tmpfs-attempt.log` | `88cfa74bfc5c320f8cc32996eb81ae26e3df90103e376c3bed92ea25fbb842db` | tmpfs distribution failures |
| `receipt.json` | `8a3b204f8563309751c29bb6d5fa065cea58b85041479a2bca09a1ac4863fe83` | Identity, command, skips, result and log hashes |

Verify the retained bytes with:

```bash
sha256sum .golden-build/s1-local-no-model-20261103/{run,sandbox-attempt,tmpfs-attempt}.log \
  .golden-build/s1-local-no-model-20261103/receipt.json
```

## Publication boundary

The user requested commit and push of this validation result to `origin/main`.
Only `CHECKPOINTS.md` and this record are new publication payload. Raw logs,
receipts, build outputs, older untracked completion records and editor caches
remain excluded and preserved. The successful local commit and fresh remote-ref
observation are recorded separately under the ignored audit root; this record
does not itself prove branch delivery. No tag, release, deployment, service
operation or reboot is included.
