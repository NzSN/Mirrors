# DPM usability first-slice source acceptance

Date: 2026-10-07
Status: F1 generated integration kit and F2 counterexample timeline source accepted.
F3 schedule reduction, F4 installed cross-language CLI and F5 synchronization
wrappers remain approved follow-on slices, with their own contracts/exit gates in
[the feature plan](../dpm-usability-features-2026-10-07.md). No broader M4 work.

[Acceptance](acceptance.json) records21 focused tests and six compiler kit modes,
ordinary binding byte preservation, canonical mapping order, static profile/model/
actor/input rejection, duplicate/unknown JSON, ownership collision/unrelated-file
protection and read-only freshness/tamper controls. Timeline controls exercise
actual CPP/ECMA/Rust/native receipts, model failure plus cleanup, repeated/fresh
identity, truncated evidence, malformed event ordering, ambiguous attribution,
trusted mapping annotation, input hash binding and no output overwrite.

C++/Node/Rust native helpers and application seeds compile against their actual
SDK interfaces. Admitted C++ header inputs are version/hash-bound separately.
The reproducible source gate is
`python3 tools/deterministic-scheduling/usability/check_helpers.py --out NEW --cpp-deps ADMITTED_HEADERS`.
The source Node consumer constructs actual fresh workers via its own factory,
uses the emitted public binding plus generated action/actor mapping and calls the
actual local Mirrors binary with retained supplied traces. Normal replay matches;
changing the actual increment causes genuine peer `step_mismatch`; both retain
confirmed worker/binding cleanup. The initial observation-shape integration error
was corrected using the existing native-value bridge; its diagnostics remain in
/tmp and earn no pass credit. No expected model state seeds implementation state.

[Mutation timeline](actual-mutate.timeline.txt) shows the actual failure and
cleanup; [successful timeline JSON](actual-ok.timeline.json) retains structured
rows. Their input receipts and generated helpers are retained byte-identically.
Existing compiler, eight-emitter language and23 migration regressions pass.
The 148 retained-receipt probe is diagnostic parsing coverage, not 148 new executions.

This is source acceptance, not an installed package, new M5 candidate, fresh model
checking or synchronization-wrapper acceptance. No local/remote model checker
ran. Earlier qualified evidence is untouched. Current code changes need a fresh
source/tool identity freeze and declared gates before a new qualification claim.
Native binaries/build trees remain temporary; this directory retains source,
input/helper hashes, real receipts and relevant logs, not a release archive.
