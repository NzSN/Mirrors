# Admission readiness (MW-50, MW-51, MW-52)

Readiness dossier for Codex review. C0 refresh, cache build, install, both D audits, `lake test`, and remote admission were not executed. S5-A, M5, Q, Windows, and platform qualification are not granted. No model checker was started.

Owned output is `Plans/mainwork-execution-20261103/admission/`: `report.md`, `commands.md`, `result.json` (schema `mirrors.mainwork-admission-readiness/v1`), `inventory.json`, and `logs/`. `inventory.json` hashes every other generated file. Failed logs are kept. No source, catalog, lock, `CHECKPOINTS.md`, ledger, or other job output was edited.

## Source and checkouts

Claimed and observed Mirrors `HEAD` are `75fbf962020cea8a13e009ecfdb3e912e7ce212f` on `main`. Subject: `distribution: accept warning-prefixed CLI diagnostics`. Cached `refs/remotes/origin/main` equals that commit and is not a fresh remote observation. No fetch was performed (`055`–`058`).

Companion `HEAD` observations, not frozen refs: MirrorECMA `f94358834dce2e527c8bc8feec0423a54cf4176c`, MirrorGate `4ef786b30ac6be45e471fb02610484581f5da3b0`, MirrorCPP `8c542a6b1339cc0b6176465ff7f17a32e614553d`, MirrorLean `a8634ebe2455f97d15b55bec3c810d945cb6e3d3`, MirrorRust `6b9480ab81717b76ca7f74b41fc554578b70c890`. `/home/lsz/Codebase/ModelMirrors` is absent. No Haskell checkout is present (`060`–`070`, `089`).

At 02:03Z, Mirrors porcelain had 29 lines: modified `CHECKPOINTS.md` and untracked `Plans/` paths, including this directory. MirrorECMA had untracked `node_modules-pnpm-isolated/`. MirrorGate, MirrorCPP, MirrorLean, and MirrorRust porcelain was empty. `git status` used `--no-optional-locks`. Those trees were left unchanged.

## Host

uid 1000, x86_64, hostname `DESKTOP-C7HNV2Q`. Ubuntu 26.04.1 LTS (Resolute), kernel `6.18.54.1-microsoft-standard-WSL2`. glibc 2.43 (`ldd`: Ubuntu GLIBC 2.43-2ubuntu2.4). Python 3.14.4 at `/usr/bin/python3` (symlink to `python3.14`, 7477160 bytes, sha256 `52e0a13e60a981d8c4b6478be2ba5176f69da07948a056bf49cf6f077e30cb41`). `cp` is GNU coreutils 9.7 via `/usr/bin/gnucp`. OpenSSL 3.5.5. gcc 15.2.0. Git 2.53.0 at `/usr/bin/git`. Lake `/home/lsz/.elan/bin/lake` is 5.0.0-src+d8b1897 (Lean 4.33.0); Lean commit `d8b18978322de05a8f3dba51ef03cf5461676c17`; elan 4.2.4; toolchain file `leanprover/lean4:v4.33.0`. Host Node `/usr/local/bin/node` is v24.22.0 and is not locked Node 24.15.0. `which` logs that use `|| true` are not existence proof; `strace` is absent.

The repo, `/var/tmp`, and `.golden-build` are ext4 device 2096, writable, and case-sensitive. `/tmp` is tmpfs device 74 and cannot be an install prefix. `mkdir` under `/home/lsz`, `/home/lsz/Codebase`, and `/home/lsz/.local` returned EACCES. Log `052` aborted on `/home/lsz` before printing filesystem JSON. Log `084` records each root. `.golden-build/` is gitignored (`.gitignore` line 3). Proposed candidate, not created: `/var/tmp/mirrors-mainwork-admission-20261103` mode 0700. `/var/tmp` may be cleared later; the executor retains manifests and audits.

## Locks

`validate_locks` passed for `distribution/reference-node` with `catalog/framework-catalog.json`, and for `distribution/reference-node-wsl2-26.04` with `catalog/framework-catalog-wsl2-26.04.json`, using `framework_catalog` sha256 `5a64a5bd40e999b20dd8268f2846c0f5ad5359067db9f014379c150e27d76126` (119687824 bytes). Lock bytes were unchanged (`081`).

Base id `mirrors-reference-node-ubuntu-24.04-x86_64-v1`, canonical catalog `e971cfec068c09532f2ffd01b15425be33aab42fa7dca507c0a0fe844c818b59`, file `f6b0e9001fa4f583a4e61a4c7726a50b6ee810444cb4cc8a9164c624122b3bc5`. WSL2 id `mirrors-reference-node-ubuntu-26.04-wsl2-x86_64-v1`, canonical `3bef64ce1e1e4fdc7b9d99e2cb4f5a1f165cd54f49cdeac7af42f6c3130253ee`, file `c6ec7f2694e27eab1406f13fcf68c85821369bce3aecfcf4fbd27de08a722a83`. Both dependency locks are `6033532222a34073408ae0a9e59da548588e8f1eccead5f035d21d4a2087d5fe`.

