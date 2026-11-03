# Operation cards — MW-72 preparation

Status: preparation only. No remote contact, tag push, release edit,
service change, or reboot was performed. Unknown current values stay
named. Dated host `windows-dev`, port `8999`, and the 2026-09-18 binary
are not current health. `verify-remote` is the post-push check: it
requires the remote tag to already peel to `S2_COMMIT`. It is the wrong
tool for proving absence.

## Named inputs

Blocking until MW-54 or MW-71 fills them: `GH_REPO`, `S2_COMMIT`,
`PROPOSED_TAG`, `LINUX_ARCHIVE_SHA256`, `WINDOWS_ZIP_SHA256`,
`DEPLOYMENT_BINARY_SHA256`, `PRODUCTION_HOST`, `PRODUCTION_SERVICE_NAME`,
`PRODUCTION_BINARY_PATH`, `PRODUCTION_CONFIG_PATH`,
`PRODUCTION_BINARY_SHA256`, `ROLLBACK_DIR`, `CANDIDATE_PORT`,
`CANDIDATE_BIND`, `CANDIDATE_BINARY`, `CLIENT_BINARY`, `SERVER_PIN`,
`VALID_SPEC` and `VALID_SPEC_SHA256`, `INVALID_INVARIANT`,
`INVALID_BOUND`, `SERVICE_STOP_COMMAND`, `SERVICE_START_COMMAND`,
`ADMITTED_APALACHE`. Credential paths are names only. Their bytes are
absent from this file. `SERVICE_*` is the admitted wrapper. Mirrors does
not implement the Windows service manager. Default `--jobs` is 4 only when
the flag is omitted; record the observed value.

The interop driver pairs HourClock with `TraceComplete` and bound `13`
for its invalid row. Use that pair unless MW-71 sets
`INVALID_INVARIANT` / `INVALID_BOUND` to another admitted pair.
`VALID` / `INVALID` lines come from `reportValidate`: valid is one
`VALID` line and exit 0; invalid is `INVALID`, then the violation line,
and exit 1. A `register_error` reply fails these four controls.

## Publication

Pre-push, MW-72 only: `git ls-remote https://github.com/$GH_REPO.git
refs/tags/$PROPOSED_TAG refs/tags/$PROPOSED_TAG^{}` is empty, and
`gh release view "$PROPOSED_TAG" --repo "$GH_REPO"` fails. Any peeled
SHA, release, or draft aborts. Do not retag rc.5.

Tag push, only with approval that includes the workflow publish job:

```sh
git push origin "refs/tags/$PROPOSED_TAG"
```

Watch tooling, build, Ubuntu 24.04 isolated `check-archive`, draft
create, second `verify-remote`, then `gh release edit --draft=false`.
Prerelease uses `--prerelease --latest=false`. If a draft remains, stop.
Do not rerun onto that draft and do not delete it here.

After publication: `release.py verify-remote --repository "$GH_REPO"
--tag "$PROPOSED_TAG" --commit "$S2_COMMIT"`; download into an empty
directory; `sha256sum --check SHA256SUMS`; asset hashes equal the S6
bindings; prerelease is not Latest.

Windows zip is a separate approval. Upload only when the file hash
equals `WINDOWS_ZIP_SHA256` and the asset name is absent. Do not pass
`--clobber`.

```sh
gh release upload "$PROPOSED_TAG" "$WINDOWS_ZIP" --repo "$GH_REPO"
```

## Candidate port

Start the admitted binary on `CANDIDATE_PORT`, which must differ from
the observed production listener. Bind is `CANDIDATE_BIND`. Stop only
this process and its child jobs afterward.

```sh
APALACHE_MC="$ADMITTED_APALACHE" \
  "$CANDIDATE_BINARY" --server "$CANDIDATE_PORT" --tls \
  --cert "$SERVER_CERT" --key "$SERVER_KEY" --ca "$SERVER_CA" \
  --bind "$CANDIDATE_BIND" --jobs "$CANDIDATE_JOBS"
```

Client checks use the packaged `CLIENT_BINARY` whose hash is the S6
binding. Same TLS flags, `--pin "$SERVER_PIN"`, `--spec "$VALID_SPEC"`,
`--init Init`, `--next Next`.

| Control | Extra arguments | Expect |
| --- | --- | --- |
| Sync valid | `--inv Inv --bound 3` | stdout `VALID`, exit 0 |
| Sync invalid | `--inv $INVALID_INVARIANT --bound $INVALID_BOUND` | first line `INVALID`, exit 1 |
| Async valid | valid arguments plus `--async` | stdout `VALID`, exit 0 |
| Async invalid | invalid arguments plus `--async` | first line `INVALID`, exit 1 |
| Wrong pin | valid arguments, `--pin` 64 zeros | exit 2, stderr contains `certificate fingerprint mismatch`, no `VALID` |

Spec bytes must match `VALID_SPEC_SHA256`. Owned candidate processes
must exit. Production is not stopped in this step.

## Replace, roll back, reboot

Reobserve the live binary, dependencies, listener, config, and
credential metadata. Copy those bytes into `ROLLBACK_DIR` and rehash.
Abort if the live hash is not `PRODUCTION_BINARY_SHA256`. Stage the new
binary beside the active path. Its hash must equal
`DEPLOYMENT_BINARY_SHA256` before `SERVICE_STOP_COMMAND`. If the live
file changes after that observation, abort with no copy. Then
`SERVICE_START_COMMAND`. Preserve configuration.

Roll back on hash mismatch, service failure, a failed positive control,
acceptance of the wrong-pin or invalid control, backend or config
drift, or incomplete cleanup. Restore rollback bytes, start, and rerun
the four controls. A restored service does not pass the deployment.

Reboot needs a separate approval. Afterward, record automatic start,
hashes, listener, backend, TLS pin, and the same four controls.
Stop/start without reboot leaves reboot `not-claimed`.

Receipts: `publication.json`, `candidate-port.json`,
`deployment.json`. Each names the operation, inputs, exits, and
hashes. Unrun cards stay `not-started`.
