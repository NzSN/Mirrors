# MW-12 selected-source correction

Catalog refresh now reads the Mirrors product version from the selected `MIRRORS` checkout. An explicit `mirrors_source` argument still overrides that default. The previous default used the running tool tree (`HERE.parents[1]`), so a selected checkout at `0.0.9` kept the tool declaration `0.2.0-rc.6`.

`test_selected_source_version_wins_over_running_tool` selects a checkout declaring `0.0.9` while this tree declares `0.2.0-rc.6`, and expects the catalog product `0.0.9`. The planning-docs fixture commits its own `Shell/Version.lean` (`0.0.9`) before use. Source validation is unchanged.

## Tests

Python 3.14.4. `TMPDIR` was `/home/lsz/Codebase/Mirrors/.golden-build/mw12-20261103/source-correction-tmp` on ext4 (`/dev/sdd[/home/lsz]` mounted at `/home/lsz`).

| Command | Result |
| --- | --- |
| `python3 Plans/mainwork-mw12-20261103/selected_source_probe.py` | exit 0; observed catalog version `0.0.9` |
| `python3 -m unittest discover -s tools/distribution -p test_*.py -v` | 68 tests, exit 0, 3808 ms |

`test_*.py` was one argv element. Logs, exit codes, and SHA-256 hashes are in `result.json`.

## Paths

- `tools/distribution/refresh_identity.py`
- `tools/distribution/test_refresh_identity.py`
- `tools/distribution/test_planning_docs_exclusion.py`
- `Plans/mainwork-mw12-20261103/source-correction/`

`Plans/mainwork-mw12-20261103/source/` was not rewritten. No catalog, lock, doc, registry, build, or Git ref change was made for this correction.
