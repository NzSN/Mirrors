# Full native Windows lake test — 2026-11-06

**Historical initial failure record.** The completed rc.11 qualification, publication, deployment and reboot are recorded in [the final checkpoint](../completion-rc11-20261106/README.md). The original results below keep their earlier source identity and scope.

The user requested the full Windows `lake test`. The unchanged retained rc.8
checkout at `f328e328d6f961b49ccffefc0a6d0250bec2fb3c` was tested on
`DESKTOP-6DKB5JD` using native Lean/Lake 4.33.0 and Python 3.10.11, the
prepared native C++ SDK, selected task-local Apalache launcher/JAR and TLC JAR.
`run.ps1` records the complete process-local environment and exact command.

**Result: exit 1; full Windows acceptance remains open.** The original strict
driver was run without modifying source, required tiers or failure handling.
Its build preflight passed. Earlier gates passed, including native integer maps,
CMake consumption, bundle/closure checks, trace capture, stdio/TCP/mTLS framing,
async validation, async protocol model checks, fixture round trips, the 500-case
differential corpus and model-interface specification.

The driver stopped at DPM Python discovery: 87 tests ran, 10 failed, eight errored
and three carried existing skips. Errors reproduce missing Windows support for
pipe/process control (`os.set_blocking` under the selected Python, `SIGKILL`,
process-group semantics), activation (`ctypes.CDLL(None)`/`renameat2`), executable
mode validation and POSIX cancellation/import fixtures. Later distribution,
evidence and other driver gates were not reached and receive no pass credit.
The isolated DPM build probe prints its existing Linux-only skip.

The Windows job wrapper reports `TASK JOB CLEANUP active=0`. The final fresh
observation independently finds no processes executing from the task stage and
a clean source checkout at the same revision. The test harness changes only
its own staging files and process environment.

`result.json` binds the raw local log by SHA-256; `command-receipt.json` retains
the remote exit/hash receipt, and the final observation records source/cleanup.
Raw logs remain under `.golden-build/windows-full-20261106/`. Earlier accepted
M5/native/live results and historical failures retain their original scope.
