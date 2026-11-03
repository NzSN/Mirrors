# Downstream task cards — MW-30 and MW-60 preparation

Status: preparation only. Nothing in this file was built, packaged, collected,
finalized, or executed against a model checker, remote host, or Git remote.
`executionState` for every card below is `not-started`. Codex review of this
directory does not pass S3, S5-B, or any later stage.

Authoritative command identity is `tools/evidence/commands.json` parsed by
`tools/evidence/command_registry.py`, and profile membership is
`tools/evidence/qualification-profiles.json` parsed by
`tools/evidence/catalog_links.py`. Dated prose that says "18 commands/16 tiers"
matches the current `m5-wsl-windows-remote` arrays; the arrays are the
authority, and the other three profiles do not have those counts.

Observed while preparing this card, without a fetch:

| Fact | Value |
| --- | --- |
| `HEAD` | `75fbf962020cea8a13e009ecfdb3e912e7ce212f` |
| `HEAD^{tree}` | `484e8f2991d1e2c56c8d47af668888e1cb48904f` |
| Branch | `main` |
| `Shell/Version.lean` | `0.2.0-rc.5` |
| Local tag `v0.2.0-rc.5` peel | `3ee3d9226f6258583fe7266c1737acff5abd1edf` |
| Registry SHA-256 | `04ded2066f18584c0fa3e87fd48d3b58bb4f2a79c24b12776abdeb3576c17bb3` |
| Profiles SHA-256 | `e89a414beb6fd16a8409e74623ad82c07e5e334c1d744504012d686183f5a86a` |
| Registry command count | 24 unique `commandId` values |
| MirrorECMA checkout `HEAD` | `f94358834dce2e527c8bc8feec0423a54cf4176c` (equals registry `ECMA_REF`; only untracked `node_modules-pnpm-isolated/`) |
| MirrorCPP / MirrorRust / MirrorLean `HEAD` | equal registry `CPP_REF` / `RUST_REF` / `LEAN_CLIENT_REF`; clean |
| MirrorGate checkout `HEAD` | `4ef786b30ac6be45e471fb02610484581f5da3b0`, clean, not a registry pin |

The shared Mirrors worktree was already dirty when this directory was added.
This task does not revert or describe those other files as its own edits.

Named inputs stay in `UPPER_SNAKE` until a later admitted receipt supplies
them. A card is not executable while any input it marks `blocking` is unknown.
No input may be filled from an October 7 or October 31 receipt.

## Dependency order

```text
MW-12 freeze -> MW-20 audited source -> MW-30 tag rule
  -> MW-31 Linux package and MW-32 Windows package
  -> MW-53 both D bindings and MW-54 remote/Windows admission
  -> MW-61 producers, MW-62 22-row clients, MW-63 three DPM profiles, MW-64 Windows lake test
  -> MW-65 Q recipes (separate file) -> MW-66
```

MW-31 and MW-32 both bind the same S2 commit. MW-62 and remote-backed rows of
MW-61 wait for MW-54. MW-63 waits for the exact installed packages from
MW-31/MW-32 and admitted tool roots. MW-64 waits for MW-32, MW-54, and an
explicit full-build approval. Preparation of the cards does not satisfy any
of those edges.

## MW-30 — unused tag and version rule

Do not create, move, delete, or push a tag from this card.

`tools/release/release.py` `identity()` requires all of the following at
once: the tag matches `vMAJOR.MINOR.PATCH[-prerelease]` or is one of the six
historical aliases; the clean checkout `HEAD` equals `refs/tags/TAG^{commit}`;
for a non-historical tag, `Shell/Version.lean` embeds exactly `TAG` without
the leading `v`. `build` also refuses a non-empty output directory and any
host other than Linux x86-64.

Current observation blocks reuse:

- Embedded version is `0.2.0-rc.5`, so the only tag `identity()` will accept
  for this source text is `v0.2.0-rc.5`.
- That tag already exists locally and peels to `3ee3d92`, not to `HEAD`.
- Moving it would retag rc.5. That is forbidden. `select` only prints
  `tag=...`; it does not prove identity and it is not permission to retag.

Rule for `PROPOSED_TAG`, which remains unresolved until S1 changes the
embedded version and the tag name is separately authorized:

1. `PROPOSED_TAG` matches the non-historical pattern in `validate_tag`, has
   no leading-zero numeric prerelease identifier, and is not `v0.2.0-rc.5`
   or any `HISTORICAL` key.
2. `git rev-parse --verify --end-of-options refs/tags/PROPOSED_TAG` fails in
   the shared checkout and in the clean packaging clone. A remote absence
   check is MW-72 work and was not run here. The 2026-10-31 checkpoint text
   that no remote rc.5 tag existed is historical.
3. `Shell/Version.lean` embeds `PROPOSED_TAG` without the leading `v` at the
   frozen S2 commit. Changing that file is a source assignment, not this
   handoff.
4. The packaging clone is clean, its `HEAD` is the S2 commit, and the
   annotated tag object peels to that commit. Do not push the tag while
   packaging. A `v*` push starts `.github/workflows/release.yml`, whose
   publish job can create a GitHub release.
5. Record the proposal as unaccepted until MW-71. A filled template row is
   not a selected tag.

`blocking` inputs: `S2_COMMIT`, `PROPOSED_TAG`, authorized embedded-version
edit, and explicit local-tag authorization.

## MW-31 — clean Linux package

Owner after this preparation: Grok, then Codex. Depends on MW-20 and the
MW-30 authorization. Requires explicit build approval. Scope is focused
non-model release gates. It is not live-model, DPM, or M5 qualification.
The archive must not contain the DPM CLI.

