# Batteries carrier recovery — 2026-11-04

The user requested checking the original producer environment and recovering
the carrier if lost. The original `73130433…` bytes were not recovered in
the accessible locations. An offline regeneration from the exact pinned
Batteries source produced **the same bytes as the earlier retained
`f6efbfeb…` carrier**. The verified replacement is now present at the user-selected
Git-managed location, and both current dependency locks select it. This is
dependency recovery only; it grants no installed D, M5/Q or release acceptance.

| Identity | Previous selection | Recovered replacement |
| --- | --- | --- |
| Carrier | `batteries-v4.33.0.bundle` | `third_party/batteries/batteries-v4.33.0.bundle` |
| Bytes | 3,739,542 | 3,684,180 |
| SHA-256 | `73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a` | `f6efbfeb6353195c3318e3ef6e46d3e4e87897659989cd7322156d9e8a5f1cd3` |
| Source commit | `4488d40d070b9700d4d5a6aa342f0d40c31b2a2d` | Unchanged |
| Source tree | `5a1de86f7997958aaffec998882c29006b688d1e` | Unchanged |

## Search scope and retained failures

- The prior S5-A/local searches covered the checkout's retained artifacts,
  readable `/tmp` and `/var/tmp`; the later broader filename search covered
  local Codebase, Workspaces, Downloads and Knowledges. Permission denials
  and search limits remain in those records.
- Current Windows host `DESKTOP-C7HNV2Q` registers only Ubuntu-26.04; the
  original `/home/nzsn/Repos/Mirrors` environment is not registered there.
  Read-only WSL/registry observations are retained. The first sandbox WSL
  call failed on its vsock permission; host execution succeeds.
- Owned `win10` registers one Ubuntu WSL environment. Its default user cannot
  traverse `/home/nzsn`; the initial search fails with that permission error.
  A subsequent approved read-only check as WSL root finds `/home/nzsn`
  (uid 1001, mode 0750), but no `/home/nzsn/Repos/Mirrors` and neither exact
  recorded `prepared.bundle` nor content-addressed artifact path.
- A bounded local filename scan for Batteries/Mirrors/Ubuntu backup archives
  and WSL images under the mounted D drive and Downloads returned no matches.
  No original VHDX was mounted, no remote files were written, and no production
  service configuration or process was changed. This is not a claim that every
  machine or backup has been searched, or that the original bytes are
  permanently unrecoverable.

## Recovery and checks

`recover.py` first requires the exact clean, non-shallow local Batteries source
and a passing `git fsck --full`. It clones to task-owned staging, checks out
the selected revision, then creates the bundle with Git 2.53.0,
`pack.threads=1`, `pack.compression=9` and `bundle create ... HEAD`.

A separate offline clone from that bundle passes full fsck, exact commit/tree,
clean status, complete/non-shallow history with 1,309 commits, bundle verification
and upstream license byte comparison. The artifact is copied without overwrite
to the canonical path, made read-only, and rehashed. Its checksum equals the
earlier retained carrier; it does not equal the unavailable selection. No general
cross-host reproducible-generation claim is made.

`repin.py` changes only the carrier byte length and SHA-256 in each current
dependency lock. The existing `refresh_identity.update_locks` API regenerates
four fixture bindings per root. Catalogs, component locks, profile locks,
the Batteries source version, and other dependency records remain unchanged.
`before/` preserves the prior lock/fixture bytes; old dated evidence and ignored
frozen snapshots remain untouched. Current README/SHA256SUMS and the license
record describe the actual vendored bytes.

Both lock roots validate with the unchanged hash-pinned C3 verifier. All
**73 distribution tests** pass, including a new real-carrier regression that
requires the vendor bytes to match both locks and expose the exact bundle HEAD.
Canonical-path input admission now exits 0. The independent recovery verifier
also creates a fresh offline clone and rejects missing carrier, same-size
corruption, previous-pin-on-replacement, and changed-source controls.
Its first run incorrectly expected Git's complete-history diagnostic on stderr;
the retained Git receipt places it on stdout. The corrected verifier checks
both captured streams and succeeds; the first failure remains retained.

```sh
sha256sum --check third_party/batteries/SHA256SUMS
python3 Plans/batteries-recovery-20261104/verify.py
```

`carrier.json`, `lock-update.json`, and `result.json` bind source/artifact,
generation, validation, and retained receipt hashes. Raw environment/search,
Git, test, and input-admission logs remain under ignored owner-only
`.golden-build/batteries-recovery-20261104/`. Earlier missing-input receipts
remain accurate for their original `73130433…` selection.

## Next boundary

The carrier availability prerequisite is resolved for the new dependency
selection. The changed builder, vendor file, lock bytes and fixture bindings
need a new source/candidate freeze before cache construction, both installations
and D audits. Old rc.6 C0/package receipts do not inherit this re-pin. Fresh
remote/runtime/client admission, M5/Q, full Windows tests and release remain
separate. No long/full build, model operation, commit/push, tag, release,
deployment, reboot, or source-version change is performed.
