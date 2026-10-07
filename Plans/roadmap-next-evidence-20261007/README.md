# Roadmap execution: source and preflight evidence

Date: 2026-10-07
Status: compiler migration source accepted; full M5 refresh incomplete.

The [execution plan](../roadmap-next-execution-2026-10-07.md) separates source
implementation from full installed/runtime qualification. The `compare-locks`
command passes 23 controls: identical/provenance-only/semantic differences,
v1-to-reviewed-v2 provenance, canonical ordering, exact semantic section deltas,
tampered digests, duplicate/unknown input keys, missing input, foreign/duplicate
CLI flags, JSON-only successful output and unchanged input bytes. Existing
compiler and eight-emitter language gates pass. Logs and current source hashes
are retained beside this record; no local model checker ran.

The M4 preflight uses the actual Gate delegation validator without creating a
child or signaling processes. It observes WSL2, no supplied operator parent and
refusal of /sys/fs/cgroup as a serving-UID delegation. These facts establish
eligibility/refusal, not kernel enforcement or post-restart recovery acceptance.
The [native-host/platform plan](../m4-native-host-and-platform-plan-2026-10-07.md)
records the missing process-to-cgroup resource binding and concrete future gates.

The available full-candidate phase passes dual D and 14/18 required commands;
[readiness](../q3-roadmap-refresh-2026-10-07.md) records exact results and the
three remote/final-Q prerequisites. Partial independent integrity accepts 16
bundles with both full-profile completion flags false. The earlier October 3 candidate remains
qualified only for its frozen identity; the new source helper needs a fresh
freeze, caches, both D audits, full linked Q1/Q2 and remote producers. No fresh
installed or release-candidate pass is inferred from these source results.