The WSL2 root without `catalog_path` failed closed: `ContractError: catalogSelectionRef does not identify the selected catalog bytes`. Bytes stayed unchanged. `manifest_check.py validate` has no catalog flag, so a CLI validate of the WSL2 root selects the base catalog. Recipes pass `--catalog`.

Profile spellings `checked-replay-local`, `checked-replay-gate`, and `fresh-trace` are shared. Catalog profile ids differ (`ubuntu-24.04-x86_64/v1` versus `ubuntu-26.04-wsl2-x86_64/v1`). Combinations are `candidate.local-node-checked`, `candidate.node-gate`, and `candidate.fresh-trace`. Checked profiles are `build-required`. Both fresh-trace profiles are `blocked-missing-java-artifact`. The lock field `prepared-cache` on Batteries is the document's availability label, not proof the carrier file exists.

Locked component revisions, stale against live `HEAD`: Mirrors `bd5d3b51b1dcd75fbdf6c3188f1c90b1e6fe6ea0`, dirty, digest `51dcae7b433da3604f0f5e068ed253895502c5b563114fce6efaa31f9cb78cdd`, included paths only the two refresh-identity tools; MirrorECMA `9192171fc5f8d8457f8d13ffaafa117222914ec2`, clean; MirrorGate `4b379ac0c017e7621c945ebf8c106cd98a6c70d1`, clean. The same revisions are in both lock roots. Their component-lock file hashes differ.

## Dependencies and permissions

Locked Batteries carrier is absent: `batteries-v4.33.0.bundle`, 3739542 bytes, sha256 `73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a`, revision `4488d40d070b9700d4d5a6aa342f0d40c31b2a2d`. `.golden-build/batteries-repin-20261031` does not exist. The walk found only the superseded bundle, 3684180 bytes, sha256 `f6efbfeb6353195c3318e3ef6e46d3e4e87897659989cd7322156d9e8a5f1cd3` (`082`, `083`, `084`). Bundle Git identity was not verified. The pin was not replaced and the old bundle was not cloned.

Bound Node archive: `.golden-build/version-0.1/toolchains/node-v24.15.0-linux-x64.tar.xz`, 31164460 bytes, sha256 `472655581fb851559730c48763e0c9d3bc25975c59d518003fc0849d3e4ba0f6`. Same-hash copies are not alternate recipes. Streamed member `node-v24.15.0-linux-x64/bin/node` matches the interop pin: 122889056 bytes, sha256 `d1de76d8edf2fededf6f8b30d244e2c0529ac607923a018283b77e9c74bd932c`. It was not extracted. Pin file `tools/interop/ecma-runtime-pin.json` is 851 bytes, sha256 `598bb5efc53447444eedec428ac72ea6d1ef478a75995452d7176414f7df8c83`. TypeScript `node_modules/typescript` matches pin digest `80a859dc2c85ecd5731cbbf3b58ddf6f5457bf11fd7ab31ffb56ef4c05855661`. `@types` symlinks `jest` and `node`, so no source runtime-tree was computed; `build.py` copies with `symlinks=False`.

Evidence wheels bound for this interpreter: `.golden-build/rc3-s5-20261031/prepared/evidence-wheels`, digest `f2c2e4edb2fe7d20afeba90192d09683b5d810b8fb2fb76df0c99cecd5301861` (pure Python, including `pyrsistent-0.20.0-py3-none-any.whl`). Two cp312 trees share digest `6423086879a2db6ae9fb9ba5e69ea29cceb6d84a0a1f079e4f79bfd20c69d743` and stay unused. `requirements.txt` still comments Python 3.12. Linux Apalache 0.61.0 is present (191998425 bytes, sha256 `68fb56dd9d053cf21d692fd7ec3fbaaeba1395661ec7434fa2b4c47e6fc432b8`) and is not Windows Apalache 0.62.2. Java 25.0.4+7 is missing.

`ptrace_scope` is 1 and `PTRACE_TRACEME` passed (`053`). `strace` is absent (`035` exit 127, `085`, `086`). `bwrap` 0.11.1, package `bubblewrap 0.11.1-1ubuntu0.3`, meets minimum 0.9.0. User-namespace creation failed (`054`). Unprivileged-userns sysctls are unreadable (`039`, `040`). `max_user_namespaces` is 2147483647. That denial is evidence, not a host relabel and not a request to raise privileges. cgroup v2 is mounted; the process cgroup `/sys/fs/cgroup/non-systemd` is not writable. No cgroup write was attempted. Loopback IPv4 port 34823, IPv6 port 41177, and a `/tmp` UNIX socket passed in `084`. `lo` operstate `unknown` is a separate sysfs reading.

