# MW-12 final source/C0 freeze preparation

This directory records a fresh source/C0 candidate for `3c4a87309cc3a81924660497207d7c295759bdc1`. Codex reviews and owns acceptance. Nothing here is installation, D, M5, Q, or release qualification.

The selected execution profile is `ubuntu-26.04-wsl2-x86_64`. The base catalog candidate is a structural control.

## Reproduce

From the repository root, with this checkout at the freeze revision:

```bash
TMPDIR="$PWD/.golden-build/mainwork-freeze-20261103/tmp" \
  python3 Plans/mainwork-freeze-20261103/verify.py
```

`prepare.py` already created the ignored candidates under `.golden-build/mainwork-freeze-20261103/`. Running it again refuses an existing output root. `verify.py` also checks owner-only candidate directories, S1 actual/expected hashes, the retained first and second refresh receipts, and a third refresh of temporary candidate copies under `tmp/fixed-point/`. The deleted first verifier failure is recovered only as a transcript in `.golden-build/mainwork-freeze-20261103/receipts/verifier-first-invocation.terminal.txt`. Focused suites, already executed on ext4 `TMPDIR`:

```bash
TMPDIR="$PWD/.golden-build/mainwork-freeze-20261103/tmp" \
  python3 -m unittest discover -s tools/distribution -p 'test_*.py'
TMPDIR="$PWD/.golden-build/mainwork-freeze-20261103/tmp" \
  python3 -m unittest discover -s tools/evidence/tests -p 'test_*.py'
```

Hashes and exits are in `result.json`, `freeze-manifest.json`, and `inventory.json`.
