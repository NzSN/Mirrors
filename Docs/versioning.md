# Product versions and local installation

Mirrors, MirrorECMA, and MirrorGate use [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).
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
Mirrors 0.0.1
$ ModelMirrors --version
Mirrors 0.0.1
```

The second command requires installation under that name on `PATH`.
See the [CLI reference](interface-reference.md) for exit codes and argument
validation. The `--version` implementation was added after the baseline tag;
checking out `v0.0.1` itself does not provide the flag. The original tag remains
unchanged. Version output reports the declared version, not a Git SHA or a
clean-tree guarantee. Record `git rev-parse HEAD`, `git status --short`, and
the executable's SHA-256 when exact build provenance is needed.

## Build and install on Linux or WSL

From the Mirrors checkout, run `lake build` and `lake test`. The executable is
`.lake/build/bin/mirror`. Lake reuses unchanged compilation results; removing
only that generated executable before `lake build mirror` forces it to relink.
For C-shim changes, also remove the affected shim object before rebuilding.
Report any skipped external test tiers separately from successful checks.

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
