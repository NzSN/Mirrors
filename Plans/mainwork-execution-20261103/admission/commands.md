# Admission command recipes (not executed)

Parsers confirmed by logs `071`–`080`. Working directory for every Mirrors command: `/home/lsz/Codebase/Mirrors`. Python: `/usr/bin/python3`. Do not run these until MW-12, MW-31, and MW-32, and until every `MISSING_*` token below is replaced. A token is an unresolved input. Historical endpoints are not substitutes. This file does not claim `REFERENCE DISTRIBUTION QUALIFICATION GREEN`, `REMOTE INTEROP PASS`, or `ALL LAKE TESTS GREEN`.

Checked-in catalogs and locks are read-only. Refresh, snapshot, cache, install, and audit outputs go under the proposed candidate. That directory was not created.

## Bindings

```text
MIRRORS=/home/lsz/Codebase/Mirrors
ECMA=/home/lsz/Codebase/MirrorECMA
GATE=/home/lsz/Codebase/MirrorGate
CPP=/home/lsz/Codebase/MirrorCPP
LEAN_CLIENT=/home/lsz/Codebase/MirrorLean
RUST=/home/lsz/Codebase/MirrorRust
CANDIDATE=/var/tmp/mirrors-mainwork-admission-20261103
PY=/usr/bin/python3
GIT=/usr/bin/git
LDD=/usr/bin/ldd
LAKE=/home/lsz/.elan/bin/lake
BWRAP=/usr/bin/bwrap
CATALOG_BIN=$MIRRORS/.lake/build/bin/framework_catalog
FRAMEWORK_CATALOG_SHA256=5a64a5bd40e999b20dd8268f2846c0f5ad5359067db9f014379c150e27d76126
NODE_ARCHIVE=$MIRRORS/.golden-build/version-0.1/toolchains/node-v24.15.0-linux-x64.tar.xz
TS_MODULES=$ECMA/node_modules
WHEELS=$MIRRORS/.golden-build/rc3-s5-20261031/prepared/evidence-wheels
BATTERIES_BUNDLE=MISSING_LOCKED_BATTERIES_BUNDLE
STRACE=MISSING_STRACE_EXECUTABLE
STRACE_SHA256=MISSING_STRACE_SHA256
ECMA_NODE_BIN=MISSING_EXTRACTED_LOCKED_NODE_BIN
```

`FRAMEWORK_CATALOG_SHA256` is the 2026-11-03 bootstrap observation (119687824 bytes). At execution, recompute `sha256sum` of `CATALOG_BIN` and abort if it differs. A binary rebuilt after MW-12 makes this value stale; replace it before use. Do not treat it as a finished C3 pin.

`BATTERIES_BUNDLE` must be a regular file of 3739542 bytes and sha256 `73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a`. The superseded file under `.golden-build/rc3-20261031/inputs/sha256/f6efbfeb6353195c3318e3ef6e46d3e4e87897659989cd7322156d9e8a5f1cd3/` is not that input. Do not regenerate it.

`ECMA_NODE_BIN` is the extracted archive member `node-v24.15.0-linux-x64/bin/node`, expected 122889056 bytes, sha256 `d1de76d8edf2fededf6f8b30d244e2c0529ac607923a018283b77e9c74bd932c`. The member was streamed, not materialized. `/usr/local/bin/node` (v24.22.0) is rejected.

`WHEELS` is the pure-Python directory (runtime-tree `f2c2e4edb2fe7d20afeba90192d09683b5d810b8fb2fb76df0c99cecd5301861`). The cp312 trees of digest `6423086879a2db6ae9fb9ba5e69ea29cceb6d84a0a1f079e4f79bfd20c69d743` are recorded alternatives, not this binding. Omit `--lean-build-cache`, `--export-lean-build-cache`, `--apalache-archive`, `--java-archive`, and `--fail-at` on every command below.

Linux Apalache `.golden-build/tla-differential/toolchain/downloads/apalache-0.61.0.tgz` matches the dependency lock and is still omitted. Fresh-trace is not emitted: both profiles are `blocked-missing-java-artifact` (`MISSING_JAVA_ARCHIVE`, Microsoft OpenJDK 25.0.4+7). Java and Apalache stay out of checked profiles.