Preconditions the builder itself enforces: Linux x86-64; clean `CLEAN_SOURCE`
whose `HEAD` is `PROPOSED_TAG`; empty `EMPTY_DIST`.

```sh
python3 -m unittest discover -s tools/release -p 'test_*.py' -v
python3 tools/release/release.py build \
  --source "$CLEAN_SOURCE" \
  --tag "$PROPOSED_TAG" \
  --output "$EMPTY_DIST"
( cd "$EMPTY_DIST" && sha256sum --check SHA256SUMS )
python3 tools/release/release.py check-archive \
  --tag "$PROPOSED_TAG" \
  --archive "$EMPTY_DIST/mirrors-$PROPOSED_TAG-linux-x86_64.tar.gz"
```

`build` runs `lake build` of `mirror`, `model_interface_gen`,
`fixtures_replay`, `diff_cross`, `model_interface_spec`, `stdio_smoke`, and
`transport_spec`, then those five gates, then `tools/check-client-framing.py`
because that file exists, then relocated `--version` / protocol smoke /
`model_interface_gen --help`. It strips `APALACHE_MC`, `APALACHE_JAR`,
`TLA2TOOLS_JAR`, `LD_LIBRARY_PATH`, and `LD_PRELOAD` from the builder
environment. `ldd` must resolve only the `SYSTEM_LIBRARIES` set in
`release.py`. Archive members are exactly the package directory, `bin`,
`bin/mirror`, `bin/model_interface_gen`, `README.txt`, and `BUILD.json`.

Isolated smoke is a second `check-archive` on the selected observed host
with Lean and the source checkout absent from the packaged runtime `PATH`.
The GitHub workflow uses Ubuntu 24.04. The completion design also requires
the actual Ubuntu 26.04.1 WSL2 host when that host is the selected one.
Record the host that ran; do not copy either OS string from a dated receipt.
This preparation did not observe that host.

Receipt: `package-set` Linux rows for the archive, external
`mirrors-$PROPOSED_TAG-linux-x86_64.build.json`, `SHA256SUMS`, each binary
SHA-256, `ldd` output, gate names, source commit, and the sentence from the
builder that qualification is focused non-model gates only. Exit fails on
any builder exception, checksum mismatch, or smoke that sees the source tree.

## MW-32 — clean Windows package

`release.py build` raises `this release profile requires Linux x86_64` and
has no Windows subcommand. There is no maintained Windows packager under
`tools/release/`. The rc.5 script
`Plans/completion-rc5-evidence-20261031/package_windows.py` is campaign code
bound to tag `v0.2.0-rc.5` and path `.golden-build/completion-rc5-20261031`.
Do not execute it for the new candidate.

`blocking` inputs: `WINDOWS_HOST` and staging paths from MW-54, `S2_COMMIT`,
`PROPOSED_TAG`, source-archive SHA-256, and build approval. Unknown host,
toolchain, and binary hashes stay blank.

Construction checks, in order:

1. Transfer a source archive of `S2_COMMIT` only. Record file count and
   archive SHA-256. Compare again after the build. Any difference rejects
   the package. Do not apply an unreviewed overlay.
2. Build `mirror` and `model_interface_gen` from that tree. Package smoke
   executables are the rc.5 eight-suite set, which is package smoke and not
   MW-64: `fixtures_replay`, `diff_cross`, `model_interface_spec`,
   `stdio_smoke`, `transport_spec`, `jobstore_spec`, `async_resource_spec`,
   `dpm_sync_spec`. A new suite list requires a reviewed recipe before the
   run. Do not start full `lake test` here.
3. Repeat the ZIP write twice from the same packaged bytes and require equal
   SHA-256. Members are `bin/` payloads, `README.txt`, and `BUILD.json`
   under `mirrors-$PROPOSED_TAG-windows-x86_64/`. No credential, source
   checkout, or `.lake` tree is a member.
4. PE import closure uses the rc.5 reviewed system set, compared
   case-insensitively: `ADVAPI32.dll`, `IPHLPAPI.DLL`, `KERNEL32.dll`,
   `SHELL32.dll`, `USER32.dll`, `USERENV.dll`, `WS2_32.dll`, `bcrypt.dll`,
   `dbghelp.dll`, `icu.dll`, `ole32.dll`, `ucrtbase.dll`, `msvcrt.dll`,
   `CRYPT32.dll`, `ntdll.dll`, plus `api-ms-win-*` and DLLs that are
   themselves package members. A new import aborts the package. Do not
   extend the set inside the run.
5. `BUILD.json` records tag, embedded version, `S2_COMMIT`, toolchain, file
   hashes, the smoke scope, `published: false`, and `deployed: false`.

Receipt: Windows rows of `package-set.json` with archive and external
manifest hashes, before/after source hashes, and the explicit limit "not
full `lake test`, not reproducible compilation, not release admission".
Exit fails if repeat packaging differs or any DLL is outside the closure.

## MW-60 — selected profile membership

Parser result for `m5-wsl-windows-remote`:

- `qualificationClass`: `local-candidate`
- `catalogVisibility`: `private`
- `requiredCommandIds`: 18
- `requiredTierIds`: 16
- Every required command and tier exists once in the registry.
- The command-derived tier set equals `requiredTierIds`.

`local-candidate` and `release-candidate` each require 16 commands and 15
tiers. They omit `framework.lease-origin-installed`,
`framework.reproduction-lease`, and tier `qualification.origin-lease`.
`release-candidate` is public and class `release-candidate`. It is not the
selected M5 profile. `source-validation` requires only
`mirrors.local-no-model` / `mirrors.required`.

Required M5 commands and their registry tiers:

