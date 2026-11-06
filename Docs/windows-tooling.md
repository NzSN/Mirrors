# Native Windows tooling boundary

The November 6 completion iteration adds native process ownership and evidence /
transaction primitives. Its dated [iteration record](../Plans/completion-rc10-20261106/README.md)
owns actual results and exact source inputs; implementation alone grants no new
framework, installed-distribution, release or production qualification.

## Declared scope

The exercised host is Windows 10 Enterprise x64, build 19045, with task-local
Python 3.12.10 and its pinned pure-Python validation packages. Storage requires a
local NTFS volume; remote devices, UNC namespaces, FAT and reparse traversal
refuse. Existing reference Node/Gate runtime profiles remain Linux/WSL2 profiles.
Testing the transaction engine on NTFS does not admit Linux artifacts as native
Windows installations or create a Windows Gate backend.

## Storage and retained bytes

The private store creates explicit current-user-owned ACLs. Validation checks the
actual owner SID and every granting ACE; another principal or a null DACL refuses.
An inherited ACL is allowed only when its effective grants remain owner-only.
Python's Windows `mkdir(0700)` administrator-readable ACL is not used as a
substitute for this contract.

Directory components are opened separately using native directory-relative
handles with reparse processing disabled. Reads compare actual opened/named NTFS
file identities and bounded byte counts. Rename/replacement of a directory name
does not redirect a held directory's children. Alternate streams, reserved DOS
names and ambiguous native file names refuse before creation.

File bytes are written in binary mode. Canonical JSON, archive members and locked
input bytes retain their original line endings. POSIX paths describing a Linux
target are validated as POSIX paths even when verification runs on Windows.
Payload files and directories are flushed before exclusive index publication.
Publication uses a no-overwrite hard link, followed by directory flushing.

The transaction backend holds no-delete directory guards, uses byte-range locks,
and performs native atomic selector replacement. Moving or deleting a stage
exchanges its guard only at the metadata boundary, opens relative to its still
pinned parent and rechecks the exact directory identity. Journal stage/version
paths are bound to their manifest digest and constructor-generated name form.
Failures cannot select another drive, an alternate stream or another transaction.

## Processes and compiler helpers

The shared Windows process primitive assigns a kill-on-close Job Object at
creation time and inherits only the selected standard handles. Bounded readers
retain original stream bytes; deadlines and interrupts stop only owned members.
Cleanup confirms both an empty job and the root process's actual exit status.
DPM loads its exact hash-pinned helper; builds refuse stale helper chains.

The native collector handles actual console-break cancellation and retains the
native exit code independently from its interruption classification. E1 v1.0
keeps its frozen exit-record range; commands outside that range refuse evidence
admission rather than widening the schema or inventing a POSIX signal.

Native Rust compilation runs in a compiler-only job whose background helpers
are stopped when compilation ends. Unit binaries then run in separate strict
jobs: surviving application descendants refuse acceptance. Documentation tests
also retain strict descendant checks. Cleanup never searches or kills processes
by a global executable name. The generated test target remains under its owned
build tree.

These are trusted tooling/runner ownership boundaries. They are not a sandbox
for hostile same-user code, aggregate resource enforcement, arbitrary native
scheduling or active-process post-restart recovery. Those retain separate Gate,
M4 and scheduling contracts.

The generated Rust gate runs through `python3 tools/model-interface-rust/check.py`
on both platforms. `lake test` calls that native Python entrypoint directly;
Windows executable lookup for bare `bash` can select the WSL launcher before
PATH and lose the native SDK environment. The shell entrypoint delegates to the
same Python driver. Select `RUST_REPO` and admit Cargo before requiring this tier;
a full qualification run must observe its actual test execution marker.
