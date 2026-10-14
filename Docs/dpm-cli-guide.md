# Installed DPM replay, exploration and reduction

The `mirrors-dpm` tool runs application-owned C++/Node-worker/Rust-thread
runners. It admits the project's selected digest and artifact closure before
application acquisition. The [runner contract](dpm-runner-contract.md) defines
ownership, schema, oracle authority, process lifetime and exact acceptance scope.

## Build and runtime prerequisites

Build the Lean launcher with `lake build mirrors_dpm`. If changing packaged host
Python files, first run `python3 -I -S -B tools/deterministic-scheduling/refresh_host_identity.py`.
The launcher embeds their hashes and the selected Python interpreter hash;
`--check` detects stale identities. Changed host code cannot execute through an
old launcher. Python runtime pinning is specific to the built distribution. Refresh also pins
the installer and installed-gate helper source bytes. Run preparation, installer,
identity refresh and installed-gate scripts with `python3 -I -S -B`; their verified
helper loading does not search adjacent modules or bytecode. The OS standard
library, extension modules and loader remain trusted platform prerequisites;
the interpreter executable hash is not a hermetic Python installation.
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
