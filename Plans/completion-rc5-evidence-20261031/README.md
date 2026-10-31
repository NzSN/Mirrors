# rc.5 clean packages and S5 admission — 2026-10-31

Executed the next boundary of the
[completion plan](../completion-qualification-release-plan-2026-10-30.md)
after the user's request to perform it. The source is committed Mirrors
`3ee3d9226f6258583fe7266c1737acff5abd1edf`, tree
`de476486fe23bb5f04ee7f8878355ffcf46fbee1`, product `0.2.0-rc.5`.
The annotated tag exists **only in the separate build clone** at
`.golden-build/completion-rc5-20261031/source`; its object is
`19db70433443d21fe5a4919873be6250fa92472e`. The shared checkout's tag refs were
not changed. Initial and final remote observations both bind `origin/main`
to the candidate and show no remote rc.5 tag.

## Results

| Boundary | Result |
| --- | --- |
| S3.1–S3.5 Linux construction | Passed from a clean clone/tag and exact Batteries source revision `4488d40d…`; 11 release-tool tests and seven focused release checks passed. |
| S3.6 isolated runtime | Passed on the actual **Ubuntu 24.04.3 WSL2** host, glibc 2.39. Lean/Lake were absent from the runtime PATH; the working directory was empty and the archive was read-only. |
| S3.7 Windows construction | Passed on the actual Windows 11 host `L`; 606 Lake jobs, exact 9,367-file source archive, no source overlay, and unchanged source hashes after gates. |
| S3.8 Windows package | Eight selected non-model suites passed; every selected binary/DLL is hashed, PE import closure checked, and two ZIP packagings of the same bytes are identical. |
| S3.9 package set | Complete scoped Linux/Windows artifact set in `package-set.json`. |
| Linux source-only checks | Complete repository-owned aggregate printed `ALL LOCAL NON-MODEL GATES GREEN`. Optional/native and live exclusions remain in the log. This is not a finalized M5 producer. |
| S5.1 host observation | Actual Ubuntu 24.04.3 WSL2 recorded. The October 30 Ubuntu 26.04.1 WSL2 receipts remain historical and unchanged. |
| S5.2 partial preparation | Fresh C0 and immutable component snapshots prepared; complete distribution admission awaits the exact locked Batteries carrier. |
| S5.3/S5.4 installation and D | Awaiting external input. The real cache builder rejected the available carrier. **0/2 D audits completed.** |
| S5 qualification | **0/18 qualified commands, 0/16 qualified tiers.** Remote oracle/client admission, full native Windows tests, installed DPM, Q1/Q2 and their controls remain outstanding. |

The selected Windows gates are `fixtures_replay`, `diff_cross`,
`model_interface_spec`, `stdio_smoke`, `transport_spec`, `jobstore_spec`,
`async_resource_spec`, and `dpm_sync_spec`. This is not full Windows `lake test`.
The local non-model runner retains its optional native integer-map and Rust
binding-execution skips, four live differential skips, and excluded live
model-checking tiers. No local Apalache/TLC was started.

## Artifacts and identity

`package-set.json` binds both archives, embedded/external build manifests,
member hashes, exact source/tag, host, and validation scope. Archives are kept
under the ignored, owner-only `.golden-build/completion-rc5-20261031/` root:

- `dist-linux/mirrors-v0.2.0-rc.5-linux-x86_64.tar.gz`
- `dist-windows/mirrors-v0.2.0-rc.5-windows-x86_64.zip`

Both directories retain external `.build.json` and `SHA256SUMS` files. The
Linux package follows the repository release tool; Windows retains the native
build receipt and explicit packaging harness. Repeat packaging does not
establish reproducible compilation.

The observed Linux host differs from the selected October 30 coordinator.
This continuation uses the existing Ubuntu 24.04 catalog for **24.04 WSL2
admission preparation only**. It neither relabels this host as 26.04 nor grants
native-Linux or 26.04 qualification. The optional scope question and missing
artifact request were sent while independent packaging work continued.

## Fresh C0 and actual S5 blocker

The separate C0 selection is
`50b12873ffd6799174efea4c1ee69afdbd2e592370e39b39cc84c9d5fab305a8`.
All component refs are clean:

| Component | Revision |
| --- | --- |
| Mirrors | `3ee3d9226f6258583fe7266c1737acff5abd1edf` |
| MirrorECMA | `f94358834dce2e527c8bc8feec0423a54cf4176c` (the October 29 client cohort) |
| MirrorGate | `4b379ac0c017e7621c945ebf8c106cd98a6c70d1` (committed runtime repairs) |

The catalog and refreshed locks are retained in `s5-c0/`. They were generated
outside the clean release source. No checked-in catalog or companion checkout
was edited. The source snapshot and its index remain in the ignored work root.

The required prepared artifact is `batteries-v4.33.0.bundle`, **3,684,180 bytes**,
SHA-256 **`f6efbfeb6353195c3318e3ef6e46d3e4e87897659989cd7322156d9e8a5f1cd3`**.
Three available retained bundles are each 3,739,625 bytes, SHA-256
`69a03e73a2cffcf1f251bc1e13a6d262bc8d32001e06e100119158c2c0f463aa`.
The admitted-verifier cache-build attempt exited 1 with
`Batteries archive differs from dependency lock`.
The dependency lock was not changed. A separately generated Git bundle was
used only to transfer the exact source revision for the Windows release
build; it is not admitted as the distribution carrier.

The next execution is to supply the exact pinned carrier, complete distribution
construction and both D audits, then run the selected M5 inventory in order.
Fresh remote endpoint/backend/certificate and five-client runtime admission is
also required; no historical PID, endpoint, or certificate is credited here.

## Retained failed attempts

Every command receipt records argv, cwd, start/finish, exit and raw-log hash.
Initial failures remain separate from the later successful runs:

- The standalone distribution tests ran before their `framework_catalog`
  prerequisite was built; the later complete aggregate passes 55 tests.
- The first C0 refresh refused clone-local origin URLs. Setting canonical
  origins in the isolated clones resolved it without source changes.
- An initial distribution-builder invocation used an invalid verifier-hash
  argument and earned no admission credit. The corrected attempt reached and
  rejected the actual mismatched Batteries carrier.
- Windows attempts 1–3 encountered path-length, documentation-symlink, and
  missing dependency Git-metadata setup failures.
- Windows attempt 4 compiled the source but exposed an incompatible MinGW
  library through the broad OpenSSL library path. Attempt 5 used an isolated
  directory containing only the exact OpenSSL import libraries and linked
  successfully, then failed because transport tests could not find `chmod`.
- Attempt 6 added the installed Git Unix helpers to PATH, revalidated all
  source bytes, rebuilt with the tracked library setting, and passed all
  eight suites. Its native receipt, import-library hashes and logs are final.

No product source was changed to accommodate these setup failures. The native
build was resumed only after exact source/dependency checks. The final Windows
observation found zero staged executables running. Failed staging directories,
throwaway PKI, build caches and all old evidence are preserved outside the
public package payloads.

## Recheck

```sh
python3 Plans/completion-rc5-evidence-20261031/verify.py
```

The offline verifier checks inventory membership and file hashes, retained
source/archive/member bytes, tag/source bindings, all successful gate receipts,
both package manifests, C0, the actual carrier refusal, and the stage ledger.
Seven negative controls reject missing/changed archives and unearned D, M5,
framework, installation, or release credit. These are record-integrity controls,
not the pending S5 Q1/Q2 controls.

No source commit/push, remote tag, release publication, production operation,
reboot, native M4, complete S5 or release admission is claimed.