| Command | Tier | Phase in `qualification_scope.py` |
| --- | --- | --- |
| `mirrors.local-no-model` | `mirrors.required` | `source-gate` |
| `mirrors.remote-model-check` | `mirrors.remote-model-check` | `source-gate` |
| `mirrors.interop` | `mirrors.interop` | `source-gate` |
| `mirrorecma.project-check` | `mirrorecma.project` | `source-gate` |
| `mirrorecma.test` | `mirrorecma.required` | `source-gate` |
| `mirrorgate.required` | `mirrorgate.required` | `source-gate` |
| `framework.install-diagnostics` | `qualification.install` | `distribution` |
| `framework.replay-correct` | `qualification.replay` | `replay` |
| `framework.replay-faulty` | `qualification.replay` | `replay` |
| `framework.lease-origin-installed` | `qualification.origin-lease` | `origin` |
| `framework.reproduction` | `qualification.reproduction` | `reproduction` |
| `framework.reproduction-lease` | `qualification.reproduction` | `reproduction` |
| `framework.reduction-prefix` | `qualification.reduction-prefix` | `reduction` |
| `framework.reduction` | `qualification.reduction-domain` | `reduction` |
| `framework.mutation-local` | `qualification.mutation-local` | `mutation` |
| `framework.mutation-gate` | `qualification.mutation-gate` | `mutation` |
| `mirrorgate.recovery` | `qualification.recovery` | `recovery` |
| `evidence.offline-verify` | `qualification.evidence` | none; Q only |

`catalog_links.py` requires a candidate Q bundle whose only command is
`evidence.offline-verify`. The scope must not credit that command. Credited
scope commands plus that Q command are what the profile's
`requiredCommandIds` are checked against. Extra credited command IDs are not
rejected by that check. Duplicate credit of one command ID is rejected.

Registry commands outside `requiredCommandIds`:

| Command | Role in this campaign |
| --- | --- |
| `framework.install-diagnostics-gate` | Stage-required second D binding. Same tier `qualification.install`, different command ID, so it can be credited beside the local D audit. Omitting it still satisfies the 18-command profile and fails the stage's two-binding gate. |
| `framework.recovery-origin-installed` | Graph origin for `mirrorgate.recovery`. `evidenceUse` is `retained-attempt`, not `qualification-credit`. The design's abrupt-stop origin is failed behavior and unconfirmed physical cleanup. |
| `mirrorgate.application-campaign.work-queue` | Supporting R0. Phase `origin`. Does not satisfy `framework.mutation-gate`. Not a required graph node for this profile. |
| `mirrorgate.application-campaign.persistent-transfer` | Same, supporting only. |
| `mirrorgate.application-campaign.lease-service` | Same, supporting only. |
| `framework.lease-origin` | Registered, tier `qualification.remote-lease-origin`, and absent from `COMMAND_PHASES`. It cannot appear in a v2 scope and is not a substitute for `framework.lease-origin-installed`. |

The 19-node scope that matches the verifier and the stage's two D bindings
is the 17 required producers other than Q, plus
`framework.install-diagnostics-gate`, plus the uncredited recovery origin.
The Q bundle is the 20th bundle and is outside the scope. That is a
structural expectation, not a claim that those runs exist.

Required artifact roles: `cache-index`, `cleanup-receipt`, `command-log`,
`distribution-manifest`, `producer-result`, `recovery-receipt`,
`reproduction-input`. Required cleanup scopes: `gate-physical`,
`gate-recovery`, `local-cooperative`. Required observation dimensions:
`installedConsumerAccepted`, `locallyAccepted`, `sourceTested`.

`collect.py` accepts a child argv only when `argv[:len(argvPrefix)]` equals
the registered prefix and `len(argv)` equals `argvLength`. Absolute paths
inside a prefix are not substitutable. Both install-diagnostics prefixes
still name `/tmp/mirrors-candidate-install-*-20261025`,
`/home/nzsn/Repos/Mirrors/.lake/build/bin/framework_catalog`, catalog SHA-256
`5a64a5bd40e999b20dd8268f2846c0f5ad5359067db9f014379c150e27d76126`, strace
SHA-256 `28f957c227012de0b18d1bd7fff2d396cb693ea60ed8013be68de071e84b5001`,
and hide roots under `/home/nzsn/Repos`. A new D prefix, C3 hash, or hide
root requires a reviewed registry edit before MW-61 can collect those two
commands. This handoff does not edit the registry.

## Shared collector contract

Run from the admitted Mirrors source root that matches the frozen component
identity. Store `EVIDENCE_STORE` is outside the checkout and outside `/tmp`,
mode `0700`, files mode `0600`. `C0_SHA256` is the frozen catalog selection,
kind `sha256`. Do not pass `git-revision` for a dirty catalog.

```sh
python3 tools/evidence/collect.py \
  --store "$EVIDENCE_STORE" \
  --registry tools/evidence/commands.json \
  --command-id "$COMMAND_ID" \
  --cwd "$CWD" \
  --catalog-selection-kind sha256 \
  --catalog-selection-value "$C0_SHA256" \
  --component mirrors="$MIRRORS_ROOT" \
  -- \
  $ARGV
python3 tools/evidence/finalize.py \
  "$EVIDENCE_STORE/staging/$RUN_ID" \
  --store "$EVIDENCE_STORE"
python3 tools/evidence/verify.py --offline \
  "$EVIDENCE_STORE/runs/$RUN_ID"
```

