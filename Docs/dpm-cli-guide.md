# Installed DPM replay, exploration and reduction

The `mirrors-dpm` tool runs application-owned C++/Node-worker/Rust-thread
runners. It admits the project's selected digest and artifact closure before
application acquisition. The [runner contract](dpm-runner-contract.md) defines
ownership, schema, oracle authority, process lifetime and exact acceptance scope.

## Build and runtime prerequisites

Build the Lean launcher with `lake build mirrors_dpm`. Before compiling its
modules, Lake runs the identity generator with `python3` from the build's `PATH`.
Set `MIRRORS_DPM_PYTHON` to select another interpreter explicitly:

```sh
MIRRORS_DPM_PYTHON=/path/to/python3 lake build mirrors_dpm
.lake/build/bin/mirrors_dpm --help
```

The generator resolves the selected interpreter's actual executable path and
hashes its bytes and the four packaged host files. It writes
`.lake/build/dpm-generated/Shell/Dpm/HostIdentity.lean`; the launcher compiles
those constants. `lake build`, `lake build Shell` and direct launcher builds
prepare this dependency automatically. An unchanged build preserves the generated
file and compiled outputs; a changed interpreter path, interpreter bytes or host
file rebuilds the launcher. Ordinary `lake build mirror` does not require this
DPM dependency. Builds do not rewrite tracked source identities.

`MIRRORS_DPM_PYTHON` selects a build input, not a runtime override. Keep it set
for builds that should retain a nondefault interpreter. An installed launcher
requires the exact compiled interpreter path and hash, even after relocating the
package. After an interpreter upgrade or a move to another host, rebuild and
prepare a new package with its own identities and acceptance evidence. Existing
installation and historical acceptance records remain unchanged.

The installer and installed-gate scripts also contain reviewed helper pins.
After changing their helper sources, explicitly refresh these tracked pins with
`python3 -I -S -B tools/deterministic-scheduling/refresh_host_identity.py --helpers-only`
and review the diff before rebuilding. The build checks them and refuses stale
pins. To check the generated identity without writing, run the same selected
interpreter with `-I -S -B tools/deterministic-scheduling/refresh_host_identity.py --check`.
`python3 tools/check-dpm-build.py` exercises regeneration, incremental builds,
runtime refusals and interpreter selection in a disposable checkout.

Changed host code or interpreter bytes cannot execute through an old launcher.
Run preparation, installer, identity refresh and installed-gate scripts with
Python's `-I -S -B` flags; their verified helper loading does not search adjacent
modules or bytecode. The OS standard library, extension modules and loader remain
trusted platform prerequisites; the interpreter executable hash is not a hermetic
Python installation.
Node is required only for Node application runners. Replay/report do not compile
applications, download packages or start a model checker.

The launcher selects the pure policy executable internally. Public command
arguments cannot replace that selection.

## Select and run a project

The trusted `--project-sha256` comes from the selected build/install manifest,
not merely a digest accepted from an unknown downloaded project.

```sh
mirrors-dpm doctor --project ./project.json --project-sha256 SELECTED_DIGEST
mirrors-dpm replay --project ./project.json --project-sha256 SELECTED_DIGEST --out ./new-replay
mirrors-dpm reduce --project ./project.json --project-sha256 SELECTED_DIGEST --out ./new-reduction
mirrors-dpm explore --project ./project.json --project-sha256 SELECTED_DIGEST --space catalog --out ./new-catalog
mirrors-dpm explore --project ./project.json --project-sha256 SELECTED_DIGEST --space sdk --out ./new-exploration
mirrors-dpm report --receipt ./new-replay/receipt.json --expected-sha256 TRUSTED_RECEIPT_DIGEST --format text
```

Projects use `mirrors.dpm-project/v2`; reprepare executable v1 projects. Typed
native/Python commands distinguish admitted artifact paths from literal argv
arguments, and Python isolation flags are supplied by the host. The nullable
`explorerIdentity` explicitly selects the SDK explorer identity; `--space sdk`
refuses without it. A separately built C++ explorer has its own identity.

Output directories must be new. Raw SDK receipts, request/response bindings and
bounded process logs remain available. `outputBytes` applies to each request;
`totalOutputBytes` counts all retained operation files, including duplicate raw
and enveloped receipts, generated request inputs, typed-check files and host
reports. Existing project inputs are excluded. A final-report reserve and fresh
best-replay allowance prevent a truncated search from claiming minimality.
These are acceptance/accounting limits, not hard OS disk or memory quotas:
direct writes can overshoot polling. Failed raw evidence stays unchanged and a
bounded refusal report records measured retention/overshoot; overflow exits 2. A mismatch exits 1; refusal, incomplete
execution and cleanup failure exit 2. Successful bounded reduction exits 0
while reproducing the failure; this does not establish conformance.

`--space catalog` actually compares each admitted candidate to its matching
retained model trace. `--space sdk` invokes the SDK's existing finite actor-chain
explorer. Its local coverage/denominator does not supply model comparison;
`modelComparison: false` remains explicit. An incomplete or unknown denominator
cannot become complete coverage.

