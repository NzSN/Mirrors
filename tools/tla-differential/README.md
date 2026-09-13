# TLA+ differential validation

The differential gate runs the captured frontend corpus through Mirrors,
standalone SANY, and Apalache. Reference tools are compatibility oracles and
are acquired explicitly; tests never download tools or use ambient installs.

## Local setup and commands

From the repository root, acquire the pinned artifacts once:

```sh
python3 tools/tla-differential/acquire.py --download
```

The command verifies both release hashes before installing under the ignored
`.golden-build/tla-differential/toolchain/` directory. To verify an existing
installation without network access:

```sh
python3 tools/tla-differential/acquire.py
```

The required gate command is:

```sh
lake build tla_frontend tla_differential_driver
python3 tools/tla-differential/run.py --required --output .golden-build/tla-differential/results
```

It emits the bounded report and summary in the runner’s ignored output
directory. A missing artifact or unavailable required observation produces an
incomplete, nonzero result. The runner owns its exact output location and
retains bounded raw evidence; do not add tool downloads to test commands.

The standalone frontend probe is `java -cp <tla2tools.jar>
tla2sany.SANY [-error-codes] <root.tla>`. Apalache’s frontend-only probe is
`apalache-mc parse --output=<output.json> <root.tla>`. Neither command invokes
model exploration or requires `Init`/`Next`.

See [`qualification.md`](qualification.md) for native output markers, API
extraction boundaries, parser lineage, and the atomic substitution comparison limits.

## Gates and evidence

Offline checks run from `lake test`, or directly with
`python3 -m unittest discover -s tools/tla-differential/tests`.
`DV_LIVE_REFERENCES=1 python3 tools/tla-differential/tests/test_references.py -v`
adds the pinned calibration probes. The required runner compiles the SANY
bridge before execution; output directories must be new or empty.

Exit codes are 0 pass, 1 disagreement/failure, 2 incomplete, and 3 invalid
configuration. Expected language rejection is a completed observation, not a
process failure. `--required` never skips missing tools into success. The
initial implementation runs one subprocess at a time on Linux/POSIX.

`captured-inputs.json` preserves the source bundles and harness source snapshot.
`report.json` includes verified identities and raw evidence references;
`semantic.json` excludes run paths/times and is suitable for repeat comparison.
Implementation/executable hashes are checked before and after the run. A run
whose implementation changes is exploratory evidence and cannot pass.

The reference adapters receive no summary/outcome fields. They are trusted
comparison tooling, not a security boundary: public fixture IDs can suggest an
outcome and are never an oracle. There is no automatic expectation update or
reviewed-difference promotion.
