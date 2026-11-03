# Codex corrections to Grok's command drafts

Status: reviewed preparation. These corrections take precedence over the
corresponding examples in `../handoff/tasks.md` and `../handoff/verification.md`.
Original Grok artifacts and inventories remain unchanged. None of the following
commands was executed against an installed candidate or campaign in this batch.

## Collector arguments and retained failures

The shared collector example omits `--attachment-plan` and expands a scalar
`$ARGV`. Use Bash arrays to preserve argument boundaries. Define `ARGV` as the
exact registered child vector plus admitted suffix, and `COMPONENT_ARGS` as the
exact component-set argument vector for that phase/D binding, before this step:

```bash
ATTACHMENT_ARGS=()
if [[ "$ATTACHMENTS_REQUIRED" == 1 ]]; then
  : "${ATTACHMENT_PLAN:?resolve the validated attachment plan first}"
  ATTACHMENT_ARGS=(--attachment-plan "$ATTACHMENT_PLAN")
fi
if python3 tools/evidence/collect.py \
  --store "$EVIDENCE_STORE" \
  --registry tools/evidence/commands.json \
  --command-id "$COMMAND_ID" \
  --cwd "$CWD" \
  --catalog-selection-kind sha256 \
  --catalog-selection-value "$C0_SHA256" \
  "${COMPONENT_ARGS[@]}" \
  "${ATTACHMENT_ARGS[@]}" \
  -- "${ARGV[@]}" >"$COLLECT_STDOUT" 2>"$COLLECT_STDERR"; then
  COLLECT_EXIT=0
else
  COLLECT_EXIT=$?
fi
```

`ATTACHMENTS_REQUIRED` comes from the selected contract. Log paths are fresh
files in an owner-only root. Retain nonzero `COLLECT_EXIT`; finalization cannot
turn a failed producer into a pass. Obtain `STAGING_ROOT` from the collector's
actual `evidence staging:` stderr receipt, verify it is inside this store's
`staging/`, then finalize that exact directory:

```bash
python3 tools/evidence/finalize.py "$STAGING_ROOT" --store "$EVIDENCE_STORE"
```

Obtain run ID, bundle path and envelope hash from the finalizer's JSON output.
Do not guess a run ID or reuse staging. If collection did not persist staging,
retain the failure and stop that task. Verify the actual finalized bundle,
keeping producer outcome and integrity result distinct.

## Local-tag and release-admission order

Local tag selection/creation precedes MW-31/MW-32 packaging. MW-71 later admits
the completed package/qualification set for publication. The draft statement
that the proposal stays unaccepted until MW-71 applies to release admission;
it cannot postpone the local packaging tag until after packaging. MW-30
proposes the unused tag/version edit; MW-12 integrates the selected source edit
before freeze. Existing rc.5 refs and artifacts remain unchanged.

## Independent Q2 isolation

The draft command hides only three source roots, omits producer scratch mounts
required by its prose, and inherits ambient Python/site settings. Resolve a
complete `HIDDEN_ROOTS` array: all source checkouts, producer scratch/tool-source
fallbacks, credential roots and relevant source-bearing `/mnt` paths. Reject an
empty/incomplete list and overlaps with installed runtime/store/scope paths.
Use verified read-only copies outside hidden roots when necessary; retain their
manifests/hashes. Private credentials are never offline-verifier inputs.

The admitted `verification/wheels` tree must be importable dependencies, not
unresolved wheel archives. Verify it against the installed D artifact and prove
dependency imports resolve there. Q2 may use `-S` to disable site packages;
these independent flags do not change registered Q1 argv. Template only:

```bash
HIDE_ARGS=()
for ROOT_TO_HIDE in "${HIDDEN_ROOTS[@]}"; do
  HIDE_ARGS+=(--tmpfs "$ROOT_TO_HIDE")
done
env -i PATH=/usr/bin:/bin /usr/bin/bwrap \
  --die-with-parent --unshare-net \
  --ro-bind / / \
  "${HIDE_ARGS[@]}" \
  --ro-bind "$MIRRORS_INSTALLED_RUNTIME" "$MIRRORS_INSTALLED_RUNTIME" \
  --ro-bind "$EVIDENCE_STORE" "$EVIDENCE_STORE" \
  --ro-bind "$Q_SCOPE_FILE" "$Q_SCOPE_FILE" \
  --chdir "$MIRRORS_INSTALLED_RUNTIME" \
  --clearenv \
  --setenv PATH /usr/bin:/bin \
  --setenv HOME /nonexistent \
  --setenv PYTHONPATH "$MIRRORS_INSTALLED_RUNTIME/verification/wheels" \
  --setenv PYTHONNOUSERSITE 1 \
  --setenv LC_ALL C.UTF-8 \
  /usr/bin/python3 -S -B \
  "$MIRRORS_INSTALLED_RUNTIME/verification/bundle/tools/evidence/qualification_scope.py" \
  --scope "$Q_SCOPE_FILE" --store "$EVIDENCE_STORE"
```

