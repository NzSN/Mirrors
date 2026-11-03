# MW-12 source version refresh

Baseline `75fbf962020cea8a13e009ecfdb3e912e7ce212f`. This job prepared Mirrors product `0.2.0-rc.6` and made catalog refresh take that declaration from the selected local checkout. Codex owns catalog integration and review.

## Change

`Shell/Version.lean` declares `0.2.0-rc.6`. Local tags `v0.2.0-rc.1` through `v0.2.0-rc.5` were left in place. No Git ref was created or moved.

`update_catalogs` reads `Shell/Version.lean` before any catalog write and before the selection digest. The Mirrors component in the selected catalog receives that product version. When component records are requested, the same product is written onto the Mirrors entry in `catalog/components/mirrors.json`. Other components keep their declared products. `update_locks` still copies catalog products by component id.

A missing file, a missing declaration, a malformed value, or more than one column-zero `def version` line raises `SourceVersionError` before either write. The accepted form is `MAJOR.MINOR.PATCH[-prerelease]`, matching the release tag rule without a leading `v` and without historical four-part tags. A numeric prerelease identifier cannot have a leading zero.

`--skip-component-records` still skips component-owned record writes. The selected catalog still receives the corrected Mirrors product, so its selection digest includes the source version. `--skip-render` still skips only compact and markdown rendering. Existing positional callers of `update_catalogs` stay valid. The default source is this checkout: a patched `MIRRORS` sandbox does not supply the product version.

## Tests

Python 3.14.4. `TMPDIR` was `/home/lsz/Codebase/Mirrors/.golden-build/mw12-20261103/tmp` on ext4 (`/dev/sdd[/home/lsz]` mounted at `/home/lsz`). `PYTHONDONTWRITEBYTECODE=1`. Unittest wrote its report to stderr.

| Suite | Result |
| --- | --- |
| `python3 -m unittest discover -s tools/distribution -p test_refresh_identity.py -v` | 8 tests, exit 0, 158 ms |
| `python3 -m unittest discover -s tools/distribution -p test_*.py -v` | 68 tests, exit 0, 3854 ms |

The `test_*.py` argument was passed as one argv element, so the shell did not expand it. The refusal test contains 10 subtests and checks that catalog bytes and the owned-record bytes stay unchanged. Raw logs, argv, timestamps, exit codes, and SHA-256 hashes are in `logs/` and `result.json`.

After those suites, `HEAD` was still the baseline. `git status` on the owned sources plus `catalog/`, `distribution/`, `Docs/framework-map.md`, and `tools/StdioSmoke.lean` showed modifications only in the three owned sources. `git diff --check` on those sources exited 0 with empty output.

## Left unchanged

- Checked-in catalogs and component locks still record Mirrors `0.1.1`.
- `tools/StdioSmoke.lean` expects `v0.2.0-rc.5`. A later `stdio_smoke` build needs that expectation moved to `v0.2.0-rc.6`. This job did not rebuild.
- `Docs/versioning.md` describes product `v0.1.1`.
- Git refs, including the existing rc.1–rc.5 tags.

## Not run

Lake and native builds, Apalache, TLC, the release suite, the evidence suite, and remote operations.

## Paths

- `Shell/Version.lean` (`1` insertion, `1` deletion)
- `tools/distribution/refresh_identity.py` (`78` insertions, `6` deletions)
- `tools/distribution/test_refresh_identity.py` (`266` insertions)
- `Plans/mainwork-mw12-20261103/source/` (`report.md`, `result.json`, `inventory.json`, `logs/`)
