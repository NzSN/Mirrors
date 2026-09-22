# Durable evidence tools

These tools implement the accepted local E1 contract in
[the durable-evidence design](../../Docs/durable-evidence-design.md). They wrap
existing commands; they do not replace producer result semantics.

Install the pinned Python 3.12 validation dependencies into an isolated runtime:

```bash
python3 -m pip install -r tools/evidence/requirements.txt
```

## Collect, finalize, and verify

Collection uses a stable command ID from `commands.json`, streams child output
to its original stdout/stderr, and records bounded copies plus exact child exit
or signal. The store should be outside the checkout and `/tmp`:

```bash
export MIRRORS_EVIDENCE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/mirrors/evidence/v1"
python3 tools/evidence/collect.py \
  --command-id mirrors.local-no-model \
  --component mirrors=. \
  -- bash tools/run-local-no-model-check.sh
```

This local aggregate is intentionally non-model-checking. Do not replace it with
`lake test`: that test driver runs the TLC async-protocol check and can discover a
developer-local Apalache even when `APALACHE_MC` is unset. The repository-owned
runner enumerates the build/unit/codec/evidence gates and prints its excluded
model-check obligations. Do not run a local Apalache/TLC process as a substitute
for the remote qualification tier.

The private remote tier uses the deployed TLS 1.3 mTLS service at
`192.168.150.219:8999`. Supply credential *paths*, the pinned server leaf, and
the identity from the retained same-time service observation; no credential
bytes belong in the registry, command line, or public evidence:

```bash
export MIRRORS_REMOTE_CLIENT_CERT=/private/client.crt
export MIRRORS_REMOTE_CLIENT_KEY=/private/client.key
export MIRRORS_REMOTE_CA=/private/ca.crt
export MIRRORS_REMOTE_SERVER_PIN=<64-lowercase-hex-server-leaf-fingerprint>
export MIRRORS_REMOTE_SERVICE_BINARY_SHA256=<64-lowercase-hex-installed-binary>
export MIRRORS_REMOTE_SERVICE_SOURCE_REF=<full-deployed-source-revision>
export MIRRORS_REMOTE_APALACHE_VERSION=0.61.0
export MIRRORS_REMOTE_APALACHE_ARCHIVE_SHA256=68fb56dd9d053cf21d692fd7ec3fbaaeba1395661ec7434fa2b4c47e6fc432b8
export MIRRORS_REMOTE_APALACHE_JAR_SHA256=33611081942d392646af60993c599907f1f41752fce4a62304dbf9e2cdad4346
export MIRRORS_REMOTE_JAVA_SELECTED_VERSION=25.0.4+7
export MIRRORS_REMOTE_JAVA_OBSERVED_VERSION=25.0.4+7-LTS
export MIRRORS_REMOTE_JAVA_ARCHIVE_SHA256=54ba13f3ef80887fa74708b2a32daaae6262517ba68433d850bb4b426343172b
export MIRRORS_REMOTE_JAVA_EXECUTABLE_SHA256=58df5c13e5d6e68f242ad9b724479122828523008ef0907d3f2a02f54afaff23
python3 tools/evidence/collect.py \
  --command-id mirrors.remote-model-check \
  --component mirrors=. \
  -- python3 tools/evidence/run_remote_model_check.py
```

The private command context retains the credential paths and declared service
identity, while the command log retains the endpoint, TLS mode, server pin,
remote binary/source declarations, local client binary hash, exact HourClock
source hash, and terminal verdict. Pair it with the private remote administrative observation specified in
the qualification harness design; a service status check or `VALID` line alone
does not bind the deployed executable and backend identity.

The 2026-09-22 live `VALID` probe used the still-running Apalache 0.58.2 / Java
21.0.11 service. It confirms reachability and function, but it is not a qualifying
run for the pinned 0.61.0 / 25.0.4+7 tier. Rerun collection only after the staged
tools are activated and independently re-observed.

The selected catalog file must exist at the clean registered revision, or the
caller must provide an already computed C2 `--catalog-selection-kind sha256`
and `--catalog-selection-value`. A dirty catalog checkout never silently uses
HEAD. Collection returns the child's exit status. Storage failure is reported
separately and does not replace that status.

Collection creates `staging/<runId>/envelope.staging.json`. It is deliberately
incomplete until finalization. Finalize and verify it as follows:

```bash
python3 tools/evidence/finalize.py \
  "$MIRRORS_EVIDENCE_ROOT/staging/<runId>" \
  --store "$MIRRORS_EVIDENCE_ROOT"
python3 tools/evidence/verify.py --offline \
  "$MIRRORS_EVIDENCE_ROOT/runs/<runId>"
```

The finalizer independently copies payload bytes, writes the private envelope
and allowlisted public summary, synchronizes every payload directory, and
publishes `bundle-index.json` last through an exclusive hard link. A directory
without that index is incomplete. The verifier needs no producer checkout,
scratch directory, or network. Pass a catalog's run digest with
`--expected-envelope-sha256` to detect a consistently rewritten local bundle.
Hashes establish retained-byte integrity, not truthful execution or signer
authority.

Every new collection also retains a required private
`mirrors.evidence-command-context/v1` diagnostic. It records the exact bounded
raw registry bytes, their SHA-256, and the selected closed entry, exact argv/cwd,
only the effective environment
names or fixed values allowlisted by that entry, the registry-owner component
identity, the resolved executable bytes/hash, and hashes for explicitly pinned
file-valued environment inputs such as the interop Haskell binary. The registry is reread after
the child exits; a change blocks persistence without replacing the child result.
No ambient environment or credential is captured. Public summaries omit the
entire command context.

