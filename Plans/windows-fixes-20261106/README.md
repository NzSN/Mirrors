# Windows failure analysis and source fixes — 2026-11-06

**Historical intermediate repair record.** The completed rc.11 qualification, publication, deployment and reboot are recorded in [the final checkpoint](../completion-rc11-20261106/README.md). The original results below keep their earlier source identity and scope.

Current result: **the original DPM/CLI/installation failures are fixed and
validated on native Windows. Full Windows `lake test` now reaches distribution
and remains failed at its POSIX storage/tooling boundary.**

The user approved transferring and testing these fixes on `win10` after the
initial automatic-review refusal. Work uses the separate owned checkout at
`D:\ModelMirrors\staging\windows-fixes-20261106\Mirrors` on
`DESKTOP-6DKB5JD`, Windows 10 Enterprise build 19045. The exact tested candidate
is frozen base `f328e328…` plus the 11 files in `source-overlay.json`, not a new
Git commit or a renewed C0/framework qualification.

## Cause and remedy

| Failure group | Cause | Applied fix |
| --- | --- | --- |
| Seven process errors and associated leaks | Windows Python 3.10 cannot use the POSIX pipe selector/`os.set_blocking`; cleanup references unavailable `SIGKILL`/`killpg` | Creation-time job membership, kill-on-close ownership, explicit inherited handles, bounded pipe readers and capped retention |
| Seven cancellation controls | Controller assumes `/proc`, `prctl`, POSIX signals, signal masks and `waitpid` | Windows controller synchronizes the exact CLI callback on the host main thread; verifies actual job closure and log-handle release |
| Two CLI/import-isolation assertions | CLI loads POSIX libc through `ctypes.CDLL(None)` before argument parsing | Guard Linux setup and monitor the Windows launcher process handle for parent-death cancellation |
| Atomic activation | Linux-only `renameat2` and libc load | Windows same-volume rename that refuses existing targets |
| Inventory mode assertion | Windows `chmod` cannot toggle a POSIX executable bit | Bind the native read-only attribute and test a supported permission change |
| Retained TLA path regression | Diagnostic uses a Windows separator | Accept either separator while keeping the exact refusal assertion |

Admitted Windows file trees also reject reparse points, including junctions.
The five new native regressions cover argv/environment handling, startup failure
cleanup, acquisition failure before execution, junctions and actual launcher-death
cleanup. No original required DPM assertion was disabled.

## Native follow-up corrections

The first native fix attempt exposed delayed job accounting, cached directory
metadata undercounting open logs, and a cancellation-file publication race.
The fix reads fresh Windows file metadata, independently caps retained log bytes
by open-handle offsets, and publishes callback synchronization files atomically.

A stricter membership check then identified `conhost.exe` inside jobs created
with `CREATE_NO_WINDOW`. The retained bounded probe compares the actual member
executable names: hidden-console launch owns Python plus conhost; detached launch
owns Python alone. `DETACHED_PROCESS` plus explicit pipe handles prevents that
console helper. Genuine non-root job members still refuse immediately after
runner exit. Only root exit-accounting lag has bounded grace.

## Validation

| Run | Outcome |
| --- | --- |
| Final native DPM discovery | 92 run: 89 pass, three existing Linux-only installed-launcher skips |
| Final Linux DPM discovery | 92 run: 87 pass, five new Windows-only skips |
| Windows offline TLA tooling, Python 3.12.10 | 81 run: 73 pass, eight existing skips; repaired path assertion passes |
| Linux offline TLA tooling | 81 run, six existing skips, no failures |
| Final full native Windows `lake test` | Exit 1 at distribution, after passing DPM and subsequent model-interface/catalog gates |
| Native distribution diagnostic, prepared Python 3.10 | 12 errors in 13 discovered cases; imports prevent complete discovery |
| Native evidence diagnostic, prepared Python 3.10 | 26 failures and 28 errors in 81 discovered cases; imports prevent complete discovery |

The final full driver retains every failure. Distribution requires unavailable
`resource`, `fcntl` and `O_DIRECTORY`; evidence storage also requires POSIX
owner-only, descriptor-relative filesystem primitives and process semantics.
These require a separate Windows storage/locking/collector implementation that
preserves those contracts. They were not converted to skips or weakened into
path-only checks. Independent earlier Python 3.12 diagnostics additionally lacked
`jsonschema`; the selected Python 3.10 diagnostics above avoid that unrelated
prerequisite gap.

`native-result.json` binds the exact final source manifest and logs.
`native-command-receipts/` retains remote exit/hash receipts. All raw attempts,
including failures, remain under `.golden-build/windows-fixes-20261106/`.
The final source audit checks all 10,034 original Git blobs against the selected
overrides, verifies every fix hash, and independently confirms every original
checkout blob remains unchanged. The final observation finds no executable
process from either owned test stage; job logs report zero remaining members.

The initial `result.json` records the earlier pre-approval preparation state;
it is historical. `tested-overlay-2.json` and `tested-overlay-3.json` retain
intermediate candidates. Earlier accepted rc.8 M5/native/live records keep their
original identity. These changes remain uncommitted and do not grant full
Windows, framework, release or production admission.

API references: [Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects),
[creation-time job assignment](https://devblogs.microsoft.com/oldnewthing/20230209-00/?p=107812),
and [Windows directory moves](https://learn.microsoft.com/en-us/windows/win32/fileio/moving-directories).
