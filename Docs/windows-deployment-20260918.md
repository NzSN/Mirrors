# Windows deployment record — 2026-09-18

This is a dated verified deployment, not a promise about the machine's future
state. General setup and client usage are in the [remote server guide](remote-server-guide.md).

| Item | Verified value |
| --- | --- |
| Host / service | `windows-dev` / `ModelMirrors` |
| Source commit | `f5f1985db8e2d4a1eebdd87c7f905f6ae8b0f3d3` |
| Product version | `0.0.2` (use the source/binary hash to distinguish builds) |
| Installed executable | `D:\ModelMirrors\bin\ModelMirrors.exe` |
| SHA-256 | `194fc1ca8b66f8ab559644eff832e722839d6aaabb2d76d1e20d20b7f25a74ed` |
| Service | Running, automatic startup, mTLS port 8999, four workers |
| Release directory | `D:\ModelMirrors\releases\20260918-f5f1985` |
| Rollback executable | `previous-ModelMirrors.exe` in that release directory |
| Rollback SHA-256 | `f27d955cac2f48f38eec2660eaad07d652ea88ffaeb6a5dd71feab49542d741f` |
| Evidence | `deployment.json`, build/gate logs, candidate and production async evidence in the release directory |

Acceptance passed: Windows build, Lean resource proofs, job-store regression,
stdio smoke, real Apalache CLI, candidate and production concurrent async valid/
invalid requests, cross-connection awaits, stable terminal results, and local CLI
async validation sending a three-module dependency closure through an SSH/TLS
relay. That relay test is not evidence of direct local CLI mTLS connectivity.
Existing OpenSSL, zlib and Apalache installation were retained. Full `lake test`,
a reboot test, and Windows heap-leak testing were not performed.