Add every component the command's phase requires. Source-gate ownership from
`SOURCE_COMMAND_COMPONENTS` is exact: `mirrors.local-no-model` and
`mirrors.remote-model-check` are `{mirrors}`; `mirrors.interop` is
`{mirrors, mirrorecma, mirrorgate}`; both MirrorECMA gates are
`{mirrors, mirrorecma}`; `mirrorgate.required` is `{mirrors, mirrorgate}`.
Installed and distribution nodes must use the component set of their credited
D manifest (`D_LOCAL_COMPONENTS` or `D_GATE_COMPONENTS`). `--cwd` for an
installed command is the absolute canonical `MIRRORS_INSTALLED_RUNTIME` or,
for Gate commands, `MIRRORS_INSTALLED_GATE_RUNTIME` plus the registered
subdirectory. It is not the source checkout.

Attachment plans are `mirrors.evidence-attachment-plan/v1`. Outputs match
`attachmentOutputs` in order, including artifact ID, relative path, role,
media type, requirement, capture mode, max bytes, and producer result.
`attachmentRootArgIndex` or `attachmentPathArgIndex` must point at the plan
root or at a file whose parent is that root. New outputs are absent
beforehand and mode `0600` after the child. Existing inputs are hashed
before the child. The plan is `blocking` per command because the run IDs and
byte hashes do not exist yet.

Finalize is per run, index-last, and never overwrites a run ID. A non-zero
child status stays failed. Cleanup must be confirmed by the adapter, not by
exit 0. No local Apalache or TLC on the WSL coordinator. `lake test` is not
a substitute for `mirrors.local-no-model`.

## MW-61 — producer commands

Depends on MW-53. Remote reduction and `mirrors.remote-model-check` also
depend on MW-54. Each row is one collect/finalize/verify triple. Failures
are retained. A retry uses a new run ID.

### Source gates

`mirrors.local-no-model`, cwd = mirrors component, argv length 2, no
attachment plan:

```contract-argv
mirrors.local-no-model
bash
tools/run-local-no-model-check.sh
```

`mirrorecma.project-check` and `mirrorecma.test`, cwd = mirrorecma
component, argv length 3:

```contract-argv
mirrorecma.project-check
pnpm
run
check
```

```contract-argv
mirrorecma.test
pnpm
run
test
```

`mirrorgate.required`, cwd = mirrorgate component, argv length 2. An
unavailable required backend stays an incomplete tier.

```contract-argv
mirrorgate.required
bash
scripts/test.sh
```

`mirrors.remote-model-check`, cwd = mirrors component, argv length 2.
`requiredEnvironment` values are the registry literals: Apalache `0.62.2`,
archive `7cfadf6e8c04c63f05ac907ec9541c66297005c8cb5efb1731f6a838dfc3fad2`,
jar `079b6c2320252469dcf79afec6886b8255d3dd1b34a9484433c88986752efaa8`, Java
selected `25.0.4+7`, observed `25.0.4+7-LTS`, archive
`54ba13f3ef80887fa74708b2a32daaae6262517ba68433d850bb4b426343172b`,
`java.exe` `58df5c13e5d6e68f242ad9b724479122828523008ef0907d3f2a02f54afaff23`.
Names that must be set and must not be copied from October observations:
`MIRRORS_REMOTE_CA`, `MIRRORS_REMOTE_CLIENT_CERT`,
`MIRRORS_REMOTE_CLIENT_KEY`, `MIRRORS_REMOTE_SERVER_PIN`,
`MIRRORS_REMOTE_SERVICE_BINARY_SHA256`,
`MIRRORS_REMOTE_SERVICE_SOURCE_REF`, `MIRRORS_REMOTE_ADMIN_OBSERVATION`,
`MIRRORS_REMOTE_HOST`, `MIRRORS_REMOTE_PORT`. Credential paths are private
files. Their bytes never enter argv, the registry, or this card.
`run_remote_model_check.py` checks the observation against the pin, binary,
and source ref before contact. Host and port are both required.

```contract-argv
mirrors.remote-model-check
python3
tools/evidence/run_remote_model_check.py
```

### Distribution audits

Both commands are blocked on a registry edit if the new prefix, C3 binary,
C3 SHA-256, strace SHA-256, or hide roots differ from the frozen prefix.
Until that edit lands, the only argv `collect.py` will accept is the
registered one. The trailing argument is the new audit JSON inside the
attachment root.

Local, argv length 22, path index 21:

```contract-argv
framework.install-diagnostics
/usr/bin/python3
verification/bundle/tools/distribution/qualification.py
--prefix
/tmp/mirrors-candidate-install-local-20261025
--framework-catalog-bin
/home/nzsn/Repos/Mirrors/.lake/build/bin/framework_catalog
--framework-catalog-sha256
5a64a5bd40e999b20dd8268f2846c0f5ad5359067db9f014379c150e27d76126
--bwrap
/usr/bin/bwrap
--strace
/usr/bin/strace
--strace-sha256
28f957c227012de0b18d1bd7fff2d396cb693ea60ed8013be68de071e84b5001
--hide-root
/home/nzsn/Repos/Mirrors
--hide-root
/home/nzsn/Repos/MirrorECMA
--hide-root
/home/nzsn/Repos/MirrorGate
--audit-out
AUDIT_OUT/install-diagnostics.json
```

Gate, argv length 24, path index 23. The extra frozen pair is
`--combination candidate.node-gate`.