Retain resolved mount argv, installed input hashes, hidden-root probes, network
namespace proof, and verifier stdout/exit. Verify every scope bundle and Q under
the same isolation. Namespace denial is unavailable admission; no weaker
fallback receives Q2 credit. Backend stop/repeat stays dependency-gated.

## Missing-artifact and incomplete-profile controls

Draft control 1 removes a bundle from the graph. That exercises missing-run
handling, not the required missing-artifact check. Keep it as an additional
control. For the required control, make an owner-only scratch copy of the store
with identical run IDs, copy a finalized bundle and delete one inventoried
required payload. Preserve its index/envelope and all scope references. Run
the installed bundle verifier and scope verifier over the scratch store. Both
must reject it; retain actual diagnostics. Never mutate the canonical store.

For changed-byte control 2, use the same coherent scratch-store arrangement
and original run IDs; flip a payload byte while preserving integrity records.
Changing a run ID to a nonexistent path only tests missing-run handling.

For control 6, the graph verifier may accept a well-formed subset. Actually run
it on a scope omitting `mirrors.local-no-model`, collect/finalize that diagnostic
Q attempt, and construct a separately hashed scratch catalog B with the normal
lineage/public-run link to that Q result. Invoke installed
`verify.py --offline --catalog SCRATCH_CATALOG_B --profile
m5-wsl-windows-remote --profiles INSTALLED_PROFILES SCRATCH_Q_BUNDLE`.
Require the semantic missing-command rejection after integrity/linkage checks
pass. Editing a finalized Q artifact without genuine collection/finalization
only tests byte integrity. Retain graph acceptance and profile rejection;
neither receives full qualification credit.

Final MW-66 also invokes profile-link verification on the **complete** Q bundle
and actual later catalog B. Graph verification alone does not enforce the
selected required command/tier denominator.

## Historical status and environment scope

Dated CHECKPOINTS.md entries remain observations of their execution. Their
no-commit-at-execution wording is not a defect to rewrite when a later commit
contains that entry. Record current continuation through new entries; update
maintained status/decisions during the later source assignment. Preserve every
historical receipt and checkpoint.

The failed tmpfs run remains retained. Codex's complete 61-test ext-family
distribution rerun passed; Grok's 14-test install-module rerun also passed. Use
a task-owned ext-family TMPDIR for final focused/local gates. Do not weaken
installation admission or turn required tests into skips.

## Operation-card completion and immutable manifests

The operation draft's client prose omits the CLI subcommand and endpoint.
Resolve a `CONTROL_HOST` and `CONTROL_PORT` for each candidate/production run;
they must match that run's same-time owned listener observation. A complete
argument pattern is:

```bash
CLIENT_ARGS=(validate --host "$CONTROL_HOST" --port "$CONTROL_PORT"
  --tls --cert "$CLIENT_CERT" --key "$CLIENT_KEY" --ca "$CLIENT_CA"
  --spec "$VALID_SPEC" --init Init --next Next)
"$CLIENT_BINARY" "${CLIENT_ARGS[@]}" --pin "$SERVER_PIN" --inv Inv --bound 3
"$CLIENT_BINARY" "${CLIENT_ARGS[@]}" --pin "$SERVER_PIN" \
  --inv "$INVALID_INVARIANT" --bound "$INVALID_BOUND"
"$CLIENT_BINARY" "${CLIENT_ARGS[@]}" --pin "$SERVER_PIN" --inv Inv --bound 3 --async
"$CLIENT_BINARY" "${CLIENT_ARGS[@]}" --pin "$SERVER_PIN" \
  --inv "$INVALID_INVARIANT" --bound "$INVALID_BOUND" --async
"$CLIENT_BINARY" "${CLIENT_ARGS[@]}" \
  --pin 0000000000000000000000000000000000000000000000000000000000000000 \
  --inv Inv --bound 3
```

