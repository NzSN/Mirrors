# SANY artifact re-pin and scoped closure — 2026-10-28

The user explicitly requested re-pinning SANY and excluding the remaining native
Linux/delegated-cgroup acceptance from this work. That exclusion is not a native
pass or a new M4/framework qualification. Earlier October 28 failed receipts and
the October 26 profile migration remain unchanged historical evidence.

## Reviewed artifact

The fresh download from the configured v1.8.0 release URL has:

| Field | Observed value |
| --- | --- |
| SHA-256 | `fc6878c603f0fdc18b9fe3e5bf51860cb90ab5b1154e3c371660c036d6bdd63e` |
| Size | 4,504,421 bytes |
| Computed SHA-1 | `bdfd4b754eee174f0bcdeaaffb96fa4d04bfbda8` |
| Manifest implementation version | `2.0 2026-10-28` |
| Build revision | `56d37a9b7bf529086fd961160e0b8975e224eafc` |
| Build timestamp | `2026-10-28T01:45:57.306Z` |
| Standard-library digest | `fc1e01131317e322a90eb5534fc217f6a1b64df8de540d949255eaa7d8ff88ad` |

The lock now records the actual development-build metadata rather than treating
the mutable v1.8.0 asset URL or legacy local filename as a version assertion.
Its SANY 2.2 help banner changed as well; the pinned banner matches the actual
`tla2sany.SANY -help` output. The SHA-1 is computed from the downloaded bytes,
not asserted to be an independently observed release-page checksum.

All 20 standard-module entries produce the same aggregate digest as the prior
pin. All 11 catalog module hashes and 17 reviewed import edges match. Therefore
frontend profile 6, standard catalog v3, corpus sources, summaries and the active
difference registry are unchanged; no new differential approval is inferred.
Apalache and Java pins are unchanged.

The prior configured artifact hash was `d15655ee…`; the pre-existing active cache
instead contained `db131ddb…`. Those cached bytes are preserved under the dated
`before-repin-20261028-db131ddb48e7` sibling filename. The reviewed new jar is
retained in the explicitly selected ignored content-addressed store
`.golden-build/tla-differential/artifact-store/sha256/<artifact-sha256>` and
installed through the existing checked no-overwrite helper. A fresh SANY-only
restore from that store passes with network access disabled. Jar binaries are
not committed.

## Validation

| Check | Result | Receipt |
| --- | --- | --- |
| Catalog hashes and public/local import facts | Two tests pass | [standard-catalog.log](standard-catalog.log) |
| Offline differential suite | 78 run, 74 pass, four explicitly live-reference skips | [offline-differential.log](offline-differential.log) |
| Complete local non-model aggregate | Exit 0; `ALL LOCAL NON-MODEL GATES GREEN` | [no-model.log](no-model.log) |
| Real SANY help and configured banner | Exit 0; exact configured banner found | [sany-help.log](sany-help.log) |
| Fresh SANY-only content-addressed restore | Exact bytes/size/library identity, network disabled | [offline-restore.json](offline-restore.json) |

The aggregate includes the earlier runtime remediation and its job-retention,
trace-overflow and evidence regressions. It retains its normal explicit native
integer-map/live-model skips; no local Apalache or TLC is started. The SANY help
probe is diagnostic under the coordinator's Java, not admission of that runtime
for the unchanged Java 25 differential pin. Full live differential qualification,
installed/release acceptance and native runner acceptance are not claimed.

[Artifact identity](artifact-identity.json), [prior lock](prior-toolchain-lock.json),
[current lock](current-toolchain-lock.json), the [manifest](manifest.txt), and
[evidence inventory](evidence-inventory.json) bind these results. No commit, push,
tag, package publication or host provisioning was requested or performed.