```contract-argv
framework.install-diagnostics-gate
/usr/bin/python3
verification/bundle/tools/distribution/qualification.py
--prefix
/tmp/mirrors-candidate-install-gate-20261025
--framework-catalog-bin
/home/nzsn/Repos/Mirrors/.lake/build/bin/framework_catalog
--framework-catalog-sha256
5a64a5bd40e999b20dd8268f2846c0f5ad5359067db9f014379c150e27d76126
--bwrap
/usr/bin/bwrap
--strace
/usr/bin/strace
--strace-sha256
28f957c227012de0b18d1bd7fff2d396cb693ea60ed8013be68de071e84b5001
--hide-root
/home/nzsn/Repos/Mirrors
--hide-root
/home/nzsn/Repos/MirrorECMA
--hide-root
/home/nzsn/Repos/MirrorGate
--combination
candidate.node-gate
--audit-out
AUDIT_OUT/install-diagnostics-gate.json
```

Cwd is `MIRRORS_INSTALLED_RUNTIME` or `MIRRORS_INSTALLED_GATE_RUNTIME`.
Each plan captures the new audit plus existing `distribution-manifest.json`
and `cache-index.json`. Those two inputs are copied into the attachment
root before collection. Their hashes become the D binding that later Q
compares. Hide roots must be the real source checkouts of this candidate
after the registry edit; the paths above are the current registry bytes.

### Replay, lease origin, and reproduction

Cwd is `MIRRORS_INSTALLED_RUNTIME`. Relative executables resolve there.

Replay, argv length 4, root index 3. Correct mode must pass with confirmed
local cleanup. Faulty mode must retain the normalized mismatch, not merely
exit non-zero.

```contract-argv
framework.replay-correct
runtimes/node/bin/node
applications/examples/application-validation/installed-project-replay.mjs
correct
PRIVATE_OUTPUT
```

```contract-argv
framework.replay-faulty
runtimes/node/bin/node
applications/examples/application-validation/installed-project-replay.mjs
faulty
PRIVATE_OUTPUT
```

Lease origin, argv length 3, root index 2. Adapter application is
`lease-faulty`. The plan requires new `lease-origin.json` and
`lease-baseline.json`, both `mirrorecma.suite-result/v1`. Baseline passes
before the fault. The installed wrapper is the authority for the mismatch
coordinate; do not copy a historical trace/state pair into the claim unless
that wrapper emits it.

```contract-argv
framework.lease-origin-installed
runtimes/node/bin/node
verification/bundle/tools/evidence/installed-lease-origin.mjs
PRIVATE_OUTPUT
```

`framework.reproduction` and `framework.reproduction-lease` have argv length
19 and root index 18. The registered prefix ends at `--bundle`. Current
MirrorECMA `src/cli.ts` at `f943588` requires `--evidence-envelope` and
`--output-root` and optionally accepts `--artifact-store`. The capture
script writes inline captures only, so the store is not consulted for those
bundles. `--tool-registry` is the other length-fitting flag and is not
selected: passing it overrides `installedRegistry`. Exactly one of those
optional flags is required by `argvLength`. The selected suffix is
`--artifact-store` of an owner-only directory created for the run.

Index 12 is `PRIVATE_OUTPUT/reproduction-bundle.json` and must be absent
before capture. Index 14 is the existing `r0-envelope.json` inside that
same root. Index 18 is the attachment root.

Reference-project branch, bound later to `framework.replay-faulty`:

```contract-argv
framework.reproduction
runtimes/node/bin/node
packages/mirrorecma/dist/cli.js
reproduce
--project
applications/reference-project/mirror.faulty.project.json
--framework-input
framework-input.json
--combination
candidate.local-node-checked
--server
bin/ModelMirrors
--bundle
PRIVATE_OUTPUT/reproduction-bundle.json
--evidence-envelope
PRIVATE_OUTPUT/r0-envelope.json
--artifact-store
ARTIFACT_STORE
--output-root
PRIVATE_OUTPUT
```

Lease branch, bound later to `framework.lease-origin-installed`. The prefix
project is `applications/lease-project/mirror.faulty.project.json`. The
remaining suffix matches the reference branch.

```contract-argv
framework.reproduction-lease
runtimes/node/bin/node
packages/mirrorecma/dist/cli.js
reproduce
--project
applications/lease-project/mirror.faulty.project.json
--framework-input
framework-input.json
--combination
candidate.local-node-checked
--server
bin/ModelMirrors
--bundle
PRIVATE_OUTPUT/reproduction-bundle.json
--evidence-envelope
PRIVATE_OUTPUT/r0-envelope.json
--artifact-store
ARTIFACT_STORE
--output-root
PRIVATE_OUTPUT
```

`collect.py` runs `verification/bundle/tools/evidence/reproduction-capture.mjs`
before the registered command and refuses if the R0 suite bytes differ from
the envelope. The child must exit 0 and the producer result status must be
`reproduced` with confirmed local-cooperative cleanup.

### Reductions

Prefix reduction, cwd = local runtime, argv length 26, root index 17.
Current `scripts/reduce-reproduction-prefix.mjs` at ECMA `f943588` requires
the eight flags through `--output-root`. `argvLength` then requires four
more pairs. Those pairs are the driver's own `POLICY_DEFAULTS`, passed
explicitly: candidate limit `64`, total `600000`, per candidate `60000`,
cleanup `10000`. The October 1 qualified bounds `40/300000/45000/10000` are
not the current parser defaults and are not used. Project and combination
match the reference reproduction prefix so the R1 bundle is the same
authority. This command depends on finalized `framework.reproduction`.
It does not start a model checker.