## 1. Candidate copies

Not executed. `install -d` creates only the new candidate. Destinations for `cp -a` of lock roots must already exist.

```bash
install -d -m 0700 \
  "$CANDIDATE/base/catalog" "$CANDIDATE/base/locks" \
  "$CANDIDATE/wsl2/catalog" "$CANDIDATE/wsl2/locks"
cp -a "$MIRRORS/catalog/framework-catalog.json" "$CANDIDATE/base/catalog/"
cp -a "$MIRRORS/distribution/reference-node/." "$CANDIDATE/base/locks/"
cp -a "$MIRRORS/catalog/framework-catalog-wsl2-26.04.json" "$CANDIDATE/wsl2/catalog/"
cp -a "$MIRRORS/distribution/reference-node-wsl2-26.04/." "$CANDIDATE/wsl2/locks/"
```

## 2. C0 refresh onto the copies

Blocked until MW-12 leaves a clean freeze. Do not refresh while MirrorECMA has untracked `node_modules-pnpm-isolated/`. Defaults select the Ubuntu 24.04 catalog and lock root, so both commands pass `--catalog` and `--locks-root`. `--skip-component-records` and `--skip-render` are required. Non-outputs, which must stay unchanged: `catalog/components/mirrors.json`, `MirrorECMA/catalog/framework-capabilities.json`, the compact JSON beside the catalog, and `Docs/framework-map.md` (the markdown path is hardcoded to the Mirrors checkout).

```bash
"$PY" "$MIRRORS/tools/distribution/refresh_identity.py" \
  --mirrorecma "$ECMA" --mirrorgate "$GATE" \
  --framework-catalog-bin "$CATALOG_BIN" \
  --catalog "$CANDIDATE/base/catalog/framework-catalog.json" \
  --locks-root "$CANDIDATE/base/locks" \
  --skip-component-records --skip-render
"$PY" "$MIRRORS/tools/distribution/refresh_identity.py" \
  --mirrorecma "$ECMA" --mirrorgate "$GATE" \
  --framework-catalog-bin "$CATALOG_BIN" \
  --catalog "$CANDIDATE/wsl2/catalog/framework-catalog-wsl2-26.04.json" \
  --locks-root "$CANDIDATE/wsl2/locks" \
  --skip-component-records --skip-render
```

The printed selection is `IDENTITY REFRESH GREEN catalogSha256=<digest>`. That line was not produced. Expected pre-refresh canonical digests are base `e971cfec068c09532f2ffd01b15425be33aab42fa7dca507c0a0fe844c818b59` and WSL2 `3bef64ce1e1e4fdc7b9d99e2cb4f5a1f165cd54f49cdeac7af42f6c3130253ee`. A real refresh binds the frozen trees and will change the candidate selection. It must not change the checked-in files.

## 3. Source snapshots

`--out` must not exist. One snapshot per family, after that family's candidate lock is the frozen lock.

```bash
"$PY" "$MIRRORS/tools/distribution/snapshot_sources.py" \
  --component-lock "$CANDIDATE/base/locks/component-lock.json" \
  --out "$CANDIDATE/base/snapshot" \
  --mirrors "$MIRRORS" --mirrorecma "$ECMA" --mirrorgate "$GATE"
"$PY" "$MIRRORS/tools/distribution/snapshot_sources.py" \
  --component-lock "$CANDIDATE/wsl2/locks/component-lock.json" \
  --out "$CANDIDATE/wsl2/snapshot" \
  --mirrors "$MIRRORS" --mirrorecma "$ECMA" --mirrorgate "$GATE"
```

## 4. Cache build

Four commands. `FAMILY` is `base` or `wsl2`. `PROFILE` is `checked-replay-local` or `checked-replay-gate`. `CATALOG_FILE` is `framework-catalog.json` for base and `framework-catalog-wsl2-26.04.json` for WSL2. `--out` must not exist. Blocked on `MISSING_LOCKED_BATTERIES_BUNDLE`. A base cache may be built on this host as bytes. Its install and D audit may not.