Capture each command/exit/output independently. Expected Lean CLI results are
0/`VALID`, 1/`INVALID` for the two async/sync pairs, and 2 plus fingerprint
mismatch for wrong pin. Hash and admit the chosen spec and invalid predicate;
do not run these examples against an unresolved endpoint.

The deployment draft moves from staging/stop to start without an explicit
replacement operation. MW-71 must supply a reviewed transactional script that:
backs up and hashes the complete old binary/DLL/configuration set; verifies
staged new bytes; guards the actual current service/hash; stops only that
owned service; rechecks old hashes; replaces the admitted binary and changed
runtime dependencies; verifies all new hashes; starts and runs the same
controls; restores the old set and controls on any failure. Include failures
between replacement and start. Until paths, hashes, replacement and rollback
commands exist in that concrete script, production replacement is not ready.
This planning batch neither implements nor executes a host-specific script.

Embedded/external `BUILD.json`, archives, checksums and original notes remain
immutable after construction. Never edit a manifest's `published`/`deployed`
flags after release/deployment or add invented Linux metadata fields. The Linux
builder has its own schema; the historical Windows packager alone records
those two false flags. Later publication/deployment state belongs in new linked
operation receipts, without changing any admitted artifact hash.

## Admission recipes: selected scope, paths and execution context

This section also overrides `../admission/commands.md`, `report.md` and
`result.json` where they propose scope or execution paths.

The active campaign selects the observed Ubuntu 26.04 WSL2 profile only.
MW-50 validates the base lock as a structural regression control. No new
Ubuntu 24.04 host, base-profile installation or base D pair is required.
Build/install/audit **two** selected checked profiles: `checked-replay-local`
and `checked-replay-gate`. Do not expand this to four builds/D audits.

Reject the proposed `/var/tmp` candidate path for this session: writable roots
are the repository and `/tmp`. Also reject the draft `$CANDIDATE/$FAMILY/locks`
layout. Bootstrap validation requires `distribution/<root>/<lock-file>` paths;
the draft would bind `base/locks/...` or `wsl2/locks/...`, which is invalid.
The corrected selected-candidate layout is:

```bash
CANDIDATE="$MIRRORS/.golden-build/mainwork-20261103-admission"
SELECTED_CATALOG="$CANDIDATE/catalog/framework-catalog-wsl2-26.04.json"
SELECTED_LOCKS="$CANDIDATE/distribution/reference-node-wsl2-26.04"
```

This is an uncreated proposal. Require an empty owned root and copy the selected
catalog and entire selected lock directory into that layout. Use these paths
for refresh/snapshot/build instead of the draft's per-family paths. Keep
`--skip-component-records --skip-render`, explicit catalog/C3 identity, admitted
source refs and all locked dependency inputs. Before final builds, assert every
generated `buildInputs.path` is exactly
`distribution/reference-node-wsl2-26.04/{profiles,component-lock,dependency-lock}.json`
for the corresponding input ID and that bootstrap root derivation accepts it.
Use fresh `$CANDIDATE/cache/$PROFILE`, `install/$PROFILE`, `audit/$PROFILE`
outputs for the two selected profiles only. Q2 must later use verified copies
outside hidden source roots; a candidate inside `.golden-build` cannot be
exposed by leaving its enclosing source checkout visible.

The admission report's socket success belongs to the **Grok subprocess
execution context**. Codex's independent AF_INET and AF_UNIX bind/listen probes
both returned EPERM, recorded in `admission-check.json`. These are different
execution-context observations. Do not infer host-wide socket permission or
transfer one context's permissions to a later producer. Reobserve every needed
capability in the actual selected execution context. The existing namespace
denial and missing strace remain unresolved; PTRACE_TRACEME is not a strace audit.

Log 090's header timestamp was manually supplied rather than observed. It
receives no freshness/chronology credit. Its content hashes are advisory until
reobserved for the final candidate. The retained original probe-summary covers
only 001–083; consult the later inventoried logs separately. The review's
retained `admission-check.py` supplies reproducible current structural checks.

Finally, the admission draft's unconditional "Do not launch it from this
coordinator" for the **remote client** is incorrect. After endpoint/TLS/runtime
admission, run the registered remote producer through the Mirrors CLI from the
coordinator, as the repository contract requires. The prohibition is on local
Apalache/TLC execution and on contacting an unadmitted remote. Host-specific
paths, refs, tool hashes and installed argv prefixes must be reconciled in the
registry before final source freeze, not patched after qualification starts.