```contract-argv
framework.reduction-prefix
runtimes/node/bin/node
packages/mirrorecma/scripts/reduce-reproduction-prefix.mjs
--project
applications/reference-project/mirror.faulty.project.json
--bundle
PRIVATE_OUTPUT/prefix-reduction-original-bundle.json
--stability
PRIVATE_OUTPUT/prefix-reduction-stability.json
--original-trace
PRIVATE_OUTPUT/prefix-reduction-original-trace.json
--framework-input
PRIVATE_OUTPUT/prefix-reduction-framework-input.json
--combination
candidate.local-node-checked
--evidence-envelope
PRIVATE_OUTPUT/prefix-reduction-r0-envelope.json
--output-root
PRIVATE_OUTPUT
--candidate-limit
64
--total-budget-ms
600000
--per-candidate-budget-ms
60000
--cleanup-budget-ms
10000
```

The existing inputs are the finalized R1 bundle and its R0 envelope, trace,
framework input, and stability record, copied under those relative names.
The new output is `prefix-reduction-result.json`
(`mirrorecma.reproduction-prefix-reduction/v1`). The reproduction-input hash
must equal the R1 bundle hash.

Domain reduction, argv length 28, path index 17. The wrapper
`installed-lease-reduction.mjs` asserts 26 arguments after the node/script
pair and forwards them to `materialize-lease-reduction.mjs`. Remote mode is
required. Local mode would not include the four TLS flags and would miss
`argvLength`. Depends on finalized `framework.reproduction-lease` and on
MW-54. No local Apalache or Java is started; the materializer's remote mode
talks to the admitted endpoint. Credential paths are private files.

```contract-argv
framework.reduction
runtimes/node/bin/node
verification/bundle/tools/evidence/installed-lease-reduction.mjs
--candidate
PRIVATE_OUTPUT/lease-reduction-candidate.json
--bundle
PRIVATE_OUTPUT/lease-reduction-original-bundle.json
--model
PRIVATE_OUTPUT/lease-reduction-model.tla
--lock
PRIVATE_OUTPUT/lease-reduction-lock.json
--original-trace
PRIVATE_OUTPUT/lease-reduction-original-trace.json
--tool-manifest
PRIVATE_OUTPUT/lease-reduction-tool-manifest.json
--out
PRIVATE_OUTPUT/lease-reduction-candidate-trace.json
--receipt
PRIVATE_OUTPUT/lease-reduction-receipt.json
--oracle-mode
remote
--service-identity
PRIVATE_OUTPUT/lease-reduction-service-identity.json
--tls-ca
TLS_CA
--tls-cert
TLS_CERT
--tls-key
TLS_KEY
```

Tool manifest schema is `mirrorecma.lease-reduction-tools/v2` with mode
`remote`. Receipt schema is `mirrorecma.lease-reduction-oracle/v2`. The
acceptance artifact `lease-reduction-acceptance.json`
(`mirrors.lease-reduction-acceptance/v1`) is written beside the receipt.
`globalMinimumClaim` stays false. The original bundle bytes must equal the
lease R1 reproduction input.

### Mutation and recovery

Local mutation, cwd = local runtime, argv length 7, path index 6:

```contract-argv
framework.mutation-local
runtimes/node/bin/node
applications/examples/application-validation/run.mjs
all
--prevalidated-registry
installed-registry.json
--receipt
PRIVATE_OUTPUT/local-application-campaigns.json
```

The adapter requires the closed WorkQueue, PersistentTransfer, and
LeaseService aggregate `mirrorecma.application-campaign-aggregate/v1` and
confirmed local cleanup. One application does not satisfy the command.

Gate mutation, cwd = `MIRRORS_INSTALLED_GATE_RUNTIME`, argv length 3, root
index 2. Depends on the Gate D binding, not on the three source campaign
commands.

```contract-argv
framework.mutation-gate
runtimes/node/bin/node
packages/mirrorgate-mirrorecma/scripts/application-program-gate-all.mjs
PRIVATE_OUTPUT
```

The plan's three new receipts are `work-queue-gate-receipt.json`,
`persistent-transfer-gate-receipt.json`, and
`lease-service-gate-receipt.json`, each
`mirrorgate.application-validation/v2`, with confirmed `gate-physical`
cleanup.

Recovery origin, cwd = Gate runtime, argv length 3, root index 2. This run
is retained and not credited. `PYTHONPATH` is a registered required name and
must point at the installed Gate supervisor packages, not a source checkout.

```contract-argv
framework.recovery-origin-installed
/usr/bin/python3
verification/bundle/tools/evidence/installed-recovery-origin.py
PRIVATE_OUTPUT
```

Plan: new `recovery-origin.json` (`mirrors.recovery-origin/v1`) and existing
`recovery-manifest.json`. Expected behavior is failed and physical cleanup
unconfirmed. If the actual receipt differs, keep the actual values and do
not relabel the run so recovery can be credited.

`mirrorgate.recovery`, cwd =
`MIRRORS_INSTALLED_GATE_RUNTIME/gate/mirrorgate-supervisor`, argv length 17,
path index 16. The inspected Gate CLI at sibling `4ef786b3` requires
`--state-root` and, when any original field is set, all four of `--run-ref`,
`--envelope-sha256`, `--original-behavior`, and `--original-cleanup`.
`--cgroup-parent` does not fit `argvLength` 17. Prepared-filesystem recovery
omits it. Aggregate cgroup enforcement stays out of this profile. Re-read
`supervisor/mirrorgate/cli.py` at `ADMITTED_GATE_SHA` before execution; this
sibling SHA is not a registry pin.

```contract-argv
mirrorgate.recovery
/usr/bin/python3
-m
mirrorgate.cli
recovery
reclaim
--state-root
RECOVERY_STATE_ROOT
--run-ref
ORIGIN_RUN_ID
--envelope-sha256
ORIGIN_ENVELOPE_SHA256
--original-behavior
ORIGIN_BEHAVIOR
--original-cleanup
ORIGIN_CLEANUP
--receipt
PRIVATE_OUTPUT/recovery-receipt.json
```