```bash
"$PY" "$MIRRORS/tools/distribution/build.py" \
  --profile "$PROFILE" \
  --locks-root "$CANDIDATE/$FAMILY/locks" \
  --catalog "$CANDIDATE/$FAMILY/catalog/$CATALOG_FILE" \
  --out "$CANDIDATE/$FAMILY/cache/$PROFILE" \
  --snapshot-root "$CANDIDATE/$FAMILY/snapshot" \
  --lake-bin "$LAKE" \
  --node-archive "$NODE_ARCHIVE" \
  --batteries-bundle "$BATTERIES_BUNDLE" \
  --git-bin "$GIT" --ldd-bin "$LDD" \
  --typescript-node-modules "$TS_MODULES" \
  --evidence-wheels "$WHEELS" \
  --framework-catalog-bin "$CATALOG_BIN" \
  --framework-catalog-sha256 "$FRAMEWORK_CATALOG_SHA256"
```

`build.py` still copies schemas from the checkout `distribution/reference-node/` regardless of `--locks-root`. The cache copies lock `hostRequirements` and does not rewrite their `observedVersion` strings.

## 5. Install

Prefix is `$CANDIDATE/$FAMILY/install/$PROFILE`. It is absent, or a uid-1000 mode-0700 real directory, ext4, case-sensitive, with no symlink chain. Stage and `versions` inside that prefix must be the same device. The cache may sit on another device. `/tmp` is rejected. On this host only `FAMILY=wsl2` is eligible, and it remains blocked. `FAMILY=base` requires `MISSING_UBUNTU_24_04_X86_64_EXT4_HOST`. The installer's `--framework-catalog-bin` is the external verifier, not the cache copy. Profile identity comes from the cache manifest. There is no install profile flag.

```bash
"$PY" "$MIRRORS/tools/distribution/install.py" \
  --cache "$CANDIDATE/$FAMILY/cache/$PROFILE" \
  --prefix "$CANDIDATE/$FAMILY/install/$PROFILE" \
  --framework-catalog-bin "$CATALOG_BIN" \
  --framework-catalog-sha256 "$FRAMEWORK_CATALOG_SHA256"
```

## 6. Two D audits

Run only after the matching install. Still blocked here: `MISSING_STRACE_EXECUTABLE`, `MISSING_STRACE_SHA256`, and the `bwrap` namespace denial in log `054`. `--strace-sha256` is the hash of the strace file. Create the audit parent with `install -d -m 0700`; the audit file must not exist (`O_EXCL`). Three `--hide-root` values are required. `--combination` defaults to `candidate.local-node-checked`; the gate command must pass `candidate.node-gate`.

```bash
install -d -m 0700 "$CANDIDATE/$FAMILY/audit/$PROFILE"
"$PY" "$MIRRORS/tools/distribution/qualification.py" \
  --prefix "$CANDIDATE/$FAMILY/install/$PROFILE" \
  --framework-catalog-bin "$CATALOG_BIN" \
  --framework-catalog-sha256 "$FRAMEWORK_CATALOG_SHA256" \
  --bwrap "$BWRAP" --strace "$STRACE" --strace-sha256 "$STRACE_SHA256" \
  --combination "$COMBINATION" \
  --audit-out "$CANDIDATE/$FAMILY/audit/$PROFILE/install-diagnostics.json" \
  --hide-root "$MIRRORS" --hide-root "$ECMA" --hide-root "$GATE"
```

| Family | Profile | COMBINATION | Where |
| --- | --- | --- | --- |
| wsl2 | checked-replay-local | candidate.local-node-checked | this host, after blockers 2 and 3 clear |
| wsl2 | checked-replay-gate | candidate.node-gate | this host, after blockers 2 and 3 clear |
| base | checked-replay-local | candidate.local-node-checked | MISSING_UBUNTU_24_04_X86_64_EXT4_HOST |
| base | checked-replay-gate | candidate.node-gate | MISSING_UBUNTU_24_04_X86_64_EXT4_HOST |

Output schema is `mirrors.installed-consumer-audit/v1`. Command ids are `framework.install-diagnostics` and `framework.install-diagnostics-gate`.

