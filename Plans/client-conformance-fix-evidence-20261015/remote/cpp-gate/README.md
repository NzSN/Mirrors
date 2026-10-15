# C++ / Gate remote validation

Status: the selected C1 and K1 remote gates passed. Final matrix attempt 4 has
all 37 required actual Gate cases, an independent exact case inventory,
unchanged no-op binaries and no remaining owned Gate processes. Historical
failed attempts remain below as test/workflow diagnostics, not open production
failures. This record does not claim full client-guide or new platform coverage.

The selected host is `windows-dev` / `192.168.150.219`, WSL distribution
`Ubuntu`, unprivileged user `jlc`. The new source/tool root is
`/home/jlc/Tools/mirrors-client-fixes-20261015`, on a fresh D-backed ext4 image;
`/tmp/fix-tests` is a bind mount of that image's temporary directory. Large
outputs remain at
`D:/Desktop/Workspaces/Mirrors-client-fixes-20261015/cpp-gate`. No original
checkout, old installed SDK or old dependency cache was modified.

## Completed checks

| Boundary | Result | Evidence |
| --- | --- | --- |
| Frozen MirrorCPP / MirrorGate source transfer | 493 files verified before build; archive SHA256 `577f5fd3dd9fd4b52741d85a242b9d14b7250d2d52dcb73f6ce38eeb7628fc83` | `manifests/source-files.sha256`, `01-source-and-bwrap-prepare.log` |
| Private Bubblewrap prerequisite | Official v0.9.0 source built without patches; real unprivileged namespace probe passed | `02-bwrap-and-sdk.log`, `manifests/bubblewrap-provenance.json`, `manifests/private-bwrap.sha256` |
| C++ SDK | Fresh warnings-as-errors build; 3/3 CTest suites passed; subsequent build reported no work | `02-bwrap-and-sdk.log`, `sdk-noop-build.log`, `manifests/sdk-binaries.sha256` |
| Actual SDK / Node workers | Owned correct, owned faulty and attached correct controls passed using Node 24.15.0, Python 3.12.14 and actual Bubblewrap 0.9.0 | `05-sdk-real-worker.log` |
| Strict 0600 K1 matrix | 103 assertions in one test passed on ext4, including unchanged bytes/modes and an accepted valid 0600 handshake | `tls-key-mode.log` |
| TLS normal/failure/integration group | 167 assertions across 10 cases passed from a separate fresh TLS-enabled Debug/Werror build; no-change build did no work | `tls-normal-and-framing.log`, `03-tls-build-and-tests.log`, `tls-noop-build.log` |
| Fresh install and downstream consumers | Installed package consumer and rebuilt SDK/facade consumer passed against corrected installed TLS objects | `06-install-and-consumers.log`, `installed-prefix-ready.json`, `manifests/downstream-consumers.sha256` |
| Actual facade matrix attempt 1 | Integration driver/SDK/facade/receipt targets built; receipt tests and four owned controls passed; intentional-cleanup assertion failed | `07-facade-matrix-attempt1.log`, `cpp-failure-matrix-attempt1.jsonl` |
| Cleanup after failed attempt | No remaining Gate processes observed; original system Bubblewrap hash retained outside the private namespace | `gate-processes-after-attempt1.json`, `manifests/system-bwrap-before.sha256` |
| Final actual facade matrix, attempt 4 | 37/37 required rows: 18 owned, 19 attached; every attached second session survived; all four broker-fault rows preserve the exact observed SDK classification | `matrix-final-summary.json`, `cpp-failure-matrix-attempt4.jsonl`, `07-facade-matrix-attempt4.log` |
| Final deterministic/incremental boundary | Both matrix builds reported no work; Counter/receipt binary hashes stayed unchanged; immutable CLI hash verified before/after; no owned Gate process remained | `matrix-noop-attempt4.log`, `manifests/matrix-noop-attempt4.sha256`, `gate-processes-after-attempt4.json`, `13-final-evidence.log` |

The real matrix's passing rows are correct replay, genuine Mirrors
`step_mismatch`, wrong-digest negotiation with zero worker acquisition, and an
equal-text ordinary adapter exception retaining `adapter_failure` without a
Gate primary snapshot. The next row deliberately throws during worker disposal.
The facade returned failure, but the test driver still globally required
`cleanup_confirmed=true`; the retained error is:

```text
Gate cleanup was not confirmed: cooperative dispose failed: same human text primary=same human text
```

