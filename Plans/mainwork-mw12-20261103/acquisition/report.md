# MW-12 exact-input acquisition

Observed 2026-11-03T03:23:36Z. New files are under `.golden-build/mw12-20261103/inputs/` and `Plans/mainwork-mw12-20261103/acquisition/`. Shared Git refs were left unchanged. `.golden-build/` is already gitignored.

## Isolated companions

Both checkouts are detached at the requested commits, with empty porcelain status. The product version is `package.json` `version`.

| Repository | HEAD | Tree | Package | Version |
| --- | --- | --- | --- | --- |
| MirrorECMA | `9192171fc5f8d8457f8d13ffaafa117222914ec2` | `3a48d828710fafdc9076f0b57bf4e089cdd372ee` | mirrorecma | 0.1.0 |
| MirrorGate | `4b379ac0c017e7621c945ebf8c106cd98a6c70d1` | `96e7fa4d0ac90c526d7e499f95664f00b1bc3e9b` | mirrorgate | 0.1.0 |

Origins are `https://github.com/NzSN/MirrorECMA.git` and `https://github.com/NzSN/MirrorGate.git`. Paths are `.golden-build/mw12-20261103/inputs/companions/MirrorECMA` and `.../MirrorGate`.

MirrorECMA attempt 1 exited 128 before any network call because `GIT_CONFIG_GLOBAL` was unset. Attempt 2 fetched that commit over HTTPS and exited 0. The resulting MirrorECMA checkout is not shallow. MirrorGate's shallow fetch exited 0 on attempt 1. No global Git URL rewrite was configured.

## Remote Mirrors

`git ls-remote https://github.com/NzSN/Mirrors.git refs/heads/main refs/tags/v0.2.0-rc.6` exited 0. It returned `refs/heads/main` as `75fbf962020cea8a13e009ecfdb3e912e7ce212f` and returned no `refs/tags/v0.2.0-rc.6` line. The shared repository was not fetched. Its observed HEAD at receipt time was `75fbf962020cea8a13e009ecfdb3e912e7ce212f`.

## Batteries carrier

Required bytes are absent, so nothing was copied and no bundle clone was made.

- File name: `batteries-v4.33.0.bundle`
- Bytes: 3739542
- SHA-256: `73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a`
- Revision: `4488d40d070b9700d4d5a6aa342f0d40c31b2a2d`
- Tree: `5a1de86f7997958aaffec998882c29006b688d1e`

The recorded path `.golden-build/batteries-repin-20261031/artifacts/sha256/73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a/batteries-v4.33.0.bundle` and `prepared.bundle` are absent. Filename lookup under `.golden-build` and `/tmp` found one bundle, the older carrier `.golden-build/rc3-20261031/inputs/sha256/f6efbfeb6353195c3318e3ef6e46d3e4e87897659989cd7322156d9e8a5f1cd3/batteries-v4.33.0.bundle`, 3684180 bytes, SHA-256 `f6efbfeb6353195c3318e3ef6e46d3e4e87897659989cd7322156d9e8a5f1cd3`. Exact-size lookup for 3739542 bytes returned no files. Five private `/tmp` directories were unreadable: `systemd-private-*` for wsl-pro, systemd-logind, polkit, and chrony, plus `/tmp/snap-private-tmp`.

## strace

`gpgv` accepted `/var/lib/apt/lists/archive.ubuntu.com_ubuntu_dists_resolute_InRelease` with Ubuntu Archive Automatic Signing Key (2018) `F6ECB3762474EDA9D21B7022871920D1991BC93C`, exit 0. `main/binary-amd64/Packages` is 7581722 bytes and SHA-256 `92eb335c0ed27983d41a5a0efdf0edce3e67bfa34e8e987af9df260ca72d9bf9`, matching the signed checksum. No local Sources index is present.

`apt-get download strace` exited 0. `strace_6.19+ds-0ubuntu5_amd64.deb` is 677520 bytes, SHA-256 `aa530bb652e46beaf92d5c916403182a5ac6b2ba79a94f18e5b9da45d1799ee5`. Control fields: package `strace`, version `6.19+ds-0ubuntu5`, architecture `amd64`. The signed stanza has no Source field, so the source package name is `strace` at that version. The executable is `.golden-build/mw12-20261103/inputs/strace/root/usr/bin/strace`, 2370264 bytes, SHA-256 `f47342683309e807bca57d6d89b82f94a9b39aa614e9c28c2b67cefbc35eee58`. Direct `--version` exited 127 because `libunwind-ptrace.so.0` was missing.

`libunwind8` 1.8.3-0ubuntu1 amd64, source package `libunwind`, came from the same signed index: 59630 bytes, SHA-256 `7a9978fadf0940f45500ced0fba219cb5954f322a31068b7b32ad04f3ddc5c3f`. `dpkg-deb -x` placed it at `.golden-build/mw12-20261103/inputs/strace/libunwind-root`. With that `usr/lib/x86_64-linux-gnu` directory on `LD_LIBRARY_PATH`, `strace --version` exited 0 and printed `strace -- version 6.19`.

## Blocker

The pinned Batteries carrier `73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a` (3739542 bytes) is not available in the searched local artifact locations. Bundle revision and tree were not checked because the bytes were not recovered.