## 7. Fresh Windows observation

Owner: the operator on the owned Windows console. Not this WSL coordinator. No SSH from here. Set `MIRRORS_REMOTE_HOST` and `MIRRORS_REMOTE_PORT` from that observation. Leaving both unset makes `selected_endpoint()` return historical `172.28.144.1` and `8999`, service name `workspace-native-console`. Do not use that default. Do not infer health from `172.20.208.1:8999`.

Read-only forms, with operator-chosen paths: `Get-CimInstance Win32_Process` and `Get-NetTCPConnection -LocalPort` for the selected port; `Get-FileHash` of the server executable, `java.exe`, and the staged Apalache archive and jar; certificate hash via `openssl x509 -in server.crt -outform DER` piped to SHA-256, plus `openssl x509 -noout -dates -subject -ext subjectAltName`; `git rev-parse` of the deployed source. Record key file mode and length only. Do not print private-key bytes.

Write `mirrors.windows-deployment-observation/v1` to `MISSING_WINDOWS_OBSERVATION` (regular file, not a symlink, at most 1 MiB). Required identity: endpoint host/port matching the explicit selection; `deploymentMode` `owned-native-console`; integer `processId` >= 1; `binarySha256`; `sourceBaseRevision` of 40 or 64 hex digits; `mtls.serverLeafSha256`; runtime exactly Apalache 0.62.2 archive `7cfadf6e8c04c63f05ac907ec9541c66297005c8cb5efb1731f6a838dfc3fad2`, jar `079b6c2320252469dcf79afec6886b8255d3dd1b34a9484433c88986752efaa8`, Java selected `25.0.4+7`, observed `25.0.4+7-LTS`, Windows archive `54ba13f3ef80887fa74708b2a32daaae6262517ba68433d850bb4b426343172b`, `java.exe` `58df5c13e5d6e68f242ad9b724479122828523008ef0907d3f2a02f54afaff23`; `sourceTreeSha256`, `sourceManifestSha256`, `runtimeManifestSha256` as 64 hex digits; timezone-aware `observedAt` and `processCreatedAt` with created <= observed and observed inside -300..3600 seconds of validation time.

Those Windows pins are not the Linux dependency-lock pins. The Linux harness Java archive `75894d107e474ffb6c947ab050e3893e0a1d3d40d36f107d42936ac6088769c1` and `bin/java` `e7bc0bc01b516a2ade3d9fceabc12d16c3a3b737adbf186a353602872ba31aad` are separate and were not observed here.

## 8. Five-client admission

Owner: remote/Windows operator, after the observation file exists. Not run. `OUTPUT_ROOT=$CANDIDATE/remote/five-client-output` must be created as a new or empty mode-0700 directory. `MIRRORS_REMOTE_INTEROP_ROOT=MISSING_REMOTE_INTEROP_ROOT` must be set to an existing fixture root. If that variable is unset, `tools/interop/run-remote.py` writes fixtures to `/mnt/c/Users/ayden/Desktop/Workspace/MirrorsRemote/interop`. Do not use that write as the default.

Rows: cpp, haskell, rust, lean, ecma, each `valid`, `invalid`, and `wrong-pin` (15), plus ECMA protocol cases `register`, `mismatch`, `register_traces`, `register_trace_gen`, `register_explore`, `register_explore_session`, `inline_multimodule` (7). Receipt schema `mirrors.remote-interop/v2`. Credential paths are type-checked and must not be printed. The wrapper removes `APALACHE_MC` before exec.