A narrow test correction was reviewed and approved after preserving attempt 1.
It changes only the Counter test driver, test harness and integration README:
the cleanup row verifies its original `APPLICATION` code, empty stage,
worker-application origin, dispose operation, cleanup-only evidence and public
failure; other rows retain strict successful cleanup. An optional new private
persistent build directory avoids rebuilding unrelated objects on each
diagnostic iteration. The approved delta is retained in
`cleanup-harness-reviewed-delta.patch`; its transfer archive SHA256 is
`b0c1e16aa91ecdaf85d8bf37ccf35b795c2fb0332ad0cfc299c13283fb938cb9`.
The refreshed 493-file source manifest SHA256 is
`259cd85a20b68a235e12fcab900aef3c059b51926d5171b536113df94bc32513`.
No production source changed for this correction. Attempt 2 then passed six
owned rows, including the declared cleanup failure and real `BUILD_FAILED`,
before a test overconstrained the broker-filtered wrong-ID subfamily. The exact
SDK snapshots for all four injected broker-fault cases were retained using an
external output-only diagnostic with unchanged assertions:

```text
origin=sdk, code=CONTROL_DISCONNECTED, family=worker_transport,
stage="", operationId=0, operation=invoke|observe,
publicCode=mirrorgate.CONTROL_DISCONNECTED
```

The normative SO7 contract and approved plan require one combined worker
transport/protocol family. The reviewed test-only correction asserts the exact
observable fields above and records wrong-ID injection separately in
`faultInjection`. Direct SDK protocol regressions retain `worker_protocol`.
No broker, control schema or SDK production channel was added. The correction
and raw diagnostic records are `broker-observation-reviewed-delta.patch` and
`broker-snapshot-diagnostic.jsonl`; message spelling is not used to classify.
An explicit 33-row partial selector is retained separately and is not the final
37-row acceptance result.

Attempt 3 stopped before any row when a parallel native-build validation changed
the mutable CLI producer's hash. The coordinator restored the explicit compiler,
verified sources, and copied the final CLI to a separate immutable path. Attempt
4 uses only that exact copy after its focused CLI controls passed.

## Final identities and scope

The final 493-file MirrorCPP/Gate manifest is
`manifests/source-files.sha256`, SHA256
`5d2cb565c8d9dc51681171ae768a01d8e7cf2607402bfaaa1342cbd478e47d71`.
All 18 owned source files match the staged and parent-applied original checkout
bytes: `local-applied-source-parity.sha256`. The immutable Mirrors executable is
`D:/Desktop/Workspaces/Mirrors-client-fixes-20261015/cpp-gate/immutable/mirror`,
SHA256 `6e06ecd3d4d2975a42db2a1822b2d28d9e382f6d5b9bf48fa36c6c9ce27fa77d`;
its producer/source/native-input record is
`manifests/frozen-mirror-producer.json`.

The complete final JSONL evidence SHA256 is
`031326f2e5626dd47ef3efe64f001a806bc404921e3fe1fc2b0c0b38d3536ed0`.
`matrix-final-summary.json` independently verifies exact case coverage, all
19 attached second-session checks, all four broker-fault field records and both
intentional cleanup failures. Those two negative rows remain public failures
with their original structured cleanup evidence; every other row requires
successful cleanup. Every row confirms control shutdown, and the final process
scan is empty. No-op binary hash checks and final full-source verification
passed. No local build or runtime test was run on the coordinator.

## Toolchain and qualification limits

GCC 12.3.0 is an explicitly recorded reuse of the prior accepted override from
the documented GCC 13 baseline. CMake 3.28.4, cached nlohmann/json 3.11.3,
Boost 1.85 and Catch2 3.5.0 were used. Compiler jobs were bounded to two for
this workstream. The corrected TLS install is
`/home/jlc/Tools/mirrors-client-fixes-20261015/cpp-gate-install`;
`libmirrorcpp.a` SHA256 is
`3d4660e80e51d94087779f2a12ed01ed81b814bf8d62d76093be2f708e15ecbc`.

System Bubblewrap 0.6.1 was not used for qualification. A root-created private
mount namespace bind-mounted the actual private 0.9.0 binary only inside that
namespace, then dropped to `jlc` with zero effective/ambient capabilities.
The system file stayed unchanged. Official GitHub release/tag metadata is
retained; that release's asset digest is null and the tag signature was not
cryptographically verified. The observed archive hash and resolved tag commit
are recorded without claiming signature verification.

No Apalache, TLC or model service was launched. Native Windows/macOS TLS/ACL
profiles, other Gate backends, current-source Rust worker replay and hosted CI
toolchain parity remain separate checks. Private key material, compiled
binaries and dependency caches remain remote; only small logs/manifests and
workflow scripts are retained here.
