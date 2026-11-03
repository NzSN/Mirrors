# Q1, Q2, and negative-control recipes — MW-65 preparation

Status: preparation only. No scope was built, no verifier was run on a
campaign store, and no oracle was stopped. Execution waits until MW-61,
MW-62, MW-63, and MW-64 have qualified the same candidate. Owned-backend
stop authority is a prerequisite recorded here, not an action.

The selected profile is `m5-wsl-windows-remote`. Its class is
`local-candidate` and its catalog visibility is `private`. A scope whose
`qualificationClass` is `release-candidate` fails
`qualification scope class differs from the selected profile` when the
profile is `m5-wsl-windows-remote`.

## Paths the installer actually materializes

`tools/distribution/install.py` is the layout authority. For an admitted
runtime prefix `MIRRORS_INSTALLED_RUNTIME`:

| Role | Path |
| --- | --- |
| Q entry script | `$MIRRORS_INSTALLED_RUNTIME/verification/bundle/tools/evidence/qualification_scope.py` |
| Schemas | `$MIRRORS_INSTALLED_RUNTIME/verification/bundle/tools/evidence/schema/` |
| Installed registry and profiles | sibling `commands.json` and `qualification-profiles.json` under that `tools/evidence` directory |
| Wheels | `$MIRRORS_INSTALLED_RUNTIME/verification/wheels` |
| Catalog snapshot input | `$MIRRORS_INSTALLED_RUNTIME/inputs/framework-catalog.A.json` |
| Local binaries | `$MIRRORS_INSTALLED_RUNTIME/bin/ModelMirrors`, `model_interface_gen`, `framework_catalog` |

Gate runtime `MIRRORS_INSTALLED_GATE_RUNTIME` is the second D prefix. Its
supervisor cwd suffix is `gate/mirrorgate-supervisor`. These paths are
roles. The bytes are whatever MW-53 installed. Before Q, hash the installed
script, schemas, registry, profiles, and wheel files and compare them to the
D manifest artifacts `evidence-verifier` and `evidence-verifier-dependencies`.
A source-tree `tools/evidence/qualification_scope.py` is not the Q2
verifier, even though this preparation read that source to learn the CLI.

Direct pins in `tools/evidence/requirements.txt` are `attrs==23.2.0`,
`jsonschema==4.10.3`, and `pyrsistent==0.20.0`. The historical phrase
"six pinned wheels" is not the current requirements list. `WHEEL_COUNT` is
the file count of the admitted wheel archive and stays unresolved until
that archive is listed. Do not pad the count to six.

`qualification_scope.py --help` accepts only `--scope` and `--store`.
`verify.py --help` accepts `--offline`, `--expected-envelope-sha256`,
`--historical-index`, `--catalog`, `--profile`, `--profiles`, and an
optional bundle. Those help checks did not verify a bundle.

## DAG

Scope document schema is `mirrors.qualification-scope/v2` (`--scope` file).
Maximum 64 nodes and 256 edges. Fields are closed: `schemaVersion`,
`scopeId`, `qualificationClass` = `local-candidate`, `selectedCatalogRef`
kind `sha256` equal to `C0_SHA256`, `distributionBindingRunIds`, and
`nodes`. Each node has `phase`, `evidenceUse`, `privateRunRef`,
`publicRunRef`, `distributionRunId`, and `dependsOnRunIds`. Private and
public run IDs match. Private projection kind is `private`; public is
`public`.

Order, after each producer is independently finalized:

```text
C0 selection
  -> D local: framework.install-diagnostics
  -> D gate:  framework.install-diagnostics-gate
  -> source gates (no D edge)
  -> replay and lease origin on the local D
  -> recovery origin on the gate D, retained-attempt
  -> R1 reproduction on its origin or faulty replay
  -> R4/R5 reduction on exactly one R1
  -> mutation on the matching D
  -> recovery on the retained origin
  -> Q outside the scope
```

`distributionBindingRunIds` lists both D run IDs. Distribution nodes have
`phase` `distribution`, `evidenceUse` `qualification-credit`, null
`distributionRunId`, and empty `dependsOnRunIds`. Every credited installed
node depends directly on its own D run and its envelope components equal
that D's component refs. Source gates use a null `distributionRunId` and
the component set in `SOURCE_COMMAND_COMPONENTS`.

Credited nodes are the 17 required producers other than
`evidence.offline-verify`, plus `framework.install-diagnostics-gate`.
`framework.recovery-origin-installed` is in the graph as
`retained-attempt`. The three `mirrorgate.application-campaign.*` commands
and `framework.lease-origin` are not nodes. Reproduction nodes depend on
the credited faulty replay or lease origin whose private run ref is inside
the bundle. Each reduction node depends on exactly one reproduction node,
and its required reproduction-input SHA-256 and byte length equal that
R1's. Recovery depends on the retained origin, and the receipt's
`original.runRef` equals that origin's private run ref.