Commands that produce native private receipts or reproduction inputs use a
predeclared `mirrors.evidence-attachment-plan/v1` passed with
`--attachment-plan`. The plan is loaded before execution, pins an existing
owner-only output root, and names every one-component output path, artifact ID,
role, media type, requirement, and byte bound. New outputs must be absent before
the child starts; existing inputs require a pre-run SHA-256. Capture opens every
file relative to the pinned root without following links, requires mode `0600`,
detects replacement/change, and copies bounded bytes into staging. The child
cannot choose an attachment path.

Installed local mutation and LeaseService reduction adapters validate producer
schemas rather than inferring success from exit zero. Local mutation requires the
ordered 9/4/4 mutant denominators, all 29 baseline/mutant/control executions,
exact mismatch coordinates, independent probe facts, catalog/component binding,
and confirmed cleanup. Reduction requires the exact Client `2` to `1` edit,
model-valid oracle, pinned validator/Apalache/Java identities, original bundle and
materialized input hashes, and `explore_done` cleanup. The linked Q verifier also
requires the reduction input bytes to equal its reproduction dependency.

The Gate application adapter derives behavioral and physical-cleanup axes from
the native `mirrorgate.application-validation/v2` receipt, independently of the
child exit. Missing, malformed, failed, or unconfirmed native cleanup never
becomes confirmed. Reproduction inputs must cite an earlier run ID. A bundle
whose origin run equals its enclosing collection run is refused: finalize R0
first, construct the bundle against finalized R0, then capture/replay it in R1.
The recovery adapter separately validates the complete native
`mirrorgate.recovery-receipt/v1` digest, original private run reference,
resource results, remaining resources, and derived cleanup status. Only a
nonempty all-reclaimed receipt establishes `gate-recovery` cleanup; command exit
alone never does.

Catalog qualification additionally requires the C3 `framework_catalog` binary.
I2 must package that exact validator and set
`MIRRORS_FRAMEWORK_CATALOG_VALIDATOR`, because a source checkout's
`.lake/build/bin` path is not an installed dependency. E4 validates an owner-only
snapshot of the catalog through that binary and uses its
`mirrors-framework-canonical-json/v1` digest; it never substitutes Python/JCS
serialization for the catalog identity.

Use a reviewed later catalog B to link a run that selected catalog A:

```bash
python3 tools/evidence/verify.py --offline \
  --catalog catalog/framework-catalog.json \
  --profile release-candidate \
  "$MIRRORS_EVIDENCE_ROOT/runs/<runId>"
```

B's `org.nzsn.catalog-lineage.previousSelectionRef` must equal the bundle's
pre-run A selection. The Q bundle's full component and dirty identities must
equal the one cited B combination, and B must contain the exact finalized public
`runRef` for Q. Q runs only the registered offline scope verifier and retains a
private `mirrors.qualification-scope/v1` producer result. That bounded DAG names
already-finalized D, source, origin, replay, reproduction, reduction, mutation,
and recovery run references. Verification rechecks every bundle and public
projection, refuses cycles, self-inclusion, missing/tampered inputs, duplicate
command credit, mixed catalog identities, and installed runs not bound to the
selected exact D. Reproduction inputs and recovery receipts must name the exact
origin run declared by their dependency edge. Failed retries and diagnostics may be retained, but receive no
qualification credit. Source-gate component subsets are fixed by command owner;
an arbitrary subset cannot stand in for the declared component.

Local/release approvals bind the canonical digest of the selected D run's
required typed `distribution-manifest` artifact and the exact raw SHA-256 of its
paired typed cache index, so B cannot approve different executable/cache bytes
than the installed qualification runs. The private graph and its run IDs are not
copied into Q's allowlisted public summary. C1 cites Q's public run reference.
Catalog A remains the distribution input; approval B is a separate E4 decision
and never causes an A/B digest cycle or retroactive manifest rewrite.
`source-validation` cannot promote installed, recovery, or release
claims. The local/release profiles require the complete M5 command, tier,
artifact, cleanup, and source/local/installed observation set.

All selected-store directories must be owned by the current user and mode
`0700`; files are mode `0600`. Paths are opened component by component without
following symlinks. Finalization never overwrites a run ID.

## Historical source packages

When old producer logs predate a selected catalog or lack a preserved pre-run
component observation, retain them without manufacturing an E1 run:

```bash
python3 tools/evidence/retain_source_package.py \
  --package /path/to/log-package \
  --manifest /path/to/log-package/sha256sums.txt \
  --reference-root /path/to/referenced/source-root \
  --label descriptive-historical-label
```

This writes a `pending/` package with copied bytes, an index published last, and
the fixed status `historical-unqualified`. It is not eligible for `runRef`,
catalog evidence, or qualification. Run a new producer command against an exact
selected catalog and immutable source snapshot to create new E1 evidence.

The older documentation sidecar is checked independently and is always
non-qualifying:

```bash
python3 tools/evidence/verify.py \
  --historical-index Docs/evidence/historical-artifact-availability.json
```

## Tests

```bash
python3 -m unittest discover -s tools/evidence/tests -p 'test_*.py'
```

The suites cover contract fixtures, child exit/signal preservation, timeouts,
retained descendants, source drift, output limits, write failure, index-last
ordering, scratch removal, tampering, symlinks, traversal, destination collision,
permissions, public canaries, and historical-package boundaries.
Qualification coverage additionally includes bounded linked scopes, graph
cycles, duplicate credit, exact distribution binding, reproduction-origin
linkage, and removal or tampering of any finalized input bundle.