```bash
export ECMA_RUNTIME_ROOT=MISSING_PREPARED_ECMA_RUNTIME
export ECMA_NODE_BIN=MISSING_EXTRACTED_LOCKED_NODE_BIN
export ECMA_REF=MISSING_FROZEN_ECMA_REF
export ECMA_REPO="$ECMA"
export CPP_REPO="$CPP" CPP_REF=MISSING_FROZEN_CPP_REF CPP_BIN=MISSING_CPP_BIN
export RUST_REPO="$RUST" RUST_REF=MISSING_FROZEN_RUST_REF RUST_BIN=MISSING_RUST_BIN
export LEAN_CLIENT_REPO="$LEAN_CLIENT"
export LEAN_CLIENT_REF=MISSING_FROZEN_LEAN_REF
export LEAN_CLIENT_BIN=MISSING_LEAN_CLIENT_BIN
export HS_REPO=MISSING_HS_REPO HS_REF=MISSING_FROZEN_HS_REF HS_BIN=MISSING_HS_BIN
export MIRRORS_REMOTE_ADMIN_OBSERVATION=MISSING_WINDOWS_OBSERVATION
export MIRRORS_REMOTE_HOST=MISSING_REMOTE_HOST
export MIRRORS_REMOTE_PORT=MISSING_REMOTE_PORT
export MIRRORS_REMOTE_SERVER_PIN=MISSING_SERVER_LEAF_SHA256
export MIRRORS_REMOTE_SERVICE_BINARY_SHA256=MISSING_SERVICE_BINARY_SHA256
export MIRRORS_REMOTE_SERVICE_SOURCE_REF=MISSING_SERVICE_SOURCE_REF
export MIRRORS_REMOTE_CLIENT_CERT=MISSING_CLIENT_CERT
export MIRRORS_REMOTE_CLIENT_KEY=MISSING_CLIENT_KEY
export MIRRORS_REMOTE_CA=MISSING_CA
export MIRRORS_REMOTE_INTEROP_ROOT=MISSING_REMOTE_INTEROP_ROOT
"$PY" "$MIRRORS/tools/interop/run-remote.py" "$OUTPUT_ROOT"
```

Current non-binding `HEAD` observations are ECMA `f94358834dce2e527c8bc8feec0423a54cf4176c`, CPP `8c542a6b1339cc0b6176465ff7f17a32e614553d`, Lean `a8634ebe2455f97d15b55bec3c810d945cb6e3d3`, Rust `6b9480ab81717b76ca7f74b41fc554578b70c890`. They are not the frozen refs. The reviewed pin `tools/interop/ecma-runtime-pin.json` currently records that ECMA revision. Rebuild the runtime only after freeze:

```bash
"$PY" "$MIRRORS/tools/interop/prepare-ecma-runtime.py" \
  --repo "$ECMA" --ref "$ECMA_REF" --node "$ECMA_NODE_BIN" \
  --node-modules "$TS_MODULES" \
  --out "$CANDIDATE/remote/ecma-runtime" \
  --pin-out "$CANDIDATE/remote/ecma-runtime-pin.json"
```

Both outputs must not exist. Pin schema `mirrors.interop-ecma-runtime/v1`. Remote model-check is a later, separate command and additionally needs the `MIRRORS_REMOTE_APALACHE_*` and `MIRRORS_REMOTE_JAVA_*` values to equal the Windows constants in section 7, plus `.lake/build/bin/mirror` and `test/specs/HourClock.tla`. Do not launch it from this coordinator. Log `077` already showed the fail-closed missing-environment path.

## 9. Windows lake admission

Owner: Windows operator, on a separately admitted live-check host (`MISSING_WINDOWS_LIVE_CHECK_HOST`), after MW-32. Not this coordinator. Set `MIRRORCPP_PREFIX` to the admitted MirrorCPP prefix (`MISSING_MIRRORCPP_PREFIX`). The lakefile `test` script builds, then runs the Python checks. It runs `tools/check-cpp-integer-maps.py --prefix "$MIRRORCPP_PREFIX"` only when that variable is set; otherwise it prints `SKIP`. OpenSSL and zlib DLLs, the service account, and `TEMP` come from the remote-server guide and stay operator inputs. No local TLC or Apalache is run here.

```bat
set MIRRORCPP_PREFIX=MISSING_MIRRORCPP_PREFIX
lake test
```

## Owners

Distribution/admission operator: host tools, installing `strace`, user-namespace permission, restoring the locked Batteries bytes without regenerating them, confirming the pure-Python wheel directory, and creating the candidate. Remote/Windows operator: endpoint, certificate, observation file, Windows build, and the Haskell checkout. Source job: MW-12 freeze and MW-20/MW-31/MW-32 delivery. This task executed none of those.