`evidence.offline-verify` is not a node. `catalog_links.py` rejects a Q
bundle that contains any other command, and it rejects a scope that
pre-credits `evidence.offline-verify`.

Node count for this graph is 19. Bundle count including the later Q run is
20. Those numbers are the size of this recipe, not existing evidence.

## Q1 — linked scope collection

Q1 is the registered command `evidence.offline-verify`, collected from the
installed runtime after the scope file and every input run exist. Argv
length is 6. Index 3 is the scope path and must sit in the attachment root
under the name `qualification-scope.json`. Capture mode is `existing-input`,
so the file exists before `collect.py` starts. The producer result is
`mirrors.qualification-scope/v2` from producer `mirrors.qualifier`.

The scope file's directory is `Q_ATTACH_ROOT`. The store is the same
`EVIDENCE_STORE` that holds `runs/`. Cwd is `MIRRORS_INSTALLED_RUNTIME`.
Set `PYTHONPATH` to `$MIRRORS_INSTALLED_RUNTIME/verification/wheels` and
`PYTHONNOUSERSITE=1`. `PYTHONPATH` is not a registered environment name for
this command, so the command context will not record it. The child still
inherits the collector environment. Do not put the source checkout on
`PYTHONPATH`. The registered executable is `/usr/bin/python3`; adding `-I`
would break the prefix.

```contract-argv
evidence.offline-verify
/usr/bin/python3
verification/bundle/tools/evidence/qualification_scope.py
--scope
Q_ATTACH_ROOT/qualification-scope.json
--store
EVIDENCE_STORE
```

Collect with `--command-id evidence.offline-verify`, the installed cwd, the
component set of the Q catalog combination, `--catalog-selection-kind
sha256`, and `--catalog-selection-value "$C0_SHA256"`. Then finalize that
staging directory and `verify.py --offline` the Q run. Expected child exit
0 and stdout JSON `status` `verified` with `verifiedRunCount` 19 and two
`bindings`. Singular `distributionBindingRunId` is present only for a
one-binding result; this recipe has two bindings, so that singular field
must be absent.

Q1 does not hide the source tree and does not stop the oracle. It is the
linked check. A second credited `evidence.offline-verify` is duplicate
credit and is refused.

## Q2 — installed offline re-execution

Q2 is not another credited collection. It re-executes the installed
verifier on the retained store after producer scratch is gone.

Isolation, using the admitted `bwrap` binary:

- `--unshare-net`
- `--ro-bind` the evidence store and the installed runtime
- `--tmpfs` over the Mirrors, MirrorECMA, and MirrorGate source roots and
  over the producer scratch directories named by MW-61
- no `/mnt` or `/tmp` path that still contains a checkout or a credential
- cwd inside the installed runtime
- `PYTHONPATH` only the installed wheels, `PYTHONNOUSERSITE=1`
- the scope file and store opened read-only

```sh
bwrap --die-with-parent --unshare-net \
  --ro-bind / / \
  --tmpfs "$MIRRORS_ROOT" \
  --tmpfs "$MIRRORECMA_ROOT" \
  --tmpfs "$MIRRORGATE_ROOT" \
  --ro-bind "$MIRRORS_INSTALLED_RUNTIME" "$MIRRORS_INSTALLED_RUNTIME" \
  --ro-bind "$EVIDENCE_STORE" "$EVIDENCE_STORE" \
  --ro-bind "$Q_SCOPE_FILE" "$Q_SCOPE_FILE" \
  --chdir "$MIRRORS_INSTALLED_RUNTIME" \
  --setenv PYTHONPATH "$MIRRORS_INSTALLED_RUNTIME/verification/wheels" \
  --setenv PYTHONNOUSERSITE 1 \
  --setenv LC_ALL C.UTF-8 \
  /usr/bin/python3 \
  "$MIRRORS_INSTALLED_RUNTIME/verification/bundle/tools/evidence/qualification_scope.py" \
  --scope "$Q_SCOPE_FILE" \
  --store "$EVIDENCE_STORE"
```

The `--ro-bind / /` plus later `--tmpfs` and `--ro-bind` overlays follow
bubblewrap's last-matching-option rule. Confirm the admitted `bwrap`
version against its own documentation before the run; if that version does
not overlay in this order, stop and record the blocker. Do not fall back to
an unshared network or a source-tree script.

Expected stdout is byte-identical to the Q1 verifier summary for
`schemaVersion`, `status`, `scopeId`, `qualificationClass`, `bindings`, and
`verifiedRunCount`. Save that stdout as the Q2 receipt. Hashes do not prove
who ran the producer; they prove the retained bytes still verify.

Also run, from the same isolated root, one offline bundle verification of
the Q run and of each scope run:

```sh
/usr/bin/python3 \
  "$MIRRORS_INSTALLED_RUNTIME/verification/bundle/tools/evidence/verify.py" \
  --offline \
  --expected-envelope-sha256 "$ENVELOPE_SHA256" \
  "$EVIDENCE_STORE/runs/$RUN_ID"
```

