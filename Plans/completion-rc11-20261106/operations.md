# Rc.11 reviewed operation card

Executed under the subsequent user approval. See [completion](completion.json)
and [resolved deployment incident](deployment-incident.json). The original
operation proposal below remains historical; `deploy-windows-v2.ps1` is the
corrected controller used for successful replacement.

Status: prepared only. No remote source/tag/release mutation, production
replacement, or reboot has been performed. The original shared main/index remain
unchanged. The governing execution plan requires separate approvals for these
operations; user approval of earlier Windows testing has already been exercised.

## Source and release publication

- Mirrors source/tag commit: `19c31bf09b58e27c2942ca123a2017c30b638216`.
- Local annotated tag: `v0.2.0-rc.11`, object `1defd75cf9e1df347103f4414ef43a10d1fe26e6`.
- MirrorGate repair: `cd4914b2fa68aaa4f22955352b81cbb890ffd6f0`, parent `4b379ac0c017e7621c945ebf8c106cd98a6c70d1`.
- Mirrors prior remote main: `f889e5e6b3197f5f008866db33848c57127cee2e`.
- A following evidence-only delivery commit carries this final checkpoint;
  [delivery.json](delivery.json) identifies it. It does not move the qualified tag
  or award qualification to a different source revision.

Immediately before pushing, reobserve both remote main refs, tag absence and
release/draft absence. Refuse divergence; do not force-push or replace a tag.
Publish the reviewed Gate and Mirrors branches, verify remote full SHAs, then
push the rc.11 tag only with approval that includes the automated GitHub release
publication in `.github/workflows/release.yml`.

The workflow builds its Linux asset on Ubuntu 24.04, runs focused release gates
and an isolated archive check, creates a draft and publishes a prerelease that
is not Latest. Verify its source manifest, gate receipts, asset checksums, tag
peel and release flags. Its generated Linux bytes are distinct from the local
WSL2 package and receive only their actually observed hosted gates. Do not
blindly rerun over a partial draft or overwrite assets.

The separately reviewed Windows asset is
`mirrors-v0.2.0-rc.11-windows-x86_64.zip`, SHA-256
`f5ec1c9ba3204be04f797acb9086c3a6edd00dce81d7f478c5292b377b7c7df0`.
Upload only with Windows-asset publication approval, after checking absence;
never use `--clobber`. [Release notes](release-notes.md) state the qualification
boundaries and may be applied to the verified release.

## Production replacement

Host `win10` / `192.168.150.219`; service `ModelMirrors`; binary
`D:\ModelMirrors\bin\ModelMirrors.exe`.

- Expected old SHA: `8173ddea65f78a88b1a303f8a233dd7113b28e7dc8aefd8916a5add25a3687cc`.
- Candidate SHA: `5bfb5248a7ab74bfbe6c86361146daa20b0e5e864699c820269279747ef81fd4`.
- Verified rollback: `D:\ModelMirrors\staging\completion-rc11-20261106\rollback\ModelMirrors.exe`.
- Existing production certificate pin: `b2fc7265145cf2b89a1a248b0932885df8d300121b47f7854317ece4bac9ce67`.
- Existing certificate IP SAN: `192.168.150.219`; leaf and CA currently expire
  2026-11-13. Recheck validity before the operation; credentials stay host-local.

[deploy-windows.ps1](deploy-windows.ps1) defaults to preparation only. Its
explicit `-Apply` operation rechecks old/new/rollback hashes, all DLL identities,
configuration hashes and credential validity, stages the new executable, stops
and waits for the service, atomically replaces only the executable, restarts,
then runs four-way mTLS and wrong-pin controls. A failure after stop requests
restores the retained old binary, restarts and reruns the controls. Rollback
execution is not claimed; the rollback bytes and current production health
have been verified. The native DLLs, service configuration and keys are preserved.

Production baseline and packaged candidate-port checks have passed. Their
receipts are retained under `.golden-build/completion-rc11-20261106/`.
Applying the script requires the separate production-replacement approval.

## Reboot and compatibility lifecycle

Reboot affects the entire shared Windows host. It requires a separately approved
window after successful deployment. Reobserve automatic service startup,
binary/DLL/configuration hashes, listener, certificate/runtime identities, then
run `production-health-admitted.py post-reboot`. Stop/start alone earns no reboot
credit.

No compatibility retirement is proposed. Two actual shipped cycles with complete
matrices, real-workload hashes/counts/divergence/incident records, consumer
migration acknowledgements, and tested fallback remain future prerequisites.
The request for the real workload and consumer acknowledgements is still pending;
calendar time and repeated synthetic runs cannot substitute for those inputs.
