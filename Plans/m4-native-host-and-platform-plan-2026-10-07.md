# M4 acceptance and platform progression

Date: 2026-10-07
Status: capability preflight implemented; native-host execution unavailable.

## Platform decision

Accept the existing Linux/Bubblewrap backend on a native Linux runner before
adding a Windows or macOS Gate backend. The runner must supply an operator-owned
cgroup-v2 parent with cpu/memory/pids controllers enabled, unprivileged Bubblewrap,
loopback and ptrace, filesystem ownership tokens and a private durable state root.
This extends acceptance of an existing backend, not the existing M5 profile.

Current WSL2 source checks and prepared-filesystem recovery remain valuable but
cannot stand in for that native-host acceptance. The Windows Mirrors service is
an external model oracle; it supplies no Windows Gate isolation or recovery claim.
The user has not selected a new host or authorized installation of a new backend.

A later Windows backend requires a separately reviewed contract for job-object
process-tree ownership/limits, restricted-token/filesystem policy and reboot/
service lifecycle. A later macOS backend requires its own supported isolation,
resource and process-tree ownership contract; API availability alone is not
acceptance. Those backends are design choices, not implemented milestones.

## Read-only eligibility gate

Run from Mirrors:

```bash
python3 tools/qualification/preflight_m4.py
python3 tools/qualification/preflight_m4.py --cgroup-parent /operator/delegated/parent
```

The preflight imports Gate's actual `CgroupDelegation` validator and retains
source hashes, current kernel/UID, selected parent identity/refusal and the native
host distinction. It does not call `probe`, create a child, kill a process or
write a journal. A successful inspection exit is not enforcement acceptance.

The 2026-10-07 coordinator reports WSL2 kernel
6.18.40.1-microsoft-standard-WSL2. No operator parent was supplied. A control using
/sys/fs/cgroup refuses with “cgroup parent is not a serving-UID cgroup-v2
delegation”. Kernel enforcement and post-restart process recovery are untested.

## Required process-recovery extension

The source audit found an implementation gap in addition to the host gap:
Gate's existing recovery loop can reclaim an exact delegated cgroup claim, but
nonterminal process claims still become ambiguous and protect enclosing
filesystem claims. Merely supplying a native Linux host does not complete this
clause. Current `process` identity records contain PID/startTime/bootId/cgroup
text; they lack a durable exact resource linkage to the cgroup claim.

Before implementing group-covered process recovery, review a versioned journal
extension binding each process to its session's exact delegated cgroup resource
identity. Preserve old v1 records as ambiguity-only. Never infer the relation
from matching PID or path text. Revalidate boot, principal, session, group inode
and delegation before action. Record process cleanup only after confirmed empty
owned-subtree cleanup; preserve failure/retry evidence and ambiguous descendants.
Individual leader pidfd/start-time proofs cannot establish descendant ownership.

## Native-host acceptance sequence

1. Freeze Gate source, tools, profile and journal schema; preserve original state.
2. Validate the supplied delegation, then probe real quota writes/readbacks in a
   new explicitly owned child; run descendant pids/memory/CPU enforcement and
   escape-refusal gates with independent counter observations.
3. After the reviewed process-binding extension, launch a real worker tree behind
   the existing journal barrier. Retain group/process identities before release.
4. Abruptly end only the owned controller. Reclaim through a new administrative
   incarnation; verify the exact child becomes empty and owned filesystem cleanup
   completes. The interrupted behavioral run remains abandoned.
5. Exercise wrong boot/UID/session/group, PID reuse, inode replacement, stale
   records, unavailable delegation, torn writes, concurrent recovery and retries.
   Unrelated sentinel processes/files must survive.
6. Retain original/run/recovery linkage, native receipts and actual host identities;
   qualify only the tested profile. Extend capability/catalog claims afterward.

Steps 2–6 need the native runner; step 3 also needs the source/journal extension.
Neither requirement is silently removed. The selected M5 refresh proceeds with
its existing ownership-safe prepared-filesystem recovery requirement.