Lock operator strings still say glibc 2.39, Python 3.12.3, cp 9.4, and bubblewrap observed 0.9.0. WSL2 also records virtualization `WSL2`. Those strings were not rewritten. This host can satisfy the WSL2 kernel-family check (`microsoft-standard-wsl2`). A base-profile install here would record observed platform `ubuntu-26.04` and would not qualify Ubuntu 24.04.

## Failures kept

These logs are evidence. None of them is a pass.

- `035` exit 127: `strace` is not on PATH. `023` used `command -v || true`, so its exit 0 does not show that `strace` exists.
- `039` and `040`: unprivileged user-namespace sysctls are unreadable.
- `052` exit 1: `mkdir` under `/home/lsz` raised `PermissionError` before any filesystem JSON was printed.
- `054` exit 1: `bwrap` cannot create a namespace. Package `bubblewrap 0.11.1-1ubuntu0.3` is installed (`087`).
- `070` exit 127: `/home/lsz/Codebase/ModelMirrors` is absent.
- `077` exit 2: `run_remote_model_check.py` stopped before `execve` because `MIRRORS_REMOTE_CLIENT_CERT` is unset. No socket was opened.
- `080` exit 2: `framework_catalog` with no arguments printed usage and wrote no catalog.
- `081`: the WSL2 default-catalog call failed closed. The two explicit-catalog calls passed. All three left lock bytes unchanged.
- `083` exit 1: the documented Batteries retention path is absent.
- `084`: the only `batteries-v4.33.0.bundle` found fails `matchesLockedPin`. Loopback IPv4 34823, IPv6 41177, and the UNIX socket passed. cgroup write access is false.
- `085`: the wrapper exited 0 and its body records `test_exit:1` for `/usr/bin/strace`.
- `086` exit 1: `dpkg-query` reports no `strace` package.

`probe-summary.json` is the first wave only (`001`–`083`). `result.json` lists all 90 command logs with the exit code and SHA-256 taken from the files as they stand. Log `090` measures tool and wheel bytes; its header clock value was not read from the system clock.

Siblings observed under `/home/lsz/Codebase`: Ariadne, Cooperators, DumpAnalyzer, DumpLedger, Forensicator, MirrorCPP, MirrorECMA, MirrorGate, MirrorLean, MirrorRust, Mirrors, WriteSentry, bap, crashpad, electron, old-skills, skills. Client binaries have no parser default and were not located. `HS_REPO`, `HS_REF`, and `HS_BIN` are unresolved.

`Plans/` and `CHECKPOINTS.md` are planning-documentation exclusions for the Mirrors component, except `Plans/q3-readiness-2026-09-25.md`, which was not in the porcelain. MirrorECMA excludes `.work/` and `catalog/framework-capabilities.json` only, so `node_modules-pnpm-isolated/` would be included by a refresh. It was not deleted.

## Disposition

MW-50 is observed, with the blockers below. MW-51 recipes are argument-complete and were not run. Final forms wait for MW-12, MW-31, and MW-32. MW-52 names fresh remote, TLS, five-client, and Windows inputs and their owners. No SSH, credential read, or backend change occurred. Code default `172.28.144.1:8999` and older `172.20.208.1:8999` material are historical. Log `077` exited 2 before `execve` because `MIRRORS_REMOTE_CLIENT_CERT` was absent.

The two D audits are local versus gate, per profile family. They were not run. The current `framework_catalog` hash is a pre-freeze bootstrap value and must be recomputed at execution.

1. Locked Batteries bytes are missing. Cache build is blocked. Bundle identity is unverified.
2. `strace` is missing. Both D audits are blocked.
3. `bwrap` cannot create a user namespace. The gate audit is blocked. The version check is not the failure.
4. Java is missing. Fresh-trace stays `blocked-missing-java-artifact`. Checked recipes omit Java and Apalache flags.
5. C0 refresh waits for a clean MW-12 freeze. MirrorECMA `node_modules-pnpm-isolated/` would enter a dirty identity. Candidate copies use `--skip-component-records` and `--skip-render`.
6. Recorded prerequisite versions do not describe this host. Locks stay unchanged.
7. Base install and the base D pair need a separate Ubuntu 24.04 x86_64 ext4 host. This host is Ubuntu 26.04.1 WSL2.
8. No fresh remote, TLS, or Windows observation exists. Client binaries and the Haskell repository were not located.
9. Post-freeze C3 hash, prefixes, cache outputs, and audit outputs are execution-time values.
10. Other jobs' `CHECKPOINTS.md` and `Plans/` changes remain. This task preserved them.

Log `090`'s header time `2026-11-03T02:12:00Z` was supplied by the writer, not read from the clock. Its JSON body is the measurement. `probe-summary.json` ends before logs `084`–`090`. Two earlier follow-up processes exited before creating a log (uncaught `mkdir` EACCES, then a symlink under `@types`); the corrected run wrote `084`–`089`.
