# Release handoff template — MW-70 preparation

Status: preparation only. Every claim row is `UNACCEPTED`. A filled cell is
not admission. No tag was created, moved, or pushed. `v0.2.0-rc.5` stays on
`3ee3d9226f6258583fe7266c1737acff5abd1edf`. Final bytes wait for MW-66.
Codex `review/corrected-commands.md` overrides draft tag timing in
`tasks.md`: the local packaging tag precedes MW-31/MW-32; MW-71 admits the
finished set for publication.

Observed here without a fetch: `HEAD`
`75fbf962020cea8a13e009ecfdb3e912e7ce212f`, tree
`484e8f2991d1e2c56c8d47af668888e1cb48904f`, `Shell/Version.lean`
`0.2.0-rc.5`. `Docs/versioning.md` still says product `v0.1.1`. `release.py`
trusts `Version.lean` plus the tag object.

## Tag and version proposal

MW-30 names `PROPOSED_TAG` and the embedded-version edit. MW-12 lands that
edit before freeze. Create the local annotated tag, then package. MW-71
does not postpone that local tag. "Unaccepted until MW-71" means release
admission only. Existing rc.5 refs and artifacts stay unchanged.

`PROPOSED_TAG` must pass `validate_tag`, have no leading-zero numeric
prerelease identifier, and not be `v0.2.0-rc.5` or a historical key
(`v0.0.1` through `v0.0.3.3`). Before creation, `git rev-parse --verify
--end-of-options refs/tags/$PROPOSED_TAG` fails locally. Remote absence is
MW-72 and was not run. At `S2_COMMIT`, `Version.lean` embeds the tag
without the leading `v`. The packaging clone is clean and the tag peels to
that commit. Do not push while packaging: a `v*` push starts
`.github/workflows/release.yml`. `select` prints `tag=` only. On current
text, `identity()` accepts only `v0.2.0-rc.5`, which peels elsewhere.

Blocking: `S2_COMMIT`, `PROPOSED_TAG`, embedded-version authorization,
local-tag authorization.

## Package bindings

Nothing was built. Hashes stay unresolved.

| Artifact | Name rule | SHA-256 |
| --- | --- | --- |
| Linux archive | `mirrors-$PROPOSED_TAG-linux-x86_64.tar.gz` | unresolved |
| External manifest | `mirrors-$PROPOSED_TAG-linux-x86_64.build.json` | unresolved |
| Linux checksums | `SHA256SUMS` beside that archive | unresolved |
| `bin/mirror`, `bin/model_interface_gen` | archive members | unresolved |
| Windows zip | `mirrors-$PROPOSED_TAG-windows-x86_64.zip` | unresolved |

Linux `build` is Linux x86-64 only and records focused non-model gates, not
M5. Windows has no `release.py` subcommand. Do not rerun the rc.5 packager.
`BUILD.json` stays `published: false` and `deployed: false` until an MW-72
receipt says otherwise. The workflow does not upload the Windows zip.

## Claim matrix

Paths and hashes stay empty. Every status is `UNACCEPTED`.

| Claim | Needs | Status |
| --- | --- | --- |
| S2 commit, embedded version, local tag peel | MW-12, MW-30 | UNACCEPTED |
| Linux members, `ldd`, focused gates | MW-31 | UNACCEPTED |
| Windows zip, PE closure, eight-suite smoke only | MW-32 | UNACCEPTED |
| M5 producers and both D bindings | MW-53, MW-61 | UNACCEPTED |
| 22-row remote clients | MW-62 | UNACCEPTED |
| Three DPM profiles, `freshModelCheck: false` | MW-63 | UNACCEPTED |
| Full Windows `lake test`, no integer-map skip | MW-64 | UNACCEPTED |
| Q1, isolated Q2, six negative controls | MW-66 | UNACCEPTED |
| Publication, deployment, reboot | MW-72 | UNACCEPTED |
| Two shipped cycles, soak, retirement | MW-81 | UNACCEPTED |

Omitting `framework.install-diagnostics-gate` can match the 18-command
profile and still fail the two-binding gate. A scoped prerelease must not
claim an unexecuted row. Exclusions stay on the row.

## Review checklist

MW-71 checks operation boundaries, companion commits, every archive and
checksum, this matrix, Q1/Q2 and negative-control refs, the WSL2 host
actually observed, runtime prerequisites, production inventory, rollback,
and reboot. One approval does not cover another. A tag-push approval
includes automated GitHub publication. No private-key bytes.

## Release-note template

```text
Mirrors PROPOSED_TAG at S2_COMMIT.
Accepted in this scope: only matrix rows MW-71 has flipped.
Not run by the Linux workflow: live model checking, full cross-client
qualification, native Windows validation.
Not claimed until accepted: M5, Q1/Q2, DPM, full Windows lake test,
deployment, reboot, compatibility cycles.
Runtime: Linux x86-64, OpenSSL 3, GMP. Lean is not required to run the
archive. Clients and credentials are not bundled.
```

`publish.sh` uploads the builder `release-notes.txt`. Substituting this
text is a reviewed publication input. Uploaded notes must not exceed
accepted rows.