`ORIGIN_*` are copied from the finalized recovery-origin private run.
`ORIGIN_BEHAVIOR` is one of `passed`, `failed`, `inconclusive`, `not_run`.
`ORIGIN_CLEANUP` is one of `confirmed`, `failed`, `unconfirmed`,
`not_applicable`. The receipt is `mirrorgate.recovery-receipt/v1` and must
name that origin. Only an all-reclaimed receipt establishes `gate-recovery`.
`RECOVERY_STATE_ROOT` is the origin's prepared state root.

Producer exit gate: every required M5 command except `evidence.offline-verify`
has one qualified finalized run, both D audits are finalized, the recovery
origin is finalized and uncredited, and no required command was skipped or
replaced by a supporting origin. Remote rows also have a same-time
observation. Cleanup after owned processes is recorded.

## MW-62 — remote 22-row clients

This is `mirrors.interop`, not a second command. `tools/interop/run-remote.py`
builds the 22 rows. The legacy `tools/interop/run.sh` all-transport matrix
must not be started. Argv length 3, attachment root index 2.

```contract-argv
mirrors.interop
python3
tools/interop/run-remote.py
OUTPUT_ROOT
```

`requiredEnvironment` literals: `INTEROP_VERIFY_PINS=1`, `ECMA_REF`
`f94358834dce2e527c8bc8feec0423a54cf4176c`, `CPP_REF`
`8c542a6b1339cc0b6176465ff7f17a32e614553d`, `RUST_REF`
`6b9480ab81717b76ca7f74b41fc554578b70c890`, `HS_REF`
`4aa693f86e18349bb97c050dd33aecbf730b6fa2`, `LEAN_CLIENT_REF`
`a8634ebe2455f97d15b55bec3c810d945cb6e3d3`. File hashes: `HS_BIN`
`cc3c378e31f2632bf96fcdcb127f902b7cdee0cead40e51d7911976e8a6e3e9d`, `CPP_BIN`
`5db2b6a3fd992d894d305dafbea93d8795af4137b769d7e7b22ea4de31853480`,
`RUST_BIN` `d7af87983f4600121d01b4f4b2e780cf5e66e0f6b79d57e3ba234d2d980f20be`,
`LEAN_CLIENT_BIN`
`b02fa982ac20e7a245bde59e9e5eb060609809349fe4634bc914b8a5d36a523c`,
`ECMA_NODE_BIN`
`d1de76d8edf2fededf6f8b30d244e2c0529ac607923a018283b77e9c74bd932c`.

Names that are paths or observations, not literals: `ECMA_REPO`, `CPP_REPO`,
`RUST_REPO`, `LEAN_CLIENT_REPO`, `HS_REPO`, `HS_BIN`, `CPP_BIN`, `RUST_BIN`,
`LEAN_CLIENT_BIN`, the three mTLS paths, `MIRRORS_REMOTE_SERVER_PIN`,
`MIRRORS_REMOTE_ADMIN_OBSERVATION`, `MIRRORS_REMOTE_SERVICE_BINARY_SHA256`,
`MIRRORS_REMOTE_SERVICE_SOURCE_REF`, `ECMA_RUNTIME_ROOT`, `ECMA_NODE_BIN`,
`MIRRORS_REMOTE_HOST`, `MIRRORS_REMOTE_PORT`, `MIRRORS_REMOTE_INTEROP_ROOT`.
`MIRRORS_REMOTE_INTEROP_ROOT` must be set so the driver uses the observed
Windows fixture root. The unset branch writes `/mnt/c/Users/ayden/Desktop/Workspace/MirrorsRemote/interop`
and is not this profile. Each client `git rev-parse HEAD` must equal its
`*_REF`. The observation's `interopFixtures` must name that root and the
hashes of `specs/Counter.tla` and `specs/traces/violation.itf.json` from
`ECMA_RUNTIME_ROOT`.

Rows, in driver order. Verdict rows are `valid` (`Inv`, bound 3, exit 0,
stdout `VALID`), `invalid` (exit 1; Lean stderr starts `spec invalid: `;
ECMA stdout is one `INVALID ` plus a JSON object whose only key is
`invalid`; other clients stdout `INVALID`), and `wrong-pin` (zero pin,
fingerprint-mismatch text, exits cpp/haskell/rust 2 and lean/ecma 1):

| # | Client | Case |
| --- | --- | --- |
| 1 | cpp | valid |
| 2 | cpp | invalid |
| 3 | cpp | wrong-pin |
| 4 | haskell | valid |
| 5 | haskell | invalid |
| 6 | haskell | wrong-pin |
| 7 | rust | valid |
| 8 | rust | invalid |
| 9 | rust | wrong-pin |
| 10 | lean | valid |
| 11 | lean | invalid |
| 12 | lean | wrong-pin |
| 13 | ecma | valid |
| 14 | ecma | invalid |
| 15 | ecma | wrong-pin |
| 16 | ecma | register |
| 17 | ecma | mismatch |
| 18 | ecma | register_traces |
| 19 | ecma | register_trace_gen |
| 20 | ecma | register_explore |
| 21 | ecma | register_explore_session |
| 22 | ecma | inline_multimodule |

The protocol receipt's `rows` must equal those seven cases with
`status: passed`, in that order. The v2 receipt
`mirrors.remote-interop/v2` and `ecma-runtime-pin.json` are required
attachments. Haskell certificate-expiry warnings and the Lean seven-day
warning are the only allowed stderr on success. A row failure retains its
log and fails the command. Before/after observations of the endpoint,
fixtures, and client binaries are part of the receipt. No credential bytes
are printed; paths are redacted to `<private-credential-path>`.

