# rc.12 publication and production operation card

Status: exact-candidate qualification complete; publication and production actions
are prepared for review. The user's latest approval covered the exact Windows
source transfer and native tests. The owned fixture-only model checks completed
under the existing continuation scope after their payload evidence passed review.
No public branch/tag/release, production trust/configuration/binary replacement or
reboot operation has occurred in this campaign.

## Exact publication payload

- Qualified source/tag commit: `6882d5b8b4787977e847e5a77467b30bfdac19a2`.
- Local annotated tag: `v0.2.0-rc.12`; tag object
  `7642edc805797ef331ebc5ae86fdf884d53ca9ad`.
- Selected WSL2 C0: `b44fe3d94c0afab187642923f81eef4a387b579289a63231bf649bdb3325456d`.
- Last observed `origin/main`: `eadc64d670243f78288e76f9f2bccdfc5b05c309`;
  the remote rc.12 tag is absent. Reobserve immediately before any push.
- Repository `NzSN/Mirrors` is public. The separate local delivery commit carries
  only reviewed status/evidence documentation after the qualified source. Public
  inputs are in `delivery.json`; the exact local commit/file-list receipt is
  `.golden-build/completion-rc12-20261116/delivery-commit.json`. It does not move the
  tag or transfer qualification to that later documentation commit.
- MirrorGate `cd4914b2fa68aaa4f22955352b81cbb890ffd6f0` and MirrorECMA
  `9192171fc5f8d8457f8d13ffaafa117222914ec2` are unchanged inputs; no new companion
  source change or push is proposed.
- Windows asset: `mirrors-v0.2.0-rc.12-windows-x86_64.zip`, SHA-256
  `f7e8b290f26107385ce3e5a44ef0bb2adf17f3ebe81164b1b6d1f30566f929c0`.
- Locally qualified WSL2 Linux archive SHA-256:
  `dab25c57260c79228bb539609b09039bfca74c6aacf5f968754a72a3a4353cd1`.

After publication approval, refuse remote divergence or existing tag/release/draft;
never force-push, replace a tag or overwrite assets. Publish the audited branch,
verify its full SHA, then push the exact annotated tag. That tag push invokes the
GitHub workflow which builds and publishes its own Ubuntu 24.04 Linux prerelease
assets. Verify workflow results, archive/build manifests, checksums and tag peel;
upload the exact Windows asset only if absent, without `--clobber`. Download and
verify all four release assets. Apply the reviewed release notes and retain the
prerelease/not-Latest flags. Raw stores, source bundles, private command contexts,
keys, credentials and the 240 unrelated files are excluded from delivery.

## Production trust renewal and deployment

The [read-only prerequisites](production-renewal-prerequisites.json) observe
`ModelMirrors` Running/Auto on `win10` / `192.168.150.219`. Production binary
SHA-256 is `5bfb5248a7ab74bfbe6c86361146daa20b0e5e864699c820269279747ef81fd4`.
The tested candidate SHA-256 is
`5ebfb99399df6006b2dcae81a64525421ca0f4490ac19dcd3a9ed8f51676d5e9`.
The production CA, server and default client certificates all expired
`2026-11-13T12:50:06Z`. The CA signing-key file is present; its bytes were neither
read nor exported by the observation. A server-leaf-only renewal cannot repair
this expired chain.

The proposed production operation requires explicit approval for trust renewal
and the service interruption:

1. Preserve all existing credential, configuration, DLL and old/new executable
   identities plus rollback bytes. Retain the old expired certificates for audit.
2. Prepare renewed CA/server/default-client certificates in an owned private stage,
   preserving the existing signing/client/server private keys and subjects, the
   server IP SAN `192.168.150.219`, and a 90-day validity period matching the prior
   certificates.
   Private keys remain on their existing hosts. Verify key/certificate pairing,
   chain, validity, TLS 1.3/mTLS and newly selected leaf pins before activation.
3. Provide the renewed public CA/client certificates and server pin to the named
   client operators. Existing expired trust stores and client certificates need
   replacement. Obtain the consumer/workload owner input needed to coordinate
   external clients; no acknowledgement is fabricated or sent on their behalf.
4. Test the exact renewed material and candidate in a separate owned native stage.
   Require sync/async valid/invalid and wrong-pin controls. Verify the old binary
   can run under the admitted renewed PKI as the binary rollback option.
5. Use hash-guarded activation with explicit backup paths and preserved DLL/service
   configuration. Stop/wait, activate renewed material and the exact candidate,
   start, then verify service/listener/runtime/certificate identities and repeat
   the four-way mTLS and pin controls. On binary failure, restore the retained old
   binary under valid admitted PKI. Restoring expired certificates is restoration
   of the earlier degraded baseline, not a successful health rollback.

No renewal signatures, new production certificates, trust-store distribution,
service stop/start, binary replacement or production health credit is claimed by
this preparation. The qualification fixture uses separate credentials and is
stopped; it does not renew production trust.

## Reboot and longer lifecycle

A host reboot affects the whole shared Windows machine and requires its own
approved window after deployment passes. Reobserve Running/Auto startup, the
exact binary/DLL/configuration/certificate/runtime identities and four-way mTLS
controls after boot. Stop/start cannot supply reboot credit.

Two actual shipped compatibility cycles, real-workload hashes/run counts/byte
comparisons/incidents, named consumer acknowledgements and tested fallback remain
open. The workload entry point and owners are still missing. Retirement remains
a separate later decision; native-runner/M4 planning is withdrawn.
