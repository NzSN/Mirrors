# MW-12 freeze preparation report

## Executed facts

HEAD `3c4a87309cc3a81924660497207d7c295759bdc1`, tree `5c15228e006f4d1b6efaa7e088488bc4b1fe619e`, branch `main`, matches `origin/main`. The tracked worktree diff was empty. Unrelated untracked planning records were left in place and are listed in `intake.json`.

The range `25b62541ca443d5779fccc8d45fd90f64312747e..3c4a87309cc3a81924660497207d7c295759bdc1` changes only `CHECKPOINTS.md` and `Plans/s1-local-no-model-evidence-20261103/README.md`. Both match `is_planning_documentation("mirrors", path)`. A quiet diff excluding those two paths was empty. That does not transfer the parent gate.

S1 log and receipt hashes match `Plans/s1-local-no-model-evidence-20261103/README.md`. `run.log` ends with `ALL LOCAL NON-MODEL GATES GREEN`. Native preparation stayed excluded because `MIRRORCPP_PREFIX` was unset. Live Apalache tiers and local Apalache/TLC stayed excluded. The aggregate was not rerun.

Task-owned companions were clean: MirrorECMA `9192171fc5f8d8457f8d13ffaafa117222914ec2` tree `3a48d828710fafdc9076f0b57bf4e089cdd372ee`, MirrorGate `4b379ac0c017e7621c945ebf8c106cd98a6c70d1` tree `96e7fa4d0ac90c526d7e499f95664f00b1bc3e9b`. `framework_catalog` is 119687824 bytes, SHA-256 `5a64a5bd40e999b20dd8268f2846c0f5ad5359067db9f014379c150e27d76126`. The ECMA runtime pin, tracer wrapper, tracer dependency hashes, and `tools/evidence/commands.json` parse matched the maintained inputs. No identity drift blocked candidate creation.

`prepare.py` copied each catalog and complete lock root under `.golden-build/mainwork-freeze-20261103/candidates/<family>/distribution/<root>/`, refreshed twice with `--skip-component-records --skip-render`, and required byte-stable repeats. Maintained `validate_locks` accepted both candidates against the explicit catalog and C3 hash. Dependency locks kept their original bytes. Fixture build inputs use `distribution/reference-node/` and `distribution/reference-node-wsl2-26.04/` prefixes. Checked-in catalogs, locks, compact projection, component record, `Docs/framework-map.md`, and the MirrorECMA capability record were unchanged.

Fresh canonical C0 selections:

| Family | Role | catalogSha256 |
| --- | --- | --- |
| base | structural control | `f2bf471a2eba49d39a414bcee2c498d05dd350ac0494c5dd482ea292ccd30a0a` |
| wsl2 | selected execution `ubuntu-26.04-wsl2-x86_64` | `4bb83aa2efb022e801c7be5d7efb102f32d2f354f01d5d002d4f8897197af1f5` |

Both differ from the historical dirty-snapshot values. Both catalogs bind clean Mirrors at the freeze revision, the selected companion revisions, and product `0.2.0-rc.6`. `snapshot_sources.py` wrote one immutable snapshot per family. Bindings are in `freeze-manifest.json`.

Focused validation used ext4 `TMPDIR=.golden-build/mainwork-freeze-20261103/tmp`. Distribution: 68 tests, exit 0, `OK`. Durable evidence: 146 tests, exit 0, `OK`. The refresh and snapshot commands exited 0.

The first `verify.py` invocation exited 1. Its three-line terminal receipt was `6374 8 6366`, `VERIFY:1`, and `FREEZE VERIFY FAILED: inventory closure mismatch missing=[] extra=['.golden-build/mainwork-freeze-20261103/receipts/verifier-rerun.stderr', '.golden-build/mainwork-freeze-20261103/receipts/verifier-rerun.stdout']`. Those two rerun receipt files were then deleted. They were not preserved. The session log `call-0e2122b2-a85d-4404-b37f-750e57463d7a-59` is the source of the recovered transcript at `.golden-build/mainwork-freeze-20261103/receipts/verifier-first-invocation.terminal.txt`.

The corrected verifier's first execution then exited 1 with `FileExistsError` while creating `tmp/fixed-point`, because the candidate copy had already created that directory. That traceback was not deleted; it is retained at `.golden-build/mainwork-freeze-20261103/receipts/verifier-fixed-point-mkdir.terminal.txt`. The mkdir now uses `exist_ok`.

Candidate directories that were mode 0755, including the task root, `candidates`, both family roots, and their lock-root directories, were changed to 0700 without rewriting file bytes. `prepare.py` now enforces that mode for a future run. The corrected verifier checks those modes, compares each S1 `sha256` with `expectedSha256`, and refreshes a temporary copy of each finalized candidate under `tmp/fixed-point/`. That third refresh stays outside the inventory closure.

## Still open

The Batteries carrier `batteries-v4.33.0.bundle` remains absent. ptrace and namespace admission, installed D audit, remote/TLS/client/Windows inputs, M5, Q, and release remain open. No C0 digest or source snapshot is installation or framework acceptance. Codex has not accepted this candidate.

## Later commands, not run here

Packaging, cache builds, installation, D audit, M5/Q producers, remote model checks, local Apalache/TLC, tags, and deployment stay outside this preparation. `verify.py` is the bounded check for the files this task produced.
