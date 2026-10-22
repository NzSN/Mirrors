# Product versions and local installation

The current cross-repository policy is
[ecosystem versioning](ecosystem-versioning.md). Current source declares Mirrors
`v0.1.1`, a compatible patch for DPM build preparation and maintained status
documentation. The build fix landed in `03510b4`; its
[bounded validation record](../Plans/dpm-build-preparation-evidence-20261022/README.md)
retains the exact tested source/artifact hashes. The newest
[checkpoint](../CHECKPOINTS.md) records the separate patch-release validation
and publication boundary.

The corrected `v0.1.0` baseline at `b243b37` remains unchanged. Its
[retag inventory](../Plans/version-migration-2026-10-22/retag.json) preserves the
superseded alias and release identities; the original
[migration evidence](../Plans/version-migration-2026-10-22/README.md) remains
bound to its original server commit and binaries. That explicitly requested
retag was a migration exception. Ordinary patch releases use new immutable tags;
the release builder has no alias exception.

For operating an installed executable as a remote service, see the [remote server guide](remote-server-guide.md)
and [dated Windows deployment record](windows-deployment-20260918.md).

Mirrors, MirrorECMA, MirrorCPP, MirrorRust, MirrorLean, and MirrorGate use
[Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).
Each repository has its own release sequence, starting from the `0.0.1`
baseline. Version numbers use `MAJOR.MINOR.PATCH`; annotated Git tags use
the prefix `v`, for example `v0.0.1`.

## Initial baseline

The following tags were created and pushed to each repository's `origin` on
2026-09-08. Each marks the existing commit without modifying its contents.