Exit: 22 passing rows, pins unchanged, and a finalized `mirrors.interop`
run. This does not renew an older platform qualification.

## MW-63 — three installed DPM profiles

One command produces three profile receipts. The profiles are the language
loop `cpp`, `ecma`, `rust` in
`tools/deterministic-scheduling/check_cli_installed.py`. They are not the
distribution profiles `checked-replay-local`, `checked-replay-gate`, and
`fresh-trace`. `freshModelCheck` is a result field set to JSON `false`, not
a CLI flag. `tools/deterministic-scheduling/check_installed.py` is a
different portable gate and is not this card.

The entrypoint refuses any interpreter other than `python3 -I -S -B`.
`--help` under that interpreter was checked. Helper pins in the source match
the current files: `dpm_host.py`
`e6177f91bda1088cb711e6c1c4848d23eecfcd60755e0b00f35556daa7bd8e88`,
`install_cli.py`
`ac0a1cc94db3be91a746e18baef15869d33dcbdd998a4706e0abae6587ed1059`. If either
file changes, the gate refuses until the pin is reviewed. Do not refresh it
in this campaign without that review.

`blocking` inputs: `INSTALLED_DPM` (admitted installed tree containing
`ecma/application.json`), `RUST_TOOLCHAIN`, `DPM_OUT` (absent directory),
`CMAKE`, `CXX`, and the source roots to hide. Optional `--tool-root`
repeats for each admitted compiler/runtime path that `bwrap` must see.
Bubblewrap must be permitted to create a network namespace. Default hidden
roots are the Mirrors checkout parent plus `MirrorCPP`, `MirrorECMA`, and
`MirrorRust`; pass them explicitly.

```sh
python3 -I -S -B tools/deterministic-scheduling/check_cli_installed.py \
  --installed "$INSTALLED_DPM" \
  --rust-toolchain "$RUST_TOOLCHAIN" \
  --out "$DPM_OUT" \
  --cmake "$CMAKE" \
  --cxx "$CXX" \
  --hidden-source "$MIRRORS_ROOT" \
  --hidden-source "$MIRRORCPP_ROOT" \
  --hidden-source "$MIRRORECMA_ROOT" \
  --hidden-source "$MIRRORRUST_ROOT"
```

The outer process writes `command.json` and runs `bwrap --die-with-parent
--unshare-net` with the installed tree read-only at `/tmp/admitted`. The
inner run builds a fresh consumer per language and must record, for each
profile, `status: passed`, `sourceHidden: true`,
`networkNamespaceIsolated: true`, and `freshModelCheck: false`. The aggregate
`work/acceptance.json` is `mirrors.dpm-cli-installed-acceptance/v1` with
those three profiles and the same `freshModelCheck: false`. Controls that
must have run are the names in the script: `tampered_mapping`,
`tampered_runtime`, `unsupported_profile`, `tampered_oracle`,
`bounded_search`, `cleanup_failure`, `isolated_host_import`,
`isolated_app_import`, `request_output_overflow`,
`aggregate_output_overflow`, `launcher_policy_argument_refused`. The sync
returning-callback overrun must be `refused`.

Exit fails if any language is absent, `freshModelCheck` is true, a checkout
is visible, or the network namespace is shared. This is installed DPM
acceptance, not M5 command credit and not a fresh model comparison.

## MW-64 — full Windows acceptance

Depends on MW-32, MW-54, and explicit long/full build approval. Host is the
admitted Windows live-check host, not the WSL coordinator. Do not start this
`lake test` on the coordinator: the driver runs
`tools/check-async-protocol.py --quick` and can probe a local Apalache.

```sh
export MIRRORCPP_PREFIX="$ADMITTED_MIRRORCPP_PREFIX"
lake test
```

`MIRRORCPP_PREFIX` is `blocking`. If it is unset, `lakefile.lean` prints
`SKIP native integer maps: set MIRRORCPP_PREFIX to the prepared MirrorCPP package`
and continues. That skip fails a full-acceptance claim even when the driver
later prints `ALL LAKE TESTS GREEN`. Live Apalache-backed specs must not be
replaced by the earlier eight-suite package smoke. A skipped live tier stays
skipped and blocks the full-suite claim.

The driver also links the TLS shim into the native test binaries and runs
`transport_spec`, the model-interface `check` commands for `mirrorecma-v1`,
`mirrorecma-async-v1`, `mirrorcpp-v1`, and `mirrorrust-v1`, and
`model_interface_gen preflight`. Those are the compiler/runtime/TLS gates
inside this one driver. `MIRRORS_ASYNC_RESOURCE_E2E=1` is opt-in and is not
required for the declared full run.

Receipt: `windows-acceptance.json` with host identity, `MIRRORCPP_PREFIX`,
exit code, the integer-map non-skip line, and every skipped tier. Exit is
code 0, no integer-map skip, and no required live tier reported skipped.
Package smoke from MW-32 remains a separate, narrower receipt.

## Unresolved inputs

`S2_COMMIT`, `PROPOSED_TAG`, embedded-version authorization, clean clone
path, `EMPTY_DIST`, Linux and Windows host facts, `EVIDENCE_STORE`,
`C0_SHA256`, both D prefixes and component refs after a registry edit, C3
and strace identities, `MIRRORS_INSTALLED_RUNTIME`,
`MIRRORS_INSTALLED_GATE_RUNTIME`, remote endpoint and observation,
credential paths, `ADMITTED_GATE_SHA`, DPM install and Rust toolchain,
`MIRRORCPP_PREFIX`, and every attachment hash. None of these were inferred.
