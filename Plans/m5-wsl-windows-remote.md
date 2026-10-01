# M5 WSL2 coordinator and Windows remote-oracle execution

Date: 2026-10-01
Profile: `m5-wsl-windows-remote/v1`
Status: complete and qualified for the named local-candidate profile.

Final installed/remote/evidence acceptance is recorded in
[completion readiness](q3-m5-complete-2026-10-01.md). The earlier
[Windows remote readiness](q3-windows-remote-2026-10-01.md) remains historical.

## Scope decision

The user removes separate native-Linux host requirements from M5 and selects
the current native Windows host as the remote oracle. This profile excludes
native Ubuntu acceptance and real aggregate-cgroup enforcement. Those capability
claims remain unqualified and belong to the separate Linux host/backend scope.
Existing WSL-supported local, installed, Gate isolation/recovery, and evidence
checks remain required; their claims name the actual WSL kernel and profile.
M5 depends on M4's ownership-safe recovery clause, not its excluded aggregate
limit clause. A result for this named profile is not a native-Linux release claim.

The oracle is `172.20.208.1:8999`, pinned mTLS, Apalache 0.62.2 and Microsoft
Java 25.0.4+7-LTS. All Windows work belongs under
`C:\Users\ayden\Desktop\Workspace\MirrorsRemote`. The existing owned console
deployment is admitted through exact process creation/ownership, listener,
binary/source, certificate and tool identities. It makes no service-manager
AUTO_START claim. The address and credential validity are checked before use.

## Execution sequence

1. Migrate remote command pins, service-observation validation, MirrorECMA's
   domain reducer and tests. Preserve the independently pinned 0.61.0 frontend
   reference and historical evidence. Require exact 0.62.2 remote identities.
2. Implement a bounded remote interop runner for the selected ECMA/C++/Rust/Lean/
   Haskell clients. Live model operations go to Windows with inline sources;
   local recorded stdio replay remains separate. Never start a local model
   checker. Missing clients or unsupported rows remain explicit non-passes.
3. Run current remote bounded validation, LeaseService domain-input reduction
   with genuine model-validity and mismatch/cleanup evidence, and the complete
   declared remote client matrix (22 pinned-mTLS verdict/pin/protocol cases). Test wrong
   identities and untrusted results.
4. Batch producer corrections, refresh catalog identities to byte stability,
   build one immutable snapshot and the required caches, then install from that
   snapshot. Run D audits first and bind every installed qualification run to
   its own distribution identity. Recollect fresh origins when old retained
   stores are unavailable; never manufacture historical logs or reuse their
   run IDs for this candidate.
5. Verify the new retained scope independently (Q2), including missing/modified
   artifact rejection, then record Q3 and current milestone status. Report
   remote-source results separately if any required installed gate is blocked.

## Completion boundary

All three requested remote tiers must have actual successful results and retained
source/client/server/tool identities. M5 for this profile additionally requires
its full installed/evidence scope. Deleting a host requirement does not turn
an unexecuted test into a pass. Historical profiles and scope bundles stay intact.