| Repository | Tag | Commit |
| --- | --- | --- |
| [Mirrors](https://github.com/NzSN/Mirrors/tree/v0.0.1) | `v0.0.1` | `df2f91aa052fedbbe7d544fb0e3d28565e04114f` |
| [MirrorECMA](https://github.com/NzSN/MirrorECMA/tree/v0.0.1) | `v0.0.1` | `1d02dc02e223c52674a479e73d35d9e80e16be61` |
| [MirrorGate](https://github.com/NzSN/MirrorGate/tree/v0.0.1) | `v0.0.1` | `15608a0a533418b243bc799513a2ca1292cbf68c` |

These are source baseline tags. They do not establish package publication or
hosted release artifacts. At these commits MirrorECMA's `package.json` still
declares `1.0.0`, and MirrorGate's declares `0.1.0`; tagging did not rewrite
those manifests. Use the tags and commit IDs above to identify the baseline,
and reconcile package metadata before publishing packages.

## Release policy

After `1.0.0`, incompatible public API changes increment MAJOR, compatible
features or deprecations increment MINOR, and compatible bug fixes increment
PATCH. Increasing a component resets the components to its right to zero.
Released versions and tags are immutable; corrections need a new version.

During initial `0.x` development, the public API is not stable. Our convention
is to increment PATCH for compatible fixes and MINOR for features or breaking
changes, documenting any migration required. Prereleases may use a suffix such
as `0.1.0-beta.1`.

The public compatibility surface includes Mirrors' documented CLI and JSONL
interfaces, generated binding contracts, MirrorECMA's exported client APIs,
and MirrorGate's control/worker protocols and SDK APIs. Existing frozen wire
contracts still apply during `0.x` development. A product release number does
not authorize an unversioned wire change.

Keep product versions separate from model-interface schema versions, semantic
digests, target profiles such as `mirrorecma-async-v1`, Gate control/worker
protocol versions, and artifact hashes. Matching product numbers alone do not
prove interoperability: record the exact companion commits and run the
[interop matrix](../tools/interop/INTEROP.md) and applicable Gate integration
gates for the combination being released.

## Inspecting the Mirrors executable

The declared product version lives in [Shell/Version.lean](../Shell/Version.lean)
and is compiled into the executable:

```console
$ .lake/build/bin/mirror --version
v0.1.1
$ ModelMirrors --version
v0.1.1
```

The second command requires installation under that name on `PATH`.
See the [CLI reference](interface-reference.md) for exit codes and argument
validation. The examples require rebuilding and, for `ModelMirrors`, reinstalling
that build. Binaries from the superseded `v0.1.0` alias still print `v0.0.3.2`;
retagging does not update an installed binary. The `--version` implementation
was added after the original `v0.0.1` baseline, which does not provide the flag.
Version output reports the declared version, not a Git SHA or a clean-tree
guarantee. Record `git rev-parse HEAD`, `git status --short`, and the executable's
SHA-256 when exact build provenance is needed.

## GitHub release builds

The [release workflow](../.github/workflows/release.yml) builds Linux x86-64
archives on Ubuntu 24.04. After this workflow is merged, pushing a new `v*`
tag whose commit contains the workflow starts a build automatically. New tags
must follow `vMAJOR.MINOR.PATCH[-prerelease]` and match `Shell.Version.version`;
the built executable must print that tag from `--version`. The source checkout
must be clean and its HEAD must equal the requested tag's commit.

The workflow builds `mirror` and `model_interface_gen`, then runs the tagged
source's `fixtures_replay`, `diff_cross`, `model_interface_spec`, `stdio_smoke`,
and `transport_spec` executables. It also runs `check-client-framing.py` when
that script exists in the tagged source. These are focused non-model release
gates; full cross-client interoperability, live Apalache/TLC work and framework
qualification remain separate obligations. No model checker is installed or
started by this workflow.

Each release contains:

- `mirrors-TAG-linux-x86_64.tar.gz`: the two executables, `README.txt`, and
  `BUILD.json`, with exact source, toolchain, regression and library identities.
- `mirrors-TAG-linux-x86_64.build.json`: the same build manifest beside the archive.
- `SHA256SUMS`: SHA-256 checksums for the archive and external manifest.

The runtime profile is Ubuntu 24.04 x86-64 (glibc 2.39), OpenSSL 3 and GMP.
Install `libssl3t64` and `libgmp10` on Ubuntu 24.04, verify `SHA256SUMS`, extract
the archive, and add its `bin` directory to `PATH`. Lean is not required at
runtime. Live model work separately needs Apalache and a compatible JVM.
The workflow checks the extracted archive in a fresh Ubuntu container without
Lean or the source checkout before publication. Native Windows/macOS packages
are not produced by this workflow. The hosted archive contains only `mirror`
and `model_interface_gen`; it does not package the DPM CLI. Build and install
DPM separately through the [DPM guide](dpm-cli-guide.md).

To build an existing tag, open **Actions → release → Run workflow**, select
the `main` branch, and enter the existing tag in the `tag` input. With GitHub
CLI, for example:

```sh
gh workflow run release.yml --ref main -f tag=v0.1.1
```

Adding the workflow does not retroactively run existing tag pushes. Backfill
tags individually with that manual input. Release tooling comes from the
workflow revision and builds a separate checkout of the exact original tag;
no historical source edits or tag moves are needed.

The six recorded historical tags have narrowly scoped exceptions bound to
their full source commit SHAs in [release.py](../tools/release/release.py):

| Tag | Embedded product version | Original `--version` output |
| --- | --- | --- |
| `v0.0.1` | absent | flag unavailable |
| `v0.0.2` | `0.0.2` | `Mirrors 0.0.2` |
| `v0.0.3` | `0.0.2` | `Mirrors 0.0.2` |
| `v0.0.3.1` | `0.0.3` | `Mirrors 0.0.3` |
| `v0.0.3.2` | `0.0.3` | `Mirrors 0.0.3` |
| `v0.0.3.3` | `0.0.3.2` | `v0.0.3.2` |

Historical releases disclose these differences and preserve original bytes.
They are not marked Latest. Prerelease tags produce GitHub prereleases and
also leave Latest unchanged. A future stable release becomes Latest only
after all release gates and runtime smoke checks pass.

The publication job alone receives `contents: write`. It verifies asset
checksums and reobserves the remote tag's peeled source commit before creating
a draft with all assets and generated release notes. It checks the remote tag
again before publishing the draft.
Existing releases and drafts are refused rather than overwritten. If an upload
fails and leaves a draft, inspect that draft and remove it before retrying.

Relevant pull requests run the tooling checks and the fixed `v0.1.0` packaging
baseline through the isolated runtime smoke, with publication disabled. This
baseline is independent of the latest product version. A tag push selects its
own `github.ref_name`; manual runs select the supplied tag. Tooling checks also
run before every release and can be run locally:

```sh
python3 -m unittest discover -s tools/release -p 'test_*.py' -v
```

## Build and install on Linux or WSL

From the Mirrors checkout, run `lake build`. The executable is
`.lake/build/bin/mirror`. Lake tracks native shim sources/headers and linker
dependencies; rebuild normally after changes. Use `lake test` on hosts where
its live model-checking tiers are authorized. On the WSL2 coordinator use
`bash tools/run-local-no-model-check.sh`; do model checking through the
designated remote Mirrors endpoint. Report skipped external tiers separately.

To replace a per-user `ModelMirrors` installation, back up the existing file,
stage the new executable beside it, and rename it into place. For an existing
regular file at `~/.local/bin/ModelMirrors`:

```bash
set -euo pipefail
installed="$HOME/.local/bin/ModelMirrors"
test -f "$installed" && test ! -L "$installed"
backup_dir="$HOME/.local/share/mirrors/backups"
mkdir -p "$backup_dir"
backup=$(mktemp "$backup_dir/ModelMirrors.XXXXXXXX")
cp -p "$installed" "$backup"
staged=$(mktemp "$HOME/.local/bin/.ModelMirrors.XXXXXXXX")
trap 'rm -f "$staged"' EXIT
install -m 0755 .lake/build/bin/mirror "$staged"
cmp .lake/build/bin/mirror "$staged"
mv -f "$staged" "$installed"
command -v ModelMirrors
"$installed" --version
sha256sum .lake/build/bin/mirror "$installed"
```

Confirm that `command -v` resolves to the intended installation and that the
two hashes match. This is a local installation procedure; it does not publish
a release. Before the next release, update the product version and its CLI
expectation in `tools/StdioSmoke.lean`, validate the build and companion
compatibility, commit the changes, and create a new annotated tag.
