# S5-A rc.6 admission attempt — 2026-11-04

Status: **blocked on the exact locked Batteries carrier; S5-A is not accepted**.
The user requested execution of the next checkpoint step. This attempt checks
the existing rc.6 freeze and available execution context. It does not change
the selected source, catalogs, dependency locks, package bytes, or remote service.

## Completed observations

- The frozen base structural control and selected WSL2 catalog/lock pairs
  validate with the hash-pinned C3 verifier. Both immutable source snapshots
  and the running distribution builder match their frozen identities.
- Selected Mirrors remains `3c4a87309cc3a81924660497207d7c295759bdc1`,
  MirrorECMA `9192171fc5f8d8457f8d13ffaafa117222914ec2`, and MirrorGate
  `4b379ac0c017e7621c945ebf8c106cd98a6c70d1`. The retained companion copies
  remain clean. The source archive, Linux package, Windows package, and
  repeated Windows package all match their accepted S3 hashes.
- The selected execution catalog remains
  `4bb83aa2efb022e801c7be5d7efb102f32d2f354f01d5d002d4f8897197af1f5`.
  The base catalog `f2bf471a…` is a structural control, not an executable
  Ubuntu 24.04 admission on this host.
- Actual local host: Ubuntu 26.04.1 WSL2, kernel
  `6.18.54.1-microsoft-standard-WSL2`, glibc 2.43, uid 1000, ext4.
  The owner-only task stage passes case-sensitivity and symlink-chain checks.
  Lean 4.33.0 / Lake 5.0.0, Python 3.14.4, and Git 2.53.0 are observed.
  Historical profile `observedVersion` literals are not substituted for these
  current observations.
- The sandbox denies socket and strace probes; bubblewrap fails on its
  netlink socket. The separate host execution passes actual strace child
  tracing, user/network namespace creation, bubblewrap network isolation,
  and IPv4/Unix bind/listen probes. Every frozen tracer/loader/library hash
  matches. These are capability probes, not installed D audits.
- The locked Node archive matches 31,164,460 bytes / `47265558…`.
  Retained TypeScript and pure-Python evidence-wheel trees are inventoried in
  `build-inputs.json`; their digests are `78e37ff4…` and `f2c2e4ed…`.
  No cache build was started with a missing prerequisite.

## Blocking input

Required file: `batteries-v4.33.0.bundle`, **3,739,542 bytes**, SHA-256
`73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a`.

The recorded path is absent. Filename/hash-name and exact-size searches under
this checkout's `.golden-build`, readable `/tmp`, and readable `/var/tmp` find
no matching carrier. Permission-denied directories are explicitly retained in
the search receipt; this is not a claim to have searched every filesystem.
The original producer root `/home/nzsn/Repos/Mirrors` is absent on this host.
The available Batteries bundles are the superseded 3,684,180-byte `f6efbfeb…`
carrier; they are not admitted. The retained Batteries Git source used for S3
packaging does not replace the locked carrier. No bundle was regenerated and
no pin was changed.

`admit-inputs.py` exits 2 with `cacheBuildReady:false` for this missing input.
Both checked-replay cache builds, installations, and D audits are therefore
not run. Existing S3 binary archives are not distribution caches or D evidence.

## Remote observation and remaining admission

Read-only SSH observes `DESKTOP-6DKB5JD`, production service Running/Automatic,
PID 9920 created October 26, executable SHA-256 `8173ddea…`, listening on 8999.
The executable and PID agree with the earlier S3 observation. No process or
configuration was changed.

The observed public server certificate covers `192.168.150.219` and is valid
August 15 through **2026-11-13T12:50:06Z**, with DER fingerprint
`b2fc7265145cf2b89a1a248b0932885df8d300121b47f7854317ece4bac9ce67`.
This updates a public certificate observation only. No mTLS/model request was
made; no key was exported. Remote Apalache/Java archive and executable pins,
source/runtime manifests, selected owned-native-console fixture admission,
client pins and independently generated per-host credentials remain pending.
Production service inventory does not establish that separate fixture's
`mirrors.windows-deployment-observation/v1` admission. Observations also expire
and must be repeated before a remote producer.

The initial sandbox SSH denial and the first remote probe failure are retained.
The latter was caused by PowerShell treating OpenSSL's harmless "No extensions
in certificate" CA diagnostic as a terminating error. The corrected read-only
probe retains that diagnostic and succeeds; it does not ignore a failed gate.

## Resume

Restore the exact retained carrier from its original producer/store, then run:

```sh
python3 Plans/mainwork-s5a-rc6-20261104/admit-inputs.py \
  --batteries-bundle /absolute/path/to/batteries-v4.33.0.bundle \
  --out Plans/mainwork-s5a-rc6-20261104/build-inputs-restored.json
```

Require both byte length and SHA-256, then independently verify bundle integrity,
HEAD `4488d40d070b9700d4d5a6aa342f0d40c31b2a2d`, tree
`5a1de86f7997958aaffec998882c29006b688d1e`, and clean offline clone.
The admission helper checks dependency bytes; Git/source admission is a separate
required check. No success from that helper grants D or S5-A credit.

Continue with [the exact selected build/install/audit commands](resume.md).
Use the existing frozen WSL2 catalog, lock root, and snapshot; do not refresh
onto the documentation HEAD or replace the bundle with a regenerated carrier.
Both D audits precede dependent producers. Remote/client admission remains a
separate S5-A gate. Full Windows tests, M5/Q, framework, and release acceptance
remain open. No commit/push, tag, release, deployment, or reboot was performed.

## Evidence

- `collect.py`: bounded local observations; raw output lives under the ignored
  owner-only `.golden-build/mainwork-s5a-rc6-20261104/{sandbox,host}/` roots.
- `initial-run.log`, `host-run.log`: retained invocation summaries.
- `admit-inputs.py`, `build-inputs.json`, `build-inputs.log`: input identities
  and the actual missing-input refusal.
- `windows-observe.ps1`, `remote-observe.py`, `remote-probe*.json`,
  `ssh-initial.log`: read-only remote attempts, including retained failures.
- `result.json`, `inventory.json`: stage status and evidence hashes.
- `verify.py`: verify retained evidence and the bounded status claim.