`--catalog` and `--profile` are the later C1 link, not Q2. They need catalog
B, whose `previousSelectionRef` equals the pre-run C0 selection and which
cites Q's public run ref. Catalog B is `blocking` and is not created here.
Profile `m5-wsl-windows-remote` requires a private catalog. A public catalog
fails the visibility check.

## Six negative controls

Each control uses a scratch copy of the scope and, when the mutation is
inside a bundle, a scratch copy of that one run. The retained
`EVIDENCE_STORE` is not modified. A control that exits 0 fails the
campaign. Expected rejection text is the current `ValueError` message.

1. Missing artifact. In the scratch scope, replace one node's `privateRunRef.runId`
   and matching public run ID with `run-missing-control`, and point no other
   node at it except through removal of edges that would dangle. Run the
   installed `qualification_scope.py`. Expect exit 1 and
   `qualification bundle is missing: run-missing-control`.

2. Changed byte. Copy one finalized run directory. Flip one byte of one
   payload file. Leave `bundle-index.json` unchanged. Point the scratch
   scope at that copy. Expect `bundle record identity mismatch:`.

3. Wrong D binding. In the scratch scope, set one local installed node's
   `distributionRunId` to the Gate D run ID and include that ID in
   `dependsOnRunIds`, without changing the run's envelope components.
   Expect `qualification components differ from bound distribution:`.

4. Wrong R0/R1 origin. Point `framework.reproduction`'s `dependsOnRunIds`
   at `framework.replay-correct` instead of `framework.replay-faulty`,
   leaving the captured bundle's `evidenceLinks.runRef` on the faulty run.
   Expect `reproduction input origin does not match a declared dependency`.

5. Wrong R1/R5 linkage. Point `framework.reduction`'s reproduction
   dependency at `framework.reproduction` (the reference-project R1) instead
   of `framework.reproduction-lease`, or the reverse for prefix reduction.
   The two bundles differ, so the reduction input hash check fails. Expect
   `reduction input differs from its reproduction dependency`.

6. Incomplete profile. This rejection is not implemented by
   `qualification_scope.py`; a smaller acyclic graph verifies. It is
   implemented by `catalog_links.evaluate_catalog_link` when the Q bundle's
   credited scope is missing a `requiredCommandIds` entry. After a scratch
   scope that drops `mirrors.local-no-model` is otherwise well formed, run
   the installed verifier:

```sh
/usr/bin/python3 \
  "$MIRRORS_INSTALLED_RUNTIME/verification/bundle/tools/evidence/verify.py" \
  --offline \
  --catalog "$CATALOG_B" \
  --profile m5-wsl-windows-remote \
  --profiles "$MIRRORS_INSTALLED_RUNTIME/verification/bundle/tools/evidence/qualification-profiles.json" \
  "$SCRATCH_Q_BUNDLE"
```

Expect `required command is absent: mirrors.local-no-model`. `CATALOG_B`
and a scratch Q bundle whose scope artifact is the reduced scope are
`blocking`. Do not mark control 6 passed because the graph verifier
accepted the reduced scope alone.

Retain each control's stdout, stderr, and exit code. Do not finalize a
negative control as qualification credit.

## Owned-backend stop prerequisite

Not executed. Q's offline repeat after the oracle stops is a separate step
inside MW-66, and only after the authority below exists.

`blocking` before any stop:

- `ORACLE_OWNER`: the operator who owns the process observed in the
  same-time `mirrors.windows-deployment-observation/v1` used by MW-54 and
  MW-62. A PID from October is not authority.
- `ORACLE_ENDPOINT`: host and port equal to `MIRRORS_REMOTE_HOST` and
  `MIRRORS_REMOTE_PORT` of those runs.
- `ORACLE_BINARY_SHA256` and `ORACLE_SOURCE_REF`: equal to that observation.
- A written stop scope that names only that owned process and its owned
  child jobs. Production listeners, unrelated users, and any process whose
  binary hash differs are outside the scope.
- A restart plan owned by the same operator if the oracle is still required
  for a later admitted use. This campaign's post-stop Q2 repeat must not
  need it.

The repeat itself is the Q2 `bwrap` command again, against the retained
store, with the endpoint unreachable from that namespace. Expected stdout
remains byte-identical to the pre-stop Q2 summary. If the isolated verifier
tries to open the endpoint, the repeat fails. No stop command is listed
because no current repository script is authorized to kill that process,
and this preparation must not contact it.

## Exit gate

MW-66 can be written only when Q1 is a finalized `evidence.offline-verify`
run, Q2's isolated stdout matches that summary, all six controls were
rejected with the messages above, both D bindings are in the scope, and the
post-stop repeat is either done under the authority above or still
explicitly unexecuted. This file does not satisfy that gate.
