# TLA+ differential validation

The differential gate runs the captured frontend corpus through Mirrors,
standalone SANY, and Apalache. Reference tools are compatibility oracles and
are acquired explicitly; tests never download tools or use ambient installs.

## Local setup and commands

From the repository root, acquire the pinned artifacts once:

```sh
python3 tools/tla-differential/acquire.py --download
```

The command verifies both release sizes and SHA-256 hashes before installing
under the ignored `.golden-build/tla-differential/toolchain/` directory. To
verify an existing installation without network access:

```sh
python3 tools/tla-differential/acquire.py
```

### Immutable artifact store

A release URL is mutable provenance, not an identity. The lock pins the archive
SHA-256, size, build revision, extracted JAR and launcher identities, and the
derived standard-library digest. An operator can retain the reviewed archives in
an explicit content-addressed store. Object paths are
`<store>/sha256/<lower-case-sha256>`; names from release URLs are not identities.
The tool never discovers a store from an environment variable, repository
sibling, package cache, or `PATH`.

Populate the store while acquiring, or restore a fresh local toolchain from the
store without any network access:

```sh
python3 tools/tla-differential/acquire.py --download --artifact-store /approved/store
python3 tools/tla-differential/acquire.py --offline --artifact-store /approved/store
```

`--artifact-store` without `--download` is also offline restoration; `--offline`
makes the no-network intent explicit. `--download` and `--offline` are mutually
exclusive. In download mode an existing valid store object is used before the
network; a missing object may be fetched from its locked URL, verified, and
published. In offline mode a missing object fails closed.

Downloads and store publications are staged beside their destination, checked
for exact size and SHA-256, and installed without overwriting existing bytes.
Apalache extraction is staged and verified before it is renamed into place.
Truncated, mismatched, partial, or unavailable content is rejected; a bad store
object never triggers a network fallback. Keep the store outside Git or in an
ignored location. Large tool archives are not committed by this repository.

These checks establish byte identity only. They do not prove artifact security,
JDK compatibility, differential completeness, or profile qualification. The JDK
is operator-supplied and admitted by the exact version/build in the lock; it is
not downloaded by this acquisition tool.

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