## Reduction scope

The first generic policy searches an explicit finite, oracle-backed candidate
catalog. It preserves each retained actor's full local chain, orders candidates
by actor count/input rank/preemptions/step count, reproduces the baseline twice,
and freshly replays the best candidate. `minimal_in_admitted_catalog` means the
conclusively tested admitted space only. Exhausted budgets or unresolved trials
yield `best_observed`; cleanup loss stops further trials.

Applications provide meaningful input ranks, subset-capable factories, and exact
trace correspondence. A materializer cannot invent expected states or assert
model validity with a standalone Boolean. The host verifies source/request/
reply/corpus hashes of selected retained remote captures and their correspondence
to the candidate. Existing captures may be reused explicitly; this is not fresh
model generation. New capture preparation uses the reobserved remote service.

The Counter consumer example normalizes only the declared `write/count` integer
delta. It rejects changes to unrelated observed fields. Its removable spectator
is an actual model-inert initialization worker; removing it changes the factory
and complete schedule. The example does not qualify arbitrary actor removal in
other applications.

## Package and install

`prepare_cli.py` is a reviewed Counter application packaging example. It consumes
compiled SDK runners, optionally includes explicit SDK consumer development kits,
and copies selected retained oracles byte-for-byte. Other applications implement
the same runner contract with their own behavior and reviewed oracle mapping.

```sh
python3 -I -S -B tools/deterministic-scheduling/install_cli.py manifest --source PREPARED_TREE --out NEW_MANIFEST.json
python3 -I -S -B tools/deterministic-scheduling/install_cli.py install --source PREPARED_TREE \
  --manifest NEW_MANIFEST.json --manifest-sha256 SELECTED_MANIFEST_DIGEST --dest NEW_PREFIX
```

The installer verifies content and executable modes, stages a complete tree,
runs read-only admission, and uses Linux atomic no-overwrite activation. An
existing destination remains intact. Upgrade activation into an occupied prefix
is intentionally unsupported; select a new prefix. Relocation within the admitted
runtime platform preserves the relative project/artifact references.

`check_cli_installed.py` rebuilds fresh consumers from packaged SDK prerequisites
with checkouts hidden and Linux networking isolated. It runs actual match,
mismatch, finite exploration, reduction, timeline, tamper, bounded-search and
cleanup controls. Its public C++ controlled-resource sample is a separate local
prototype check, with `modelComparison: false`.

## Experimental controlled resources

F5 provides the separate C++ `mirrorcpp.controlled-sync-experimental/v1` SDK
module. The ordinary checkpoint CLI profiles do not silently admit its extra
resource boundaries or perform resource-aware reduction. The CLI can render its
actual receipts. A generated model binding needs an explicit reviewed adapter.
See the [C++ resource guide](../../MirrorCPP/docs/controlled-synchronization.md).

## Finite controlled mutex/FIFO comparison

`compare-sync` consumes a completed real C++ controlled-resource receipt and
validates its decision/observation witness against the independently reviewed
model through a selected remote Mirrors CLI. Its separate result schema is
`mirrors.controlled-sync-model-comparison/v1`; the raw SDK v1 receipt retains
`modelComparison:false`. A model rejection exits 1; incomplete admission,
transport, deadline or cleanup exits 2. A completed match exits 0.

```sh
mirrors-dpm compare-sync \
  --receipt native.json --receipt-sha256 SELECTED_RECEIPT_SHA \
  --mapping mapping.json --mapping-sha256 SELECTED_MAPPING_SHA \
  --implementation ./native --model specs/ControlledMutexFifo.tla \
  --mirror ./mirror --mirror-sha256 SELECTED_MIRROR_SHA \
  --remote remote.json --remote-sha256 SELECTED_REMOTE_CONFIG_SHA \
  --out ./new-comparison
```

Select hashes from the reviewed build manifest. The mapping pins the model and
implementation hashes; an input's self-asserted identity is insufficient. The
new output directory retains the original native receipt, typed admission,
witness, exact model/query, fresh remote observation and bounded verdict logs.
`report --receipt new-comparison/result.json --expected-sha256 TRUSTED_RESULT_SHA`
checks the complete retained artifact inventory.

The selected remote config binds the endpoint, mTLS pin, credential paths,
server source/binary, Apalache JAR and Java 25.0.4+7 identities. Observations
must be fresh within 300 seconds and the certificate unexpired. Future clock
tolerance defaults to zero; an explicitly measured `clockSkewSeconds` is bounded
at five. For credentials already on the coordinator, direct mTLS is supported.
The `ssh-windows` execution mode instead pins SSH, its configuration and a fixed
remote helper; only public model sources and verdict evidence cross SSH. Keys
remain on the remote host. See
[the finite profile contract](dpm-controlled-model-comparison.md) and
[the acceptance record](../Plans/completion-evidence-20261029/README.md).
